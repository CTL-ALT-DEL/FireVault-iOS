# FireVault Current Build

## Official `main` release candidate

- Visible version: **1.08.72**
- Build number: **132**
- Includes the tested CarPlay optimization and four-widget portfolio:
  Dashboard, Trip Log, Field Account, and Cloud Status.
- Includes the rebuilt searchable Help Center with task-based guides, concise
  visuals, troubleshooting, and accurate account-sync guidance.
- Credits Bannerman US LLC as the creator, developer, and publisher in About.
- Adds a clickable Bannerman US LLC website, corrected iPhone/iPad capability
  icons, and a true compile-time build timestamp on the About screen.
- Moves account identity, compact Cloud Sync status, Sync Now, and Sign Out into
  Technician Profile while keeping required account deletion under Security.
- Intended distribution: TestFlight.

## Release rule

1. Development happens on a protected `build/*` branch.
2. The generic iOS device build and automated tests must pass.
3. Location-related changes require a physical-device field test.
4. The visible version/build is changed only after approval.
5. Only the approved candidate is merged into `main`.

Deleting FireVault from a device deletes its local app container. Export a
complete vault backup before removing the installed app.
