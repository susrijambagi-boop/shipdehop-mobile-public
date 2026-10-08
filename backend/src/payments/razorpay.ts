import { config } from '../config.js';
import { toMinorUnits } from '../lib/money.js';
import type { PaymentLockInput, PaymentLockResult, PaymentProvider, PayoutInput } from './provider.js';

type RazorpayOrder = { id: string; amount: number; currency: string };
type RazorpayTransfer = { id: string };
type RazorpayRefund = { id: string };

export class RazorpayProvider implements PaymentProvider {
  private readonly auth: string;

  constructor() {
    if (!config.RAZORPAY_KEY_ID || !config.RAZORPAY_KEY_SECRET) {
      throw new Error('RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET are required');
    }
    this.auth = Buffer.from(`${config.RAZORPAY_KEY_ID}:${config.RAZORPAY_KEY_SECRET}`).toString('base64');
  }

  private async request<T>(path: string, init: RequestInit): Promise<T> {
    const response = await fetch(`https://api.razorpay.com${path}`, {
      ...init,
      headers: {
        Authorization: `Basic ${this.auth}`,
        'Content-Type': 'application/json',
        ...(init.headers ?? {}),
      },
    });
    if (!response.ok) throw new Error(`Razorpay ${response.status}: ${await response.text()}`);
    return response.json() as Promise<T>;
  }

  async createLock(input: PaymentLockInput): Promise<PaymentLockResult> {
    const order = await this.request<RazorpayOrder>('/v1/orders', {
      method: 'POST',
      body: JSON.stringify({
        amount: toMinorUnits(input.amount, input.currency),
        currency: input.currency.toUpperCase(),
        receipt: input.orderId,
        notes: { shipdehop_order_id: input.orderId },
      }),
    });
    return { provider: 'RAZORPAY', paymentRef: order.id, checkoutOrderId: order.id, amountMinor: order.amount };
  }

  async resumeLock(paymentRef: string): Promise<PaymentLockResult> {
    const order = await this.request<RazorpayOrder>(`/v1/orders/${paymentRef}`, { method: 'GET' });
    return { provider: 'RAZORPAY', paymentRef: order.id, checkoutOrderId: order.id, amountMinor: order.amount };
  }

  async release(input: PayoutInput): Promise<{ transferRef: string }> {
    const transferKey = input.idempotencyKey ?? `order-${input.orderId}-release-${input.connectedAccountId}`;
    const result = await this.request<{ items: RazorpayTransfer[] }>(`/v1/payments/${input.paymentRef}/transfers`, {
      method: 'POST',
      headers: { 'X-Razorpay-Idempotency-Key': transferKey },
      body: JSON.stringify({ transfers: [{ account: input.connectedAccountId, amount: toMinorUnits(input.providerAmount, input.currency), currency: input.currency.toUpperCase(), notes: { shipdehop_order_id: input.orderId } }] }),
    });
    const first = result.items[0];
    if (!first) throw new Error('Razorpay transfer response was empty');
    return { transferRef: first.id };
  }

  async refund(paymentRef: string, amount: number, currency: string): Promise<{ refundRef: string }> {
    const refund = await this.request<RazorpayRefund>(`/v1/payments/${paymentRef}/refund`, {
      method: 'POST',
      body: JSON.stringify({ amount: toMinorUnits(amount, currency), notes: { reason: 'shipdehop_order_refund' } }),
    });
    return { refundRef: refund.id };
  }
}
