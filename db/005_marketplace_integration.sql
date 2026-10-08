-- Phase 14: Additive migration for Marketplace End-to-End Integration

-- 1. Alter cost_sharing_policies table with additive marketplace_platform_fee_bps column
alter table public.cost_sharing_policies
  add column if not exists marketplace_platform_fee_bps integer check (marketplace_platform_fee_bps >= 0 and marketplace_platform_fee_bps <= 3000);

-- Explicitly populate QA marketplace_platform_fee_bps ONLY (no fallback or invented rates for other jurisdictions)
update public.cost_sharing_policies
set marketplace_platform_fee_bps = 600
where jurisdiction_code = 'QA' and marketplace_platform_fee_bps is null;

-- 2. Alter marketplace_items table with stock bounds, location_name, jurisdiction_code, ship_eligible, and images (NO DEFAULTS)
alter table public.marketplace_items
  add column if not exists quantity integer not null default 1 check (quantity >= 1),
  add column if not exists available_quantity integer not null default 1,
  add column if not exists location_name text not null check (char_length(location_name) >= 2),
  add column if not exists jurisdiction_code varchar(10) not null check (jurisdiction_code in ('QA', 'IN', 'AE')),
  add column if not exists ship_eligible boolean not null default false,
  add column if not exists images text[] default array[]::text[];

-- Add inventory bound constraint safely
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'check_inventory_bounds'
  ) then
    alter table public.marketplace_items
      add constraint check_inventory_bounds check (available_quantity >= 0 and available_quantity <= quantity);
  end if;
end $$;

