create table public.cloud_vault_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_label text not null default 'iPhone',
  schema_version integer not null default 1 check (schema_version > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  account_count integer not null check (account_count >= 0),
  trip_log_day_count integer not null check (trip_log_day_count >= 0),
  created_at timestamp with time zone not null default now(),
  unique (user_id, sha256)
);

comment on table public.cloud_vault_snapshots is
  'Small metadata-only FireVault recovery points. Field-media bytes remain in private Storage.';

create index cloud_vault_snapshots_user_created_idx
  on public.cloud_vault_snapshots (user_id, created_at desc);

alter table public.cloud_vault_snapshots enable row level security;

create policy "Users can read their cloud vault snapshots"
on public.cloud_vault_snapshots for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "Users can create their cloud vault snapshots"
on public.cloud_vault_snapshots for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "Users can delete their cloud vault snapshots"
on public.cloud_vault_snapshots for delete
to authenticated
using ((select auth.uid()) = user_id);

revoke all on table public.cloud_vault_snapshots from anon, authenticated;
grant select, insert, delete on table public.cloud_vault_snapshots to authenticated;
