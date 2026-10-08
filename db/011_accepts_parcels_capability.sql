-- Migration 011: Explicit accepts_parcels capability, shopping-only matching, and feed RPC input/privacy hardening

-- 1. Add accepts_parcels column to trip_routes idempotently
alter table public.trip_routes
  add column if not exists accepts_parcels boolean not null default true;

-- 2. Update create_trip_route RPC to support accepts_parcels parameter
drop function if exists public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean,boolean,boolean);
drop function if exists public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean,boolean,boolean,boolean);

create or replace function public.create_trip_route(
  p_origin_name text,
  p_origin_lon double precision,
  p_origin_lat double precision,
  p_dest_name text,
  p_dest_lon double precision,
  p_dest_lat double precision,
  p_route_geojson text,
  p_departure_time timestamptz,
  p_seat_capacity smallint,
  p_parcel_capacity_tier public.parcel_capacity_tier,
  p_price_per_seat numeric,
  p_estimated_trip_cost numeric,
  p_currency char(3),
  p_jurisdiction_code text,
  p_ladies_only boolean default false,
  p_accepts_passengers boolean default true,
  p_accepts_parcels boolean default true,
  p_accepts_shopping_requests boolean default false
)
returns public.trip_routes
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
declare
  v_driver_id uuid;
  v_route_geom geography;
  v_policy public.cost_sharing_policies;
  v_cap numeric;
  v_units integer;
  v_result public.trip_routes;
  v_accepts_passengers boolean;
  v_accepts_parcels boolean;
begin
  v_driver_id := auth.uid();
  if v_driver_id is null then
    raise exception 'Authentication required';
  end if;

  if p_seat_capacity < 0 or p_seat_capacity > 8 then
    raise exception 'seat_capacity must be between 0 and 8';
  end if;

  v_accepts_passengers := coalesce(p_accepts_passengers, p_seat_capacity > 0);
  if not v_accepts_passengers then
    p_seat_capacity := 0;
  end if;

  v_accepts_parcels := coalesce(p_accepts_parcels, p_parcel_capacity_tier <> 'NONE');
  if not v_accepts_parcels and not p_accepts_shopping_requests then
    p_parcel_capacity_tier := 'NONE';
  end if;

  if p_estimated_trip_cost <= 0 then
    raise exception 'estimated_trip_cost must be positive';
  end if;

  -- Ensure at least one capability is enabled
  if not v_accepts_passengers and not v_accepts_parcels and not p_accepts_shopping_requests then
    raise exception 'Trip route must offer at least one capability (passengers, parcels, or shopping)';
  end if;

  -- Load cost sharing policy (fail closed)
  select * into v_policy
  from public.cost_sharing_policies
  where jurisdiction_code = p_jurisdiction_code
    and enabled = true;

  if not found then
    raise exception 'No enabled cost sharing policy for jurisdiction %', p_jurisdiction_code;
  end if;

  if v_policy.currency <> p_currency then
    raise exception 'Currency mismatch with jurisdiction policy';
  end if;

  if v_accepts_passengers and p_seat_capacity > 0 then
    v_cap := (p_estimated_trip_cost / p_seat_capacity) * v_policy.max_recovery_ratio;
    if v_policy.hard_cap_per_seat is not null and v_policy.hard_cap_per_seat < v_cap then
      v_cap := v_policy.hard_cap_per_seat;
    end if;
    if p_price_per_seat > v_cap then
      raise exception 'price_per_seat exceeds cost share cap of %', v_cap;
    end if;
  else
    v_cap := 0;
    p_price_per_seat := 0;
  end if;

  v_route_geom := ST_SetSRID(ST_GeomFromGeoJSON(p_route_geojson), 4326)::geography;
  v_units := public.parcel_tier_max_units(p_parcel_capacity_tier);

  insert into public.trip_routes (
    driver_id,
    origin_name,
    origin_geo,
    dest_name,
    dest_geo,
    route_polyline,
    departure_time,
    seat_capacity,
    available_seats,
    parcel_capacity_tier,
    parcel_capacity_units_total,
    parcel_capacity_units_available,
    price_per_seat,
    estimated_trip_cost,
    cost_share_cap_per_seat,
    currency,
    jurisdiction_code,
    ladies_only,
    accepts_passengers,
    accepts_parcels,
    accepts_shopping_requests
  ) values (
    v_driver_id,
    p_origin_name,
    ST_SetSRID(ST_MakePoint(p_origin_lon, p_origin_lat), 4326)::geography,
    p_dest_name,
    ST_SetSRID(ST_MakePoint(p_dest_lon, p_dest_lat), 4326)::geography,
    v_route_geom,
    p_departure_time,
    p_seat_capacity,
    p_seat_capacity,
    p_parcel_capacity_tier,
    v_units,
    v_units,
    p_price_per_seat,
    p_estimated_trip_cost,
    v_cap,
    p_currency,
    p_jurisdiction_code,
    p_ladies_only,
    v_accepts_passengers,
    v_accepts_parcels,
    p_accepts_shopping_requests
  )
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean,boolean,boolean,boolean) from public, anon;
grant execute on function public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean,boolean,boolean,boolean) to authenticated, service_role;


-- 3. Update match_shipments_along_route with accepts_parcels distinction
drop function if exists public.match_shipments_along_route(uuid, integer);

