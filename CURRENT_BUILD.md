# FireVault Current Build

## Official `main` release candidate

- Visible version: **1.08.69**
- Build number: **129**
- Includes the tested CarPlay optimization and the four-widget portfolio:
  Dashboard, Trip Log, Field Account, and Cloud Status.
- Intended distribution: TestFlight.

## Release rule

1. Development happens on a protected `build/*` branch.
2. The generic iOS device build and automated tests must pass.
3. Location-related changes require a physical-device field test.
4. The visible version/build is changed only after approval.
5. Only the approved candidate is merged into `main`.

Deleting FireVault from a device deletes its local app container. Export a
complete vault backup before removing the installed app.
