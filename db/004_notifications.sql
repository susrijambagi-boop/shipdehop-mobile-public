-- Phase 13: Additive migration for Real Notifications & Activity Events (Full Syntax Audited, Signature Secured & Impersonation Guarded)

-- 1. Create public.notifications table with check constraints and idempotency key
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  type text not null check (type in (
    'RIDE_MATCHED',
    'RIDER_RESERVED',
    'PARCEL_RESERVED',
    'DELIVERY_STARTED',
    'HANDOFF_VERIFIED',
    'PAYMENT_SECURED',
    'PAYMENT_RELEASED',
    'DELIVERY_COMPLETED',
    'ORDER_CANCELLED'
  )),
  title text not null,
  body text not null,
  entity_type text not null check (entity_type in ('ORDER', 'RIDE_REQUEST', 'TRIP')),
  entity_id uuid not null,
  order_id uuid references public.escrow_orders(id) on delete set null,
  trip_id uuid references public.trip_routes(id) on delete set null,
  ride_request_id uuid references public.ride_requests(id) on delete set null,
  read_at timestamptz default null,
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);

-- Index for fast user feed lookups
create index if not exists idx_notifications_user_id_created_at on public.notifications(user_id, created_at desc);
create index if not exists idx_notifications_user_id_read_at on public.notifications(user_id, read_at);

-- 2. RLS & Strict Security Policies on public.notifications
alter table public.notifications enable row level security;

-- Drop any prior policies
drop policy if exists "Users can view own notifications" on public.notifications;

create policy "Users can view own notifications"
  on public.notifications
  for select
  using (user_id = auth.uid());

-- Explicit privilege revocation for client security
revoke insert, update, delete on public.notifications from public, anon, authenticated;
grant select on public.notifications to authenticated;
grant all on public.notifications to service_role;

-- 3. Helper function for creating notifications safely with deterministic idempotency
create or replace function public.create_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_entity_type text,
  p_entity_id uuid,
  p_idempotency_key text,
  p_order_id uuid default null,
  p_trip_id uuid default null,
  p_ride_request_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null or p_idempotency_key is null then
    raise exception 'Invalid notification parameters: user_id and idempotency_key are required';
  end if;

  insert into public.notifications (
    user_id, type, title, body, entity_type, entity_id,
    order_id, trip_id, ride_request_id, idempotency_key
  ) values (
    p_user_id, p_type, p_title, p_body, p_entity_type, p_entity_id,
    p_order_id, p_trip_id, p_ride_request_id, p_idempotency_key
  )
  on conflict (idempotency_key) do nothing;
end;
$$;

