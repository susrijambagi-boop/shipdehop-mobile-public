import { toMinorUnits } from '../lib/money.js';
import type {
    PaymentLockInput,
    PaymentLockResult,
    PaymentProvider,
    PayoutInput,
} from './provider.js';

export class MockProvider implements PaymentProvider {
    async createLock(input: PaymentLockInput): Promise<PaymentLockResult> {
        return {
            provider: 'MOCK',
            paymentRef: `mock_payment_${input.orderId}`,
            clientSecret: `mock_secret_${input.orderId}`,
            amountMinor: toMinorUnits(input.amount, input.currency),
        };
    }

    async resumeLock(paymentRef: string): Promise<PaymentLockResult> {
        return {
            provider: 'MOCK',
            paymentRef,
            clientSecret: `mock_secret_resume`,
            amountMinor: 0,
        };
    }

    async release(input: PayoutInput): Promise<{ transferRef: string }> {
        const refSuffix = input.idempotencyKey
            ? input.idempotencyKey.replace(/[^a-zA-Z0-9_-]/g, '_')
            : `${input.orderId}_${input.connectedAccountId}`;
        return {
            transferRef: `mock_transfer_${refSuffix}`,
        };
    }

    async refund(paymentRef: string): Promise<{ refundRef: string }> {
        return {
            refundRef: `mock_refund_${paymentRef}`,
        };
    }
}