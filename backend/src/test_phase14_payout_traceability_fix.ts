import 'dotenv/config';
import { adminSupabase, createUserSupabase } from './lib/supabase.js';
import { releaseVerifiedOrder } from './services/escrow.js';

async function testPayoutTraceabilityFix() {
  console.log('================================================================');
  console.log(' PHASE 14 — MOCK PAYOUT TRACEABILITY FIX LIVE PROOF            ');
  console.log('================================================================');

  const userAId = 'ed9517fc-7ebe-437c-bdc0-abb45bef9079'; // Seller
  const userAEmail = 'shipsterheadquarter@gmail.com';

  const userBId = 'dc07d14a-b820-4178-928f-4de1cfab13bb'; // Buyer
  const userBEmail = 'susrijambagi@gmail.com';

  const userCEmail = 'e2e_carrier_user_c@shipdehop.internal'; // Hopster Carrier
  const { data: userCObj } = await adminSupabase.from('users').select('id').eq('email', userCEmail).single();
  const userCId = userCObj!.id;

  // Authenticate users
  const { data: authA } = await adminSupabase.auth.signInWithPassword({ email: userAEmail, password: 'E2ETestPassword123!' });
  const { data: authB } = await adminSupabase.auth.signInWithPassword({ email: userBEmail, password: 'E2ETestPassword123!' });
  const { data: authC } = await adminSupabase.auth.signInWithPassword({ email: userCEmail, password: 'E2ETestPassword123!' });

  const clientA = createUserSupabase(authA!.session!.access_token);
  const clientB = createUserSupabase(authB!.session!.access_token);
  const clientC = createUserSupabase(authC!.session!.access_token);

  // 1. Create NEW disposable shippable listing
  const { data: item, error: itemErr } = await clientA.from('marketplace_items').insert({
    seller_id: userAId,
    title: 'E2E Traceability Proof Gaming Mouse',
    description: 'Disposable E2E Test Item for Payout Traceability Fix',
    price: 200.00,
    quantity: 5,
    available_quantity: 5,
    category: 'Electronics',
    condition: 'NEW',
    currency: 'QAR',
    location_name: 'Doha West Bay',
    jurisdiction_code: 'QA',
    ship_eligible: true,
    status: 'LISTED',
    location_geo: 'POINT(51.5 25.3)'
  }).select().single();

  if (itemErr || !item) throw new Error(`Listing creation failed: ${itemErr?.message}`);
  console.log(`[PASS] Created disposable listing: ID = ${item.id}`);

  // 2. Buyer (User B) purchases qty 2 via PARCELPOOL (subtotal = 400 QAR, delivery reward = 60 QAR)
  const idempKey = `traceability_proof_${Date.now()}`;
  const { data: purchaseRes, error: purchaseErr } = await clientB.rpc('reserve_marketplace_purchase', {
    p_actor_id: userBId,
    p_item_id: item.id,
    p_quantity: 2,
    p_fulfillment_mode: 'PARCELPOOL',
    p_delivery_reward: 60.00,
    p_idempotency_key: idempKey,
    p_dest_name: 'Pearl Qatar',
    p_dest_lat: 25.37,
    p_dest_lng: 51.55,
    p_weight_kg: 1.5
  });

  if (purchaseErr) throw new Error(`Purchase reservation failed: ${purchaseErr.message}`);
  const parsedRes = typeof purchaseRes === 'string' ? JSON.parse(purchaseRes) : purchaseRes;
  const purchase = parsedRes.purchase;
  const escrowOrder = parsedRes.escrow_order;
  const shipmentTaskId = parsedRes.shipment_task_id;

  console.log(`[PASS] Created purchase ID = ${purchase.id}, Escrow Order ID = ${escrowOrder.id}, Shipment Task ID = ${shipmentTaskId}`);

  // 3. Lock MOCK payment & Approve inspection
  await adminSupabase.from('escrow_orders').update({
    escrow_status: 'LOCKED',
    payment_provider: 'MOCK',
    provider_payment_ref: `mock_pay_ref_traceability_${Date.now()}`
  }).eq('id', escrowOrder.id);

  await adminSupabase.from('shipment_tasks').update({ inspection_status: 'APPROVED' }).eq('id', shipmentTaskId);

  // 4. Create carrier trip for User C
  const { data: trip, error: tripErr } = await adminSupabase.from('trip_routes').insert({
    driver_id: userCId,
    origin_name: 'Doha West Bay',
    dest_name: 'Pearl Qatar',
    departure_time: new Date(Date.now() + 7200000).toISOString(),
    seat_capacity: 4,
    available_seats: 4,
    parcel_capacity_tier: 'LUGGAGE',
    parcel_capacity_units_total: 6,
    parcel_capacity_units_available: 6,
    estimated_trip_cost: 100.00,
    price_per_seat: 15.00,
    currency: 'QAR',
    jurisdiction_code: 'QA',
    status: 'SCHEDULED',
    origin_geo: 'POINT(51.5 25.3)',
    dest_geo: 'POINT(51.55 25.37)',
    route_polyline: 'LINESTRING(51.5 25.3, 51.55 25.37)'
  }).select().single();

  if (tripErr || !trip) throw new Error(`Carrier trip creation failed: ${tripErr?.message}`);

  // 5. Match Hopster Carrier User C
  const { error: matchErr } = await clientC.rpc('reserve_shipment_order', {
    p_actor_id: userCId,
    p_shipment_id: shipmentTaskId,
    p_provider_id: userCId,
    p_trip_id: trip.id,
    p_platform_fee_bps: 600,
    p_max_detour_meters: 5000
  });

  if (matchErr) throw new Error(`Carrier match failed: ${matchErr.message}`);
  console.log('[PASS] Hopster carrier match completed');

  // 6. Complete delivery handoff
  await adminSupabase.from('shipment_tasks').update({ status: 'IN_TRANSIT' }).eq('id', shipmentTaskId);
  await adminSupabase.from('escrow_orders').update({ fulfillment_status: 'VERIFIED' }).eq('id', escrowOrder.id);
  await adminSupabase.from('marketplace_purchases').update({ status: 'VERIFIED' }).eq('id', purchase.id);
  await adminSupabase.from('shipment_tasks').update({ status: 'DELIVERED' }).eq('id', shipmentTaskId);

  // 7. Execute releaseVerifiedOrder
  const releaseResult = await releaseVerifiedOrder(escrowOrder.id);
  console.log('[PASS] releaseVerifiedOrder executed, returned transferRef:', releaseResult.transferRef);

  // 8. Fetch allocations and verify transfer refs
  const { data: allocs, error: allocsErr } = await adminSupabase
    .from('escrow_payout_allocations')
    .select('allocation_type, recipient_id, amount, status, transfer_ref')
    .eq('order_id', escrowOrder.id)
    .order('allocation_type');

  if (allocsErr || !allocs || allocs.length !== 2) {
    throw new Error('Payout allocations query failed or count mismatch');
  }

  const sellerAlloc = allocs.find((a) => a.allocation_type === 'SELLER_PROCEEDS');
  const hopsterAlloc = allocs.find((a) => a.allocation_type === 'HOPSTER_REWARD');

  console.log('\n--- LIVE PAYOUT ALLOCATION TRANSFER REFS ---');
  console.log(`Seller Proceeds (${sellerAlloc?.amount} QAR): transfer_ref = ${sellerAlloc?.transfer_ref}`);
  console.log(`Hopster Reward (${hopsterAlloc?.amount} QAR): transfer_ref = ${hopsterAlloc?.transfer_ref}`);

  // PROOF 1: seller.transfer_ref != hopster.transfer_ref
  if (sellerAlloc?.transfer_ref === hopsterAlloc?.transfer_ref) {
    throw new Error(`FAIL: Seller transfer_ref equals Hopster transfer_ref (${sellerAlloc?.transfer_ref})`);
  }
  console.log('[PASS] PROOF 1: Seller transfer_ref != Hopster transfer_ref');

  // 9. Retry releaseVerifiedOrder
  const retryResult = await releaseVerifiedOrder(escrowOrder.id);
  console.log('[PASS] Retry releaseVerifiedOrder executed');

  // Fetch allocations after retry
  const { data: allocsRetry } = await adminSupabase
    .from('escrow_payout_allocations')
    .select('allocation_type, recipient_id, amount, status, transfer_ref')
    .eq('order_id', escrowOrder.id)
    .order('allocation_type');

  const sellerAllocRetry = allocsRetry?.find((a) => a.allocation_type === 'SELLER_PROCEEDS');
  const hopsterAllocRetry = allocsRetry?.find((a) => a.allocation_type === 'HOPSTER_REWARD');

  const { data: tripRetry } = await adminSupabase.from('trip_routes').select('parcel_capacity_units_available').eq('id', trip.id).single();
  const { data: escrowRetry } = await adminSupabase.from('escrow_orders').select('escrow_status').eq('id', escrowOrder.id).single();

  // PROOF 2: seller transfer_ref unchanged
  if (sellerAllocRetry?.transfer_ref !== sellerAlloc?.transfer_ref) {
    throw new Error('FAIL: Seller transfer_ref changed on retry');
  }
  console.log('[PASS] PROOF 2: Seller transfer_ref unchanged on retry');

  // PROOF 3: hopster transfer_ref unchanged
  if (hopsterAllocRetry?.transfer_ref !== hopsterAlloc?.transfer_ref) {
    throw new Error('FAIL: Hopster transfer_ref changed on retry');
  }
  console.log('[PASS] PROOF 3: Hopster transfer_ref unchanged on retry');

  // PROOF 4: no additional payout allocations
  if (allocsRetry?.length !== 2) {
    throw new Error('FAIL: Additional payout allocations created on retry');
  }
  console.log('[PASS] PROOF 4: No additional payout allocations created (allocations count = 2)');

  // PROOF 5: no additional capacity mutation
  if (tripRetry?.parcel_capacity_units_available !== 3) {
    throw new Error(`FAIL: Trip capacity mutated on retry (got ${tripRetry?.parcel_capacity_units_available})`);
  }
  console.log('[PASS] PROOF 5: Trip parcel capacity unchanged on retry (available = 3)');

  // PROOF 6: parent escrow remains RELEASED
  if (escrowRetry?.escrow_status !== 'RELEASED') {
    throw new Error('FAIL: Escrow status changed on retry');
  }
  console.log('[PASS] PROOF 6: Parent escrow status remains RELEASED');

  console.log('\n================================================================');
  console.log('  DISPOSABLE LIVE PAYOUT TRACEABILITY TEST SUMMARY              ');
  console.log('================================================================');
  console.log(`  - Disposable Purchase ID: ${purchase.id}`);
  console.log(`  - Disposable Escrow Order ID: ${escrowOrder.id}`);
  console.log(`  - Disposable Shipment Task ID: ${shipmentTaskId}`);
  console.log(`  - Seller Proceeds (396.00 QAR): ${sellerAlloc?.transfer_ref}`);
  console.log(`  - Hopster Reward (60.00 QAR): ${hopsterAlloc?.transfer_ref}`);
  console.log('================================================================');
  console.log(' PHASE 14 PAYOUT TRACEABILITY FIX PASSED — PHASE 14 CLOSED     ');
  console.log('================================================================');
}

testPayoutTraceabilityFix().catch((err) => {
  console.error('TRACEABILITY FIX TEST FAILED:', err);
  process.exit(1);
});
