//
//  FireVaultCarPlaySceneDelegate.swift
//  FireVault
//
//  A restrained, native Driving Task experience for FireVault Pro.
//

import CarPlay
import Combine
import CoreLocation
import MapKit
import UIKit

@MainActor
final class FireVaultCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private weak var interfaceController: CPInterfaceController?
    private let store = FireVaultStore()
    private let settings = FireVaultNativeSettingsStore()
    // Share the live Trip Log owner with the handset scene. Demo Mode keeps a
    // separate deterministic archive so CarPlay can never write demo activity
    // into the technician's live history.
    private lazy var breadcrumbs: FireVaultBreadcrumbStore = store.demoMode
        ? FireVaultDemoShowroom.makeBreadcrumbStore()
        : FireVaultBreadcrumbStore.shared
    private let locationService = FireVaultLocationService()

    private var nearbyTemplate: CPListTemplate?
    private var favoritesTemplate: CPListTemplate?
    private var recentsTemplate: CPListTemplate?
    private var tripLogTemplate: CPInformationTemplate?
    private var rootTabTemplate: CPTabBarTemplate?
    private var liveRefreshTask: Task<Void, Never>?
    private var locationObservation: AnyCancellable?
    private var tripLogLocationObservation: AnyCancellable?
    private var tripLogRecordingObservation: AnyCancellable?
    private var announcedArrivalAccountID: String?
    private var speedReferenceLocation: CLLocation?
    private var lastMeaningfulMovementAt: Date?

    private let demoLocation = CLLocation(latitude: 43.6150, longitude: -116.2023)
    private let recentAccountIDsKey = "firevault.carplay.recentAccountIDs"

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        if store.demoMode {
            FireVaultDemoShowroom.installAccountsIfNeeded(into: store)
        }
        breadcrumbs.restoreActiveWorkday(accounts: store.accounts)
        synchronizeLocationOwnership()
        observeLiveLocation()

        interfaceController.setRootTemplate(makeRootTemplate(), animated: false, completion: nil)
        beginLiveRefresh()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        liveRefreshTask?.cancel()
        liveRefreshTask = nil
        locationObservation?.cancel()
        locationObservation = nil
        tripLogLocationObservation?.cancel()
        tripLogLocationObservation = nil
        tripLogRecordingObservation?.cancel()
        tripLogRecordingObservation = nil
        locationService.stopLiveNearbyUpdates()
        nearbyTemplate = nil
        favoritesTemplate = nil
        recentsTemplate = nil
        tripLogTemplate = nil
        rootTabTemplate = nil
        announcedArrivalAccountID = nil
        speedReferenceLocation = nil
        lastMeaningfulMovementAt = nil
        self.interfaceController = nil
    }

    // MARK: - Native CarPlay tab workspace

    private func makeRootTemplate() -> CPTabBarTemplate {
        let nearby = makeNearbyTemplate()
        configureTab(nearby, title: "Nearby", symbol: "location.fill", color: .systemBlue)
        nearbyTemplate = nearby

        let tripLog = makeTripLogTemplate()
        configureTab(
            tripLog,
            title: "Trip Log",
            symbol: breadcrumbs.isRecording ? "record.circle.fill" : "gauge.with.dots.needle.50percent",
            color: breadcrumbs.isRecording ? .systemRed : .systemTeal
        )
        tripLogTemplate = tripLog

        let favorites = makeFavoritesTemplate()
        configureTab(favorites, title: "Favorites", symbol: "star.fill", color: .systemYellow)
        favoritesTemplate = favorites

        let recents = makeRecentsTemplate()
        configureTab(recents, title: "Recent", symbol: "clock.arrow.circlepath", color: .systemPurple)
        recentsTemplate = recents

        let tabs = CPTabBarTemplate(templates: [nearby, tripLog, favorites, recents])
        rootTabTemplate = tabs
        return tabs
    }

    private func configureTab(
        _ template: CPTemplate,
        title: String,
        symbol: String,
        color: UIColor
    ) {
        template.tabTitle = title
        template.tabImage = requiredCarPlayIcon(symbol, color: color)
    }

    // MARK: - Nearby and Favorites

    private func makeNearbyTemplate() -> CPListTemplate {
        CPListTemplate(
            title: "Nearby",
            sections: makeNearbySections()
        )
    }

    private func makeNearbySections() -> [CPListSection] {
        let accounts = Array(sortedMappedAccounts(favoritesOnly: false).prefix(6))
        guard !accounts.isEmpty else {
            return [CPListSection(items: [emptyAccountItem(
                title: "No mapped accounts",
                detail: "Add account coordinates in FireVault."
            )])]
        }
        let items = accounts.enumerated().map { index, account in
            let accountID = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
            let identifier = accountID.isEmpty ? "No account ID" : "#\(accountID)"
            let miles = effectiveLocation.map {
                String(format: "%.1f mi", self.distance(from: $0, to: account) / 1_609.344)
            } ?? "Distance unavailable"
            let item = CPListItem(
                text: account.name,
                detailText: "\(identifier) • \(miles)",
                image: carPlayIcon(
                    index == 0 ? "location.circle.fill" : "building.2.fill",
                    color: index == 0 ? .systemBlue : .secondaryLabel
                ),
                accessoryImage: nil,
                accessoryType: .disclosureIndicator
            )
            item.handler = { [weak self] _, completion in
                self?.showAccount(account)
                completion()
            }
            return item
        }
        return [CPListSection(items: items, header: "Closest accounts", sectionIndexTitle: nil)]
    }

    private func makeFavoritesTemplate() -> CPListTemplate {
        CPListTemplate(title: "Favorites", sections: makeFavoriteSections())
    }

    private func makeFavoriteSections() -> [CPListSection] {
        let accounts = Array(sortedMappedAccounts(favoritesOnly: true).prefix(4))
        guard !accounts.isEmpty else {
            return [CPListSection(items: [emptyAccountItem(
                title: "No favorite accounts",
                detail: "Mark favorites in FireVault on iPhone."
            )])]
        }
        return [CPListSection(items: accounts.enumerated().map { index, account in
            makeAccountItem(account, isNearest: index == 0)
        })]
    }

    private func makeRecentsTemplate() -> CPListTemplate {
        CPListTemplate(title: "Recent", sections: makeRecentSections())
    }

    private func makeRecentSections() -> [CPListSection] {
        let accounts = Array(recentAccounts.prefix(4))
        guard !accounts.isEmpty else {
            return [CPListSection(items: [emptyAccountItem(
                title: "No recent sites",
                detail: "Open a site from Nearby or Favorites."
            )])]
        }
        return [CPListSection(items: accounts.map { account in
            makeAccountItem(account, isNearest: false)
        })]
    }

    private func makeAccountItem(
        _ account: FireVaultWorkspaceAccount,
        isNearest: Bool
    ) -> CPListItem {
        let arriving = effectiveLocation.map { distance(from: $0, to: account) <= 402.336 } ?? false
        let detail: String
        if arriving {
            detail = "Arriving • \(accountDetailText(account))"
        } else if isNearest {
            detail = "Nearest • \(accountDetailText(account))"
        } else {
            detail = accountDetailText(account)
        }
        let item = CPListItem(
            text: account.name,
            detailText: detail,
            image: carPlayIcon(
                arriving ? "mappin.circle.fill" : (isNearest ? "location.fill" : "building.2.fill"),
                color: arriving ? .systemRed : (isNearest ? .systemBlue : .secondaryLabel)
            ),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        item.handler = { [weak self] _, completion in
            self?.showAccount(account)
            completion()
        }
        return item
    }

    private func emptyAccountItem(title: String, detail: String) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail)
        item.isEnabled = false
        return item
    }

    // MARK: - Site actions

    private func showAccount(_ account: FireVaultWorkspaceAccount) {
        rememberRecentAccount(account)
        let actions = makeAccountActions(account)
        let template = CPListTemplate(
            title: "Account",
            sections: [CPListSection(items: actions, header: account.name, sectionIndexTitle: nil)]
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func makeAccountActions(_ account: FireVaultWorkspaceAccount) -> [CPListItem] {
        var items: [CPListItem] = []

        if let coordinate = account.coordinate {
            items.append(actionItem(
                title: "Directions",
                detail: account.address,
                symbol: "arrow.triangle.turn.up.right.diamond.fill",
                color: .systemBlue
            ) { [weak self] in
                self?.openDrivingDirections(to: coordinate, name: account.name)
            })
        }

        if account.phone.contains(where: \.isNumber) {
            items.append(actionItem(
                title: "Call",
                detail: formattedPhone(account.phone),
                symbol: "phone.fill",
                color: .systemGreen
            ) { [weak self] in
                self?.store.call(account.phone)
            })
        }

        if let parking = arrivalLocation(in: account, matching: ["parking", "park here"]),
           let coordinate = parking.coordinate {
            items.append(actionItem(
                title: "Parking",
                detail: parking.label,
                symbol: "parkingsign.circle.fill",
                color: .systemOrange
            ) { [weak self] in
                self?.openDrivingDirections(to: coordinate, name: "\(account.name) Parking")
            })
        }

        return Array(items.prefix(4))
    }

    private func actionItem(
        title: String,
        detail: String,
        symbol: String,
        color: UIColor,
        action: @escaping @MainActor () -> Void
    ) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail, image: carPlayIcon(symbol, color: color))
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    private func arrivalLocation(
        in account: FireVaultWorkspaceAccount,
        matching terms: [String]
    ) -> FireVaultWorkspaceLocation? {
        account.locations.first { location in
            guard location.coordinate != nil else { return false }
            let searchable = "\(location.label) \(location.type)".lowercased()
            return terms.contains { searchable.contains($0) }
        }
    }

    private func showArrivalPoints(for account: FireVaultWorkspaceAccount) {
        let items = arrivalPoints(in: account).prefix(6).map { location in
            let item = CPListItem(
                text: location.label,
                detailText: displayLocationType(location.type),
                image: carPlayIcon(
                    arrivalSymbol(for: location),
                    color: arrivalColor(for: location)
                ),
                accessoryImage: nil,
                accessoryType: .disclosureIndicator
            )
            item.handler = { [weak self] _, completion in
                if let coordinate = location.coordinate {
                    self?.openDrivingDirections(
                        to: coordinate,
                        name: "\(account.name) • \(location.label)"
                    )
                }
                completion()
            }
            return item
        }

        guard !items.isEmpty else { return }
        let template = CPListTemplate(
            title: "Arrival",
            sections: [CPListSection(
                items: Array(items),
                header: account.name,
                sectionIndexTitle: nil
            )]
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func arrivalPoints(in account: FireVaultWorkspaceAccount) -> [FireVaultWorkspaceLocation] {
        account.locations
            .filter { $0.coordinate != nil }
            .sorted { arrivalPriority(for: $0) < arrivalPriority(for: $1) }
    }

    private func arrivalPriority(for location: FireVaultWorkspaceLocation) -> Int {
        let value = "\(location.label) \(location.type)".lowercased()
        if value.contains("parking") || value.contains("park here") { return 0 }
        if value.contains("front entrance") || value.contains("main entrance") { return 1 }
        if value.contains("entrance") || value.contains("door") { return 2 }
        if value.contains("panel") { return 3 }
        if value.contains("riser") { return 4 }
        return 5
    }

    private func arrivalSymbol(for location: FireVaultWorkspaceLocation) -> String {
        switch arrivalPriority(for: location) {
        case 0: return "parkingsign.circle.fill"
        case 1, 2: return "door.left.hand.open"
        case 3: return "rectangle.connected.to.line.below"
        case 4: return "drop.triangle.fill"
        default: return "mappin.circle.fill"
        }
    }

    private func arrivalColor(for location: FireVaultWorkspaceLocation) -> UIColor {
        switch arrivalPriority(for: location) {
        case 0: return .systemRed
        case 1, 2: return .systemGreen
        case 3: return .systemBlue
        case 4: return .systemTeal
        default: return .systemOrange
        }
    }

    private func checkForArrival() {
        guard let location = effectiveLocation,
              let account = sortedMappedAccounts(favoritesOnly: false).first else {
            announcedArrivalAccountID = nil
            return
        }

        let distanceMeters = distance(from: location, to: account)
        if distanceMeters > 804.672 {
            announcedArrivalAccountID = nil
            return
        }

        guard distanceMeters <= 402.336,
              announcedArrivalAccountID != account.id,
              !arrivalPoints(in: account).isEmpty,
              let interfaceController else { return }

        announcedArrivalAccountID = account.id
        let viewPoints = CPAlertAction(title: "View", style: .default) { [weak self] _ in
            self?.dismissArrivalPrompt {
                self?.showArrivalPoints(for: account)
            }
        }
        let dismiss = CPAlertAction(title: "Later", style: .cancel) { [weak self] _ in
            self?.dismissArrivalPrompt()
        }
        interfaceController.presentTemplate(
            CPAlertTemplate(
                titleVariants: ["Arrival points available"],
                actions: [viewPoints, dismiss]
            ),
            animated: true,
            completion: nil
        )
    }

    private func dismissArrivalPrompt(then action: (@MainActor () -> Void)? = nil) {
        guard let interfaceController else {
            action?()
            return
        }
        interfaceController.dismissTemplate(animated: true) { success, _ in
            guard success else { return }
            action?()
        }
    }

    private func displayLocationType(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "POI"
            ? "POI"
            : value
    }

    private func openDrivingDirections(to coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: - Trip Log dashboard

    private func makeTripLogTemplate() -> CPInformationTemplate {
        let template = CPInformationTemplate(
            // The persistent Trip Log tab already names this screen. An empty
            // template title recovers a full row on compact CarPlay displays
            // so all dashboard details remain visible without scrolling.
            title: "",
            layout: .leading,
            items: makeTripLogInformationItems(),
            actions: makeTripLogActions()
        )
        template.trailingNavigationBarButtons = [
            CPBarButton(
                title: "GPS",
                handler: { [weak self] _ in self?.showGPSDiagnostics() }
            )
        ]
        return template
    }

    private func makeTripLogInformationItems() -> [CPInformationItem] {
        let location = effectiveLocation
        let day = breadcrumbs.activeDay ?? breadcrumbs.today

        let speed = store.demoMode ? "64 mph" : currentSpeedText(location)
        let elevation = store.demoMode ? "5,284 ft" : currentElevationText(location, day: day)
        let trip = store.demoMode ? "42.6 mi" : distanceText(day)
        let stops = store.demoMode ? "2 stops" : stopSummaryText(day)
        let time = store.demoMode ? "00:48:17" : elapsedText(day?.elapsedTime ?? 0)
        let accuracy = store.demoMode ? "±10 ft" : currentGPSAccuracyText(location)

        return [
            CPInformationItem(title: tripLogStatus.uppercased(), detail: tripLogStatusDetail),
            CPInformationItem(title: "SPEED  \(speed)", detail: "ELEVATION  \(elevation)"),
            CPInformationItem(title: "TRIP  \(trip)", detail: "STOPS  \(stops)"),
            CPInformationItem(title: "TIME  \(time)", detail: "GPS ACCURACY  \(accuracy)")
        ]
    }

    private var tripLogStatusDetail: String {
        guard let day = breadcrumbs.activeDay ?? breadcrumbs.today else {
            return "Ready to record today’s route"
        }
        if day.isPaused { return "Recording paused" }
        if breadcrumbs.isRecording { return "Recording route and stops" }
        return day.endedAt == nil ? "Ready to resume" : "Today’s Trip Log is complete"
    }

    private func makeTripLogActions() -> [CPTextButton] {
        if breadcrumbs.activeDay == nil {
            return [CPTextButton(title: "Start", textStyle: .confirm) { [weak self] _ in
                guard let self else { return }
                breadcrumbs.startWorkday(accounts: store.accounts)
                refreshCarPlayState()
            }]
        }

        if breadcrumbs.activeDay?.isPaused == true {
            return [
                CPTextButton(title: "Resume", textStyle: .confirm) { [weak self] _ in
                    guard let self else { return }
                    breadcrumbs.resumeWorkday(accounts: store.accounts)
                    refreshCarPlayState()
                },
                CPTextButton(title: "End", textStyle: .cancel) { [weak self] _ in
                    self?.confirmEndTripLog()
                }
            ]
        }

        return [
            CPTextButton(title: "Pause", textStyle: .normal) { [weak self] _ in
                guard let self else { return }
                breadcrumbs.pauseWorkday()
                refreshCarPlayState()
            },
            CPTextButton(title: "End", textStyle: .cancel) { [weak self] _ in
                self?.confirmEndTripLog()
            }
        ]
    }

    private func showGPSDiagnostics() {
        let template = CPInformationTemplate(
            title: "GPS Diagnostics",
            layout: .leading,
            items: makeGPSDiagnosticItems(),
            actions: []
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func makeGPSDiagnosticItems() -> [CPInformationItem] {
        let location = effectiveLocation
        let source = breadcrumbs.isRecording ? "Trip Log recorder" : "Live nearby service"
        let horizontal = location.map(currentGPSAccuracyText) ?? "No fix"
        let vertical: String
        if let location, location.verticalAccuracy >= 0 {
            vertical = "±\(Int((location.verticalAccuracy * 3.280_84).rounded())) ft"
        } else {
            vertical = "Unavailable"
        }
        let age: String
        if let location {
            age = "\(max(0, Int(Date().timeIntervalSince(location.timestamp).rounded()))) sec"
        } else {
            age = "No location"
        }

        return [
            CPInformationItem(title: "LOCATION ACCESS", detail: locationAuthorizationText),
            CPInformationItem(title: "SOURCE", detail: source),
            CPInformationItem(title: "HORIZONTAL", detail: horizontal),
            CPInformationItem(title: "VERTICAL", detail: vertical),
            CPInformationItem(title: "LAST UPDATE", detail: age),
            CPInformationItem(title: "TRACKING", detail: breadcrumbs.isRecording ? "Recording" : "Standby")
        ]
    }

    private var locationAuthorizationText: String {
        switch breadcrumbs.isRecording
            ? breadcrumbs.authorizationStatus
            : locationService.authorizationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not Requested"
        @unknown default: "Unknown"
        }
    }

    private func confirmEndTripLog() {
        guard let interfaceController else { return }
        let end = CPAlertAction(title: "End Trip Log", style: .destructive) { [weak self] _ in
            self?.endTripLogAndReturnHome()
        }
        let cancel = CPAlertAction(title: "Keep Recording", style: .cancel) { [weak self] _ in
            self?.dismissTripLogConfirmation()
        }
        interfaceController.presentTemplate(
            CPAlertTemplate(titleVariants: ["End today’s Trip Log?"], actions: [end, cancel]),
            animated: true,
            completion: nil
        )
    }

    private func endTripLogAndReturnHome() {
        breadcrumbs.endWorkday()
        refreshCarPlayState()

        guard let interfaceController else { return }
        interfaceController.dismissTemplate(animated: true, completion: nil)
    }

    private func dismissTripLogConfirmation() {
        interfaceController?.dismissTemplate(animated: true, completion: nil)
    }

    // MARK: - Live refresh

    private func observeLiveLocation() {
        locationObservation?.cancel()
        locationObservation = locationService.$latestLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                Task { @MainActor [weak self] in
                    self?.updateMotionEvidence(with: location)
                    self?.refreshCarPlayState()
                }
            }
        tripLogLocationObservation?.cancel()
        tripLogLocationObservation = breadcrumbs.$latestLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                Task { @MainActor [weak self] in
                    self?.updateMotionEvidence(with: location)
                    self?.refreshCarPlayState()
                }
            }
        tripLogRecordingObservation?.cancel()
        tripLogRecordingObservation = breadcrumbs.$isRecording
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.synchronizeLocationOwnership()
                    self?.refreshCarPlayState()
                }
            }
    }

    private func synchronizeLocationOwnership() {
        if breadcrumbs.isRecording {
            locationService.stopLiveNearbyUpdates()
        } else {
            locationService.startLiveNearbyUpdates(highAccuracy: settings.gps.highAccuracy)
        }
    }

    private func beginLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                self?.refreshCarPlayState()
            }
        }
    }

    private func refreshCarPlayState() {
        nearbyTemplate?.updateSections(makeNearbySections())
        favoritesTemplate?.updateSections(makeFavoriteSections())
        recentsTemplate?.updateSections(makeRecentSections())
        tripLogTemplate?.items = makeTripLogInformationItems()
        tripLogTemplate?.actions = makeTripLogActions()
        tripLogTemplate?.tabImage = requiredCarPlayIcon(
            breadcrumbs.isRecording ? "record.circle.fill" : "gauge.with.dots.needle.50percent",
            color: breadcrumbs.isRecording ? .systemRed : .systemTeal
        )
        tripLogTemplate?.showsTabBadge = breadcrumbs.isRecording
        checkForArrival()
    }

    // MARK: - Data helpers

    private var effectiveLocation: CLLocation? {
        if store.demoMode { return demoLocation }
        return breadcrumbs.isRecording
            ? (breadcrumbs.latestLocation ?? locationService.latestLocation)
            : (locationService.latestLocation ?? breadcrumbs.latestLocation)
    }

    private func sortedMappedAccounts(favoritesOnly: Bool) -> [FireVaultWorkspaceAccount] {
        let location = effectiveLocation
        return store.accounts
            .filter { $0.coordinate != nil && (!favoritesOnly || $0.favorite) }
            .sorted { lhs, rhs in
                guard let location else {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return distance(from: location, to: lhs) < distance(from: location, to: rhs)
            }
    }

    private func accountDetailText(_ account: FireVaultWorkspaceAccount) -> String {
        var details: [String] = []
        let accountID = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        details.append(accountID.isEmpty ? account.category : "#\(accountID)")
        if let location = effectiveLocation {
            let miles = distance(from: location, to: account) / 1_609.344
            details.append(String(format: "%.1f mi", miles))
        }
        return details.joined(separator: " • ")
    }

    private func distance(from location: CLLocation, to account: FireVaultWorkspaceAccount) -> CLLocationDistance {
        guard let coordinate = account.coordinate else { return .greatestFiniteMagnitude }
        return location.distance(from: CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ))
    }

    private func formattedPhone(_ value: String) -> String {
        let digits = value.filter(\.isNumber)
        guard digits.count == 10 else { return value }
        let area = digits.prefix(3)
        let exchange = digits.dropFirst(3).prefix(3)
        let line = digits.suffix(4)
        return "(\(area)) \(exchange)-\(line)"
    }

    private var tripLogStatus: String {
        if breadcrumbs.activeDay?.stops.contains(where: { $0.departure == nil }) == true {
            return "On Site"
        }
        if breadcrumbs.isRecording { return "Recording" }
        if breadcrumbs.activeDay?.isPaused == true { return "Paused" }
        if breadcrumbs.activeDay == nil { return "Ready" }
        return "Complete"
    }

    private var recentAccounts: [FireVaultWorkspaceAccount] {
        let ids = UserDefaults.standard.stringArray(forKey: recentAccountIDsKey) ?? []
        let accountsByID = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, $0) })
        return ids.compactMap { accountsByID[$0] }
    }

    private func rememberRecentAccount(_ account: FireVaultWorkspaceAccount) {
        var ids = UserDefaults.standard.stringArray(forKey: recentAccountIDsKey) ?? []
        ids.removeAll { $0 == account.id }
        ids.insert(account.id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(8)), forKey: recentAccountIDsKey)
        recentsTemplate?.updateSections(makeRecentSections())
    }

    private func currentSpeedText(_ location: CLLocation?) -> String {
        guard let speed = FireVaultBreadcrumbRules.resolvedLiveSpeed(
            location: location,
            lastMeaningfulMovementAt: lastMeaningfulMovementAt
        ) else { return "— mph" }
        return "\(Int((speed * 2.236_936).rounded())) mph"
    }

    private func updateMotionEvidence(with location: CLLocation) {
        guard let reference = speedReferenceLocation else {
            speedReferenceLocation = location
            lastMeaningfulMovementAt = location.timestamp
            return
        }

        let interval = location.timestamp.timeIntervalSince(reference.timestamp)
        guard interval > 0 else { return }
        let distance = location.distance(from: reference)
        let derivedSpeed = distance / interval
        if distance >= FireVaultBreadcrumbRules.minimumPointDistance
            && derivedSpeed > FireVaultBreadcrumbRules.maximumDerivedStationarySpeed {
            lastMeaningfulMovementAt = location.timestamp
            speedReferenceLocation = location
        } else if interval >= FireVaultBreadcrumbRules.maximumLiveSpeedAge {
            // Advance the comparison window without claiming movement. This
            // prevents accumulated GPS drift from reviving a stale MPH value.
            speedReferenceLocation = location
        }
    }

    private func currentElevationText(_ location: CLLocation?, day: FireVaultBreadcrumbDay?) -> String {
        let meters: Double?
        if let location, location.verticalAccuracy >= 0 {
            meters = location.altitude
        } else {
            meters = day?.points.compactMap(\.altitude).last
        }
        guard let meters else { return "Unavailable" }
        return "\(Int((meters * 3.280_84).rounded()).formatted()) ft"
    }

    private func currentGPSAccuracyText(_ location: CLLocation?) -> String {
        guard let location, location.horizontalAccuracy >= 0 else { return "Unavailable" }
        let feet = max(1, Int((location.horizontalAccuracy * 3.280_84).rounded()))
        return "±\(feet.formatted()) ft • \(gpsQuality(for: feet))"
    }

    private func gpsQuality(for accuracyFeet: Int) -> String {
        switch accuracyFeet {
        case ...20: "Excellent"
        case ...50: "Good"
        case ...100: "Fair"
        default: "Weak"
        }
    }

    private func distanceText(_ day: FireVaultBreadcrumbDay?) -> String {
        guard let day else { return "0.0 mi" }
        return String(format: "%.1f mi", day.totalDistanceMeters / 1_609.344)
    }

    private func stopCountText(_ day: FireVaultBreadcrumbDay?) -> String {
        let count = day?.stops.count ?? 0
        return count == 1 ? "1 stop" : "\(count) stops"
    }

    private func stopSummaryText(_ day: FireVaultBreadcrumbDay?) -> String {
        guard let day,
              let activeStop = day.stops.last(where: { $0.departure == nil }) else {
            return stopCountText(day)
        }
        return "\(stopCountText(day)) • \(compactDuration(activeStop.duration)) onsite"
    }

    private func compactDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let minutes = seconds / 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private func elapsedText(_ elapsedTime: TimeInterval) -> String {
        let seconds = max(0, Int(elapsedTime.rounded()))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3_600,
            (seconds % 3_600) / 60,
            seconds % 60
        )
    }

    private func carPlayIcon(_ systemName: String, color: UIColor) -> UIImage? {
        UIImage(systemName: systemName)?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    private func requiredCarPlayIcon(_ systemName: String, color: UIColor) -> UIImage {
        carPlayIcon(systemName, color: color)
            ?? UIImage(systemName: "circle.fill")!
                .withTintColor(color, renderingMode: .alwaysOriginal)
    }

}
