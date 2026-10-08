import { config } from '../config.js';
import type { PaymentProvider } from './provider.js';
import { RazorpayProvider } from './razorpay.js';
import { StripeProvider } from './stripe.js';
import { MockProvider } from './mock.js';
import { DisabledProvider } from './disabled.js';

const cache = new Map<string, PaymentProvider>();

export function paymentProvider(
  name: 'STRIPE' | 'RAZORPAY' | 'DISABLED' | 'MOCK' = config.PAYMENT_PROVIDER
): PaymentProvider {
  const existing = cache.get(name);
  if (existing) return existing;

  const created =
    name === 'RAZORPAY'
      ? new RazorpayProvider()
      : name === 'MOCK'
        ? new MockProvider()
        : name === 'DISABLED'
          ? new DisabledProvider()
          : new StripeProvider();

  cache.set(name, created);
  return created;
}