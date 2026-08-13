# Build 1.08.60 — Vault Reliability & Optimization

This checklist is the acceptance record for the optimization audit approved on
August 13, 2026. A checked item requires implementation plus an automated or
documented verification step. The visible app version and build number remain
unchanged until device testing is approved.

## Data safety and storage

- [x] Export and restore a versioned full-vault backup containing accounts,
      settings, Trip Log history, and referenced photos/scans.
- [x] Preserve compatibility with legacy account-only JSON backups.
- [x] Move production account persistence from `UserDefaults` to a versioned,
      atomic Application Support archive with automatic legacy migration.
- [x] Coalesce file writes away from the main UI path and retain a last-known-good
      backup.
- [x] Add photo/scan deletion, orphan cleanup, and storage-usage reporting.

## Location and energy

- [x] Keep Nearby and Trip Log on a single active location owner.
- [x] Use battery-conscious route sampling and adaptive accuracy without weakening
      arrival or departure detection.
- [x] Verify GPS diagnostics cannot remain active after its screen closes.
- [x] Document a physical-device battery test procedure.
- [ ] Complete the comparative physical-device battery test and record the
      result. This cannot be substituted with a Simulator test.

## Quality and release readiness

- [x] Add Light/Dark contrast regression coverage plus a Warm Ivory Settings
      visual reference and primary-navigation smoke coverage.
- [x] Check Dynamic Type, VoiceOver labels, Reduce Motion, and increased contrast.
- [x] Update stale build and repository documentation.
- [x] Add repeatable local release verification.
- [x] Run the unsigned generic iPhone build, unit tests, and targeted UI smoke tests.

## Scope protection

- Do not merge this branch into `main` before user approval.
- Do not change `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` before approval.
- Do not remove legacy data until its replacement archive has been decoded and
  validated successfully.
