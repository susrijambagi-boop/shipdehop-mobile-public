-- Migration 017: parcel timing + private assistant shipment matching

alter table public.shipment_tasks
  add column if not exists earliest_pickup timestamptz,
  add column if not exists latest_delivery timestamptz;

alter table public.shipment_tasks
  drop constraint if exists shipment_tasks_timing_window_check;

alter table public.shipment_tasks
  add constraint shipment_tasks_timing_window_check
  check (
    earliest_pickup is null
    or latest_delivery is null
    or latest_delivery >= earliest_pickup
  );

drop function if exists public.create_shipment_task(
  public.shipment_item_type,
  text,
  numeric,
  numeric,
  char,
  text,
  double precision,
  double precision,
  text,
  double precision,
  double precision,
  numeric
);

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
  p_weight_kg numeric,
  p_earliest_pickup timestamptz default null,
  p_latest_delivery timestamptz default null
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
  if v_user is null then
    raise exception 'Authentication required';
  end if;

  if upper(p_currency) <> 'INR' then
    raise exception 'Currency must be INR for India transactions';
  end if;

  if p_earliest_pickup is not null
     and p_latest_delivery is not null
     and p_latest_delivery < p_earliest_pickup then
    raise exception 'Latest delivery cannot be before earliest pickup';
  end if;

  if p_item_type = 'URL_PURCHASE' then
    if p_product_url is null or p_product_url !~* '^https://[^ ]+$' then
      raise exception 'A valid HTTPS product URL is required';
    end if;
    if not exists (
      select 1
      from public.users u
      where u.id = v_user
        and u.ekyc_tier in ('TIER_2','TIER_3')
    ) then
      raise exception 'Buy-for-Me requires completed identity verification';
    end if;
  end if;

  insert into public.shipment_tasks(
    sender_id,
    item_type,
    product_url,
    declared_value,
    reward_amount,
    currency,
    pickup_name,
    pickup_geo,
    drop_name,
    drop_geo,
    weight_kg,
    earliest_pickup,
    latest_delivery,
    status
  ) values (
    v_user,
    p_item_type,
    p_product_url,
    p_declared_value,
    p_reward_amount,
    'INR',
    p_pickup_name,
    ST_SetSRID(ST_Point(p_pickup_lon,p_pickup_lat),4326)::geography,
    p_drop_name,
    ST_SetSRID(ST_Point(p_drop_lon,p_drop_lat),4326)::geography,
    p_weight_kg,
    p_earliest_pickup,
    p_latest_delivery,
    'DRAFT'
  )
  returning * into v_result;

  return v_result;
end;
$$;

revoke execute on function public.create_shipment_task(
  public.shipment_item_type,
  text,
  numeric,
  numeric,
  char,
  text,
  double precision,
  double precision,
  text,
  double precision,
  double precision,
  numeric,
  timestamptz,
  timestamptz
) from public, anon;

grant execute on function public.create_shipment_task(
  public.shipment_item_type,
  text,
  numeric,
  numeric,
  char,
  text,
  double precision,
  double precision,
  text,
  double precision,
  double precision,
  numeric,
  timestamptz,
  timestamptz
) to authenticated, service_role;

create or replace function public.assistant_match_open_shipments(
  p_origin_lon double precision,
  p_origin_lat double precision,
  p_dest_lon double precision,
  p_dest_lat double precision,
  p_max_weight_kg numeric default null,
  p_travel_date timestamptz default null,
  p_max_endpoint_detour_meters integer default 50000,
  p_limit integer default 25
)
returns table (
  shipment_task_id uuid,
  item_type public.shipment_item_type,
  pickup_name text,
  drop_name text,
  weight_kg numeric,
  reward_amount numeric,
  declared_value numeric,
  currency char(3),
  earliest_pickup timestamptz,
  latest_delivery timestamptz,
  pickup_distance_meters double precision,
  drop_distance_meters double precision
)
language sql
stable
security definer
set search_path = public, gis, extensions
as $$
  with points as (
    select
      ST_SetSRID(ST_Point(p_origin_lon, p_origin_lat), 4326)::geography as origin_geo,
      ST_SetSRID(ST_Point(p_dest_lon, p_dest_lat), 4326)::geography as dest_geo
  )
  select
    s.id,
    s.item_type,
    s.pickup_name,
    s.drop_name,
    s.weight_kg,
    s.reward_amount,
    s.declared_value,
    s.currency,
    s.earliest_pickup,
    s.latest_delivery,
    ST_Distance(s.pickup_geo, points.origin_geo),
    ST_Distance(s.drop_geo, points.dest_geo)
  from public.shipment_tasks s
  cross join points
  where s.status = 'OPEN'
    and s.inspection_status = 'APPROVED'
    and s.currency = 'INR'
    and (p_max_weight_kg is null or s.weight_kg <= p_max_weight_kg)
    and ST_DWithin(
      s.pickup_geo,
      points.origin_geo,
      least(greatest(p_max_endpoint_detour_meters, 1000), 100000)
    )
    and ST_DWithin(
      s.drop_geo,
      points.dest_geo,
      least(greatest(p_max_endpoint_detour_meters, 1000), 100000)
    )
    and (
      p_travel_date is null
      or (
        (s.earliest_pickup is null or s.earliest_pickup <= p_travel_date + interval '1 day')
        and (s.latest_delivery is null or s.latest_delivery >= p_travel_date)
      )
    )
  order by (
    ST_Distance(s.pickup_geo, points.origin_geo)
    + ST_Distance(s.drop_geo, points.dest_geo)
  ) asc
  limit least(greatest(p_limit, 1), 50);
$$;

revoke execute on function public.assistant_match_open_shipments(
  double precision,
  double precision,
  double precision,
  double precision,
  numeric,
  timestamptz,
  integer,
  integer
) from public, anon, authenticated;

grant execute on function public.assistant_match_open_shipments(
  double precision,
  double precision,
  double precision,
  double precision,
  numeric,
  timestamptz,
  integer,
  integer
) to service_role;
