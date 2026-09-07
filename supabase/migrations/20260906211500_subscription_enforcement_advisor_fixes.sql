-- Make the server-only notification ledger's denial explicit and add the
-- covering index recommended by the Supabase database advisor.

create index app_store_notification_events_user_id_idx
  on public.app_store_notification_events (user_id);

create policy "Clients cannot access App Store notification events"
on public.app_store_notification_events for all
to anon, authenticated
using (false)
with check (false);