revoke execute on function public.create_notification(uuid, text, text, text, text, uuid, text, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.create_notification(uuid, text, text, text, text, uuid, text, uuid, uuid, uuid) to service_role;

-- 4. Controlled RPCs for marking notifications read
create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.notifications
  set read_at = now()
  where id = p_notification_id
    and user_id = auth.uid()
    and read_at is null;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.notifications
  set read_at = now()
  where user_id = auth.uid()
    and read_at is null;
end;
$$;

revoke execute on function public.mark_notification_read(uuid) from public, anon;
grant execute on function public.mark_notification_read(uuid) to authenticated, service_role;

revoke execute on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.mark_all_notifications_read() to authenticated, service_role;

-- 5. Update accept_ride_request_and_reserve_order (Preserving Phase 11.4 logic, fixing column names & actor rule)
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

  -- Dispatch notification to Pooler ONLY (Driver is the actor performing the match)
  perform public.create_notification(
    req.requester_id,
    'RIDE_MATCHED',
    'Your ride request was matched',
    'Driver matched your ride from ' || req.pickup_name || ' to ' || req.drop_name || '.',
    'ORDER',
    v_order.id,
    'ride_match:' || req.id || ':' || req.requester_id,
    v_order.id,
    t.id,
    req.id
  );

  return v_order;
end;
$$;

-- 6. Update reserve_ride_order for direct CarPool seat booking (Strict auth.uid anti-impersonation guard)
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
  v_actor_id uuid;
  v_base numeric(12,2);
  v_fee numeric(12,2);
  v_order public.escrow_orders;
begin
  if auth.role() = 'authenticated' then
    if auth.uid() is null then raise exception 'Authentication required'; end if;
    if p_actor_id is not null and p_actor_id <> auth.uid() then
      raise exception 'Cannot impersonate another user';
    end if;
    v_actor_id := auth.uid();
  else
    v_actor_id := p_actor_id;
  end if;

  if v_actor_id is null or p_quantity < 1 or p_quantity > 8 then raise exception 'Invalid reservation'; end if;
  if p_platform_fee_bps < 0 or p_platform_fee_bps > 3000 then raise exception 'Invalid platform fee'; end if;

  select * into t from public.trip_routes where id = p_trip_id for update;
  if not found or t.status <> 'SCHEDULED' or t.departure_time <= now() then raise exception 'Trip unavailable'; end if;
  if t.driver_id = v_actor_id then raise exception 'Driver cannot book own trip'; end if;
  if t.available_seats < p_quantity then raise exception 'Insufficient seats'; end if;
  if t.price_per_seat > t.cost_share_cap_per_seat then raise exception 'Trip violates cost-sharing cap'; end if;
  if t.ladies_only and not exists (
    select 1 from public.users u where u.id = v_actor_id and u.is_female is true and u.ekyc_tier in ('TIER_2','TIER_3')
  ) then raise exception 'This ride requires verified Ladies Only eligibility'; end if;

  v_base := round(t.price_per_seat * p_quantity, 2);
  v_fee := round(v_base * p_platform_fee_bps / 10000.0, 2);

  update public.trip_routes set available_seats = available_seats - p_quantity where id = t.id;

  insert into public.escrow_orders(
    order_type,buyer_id,provider_id,trip_id,quantity,total_amount,base_price,reward_fee,platform_fee,
    currency,escrow_status,fulfillment_status,reservation_expires_at
  ) values (
    'RIDE',v_actor_id,t.driver_id,t.id,p_quantity,v_base + v_fee,v_base,0,v_fee,
    t.currency,'PENDING','CREATED',now() + interval '15 minutes'
  ) returning * into v_order;

  insert into public.escrow_events(order_id,actor_id,event_type,metadata)
  values (v_order.id,v_actor_id,'ORDER_RESERVED',jsonb_build_object('quantity',p_quantity));

  -- Dispatch notification to Driver ONLY (Pooler is the actor booking the seat)
  perform public.create_notification(
    t.driver_id,
    'RIDER_RESERVED',
    'New Pooler booking',
    'A Pooler reserved ' || p_quantity || ' seat(s) on your journey.',
    'ORDER',
    v_order.id,
    'carpool_reserved:' || v_order.id || ':' || t.driver_id,
    v_order.id,
    t.id,
    null
  );

  return v_order;
end;
$$;

-- 7. Update reserve_shipment_order (Preserving Phase 12 PostGIS & parcel capacity logic)
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
  if v_req_units <= 0 then raise exception 'Invalid required parcel capacity units'; end if;

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

  -- Dispatch notification to Shipster ONLY (Hopster is the actor claiming the shipment)
  perform public.create_notification(
    s.sender_id,
    'PARCEL_RESERVED',
    'A Hopster matched your parcel',
    'A Hopster reserved your parcel from ' || s.pickup_name || ' to ' || s.drop_name || '.',
    'ORDER',
    v_order.id,
    'parcel_reserved:' || v_order.id || ':' || s.sender_id,
    v_order.id,
    t.id,
    null
  );

  return v_order;
end;
$$;

revoke execute on function public.accept_ride_request_and_reserve_order(uuid,uuid,int) from public, anon;
grant execute on function public.accept_ride_request_and_reserve_order(uuid,uuid,int) to authenticated, service_role;

revoke execute on function public.reserve_ride_order(uuid,uuid,int,int) from public, anon;
grant execute on function public.reserve_ride_order(uuid,uuid,int,int) to authenticated, service_role;

revoke execute on function public.reserve_shipment_order(uuid,uuid,uuid,uuid,integer,integer) from public, anon;
grant execute on function public.reserve_shipment_order(uuid,uuid,uuid,uuid,integer,integer) to authenticated, service_role;
