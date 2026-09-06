# Nightly Supabase-to-R2 disaster backup

FireVault's nightly backup creates a complete, independent snapshot containing:

- Supabase database roles, schema, and data, including Auth and Storage metadata.
- Every object from every Supabase Storage bucket.
- SHA-256 checksums for the compressed database artifacts.
- A manifest with the verified object count and byte count for each bucket.
- A `_SUCCESS` marker written only after the snapshot passes verification.

The destination is a private Cloudflare R2 bucket. `rclone crypt` encrypts file
contents, file names, and directory names before they leave the GitHub runner.
An incomplete run can leave a partial prefix, but it cannot create `_SUCCESS`.

## One-time setup

### 1. Create the R2 destination

1. In Cloudflare, create a private R2 bucket dedicated to FireVault backups.
2. Create an R2 API token limited to Object Read & Write for only that bucket.
3. Record the S3 endpoint, access-key ID, and secret access key.

Do not add a deletion lifecycle rule yet. Retention is a product decision because
it controls the last recoverable date after corruption or accidental deletion.

### 2. Enable Supabase Storage S3 access

In **Supabase Dashboard → Storage → Configuration → S3**, enable the S3 protocol
and generate server-side S3 access keys. These keys bypass Storage RLS, so store
them only as GitHub Actions secrets.

Use the direct endpoint:

```text
https://<project-ref>.storage.supabase.co/storage/v1/s3
```

### 3. Configure GitHub Actions

In **GitHub → Settings → Secrets and variables → Actions**, add these repository
variables:

- `SUPABASE_PROJECT_REF`
- `SUPABASE_STORAGE_REGION`
- `R2_ENDPOINT`
- `R2_BUCKET`

Add these repository secrets:

- `SUPABASE_DB_URL`: the encoded Session Pooler connection string from the
  Supabase Connect panel. Prefer the Session Pooler unless the runner has IPv6.
- `SUPABASE_STORAGE_ACCESS_KEY_ID`
- `SUPABASE_STORAGE_SECRET_ACCESS_KEY`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `BACKUP_ENCRYPTION_PASSWORD`: a randomly generated, long password.
- `BACKUP_ENCRYPTION_SALT`: a second independently generated random value.

Keep the two encryption secrets in an offline password manager as well as GitHub.
Losing either value makes every encrypted backup unrecoverable.

### 4. Run and confirm the first backup

1. Open **GitHub → Actions → Nightly Supabase disaster backup**.
2. Choose **Run workflow**.
3. Confirm the run completes successfully.
4. In R2, confirm encrypted objects were created. Their names are intentionally
   unreadable without the encryption password and salt.

The schedule is `08:23 UTC`, which is 1:23 AM Mountain Standard Time or 2:23 AM
Mountain Daylight Time. GitHub may delay scheduled jobs during high load.

## Snapshot rules

- Backups use `copy`, never `sync`, so the job cannot delete existing snapshots.
- Each run gets a new timestamped prefix.
- Restore only a snapshot containing `_SUCCESS`.
- Database artifacts are checked after upload; Storage source and destination
  object counts and byte totals must match before the run succeeds.
- GitHub's concurrency guard prevents two backup jobs from overlapping.

## Restore drill

Perform a restore drill into a separate Supabase project before relying on this
backup in production, and repeat the drill after major schema or Auth changes.

1. Install current `rclone`, the Supabase CLI, Postgres `psql`, and Docker.
2. Recreate the `r2` and `r2crypt` remotes with the same endpoint, bucket,
   credentials, encryption password, and encryption salt used by the workflow.
3. List `r2crypt:firevault` and select a snapshot containing `_SUCCESS`.
4. Copy its `database` directory locally, then verify `SHA256SUMS` before
   decompressing the three SQL files.
5. Follow Supabase's current **Backup and Restore using the CLI** guide to restore
   `roles.sql`, `schema.sql`, and `data.sql` into a newly created project.
6. Create any missing target Storage buckets, configure a `target-supabase` S3
   remote, and copy each snapshot Storage directory to its corresponding bucket.
7. Verify object counts and bytes, sign in with a test account, open an account,
   and download at least one Backed-Up Media original.
8. Redeploy the version-controlled Edge Functions in `supabase/functions` and
   recreate their secrets and scheduled jobs.

Supabase's restore guidance changes as Auth and Storage evolve. Always use the
current official guide during a real recovery rather than treating these notes
as a replacement for it.

## Retention decision

The workflow intentionally never deletes backups. Before enabling an R2 lifecycle
rule, choose and document:

- how many daily snapshots to retain;
- whether month-end or year-end snapshots need longer retention;
- who is authorized to shorten retention;
- the acceptable storage cost; and
- the most recent successful restore-drill date.
