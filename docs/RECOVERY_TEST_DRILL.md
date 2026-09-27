# FireVault recovery test on Free

This is a manual drill for the separate Supabase project **FireVault Recovery Test**
(`llfvzebabfkxslrlgwav`). It uses the existing encrypted disaster snapshot in
Cloudflare R2. It never points the restore script at production
(`dgzriqqflbhioflblirm`). The project was quoted at $0/month when created.

## Before running

The target must remain empty (zero public tables, Auth users, and Storage
objects). In the target project, ensure the database password and the
`Recovery test` S3 key are safely stored. The S3 key grants full Storage
access to this test project; never copy it to production.

The GitHub environment `firevault-recovery-test` is already created and limited
to the `main` branch. Add these **environment secrets** from the password
manager:

- `RECOVERY_TEST_DB_PASSWORD` — the target project database password.
- `RECOVERY_TEST_STORAGE_ACCESS_KEY_ID` — target S3 key ID.
- `RECOVERY_TEST_STORAGE_SECRET_ACCESS_KEY` — target S3 secret key.

Do not place secret values in issues, commits, workflow inputs, or chat. The
workflow reuses the repo's existing read-only R2 recovery credentials and
backup encryption secrets. It uses the target's Session Pooler address and
`PGPASSWORD` so no URL encoding of the password is needed.

Check the target extensions against production before the drill. Production
currently enables `pg_cron` and `pg_net`; the target initially lacks both.
Do not connect the target project to the live app, website, email provider, or
webhooks. The restore uses `--disable-restored-cron-jobs`, which updates copied
`cron.job` records to inactive **inside the database restore transaction**,
before the data is committed. A failed database step rolls back.

## Run

After the draft PR is merged, open GitHub Actions → **Restore encrypted backup
to recovery test** → **Run workflow**. It selects the latest complete snapshot,
decrypts and verifies it, refuses the source project or a nonempty target,
restores database and Storage, checks bucket counts/bytes, and prints only
aggregate row counts. R2 access is read-only. The job runs only on manual
dispatch and uploads no decrypted artifact.

Review the Actions log for errors. If the database restore fails, inspect the
specific error and repair the **test project only** before retrying. If Storage
copy fails after the database completed, the existing recovery script supports
a Storage-only retry; the workflow must not simply be rerun because its
empty-target guard will reject the populated database.

A passing job is still only an infrastructure restore. Follow
`docs/DISASTER_RECOVERY_RUNBOOK.md` to check sample records, RLS ownership,
file downloads, missing functions/secrets/configuration, and whether a
test-only app can use the restored project. Record snapshot ID and result.
Keep credentials in the password manager. Remove the temporary test project
only after the drill record is complete and approved.
