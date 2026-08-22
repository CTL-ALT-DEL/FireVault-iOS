//
//  FireVaultSiriIntents.swift
//  FireVault
//
//  Local, privacy-conscious account lookup for Siri and Shortcuts.
//

import AppIntents
import CoreLocation
import MapKit
import UIKit

struct FireVaultAccountEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "FireVault Account")
    static var defaultQuery = FireVaultAccountEntityQuery()

    let id: String

    @Property(title: "Site Name")
    var name: String

    @Property(title: "Account ID")
    var accountID: String

    @Property(title: "Address")
    var address: String

    @Property(title: "Category")
    var category: String

    fileprivate var phone: String
    fileprivate var latitude: Double?
    fileprivate var longitude: Double?

    var displayRepresentation: DisplayRepresentation {
        let identifier = accountID.isEmpty ? category : accountID
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(identifier) • \(category)"
        )
    }

    fileprivate init(account: FireVaultWorkspaceAccount) {
        id = account.id
        phone = account.phone
        latitude = account.latitude
        longitude = account.longitude
        name = account.name
        accountID = account.accountId
        address = account.address
        category = account.category
    }

    fileprivate var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }
}

struct FireVaultAccountEntityQuery: EntityStringQuery {
    func entities(for identifiers: [FireVaultAccountEntity.ID]) async throws -> [FireVaultAccountEntity] {
        let entities = await FireVaultSiriAccountData.allEntities()
        let byID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0] }
    }

    func entities(matching string: String) async throws -> [FireVaultAccountEntity] {
        await FireVaultSiriAccountData.matchingEntities(string)
    }

    func suggestedEntities() async throws -> [FireVaultAccountEntity] {
        Array(await FireVaultSiriAccountData.allEntities().prefix(10))
    }
}

struct FindFireVaultAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Find FireVault Account"
    static var description = IntentDescription(
        "Looks up a FireVault account by site name, Account ID, address, or category without exposing field notes."
    )

    @Parameter(title: "Account")
    var account: FireVaultAccountEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$account)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let accountID = account.accountID.isEmpty ? "No Account ID" : "Account \(account.accountID)"
        return .result(dialog: "\(account.name). \(accountID). Category: \(account.category).")
    }
}

struct FindNearestFireVaultAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Nearest FireVault Account"
    static var description = IntentDescription(
        "Finds the nearest mapped FireVault account using the most recent location recorded by FireVault."
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let currentLocation = FireVaultSiriLocationCache.recentLocation else {
            return .result(dialog: "Open FireVault to refresh your location, then ask again.")
        }

        let mapped = await FireVaultSiriAccountData.allEntities().compactMap { entity -> (FireVaultAccountEntity, CLLocationDistance)? in
            guard let coordinate = entity.coordinate else { return nil }
            let destination = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return (entity, currentLocation.distance(from: destination))
        }

        guard let nearest = mapped.min(by: { $0.1 < $1.1 }) else {
            return .result(dialog: "I couldn't find a mapped FireVault account.")
        }

        let miles = nearest.1 / 1_609.344
        let identifier = nearest.0.accountID.isEmpty ? "" : ", account \(nearest.0.accountID)"
        return .result(dialog: "The nearest site is \(nearest.0.name)\(identifier), \(String(format: "%.1f", miles)) miles away.")
    }
}

struct RouteToFireVaultAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Route to FireVault Account"
    static var description = IntentDescription("Opens driving directions to a mapped FireVault account.")
    static var openAppWhenRun = true

    @Parameter(title: "Account")
    var account: FireVaultAccountEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Route to \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let coordinate = account.coordinate else {
            return .result(dialog: "\(account.name) doesn't have a mapped location yet.")
        }

        let mapItem = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        mapItem.name = account.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
        return .result(dialog: "Opening driving directions to \(account.name).")
    }
}

