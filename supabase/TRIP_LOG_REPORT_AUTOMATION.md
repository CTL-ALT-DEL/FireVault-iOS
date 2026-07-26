# Trip Log report automation deployment

Build 1.08.12 adds the application and backend source required to email daily
and weekly Trip Log PDFs through the existing Supabase and Resend accounts.

## One-time Supabase deployment

1. Link the Supabase CLI to the FireVault project.
2. Apply `migrations/202607260001_trip_log_report_automation.sql`.
3. Add these Edge Function secrets:

   - `RESEND_API_KEY`: existing Resend API key
   - `TRIP_LOG_CRON_SECRET`: a new random value used only by the scheduler
   - `RESEND_FROM`: `FireVault Reports <reports@mail.bannerman.us>`
   - `REPORT_REPLY_TO`: a monitored Bannerman address

   `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are supplied to hosted Edge
   Functions automatically.

4. Deploy `trip-log-report-dispatch`.
5. In Supabase Dashboard, create a Cron job that runs every five minutes and
   invokes the function with:

   - Method: `POST`
   - Header: `x-trip-log-cron-secret: <TRIP_LOG_CRON_SECRET>`
   - Body: `{}`

## Safety

- Never place `RESEND_API_KEY`, `TRIP_LOG_CRON_SECRET`, or the Supabase service
  role key in the iOS project.
- Row-level security keeps each technician's schedule and Trip Log records
  isolated.
- Delivery rows use a unique user/report/period key plus a Resend idempotency
  key, preventing duplicate scheduled reports.
- Failed deliveries can retry up to three times.
- Personal Stop names, addresses, stop markers, and notes are excluded from the
  emailed PDF. The day-level route line remains part of the Trip Log report.
