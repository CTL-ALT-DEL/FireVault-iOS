-- Server-owned App Store subscription state and staged paid-feature enforcement.
--
-- Rollout safety: enforcement starts disabled. Deploy the entitlement Edge
-- Functions and an iOS build that links StoreKit transactions first, verify
-- user_subscription_access rows, then enable the singleton setting.

create table public.subscription_enforcement_settings (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false,
  updated_at timestamp with time zone not null default now(),
  constraint subscription_enforcement_singleton check (singleton = true)
);

insert into public.subscription_enforcement_settings (singleton, enabled)
values (true, false)
on conflict (singleton) do nothing;

comment on table public.subscription_enforcement_settings is
  'Publicly readable rollout flag. Only trusted server/admin roles may change it.';

alter table public.subscription_enforcement_settings enable row level security;

create policy "Authenticated users can read subscription enforcement status"
on public.subscription_enforcement_settings for select
to authenticated
using (true);

revoke all on table public.subscription_enforcement_settings from anon, authenticated;
grant select on table public.subscription_enforcement_settings to authenticated;

create table public.user_subscription_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  provider text not null default 'app_store' check (provider = 'app_store'),
  product_id text not null check (
    product_id in (
      'us.bannerman.firevault.technician.monthly',
      'us.bannerman.firevault.technician.annual'
    )
  ),
  status text not null check (
    status in ('active', 'grace_period', 'billing_retry', 'expired', 'revoked')
  ),
  environment text not null check (environment in ('Production', 'Sandbox')),
  original_transaction_id text not null unique,
  latest_transaction_id text not null,
  app_account_token uuid,
  expires_at timestamp with time zone,
  grace_period_expires_at timestamp with time zone,
  revoked_at timestamp with time zone,
  auto_renew_enabled boolean,
  offer_type integer,
  source_signed_at timestamp with time zone not null,
  last_verified_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create unique index user_subscription_access_latest_transaction_idx
  on public.user_subscription_access (latest_transaction_id);

create index user_subscription_access_active_idx
  on public.user_subscription_access (user_id, status, expires_at, grace_period_expires_at);

comment on table public.user_subscription_access is
  'Server-verified App Store subscription state. Clients may read only their own row.';

alter table public.user_subscription_access enable row level security;

create policy "Users can read their verified subscription"
on public.user_subscription_access for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on table public.user_subscription_access from anon, authenticated;
grant select on table public.user_subscription_access to authenticated;

create table public.app_store_notification_events (
  notification_uuid uuid primary key,
  notification_type text,
  subtype text,
  environment text,
  signed_at timestamp with time zone,
  user_id uuid references auth.users(id) on delete set null,
  original_transaction_id text,
  latest_transaction_id text,
  processed_at timestamp with time zone not null default now()
);

comment on table public.app_store_notification_events is
  'Idempotency ledger for cryptographically verified App Store Server Notifications V2.';

alter table public.app_store_notification_events enable row level security;
revoke all on table public.app_store_notification_events from public, anon, authenticated;

