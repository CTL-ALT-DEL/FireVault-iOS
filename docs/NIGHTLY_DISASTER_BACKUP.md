# Nightly Supabase-to-R2 disaster backup

FireVault's nightly backup creates a complete logical recovery point containing:

- Supabase database roles, schema, and data, including Auth and Storage metadata.
- A complete inventory of every Supabase Storage bucket and its current objects,
  referencing immutable encrypted file versions stored in R2.
- SHA-256 checksums for the compressed database artifacts.
- A daily manifest with object keys, source checksums, SHA-256 version checksums,
  sizes, MIME/cache metadata, version references, and object/byte totals for every bucket.
- A `_SUCCESS` marker written only after the snapshot passes verification.

The destination is a private Cloudflare R2 bucket. `rclone crypt` encrypts file
contents, file names, and directory names before they leave the GitHub runner.
An incomplete run can leave a partial prefix or unreferenced immutable versions,
but it cannot create `_SUCCESS`. Database roles/schema/data dumps and their
checksums remain in each daily snapshot, as before. Only the disaster-backup
and recovery scripts change; app sync, schema, customer data, and iOS behavior
are unaffected.

## One-time setup

### 1. Create the R2 destination

1. In Cloudflare, create a private R2 bucket dedicated to FireVault backups.
2. Create an R2 API token limited to Object Read & Write for only that bucket.
3. Create a second R2 API token limited to Object Read only for only that bucket.
   This credential is used by recovery verification and cannot modify or delete
   backup objects.
4. Record the S3 endpoint and both access-key pairs. Cloudflare shows each
   secret access key only once.

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
- `R2_RECOVERY_ACCESS_KEY_ID`: the bucket-scoped Object Read only key.
- `R2_RECOVERY_SECRET_ACCESS_KEY`: the matching Object Read only secret.
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

## Incremental Storage format (version 2)

Each completed snapshot keeps `database/`, `manifest.json`, and `_SUCCESS` under
its timestamped prefix. Storage payloads live separately at
`<BACKUP_PREFIX>/_storage-versions/<random-unique-id>`, inside the same `rclone
crypt` remote. Every new or changed file gets a new immutable version; nothing
replaces an older version. Each manifest is a **full inventory**, not a chain of
deltas. Recovering one day requires that day's manifest/database and its
referenced versions; other daily manifests are not needed.

The job lists source keys, byte sizes, modification times, and MD5 checksums
and object metadata through the S3 interface. When those fields match the last completed format-2
manifest and its R2 version still exists with the expected decrypted size, it
reuses that version without downloading source contents. Changed files are
downloaded to private temporary storage, checked against source size/MD5,
SHA-256 hashed, uploaded as a new encrypted version, then decrypted from R2 and
SHA-256 checked. A second source inventory must match the first before commit;
a concurrent change causes failure and a retry rather than a successful marker.
The manifest itself is read back and checksum checked before `_SUCCESS`.

A deletion is represented by absence from the new inventory. It does not delete
the old R2 object. A recreated key receives a new version when absent from the
previous completed inventory, even if its contents match an older historical
file. Empty and newly added buckets remain represented in the manifest.

### First format-2 run

The newest completed legacy format-1 snapshot remains unchanged and readable.
On the first run, the job reads its Storage bytes from **R2**, checks each
candidate against the current source MD5, and seeds matching bytes into the
immutable version pool. Only new or changed files download from Supabase.
If there is no completed legacy snapshot, the first run needs one full Storage
baseline. A corrupt/unreadable legacy listing fails closed; investigate it
before retrying. No production baseline or migration has been run as part of
the local implementation.

### Snapshot rules and limits

- No `sync`, delete, purge, remote cleanup, or retention operation is used.
- Restore only snapshots containing `_SUCCESS`; incomplete snapshots are ignored.
  Recovery selection fails on unreadable/malformed listings or unreadable markers;
  `latest` never silently falls back because a newer snapshot cannot be read.
- Repeating the exact completed snapshot ID makes no writes. Retrying an
  incomplete run may download uncommitted changed files again and leave orphan
  versions. This is deliberate: an interrupted upload is never trusted as a
  completed backup. The next success references only verified versions.
- The existing GitHub concurrency guard remains required. Do not run the script
  manually concurrently with the workflow: snapshot commits assume one writer.
- Missing/multipart MD5 checksums are handled conservatively: those files are
  downloaded and versioned every run. Check real first-run hash coverage before
  promising savings; MD5 is a change detector, while SHA-256 verifies recovery.
- Reused versions get existence/size checks nightly. The weekly verification
  decrypts and SHA-256 checks their contents; the nightly job does not reread all
  unchanged payloads. The design assumes committed versions are immutable.
