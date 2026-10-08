/**
 * test_migration_order_suite.ts
 *
 * Authoritative migration-order and DB-constraint test suite.
 * Derives the canonical migration list from db/migrations.json.
 *
 * Tests:
 *   A. Manifest integrity: all 17 SQL files exist, no unlisted files
 *   B. FRESH INSTALL: apply all 17 migrations on a clean PGlite instance
 *   C. UPGRADE: apply 001-012, seed legacy data, then apply 013 only
 *   D. Direct DB postal-code invariant assertions (A-G from spec)
 *
 * Wired into `npm test` via package.json.
 */

import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { postgis } from '@electric-sql/pglite-postgis';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);
const DB_DIR     = path.resolve(__dirname, '../../db');

// ─── Load canonical manifest ───────────────────────────────────────────────────

const manifestPath   = path.join(DB_DIR, 'migrations.json');
const manifest       = JSON.parse(fs.readFileSync(manifestPath, 'utf8')) as { migrations: string[] };
const CANONICAL_LIST = manifest.migrations as string[];

console.log('=== MIGRATION ORDER + POSTAL INVARIANT TEST SUITE ===');
console.log(`Canonical manifest: ${CANONICAL_LIST.length} migrations`);

// ─── PGlite bootstrap ─────────────────────────────────────────────────────────

const PREAMBLE = `
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
`;

function loadMigration(file: string): string {
  const fullPath = path.join(DB_DIR, file);
  let sql = fs.readFileSync(fullPath, 'utf8');
  // pgcrypto is pre-stubbed via the pg_extension INSERT above
  sql = sql.replace(/create extension if not exists pgcrypto[^;]*;/gi, '-- skipped pgcrypto');
  return sql;
}

async function applyMigrations(db: PGlite, files: string[]): Promise<void> {
  for (const file of files) {
    const sql = loadMigration(file);
    await db.exec(sql);
    console.log(`  ✓ Applied ${file}`);
  }
}

async function newDb(): Promise<PGlite> {
  const db = new PGlite({ extensions: { postgis } });
  await db.exec(PREAMBLE);
  return db;
}

// ─── Test A: Manifest integrity ───────────────────────────────────────────────

async function testManifestIntegrity(): Promise<void> {
  console.log('\n--- A. Manifest integrity ---');

  assert.equal(CANONICAL_LIST.length, 20, `Expected 20 canonical migrations, got ${CANONICAL_LIST.length}`);
  console.log(`  ✓ Canonical count = ${CANONICAL_LIST.length}`);

  // Every listed file must exist on disk
  for (const file of CANONICAL_LIST) {
    const fullPath = path.join(DB_DIR, file);
    assert.ok(fs.existsSync(fullPath), `Listed migration missing from disk: ${file}`);
  }
  console.log('  ✓ All 20 listed migration files exist on disk');

  // No unlisted .sql files should exist in db/
  const onDisk = fs.readdirSync(DB_DIR)
    .filter(f => f.endsWith('.sql'))
    .sort();
  const listed = new Set(CANONICAL_LIST);
  for (const f of onDisk) {
    assert.ok(listed.has(f), `Unlisted SQL file found in db/: ${f}`);
  }
  console.log(`  ✓ No unlisted SQL files found in db/ (${onDisk.length} total)`);

  // Spot-check canonical ordering
  assert.equal(CANONICAL_LIST[0],  '001_shipdehop.sql',                  'First migration must be 001');
  assert.equal(CANONICAL_LIST[19], '016_cloudflare_coord_validation_rpc.sql',  'Last migration must be 016');
  assert.ok(
    CANONICAL_LIST.indexOf('012_release_contract_fixes.sql') <
    CANONICAL_LIST.indexOf('013_release_closeout_hardening.sql'),
    '012 must precede 013',
  );
  console.log('  ✓ Ordering invariants satisfied');
}

// ─── Test B: Fresh install — all 17 migrations ────────────────────────────────

async function testFreshInstall(): Promise<PGlite> {
  console.log('\n--- B. FRESH INSTALL (all 17 migrations on clean DB) ---');
  const db = await newDb();
  await applyMigrations(db, CANONICAL_LIST);

  // Sanity: key tables exist post-install
  const tables = await db.query<{tablename: string}>(
    `SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename`,
  );
  const names = tables.rows.map(r => r.tablename);
  for (const t of ['users', 'trip_routes', 'shipment_tasks', 'marketplace_items']) {
    assert.ok(names.includes(t), `Table '${t}' missing after full migration`);
  }

  // Confirm 013 applied: sender_postal_code column must exist
  const cols = await db.query<{column_name: string}>(
    `SELECT column_name FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'shipment_tasks'
     AND column_name = 'sender_postal_code'`,
  );
  assert.equal(cols.rows.length, 1, 'sender_postal_code must exist after 013');

  // Confirm ship_eligible→postal invariant constraint exists
  const con = await db.query<{conname: string}>(
    `SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.marketplace_items'::regclass
     AND conname = 'marketplace_items_ship_eligible_requires_postal'`,
  );
  assert.equal(con.rows.length, 1, 'ship_eligible_requires_postal constraint must exist after 013');

  console.log('  ✓ Fresh install: all 17 migrations applied, schema validated');
  return db;
}