create or replace function public.match_shipments_along_route(
  p_trip_id uuid,
  p_max_detour_meters integer default 5000
)
returns table (
  shipment_task_id uuid,
  item_type public.shipment_item_type,
  sender_id uuid,
  sender_name text,
  pickup_name text,
  pickup_lat double precision,
  pickup_lon double precision,
  drop_name text,
  drop_lat double precision,
  drop_lon double precision,
  weight_kg numeric,
  reward_amount numeric,
  declared_value numeric,
  currency char(3),
  required_parcel_units integer,
  pickup_distance_meters double precision,
  drop_distance_meters double precision
)
language plpgsql
stable
security definer
set search_path = public, gis, extensions
as $$
declare
  v_caller_id uuid;
  v_driver_id uuid;
  v_is_service_role boolean;
begin
  v_caller_id := auth.uid();
  v_is_service_role := (v_caller_id is null and current_setting('role', true) = 'service_role');

  -- Query target trip route
  select driver_id into v_driver_id
  from public.trip_routes
  where id = p_trip_id;

  if not found then
    raise exception 'Trip route not found';
  end if;

  -- Security Guard: Caller must be driver of the trip unless service role
  if not v_is_service_role and (v_caller_id is null or v_caller_id <> v_driver_id) then
    raise exception 'Access denied: caller does not own trip route';
  end if;

  if p_max_detour_meters < 1 or p_max_detour_meters > 50000 then
    raise exception 'Invalid detour limit';
  end if;

  return query
  with route as (
    select
      t.route_polyline,
      t.parcel_capacity_tier,
      t.parcel_capacity_units_available,
      t.currency,
      t.jurisdiction_code,
      t.accepts_parcels,
      t.accepts_shopping_requests
    from public.trip_routes t
    where t.id = p_trip_id
      and t.status = 'SCHEDULED'
      and (t.accepts_parcels = true or t.accepts_shopping_requests = true)
      and t.parcel_capacity_units_available > 0
  ), candidates as (
    select
      s.*,
      ST_Distance(s.pickup_geo, rt.route_polyline) as pickup_dist,
      ST_Distance(s.drop_geo, rt.route_polyline) as drop_dist,
      ST_LineLocatePoint(rt.route_polyline::geometry, s.pickup_geo::geometry) as pickup_frac,
      ST_LineLocatePoint(rt.route_polyline::geometry, s.drop_geo::geometry) as drop_frac,
      coalesce(u.full_name, 'Verified Sender') as display_name
    from public.shipment_tasks s
    cross join route rt
    left join public.users u on u.id = s.sender_id
    where s.status = 'OPEN'
      and s.inspection_status = 'APPROVED'
      and s.currency = rt.currency
      and (
        (s.item_type <> 'URL_PURCHASE' and rt.accepts_parcels = true)
        or (s.item_type = 'URL_PURCHASE' and rt.accepts_shopping_requests = true)
      )
      and s.parcel_capacity_units_required <= rt.parcel_capacity_units_available
      and public.parcel_tier_allows_weight(rt.parcel_capacity_tier, s.weight_kg)
  )
  select
    c.id, c.item_type, c.sender_id, c.display_name as sender_name,
    c.pickup_name,
    ST_Y(c.pickup_geo::geometry) as pickup_lat,
    ST_X(c.pickup_geo::geometry) as pickup_lon,
    c.drop_name,
    ST_Y(c.drop_geo::geometry) as drop_lat,
    ST_X(c.drop_geo::geometry) as drop_lon,
    c.weight_kg, c.reward_amount, c.declared_value, c.currency,
    c.parcel_capacity_units_required as required_parcel_units,
    c.pickup_dist, c.drop_dist
  from candidates c
  where c.pickup_dist <= p_max_detour_meters
    and c.drop_dist <= p_max_detour_meters
    and c.pickup_frac <= c.drop_frac
  order by (c.pickup_dist + c.drop_dist) asc;
end;
$$;

revoke execute on function public.match_shipments_along_route(uuid,int) from public, anon;
grant execute on function public.match_shipments_along_route(uuid,int) to authenticated, service_role;


-- 4. Spatial Location Feed RPCs Input & Privacy Hardening
drop function if exists public.list_nearby_marketplace_items(double precision, double precision, double precision, int);

create or replace function public.list_nearby_marketplace_items(
  p_lon double precision,
  p_lat double precision,
  p_radius_meters double precision default 50000,
  p_limit int default 50
)
returns table (
  id uuid,
  title text,
  description text,
  price_amount numeric,
  price_currency char(3),
  category text,
  pickup_locality text,
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
    m.title,
    m.description,
    m.price as price_amount,
    m.currency as price_currency,
    m.category,
    m.location_name as pickup_locality,
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


drop function if exists public.list_nearby_open_shipments(double precision, double precision, double precision, int);

create or replace function public.list_nearby_open_shipments(
  p_lon double precision,
  p_lat double precision,
  p_radius_meters double precision default 50000,
  p_limit int default 50
)
returns table (
  id uuid,
  title text,
  parcel_size_tier public.parcel_capacity_tier,
  reward_amount numeric,
  reward_currency char(3),
  pickup_name text,
  pickup_lat double precision,
  pickup_lon double precision,
  drop_name text,
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
    s.id,
    s.title,
    s.parcel_size_tier,
    s.reward_amount,
    s.currency as reward_currency,
    s.pickup_name,
    ST_Y(s.pickup_geo::geometry) as pickup_lat,
    ST_X(s.pickup_geo::geometry) as pickup_lon,
    s.drop_name,
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

