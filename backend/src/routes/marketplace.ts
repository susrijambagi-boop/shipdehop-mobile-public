import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';
import { assertIndiaRoute, INDIA_ONLY_MESSAGE, isIndiaPoint } from '../lib/launchMarket.js';
import { requireVerifiedIdentity } from './identity.js';
import {
  processAndUploadMarketplaceImages,
  cleanupMarketplaceImages,
  MAX_IMAGES_PER_LISTING,
} from '../services/marketplaceStorage.js';
import { verifyIndiaLocation, normalizeCountryCode, validateIndianPinCode } from '../lib/locationValidation.js';

export async function marketplaceRoutes(app: FastifyInstance): Promise<void> {
  // 1. Create Marketplace Listing (route-specific 10MB body limit for compressed photo payloads)
  app.post('/marketplace/items', { bodyLimit: 10 * 1024 * 1024 }, async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const body = z.object({
      title: z.string().trim().min(3, 'Title must be between 3 and 140 characters').max(140, 'Title must be between 3 and 140 characters'),
      description: z.string().trim().min(2, 'Description must be at least 2 characters'),
      price: z.number().nonnegative(),
      quantity: z.number().int().min(1).default(1),
      category: z.string().min(2),
      condition: z.string().min(2),
      currency: z.string().length(3),
      locationName: z.string().min(2),
      postalCode: z.string().optional(),
      jurisdictionCode: z.string().min(2).max(20),
      shipEligible: z.boolean().default(false),
      lat: z.number().min(-90).max(90),
      lng: z.number().min(-180).max(180),
      images: z.array(z.string()).max(MAX_IMAGES_PER_LISTING, `Marketplace supports maximum ${MAX_IMAGES_PER_LISTING} photos`).default([]),
    }).parse(request.body);

    if (body.shipEligible && (!body.postalCode || body.postalCode.trim() === '')) {
      throw app.httpErrors.badRequest('Postal code is required for shipping-eligible marketplace items');
    }

    if (body.postalCode && !validateIndianPinCode(body.postalCode)) {
      throw app.httpErrors.badRequest('Invalid 6-digit Indian PIN code');
    }

    const locationCheck = await verifyIndiaLocation({ lat: body.lat, lon: body.lng });
    if (!locationCheck.isValid) {
      if (locationCheck.status === 'SERVICE_UNAVAILABLE') {
        throw app.httpErrors.serviceUnavailable(locationCheck.errorMessage || "We couldn't verify this location. Please try again.");
      }
      throw app.httpErrors.badRequest(`Listing location error: ${locationCheck.errorMessage || 'Currently available in India.'}`);
    }

    if (body.currency.toUpperCase().trim() !== 'INR') {
      throw app.httpErrors.badRequest('Currency must be INR for India transactions');
    }

    if (normalizeCountryCode(body.jurisdictionCode) !== 'IN') {
      throw app.httpErrors.badRequest('Jurisdiction must be IN for India transactions');
    }

    const sellerId = request.authUser.id;

    // Process, validate, and upload images to trusted Supabase Storage
    let uploaded: { urls: string[]; paths: string[] };
    try {
      uploaded = await processAndUploadMarketplaceImages(sellerId, body.images);
    } catch (err: any) {
      throw app.httpErrors.badRequest(err.message || 'Image validation or upload failed');
    }

    // Build insert payload storing ONLY public Storage URLs, NEVER Base64 blobs
    const payload: Record<string, unknown> = {
      seller_id: sellerId,
      title: body.title,
      description: body.description,
      price: body.price,
      quantity: body.quantity,
      available_quantity: body.quantity,
      category: body.category,
      condition: body.condition,
      currency: 'INR',
      location_name: body.locationName,
      location_geo: `SRID=4326;POINT(${body.lng} ${body.lat})`,
      jurisdiction_code: 'IN',
      postal_code: body.postalCode?.trim() || null,
      ship_eligible: body.shipEligible,
      status: 'LISTED',
      images: uploaded.urls,
    };

    try {
      const { data, error } = await request.userSupabase
        .from('marketplace_items')
        .insert(payload)
        .select()
        .single();

      if (error) {
        // Atomic DB failure cleanup
        await cleanupMarketplaceImages(uploaded.paths);
        throw app.httpErrors.badRequest(error.message);
      }
      return data;
    } catch (err) {
      if (uploaded.paths.length > 0) {
        await cleanupMarketplaceImages(uploaded.paths);
      }
      throw err;
    }
  });

  app.get('/marketplace/items', async (request) => {
    const query = z.object({
      category: z.string().optional(),
      jurisdictionCode: z.string().optional(),
      condition: z.string().optional(),
      limit: z.coerce.number().int().min(1).max(100).default(50),
    }).parse(request.query);

    let dbQuery = request.userSupabase
      .from('marketplace_items')
      .select(
        'id,seller_id,title,description,price,quantity,available_quantity,category,condition,currency,location_name,jurisdiction_code,ship_eligible,status,images,created_at',
      )
      .eq('status', 'LISTED')
      .eq('currency', 'INR')
      .eq('jurisdiction_code', 'IN')
      .order('created_at', { ascending: false })
      .limit(query.limit);

    if (query.category) dbQuery = dbQuery.eq('category', query.category);
    if (query.condition) dbQuery = dbQuery.eq('condition', query.condition);

    const { data, error } = await dbQuery;
    if (error) throw app.httpErrors.badRequest(error.message);
    return data;
  });

  app.get('/marketplace/items/:id', async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const { data, error } = await request.userSupabase
      .from('marketplace_items')
      .select(
        '*, seller:users!marketplace_items_seller_id_fkey(id, full_name, avatar_url, ekyc_tier)',
      )
      .eq('id', id)
      .eq('currency', 'INR')
      .eq('jurisdiction_code', 'IN')
      .single();

    if (error || !data) throw app.httpErrors.notFound('Listing not found');
    return data;
  });

  app.patch('/marketplace/items/:id/stock', async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);
    const body = z
      .object({ newQuantity: z.number().int().min(1) })
      .parse(request.body);

    const { data, error } = await request.userSupabase.rpc(
      'update_marketplace_listing_stock',
      {
        p_actor_id: request.authUser.id,
        p_item_id: id,
        p_new_quantity: body.newQuantity,
      },
    );

    if (error) throw app.httpErrors.badRequest(error.message);
    return data;
  });

  app.post('/marketplace/purchases', async (request) => {
    const body = z
      .object({
        itemId: z.string().uuid(),
        quantity: z.number().int().min(1).default(1),
        fulfillmentMode: z.enum(['LOCAL_HANDOFF', 'PARCELPOOL']),
        deliveryReward: z.number().nonnegative().default(0),
        idempotencyKey: z.string().min(1),
        destName: z.string().optional(),
        destLat: z.number().optional(),
        destLng: z.number().optional(),
        weightKg: z.number().positive().optional(),
      })
      .parse(request.body);

    // Verify target item stored jurisdiction and location
    const { data: targetItem, error: itemErr } = await adminSupabase
      .from('marketplace_items')
      .select('id, jurisdiction_code, currency')
      .eq('id', body.itemId)
      .maybeSingle();

    if (itemErr || !targetItem) {
      throw app.httpErrors.notFound('Marketplace listing not found');
    }

    if (normalizeCountryCode(targetItem.jurisdiction_code) !== 'IN') {
      throw app.httpErrors.badRequest('Currently available in India.');
    }

    if (body.destLat !== undefined && body.destLng !== undefined) {
      const destCheck = await verifyIndiaLocation({ lat: body.destLat, lon: body.destLng });
      if (!destCheck.isValid) {
        if (destCheck.status === 'SERVICE_UNAVAILABLE') {
          throw app.httpErrors.serviceUnavailable(destCheck.errorMessage || "We couldn't verify this location. Please try again.");
        }
        throw app.httpErrors.badRequest(`Destination location error: ${destCheck.errorMessage || 'Currently available in India.'}`);
      }
    }

    const { data, error } = await request.userSupabase.rpc('reserve_marketplace_purchase', {
      p_actor_id: request.authUser.id,
      p_item_id: body.itemId,
      p_quantity: body.quantity,
      p_fulfillment_mode: body.fulfillmentMode,
      p_delivery_reward: body.deliveryReward,
      p_idempotency_key: body.idempotencyKey,
      p_dest_name: body.destName ?? null,
      p_dest_lat: body.destLat ?? null,
      p_dest_lng: body.destLng ?? null,
      p_weight_kg: body.weightKg ?? 1.0,
    });

    if (error) throw app.httpErrors.badRequest(error.message);
    return data;
  });

  app.post('/marketplace/purchases/:id/cancel', async (request) => {
    const { id } = z.object({ id: z.string().uuid() }).parse(request.params);

    const { data, error } = await request.userSupabase.rpc(
      'cancel_marketplace_purchase',
      {
        p_actor_id: request.authUser.id,
        p_purchase_id: id,
      },
    );

    if (error) throw app.httpErrors.badRequest(error.message);
    return data;
  });


}


