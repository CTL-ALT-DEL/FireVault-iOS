# Incremental backup — preactivation review, 2026-10-16

**Recommendation: no-go for activation until the remaining live access checks
pass. Code review and local fixture verification are ready.** No push, merge,
activation, workflow dispatch, credential change, remote write, app build, phone
installation, or source Storage content download was performed.

Reviewed implementation commit: `8737bb1bc676477e0bf02dcd8c923eb58122608b`.
The same isolated branch now includes the recovery-selection hardening below.
The build-197 candidate, original app checkout, and all remote backups remain
untouched by this work.

## Independent review

An independent local reviewer read the writer, helper, recovery reader, tests,
and rollback documentation. They found no confirmed blocker under the documented
single-writer GitHub workflow. Their review confirmed full historical inventories,
immutable UUID versions, source-MD5-checked legacy seeding, SHA-256 readback and
recovery verification, path/reference validation, and reader-preserving rollback.
They also independently reviewed the follow-up fix and regression test.

Operational limits remain explicit:

- The initial `_SUCCESS` check is not a distributed lock. The existing GitHub
  concurrency guard is mandatory. Manual writers must not overlap; two writers
  using the same snapshot ID could overwrite each other's incomplete prefix.
- Reused versions receive existence/size checks nightly; full-content integrity
  is checked by weekly recovery. Committed versions must remain immutable.
- Source MD5 is a non-adversarial change detector, not an authenticity guarantee.
  Recovery SHA-256 and crypt authentication verify the stored payload. Missing
  reliable source hashes trigger conservative downloads, not size-only reuse.
- Database/Storage capture is not an atomic cross-service transaction. Local
  fixture SQL and count/size target checks do not prove a real PostgreSQL restore
  or target-side full-content verification after uploading to Supabase.

## Finding and fix

An inherited reader bug treated every `_SUCCESS` read failure as an incomplete
snapshot. With an older valid snapshot present, `latest` could silently select
that older state when a newer completed marker was unreadable.

The reader now positively lists each dated snapshot before skipping a missing
marker and explicitly aborts on history-list, per-snapshot-list, malformed-list,
or marker-read failures. The `latest` pipeline assignment also explicitly
propagates failure: Bash command substitutions do not reliably preserve
`errexit`. Explicit snapshot selection also fails on unreadable markers.

The new regression first reproduced the bug, then passed after the fix. It uses
an older valid snapshot and a newer valid snapshot with injected list/marker
failures, checks that no recovery output is published and no payload download
starts, and confirms normal latest recovery still works. The independent
reviewer confirmed the final propagation paths.

## Actual live read-only observations

Two aggregate SELECT queries through the existing authorized Supabase connector
reported:

| Measure | Result |
| --- | ---: |
| Storage objects | 70 |
| Total stored bytes | 217,883,350 |
| Buckets | 3 |
| MD5-shaped metadata ETags | 70/70, covering 217,883,350 bytes |
| Missing / multipart / other-shaped ETags | 0 / 0 / 0 |
| Objects with MIME metadata | 70/70 |
| Unsupported raw keys / casefold collision groups / file-directory conflicts | 0 / 0 / 0 |

This is **100% MD5-shaped coverage in database metadata**, not confirmation of
rclone S3 hash results or proof that ETags equal actual contents. The latter
requires the existing S3 access context. No object keys, actual ETag values,
customer file contents, or secrets were returned in the aggregate evidence.

Source Storage payload downloaded: **0 bytes**. R2 payload downloaded: **0 bytes**.
Metadata/connector wire bytes were not metered. At the measured stable size,
30 repeated full copies would be 6,536,500,500 bytes (about 6.54 GB); incremental
Storage payload savings depend on direct S3 checksum availability and churn.

Existing GitHub run records show the October 16 nightly legacy backup succeeded:
[run 38907268599](https://github.com/CTL-ALT-DEL/FireVault-iOS/actions/runs/38907268599).
Read-only inspection of the October 11 recovery job logs confirmed database SHA
checks and manifest/gzip/Storage-size verification of snapshot
`2026-10-11T14-58-41Z-38149350695-1`:
[run 38151879876](https://github.com/CTL-ALT-DEL/FireVault-iOS/actions/runs/38151879876).
These are existing-run evidence, not a fresh recovery test of this patch.

## Local tests

The final real-rclone-crypt fixture suite passes nine tests covering unchanged,
new/changed/deleted/recreated files; same-size/same-time and metadata-only edits;
legacy migration; current and historical reconstruction and guarded local-target
Storage restore; interruption/retry; corrupt payload/readback; missing
hashes/versions; unsafe keys/references; repeated IDs; and the new latest-selection
failure regression. The existing legacy recovery shell suite also passes.

Commands:

```bash
FIREVAULT_TEST_RCLONE=/tmp/firevault-backup-tools/rclone-v1.75.1-osx-arm64/rclone \
  scripts/test-backup-supabase-to-r2.sh
scripts/test-recover-supabase-from-r2.sh
```

Bash syntax, Python AST parsing, whitespace, and exported-patch applicability
checks are also performed before final delivery. Fixtures cannot reach a network
backend; SQL dumps are fake and target Storage writes go only to temporary local
folders. No production baseline or real SQL restore was executed.

## Exact remaining access blockers and activation steps

1. **Direct S3 checksum/metadata inventory: not attempted because existing access
   keys are unavailable in the local execution environment.** There is no local
   rclone configuration and no exported Supabase Storage endpoint/keys. The
   authorized connector exposes database queries, not this S3 interface. Run
   `rclone lsjson` with `--hash --metadata` in an authorized context where the
   existing keys are already available, returning only aggregate coverage.
   Do not fetch source contents merely to count available hashes.
2. **Fresh R2 decrypt/recovery verification: not attempted because existing R2
   read-only keys and both encryption secrets are unavailable locally.** GitHub
   secrets cannot be read back through the available connector. Use an approved
   execution context with the already configured read-only recovery credentials
   to download and verify a selected existing legacy snapshot. No new credentials,
   credential disclosure, remote mutation, or recovery-project reactivation is
   needed or authorized here.
3. After those checks and activation approval, apply writer/reader/helper/docs
   together while preserving concurrency, current credentials, all old snapshots,
   and shared versions. Run one controlled format-2 backup, read-only verify it,
   and confirm the next unchanged run's source payload count. Keep no lifecycle
   rule that removes referenced shared versions.
4. Rollback the writer only if needed; keep the format-2-aware reader/helper and
   every R2 version/manifest so all prior dates remain recoverable. A separate
   authorized SQL/app restore drill remains distinct from this read-only review.

Neither access blocker was an automatic-review denial or an uncertain remote
operation. Both requested remote payload operations were intentionally left
unattempted because the required existing access was unavailable.
