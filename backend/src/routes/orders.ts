import { createHash, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { adminSupabase } from '../lib/supabase.js';
import { config } from '../config.js';
import { requireVerifiedIdentity } from './identity.js';
import { calculatedPlatformFee, fundExistingOrder, reserveAndCreatePayment, reserveShipmentMatch, releaseVerifiedOrder } from '../services/escrow.js';
import { verifyIndiaLocation, normalizeCountryCode } from '../lib/locationValidation.js';

function hashCredential(code: string, orderId: string, purpose: 'PICKUP' | 'DELIVERY'): string {
  return createHash('sha256').update(`${code}:${orderId}:${purpose}`).digest('hex');
}

async function issuePickupSecret(app: FastifyInstance, orderId: string, userId: string) {
  const { data: order, error } = await adminSupabase
    .from('escrow_orders')
    .select('id,buyer_id,provider_id,escrow_status,fulfillment_status')
    .eq('id', orderId)
    .single();
  if (error || !order) throw app.httpErrors.notFound('Order not found');
  if (order.buyer_id !== userId) throw app.httpErrors.forbidden('Only the parcel sender can reveal the pickup secret');
  if (order.fulfillment_status !== 'READY') {
    throw app.httpErrors.badRequest(`Pickup secret is only available in READY status (current: ${order.fulfillment_status})`);
  }

  const otp = randomInt(100_000, 1_000_000).toString();
  const qrSecret = randomBytes(24).toString('base64url');
  const otpHash = hashCredential(otp, orderId, 'PICKUP');
  const qrHash = hashCredential(qrSecret, orderId, 'PICKUP');

  // Database-authoritative persistence in escrow_orders table (survives process restarts and multi-instance)
  const { error: updateErr } = await adminSupabase
    .from('escrow_orders')
    .update({
      handoff_otp_hash: JSON.stringify({ purpose: 'PICKUP', hash: otpHash, createdAt: new Date().toISOString() }),
      tamper_qr_code: JSON.stringify({ purpose: 'PICKUP', qrHash, createdAt: new Date().toISOString() }),
      handoff_otp_expires_at: new Date(Date.now() + 1800_000).toISOString(),
      handoff_attempts: 0,
      handoff_locked_until: null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId);

  if (updateErr) {
    throw app.httpErrors.internalServerError('Failed to persist pickup credentials to database');
  }

  // NEVER LOG OTP
  return {
    otp,
    qrPayload: `shipdehop://pickup/${orderId}?token=${encodeURIComponent(qrSecret)}&purpose=PICKUP`,
    expiresInSeconds: 1800,
    purpose: 'PICKUP',
  };
}

async function issueDeliverySecret(app: FastifyInstance, orderId: string, userId: string) {
  const { data: order, error } = await adminSupabase
    .from('escrow_orders')
    .select('id,buyer_id,provider_id,escrow_status,fulfillment_status')
    .eq('id', orderId)
    .single();
  if (error || !order) throw app.httpErrors.notFound('Order not found');
  if (order.buyer_id !== userId) throw app.httpErrors.forbidden('Only the buyer/recipient can reveal the handoff secret');
  if (config.PAYMENT_PROVIDER !== 'DISABLED' && order.escrow_status !== 'LOCKED') {
    throw app.httpErrors.badRequest('Funds must be locked first');
  }
  if (!['IN_TRANSIT', 'AWAITING_HANDOFF'].includes(order.fulfillment_status)) {
    throw app.httpErrors.badRequest('Delivery secret is available only at the handoff stage');
  }

  const otp = randomInt(100_000, 1_000_000).toString();
  const qrSecret = randomBytes(32).toString('base64url');
  const otpHash = hashCredential(otp, orderId, 'DELIVERY');
  const qrHash = hashCredential(qrSecret, orderId, 'DELIVERY');

  // Database-authoritative persistence in escrow_orders table (survives process restarts and multi-instance)
  const { error: updateErr } = await adminSupabase
    .from('escrow_orders')
    .update({
      handoff_otp_hash: JSON.stringify({ purpose: 'DELIVERY', hash: otpHash, createdAt: new Date().toISOString() }),
      tamper_qr_code: JSON.stringify({ purpose: 'DELIVERY', qrHash, createdAt: new Date().toISOString() }),
      handoff_otp_expires_at: new Date(Date.now() + 1800_000).toISOString(),
      handoff_attempts: 0,
      handoff_locked_until: null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId);

  if (updateErr) {
    throw app.httpErrors.internalServerError('Failed to persist delivery credentials to database');
  }

  if (config.PAYMENT_PROVIDER !== 'DISABLED') {
    try {
      await adminSupabase.rpc('service_set_handoff_secret', {
        p_order_id: orderId,
        p_handoff_otp: otp,
        p_qr_secret: qrSecret,
      });
    } catch (_) {}
  }

  // NEVER LOG OTP
  return {
    otp,
    qrPayload: `shipdehop://handoff/${orderId}?token=${encodeURIComponent(qrSecret)}&purpose=DELIVERY`,
    expiresInSeconds: 1800,
    purpose: 'DELIVERY',
  };
}

export async function orderRoutes(app: FastifyInstance): Promise<void> {
  app.post('/pricing/shipment', async (request) => {
    const body = z.object({ itemType: z.enum(['PARCEL','URL_PURCHASE']), declaredValue: z.number().nonnegative(), reward: z.number().nonnegative(), currency: z.string().length(3) }).parse(request.body);
    const base = body.itemType === 'URL_PURCHASE' ? body.declaredValue : 0;
    const platformFee = calculatedPlatformFee('SHIPMENT', base + body.reward);
    return { base, reward: body.reward, platformFee, total: base + body.reward + platformFee, currency: body.currency.toUpperCase() };
  });

  app.post('/orders/reserve', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const body = z.discriminatedUnion('type', [
      z.object({ type: z.literal('RIDE'), tripId: z.string().uuid(), quantity: z.number().int().min(1).max(8).default(1) }),
      z.object({ type: z.literal('MARKETPLACE'), marketplaceItemId: z.string().uuid() }),
      z.object({ type: z.literal('SHIPMENT'), shipmentTaskId: z.string().uuid(), providerId: z.string().uuid(), tripId: z.string().uuid() }),
    ]).parse(request.body);

    if (body.type === 'SHIPMENT') {
      if (body.providerId !== request.authUser.id) {
        throw app.httpErrors.forbidden('Carrier identity must match the authenticated user');
      }

      // Response-loss idempotency check: if already reserved by this carrier on this trip, return existing order safely
      const { data: existingOrder } = await adminSupabase
        .from('escrow_orders')
        .select('*')
        .eq('shipment_task_id', body.shipmentTaskId)
        .eq('provider_id', request.authUser.id)
        .eq('trip_id', body.tripId)
        .eq('fulfillment_status', 'CREATED')
        .maybeSingle();

      if (existingOrder) {
        return {
          order: existingOrder,
          requiresBuyerPayment: true,
          paymentMode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW',
          paymentRequired: config.PAYMENT_PROVIDER !== 'DISABLED',
          requiresCounterpartyAcceptance: true,
          idempotent: true,
        };
      }

      // Server-side self-match protection
      const { data: shipmentTask, error: taskErr } = await adminSupabase
        .from('shipment_tasks')
        .select('id, sender_id, status, inspection_status')
        .eq('id', body.shipmentTaskId)
        .maybeSingle();

      if (taskErr || !shipmentTask) {
        throw app.httpErrors.notFound('Shipment task not found');
      }
      if (shipmentTask.sender_id === request.authUser.id) {
        throw app.httpErrors.badRequest('Sender cannot carry own shipment');
      }
      if (shipmentTask.status !== 'OPEN' || shipmentTask.inspection_status !== 'APPROVED') {
        throw app.httpErrors.badRequest('Shipment is not available for matching');
      }

      try {
        const res = await reserveShipmentMatch({
          carrierId: request.authUser.id,
          shipmentTaskId: body.shipmentTaskId,
          tripId: body.tripId,
        });

        return {
          ...res,
          paymentMode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW',
          paymentRequired: config.PAYMENT_PROVIDER !== 'DISABLED',
          requiresCounterpartyAcceptance: true,
        };
      } catch (err: any) {
        throw app.httpErrors.badRequest(err.message || 'Failed to reserve shipment match');
      }
    }

    return reserveAndCreatePayment({
      userId: request.authUser.id,
      ...(request.authUser.email ? { email: request.authUser.email } : {}),
      type: body.type,
      ...(body.type === 'RIDE' ? { tripId: body.tripId, quantity: body.quantity } : { marketplaceItemId: body.marketplaceItemId }),
    });
  });

  app.post('/orders/:orderId/accept', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);

    const { data: order, error } = await adminSupabase
      .from('escrow_orders')
      .select('id, buyer_id, provider_id, trip_id, shipment_task_id, fulfillment_status, escrow_status, reservation_expires_at')
      .eq('id', orderId)
      .maybeSingle();

    if (error || !order) throw app.httpErrors.notFound('Order not found');

    // Mutual acceptance: The sender (buyer_id) must accept the match requested by the carrier
    if (order.buyer_id !== request.authUser.id) {
      throw app.httpErrors.forbidden('Only the parcel sender can accept this match');
    }

    // Response-loss idempotency check: if already accepted, return existing state safely
    if (order.fulfillment_status === 'READY') {
      return {
        order,
        accepted: true,
        paymentMode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW',
        paymentRequired: config.PAYMENT_PROVIDER !== 'DISABLED',
        idempotent: true,
      };
    }

    if (order.fulfillment_status !== 'CREATED') {
      throw app.httpErrors.badRequest(`Cannot accept match in status ${order.fulfillment_status}`);
    }

    if (order.reservation_expires_at && new Date(order.reservation_expires_at).getTime() < Date.now()) {
      throw app.httpErrors.badRequest('Match reservation has expired');
    }

    // Update fulfillment_status to READY (escrow_status remains PENDING until payment lock)
    const updatePayload: Record<string, any> = {
      fulfillment_status: 'READY',
      updated_at: new Date().toISOString(),
    };

    const { data: updatedOrder, error: updateErr } = await adminSupabase
      .from('escrow_orders')
      .update(updatePayload)
      .eq('id', orderId)
      .select()
      .single();

    if (updateErr || !updatedOrder) throw app.httpErrors.badRequest(updateErr?.message || 'Failed to accept match');

    await adminSupabase.from('escrow_events').insert({
      order_id: orderId,
      actor_id: request.authUser.id,
      event_type: 'MATCH_ACCEPTED',
      metadata: { payment_mode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW' },
    });

    try {
      await adminSupabase.rpc('create_notification', {
        p_user_id: order.provider_id,
        p_type: 'MATCH_ACCEPTED',
        p_title: 'Match accepted',
        p_body: 'Sender accepted your match request. You can now coordinate pickup.',
        p_entity_type: 'ORDER',
        p_entity_id: orderId,
        p_idempotency_key: `match_accepted:${orderId}:${order.provider_id}`,
        p_order_id: orderId,
        p_trip_id: order.trip_id,
      });
    } catch (_) {}

    return {
      order: updatedOrder,
      accepted: true,
      paymentMode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW',
      paymentRequired: config.PAYMENT_PROVIDER !== 'DISABLED',
    };
  });

  app.post('/orders/:orderId/fund', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    return fundExistingOrder({
      orderId,
      buyerId: request.authUser.id,
      ...(request.authUser.email ? { email: request.authUser.email } : {}),
    });
  });

  app.post('/orders/:orderId/pickup-secret', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    return issuePickupSecret(app, orderId, request.authUser.id);
  });

  // Pickup & In-Transit handler
  const handleStartTransit = async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    const body = z.object({
      pickupOtp: z.string().optional(),
      pickupCode: z.string().optional(),
      pickupQr: z.string().optional(),
      qrToken: z.string().optional(),
    }).parse(request.body || {});

    const { data: orderData, error: fetchErr } = await adminSupabase
      .from('escrow_orders')
      .select('id, buyer_id, provider_id, trip_id, shipment_task_id, fulfillment_status, escrow_status, handoff_otp_hash, handoff_otp_expires_at, handoff_attempts, handoff_locked_until, tamper_qr_code')
      .eq('id', orderId)
      .maybeSingle();

    if (fetchErr || !orderData) throw app.httpErrors.notFound('Order not found');
    if (orderData.provider_id !== request.authUser.id) {
      throw app.httpErrors.forbidden('Only the assigned carrier can confirm pickup');
    }

    // Response-loss idempotency check: if already in transit, return existing state safely
    if (orderData.fulfillment_status === 'IN_TRANSIT') {
      return { order: orderData, verified: true, fulfillmentStatus: 'IN_TRANSIT', idempotent: true };
    }

    // Critical rule: CREATED must NEVER jump directly to IN_TRANSIT
    if (orderData.fulfillment_status === 'CREATED') {
      throw app.httpErrors.badRequest('Match must be accepted by the sender before pickup can be confirmed');
    }
    if (!['READY', 'AWAITING_HANDOFF'].includes(orderData.fulfillment_status)) {
      throw app.httpErrors.badRequest(`Cannot start transit from fulfillment status ${orderData.fulfillment_status}`);
    }

    if (config.PAYMENT_PROVIDER !== 'DISABLED' && orderData.escrow_status !== 'LOCKED') {
      throw app.httpErrors.badRequest('Escrow funds must be locked before starting transit');
    }

    // Mutual pickup verification requirement: Carrier cannot self-certify pickup!
    const submittedCode = (body.pickupOtp || body.pickupCode)?.trim();
    const submittedQr = (body.pickupQr || body.qrToken)?.trim();

    if (!submittedCode && !submittedQr) {
      throw app.httpErrors.badRequest('Mutual pickup verification required. Sender must provide the 6-digit pickup code or QR.');
    }

    if (orderData.handoff_locked_until && new Date(orderData.handoff_locked_until).getTime() > Date.now()) {
      throw app.httpErrors.badRequest('Too many failed pickup attempts. Verification locked temporarily.');
    }

    if (!orderData.handoff_otp_expires_at || new Date(orderData.handoff_otp_expires_at).getTime() < Date.now()) {
      throw app.httpErrors.badRequest('Pickup code has expired or was not requested yet');
    }

    if (!orderData.handoff_otp_hash) {
      throw app.httpErrors.badRequest('Pickup code has expired or was not requested yet');
    }

    let storedRecord: { purpose: string; hash: string } | null = null;
    try {
      storedRecord = JSON.parse(orderData.handoff_otp_hash);
    } catch {
      throw app.httpErrors.badRequest('Invalid pickup credential record');
    }

    if (!storedRecord || storedRecord.purpose !== 'PICKUP') {
      throw app.httpErrors.badRequest('Invalid pickup credential');
    }

    let verified = false;
    if (submittedCode) {
      const computedHash = hashCredential(submittedCode, orderId, 'PICKUP');
      if (computedHash.length === storedRecord.hash.length &&
          timingSafeEqual(Buffer.from(computedHash, 'hex'), Buffer.from(storedRecord.hash, 'hex'))) {
        verified = true;
      }
    } else if (submittedQr && orderData.tamper_qr_code) {
      try {
        const storedQr = JSON.parse(orderData.tamper_qr_code);
        if (storedQr && storedQr.purpose === 'PICKUP') {
          const computedQrHash = hashCredential(submittedQr, orderId, 'PICKUP');
          if (computedQrHash.length === storedQr.qrHash.length &&
              timingSafeEqual(Buffer.from(computedQrHash, 'hex'), Buffer.from(storedQr.qrHash, 'hex'))) {
            verified = true;
          }
        }
      } catch (_) {}
    }

    if (!verified) {
      const attempts = (orderData.handoff_attempts || 0) + 1;
      const lockedUntil = attempts >= 5 ? new Date(Date.now() + 900_000).toISOString() : null;
      await adminSupabase.from('escrow_orders').update({
        handoff_attempts: attempts,
        handoff_locked_until: lockedUntil,
        updated_at: new Date().toISOString(),
      }).eq('id', orderId);
      throw app.httpErrors.badRequest('Invalid pickup credential');
    }

    // Database single-use consumption: atomically clear credentials
    const { data: updatedOrder, error: updateErr } = await adminSupabase
      .from('escrow_orders')
      .update({
        fulfillment_status: 'IN_TRANSIT',
        handoff_otp_hash: null,
        tamper_qr_code: null,
        handoff_attempts: 0,
        handoff_locked_until: null,
        handoff_otp_expires_at: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', orderId)
      .select()
      .single();

    if (updateErr || !updatedOrder) throw app.httpErrors.badRequest(updateErr?.message || 'Failed to update order');

    if (orderData.shipment_task_id) {
      await adminSupabase
        .from('shipment_tasks')
        .update({ status: 'IN_TRANSIT', updated_at: new Date().toISOString() })
        .eq('id', orderData.shipment_task_id);
    }

    await adminSupabase.from('escrow_events').insert([
      {
        order_id: orderId,
        actor_id: request.authUser.id,
        event_type: 'PICKUP_CONFIRMED',
        metadata: { verified_by: 'MUTUAL_CODE', payment_mode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW' },
      },
      {
        order_id: orderId,
        actor_id: request.authUser.id,
        event_type: 'IN_TRANSIT',
        metadata: {},
      },
    ]);

    try {
      await adminSupabase.rpc('create_notification', {
        p_user_id: orderData.buyer_id,
        p_type: 'DELIVERY_STARTED',
        p_title: 'Parcel in transit',
        p_body: 'Traveller has collected your parcel and started the journey.',
        p_entity_type: 'ORDER',
        p_entity_id: orderId,
        p_idempotency_key: `delivery_started:${orderId}:${orderData.buyer_id}`,
        p_order_id: orderId,
        p_trip_id: orderData.trip_id,
      });
    } catch (_) {}

    return { order: updatedOrder, verified: true, fulfillmentStatus: 'IN_TRANSIT' };
  };

  app.post('/orders/:orderId/in-transit', handleStartTransit);
  app.post('/orders/:orderId/pickup', handleStartTransit);
  app.post('/orders/:orderId/confirm-pickup', handleStartTransit);

  app.post('/orders/:orderId/handoff-secret', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    return issueDeliverySecret(app, orderId, request.authUser.id);
  });

  app.post('/orders/:orderId/verify-otp', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    const { otp } = z.object({ otp: z.string().regex(/^\d{6}$/) }).parse(request.body);

    const { data: orderBefore, error: orderErr } = await adminSupabase
      .from('escrow_orders')
      .select('id, buyer_id, provider_id, trip_id, shipment_task_id, fulfillment_status, escrow_status, handoff_otp_hash, handoff_otp_expires_at, handoff_attempts, handoff_locked_until')
      .eq('id', orderId)
      .maybeSingle();

    if (orderErr || !orderBefore) throw app.httpErrors.notFound('Order not found');
    if (orderBefore.provider_id !== request.authUser.id) {
      throw app.httpErrors.forbidden('Only the assigned carrier can verify delivery handoff');
    }

    // Response-loss idempotency check: if already completed, return existing state safely
    if (['VERIFIED', 'COMPLETED'].includes(orderBefore.fulfillment_status)) {
      return {
        order: orderBefore,
        paymentMode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW',
        paymentRequired: config.PAYMENT_PROVIDER !== 'DISABLED',
        verified: true,
        fulfillmentStatus: orderBefore.fulfillment_status,
        idempotent: true,
      };
    }

    if (!['IN_TRANSIT', 'AWAITING_HANDOFF'].includes(orderBefore.fulfillment_status)) {
      throw app.httpErrors.badRequest('Handoff can only be verified when delivery is in transit');
    }

    if (orderBefore.handoff_locked_until && new Date(orderBefore.handoff_locked_until).getTime() > Date.now()) {
      throw app.httpErrors.badRequest('Too many failed delivery attempts. Verification locked temporarily.');
    }

    if (!orderBefore.handoff_otp_expires_at || new Date(orderBefore.handoff_otp_expires_at).getTime() < Date.now()) {
      throw app.httpErrors.badRequest('Delivery code has expired');
    }

    if (!orderBefore.handoff_otp_hash) {
      throw app.httpErrors.badRequest('Delivery code has expired or was not requested yet');
    }

    let storedRecord: { purpose: string; hash: string } | null = null;
    try {
      storedRecord = JSON.parse(orderBefore.handoff_otp_hash);
    } catch {
      throw app.httpErrors.badRequest('Invalid delivery credential record');
    }

    if (!storedRecord || storedRecord.purpose !== 'DELIVERY') {
      throw app.httpErrors.badRequest('Invalid delivery code');
    }

    const computedHash = hashCredential(otp.trim(), orderId, 'DELIVERY');
    if (computedHash.length !== storedRecord.hash.length ||
        !timingSafeEqual(Buffer.from(computedHash, 'hex'), Buffer.from(storedRecord.hash, 'hex'))) {
      const attempts = (orderBefore.handoff_attempts || 0) + 1;
      const lockedUntil = attempts >= 5 ? new Date(Date.now() + 900_000).toISOString() : null;
      await adminSupabase.from('escrow_orders').update({
        handoff_attempts: attempts,
        handoff_locked_until: lockedUntil,
        updated_at: new Date().toISOString(),
      }).eq('id', orderId);
      throw app.httpErrors.badRequest('Invalid delivery code');
    }

    // Atomic update of fulfillment_status to COMPLETED and clear credentials
    const { data: updatedOrder, error: updateErr } = await adminSupabase
      .from('escrow_orders')
      .update({
        fulfillment_status: 'COMPLETED',
        handoff_otp_hash: null,
        tamper_qr_code: null,
        handoff_attempts: 0,
        handoff_locked_until: null,
        handoff_otp_expires_at: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', orderId)
      .select()
      .single();

    if (updateErr || !updatedOrder) throw app.httpErrors.badRequest(updateErr?.message || 'Failed to complete order');

    // Update linked shipment task to DELIVERED
    if (orderBefore.shipment_task_id) {
      await adminSupabase
        .from('shipment_tasks')
        .update({ status: 'DELIVERED', updated_at: new Date().toISOString() })
        .eq('id', orderBefore.shipment_task_id);
    }

    await adminSupabase.from('escrow_events').insert([
      {
        order_id: orderId,
        actor_id: request.authUser.id,
        event_type: 'HANDOFF_VERIFIED',
        metadata: { payment_mode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW' },
      },
      {
        order_id: orderId,
        actor_id: request.authUser.id,
        event_type: 'ORDER_COMPLETED',
        metadata: { payment_mode: config.PAYMENT_PROVIDER === 'DISABLED' ? 'BETA_NO_PAYMENT' : 'ESCROW' },
      },
    ]);

    try {
      await adminSupabase.rpc('create_notification', {
        p_user_id: orderBefore.buyer_id,
        p_type: 'HANDOFF_VERIFIED',
        p_title: 'Delivery confirmed',
        p_body: 'Package handoff has been verified with security code.',
        p_entity_type: 'ORDER',
        p_entity_id: orderId,
        p_idempotency_key: `handoff_verified:${orderId}:${orderBefore.buyer_id}`,
        p_order_id: orderId,
        p_trip_id: orderBefore.trip_id,
      });
    } catch (_) {}

    if (config.PAYMENT_PROVIDER === 'DISABLED') {
      return {
        order: updatedOrder,
        paymentMode: 'BETA_NO_PAYMENT',
        paymentRequired: false,
        verified: true,
        fulfillmentStatus: 'COMPLETED',
      };
    }

    const payout = await releaseVerifiedOrder(orderId);
    return { order: updatedOrder, payout, verified: true, fulfillmentStatus: 'COMPLETED' };
  });

  app.post('/orders/:orderId/cancel', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    const body = z.object({ reason: z.string().min(3).max(500).default('Cancelled by user') }).parse(request.body || {});

    const { data: order, error } = await adminSupabase
      .from('escrow_orders')
      .select('*')
      .eq('id', orderId)
      .maybeSingle();

    if (error || !order) throw app.httpErrors.notFound('Order not found');

    const isBuyer = order.buyer_id === request.authUser.id;
    const isProvider = order.provider_id === request.authUser.id;

    if (!isBuyer && !isProvider) {
      throw app.httpErrors.forbidden('Only order participants can cancel this order');
    }

    if (['IN_TRANSIT', 'AWAITING_HANDOFF', 'VERIFIED', 'COMPLETED'].includes(order.fulfillment_status)) {
      throw app.httpErrors.badRequest(`Cannot cancel order once in transit or completed (status: ${order.fulfillment_status})`);
    }

    if (order.fulfillment_status === 'CANCELLED') {
      return { order, cancelled: true, message: 'Already cancelled', idempotent: true };
    }

    // Atomic restore of reserved parcel units on trip
    if (order.trip_id && (order.reserved_parcel_capacity_units || 0) > 0) {
      const { data: trip } = await adminSupabase
        .from('trip_routes')
        .select('parcel_capacity_units_available, parcel_capacity_units_total')
        .eq('id', order.trip_id)
        .maybeSingle();

      if (trip) {
        const restored = Math.min(
          trip.parcel_capacity_units_total,
          (trip.parcel_capacity_units_available || 0) + order.reserved_parcel_capacity_units,
        );
        await adminSupabase
          .from('trip_routes')
          .update({ parcel_capacity_units_available: restored, updated_at: new Date().toISOString() })
          .eq('id', order.trip_id);
      }
    }

    // Update linked shipment task status
    if (order.shipment_task_id) {
      const nextTaskStatus = isBuyer ? 'CANCELLED' : 'OPEN';
      await adminSupabase
        .from('shipment_tasks')
        .update({ status: nextTaskStatus, updated_at: new Date().toISOString() })
        .eq('id', order.shipment_task_id);
    }

    const cancelUpdatePayload: Record<string, any> = {
      fulfillment_status: 'CANCELLED',
      updated_at: new Date().toISOString(),
    };
    if (config.PAYMENT_PROVIDER !== 'DISABLED') {
      cancelUpdatePayload.escrow_status = 'REFUNDED';
    }

    const { data: updatedOrder, error: cancelErr } = await adminSupabase
      .from('escrow_orders')
      .update(cancelUpdatePayload)
      .eq('id', orderId)
      .select()
      .single();

    if (cancelErr) throw app.httpErrors.badRequest(cancelErr.message);

    await adminSupabase.from('escrow_events').insert({
      order_id: orderId,
      actor_id: request.authUser.id,
      event_type: 'ORDER_CANCELLED',
      metadata: { reason: body.reason, cancelled_by: isBuyer ? 'SENDER' : 'CARRIER' },
    });

    const counterpartyId = isBuyer ? order.provider_id : order.buyer_id;
    if (counterpartyId) {
      try {
        await adminSupabase.rpc('create_notification', {
          p_user_id: counterpartyId,
          p_type: 'ORDER_CANCELLED',
          p_title: 'Match cancelled',
          p_body: isBuyer ? 'Sender has cancelled this parcel match.' : 'Traveller has cancelled their match reservation.',
          p_entity_type: 'ORDER',
          p_entity_id: orderId,
          p_idempotency_key: `order_cancelled:${orderId}:${counterpartyId}`,
          p_order_id: orderId,
          p_trip_id: order.trip_id,
        });
      } catch (_) {}
    }

    return { order: updatedOrder, cancelled: true };
  });

  app.post('/orders/:orderId/report-issue', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    const body = z.object({
      category: z.enum([
        'TRAVELLER_DID_NOT_ARRIVE',
        'SENDER_UNAVAILABLE',
        'PARCEL_MISMATCH',
        'SAFETY_CONCERN',
        'DELIVERY_PROBLEM',
        'OTHER',
      ]),
      description: z.string().min(5).max(1000),
    }).parse(request.body);

    const { data: order, error } = await adminSupabase
      .from('escrow_orders')
      .select('id, buyer_id, provider_id, trip_id')
      .eq('id', orderId)
      .maybeSingle();

    if (error || !order) throw app.httpErrors.notFound('Order not found');

    const isBuyer = order.buyer_id === request.authUser.id;
    const isProvider = order.provider_id === request.authUser.id;
    if (!isBuyer && !isProvider) {
      throw app.httpErrors.forbidden('Only participants can report an issue on this order');
    }

    // Response-loss idempotency check: check if same category reported by this user within last 60s
    const { data: recentEvents } = await adminSupabase
      .from('escrow_events')
      .select('id, created_at, metadata')
      .eq('order_id', orderId)
      .eq('actor_id', request.authUser.id)
      .eq('event_type', 'ISSUE_REPORTED')
      .order('created_at', { ascending: false })
      .limit(1);

    if (recentEvents && recentEvents.length > 0 && recentEvents[0]) {
      const lastEvent = recentEvents[0];
      const timeDiff = Date.now() - new Date(lastEvent.created_at).getTime();
      if (timeDiff < 60_000 && (lastEvent.metadata as any)?.category === body.category) {
        return { ok: true, issueReported: true, category: body.category, idempotent: true };
      }
    }

    await adminSupabase.from('escrow_events').insert({
      order_id: orderId,
      actor_id: request.authUser.id,
      event_type: 'ISSUE_REPORTED',
      metadata: {
        category: body.category,
        description: body.description,
        reporter_role: isBuyer ? 'SENDER' : 'CARRIER',
        timestamp: new Date().toISOString(),
      },
      created_at: new Date().toISOString(),
    });

    const counterpartyId = isBuyer ? order.provider_id : order.buyer_id;
    if (counterpartyId) {
      try {
        await adminSupabase.rpc('create_notification', {
          p_user_id: counterpartyId,
          p_type: 'SAFETY_ALERT',
          p_title: 'Issue reported',
          p_body: 'An issue has been reported on this delivery. ShipdeHop beta support will review this report.',
          p_entity_type: 'ORDER',
          p_entity_id: orderId,
          p_idempotency_key: `issue_reported:${orderId}:${body.category}:${request.authUser.id}`,
          p_order_id: orderId,
          p_trip_id: order.trip_id,
        });
      } catch (_) {}
    }

    return { ok: true, issueReported: true, category: body.category };
  });

  app.post('/orders/:orderId/verify-qr', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const { orderId } = z.object({ orderId: z.string().uuid() }).parse(request.params);
    const { token } = z.object({ token: z.string().min(10) }).parse(request.body);

    const { data: orderBefore, error: orderErr } = await adminSupabase
      .from('escrow_orders')
      .select('id, buyer_id, provider_id, trip_id, shipment_task_id, fulfillment_status, escrow_status, tamper_qr_code, handoff_otp_expires_at, handoff_attempts, handoff_locked_until')
      .eq('id', orderId)
      .maybeSingle();

    if (orderErr || !orderBefore) throw app.httpErrors.notFound('Order not found');
    if (orderBefore.provider_id !== request.authUser.id) {
      throw app.httpErrors.forbidden('Only the assigned carrier can verify delivery handoff');
    }

    if (['VERIFIED', 'COMPLETED'].includes(orderBefore.fulfillment_status)) {
      return { order: orderBefore, verified: true, fulfillmentStatus: orderBefore.fulfillment_status, idempotent: true };
    }

    if (!['IN_TRANSIT', 'AWAITING_HANDOFF'].includes(orderBefore.fulfillment_status)) {
      throw app.httpErrors.badRequest('Order is not ready for handoff');
    }

    if (orderBefore.handoff_locked_until && new Date(orderBefore.handoff_locked_until).getTime() > Date.now()) {
      throw app.httpErrors.badRequest('Verification locked temporarily');
    }

    if (!orderBefore.handoff_otp_expires_at || new Date(orderBefore.handoff_otp_expires_at).getTime() < Date.now()) {
      throw app.httpErrors.badRequest('Delivery QR has expired');
    }

    if (!orderBefore.tamper_qr_code) {
      throw app.httpErrors.badRequest('Delivery QR has expired or was not requested yet');
    }

    let storedQr: { purpose: string; qrHash: string } | null = null;
    try {
      storedQr = JSON.parse(orderBefore.tamper_qr_code);
    } catch {
      throw app.httpErrors.badRequest('Invalid QR record');
    }

    if (!storedQr || storedQr.purpose !== 'DELIVERY') {
      throw app.httpErrors.badRequest('Invalid QR token');
    }

    const computedQrHash = hashCredential(token.trim(), orderId, 'DELIVERY');
    if (computedQrHash.length !== storedQr.qrHash.length ||
        !timingSafeEqual(Buffer.from(computedQrHash, 'hex'), Buffer.from(storedQr.qrHash, 'hex'))) {
      const attempts = (orderBefore.handoff_attempts || 0) + 1;
      const lockedUntil = attempts >= 5 ? new Date(Date.now() + 900_000).toISOString() : null;
      await adminSupabase.from('escrow_orders').update({
        handoff_attempts: attempts,
        handoff_locked_until: lockedUntil,
        updated_at: new Date().toISOString(),
      }).eq('id', orderId);
      throw app.httpErrors.badRequest('Invalid QR token');
    }

    const { data: updatedOrder, error: updateErr } = await adminSupabase
      .from('escrow_orders')
      .update({
        fulfillment_status: 'COMPLETED',
        handoff_otp_hash: null,
        tamper_qr_code: null,
        handoff_attempts: 0,
        handoff_locked_until: null,
        handoff_otp_expires_at: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', orderId)
      .select()
      .single();

    if (updateErr || !updatedOrder) throw app.httpErrors.badRequest(updateErr?.message || 'Failed to complete order');

    if (orderBefore.shipment_task_id) {
      await adminSupabase
        .from('shipment_tasks')
        .update({ status: 'DELIVERED', updated_at: new Date().toISOString() })
        .eq('id', orderBefore.shipment_task_id);
    }

    await adminSupabase.from('escrow_events').insert([
      { order_id: orderId, actor_id: request.authUser.id, event_type: 'HANDOFF_QR_VERIFIED', metadata: {} },
      { order_id: orderId, actor_id: request.authUser.id, event_type: 'ORDER_COMPLETED', metadata: {} },
    ]);

    return { order: updatedOrder, verified: true, fulfillmentStatus: 'COMPLETED' };
  });

  app.post('/shipments', async (request: FastifyRequest, reply: FastifyReply) => {
    if (!(await requireVerifiedIdentity(request, reply))) return;
    const body = z.object({
      itemType: z.enum(['PARCEL', 'URL_PURCHASE']).default('PARCEL'),
      productUrl: z.string().url().optional(),
      declaredValue: z.number().nonnegative().default(0),
      rewardAmount: z.number().nonnegative().default(0),
      currency: z.string().length(3).default('INR'),
      pickupName: z.string().min(2).max(160),
      pickup: z.object({ lat: z.number(), lon: z.number() }),
      dropName: z.string().min(2).max(160),
      drop: z.object({ lat: z.number(), lon: z.number() }),
      weightKg: z.number().positive().max(40).default(1),
    }).parse(request.body);

    const pickupCheck = await verifyIndiaLocation({ lat: body.pickup.lat, lon: body.pickup.lon });
    if (!pickupCheck.isValid) {
      throw app.httpErrors.badRequest(`Pickup location error: ${pickupCheck.errorMessage || 'Currently available in India.'}`);
    }

    const dropCheck = await verifyIndiaLocation({ lat: body.drop.lat, lon: body.drop.lon });
    if (!dropCheck.isValid) {
      throw app.httpErrors.badRequest(`Drop location error: ${dropCheck.errorMessage || 'Currently available in India.'}`);
    }

    if (body.currency.toUpperCase().trim() !== 'INR') {
      throw app.httpErrors.badRequest('Currency must be INR for India transactions');
    }

    const { data: created, error } = await adminSupabase
      .from('shipment_tasks')
      .insert({
        sender_id: request.authUser.id,
        item_type: body.itemType,
        product_url: body.productUrl || null,
        declared_value: body.declaredValue,
        reward_amount: body.rewardAmount,
        currency: 'INR',
        pickup_name: body.pickupName,
        pickup_geo: `POINT(${body.pickup.lon} ${body.pickup.lat})`,
        drop_name: body.dropName,
        drop_geo: `POINT(${body.drop.lon} ${body.drop.lat})`,
        weight_kg: body.weightKg,
        status: 'OPEN',
        inspection_status: 'APPROVED',
      })
      .select()
      .single();

    if (error || !created) throw app.httpErrors.badRequest(error?.message || 'Failed to create shipment');
    return reply.code(201).send({ shipment: created });
  });
}

