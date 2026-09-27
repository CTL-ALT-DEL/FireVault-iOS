# FireVault recovery test on Free

This is a manual drill for the separate Supabase project **FireVault Recovery Test**
(`llfvzebabfkxslrlgwav`). Production is `dgzriqqflbhioflblirm`; the restore
script refuses to target the source project. The test project was quoted at
$0/month on the Supabase Free plan.

## September 27, 2026 result

The encrypted R2 snapshot `2026-09-27T14-07-55Z-36324793492-1` was restored
into the separate test project. The database contains 46 public tables, 7 Auth
users, 3 Storage buckets, and 48 Storage object records, matching production
totals at the time. The test project has zero active scheduled jobs.

[Storage-only run #7](https://github.com/CTL-ALT-DEL/FireVault-iOS/actions/runs/36345606513)
completed the file copy. Rclone downloaded and compared all 48 target files
against the decrypted backup: 48 matched, zero differences. Per-bucket object
and byte totals passed. Earlier runs identified and resolved a nonportable
Supabase-managed role grant, a protected cron table, an incorrect test S3 key
pair, and rclone timestamp updates against metadata-only Storage records.
Those runs did not restore over production.

The CLI dump omitted eight custom policies on `storage.objects`. They were
restored separately **in the test project only**. A definition-by-definition
comparison with production matched all eight. SQL-level checks under simulated
roles showed the file owner could see 48 records, while another authenticated
user and an anonymous user saw none. These checks do not replace an app-level
sign-in and download test.

The test project has no Edge Functions deployed; production has ten. Both
projects' Realtime publications currently include no tables. No live email,
Apple subscription, AI, geocoding, webhook, or scheduled integrations were
enabled in the test project.

## Running a future drill

Create a new, blank Free test project. Keep its database password and
Storage S3 key in a password manager. The S3 key grants full Storage access to
that test project. Never copy production credentials into the test project.

The GitHub environment `firevault-recovery-test` is limited to `main`.
Its three environment secrets are:

- `RECOVERY_TEST_DB_PASSWORD`
- `RECOVERY_TEST_STORAGE_ACCESS_KEY_ID`
- `RECOVERY_TEST_STORAGE_SECRET_ACCESS_KEY`

Do not put secret values in workflow inputs, commits, issues, or chat. The
workflow reuses the repository's read-only R2 recovery credential and backup
encryption secrets. Match the production Postgres extensions before restoring;
this drill needed `pg_cron` and `pg_net`.

Open GitHub Actions → **Restore encrypted backup to recovery test** →
**Run workflow**. Select `all` only for a blank target. Record the snapshot
ID. The workflow checks the target is empty before importing the database.
The `--disable-restored-cron-jobs` option now aborts the database transaction
if active jobs would be committed; it does not edit Supabase's protected
`cron.job` table.

If the database imports but Storage fails, choose `storage` and enter the
**same snapshot ID** on the next manual run. This phase forces physical file
uploads, compares downloaded bytes, and checks object counts and byte totals.
Do not rerun `all` against a populated target.

After the database restore, compare custom policies in Supabase-managed
`auth` and `storage` schemas with production or version-controlled
migrations. The CLI dump may omit them. Restore only the needed policies and
check their definitions and access behavior; do not add broad anonymous
grants. For this drill, the eight `storage.objects` policies were restored
from the production definitions. See Supabase's
[backup and restore guidance](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
for managed-schema caveats.

## Remaining app validation

Prepare a test build that points only to the recovery project. The current
iOS client hardcodes the production project URL, so the installed app must not
be used for this check. Keep outgoing integrations and scheduled jobs
inactive. With a recovery test account, verify sign-in, a representative
record, one original file download, and denial of another user's file.
Deploy and configure only the Edge Functions needed for that test, using
test-only secrets. Production has ten deployed functions but the current
repository's `supabase/functions` directory has only six function directories;
reconcile that difference before treating the test project as a full app
recovery.

Record the snapshot, date, operator, elapsed time, and results. Follow
[the disaster recovery runbook](DISASTER_RECOVERY_RUNBOOK.md) for remaining
providers, functions, secrets, and integrations. Keep the test project and
credentials private. Remove the project only after the drill record is
complete and approved.
