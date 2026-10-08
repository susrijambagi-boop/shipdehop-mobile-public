import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';
import { inspectParcel, PARCEL_INSPECTION_MODEL } from '../services/parcelInspection.js';
import { requireVerifiedIdentity } from './identity.js';

export async function hopShieldRoutes(app: FastifyInstance): Promise<void> {
  app.post('/hopshield/shipments/:shipmentId/inspect', { bodyLimit: 8 * 1024 * 1024 }, async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const reqStartTime = Date.now();
    const { shipmentId } = z.object({ shipmentId: z.string().uuid() }).parse(request.params);
    const body = z.object({
      imageBase64: z.string().min(100).max(7_000_000),
      imageMimeType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
    }).parse(request.body);

    const imageSizeBytes = Math.round((body.imageBase64.length * 3) / 4);

    const dbFetchStart = Date.now();
    const { data: shipment, error } = await request.userSupabase
      .from('shipment_tasks')
      .select('id,sender_id,item_type,product_url,status')
      .eq('id', shipmentId)
      .single();
    const dbFetchMs = Date.now() - dbFetchStart;

    if (error || !shipment) throw app.httpErrors.notFound('Shipment not found');
    if (shipment.sender_id !== request.authUser.id) {
      throw app.httpErrors.forbidden('Only the sender can submit the pre-publish parcel inspection');
    }
    if (!['DRAFT', 'OPEN'].includes(shipment.status)) {
      throw app.httpErrors.badRequest('This shipment can no longer be inspected for publishing');
    }

    const assessment = await inspectParcel({
      imageBase64: body.imageBase64,
      imageMimeType: body.imageMimeType,
      itemType: shipment.item_type as 'PARCEL' | 'URL_PURCHASE',
      productUrl: shipment.product_url,
    });

    const dbUpdateStart = Date.now();
    const { data, error: recordError } = await adminSupabase.rpc('service_record_parcel_inspection', {
      p_shipment_task_id: shipmentId,
      p_submitted_by: request.authUser.id,
      p_decision: assessment.decision,
      p_confidence: assessment.confidence,
      p_content_mismatch: assessment.contentMismatch,
      p_prohibited_categories: assessment.prohibitedCategories,
      p_rationale: assessment.rationale,
      p_model: PARCEL_INSPECTION_MODEL,
    });
    const dbUpdateMs = Date.now() - dbUpdateStart;
    if (recordError) throw app.httpErrors.badRequest(recordError.message);

    const totalReqMs = Date.now() - reqStartTime;

    console.log('[HopShield Performance Metrics]', JSON.stringify({
      imageSizeBytes,
      dbFetchMs,
      dbUpdateMs,
      totalReqMs,
      ollamaTiming: assessment.timing,
    }));

    return { shipment: data, hopShield: assessment };
  });
}