create or replace function public.upsert_app_store_subscription_access(
  p_user_id uuid,
  p_product_id text,
  p_status text,
  p_environment text,
  p_original_transaction_id text,
  p_latest_transaction_id text,
  p_app_account_token uuid,
  p_expires_at timestamp with time zone,
  p_grace_period_expires_at timestamp with time zone,
  p_revoked_at timestamp with time zone,
  p_auto_renew_enabled boolean,
  p_offer_type integer,
  p_source_signed_at timestamp with time zone
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into public.user_subscription_access (
    user_id,
    product_id,
    status,
    environment,
    original_transaction_id,
    latest_transaction_id,
    app_account_token,
    expires_at,
    grace_period_expires_at,
    revoked_at,
    auto_renew_enabled,
    offer_type,
    source_signed_at,
    last_verified_at,
    updated_at
  ) values (
    p_user_id,
    p_product_id,
    p_status,
    p_environment,
    p_original_transaction_id,
    p_latest_transaction_id,
    p_app_account_token,
    p_expires_at,
    p_grace_period_expires_at,
    p_revoked_at,
    p_auto_renew_enabled,
    p_offer_type,
    p_source_signed_at,
    now(),
    now()
  )
  on conflict (user_id) do update
  set product_id = excluded.product_id,
      status = excluded.status,
      environment = excluded.environment,
      original_transaction_id = excluded.original_transaction_id,
      latest_transaction_id = excluded.latest_transaction_id,
      app_account_token = coalesce(
        excluded.app_account_token,
        public.user_subscription_access.app_account_token
      ),
      expires_at = excluded.expires_at,
      grace_period_expires_at = excluded.grace_period_expires_at,
      revoked_at = excluded.revoked_at,
      auto_renew_enabled = excluded.auto_renew_enabled,
      offer_type = excluded.offer_type,
      source_signed_at = excluded.source_signed_at,
      last_verified_at = now(),
      updated_at = now()
  where excluded.source_signed_at >= public.user_subscription_access.source_signed_at;

  return found;
end;
$$;

comment on function public.upsert_app_store_subscription_access(
  uuid, text, text, text, text, text, uuid, timestamp with time zone,
  timestamp with time zone, timestamp with time zone, boolean, integer,
  timestamp with time zone
) is 'Service-role-only monotonic update for Apple-verified subscription state.';

revoke all on function public.upsert_app_store_subscription_access(
  uuid, text, text, text, text, text, uuid, timestamp with time zone,
  timestamp with time zone, timestamp with time zone, boolean, integer,
  timestamp with time zone
) from public, anon, authenticated;
grant execute on function public.upsert_app_store_subscription_access(
  uuid, text, text, text, text, text, uuid, timestamp with time zone,
  timestamp with time zone, timestamp with time zone, boolean, integer,
  timestamp with time zone
) to service_role;

create or replace function public.current_user_has_cloud_write_access()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select
    not coalesce((
      select settings.enabled
      from public.subscription_enforcement_settings as settings
      where settings.singleton = true
    ), false)
    or exists (
      select 1
      from public.user_subscription_access as access
      where access.user_id = (select auth.uid())
        and (
          (
            access.status = 'active'
            and access.revoked_at is null
            and access.expires_at > now()
          )
          or (
            access.status = 'grace_period'
            and access.revoked_at is null
            and access.grace_period_expires_at > now()
          )
        )
    );
$$;

comment on function public.current_user_has_cloud_write_access() is
  'True during staged rollout or when the authenticated user has current verified paid access.';

revoke all on function public.current_user_has_cloud_write_access()
  from public, anon, authenticated;
grant execute on function public.current_user_has_cloud_write_access()
  to authenticated;

create or replace function public.get_my_subscription_access()
returns table (
  enforcement_enabled boolean,
  cloud_writes_allowed boolean,
  has_active_entitlement boolean,
  status text,
  product_id text,
  expires_at timestamp with time zone,
  grace_period_expires_at timestamp with time zone,
  auto_renew_enabled boolean,
  last_verified_at timestamp with time zone
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    settings.enabled,
    public.current_user_has_cloud_write_access(),
    coalesce(
      access.revoked_at is null
      and (
        (access.status = 'active' and access.expires_at > now())
        or (
          access.status = 'grace_period'
          and access.grace_period_expires_at > now()
        )
      ),
      false
    ),
    coalesce(access.status, 'not_subscribed'),
    access.product_id,
    access.expires_at,
    access.grace_period_expires_at,
    access.auto_renew_enabled,
    access.last_verified_at
  from public.subscription_enforcement_settings as settings
  left join public.user_subscription_access as access
    on access.user_id = (select auth.uid())
  where settings.singleton = true;
$$;

comment on function public.get_my_subscription_access() is
  'Returns the authenticated user''s sanitized server entitlement and rollout state.';

revoke all on function public.get_my_subscription_access()
  from public, anon, authenticated;
grant execute on function public.get_my_subscription_access()
  to authenticated;

-- Account records: preserve read and deletion access, require paid access for
-- creating or changing cloud copies.
drop policy if exists "Users create their own accounts" on public.accounts;
create policy "Users create their own accounts"
on public.accounts for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users update their own accounts" on public.accounts;
create policy "Users update their own accounts"
on public.accounts for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users create their own account files" on public.account_files;
create policy "Users create their own account files"
on public.account_files for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users update their own account files" on public.account_files;
create policy "Users update their own account files"
on public.account_files for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users can create their cloud vault snapshots" on public.cloud_vault_snapshots;
create policy "Users can create their cloud vault snapshots"
on public.cloud_vault_snapshots for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users create their own CSV imports" on public.csv_import_jobs;
create policy "Users create their own CSV imports"
on public.csv_import_jobs for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users update their own CSV imports" on public.csv_import_jobs;
create policy "Users update their own CSV imports"
on public.csv_import_jobs for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Technicians manage their Trip Log days" on public.trip_log_days;

create policy "Technicians read their Trip Log days"
on public.trip_log_days for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Technicians create their Trip Log days"
on public.trip_log_days for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

create policy "Technicians update their Trip Log days"
on public.trip_log_days for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

create policy "Technicians delete their Trip Log days"
on public.trip_log_days for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users create their own trip files" on public.trip_log_files;
create policy "Users create their own trip files"
on public.trip_log_files for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users update their own trip files" on public.trip_log_files;
create policy "Users update their own trip files"
on public.trip_log_files for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and public.current_user_has_cloud_write_access()
);

-- Storage bytes follow the same rule. SELECT and DELETE policies are left
-- unchanged so inactive users can download or remove their own files.
drop policy if exists "FireVault users can upload own cloud files" on storage.objects;
create policy "FireVault users can upload own cloud files"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'firevault-user-files'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (storage.foldername(name))[2] = 'accounts'
  and (storage.foldername(name))[4] = any (
    array['documents', 'photos', 'scans', 'reports', 'other']::text[]
  )
  and exists (
    select 1
    from public.accounts as account
    where account.user_id = (select auth.uid())
      and account.id::text = (storage.foldername(name))[3]
  )
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "FireVault users can update own cloud files" on storage.objects;
create policy "FireVault users can update own cloud files"
on storage.objects for update
to authenticated
using (
  bucket_id = 'firevault-user-files'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (storage.foldername(name))[2] = 'accounts'
  and (storage.foldername(name))[4] = any (
    array['documents', 'photos', 'scans', 'reports', 'other']::text[]
  )
  and exists (
    select 1
    from public.accounts as account
    where account.user_id = (select auth.uid())
      and account.id::text = (storage.foldername(name))[3]
  )
)
with check (
  bucket_id = 'firevault-user-files'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and (storage.foldername(name))[2] = 'accounts'
  and (storage.foldername(name))[4] = any (
    array['documents', 'photos', 'scans', 'reports', 'other']::text[]
  )
  and exists (
    select 1
    from public.accounts as account
    where account.user_id = (select auth.uid())
      and account.id::text = (storage.foldername(name))[3]
  )
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users upload their own FireVault files" on storage.objects;
create policy "Users upload their own FireVault files"
on storage.objects for insert
to authenticated
with check (
  bucket_id = any (array['trip-logs', 'csv-imports']::text[])
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.current_user_has_cloud_write_access()
);

drop policy if exists "Users update their own FireVault files" on storage.objects;
create policy "Users update their own FireVault files"
on storage.objects for update
to authenticated
using (
  bucket_id = any (array['trip-logs', 'csv-imports']::text[])
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = any (array['trip-logs', 'csv-imports']::text[])
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and public.current_user_has_cloud_write_access()
);
