# FireVault Current Build

**Current development candidate: 1.08.58 (118)**

Build 1.08.58 (118) adds visible FireVault account status and sign-out controls
to Settings on iPhone and iPad. It must compile and pass the Xcode test suite
before it replaces the latest tested build below.


**Latest tested build: 1.08.42 (101)**

Build 1.08.42 (101) became the official latest tested build after the iPhone
target compiled and the FireVault unit-test suite passed locally. Future build
candidates must meet the same build-and-test requirement before replacing it.

This is the only number to use when deciding whether an installed copy is current.
In FireVault, open **Settings → About FireVault** and compare the displayed version
and build with the number above.

## Included in 1.08.42 (101)

- Fixed the Accounts add action so a new account is immediately selected and opened
- Added production-safe blank defaults without fabricated coordinates
- Added Edit Account for name, address, category, account ID, and phone number
- Preserved account identity, favorites, coordinates, field records, files, equipment,
  saved locations, and recent history while editing account details
- Migrated Home Screen quick actions to the `us.bannerman.firevault` namespace while
  retaining compatibility with legacy installed shortcuts

## Included in 1.08.39 (97)

- Structured FireVault account briefs
- Flexible CSV import with latitude/longitude recognition and mapping review
- Restored Trip Log start, pause/resume, stop, history, and report workflow
- Updated amber radius selector
- Nearby map zooms only after account-list scrolling settles
- Nearby Accounts refresh and re-sort live while driving
- Nearby rows stay one-line while scrolling and expand only when selected
- Centered Nearby account/range summary and auto-collapsing radius selector
- More compact Account Detail titles and Field Workspace tiles
- Simplified Generate Account Brief action
- Preferred Compact, Simple, or customizable Advanced Settings layouts
- Hidden Developer Center unlocked by tapping the About version four times
- Persistent Simple-mode feature switches and safe development diagnostics
- Executable local-vault, storage, authentication, and Supabase table diagnostics
- Optional billable AI Edge Function test with copyable results and timing
- Restored fully expanded cards for every Nearby Account list item
- Dark, porcelain Light, and System Default appearance themes
- Fixed the authentication container overriding the selected app theme
- Removed beveled map borders and added porcelain Light-theme map shadows
- Removed the Nearby Accounts radius slider (radius remains in GPS Settings)
- Improved header and Trip Log text contrast in Light mode
- Removed the Trip Log waypoints-per-minute display
- Added a tappable animated truck in the header while Trip Log is recording
- Added a stationary amber truck while Trip Log is paused
- Replaced the sliding Trip Log truck with rotating wheels and passing trees
- Removed the animated Trip Log header icon
- Added diffused depth shadows to bottom navigation buttons
- Added a diffused shadow to the splash-screen FireVault title
- Added layered depth shadows to Nearby Account cards
- Extended diffused card depth throughout shared app surfaces and Account Details
- Added shadows to cards in Accounts Search
- Restored a distinct haptic click on every Nearby Account tap
- Redesigned Account Details with a unified identity card and field actions
- Rebuilt About FireVault with the real logo and justified product description
- Removed the obsolete App Updates section
- Redesigned Customer CSV Import with staged progress, mapping feedback, and concise results
- Indexed large CSV imports for faster account matching
- Added working JSON vault export and safe backup merge
- Replaced the placeholder Security page with device and workspace protection controls
- Corrected completed Trip Log stop durations so they never grow with the current clock
- Redesigned daily and weekly Trip Log PDFs with compact pagination and readable stop details
- Added accurate arrival-to-departure time ranges and stop-duration badges to PDF reports
- Inferred missing historical departures from the next stop instead of inflating durations
- Connected the active portrait Trip Log to the complete stop editor
- Added custom stop titles and one-tap account creation from an unassigned stop
- Added the real FireVault flame logo and a premium masthead to PDF reports
- Added inline-email JPG report sharing for daily and weekly report pages
- Kept Settings content clear of the fixed bottom navigation
- Removed temporary native-build language from customer-facing Settings copy
- Aligned the FireVault wordmark with the day-of-week header label
- Reduced the bottom navigation height while retaining 48-point touch targets
- Centered the lower navigation controls and added a pulsing green Trip Log recording glow
- Rewrote About FireVault with field-focused product copy and David Bannerman developer credit
- Replaced the Nearby Accounts vault label with Trip Log status and right-aligned live location status
- Added David@Bannerman.us to About FireVault
- Replaced selected-navigation glow with a darker 3D-style shadow; the Trip Log truck is bright green while recording
- Simplified the About FireVault email and styled the supporting developer message in script

## Roadmap

- Future: optional photo/report QR overlay that encodes the captured image's
  Plus Code or exact map-location URL so a recipient can scan the photo or
  report and open the precise location.

## Simple release rule

1. Every user-visible update receives a new app version and build number.
2. The version in **Settings → About FireVault** is authoritative.
3. Branch names and Git staging status do not identify the installed app version.
4. A build is called “latest” only after the iPhone target builds and unit tests pass.
