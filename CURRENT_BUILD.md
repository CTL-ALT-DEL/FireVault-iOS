# FireVault Current Build

## Official `main` baseline

- Visible version: **1.08.56**
- Build number: **116**
- Main includes the tested CarPlay workspace and protected Google Places stop
  classification corrections.

## Active candidate

- Branch: `build/1.08.60-vault-reliability-optimization`
- Purpose: complete backups, scalable persistence, media housekeeping, Trip Log
  energy improvements, regression coverage, accessibility, and release hygiene.
- The candidate intentionally keeps version **1.08.56 (116)** until local Xcode
  and physical-device testing are approved.
- Acceptance checklist: `BUILD_1.08.60_CHECKLIST.md`

## Release rule

1. Development happens on a protected `build/*` branch.
2. The generic iOS device build and automated tests must pass.
3. Location-related changes require a physical-device field test.
4. The visible version/build is changed only after approval.
5. Only the approved candidate is merged into `main`.

Deleting FireVault from a device deletes its local app container. Export a
complete vault backup before removing the installed app.
