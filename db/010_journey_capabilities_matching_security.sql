-- Migration 010: Journey Capabilities, Ride & Shipment Matching Security, and Spatial Location Feeds

-- 1. Add capability columns to trip_routes idempotently
alter table public.trip_routes
  add column if not exists accepts_passengers boolean not null default true,
  add column if not exists accepts_shopping_requests boolean not null default false;

-- 2. Update check constraints on seat_capacity and available_seats to support zero passengers
do $$
begin
  -- Drop existing seat capacity constraints if present
  alter table public.trip_routes drop constraint if exists trip_routes_seat_capacity_check;
  alter table public.trip_routes drop constraint if exists chk_trip_routes_seat_capacity;

  -- Add updated check constraint allowing 0 to 8 seats
  if not exists (select 1 from pg_constraint where conname = 'chk_trip_routes_seat_capacity_0_8') then
    alter table public.trip_routes add constraint chk_trip_routes_seat_capacity_0_8 check (seat_capacity between 0 and 8);
  end if;

  -- Drop existing available seats constraints if present
  alter table public.trip_routes drop constraint if exists trip_routes_available_seats_check;
  alter table public.trip_routes drop constraint if exists chk_trip_routes_available_seats;

  if not exists (select 1 from pg_constraint where conname = 'chk_trip_routes_avail_seats_0_8') then
    alter table public.trip_routes add constraint chk_trip_routes_avail_seats_0_8 check (available_seats between 0 and 8);
  end if;
end $$;

-- Helper function to map parcel_capacity_tier to unit max
create or replace function public.parcel_tier_max_units(p_tier public.parcel_capacity_tier)
returns integer
language sql
immutable
as $$
  select case p_tier
    when 'NONE' then 0
    when 'ENVELOPE' then 2
    when 'MEDIUM' then 6
    when 'LUGGAGE' then 12
    else 0
  end;
$$;

-- 3. Update create_trip_route RPC to support zero seats, capabilities, and estimated trip cost validation
drop function if exists public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean);
drop function if exists public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean,boolean,boolean);

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

  if p_estimated_trip_cost <= 0 then
    raise exception 'estimated_trip_cost must be positive';
  end if;

  -- Ensure at least one capability is enabled
  if not v_accepts_passengers and p_parcel_capacity_tier = 'NONE' and not p_accepts_shopping_requests then
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
    p_accepts_shopping_requests
  )
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean,boolean,boolean) from public, anon;
grant execute on function public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean,boolean,boolean) to authenticated, service_role;


-- 4. Update match_ride_requests_along_route with ownership guard and full coordinates
drop function if exists public.match_ride_requests_along_route(uuid, integer);

