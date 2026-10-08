export type PaymentLockInput = {
  orderId: string;
  amount: number;
  currency: string;
  customerEmail?: string;
};

export type PaymentLockResult = {
  provider: 'STRIPE' | 'RAZORPAY' | 'DISABLED' | 'MOCK';
  paymentRef: string;
  clientSecret?: string;
  checkoutOrderId?: string;
  amountMinor: number;
};

export type PayoutInput = {
  orderId: string;
  paymentRef: string;
  connectedAccountId: string;
  providerAmount: number;
  currency: string;
  idempotencyKey?: string;
};

export interface PaymentProvider {
  createLock(input: PaymentLockInput): Promise<PaymentLockResult>;

  resumeLock(paymentRef: string): Promise<PaymentLockResult>;

  release(input: PayoutInput): Promise<{
    transferRef: string;
  }>;

  refund(
    paymentRef: string,
    amount: number,
    currency: string,
  ): Promise<{
    refundRef: string;
  }>;
}