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
    private var homeTemplate: CPListTemplate?
    private var liveRefreshTask: Task<Void, Never>?
    private var locationObservation: AnyCancellable?
    private var announcedArrivalAccountID: String?

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
        locationService.startLiveNearbyUpdates(highAccuracy: settings.gps.highAccuracy)
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
        locationService.stopLiveNearbyUpdates()
        nearbyTemplate = nil
        favoritesTemplate = nil
        recentsTemplate = nil
        tripLogTemplate = nil
        homeTemplate = nil
        announcedArrivalAccountID = nil
        self.interfaceController = nil
    }

    // MARK: - Compact CarPlay home

    private func makeRootTemplate() -> CPListTemplate {
        let nearby = makeNearbyTemplate()
        nearbyTemplate = nearby

        let tripLog = makeTripLogTemplate()
        tripLogTemplate = tripLog

        let favorites = makeFavoritesTemplate()
        favoritesTemplate = favorites

        let recents = makeRecentsTemplate()
        recentsTemplate = recents

        let home = CPListTemplate(title: "FireVault", sections: makeHomeSections())
        homeTemplate = home
        return home
    }

    private func makeHomeSections() -> [CPListSection] {
        let nearby = CPListItem(
            text: "Nearby Accounts",
            detailText: nearestAccountSummary,
            image: carPlayIcon("mappin.and.ellipse", color: .systemBlue),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        nearby.handler = { [weak self] _, completion in
            guard let self, let template = nearbyTemplate else {
                completion()
                return
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
            completion()
        }

        let tripLog = CPListItem(
            text: "Trip Log",
            detailText: tripLogHomeSummary,
            image: carPlayIcon(
                breadcrumbs.isRecording ? "record.circle.fill" : "point.3.connected.trianglepath.dotted",
                color: breadcrumbs.isRecording ? .systemRed : .systemTeal
            ),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        tripLog.handler = { [weak self] _, completion in
            guard let self, let template = tripLogTemplate else {
                completion()
                return
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
            completion()
        }

        let favorites = CPListItem(
            text: "Favorite Sites",
            detailText: favoriteAccountSummary,
            image: carPlayIcon("star.fill", color: .systemYellow),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        favorites.handler = { [weak self] _, completion in
            guard let self, let template = favoritesTemplate else {
                completion()
                return
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
            completion()
        }

        let recents = CPListItem(
            text: "Recent Sites",
            detailText: recentAccountSummary,
            image: carPlayIcon("clock.arrow.circlepath", color: .systemPurple),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        recents.handler = { [weak self] _, completion in
            guard let self, let template = recentsTemplate else {
                completion()
                return
            }
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
            completion()
        }

        let items = breadcrumbs.isRecording
            ? [tripLog, nearby, favorites, recents]
            : [nearby, tripLog, favorites, recents]
        return [CPListSection(items: items)]
    }

    // MARK: - Nearby and Favorites

    private func makeNearbyTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Nearby", sections: makeNearbySections())
        template.emptyViewTitleVariants = ["No Nearby Accounts"]
        template.emptyViewSubtitleVariants = ["Map account addresses in FireVault on iPhone."]
        return template
    }

    private func makeNearbySections() -> [CPListSection] {
        let accounts = Array(sortedMappedAccounts(favoritesOnly: false).prefix(4))
        guard !accounts.isEmpty else {
            return [CPListSection(items: [emptyAccountItem(
                title: "No mapped accounts",
                detail: "Add account coordinates in FireVault."
            )])]
        }
        return [CPListSection(items: accounts.enumerated().map { index, account in
            makeAccountItem(account, isNearest: index == 0)
        })]
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
        CPListTemplate(title: "Recent Sites", sections: makeRecentSections())
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
            title: "Site Actions",
            sections: [CPListSection(items: actions, header: account.name, sectionIndexTitle: nil)]
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func makeAccountActions(_ account: FireVaultWorkspaceAccount) -> [CPListItem] {
        var items: [CPListItem] = []

        if let coordinate = account.coordinate {
            items.append(actionItem(
                title: "Route to Account",
                detail: account.address,
                symbol: "arrow.triangle.turn.up.right.diamond.fill",
                color: .systemBlue
            ) { [weak self] in
                self?.openDrivingDirections(to: coordinate, name: account.name)
            })
        }

        if account.phone.contains(where: \.isNumber) {
            items.append(actionItem(
                title: "Call Site",
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
                title: "Route to Parking",
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
            title: "Arrival Points",
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
        let viewPoints = CPAlertAction(title: "View Map", style: .default) { [weak self] _ in
            self?.dismissArrivalPrompt {
                self?.showArrivalPoints(for: account)
            }
        }
        let dismiss = CPAlertAction(title: "Dismiss", style: .cancel) { [weak self] _ in
            self?.dismissArrivalPrompt()
        }
        interfaceController.presentTemplate(
            CPAlertTemplate(
                titleVariants: ["Arrival Points Ready"],
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

    // MARK: - Trip Log information dashboard

    private func makeTripLogTemplate() -> CPInformationTemplate {
        CPInformationTemplate(
            title: "Trip Log",
            layout: .twoColumn,
            items: makeTripLogInformationItems(),
            actions: makeTripLogActions()
        )
    }

    private func makeTripLogInformationItems() -> [CPInformationItem] {
        let location = locationService.latestLocation
        let day = breadcrumbs.activeDay ?? breadcrumbs.today

        return [
            CPInformationItem(title: "SPEED", detail: store.demoMode ? "64 mph" : currentSpeedText(location)),
            CPInformationItem(title: "ELEVATION", detail: store.demoMode ? "5,284 ft" : currentElevationText(location, day: day)),
            CPInformationItem(title: "TRIP", detail: store.demoMode ? "42.6 mi" : distanceText(day)),
            CPInformationItem(title: "TIME", detail: store.demoMode ? "00:48:17" : elapsedText(day?.elapsedTime ?? 0)),
            CPInformationItem(title: "STOPS", detail: store.demoMode ? "2 stops" : stopSummaryText(day))
        ]
    }

    private func makeTripLogActions() -> [CPTextButton] {
        if breadcrumbs.activeDay == nil {
            return [CPTextButton(title: "Start Trip Log", textStyle: .confirm) { [weak self] _ in
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
        interfaceController.dismissTemplate(animated: true) { [weak self] _, _ in
            self?.interfaceController?.popToRootTemplate(animated: true, completion: nil)
        }
    }

    private func dismissTripLogConfirmation() {
        interfaceController?.dismissTemplate(animated: true, completion: nil)
    }

    // MARK: - Live refresh

    private func observeLiveLocation() {
        locationObservation?.cancel()
        locationObservation = locationService.$latestLocation
            .compactMap { $0 }
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshCarPlayState()
                }
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
        homeTemplate?.updateSections(makeHomeSections())
        nearbyTemplate?.updateSections(makeNearbySections())
        favoritesTemplate?.updateSections(makeFavoriteSections())
        recentsTemplate?.updateSections(makeRecentSections())
        tripLogTemplate?.items = makeTripLogInformationItems()
        tripLogTemplate?.actions = makeTripLogActions()
        checkForArrival()
    }

    // MARK: - Data helpers

    private var effectiveLocation: CLLocation? {
        store.demoMode ? demoLocation : locationService.latestLocation
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
        if let location = effectiveLocation {
            let miles = distance(from: location, to: account) / 1_609.344
            details.append(String(format: "%.1f mi", miles))
        }
        let accountID = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        details.append(accountID.isEmpty ? account.category : "#\(accountID)")
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

    private var nearestAccountSummary: String {
        guard let account = sortedMappedAccounts(favoritesOnly: false).first else {
            return "No mapped accounts"
        }
        guard let location = effectiveLocation else { return account.name }
        let miles = distance(from: location, to: account) / 1_609.344
        return "\(account.name) • \(String(format: "%.1f mi", miles))"
    }

    private var favoriteAccountSummary: String {
        let count = sortedMappedAccounts(favoritesOnly: true).count
        return count == 1 ? "1 saved site" : "\(count) saved sites"
    }

    private var recentAccountSummary: String {
        guard let account = recentAccounts.first else { return "No recent sites yet" }
        return "Last: \(account.name)"
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
        homeTemplate?.updateSections(makeHomeSections())
    }

    private var tripLogHomeSummary: String {
        let day = breadcrumbs.activeDay ?? breadcrumbs.today
        return "\(tripLogStatus) • \(distanceText(day)) • \(timeAndStopsText(day))"
    }

    private func currentSpeedText(_ location: CLLocation?) -> String {
        guard let location, location.speed >= 0 else { return "— mph" }
        return "\(Int((location.speed * 2.236_936).rounded())) mph"
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

    private func distanceText(_ day: FireVaultBreadcrumbDay?) -> String {
        guard let day else { return "0.0 mi" }
        return String(format: "%.1f mi", day.totalDistanceMeters / 1_609.344)
    }

    private func timeAndStopsText(_ day: FireVaultBreadcrumbDay?) -> String {
        guard let day else { return "00:00:00 • 0" }
        return "\(elapsedText(day.elapsedTime)) • \(day.stops.count)"
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
        return "\(stopCountText(day)) • On site \(elapsedText(activeStop.duration))"
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

}
