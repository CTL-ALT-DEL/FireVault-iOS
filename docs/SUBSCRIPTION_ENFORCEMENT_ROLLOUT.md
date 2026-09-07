# Server subscription enforcement rollout

FireVault treats the App Store as the billing authority and Supabase as the
server-side authorization authority. The iPhone submits Apple's signed StoreKit
transaction to Supabase; the server verifies Apple's certificate chain and binds
the purchase to the signed-in FireVault user. App Store Server Notifications V2
then keep renewals, grace periods, expirations, and revocations current.

## Product policy

An expired trial or subscription does not delete customer data. The iPhone keeps
its local data. The portal continues to allow viewing, downloading, exporting,
and deletion of existing cloud records and files. The following require an
active subscription or an unexpired App Store billing grace period:

- new or changed cloud account data;
- cloud file and media uploads;
- cloud vault snapshots and Trip Log uploads;
- AI and paid geocoding calls; and
- emailed Trip Reports.

Billing-retry status without an Apple grace-period expiration is read-only.

## Safe deployment order

1. Apply `20260906210000_server_subscription_enforcement.sql`. It creates the
   tables, RPCs, and policies with enforcement disabled.
2. Deploy `app-store-entitlement-sync`, `app-store-notifications`, `firevault-ai`,
   `google-places-stop-lookup`, and `trip-log-report-dispatch` from this repo.
   Deploy `csv-geocode` from FireVault-Web.
3. Add the numeric App Store Connect Apple ID as the Supabase Edge secret
   `APPLE_APP_ID`. This is required to verify production transactions. Sandbox
   and TestFlight verification do not require it.
4. In App Store Connect, set both App Store Server Notifications V2 URLs to:

   `https://dgzriqqflbhioflblirm.supabase.co/functions/v1/app-store-notifications`

5. Install build 149 through TestFlight. Open **Settings → FireVault Plan** and
   use **Restore** once. This submits the latest signed transaction and creates
   the first `user_subscription_access` row.
6. Confirm the user's row has the expected product, Sandbox environment, status,
   and expiration date. Verify that the portal still reports writes allowed.
7. Only after active customers have linked successfully, enable enforcement:

   ```sql
   update public.subscription_enforcement_settings
   set enabled = true, updated_at = now()
   where singleton = true;
   ```

8. Test one active account and one account with no entitlement. The active user
   must be able to sync and upload. The inactive user must retain read, download,
   export, and delete access while writes and paid API calls are blocked.

## Rollback

Disable enforcement immediately without removing tables or verified state:

```sql
update public.subscription_enforcement_settings
set enabled = false, updated_at = now()
where singleton = true;
```

The switch restores cloud writes and paid API calls while the underlying issue
is investigated. Never delete `user_subscription_access` or the notification
ledger as part of a routine rollback.
