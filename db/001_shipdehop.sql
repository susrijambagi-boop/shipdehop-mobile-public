create schema if not exists extensions;
set search_path = public, extensions;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists postgis with schema extensions;

create type public.ekyc_tier as enum ('TIER_1','TIER_2','TIER_3');
create type public.parcel_capacity_tier as enum ('NONE','ENVELOPE','MEDIUM','LUGGAGE');
create type public.trip_status as enum ('DRAFT','SCHEDULED','IN_PROGRESS','COMPLETED','CANCELLED');
create type public.marketplace_item_status as enum ('DRAFT','LISTED','RESERVED','SOLD','REMOVED');
create type public.item_condition as enum ('NEW','LIKE_NEW','GOOD','FAIR','POOR');
create type public.shipment_item_type as enum ('PARCEL','URL_PURCHASE');
create type public.shipment_status as enum ('DRAFT','OPEN','MATCHED','IN_TRANSIT','DELIVERED','CANCELLED');
create type public.shipment_inspection_status as enum ('PENDING','APPROVED','REVIEW','BLOCKED');
create type public.order_type as enum ('RIDE','MARKETPLACE','SHIPMENT');
create type public.escrow_status as enum ('PENDING','LOCKED','RELEASED','REFUNDED','DISPUTED');
create type public.fulfillment_status as enum ('CREATED','READY','IN_TRANSIT','AWAITING_HANDOFF','VERIFIED','COMPLETED','CANCELLED');
create type public.safe_zone_type as enum ('FUEL_STATION','METRO','TRANSIT_HUB');
create type public.chat_safety_status as enum ('SAFE','WARN','BLOCKED');
create type public.payment_provider as enum ('STRIPE','RAZORPAY','UPI_ESCROW');

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  phone text,
  ekyc_tier public.ekyc_tier not null default 'TIER_1',
  trust_score numeric(5,2) not null default 50.00 check (trust_score between 0 and 100),
  is_female boolean,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table public.cost_sharing_policies (
  jurisdiction_code text primary key,
  max_recovery_ratio numeric(6,4) not null check (max_recovery_ratio > 0 and max_recovery_ratio <= 1.5),
  hard_cap_per_seat numeric(12,2),
  currency char(3) not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.trip_routes (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.users(id) on delete cascade,
  origin_name text not null,
  origin_geo geography(Point,4326) not null,
  dest_name text not null,
  dest_geo geography(Point,4326) not null,
  route_polyline geography(LineString,4326) not null,
  departure_time timestamptz not null,
  seat_capacity smallint not null check (seat_capacity between 1 and 8),
  available_seats smallint not null check (available_seats between 0 and 8),
  parcel_capacity_tier public.parcel_capacity_tier not null default 'NONE',
  price_per_seat numeric(12,2) not null check (price_per_seat >= 0),
  estimated_trip_cost numeric(12,2) not null check (estimated_trip_cost > 0),
  cost_share_cap_per_seat numeric(12,2) not null check (cost_share_cap_per_seat >= 0),
  currency char(3) not null,
  jurisdiction_code text not null references public.cost_sharing_policies(jurisdiction_code),
  ladies_only boolean not null default false,
  status public.trip_status not null default 'SCHEDULED',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (available_seats <= seat_capacity),
  check (price_per_seat <= cost_share_cap_per_seat)
);

create table public.marketplace_items (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.users(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 140),
  description text not null,
  category text not null,
  price numeric(12,2) not null check (price >= 0),
  currency char(3) not null,
  condition public.item_condition not null,
  location_geo geography(Point,4326) not null,
  ship_eligible boolean not null default false,
  status public.marketplace_item_status not null default 'DRAFT',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.shipment_tasks (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.users(id) on delete cascade,
  item_type public.shipment_item_type not null,
  product_url text,
  declared_value numeric(12,2) not null default 0 check (declared_value >= 0),
  reward_amount numeric(12,2) not null default 0 check (reward_amount >= 0),
  currency char(3) not null,
  pickup_geo geography(Point,4326) not null,
  drop_geo geography(Point,4326) not null,
  weight_kg numeric(8,3) not null check (weight_kg > 0 and weight_kg <= 40),
  status public.shipment_status not null default 'DRAFT',
  inspection_status public.shipment_inspection_status not null default 'PENDING',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((item_type = 'URL_PURCHASE' and product_url is not null) or item_type = 'PARCEL')
);

create table public.parcel_inspections (
  id uuid primary key default gen_random_uuid(),
  shipment_task_id uuid not null references public.shipment_tasks(id) on delete cascade,
  submitted_by uuid not null references public.users(id),
  decision public.shipment_inspection_status not null check (decision in ('APPROVED','REVIEW','BLOCKED')),
  confidence numeric(5,4) not null check (confidence between 0 and 1),
  content_mismatch boolean not null default false,
  prohibited_categories text[] not null default '{}',
  rationale text not null,
  model text not null,
  created_at timestamptz not null default now()
);

create table public.payment_accounts (
  user_id uuid not null references public.users(id) on delete cascade,
  provider public.payment_provider not null,
  external_account_id text not null,
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (user_id, provider)
);

create table public.escrow_orders (
  id uuid primary key default gen_random_uuid(),
  order_type public.order_type not null,
  buyer_id uuid not null references public.users(id),
  provider_id uuid not null references public.users(id),
  trip_id uuid references public.trip_routes(id),
  marketplace_item_id uuid references public.marketplace_items(id),
  shipment_task_id uuid references public.shipment_tasks(id),
  quantity integer not null default 1 check (quantity > 0 and quantity <= 8),
  total_amount numeric(12,2) not null check (total_amount >= 0),
  base_price numeric(12,2) not null check (base_price >= 0),
  reward_fee numeric(12,2) not null default 0 check (reward_fee >= 0),
  platform_fee numeric(12,2) not null default 0 check (platform_fee >= 0),
  currency char(3) not null,
  escrow_status public.escrow_status not null default 'PENDING',
  fulfillment_status public.fulfillment_status not null default 'CREATED',
  payment_provider public.payment_provider,
  provider_checkout_ref text,
  provider_payment_ref text,
  handoff_otp_hash text,
  handoff_otp_expires_at timestamptz,
  handoff_attempts smallint not null default 0 check (handoff_attempts between 0 and 10),
  handoff_locked_until timestamptz,
  tamper_qr_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (buyer_id <> provider_id),
  check (total_amount = base_price + reward_fee + platform_fee),
  check (
    (order_type = 'RIDE' and trip_id is not null and marketplace_item_id is null and shipment_task_id is null) or
    (order_type = 'MARKETPLACE' and trip_id is null and marketplace_item_id is not null and shipment_task_id is null) or
    (order_type = 'SHIPMENT' and marketplace_item_id is null and shipment_task_id is not null)
  )
);

create table public.safe_zones (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type public.safe_zone_type not null,
  location_geo geography(Point,4326) not null,
  address text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.chat_threads (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.escrow_orders(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.chat_threads(id) on delete cascade,
  sender_id uuid not null references public.users(id),
  body text,
  image_url text,
  safety_status public.chat_safety_status not null default 'SAFE',
  safety_reason text,
  created_at timestamptz not null default now(),
  check (body is not null or image_url is not null)
);

create table public.trip_live_state (
  trip_id uuid primary key references public.trip_routes(id) on delete cascade,
  driver_id uuid not null references public.users(id),
  location_geo geography(Point,4326) not null,
  heading numeric(6,2),
  speed_mps numeric(8,3),
  recorded_at timestamptz not null,
  updated_at timestamptz not null default now()
);

create table public.escrow_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.escrow_orders(id) on delete cascade,
  actor_id uuid references public.users(id),
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index users_email_idx on public.users(email);
create index users_phone_idx on public.users(phone);
create index trip_routes_driver_idx on public.trip_routes(driver_id);
create index trip_routes_departure_idx on public.trip_routes(departure_time) where status = 'SCHEDULED';
create index trip_routes_origin_gix on public.trip_routes using gist(origin_geo);
create index trip_routes_dest_gix on public.trip_routes using gist(dest_geo);
create index trip_routes_polyline_gix on public.trip_routes using gist(route_polyline);
create index marketplace_items_seller_idx on public.marketplace_items(seller_id);
create index marketplace_items_location_gix on public.marketplace_items using gist(location_geo);
create index shipment_tasks_sender_idx on public.shipment_tasks(sender_id);
create index shipment_tasks_pickup_gix on public.shipment_tasks using gist(pickup_geo);
create index shipment_tasks_drop_gix on public.shipment_tasks using gist(drop_geo);
create index parcel_inspections_task_idx on public.parcel_inspections(shipment_task_id, created_at desc);
create index escrow_orders_buyer_idx on public.escrow_orders(buyer_id);
create index escrow_orders_provider_idx on public.escrow_orders(provider_id);
create index escrow_orders_trip_idx on public.escrow_orders(trip_id);
create index escrow_orders_item_idx on public.escrow_orders(marketplace_item_id);
create index escrow_orders_shipment_idx on public.escrow_orders(shipment_task_id);
create index safe_zones_location_gix on public.safe_zones using gist(location_geo);
create index chat_messages_thread_time_idx on public.chat_messages(thread_id, created_at);
create index trip_live_state_location_gix on public.trip_live_state using gist(location_geo);
create index escrow_events_order_time_idx on public.escrow_events(order_id, created_at);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

create or replace function public.current_user_is_verified_female()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users u
    where u.id = (select auth.uid())
      and u.is_female is true
      and u.ekyc_tier in ('TIER_2','TIER_3')
  );
$$;

create or replace function public.is_order_party(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.escrow_orders e
    where e.id = p_order_id
      and ((select auth.uid()) = e.buyer_id or (select auth.uid()) = e.provider_id)
  );
$$;

create or replace function public.is_trip_party(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin()
    or exists (select 1 from public.trip_routes t where t.id = p_trip_id and t.driver_id = (select auth.uid()))
    or exists (
      select 1 from public.escrow_orders e
      where e.trip_id = p_trip_id
        and e.escrow_status in ('LOCKED','RELEASED','DISPUTED')
        and ((select auth.uid()) = e.buyer_id or (select auth.uid()) = e.provider_id)
    );
$$;

create or replace function public.has_shipment_access(p_shipment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin()
    or exists (select 1 from public.shipment_tasks s where s.id = p_shipment_id and s.sender_id = (select auth.uid()))
    or exists (
      select 1 from public.escrow_orders e
      where e.shipment_task_id = p_shipment_id
        and e.escrow_status in ('LOCKED','RELEASED','DISPUTED')
        and ((select auth.uid()) = e.buyer_id or (select auth.uid()) = e.provider_id)
    );
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trip_routes_updated_at before update on public.trip_routes
for each row execute function public.set_updated_at();
create trigger marketplace_items_updated_at before update on public.marketplace_items
for each row execute function public.set_updated_at();
create trigger shipment_tasks_updated_at before update on public.shipment_tasks
for each row execute function public.set_updated_at();
create trigger escrow_orders_updated_at before update on public.escrow_orders
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users(id, email, phone)
  values (new.id, new.email, new.phone)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

create or replace function public.enforce_trip_cost_share_cap()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  p public.cost_sharing_policies;
  computed_cap numeric(12,2);
begin
  select * into p
  from public.cost_sharing_policies
  where jurisdiction_code = new.jurisdiction_code and enabled is true;

  if not found then
    raise exception 'No enabled cost-sharing policy for jurisdiction %', new.jurisdiction_code;
  end if;

  if p.currency <> new.currency then
    raise exception 'Trip currency % does not match jurisdiction policy currency %', new.currency, p.currency;
  end if;

  computed_cap := round((new.estimated_trip_cost * p.max_recovery_ratio) / (new.seat_capacity + 1), 2);
  if p.hard_cap_per_seat is not null then
    computed_cap := least(computed_cap, p.hard_cap_per_seat);
  end if;

  new.cost_share_cap_per_seat := computed_cap;
  if new.price_per_seat > computed_cap then
    raise exception 'price_per_seat % exceeds non-commercial cap %', new.price_per_seat, computed_cap;
  end if;
  return new;
end;
$$;

create trigger trip_cost_share_cap_guard
before insert or update of price_per_seat, estimated_trip_cost, seat_capacity, jurisdiction_code, currency
on public.trip_routes
for each row execute function public.enforce_trip_cost_share_cap();

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
set search_path = public, extensions
as $$
declare
  v_driver uuid := auth.uid();
  v_route geometry;
  v_result public.trip_routes;
begin
  if v_driver is null then raise exception 'Authentication required'; end if;
  if p_departure_time <= now() then raise exception 'Departure must be in the future'; end if;
  if p_seat_capacity < 1 or p_seat_capacity > 8 then raise exception 'Invalid seat capacity'; end if;

  v_route := ST_SetSRID(ST_Force2D(ST_GeomFromGeoJSON(p_route_geojson)), 4326);
  if GeometryType(v_route) <> 'LINESTRING' then raise exception 'route_geojson must be a LineString'; end if;

  insert into public.trip_routes(
    driver_id, origin_name, origin_geo, dest_name, dest_geo, route_polyline,
    departure_time, seat_capacity, available_seats, parcel_capacity_tier,
    price_per_seat, estimated_trip_cost, cost_share_cap_per_seat,
    currency, jurisdiction_code, ladies_only, status
  ) values (
    v_driver,
    p_origin_name, ST_SetSRID(ST_Point(p_origin_lon,p_origin_lat),4326)::geography,
    p_dest_name, ST_SetSRID(ST_Point(p_dest_lon,p_dest_lat),4326)::geography,
    v_route::geography,
    p_departure_time, p_seat_capacity, p_seat_capacity, p_parcel_capacity_tier,
    p_price_per_seat, p_estimated_trip_cost, 0,
    upper(p_currency), p_jurisdiction_code, p_ladies_only, 'SCHEDULED'
  ) returning * into v_result;

  return v_result;
end;
$$;

create or replace function public.match_shipments_along_route(
  p_trip_id uuid,
  p_max_detour_meters int
)
returns table (
  shipment_task_id uuid,
  item_type public.shipment_item_type,
  weight_kg numeric,
  declared_value numeric,
  reward_amount numeric,
  currency char(3),
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

  if not exists (
    select 1 from public.trip_routes t
    where t.id = p_trip_id
      and (t.driver_id = auth.uid() or public.is_admin())
  ) then
    raise exception 'Not authorized for this trip';
  end if;

  return query
  with route as (
    select t.route_polyline, t.parcel_capacity_tier
    from public.trip_routes t
    where t.id = p_trip_id
      and t.status in ('SCHEDULED','IN_PROGRESS')
      and t.parcel_capacity_tier <> 'NONE'
  ), candidates as (
    select
      s.*,
      ST_Distance(s.pickup_geo, r.route_polyline) as pickup_m,
      ST_Distance(s.drop_geo, r.route_polyline) as drop_m,
      ST_LineLocatePoint(r.route_polyline::geometry, s.pickup_geo::geometry) as pickup_frac,
      ST_LineLocatePoint(r.route_polyline::geometry, s.drop_geo::geometry) as drop_frac
    from public.shipment_tasks s
    cross join route r
    where s.status = 'OPEN'
      and s.inspection_status = 'APPROVED'
      and case r.parcel_capacity_tier
        when 'ENVELOPE' then s.weight_kg <= 1.0
        when 'MEDIUM' then s.weight_kg <= 5.0
        when 'LUGGAGE' then s.weight_kg <= 25.0
        else false
      end
      and ST_DWithin(s.pickup_geo, r.route_polyline, p_max_detour_meters)
      and ST_DWithin(s.drop_geo, r.route_polyline, p_max_detour_meters)
  )
  select
    c.id, c.item_type, c.weight_kg, c.declared_value, c.reward_amount, c.currency,
    c.pickup_m, c.drop_m, c.pickup_frac, c.drop_frac
  from candidates c
  where c.pickup_frac < c.drop_frac
  order by (c.pickup_m + c.drop_m), c.reward_amount desc;
end;
$$;

create or replace function public.match_passenger_trips(
  p_origin_lon double precision,
  p_origin_lat double precision,
  p_dest_lon double precision,
  p_dest_lat double precision,
  p_depart_after timestamptz,
  p_depart_before timestamptz,
  p_max_detour_meters int,
  p_require_ladies_only boolean default false
)
returns table (
  trip_id uuid,
  origin_name text,
  dest_name text,
  departure_time timestamptz,
  available_seats smallint,
  price_per_seat numeric,
  currency char(3),
  ladies_only boolean,
  origin_distance_m double precision,
  dest_distance_m double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with input as (
    select
      ST_SetSRID(ST_Point(p_origin_lon,p_origin_lat),4326)::geography as o,
      ST_SetSRID(ST_Point(p_dest_lon,p_dest_lat),4326)::geography as d
  ), candidates as (
    select
      t.*,
      ST_Distance(i.o, t.route_polyline) as o_dist,
      ST_Distance(i.d, t.route_polyline) as d_dist,
      ST_LineLocatePoint(t.route_polyline::geometry, i.o::geometry) as o_frac,
      ST_LineLocatePoint(t.route_polyline::geometry, i.d::geometry) as d_frac
    from public.trip_routes t cross join input i
    where t.status = 'SCHEDULED'
      and t.available_seats > 0
      and t.departure_time between p_depart_after and p_depart_before
      and ST_DWithin(i.o, t.route_polyline, p_max_detour_meters)
      and ST_DWithin(i.d, t.route_polyline, p_max_detour_meters)
      and (not t.ladies_only or public.current_user_is_verified_female())
      and (not p_require_ladies_only or t.ladies_only)
  )
  select id, origin_name, dest_name, departure_time, available_seats, price_per_seat,
         currency, ladies_only, o_dist, d_dist
  from candidates
  where o_frac < d_frac
  order by departure_time, (o_dist + d_dist);
$$;

create or replace function public.mark_order_in_transit(p_order_id uuid)
returns public.escrow_orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if auth.uid() <> v.provider_id and not public.is_admin() then raise exception 'Provider only'; end if;
  if v.escrow_status <> 'LOCKED' then raise exception 'Funds are not locked'; end if;
  if v.fulfillment_status not in ('READY','CREATED') then raise exception 'Invalid fulfillment state'; end if;

  update public.escrow_orders
  set fulfillment_status = 'IN_TRANSIT'
  where id = p_order_id returning * into v;

  insert into public.escrow_events(order_id,actor_id,event_type)
  values (p_order_id, auth.uid(), 'IN_TRANSIT');
  return v;
end;
$$;

create or replace function public.verify_handoff_otp(p_order_id uuid, p_otp text)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if auth.uid() <> v.buyer_id and not public.is_admin() then raise exception 'Buyer confirmation required'; end if;
  if v.escrow_status <> 'LOCKED' then raise exception 'Order is not locked'; end if;
  if v.fulfillment_status not in ('IN_TRANSIT','AWAITING_HANDOFF') then raise exception 'Order is not ready for handoff'; end if;
  if v.handoff_locked_until is not null and v.handoff_locked_until > now() then raise exception 'OTP verification temporarily locked'; end if;
  if v.handoff_otp_expires_at is null or v.handoff_otp_expires_at < now() then raise exception 'OTP expired'; end if;

  if v.handoff_otp_hash is null or crypt(p_otp, v.handoff_otp_hash) <> v.handoff_otp_hash then
    update public.escrow_orders
    set handoff_attempts = handoff_attempts + 1,
        handoff_locked_until = case when handoff_attempts + 1 >= 5 then now() + interval '15 minutes' else handoff_locked_until end
    where id = p_order_id;
    raise exception 'Invalid OTP';
  end if;

  update public.escrow_orders
  set fulfillment_status = 'VERIFIED', handoff_attempts = 0, handoff_locked_until = null
  where id = p_order_id returning * into v;

  insert into public.escrow_events(order_id,actor_id,event_type)
  values (p_order_id, auth.uid(), 'HANDOFF_VERIFIED');
  return v;
end;
$$;

alter table public.users enable row level security;
alter table public.cost_sharing_policies enable row level security;
alter table public.trip_routes enable row level security;
alter table public.marketplace_items enable row level security;
alter table public.shipment_tasks enable row level security;
alter table public.payment_accounts enable row level security;
alter table public.parcel_inspections enable row level security;
alter table public.escrow_orders enable row level security;
alter table public.safe_zones enable row level security;
alter table public.chat_threads enable row level security;
alter table public.chat_messages enable row level security;
alter table public.trip_live_state enable row level security;
alter table public.escrow_events enable row level security;

create policy users_self_select on public.users for select to authenticated
using ((select auth.uid()) = id or public.is_admin());
create policy users_self_avatar_update on public.users for update to authenticated
using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy admin_cost_policy_all on public.cost_sharing_policies for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy trip_routes_select on public.trip_routes for select to authenticated
using (
  driver_id = (select auth.uid())
  or public.is_admin()
  or (status = 'SCHEDULED' and (not ladies_only or public.current_user_is_verified_female()))
  or public.is_trip_party(id)
);
create policy trip_routes_owner_update on public.trip_routes for update to authenticated
using (driver_id = (select auth.uid()))
with check (driver_id = (select auth.uid()));

create policy marketplace_select on public.marketplace_items for select to authenticated
using (status = 'LISTED' or seller_id = (select auth.uid()) or public.is_admin());
create policy marketplace_insert on public.marketplace_items for insert to authenticated
with check (seller_id = (select auth.uid()));
create policy marketplace_update on public.marketplace_items for update to authenticated
using (seller_id = (select auth.uid())) with check (seller_id = (select auth.uid()));
create policy marketplace_delete on public.marketplace_items for delete to authenticated
using (seller_id = (select auth.uid()) and status in ('DRAFT','LISTED','REMOVED'));

create policy shipment_select on public.shipment_tasks for select to authenticated
using (public.has_shipment_access(id));
create policy shipment_insert on public.shipment_tasks for insert to authenticated
with check (sender_id = (select auth.uid()));
create policy shipment_update on public.shipment_tasks for update to authenticated
using (sender_id = (select auth.uid())) with check (sender_id = (select auth.uid()));

create policy parcel_inspections_party_select on public.parcel_inspections for select to authenticated
using (public.has_shipment_access(shipment_task_id));

create policy payment_accounts_self_select on public.payment_accounts for select to authenticated
using (user_id = (select auth.uid()) or public.is_admin());

create policy escrow_party_select on public.escrow_orders for select to authenticated
using ((select auth.uid()) in (buyer_id, provider_id) or public.is_admin());

create policy safe_zones_select on public.safe_zones for select to authenticated
using (active or public.is_admin());
create policy safe_zones_admin_all on public.safe_zones for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy chat_threads_party_select on public.chat_threads for select to authenticated
using (public.is_order_party(order_id));
create policy chat_messages_party_select on public.chat_messages for select to authenticated
using (exists (
  select 1 from public.chat_threads t
  where t.id = chat_messages.thread_id and public.is_order_party(t.order_id)
));

create policy live_state_party_select on public.trip_live_state for select to authenticated
using (public.is_trip_party(trip_id));

create policy escrow_events_party_select on public.escrow_events for select to authenticated
using (public.is_order_party(order_id));

revoke all on public.users from anon, authenticated;
grant select on public.users to authenticated;
grant update (avatar_url) on public.users to authenticated;

revoke all on public.cost_sharing_policies from anon, authenticated;
grant select, insert, update, delete on public.cost_sharing_policies to authenticated;

revoke all on public.trip_routes from anon, authenticated;
grant select on public.trip_routes to authenticated;
grant update (status) on public.trip_routes to authenticated;

revoke all on public.marketplace_items from anon, authenticated;
grant select, insert, update, delete on public.marketplace_items to authenticated;

revoke all on public.shipment_tasks from anon, authenticated;
grant select, insert, update on public.shipment_tasks to authenticated;

revoke all on public.parcel_inspections from anon, authenticated;
grant select on public.parcel_inspections to authenticated;

revoke all on public.payment_accounts from anon, authenticated;
grant select on public.payment_accounts to authenticated;

revoke all on public.escrow_orders from anon, authenticated;
grant select on public.escrow_orders to authenticated;

revoke all on public.safe_zones from anon, authenticated;
grant select, insert, update, delete on public.safe_zones to authenticated;

revoke all on public.chat_threads from anon, authenticated;
grant select on public.chat_threads to authenticated;
revoke all on public.chat_messages from anon, authenticated;
grant select on public.chat_messages to authenticated;

revoke all on public.trip_live_state from anon, authenticated;
grant select on public.trip_live_state to authenticated;
revoke all on public.escrow_events from anon, authenticated;
grant select on public.escrow_events to authenticated;

revoke execute on function public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean) from public;
grant execute on function public.create_trip_route(text,double precision,double precision,text,double precision,double precision,text,timestamptz,smallint,public.parcel_capacity_tier,numeric,numeric,char,text,boolean) to authenticated;
revoke execute on function public.match_shipments_along_route(uuid,int) from public;
grant execute on function public.match_shipments_along_route(uuid,int) to authenticated;
revoke execute on function public.match_passenger_trips(double precision,double precision,double precision,double precision,timestamptz,timestamptz,int,boolean) from public;
grant execute on function public.match_passenger_trips(double precision,double precision,double precision,double precision,timestamptz,timestamptz,int,boolean) to authenticated;
revoke execute on function public.mark_order_in_transit(uuid) from public;
grant execute on function public.mark_order_in_transit(uuid) to authenticated;
revoke execute on function public.verify_handoff_otp(uuid,text) from public;
grant execute on function public.verify_handoff_otp(uuid,text) to authenticated;

-- Private Realtime authorization for high-frequency trip tracking.
-- Topic format: trip:<trip_uuid>:tracking
create policy "trip parties can receive tracking"
on realtime.messages for select to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and split_part((select realtime.topic()), ':', 1) = 'trip'
  and split_part((select realtime.topic()), ':', 3) = 'tracking'
  and public.is_trip_party(split_part((select realtime.topic()), ':', 2)::uuid)
);

create policy "driver can send tracking"
on realtime.messages for insert to authenticated
with check (
  realtime.messages.extension = 'broadcast'
  and split_part((select realtime.topic()), ':', 1) = 'trip'
  and split_part((select realtime.topic()), ':', 3) = 'tracking'
  and exists (
    select 1 from public.trip_routes t
    where t.id = split_part((select realtime.topic()), ':', 2)::uuid
      and t.driver_id = (select auth.uid())
      and t.status = 'IN_PROGRESS'
  )
);

-- Chat is durable and lower frequency, so Postgres Changes is acceptable here.
-- Enable only the chat table in the publication if it is not already present.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'chat_messages'
  ) then
    alter publication supabase_realtime add table public.chat_messages;
  end if;
end $$;

create or replace function public.hash_handoff_secret(p_secret text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select crypt(p_secret, gen_salt('bf', 12));
$$;
revoke execute on function public.hash_handoff_secret(text) from public, anon, authenticated;
grant execute on function public.hash_handoff_secret(text) to service_role;

-- ---------------------------------------------------------------------------
-- Atomic inventory reservations and service-only escrow transitions.
-- ---------------------------------------------------------------------------
alter table public.escrow_orders
  add column if not exists provider_checkout_ref text,
  add column if not exists reservation_expires_at timestamptz,
  add column if not exists payout_transfer_ref text,
  add column if not exists refund_ref text;

create index if not exists escrow_pending_expiry_idx
  on public.escrow_orders(reservation_expires_at)
  where escrow_status = 'PENDING';

create or replace function public.create_order_chat_thread()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.chat_threads(order_id) values (new.id) on conflict (order_id) do nothing;
  return new;
end;
$$;

drop trigger if exists escrow_create_chat_thread on public.escrow_orders;
create trigger escrow_create_chat_thread
after insert on public.escrow_orders
for each row execute function public.create_order_chat_thread();

create or replace function public.reserve_ride_order(
  p_actor_id uuid,
  p_trip_id uuid,
  p_quantity integer,
  p_platform_fee_bps integer
)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  t public.trip_routes;
  v_base numeric(12,2);
  v_fee numeric(12,2);
  v_order public.escrow_orders;
begin
  if p_actor_id is null or p_quantity < 1 or p_quantity > 8 then raise exception 'Invalid reservation'; end if;
  if p_platform_fee_bps < 0 or p_platform_fee_bps > 3000 then raise exception 'Invalid platform fee'; end if;

  select * into t from public.trip_routes where id = p_trip_id for update;
  if not found or t.status <> 'SCHEDULED' or t.departure_time <= now() then raise exception 'Trip unavailable'; end if;
  if t.driver_id = p_actor_id then raise exception 'Driver cannot book own trip'; end if;
  if t.available_seats < p_quantity then raise exception 'Insufficient seats'; end if;
  if t.price_per_seat > t.cost_share_cap_per_seat then raise exception 'Trip violates cost-sharing cap'; end if;
  if t.ladies_only and not exists (
    select 1 from public.users u where u.id = p_actor_id and u.is_female is true and u.ekyc_tier in ('TIER_2','TIER_3')
  ) then raise exception 'This ride requires verified Ladies Only eligibility'; end if;

  v_base := round(t.price_per_seat * p_quantity, 2);
  v_fee := round(v_base * p_platform_fee_bps / 10000.0, 2);

  update public.trip_routes set available_seats = available_seats - p_quantity where id = t.id;
  insert into public.escrow_orders(
    order_type,buyer_id,provider_id,trip_id,quantity,total_amount,base_price,reward_fee,platform_fee,
    currency,escrow_status,fulfillment_status,reservation_expires_at
  ) values (
    'RIDE',p_actor_id,t.driver_id,t.id,p_quantity,v_base + v_fee,v_base,0,v_fee,
    t.currency,'PENDING','CREATED',now() + interval '15 minutes'
  ) returning * into v_order;

  insert into public.escrow_events(order_id,actor_id,event_type,metadata)
  values (v_order.id,p_actor_id,'ORDER_RESERVED',jsonb_build_object('quantity',p_quantity));
  return v_order;
end;
$$;

create or replace function public.reserve_marketplace_order(
  p_actor_id uuid,
  p_item_id uuid,
  p_platform_fee_bps integer
)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  i public.marketplace_items;
  v_fee numeric(12,2);
  v_order public.escrow_orders;
begin
  if p_platform_fee_bps < 0 or p_platform_fee_bps > 3000 then raise exception 'Invalid platform fee'; end if;
  select * into i from public.marketplace_items where id = p_item_id for update;
  if not found or i.status <> 'LISTED' then raise exception 'Item unavailable'; end if;
  if i.seller_id = p_actor_id then raise exception 'Seller cannot buy own item'; end if;

  v_fee := round(i.price * p_platform_fee_bps / 10000.0, 2);
  update public.marketplace_items set status = 'RESERVED' where id = i.id;
  insert into public.escrow_orders(
    order_type,buyer_id,provider_id,marketplace_item_id,total_amount,base_price,reward_fee,platform_fee,
    currency,escrow_status,fulfillment_status,reservation_expires_at
  ) values (
    'MARKETPLACE',p_actor_id,i.seller_id,i.id,i.price + v_fee,i.price,0,v_fee,
    i.currency,'PENDING','CREATED',now() + interval '15 minutes'
  ) returning * into v_order;

  insert into public.escrow_events(order_id,actor_id,event_type) values (v_order.id,p_actor_id,'ORDER_RESERVED');
  return v_order;
end;
$$;

create or replace function public.reserve_shipment_order(
  p_actor_id uuid,
  p_shipment_id uuid,
  p_provider_id uuid,
  p_platform_fee_bps integer
)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  s public.shipment_tasks;
  v_base numeric(12,2);
  v_fee numeric(12,2);
  v_order public.escrow_orders;
begin
  if p_actor_id <> p_provider_id then raise exception 'Carrier must claim shipment personally'; end if;
  if p_platform_fee_bps < 0 or p_platform_fee_bps > 3000 then raise exception 'Invalid platform fee'; end if;
  if not exists (select 1 from public.users u where u.id = p_provider_id and u.ekyc_tier in ('TIER_2','TIER_3')) then
    raise exception 'Carrier requires Tier 2 or Tier 3 eKYC';
  end if;

  select * into s from public.shipment_tasks where id = p_shipment_id for update;
  if not found or s.status <> 'OPEN' then raise exception 'Shipment unavailable'; end if;
  if s.inspection_status <> 'APPROVED' then raise exception 'Shipment has not passed HopShield parcel inspection'; end if;
  if s.sender_id = p_provider_id then raise exception 'Sender cannot carry own shipment order'; end if;

  v_base := case when s.item_type = 'URL_PURCHASE' then s.declared_value else 0 end;
  v_fee := round((v_base + s.reward_amount) * p_platform_fee_bps / 10000.0, 2);
  update public.shipment_tasks set status = 'MATCHED' where id = s.id;
  insert into public.escrow_orders(
    order_type,buyer_id,provider_id,shipment_task_id,total_amount,base_price,reward_fee,platform_fee,
    currency,escrow_status,fulfillment_status,reservation_expires_at
  ) values (
    'SHIPMENT',s.sender_id,p_provider_id,s.id,v_base + s.reward_amount + v_fee,v_base,s.reward_amount,v_fee,
    s.currency,'PENDING','CREATED',now() + interval '15 minutes'
  ) returning * into v_order;

  insert into public.escrow_events(order_id,actor_id,event_type) values (v_order.id,p_provider_id,'ORDER_RESERVED');
  return v_order;
end;
$$;

create or replace function public.restore_order_inventory(p_order public.escrow_orders)
returns void
language plpgsql
security definer
set search_path = ''
as $$
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
  end if;
end;
$$;

create or replace function public.service_attach_payment_reference(
  p_order_id uuid,
  p_provider public.payment_provider,
  p_payment_ref text
)
returns public.escrow_orders
language plpgsql
security definer
set search_path = ''
as $$
declare v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found or v.escrow_status <> 'PENDING' then raise exception 'Pending order not found'; end if;
  update public.escrow_orders set payment_provider = p_provider, provider_checkout_ref = p_payment_ref
    where id = p_order_id returning * into v;
  return v;
end;
$$;

create or replace function public.service_cancel_pending_order(p_order_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found or v.escrow_status <> 'PENDING' then return; end if;
  perform public.restore_order_inventory(v);
  update public.escrow_orders set fulfillment_status = 'CANCELLED', reservation_expires_at = null where id = p_order_id;
  insert into public.escrow_events(order_id,event_type,metadata) values (p_order_id,'ORDER_CANCELLED',jsonb_build_object('reason',p_reason));
end;
$$;

create or replace function public.release_expired_reservations()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v public.escrow_orders; n integer := 0;
begin
  for v in select * from public.escrow_orders
    where escrow_status = 'PENDING' and reservation_expires_at < now()
    for update skip locked
  loop
    perform public.restore_order_inventory(v);
    update public.escrow_orders set fulfillment_status = 'CANCELLED', reservation_expires_at = null where id = v.id;
    insert into public.escrow_events(order_id,event_type,metadata) values (v.id,'RESERVATION_EXPIRED','{}'::jsonb);
    n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function public.service_lock_order_payment(
  p_order_id uuid,
  p_provider public.payment_provider,
  p_payment_ref text,
  p_handoff_otp text,
  p_qr_secret text
)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v.escrow_status = 'LOCKED' and v.payment_provider = p_provider and v.provider_payment_ref = p_payment_ref then return v; end if;
  if v.escrow_status <> 'PENDING' then raise exception 'Invalid escrow state'; end if;
  if v.reservation_expires_at is not null and v.reservation_expires_at < now() then raise exception 'Reservation expired'; end if;
  if v.payment_provider is not null and v.payment_provider <> p_provider then raise exception 'Payment provider mismatch'; end if;

  update public.escrow_orders set
    escrow_status = 'LOCKED',
    payment_provider = p_provider,
    provider_payment_ref = p_payment_ref,
    reservation_expires_at = null,
    handoff_otp_hash = crypt(p_handoff_otp, gen_salt('bf',12)),
    handoff_otp_expires_at = now() + interval '24 hours',
    handoff_attempts = 0,
    handoff_locked_until = null,
    tamper_qr_code = crypt(p_qr_secret, gen_salt('bf',12))
  where id = p_order_id returning * into v;
  insert into public.escrow_events(order_id,event_type,metadata)
  values (p_order_id,'FUNDS_LOCKED',jsonb_build_object('provider',p_provider,'payment_ref',p_payment_ref));
  return v;
end;
$$;

create or replace function public.service_set_handoff_secret(
  p_order_id uuid,
  p_handoff_otp text,
  p_qr_secret text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not exists (select 1 from public.escrow_orders where id = p_order_id and escrow_status = 'LOCKED') then
    raise exception 'Locked order not found';
  end if;
  update public.escrow_orders set
    handoff_otp_hash = crypt(p_handoff_otp, gen_salt('bf',12)),
    handoff_otp_expires_at = now() + interval '30 minutes',
    handoff_attempts = 0,
    handoff_locked_until = null,
    tamper_qr_code = crypt(p_qr_secret, gen_salt('bf',12))
  where id = p_order_id;
end;
$$;

create or replace function public.verify_handoff_otp(p_order_id uuid, p_otp text)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if auth.uid() <> v.provider_id and not public.is_admin() then raise exception 'Provider verification required'; end if;
  if v.escrow_status <> 'LOCKED' then raise exception 'Order is not locked'; end if;
  if v.fulfillment_status not in ('IN_TRANSIT','AWAITING_HANDOFF') then raise exception 'Order is not ready for handoff'; end if;
  if v.handoff_locked_until is not null and v.handoff_locked_until > now() then raise exception 'OTP verification temporarily locked'; end if;
  if v.handoff_otp_expires_at is null or v.handoff_otp_expires_at < now() then raise exception 'OTP expired'; end if;

  if v.handoff_otp_hash is null or crypt(p_otp, v.handoff_otp_hash) <> v.handoff_otp_hash then
    update public.escrow_orders set
      handoff_attempts = handoff_attempts + 1,
      handoff_locked_until = case when handoff_attempts + 1 >= 5 then now() + interval '15 minutes' else handoff_locked_until end
    where id = p_order_id;
    raise exception 'Invalid OTP';
  end if;

  update public.escrow_orders set fulfillment_status = 'VERIFIED', handoff_attempts = 0, handoff_locked_until = null
    where id = p_order_id returning * into v;
  insert into public.escrow_events(order_id,actor_id,event_type) values (p_order_id,auth.uid(),'HANDOFF_VERIFIED');
  return v;
end;
$$;

create or replace function public.verify_handoff_qr(p_order_id uuid, p_qr_secret text)
returns public.escrow_orders
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if auth.uid() <> v.provider_id and not public.is_admin() then raise exception 'Provider verification required'; end if;
  if v.escrow_status <> 'LOCKED' or v.fulfillment_status not in ('IN_TRANSIT','AWAITING_HANDOFF') then raise exception 'Order is not ready'; end if;
  if v.tamper_qr_code is null or crypt(p_qr_secret, v.tamper_qr_code) <> v.tamper_qr_code then raise exception 'Invalid QR token'; end if;
  update public.escrow_orders set fulfillment_status = 'VERIFIED', tamper_qr_code = null where id = p_order_id returning * into v;
  insert into public.escrow_events(order_id,actor_id,event_type) values (p_order_id,auth.uid(),'HANDOFF_QR_VERIFIED');
  return v;
end;
$$;

create or replace function public.service_mark_order_released(p_order_id uuid, p_transfer_ref text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v.escrow_status = 'RELEASED' then return; end if;
  if v.escrow_status <> 'LOCKED' or v.fulfillment_status <> 'VERIFIED' then raise exception 'Order cannot be released'; end if;

  update public.escrow_orders set escrow_status = 'RELEASED', fulfillment_status = 'COMPLETED', payout_transfer_ref = p_transfer_ref where id = p_order_id;
  if v.order_type = 'MARKETPLACE' then update public.marketplace_items set status = 'SOLD' where id = v.marketplace_item_id; end if;
  if v.order_type = 'SHIPMENT' then update public.shipment_tasks set status = 'DELIVERED' where id = v.shipment_task_id; end if;
  insert into public.escrow_events(order_id,event_type,metadata) values (p_order_id,'FUNDS_RELEASED',jsonb_build_object('transfer_ref',p_transfer_ref));
end;
$$;

create or replace function public.service_mark_order_refunded(p_order_id uuid, p_refund_ref text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v public.escrow_orders;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v.escrow_status = 'REFUNDED' then return; end if;
  if v.escrow_status = 'RELEASED' then raise exception 'Released order cannot be directly refunded'; end if;
  perform public.restore_order_inventory(v);
  update public.escrow_orders set escrow_status = 'REFUNDED', fulfillment_status = 'CANCELLED', refund_ref = p_refund_ref where id = p_order_id;
  insert into public.escrow_events(order_id,event_type,metadata) values (p_order_id,'FUNDS_REFUNDED',jsonb_build_object('refund_ref',p_refund_ref));
end;
$$;

create or replace function public.service_upsert_trip_snapshot(
  p_trip_id uuid,
  p_driver_id uuid,
  p_lon double precision,
  p_lat double precision,
  p_heading numeric,
  p_speed_mps numeric,
  p_recorded_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if not exists (select 1 from public.trip_routes where id = p_trip_id and driver_id = p_driver_id and status = 'IN_PROGRESS') then
    raise exception 'Active driver/trip mismatch';
  end if;
  insert into public.trip_live_state(trip_id,driver_id,location_geo,heading,speed_mps,recorded_at)
  values (p_trip_id,p_driver_id,ST_SetSRID(ST_Point(p_lon,p_lat),4326)::geography,p_heading,p_speed_mps,p_recorded_at)
  on conflict (trip_id) do update set
    location_geo = excluded.location_geo,
    heading = excluded.heading,
    speed_mps = excluded.speed_mps,
    recorded_at = excluded.recorded_at,
    updated_at = now()
  where public.trip_live_state.recorded_at <= excluded.recorded_at;
end;
$$;

revoke execute on function public.reserve_ride_order(uuid,uuid,integer,integer) from public, anon, authenticated;
revoke execute on function public.reserve_marketplace_order(uuid,uuid,integer) from public, anon, authenticated;
revoke execute on function public.reserve_shipment_order(uuid,uuid,uuid,integer) from public, anon, authenticated;
grant execute on function public.reserve_ride_order(uuid,uuid,integer,integer) to service_role;
grant execute on function public.reserve_marketplace_order(uuid,uuid,integer) to service_role;
grant execute on function public.reserve_shipment_order(uuid,uuid,uuid,integer) to service_role;

revoke execute on function public.restore_order_inventory(public.escrow_orders) from public, anon, authenticated;
revoke execute on function public.service_attach_payment_reference(uuid,public.payment_provider,text) from public, anon, authenticated;
revoke execute on function public.service_cancel_pending_order(uuid,text) from public, anon, authenticated;
revoke execute on function public.release_expired_reservations() from public, anon, authenticated;
revoke execute on function public.service_lock_order_payment(uuid,public.payment_provider,text,text,text) from public, anon, authenticated;
revoke execute on function public.service_set_handoff_secret(uuid,text,text) from public, anon, authenticated;
revoke execute on function public.service_mark_order_released(uuid,text) from public, anon, authenticated;
revoke execute on function public.service_mark_order_refunded(uuid,text) from public, anon, authenticated;
revoke execute on function public.service_upsert_trip_snapshot(uuid,uuid,double precision,double precision,numeric,numeric,timestamptz) from public, anon, authenticated;

grant execute on function public.service_attach_payment_reference(uuid,public.payment_provider,text) to service_role;
grant execute on function public.service_cancel_pending_order(uuid,text) to service_role;
grant execute on function public.release_expired_reservations() to service_role;
grant execute on function public.service_lock_order_payment(uuid,public.payment_provider,text,text,text) to service_role;
grant execute on function public.service_set_handoff_secret(uuid,text,text) to service_role;
grant execute on function public.service_mark_order_released(uuid,text) to service_role;
grant execute on function public.service_mark_order_refunded(uuid,text) to service_role;
grant execute on function public.service_upsert_trip_snapshot(uuid,uuid,double precision,double precision,numeric,numeric,timestamptz) to service_role;

revoke execute on function public.verify_handoff_qr(uuid,text) from public;
grant execute on function public.verify_handoff_qr(uuid,text) to authenticated;

-- Privacy-safe delivery feed: exact coordinates remain protected by shipment RLS.
create or replace function public.list_open_shipments(p_limit integer default 50)
returns table (
  shipment_task_id uuid,
  item_type public.shipment_item_type,
  weight_kg numeric,
  declared_value numeric,
  reward_amount numeric,
  currency char(3),
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.item_type, s.weight_kg, s.declared_value, s.reward_amount, s.currency, s.created_at
  from public.shipment_tasks s
  where s.status = 'OPEN' and s.inspection_status = 'APPROVED'
  order by s.created_at desc
  limit least(greatest(p_limit,1),100);
$$;
revoke execute on function public.list_open_shipments(integer) from public;
grant execute on function public.list_open_shipments(integer) to authenticated;

alter table public.shipment_tasks
  add column if not exists pickup_name text,
  add column if not exists drop_name text;

create or replace function public.create_shipment_task(
  p_item_type public.shipment_item_type,
  p_product_url text,
  p_declared_value numeric,
  p_reward_amount numeric,
  p_currency char(3),
  p_pickup_name text,
  p_pickup_lon double precision,
  p_pickup_lat double precision,
  p_drop_name text,
  p_drop_lon double precision,
  p_drop_lat double precision,
  p_weight_kg numeric
)
returns public.shipment_tasks
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user uuid := auth.uid();
  v_result public.shipment_tasks;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_item_type = 'URL_PURCHASE' then
    if p_product_url is null or p_product_url !~* '^https://[^ ]+$' then raise exception 'A valid HTTPS product URL is required'; end if;
    if not exists (select 1 from public.users u where u.id = v_user and u.ekyc_tier in ('TIER_2','TIER_3')) then
      raise exception 'Buy-for-Me requires Tier 2 or Tier 3 eKYC';
    end if;
  end if;
  insert into public.shipment_tasks(
    sender_id,item_type,product_url,declared_value,reward_amount,currency,
    pickup_name,pickup_geo,drop_name,drop_geo,weight_kg,status
  ) values (
    v_user,p_item_type,p_product_url,p_declared_value,p_reward_amount,upper(p_currency),
    p_pickup_name,ST_SetSRID(ST_Point(p_pickup_lon,p_pickup_lat),4326)::geography,
    p_drop_name,ST_SetSRID(ST_Point(p_drop_lon,p_drop_lat),4326)::geography,p_weight_kg,'DRAFT'
  ) returning * into v_result;
  return v_result;
end;
$$;
revoke execute on function public.create_shipment_task(public.shipment_item_type,text,numeric,numeric,char,text,double precision,double precision,text,double precision,double precision,numeric) from public;
grant execute on function public.create_shipment_task(public.shipment_item_type,text,numeric,numeric,char,text,double precision,double precision,text,double precision,double precision,numeric) to authenticated;

drop function if exists public.list_open_shipments(integer);

create or replace function public.list_open_shipments(p_limit integer default 50)
returns table (
  shipment_task_id uuid,
  item_type public.shipment_item_type,
  pickup_name text,
  drop_name text,
  weight_kg numeric,
  declared_value numeric,
  reward_amount numeric,
  currency char(3),
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.item_type, s.pickup_name, s.drop_name, s.weight_kg, s.declared_value, s.reward_amount, s.currency, s.created_at
  from public.shipment_tasks s
  where s.status = 'OPEN' and s.inspection_status = 'APPROVED'
  order by s.created_at desc
  limit least(greatest(p_limit,1),100);
$$;

create or replace function public.safe_zones_nearby(
  p_lon double precision,
  p_lat double precision,
  p_radius_m integer default 10000
)
returns table(id uuid, name text, type public.safe_zone_type, address text, lat double precision, lon double precision, distance_m double precision)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with q as (select ST_SetSRID(ST_Point(p_lon,p_lat),4326)::geography as g)
  select z.id,z.name,z.type,z.address,
    ST_Y(z.location_geo::geometry) as lat,
    ST_X(z.location_geo::geometry) as lon,
    ST_Distance(z.location_geo,q.g) as distance_m
  from public.safe_zones z cross join q
  where z.active and ST_DWithin(z.location_geo,q.g,least(greatest(p_radius_m,100),50000))
  order by distance_m
  limit 100;
$$;
revoke execute on function public.safe_zones_nearby(double precision,double precision,integer) from public;
grant execute on function public.safe_zones_nearby(double precision,double precision,integer) to authenticated;

create or replace function public.parcel_tier_allows_weight(p_tier public.parcel_capacity_tier, p_weight_kg numeric)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_tier
    when 'ENVELOPE' then p_weight_kg <= 1.0
    when 'MEDIUM' then p_weight_kg <= 5.0
    when 'LUGGAGE' then p_weight_kg <= 25.0
    else false
  end;
$$;

drop function if exists public.reserve_shipment_order(uuid,uuid,uuid,integer);
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
set search_path = public, extensions
as $$
declare
  s public.shipment_tasks;
  t public.trip_routes;
  v_pickup_frac double precision;
  v_drop_frac double precision;
  v_base numeric(12,2);
  v_fee numeric(12,2);
  v_order public.escrow_orders;
begin
  if p_actor_id <> p_provider_id then raise exception 'Carrier must claim shipment personally'; end if;
  if p_platform_fee_bps < 0 or p_platform_fee_bps > 3000 then raise exception 'Invalid platform fee'; end if;
  if p_max_detour_meters < 1 or p_max_detour_meters > 50000 then raise exception 'Invalid detour limit'; end if;
  if not exists (select 1 from public.users u where u.id = p_provider_id and u.ekyc_tier in ('TIER_2','TIER_3')) then
    raise exception 'Carrier requires Tier 2 or Tier 3 eKYC';
  end if;

  select * into t from public.trip_routes where id = p_trip_id for update;
  if not found or t.driver_id <> p_provider_id or t.status <> 'SCHEDULED' or t.departure_time <= now() then raise exception 'Eligible carrier route not found'; end if;
  if t.parcel_capacity_tier = 'NONE' then raise exception 'Route has no parcel capacity'; end if;

  select * into s from public.shipment_tasks where id = p_shipment_id for update;
  if not found or s.status <> 'OPEN' then raise exception 'Shipment unavailable'; end if;
  if s.inspection_status <> 'APPROVED' then raise exception 'Shipment has not passed HopShield parcel inspection'; end if;
  if s.sender_id = p_provider_id then raise exception 'Sender cannot carry own shipment order'; end if;
  if not public.parcel_tier_allows_weight(t.parcel_capacity_tier, s.weight_kg) then raise exception 'Shipment exceeds route cargo tier'; end if;
  if not ST_DWithin(s.pickup_geo,t.route_polyline,p_max_detour_meters) or not ST_DWithin(s.drop_geo,t.route_polyline,p_max_detour_meters) then
    raise exception 'Shipment is outside route corridor';
  end if;
  v_pickup_frac := ST_LineLocatePoint(t.route_polyline::geometry,s.pickup_geo::geometry);
  v_drop_frac := ST_LineLocatePoint(t.route_polyline::geometry,s.drop_geo::geometry);
  if v_pickup_frac >= v_drop_frac then raise exception 'Shipment direction does not match route'; end if;

  v_base := case when s.item_type = 'URL_PURCHASE' then s.declared_value else 0 end;
  v_fee := round((v_base + s.reward_amount) * p_platform_fee_bps / 10000.0, 2);
  update public.shipment_tasks set status = 'MATCHED' where id = s.id;
  insert into public.escrow_orders(
    order_type,buyer_id,provider_id,trip_id,shipment_task_id,total_amount,base_price,reward_fee,platform_fee,
    currency,escrow_status,fulfillment_status,reservation_expires_at
  ) values (
    'SHIPMENT',s.sender_id,p_provider_id,t.id,s.id,v_base + s.reward_amount + v_fee,v_base,s.reward_amount,v_fee,
    s.currency,'PENDING','CREATED',now() + interval '30 minutes'
  ) returning * into v_order;
  insert into public.escrow_events(order_id,actor_id,event_type,metadata)
  values (v_order.id,p_provider_id,'ORDER_RESERVED',jsonb_build_object('trip_id',t.id,'max_detour_meters',p_max_detour_meters,'payer_id',s.sender_id));
  return v_order;
end;
$$;
revoke execute on function public.reserve_shipment_order(uuid,uuid,uuid,uuid,integer,integer) from public, anon, authenticated;
grant execute on function public.reserve_shipment_order(uuid,uuid,uuid,uuid,integer,integer) to service_role;

create or replace function public.get_trip_tracking_snapshot(p_trip_id uuid)
returns table(lat double precision, lon double precision, heading numeric, speed_mps numeric, recorded_at timestamptz)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select ST_Y(s.location_geo::geometry), ST_X(s.location_geo::geometry), s.heading, s.speed_mps, s.recorded_at
  from public.trip_live_state s
  where s.trip_id = p_trip_id and public.is_trip_party(p_trip_id);
$$;
revoke execute on function public.get_trip_tracking_snapshot(uuid) from public;
grant execute on function public.get_trip_tracking_snapshot(uuid) to authenticated;

-- HopShield parcel inspection is recorded by the trusted backend only.
-- AI can approve obvious benign content or hold a task for review; the raw inspection image is not stored here.
create or replace function public.service_record_parcel_inspection(
  p_shipment_task_id uuid,
  p_submitted_by uuid,
  p_decision public.shipment_inspection_status,
  p_confidence numeric,
  p_content_mismatch boolean,
  p_prohibited_categories text[],
  p_rationale text,
  p_model text
)
returns public.shipment_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.shipment_tasks;
begin
  if p_decision not in ('APPROVED','REVIEW','BLOCKED') then raise exception 'Invalid inspection decision'; end if;
  if p_confidence < 0 or p_confidence > 1 then raise exception 'Invalid confidence'; end if;

  select * into s from public.shipment_tasks where id = p_shipment_task_id for update;
  if not found then raise exception 'Shipment not found'; end if;
  if s.sender_id <> p_submitted_by then raise exception 'Only the sender can submit the pre-publish inspection'; end if;
  if s.status not in ('DRAFT','OPEN') then raise exception 'Shipment can no longer be inspected for publishing'; end if;

  insert into public.parcel_inspections(
    shipment_task_id,submitted_by,decision,confidence,content_mismatch,
    prohibited_categories,rationale,model
  ) values (
    p_shipment_task_id,p_submitted_by,p_decision,p_confidence,p_content_mismatch,
    coalesce(p_prohibited_categories,'{}'::text[]),left(p_rationale,2000),left(p_model,120)
  );

  update public.shipment_tasks
  set inspection_status = p_decision,
      status = case when p_decision = 'APPROVED' then 'OPEN'::public.shipment_status else 'DRAFT'::public.shipment_status end
  where id = p_shipment_task_id
  returning * into s;

  return s;
end;
$$;

revoke execute on function public.service_record_parcel_inspection(uuid,uuid,public.shipment_inspection_status,numeric,boolean,text[],text,text)
  from public, anon, authenticated;
grant execute on function public.service_record_parcel_inspection(uuid,uuid,public.shipment_inspection_status,numeric,boolean,text[],text,text)
  to service_role;

-- Client hardening: shipment creation and safety-state mutation are RPC-only.
revoke insert, update on public.shipment_tasks from authenticated;

create or replace function public.cancel_shipment_task(p_shipment_task_id uuid)
returns public.shipment_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.shipment_tasks;
begin
  select * into s from public.shipment_tasks where id = p_shipment_task_id for update;
  if not found then raise exception 'Shipment not found'; end if;
  if s.sender_id <> auth.uid() then raise exception 'Sender only'; end if;
  if s.status not in ('DRAFT','OPEN') then raise exception 'Matched/in-transit shipment cannot be cancelled here'; end if;
  update public.shipment_tasks set status = 'CANCELLED' where id = p_shipment_task_id returning * into s;
  return s;
end;
$$;
revoke execute on function public.cancel_shipment_task(uuid) from public;
grant execute on function public.cancel_shipment_task(uuid) to authenticated;

create or replace function public.admin_update_user_verification(
  p_user_id uuid,
  p_ekyc_tier public.ekyc_tier,
  p_ladies_only_eligible boolean,
  p_trust_score numeric
)
returns public.users
language plpgsql
security definer
set search_path = ''
as $$
declare u public.users;
begin
  if not public.is_admin() then raise exception 'Admin required'; end if;
  if p_trust_score < 0 or p_trust_score > 100 then raise exception 'Invalid trust score'; end if;
  update public.users
  set ekyc_tier = p_ekyc_tier,
      is_female = p_ladies_only_eligible,
      trust_score = p_trust_score
  where id = p_user_id
  returning * into u;
  if not found then raise exception 'User not found'; end if;
  return u;
end;
$$;
revoke execute on function public.admin_update_user_verification(uuid,public.ekyc_tier,boolean,numeric) from public;
grant execute on function public.admin_update_user_verification(uuid,public.ekyc_tier,boolean,numeric) to authenticated;

create or replace function public.admin_resolve_parcel_inspection(
  p_shipment_task_id uuid,
  p_decision public.shipment_inspection_status,
  p_note text
)
returns public.shipment_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare s public.shipment_tasks;
begin
  if not public.is_admin() then raise exception 'Admin required'; end if;
  if p_decision not in ('APPROVED','REVIEW','BLOCKED') then raise exception 'Invalid review decision'; end if;
  select * into s from public.shipment_tasks where id = p_shipment_task_id for update;
  if not found then raise exception 'Shipment not found'; end if;
  if s.status not in ('DRAFT','OPEN') then raise exception 'Shipment is no longer reviewable'; end if;

  insert into public.parcel_inspections(
    shipment_task_id,submitted_by,decision,confidence,content_mismatch,prohibited_categories,rationale,model
  ) values (
    s.id,auth.uid(),p_decision,1,false,'{}'::text[],left(coalesce(p_note,'Human admin review'),2000),'HUMAN_ADMIN'
  );

  update public.shipment_tasks
  set inspection_status = p_decision,
      status = case when p_decision = 'APPROVED' then 'OPEN'::public.shipment_status else 'DRAFT'::public.shipment_status end
  where id = s.id returning * into s;
  return s;
end;
$$;
revoke execute on function public.admin_resolve_parcel_inspection(uuid,public.shipment_inspection_status,text) from public;
grant execute on function public.admin_resolve_parcel_inspection(uuid,public.shipment_inspection_status,text) to authenticated;
