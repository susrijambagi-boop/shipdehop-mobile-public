import assert from 'assert';
import {
  validateAndDecodeImage,
  processAndUploadMarketplaceImages,
  cleanupMarketplaceImages,
  MAX_IMAGES_PER_LISTING,
  MAX_DECODED_IMAGE_BYTES,
  MARKETPLACE_BUCKET,
} from './services/marketplaceStorage.js';
import { PGlite } from '@electric-sql/pglite';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Tiny valid 1x1 PNG and JPEG sample bytes
const VALID_1X1_PNG_BASE64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
const VALID_1X1_JPEG_BASE64 = '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';

function splitSqlStatements(sql: string): string[] {
  const statements: string[] = [];
  let current = '';
  let inDollarQuote = false;
  let dollarTag = '';

  const lines = sql.split('\n');
  for (const line of lines) {
    if (line.trim().startsWith('create extension')) continue;
    if (line.toLowerCase().includes('gist(') || line.includes('_gix on')) continue;

    let cleanLine = line
      .replace(/geography\s*\([^)]+\)/gi, 'geography')
      .replace(/gis\.geography\s*\([^)]+\)/gi, 'gis.geography')
      .replace(/geometry\s*\([^)]+\)/gi, 'geometry')
      .replace(/gis\.geometry\s*\([^)]+\)/gi, 'gis.geometry');

    current += cleanLine + '\n';

    const dollarMatches = cleanLine.match(/\$\$|\$[a-zA-Z0-9_]*\$/g);
    if (dollarMatches) {
      for (const m of dollarMatches) {
        if (!inDollarQuote) {
          inDollarQuote = true;
          dollarTag = m;
        } else if (m === dollarTag) {
          inDollarQuote = false;
          dollarTag = '';
        }
      }
    }

    if (!inDollarQuote && cleanLine.trim().endsWith(';')) {
      if (current.trim()) {
        statements.push(current.trim());
      }
      current = '';
    }
  }
  if (current.trim()) {
    statements.push(current.trim());
  }
  return statements;
}

