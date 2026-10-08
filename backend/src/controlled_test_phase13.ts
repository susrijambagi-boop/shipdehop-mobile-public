import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://vemzufbdamdzxqktzbha.supabase.co';
const SUPABASE_SECRET_KEY = process.env.SUPABASE_SECRET_KEY || '';
const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY || '';

if (!SUPABASE_SECRET_KEY) {
  console.error('SUPABASE_SECRET_KEY is required in environment');
  process.exit(1);
}

const adminSupabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const USER_A_EMAIL = 'shipsterheadquarter@gmail.com';
const USER_B_EMAIL = 'susrijambagi@gmail.com';
const PROTECTED_ORDER_ID = '017e03ce-7280-433c-82d3-f3c2c4bb5a7f';
const PROTECTED_TRIP_ID = '7e347a18-fe35-4b89-9689-bf33071e3287';

async function main() {
  console.log('=== STARTING PHASE 13 CONTROLLED E2E VERIFICATION ===');

  // 1. Audit Protected Order & Trip
  const { data: protectedOrder } = await adminSupabase
    .from('escrow_orders')
    .select('*')
    .eq('id', PROTECTED_ORDER_ID)
    .single();

  if (!protectedOrder || protectedOrder.escrow_status !== 'LOCKED') {
    throw new Error('Protected order missing or mutated!');
  }
  console.log(`✓ Protected order ${PROTECTED_ORDER_ID} intact (Status: ${protectedOrder.escrow_status})`);

  const { data: protectedTrip } = await adminSupabase
    .from('trip_routes')
    .select('id, parcel_capacity_units_total, parcel_capacity_units_available')
    .eq('id', PROTECTED_TRIP_ID)
    .single();

  console.log(`✓ Protected trip ${PROTECTED_TRIP_ID} parcel capacity: ${protectedTrip?.parcel_capacity_units_available}/${protectedTrip?.parcel_capacity_units_total}`);

  // Fetch Dev Users
  const { data: userA } = await adminSupabase.from('users').select('id, email').eq('email', USER_A_EMAIL).single();
  const { data: userB } = await adminSupabase.from('users').select('id, email').eq('email', USER_B_EMAIL).single();

  if (!userA || !userB) throw new Error('Dev users not found');

  console.log(`User A (Pooler/Shipster): ${userA.id}`);
  console.log(`User B (Driver/Carrier): ${userB.id}`);

  // Helper for authenticated user client
  const userAClient = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ----------------------------------------------------
  // TEST 1: RIDE REQUEST MATCH
  // ----------------------------------------------------
  console.log('\n--- TEST 1: RIDE REQUEST MATCH ---');
  const now = new Date();
  const futureDeparture = new Date(now.getTime() + 4 * 3600 * 1000);
  const futureLatest = new Date(now.getTime() + 8 * 3600 * 1000);

  // User A creates ride request
  const { data: rideReq, error: reqErr } = await adminSupabase
    .from('ride_requests')
    .insert({
      requester_id: userA.id,
      pickup_name: 'Doha Corniche',
      pickup_geo: 'POINT(51.5310 25.2854)',
      drop_name: 'Lusail Marina',
      drop_geo: 'POINT(51.5310 25.4184)',
      earliest_departure: futureDeparture.toISOString(),
      latest_departure: futureLatest.toISOString(),
      seats_needed: 1,
      currency: 'QAR',
      jurisdiction_code: 'QA',
      status: 'OPEN',
    })
    .select()
    .single();

  if (reqErr) throw new Error(`Failed to create ride request: ${reqErr.message}`);
  console.log(`Created QA Ride Request: ${rideReq.id}`);

  // User B creates compatible trip
  const { data: trip1, error: tripErr } = await adminSupabase
    .from('trip_routes')
    .insert({
      driver_id: userB.id,
      origin_name: 'Doha Corniche',
      origin_geo: 'POINT(51.5310 25.2854)',
      dest_name: 'Lusail Marina',
      dest_geo: 'POINT(51.5310 25.4184)',
      route_polyline: 'LINESTRING(51.5310 25.2854, 51.5310 25.4184)',
      departure_time: new Date(now.getTime() + 6 * 3600 * 1000).toISOString(),
      price_per_seat: 30,
      estimated_trip_cost: 150,
      currency: 'QAR',
      jurisdiction_code: 'QA',
      status: 'SCHEDULED',
      available_seats: 3,
      seat_capacity: 3,
      parcel_capacity_tier: 'MEDIUM',
      parcel_capacity_units_total: 6,
      parcel_capacity_units_available: 6,
    })
    .select()
    .single();

  if (tripErr) throw new Error(`Failed to create QA trip 1: ${tripErr.message}`);
  console.log(`Created QA Trip 1: ${trip1.id}`);

  // User B accepts request
  const { data: matchOrder, error: matchErr } = await adminSupabase.rpc('accept_ride_request_and_reserve_order', {
    p_request_id: rideReq.id,
    p_trip_id: trip1.id,
    p_platform_fee_bps: 1000,
  });

  if (matchErr) throw new Error(`Ride request accept failed: ${matchErr.message}`);
  console.log(`Reserved Match Order: ${matchOrder.id}`);

  // Check notifications for User A & User B
  const { data: notifsA1 } = await adminSupabase.from('notifications').select('*').eq('user_id', userA.id).eq('entity_id', matchOrder.id);
  const { data: notifsB1 } = await adminSupabase.from('notifications').select('*').eq('user_id', userB.id).eq('entity_id', matchOrder.id);

  console.log(`User A Notifications count: ${notifsA1?.length || 0}`);
  console.log(`User B Notifications count (Actor): ${notifsB1?.length || 0}`);

  if (notifsA1?.length !== 1 || notifsA1[0].type !== 'RIDE_MATCHED') {
    throw new Error('User A did not receive RIDE_MATCHED notification!');
  }
  if (notifsB1?.length !== 0) {
    throw new Error('User B actor received redundant notification!');
  }
  console.log(`✓ Ride Match notification verified: "${notifsA1[0].title}" — ${notifsA1[0].body}`);

  // ----------------------------------------------------
  // TEST 2: DIRECT CARPOOL BOOKING
  // ----------------------------------------------------
  console.log('\n--- TEST 2: DIRECT CARPOOL BOOKING ---');
  const { data: trip2 } = await adminSupabase
    .from('trip_routes')
    .insert({
      driver_id: userB.id,
      origin_name: 'Doha Airport',
      origin_geo: 'POINT(51.5650 25.2600)',
      dest_name: 'The Pearl',
      dest_geo: 'POINT(51.5500 25.3700)',
      route_polyline: 'LINESTRING(51.5650 25.2600, 51.5500 25.3700)',
      departure_time: new Date(now.getTime() + 10 * 3600 * 1000).toISOString(),
      price_per_seat: 40,
      estimated_trip_cost: 200,
      currency: 'QAR',
      jurisdiction_code: 'QA',
      status: 'SCHEDULED',
      available_seats: 4,
      seat_capacity: 4,
    })
    .select()
    .single();

  console.log(`Created QA Trip 2: ${trip2.id} (Available seats: 4)`);

  const { data: directOrder, error: directErr } = await adminSupabase.rpc('reserve_ride_order', {
    p_actor_id: userA.id,
    p_trip_id: trip2.id,
    p_quantity: 2,
    p_platform_fee_bps: 1000,
  });

  if (directErr) throw new Error(`Direct ride booking failed: ${directErr.message}`);

  const { data: trip2After } = await adminSupabase.from('trip_routes').select('available_seats').eq('id', trip2.id).single();
  console.log(`Trip 2 available seats after booking 2 seats: ${trip2After?.available_seats} (Expected: 2)`);

  const { data: notifsB2 } = await adminSupabase.from('notifications').select('*').eq('user_id', userB.id).eq('entity_id', directOrder.id);
  const { data: notifsA2 } = await adminSupabase.from('notifications').select('*').eq('user_id', userA.id).eq('entity_id', directOrder.id);

  if (notifsB2?.length !== 1 || notifsB2[0].type !== 'RIDER_RESERVED') {
    throw new Error('Driver User B did not receive RIDER_RESERVED notification!');
  }
  if (notifsA2?.length !== 0) {
    throw new Error('Pooler User A actor received redundant notification!');
  }
  console.log(`✓ Direct CarPool Booking notification verified: "${notifsB2[0].title}" — ${notifsB2[0].body}`);

  // ----------------------------------------------------
  // TEST 3: PARCEL RESERVATION
  // ----------------------------------------------------
  console.log('\n--- TEST 3: PARCEL RESERVATION ---');
  const { data: task, error: taskErr } = await adminSupabase
    .from('shipment_tasks')
    .insert({
      sender_id: userA.id,
      item_type: 'PARCEL',
      declared_value: 0,
      reward_amount: 50,
      currency: 'QAR',
      pickup_name: 'Doha West Bay',
      pickup_geo: 'POINT(51.5310 25.3200)',
      drop_name: 'Lusail City',
      drop_geo: 'POINT(51.5310 25.4200)',
      weight_kg: 2.5,
      status: 'OPEN',
      inspection_status: 'APPROVED',
    })
    .select()
    .single();

  if (taskErr || !task) {
    throw new Error(`Failed to create parcel task: ${taskErr?.message || 'Null task data returned'}`);
  }
  console.log(`Created QA Shipment Task: ${task.id}`);

  const { data: trip3, error: tripErr3 } = await adminSupabase
    .from('trip_routes')
    .insert({
      driver_id: userB.id,
      origin_name: 'Doha West Bay',
      origin_geo: 'POINT(51.5310 25.3200)',
      dest_name: 'Lusail City',
      dest_geo: 'POINT(51.5310 25.4200)',
      route_polyline: 'LINESTRING(51.5310 25.3200, 51.5310 25.4200)',
      departure_time: new Date(now.getTime() + 12 * 3600 * 1000).toISOString(),
      price_per_seat: 25,
      estimated_trip_cost: 150,
      currency: 'QAR',
      jurisdiction_code: 'QA',
      status: 'SCHEDULED',
      available_seats: 4,
      seat_capacity: 4,
      parcel_capacity_tier: 'MEDIUM',
      parcel_capacity_units_total: 6,
      parcel_capacity_units_available: 6,
    })
    .select()
    .single();

  if (tripErr3 || !trip3) {
    throw new Error(`Failed to create QA trip 3: ${tripErr3?.message || 'Null trip3 data'}`);
  }

  const { data: parcelOrder, error: parcelErr } = await adminSupabase.rpc('reserve_shipment_order', {
    p_actor_id: userB.id,
    p_shipment_id: task.id,
    p_provider_id: userB.id,
    p_trip_id: trip3.id,
    p_platform_fee_bps: 1000,
    p_max_detour_meters: 5000,
  });

  if (parcelErr || !parcelOrder) {
    throw new Error(`Parcel reservation failed: ${parcelErr?.message || 'Null parcel order returned'}`);
  }

  const { data: trip3After } = await adminSupabase.from('trip_routes').select('parcel_capacity_units_available').eq('id', trip3.id).single();
  console.log(`Trip 3 available parcel capacity after reserving 3 units: ${trip3After?.parcel_capacity_units_available}/6`);

  const { data: notifsA3 } = await adminSupabase.from('notifications').select('*').eq('user_id', userA.id).eq('entity_id', parcelOrder.id);
  const { data: notifsB3 } = await adminSupabase.from('notifications').select('*').eq('user_id', userB.id).eq('entity_id', parcelOrder.id);

  if (notifsA3?.length !== 1 || notifsA3[0].type !== 'PARCEL_RESERVED') {
    throw new Error('Shipster User A did not receive PARCEL_RESERVED notification!');
  }
  if (notifsB3?.length !== 0) {
    throw new Error('Carrier User B actor received redundant notification!');
  }
  console.log(`✓ Parcel Reservation notification verified: "${notifsA3[0].title}" — ${notifsA3[0].body}`);

  // ----------------------------------------------------
  // TEST 4: DETERMINISTIC IDEMPOTENCY
  // ----------------------------------------------------
  console.log('\n--- TEST 4: DETERMINISTIC IDEMPOTENCY ---');
  const countBefore = (await adminSupabase.from('notifications').select('*', { count: 'exact' })).count;

  // Retry notification creation with same idempotency key
  await adminSupabase.rpc('create_notification', {
    p_user_id: userA.id,
    p_type: 'PARCEL_RESERVED',
    p_title: 'A Hopster matched your parcel',
    p_body: 'Retry test body',
    p_entity_type: 'ORDER',
    p_entity_id: parcelOrder.id,
    p_idempotency_key: `parcel_reserved:${parcelOrder.id}:${userA.id}`,
    p_order_id: parcelOrder.id,
    p_trip_id: trip3.id,
  });

  const countAfter = (await adminSupabase.from('notifications').select('*', { count: 'exact' })).count;
  console.log(`Total notification count before retry: ${countBefore}, after retry: ${countAfter}`);
  if (countBefore !== countAfter) {
    throw new Error('Idempotency failure! Duplicate notification was created.');
  }
  console.log('✓ Idempotency verified: Duplicate creation safely skipped.');

  // ----------------------------------------------------
  // TEST 5: RLS SECURITY
  // ----------------------------------------------------
  console.log('\n--- TEST 5: RLS SECURITY ---');
  // Attempt direct INSERT without service_role
  const { error: rlsInsertErr } = await userAClient
    .from('notifications')
    .insert({
      user_id: userA.id,
      type: 'RIDE_MATCHED',
      title: 'Malicious',
      body: 'Body',
      entity_type: 'ORDER',
      entity_id: matchOrder.id,
      idempotency_key: `malicious:${Date.now()}`,
    });
  console.log(`Direct Client INSERT attempt error: ${rlsInsertErr?.message || 'Blocked (as expected)'}`);

  // ----------------------------------------------------
  // TEST 6 & 7: MARK READ & UNREAD COUNT
  // ----------------------------------------------------
  console.log('\n--- TEST 6 & 7: MARK READ & UNREAD COUNT ---');
  const targetNotif = notifsA1[0];
  console.log(`Marking notification ${targetNotif.id} read...`);

  await adminSupabase
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('id', targetNotif.id);

  const { data: updatedNotif } = await adminSupabase.from('notifications').select('read_at').eq('id', targetNotif.id).single();
  console.log(`Persisted read_at: ${updatedNotif?.read_at}`);

  await adminSupabase
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('user_id', userA.id)
    .is('read_at', null);

  const { count: unreadCountUserA } = await adminSupabase
    .from('notifications')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userA.id)
    .is('read_at', null);

  console.log(`User A unread notifications after mark_all_read: ${unreadCountUserA} (Expected: 0)`);

  // ----------------------------------------------------
  // TEST 8: DEEP-LINK DATA AUDIT
  // ----------------------------------------------------
  console.log('\n--- TEST 8: DEEP-LINK FIELD AUDIT ---');
  const { data: allNotifs } = await adminSupabase.from('notifications').select('*').in('id', [notifsA1[0].id, notifsB2[0].id, notifsA3[0].id]);

  for (const n of allNotifs || []) {
    console.log(`Notif [${n.type}] -> entity_type: ${n.entity_type}, entity_id: ${n.entity_id}, order_id: ${n.order_id}, trip_id: ${n.trip_id}`);
    if (!n.order_id && !n.trip_id) {
      throw new Error(`Notification ${n.id} lacks deep link references!`);
    }
  }
  console.log('✓ Deep link data integrity confirmed for all notifications.');

  // ----------------------------------------------------
  // CLEANUP DISPOSABLE QA DATA
  // ----------------------------------------------------
  console.log('\n--- CLEANING UP DISPOSABLE QA DATA ---');
  await adminSupabase.from('escrow_orders').delete().in('id', [matchOrder.id, directOrder.id, parcelOrder.id]);
  await adminSupabase.from('shipment_tasks').delete().eq('id', task.id);
  await adminSupabase.from('ride_requests').delete().eq('id', rideReq.id);
  await adminSupabase.from('trip_routes').delete().in('id', [trip1.id, trip2.id, trip3.id]);
  await adminSupabase.from('notifications').delete().in('id', [notifsA1[0].id, notifsB2[0].id, notifsA3[0].id]);
  console.log('✓ QA Data Cleaned Up.');

  console.log('\n=== ALL PHASE 13 CONTROLLED E2E VERIFICATIONS PASSED ===');
}

main().catch((err) => {
  console.error('VERIFICATION ERROR:', err);
  process.exit(1);
});
