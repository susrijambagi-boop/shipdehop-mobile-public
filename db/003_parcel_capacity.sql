-- Phase 12: Additive migration for transactional parcel capacity accounting (Corrected Fulfillment Predicates)

-- 1. Add parcel capacity units to trip_routes idempotently with CHECK constraints
alter table public.trip_routes
  add column if not exists parcel_capacity_units_total integer,
  add column if not exists parcel_capacity_units_available integer;

-- 2. Add parcel capacity units required to shipment_tasks idempotently
alter table public.shipment_tasks
  add column if not exists parcel_capacity_units_required integer;

-- Backfill parcel_capacity_units_required ONLY where null
update public.shipment_tasks
set parcel_capacity_units_required = case
      when weight_kg <= 1.0 then 1
      when weight_kg <= 5.0 then 3
      else 6
    end
where parcel_capacity_units_required is null;

alter table public.shipment_tasks
  alter column parcel_capacity_units_required set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_shipment_tasks_parcel_units_range') then
    alter table public.shipment_tasks add constraint chk_shipment_tasks_parcel_units_range check (parcel_capacity_units_required between 1 and 12);
  end if;
end $$;

-- Database trigger to automatically derive required parcel units from weight_kg for ALL new/updated shipment tasks
create or replace function public.trg_fn_calculate_shipment_parcel_units()
returns trigger
language plpgsql
as $$
begin
  if NEW.weight_kg <= 1.0 then
    NEW.parcel_capacity_units_required := 1;
  elsif NEW.weight_kg <= 5.0 then
    NEW.parcel_capacity_units_required := 3;
  else
    NEW.parcel_capacity_units_required := 6;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_calculate_shipment_parcel_units on public.shipment_tasks;
create trigger trg_calculate_shipment_parcel_units
  before insert or update of weight_kg on public.shipment_tasks
  for each row
  execute function public.trg_fn_calculate_shipment_parcel_units();

-- 3. Add reserved_parcel_capacity_units to escrow_orders idempotently
alter table public.escrow_orders
  add column if not exists reserved_parcel_capacity_units integer not null default 0;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_escrow_orders_reserved_parcel_units_nonneg') then
    alter table public.escrow_orders add constraint chk_escrow_orders_reserved_parcel_units_nonneg check (reserved_parcel_capacity_units >= 0);
  end if;
end $$;

-- Backfill reserved_parcel_capacity_units on active legacy SHIPMENT orders (escrow_status in PENDING, LOCKED; fulfillment_status not in CANCELLED, COMPLETED)
update public.escrow_orders o
set reserved_parcel_capacity_units = case
      when s.weight_kg <= 1.0 then 1
      when s.weight_kg <= 5.0 then 3
      else 6
    end
from public.shipment_tasks s
where o.shipment_task_id = s.id
  and o.order_type = 'SHIPMENT'
  and o.escrow_status in ('PENDING', 'LOCKED')
  and o.fulfillment_status not in ('CANCELLED', 'COMPLETED')
  and o.reserved_parcel_capacity_units = 0;

-- 4. Initial backfill for trip_routes ONLY where parcel_capacity_units_total is null (accounting for active legacy reservations)
with active_legacy_consumed as (
  select
    o.trip_id,
    sum(
      case
        when s.weight_kg <= 1.0 then 1
        when s.weight_kg <= 5.0 then 3
        else 6
      end
    )::integer as consumed_units
  from public.escrow_orders o
  join public.shipment_tasks s on o.shipment_task_id = s.id
  where o.order_type = 'SHIPMENT'
    and o.trip_id is not null
    and o.escrow_status in ('PENDING', 'LOCKED')
    and o.fulfillment_status not in ('CANCELLED', 'COMPLETED')
  group by o.trip_id
)
update public.trip_routes t
set parcel_capacity_units_total = case t.parcel_capacity_tier
      when 'NONE' then 0
      when 'ENVELOPE' then 2
      when 'MEDIUM' then 6
      when 'LUGGAGE' then 12
      else 0
    end,
    parcel_capacity_units_available = greatest(0,
      case t.parcel_capacity_tier
        when 'NONE' then 0
        when 'ENVELOPE' then 2
        when 'MEDIUM' then 6
        when 'LUGGAGE' then 12
        else 0
      end - coalesce(alc.consumed_units, 0)
    )
