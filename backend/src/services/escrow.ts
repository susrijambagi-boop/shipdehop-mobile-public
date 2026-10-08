import { randomBytes, randomInt } from 'node:crypto';
import { config } from '../config.js';
import { adminSupabase } from '../lib/supabase.js';
import { feeFor } from '../lib/money.js';
import { paymentProvider } from '../payments/index.js';
import type { PaymentLockResult } from '../payments/provider.js';

export type OrderType = 'RIDE' | 'MARKETPLACE' | 'SHIPMENT';

export type SupportedPaymentProvider = 'STRIPE' | 'RAZORPAY' | 'DISABLED' | 'MOCK';

export type OrderRow = {
  id: string;
  order_type: OrderType;
  buyer_id: string;
  provider_id: string;
  trip_id: string | null;
  marketplace_item_id: string | null;
  shipment_task_id: string | null;
  total_amount: number;
  base_price: number;
  reward_fee: number;
  platform_fee: number;
  currency: string;
  escrow_status: 'PENDING' | 'LOCKED' | 'RELEASED' | 'REFUNDED' | 'DISPUTED';
  fulfillment_status: string;
  payment_provider: 'STRIPE' | 'RAZORPAY' | 'DISABLED' | 'UPI_ESCROW' | 'MOCK' | null;
  provider_checkout_ref: string | null;
  provider_payment_ref: string | null;
  reservation_expires_at: string | null;
  payout_transfer_ref?: string | null;
};

function bpsFor(type: OrderType): number {
  if (type === 'RIDE') return config.PLATFORM_FEE_BPS_RIDE;
  if (type === 'MARKETPLACE') return config.PLATFORM_FEE_BPS_MARKETPLACE;
  return config.PLATFORM_FEE_BPS_SHIPMENT;
}

function supportedProvider(
  value: OrderRow['payment_provider'],
): SupportedPaymentProvider {
  if (
    value === 'STRIPE' ||
    value === 'RAZORPAY' ||
    value === 'DISABLED' ||
    value === 'MOCK'
  ) {
    return value;
  }

  throw new Error(
    `Unsupported payment provider: ${value ?? 'not selected'}`,
  );
}

async function attachCheckoutReference(
  orderId: string,
  payment: PaymentLockResult,
): Promise<void> {
  const { error } = await adminSupabase.rpc(
    'service_attach_payment_reference',
    {
      p_order_id: orderId,
      p_provider: payment.provider,
      p_payment_ref: payment.paymentRef,
    },
  );

  if (error) {
    throw new Error(error.message);
  }
}

async function createOrResumePayment(
  order: OrderRow,
  email?: string,
): Promise<PaymentLockResult> {
  if (order.escrow_status !== 'PENDING') {
    throw new Error('Only PENDING orders can be funded');
  }

  if (
    order.reservation_expires_at &&
    new Date(order.reservation_expires_at).getTime() <= Date.now()
  ) {
    throw new Error('Reservation expired');
  }

  if (order.payment_provider && order.provider_checkout_ref) {
    const provider = supportedProvider(order.payment_provider);

    const payment = await paymentProvider(provider).resumeLock(
      order.provider_checkout_ref,
    );

    if (payment.provider === 'MOCK') {
      await markPaymentLocked(
        order.id,
        payment.paymentRef,
        'MOCK',
      );
    }

    return payment;
  }

  const lockInput = {
    orderId: order.id,
    amount: Number(order.total_amount),
    currency: order.currency,
    ...(email ? { customerEmail: email } : {}),
  };

  const payment = await paymentProvider().createLock(lockInput);

  await attachCheckoutReference(order.id, payment);

  // Development-only MOCK provider:
  // immediately simulate successful payment instead of waiting
  // for a Stripe/Razorpay webhook.
  if (payment.provider === 'MOCK') {
    await markPaymentLocked(
      order.id,
      payment.paymentRef,
      'MOCK',
    );
  }

  return payment;
}

