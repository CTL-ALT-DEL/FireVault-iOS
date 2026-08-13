# FireVault Pro for iPhone, iPad, and CarPlay

FireVault Pro is a native SwiftUI field workspace for fire-alarm technicians.
It organizes customer accounts, equipment, saved locations, notes, photos,
document scans, Trip Log history, reports, maps, and driving-safe CarPlay tools.

## Open and run

1. Open `FireVault.xcodeproj` in Xcode.
2. Select the `FireVault` scheme.
3. Select an iPhone, iPad, or Simulator.
4. Use **Product → Clean Build Folder** after switching build branches.
5. Press **Run**.

Supabase package dependencies resolve through Swift Package Manager. CarPlay
testing requires Xcode's paired iPhone and CarPlay simulators or an approved
physical CarPlay environment.

## Verify a candidate

Run the repeatable local verification command:

```text
scripts/verify-build.sh
```

Override the simulator when necessary:

```text
FIREVAULT_TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro' scripts/verify-build.sh
```

The script performs an unsigned generic-device build, the unit-test suite, and
the targeted Warm Ivory/accessibility UI smoke tests. Location changes still
require the physical-device checks recorded in the active build checklist.

## Data safety

- Keep an approved `main` commit as the rollback point.
- Do not delete the installed app before exporting a current vault backup.
- Demo records are isolated from the live workspace.
- Full backups use the `.firevaultbackup` format; legacy account-only JSON files
  remain importable.

See `CURRENT_BUILD.md` for the official baseline and active candidate.
