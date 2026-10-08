-- Migration 013: Release closeout hardening
-- Fixes:
--   A. References shipment_tasks.currency (not declared_currency)
--   B. Uses canonical India PIN regex ^[1-9][0-9]{5}$ (no leading zeros)
--   C. Adds ship_eligible→postal_code invariant on marketplace_items
--
-- Strategy:
--   All constraints use NOT VALID so existing historical rows are not
--   scanned at migration time. Only new/updated rows are enforced.
--   This is safe for legacy QAR/QA rows and NULL postal_code rows.
--
-- This migration is ADDITIVE ONLY. It does not DROP, TRUNCATE,
-- or backfill any existing data.

-- ─── 1. marketplace_items: canonical India PIN format ─────────────────────────
-- Replaces any prior incorrect ^\\d{6}$ constraint first.

do $$
begin
  -- Drop old (incorrect leading-zero-permitting) constraint if it slipped in
  if exists (
    select 1
    from   pg_constraint
    where  conname = 'marketplace_items_postal_code_format'
    and    conrelid = 'public.marketplace_items'::regclass
  ) then
    alter table public.marketplace_items
      drop constraint marketplace_items_postal_code_format;
  end if;
end;
$$;

-- Add correct constraint: NULL allowed (non-shipping items), non-NULL must be
-- a canonical India PIN (first digit 1-9, then exactly 5 more digits).
alter table public.marketplace_items
  add constraint marketplace_items_postal_code_format
  check (postal_code is null or postal_code ~ '^[1-9][0-9]{5}$')
  not valid;

-- ─── 2. marketplace_items: ship_eligible requires valid postal_code ────────────
-- Invariant: NOT ship_eligible OR (postal_code IS NOT NULL AND postal_code ~ '^[1-9][0-9]{5}$')
-- This closes the DB-level bypass: even a direct INSERT cannot set
-- ship_eligible=true with a NULL or malformed postal_code.

do $$
begin
  if exists (
    select 1
    from   pg_constraint
    where  conname = 'marketplace_items_ship_eligible_requires_postal'
    and    conrelid = 'public.marketplace_items'::regclass
  ) then
    alter table public.marketplace_items
      drop constraint marketplace_items_ship_eligible_requires_postal;
  end if;
end;
$$;

alter table public.marketplace_items
  add constraint marketplace_items_ship_eligible_requires_postal
  check (
    not ship_eligible
    or (postal_code is not null and postal_code ~ '^[1-9][0-9]{5}$')
  )
  not valid;

-- ─── 3. shipment_tasks: sender/receiver postal code columns ───────────────────
alter table public.shipment_tasks
  add column if not exists sender_postal_code   text,
  add column if not exists receiver_postal_code text;

-- Drop incorrect ^\\d{6}$ constraints if they were previously added
do $$
begin
  if exists (
    select 1
    from   pg_constraint
    where  conname = 'shipment_tasks_sender_postal_code_format'
    and    conrelid = 'public.shipment_tasks'::regclass
  ) then
    alter table public.shipment_tasks
      drop constraint shipment_tasks_sender_postal_code_format;
  end if;

  if exists (
    select 1
    from   pg_constraint
    where  conname = 'shipment_tasks_receiver_postal_code_format'
    and    conrelid = 'public.shipment_tasks'::regclass
  ) then
    alter table public.shipment_tasks
      drop constraint shipment_tasks_receiver_postal_code_format;
  end if;
end;
$$;

alter table public.shipment_tasks
  add constraint shipment_tasks_sender_postal_code_format
  check (sender_postal_code is null or sender_postal_code ~ '^[1-9][0-9]{5}$')
  not valid;

alter table public.shipment_tasks
  add constraint shipment_tasks_receiver_postal_code_format
  check (receiver_postal_code is null or receiver_postal_code ~ '^[1-9][0-9]{5}$')
  not valid;

-- ─── 4. trip_routes: currency must be valid 3-letter ISO code ─────────────────
do $$
begin
  if exists (
    select 1
    from   pg_constraint
    where  conname = 'trip_routes_currency_iso_format'
    and    conrelid = 'public.trip_routes'::regclass
  ) then
    alter table public.trip_routes
      drop constraint trip_routes_currency_iso_format;
  end if;
end;
$$;

alter table public.trip_routes
  add constraint trip_routes_currency_iso_format
  check (currency ~ '^[A-Z]{3}$')
  not valid;

-- ─── 5. marketplace_items: currency must be valid 3-letter ISO code ───────────
do $$
begin
  if exists (
    select 1
    from   pg_constraint
    where  conname = 'marketplace_items_currency_iso_format'
    and    conrelid = 'public.marketplace_items'::regclass
  ) then
    alter table public.marketplace_items
      drop constraint marketplace_items_currency_iso_format;
  end if;
end;
$$;

alter table public.marketplace_items
  add constraint marketplace_items_currency_iso_format
  check (currency ~ '^[A-Z]{3}$')
  not valid;

-- ─── 6. shipment_tasks: currency (NOT declared_currency) ISO format ───────────
-- The column is `currency char(3)` as defined in 001_shipdehop.sql.
-- The erroneous reference to `declared_currency` is intentionally absent here.
do $$
begin
  if exists (
    select 1
    from   pg_constraint
    where  conname = 'shipment_tasks_currency_iso_format'
    and    conrelid = 'public.shipment_tasks'::regclass
  ) then
    alter table public.shipment_tasks
      drop constraint shipment_tasks_currency_iso_format;
  end if;
end;
$$;

alter table public.shipment_tasks
  add constraint shipment_tasks_currency_iso_format
  check (currency ~ '^[A-Z]{3}$')
  not valid;
