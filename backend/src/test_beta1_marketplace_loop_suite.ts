import assert from 'node:assert';
import { randomBytes, randomInt, createHash } from 'node:crypto';
import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import { orderRoutes } from './routes/orders.js';
import { tripRoutes } from './routes/trips.js';
import { historyRoutes } from './routes/history.js';
import { config } from './config.js';
import { JwtSessionManager } from './services/jwt_session.js';
import { IdentityVerificationManager } from './services/identity_verification.js';

// Enforce PAYMENT_PROVIDER=DISABLED for Beta 1 marketplace testing
(config as any).PAYMENT_PROVIDER = 'DISABLED';

console.log('=== RUNNING BETA 1 SENDER ↔ TRAVELLER MARKETPLACE LOOP TEST SUITE ===');

async function runTests() {
  let passed = 0;
  async function it(name: string, fn: () => void | Promise<void>) {
    try {
      await fn();
      passed++;
      console.log(`  ✓ ${name}`);
    } catch (err: any) {
      console.error(`  ✗ ${name}:`, err.message);
      throw err;
    }
  }

  // Generate test user identities
  const senderId = '11111111-1111-4111-8111-111111111111';
  const travellerId = '22222222-2222-4222-8222-222222222222';
  const traveller2Id = '22222222-2222-4222-8222-333333333333';
  const thirdPartyId = '33333333-3333-4333-8333-333333333333';
  const unverifiedId = '44444444-4444-4444-8444-444444444444';
  const pendingReviewId = '44444444-4444-4444-8444-555555555555';
  const blockedId = '44444444-4444-4444-8444-666666666666';

  // Seed identities into IdentityVerificationManager
  for (const uid of [senderId, travellerId, traveller2Id, thirdPartyId]) {
    IdentityVerificationManager.setIdentity(uid, {
      id: uid,
      userId: uid,
      verificationStatus: 'VERIFIED',
      consentVersion: '1.0',
      consentedAt: new Date(),
      identityMethod: 'OTHER_GOV_ID',
      signatureValid: true,
      livenessStatus: 'PASS',
      faceMatchStatus: 'PASS',
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  }

  IdentityVerificationManager.setIdentity(pendingReviewId, {
    id: pendingReviewId,
    userId: pendingReviewId,
    verificationStatus: 'PENDING_REVIEW',
    consentVersion: '1.0',
    consentedAt: new Date(),
    identityMethod: 'OTHER_GOV_ID',
    signatureValid: true,
    livenessStatus: 'PASS',
    faceMatchStatus: 'PASS',
    createdAt: new Date(),
    updatedAt: new Date(),
  });

  IdentityVerificationManager.setIdentity(blockedId, {
    id: blockedId,
    userId: blockedId,
    verificationStatus: 'REJECTED',
    consentVersion: '1.0',
    consentedAt: new Date(),
    identityMethod: 'OTHER_GOV_ID',
    signatureValid: false,
    livenessStatus: 'FAIL',
    faceMatchStatus: 'FAIL',
    createdAt: new Date(),
    updatedAt: new Date(),
  });

  const tripId = '55555555-5555-4555-8555-555555555555';
  const parcelId = '66666666-6666-4666-8666-666666666666';
  const orderId = '77777777-7777-4777-8777-777777777777';

  // State stores for mock database
  const shipmentTasks = new Map<string, any>([
    [
      parcelId,
      {
        id: parcelId,
        sender_id: senderId,
        item_type: 'PARCEL',
        status: 'OPEN',
        inspection_status: 'APPROVED',
        pickup_name: 'Bangalore Indiranagar',
        drop_name: 'Bangalore Koramangala',
        weight_kg: 2.5,
        declared_value: 500,
        reward_amount: 150,
        currency: 'INR',
        parcel_capacity_units_required: 2,
      },
    ],
  ]);

  const tripRoutesMap = new Map<string, any>([
    [
      tripId,
      {
        id: tripId,
        driver_id: travellerId,
        status: 'SCHEDULED',
        parcel_capacity_tier: 'MEDIUM',
        parcel_capacity_units_total: 6,
        parcel_capacity_units_available: 6,
        origin_name: 'Bangalore Indiranagar',
        dest_name: 'Bangalore Electronic City',
        currency: 'INR',
      },
    ],
  ]);

  const escrowOrders = new Map<string, any>();
  const escrowEvents: any[] = [];
  const notifications: any[] = [];
  const notificationKeys = new Set<string>();

  // Mock Supabase client
  const createMockUserSupabase = (userId: string) => ({
    rpc: async (fn: string, params: any) => {
      return { data: null, error: null };
    },
  });

  // Mock admin Supabase
  const mockAdminSupabase: any = {
    from: (table: string) => {
      let currentTable = table;
      let selectedCols = '*';
      const eqFilters = new Map<string, any>();
      let filterCol: string | null = null;
      let filterVal: any = null;
      let orFilter: string | null = null;
      let updatePayload: any = null;
      let insertPayload: any = null;
      let limitCount: number | null = null;

      const builder: any = {
        select: (cols = '*') => {
          selectedCols = cols;
          return builder;
        },
        eq: (col: string, val: any) => {
          eqFilters.set(col, val);
          filterCol = col;
          filterVal = val;
          return builder;
        },
        or: (cond: string) => {
          orFilter = cond;
          return builder;
        },
        in: (col: string, vals: any[]) => {
          return builder;
        },
        order: (col: string, opts?: any) => {
          return builder;
        },
        range: (from: number, to: number) => {
          return builder;
        },
        limit: (n: number) => {
          limitCount = n;
          return builder;
        },
        update: (payload: any) => {
          updatePayload = payload;
          const chain: any = {
            ...builder,
            eq: (col: string, val: any) => {
              eqFilters.set(col, val);
              filterCol = col;
              filterVal = val;
              const id = eqFilters.get('id') || (col === 'id' ? val : null);
              if (currentTable === 'escrow_orders' && id) {
                const ord = escrowOrders.get(id);
                if (ord) Object.assign(ord, payload);
              }
              if (currentTable === 'shipment_tasks' && id) {
                const task = shipmentTasks.get(id);
                if (task) Object.assign(task, payload);
              }
              if (currentTable === 'trip_routes' && id) {
                const trip = tripRoutesMap.get(id);
                if (trip) Object.assign(trip, payload);
              }
              return {
                ...chain,
                select: () => ({
                  single: async () => {
                    const ord = id ? escrowOrders.get(id) : null;
                    return { data: ord ?? null, error: null };
                  },
                }),
                then: (resolve: any) => {
                  resolve({ data: null, error: null });
                },
              };
            },
          };
          return chain;
        },
        insert: (payload: any) => {
          insertPayload = payload;
          const items = Array.isArray(payload) ? payload : [payload];
          if (currentTable === 'escrow_events') {
            escrowEvents.push(...items);
          }
          if (currentTable === 'shipment_tasks') {
            for (let i = 0; i < items.length; i++) {
              const id = items[i].id || `task-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
              const record = { ...items[i], id };
              shipmentTasks.set(id, record);
              items[i] = record;
            }
          }
          const res = { data: items, error: null };
          return {
            ...res,
            select: () => ({
              single: async () => ({ data: items[0], error: null }),
            }),
            then: (resolve: any) => resolve(res),
          };
        },
        maybeSingle: async () => {
          if (currentTable === 'shipment_tasks') {
            const id = eqFilters.get('id') || filterVal;
            const task = id ? shipmentTasks.get(id) : null;
            return { data: task ?? null, error: null };
          }
          if (currentTable === 'trip_routes') {
            const id = eqFilters.get('id') || filterVal;
            const trip = id ? tripRoutesMap.get(id) : null;
            return { data: trip ?? null, error: null };
          }
          if (currentTable === 'escrow_orders') {
            let matches = Array.from(escrowOrders.values());
            for (const [col, val] of eqFilters.entries()) {
              matches = matches.filter((o) => o[col] === val);
            }
            return { data: matches[0] ?? null, error: null };
          }
          return { data: null, error: null };
        },
        single: async () => {
          if (currentTable === 'escrow_orders') {
            const id = eqFilters.get('id') || filterVal;
            if (updatePayload && id) {
              const ord = escrowOrders.get(id);
              if (ord) {
                Object.assign(ord, updatePayload);
                return { data: ord, error: null };
              }
            }
            let matches = Array.from(escrowOrders.values());
            for (const [col, val] of eqFilters.entries()) {
              matches = matches.filter((o) => o[col] === val);
            }
            return { data: matches[0] ?? null, error: null };
          }
          if (currentTable === 'shipment_tasks') {
            const id = eqFilters.get('id') || filterVal;
            const task = id ? shipmentTasks.get(id) : null;
            return { data: task ?? null, error: null };
          }
          return { data: null, error: null };
        },
        selectSingle: async () => {
          return builder.single();
        },
        then: (resolve: any) => {
          if (updatePayload && filterVal) {
            if (currentTable === 'shipment_tasks') {
              const task = shipmentTasks.get(filterVal);
              if (task) Object.assign(task, updatePayload);
            }
            if (currentTable === 'trip_routes') {
              const trip = tripRoutesMap.get(filterVal);
              if (trip) Object.assign(trip, updatePayload);
            }
            if (currentTable === 'escrow_orders') {
              const ord = escrowOrders.get(filterVal);
              if (ord) Object.assign(ord, updatePayload);
            }
          }
          if (currentTable === 'escrow_events') {
            let matches = [...escrowEvents];
            for (const [col, val] of eqFilters.entries()) {
              matches = matches.filter((e) => e[col] === val);
            }
            if (limitCount != null) {
              matches = matches.slice(0, limitCount);
            }
            resolve({ data: matches, error: null });
            return;
          }
          if (currentTable === 'escrow_orders') {
            const list = Array.from(escrowOrders.values());
            resolve({ data: list, error: null });
            return;
          }
          if (currentTable === 'users') {
            resolve({
              data: [
                { id: senderId, full_name: 'Sender One', email: 'sender@example.com', ekyc_tier: 'TIER_2' },
                { id: travellerId, full_name: 'Traveller One', email: 'traveller@example.com', ekyc_tier: 'TIER_2' },
              ],
              error: null,
            });
            return;
          }
          resolve({ data: [], error: null });
        },
      };

      return builder;
    },
    rpc: async (fn: string, params: any) => {
      if (fn === 'reserve_shipment_order') {
        const trip = tripRoutesMap.get(params.p_trip_id);
        if (!trip || trip.driver_id !== params.p_provider_id || trip.status !== 'SCHEDULED') {
          return { data: null, error: { message: 'Eligible carrier route not found' } };
        }
        if (trip.departure_time && new Date(trip.departure_time).getTime() <= Date.now()) {
          return { data: null, error: { message: 'Eligible carrier route not found' } };
        }
        const task = shipmentTasks.get(params.p_shipment_id);
        if (!task || task.status !== 'OPEN') {
          return { data: null, error: { message: 'Shipment unavailable' } };
        }
        const reqUnits = task.parcel_capacity_units_required || 2;
        if (trip.parcel_capacity_units_available < reqUnits) {
          return { data: null, error: { message: 'Insufficient parcel carrying capacity on route' } };
        }

        // Atomically decrement capacity and mark task MATCHED
        trip.parcel_capacity_units_available -= reqUnits;
        task.status = 'MATCHED';

        const newOrdId = 'ord-' + Date.now() + '-' + Math.floor(Math.random() * 10000);
        const newOrd = {
          id: newOrdId,
          order_type: 'SHIPMENT',
          buyer_id: task.sender_id,
          provider_id: params.p_provider_id,
          trip_id: params.p_trip_id,
          shipment_task_id: task.id,
          total_amount: (task.reward_amount || 150) * 1.15,
          base_price: 0,
          reward_fee: task.reward_amount || 150,
          platform_fee: (task.reward_amount || 150) * 0.15,
          currency: task.currency || 'INR',
          escrow_status: 'PENDING',
          fulfillment_status: 'CREATED',
          reservation_expires_at: new Date(Date.now() + 1800_000).toISOString(),
          reserved_parcel_capacity_units: reqUnits,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        };
        escrowOrders.set(newOrdId, newOrd);
        return { data: newOrd, error: null };
      }
      if (fn === 'match_shipments_along_route') {
        const matches = Array.from(shipmentTasks.values())
          .filter((t) => t.status === 'OPEN' && t.inspection_status === 'APPROVED')
          .map((t) => ({
            shipment_task_id: t.id,
            sender_id: t.sender_id,
            pickup_name: t.pickup_name,
            drop_name: t.drop_name,
            weight_kg: t.weight_kg,
            reward_amount: t.reward_amount,
            currency: t.currency,
            pickup_distance_meters: 250,
            drop_distance_meters: 350,
          }));
        return { data: matches, error: null };
      }
      if (fn === 'create_notification') {
        if (params.p_idempotency_key && notificationKeys.has(params.p_idempotency_key)) {
          // Idempotent: ignore duplicate notification
          return { data: null, error: null };
        }
        if (params.p_idempotency_key) {
          notificationKeys.add(params.p_idempotency_key);
        }
        notifications.push(params);
        return { data: { id: 'notif-' + notifications.length }, error: null };
      }
      return { data: null, error: null };
    },
  };

  // Mock adminSupabase methods
  const { adminSupabase } = await import('./lib/supabase.js');
  (adminSupabase as any).from = mockAdminSupabase.from;
  (adminSupabase as any).rpc = mockAdminSupabase.rpc;

  // Build Fastify App
  const app = Fastify();
  await app.register(sensible);

  let currentAuthUser: any = { id: travellerId, ekyc_tier: 'TIER_2' };

  app.addHook('onRequest', async (request: any) => {
    request.authUser = currentAuthUser;
    request.userSupabase = createMockUserSupabase(currentAuthUser.id);
  });

  await app.register(orderRoutes);
  await app.register(tripRoutes);
  await app.register(historyRoutes);
  await app.ready();

  // -------------------------------------------------------------
  // GOLDEN HAPPY PATH (10 Steps) WITH MUTUAL PICKUP & ZERO FAKE ESCROW
  // -------------------------------------------------------------
  await it('Step 1: Unverified user blocked from shipment match inspection', async () => {
    currentAuthUser = { id: unverifiedId, ekyc_tier: 'TIER_1' };
    const res = await app.inject({ method: 'GET', url: `/trips/${tripId}/shipment-matches` });
    assert.strictEqual(res.statusCode, 403, 'Unverified user must be blocked with 403');
  });

  await it('Step 2: Driver fetches matching shipments along route without PII', async () => {
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'GET', url: `/trips/${tripId}/shipment-matches` });
    assert.strictEqual(res.statusCode, 200);
    const body = res.json();
    assert.ok(Array.isArray(body));
    assert.strictEqual(body.length, 1);
    assert.strictEqual(body[0].shipmentTaskId, parcelId);
    assert.strictEqual(body[0].pickupName, 'Bangalore Indiranagar');
    assert.strictEqual(body[0].phone, undefined);
    assert.strictEqual(body[0].email, undefined);
  });

  await it('Step 3: Self-matching is strictly rejected', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({
      method: 'POST',
      url: '/orders/reserve',
      payload: { type: 'SHIPMENT', shipmentTaskId: parcelId, providerId: senderId, tripId: tripId },
    });
    assert.strictEqual(res.statusCode, 400);
    assert.ok(res.json().message.includes('Sender cannot carry own shipment'));
  });

  await it('Step 4: Traveller reserves match -> order created in CREATED status under BETA_NO_PAYMENT with escrow_status=PENDING', async () => {
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    escrowOrders.set(orderId, {
      id: orderId,
      order_type: 'SHIPMENT',
      buyer_id: senderId,
      provider_id: travellerId,
      trip_id: tripId,
      shipment_task_id: parcelId,
      total_amount: 172.5,
      base_price: 0,
      reward_fee: 150,
      platform_fee: 22.5,
      currency: 'INR',
      escrow_status: 'PENDING',
      fulfillment_status: 'CREATED',
      reservation_expires_at: new Date(Date.now() + 1800_000).toISOString(),
      reserved_parcel_capacity_units: 2,
    });

    const ord = escrowOrders.get(orderId);
    assert.strictEqual(ord.fulfillment_status, 'CREATED');
    // Financial state is truthfully PENDING (unfunded)
    assert.strictEqual(ord.escrow_status, 'PENDING');
  });

  await it('Step 5: CREATED status can NEVER jump directly to IN_TRANSIT', async () => {
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/in-transit`, payload: { pickupCode: '123456' } });
    assert.strictEqual(res.statusCode, 400);
    assert.ok(res.json().message.includes('Match must be accepted by the sender before pickup'));
  });

  await it('Step 6: Mutual Acceptance: Sender accepts match -> order transitions to READY; escrow_status remains PENDING (No fake lock)', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/accept` });
    assert.strictEqual(res.statusCode, 200);
    const body = res.json();
    assert.strictEqual(body.accepted, true);
    assert.strictEqual(body.paymentMode, 'BETA_NO_PAYMENT');
    assert.strictEqual(body.order.fulfillment_status, 'READY');
    // Escrow status must NOT be faked as LOCKED
    assert.strictEqual(body.order.escrow_status, 'PENDING');

    const acceptedEvent = escrowEvents.find((e) => e.event_type === 'MATCH_ACCEPTED');
    assert.ok(acceptedEvent, 'MATCH_ACCEPTED audit event must be recorded');
  });

  let activePickupCode = '';
  await it('Step 7a: Mutual Pickup: Sender generates short-lived 6-digit pickup code', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/pickup-secret` });
    assert.strictEqual(res.statusCode, 200);
    const body = res.json();
    assert.match(body.otp, /^\d{6}$/);
    assert.ok(body.qrPayload.startsWith(`shipdehop://pickup/${orderId}`));
    assert.strictEqual(body.purpose, 'PICKUP');
    activePickupCode = body.otp;
  });

  await it('Step 7b: Mutual Pickup: Traveller cannot self-certify pickup without code', async () => {
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/confirm-pickup`, payload: {} });
    assert.strictEqual(res.statusCode, 400);
    assert.ok(res.json().message.includes('Mutual pickup verification required'));
  });

  await it('Step 7c: Mutual Pickup: Traveller enters sender pickup code -> transitions to IN_TRANSIT; escrow_status remains PENDING', async () => {
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({
      method: 'POST',
      url: `/orders/${orderId}/confirm-pickup`,
      payload: { pickupCode: activePickupCode },
    });
    assert.strictEqual(res.statusCode, 200);
    const body = res.json();
    assert.strictEqual(body.fulfillmentStatus, 'IN_TRANSIT');
    assert.strictEqual(body.verified, true);

    const ord = escrowOrders.get(orderId);
    assert.strictEqual(ord.fulfillment_status, 'IN_TRANSIT');
    assert.strictEqual(ord.escrow_status, 'PENDING'); // No fake lock

    const task = shipmentTasks.get(parcelId);
    assert.strictEqual(task.status, 'IN_TRANSIT');

    const pickupEvent = escrowEvents.find((e) => e.event_type === 'PICKUP_CONFIRMED');
    assert.ok(pickupEvent, 'PICKUP_CONFIRMED audit event must be recorded');
  });

  let activeDeliveryOtp = '';
  await it('Step 8: Delivery Secret: Sender reveals 6-digit delivery OTP at destination', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/handoff-secret` });
    assert.strictEqual(res.statusCode, 200);
    const body = res.json();
    assert.match(body.otp, /^\d{6}$/);
    assert.ok(body.qrPayload.startsWith(`shipdehop://handoff/${orderId}`));
    assert.strictEqual(body.purpose, 'DELIVERY');
    activeDeliveryOtp = body.otp;
  });

  await it('Step 9: Delivery Verification: Traveller enters delivery OTP -> COMPLETED (Zero money movement, no fake payout)', async () => {
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({
      method: 'POST',
      url: `/orders/${orderId}/verify-otp`,
      payload: { otp: activeDeliveryOtp },
    });
    assert.strictEqual(res.statusCode, 200);
    const body = res.json();
    assert.strictEqual(body.verified, true);
    assert.strictEqual(body.paymentMode, 'BETA_NO_PAYMENT');
    assert.strictEqual(body.paymentRequired, false);
    assert.strictEqual(body.fulfillmentStatus, 'COMPLETED');

    const ord = escrowOrders.get(orderId);
    assert.strictEqual(ord.fulfillment_status, 'COMPLETED');
    assert.strictEqual(ord.escrow_status, 'PENDING'); // Truthful: no fake release

    const task = shipmentTasks.get(parcelId);
    assert.strictEqual(task.status, 'DELIVERED');

    // No fake transfer refs
    assert.strictEqual(body.payout, undefined);
    assert.strictEqual(body.transferRef, undefined);
  });

  await it('Step 10: History consistency: Sender sees Delivered & Completed without fake payment claims', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'GET', url: '/history' });
    assert.strictEqual(res.statusCode, 200);
    const body = res.json();
    assert.strictEqual(body.history.length, 1);
    assert.strictEqual(body.history[0].module, 'PARCELPOOL');
    assert.strictEqual(body.history[0].roleLabel, 'Sender');
    assert.strictEqual(body.history[0].statusCategory, 'COMPLETED');
    assert.strictEqual(body.history[0].userStatusLabel, 'Delivered & Completed');
    assert.strictEqual(body.history[0].counterparty.email, null); // Privacy enforced
  });

  // -------------------------------------------------------------
  // CREDENTIAL SEPARATION & ADVERSARIAL SECRET TESTS
  // -------------------------------------------------------------
  await it('Secret Separation: Delivery OTP rejected when used as pickup code', async () => {
    // Setup fresh test order in READY state
    const sepOrderId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    escrowOrders.set(sepOrderId, {
      id: sepOrderId,
      buyer_id: senderId,
      provider_id: travellerId,
      fulfillment_status: 'READY',
      escrow_status: 'PENDING',
    });

    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    // Issue pickup secret
    const pRes = await app.inject({ method: 'POST', url: `/orders/${sepOrderId}/pickup-secret` });
    const pickupOtp = pRes.json().otp;

    // Traveller tries to submit random delivery OTP as pickup code
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({
      method: 'POST',
      url: `/orders/${sepOrderId}/confirm-pickup`,
      payload: { pickupCode: '999999' },
    });
    assert.strictEqual(res.statusCode, 400);
    assert.ok(res.json().message.includes('Invalid pickup credential'));
  });

  await it('Secret Separation: Pickup code rejected when used as delivery OTP', async () => {
    const sepOrderId2 = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    escrowOrders.set(sepOrderId2, {
      id: sepOrderId2,
      buyer_id: senderId,
      provider_id: travellerId,
      fulfillment_status: 'READY',
      escrow_status: 'PENDING',
    });

    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const pRes = await app.inject({ method: 'POST', url: `/orders/${sepOrderId2}/pickup-secret` });
    const pickupOtp = pRes.json().otp;

    // Advance order to IN_TRANSIT
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    await app.inject({ method: 'POST', url: `/orders/${sepOrderId2}/confirm-pickup`, payload: { pickupCode: pickupOtp } });

    // Issue delivery secret
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const dRes = await app.inject({ method: 'POST', url: `/orders/${sepOrderId2}/handoff-secret` });
    const deliveryOtp = dRes.json().otp;

    // Traveller tries to submit the pickup OTP at delivery verification!
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({
      method: 'POST',
      url: `/orders/${sepOrderId2}/verify-otp`,
      payload: { otp: pickupOtp },
    });
    assert.strictEqual(res.statusCode, 400);
    assert.ok(res.json().message.includes('Invalid delivery code'));
  });

  await it('Adversarial: Replaying consumed delivery OTP is rejected (Single-Use)', async () => {
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({
      method: 'POST',
      url: `/orders/${orderId}/verify-otp`,
      payload: { otp: activeDeliveryOtp },
    });
    // Already completed -> idempotent response
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(res.json().idempotent, true);
  });

  await it('Adversarial: Third party User C cannot accept match or fetch secrets', async () => {
    currentAuthUser = { id: thirdPartyId, ekyc_tier: 'TIER_2' };
    const res1 = await app.inject({ method: 'POST', url: `/orders/${orderId}/accept` });
    assert.strictEqual(res1.statusCode, 403);

    const res2 = await app.inject({ method: 'POST', url: `/orders/${orderId}/pickup-secret` });
    assert.strictEqual(res2.statusCode, 403);

    const res3 = await app.inject({ method: 'POST', url: `/orders/${orderId}/handoff-secret` });
    assert.strictEqual(res3.statusCode, 403);
  });

  await it('Adversarial: Cancellation after IN_TRANSIT is strictly forbidden', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const transOrderId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    escrowOrders.set(transOrderId, {
      id: transOrderId,
      buyer_id: senderId,
      provider_id: travellerId,
      fulfillment_status: 'IN_TRANSIT',
      escrow_status: 'PENDING',
    });

    const res = await app.inject({
      method: 'POST',
      url: `/orders/${transOrderId}/cancel`,
      payload: { reason: 'Changed mind' },
    });
    assert.strictEqual(res.statusCode, 400);
    assert.ok(res.json().message.includes('Cannot cancel order once in transit'));
  });

  // -------------------------------------------------------------
  // TRUE CONCURRENCY TESTS (Actual Promise.all parallel executions)
  // -------------------------------------------------------------
  await it('Concurrency 1: Two simultaneous sender accept calls -> exactly one transitions and one notification', async () => {
    const concOrderId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    escrowOrders.set(concOrderId, {
      id: concOrderId,
      buyer_id: senderId,
      provider_id: travellerId,
      trip_id: tripId,
      fulfillment_status: 'CREATED',
      escrow_status: 'PENDING',
      reservation_expires_at: new Date(Date.now() + 1800_000).toISOString(),
    });

    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const [res1, res2] = await Promise.all([
      app.inject({ method: 'POST', url: `/orders/${concOrderId}/accept` }),
      app.inject({ method: 'POST', url: `/orders/${concOrderId}/accept` }),
    ]);

    assert.strictEqual(res1.statusCode, 200);
    assert.strictEqual(res2.statusCode, 200);
    // One was the initial accept, the second was idempotent
    const acceptedCount = (res1.json().idempotent ? 0 : 1) + (res2.json().idempotent ? 0 : 1);
    assert.strictEqual(acceptedCount, 1, 'Exactly one call performs state mutation');
  });

  await it('Concurrency 2: Two simultaneous pickup confirmations -> exactly one transitions', async () => {
    const concPickOrderId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
    escrowOrders.set(concPickOrderId, {
      id: concPickOrderId,
      buyer_id: senderId,
      provider_id: travellerId,
      trip_id: tripId,
      fulfillment_status: 'READY',
      escrow_status: 'PENDING',
    });

    // Sender generates pickup secret
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const pRes = await app.inject({ method: 'POST', url: `/orders/${concPickOrderId}/pickup-secret` });
    const pickupOtp = pRes.json().otp;

    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const [res1, res2] = await Promise.all([
      app.inject({ method: 'POST', url: `/orders/${concPickOrderId}/confirm-pickup`, payload: { pickupCode: pickupOtp } }),
      app.inject({ method: 'POST', url: `/orders/${concPickOrderId}/confirm-pickup`, payload: { pickupCode: pickupOtp } }),
    ]);

    assert.strictEqual(res1.statusCode, 200);
    assert.strictEqual(res2.statusCode, 200);
    const successCount = (res1.json().idempotent ? 0 : 1) + (res2.json().idempotent ? 0 : 1);
    assert.strictEqual(successCount, 1, 'Exactly one pickup consumes credential');
  });

  await it('Concurrency 3: Two simultaneous delivery confirmations -> exactly one completes', async () => {
    const concDelivOrderId = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
    escrowOrders.set(concDelivOrderId, {
      id: concDelivOrderId,
      buyer_id: senderId,
      provider_id: travellerId,
      trip_id: tripId,
      fulfillment_status: 'IN_TRANSIT',
      escrow_status: 'PENDING',
    });

    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const dRes = await app.inject({ method: 'POST', url: `/orders/${concDelivOrderId}/handoff-secret` });
    const deliveryOtp = dRes.json().otp;

    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const [res1, res2] = await Promise.all([
      app.inject({ method: 'POST', url: `/orders/${concDelivOrderId}/verify-otp`, payload: { otp: deliveryOtp } }),
      app.inject({ method: 'POST', url: `/orders/${concDelivOrderId}/verify-otp`, payload: { otp: deliveryOtp } }),
    ]);

    assert.strictEqual(res1.statusCode, 200);
    assert.strictEqual(res2.statusCode, 200);
    const completionCount = (res1.json().idempotent ? 0 : 1) + (res2.json().idempotent ? 0 : 1);
    assert.strictEqual(completionCount, 1, 'Exactly one delivery confirmation executes completion');
  });

  // -------------------------------------------------------------
  // RESPONSE-LOSS & IDEMPOTENCY RETRY TESTS
  // -------------------------------------------------------------
  await it('Response-loss: Accept retry returns existing accepted state without duplicate events', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const initialEventCount = escrowEvents.length;
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/accept` });
    assert.strictEqual(res.statusCode, 400); // Already completed in step 9
  });

  await it('Response-loss: Cancel retry does not duplicate capacity credit or events', async () => {
    const cancelOrderId = '88888888-8888-4888-8888-888888888888';
    const cancelParcelId = '99999999-9999-4999-8999-999999999999';

    shipmentTasks.set(cancelParcelId, { id: cancelParcelId, sender_id: senderId, status: 'MATCHED' });
    escrowOrders.set(cancelOrderId, {
      id: cancelOrderId,
      order_type: 'SHIPMENT',
      buyer_id: senderId,
      provider_id: travellerId,
      trip_id: tripId,
      shipment_task_id: cancelParcelId,
      fulfillment_status: 'READY',
      escrow_status: 'PENDING',
      reserved_parcel_capacity_units: 2,
    });
    tripRoutesMap.get(tripId).parcel_capacity_units_available = 4;

    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res1 = await app.inject({ method: 'POST', url: `/orders/${cancelOrderId}/cancel`, payload: { reason: 'User cancel' } });
    assert.strictEqual(res1.statusCode, 200);
    assert.strictEqual(tripRoutesMap.get(tripId).parcel_capacity_units_available, 6);

    // Simulated retry after response lost
    const res2 = await app.inject({ method: 'POST', url: `/orders/${cancelOrderId}/cancel`, payload: { reason: 'User cancel' } });
    assert.strictEqual(res2.statusCode, 200);
    assert.strictEqual(res2.json().message, 'Already cancelled');
    assert.strictEqual(tripRoutesMap.get(tripId).parcel_capacity_units_available, 6, 'Capacity must not be double-credited');
  });

  await it('Response-loss: Issue report retry within 60s returns idempotent response', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res1 = await app.inject({
      method: 'POST',
      url: `/orders/${orderId}/report-issue`,
      payload: { category: 'DELIVERY_PROBLEM', description: 'Address not found by traveller' },
    });
    assert.strictEqual(res1.statusCode, 200);

    const res2 = await app.inject({
      method: 'POST',
      url: `/orders/${orderId}/report-issue`,
      payload: { category: 'DELIVERY_PROBLEM', description: 'Address not found by traveller' },
    });
    assert.strictEqual(res2.statusCode, 200);
    assert.strictEqual(res2.json().idempotent, true);
  });

  // -------------------------------------------------------------
  // ENTITY EXPIRY & INVALID STATE TESTS
  // -------------------------------------------------------------
  await it('Invalid State: Expired reservation cannot be accepted', async () => {
    const expOrderId = '12121212-1212-4212-8212-121212121212';
    escrowOrders.set(expOrderId, {
      id: expOrderId,
      buyer_id: senderId,
      provider_id: travellerId,
      fulfillment_status: 'CREATED',
      escrow_status: 'PENDING',
      reservation_expires_at: new Date(Date.now() - 10_000).toISOString(), // expired
    });

    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'POST', url: `/orders/${expOrderId}/accept` });
    assert.strictEqual(res.statusCode, 400);
    assert.ok(res.json().message.includes('Match reservation has expired'));
  });

  await it('Invalid State: Cancelled order cannot be picked up', async () => {
    const canOrderId = '13131313-1313-4313-8313-131313131313';
    escrowOrders.set(canOrderId, {
      id: canOrderId,
      buyer_id: senderId,
      provider_id: travellerId,
      fulfillment_status: 'CANCELLED',
      escrow_status: 'PENDING',
    });

    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'POST', url: `/orders/${canOrderId}/confirm-pickup`, payload: { pickupCode: '123456' } });
    assert.strictEqual(res.statusCode, 400);
    assert.ok(res.json().message.includes('Cannot start transit from fulfillment status CANCELLED'));
  });

  // -------------------------------------------------------------
  // IDENTITY MATRIX TESTS
  // -------------------------------------------------------------
  await it('Identity Matrix: NOT_STARTED user rejected at all marketplace endpoints', async () => {
    currentAuthUser = { id: unverifiedId, ekyc_tier: 'TIER_1' };
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/accept` });
    assert.strictEqual(res.statusCode, 403);
  });

  await it('Identity Matrix: PENDING_REVIEW user rejected at all marketplace endpoints', async () => {
    currentAuthUser = { id: pendingReviewId, ekyc_tier: 'TIER_1' };
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/accept` });
    assert.strictEqual(res.statusCode, 403);
  });

  await it('Identity Matrix: BLOCKED user rejected at all marketplace endpoints', async () => {
    currentAuthUser = { id: blockedId, ekyc_tier: 'TIER_1' };
    const res = await app.inject({ method: 'POST', url: `/orders/${orderId}/accept` });
    assert.strictEqual(res.statusCode, 403);
  });

  await it('Identity Matrix: VERIFIED user allowed to interact', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'GET', url: '/history' });
    assert.strictEqual(res.statusCode, 200);
  });

  // -------------------------------------------------------------
  // NOTIFICATION IDEMPOTENCY TESTS
  // -------------------------------------------------------------
  await it('Notification Idempotency: Retrying notification with same key is ignored', async () => {
    const key = `test_notif_${Date.now()}`;
    const res1 = await mockAdminSupabase.rpc('create_notification', {
      p_user_id: senderId,
      p_idempotency_key: key,
      p_title: 'Test',
      p_body: 'Body',
    });
    const countBefore = notifications.length;

    const res2 = await mockAdminSupabase.rpc('create_notification', {
      p_user_id: senderId,
      p_idempotency_key: key,
      p_title: 'Test',
      p_body: 'Body',
    });
    assert.strictEqual(notifications.length, countBefore, 'Duplicate notification key must be ignored');
  });

  // -------------------------------------------------------------
  // STEP 5C: CROSS-PROCESS / RESTART PERSISTENCE REGRESSION TESTS
  // -------------------------------------------------------------
  await it('Step 5C Persistence: Process A creates pickup credential; fresh Process B validates from DB; Process C replay fails', async () => {
    const pOrderId = '88888888-8888-4888-8888-888888888888';
    escrowOrders.set(pOrderId, {
      id: pOrderId,
      order_type: 'SHIPMENT',
      buyer_id: senderId,
      provider_id: travellerId,
      trip_id: tripId,
      shipment_task_id: parcelId,
      fulfillment_status: 'READY',
      escrow_status: 'PENDING',
    });

    // Process A issues pickup secret
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const resA = await app.inject({ method: 'POST', url: `/orders/${pOrderId}/pickup-secret` });
    assert.strictEqual(resA.statusCode, 200);
    const pickupCode = resA.json().otp;

    // Verify written to database column
    const dbRecordA = escrowOrders.get(pOrderId);
    assert.ok(dbRecordA.handoff_otp_hash, 'Pickup hash must be stored in database');
    const parsedRecord = JSON.parse(dbRecordA.handoff_otp_hash);
    assert.strictEqual(parsedRecord.purpose, 'PICKUP');

    // Instantiate fresh service context (Process B) with ZERO in-memory state from Process A
    const appB = Fastify();
    await appB.register(sensible);
    appB.addHook('onRequest', async (req: any) => {
      req.authUser = { id: travellerId, ekyc_tier: 'TIER_2' };
      req.userSupabase = createMockUserSupabase(travellerId);
    });
    await appB.register(orderRoutes);
    await appB.ready();

    // Process B validates pickup credential strictly from DB
    const resB = await appB.inject({
      method: 'POST',
      url: `/orders/${pOrderId}/confirm-pickup`,
      payload: { pickupCode },
    });
    assert.strictEqual(resB.statusCode, 200, 'Process B must validate successfully from DB');
    assert.strictEqual(resB.json().fulfillmentStatus, 'IN_TRANSIT');

    // Single-use consumption: verify cleared in DB
    const dbRecordB = escrowOrders.get(pOrderId);
    assert.strictEqual(dbRecordB.handoff_otp_hash, null, 'Credential must be cleared in DB upon consumption');

    // Process C retries same code -> Handled as idempotent (already in transit) without duplicate transit events
    const appC = Fastify();
    await appC.register(sensible);
    appC.addHook('onRequest', async (req: any) => {
      req.authUser = { id: travellerId, ekyc_tier: 'TIER_2' };
      req.userSupabase = createMockUserSupabase(travellerId);
    });
    await appC.register(orderRoutes);
    await appC.ready();

    const resC = await appC.inject({
      method: 'POST',
      url: `/orders/${pOrderId}/confirm-pickup`,
      payload: { pickupCode },
    });
    assert.strictEqual(resC.statusCode, 200);
    assert.strictEqual(resC.json().idempotent, true);
  });

  await it('Step 5C Persistence: Process A creates delivery credential; fresh Process B validates from DB; Process C replay fails', async () => {
    const dOrderId = '99999999-9999-4999-8999-999999999999';
    escrowOrders.set(dOrderId, {
      id: dOrderId,
      order_type: 'SHIPMENT',
      buyer_id: senderId,
      provider_id: travellerId,
      trip_id: tripId,
      shipment_task_id: parcelId,
      fulfillment_status: 'IN_TRANSIT',
      escrow_status: 'PENDING',
    });

    // Process A issues delivery secret
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const resA = await app.inject({ method: 'POST', url: `/orders/${dOrderId}/handoff-secret` });
    assert.strictEqual(resA.statusCode, 200);
    const deliveryOtp = resA.json().otp;

    const dbRecordA = escrowOrders.get(dOrderId);
    assert.ok(dbRecordA.handoff_otp_hash, 'Delivery hash must be stored in database');
    const parsedRecord = JSON.parse(dbRecordA.handoff_otp_hash);
    assert.strictEqual(parsedRecord.purpose, 'DELIVERY');

    // Process B
    const appB = Fastify();
    await appB.register(sensible);
    appB.addHook('onRequest', async (req: any) => {
      req.authUser = { id: travellerId, ekyc_tier: 'TIER_2' };
      req.userSupabase = createMockUserSupabase(travellerId);
    });
    await appB.register(orderRoutes);
    await appB.ready();

    const resB = await appB.inject({
      method: 'POST',
      url: `/orders/${dOrderId}/verify-otp`,
      payload: { otp: deliveryOtp },
    });
    assert.strictEqual(resB.statusCode, 200, 'Process B must validate delivery OTP from DB');
    assert.strictEqual(resB.json().fulfillmentStatus, 'COMPLETED');

    // Consumed in DB
    const dbRecordB = escrowOrders.get(dOrderId);
    assert.strictEqual(dbRecordB.handoff_otp_hash, null, 'Delivery credential must be cleared in DB upon consumption');

    // Process C retries
    const appC = Fastify();
    await appC.register(sensible);
    appC.addHook('onRequest', async (req: any) => {
      req.authUser = { id: travellerId, ekyc_tier: 'TIER_2' };
      req.userSupabase = createMockUserSupabase(travellerId);
    });
    await appC.register(orderRoutes);
    await appC.ready();

    const resC = await appC.inject({
      method: 'POST',
      url: `/orders/${dOrderId}/verify-otp`,
      payload: { otp: deliveryOtp },
    });
    assert.strictEqual(resC.statusCode, 200);
    assert.strictEqual(resC.json().idempotent, true);
  });

  // -------------------------------------------------------------
  // STEP 5C: TRUE DOUBLE-MATCH RACE & CAPACITY RACE TESTS
  // -------------------------------------------------------------
  await it('Step 5C Race: True Double-Match Race: Two travellers reserve same open parcel simultaneously via Promise.all', async () => {
    const raceParcelId = 'aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    shipmentTasks.set(raceParcelId, {
      id: raceParcelId,
      sender_id: senderId,
      item_type: 'PARCEL',
      status: 'OPEN',
      inspection_status: 'APPROVED',
      weight_kg: 2,
      reward_amount: 200,
      parcel_capacity_units_required: 2,
    });

    const trip2Id = 'bbbb2222-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    tripRoutesMap.set(trip2Id, {
      id: trip2Id,
      driver_id: traveller2Id,
      status: 'SCHEDULED',
      parcel_capacity_units_total: 4,
      parcel_capacity_units_available: 4,
      departure_time: new Date(Date.now() + 86400000).toISOString(),
    });

    const initialTrip1Cap = tripRoutesMap.get(tripId).parcel_capacity_units_available;
    const initialTrip2Cap = tripRoutesMap.get(trip2Id).parcel_capacity_units_available;

    const [res1, res2] = await Promise.all([
      (async () => {
        const subApp = Fastify();
        await subApp.register(sensible);
        subApp.addHook('onRequest', async (req: any) => {
          req.authUser = { id: travellerId, ekyc_tier: 'TIER_2' };
          req.userSupabase = createMockUserSupabase(travellerId);
        });
        await subApp.register(orderRoutes);
        await subApp.ready();
        return subApp.inject({
          method: 'POST',
          url: '/orders/reserve',
          payload: { type: 'SHIPMENT', shipmentTaskId: raceParcelId, providerId: travellerId, tripId },
        });
      })(),
      (async () => {
        const subApp = Fastify();
        await subApp.register(sensible);
        subApp.addHook('onRequest', async (req: any) => {
          req.authUser = { id: traveller2Id, ekyc_tier: 'TIER_2' };
          req.userSupabase = createMockUserSupabase(traveller2Id);
        });
        await subApp.register(orderRoutes);
        await subApp.ready();
        return subApp.inject({
          method: 'POST',
          url: '/orders/reserve',
          payload: { type: 'SHIPMENT', shipmentTaskId: raceParcelId, providerId: traveller2Id, tripId: trip2Id },
        });
      })(),
    ]);

    const statuses = [res1.statusCode, res2.statusCode].sort();
    assert.deepStrictEqual(statuses, [200, 400], 'Exactly one reserve must succeed (200) and one must fail (400)');

    const matchingOrders = Array.from(escrowOrders.values()).filter((o) => o.shipment_task_id === raceParcelId);
    assert.strictEqual(matchingOrders.length, 1, 'Exactly one order must be created');
    assert.strictEqual(shipmentTasks.get(raceParcelId).status, 'MATCHED');

    const finalCap1 = tripRoutesMap.get(tripId).parcel_capacity_units_available;
    const finalCap2 = tripRoutesMap.get(trip2Id).parcel_capacity_units_available;
    const totalCapDecremented = (initialTrip1Cap - finalCap1) + (initialTrip2Cap - finalCap2);
    assert.strictEqual(totalCapDecremented, 2, 'Capacity must be decremented exactly once by 2 units');
  });

  await it('Step 5C Race: True Capacity Race: One unit available; two parcels reserve simultaneously via Promise.all', async () => {
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const tightTripId = 'cccc3333-cccc-4ccc-8ccc-cccccccccccc';
    tripRoutesMap.set(tightTripId, {
      id: tightTripId,
      driver_id: travellerId,
      status: 'SCHEDULED',
      parcel_capacity_units_total: 2,
      parcel_capacity_units_available: 2,
      departure_time: new Date(Date.now() + 86400000).toISOString(),
    });

    const pA = 'dddd4444-dddd-4ddd-8ddd-dddddddddddd';
    const pB = 'eeee5555-eeee-4eee-8eee-eeeeeeeeeeee';
    shipmentTasks.set(pA, { id: pA, sender_id: senderId, status: 'OPEN', inspection_status: 'APPROVED', reward_amount: 100, parcel_capacity_units_required: 2 });
    shipmentTasks.set(pB, { id: pB, sender_id: senderId, status: 'OPEN', inspection_status: 'APPROVED', reward_amount: 100, parcel_capacity_units_required: 2 });

    const [resA, resB] = await Promise.all([
      app.inject({ method: 'POST', url: '/orders/reserve', payload: { type: 'SHIPMENT', shipmentTaskId: pA, providerId: travellerId, tripId: tightTripId } }),
      app.inject({ method: 'POST', url: '/orders/reserve', payload: { type: 'SHIPMENT', shipmentTaskId: pB, providerId: travellerId, tripId: tightTripId } }),
    ]);

    const statuses = [resA.statusCode, resB.statusCode].sort();
    assert.deepStrictEqual(statuses, [200, 400], 'One must succeed and one must fail due to capacity exhaustion');
    assert.strictEqual(tripRoutesMap.get(tightTripId).parcel_capacity_units_available, 0, 'Capacity must be exactly 0, never negative');
  });

  // -------------------------------------------------------------
  // STEP 5C: RESPONSE-LOSS RESERVE & EXPIRED ENTITIES TESTS
  // -------------------------------------------------------------
  await it('Step 5C Response-loss: Reserve retry returns existing order without duplicate order, capacity deduction, or events', async () => {
    const rlParcel = 'ffff6666-ffff-4fff-8fff-ffffffffffff';
    shipmentTasks.set(rlParcel, { id: rlParcel, sender_id: senderId, status: 'OPEN', inspection_status: 'APPROVED', reward_amount: 100, parcel_capacity_units_required: 1 });
    const capBefore = tripRoutesMap.get(tripId).parcel_capacity_units_available;
    const ordersCountBefore = escrowOrders.size;

    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res1 = await app.inject({ method: 'POST', url: '/orders/reserve', payload: { type: 'SHIPMENT', shipmentTaskId: rlParcel, providerId: travellerId, tripId } });
    assert.strictEqual(res1.statusCode, 200);
    const orderId1 = res1.json().order.id;

    // Simulate network loss and immediate retry
    const res2 = await app.inject({ method: 'POST', url: '/orders/reserve', payload: { type: 'SHIPMENT', shipmentTaskId: rlParcel, providerId: travellerId, tripId } });
    assert.strictEqual(res2.statusCode, 200);
    assert.strictEqual(res2.json().idempotent, true);
    assert.strictEqual(res2.json().order.id, orderId1);

    assert.strictEqual(escrowOrders.size, ordersCountBefore + 1, 'No duplicate order created');
    assert.strictEqual(tripRoutesMap.get(tripId).parcel_capacity_units_available, capBefore - 1, 'No second capacity deduction');
  });

  await it('Step 5C Expired: Expired journey cannot reserve parcel; matched parcel cannot be re-reserved; unknown state fails closed', async () => {
    const expTripId = '14141414-1414-4414-8414-141414141414';
    tripRoutesMap.set(expTripId, {
      id: expTripId,
      driver_id: travellerId,
      status: 'SCHEDULED',
      departure_time: new Date(Date.now() - 3600000).toISOString(), // 1h ago
      parcel_capacity_units_available: 4,
    });
    const expP = '15151515-1515-4515-8515-151515151515';
    shipmentTasks.set(expP, { id: expP, sender_id: senderId, status: 'OPEN', inspection_status: 'APPROVED', reward_amount: 100, parcel_capacity_units_required: 1 });

    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const resExpTrip = await app.inject({ method: 'POST', url: '/orders/reserve', payload: { type: 'SHIPMENT', shipmentTaskId: expP, providerId: travellerId, tripId: expTripId } });
    assert.strictEqual(resExpTrip.statusCode, 400);

    // Mark parcel as already MATCHED
    shipmentTasks.get(expP).status = 'MATCHED';
    const resMatched = await app.inject({ method: 'POST', url: '/orders/reserve', payload: { type: 'SHIPMENT', shipmentTaskId: expP, providerId: travellerId, tripId } });
    assert.strictEqual(resMatched.statusCode, 400);
  });

  // -------------------------------------------------------------
  // STEP 5C: IDENTITY MATRIX ON CREATION (PARCEL & JOURNEY)
  // -------------------------------------------------------------
  await it('Step 5C Identity: PARCEL CREATE rejects NOT_STARTED, PENDING_REVIEW, BLOCKED; allows VERIFIED', async () => {
    const sampleParcel = {
      pickupName: 'Indiranagar',
      pickup: { lat: 12.97, lon: 77.64 },
      dropName: 'Koramangala',
      drop: { lat: 12.93, lon: 77.62 },
      rewardAmount: 150,
    };

    // NOT_STARTED
    currentAuthUser = { id: unverifiedId, ekyc_tier: 'TIER_1' };
    const res1 = await app.inject({ method: 'POST', url: '/shipments', payload: sampleParcel });
    assert.strictEqual(res1.statusCode, 403);

    // PENDING_REVIEW
    currentAuthUser = { id: pendingReviewId, ekyc_tier: 'TIER_1' };
    const res2 = await app.inject({ method: 'POST', url: '/shipments', payload: sampleParcel });
    assert.strictEqual(res2.statusCode, 403);

    // BLOCKED
    currentAuthUser = { id: blockedId, ekyc_tier: 'TIER_1' };
    const res3 = await app.inject({ method: 'POST', url: '/shipments', payload: sampleParcel });
    assert.strictEqual(res3.statusCode, 403);

    // VERIFIED
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res4 = await app.inject({ method: 'POST', url: '/shipments', payload: sampleParcel });
    assert.strictEqual(res4.statusCode, 201);
    assert.ok(res4.json().shipment.id);
  });

  await it('Step 5C Identity: JOURNEY CREATE rejects NOT_STARTED, PENDING_REVIEW, BLOCKED; allows VERIFIED', async () => {
    const sampleTrip = {
      originName: 'Indiranagar',
      origin: { lat: 12.97, lon: 77.64 },
      destinationName: 'Koramangala',
      destination: { lat: 12.93, lon: 77.62 },
      departureTime: new Date(Date.now() + 86400000).toISOString(),
      seats: 3,
      parcelCapacityTier: 'MEDIUM',
      pricePerSeat: 100,
      estimatedTripCost: 200,
      currency: 'INR',
      jurisdictionCode: 'IN-KA',
    };

    // NOT_STARTED
    currentAuthUser = { id: unverifiedId, ekyc_tier: 'TIER_1' };
    const res1 = await app.inject({ method: 'POST', url: '/trips', payload: sampleTrip });
    assert.strictEqual(res1.statusCode, 403);

    // PENDING_REVIEW
    currentAuthUser = { id: pendingReviewId, ekyc_tier: 'TIER_1' };
    const res2 = await app.inject({ method: 'POST', url: '/trips', payload: sampleTrip });
    assert.strictEqual(res2.statusCode, 403);

    // BLOCKED
    currentAuthUser = { id: blockedId, ekyc_tier: 'TIER_1' };
    const res3 = await app.inject({ method: 'POST', url: '/trips', payload: sampleTrip });
    assert.strictEqual(res3.statusCode, 403);

    // VERIFIED
    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res4 = await app.inject({ method: 'POST', url: '/trips', payload: sampleTrip });
    assert.strictEqual(res4.statusCode, 200);
  });

  // -------------------------------------------------------------
  // STEP 5C: ISSUE NOTIFICATION IDEMPOTENCY & CONTACT PRIVACY
  // -------------------------------------------------------------
  await it('Step 5C Issue Idempotency: Repeated identical issue report retry emits 1 event and 1 notification', async () => {
    const issueOrderId = '16161616-1616-4616-8616-161616161616';
    escrowOrders.set(issueOrderId, {
      id: issueOrderId,
      buyer_id: senderId,
      provider_id: travellerId,
      fulfillment_status: 'IN_TRANSIT',
      trip_id: tripId,
    });

    currentAuthUser = { id: travellerId, ekyc_tier: 'TIER_2' };
    const res1 = await app.inject({
      method: 'POST',
      url: `/orders/${issueOrderId}/report-issue`,
      payload: { category: 'SENDER_UNAVAILABLE', description: 'Sender not at pickup point' },
    });
    assert.strictEqual(res1.statusCode, 200);
    assert.strictEqual(res1.json().ok, true);

    // Immediate retry within 60s window
    const res2 = await app.inject({
      method: 'POST',
      url: `/orders/${issueOrderId}/report-issue`,
      payload: { category: 'SENDER_UNAVAILABLE', description: 'Sender not at pickup point' },
    });
    assert.strictEqual(res2.statusCode, 200);
    assert.strictEqual(res2.json().idempotent, true);

    const eventsAfter = escrowEvents.filter((e) => e.order_id === issueOrderId && e.event_type === 'ISSUE_REPORTED');
    assert.strictEqual(eventsAfter.length, 1, 'Exactly one ISSUE_REPORTED event must be recorded');

    const notifsAfter = notifications.filter((n) => n.p_entity_id === issueOrderId && n.p_type === 'SAFETY_ALERT');
    assert.strictEqual(notifsAfter.length, 1, 'Exactly one counterparty notification must be dispatched');
  });

  await it('Step 5C Privacy: Post-Match Contact Privacy: Phone and email are not exposed in history payload', async () => {
    currentAuthUser = { id: senderId, ekyc_tier: 'TIER_2' };
    const res = await app.inject({ method: 'GET', url: '/history' });
    assert.strictEqual(res.statusCode, 200);
    const history = res.json().history;
    assert.ok(history.length > 0);
    const item = history[0];
    assert.strictEqual(item.counterparty.email, null, 'Email must be redacted as null');
    assert.strictEqual(item.counterparty.phone, undefined, 'Phone must not be exposed');
  });

  console.log(`\n========================================`);
  console.log(`  Beta 1 Suite Tests Passed: ${passed}`);
  console.log(`========================================\n`);
}

runTests().catch((err) => {
  console.error('Test Suite Failed:', err);
  process.exit(1);
});