struct CallFireVaultAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Call FireVault Account"
    static var description = IntentDescription("Calls the primary telephone number saved for a FireVault account.")
    static var openAppWhenRun = true

    @Parameter(title: "Account")
    var account: FireVaultAccountEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Call \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let digits = account.phone.filter(\.isNumber)
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else {
            return .result(dialog: "\(account.name) doesn't have a telephone number.")
        }
        await UIApplication.shared.open(url)
        return .result(dialog: "Calling \(account.name).")
    }
}

struct StartFireVaultTripLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Start FireVault Trip Log"
    static var description = IntentDescription("Starts today’s FireVault Trip Log.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let breadcrumbs = FireVaultBreadcrumbStore.shared
        if breadcrumbs.isRecording {
            return .result(dialog: "Trip Log is already recording.")
        }
        let store = FireVaultStore()
        if breadcrumbs.activeDay?.isPaused == true {
            breadcrumbs.resumeWorkday(accounts: store.accounts)
            return .result(dialog: "Trip Log resumed.")
        }
        breadcrumbs.startWorkday(accounts: store.accounts)
        return .result(dialog: "Trip Log started.")
    }
}

struct PauseFireVaultTripLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause FireVault Trip Log"
    static var description = IntentDescription("Pauses the active FireVault Trip Log.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let breadcrumbs = FireVaultBreadcrumbStore.shared
        guard breadcrumbs.activeDay != nil else {
            return .result(dialog: "There is no active Trip Log to pause.")
        }
        guard breadcrumbs.activeDay?.isPaused == false else {
            return .result(dialog: "Trip Log is already paused.")
        }
        breadcrumbs.pauseWorkday()
        return .result(dialog: "Trip Log paused.")
    }
}

struct ResumeFireVaultTripLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume FireVault Trip Log"
    static var description = IntentDescription("Resumes the paused FireVault Trip Log.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let breadcrumbs = FireVaultBreadcrumbStore.shared
        guard breadcrumbs.activeDay != nil else {
            return .result(dialog: "There is no paused Trip Log to resume.")
        }
        guard breadcrumbs.activeDay?.isPaused == true else {
            return .result(dialog: "Trip Log is already recording.")
        }
        let store = FireVaultStore()
        breadcrumbs.resumeWorkday(accounts: store.accounts)
        return .result(dialog: "Trip Log resumed.")
    }
}

struct FireVaultTripLogStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "FireVault Trip Log Status"
    static var description = IntentDescription("Reports the status of today’s FireVault Trip Log.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let breadcrumbs = FireVaultBreadcrumbStore.shared
        guard let day = breadcrumbs.activeDay ?? breadcrumbs.today else {
            return .result(dialog: "There is no Trip Log for today.")
        }
        let state = day.isActive ? (day.isPaused ? "paused" : "recording") : "complete"
        let miles = day.totalDistanceMeters / 1_609.344
        let stops = day.stops.count == 1 ? "1 stop" : "\(day.stops.count) stops"
        return .result(
            dialog: "Trip Log is \(state), with \(String(format: "%.1f", miles)) miles and \(stops)."
        )
    }
}

struct EndFireVaultTripLogIntent: AppIntent {
    static var title: LocalizedStringResource = "End FireVault Trip Log"
    static var description = IntentDescription("Finishes and saves the active FireVault Trip Log.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let breadcrumbs = FireVaultBreadcrumbStore.shared
        guard let day = breadcrumbs.activeDay else {
            return .result(dialog: "There is no active Trip Log to end.")
        }
        let miles = day.totalDistanceMeters / 1_609.344
        let stopCount = day.stops.count
        breadcrumbs.endWorkday()
        let stops = stopCount == 1 ? "1 stop" : "\(stopCount) stops"
        return .result(
            dialog: "Trip Log ended and saved with \(String(format: "%.1f", miles)) miles and \(stops)."
        )
    }
}