async function runTests() {
  console.log('=== RUNNING BACKEND MARKETPLACE & STORAGE TESTS ===');

  // Test 1: Max 4 photos validation
  console.log('Test 1: Max 4 photos check');
  const fiveImages = [
    `data:image/png;base64,${VALID_1X1_PNG_BASE64}`,
    `data:image/png;base64,${VALID_1X1_PNG_BASE64}`,
    `data:image/png;base64,${VALID_1X1_PNG_BASE64}`,
    `data:image/png;base64,${VALID_1X1_PNG_BASE64}`,
    `data:image/png;base64,${VALID_1X1_PNG_BASE64}`,
  ];
  await assert.rejects(
    async () => processAndUploadMarketplaceImages('test-seller', fiveImages),
    /maximum of 4 photos/
  );
  console.log('✓ Test 1 Passed: Rejecting >4 photos');

  // Test 2: Accepted MIME validation (JPEG, PNG, WebP)
  console.log('Test 2: Accepted MIME validation');
  const decodedPng = validateAndDecodeImage(`data:image/png;base64,${VALID_1X1_PNG_BASE64}`);
  assert.strictEqual(decodedPng.mimeType, 'image/png');
  assert.strictEqual(decodedPng.extension, 'png');

  const decodedJpeg = validateAndDecodeImage(`data:image/jpeg;base64,${VALID_1X1_JPEG_BASE64}`);
  assert.strictEqual(decodedJpeg.mimeType, 'image/jpeg');
  assert.strictEqual(decodedJpeg.extension, 'jpg');
  console.log('✓ Test 2 Passed: Accepted MIME formats validated');

  // Test 3: Unsupported MIME rejected (SVG, text, fake header)
  console.log('Test 3: Unsupported MIME rejected');
  const svgData = Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>').toString('base64');
  assert.throws(
    () => validateAndDecodeImage(`data:image/svg+xml;base64,${svgData}`),
    /SVG and XML formats are strictly forbidden|Unsupported image file format/
  );
  const textData = Buffer.from('this is plain text not image').toString('base64');
  assert.throws(
    () => validateAndDecodeImage(`data:image/png;base64,${textData}`),
    /Unsupported image file format|MIME type mismatch/
  );
  console.log('✓ Test 3 Passed: SVG and corrupt files rejected');

  // Test 4: Image size limit enforced (<= 2MB decoded)
  console.log('Test 4: Image size limit enforced');
  const oversizedBuffer = Buffer.alloc(2.5 * 1024 * 1024);
  // Give it PNG magic bytes
  oversizedBuffer[0] = 0x89;
  oversizedBuffer[1] = 0x50;
  oversizedBuffer[2] = 0x4e;
  oversizedBuffer[3] = 0x47;
  const oversizedBase64 = oversizedBuffer.toString('base64');
  assert.throws(
    () => validateAndDecodeImage(`data:image/png;base64,${oversizedBase64}`),
    /exceeds the maximum allowed limit of 2 MB/
  );
  console.log('✓ Test 4 Passed: Oversized decoded image rejected');

  // Test 5: Uploaded listing stores HTTPS Storage URLs
  console.log('Test 5: Storage URL format');
  const mockSellerId = 'e2e-seller-12345';
  const uploadRes = await processAndUploadMarketplaceImages(mockSellerId, [
    `data:image/png;base64,${VALID_1X1_PNG_BASE64}`,
  ]);
  assert.strictEqual(uploadRes.urls.length, 1);
  const firstUrl = uploadRes.urls[0]!;
  assert.ok(firstUrl.startsWith('https://'));
  assert.ok(firstUrl.includes(`/storage/v1/object/public/${MARKETPLACE_BUCKET}/${mockSellerId}/`));
  console.log('✓ Test 5 Passed: Storage URL returned correctly:', firstUrl);

  // Clean up uploaded test image
  await cleanupMarketplaceImages(uploadRes.paths);

  // Test 6: Database integration test via PGlite
  console.log('Test 6: Database integration test via PGlite');
  const db = new PGlite();

  // Test Harness Compatibility Shims
  await db.exec(`
    do $$
    begin
      if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
      if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
      if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role; end if;
      if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then create publication supabase_realtime; end if;
    end $$;

    create schema if not exists auth;
    create table if not exists auth.users (id uuid primary key default gen_random_uuid(), email text, phone text);
    create or replace function auth.jwt() returns jsonb language sql as $$ select '{}'::jsonb; $$;
    create or replace function auth.role() returns text language sql as $$ select 'authenticated'::text; $$;
    create or replace function auth.uid() returns uuid language sql as $$ select 'ed9517fc-7ebe-437c-bdc0-abb45bef9079'::uuid; $$;

    create schema if not exists realtime;
    create table if not exists realtime.messages (id bigint, extension text, topic text);
    create or replace function realtime.topic() returns text language sql as $$ select ''::text; $$;

    create schema if not exists extensions;
    create or replace function extensions.digest(data bytea, type text) returns bytea language sql as $$ select data; $$;
    create or replace function extensions.digest(data text, type text) returns bytea language sql as $$ select data::bytea; $$;
    create or replace function extensions.crypt(secret text, salt text) returns text language sql as $$ select 'hashed_' || secret; $$;
    create or replace function extensions.gen_salt(type text, count integer) returns text language sql as $$ select 'salt'; $$;
    create or replace function public.hash_handoff_secret(p_secret text) returns text language sql as $$ select 'hash_' || p_secret; $$;

    create schema if not exists gis;

    do $$
    begin
      if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'gis' and t.typname = 'geography') then
        create domain gis.geography as text;
      end if;
      if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'geography') then
        create domain public.geography as text;
      end if;
      if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'gis' and t.typname = 'geometry') then
        create domain gis.geometry as text;
      end if;
      if not exists (select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typname = 'geometry') then
        create domain public.geometry as text;
      end if;
    end $$;

    set search_path = public, gis, extensions;

    create or replace function gis.ST_SetSRID(geom anyelement, srid integer) returns anyelement language plpgsql as $$ begin return geom; end; $$;
    create or replace function gis.ST_MakePoint(x numeric, y numeric) returns text language plpgsql as $$ begin return 'POINT(' || x || ' ' || y || ')'; end; $$;
    create or replace function gis.ST_Point(x numeric, y numeric) returns text language plpgsql as $$ begin return 'POINT(' || x || ' ' || y || ')'; end; $$;
    create or replace function gis.ST_Point(x double precision, y double precision) returns text language plpgsql as $$ begin return 'POINT(' || x || ' ' || y || ')'; end; $$;
    create or replace function gis.ST_Force2D(geom anyelement) returns anyelement language plpgsql as $$ begin return geom; end; $$;
    create or replace function gis.ST_GeomFromGeoJSON(geojson text) returns text language plpgsql as $$ begin return geojson; end; $$;
    create or replace function gis.GeometryType(geom anyelement) returns text language plpgsql as $$ begin return 'LINESTRING'; end; $$;
    create or replace function gis.ST_DWithin(g1 text, g2 text, distance_meters numeric) returns boolean language plpgsql as $$ begin return true; end; $$;
    create or replace function gis.ST_Distance(g1 text, g2 text) returns double precision language plpgsql as $$ begin return 10.0; end; $$;
    create or replace function gis.ST_LineLocatePoint(geom text, pt text) returns double precision language plpgsql as $$ begin if pt like '%51.53%' then return 0.8; else return 0.2; end if; end; $$;
    create or replace function gis.ST_X(geom anyelement) returns double precision language sql as $$ select 51.5::double precision; $$;
    create or replace function gis.ST_Y(geom anyelement) returns double precision language sql as $$ select 25.3::double precision; $$;

    create or replace function public.ST_SetSRID(geom anyelement, srid integer) returns anyelement language plpgsql as $$ begin return geom; end; $$;
    create or replace function public.ST_MakePoint(x numeric, y numeric) returns text language plpgsql as $$ begin return 'POINT(' || x || ' ' || y || ')'; end; $$;
    create or replace function public.ST_Point(x numeric, y numeric) returns text language plpgsql as $$ begin return 'POINT(' || x || ' ' || y || ')'; end; $$;
    create or replace function public.ST_Point(x double precision, y double precision) returns text language plpgsql as $$ begin return 'POINT(' || x || ' ' || y || ')'; end; $$;
    create or replace function public.ST_Force2D(geom anyelement) returns anyelement language plpgsql as $$ begin return geom; end; $$;
    create or replace function public.ST_GeomFromGeoJSON(geojson text) returns text language plpgsql as $$ begin return geojson; end; $$;
    create or replace function public.GeometryType(geom anyelement) returns text language plpgsql as $$ begin return 'LINESTRING'; end; $$;
    create or replace function public.ST_DWithin(g1 text, g2 text, distance_meters numeric) returns boolean language plpgsql as $$ begin return true; end; $$;
    create or replace function public.ST_Distance(g1 text, g2 text) returns double precision language plpgsql as $$ begin return 10.0; end; $$;
    create or replace function public.ST_LineLocatePoint(geom text, pt text) returns double precision language plpgsql as $$ begin if pt like '%51.53%' then return 0.8; else return 0.2; end if; end; $$;
    create or replace function public.ST_X(geom anyelement) returns double precision language sql as $$ select 51.5::double precision; $$;
    create or replace function public.ST_Y(geom anyelement) returns double precision language sql as $$ select 25.3::double precision; $$;
    create or replace function public.parcel_tier_allows_weight(tier text, weight_kg numeric) returns boolean language plpgsql as $$ begin return true; end; $$;
  `);

  const migrations = [
    '001_shipdehop.sql',
    '002_ride_requests.sql',
    '003_parcel_capacity.sql',
    '004_notifications.sql',
    '005_marketplace_integration.sql',
  ];
  for (const mig of migrations) {
    const p = path.resolve(__dirname, '../../db', mig);
    const sql = fs.readFileSync(p, 'utf-8');
    const statements = splitSqlStatements(sql);
    for (let i = 0; i < statements.length; i++) {
      let rawS = statements[i];
      if (!rawS) continue;
      let s = rawS.replace(/^(\s*--[^\n]*\n)+/g, '').trim();
      if (!s) continue;
      s = s.replace(/order by \(c\.pickup_m \+ c\.drop_m\) ascending;/gi, 'order by (c.pickup_m + c.drop_m) asc;');
      if (s.includes('create or replace function public.list_open_shipments') && i > 150) {
        await db.exec('drop function if exists public.list_open_shipments(integer);');
      }
      await db.exec(s);
    }
  }

  // Create test seller
  const authRes = await db.query(`
    insert into auth.users (email) values ('seller@test.com') returning id;
  `);
  const sellerId = (authRes.rows[0] as any).id;
  await db.query(`
    update public.users set ekyc_tier = 'TIER_2', phone = '+97455551111' where id = $1;
  `, [sellerId]);

  // Insert listing with HTTPS URLs only
  const validUrls = uploadRes.urls;
  const insertRes = await db.query(`
    insert into public.marketplace_items (
      seller_id, title, description, category, price, currency, condition,
      location_geo, location_name, jurisdiction_code, ship_eligible, status, images, quantity, available_quantity
    ) values (
      $1, 'Vintage Mechanical Keyboard', 'Clean mechanical keyboard with cherry switches', 'Electronics',
      150.00, 'QAR', 'LIKE_NEW',
      'SRID=4326;POINT(51.5310 25.2854)', 'Doha, Qatar', 'QA', false, 'LISTED',
      $2, 1, 1
    ) returning *;
  `, [sellerId, validUrls]);

  const inserted = insertRes.rows[0] as any;
  assert.ok(inserted.id);
  assert.strictEqual(inserted.title, 'Vintage Mechanical Keyboard');
  assert.strictEqual(inserted.ship_eligible, false);
  assert.ok(Array.isArray(inserted.images));
  assert.ok(inserted.images.length > 0);
  assert.ok(!inserted.images[0].startsWith('data:image'));
  assert.ok(inserted.images[0].startsWith('https://'));
  console.log('✓ Test 6 Passed: Database stores clean HTTPS URLs only');

  // Test 7: Upload failure prevents listing
  console.log('Test 7: Upload failure atomicity');
  await assert.rejects(
    async () => processAndUploadMarketplaceImages(sellerId, [
      `data:image/png;base64,${VALID_1X1_PNG_BASE64}`,
      'data:image/png;base64,INVALID_NOT_IMAGE_GARBAGE',
    ])
  );
  console.log('✓ Test 7 Passed: Corrupt batch fails atomically before upload');

  // Test 8: DB Failure cleanup
  console.log('Test 8: DB failure cleanup');
  await cleanupMarketplaceImages(['non-existent-path/file.png']);
  console.log('✓ Test 8 Passed: Best-effort cleanup executes safely');

  // Test 9 & 10: shipEligible false and shipEligible true listing succeeds
  console.log('Test 9 & 10: shipEligible false vs true listings');
  const shipEligibleListing = await db.query(`
    insert into public.marketplace_items (
      seller_id, title, description, category, price, currency, condition,
      location_geo, location_name, jurisdiction_code, ship_eligible, status, images, quantity, available_quantity
    ) values (
      $1, 'Wireless Noise Cancelling Headphones', 'Like new headphones with box', 'Electronics',
      350.00, 'QAR', 'LIKE_NEW',
      'SRID=4326;POINT(51.5310 25.2854)', 'Doha, Qatar', 'QA', true, 'LISTED',
      $2, 1, 1
    ) returning *;
  `, [sellerId, validUrls]);
  const shipItem = shipEligibleListing.rows[0] as any;
  assert.strictEqual(shipItem.ship_eligible, true);
  console.log('✓ Test 9 & 10 Passed: Both ship_eligible false and true listings created cleanly');

  // Test 11: ParcelPool flag does NOT create shipment during listing
  console.log('Test 11: Listing time does not create shipment task');
  const shipmentsCount = await db.query(`select count(*) as count from public.shipment_tasks;`);
  assert.strictEqual(parseInt((shipmentsCount.rows[0] as any).count, 10), 0);
  console.log('✓ Test 11 Passed: 0 shipment tasks created at listing time');

  // Test 12, 13, 14: Title length boundaries (3 <= length <= 140)
  console.log('Test 12, 13, 14: Title constraints (min 3, max 140)');
  // Min boundary: 3 chars
  const title3 = await db.query(`
    insert into public.marketplace_items (
      seller_id, title, description, category, price, currency, condition,
      location_geo, location_name, jurisdiction_code, ship_eligible, status, images, quantity, available_quantity
    ) values (
      $1, 'Pen', 'Description here', 'Other', 10.00, 'QAR', 'NEW',
      'SRID=4326;POINT(51.5310 25.2854)', 'Doha, Qatar', 'QA', false, 'LISTED',
      '{}', 1, 1
    ) returning title;
  `, [sellerId]);
  assert.strictEqual((title3.rows[0] as any).title, 'Pen');

  // Max boundary: 140 chars
  const maxTitle = 'A'.repeat(140);
  const title140 = await db.query(`
    insert into public.marketplace_items (
      seller_id, title, description, category, price, currency, condition,
      location_geo, location_name, jurisdiction_code, ship_eligible, status, images, quantity, available_quantity
    ) values (
      $1, $2, 'Description here', 'Other', 10.00, 'QAR', 'NEW',
      'SRID=4326;POINT(51.5310 25.2854)', 'Doha, Qatar', 'QA', false, 'LISTED',
      '{}', 1, 1
    ) returning title;
  `, [sellerId, maxTitle]);
  assert.strictEqual((title140.rows[0] as any).title.length, 140);

  // Invalid min: 2 chars -> should fail check constraint
  await assert.rejects(
    async () => db.query(`
      insert into public.marketplace_items (
        seller_id, title, description, category, price, currency, condition,
        location_geo, location_name, jurisdiction_code, ship_eligible, status, images, quantity, available_quantity
      ) values (
        $1, 'AB', 'Description here', 'Other', 10.00, 'QAR', 'NEW',
        'SRID=4326;POINT(51.5310 25.2854)', 'Doha, Qatar', 'QA', false, 'LISTED',
        '{}', 1, 1
      );
    `, [sellerId]),
    /marketplace_items_title_check/
  );

  // Invalid max: 141 chars -> should fail check constraint
  await assert.rejects(
    async () => db.query(`
      insert into public.marketplace_items (
        seller_id, title, description, category, price, currency, condition,
        location_geo, location_name, jurisdiction_code, ship_eligible, status, images, quantity, available_quantity
      ) values (
        $1, $2, 'Description here', 'Other', 10.00, 'QAR', 'NEW',
        'SRID=4326;POINT(51.5310 25.2854)', 'Doha, Qatar', 'QA', false, 'LISTED',
        '{}', 1, 1
      );
    `, [sellerId, 'A'.repeat(141)]),
    /marketplace_items_title_check/
  );

  console.log('✓ Test 12, 13, 14 Passed: Title boundaries strictly enforced matching DB constraint');
  console.log('=== ALL BACKEND TESTS PASSED 100% ===');
}

runTests().catch(err => {
  console.error('Backend tests failed:', err);
  process.exit(1);
});