create or replace function public.match_ride_requests_along_route(
  p_trip_id uuid,
  p_max_detour_meters int default 5000
)
returns table (
  request_id uuid,
  requester_id uuid,
  requester_name text,
  pickup_name text,
  pickup_lat double precision,
  pickup_lon double precision,
  drop_name text,
  drop_lat double precision,
  drop_lon double precision,
  earliest_departure timestamptz,
  latest_departure timestamptz,
  seats_needed smallint,
  offered_contribution_per_seat numeric,
  currency char(3),
  jurisdiction_code text,
  status public.ride_request_status,
  pickup_distance_m double precision,
  drop_distance_m double precision,
  pickup_route_fraction double precision,
  drop_route_fraction double precision
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

  if p_max_detour_meters <= 0 or p_max_detour_meters > 50000 then
    raise exception 'p_max_detour_meters must be between 1 and 50000';
  end if;

  return query
  with route as (
    select t.route_polyline, t.available_seats, t.departure_time, t.currency, t.jurisdiction_code, t.price_per_seat
    from public.trip_routes t
    where t.id = p_trip_id
      and t.status in ('SCHEDULED','IN_PROGRESS')
      and t.accepts_passengers = true
      and t.available_seats > 0
  ), candidates as (
    select
      r.*,
      rt.price_per_seat as offered_contribution_per_seat,
      ST_Distance(r.pickup_geo, rt.route_polyline) as pickup_m,
      ST_Distance(r.drop_geo, rt.route_polyline) as drop_m,
      ST_LineLocatePoint(rt.route_polyline::geometry, r.pickup_geo::geometry) as pickup_frac,
      ST_LineLocatePoint(rt.route_polyline::geometry, r.drop_geo::geometry) as drop_frac,
      coalesce(u.full_name, 'Verified Passenger') as display_name
    from public.ride_requests r
    cross join route rt
    left join public.users u on u.id = r.requester_id
    where r.status = 'OPEN'
      and r.latest_departure >= now()
      and r.seats_needed <= rt.available_seats
      and r.jurisdiction_code = rt.jurisdiction_code
      and r.currency = rt.currency
      and r.earliest_departure <= rt.departure_time
      and r.latest_departure >= rt.departure_time
  )
  select
    c.id as request_id,
    c.requester_id,
    c.display_name as requester_name,
    c.pickup_name,
    ST_Y(c.pickup_geo::geometry) as pickup_lat,
    ST_X(c.pickup_geo::geometry) as pickup_lon,
    c.drop_name,
    ST_Y(c.drop_geo::geometry) as drop_lat,
    ST_X(c.drop_geo::geometry) as drop_lon,
    c.earliest_departure,
    c.latest_departure,
    c.seats_needed,
    c.offered_contribution_per_seat,
    c.currency,
    c.jurisdiction_code,
    c.status,
    c.pickup_m as pickup_distance_m,
    c.drop_m as drop_distance_m,
    c.pickup_frac as pickup_route_fraction,
    c.drop_frac as drop_route_fraction
  from candidates c
  where c.pickup_m <= p_max_detour_meters
    and c.drop_m <= p_max_detour_meters
    and c.pickup_frac <= c.drop_frac
  order by (c.pickup_m + c.drop_m) asc;
end;
$$;

revoke execute on function public.match_ride_requests_along_route(uuid,int) from public, anon;
grant execute on function public.match_ride_requests_along_route(uuid,int) to authenticated, service_role;


-- 5. Update match_shipments_along_route with ownership guard and full coordinates
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
    select t.route_polyline, t.parcel_capacity_tier, t.parcel_capacity_units_available, t.currency, t.jurisdiction_code, t.accepts_shopping_requests
    from public.trip_routes t
    where t.id = p_trip_id
      and t.status = 'SCHEDULED'
      and (t.parcel_capacity_tier <> 'NONE' or t.accepts_shopping_requests = true)
      and t.parcel_capacity_units_available > 0
  ), candidates as (
    select
      s.*,
      ST_Distance(s.pickup_geo, rt.route_polyline) as pickup_dist,
      ST_Distance(s.drop_geo, rt.route_polyline) as drop_dist,
      ST_LineLocatePoint(rt.route_polyline::geometry, s.pickup_geo::geometry) as pickup_frac,
      ST_LineLocatePoint(rt.route_polyline::geometry, s.drop_geo::geometry) as drop_frac,
      coalesce(u.full_name, 'Verified Sender') as display_name,
      rt.accepts_shopping_requests as trip_accepts_shopping
    from public.shipment_tasks s
    cross join route rt
    left join public.users u on u.id = s.sender_id
    where s.status = 'OPEN'
      and s.inspection_status = 'APPROVED'
      and s.currency = rt.currency
      and (
        (s.item_type <> 'URL_PURCHASE' and rt.parcel_capacity_tier <> 'NONE')
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


-- 6. Spatial Location Feed RPCs
create or replace function public.list_nearby_marketplace_items(
  p_lon double precision,
  p_lat double precision,
  p_radius_meters double precision default 50000,
  p_limit int default 50
)
returns setof public.marketplace_items
language sql
stable
security definer
set search_path = public, gis, extensions
as $$
  select *
  from public.marketplace_items
  where status = 'LISTED'
    and available_quantity > 0
    and currency = 'INR'
    and (jurisdiction_code = 'IN' or jurisdiction_code like 'IN_%')
    and ST_DWithin(
          location_geo,
          ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
          p_radius_meters
        )
  order by ST_Distance(location_geo, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography) asc
  limit p_limit;
$$;

revoke execute on function public.list_nearby_marketplace_items(double precision, double precision, double precision, int) from public, anon;
grant execute on function public.list_nearby_marketplace_items(double precision, double precision, double precision, int) to authenticated, service_role;

create or replace function public.list_nearby_open_shipments(
  p_lon double precision,
  p_lat double precision,
  p_radius_meters double precision default 50000,
  p_limit int default 50
)
returns setof public.shipment_tasks
language sql
stable
security definer
set search_path = public, gis, extensions
as $$
  select *
  from public.shipment_tasks
  where status = 'OPEN'
    and inspection_status = 'APPROVED'
    and currency = 'INR'
    and (
      ST_DWithin(pickup_geo, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography, p_radius_meters)
      or ST_DWithin(drop_geo, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography, p_radius_meters)
    )
  order by ST_Distance(pickup_geo, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography) asc
  limit p_limit;
$$;

revoke execute on function public.list_nearby_open_shipments(double precision, double precision, double precision, int) from public, anon;
grant execute on function public.list_nearby_open_shipments(double precision, double precision, double precision, int) to authenticated, service_role;
