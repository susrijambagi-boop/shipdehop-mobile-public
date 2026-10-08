import type {
  PaymentLockInput,
  PaymentLockResult,
  PaymentProvider,
  PayoutInput,
} from './provider.js';

export class PaymentUnavailableError extends Error {
  statusCode = 503;
  constructor(message = 'Payments are temporarily unavailable.') {
    super(message);
    this.name = 'PaymentUnavailableError';
  }
}

export class DisabledProvider implements PaymentProvider {
  async createLock(_input: PaymentLockInput): Promise<PaymentLockResult> {
    throw new PaymentUnavailableError();
  }

  async resumeLock(_paymentRef: string): Promise<PaymentLockResult> {
    throw new PaymentUnavailableError();
  }

  async release(_input: PayoutInput): Promise<{ transferRef: string }> {
    throw new PaymentUnavailableError();
  }

  async refund(
    _paymentRef: string,
    _amount: number,
    _currency: string,
  ): Promise<{ refundRef: string }> {
    throw new PaymentUnavailableError();
  }
}
