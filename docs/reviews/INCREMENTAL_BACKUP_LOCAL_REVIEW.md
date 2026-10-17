# Incremental disaster backup — local review, 2026-10-16

Follow-up: `INCREMENTAL_BACKUP_PREACTIVATION_REVIEW.md` records the independent
review, later read-only aggregate live checks, and recovery-selection hardening.
This document describes the initial implementation phase.

Status: implemented and fixture-tested locally; **not activated, pushed, merged,
or deployed**. No production service was contacted. No backup credentials were
read or configured. No app build, TestFlight upload, phone installation, schema
change, or customer-data write was performed.

## Isolation and scope

The review branch is `backup/incremental-storage` in the isolated
`2026-10-16/task/backup-fix` repository. Its baseline is an archive of committed
FireVault-iOS HEAD `a4c386c54ee3cae790311fd883b748c425eee1da`, independently
initialized as local commit `ec73f20bc857839dcc24a96c7663276a86e4d3e7`.
The original Desktop checkout and the build-197 candidate were left untouched.
The baseline backup writer's SHA-256 exactly matches the candidate's copy:
`19e80d972fcd33644c28f1f2351e0b8d03f8ade39f2c0859482e82f36e8eb84b`.

Changes are limited to the backup writer, a Python standard-library Storage
helper, the existing recovery reader, backup test fixtures, and backup/recovery
documentation. Workflow schedules, credentials, concurrency, database dump
commands, app/release files, and target-project recovery guards are unchanged.

## Result

Format-2 daily manifests reference immutable encrypted R2 file versions. Reliable
source MD5/size/modification-time/metadata matches reuse an existing verified
version. The manifest retains MIME/cache metadata and the Storage restore
applies it to the separate target project.
Only new/changed or unverifiable source payloads download. Each new version is
read back from R2 and SHA-256 checked. Deleted keys are absent only from the new
manifest; old manifests retain the old versions. Recreated keys receive new
versions. A second source inventory must match before completion. The manifest
is also read back before the `_SUCCESS` commit marker.

The first format-2 run can seed unchanged bytes from the latest full legacy R2
snapshot, verifying its contents against the current source MD5. It therefore
does not require an unnecessary full Supabase download. Existing snapshots and
database dumps are never deleted or rewritten. Completed IDs are no-ops;
incomplete attempts can leave unreferenced versions and may recopy uncommitted
changes on retry. No deletion/garbage-collection feature is introduced.

## Verification

- Eight end-to-end fixture tests passed with real rclone crypt 1.75.1 on macOS
  arm64 (`Ran 8 tests`, `OK`). The local-only adapter forbids remote
  deletion commands, source writes, and network backends, and uses fake SQL
  dumps. The suite covered baseline; zero-download unchanged runs; new objects
  and buckets; empty buckets and files; Unicode/space keys; same-size/same-time
  edits; deleted and recreated objects; MIME/cache metadata and metadata-only changes; five historical reconstructions; latest
  selection; actual guarded Storage restores of current/historical data into
  temporary local targets; and repeated completed IDs with identical R2 bytes.
- Failure coverage passed: interrupted version upload and commit, retry of the
  same incomplete ID, no false success marker, failed R2 listing, concurrent
  source mutation, missing checksums, missing version references, same-size
  content corruption, failed upload readback, unsafe keys, and cross-prefix
  reference rejection. Previously committed encrypted fixture bytes were
  asserted unchanged.
- Real encrypted legacy format-1 download/recovery and format-1-to-2 seeding
  passed. A changed legacy file downloaded from the simulated source; its
  unchanged sibling seeded from R2. A subsequent run downloaded no source files.
- Existing `test-recover-supabase-from-r2.sh` passed, including legacy checksums,
  corrupt-dump rejection, explicit apply/target guards, source-project rejection,
  nonempty database rejection, and mocked database/Storage restore behavior.
- Bash syntax, Python AST parsing, and `git diff --check` passed.
- rclone download SHA-256 matched its published v1.75.1 checksum:
  `c61d7a371c62bcbbe882c3423aa4b8bf63485c248dd0f692997b8f0c3f6d0c6f`
  for `rclone-v1.75.1-osx-arm64.zip`. The binary was downloaded only into `/tmp`.

Reproduce with:

```bash
FIREVAULT_TEST_RCLONE=/path/to/rclone scripts/test-backup-supabase-to-r2.sh
scripts/test-recover-supabase-from-r2.sh
```

## Savings and limits

For 218 MB of unchanged source files with reliable MD5s, ongoing Storage payload
reads fall from about 6.54 GB per 30 days to zero after seeding. With 10 MB/day
of changed/new data, that portion is about 300 MB/month, roughly 95% lower.
Database dumps, metadata/list/HEAD traffic, and R2 verification reads remain.
R2 retains all old backups and adds a one-time version pool during seeding.

No live Supabase hash coverage, S3/R2 interoperability, or real PostgreSQL restore
was tested. Hashless/multipart objects are conservatively copied each run; the
real checksum coverage is an explicit rollout check. Nightly checks of reused
versions verify existence/size; weekly recovery verifies full SHA-256 contents.
The database and Storage do not form one atomic cross-service transaction.
Specially encoded/unsafe filenames fail closed, and case-distinct names need a
case-sensitive recovery filesystem. Processing changed files serially can be
slower for a large changed set. Shared-version retention needs manifest-aware
planning; an ordinary age-based lifecycle must not delete referenced versions.

## Rollout and rollback requirements

After review and separate activation approval, apply writer, reader, helper,
tests, and documentation together. Run one controlled backup using existing
credentials, verify logged MD5 coverage and source-download bytes, and use the
updated read-only recovery downloader on that exact snapshot and an older
legacy snapshot. Confirm the following unchanged run avoids source payload
transfers. Monitor actual egress; perform a separate-project SQL/app restore
drill before asserting full backend recovery readiness.

For rollback, restore the old full-snapshot **writer only** and retain the
format-2-aware recovery reader/helper plus every R2 manifest/version. This
resumes higher egress while preserving all recoverable dates. No app or schema
rollback is needed. Nothing in this local change authorizes activation.
