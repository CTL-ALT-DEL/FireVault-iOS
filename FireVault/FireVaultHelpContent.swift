//
//  FireVaultHelpContent.swift
//  FireVault
//
//  Testable, task-based help content shared by the native Help center views.
//

import Foundation

enum FireVaultHelpTopicID: String, CaseIterable, Identifiable {
    case quickStart
    case accounts
    case cloudSync
    case tripLog
    case carPlay
    case fieldCapture
    case widgets
    case privacy
    case troubleshooting

    var id: String { rawValue }
}

enum FireVaultHelpVisual: String, Equatable {
    case quickStart
    case account
    case cloudSync
    case tripLog
    case carPlay
    case fieldCapture
    case widgets
    case privacy
    case troubleshooting
}

struct FireVaultHelpStep: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String

    init(_ id: String, _ title: String, _ detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

struct FireVaultHelpResource: Identifiable, Equatable {
    let id: String
    let title: String
    let url: URL
}

struct FireVaultHelpTopic: Identifiable, Equatable {
    let id: FireVaultHelpTopicID
    let eyebrow: String
    let title: String
    let summary: String
    let symbol: String
    let tint: String
    let visual: FireVaultHelpVisual
    let steps: [FireVaultHelpStep]
    let successTitle: String
    let successDetail: String
    let notes: [String]
    let resources: [FireVaultHelpResource]

    var searchableText: String {
        ([eyebrow, title, summary, successTitle, successDetail]
            + steps.flatMap { [$0.title, $0.detail] }
            + notes)
            .joined(separator: " ")
            .lowercased()
    }
}

enum FireVaultHelpCatalog {
    static let topics: [FireVaultHelpTopic] = [
        .init(
            id: .quickStart,
            eyebrow: "START HERE",
            title: "Set up your field day",
            summary: "Sign in, confirm your accounts, and start Trip Log without hunting through settings.",
            symbol: "flag.checkered",
            tint: "green",
            visual: .quickStart,
            steps: [
                .init("quick-login", "Log in", "Open FireVault Pro and use Log In. If the main tabs are already visible, you are signed in."),
                .init("quick-sync", "Check the vault", "Open Settings → Technician Profile, then tap Sync Now. Wait for account-record status to read Up to date."),
                .init("quick-accounts", "Find an account", "Open Accounts and search by name, address, or account ID. Tap a result to open its field workspace."),
                .init("quick-trip", "Start the workday", "Open Trip Log, tap Recording, then Start Trip Log. The status changes from READY to RECORDING.")
            ],
            successTitle: "Ready for the road",
            successDetail: "Your accounts are visible, cloud status is current, and Trip Log clearly says RECORDING.",
            notes: [
                "Trip Log does not begin automatically. You stay in control of when route recording starts and stops.",
                "Demo Mode uses a separate fictional vault and never changes your live customer records."
            ],
            resources: []
        ),
        .init(
            id: .accounts,
            eyebrow: "CUSTOMER RECORDS",
            title: "Find, edit, and delete one account",
            summary: "Keep a single site accurate without affecting the rest of your account database.",
            symbol: "building.2.crop.circle",
            tint: "blue",
            visual: .account,
            steps: [
                .init("account-open", "Open the customer", "Tap Accounts, search for the customer, then tap its account card."),
                .init("account-edit", "Update the record", "Tap Edit for common fields. Notes, Files & Scans, Equipment, and Locations each open their own workspace."),
                .init("account-delete", "Delete only this customer", "Tap the red Delete Customer Account button near the bottom, or use the ••• account-actions menu, then confirm Delete Customer Account."),
                .init("account-confirm", "Confirm the result", "FireVault returns to Accounts after the local and cloud record are removed. If cloud deletion fails, nothing is deleted locally.")
            ],
            successTitle: "One account—not your login",
            successDetail: "Delete Customer Account removes the selected customer and its field records. It does not delete your FireVault sign-in or other customers.",
            notes: [
                "Deletion cannot be undone. Create a protected backup first if the record may be needed later.",
                "Use Arrival Map to save precise parking, entrance, panel, or riser pins for the customer."
            ],
            resources: []
        ),
        .init(
            id: .cloudSync,
            eyebrow: "FIREVAULT CLOUD",
            title: "Sync account records",
            summary: "Understand what Sync Now does, what the timestamps mean, and how to recover from an error.",
            symbol: "arrow.triangle.2.circlepath",
            tint: "purple",
            visual: .cloudSync,
            steps: [
                .init("sync-open", "Open cloud status", "Go to Settings → Technician Profile and find Cloud Sync below your contact information."),
                .init("sync-run", "Run a manual check", "Tap Sync Now. Keep FireVault open while the progress indicator is visible."),
                .init("sync-read", "Read the result", "Up to date means the account-record sync finished. Last checked is the latest attempt; Last successful sync is the latest completed sync."),
                .init("sync-retry", "Retry safely", "If Status says Needs attention, check the connection and sign-in, then tap Sync Now again. FireVault keeps local records when a sync fails.")
            ],
            successTitle: "What is actually synced",
            successDetail: "Sync Now exchanges customer account records with your private FireVault Cloud vault and resolves older records that predate cloud sync.",
            notes: [
                "Photos and scans follow the destinations configured under Settings → File Storage; they are not uploaded by the account-record Sync Now button.",
                "A Last checked time without a newer Last successful sync usually means the most recent attempt did not finish."
            ],
            resources: []
        ),
        .init(
            id: .tripLog,
            eyebrow: "ROUTE & GPS",
            title: "Record a clean Trip Log",
            summary: "Start deliberately, verify GPS, manage pauses, and export the correct day.",
            symbol: "truck.box.fill",
            tint: "red",
            visual: .tripLog,
            steps: [
                .init("trip-start", "Start recording", "Open Trip Log → Recording → Start Trip Log. Approve location access if iPhone asks."),
                .init("trip-verify", "Verify the status", "Look for RECORDING and route active. The map begins drawing after reliable GPS points arrive."),
                .init("trip-pause", "Pause only when needed", "Tap Recording → Pause Recording to stop collection temporarily. Choose Resume Recording when work continues."),
                .init("trip-end", "Finish the day", "Tap Recording → Stop Trip Log, then confirm End Trip Log. Use History to choose a saved day and Report to preview or export it.")
            ],
            successTitle: "Best GPS results",
            successDetail: "Keep Precise Location on. Mount the iPhone with a clear view of the sky when possible and check GPS Diagnostics if accuracy remains poor.",
            notes: [
                "If FireVault shows Open Location Settings, tap it. In iPhone Settings, allow location access for FireVault Pro and turn on Precise Location.",
                "Trip Log history stays on this iPhone unless you explicitly export a report or create a protected backup."
            ],
            resources: [
                .init(
                    id: "apple-location",
                    title: "Apple: Control Location Services",
                    url: URL(string: "https://support.apple.com/guide/iphone/control-the-location-information-you-share-iph3dd5f9be/ios")!
                )
            ]
        ),
        .init(
            id: .carPlay,
            eyebrow: "CARPLAY",
            title: "Use FireVault on the road",
            summary: "Get the right dashboard, nearby accounts, arrival details, and saved drop pins with minimal taps.",
            symbol: "car.fill",
            tint: "blue",
            visual: .carPlay,
            steps: [
                .init("car-connect", "Connect iPhone", "Use your vehicle’s supported USB or wireless CarPlay setup. FireVault appears automatically among compatible CarPlay apps."),
                .init("car-trip", "Record from Trip Log", "Open FireVault in CarPlay, choose Trip Log, then Start Trip Log. The dashboard shows trip distance, stops, elapsed time, and GPS accuracy."),
                .init("car-nearby", "Choose a destination", "Open Nearby to see mapped accounts. Select an account to review it or begin routing."),
                .init("car-arrive", "Use the Arrived screen", "When FireVault recognizes arrival near a mapped account, Arrived shows the customer and its saved drop-pin locations when available."),
                .init("car-diagnose", "Check live GPS", "Open Drive for speed, elevation, heading, coordinates, GPS accuracy, and the age of the latest location reading.")
            ],
            successTitle: "Why an account may be missing",
            successDetail: "CarPlay can show only accounts with usable coordinates. Add or adjust the account pin on iPhone, then reconnect or refresh CarPlay.",
            notes: [
                "Keep driving interactions glanceable. Make detailed edits on iPhone after parking.",
                "Saved parking and entrance pins are prioritized on the Arrived screen."
            ],
            resources: [
                .init(
                    id: "apple-carplay",
                    title: "Apple: Connect and use CarPlay",
                    url: URL(string: "https://support.apple.com/102521")!
                )
            ]
        ),
        .init(
            id: .fieldCapture,
            eyebrow: "PHOTOS & LOCATIONS",
            title: "Capture useful field records",
            summary: "Attach clear photos, scans, notes, equipment, and arrival pins to the correct customer.",
            symbol: "camera.viewfinder",
            tint: "amber",
            visual: .fieldCapture,
            steps: [
                .init("capture-account", "Choose the customer first", "Open an account for notes, equipment, files, scans, and locations. Use the Photo tab for a new photo, video, scan, or photo-library capture."),
                .init("capture-overlay", "Check the overlay", "Before field photos or videos, review Settings → Photo Overlay so the visible account information and logo are useful and not intrusive."),
                .init("capture-save", "Save to the right place", "Select the customer when prompted and confirm the save result. Photos, overlaid videos, and scans appear under that account’s Files & Scans workspace."),
                .init("capture-pin", "Place precise arrival pins", "Open the account’s Arrival Map or Locations workspace. Add a location, name its purpose, and drag the pin to the actual entrance, parking area, panel, or riser.")
            ],
            successTitle: "Storage is explicit",
            successDetail: "Review Settings → File Storage before relying on an external destination. Connected storage remains inactive until it is configured.",
            notes: [
                "A descriptive location label such as Main Entrance or South Parking is more useful in CarPlay than a generic pin name.",
                "Protected backups can include referenced photos and scans along with accounts, settings, and Trip Log history."
            ],
            resources: []
        ),
        .init(
            id: .widgets,
            eyebrow: "HOME & LOCK SCREEN",
            title: "Choose the right widget",
            summary: "Use four focused designs instead of trying to squeeze every field tool into one card.",
            symbol: "rectangle.grid.2x2.fill",
            tint: "green",
            visual: .widgets,
            steps: [
                .init("widget-open", "Open the widget gallery", "Touch and hold an empty area on the Home Screen until apps jiggle. Tap Edit, then Add Widget."),
                .init("widget-find", "Find FireVault", "Search for FireVault, tap it, then swipe through the available designs and sizes."),
                .init("widget-add", "Place the widget", "Tap Add Widget, move it where you want it, then tap Done."),
                .init("widget-account", "Choose a field account", "For the Field Account widget, touch and hold the widget, tap Edit Widget, then choose the customer to display.")
            ],
            successTitle: "Four designs, different jobs",
            successDetail: "Field Dashboard opens the workspace; Trip Log emphasizes recording; Field Account returns to a customer; Cloud Status shows account-sync health.",
            notes: [
                "Field Dashboard and Trip Log support Home Screen and Lock Screen families. Field Account is available in small, medium, and large Home Screen sizes.",
                "Open FireVault after updating so widgets can receive a fresh snapshot. iOS controls the final widget refresh schedule."
            ],
            resources: [
                .init(
                    id: "apple-widgets",
                    title: "Apple: Add and edit widgets",
                    url: URL(string: "https://support.apple.com/guide/iphone/add-edit-and-remove-widgets-iphb8f1bf206/ios")!
                )
            ]
        ),
        .init(
            id: .privacy,
            eyebrow: "PRIVACY & RECOVERY",
            title: "Protect, back up, or delete data",
            summary: "Know the difference between locking the app, backing up the vault, deleting one customer, and deleting your sign-in.",
            symbol: "lock.shield.fill",
            tint: "purple",
            visual: .privacy,
            steps: [
                .init("privacy-lock", "Lock private screens", "Open Settings → Security to require device authentication and optionally hide content in the app switcher."),
                .init("privacy-backup", "Create a protected backup", "Open Settings → Backup & Restore, create the backup, and save the exported file somewhere you control."),
                .init("privacy-customer", "Delete one customer", "Open that customer and choose Delete Customer Account. This removes only the selected customer and its field records."),
                .init("privacy-login", "Delete the FireVault sign-in", "Open Settings → Security → Account Data & Deletion, choose Delete FireVault Account, then confirm Delete Account and Data. This permanently removes the cloud sign-in and its data, then clears matching local account records.")
            ],
            successTitle: "Pause before permanent deletion",
            successDetail: "Both deletion choices are intentionally named differently. Read the confirmation carefully and make a backup first when recovery may matter.",
            notes: [
                "Signing out is not deletion. It disconnects the device while keeping local information on the iPhone.",
                "If full cloud-account deletion fails, FireVault leaves local data on the iPhone."
            ],
            resources: []
        ),
        .init(
            id: .troubleshooting,
            eyebrow: "QUICK FIXES",
            title: "When something looks wrong",
            summary: "Use the status that FireVault already shows before changing settings or reinstalling anything.",
            symbol: "wrench.adjustable.fill",
            tint: "red",
            visual: .troubleshooting,
            steps: [
                .init("fix-sync", "Sync says Needs attention", "Confirm the iPhone is online and you are signed in. Open Settings → Technician Profile, read the Cloud Sync error, then tap Sync Now again."),
                .init("fix-gps", "Trip Log is waiting for GPS", "Keep the workday active, move into open sky if possible, and confirm Precise Location is on. Open Settings → GPS & Maps → GPS Diagnostics for live accuracy."),
                .init("fix-carplay", "CarPlay shows no nearby accounts", "Open the customer on iPhone and add valid coordinates or adjust its map pin. Reopen FireVault in CarPlay after the account is mapped."),
                .init("fix-widget", "A widget looks stale", "Open FireVault once, confirm the desired account or Trip Log state, then return to the Home Screen. iOS refreshes widgets on its own schedule."),
                .init("fix-missing", "A feature seems missing", "Check whether Demo Mode is active and search Settings by the feature name. Connected storage tools remain unavailable until configured.")
            ],
            successTitle: "Still stuck?",
            successDetail: "Include what you tapped, the exact message, and a screenshot when contacting support. That usually identifies the problem fastest.",
            notes: [
                "Do not delete and reinstall the app as a first troubleshooting step; local-only records may be removed with the app.",
                "A timestamp or exact error message is more useful than a general description such as “sync is broken.”"
            ],
            resources: []
        )
    ]

    static func topic(_ id: FireVaultHelpTopicID) -> FireVaultHelpTopic? {
        topics.first { $0.id == id }
    }

    static func matching(_ query: String) -> [FireVaultHelpTopic] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return topics }
        return topics.filter { $0.searchableText.contains(normalized) }
    }
}
