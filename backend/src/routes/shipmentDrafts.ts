import { createHash } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';
import { verifyIndiaLocation } from '../lib/locationValidation.js';
import { requireVerifiedIdentity } from './identity.js';

const money = z.number().finite().min(0).max(9_999_999_999.99).multipleOf(0.01);
const point = z.object({ lat: z.number().finite().min(-90).max(90), lon: z.number().finite().min(-180).max(180) }).strict();
const instant = z.string().datetime({ offset: true }).transform(s => new Date(s).toISOString()).nullable().default(null);
export const shipmentDraftSchema = z.object({
  requestId: z.string().uuid(),
  itemType: z.enum(['PARCEL', 'URL_PURCHASE']),
  productUrl: z.string().trim().max(2048).nullable().default(null),
  declaredValue: money,
  rewardAmount: money.refine(n => n > 0, 'Enter a positive traveller reward'),
  weightKg: z.number().finite().positive().max(40).multipleOf(0.001),
  currency: z.literal('INR'),
  pickupName: z.string().trim().min(2).max(160), pickup: point,
  dropName: z.string().trim().min(2).max(160), drop: point,
  earliestPickup: instant, latestDelivery: instant,
}).strict().superRefine((input, ctx) => {
  if (input.itemType === 'URL_PURCHASE') {
    try {
      const url = new URL(input.productUrl ?? '');
      if (url.protocol !== 'https:' || !url.hostname || url.username || url.password) throw new Error();
    } catch { ctx.addIssue({ code: 'custom', path: ['productUrl'], message: 'A valid HTTPS product URL is required' }); }
  }
  if (input.earliestPickup && input.latestDelivery && input.earliestPickup > input.latestDelivery) {
    ctx.addIssue({ code: 'custom', path: ['latestDelivery'], message: 'Latest delivery cannot be before earliest pickup' });
  }
});
export type ShipmentDraftInput = z.infer<typeof shipmentDraftSchema>;

/** An exact replay has one DB primary key across workers. The user and complete
 * canonical payload are part of the key; a key is not an authorization token.
 * UUIDv8 uses a SHA-256-derived 122-bit identifier. Never log the payload/hash.
 */
export function shipmentDraftRecord(actorId: string, input: ShipmentDraftInput) {
  const canonical = {
    requestId: input.requestId, itemType: input.itemType,
    productUrl: input.itemType === 'URL_PURCHASE' ? input.productUrl : null,
    declaredValue: input.declaredValue, rewardAmount: input.rewardAmount,
    weightKg: input.weightKg, currency: 'INR',
    pickupName: input.pickupName, pickup: input.pickup,
    dropName: input.dropName, drop: input.drop,
    earliestPickup: input.earliestPickup, latestDelivery: input.latestDelivery,
  };
  const hash = createHash('sha256').update(JSON.stringify(['shipdehop-parcel-draft-v1', actorId, canonical])).digest('hex');
  const id = `${hash.slice(0,8)}-${hash.slice(8,12)}-8${hash.slice(13,16)}-${((parseInt(hash[16]!,16) & 3) | 8).toString(16)}${hash.slice(17,20)}-${hash.slice(20,32)}`;
  return {
    id, sender_id: actorId, item_type: input.itemType, product_url: canonical.productUrl,
    declared_value: input.declaredValue, reward_amount: input.rewardAmount, weight_kg: input.weightKg,
    currency: 'INR', pickup_name: input.pickupName, drop_name: input.dropName,
    pickup_geo: `SRID=4326;POINT(${input.pickup.lon} ${input.pickup.lat})`,
    drop_geo: `SRID=4326;POINT(${input.drop.lon} ${input.drop.lat})`,
    earliest_pickup: input.earliestPickup, latest_delivery: input.latestDelivery,
    status: 'DRAFT', inspection_status: 'PENDING',
  };
}
const statusFields = 'id,status,inspection_status';

export async function shipmentDraftRoutes(app: FastifyInstance): Promise<void> {
  app.post('/hopshield/shipments/draft', async (request, reply) => {
    if (!request.authUser?.id || !request.userSupabase) return reply.code(401).send({ message: 'Sign in to submit a parcel.' });
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const parsed = shipmentDraftSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'INVALID_PARCEL_DETAILS', message: parsed.error.issues[0]?.message ?? 'Check your parcel details.' });
    const input = parsed.data;
    const row = shipmentDraftRecord(request.authUser.id, input);
    const readOwn = () => adminSupabase.from('shipment_tasks').select(statusFields)
      .eq('id', row.id).eq('sender_id', request.authUser.id).maybeSingle();
    const previous = await readOwn();
    if (previous.error) return reply.code(503).send({ error: 'DRAFT_LOOKUP_UNAVAILABLE', message: 'Could not check your saved draft. Retry this same request.' });
    if (previous.data) return { shipment: previous.data, replayed: true };
    if (input.latestDelivery && new Date(input.latestDelivery).getTime() <= Date.now()) {
      return reply.code(400).send({ error: 'EXPIRED_TIMING', message: 'The delivery window has ended. Choose a future delivery time.' });
    }
    if (input.itemType === 'URL_PURCHASE') {
      const profile = await adminSupabase.from('users').select('ekyc_tier').eq('id', request.authUser.id).maybeSingle();
      if (profile.error) return reply.code(503).send({ message: 'Could not check identity eligibility. Please retry.' });
      if (!['TIER_2','TIER_3'].includes(profile.data?.ekyc_tier)) {
        return reply.code(403).send({ error: 'IDENTITY_VERIFICATION_REQUIRED', message: 'Buy-for-Me requires completed identity verification.' });
      }
    }
    for (const [label, location] of [['Pickup', input.pickup], ['Drop-off', input.drop]] as const) {
      const checked = await verifyIndiaLocation(location);
      if (!checked.isValid) return reply.code(checked.status === 'SERVICE_UNAVAILABLE' ? 503 : 400).send({
        error: checked.status, message: `${label}: ${checked.errorMessage ?? 'Choose a verified Indian location.'}`,
      });
    }
    // Service client stays on the server. Ownership, currency, status and safety
    // fields are server-owned; direct client insert/update grants stay revoked.
    const saved = await adminSupabase.from('shipment_tasks').insert(row).select(statusFields).single();
    if (saved.error) {
      // Concurrent/lost-response retries converge through the DB primary key.
      if (saved.error.code === '23505') {
        const replay = await readOwn();
        if (!replay.error && replay.data) return { shipment: replay.data, replayed: true };
      }
      return reply.code(503).send({ error: 'DRAFT_SAVE_UNCONFIRMED', message: 'Draft saving could not be confirmed. Retry unchanged; the same request will not create a second draft.' });
    }
    return reply.code(201).send({ shipment: saved.data, replayed: false });
  });
}