// ─── Test C: Upgrade — 001→012 with legacy data, then apply 013 only ──────────

async function testUpgradeFrom012(): Promise<PGlite> {
  console.log('\n--- C. UPGRADE (001-012 + legacy seed → apply 013 only) ---');
  const db = await newDb();

  // Apply 001-012
  const pre013 = CANONICAL_LIST.slice(0, 16); // indices 0-15
  assert.equal(pre013[pre013.length - 1], '012_release_contract_fixes.sql', 'pre-013 last file must be 012');
  await applyMigrations(db, pre013);

  // Seed legacy data that must survive migration 013:
  // - A QAR/QA historical marketplace item with NULL postal_code and ship_eligible=false
  // - A legacy shipment_tasks row with old currency=QAR
  const legacySellerId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const legacySenderId  = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

  await db.exec(`
    INSERT INTO auth.users (id, email, phone)
    VALUES
      ('${legacySellerId}', 'seller@legacy.test', '+919876543299'),
      ('${legacySenderId}', 'sender@legacy.test', '+919876543298')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.users (id, email, phone, ekyc_tier)
    VALUES
      ('${legacySellerId}', 'seller@legacy.test', '+919876543299', 'TIER_1'),
      ('${legacySenderId}', 'sender@legacy.test', '+919876543298', 'TIER_1')
    ON CONFLICT (id) DO NOTHING;

    -- Legacy marketplace item: ship_eligible=false, postal_code=NULL, currency=INR.
    -- After migration 009, the India trigger enforces INR for IN marketplace items.
    -- This row tests that existing non-shipping items with NULL postal_code
    -- are preserved unchanged by migration 013 (the new constraint uses NOT VALID).
    INSERT INTO public.marketplace_items
      (id, seller_id, title, description, price, currency, category, condition, location_name,
       location_geo, jurisdiction_code, available_quantity, ship_eligible, status)
    VALUES
      ('cccccccc-cccc-cccc-cccc-cccccccccccc',
       '${legacySellerId}', 'Legacy Listing', 'Pre-013 item with NULL postal_code, non-shipping',
       2500.00, 'INR', 'Electronics', 'GOOD', 'Mumbai, Maharashtra',
       ST_SetSRID(ST_MakePoint(72.8777, 19.0760), 4326)::geography,
       'IN', 1, false, 'LISTED')
    ON CONFLICT (id) DO NOTHING;

    -- Legacy shipment_tasks row with currency=INR (India trigger from 009 enforces INR).
    -- The goal of this upgrade test is proving migration 013 applies without error,
    -- uses the correct column name 'currency' (not 'declared_currency'),
    -- and that NOT VALID constraints do not scan/reject existing rows.
    INSERT INTO public.shipment_tasks
      (id, sender_id, item_type, weight_kg, declared_value, reward_amount,
       currency, pickup_geo, drop_geo, status)
    VALUES
      ('dddddddd-dddd-dddd-dddd-dddddddddddd',
       '${legacySenderId}', 'PARCEL', 1.5, 100.00, 10.00,
       'INR',
       ST_SetSRID(ST_MakePoint(77.5946, 12.9716), 4326)::geography,
       ST_SetSRID(ST_MakePoint(76.6394, 12.2958), 4326)::geography,
       'OPEN')
    ON CONFLICT (id) DO NOTHING;
  `);
  console.log('  ✓ Legacy seed data inserted (pre-013 INR items with NULL postal_code)');

  // Apply ONLY migration 013
  console.log('  Applying migration 013 (upgrade path)...');
  await db.exec(loadMigration('013_release_closeout_hardening.sql'));
  console.log('  ✓ Migration 013 applied');

  // Legacy data must still be readable
  const items = await db.query<{id: string, ship_eligible: boolean, postal_code: string | null}>(
    `SELECT id, ship_eligible, postal_code FROM public.marketplace_items WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'`,
  );
  assert.equal(items.rows.length, 1, 'Legacy marketplace item must survive migration 013');
  const legacyItem = items.rows[0];
  assert.ok(legacyItem !== undefined, 'Legacy item row must be defined');
  assert.equal(legacyItem.ship_eligible, false, 'Legacy ship_eligible must remain false');
  assert.equal(legacyItem.postal_code, null, 'Legacy postal_code must remain NULL');

  const tasks = await db.query<{id: string, currency: string}>(
    `SELECT id, currency FROM public.shipment_tasks WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'`,
  );
  assert.equal(tasks.rows.length, 1, 'Legacy shipment_task must survive migration 013');
  const legacyTask = tasks.rows[0];
  assert.ok(legacyTask !== undefined, 'Legacy task row must be defined');
  assert.equal(legacyTask.currency, 'INR', 'Pre-013 INR currency must be preserved unchanged by migration 013');

  console.log('  ✓ Legacy pre-013 rows (NULL postal_code marketplace item + INR shipment) intact after upgrade');
  return db;
}

