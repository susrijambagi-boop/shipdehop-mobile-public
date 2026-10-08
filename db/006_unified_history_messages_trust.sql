-- =================================================================
-- SHIPDEHOP MIGRATION 006: UNIFIED HISTORY, MESSAGES, PROFILE & TRUST
-- =================================================================

-- 1. ADDITIVE COLUMNS ON public.users
alter table public.users add column if not exists full_name text;
alter table public.users add column if not exists xp_points integer not null default 0 check (xp_points >= 0);

-- 2. CHAT THREAD READS (Per-user durable unread tracking)
create table if not exists public.chat_thread_reads (
  thread_id uuid not null references public.chat_threads(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

alter table public.chat_thread_reads enable row level security;

drop policy if exists "Thread participants can view read status" on public.chat_thread_reads;
create policy "Thread participants can view read status" on public.chat_thread_reads
  for select to authenticated
  using (
    user_id = (select auth.uid()) or
    exists (
      select 1 from public.chat_threads t
      join public.escrow_orders o on o.id = t.order_id
      where t.id = chat_thread_reads.thread_id
        and (o.buyer_id = (select auth.uid()) or o.provider_id = (select auth.uid()))
    )
  );

drop policy if exists "Users can update own read status" on public.chat_thread_reads;
create policy "Users can update own read status" on public.chat_thread_reads
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- 3. TRUST & XP LEDGER TABLES
create table if not exists public.trust_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  event_type text not null,
  delta numeric(5,2) not null,
  reason text,
  idempotency_key text unique,
  created_at timestamptz not null default now()
);

alter table public.trust_events enable row level security;
drop policy if exists "Users can view own trust events" on public.trust_events;
create policy "Users can view own trust events" on public.trust_events
  for select to authenticated
  using (user_id = (select auth.uid()));

create table if not exists public.xp_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  event_type text not null,
  xp_awarded integer not null check (xp_awarded > 0),
  idempotency_key text unique,
  created_at timestamptz not null default now()
);

alter table public.xp_events enable row level security;
drop policy if exists "Users can view own xp events" on public.xp_events;
create policy "Users can view own xp events" on public.xp_events
  for select to authenticated
  using (user_id = (select auth.uid()));

-- 4. TRUSTED RPC TO AWARD XP (SERVER AUTHORITATIVE ONLY)
create or replace function public.award_user_xp(
  p_user_id uuid,
  p_xp_amount integer,
  p_event_type text,
  p_idempotency_key text
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_xp_amount <= 0 then
    raise exception 'XP amount must be positive';
  end if;

  -- Check idempotency for XP award
  if not exists (select 1 from public.xp_events where idempotency_key = p_idempotency_key) then
    insert into public.xp_events (user_id, event_type, xp_awarded, idempotency_key)
    values (p_user_id, p_event_type, p_xp_amount, p_idempotency_key);

    update public.users
    set xp_points = xp_points + p_xp_amount
    where id = p_user_id;
  end if;
end $$;

-- 5. TRUSTED RPC TO MARK CHAT THREAD AS READ
create or replace function public.mark_chat_thread_read(
  p_actor_id uuid,
  p_thread_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_order public.escrow_orders;
begin
  if auth.uid() is not null and auth.uid() <> '00000000-0000-0000-0000-000000000000'::uuid and auth.uid() <> p_actor_id then
    raise exception 'Cannot impersonate another user';
  end if;

  select o.* into v_order
  from public.chat_threads t
  join public.escrow_orders o on o.id = t.order_id
  where t.id = p_thread_id;

  if not found then
    raise exception 'Chat thread not found';
  end if;

  if v_order.buyer_id <> p_actor_id and v_order.provider_id <> p_actor_id then
    raise exception 'Access denied to thread';
  end if;

  insert into public.chat_thread_reads (thread_id, user_id, last_read_at)
  values (p_thread_id, p_actor_id, now())
  on conflict (thread_id, user_id)
  do update set last_read_at = excluded.last_read_at;
end $$;

-- 6. INDEXES FOR PERFORMANCE
create index if not exists idx_chat_messages_thread_created on public.chat_messages(thread_id, created_at desc);
create index if not exists idx_chat_thread_reads_user on public.chat_thread_reads(user_id);
create index if not exists idx_escrow_orders_buyer on public.escrow_orders(buyer_id);
create index if not exists idx_escrow_orders_provider on public.escrow_orders(provider_id);
create index if not exists idx_shipment_tasks_sender on public.shipment_tasks(sender_id);
