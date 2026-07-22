# FireVault iPhone App — Build 1.03.31 · Native Settings Polish

This Xcode project installs FireVault’s native SwiftUI app shell, the Account Field Workspace, Apple Maps, Liquid Glass controls, the FireVault flame icon, and Apple’s built-in document camera. Nearby, Accounts, Photo access, and the simplified five-area Settings hub now use the native shell. Established editors continue using the deployed FireVault vault engine so existing data and save workflows remain compatible.

This build uses native build number 32 and marketing version 1.03.31. It preserves the existing web bridge and stored-data behavior while refining the native grouped Settings experience, accessibility metadata, version display, and repository hygiene.

## Install in the correct order

1. Clone or pull the `FireVault-iOS` GitHub repository.
2. Commit the upload to the `main` branch.
3. Open the repository’s **Actions** page and wait for the newest Pages deployment to turn green.
4. On the Mac, extract the native Xcode ZIP to a normal folder such as **Downloads** or **Documents**.
5. Open the extracted `FireVault` folder, then double-click the blue `FireVault.xcodeproj` project file.
6. Connect and unlock the iPhone. Trust the Mac if the iPhone asks. 
7. In Xcode’s top device selector, choose the connected iPhone instead of a Simulator.
8. If Xcode shows a signing warning, select the blue FireVault project, select the FireVault app target, open **Signing & Capabilities**, and choose your Personal Team.
9. Press the triangular **Run** button. Keep the iPhone connected until Xcode reports that the app is running.

Do not delete the existing FireVault iPhone app before installing this build. Installing with the same bundle identifier preserves the native app’s local vault; deleting the app also deletes that app container’s local data. Export a current FireVault backup before replacing or removing the app.

## Test Apple Document Scanner

1. Open FireVault on the physical iPhone.
2. Open the correct customer account.
3. Tap **Scan** in the native Field Workspace action dock.
4. Capture one or more pages with Apple’s scanner, review the detected edges, and tap **Done**.
5. Enter a title, choose a document type, add optional notes, and tap **Save Scan**.
6. Confirm FireVault returns to the same account. Open **Files & Scans** later and verify Preview, Download PDF, and Share.

The Scan Document button appears only in this native iPhone app. It is intentionally hidden in the Safari/PWA version because Apple VisionKit is an iOS-native camera service.
