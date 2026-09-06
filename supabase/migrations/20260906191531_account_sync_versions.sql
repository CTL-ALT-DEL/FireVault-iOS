alter table public.accounts
  add column if not exists sync_version bigint not null default 1;

alter table public.accounts
  drop constraint if exists accounts_sync_version_positive;

alter table public.accounts
  add constraint accounts_sync_version_positive
  check (sync_version > 0);

comment on column public.accounts.sync_version is
  'Monotonic revision used for conditional iPhone and portal account synchronization.';

create or replace function public.set_account_sync_revision()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  new.sync_version = old.sync_version + 1;
  return new;
end;
$$;

revoke all on function public.set_account_sync_revision()
  from public, anon, authenticated;

drop trigger if exists set_account_sync_revision on public.accounts;

create trigger set_account_sync_revision
before update on public.accounts
for each row
execute function public.set_account_sync_revision();
