-- Migration 012: Additive release contract fixes, postal code storage, and RPC return column alignment

-- 1. Add postal_code column to marketplace_items idempotently
alter table public.marketplace_items
  add column if not exists postal_code text;

-- 2. Drop existing list_nearby_marketplace_items overload and re-create with exact Flutter MarketplaceCardModel columns
drop function if exists public.list_nearby_marketplace_items(double precision, double precision, double precision, int);

create or replace function public.list_nearby_marketplace_items(
  p_lon double precision,
  p_lat double precision,
  p_radius_meters double precision default 50000,
  p_limit int default 50
)
returns table (
  id uuid,
  seller_id uuid,
  title text,
  description text,
  price numeric,
  currency text,
  category text,
  condition text,
  location_name text,
  jurisdiction_code text,
  available_quantity int,
  ship_eligible boolean,
  images text[],
  pickup_lat double precision,
  pickup_lon double precision,
  distance_km double precision,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, gis, extensions
as $$
declare
  v_query_point geography;
begin
  if not public.is_coord_in_india(p_lat, p_lon) then
    raise exception 'Search location coordinates must be within India';
  end if;

  if p_radius_meters is null or p_radius_meters <= 0 or p_radius_meters > 50000 then
    raise exception 'p_radius_meters must be > 0 and <= 50000 (50 km)';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'p_limit must be between 1 and 100';
  end if;

  v_query_point := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;

  return query
  select
    m.id,
    m.seller_id,
    m.title::text as title,
    m.description::text as description,
    m.price,
    m.currency::text as currency,
    m.category::text as category,
    m.condition::text as condition,
    m.location_name::text as location_name,
    m.jurisdiction_code::text as jurisdiction_code,
    m.available_quantity,
    m.ship_eligible,
    m.images,
    ST_Y(m.location_geo::geometry) as pickup_lat,
    ST_X(m.location_geo::geometry) as pickup_lon,
    (ST_Distance(m.location_geo, v_query_point) / 1000.0) as distance_km,
    m.created_at
  from public.marketplace_items m
  where m.status = 'LISTED'
    and m.available_quantity > 0
    and m.currency = 'INR'
    and (m.jurisdiction_code = 'IN' or m.jurisdiction_code like 'IN_%')
    and ST_DWithin(m.location_geo, v_query_point, p_radius_meters)
  order by ST_Distance(m.location_geo, v_query_point) asc
  limit p_limit;
end;
$$;

revoke execute on function public.list_nearby_marketplace_items(double precision, double precision, double precision, int) from public, anon;
grant execute on function public.list_nearby_marketplace_items(double precision, double precision, double precision, int) to authenticated, service_role;


-- 3. Drop existing list_nearby_open_shipments overload and re-create with exact Flutter ShipmentCardModel columns
drop function if exists public.list_nearby_open_shipments(double precision, double precision, double precision, int);

create or replace function public.list_nearby_open_shipments(
  p_lon double precision,
  p_lat double precision,
  p_radius_meters double precision default 50000,
  p_limit int default 50
)
returns table (
  shipment_task_id uuid,
  item_type text,
  pickup_name text,
  drop_name text,
  weight_kg numeric,
  reward_amount numeric,
  currency text,
  parcel_size_tier public.parcel_capacity_tier,
  pickup_lat double precision,
  pickup_lon double precision,
  drop_lat double precision,
  drop_lon double precision,
  distance_km double precision,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, gis, extensions
as $$
declare
  v_query_point geography;
begin
  if not public.is_coord_in_india(p_lat, p_lon) then
    raise exception 'Search location coordinates must be within India';
  end if;

  if p_radius_meters is null or p_radius_meters <= 0 or p_radius_meters > 50000 then
    raise exception 'p_radius_meters must be > 0 and <= 50000 (50 km)';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'p_limit must be between 1 and 100';
  end if;

  v_query_point := ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography;

  return query
  select
    s.id as shipment_task_id,
    s.item_type::text as item_type,
    s.pickup_name::text as pickup_name,
    s.drop_name::text as drop_name,
    s.weight_kg,
    s.reward_amount,
    s.currency::text as currency,
    s.parcel_size_tier,
    ST_Y(s.pickup_geo::geometry) as pickup_lat,
    ST_X(s.pickup_geo::geometry) as pickup_lon,
    ST_Y(s.drop_geo::geometry) as drop_lat,
    ST_X(s.drop_geo::geometry) as drop_lon,
    (ST_Distance(s.pickup_geo, v_query_point) / 1000.0) as distance_km,
    s.created_at
  from public.shipment_tasks s
  where s.status = 'OPEN'
    and s.inspection_status = 'APPROVED'
    and s.currency = 'INR'
    and (
      ST_DWithin(s.pickup_geo, v_query_point, p_radius_meters)
      or ST_DWithin(s.drop_geo, v_query_point, p_radius_meters)
    )
  order by ST_Distance(s.pickup_geo, v_query_point) asc
  limit p_limit;
end;
$$;

revoke execute on function public.list_nearby_open_shipments(double precision, double precision, double precision, int) from public, anon;
grant execute on function public.list_nearby_open_shipments(double precision, double precision, double precision, int) to authenticated, service_role;
