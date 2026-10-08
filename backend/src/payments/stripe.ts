import Stripe from 'stripe';
import { config } from '../config.js';
import { toMinorUnits } from '../lib/money.js';
import type { PaymentLockInput, PaymentLockResult, PaymentProvider, PayoutInput } from './provider.js';

export class StripeProvider implements PaymentProvider {
  private readonly stripe: Stripe;

  constructor() {
    if (!config.STRIPE_SECRET_KEY) throw new Error('STRIPE_SECRET_KEY is required');
    this.stripe = new Stripe(config.STRIPE_SECRET_KEY);
  }

  async createLock(input: PaymentLockInput): Promise<PaymentLockResult> {
    const intent = await this.stripe.paymentIntents.create({
      amount: toMinorUnits(input.amount, input.currency),
      currency: input.currency.toLowerCase(),
      capture_method: 'automatic',
      automatic_payment_methods: { enabled: true },
      metadata: { shipdehop_order_id: input.orderId },
      ...(input.customerEmail ? { receipt_email: input.customerEmail } : {}),
    }, { idempotencyKey: `order:${input.orderId}:payment` });

    if (!intent.client_secret) throw new Error('Stripe did not return a client secret');
    return { provider: 'STRIPE', paymentRef: intent.id, clientSecret: intent.client_secret, amountMinor: intent.amount };
  }

  async resumeLock(paymentRef: string): Promise<PaymentLockResult> {
    const intent = await this.stripe.paymentIntents.retrieve(paymentRef);
    if (!intent.client_secret) throw new Error('Stripe payment intent has no client secret');
    return { provider: 'STRIPE', paymentRef: intent.id, clientSecret: intent.client_secret, amountMinor: intent.amount };
  }

  async release(input: PayoutInput): Promise<{ transferRef: string }> {
    const intent = await this.stripe.paymentIntents.retrieve(input.paymentRef, { expand: ['latest_charge'] });
    const latestCharge = intent.latest_charge;
    const chargeId = typeof latestCharge === 'string' ? latestCharge : latestCharge?.id;
    if (!chargeId) throw new Error('Stripe captured charge is unavailable for transfer');
    const transferKey = input.idempotencyKey ?? `order:${input.orderId}:release:${input.connectedAccountId}`;
    const transfer = await this.stripe.transfers.create({
      amount: toMinorUnits(input.providerAmount, input.currency),
      currency: input.currency.toLowerCase(),
      destination: input.connectedAccountId,
      source_transaction: chargeId,
      transfer_group: `order_${input.orderId}`,
      metadata: { shipdehop_order_id: input.orderId, payment_intent: input.paymentRef },
    }, { idempotencyKey: transferKey });
    return { transferRef: transfer.id };
  }

  async refund(paymentRef: string, amount: number, currency: string): Promise<{ refundRef: string }> {
    const refund = await this.stripe.refunds.create({
      payment_intent: paymentRef,
      amount: toMinorUnits(amount, currency),
    }, { idempotencyKey: `refund:${paymentRef}:${toMinorUnits(amount, currency)}` });
    return { refundRef: refund.id };
  }

  get client(): Stripe { return this.stripe; }
}
