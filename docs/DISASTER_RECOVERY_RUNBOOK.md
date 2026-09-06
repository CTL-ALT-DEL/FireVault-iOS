# FireVault backend disaster-recovery runbook

This runbook recovers a completed, encrypted Cloudflare R2 snapshot into a
**new, separate Supabase project**. The recovery script refuses to overwrite the
source project recorded in the snapshot manifest.

The process has two levels:

1. A safe weekly workflow decrypts the newest snapshot on an ephemeral GitHub
   runner and verifies its manifest, SHA-256 checksums, gzip streams, and Storage
   object counts and byte totals. It never connects to a target database.
2. An authorized operator can restore a verified snapshot into a newly created
   Supabase project from a trusted computer.

Do not point the production iOS app or website at a recovery project until the
post-restore checks in this document pass.

## Safe recovery verification

The **Verify latest disaster backup** GitHub Actions workflow runs every Sunday
and can also be started manually. Its decrypted working files remain only on the
ephemeral runner and are not uploaded as workflow artifacts. It uses a
bucket-scoped Cloudflare R2 **Object Read only** credential, so verification
cannot change or delete backup objects.

For a manual check:

1. Open **GitHub → Actions → Verify latest disaster backup**.
2. Choose **Run workflow**.
3. Leave `snapshot` set to `latest`, or enter an exact snapshot ID.
4. Confirm the job reports that the manifest, checksums, gzip streams, and
   Storage sizes passed verification.

This proves the R2 credentials and both encryption secrets can decrypt a
complete snapshot. It is not a full restore drill because it does not write to
Supabase.

## Prerequisites for a full restore drill

1. Create a new Supabase project used only for recovery testing. Do not reuse the
   production project ref.
2. Match the production project's Postgres extensions before restoring.
3. Copy the new project's **Session Pooler** database connection string and
   percent-encode special characters in its password.
4. Enable the new project's Storage S3 protocol and generate a new S3 access-key
   pair.
5. On a trusted computer, install current `rclone`, `jq`, `gzip`, and PostgreSQL
   `psql`.
6. Obtain an R2 Object Read only credential scoped to the disaster-backup bucket
   and the backup encryption password and salt from the offline password
   manager.

The target project must be blank: no `public` tables, Auth users, or Storage
objects. The script checks this immediately before starting the database
transaction.

## Inspect and download without restoring

Export the R2 settings in the current terminal session. Do not save these values
in the repository or paste them into shell history on a shared computer.

```bash
export R2_ENDPOINT='https://<account-id>.r2.cloudflarestorage.com'
export R2_BUCKET='firevault-disaster-backups'
export R2_ACCESS_KEY_ID='<r2-access-key-id>'
export R2_SECRET_ACCESS_KEY='<r2-secret-access-key>'
export BACKUP_ENCRYPTION_PASSWORD='<offline-backup-password>'
export BACKUP_ENCRYPTION_SALT='<offline-backup-salt>'
```

List only completed snapshots. Partial snapshots without `_SUCCESS` are hidden:

```bash
scripts/recover-supabase-from-r2.sh list
```

Download, decrypt, and fully verify the newest snapshot into a new local
directory:

```bash
scripts/recover-supabase-from-r2.sh download \
  --snapshot latest \
  --output ./firevault-recovery-package
```

The command refuses to use an existing output path. Treat the resulting folder
as highly sensitive because it contains decrypted Auth records and user data.

## Restore into the separate target project

Add the target settings to the same trusted terminal session:

```bash
export TARGET_SUPABASE_PROJECT_REF='<new-project-ref>'
export TARGET_SUPABASE_DB_URL='postgresql://postgres.<new-project-ref>:<encoded-password>@<session-pooler-host>:5432/postgres'
export TARGET_SUPABASE_STORAGE_REGION='<region-from-storage-s3-settings>'
export TARGET_SUPABASE_STORAGE_ACCESS_KEY_ID='<new-project-storage-access-key-id>'
export TARGET_SUPABASE_STORAGE_SECRET_ACCESS_KEY='<new-project-storage-secret-access-key>'
```

Run the guarded restore. The confirmation value must exactly match the target
project ref:

```bash
scripts/recover-supabase-from-r2.sh restore \
  --snapshot latest \
  --phase all \
  --confirm-target-project-ref "$TARGET_SUPABASE_PROJECT_REF" \
  --apply
```

The database portion uses Supabase's documented order—roles, schema, then data—
inside one `psql` transaction with `ON_ERROR_STOP`. If it fails, PostgreSQL rolls
back that database transaction. Storage copies are external operations and can
be partially complete if a network error occurs; after resolving the error,
rerun only the idempotent Storage phase:

```bash
scripts/recover-supabase-from-r2.sh restore \
  --snapshot latest \
  --phase storage \
  --confirm-target-project-ref "$TARGET_SUPABASE_PROJECT_REF" \
  --apply
```

The Storage phase requires the bucket metadata restored by the database phase.
It verifies every target bucket's final object count and byte total against the
snapshot manifest.

## Post-restore validation

Before calling the recovery successful:

1. Confirm expected Auth users, `public` tables, row counts, and RLS policies in
   Supabase Studio.
2. Confirm each Storage bucket is private/public as expected and its object
   totals match the recovery log.
3. New Supabase projects may not expose restored tables to the Data API by
   default. Confirm the Data API schema settings and existing grants. Do not add
   broad `anon` or `authenticated` grants; preserve FireVault's ownership-based
   RLS policies.
4. Re-enable the required Realtime publications.
5. Deploy the version-controlled functions in `supabase/functions`, configure
   their secrets, and recreate the Trip Log scheduled invocation documented in
   `supabase/TRIP_LOG_REPORT_AUTOMATION.md`.
6. Recreate non-database configuration: Auth providers and redirect URLs, SMTP,
   API keys, webhooks, Google Places, Resend, and any rate-limit settings.
7. Build a test version of FireVault that points only to the recovery project.
   Sign in with a recovery test account, open an account, and download at least
   one Backed-Up Media original.
8. Record the snapshot ID, date, operator, elapsed time, and results in the
   incident or drill record. Delete the recovery project and decrypted local
   package only after the record is approved.

Supabase documents additional caveats for custom login-role passwords,
`supabase_admin` ownership statements, `cli_login_postgres`, Vault/column
encryption root keys, and changes made directly inside managed `auth` or
`storage` schemas. Stop and use the current official instructions if any of
those apply; do not edit a backup until the original verified copy is preserved.

Current references:

- [Supabase: Backup and Restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
- [Supabase: Download Storage objects](https://supabase.com/docs/guides/storage/management/download-objects)
- [Cloudflare: R2 S3-compatible API](https://developers.cloudflare.com/r2/api/)
- [rclone crypt](https://rclone.org/crypt/)

## In-place production recovery

This script intentionally does not support an in-place restore over the source
project. An in-place rollback changes live data and may require downtime,
subscription/replication handling, and Supabase-managed physical backup or PITR
operations. Use the Supabase Dashboard recovery flow and an approved incident
plan for that scenario.
