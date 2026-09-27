# FireVault recovery test build for Mac

This branch is **only** for testing the September 27 recovery project
`llfvzebabfkxslrlgwav`. It points the iOS client to that project's public
URL and publishable key. No service-role key or other private credential is
in this branch. A compile-time guard blocks Release builds. Do not merge this
branch into `main`, archive it, upload it to TestFlight, or use it on the
iPhone that has your normal FireVault app.

## Run on a fresh iPhone Simulator

1. On the Mac, sign in to GitHub and download this branch's ZIP file:
   `https://github.com/CTL-ALT-DEL/FireVault-iOS/archive/refs/heads/recovery-test-ios-20260927.zip`.
2. Extract the ZIP to a new local folder.
3. Open `FireVault.xcodeproj` inside that folder with Xcode.
4. In Xcode's top bar, select the **FireVault** scheme and an **iPhone Simulator**.
   Use a fresh simulator so it has no production FireVault session or local data.
5. Choose **Product → Clean Build Folder**, then **Product → Run**. Xcode may
   first download the project's Swift packages and simulator components.
6. In the Simulator, sign in with your own FireVault email and password. Enter
   them only in the app; do not send them in chat. The restored Auth users are
   in the recovery project.
7. Open one familiar account and one Backed-Up Media original. Confirm the
   account details and file open. Avoid AI, Google Places, Trip Log email,
   subscription actions, and account deletion; this recovery project has no
   Edge Functions or external-provider secrets configured.
8. Tell Codex whether sign-in, account opening, and file opening worked.
   If something fails, share the error text without passwords, keys, or
   personal file contents.

The separate recovery database has the copied data and file bytes. Its eight
Storage access policies match production. SQL-level checks found that the
owner can see their files and a different user and anonymous user cannot.
A real app test is still needed.

When finished, close this Xcode project. Open the normal `main` branch for
any production build. This branch must not be distributed.
