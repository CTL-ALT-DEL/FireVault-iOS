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
final class FireVaultCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate,
    CPPointOfInterestTemplateDelegate {
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

    private var nearbyTemplate: CPPointOfInterestTemplate?
    private var favoritesTemplate: CPListTemplate?
    private var recentsTemplate: CPListTemplate?
    private var tripLogTemplate: CPInformationTemplate?
    private var homeTemplate: CPListTemplate?
    private var liveRefreshTask: Task<Void, Never>?
    private var locationObservation: AnyCancellable?
    private var tripLogLocationObservation: AnyCancellable?
    private var tripLogRecordingObservation: AnyCancellable?
    private var announcedArrivalAccountID: String?
    private var speedReferenceLocation: CLLocation?
    private var lastMeaningfulMovementAt: Date?
    private var selectedNearbyAccountID: String?
    private var lastNearbyRefreshAt: Date?
    private var followsNearbyLocation = true
    private var ignoreNearbyRegionChangesUntil: Date?

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
        homeTemplate = nil
        announcedArrivalAccountID = nil
        speedReferenceLocation = nil
        lastMeaningfulMovementAt = nil
        selectedNearbyAccountID = nil
        lastNearbyRefreshAt = nil
        followsNearbyLocation = true
        ignoreNearbyRegionChangesUntil = nil
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

        let home = CPListTemplate(
            title: "FireVault",
            sections: makeHomeSections(),
            assistantCellConfiguration: nil,
            headerGridButtons: makeHomeGridButtons()
        )
        homeTemplate = home
        return home
    }

    private func makeHomeGridButtons() -> [CPGridButton] {
        [
            homeGridButton(title: "Nearby", symbol: "mappin.and.ellipse", color: .systemBlue) { [weak self] in
                guard let self, let template = nearbyTemplate else { return }
                interfaceController?.pushTemplate(template, animated: true, completion: nil)
            },
            homeGridButton(
                title: "Trip Log",
                symbol: breadcrumbs.isRecording ? "record.circle.fill" : "point.3.connected.trianglepath.dotted",
                color: breadcrumbs.isRecording ? .systemRed : .systemTeal
            ) { [weak self] in
                guard let self, let template = tripLogTemplate else { return }
                interfaceController?.pushTemplate(template, animated: true, completion: nil)
            },
            homeGridButton(title: "Favorites", symbol: "star.fill", color: .systemYellow) { [weak self] in
                guard let self, let template = favoritesTemplate else { return }
                interfaceController?.pushTemplate(template, animated: true, completion: nil)
            },
            homeGridButton(title: "Recent", symbol: "clock.arrow.circlepath", color: .systemPurple) { [weak self] in
                guard let self, let template = recentsTemplate else { return }
                interfaceController?.pushTemplate(template, animated: true, completion: nil)
            }
        ]
    }

    private func homeGridButton(
        title: String,
        symbol: String,
        color: UIColor,
        action: @escaping @MainActor () -> Void
    ) -> CPGridButton {
        CPGridButton(
            titleVariants: [title],
            image: requiredCarPlayIcon(symbol, color: color)
        ) { _ in
            action()
        }
    }

    private func makeHomeSections() -> [CPListSection] {
        let tripLog = CPListItem(
            text: "Trip Log • \(tripLogStatus)",
            detailText: tripLogAtAGlanceSummary,
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

        let nearest: CPListItem
        if let account = sortedMappedAccounts(favoritesOnly: false).first {
            nearest = CPListItem(
                text: account.name,
                detailText: nearestAccountAtAGlanceSummary(account),
                image: carPlayIcon("building.2.fill", color: .systemBlue),
                accessoryImage: nil,
                accessoryType: .disclosureIndicator
            )
            nearest.handler = { [weak self] _, completion in
                self?.showAccount(account)
                completion()
            }
        } else {
            nearest = emptyAccountItem(
                title: "Nearest Account",
                detail: "No mapped accounts are available."
            )
        }

        return [CPListSection(items: [tripLog, nearest], header: "At a Glance", sectionIndexTitle: nil)]
    }

    // MARK: - Nearby and Favorites

    private func makeNearbyTemplate() -> CPPointOfInterestTemplate {
        let points = makeNearbyPoints()
        let template = CPPointOfInterestTemplate(
            title: "Nearby",
            pointsOfInterest: points,
            selectedIndex: points.isEmpty ? NSNotFound : selectedNearbyIndex(in: points)
        )
        template.pointOfInterestDelegate = self
        template.trailingNavigationBarButtons = [
            CPBarButton(image: requiredCarPlayIcon("location.fill", color: .systemBlue)) { [weak self] _ in
                self?.recenterNearbyMap()
            }
        ]
        ignoreNearbyRegionChangesUntil = Date().addingTimeInterval(2)
        return template
    }

    private func makeNearbyPoints() -> [CPPointOfInterest] {
        Array(sortedMappedAccounts(favoritesOnly: false).prefix(6)).compactMap { account in
            guard let coordinate = account.coordinate else { return nil }
            let mapItem = MKMapItem(
                location: CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                address: nil
            )
            mapItem.name = account.name

            let accountID = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
            let identifier = accountID.isEmpty ? "No account ID" : "#\(accountID)"
            let distance = effectiveLocation.map {
                String(format: "%.1f mi", self.distance(from: $0, to: account) / 1_609.344)
            } ?? "Distance unavailable"
            let point = CPPointOfInterest(
                location: mapItem,
                title: account.name,
                subtitle: "\(identifier) • \(distance)",
                // Keep the Nearby list to one compact detail line. CarPlay
                // renders both subtitle and summary beneath the title, so an
                // additional summary duplicates the account information and
                // creates an unwanted third line.
                summary: nil,
                detailTitle: account.name,
                detailSubtitle: account.address,
                detailSummary: "\(distance) • \(account.category)",
                pinImage: nil,
                selectedPinImage: nil
            )
            point.userInfo = account.id as NSString
            point.primaryButton = CPTextButton(title: "Route", textStyle: .confirm) { [weak self] _ in
                self?.rememberRecentAccount(account)
                self?.openDrivingDirections(to: coordinate, name: account.name)
            }
            if !arrivalPoints(in: account).isEmpty {
                point.secondaryButton = CPTextButton(title: "Arrival", textStyle: .normal) { [weak self] _ in
                    self?.rememberRecentAccount(account)
                    self?.showArrivalPoints(for: account)
                }
            }
            return point
        }
    }

    private func selectedNearbyIndex(in points: [CPPointOfInterest]) -> Int {
        guard let selectedNearbyAccountID,
              let index = points.firstIndex(where: {
                  ($0.userInfo as? String) == selectedNearbyAccountID
              }) else {
            // Do not force-select the first result. On compact CarPlay
            // displays, the system offsets a selected row beneath the Nearby
            // header and leaves its upper half obscured.
            return NSNotFound
        }
        return index
    }

    func pointOfInterestTemplate(
        _ pointOfInterestTemplate: CPPointOfInterestTemplate,
        didChangeMapRegion region: MKCoordinateRegion
    ) {
        guard Date() >= (ignoreNearbyRegionChangesUntil ?? .distantPast) else { return }
        // A manual map gesture suspends automatic following. The location
        // button explicitly restores it, so periodic refreshes never fight a
        // driver who chose to inspect another area.
        followsNearbyLocation = false
    }

    func pointOfInterestTemplate(
        _ pointOfInterestTemplate: CPPointOfInterestTemplate,
        didSelectPointOfInterest pointOfInterest: CPPointOfInterest
    ) {
        guard let accountID = pointOfInterest.userInfo as? String,
              let account = store.accounts.first(where: { $0.id == accountID }) else { return }
        selectedNearbyAccountID = accountID
        ignoreNearbyRegionChangesUntil = Date().addingTimeInterval(1)
        rememberRecentAccount(account)
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
        let location = effectiveLocation
        let day = breadcrumbs.activeDay ?? breadcrumbs.today

        let speed = store.demoMode ? "64 mph" : currentSpeedText(location)
        let elevation = store.demoMode ? "5,284 ft" : currentElevationText(location, day: day)
        let trip = store.demoMode ? "42.6 mi" : distanceText(day)
        let stops = store.demoMode ? "2 stops" : stopSummaryText(day)
        let time = store.demoMode ? "00:48:17" : elapsedText(day?.elapsedTime ?? 0)
        let accuracy = store.demoMode ? "±10 ft" : currentGPSAccuracyText(location)

        // CPInformationTemplate's `.twoColumn` layout places each item's
        // title and detail in the two columns; it does not pair adjacent
        // information items. Keep this to three explicit rows so every
        // metric remains visible above the CarPlay action buttons.
        return [
            CPInformationItem(
                title: "SPEED  ·  \(speed)",
                detail: "ELEVATION  ·  \(elevation)"
            ),
            CPInformationItem(
                title: "TRIP  ·  \(trip)",
                detail: "STOPS  ·  \(stops)"
            ),
            CPInformationItem(
                title: "TIME  ·  \(time)",
                detail: "GPS ACCURACY  ·  \(accuracy)"
            )
        ]
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
        homeTemplate?.updateSections(makeHomeSections())
        homeTemplate?.headerGridButtons = makeHomeGridButtons()
        refreshNearbyMapIfNeeded()
        favoritesTemplate?.updateSections(makeFavoriteSections())
        recentsTemplate?.updateSections(makeRecentSections())
        tripLogTemplate?.items = makeTripLogInformationItems()
        tripLogTemplate?.actions = makeTripLogActions()
        checkForArrival()
    }

    private func refreshNearbyMapIfNeeded() {
        guard followsNearbyLocation else { return }
        let now = Date()
        guard lastNearbyRefreshAt == nil
                || now.timeIntervalSince(lastNearbyRefreshAt!) >= 15 else { return }
        lastNearbyRefreshAt = now
        let points = makeNearbyPoints()
        ignoreNearbyRegionChangesUntil = now.addingTimeInterval(2)
        nearbyTemplate?.setPointsOfInterest(
            points,
            selectedIndex: points.isEmpty ? NSNotFound : selectedNearbyIndex(in: points)
        )
    }

    private func recenterNearbyMap() {
        followsNearbyLocation = true
        selectedNearbyAccountID = nil
        lastNearbyRefreshAt = nil
        ignoreNearbyRegionChangesUntil = Date().addingTimeInterval(2)
        refreshNearbyMapIfNeeded()
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

    private var tripLogAtAGlanceSummary: String {
        let day = breadcrumbs.activeDay ?? breadcrumbs.today
        return "\(distanceText(day)) • \(elapsedText(day?.elapsedTime ?? 0)) • \(stopCountText(day))"
    }

    private func nearestAccountAtAGlanceSummary(_ account: FireVaultWorkspaceAccount) -> String {
        let accountID = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = accountID.isEmpty ? account.category : "#\(accountID)"
        guard let location = effectiveLocation else {
            return identifier
        }
        let miles = distance(from: location, to: account) / 1_609.344
        return "\(identifier) • \(String(format: "%.1f mi", miles))"
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