-- 3. Create marketplace_purchases table
create table if not exists public.marketplace_purchases (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.marketplace_items(id) on delete restrict,
  buyer_id uuid not null references public.users(id) on delete cascade,
  seller_id uuid not null references public.users(id) on delete cascade,
  quantity integer not null check (quantity >= 1),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  subtotal numeric(12,2) not null check (subtotal >= 0),
  fulfillment_mode text not null check (fulfillment_mode in ('LOCAL_HANDOFF', 'PARCELPOOL')),
  delivery_reward numeric(12,2) not null default 0 check (delivery_reward >= 0),
  platform_fee numeric(12,2) not null default 0 check (platform_fee >= 0),
  total_amount numeric(12,2) not null check (total_amount >= 0),
  currency char(3) not null,
  jurisdiction_code varchar(10) not null,
  status text not null default 'PENDING' check (status in (
    'PENDING', 'PAYMENT_LOCKED', 'HOPSTER_MATCHED', 'AWAITING_HANDOFF', 'IN_TRANSIT', 'COMPLETED', 'CANCELLED', 'REFUNDED'
  )),
  escrow_order_id uuid references public.escrow_orders(id) on delete set null,
  idempotency_key text not null unique,
  inventory_restored boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 4. Create escrow_payout_allocations table for multi-recipient split payouts (Seller proceeds + Hopster reward)
create table if not exists public.escrow_payout_allocations (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.escrow_orders(id) on delete cascade,
  recipient_id uuid not null references public.users(id) on delete cascade,
  allocation_type text not null check (allocation_type in ('SELLER_PROCEEDS', 'HOPSTER_REWARD')),
  amount numeric(12,2) not null check (amount >= 0),
  currency char(3) not null,
  status text not null default 'PENDING' check (status in ('PENDING', 'RELEASED', 'CANCELLED', 'REFUNDED')),
  transfer_ref text,
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 5. Alter shipment_tasks table with single authoritative FK link and human-readable place names
alter table public.shipment_tasks
  add column if not exists marketplace_purchase_id uuid unique references public.marketplace_purchases(id) on delete set null,
  add column if not exists pickup_name text,
  add column if not exists drop_name text;

-- 6. Update notifications check constraint safely preserving all existing types
do $$
begin
  if exists (
    select 1 from pg_constraint where conname = 'notifications_type_check'
  ) then
    alter table public.notifications drop constraint notifications_type_check;
  end if;

  alter table public.notifications add constraint notifications_type_check check (type in (
    'RIDE_MATCHED',
    'RIDER_RESERVED',
    'PARCEL_RESERVED',
    'DELIVERY_STARTED',
    'HANDOFF_VERIFIED',
    'PAYMENT_SECURED',
    'PAYMENT_RELEASED',
    'DELIVERY_COMPLETED',
    'ORDER_CANCELLED',
    'MARKETPLACE_PURCHASED'
  ));
end $$;

-- 6b. Update escrow_orders type check constraint safely to allow carrier trip match on MARKETPLACE orders
do $$
declare
  r record;
begin
  for r in (
    select conname
    from pg_constraint
    where conrelid = 'public.escrow_orders'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%MARKETPLACE%'
  ) loop
    execute 'alter table public.escrow_orders drop constraint ' || quote_ident(r.conname);
  end loop;

  if not exists (select 1 from pg_constraint where conname = 'escrow_orders_type_check') then
    alter table public.escrow_orders add constraint escrow_orders_type_check check (
      (order_type = 'RIDE' and trip_id is not null and marketplace_item_id is null and shipment_task_id is null) or
      (order_type = 'MARKETPLACE' and marketplace_item_id is not null and shipment_task_id is null) or
      (order_type = 'SHIPMENT' and marketplace_item_id is null and shipment_task_id is not null)
    );
  end if;
end $$;

-- 7. RLS Policies on marketplace_purchases and escrow_payout_allocations
alter table public.marketplace_purchases enable row level security;
alter table public.escrow_payout_allocations enable row level security;

drop policy if exists "Users can view own marketplace purchases" on public.marketplace_purchases;
create policy "Users can view own marketplace purchases"
  on public.marketplace_purchases for select to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid());

drop policy if exists "Users can view own escrow payout allocations" on public.escrow_payout_allocations;
create policy "Users can view own escrow payout allocations"
  on public.escrow_payout_allocations for select to authenticated
  using (recipient_id = auth.uid());

revoke all on public.marketplace_purchases from anon, authenticated;
grant select on public.marketplace_purchases to authenticated;

revoke all on public.escrow_payout_allocations from anon, authenticated;
grant select on public.escrow_payout_allocations to authenticated;

-- 8. Trigger to block direct client table mutation of quantity, available_quantity, or inventory status on marketplace_items
create or replace function public.prevent_direct_inventory_mutation()
returns trigger
language plpgsql
as $$
begin
  -- Check transaction session context variable set exclusively by trusted RPCs
  if current_setting('shipdehop.allow_inventory_mutation', true) = 'true' then
    return new;
  end if;

  -- Block direct table UPDATE from modifying quantity, available_quantity, or inventory status directly
  if (old.quantity <> new.quantity) then
    raise exception 'Direct client mutation of listing quantity is forbidden. Use update_marketplace_listing_stock RPC.';
  end if;

  if (old.available_quantity <> new.available_quantity) then
    raise exception 'Direct client mutation of available_quantity is forbidden. Use trusted RPCs.';
  end if;

  if (old.status <> new.status and (old.status in ('LISTED', 'SOLD') or new.status in ('LISTED', 'SOLD'))) then
    raise exception 'Direct client mutation of inventory status is forbidden. Use trusted RPCs.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_direct_inventory_mutation on public.marketplace_items;
create trigger trg_prevent_direct_inventory_mutation
  before update on public.marketplace_items
  for each row
  execute function public.prevent_direct_inventory_mutation();

-- 9. Seller Stock Ceiling Mutation RPC
create or replace function public.update_marketplace_listing_stock(
  p_actor_id uuid,
  p_item_id uuid,
  p_new_quantity integer
)
returns public.marketplace_items
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
declare
  i public.marketplace_items;
  v_committed integer;
  v_new_available integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_actor_id <> auth.uid() then
    raise exception 'Cannot impersonate another user';
  end if;

  if p_new_quantity < 1 then
    raise exception 'Quantity must be at least 1';
  end if;

  select * into i from public.marketplace_items where id = p_item_id for update;
  if not found then
    raise exception 'Marketplace listing not found';
  end if;

  if i.seller_id <> p_actor_id then
    raise exception 'Only the seller can update listing stock';
  end if;

  v_committed := i.quantity - i.available_quantity;
  if p_new_quantity < v_committed then
    raise exception 'Cannot reduce quantity below committed reserved stock (% units reserved)', v_committed;
  end if;

  v_new_available := p_new_quantity - v_committed;

  -- Enable session variable for inventory mutation
  perform set_config('shipdehop.allow_inventory_mutation', 'true', true);

  update public.marketplace_items
  set quantity = p_new_quantity,
      available_quantity = v_new_available,
      status = (case when v_new_available > 0 and status = 'SOLD' then 'LISTED'::public.marketplace_item_status else status end),
      updated_at = now()
  where id = i.id
  returning * into i;

  return i;
end;
$$;

-- 10. Trigger to synchronize escrow_orders lifecycle events to marketplace_purchases status ONLY (No payout release or physical restoration)
create or replace function public.trg_sync_marketplace_purchase_status()
returns trigger
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
begin
  if NEW.order_type = 'MARKETPLACE' then
    if NEW.escrow_status = 'LOCKED' and NEW.fulfillment_status = 'CREATED' then
      update public.marketplace_purchases
      set status = 'PAYMENT_LOCKED', updated_at = now()
      where escrow_order_id = NEW.id and status = 'PENDING';
    elsif NEW.fulfillment_status in ('VERIFIED', 'COMPLETED') or NEW.escrow_status = 'RELEASED' then
      update public.marketplace_purchases
      set status = 'COMPLETED', updated_at = now()
      where escrow_order_id = NEW.id and status <> 'COMPLETED';
    elsif NEW.escrow_status = 'REFUNDED' or NEW.fulfillment_status = 'CANCELLED' then
      update public.marketplace_purchases
      set status = 'CANCELLED', updated_at = now()
      where escrow_order_id = NEW.id and status <> 'CANCELLED';
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_sync_marketplace_purchase_status on public.escrow_orders;
create trigger trg_sync_marketplace_purchase_status
  after update on public.escrow_orders
  for each row
  execute function public.trg_sync_marketplace_purchase_status();

-- 11. Atomic Marketplace Purchase Reservation RPC with PostGIS & Split Payout Allocations
create or replace function public.reserve_marketplace_purchase(
  p_actor_id uuid,
  p_item_id uuid,
  p_quantity integer,
  p_fulfillment_mode text,
  p_delivery_reward numeric,
  p_idempotency_key text,
  p_dest_name text default null,
  p_dest_lat numeric default null,
  p_dest_lng numeric default null,
  p_weight_kg numeric default 1.0
)
returns jsonb
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
declare
  existing_purchase public.marketplace_purchases;
  existing_order public.escrow_orders;
  i public.marketplace_items;
  v_policy public.cost_sharing_policies;
  v_subtotal numeric(12,2);
  v_reward numeric(12,2);
  v_bps integer;
  v_fee numeric(12,2);
  v_total numeric(12,2);
  v_purchase public.marketplace_purchases;
  v_order public.escrow_orders;
  v_task public.shipment_tasks;
  v_dest_geo geography(Point,4326);
  v_thread_id uuid;
  v_existing_task_id uuid;
begin
  -- Strict authentication check
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_actor_id <> auth.uid() then
    raise exception 'Cannot impersonate another user';
  end if;

  -- Input validation
  if p_quantity < 1 then
    raise exception 'Purchase quantity must be at least 1';
  end if;

  if p_fulfillment_mode not in ('LOCAL_HANDOFF', 'PARCELPOOL') then
    raise exception 'Invalid fulfillment mode';
  end if;

  if p_fulfillment_mode = 'LOCAL_HANDOFF' then
    if coalesce(p_delivery_reward, 0) <> 0 then
      raise exception 'Local handoff delivery reward must be zero';
    end if;
    v_reward := 0;
  else
    if p_delivery_reward is null or p_delivery_reward < 0 then
      raise exception 'Invalid delivery reward for ParcelPool crowdshipping';
    end if;
    v_reward := p_delivery_reward;

    if p_dest_name is null or char_length(trim(p_dest_name)) < 2 then
      raise exception 'ParcelPool crowdshipping requires a valid destination address name';
    end if;

    if p_dest_lat is null or p_dest_lng is null or p_dest_lat < -90 or p_dest_lat > 90 or p_dest_lng < -180 or p_dest_lng > 180 then
      raise exception 'ParcelPool crowdshipping requires valid destination coordinates';
    end if;

    v_dest_geo := ST_SetSRID(ST_MakePoint(p_dest_lng, p_dest_lat), 4326)::geography;
  end if;

  -- Idempotency security check
  select * into existing_purchase from public.marketplace_purchases where idempotency_key = p_idempotency_key;
  if found then
    if existing_purchase.buyer_id <> p_actor_id or existing_purchase.item_id <> p_item_id or existing_purchase.quantity <> p_quantity or existing_purchase.fulfillment_mode <> p_fulfillment_mode then
      raise exception 'Idempotency key reuse with mismatched parameters or unauthorized actor';
    end if;

    select * into existing_order from public.escrow_orders where id = existing_purchase.escrow_order_id;
    select id into v_existing_task_id from public.shipment_tasks where marketplace_purchase_id = existing_purchase.id limit 1;

    select id into v_thread_id from public.chat_threads where order_id = existing_order.id limit 1;

    return jsonb_build_object(
      'purchase', to_jsonb(existing_purchase),
      'escrow_order', to_jsonb(existing_order),
      'shipment_task_id', v_existing_task_id,
      'chat_thread_id', v_thread_id
    );
  end if;

  -- Lock item row for atomic inventory check
  select * into i from public.marketplace_items where id = p_item_id for update;
  if not found or i.status <> 'LISTED' or i.available_quantity < p_quantity then
    raise exception 'Insufficient item stock available';
  end if;

  if i.seller_id = p_actor_id then
    raise exception 'Seller cannot purchase own item';
  end if;

  if p_fulfillment_mode = 'PARCELPOOL' and not i.ship_eligible then
    raise exception 'This item is not eligible for ParcelPool crowdshipping';
  end if;

  -- Canonical Jurisdiction / Cost-Sharing Policy Lookup & Platform Fee BPS Derivation
  select * into v_policy from public.cost_sharing_policies
  where jurisdiction_code = i.jurisdiction_code and enabled is true;
  if not found or v_policy.marketplace_platform_fee_bps is null then
    raise exception 'No enabled marketplace platform fee policy for jurisdiction %', i.jurisdiction_code;
  end if;

  if i.currency <> v_policy.currency then
    raise exception 'Item currency % does not match jurisdiction policy currency %', i.currency, v_policy.currency;
  end if;

  v_bps := v_policy.marketplace_platform_fee_bps;

  -- Authoritative DB price & fee calculation
  v_subtotal := i.price * p_quantity;
  v_fee := round(v_subtotal * v_bps / 10000.0, 2);
  v_total := v_subtotal + v_reward + v_fee;

  -- Enable session variable for inventory mutation
  perform set_config('shipdehop.allow_inventory_mutation', 'true', true);

  -- Atomic inventory decrement
  update public.marketplace_items
  set available_quantity = available_quantity - p_quantity,
      status = (case when (available_quantity - p_quantity) = 0 then 'SOLD'::public.marketplace_item_status else status end),
      updated_at = now()
  where id = i.id;

  -- Insert Escrow Order (HopPay Escrow Engine)
  insert into public.escrow_orders (
    order_type, buyer_id, provider_id, marketplace_item_id, total_amount, base_price, reward_fee, platform_fee,
    currency, escrow_status, fulfillment_status, reservation_expires_at
  ) values (
    'MARKETPLACE', p_actor_id, i.seller_id, i.id, v_total, v_subtotal, v_reward, v_fee,
    i.currency, 'PENDING', 'CREATED', now() + interval '15 minutes'
  ) returning * into v_order;

  -- Insert Marketplace Purchase (Commerce Entity)
  insert into public.marketplace_purchases (
    item_id, buyer_id, seller_id, quantity, unit_price, subtotal, fulfillment_mode, delivery_reward, platform_fee,
    total_amount, currency, jurisdiction_code, status, escrow_order_id, idempotency_key
  ) values (
    i.id, p_actor_id, i.seller_id, p_quantity, i.price, v_subtotal, p_fulfillment_mode, v_reward, v_fee,
    v_total, i.currency, i.jurisdiction_code, 'PENDING', v_order.id, p_idempotency_key
  ) returning * into v_purchase;

  -- Create Seller Proceeds Payout Allocation
  insert into public.escrow_payout_allocations (
    order_id, recipient_id, allocation_type, amount, currency, status, idempotency_key
  ) values (
    v_order.id, i.seller_id, 'SELLER_PROCEEDS', v_subtotal, i.currency, 'PENDING',
    'seller_proceeds:' || v_order.id || ':' || i.seller_id
  );

  -- If PARCELPOOL crowdshipping selected, create linked shipment task with buyer_id as sender_id (requester/payer)
  if p_fulfillment_mode = 'PARCELPOOL' then
    insert into public.shipment_tasks (
      sender_id, item_type, declared_value, reward_amount, currency, weight_kg, status, inspection_status,
      pickup_name, drop_name, pickup_geo, drop_geo, marketplace_purchase_id
    ) values (
      p_actor_id, 'PARCEL'::public.shipment_item_type, v_subtotal, v_reward, i.currency, coalesce(p_weight_kg, 1.0),
      'OPEN'::public.shipment_status, 'PENDING'::public.shipment_inspection_status,
      i.location_name, trim(p_dest_name), i.location_geo, v_dest_geo, v_purchase.id
    ) returning * into v_task;
  end if;

  -- Fetch canonical chat thread automatically created for THIS escrow order ID by trigger
  select id into v_thread_id from public.chat_threads where order_id = v_order.id limit 1;

  -- Dispatch idempotent notification to Seller
  perform public.create_notification(
    i.seller_id,
    'MARKETPLACE_PURCHASED',
    'Item purchased',
    'A buyer has purchased ' || p_quantity || ' unit(s) of ' || i.title,
    'ORDER',
    v_order.id,
    'marketplace_purchased:' || v_purchase.id || ':' || i.seller_id,
    v_order.id,
    null,
    null
  );

  insert into public.escrow_events(order_id, actor_id, event_type)
  values (v_order.id, p_actor_id, 'ORDER_RESERVED');

  return jsonb_build_object(
    'purchase', to_jsonb(v_purchase),
    'escrow_order', to_jsonb(v_order),
    'shipment_task_id', v_task.id,
    'chat_thread_id', v_thread_id
  );
end;
$$;

-- 12. Marketplace Purchase Cancellation & Pre-Funding Inventory Restoration RPC
create or replace function public.cancel_marketplace_purchase(
  p_actor_id uuid,
  p_purchase_id uuid
)
returns public.marketplace_purchases
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
declare
  v_purchase public.marketplace_purchases;
  v_order public.escrow_orders;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_actor_id <> auth.uid() then
    raise exception 'Cannot impersonate another user';
  end if;

  select * into v_purchase from public.marketplace_purchases where id = p_purchase_id for update;
  if not found then
    raise exception 'Marketplace purchase not found';
  end if;

  if v_purchase.buyer_id <> p_actor_id and v_purchase.seller_id <> p_actor_id then
    raise exception 'Unauthorized to cancel this purchase';
  end if;

  if v_purchase.status in ('COMPLETED', 'IN_TRANSIT', 'AWAITING_HANDOFF') then
    raise exception 'Completed or active in-transit sales cannot be cancelled directly. Use escrow refund lifecycle.';
  end if;

  if v_purchase.status = 'PAYMENT_LOCKED' then
    raise exception 'Payment is locked in escrow. Execute canonical payment refund path to cancel.';
  end if;

  if v_purchase.inventory_restored then
    -- Idempotent cancel: return purchase without double restoration
    return v_purchase;
  end if;

  -- Update purchase status
  update public.marketplace_purchases
  set status = 'CANCELLED', updated_at = now()
  where id = v_purchase.id
  returning * into v_purchase;

  -- Execute canonical order inventory restoration (restores stock, trip capacity, cancels payout allocations & closes shipment)
  if v_purchase.escrow_order_id is not null then
    select * into v_order from public.escrow_orders where id = v_purchase.escrow_order_id for update;
    if found and v_order.escrow_status = 'PENDING' then
      perform public.restore_order_inventory(v_order);
      update public.escrow_orders
      set fulfillment_status = 'CANCELLED', reservation_expires_at = null, updated_at = now()
      where id = v_order.id;

      insert into public.escrow_events(order_id, actor_id, event_type, metadata)
      values (v_order.id, p_actor_id, 'ORDER_CANCELLED', jsonb_build_object('reason', 'Buyer cancelled pending marketplace reservation'));
    end if;
  else
    -- Fallback for purchase without escrow order
    perform set_config('shipdehop.allow_inventory_mutation', 'true', true);
    update public.marketplace_items
    set available_quantity = available_quantity + v_purchase.quantity,
        status = (case when status = 'SOLD' then 'LISTED'::public.marketplace_item_status else status end),
        updated_at = now()
    where id = v_purchase.item_id;

    update public.marketplace_purchases
    set inventory_restored = true, updated_at = now()
    where id = v_purchase.id;
  end if;

  return v_purchase;
end;
$$;

-- 13. Updated reserve_shipment_order supporting MARKETPLACE-LINKED Crowdshipping Tasks with Payment Gate & Hopster Payout Allocation
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
  v_purchase public.marketplace_purchases;
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

  -- =========================================================================
  -- MARKETPLACE-LINKED CROWDSHIPPING BRANCH (Payment Gate & Split Payout)
  -- =========================================================================
  if s.marketplace_purchase_id is not null then
    select * into v_purchase from public.marketplace_purchases where id = s.marketplace_purchase_id for update;
    if not found or v_purchase.status = 'CANCELLED' then
      raise exception 'Marketplace purchase for this shipment is no longer active';
    end if;

    select * into v_order from public.escrow_orders where id = v_purchase.escrow_order_id for update;
    if not found then
      raise exception 'Escrow order not found for marketplace purchase';
    end if;

    -- PAYMENT SECURED GATE: Marketplace payment MUST be locked before carrier capacity is reserved
    if v_order.escrow_status <> 'LOCKED' then
      raise exception 'Marketplace escrow payment must be LOCKED before reserving carrier capacity';
    end if;

    if v_purchase.buyer_id = p_provider_id or v_purchase.seller_id = p_provider_id then
      raise exception 'Buyer or seller cannot carry own marketplace shipment';
    end if;

    -- Reserve parcel capacity on carrier trip
    update public.trip_routes
    set parcel_capacity_units_available = parcel_capacity_units_available - v_req_units
    where id = t.id;

    -- Update shipment task status to MATCHED
    update public.shipment_tasks set status = 'MATCHED'::public.shipment_status where id = s.id;

    -- Link carrier trip to existing Marketplace escrow order (Zero double charge)
    update public.escrow_orders
    set trip_id = t.id,
        reserved_parcel_capacity_units = v_req_units,
        updated_at = now()
    where id = v_order.id
    returning * into v_order;

    -- Update marketplace purchase status to HOPSTER_MATCHED
    update public.marketplace_purchases
    set status = 'HOPSTER_MATCHED', updated_at = now()
    where id = v_purchase.id;

    -- Create Hopster Delivery Reward Payout Allocation
    insert into public.escrow_payout_allocations (
      order_id, recipient_id, allocation_type, amount, currency, status, idempotency_key
    ) values (
      v_order.id, p_provider_id, 'HOPSTER_REWARD', v_order.reward_fee, v_order.currency, 'PENDING',
      'hopster_reward:' || v_order.id || ':' || p_provider_id
    ) on conflict (idempotency_key) do nothing;

    -- Record carrier match event
    insert into public.escrow_events(order_id, actor_id, event_type, metadata)
    values (v_order.id, p_provider_id, 'ORDER_RESERVED', jsonb_build_object('trip_id', t.id, 'max_detour_meters', p_max_detour_meters, 'carrier_id', p_provider_id, 'reserved_parcel_units', v_req_units));

    -- Dispatch notification to Buyer
    perform public.create_notification(
      v_purchase.buyer_id,
      'PARCEL_RESERVED',
      'Hopster matched your delivery',
      'A Hopster reserved your marketplace delivery from ' || s.pickup_name || ' to ' || s.drop_name || '.',
      'ORDER',
      v_order.id,
      'parcel_reserved_buyer:' || v_order.id || ':' || v_purchase.buyer_id,
      v_order.id,
      t.id,
      null
    );

    -- Dispatch notification to Seller
    perform public.create_notification(
      v_purchase.seller_id,
      'PARCEL_RESERVED',
      'Hopster assigned for pickup',
      'A Hopster was assigned for pickup of your sold item from ' || s.pickup_name || '.',
      'ORDER',
      v_order.id,
      'parcel_reserved_seller:' || v_order.id || ':' || v_purchase.seller_id,
      v_order.id,
      t.id,
      null
    );

    return v_order;
  end if;

  -- =========================================================================
  -- NORMAL NON-MARKETPLACE SHIPMENT BRANCH (Phase 12 Unchanged)
  -- =========================================================================
  if s.sender_id = p_provider_id then raise exception 'Sender cannot carry own shipment order'; end if;

  update public.trip_routes
  set parcel_capacity_units_available = parcel_capacity_units_available - v_req_units
  where id = t.id;

  v_base := case when s.item_type = 'URL_PURCHASE' then s.declared_value else 0 end;
  v_fee := round((v_base + s.reward_amount) * p_platform_fee_bps / 10000.0, 2);

  update public.shipment_tasks set status = 'MATCHED'::public.shipment_status where id = s.id;

  insert into public.escrow_orders(
    order_type,buyer_id,provider_id,trip_id,shipment_task_id,total_amount,base_price,reward_fee,platform_fee,
    currency,escrow_status,fulfillment_status,reservation_expires_at,reserved_parcel_capacity_units
  ) values (
    'SHIPMENT',s.sender_id,p_provider_id,t.id,s.id,v_base + s.reward_amount + v_fee,v_base,s.reward_amount,v_fee,
    s.currency,'PENDING','CREATED',now() + interval '30 minutes',v_req_units
  ) returning * into v_order;

  insert into public.escrow_events(order_id,actor_id,event_type,metadata)
  values (v_order.id,p_provider_id,'ORDER_RESERVED',jsonb_build_object('trip_id',t.id,'max_detour_meters',p_max_detour_meters,'payer_id',s.sender_id,'reserved_parcel_units',v_req_units));

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

-- 14. Single Authoritative Order Inventory & Capacity Restoration Function
create or replace function public.restore_order_inventory(p_order public.escrow_orders)
returns void
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
declare
  v_units int;
  v_purchase public.marketplace_purchases;
  v_shipment_id uuid;
begin
  if p_order.order_type = 'RIDE' and p_order.trip_id is not null then
    update public.trip_routes
      set available_seats = least(seat_capacity, available_seats + p_order.quantity)
      where id = p_order.trip_id and status = 'SCHEDULED';
  elsif p_order.order_type = 'MARKETPLACE' then
    -- Find and lock linked marketplace purchase
    select * into v_purchase from public.marketplace_purchases
      where escrow_order_id = p_order.id for update;

    -- EXACTLY-ONCE GUARD: All physical restoration belongs inside this section
    if found then
      if v_purchase.inventory_restored then
        return; -- Skip all restoration if already performed
      end if;

      perform set_config('shipdehop.allow_inventory_mutation', 'true', true);

      -- 1. Restore listing available_quantity and reopen SOLD -> LISTED
      update public.marketplace_items mi
      set available_quantity = mi.available_quantity + v_purchase.quantity,
          status = (case when mi.status = 'SOLD' then 'LISTED'::public.marketplace_item_status else mi.status end),
          updated_at = now()
      where id = v_purchase.item_id;

      -- 2. Restore reserved trip parcel capacity if carrier was matched
      if p_order.trip_id is not null then
        v_units := coalesce(p_order.reserved_parcel_capacity_units, 3);
        update public.trip_routes
        set parcel_capacity_units_available = least(parcel_capacity_units_total, parcel_capacity_units_available + v_units)
        where id = p_order.trip_id and status = 'SCHEDULED';
      end if;

      -- 3. Cancel pending payout allocations
      update public.escrow_payout_allocations
      set status = 'CANCELLED', updated_at = now()
      where order_id = p_order.id and status = 'PENDING';

      -- 4. Close linked shipment task so it no longer appears in open match feed
      select id into v_shipment_id from public.shipment_tasks where marketplace_purchase_id = v_purchase.id limit 1;
      if v_shipment_id is not null then
        update public.shipment_tasks
        set status = 'CANCELLED'::public.shipment_status, updated_at = now()
        where id = v_shipment_id and status in ('OPEN'::public.shipment_status, 'MATCHED'::public.shipment_status, 'DRAFT'::public.shipment_status);
      end if;

      -- 5. Atomically mark inventory restored
      update public.marketplace_purchases
      set inventory_restored = true, updated_at = now()
      where id = v_purchase.id;
    elsif p_order.marketplace_item_id is not null then
      update public.marketplace_items set status = 'LISTED'
        where id = p_order.marketplace_item_id and status = 'RESERVED';
    end if;
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

-- 15. Override service_mark_order_released to respect available_quantity bounds (SOLD only if available_quantity = 0)
create or replace function public.service_mark_order_released(p_order_id uuid, p_transfer_ref text)
returns void
language plpgsql
security definer
set search_path = public, gis, extensions
as $$
declare
  v public.escrow_orders;
  v_item public.marketplace_items;
begin
  select * into v from public.escrow_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if v.escrow_status = 'RELEASED' then return; end if;
  if v.escrow_status <> 'LOCKED' or v.fulfillment_status <> 'VERIFIED' then raise exception 'Order cannot be released'; end if;

  update public.escrow_orders
  set escrow_status = 'RELEASED', fulfillment_status = 'COMPLETED', payout_transfer_ref = p_transfer_ref, updated_at = now()
  where id = p_order_id;

  if v.order_type = 'MARKETPLACE' and v.marketplace_item_id is not null then
    select * into v_item from public.marketplace_items where id = v.marketplace_item_id for update;
    if found then
      -- Update status according to remaining available quantity: SOLD only if available_quantity = 0, else LISTED
      perform set_config('shipdehop.allow_inventory_mutation', 'true', true);
      update public.marketplace_items
      set status = (case when available_quantity = 0 then 'SOLD'::public.marketplace_item_status else 'LISTED'::public.marketplace_item_status end),
          updated_at = now()
      where id = v_item.id;
    end if;
  end if;

  if v.order_type = 'SHIPMENT' and v.shipment_task_id is not null then
    update public.shipment_tasks set status = 'DELIVERED', updated_at = now() where id = v.shipment_task_id;
  end if;

  insert into public.escrow_events(order_id, event_type, metadata)
  values (p_order_id, 'FUNDS_RELEASED', jsonb_build_object('transfer_ref', p_transfer_ref));
end;
$$;

-- Grant permissions for RPCs
revoke execute on function public.update_marketplace_listing_stock(uuid, uuid, integer) from public, anon;
grant execute on function public.update_marketplace_listing_stock(uuid, uuid, integer) to authenticated;

revoke execute on function public.reserve_marketplace_purchase(uuid, uuid, integer, text, numeric, text, text, numeric, numeric, numeric) from public, anon;
grant execute on function public.reserve_marketplace_purchase(uuid, uuid, integer, text, numeric, text, text, numeric, numeric, numeric) to authenticated;

revoke execute on function public.cancel_marketplace_purchase(uuid, uuid) from public, anon;
grant execute on function public.cancel_marketplace_purchase(uuid, uuid) to authenticated;

revoke execute on function public.reserve_shipment_order(uuid,uuid,uuid,uuid,integer,integer) from public, anon;
grant execute on function public.reserve_shipment_order(uuid,uuid,uuid,uuid,integer,integer) to authenticated, service_role;

revoke execute on function public.service_mark_order_released(uuid,text) from public, anon, authenticated;
grant execute on function public.service_mark_order_released(uuid,text) to service_role;