- Source listing/hash/HEAD requests still occur. Database dump egress, new/changed
  file bytes, and weekly R2 recovery traffic remain. Listing does not download
  the Storage payloads, but may incur API/metadata traffic.
- As with the original job, database and Storage are captured in separate
  operations, not one transaction. The double inventory detects ordinary
  concurrent Storage changes, but cannot guarantee an atomic cross-service
  point in time or detect a change-and-revert entirely between inventories.
- Keys containing traversal components, backslashes, control characters, or
  rclone's special filename-encoding glyphs fail closed. This avoids a silently
  renamed recovery file. Recovery needs a filesystem that can represent all
  manifest keys (use a case-sensitive filesystem for case-distinct names).
- A file is processed at a time to bound decrypted temporary storage and avoid
  a whole Storage download on the runner. Very large changed sets can take
  longer than the previous parallel copy; the workflow timeout is unchanged.

For an unchanged 218 MB set with reliable hashes, ongoing Storage payload
transfers from Supabase fall from about **6.54 GB per 30 days to zero** after
seeding. With 10 MB/day of new or changed data, that portion becomes roughly
300 MB/month (about 95% less). Hashless files reduce savings. R2 still grows
with new versions, database dumps, and small daily inventories; no automatic
retention or deletion is introduced.

## Local verification and rollout (review required before activation)

Run with Python 3, jq, gzip, and rclone 1.75.1 available:

```bash
scripts/test-backup-supabase-to-r2.sh
scripts/test-recover-supabase-from-r2.sh
```

Alternatively set `FIREVAULT_TEST_RCLONE` to an installed rclone binary path.
The incremental suite uses real `rclone crypt` with temporary local folders and
fake SQL dumps. Its adapter rejects source writes and network remotes. It tests
unchanged runs; same-size/same-time and metadata-only modifications; additions; deletion and
recreation; legacy seeding; current/historical recovery; empty and Unicode paths;
interrupted uploads/commits and retries; corrupt payload/readback rejection;
failed listings; missing hashes/versions; path validation; and repeated IDs.
It does not test a live Supabase/R2 service or execute SQL in PostgreSQL.

Rollout after review:

1. Apply the backup/recovery/helper, tests, and docs together to the intended
   repository branch. Keep the existing workflow schedule, secrets, concurrency,
   database commands, and app/release files unchanged. Python 3 is available on
   the existing Ubuntu runner; install it on any manual recovery workstation.
2. Keep all legacy snapshots and encryption secrets. Confirm no bucket lifecycle
   rule removes shared versions. Do not configure new credentials or change plans.
3. After activation approval, run one controlled backup. Inspect completion,
   source-download byte totals, and the logged source checksum coverage. Expect R2 reads
   during legacy seeding, not a repeated whole-source copy.
4. Use the updated recovery downloader with the existing read-only recovery
   credential to verify that exact snapshot, then an older legacy snapshot.
   The normal weekly workflow automatically uses the updated downloader.
5. Compare the following unchanged run's source-download total (ideally zero)
   and monitor actual Supabase egress. A separate-project SQL/app drill remains
   required before declaring full backend disaster recovery proven.

Rollback: revert only the backup writer to the prior full-snapshot algorithm;
it will resume larger daily Storage transfers. **Keep the format-2-aware
recovery script/helper and all R2 versions/manifests** so any format-2 dates
remain recoverable. Do not revert the reader along with the writer, delete
shared versions, or shorten retention. No app or database rollback is involved.

## Restore drill

The weekly **Verify latest disaster backup** workflow first caps the complete
logical recovery package at 300 MiB, including format-2 shared versions and the
dated database package. Oversized or missing references fail before large
payload downloads. Raw tool diagnostics are suppressed and only aggregate
verification results are logged. It then decrypts the newest
snapshot on an ephemeral runner and validates its manifest, SHA-256 checksums,
gzip streams, Storage totals, and (for format 2) every Storage object SHA-256. It never uploads decrypted artifacts and uses
the dedicated Object Read only R2 credential.

The guarded download and separate-project restore procedure is documented in
`docs/DISASTER_RECOVERY_RUNBOOK.md`. Perform a full restore drill after major
schema or Auth changes and before relying on the backup for production recovery.

## Retention decision

The workflow intentionally never deletes backups. Format-2 file versions may
be shared by many dates: never apply a simple age-based lifecycle to the
`_storage-versions` pool. Future cleanup requires reachability analysis across
all retained completed manifests, plus an independently reviewed retention plan.
Do not remove versions or legacy snapshots as part of this change. Before enabling an R2 lifecycle
rule, choose and document:

- how many daily snapshots to retain;
- whether month-end or year-end snapshots need longer retention;
- who is authorized to shorten retention;
- the acceptable storage cost; and
- the most recent successful restore-drill date.