from public.trip_routes tr
left join active_legacy_consumed alc on tr.id = alc.trip_id
where t.id = tr.id
  and t.parcel_capacity_units_total is null;

alter table public.trip_routes
  alter column parcel_capacity_units_total set default 0,
  alter column parcel_capacity_units_total set not null,
  alter column parcel_capacity_units_available set default 0,
  alter column parcel_capacity_units_available set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'chk_trip_routes_parcel_units_total_nonneg') then
    alter table public.trip_routes add constraint chk_trip_routes_parcel_units_total_nonneg check (parcel_capacity_units_total >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'chk_trip_routes_parcel_units_avail_nonneg') then
    alter table public.trip_routes add constraint chk_trip_routes_parcel_units_avail_nonneg check (parcel_capacity_units_available >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'chk_trip_routes_parcel_units_avail_le_total') then
    alter table public.trip_routes add constraint chk_trip_routes_parcel_units_avail_le_total check (parcel_capacity_units_available <= parcel_capacity_units_total);
  end if;
end $$;

-- 5. Update create_trip_route function to set initial parcel units
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
  p_ladies_only boolean default false
)
returns public.trip_routes
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
declare
  v_driver uuid := auth.uid();
  v_route geometry;
  v_result public.trip_routes;
  v_units int := 0;
begin
  if v_driver is null then raise exception 'Authentication required'; end if;
  if p_departure_time <= now() then raise exception 'Departure must be in the future'; end if;
  if p_seat_capacity < 1 or p_seat_capacity > 8 then raise exception 'Invalid seat capacity'; end if;

  v_route := ST_SetSRID(ST_Force2D(ST_GeomFromGeoJSON(p_route_geojson)), 4326);
  if GeometryType(v_route) <> 'LINESTRING' then raise exception 'route_geojson must be a LineString'; end if;

  v_units := case p_parcel_capacity_tier
    when 'NONE' then 0
    when 'ENVELOPE' then 2
    when 'MEDIUM' then 6
    when 'LUGGAGE' then 12
    else 0
  end;

  insert into public.trip_routes(
    driver_id, origin_name, origin_geo, dest_name, dest_geo, route_polyline,
    departure_time, seat_capacity, available_seats, parcel_capacity_tier,
    parcel_capacity_units_total, parcel_capacity_units_available,
    price_per_seat, estimated_trip_cost, cost_share_cap_per_seat,
    currency, jurisdiction_code, ladies_only, status
  ) values (
    v_driver, p_origin_name, ST_SetSRID(ST_MakePoint(p_origin_lon, p_origin_lat), 4326)::geography,
    p_dest_name, ST_SetSRID(ST_MakePoint(p_dest_lon, p_dest_lat), 4326)::geography, v_route,
    p_departure_time, p_seat_capacity, p_seat_capacity, p_parcel_capacity_tier,
    v_units, v_units,
    p_price_per_seat, p_estimated_trip_cost, round(p_estimated_trip_cost / p_seat_capacity, 2),
    p_currency, p_jurisdiction_code, p_ladies_only, 'SCHEDULED'
  ) returning * into v_result;

  return v_result;
end;
$$;

-- 6. Drop old function return type signature before recreating match_shipments_along_route
drop function if exists public.match_shipments_along_route(uuid, integer);