export async function reserveAndCreatePayment(args: {
  userId: string;
  type: 'RIDE' | 'MARKETPLACE';
  tripId?: string;
  marketplaceItemId?: string;
  quantity?: number;
  email?: string;
}): Promise<{
  order: OrderRow;
  payment: PaymentLockResult;
}> {
  const isRide = args.type === 'RIDE';

  const rpcName = isRide
    ? 'reserve_ride_order'
    : 'reserve_marketplace_order';

  const params = isRide
    ? {
      p_trip_id: args.tripId,
      p_quantity: args.quantity ?? 1,
      p_platform_fee_bps: bpsFor('RIDE'),
    }
    : {
      p_item_id: args.marketplaceItemId,
      p_platform_fee_bps: bpsFor('MARKETPLACE'),
    };

  const { data, error } = await adminSupabase.rpc(
    rpcName,
    {
      ...params,
      p_actor_id: args.userId,
    },
  );

  if (error) {
    throw new Error(error.message);
  }

  const order = data as OrderRow;

  try {
    const payment = await createOrResumePayment(
      order,
      args.email,
    );

    return {
      order,
      payment,
    };
  } catch (error) {
    await adminSupabase.rpc(
      'service_cancel_pending_order',
      {
        p_order_id: order.id,
        p_reason: 'PAYMENT_SETUP_FAILED',
      },
    );

    throw error;
  }
}

export async function reserveShipmentMatch(args: {
  carrierId: string;
  shipmentTaskId: string;
  tripId: string;
  maxDetourMeters?: number;
}): Promise<{
  order: OrderRow;
  requiresBuyerPayment: true;
}> {
  const { data, error } = await adminSupabase.rpc(
    'reserve_shipment_order',
    {
      p_actor_id: args.carrierId,
      p_shipment_id: args.shipmentTaskId,
      p_provider_id: args.carrierId,
      p_trip_id: args.tripId,
      p_platform_fee_bps: bpsFor('SHIPMENT'),
      p_max_detour_meters:
        args.maxDetourMeters ?? 5000,
    },
  );

  if (error) {
    throw new Error(error.message);
  }

  return {
    order: data as OrderRow,
    requiresBuyerPayment: true,
  };
}

export async function fundExistingOrder(args: {
  orderId: string;
  buyerId: string;
  email?: string;
}): Promise<{
  order: OrderRow;
  payment: PaymentLockResult;
}> {
  const { data, error } = await adminSupabase
    .from('escrow_orders')
    .select('*')
    .eq('id', args.orderId)
    .single();

  if (error || !data) {
    throw new Error(error?.message ?? 'Order not found');
  }

  const order = data as OrderRow;

  if (order.buyer_id !== args.buyerId) {
    throw new Error(
      'Only the order buyer can fund HopPay',
    );
  }

  const eligibility = await adminSupabase.rpc('assert_india_order_eligible', { p_order: order });
  if (eligibility.error) throw new Error(eligibility.error.message);

  const payment = await createOrResumePayment(
    order,
    args.email,
  );

  return {
    order,
    payment,
  };
}

export async function markPaymentLocked(
  orderId: string,
  paymentRef: string,
  provider: SupportedPaymentProvider,
): Promise<void> {
  const otp = randomInt(0, 1_000_000)
    .toString()
    .padStart(6, '0');

  const qrSecret = randomBytes(32).toString(
    'base64url',
  );

  const { error } = await adminSupabase.rpc(
    'service_lock_order_payment',
    {
      p_order_id: orderId,
      p_provider: provider,
      p_payment_ref: paymentRef,
      p_handoff_otp: otp,
      p_qr_secret: qrSecret,
    },
  );

  if (error) {
    throw new Error(error.message);
  }

  // Dispatch payment secured notification to provider
  const { data: orderData } = await adminSupabase
    .from('escrow_orders')
    .select('id, buyer_id, provider_id, trip_id')
    .eq('id', orderId)
    .single();

  if (orderData) {
    try {
      await adminSupabase.rpc('create_notification', {
        p_user_id: orderData.provider_id,
        p_type: 'PAYMENT_SECURED',
        p_title: 'Payment secured',
        p_body: 'Escrow payment has been locked in HopPay.',
        p_entity_type: 'ORDER',
        p_entity_id: orderId,
        p_idempotency_key: `payment_secured:${orderId}:${orderData.provider_id}`,
        p_order_id: orderId,
        p_trip_id: orderData.trip_id,
      });
    } catch {
      // Non-fatal notification error handling
    }
  }
}

