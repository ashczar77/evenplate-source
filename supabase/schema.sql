-- EvenPlate: Production Supabase PostgreSQL Schema with Row-Level Security (RLS)
-- Safe to re-run against an existing database.

-- 1. Profiles Table (Extends auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  is_pro boolean not null default false,
  free_scans_remaining int not null default 3,
  promo_pro_until timestamp with time zone,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.profiles enable row level security;

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

-- profiles is the quota ledger. The phone caches the last row it pulled.
-- is_pro is written by the RevenueCat webhook, redeem_promo_code, or
-- reconcile_expired_entitlement when the store has already expired. Weekly
-- remaining only moves through those functions plus consume/refund/reset.
-- No client writes this table, so it carries no client write privilege and
-- no update policy. If an update grant is ever added back, RLS denies until
-- a policy is added with it.
drop policy if exists "Users can update own profile" on public.profiles;
revoke insert, update, delete on public.profiles from anon, authenticated;

-- Existing databases created before this column still need it. New ones get it
-- from create table above, and if not exists makes the alter a no-op for them.
alter table public.profiles
  add column if not exists promo_pro_until timestamp with time zone;

alter table public.profiles
  add column if not exists photo_purchased int not null default 0;
alter table public.profiles
  add column if not exists text_included_remaining int not null default 20;
alter table public.profiles
  add column if not exists text_purchased int not null default 0;
alter table public.profiles
  add column if not exists foods_hour_count int not null default 0;
alter table public.profiles
  add column if not exists foods_hour_started_at timestamp with time zone;

alter table public.profiles add column if not exists subscription_expires_at timestamptz;
alter table public.profiles add column if not exists subscription_environment text;
alter table public.profiles add column if not exists subscription_event_ms bigint not null default 0;
alter table public.profiles add column if not exists pro_credit_week date;
alter table public.profiles add column if not exists quota_week date not null default date_trunc('week', now() at time zone 'UTC')::date;
alter table public.profiles add column if not exists photo_included_used_week int;
alter table public.profiles add column if not exists text_included_used_week int;

-- 2. Meals Table (Satiety Matrix Meal History)
create table if not exists public.meals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  meal_name text not null,
  satiety_score int not null,
  duration_hours numeric not null,
  satiety_result jsonb not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.meals enable row level security;

drop policy if exists "Users can view own meals" on public.meals;
create policy "Users can view own meals"
  on public.meals for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own meals" on public.meals;
create policy "Users can insert own meals"
  on public.meals for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own meals" on public.meals;
create policy "Users can update own meals"
  on public.meals for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own meals" on public.meals;
create policy "Users can delete own meals"
  on public.meals for delete
  using (auth.uid() = user_id);

-- 3. Terrarium Progression Table
create table if not exists public.terrarium (
  user_id uuid primary key references auth.users(id) on delete cascade,
  total_balanced_plates int not null default 0,
  current_level int not null default 1,
  unlocked_flora jsonb not null default '["Sprout"]'::jsonb,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.terrarium enable row level security;

drop policy if exists "Users can view own terrarium" on public.terrarium;
create policy "Users can view own terrarium"
  on public.terrarium for select
  using (auth.uid() = user_id);

-- The previous "for all" policy had no with check, so inserts were unrestricted
-- and a user could create a terrarium row owned by someone else.
drop policy if exists "Users can update own terrarium" on public.terrarium;
drop policy if exists "Users can write own terrarium" on public.terrarium;
create policy "Users can write own terrarium"
  on public.terrarium for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 4. Trigger: Auto-create Profile and Terrarium upon auth signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (
    id, email, is_pro, free_scans_remaining, text_included_remaining
  )
  values (new.id, new.email, false, 3, 20)
  on conflict (id) do nothing;

  insert into public.terrarium (user_id, total_balanced_plates, current_level, unlocked_flora)
  values (new.id, 0, 1, '["Sprout"]'::jsonb)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create or replace function public.refresh_user_quota(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v public.profiles%rowtype;
  v_week date := date_trunc('week', now() at time zone 'UTC')::date;
  v_pro boolean;
begin
  select * into v from public.profiles where id = p_user_id for update;
  if not found then return; end if;
  v_pro := (v.is_pro and (v.subscription_expires_at is null or v.subscription_expires_at > now())) or coalesce(v.promo_pro_until > now(), false);
  update public.profiles set
    is_pro = v.is_pro and (v.subscription_expires_at is null or v.subscription_expires_at > now()),
    free_scans_remaining = case when v.quota_week < v_week then case when v_pro then 75 else 3 end when not v_pro then least(v.free_scans_remaining, 3) when v.pro_credit_week = v_week then greatest(v.free_scans_remaining, 75 - coalesce(v.photo_included_used_week, 0)) else v.free_scans_remaining end,
    text_included_remaining = case when v.quota_week < v_week then case when v_pro then 100 else 20 end when not v_pro then least(v.text_included_remaining, 20) when v.pro_credit_week = v_week then greatest(v.text_included_remaining, 100 - coalesce(v.text_included_used_week, 0)) else v.text_included_remaining end,
    quota_week = v_week,
    pro_credit_week = case when v_pro then v_week else v.pro_credit_week end,
    photo_included_used_week = case when v.quota_week < v_week then 0 else v.photo_included_used_week end,
    text_included_used_week = case when v.quota_week < v_week then 0 else v.text_included_used_week end
  where id = p_user_id;
end;
$$;
revoke all on function public.refresh_user_quota(uuid) from public, anon, authenticated;
grant execute on function public.refresh_user_quota(uuid) to service_role;

-- 5. Atomic scan quota check and consume
-- Reading the quota and decrementing it in two round trips lets concurrent
-- requests all observe the same value and pass the check. This does both under
-- a row lock so parallel scans serialize.
create or replace function public.consume_scan_credit()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_pro boolean;
  v_included int;
  v_purchased int;
  v_promo_until timestamp with time zone;
  v_entitled boolean;
  v_used_purchased boolean := false;
begin
  if v_uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  perform public.refresh_user_quota(v_uid);
  select is_pro, free_scans_remaining, photo_purchased, promo_pro_until
    into v_is_pro, v_included, v_purchased, v_promo_until
  from public.profiles
  where id = v_uid
  for update;

  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'no_profile');
  end if;

  v_entitled := v_is_pro
    or (v_promo_until is not null
        and v_promo_until > timezone('utc'::text, now()));

  -- An expired Pro week can leave leftover above the Free cap if the
  -- webhook never clamped. Free consume must not keep treating that as Pro.
  if not v_entitled and v_included > 3 then
    v_included := 3;
  end if;

  if v_included > 0 and (v_entitled or private.has_device_eligibility(v_uid)) then
    update public.profiles
       set free_scans_remaining = v_included - 1,
           photo_included_used_week = least(75, photo_included_used_week + 1),
           updated_at = timezone('utc'::text, now())
     where id = v_uid
    returning free_scans_remaining into v_included;
  elsif v_purchased > 0 then
    v_used_purchased := true;
    update public.profiles
       set photo_purchased = photo_purchased - 1,
           updated_at = timezone('utc'::text, now())
     where id = v_uid
    returning photo_purchased into v_purchased;
  else
    return jsonb_build_object(
      'allowed', false, 'reason', case when not v_entitled and not private.has_device_eligibility(v_uid) then 'device_required' else 'quota_exceeded' end,
      'is_pro', v_entitled, 'remaining', 0,
      'photo_remaining', 0, 'photo_purchased', 0
    );
  end if;

  return jsonb_build_object(
    'allowed', true,
    'is_pro', v_entitled,
    'remaining', v_included + v_purchased,
    'photo_remaining', v_included,
    'photo_purchased', v_purchased,
    'used_purchased', v_used_purchased
  );
end;
$$;

revoke execute on function public.consume_scan_credit() from public;
grant execute on function public.consume_scan_credit() to authenticated;

-- 6. Refund a reserved credit when analysis fails after the consume.
-- Deliberately not callable by end users: a user who could call this directly
-- would be able to mint unlimited scans.
create or replace function public.refund_scan_credit(
  p_user_id uuid,
  p_purchased boolean default false
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_remaining int;
begin
  if p_purchased then
    update public.profiles
       set photo_purchased = photo_purchased + case when photo_credit_debt > 0 then 0 else 1 end,
           photo_credit_debt = greatest(photo_credit_debt - 1,0),
           updated_at = timezone('utc'::text, now())
     where id = p_user_id
    returning photo_purchased into v_remaining;
  else
    update public.profiles
       set free_scans_remaining = free_scans_remaining + 1,
           photo_included_used_week = greatest(0, photo_included_used_week - 1),
           updated_at = timezone('utc'::text, now())
     where id = p_user_id
    returning free_scans_remaining into v_remaining;
  end if;

  if not found then
    return jsonb_build_object('refunded', false);
  end if;

  return jsonb_build_object('refunded', true, 'remaining', v_remaining);
end;
$$;

revoke execute on function public.refund_scan_credit(uuid, boolean) from public;
revoke execute on function public.refund_scan_credit(uuid, boolean) from anon, authenticated;
grant execute on function public.refund_scan_credit(uuid, boolean) to service_role;

-- 7. Weekly free scan reset, invoked by a scheduled job under service_role.
create or replace function public.reset_weekly_free_scans(p_default_scans int default 3)
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int:=0;
begin
  for r in select id from public.profiles where quota_week < date_trunc('week',now() at time zone 'UTC')::date for update skip locked loop
    perform public.refresh_user_quota(r.id); n:=n+1;
  end loop;
  return n;
end;
$$;

revoke execute on function public.reset_weekly_free_scans(int) from public;
revoke execute on function public.reset_weekly_free_scans(int) from anon, authenticated;
grant execute on function public.reset_weekly_free_scans(int) to service_role;

create or replace function public.consume_food_score_credit()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_is_pro boolean;
  v_promo_until timestamp with time zone;
  v_entitled boolean;
  v_included int;
  v_purchased int;
  v_hour_count int;
  v_hour_started timestamp with time zone;
  v_now timestamp with time zone := timezone('utc'::text, now());
  v_used_purchased boolean := false;
begin
  if v_uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'unauthenticated');
  end if;

  perform public.refresh_user_quota(v_uid);
  select is_pro, promo_pro_until, text_included_remaining, text_purchased,
         foods_hour_count, foods_hour_started_at
    into v_is_pro, v_promo_until, v_included, v_purchased,
         v_hour_count, v_hour_started
  from public.profiles
  where id = v_uid
  for update;

  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'no_profile');
  end if;

  v_entitled := v_is_pro
    or (v_promo_until is not null
        and v_promo_until > v_now);

  if not v_entitled and v_included > 20 then
    v_included := 20;
  end if;

  if v_hour_started is null or v_now - v_hour_started >= interval '1 hour' then
    v_hour_count := 0;
    v_hour_started := v_now;
  end if;

  if v_hour_count >= 20 then
    return jsonb_build_object(
      'allowed', false, 'reason', 'rate_limited',
      'is_pro', v_entitled,
      'text_remaining', v_included,
      'text_purchased', v_purchased
    );
  end if;

  if v_included > 0 and (v_entitled or private.has_device_eligibility(v_uid)) then
    v_included := v_included - 1;
  elsif v_purchased > 0 then
    v_used_purchased := true;
    v_purchased := v_purchased - 1;
  else
    return jsonb_build_object(
      'allowed', false, 'reason', case when not v_entitled and not private.has_device_eligibility(v_uid) then 'device_required' else 'quota_exceeded' end,
      'is_pro', v_entitled,
      'text_remaining', 0, 'text_purchased', 0
    );
  end if;

  update public.profiles
     set text_included_remaining = v_included,
         text_included_used_week = case when v_used_purchased then text_included_used_week else least(100, text_included_used_week + 1) end,
         text_purchased = v_purchased,
         foods_hour_count = v_hour_count + 1,
         foods_hour_started_at = v_hour_started,
         updated_at = v_now
   where id = v_uid;

  return jsonb_build_object(
    'allowed', true,
    'is_pro', v_entitled,
    'text_remaining', v_included,
    'text_purchased', v_purchased,
    'used_purchased', v_used_purchased
  );
end;
$$;

revoke execute on function public.consume_food_score_credit() from public;
grant execute on function public.consume_food_score_credit() to authenticated;

create or replace function public.refund_food_score_credit(
  p_user_id uuid,
  p_purchased boolean default false
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
begin
  if p_purchased then
    update public.profiles
       set text_purchased = text_purchased + case when text_credit_debt > 0 then 0 else 1 end,
           text_credit_debt = greatest(text_credit_debt - 1,0),
           foods_hour_count = greatest(foods_hour_count - 1, 0),
           updated_at = timezone('utc'::text, now())
     where id = p_user_id;
  else
    update public.profiles
       set text_included_remaining = text_included_remaining + 1,
           text_included_used_week = greatest(0, text_included_used_week - 1),
           foods_hour_count = greatest(foods_hour_count - 1, 0),
           updated_at = timezone('utc'::text, now())
     where id = p_user_id;
  end if;
  return jsonb_build_object('refunded', true);
end;
$$;

revoke execute on function public.refund_food_score_credit(uuid, boolean) from public;
revoke execute on function public.refund_food_score_credit(uuid, boolean)
  from anon, authenticated;
grant execute on function public.refund_food_score_credit(uuid, boolean) to service_role;

create table if not exists public.credit_grant_events (
  event_id text primary key,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.credit_grant_events enable row level security;

create or replace function public.add_purchased_credits(
  p_user_id uuid,
  p_event_id text,
  p_photo int default 0,
  p_text int default 0
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
begin
  if p_event_id is null or length(trim(p_event_id)) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'missing_event');
  end if;

  insert into public.credit_grant_events (event_id) values (p_event_id)
  on conflict (event_id) do nothing;

  if not found then
    return jsonb_build_object('ok', true, 'duplicate', true);
  end if;

  update public.profiles
     set photo_purchased = photo_purchased + greatest(p_photo, 0),
         text_purchased = text_purchased + greatest(p_text, 0),
         updated_at = timezone('utc'::text, now())
   where id = p_user_id;

  if not found then
    delete from public.credit_grant_events where event_id = p_event_id;
    return jsonb_build_object('ok', false, 'reason', 'no_profile');
  end if;

  return jsonb_build_object('ok', true, 'duplicate', false);
end;
$$;

revoke execute on function public.add_purchased_credits(uuid, text, int, int)
  from public, anon, authenticated;
grant execute on function public.add_purchased_credits(uuid, text, int, int)
  to service_role;

-- 8. Judge / reviewer promo codes
-- The plaintext never lives in the app binary or this file. Only the SHA-256
-- of the normalised (trim + upper) code is stored. Clients call
-- redeem_promo_code, which writes promo_pro_until and never touches is_pro,
-- so a RevenueCat webhook cannot clobber a redeemed review grant.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.promo_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  label text not null,
  max_redemptions int not null default 5000,
  redemption_count int not null default 0,
  grants_days int not null default 90,
  expires_at timestamp with time zone not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create table if not exists public.promo_redemptions (
  code_id uuid not null references public.promo_codes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  redeemed_at timestamp with time zone default timezone('utc'::text, now()) not null,
  primary key (code_id, user_id)
);

alter table public.promo_codes enable row level security;
alter table public.promo_redemptions enable row level security;

create or replace function public.redeem_promo_code(p_code text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_hash text;
  v_code public.promo_codes%rowtype;
  v_already boolean;
  v_until timestamp with time zone;
begin
  if v_uid is null then
    return jsonb_build_object('redeemed', false, 'reason', 'unauthenticated');
  end if;

  if p_code is null or length(btrim(p_code)) = 0 then
    return jsonb_build_object('redeemed', false, 'reason', 'invalid');
  end if;

  v_hash := encode(extensions.digest(upper(btrim(p_code)), 'sha256'), 'hex');

  select * into v_code
    from public.promo_codes
   where code_hash = v_hash
   for update;

  if not found then
    return jsonb_build_object('redeemed', false, 'reason', 'invalid');
  end if;

  -- Collapse expired and exhausted into invalid so the client cannot probe
  -- which failure mode it hit.
  if v_code.expires_at <= timezone('utc'::text, now()) then
    return jsonb_build_object('redeemed', false, 'reason', 'invalid');
  end if;

  select exists(
    select 1
      from public.promo_redemptions
     where code_id = v_code.id
       and user_id = v_uid
  ) into v_already;

  if not v_already and v_code.redemption_count >= v_code.max_redemptions then
    return jsonb_build_object('redeemed', false, 'reason', 'invalid');
  end if;

  if v_already then
    select redeemed_at + make_interval(days => v_code.grants_days)
      into v_until from public.promo_redemptions
      where code_id = v_code.id and user_id = v_uid;
    return jsonb_build_object('redeemed', v_until > now(), 'is_pro', v_until > now(), 'until', v_until, 'duplicate', true);
  end if;
  v_until := now() + make_interval(days => v_code.grants_days);

  if not v_already then
    insert into public.promo_redemptions (code_id, user_id)
    values (v_code.id, v_uid);
    update public.promo_codes
       set redemption_count = redemption_count + 1
     where id = v_code.id;
  end if;

  update public.profiles
     set promo_pro_until = v_until,
         free_scans_remaining = greatest(free_scans_remaining, 75),
         text_included_remaining = greatest(text_included_remaining, 100),
         updated_at = timezone('utc'::text, now())
   where id = v_uid;

  if not found then
    return jsonb_build_object('redeemed', false, 'reason', 'no_profile');
  end if;

  return jsonb_build_object(
    'redeemed', true,
    'is_pro', true,
    'until', v_until
  );
end;
$$;

revoke execute on function public.redeem_promo_code(text) from public;
revoke execute on function public.redeem_promo_code(text) from anon;
grant execute on function public.redeem_promo_code(text) to authenticated;

-- 9. RevenueCat webhook deduplication
-- Deliveries are at least once and retries reuse the same event id, so without
-- this a retried delivery would be applied twice.
create table if not exists public.processed_webhook_events (
  event_id text primary key,
  event_type text,
  environment text,
  received_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.processed_webhook_events enable row level security;

-- Deliberately no policies. Only the webhook touches this, through the function
-- below, and service_role bypasses RLS.

-- 10. Apply a RevenueCat entitlement change
-- Claims the event id and applies the entitlement in one statement pair so a
-- concurrent retry cannot both pass the duplicate check.
--
-- p_candidate_ids carries app_user_id, original_app_user_id and aliases, because
-- a purchase made before sign-in arrives under a RevenueCat anonymous id with
-- the real user id only present among the aliases.
drop function if exists public.apply_revenuecat_event(text, text, text, uuid[], boolean);
create or replace function public.apply_revenuecat_event(
  p_event_id text,
  p_event_type text,
  p_environment text,
  p_candidate_ids uuid[],
  p_is_pro boolean,
  p_expires_at timestamptz,
  p_event_ms bigint
)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_updated int;
begin
  if p_event_id is null or p_event_id = '' then
    return jsonb_build_object('status', 'invalid', 'reason', 'missing_event_id');
  end if;

  -- Roll the allowance forward before applying an event from a new week.
  if p_candidate_ids is not null then
    perform public.refresh_user_quota(id)
      from unnest(p_candidate_ids) as candidate(id)
     where exists(select 1 from public.profiles p where p.id = candidate.id);
  end if;

  insert into public.processed_webhook_events (event_id, event_type, environment)
  values (p_event_id, p_event_type, p_environment)
  on conflict (event_id) do nothing;

  if not found then
    return jsonb_build_object('status', 'duplicate');
  end if;

  update public.profiles
     set is_pro = p_is_pro,
         subscription_expires_at = p_expires_at,
         subscription_event_ms = p_event_ms,
         subscription_environment = p_environment,
         free_scans_remaining = case
           when p_is_pro
           then greatest(free_scans_remaining, 75 - coalesce(photo_included_used_week, 0))
           when not p_is_pro and not coalesce(promo_pro_until > now(), false) then least(free_scans_remaining, 3)
           else free_scans_remaining end,
         text_included_remaining = case
           when p_is_pro
           then greatest(text_included_remaining, 100 - coalesce(text_included_used_week, 0))
           when not p_is_pro and not coalesce(promo_pro_until > now(), false) then least(text_included_remaining, 20)
           else text_included_remaining end,
         pro_credit_week = case when p_is_pro then date_trunc('week', now() at time zone 'UTC')::date else pro_credit_week end,
         updated_at = now()
   where id = (select id from unnest(p_candidate_ids) with ordinality candidates(id, position) where exists(select 1 from public.profiles p where p.id=candidates.id) order by position limit 1)
     and subscription_event_ms <= p_event_ms
     and (p_environment='PRODUCTION' or subscription_environment is distinct from 'PRODUCTION'
          or not (is_pro and (subscription_expires_at is null or subscription_expires_at > now())));

  get diagnostics v_updated = row_count;
  if v_updated = 0 and exists(select 1 from public.profiles where id = any(p_candidate_ids)) then
    return jsonb_build_object('status', 'stale');
  end if;

  if v_updated = 0 then
    -- Release the claim so a retry can be processed. A purchase can arrive
    -- before the profile row exists, and keeping the claim would make every
    -- retry look like a duplicate and lose the entitlement permanently.
    delete from public.processed_webhook_events where event_id = p_event_id;
    return jsonb_build_object('status', 'no_profile');
  end if;

  return jsonb_build_object(
    'status', 'applied', 'is_pro', p_is_pro, 'profiles_updated', v_updated
  );
end;
$$;

revoke execute on function public.apply_revenuecat_event(
  text, text, text, uuid[], boolean, timestamptz, bigint
) from public;
revoke execute on function public.apply_revenuecat_event(
  text, text, text, uuid[], boolean, timestamptz, bigint
) from anon, authenticated;
grant execute on function public.apply_revenuecat_event(
  text, text, text, uuid[], boolean, timestamptz, bigint
) to service_role;

-- Legacy clients read the authoritative ledger through this compatibility RPC.
create or replace function public.reconcile_expired_entitlement()
returns jsonb language plpgsql security definer set search_path = public as $$
declare q jsonb; promo_live boolean;
begin
 q := public.get_my_quota();
 if q is null then return jsonb_build_object('ok',false,'reason','no_profile'); end if;
 promo_live := coalesce((q->>'promo_pro_until')::timestamptz > now(),false);
 return q || jsonb_build_object('ok',true,'promo_live',promo_live,'is_pro',coalesce((q->>'is_pro')::boolean,false) or promo_live);
end;
$$;
revoke execute on function public.reconcile_expired_entitlement() from public, anon;
grant execute on function public.reconcile_expired_entitlement() to authenticated;

-- Rows that already lost entitlement but still hold leftover Pro meters.
-- Real Pro rows are left alone. A missed expire is healed by the function
-- above the next time the store says the grant is gone.
update public.profiles
   set is_pro = false,
       free_scans_remaining = least(greatest(free_scans_remaining, 0), 3),
       text_included_remaining = least(greatest(text_included_remaining, 0), 20),
       updated_at = timezone('utc'::text, now())
 where not (
         is_pro
         or (promo_pro_until is not null
             and promo_pro_until > timezone('utc'::text, now()))
       )
   and (free_scans_remaining > 3 or text_included_remaining > 20);

-- 11. Table privileges
-- The project is configured with "Automatically expose new tables" disabled, so
-- tables carry no Data API privileges by default and every privilege the app
-- needs is stated here. Grants are the outer gate: a policy can only permit
-- what is granted below, so this is deliberately narrower than the policies.
grant usage on schema public to anon, authenticated, service_role;

-- anon is the pre sign-in role and reads nothing: the app authenticates first.

-- profiles: read only. Reads are needed so a client can see its own
-- entitlement and remaining quota.
grant select on public.profiles to authenticated;

-- meals: the client updates a row when the same plate is saved again.
grant select, insert, update, delete on public.meals to authenticated;

-- terrarium: progression is upserted, never deleted by the client. Account
-- deletion is handled by the cascade from auth.users.
grant select, insert, update on public.terrarium to authenticated;

-- service_role backs the edge functions, which own entitlement writes.
grant select, insert, update, delete on public.profiles to service_role;
grant select, insert, update, delete on public.meals to service_role;
grant select, insert, update, delete on public.terrarium to service_role;

-- The webhook ledger is server only. anon and authenticated get nothing, so a
-- client cannot read purchase history or forge a duplicate suppression entry.
revoke all on public.processed_webhook_events from anon, authenticated;
grant select, insert, delete on public.processed_webhook_events to service_role;

-- Promo tables are server only. Clients redeem through the function, which
-- runs as security definer, so they never need table privileges.
revoke all on public.promo_codes from anon, authenticated;
revoke all on public.promo_redemptions from anon, authenticated;

create index if not exists meals_owner_created on public.meals(user_id, created_at, id);
create index if not exists meals_owner_local_id on public.meals(user_id, (satiety_result->'_evenplate'->>'id'));

alter table public.meals add column if not exists local_id text;
update public.meals set local_id = coalesce(satiety_result->'_evenplate'->>'id', id::text) where local_id is null;
create unique index if not exists meals_owner_identity on public.meals(user_id, local_id);
-- Durable analysis reservations. Only the caller can reserve, only the server can settle.
create table if not exists public.analysis_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  kind text not null check(kind in ('photo','text')),
  status text not null default 'reserved' check(status in ('reserved','complete','refunded')),
  purchased boolean not null,
  quota_week date not null,
  response jsonb,
  created_at timestamptz not null default now(),
  primary key(user_id, request_id)
);
-- Recover current-week usage before enabling the durable counters. The
-- reservation ledger retains the whole current week, including refunded rows.
update public.profiles p set
  photo_included_used_week = coalesce(p.photo_included_used_week, (
    select least(75, count(*)::int) from public.analysis_requests r
     where r.user_id = p.id and r.kind = 'photo' and not r.purchased
       and r.status <> 'refunded' and r.quota_week = p.quota_week
  )),
  text_included_used_week = coalesce(p.text_included_used_week, (
    select least(100, count(*)::int) from public.analysis_requests r
     where r.user_id = p.id and r.kind = 'text' and not r.purchased
       and r.status <> 'refunded' and r.quota_week = p.quota_week
  ))
where p.photo_included_used_week is null or p.text_included_used_week is null;
alter table public.profiles alter column photo_included_used_week set default 0;
alter table public.profiles alter column text_included_used_week set default 0;
alter table public.profiles alter column photo_included_used_week set not null;
alter table public.profiles alter column text_included_used_week set not null;
alter table public.analysis_requests enable row level security;
revoke all on public.analysis_requests from anon, authenticated;
grant select, insert, update, delete on public.analysis_requests to service_role;
create index if not exists analysis_requests_pending on public.analysis_requests(created_at) where status = 'reserved';

create or replace function public.settle_analysis_request(p_user_id uuid, p_request_id uuid, p_success boolean, p_response jsonb default null, p_meal jsonb default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.analysis_requests%rowtype;
begin
  -- Lock the owner first, matching the reservation lock order.
  perform 1 from public.profiles where id = p_user_id for update;
  select * into v from public.analysis_requests where user_id = p_user_id and request_id = p_request_id for update;
  if not found then return jsonb_build_object('ok',false,'reason','missing_request'); end if;
  if v.status <> 'reserved' then return jsonb_build_object('ok',true,'duplicate',true,'response',v.response); end if;
  if p_success then
    if p_response is null then raise exception 'Successful analysis needs response'; end if;
    if p_meal is not null then
      insert into public.meals(user_id,local_id,meal_name,satiety_score,duration_hours,satiety_result)
      values(p_user_id,p_request_id::text,p_meal->>'mealName',(p_meal->>'satietyScore')::int,(p_meal->>'durationHours')::numeric,p_meal)
      on conflict(user_id,local_id) do nothing;
    end if;
    update public.analysis_requests set status='complete',response=p_response where user_id=p_user_id and request_id=p_request_id;
  else
    -- An included credit from an old week cannot inflate the new allowance.
    if v.purchased or v.quota_week = date_trunc('week', now() at time zone 'UTC')::date then
      if v.kind='photo' then perform public.refund_scan_credit(p_user_id,v.purchased);
      else perform public.refund_food_score_credit(p_user_id,v.purchased); end if;
    end if;
    update public.analysis_requests set status='refunded' where user_id=p_user_id and request_id=p_request_id;
  end if;
  return jsonb_build_object('ok',true);
end;
$$;
revoke all on function public.settle_analysis_request(uuid,uuid,boolean,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.settle_analysis_request(uuid,uuid,boolean,jsonb,jsonb) to service_role;

create or replace function public.reserve_analysis_request(p_request_id uuid,p_kind text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid:=auth.uid(); v public.analysis_requests%rowtype; q jsonb; old record;
begin
  if v_uid is null or p_kind not in ('photo','text') or p_request_id is null then return jsonb_build_object('allowed',false,'reason','invalid'); end if;
  perform 1 from public.profiles where id=v_uid for update;
  for old in select request_id from public.analysis_requests where user_id=v_uid and status='reserved' and created_at < now()-interval '2 minutes' loop
    perform public.settle_analysis_request(v_uid,old.request_id,false);
  end loop;
  select * into v from public.analysis_requests where user_id=v_uid and request_id=p_request_id;
  if found then
    if v.kind<>p_kind then return jsonb_build_object('allowed',false,'reason','request_mismatch'); end if;
    return jsonb_build_object('allowed',false,'reason',v.status,'response',v.response);
  end if;
  if p_kind='photo' then q:=public.consume_scan_credit(); else q:=public.consume_food_score_credit(); end if;
  if q->>'allowed'='true' then
    insert into public.analysis_requests(user_id,request_id,kind,purchased,quota_week)
    values(v_uid,p_request_id,p_kind,coalesce((q->>'used_purchased')::boolean,false),date_trunc('week',now() at time zone 'UTC')::date);
  end if;
  return q;
end;
$$;
revoke all on function public.reserve_analysis_request(uuid,text) from public,anon;
grant execute on function public.reserve_analysis_request(uuid,text) to authenticated;

create or replace function public.recover_analysis_reservations()
returns int language plpgsql security definer set search_path = public as $$
declare v record; n int:=0;
begin
  for v in select r.user_id,r.request_id from public.analysis_requests r join public.profiles p on p.id=r.user_id where r.status='reserved' and r.created_at < now()-interval '2 minutes' order by r.user_id for update of p skip locked loop
    perform public.settle_analysis_request(v.user_id,v.request_id,false); n:=n+1;
  end loop;
  delete from public.analysis_requests where status <> 'reserved' and created_at < now()-interval '7 days';
  return n;
end;
$$;
revoke all on function public.recover_analysis_reservations() from public,anon,authenticated;
grant execute on function public.recover_analysis_reservations() to service_role;

-- Purchased credits are settled once per store transaction, including refund-before-purchase deliveries.
alter table public.profiles add column if not exists photo_credit_debt int not null default 0;
alter table public.profiles add column if not exists text_credit_debt int not null default 0;
create table if not exists public.credit_purchases (
 transaction_key text primary key, user_id uuid references auth.users(id) on delete cascade,
 photo int not null, text int not null, refunded boolean not null default false,
 granted boolean not null default false, created_at timestamptz not null default now()
);
alter table public.credit_purchases enable row level security;
revoke all on public.credit_purchases from anon, authenticated;
grant all on public.credit_purchases to service_role;
create or replace function public.apply_credit_purchase(p_user_id uuid,p_transaction text,p_photo int,p_text int,p_refund boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v public.credit_purchases%rowtype; p public.profiles%rowtype;
begin
 select * into p from public.profiles where id=p_user_id for update;
 if not found then return jsonb_build_object('ok',false,'reason','no_profile'); end if;
 insert into public.credit_purchases(transaction_key,user_id,photo,text,refunded)
 values(p_transaction,p_user_id,p_photo,p_text,p_refund) on conflict do nothing;
 select * into v from public.credit_purchases where transaction_key=p_transaction for update;
 if v.user_id<>p_user_id then return jsonb_build_object('ok',false,'reason','identity_mismatch'); end if;
 if p_refund then
   if v.granted and not v.refunded then
     update public.profiles set photo_purchased=greatest(photo_purchased-v.photo,0),text_purchased=greatest(text_purchased-v.text,0),
      photo_credit_debt=photo_credit_debt+greatest(v.photo-photo_purchased,0),text_credit_debt=text_credit_debt+greatest(v.text-text_purchased,0) where id=p_user_id;
   end if;
   update public.credit_purchases set refunded=true where transaction_key=p_transaction;
 elsif not v.granted and not v.refunded then
   update public.profiles set photo_purchased=photo_purchased+greatest(v.photo-photo_credit_debt,0),text_purchased=text_purchased+greatest(v.text-text_credit_debt,0),
    photo_credit_debt=greatest(photo_credit_debt-v.photo,0),text_credit_debt=greatest(text_credit_debt-v.text,0) where id=p_user_id;
   update public.credit_purchases set granted=true where transaction_key=p_transaction;
 end if;
 return jsonb_build_object('ok',true);
end;
$$;
revoke all on function public.apply_credit_purchase(uuid,text,int,int,boolean) from public,anon,authenticated;
grant execute on function public.apply_credit_purchase(uuid,text,int,int,boolean) to service_role;

-- Customer settings sync independently of the server-owned billing ledger.
create table if not exists public.user_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 preferences jsonb not null default '{}'::jsonb check(jsonb_typeof(preferences)='object'),
 updated_at timestamptz not null default now()
);
alter table public.user_preferences enable row level security;
drop policy if exists preferences_owner on public.user_preferences;
create policy preferences_owner on public.user_preferences for all using(auth.uid()=user_id) with check(auth.uid()=user_id);
grant select,insert,update,delete on public.user_preferences to authenticated;
grant all on public.user_preferences to service_role;
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
   if exists(select 1 from cron.job where jobname='evenplate-reset-weekly-free-scans') then
     perform cron.unschedule('evenplate-reset-weekly-free-scans');
   end if;
   perform cron.schedule('evenplate-recover-analysis','* * * * *','select public.recover_analysis_reservations()');
   perform cron.schedule('evenplate-weekly-quota','0 0 * * 1','select public.reset_weekly_free_scans()');
 end if;
end $$;

-- Stable identity and bounded client JSON at the storage boundary.
create or replace function public.set_meal_identity()
returns trigger language plpgsql set search_path=public as $$
begin
 new.local_id := coalesce(nullif(new.local_id,''),nullif(new.satiety_result->'_evenplate'->>'id',''),new.id::text);
 if length(new.local_id)>128 or octet_length(new.satiety_result::text)>65536 then raise exception 'Meal payload is too large'; end if;
 return new;
end;
$$;
create or replace trigger meal_identity before insert or update on public.meals for each row execute function public.set_meal_identity();
-- Quota reads also heal week boundaries without trusting a client entitlement flag.
create or replace function public.get_my_quota()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid(); p public.profiles%rowtype;
begin
 if v_uid is null then return null; end if;
 perform public.refresh_user_quota(v_uid);
 select * into p from public.profiles where id=v_uid;
 if not found then return null; end if;
 return jsonb_build_object('is_pro',p.is_pro,'promo_pro_until',p.promo_pro_until,'free_scans_remaining',p.free_scans_remaining,'photo_purchased',p.photo_purchased,'text_included_remaining',p.text_included_remaining,'text_purchased',p.text_purchased);
end;
$$;
revoke all on function public.get_my_quota() from public,anon;
grant execute on function public.get_my_quota() to authenticated;


-- Shared free usage survives account deletion until the weekly window expires.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.quota_identity_secret (
 singleton boolean primary key default true check(singleton),
 secret bytea not null,
 seeded boolean not null default false
);
revoke all on private.quota_identity_secret from public, anon, authenticated;
insert into private.quota_identity_secret(singleton,secret)
values(true,extensions.gen_random_bytes(32)) on conflict do nothing;
create table if not exists private.free_week_usage (
 identity_key text not null,
 quota_week date not null,
 photo_used int not null default 0 check(photo_used between 0 and 3),
 text_used int not null default 0 check(text_used between 0 and 20),
 expires_at timestamptz not null,
 primary key(identity_key,quota_week)
);
revoke all on private.free_week_usage from public, anon, authenticated;

create or replace function private.quota_identity(p_email text,p_user_id uuid)
returns text language plpgsql security definer set search_path='' as $$
declare mailbox text:=lower(btrim(coalesce(p_email,''))); localpart text; domainpart text; key bytea;
begin
 if mailbox='' then mailbox:='no-email:'||p_user_id::text;
 else
  localpart:=split_part(mailbox,'@',1); domainpart:=split_part(mailbox,'@',2);
  if domainpart in ('gmail.com','googlemail.com') then
   localpart:=replace(split_part(localpart,'+',1),'.','');
   mailbox:=localpart||'@gmail.com';
  end if;
 end if;
 select secret into strict key from private.quota_identity_secret where singleton;
 return encode(extensions.hmac(convert_to(mailbox,'UTF8'),key,'sha256'),'hex');
end;
$$;
revoke all on function private.quota_identity(text,uuid) from public,anon,authenticated;

-- Seed once. Reapplying the schema must never count already-shared usage twice.
do $$ begin
 lock table public.profiles in exclusive mode;
 if not (select seeded from private.quota_identity_secret where singleton for update) then
  insert into private.free_week_usage(identity_key,quota_week,photo_used,text_used,expires_at)
  select private.quota_identity(email,id),quota_week,
   least(3,sum(greatest(0,3-free_scans_remaining)))::int,
   least(20,sum(greatest(0,20-text_included_remaining)))::int,
   (quota_week + 7)::timestamp at time zone 'UTC'
  from public.profiles
  where quota_week=date_trunc('week',now() at time zone 'UTC')::date
   and not (is_pro and (subscription_expires_at is null or subscription_expires_at>now()))
   and not coalesce(promo_pro_until>now(),false)
  group by private.quota_identity(email,id),quota_week
  on conflict do nothing;
  update private.quota_identity_secret set seeded=true where singleton;
 end if;
end $$;

create or replace function private.enforce_free_usage()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 identity text; usage private.free_week_usage%rowtype;
 photo_delta int:=0; text_delta int:=0; was_free boolean:=false;
 v_week date:=date_trunc('week',now() at time zone 'UTC')::date;
begin
 if (new.is_pro and (new.subscription_expires_at is null or new.subscription_expires_at>now()))
  or coalesce(new.promo_pro_until>now(),false) then return new; end if;
 -- Historical quota changes cannot spend the current window.
 if new.quota_week<>v_week then return new; end if;
 identity:=private.quota_identity(new.email,new.id);
 insert into private.free_week_usage(identity_key,quota_week,expires_at)
 values(identity,v_week,(v_week+7)::timestamp at time zone 'UTC') on conflict do nothing;
 select * into strict usage from private.free_week_usage
 where identity_key=identity and quota_week=v_week for update;
 if tg_op='UPDATE' then
  was_free:=not (old.is_pro or coalesce(old.promo_pro_until>now(),false)
   or old.free_scans_remaining>3 or old.text_included_remaining>20);
  if was_free and old.quota_week=new.quota_week then
   photo_delta:=old.free_scans_remaining-new.free_scans_remaining;
   text_delta:=old.text_included_remaining-new.text_included_remaining;
  end if;
 end if;
 usage.photo_used:=least(3,greatest(0,usage.photo_used+photo_delta));
 usage.text_used:=least(20,greatest(0,usage.text_used+text_delta));
 update private.free_week_usage set photo_used=usage.photo_used,text_used=usage.text_used
 where identity_key=identity and quota_week=v_week;
 new.free_scans_remaining:=least(greatest(0,new.free_scans_remaining),3-usage.photo_used);
 new.text_included_remaining:=least(greatest(0,new.text_included_remaining),20-usage.text_used);
 return new;
end;
$$;
revoke all on function private.enforce_free_usage() from public,anon,authenticated;
create or replace trigger shared_free_usage before insert or update on public.profiles
for each row execute function private.enforce_free_usage();

create or replace function public.expire_free_usage()
returns void language sql security definer set search_path='' as $$
 delete from private.free_week_usage where expires_at<=now();
$$;
revoke all on function public.expire_free_usage() from public,anon,authenticated;
grant execute on function public.expire_free_usage() to service_role;
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.schedule('evenplate-expire-free-usage','0 * * * *','select public.expire_free_usage()');
 end if;
end $$;

create schema if not exists private;
create schema if not exists private;
create table if not exists private.device_policy (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 environment text not null default 'production' check(environment in ('production','development'))
);
insert into private.device_policy(singleton) values(true) on conflict do nothing;
create table if not exists private.device_eligibility (
 identity_key text not null,
 environment text not null,
 granted_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '12 months',
 source text not null check(source in ('devicecheck','support')),
 primary key(identity_key,environment)
);
-- One durable admission at a time: Apple does not provide atomic bit increments.
create table if not exists private.device_admission (
 singleton boolean primary key default true check(singleton),
 operation_id uuid not null unique,
 identity_key text,
 environment text not null,
 token_cipher bytea,
 selected_bit int check(selected_bit in (0,1)),
 created_at timestamptz not null default now()
);
create table if not exists private.device_verification (
 user_id uuid primary key references auth.users(id) on delete cascade,
 environment text not null,
 verified_at timestamptz not null default now()
);
revoke all on private.device_policy,private.device_eligibility,private.device_admission,private.device_verification from public,anon,authenticated;

create or replace function private.device_identity(p_user_id uuid)
returns text language plpgsql security definer set search_path='' as $$
declare email text;
begin
 select u.email into email from auth.users u where u.id=p_user_id;
 if not found or email is null then raise exception 'No verified mailbox'; end if;
 return private.quota_identity(email,p_user_id);
end;
$$;
create or replace function private.has_device_eligibility(p_user_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare policy private.device_policy%rowtype;
begin
 select * into policy from private.device_policy where singleton;
 if not policy.enabled then return true; end if;
 return exists(select 1 from private.device_eligibility where identity_key=private.device_identity(p_user_id) and environment=policy.environment and expires_at>now());
end;
$$;
revoke all on function private.device_identity(uuid),private.has_device_eligibility(uuid) from public,anon,authenticated;

create or replace function public.device_access_status(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare policy private.device_policy%rowtype; paid boolean;
begin
 perform public.refresh_user_quota(p_user_id);
 select * into policy from private.device_policy where singleton;
 select is_pro or coalesce(promo_pro_until>now(),false) into paid from public.profiles where id=p_user_id;
 return jsonb_build_object('enabled',policy.enabled,'environment',policy.environment,'paid',coalesce(paid,false),'eligible',private.has_device_eligibility(p_user_id),'photo_purchased',(select photo_purchased from public.profiles where id=p_user_id),'text_purchased',(select text_purchased from public.profiles where id=p_user_id));
end;
$$;
create or replace function public.begin_device_admission(p_user_id uuid,p_token text,p_environment text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare identity text:=private.device_identity(p_user_id); secret text; op private.device_admission%rowtype;
begin
 if p_environment not in ('production','development') or length(p_token)>16384 then raise exception 'Invalid admission'; end if;
 if exists(select 1 from private.device_eligibility where identity_key=identity and environment=p_environment and expires_at>now()) then return jsonb_build_object('status','eligible'); end if;
 select encode(extensions.hmac(convert_to('device-token','UTF8'),s.secret,'sha256'),'hex') into secret from private.quota_identity_secret s where singleton;
 insert into private.device_admission(singleton,operation_id,identity_key,environment,token_cipher)
 values(true,extensions.gen_random_uuid(),identity,p_environment,extensions.pgp_sym_encrypt(p_token,secret)) on conflict do nothing;
 select * into strict op from private.device_admission where singleton for update;
 if op.identity_key<>identity or op.environment<>p_environment then return jsonb_build_object('status','busy'); end if;
 if op.token_cipher is null then return jsonb_build_object('status','support'); end if;
 return jsonb_build_object('status','claim','operation',op.operation_id,'bit',op.selected_bit,'token',extensions.pgp_sym_decrypt(op.token_cipher,secret));
end;
$$;
create or replace function public.select_device_admission_bit(p_operation uuid,p_bit int)
returns int language plpgsql security definer set search_path='' as $$
declare result int;
begin
 if p_bit not in (0,1) then raise exception 'Invalid slot'; end if;
 update private.device_admission set selected_bit=coalesce(selected_bit,p_bit) where operation_id=p_operation returning selected_bit into result;
 if not found then raise exception 'Admission no longer active'; end if;
 return result;
end;
$$;
create or replace function public.finish_device_admission(p_operation uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare op private.device_admission%rowtype;
begin
 select * into op from private.device_admission where operation_id=p_operation for update;
 if not found then return false; end if;
 if op.selected_bit is null then raise exception 'No slot recorded'; end if;
 insert into private.device_eligibility(identity_key,environment,source) values(op.identity_key,op.environment,'devicecheck') on conflict(identity_key,environment) do update set granted_at=excluded.granted_at,expires_at=excluded.expires_at,source=excluded.source where private.device_eligibility.expires_at<=now();
 delete from private.device_admission where operation_id=p_operation;
 return true;
end;
$$;
create or replace function public.abort_device_admission(p_operation uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 -- An uncertain Apple write must be resolved, never automatically reopened.
 delete from private.device_admission where operation_id=p_operation and selected_bit is null;
 return found;
end;
$$;
create or replace function public.record_device_verification(p_user_id uuid,p_environment text)
returns void language sql security definer set search_path='' as $$
 insert into private.device_verification(user_id,environment) values(p_user_id,p_environment)
 on conflict(user_id) do update set environment=excluded.environment,verified_at=now();
$$;
create or replace function public.grant_device_support_exception(p_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 insert into private.device_eligibility(identity_key,environment,source)
 select private.device_identity(p_user_id),environment,'support' from private.device_policy where singleton
 on conflict(identity_key,environment) do update set granted_at=now(),expires_at=now()+interval '12 months',source='support';
end;
$$;
create table if not exists private.device_attempts (
 identity_key text primary key,
 started_at timestamptz not null default now(),
 attempts int not null default 1
);
revoke all on private.device_attempts from public,anon,authenticated;
create or replace function public.take_device_verification_attempt(p_user_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare count int;
begin
 insert into private.device_attempts(identity_key) values(private.device_identity(p_user_id))
 on conflict(identity_key) do update set
 attempts=case when private.device_attempts.started_at<now()-interval '1 hour' then 1 else private.device_attempts.attempts+1 end,
 started_at=case when private.device_attempts.started_at<now()-interval '1 hour' then now() else private.device_attempts.started_at end
 returning attempts into count;
 return count<=20;
end;
$$;
revoke all on function public.take_device_verification_attempt(uuid) from public,anon,authenticated;
grant execute on function public.take_device_verification_attempt(uuid) to service_role;

create or replace function public.expire_device_eligibility()
returns void language plpgsql security definer set search_path='' as $$
begin
 delete from private.device_eligibility where expires_at<=now();
 delete from private.device_verification where verified_at<now()-interval '1 hour';
 delete from private.device_attempts where started_at<now()-interval '1 hour';
 -- Purge ephemeral token material without reopening an ambiguous consumed slot.
 update private.device_admission set token_cipher=null,identity_key=null where created_at<now()-interval '15 minutes';
end;
$$;
revoke all on function public.device_access_status(uuid),public.begin_device_admission(uuid,text,text),public.select_device_admission_bit(uuid,int),public.finish_device_admission(uuid),public.abort_device_admission(uuid),public.record_device_verification(uuid,text),public.grant_device_support_exception(uuid),public.expire_device_eligibility() from public,anon,authenticated;
grant execute on function public.device_access_status(uuid),public.begin_device_admission(uuid,text,text),public.select_device_admission_bit(uuid,int),public.finish_device_admission(uuid),public.abort_device_admission(uuid),public.record_device_verification(uuid,text),public.grant_device_support_exception(uuid),public.expire_device_eligibility() to service_role;
do $$ begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.schedule('evenplate-expire-device-eligibility','* * * * *','select public.expire_device_eligibility()');
 end if;
end $$;