// ─── Test D: Direct DB postal-code invariant assertions (A-G) ─────────────────

async function testPostalInvariantsDirect(db: PGlite): Promise<void> {
  console.log('\n--- D. Direct DB postal-code constraint assertions (A–G) ---');

  const sellerId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';
  await db.exec(`
    INSERT INTO auth.users (id, email, phone) VALUES ('${sellerId}', 'pc@test.test', '+919876543297') ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.users (id, email, phone, ekyc_tier) VALUES ('${sellerId}', 'pc@test.test', '+919876543297', 'TIER_1') ON CONFLICT (id) DO NOTHING;
  `);

  function mkItem(id: string, shipEligible: boolean, postalCode: string | null, currency = 'INR', jurisdiction = 'IN'): string {
    const pc = postalCode === null ? 'NULL' : `'${postalCode}'`;
    return `INSERT INTO public.marketplace_items
      (id, seller_id, title, description, price, currency, category, condition,
       location_name, location_geo, jurisdiction_code, available_quantity, ship_eligible, status, postal_code)
    VALUES
      ('${id}', '${sellerId}', 'Test Item', 'Test', 100.00, '${currency}',
       'Electronics', 'GOOD', 'Mumbai',
       ST_SetSRID(ST_MakePoint(72.8777, 19.0760), 4326)::geography,
       '${jurisdiction}', 1, ${shipEligible}, 'LISTED', ${pc})`;
  }

  async function expectSuccess(label: string, sql: string): Promise<void> {
    await db.exec(sql);
    console.log(`  ✓ ${label}: INSERT succeeded (expected)`);
  }

  async function expectReject(label: string, sql: string): Promise<void> {
    try {
      await db.exec(sql);
      assert.fail(`${label}: INSERT should have been rejected by DB constraint, but succeeded`);
    } catch (e: unknown) {
      const msg = (e as Error).message ?? String(e);
      // Constraint violations surface as check_violation or similar
      if (!msg.includes('violates check constraint') && !msg.includes('check constraint')) {
        // Re-throw unexpected errors
        throw e;
      }
      console.log(`  ✓ ${label}: INSERT correctly rejected by DB (${msg.slice(0, 80)}...)`);
    }
  }

  // A. ship_eligible=true, postal 560001 → SUCCESS
  await expectSuccess(
    'A: ship_eligible=true + postal 560001',
    mkItem('f0000001-0000-0000-0000-000000000001', true, '560001'),
  );

  // B. ship_eligible=true, postal NULL → REJECTED
  await expectReject(
    'B: ship_eligible=true + postal NULL',
    mkItem('f0000002-0000-0000-0000-000000000002', true, null),
  );

  // C. ship_eligible=true, postal 012345 (leading zero) → REJECTED
  await expectReject(
    'C: ship_eligible=true + postal 012345 (leading zero)',
    mkItem('f0000003-0000-0000-0000-000000000003', true, '012345'),
  );

  // D. ship_eligible=true, postal 56000A (alphanumeric) → REJECTED
  await expectReject(
    'D: ship_eligible=true + postal 56000A (alphanumeric)',
    mkItem('f0000004-0000-0000-0000-000000000004', true, '56000A'),
  );

  // E. ship_eligible=false, postal NULL → SUCCESS
  await expectSuccess(
    'E: ship_eligible=false + postal NULL',
    mkItem('f0000005-0000-0000-0000-000000000005', false, null),
  );

  // F. ship_eligible=false, valid postal → SUCCESS (non-shipping listing with postal is fine)
  await expectSuccess(
    'F: ship_eligible=false + valid postal 400001',
    mkItem('f0000006-0000-0000-0000-000000000006', false, '400001'),
  );

  // G. UPDATE existing false→true while postal_code is NULL → REJECTED
  // First insert a non-shipping row (no postal), then try to flip ship_eligible
  await db.exec(mkItem('f0000007-0000-0000-0000-000000000007', false, null));
  await expectReject(
    'G: UPDATE ship_eligible false→true while postal_code=NULL',
    `UPDATE public.marketplace_items
     SET ship_eligible = true
     WHERE id = 'f0000007-0000-0000-0000-000000000007'`,
  );

  console.log('  ✓ All DB postal-code invariant assertions A-G passed');
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function run(): Promise<void> {
  await testManifestIntegrity();

  const freshDb = await testFreshInstall();
  // Run postal invariant tests on the fresh install DB (has all constraints)
  await testPostalInvariantsDirect(freshDb);
  await freshDb.close();

  await testUpgradeFrom012();

  console.log('\n🎉 ALL MIGRATION ORDER + POSTAL INVARIANT TESTS PASSED!\n');
}

run().catch(err => {
  console.error('\n❌ MIGRATION ORDER SUITE FAILED:', err);
  process.exit(1);
});
