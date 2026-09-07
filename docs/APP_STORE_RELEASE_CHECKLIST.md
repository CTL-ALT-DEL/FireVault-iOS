# App Store release checklist

Use this checklist for the first public FireVault Pro submission and for later
releases that change subscriptions, cloud behavior, privacy, or permissions.
Never commit reviewer passwords, App Store credentials, or production secrets.

## Current candidate

- Version: **1.08.86**
- Build: **154**
- Bundle ID: `us.bannerman.firevault`
- Display name: **FireVault Pro**
- Minimum iOS/iPadOS: **26.5**
- Encryption declaration: `ITSAppUsesNonExemptEncryption = false`
- Privacy policy: `https://firevault.bannerman.us/privacy`
- Terms of Use: `https://firevault.bannerman.us/terms`

Any code change after build 154 requires a new build number and TestFlight
upload before submission.

## Blocking business requirement

- [ ] The Paid Apps Agreement is active in App Store Connect.
- [ ] Tax and banking status are approved. The pending disregarded-LLC W-9 case
  must be resolved by Apple before paid subscriptions can be sold.
- [ ] Keep Supabase subscription enforcement **disabled** until the agreement is
  active, both products are available, and a TestFlight purchase or restore has
  created the expected subscription-access row.

## Subscription products

Both products must be in the same subscription group, available in every
intended storefront, and attached to the app version submitted for review.

| Product | Product ID | Price | Period | Introductory offer |
| --- | --- | ---: | --- | --- |
| Technician Monthly | `us.bannerman.firevault.technician.monthly` | US $9.99 | 1 month | 2 weeks free |
| Technician Annual | `us.bannerman.firevault.technician.annual` | US $99.99 | 1 year | 2 weeks free |

- [ ] Add each subscription to the app version under **In-App Purchases and Subscriptions**.
- [ ] Add an App Review screenshot for each subscription.
- [ ] Confirm the localized display name and description are complete.
- [ ] Confirm the introductory offer covers the intended 175 storefronts.
- [ ] Confirm **Settings → FireVault Plan** loads both products, purchases, and
  restores in the TestFlight build selected for review.
- [ ] Confirm **Manage** opens Apple subscription settings.

## App privacy answers

The app privacy answers in App Store Connect must match `PrivacyInfo.xcprivacy`
and the public Privacy Policy. FireVault does not track users; each listed type
is linked to the signed-in user and used for app functionality.

- [ ] Name
- [ ] Email Address
- [ ] Phone Number
- [ ] Physical Address
- [ ] User ID
- [ ] Precise Location
- [ ] Photos or Videos (cloud photo backup; videos currently remain local)
- [ ] Emails or Text Messages (automated Trip Report recipients and content)
- [ ] Purchase History (verified subscription status)
- [ ] Other User Content (notes, equipment, documents, scans, reports, CSV data)
- [ ] Other Diagnostic Data (authenticated request/error and operational logs)
- [ ] Tracking: **No**

If Apple presents different wording, choose the closest current category and
keep the public Privacy Policy and App Store Connect answers consistent.

## Permissions and reviewer access

- [ ] Camera: capture field photos, videos, and document scans.
- [ ] Microphone: record audio only while the user records a field video.
- [ ] Photos: import photos and save user-requested exports.
- [ ] Location When In Use: Nearby Accounts, maps, account coordinates, and
  arrival assistance.
- [ ] Always Location: Trip Log only after the user explicitly starts a workday;
  the user can stop it at any time.
- [ ] Face ID / Touch ID: optional local workspace lock; FireVault does not
  receive biometric data.
- [ ] CarPlay entitlement and reviewer explanation are present.
- [ ] A dedicated reviewer account is active and its credentials are entered
  only in App Store Connect **App Review Information**.

## Required review paths

Verify these paths in the exact build submitted:

- Subscription screen: **Settings → FireVault Plan**
- Account deletion: **Settings → Security → Account Data & Deletion**
- Privacy and terms: **Settings → FireVault Plan**, then the legal links
- Cloud synchronization: **Accounts → Data & File Sync → Sync All**
- Backed-up media: **Settings → File Storage → Backed-Up Media**
- Trip Log: open **Trip Log**, then explicitly start and stop a workday

Account deletion must remove the FireVault cloud identity and user-scoped cloud
data. It does not cancel Apple billing, so the deletion screen must warn the user
and link to Apple subscription management before the destructive action.

## Suggested App Review notes

Replace bracketed fields in App Store Connect; do not commit their values:

> FireVault Pro is a field-service productivity app. Sign in with the dedicated
> reviewer account listed above. Subscription plans are under Settings →
> FireVault Plan; Restore and Manage are on that screen. Account deletion is
> under Settings → Security → Account Data & Deletion. To test background
> location, open Trip Log and explicitly start a workday; FireVault does not run
> Trip Log before that action, and Stop Workday ends tracking. CarPlay provides
> driving-safe nearby-account navigation and Trip Log controls. Cloud sync and
> backed-up media use the reviewer account's private Supabase storage. Contact
> [review contact] if the reviewer account needs to be reset.

## Assets and submission

- [ ] App icon, description, keywords, support URL, marketing URL, copyright,
  category, age rating, and contact information are complete.
- [ ] Upload current iPhone screenshots (1–10) with no alpha channel.
- [ ] Because the app supports iPad, upload the required iPad screenshots too.
- [ ] Screenshots show current UI and do not show private customer data.
- [ ] Select the exact tested build and answer export-compliance questions.
- [ ] Add the two subscription products for review, then submit the app version.

## Final device smoke test

- [ ] Fresh install and sign in.
- [ ] Monthly and annual plans load; Restore returns an accurate result.
- [ ] Create or edit an account, run Sync All, and confirm the portal updates.
- [ ] Capture a photo, wait for backup, preview/download it, remove the local
  original, and restore the missing original with checksum verification.
- [ ] Start/stop Trip Log and export a report.
- [ ] Verify free/expired state leaves existing local and cloud data readable
  while cloud writes, AI, and emailed Trip Reports show Subscription Required.
- [ ] Verify account deletion explains Apple billing and completes successfully
  with a disposable test account.
