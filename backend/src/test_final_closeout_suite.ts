import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateIndianPinCode, normalizeIndianPhoneNumber, verifyIndiaLocation, verifyRoadRouteInIndia } from './lib/locationValidation.js';
import { generateAndVerifyBoundaryAsync, EXPECTED_GENERATED_SHA256 } from '../scripts/generate_india_boundary.node.js';

import { postgis } from '@electric-sql/pglite-postgis';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

console.log('=== STARTING FINAL INDIA-LAUNCH CLOSEOUT TEST SUITE ===');

async function runCloseoutSuite() {
  const db = new PGlite({ extensions: { postgis } });

  // Install PostGIS extension and mock Supabase auth schema
  console.log('Setting up PGlite with PostGIS...');
  await db.exec(`
    CREATE EXTENSION IF NOT EXISTS postgis SCHEMA public;

    CREATE SCHEMA IF NOT EXISTS extensions;
    CREATE SCHEMA IF NOT EXISTS gis;
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE SCHEMA IF NOT EXISTS realtime;
    CREATE SCHEMA IF NOT EXISTS storage;

    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated;
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon;
      END IF;
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role;
      END IF;
    END $$;

    ALTER ROLE CURRENT_ROLE SET search_path = public, extensions, gis;
    SET search_path = public, extensions, gis;

    CREATE TABLE IF NOT EXISTS auth.users (
      id uuid PRIMARY KEY,
      email text,
      phone text,
      raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
      created_at timestamptz DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS realtime.messages (id bigint primary key, extension text, topic text);
    CREATE OR REPLACE FUNCTION realtime.topic() RETURNS text LANGUAGE sql STABLE AS $$ SELECT ''::text; $$;
    CREATE OR REPLACE FUNCTION gen_salt(type text, rounds integer DEFAULT 6) RETURNS text LANGUAGE sql AS $$ SELECT 'salt'::text; $$;
    CREATE OR REPLACE FUNCTION crypt(password text, salt text) RETURNS text LANGUAGE sql AS $$ SELECT password; $$;

    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp') THEN
        INSERT INTO pg_extension (oid, extname, extowner, extnamespace, extrelocatable, extversion)
        VALUES (99991, 'uuid-ossp', 10, (SELECT oid FROM pg_namespace WHERE nspname = 'extensions'), true, '1.1');
      END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
        INSERT INTO pg_extension (oid, extname, extowner, extnamespace, extrelocatable, extversion)
        VALUES (99992, 'pgcrypto', 10, (SELECT oid FROM pg_namespace WHERE nspname = 'extensions'), true, '1.3');
      END IF;
      IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
      END IF;
    END $$;

    CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
      SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
    $$;

    CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
      SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''), 'authenticated')::text;
    $$;

    CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
      SELECT '{}'::jsonb;
    $$;
  `);

  // Apply all 17 migrations in canonical manifest order
  const manifestPath = path.resolve(__dirname, '../../db/migrations.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as { migrations: string[] };
  const migrationFiles = manifest.migrations;

  for (const file of migrationFiles) {
    const fullPath = path.resolve(__dirname, '../../db', file);
    let sql = fs.readFileSync(fullPath, 'utf8');
    sql = sql.replace(/create extension if not exists pgcrypto[^;]*;/gi, '-- skipped pgcrypto');
    console.log(`Applying migration: ${file}...`);
    await db.exec(sql);
    console.log(`✅ Applied ${file}`);
  }

  console.log('\n--- 1. Database Boundary Provenance & Asset Reproducibility ---');
  await generateAndVerifyBoundaryAsync();
  console.log('✅ Boundary dataset generation and checksum reproducibility verified.');

  console.log('\n--- 2. Address PIN Code & Phone Normalization Tests ---');
  assert.equal(validateIndianPinCode('400001'), true, 'Valid 6-digit PIN accepted');
  assert.equal(validateIndianPinCode('560001'), true, 'Valid Bengaluru PIN accepted');
  assert.equal(validateIndianPinCode('012345'), false, 'Leading zero PIN rejected');
  assert.equal(validateIndianPinCode('12345'), false, '5-digit PIN rejected');
  assert.equal(validateIndianPinCode('1234567'), false, '7-digit PIN rejected');
  assert.equal(validateIndianPinCode('56000A'), false, 'Alphanumeric PIN rejected');
  assert.equal(validateIndianPinCode(''), false, 'Empty PIN rejected');

  const phoneRes = normalizeIndianPhoneNumber('9876543210');
  assert.equal(phoneRes.isValid, true);
  assert.equal(phoneRes.phoneE164, '+919876543210');
  console.log('✅ Address PIN and phone normalization tests passed.');

  console.log('\n--- 3. Seed Users & Cost Sharing Policy ---');
  const driverId = '11111111-1111-1111-1111-111111111111';
  const requesterId = '22222222-2222-2222-2222-222222222222';
  const attackerId = '99999999-9999-9999-9999-999999999999';

  await db.exec(`
    INSERT INTO auth.users (id, phone, email)
    VALUES
      ('${driverId}', '+919876543210', 'driver@shipdehop.test'),
      ('${requesterId}', '+919876543211', 'requester@shipdehop.test'),
      ('${attackerId}', '+919876543212', 'attacker@shipdehop.test')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, phone, email, ekyc_tier)
    VALUES
      ('${driverId}', '+919876543210', 'driver@shipdehop.test', 'TIER_2'),
      ('${requesterId}', '+919876543211', 'requester@shipdehop.test', 'TIER_2'),
      ('${attackerId}', '+919876543212', 'attacker@shipdehop.test', 'TIER_1')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.cost_sharing_policies (jurisdiction_code, max_recovery_ratio, hard_cap_per_seat, currency, enabled, marketplace_platform_fee_bps)
    VALUES ('IN', 1.25, 1000.00, 'INR', true, 500)
    ON CONFLICT (jurisdiction_code) DO NOTHING;
  `);

  console.log('\n--- 4. Journey Creation Capability Tests ---');

  // Seed sample route polyline GeoJSON (Bengaluru to Mysuru)
  const blrToMysGeoJson = JSON.stringify({
    type: 'LineString',
    coordinates: [
      [77.5946, 12.9716],
      [76.6497, 12.3168]
    ]
  });

  // A. Zero estimated trip cost rejection test
  await db.exec(`SET request.jwt.claim.sub = '${driverId}';`);
  try {
    await db.exec(`
      SELECT public.create_trip_route(
        'Bengaluru', 77.5946, 12.9716,
        'Mysuru', 76.6497, 12.3168,
        '${blrToMysGeoJson}',
        NOW() + INTERVAL '2 hours',
        2::smallint, 'MEDIUM'::public.parcel_capacity_tier,
        200.0, 0.0, 'INR', 'IN', false, true, true
      );
    `);
    assert.fail('Should have rejected zero estimated trip cost');
  } catch (err: any) {
    assert.match(err.message, /estimated_trip_cost must be positive/i);
    console.log('✅ Rejection of zero estimated trip cost confirmed.');
  }

  // B. Passenger journey creation
  await db.exec(`SET request.jwt.claim.sub = '${driverId}';`);
  await db.exec(`
    SELECT public.create_trip_route(
      'Bengaluru', 77.5946, 12.9716,
      'Mysuru', 76.6497, 12.3168,
      '${blrToMysGeoJson}',
      NOW() + INTERVAL '3 hours',
      3::smallint, 'NONE'::public.parcel_capacity_tier,
      150.0, 600.0, 'INR', 'IN', false, true, false
    );
  `);
  console.log('✅ Passenger-only journey creation succeeded.');

  // C. Parcel-only journey creation (0 seats)
  const parcelTripRes: any = await db.query(`
    SELECT id FROM public.create_trip_route(
      'Bengaluru', 77.5946, 12.9716,
      'Mysuru', 76.6497, 12.3168,
      '${blrToMysGeoJson}',
      NOW() + INTERVAL '4 hours',
      0::smallint, 'LUGGAGE'::public.parcel_capacity_tier,
      0.0, 800.0, 'INR', 'IN', false, false, true, false
    );
  `);
  const parcelTripId = parcelTripRes.rows[0].id;
  assert.ok(parcelTripId, 'Parcel-only trip created successfully');
  console.log(`✅ Parcel-only journey (0 seats) created: ${parcelTripId}`);

  // D. Shopping-only journey creation (0 seats)
  const shoppingTripRes: any = await db.query(`
    SELECT id FROM public.create_trip_route(
      'Bengaluru', 77.5946, 12.9716,
      'Mysuru', 76.6497, 12.3168,
      '${blrToMysGeoJson}',
      NOW() + INTERVAL '5 hours',
      0::smallint, 'MEDIUM'::public.parcel_capacity_tier,
      0.0, 500.0, 'INR', 'IN', false, false, false, true
    );
  `);
  const shoppingTripId = shoppingTripRes.rows[0].id;
  assert.ok(shoppingTripId);
  console.log(`✅ Shopping-only journey (0 seats) created: ${shoppingTripId}`);

  console.log('\n--- 5. Matcher RPC Security & Ownership Guards ---');

  // Seed open shipment task and ride request along route
  await db.exec(`
    INSERT INTO public.shipment_tasks (sender_id, item_type, declared_value, reward_amount, currency, pickup_name, pickup_geo, drop_name, drop_geo, weight_kg, status, inspection_status)
    VALUES (
      '${requesterId}', 'PARCEL', 1000, 250, 'INR',
      'Bengaluru Pickup', ST_SetSRID(ST_MakePoint(77.5950, 12.9720), 4326)::geography,
      'Mysuru Drop', ST_SetSRID(ST_MakePoint(76.6500, 12.3170), 4326)::geography,
      2.5, 'OPEN', 'APPROVED'
    );

    INSERT INTO public.ride_requests (requester_id, pickup_name, pickup_geo, drop_name, drop_geo, earliest_departure, latest_departure, seats_needed, currency, jurisdiction_code, status)
    VALUES (
      '${requesterId}',
      'Bengaluru Stop', ST_SetSRID(ST_MakePoint(77.5950, 12.9720), 4326)::geography,
      'Mysuru Stop', ST_SetSRID(ST_MakePoint(76.6500, 12.3170), 4326)::geography,
      NOW() - INTERVAL '10 minutes', NOW() + INTERVAL '10 hours', 1, 'INR', 'IN', 'OPEN'
    );
  `);

  // Direct RPC invocation by unrelated attacker MUST fail with permission denied
  await db.exec(`SET request.jwt.claim.sub = '${attackerId}';`);
  try {
    await db.exec(`
      SELECT * FROM public.match_shipments_along_route('${parcelTripId}', 5000);
    `);
    assert.fail('Unrelated attacker should have been blocked from match_shipments_along_route');
  } catch (err: any) {
    assert.match(err.message, /Access denied: caller does not own trip route/i);
    console.log('✅ Unrelated attacker blocked from match_shipments_along_route RPC.');
  }

  try {
    await db.exec(`
      SELECT * FROM public.match_ride_requests_along_route('${parcelTripId}', 5000);
    `);
    assert.fail('Unrelated attacker should have been blocked from match_ride_requests_along_route');
  } catch (err: any) {
    assert.match(err.message, /Access denied: caller does not own trip route/i);
    console.log('✅ Unrelated attacker blocked from match_ride_requests_along_route RPC.');
  }

  // Legitimate driver RPC invocation returns PostGIS coordinates & canonical fields
  await db.exec(`SET request.jwt.claim.sub = '${driverId}';`);
  const matchShipmentsRes: any = await db.query(`
    SELECT * FROM public.match_shipments_along_route('${parcelTripId}', 5000);
  `);
  const shipmentMatches = matchShipmentsRes.rows;
  assert.equal(shipmentMatches.length, 1);
  assert.ok(shipmentMatches[0].pickup_lat);
  assert.ok(shipmentMatches[0].pickup_lon);
  assert.equal(shipmentMatches[0].sender_name, 'Verified Sender');
  console.log('✅ Legitimate driver receives valid shipment match with PostGIS coordinates and sender display label.');

  // Seed open URL_PURCHASE shopping task along route
  await db.exec(`
    INSERT INTO public.shipment_tasks (sender_id, item_type, product_url, declared_value, reward_amount, currency, pickup_name, pickup_geo, drop_name, drop_geo, weight_kg, status, inspection_status)
    VALUES (
      '${requesterId}', 'URL_PURCHASE', 'https://example.com/item/1', 1500, 300, 'INR',
      'Bengaluru Mall', ST_SetSRID(ST_MakePoint(77.5950, 12.9720), 4326)::geography,
      'Mysuru Home', ST_SetSRID(ST_MakePoint(76.6500, 12.3170), 4326)::geography,
      1.0, 'OPEN', 'APPROVED'
    );
  `);

  // Shopping-only trip (accepts_shopping_requests = true, accepts_parcels = false)
  const shoppingMatchesRes: any = await db.query(`
    SELECT * FROM public.match_shipments_along_route('${shoppingTripId}', 5000);
  `);
  const shoppingMatches = shoppingMatchesRes.rows;
  assert.equal(shoppingMatches.length, 1, 'Shopping-only trip matches exactly 1 URL_PURCHASE task');
  assert.equal(shoppingMatches[0].item_type, 'URL_PURCHASE', 'Shopping-only trip returned URL_PURCHASE task');
  console.log('✅ Shopping-only trip returned URL_PURCHASE task and excluded ordinary PARCEL task.');

  // Passenger match on zero-passenger (parcel-only) trip must return 0 matches
  const matchRidesRes: any = await db.query(`
    SELECT * FROM public.match_ride_requests_along_route('${parcelTripId}', 5000);
  `);
  assert.equal(matchRidesRes.rows.length, 0, 'No passenger matches offered when passengers disabled');
  console.log('✅ Passenger matching correctly suppressed for zero-passenger trip.');

  console.log('\n--- 6. Location-Aware Spatial Feed RPCs ---');

  // Seed marketplace items in Bengaluru and Mumbai
  await db.exec(`
    INSERT INTO public.marketplace_items (seller_id, title, description, price, currency, category, condition, location_name, location_geo, jurisdiction_code, available_quantity, ship_eligible, status, postal_code)
    VALUES
      ('${driverId}', 'Bengaluru Helmet', 'Riding helmet in Bengaluru', 1500, 'INR', 'Gear', 'LIKE_NEW', 'Bengaluru', ST_SetSRID(ST_MakePoint(77.5946, 12.9716), 4326)::geography, 'IN', 1, true, 'LISTED', '560001'),
      ('${driverId}', 'Mumbai Jacket', 'Leather jacket in Mumbai', 3000, 'INR', 'Apparel', 'NEW', 'Mumbai', ST_SetSRID(ST_MakePoint(72.8777, 19.0760), 4326)::geography, 'IN', 1, true, 'LISTED', '400001');
  `);

  // Query nearby items from Bengaluru (77.5946, 12.9716) within 50km
  const blrFeedRes: any = await db.query(`
    SELECT title FROM public.list_nearby_marketplace_items(77.5946, 12.9716, 50000, 50);
  `);
  const blrItems = blrFeedRes.rows.map((r: any) => r.title);
  assert.ok(blrItems.includes('Bengaluru Helmet'), 'Nearby Bengaluru item returned');
  assert.ok(!blrItems.includes('Mumbai Jacket'), 'Distant Mumbai item excluded from 50km Bengaluru feed');
  console.log('✅ Spatial PostGIS distance filtering (list_nearby_marketplace_items) confirmed.');

  console.log('\n--- 7. Spatial Adversarial RPC Parameter Validation ---');

  const adversarialCases = [
    { name: 'radius = 0', query: "SELECT * FROM public.list_nearby_marketplace_items(77.5946, 12.9716, 0, 50);", match: /p_radius_meters must be > 0/i },
    { name: 'radius = -1', query: "SELECT * FROM public.list_nearby_marketplace_items(77.5946, 12.9716, -1, 50);", match: /p_radius_meters must be > 0/i },
    { name: 'radius = 50001', query: "SELECT * FROM public.list_nearby_marketplace_items(77.5946, 12.9716, 50001, 50);", match: /p_radius_meters must be > 0/i },
    { name: 'limit = 0', query: "SELECT * FROM public.list_nearby_marketplace_items(77.5946, 12.9716, 50000, 0);", match: /p_limit must be between 1 and 100/i },
    { name: 'limit = 101', query: "SELECT * FROM public.list_nearby_marketplace_items(77.5946, 12.9716, 50000, 101);", match: /p_limit must be between 1 and 100/i },
    { name: 'coordinates outside India', query: "SELECT * FROM public.list_nearby_marketplace_items(55.2708, 25.2048, 50000, 50);", match: /must be within India/i },
    { name: 'shipment radius = 0', query: "SELECT * FROM public.list_nearby_open_shipments(77.5946, 12.9716, 0, 50);", match: /p_radius_meters must be > 0/i },
    { name: 'shipment limit = 101', query: "SELECT * FROM public.list_nearby_open_shipments(77.5946, 12.9716, 50000, 101);", match: /p_limit must be between 1 and 100/i },
    { name: 'shipment outside India', query: "SELECT * FROM public.list_nearby_open_shipments(55.2708, 25.2048, 50000, 50);", match: /must be within India/i },
  ];

  for (const c of adversarialCases) {
    try {
      await db.query(c.query);
      assert.fail(`Expected adversarial spatial query (${c.name}) to fail, but it succeeded.`);
    } catch (err: any) {
      assert.match(err.message, c.match, `Adversarial spatial query (${c.name}) failed with expected SQL error`);
    }
  }
  console.log('✅ Adversarial spatial parameter validation (radius=0, -1, 50001, limit=0, 101, outside India) confirmed.');

  console.log('\n🎉 ALL FINAL INDIA-LAUNCH CLOSEOUT BACKEND TESTS PASSED CLEANLY!');
}

runCloseoutSuite().catch((err) => {
  console.error('❌ Test suite failed:', err);
  process.exit(1);
});