struct FireVaultAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindFireVaultAccountIntent(),
            phrases: [
                "Find \(\.$account) in \(.applicationName)",
                "Look up \(\.$account) with \(.applicationName)"
            ],
            shortTitle: "Find Account",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: FindNearestFireVaultAccountIntent(),
            phrases: [
                "Find my nearest account in \(.applicationName)",
                "What's my nearest \(.applicationName) account"
            ],
            shortTitle: "Nearest Account",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: RouteToFireVaultAccountIntent(),
            phrases: [
                "Route to \(\.$account) with \(.applicationName)",
                "Drive to \(\.$account) using \(.applicationName)"
            ],
            shortTitle: "Route to Account",
            systemImageName: "arrow.triangle.turn.up.right.diamond.fill"
        )
        AppShortcut(
            intent: CallFireVaultAccountIntent(),
            phrases: [
                "Call \(\.$account) with \(.applicationName)"
            ],
            shortTitle: "Call Account",
            systemImageName: "phone.fill"
        )
        AppShortcut(
            intent: StartFireVaultTripLogIntent(),
            phrases: [
                "Start Trip Log in \(.applicationName)",
                "Start my \(.applicationName) Trip Log"
            ],
            shortTitle: "Start Trip Log",
            systemImageName: "record.circle.fill"
        )
        AppShortcut(
            intent: PauseFireVaultTripLogIntent(),
            phrases: [
                "Pause Trip Log in \(.applicationName)"
            ],
            shortTitle: "Pause Trip Log",
            systemImageName: "pause.circle.fill"
        )
        AppShortcut(
            intent: ResumeFireVaultTripLogIntent(),
            phrases: [
                "Resume Trip Log in \(.applicationName)"
            ],
            shortTitle: "Resume Trip Log",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: FireVaultTripLogStatusIntent(),
            phrases: [
                "Check Trip Log in \(.applicationName)"
            ],
            shortTitle: "Trip Log Status",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
        AppShortcut(
            intent: EndFireVaultTripLogIntent(),
            phrases: [
                "End Trip Log in \(.applicationName)"
            ],
            shortTitle: "End Trip Log",
            systemImageName: "stop.circle.fill"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .red
}

private enum FireVaultSiriAccountData {
    @MainActor
    static func allEntities() -> [FireVaultAccountEntity] {
        let store = FireVaultStore()
        if store.demoMode {
            FireVaultDemoShowroom.installAccountsIfNeeded(into: store)
            store.reloadAccounts()
        }
        return store.accounts
            .map(FireVaultAccountEntity.init(account:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor
    static func matchingEntities(_ value: String) -> [FireVaultAccountEntity] {
        let query = normalized(value)
        guard !query.isEmpty else { return Array(allEntities().prefix(10)) }

        return allEntities()
            .filter { entity in
                [entity.name, entity.accountID, entity.address, entity.category]
                    .map(normalized)
                    .contains { $0.contains(query) }
            }
            .sorted { lhs, rhs in
                matchRank(lhs, query: query) < matchRank(rhs, query: query)
            }
    }

    nonisolated static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchRank(_ entity: FireVaultAccountEntity, query: String) -> Int {
        let accountID = normalized(entity.accountID)
        let name = normalized(entity.name)
        if accountID == query { return 0 }
        if name == query { return 1 }
        if name.hasPrefix(query) { return 2 }
        if accountID.hasPrefix(query) { return 3 }
        return 4
    }
}

enum FireVaultSiriLocationCache {
    nonisolated private static let latitudeKey = "firevault.siri.lastLatitude"
    nonisolated private static let longitudeKey = "firevault.siri.lastLongitude"
    nonisolated private static let timestampKey = "firevault.siri.lastLocationTimestamp"
    nonisolated private static let maximumAge: TimeInterval = 30 * 60

    nonisolated static func store(_ location: CLLocation) {
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: latitudeKey)
        defaults.set(location.coordinate.longitude, forKey: longitudeKey)
        defaults.set(location.timestamp.timeIntervalSince1970, forKey: timestampKey)
    }

    nonisolated static var recentLocation: CLLocation? {
        let defaults = UserDefaults.standard
        let timestamp = defaults.double(forKey: timestampKey)
        guard timestamp > 0, Date().timeIntervalSince1970 - timestamp <= maximumAge else { return nil }
        let latitude = defaults.double(forKey: latitudeKey)
        let longitude = defaults.double(forKey: longitudeKey)
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        return CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
    }
}
