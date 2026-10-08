-- Phase 11: Additive migration for persistent Pooler ride requests and driver matching

do $$ begin
  create type public.ride_request_status as enum ('OPEN', 'MATCHED', 'RESERVED', 'CANCELLED', 'COMPLETED', 'EXPIRED');
exception
  when duplicate_object then null;
end $$;

create table if not exists public.ride_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id),
  pickup_name text not null,
  pickup_geo geography(Point, 4326) not null,
  drop_name text not null,
  drop_geo geography(Point, 4326) not null,
  earliest_departure timestamptz not null,
  latest_departure timestamptz not null,
  seats_needed smallint not null default 1 check (seats_needed between 1 and 8),
  currency char(3) not null,
  jurisdiction_code text not null,
  status public.ride_request_status not null default 'OPEN',
  matched_trip_id uuid references public.trip_routes(id),
  matched_order_id uuid references public.escrow_orders(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ride_requests_pickup_geo on public.ride_requests using gist(pickup_geo);
create index if not exists idx_ride_requests_drop_geo on public.ride_requests using gist(drop_geo);
create index if not exists idx_ride_requests_status on public.ride_requests(status);
create index if not exists idx_ride_requests_requester on public.ride_requests(requester_id);

alter table public.ride_requests enable row level security;

do $$ begin
  drop policy if exists ride_requests_requester_select on public.ride_requests;
  drop policy if exists ride_requests_requester_insert on public.ride_requests;
  drop policy if exists ride_requests_requester_update on public.ride_requests;
exception when others then null;
end $$;

create policy ride_requests_requester_select on public.ride_requests
  for select to authenticated
  using (requester_id = auth.uid() or status = 'OPEN');

create policy ride_requests_requester_insert on public.ride_requests
  for insert to authenticated
  with check (requester_id = auth.uid());

create policy ride_requests_requester_update on public.ride_requests
  for update to authenticated
  using (requester_id = auth.uid() and status = 'OPEN')
  with check (status in ('OPEN', 'CANCELLED'));

create or replace function public.create_ride_request(
  p_pickup_name text,
  p_pickup_lat double precision,
  p_pickup_lon double precision,
  p_drop_name text,
  p_drop_lat double precision,
  p_drop_lon double precision,
  p_earliest_departure timestamptz,
  p_latest_departure timestamptz,
  p_seats_needed smallint,
  p_currency char(3),
  p_jurisdiction_code text,
  p_requester_id uuid default null
)
returns public.ride_requests
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_req public.ride_requests;
  v_actor_id uuid := coalesce(p_requester_id, auth.uid());
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  if p_latest_departure < p_earliest_departure then
    raise exception 'Latest departure time must be after earliest departure time';
  end if;

  insert into public.ride_requests(
    requester_id, pickup_name, pickup_geo, drop_name, drop_geo,
    earliest_departure, latest_departure, seats_needed, currency, jurisdiction_code, status
  ) values (
    v_actor_id, p_pickup_name,
    ST_SetSRID(ST_MakePoint(p_pickup_lon, p_pickup_lat), 4326)::geography,
    p_drop_name,
    ST_SetSRID(ST_MakePoint(p_drop_lon, p_drop_lat), 4326)::geography,
    p_earliest_departure, p_latest_departure, p_seats_needed, p_currency, p_jurisdiction_code, 'OPEN'
  ) returning * into v_req;

  return v_req;
end;
$$;

create or replace function public.match_ride_requests_along_route(
  p_trip_id uuid,
  p_max_detour_meters int default 5000
)
returns table (
  request_id uuid,
  requester_id uuid,
  pickup_name text,
  drop_name text,
  earliest_departure timestamptz,
  latest_departure timestamptz,
  seats_needed smallint,
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
set search_path = public, extensions
as $$
begin
  if p_max_detour_meters <= 0 or p_max_detour_meters > 50000 then
    raise exception 'p_max_detour_meters must be between 1 and 50000';
  end if;

  return query
  with route as (
    select t.route_polyline, t.available_seats, t.departure_time, t.currency, t.jurisdiction_code
    from public.trip_routes t
    where t.id = p_trip_id
      and t.status in ('SCHEDULED','IN_PROGRESS')
      and t.available_seats > 0
  ), candidates as (
    select
      r.*,
      ST_Distance(r.pickup_geo, rt.route_polyline) as pickup_m,
      ST_Distance(r.drop_geo, rt.route_polyline) as drop_m,
      ST_LineLocatePoint(rt.route_polyline::geometry, r.pickup_geo::geometry) as pickup_frac,
      ST_LineLocatePoint(rt.route_polyline::geometry, r.drop_geo::geometry) as drop_frac,
      rt.available_seats as trip_avail_seats,
      rt.departure_time as trip_dept_time,
      rt.currency as trip_curr,
      rt.jurisdiction_code as trip_jurisdiction
    from public.ride_requests r
    cross join route rt
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
    c.pickup_name,
    c.drop_name,
    c.earliest_departure,
    c.latest_departure,
    c.seats_needed,
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
    and c.pickup_frac < c.drop_frac
  order by (c.pickup_m + c.drop_m) asc;
end;
$$;

create or replace function public.accept_ride_request_and_reserve_order(
  p_request_id uuid,
  p_trip_id uuid,
  p_platform_fee_bps integer default 1000
)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  req public.ride_requests;
  t public.trip_routes;
  v_base numeric(12,2);
  v_fee numeric(12,2);
  v_order public.escrow_orders;
  v_actor_id uuid := auth.uid();
begin
  if p_request_id is null or p_trip_id is null then
    raise exception 'Invalid request or trip parameters';
  end if;

  select * into req from public.ride_requests where id = p_request_id for update;
  if not found then raise exception 'Ride request not found'; end if;
  if req.status <> 'OPEN' then raise exception 'Ride request is no longer open'; end if;
  if req.latest_departure < now() then raise exception 'Ride request has expired'; end if;

  select * into t from public.trip_routes where id = p_trip_id for update;
  if not found or t.status not in ('SCHEDULED','IN_PROGRESS') then raise exception 'Trip unavailable'; end if;

  if v_actor_id is not null and t.driver_id <> v_actor_id and not public.is_admin() then
    raise exception 'Only the trip driver can accept a ride request for this trip';
  end if;

  if req.requester_id = t.driver_id then
    raise exception 'Driver cannot accept own ride request';
  end if;

  if t.available_seats < req.seats_needed then
    raise exception 'Insufficient seats available on trip';
  end if;

  if req.jurisdiction_code <> t.jurisdiction_code or req.currency <> t.currency then
    raise exception 'Jurisdiction or currency mismatch between ride request and trip route';
  end if;

  if req.earliest_departure > t.departure_time or req.latest_departure < t.departure_time then
    raise exception 'Ride request departure window does not overlap with trip departure time';
  end if;

  v_base := round(t.price_per_seat * req.seats_needed, 2);
  v_fee := round(v_base * p_platform_fee_bps / 10000.0, 2);

  update public.trip_routes
  set available_seats = available_seats - req.seats_needed
  where id = t.id;

  insert into public.escrow_orders(
    order_type, buyer_id, provider_id, trip_id, quantity, total_amount, base_price, reward_fee, platform_fee,
    currency, escrow_status, fulfillment_status, reservation_expires_at
  ) values (
    'RIDE', req.requester_id, t.driver_id, t.id, req.seats_needed, v_base + v_fee, v_base, 0, v_fee,
    t.currency, 'PENDING', 'CREATED', now() + interval '15 minutes'
  ) returning * into v_order;

  update public.ride_requests
  set status = 'MATCHED',
      matched_trip_id = t.id,
      matched_order_id = v_order.id,
      updated_at = now()
  where id = req.id;

  insert into public.escrow_events(order_id, actor_id, event_type, metadata)
  values (v_order.id, t.driver_id, 'ORDER_RESERVED', jsonb_build_object(
    'quantity', req.seats_needed,
    'ride_request_id', req.id
  ));

  return v_order;
end;
$$;

grant select, insert, update on public.ride_requests to authenticated, service_role;
grant execute on function public.create_ride_request to authenticated, service_role;
grant execute on function public.match_ride_requests_along_route(uuid, int) to authenticated, service_role;
grant execute on function public.accept_ride_request_and_reserve_order(uuid, uuid, int) to authenticated, service_role;