export async function releaseVerifiedOrder(
  orderId: string,
): Promise<{
  transferRef: string;
}> {
  const { data, error } = await adminSupabase
    .from('escrow_orders')
    .select('*')
    .eq('id', orderId)
    .single();

  if (error || !data) {
    throw new Error(error?.message ?? 'Order not found');
  }

  const order = data as OrderRow;

  if (
    order.escrow_status === 'RELEASED' &&
    order.payout_transfer_ref
  ) {
    return {
      transferRef: order.payout_transfer_ref,
    };
  }

  if (
    order.escrow_status !== 'LOCKED' ||
    order.fulfillment_status !== 'VERIFIED'
  ) {
    throw new Error(
      'Order must be LOCKED and VERIFIED before payout',
    );
  }

  if (
    !order.provider_payment_ref ||
    !order.payment_provider
  ) {
    throw new Error(
      'Captured payment reference missing',
    );
  }

  const providerName = supportedProvider(
    order.payment_provider,
  );

  const providerAmount =
    Number(order.base_price) +
    Number(order.reward_fee);

  /*
   * MOCK payment flow
   *
   * Development only.
   * No real connected payout account is required.
   */
  // Check if order has split payout allocations (e.g. Marketplace + ParcelPool split between Seller & Hopster)
  const { data: allocations, error: allocError } = await adminSupabase
    .from('escrow_payout_allocations')
    .select('*')
    .eq('order_id', order.id);

  if (allocError) {
    throw new Error(allocError.message);
  }

  let lastTransferRef = `${providerName.toLowerCase()}_tr_${order.id.slice(0, 8)}`;

  if (allocations && allocations.length > 0) {
    const pendingAllocations = allocations.filter((a) => a.status === 'PENDING');

    // Process each PENDING allocation independently
    for (const alloc of pendingAllocations) {
      let recipientAccountId: string;

      if (providerName === 'MOCK') {
        recipientAccountId = `mock_account_${alloc.recipient_id}`;
      } else {
        const { data: account, error: accountError } = await adminSupabase
          .from('payment_accounts')
          .select('external_account_id,verified')
          .eq('user_id', alloc.recipient_id)
          .eq('provider', providerName)
          .single();

        if (accountError || !account?.verified || !account.external_account_id) {
          throw new Error(
            `Recipient ${alloc.recipient_id} (${alloc.allocation_type}) payout account is not verified for ${providerName}`,
          );
        }
        recipientAccountId = account.external_account_id;
      }

      const payout = await paymentProvider(providerName).release({
        orderId: order.id,
        paymentRef: order.provider_payment_ref,
        connectedAccountId: recipientAccountId,
        providerAmount: Number(alloc.amount),
        currency: alloc.currency,
        idempotencyKey: alloc.idempotency_key,
      });

      lastTransferRef = payout.transferRef;

      const { error: updateError } = await adminSupabase
        .from('escrow_payout_allocations')
        .update({
          status: 'RELEASED',
          transfer_ref: payout.transferRef,
          updated_at: new Date().toISOString(),
        })
        .eq('id', alloc.id);

      if (updateError) {
        throw new Error(`Failed to persist payout allocation status for recipient ${alloc.recipient_id}: ${updateError.message}`);
      }

      try {
        await adminSupabase.rpc('award_user_xp', {
          p_user_id: alloc.recipient_id,
          p_xp_amount: 25,
          p_event_type: alloc.allocation_type === 'SELLER_PROCEEDS' ? 'MARKETPLACE_SALE_COMPLETED' : 'DELIVERY_FULFILLED',
          p_idempotency_key: `xp_alloc_${alloc.id}`,
        });
      } catch {
        // Non-fatal gamification error handling
      }

      try {
        const bodyText =
          alloc.allocation_type === 'SELLER_PROCEEDS'
            ? 'Item sale proceeds have been released to your account.'
            : 'Delivery reward has been released for your completed delivery.';

        await adminSupabase.rpc('create_notification', {
          p_user_id: alloc.recipient_id,
          p_type: 'PAYMENT_RELEASED',
          p_title: 'Payment released',
          p_body: bodyText,
          p_entity_type: 'ORDER',
          p_entity_id: order.id,
          p_idempotency_key: `funds_released:${order.id}:${alloc.recipient_id}:${alloc.allocation_type}`,
          p_order_id: order.id,
          p_trip_id: order.trip_id,
        });
      } catch {
        // Non-fatal notification error handling
      }
    }

    // Verify whether ALL allocations for this order are now RELEASED
    const { data: refreshedAllocations } = await adminSupabase
      .from('escrow_payout_allocations')
      .select('status')
      .eq('order_id', order.id);

    const stillPending = refreshedAllocations?.some((a) => a.status !== 'RELEASED');
    if (stillPending) {
      throw new Error('Not all payout allocations could be released. Parent order remains unreleased for retry.');
    }
  } else {
    // Normal single-provider order (RIDE or non-Marketplace SHIPMENT)
    let providerAccountId: string;

    if (providerName === 'MOCK') {
      providerAccountId = `mock_account_${order.provider_id}`;
    } else {
      const { data: account, error: accountError } = await adminSupabase
        .from('payment_accounts')
        .select('external_account_id,verified')
        .eq('user_id', order.provider_id)
        .eq('provider', providerName)
        .single();

      if (accountError || !account?.verified || !account.external_account_id) {
        throw new Error(
          `Provider payout account is not verified for ${providerName}`,
        );
      }
      providerAccountId = account.external_account_id;
    }

    const payout = await paymentProvider(providerName).release({
      orderId: order.id,
      paymentRef: order.provider_payment_ref,
      connectedAccountId: providerAccountId,
      providerAmount,
      currency: order.currency,
      idempotencyKey: `order:${order.id}:release`,
    });
    lastTransferRef = payout.transferRef;

    try {
      await adminSupabase.rpc('create_notification', {
        p_user_id: order.provider_id,
        p_type: 'PAYMENT_RELEASED',
        p_title: 'Payment released',
        p_body: 'Funds have been released for your completed delivery.',
        p_entity_type: 'ORDER',
        p_entity_id: order.id,
        p_idempotency_key: `funds_released:${order.id}:${order.provider_id}`,
        p_order_id: order.id,
        p_trip_id: order.trip_id,
      });
    } catch {
      // Non-fatal notification error handling
    }
  }

  // Only mark parent escrow order RELEASED after all required payout allocations succeed
  const { error: releaseError } = await adminSupabase.rpc(
    'service_mark_order_released',
    {
      p_order_id: order.id,
      p_transfer_ref: lastTransferRef,
    },
  );

  if (releaseError) {
    throw new Error(releaseError.message);
  }

  try {
    await adminSupabase.rpc('create_notification', {
      p_user_id: order.buyer_id,
      p_type: 'DELIVERY_COMPLETED',
      p_title: 'Delivery completed',
      p_body: 'Your delivery has been completed successfully.',
      p_entity_type: 'ORDER',
      p_entity_id: order.id,
      p_idempotency_key: `delivery_completed:${order.id}:${order.buyer_id}`,
      p_order_id: order.id,
      p_trip_id: order.trip_id,
    });
  } catch {
    // Non-fatal notification error handling
  }

  return { transferRef: lastTransferRef };
}

