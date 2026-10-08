import type { FastifyInstance } from 'fastify';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { config } from '../config.js';
import { markPaymentLocked } from '../services/escrow.js';
import { StripeProvider } from '../payments/stripe.js';
import { adminSupabase } from '../lib/supabase.js';

function safeEqual(a: string, b: string): boolean {
  const aa = Buffer.from(a); const bb = Buffer.from(b);
  return aa.length === bb.length && timingSafeEqual(aa, bb);
}

export async function webhookRoutes(app: FastifyInstance): Promise<void> {
  app.post('/webhooks/stripe', { config: { rawBody: true } }, async (request, reply) => {
    if (config.PAYMENT_PROVIDER === 'DISABLED') {
      return reply.code(503).send({ error: 'Service Unavailable', message: 'Payments are temporarily unavailable.' });
    }
    if (!config.STRIPE_WEBHOOK_SECRET || !config.STRIPE_SECRET_KEY) {
      throw app.httpErrors.internalServerError('Stripe webhook secret not configured');
    }
    const signature = request.headers['stripe-signature'];
    if (typeof signature !== 'string') throw app.httpErrors.badRequest('Missing Stripe signature');
    const raw = (request as typeof request & { rawBody?: Buffer }).rawBody;
    if (!raw) throw app.httpErrors.badRequest('Raw webhook body unavailable');
    const stripe = new StripeProvider().client;
    const event = stripe.webhooks.constructEvent(raw, signature, config.STRIPE_WEBHOOK_SECRET);
    if (event.type === 'payment_intent.succeeded') {
      const intent = event.data.object;
      const orderId = intent.metadata.shipdehop_order_id;
      if (orderId) await markPaymentLocked(orderId, intent.id, 'STRIPE');
    }
    return reply.code(200).send({ received: true });
  });

  app.post('/webhooks/razorpay', { config: { rawBody: true } }, async (request, reply) => {
    if (config.PAYMENT_PROVIDER === 'DISABLED') {
      return reply.code(503).send({ error: 'Service Unavailable', message: 'Payments are temporarily unavailable.' });
    }
    if (!config.RAZORPAY_KEY_SECRET) throw app.httpErrors.internalServerError('Razorpay secret not configured');
    const signature = request.headers['x-razorpay-signature'];
    if (typeof signature !== 'string') throw app.httpErrors.badRequest('Missing Razorpay signature');
    const raw = (request as typeof request & { rawBody?: Buffer }).rawBody;
    if (!raw) throw app.httpErrors.badRequest('Raw webhook body unavailable');
    const expected = createHmac('sha256', config.RAZORPAY_KEY_SECRET).update(raw).digest('hex');
    if (!safeEqual(signature, expected)) throw app.httpErrors.unauthorized('Invalid Razorpay signature');

    const event = request.body as { event?: string; payload?: { payment?: { entity?: { id?: string; order_id?: string; notes?: { shipdehop_order_id?: string } } } } };
    if (event.event === 'payment.captured') {
      const payment = event.payload?.payment?.entity;
      let orderId = payment?.notes?.shipdehop_order_id;
      if (!orderId && payment?.order_id) {
        const { data } = await adminSupabase
          .from('escrow_orders')
          .select('id')
          .eq('payment_provider', 'RAZORPAY')
          .eq('provider_checkout_ref', payment.order_id)
          .maybeSingle();
        orderId = data?.id;
      }
      if (orderId && payment?.id) await markPaymentLocked(orderId, payment.id, 'RAZORPAY');
    }
    return reply.code(200).send({ received: true });
  });
}