create or replace function public.match_shipments_along_route(
  p_trip_id uuid,
  p_max_detour_meters integer default 5000
)
returns table (
  shipment_task_id uuid,
  item_type public.shipment_item_type,
  sender_id uuid,
  pickup_name text,
  drop_name text,
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
begin
  if p_max_detour_meters < 1 or p_max_detour_meters > 50000 then
    raise exception 'Invalid detour limit';
  end if;

  return query
  with route as (
    select t.route_polyline, t.parcel_capacity_tier, t.parcel_capacity_units_available, t.currency, t.jurisdiction_code
    from public.trip_routes t
    where t.id = p_trip_id
      and t.status = 'SCHEDULED'
      and t.parcel_capacity_tier <> 'NONE'
      and t.parcel_capacity_units_available > 0
  ), candidates as (
    select
      s.*,
      ST_Distance(s.pickup_geo, rt.route_polyline) as pickup_dist,
      ST_Distance(s.drop_geo, rt.route_polyline) as drop_dist,
      ST_LineLocatePoint(rt.route_polyline::geometry, s.pickup_geo::geometry) as pickup_frac,
      ST_LineLocatePoint(rt.route_polyline::geometry, s.drop_geo::geometry) as drop_frac
    from public.shipment_tasks s
    cross join route rt
    where s.status = 'OPEN'
      and s.inspection_status = 'APPROVED'
      and s.currency = rt.currency
      and s.parcel_capacity_units_required <= rt.parcel_capacity_units_available
      and public.parcel_tier_allows_weight(rt.parcel_capacity_tier, s.weight_kg)
  )
  select
    c.id, c.item_type, c.sender_id, c.pickup_name, c.drop_name,
    c.weight_kg, c.reward_amount, c.declared_value, c.currency,
    c.parcel_capacity_units_required as required_parcel_units,
    c.pickup_dist, c.drop_dist
  from candidates c
  where c.pickup_dist <= p_max_detour_meters
    and c.drop_dist <= p_max_detour_meters
    and c.pickup_frac < c.drop_frac
  order by (c.pickup_dist + c.drop_dist) asc;
end;
$$;

-- 7. Update reserve_shipment_order to transactionally check and decrement parcel capacity
create or replace function public.reserve_shipment_order(
  p_actor_id uuid,
  p_shipment_id uuid,
  p_provider_id uuid,
  p_trip_id uuid,
  p_platform_fee_bps integer,
  p_max_detour_meters integer default 5000
)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
declare
  s public.shipment_tasks;
  t public.trip_routes;
  v_actor_id uuid;
  v_pickup_frac double precision;
  v_drop_frac double precision;
  v_base numeric(12,2);
  v_fee numeric(12,2);
  v_order public.escrow_orders;
  v_req_units int;
begin
  -- Enforce caller authority via auth.uid()
  if auth.role() = 'authenticated' then
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if p_actor_id is not null and p_actor_id <> auth.uid() then raise exception 'Cannot impersonate another user'; end if;
    v_actor_id := auth.uid();
  else
    v_actor_id := p_actor_id;
  end if;

  if v_actor_id <> p_provider_id then raise exception 'Carrier must claim shipment personally'; end if;
  if p_platform_fee_bps < 0 or p_platform_fee_bps > 3000 then raise exception 'Invalid platform fee'; end if;
  if p_max_detour_meters < 1 or p_max_detour_meters > 50000 then raise exception 'Invalid detour limit'; end if;

  if not exists (select 1 from public.users u where u.id = p_provider_id and u.ekyc_tier in ('TIER_2','TIER_3')) then
    raise exception 'Carrier requires Tier 2 or Tier 3 eKYC';
  end if;

  select * into t from public.trip_routes where id = p_trip_id for update;
  if not found or t.driver_id <> p_provider_id or t.status <> 'SCHEDULED' or t.departure_time <= now() then raise exception 'Eligible carrier route not found'; end if;
  if t.parcel_capacity_tier = 'NONE' or t.parcel_capacity_units_available <= 0 then raise exception 'Route has no available parcel capacity'; end if;

  select * into s from public.shipment_tasks where id = p_shipment_id for update;
  if not found or s.status <> 'OPEN' then raise exception 'Shipment unavailable'; end if;
  if s.inspection_status <> 'APPROVED' then raise exception 'Shipment has not passed HopShield parcel inspection'; end if;
  if s.sender_id = p_provider_id then raise exception 'Sender cannot carry own shipment order'; end if;
  
  v_req_units := coalesce(s.parcel_capacity_units_required, 3);
  if v_req_units <= 0 then
    raise exception 'Invalid required parcel capacity units';
  end if;

  if t.parcel_capacity_units_available < v_req_units then
    raise exception 'Insufficient parcel carrying capacity on route';
  end if;

  if not public.parcel_tier_allows_weight(t.parcel_capacity_tier, s.weight_kg) then raise exception 'Shipment exceeds route cargo tier'; end if;
  if not ST_DWithin(s.pickup_geo, t.route_polyline, p_max_detour_meters) or not ST_DWithin(s.drop_geo, t.route_polyline, p_max_detour_meters) then
    raise exception 'Shipment is outside route corridor';
  end if;

  v_pickup_frac := ST_LineLocatePoint(t.route_polyline::geometry, s.pickup_geo::geometry);
  v_drop_frac := ST_LineLocatePoint(t.route_polyline::geometry, s.drop_geo::geometry);
  if v_pickup_frac >= v_drop_frac then raise exception 'Shipment direction does not match route'; end if;

  -- Decrement trip parcel capacity units atomically
  update public.trip_routes
  set parcel_capacity_units_available = parcel_capacity_units_available - v_req_units
  where id = t.id;

  v_base := case when s.item_type = 'URL_PURCHASE' then s.declared_value else 0 end;
  v_fee := round((v_base + s.reward_amount) * p_platform_fee_bps / 10000.0, 2);

  update public.shipment_tasks set status = 'MATCHED' where id = s.id;

  insert into public.escrow_orders(
    order_type,buyer_id,provider_id,trip_id,shipment_task_id,total_amount,base_price,reward_fee,platform_fee,
    currency,escrow_status,fulfillment_status,reservation_expires_at,reserved_parcel_capacity_units
  ) values (
    'SHIPMENT',s.sender_id,p_provider_id,t.id,s.id,v_base + s.reward_amount + v_fee,v_base,s.reward_amount,v_fee,
    s.currency,'PENDING','CREATED',now() + interval '30 minutes',v_req_units
  ) returning * into v_order;

  insert into public.escrow_events(order_id,actor_id,event_type,metadata)
  values (v_order.id,p_provider_id,'ORDER_RESERVED',jsonb_build_object('trip_id',t.id,'max_detour_meters',p_max_detour_meters,'payer_id',s.sender_id,'reserved_parcel_units',v_req_units));

  return v_order;
end;
$$;

-- 8. Update restore_order_inventory to restore parcel capacity upon cancellation
create or replace function public.restore_order_inventory(p_order public.escrow_orders)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_units int;
begin
  if p_order.order_type = 'RIDE' and p_order.trip_id is not null then
    update public.trip_routes
      set available_seats = least(seat_capacity, available_seats + p_order.quantity)
      where id = p_order.trip_id and status = 'SCHEDULED';
  elsif p_order.order_type = 'MARKETPLACE' and p_order.marketplace_item_id is not null then
    update public.marketplace_items set status = 'LISTED'
      where id = p_order.marketplace_item_id and status = 'RESERVED';
  elsif p_order.order_type = 'SHIPMENT' and p_order.shipment_task_id is not null then
    update public.shipment_tasks set status = 'OPEN'
      where id = p_order.shipment_task_id and status = 'MATCHED';

    if p_order.trip_id is not null then
      v_units := coalesce(p_order.reserved_parcel_capacity_units, 3);
      update public.trip_routes
        set parcel_capacity_units_available = least(parcel_capacity_units_total, parcel_capacity_units_available + v_units)
        where id = p_order.trip_id and status = 'SCHEDULED';
    end if;
  end if;
end;
$$;

-- 9. Explicit Least-Privilege Grants (No Anon Access to Mutation RPCs)
revoke execute on function public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean) from public, anon;
grant execute on function public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean) to authenticated, service_role;

revoke execute on function public.match_shipments_along_route(uuid,int) from public, anon;
grant execute on function public.match_shipments_along_route(uuid,int) to authenticated, service_role;

revoke execute on function public.reserve_shipment_order(uuid,uuid,uuid,uuid,integer,integer) from public, anon;
grant execute on function public.reserve_shipment_order(uuid,uuid,uuid,uuid,integer,integer) to authenticated, service_role;

revoke execute on function public.restore_order_inventory(public.escrow_orders) from public, anon, authenticated;
grant execute on function public.restore_order_inventory(public.escrow_orders) to service_role;