export async function refundOrder(
  orderId: string,
): Promise<{
  refundRef: string;
}> {
  const { data, error } = await adminSupabase
    .from('escrow_orders')
    .select('*')
    .eq('id', orderId)
    .single();

  if (error || !data) {
    throw new Error(error?.message ?? 'Order not found');
  }

  const order = data as OrderRow;

  if (order.escrow_status === 'RELEASED') {
    throw new Error(
      'Released orders require dispute/reversal workflow',
    );
  }

  if (
    !order.provider_payment_ref ||
    !order.payment_provider
  ) {
    throw new Error(
      'Captured payment reference missing',
    );
  }

  const result = await paymentProvider(
    supportedProvider(order.payment_provider),
  ).refund(
    order.provider_payment_ref,
    Number(order.total_amount),
    order.currency,
  );

  const { error: refundError } =
    await adminSupabase.rpc(
      'service_mark_order_refunded',
      {
        p_order_id: order.id,
        p_refund_ref: result.refundRef,
      },
    );

  if (refundError) {
    throw new Error(refundError.message);
  }

  try {
    await adminSupabase.rpc('create_notification', {
      p_user_id: order.buyer_id,
      p_type: 'ORDER_CANCELLED',
      p_title: 'Order cancelled',
      p_body: 'Escrow order has been cancelled and refunded.',
      p_entity_type: 'ORDER',
      p_entity_id: order.id,
      p_idempotency_key: `order_cancelled:${order.id}:${order.buyer_id}`,
      p_order_id: order.id,
      p_trip_id: order.trip_id,
    });
    if (order.provider_id) {
      await adminSupabase.rpc('create_notification', {
        p_user_id: order.provider_id,
        p_type: 'ORDER_CANCELLED',
        p_title: 'Order cancelled',
        p_body: 'Escrow order has been cancelled.',
        p_entity_type: 'ORDER',
        p_entity_id: order.id,
        p_idempotency_key: `order_cancelled:${order.id}:${order.provider_id}`,
        p_order_id: order.id,
        p_trip_id: order.trip_id,
      });
    }
  } catch (_) {}

  return result;
}

export function calculatedPlatformFee(
  type: OrderType,
  base: number,
): number {
  return feeFor(base, bpsFor(type));
}
