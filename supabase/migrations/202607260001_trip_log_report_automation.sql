-- Build 1.08.12: secure Trip Log report automation.

create table if not exists public.trip_log_report_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_enabled boolean not null default false,
  daily_hour smallint not null default 18 check (daily_hour between 0 and 23),
  daily_minute smallint not null default 0 check (daily_minute between 0 and 59),
  weekly_enabled boolean not null default false,
  weekly_weekday smallint not null default 6 check (weekly_weekday between 1 and 7),
  weekly_hour smallint not null default 18 check (weekly_hour between 0 and 23),
  weekly_minute smallint not null default 15 check (weekly_minute between 0 and 59),
  time_zone text not null default 'America/Denver',
  recipients text[] not null default '{}',
  cc text[] not null default '{}',
  report_detail text not null default 'detailed' check (report_detail in ('detailed', 'compact')),
  include_coordinates boolean not null default true,
  include_technician boolean not null default true,
  technician_name text not null default '',
  company_name text not null default '',
  reply_to text,
  updated_at timestamptz not null default now()
);

create table if not exists public.trip_log_days (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  unique (user_id, id)
);

create index if not exists trip_log_days_user_started_idx
  on public.trip_log_days (user_id, started_at desc);

create table if not exists public.trip_log_report_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  report_type text not null check (report_type in ('daily', 'weekly')),
  period_start date not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed', 'skipped')),
  attempts integer not null default 0,
  scheduled_for timestamptz not null,
  sent_at timestamptz,
  resend_email_id text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, report_type, period_start)
);

create index if not exists trip_log_report_deliveries_retry_idx
  on public.trip_log_report_deliveries (status, scheduled_for)
  where status in ('pending', 'failed');

alter table public.trip_log_report_preferences enable row level security;
alter table public.trip_log_days enable row level security;
alter table public.trip_log_report_deliveries enable row level security;

drop policy if exists "Technicians manage their report preferences"
  on public.trip_log_report_preferences;
create policy "Technicians manage their report preferences"
  on public.trip_log_report_preferences
  for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Technicians manage their Trip Log days"
  on public.trip_log_days;
create policy "Technicians manage their Trip Log days"
  on public.trip_log_days
  for all
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Technicians can view their report deliveries"
  on public.trip_log_report_deliveries;
create policy "Technicians can view their report deliveries"
  on public.trip_log_report_deliveries
  for select
  using ((select auth.uid()) = user_id);

revoke all on public.trip_log_report_preferences from anon;
revoke all on public.trip_log_days from anon;
revoke all on public.trip_log_report_deliveries from anon;

grant select, insert, update, delete on public.trip_log_report_preferences to authenticated;
grant select, insert, update, delete on public.trip_log_days to authenticated;
grant select on public.trip_log_report_deliveries to authenticated;

