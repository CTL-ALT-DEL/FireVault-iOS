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

enum FireVaultCarPlayArrivalPolicy {
    static let arrivalRadiusMeters: CLLocationDistance = 100
    static let resetRadiusMeters: CLLocationDistance = 200

    static func hasArrived(distanceMeters: CLLocationDistance) -> Bool {
        distanceMeters >= 0 && distanceMeters <= arrivalRadiusMeters
    }

    static func shouldClearArrival(distanceMeters: CLLocationDistance) -> Bool {
        distanceMeters > resetRadiusMeters
    }

    static func pinPriority(label: String, type: String) -> Int {
        let value = "\(label) \(type)".lowercased()
        if value.contains("parking") || value.contains("park here") { return 0 }
        if value.contains("front entrance") || value.contains("main entrance") { return 1 }
        if value.contains("entrance") || value.contains("door") { return 2 }
        if value.contains("panel") { return 3 }
        if value.contains("riser") { return 4 }
        return 5
    }
}

enum FireVaultCarPlayPresentation {
    static func heading(course: CLLocationDirection) -> String {
        guard course >= 0, course.isFinite else { return "Unavailable" }
        let normalized = course.truncatingRemainder(dividingBy: 360)
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((normalized + 22.5) / 45.0) % directions.count
        return "\(directions[index]) • \(Int(normalized.rounded()) % 360)°"
    }

    static func locationAge(seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value < 2 { return "Just now" }
        if value < 60 { return "\(value) sec ago" }
        let minutes = value / 60
        let seconds = value % 60
        return seconds == 0 ? "\(minutes) min ago" : "\(minutes)m \(seconds)s ago"
    }

    static func joined(_ values: [String?]) -> String {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

enum FireVaultCarPlayRefreshPolicy {
    /// Keep live driving telemetry responsive without coupling the CarPlay
    /// presentation cadence to Trip Log's route-archive sampling interval.
    static let minimumInterfaceInterval: TimeInterval = 2
    static let minimumPointOfInterestInterval: TimeInterval = 60
}

private enum FireVaultCarPlayAccountEmphasis {
    case nearest
    case favorite
    case recent
    case standard
}

@MainActor
final class FireVaultCarPlaySceneDelegate: UIResponder,
    CPTemplateApplicationSceneDelegate,
    CPPointOfInterestTemplateDelegate {
    private weak var interfaceController: CPInterfaceController?
    private weak var templateApplicationScene: CPTemplateApplicationScene?
    private let store = FireVaultStore()
    private let settings = FireVaultNativeSettingsStore()
    // Share the live Trip Log owner with the handset scene. Demo Mode keeps a
    // separate deterministic archive so CarPlay can never write demo activity
    // into the technician's live history.
    private lazy var breadcrumbs: FireVaultBreadcrumbStore = store.demoMode
        ? FireVaultDemoShowroom.makeBreadcrumbStore()
        : FireVaultBreadcrumbStore.shared
    private let locationService = FireVaultLocationService.shared

    private var tripLogTemplate: CPInformationTemplate?
    private var nearbyTemplate: CPListTemplate?
    private var driveTemplate: CPInformationTemplate?
    private var arrivedTemplate: CPListTemplate?
    private var nearbyMapTemplate: CPPointOfInterestTemplate?
    private var rootTabTemplate: CPTabBarTemplate?
    private var liveRefreshTask: Task<Void, Never>?
    private var metricRefreshTask: Task<Void, Never>?
    private var lastMetricRefreshAt = Date.distantPast
    private var locationObservation: AnyCancellable?
    private var tripLogLocationObservation: AnyCancellable?
    private var tripLogRecordingObservation: AnyCancellable?
    private var announcedArrivalAccountID: String?
    private var arrivedAccountID: String?
    private var tabAppearanceSignature: String?
    private var lastPointOfInterestRefreshAt = Date.distantPast

    private let demoLocation = CLLocation(latitude: 43.6150, longitude: -116.2023)
    private let recentAccountIDsKey = "firevault.carplay.recentAccountIDs"

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        self.templateApplicationScene = templateApplicationScene

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
        metricRefreshTask?.cancel()
        metricRefreshTask = nil
        locationObservation?.cancel()
        locationObservation = nil
        tripLogLocationObservation?.cancel()
        tripLogLocationObservation = nil
        tripLogRecordingObservation?.cancel()
        tripLogRecordingObservation = nil
        locationService.stopLiveNearbyUpdates(consumer: .carPlay)
        tripLogTemplate = nil
        nearbyTemplate = nil
        driveTemplate = nil
        arrivedTemplate = nil
        nearbyMapTemplate = nil
        rootTabTemplate = nil
        announcedArrivalAccountID = nil
        arrivedAccountID = nil
        tabAppearanceSignature = nil
        lastPointOfInterestRefreshAt = .distantPast
        self.interfaceController = nil
        self.templateApplicationScene = nil
    }

    // MARK: - Native CarPlay tab workspace

    private func makeRootTemplate() -> CPTabBarTemplate {
        let tripLog = makeTripLogTemplate()
        configureTab(
            tripLog,
            title: "Trip Log",
            symbol: breadcrumbs.isRecording ? "record.circle.fill" : "gauge.with.dots.needle.50percent",
            color: breadcrumbs.isRecording ? .systemRed : .systemTeal
        )
        tripLogTemplate = tripLog

        let nearby = makeNearbyTemplate()
        configureTab(nearby, title: "Nearby", symbol: "location.fill", color: .systemBlue)
        nearbyTemplate = nearby

        let drive = makeDriveTemplate()
        configureTab(drive, title: "Drive", symbol: "location.north.line.fill", color: .systemTeal)
        driveTemplate = drive

        let tabs = CPTabBarTemplate(templates: [tripLog, nearby, drive])
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

    // MARK: - Accounts hub

    private func makeNearbyTemplate() -> CPListTemplate {
        let template = CPListTemplate(
            title: "Nearby",
            sections: makeNearbySections()
        )
        template.trailingNavigationBarButtons = [
            CPBarButton(
                title: "Map",
                handler: { [weak self] _ in self?.showNearbyMap() }
            )
        ]
        return template
    }

    private func makeNearbySections() -> [CPListSection] {
        let closest = Array(sortedMappedAccounts(favoritesOnly: false).prefix(4))
        guard !closest.isEmpty else {
            return [CPListSection(items: [emptyAccountItem(
                title: "No mapped accounts",
                detail: "Accounts need coordinates before they can appear in CarPlay."
            )])]
        }

        let closestIDs = Set(closest.map(\.id))
        let favorites = Array(
            sortedMappedAccounts(favoritesOnly: true)
                .filter { !closestIDs.contains($0.id) }
                .prefix(2)
        )
        let displayedIDs = closestIDs.union(favorites.map(\.id))
        let recent = Array(
            recentAccounts
                .filter { $0.coordinate != nil && !displayedIDs.contains($0.id) }
                .prefix(2)
        )

        var sections = [CPListSection(
            items: closest.enumerated().map { index, account in
                makeAccountItem(account, emphasis: index == 0 ? .nearest : .standard)
            },
            header: effectiveLocation == nil ? "Mapped accounts" : "Closest accounts",
            sectionIndexTitle: nil
        )]
        if !favorites.isEmpty {
            sections.append(CPListSection(
                items: favorites.map { makeAccountItem($0, emphasis: .favorite) },
                header: "Favorites",
                sectionIndexTitle: nil
            ))
        }
        if !recent.isEmpty {
            sections.append(CPListSection(
                items: recent.map { makeAccountItem($0, emphasis: .recent) },
                header: "Recent",
                sectionIndexTitle: nil
            ))
        }
        return sections
    }

    // MARK: - Nearby map

    private func showNearbyMap() {
        let accounts = Array(sortedMappedAccounts(favoritesOnly: false).prefix(12))
        guard !accounts.isEmpty else {
            presentAlert(
                title: "No mapped accounts",
                actionTitle: "OK"
            )
            return
        }

        let template: CPPointOfInterestTemplate
        if let nearbyMapTemplate {
            template = nearbyMapTemplate
            refreshNearbyMapIfAllowed(accounts: accounts)
        } else {
            template = CPPointOfInterestTemplate(
                title: "Nearby Accounts",
                pointsOfInterest: makePointsOfInterest(accounts),
                selectedIndex: accounts.isEmpty ? NSNotFound : 0
            )
            template.pointOfInterestDelegate = self
            nearbyMapTemplate = template
            lastPointOfInterestRefreshAt = Date()
        }

        guard interfaceController?.topTemplate != template else { return }
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func makePointsOfInterest(
        _ accounts: [FireVaultWorkspaceAccount]
    ) -> [CPPointOfInterest] {
        accounts.prefix(12).compactMap { account in
            guard let coordinate = account.coordinate else { return nil }
            let mapItem = MKMapItem(
                location: CLLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                ),
                address: nil
            )
            mapItem.name = account.name

            let identifier = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = FireVaultCarPlayPresentation.joined([
                identifier.isEmpty ? nil : "#\(identifier)",
                effectiveLocation.map {
                    String(format: "%.1f mi", distance(from: $0, to: account) / 1_609.344)
                }
            ])
            let address = account.address.trimmingCharacters(in: .whitespacesAndNewlines)
            let point = CPPointOfInterest(
                location: mapItem,
                title: account.name,
                subtitle: subtitle.isEmpty ? nil : subtitle,
                summary: address.isEmpty ? nil : address,
                detailTitle: account.name,
                detailSubtitle: subtitle.isEmpty ? nil : subtitle,
                detailSummary: address.isEmpty ? nil : address,
                pinImage: carPlayIcon(
                    account.favorite ? "star.circle.fill" : "building.2.fill",
                    color: account.favorite ? .systemYellow : .systemBlue
                ),
                selectedPinImage: carPlayIcon("mappin.circle.fill", color: .systemRed)
            )
            point.primaryButton = CPTextButton(
                title: "Directions",
                textStyle: .confirm
            ) { [weak self] _ in
                self?.openDrivingDirections(to: coordinate, name: account.name)
            }
            if account.phone.contains(where: \.isNumber) {
                point.secondaryButton = CPTextButton(
                    title: "Call",
                    textStyle: .normal
                ) { [weak self] _ in
                    self?.openPhone(account.phone)
                }
            }
            return point
        }
    }

    private func refreshNearbyMapIfAllowed(
        accounts: [FireVaultWorkspaceAccount]
    ) {
        guard let nearbyMapTemplate else { return }
        let elapsed = Date().timeIntervalSince(lastPointOfInterestRefreshAt)
        guard elapsed >= FireVaultCarPlayRefreshPolicy.minimumPointOfInterestInterval else {
            return
        }
        lastPointOfInterestRefreshAt = Date()
        let points = makePointsOfInterest(accounts)
        nearbyMapTemplate.setPointsOfInterest(
            points,
            selectedIndex: points.isEmpty ? NSNotFound : 0
        )
    }

    func pointOfInterestTemplate(
        _ pointOfInterestTemplate: CPPointOfInterestTemplate,
        didChangeMapRegion region: MKCoordinateRegion
    ) {
        // Panning is user-driven rather than a periodic refresh. Keep the
        // closest relevant sites available without tying POI updates to the
        // high-frequency Core Location stream.
        let accounts = sortedMappedAccounts(favoritesOnly: false)
            .filter { account in
                guard let coordinate = account.coordinate else { return false }
                return regionContains(region, coordinate: coordinate)
            }
        let relevant = accounts.isEmpty
            ? Array(sortedMappedAccounts(favoritesOnly: false).prefix(12))
            : Array(accounts.prefix(12))
        let points = makePointsOfInterest(relevant)
        pointOfInterestTemplate.setPointsOfInterest(
            points,
            selectedIndex: points.isEmpty ? NSNotFound : 0
        )
        lastPointOfInterestRefreshAt = Date()
    }

    private func regionContains(
        _ region: MKCoordinateRegion,
        coordinate: CLLocationCoordinate2D
    ) -> Bool {
        let latitudeDelta = abs(coordinate.latitude - region.center.latitude)
        let rawLongitudeDelta = abs(coordinate.longitude - region.center.longitude)
        let longitudeDelta = min(rawLongitudeDelta, 360 - rawLongitudeDelta)
        return latitudeDelta <= region.span.latitudeDelta / 2
            && longitudeDelta <= region.span.longitudeDelta / 2
    }

    private func makeArrivedTemplate() -> CPListTemplate {
        CPListTemplate(title: "Arrived", sections: makeArrivedSections())
    }

    private func makeArrivedSections() -> [CPListSection] {
        guard let account = arrivedAccount else {
            return [CPListSection(items: [emptyAccountItem(
                title: "No arrival detected",
                detail: "This screen updates when you reach a mapped account."
            )])]
        }

        let accountItem = CPListItem(
            text: account.name,
            detailText: accountSummaryText(account),
            image: carPlayIcon("checkmark.circle.fill", color: .systemGreen)
        )
        accountItem.isEnabled = false

        var sections = [
            CPListSection(items: [accountItem], header: "Arrived", sectionIndexTitle: nil)
        ]

        let locations = Array(arrivalPoints(in: account).prefix(6))
        let parkingLocations = locations.filter { arrivalPriority(for: $0) == 0 }
        let otherLocations = locations.filter { arrivalPriority(for: $0) != 0 }

        if !parkingLocations.isEmpty {
            sections.append(CPListSection(
                items: parkingLocations.map { dropPinItem($0, account: account) },
                header: "Parking • Start here",
                sectionIndexTitle: nil
            ))
        }

        let arrivalNoteItems = account.notes
            .filter(\.showsOnArrival)
            .prefix(3)
            .map { note in
                let item = CPListItem(
                    text: note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Arrival note" : note.title,
                    detailText: note.text,
                    image: carPlayIcon("bell.badge.fill", color: .systemOrange)
                )
                item.isEnabled = false
                return item
            }
        if !arrivalNoteItems.isEmpty {
            sections.append(CPListSection(
                items: Array(arrivalNoteItems),
                header: "Arrival notes",
                sectionIndexTitle: nil
            ))
        }

        guard !locations.isEmpty else {
            sections.append(CPListSection(items: [emptyAccountItem(
                    title: "No drop-pin locations",
                    detail: "No saved parking, entrance, panel, or riser pins."
                )], header: "Drop-pin locations", sectionIndexTitle: nil))
            return sections
        }

        if !otherLocations.isEmpty {
            sections.append(CPListSection(
                items: otherLocations.map { dropPinItem($0, account: account) },
                header: "Other site locations",
                sectionIndexTitle: nil
            ))
        }
        return sections
    }

    private func makeAccountItem(
        _ account: FireVaultWorkspaceAccount,
        emphasis: FireVaultCarPlayAccountEmphasis
    ) -> CPListItem {
        let arriving = effectiveLocation.map {
            FireVaultCarPlayArrivalPolicy.hasArrived(distanceMeters: distance(from: $0, to: account))
        } ?? false
        let prefix: String?
        let symbol: String
        let color: UIColor
        if arriving {
            prefix = "Arriving"
            symbol = "mappin.circle.fill"
            color = .systemGreen
        } else {
            switch emphasis {
            case .nearest:
                prefix = "Nearest"
                symbol = "location.circle.fill"
                color = .systemBlue
            case .favorite:
                prefix = "Favorite"
                symbol = "star.circle.fill"
                color = .systemYellow
            case .recent:
                prefix = "Recent"
                symbol = "clock.fill"
                color = .systemPurple
            case .standard:
                prefix = nil
                symbol = "building.2.fill"
                color = .secondaryLabel
            }
        }
        let detail = ([prefix] + accountDetailComponents(account)).compactMap { $0 }.joined(separator: " • ")
        let item = CPListItem(
            text: account.name,
            detailText: detail,
            image: carPlayIcon(symbol, color: color),
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
        let template = CPListTemplate(
            title: "Account",
            sections: makeAccountSections(account)
        )
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func makeAccountSections(_ account: FireVaultWorkspaceAccount) -> [CPListSection] {
        let summary = CPListItem(
            text: account.name,
            detailText: accountSummaryText(account),
            image: carPlayIcon(account.favorite ? "star.circle.fill" : "building.2.crop.circle.fill", color: account.favorite ? .systemYellow : .systemBlue)
        )
        summary.isEnabled = false

        var actions: [CPListItem] = []

        if let coordinate = account.coordinate {
            actions.append(actionItem(
                title: "Directions to account",
                detail: account.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Open in Apple Maps"
                    : account.address,
                symbol: "arrow.triangle.turn.up.right.diamond.fill",
                color: .systemBlue
            ) { [weak self] in
                self?.openDrivingDirections(to: coordinate, name: account.name)
            })
        }

        if account.phone.contains(where: \.isNumber) {
            actions.append(actionItem(
                title: "Call account",
                detail: formattedPhone(account.phone),
                symbol: "phone.fill",
                color: .systemGreen
            ) { [weak self] in
                self?.openPhone(account.phone)
            })
        }

        var sections = [CPListSection(items: [summary], header: "Account", sectionIndexTitle: nil)]
        if !actions.isEmpty {
            sections.append(CPListSection(items: actions, header: "Actions", sectionIndexTitle: nil))
        }

        let pins = Array(arrivalPoints(in: account).prefix(4)).map { location in
            dropPinItem(location, account: account)
        }
        if pins.isEmpty {
            sections.append(CPListSection(items: [emptyAccountItem(
                title: "No drop-pin locations",
                detail: "Saved account pins will appear here."
            )], header: "Drop-pin locations", sectionIndexTitle: nil))
        } else {
            sections.append(CPListSection(items: pins, header: "Drop-pin locations", sectionIndexTitle: nil))
        }
        return sections
    }

    private func actionItem(
        title: String,
        detail: String,
        symbol: String,
        color: UIColor,
        action: @escaping @MainActor () -> Void
    ) -> CPListItem {
        let item = CPListItem(
            text: title,
            detailText: detail,
            image: carPlayIcon(symbol, color: color),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }

    private func dropPinItem(
        _ location: FireVaultWorkspaceLocation,
        account: FireVaultWorkspaceAccount
    ) -> CPListItem {
        let label = location.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = CPListItem(
            text: label.isEmpty ? displayLocationType(location.type) : label,
            detailText: "\(displayLocationType(location.type)) • \(location.resolvedDirectionsMode == .driving ? "Drive" : "Walk") directions",
            image: carPlayIcon(arrivalSymbol(for: location), color: arrivalColor(for: location)),
            accessoryImage: nil,
            accessoryType: .disclosureIndicator
        )
        item.handler = { [weak self] _, completion in
            if let coordinate = location.coordinate {
                self?.openDirections(
                    to: coordinate,
                    name: "\(account.name) • \(label.isEmpty ? location.type : label)",
                    mode: location.resolvedDirectionsMode
                )
            }
            completion()
        }
        return item
    }

    private func arrivalPoints(in account: FireVaultWorkspaceAccount) -> [FireVaultWorkspaceLocation] {
        account.locations
            .filter { $0.coordinate != nil }
            .sorted { arrivalPriority(for: $0) < arrivalPriority(for: $1) }
    }

    private func arrivalPriority(for location: FireVaultWorkspaceLocation) -> Int {
        FireVaultCarPlayArrivalPolicy.pinPriority(label: location.label, type: location.type)
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
            clearArrivalState()
            return
        }

        let distanceMeters = distance(from: location, to: account)
        if FireVaultCarPlayArrivalPolicy.shouldClearArrival(distanceMeters: distanceMeters) {
            clearArrivalState()
            return
        }

        guard FireVaultCarPlayArrivalPolicy.hasArrived(distanceMeters: distanceMeters),
              announcedArrivalAccountID != account.id else { return }

        announcedArrivalAccountID = account.id
        arrivedAccountID = account.id
        let template = arrivedTemplate ?? makeArrivedTemplate()
        arrivedTemplate = template
        template.updateSections(makeArrivedSections())
        showArrival(template)
    }

    private func clearArrivalState() {
        announcedArrivalAccountID = nil
        guard arrivedAccountID != nil else { return }
        arrivedAccountID = nil
        if let arrivedTemplate,
           interfaceController?.topTemplate == arrivedTemplate {
            interfaceController?.popTemplate(animated: true, completion: nil)
        }
        arrivedTemplate = nil
    }

    private func showArrival(_ template: CPListTemplate) {
        guard let nearbyTemplate,
              let rootTabTemplate,
              let interfaceController else { return }
        rootTabTemplate.select(nearbyTemplate)
        guard interfaceController.topTemplate != template else { return }
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func displayLocationType(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Saved location" }
        return trimmed.uppercased() == "POI" ? "POI" : trimmed
    }

    private func openDrivingDirections(to coordinate: CLLocationCoordinate2D, name: String) {
        openDirections(to: coordinate, name: name, mode: .driving)
    }

    private func openDirections(
        to coordinate: CLLocationCoordinate2D,
        name: String,
        mode: FireVaultDirectionsMode
    ) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "dirflg", value: mode == .driving ? "d" : "w"),
            URLQueryItem(name: "q", value: name)
        ]
        guard let url = components?.url else { return }
        templateApplicationScene?.open(url, options: nil, completionHandler: nil)
    }

    private func openPhone(_ value: String) {
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty,
              let url = URL(string: "tel:\(digits)") else { return }
        templateApplicationScene?.open(url, options: nil, completionHandler: nil)
    }

    // MARK: - Trip Log dashboard

    private func makeTripLogTemplate() -> CPInformationTemplate {
        let template = CPInformationTemplate(
            // The persistent Trip Log tab already names this screen. Keeping
            // the navigation title empty leaves room for the native dashboard
            // and its driving controls on compact CarPlay displays.
            title: "",
            layout: .twoColumn,
            items: makeTripLogInformationItems(),
            actions: makeTripLogActions()
        )
        template.trailingNavigationBarButtons = [
            CPBarButton(
                title: "GPS",
                handler: { [weak self] _ in self?.showDriveDashboard() }
            )
        ]
        return template
    }

    private func makeTripLogInformationItems() -> [CPInformationItem] {
        let location = effectiveLocation
        let day = breadcrumbs.activeDay ?? breadcrumbs.today

        let speed = store.demoMode ? "64 mph" : currentSpeedText
        let trip = store.demoMode ? "42.6 mi" : distanceText(day)
        // Keep the driving dashboard factual and glanceable. Active-stop
        // duration belongs in the completed Trip Log, where its meaning is
        // clear, rather than implying that the driver is currently onsite.
        let stops = store.demoMode ? "2 stops" : stopCountText(day)
        let time = store.demoMode ? "00:48:17" : elapsedText(day?.elapsedTime ?? 0)
        let accuracy = store.demoMode ? "±10 ft" : currentGPSAccuracyText(location)

        return [
            CPInformationItem(title: "STATUS", detail: "\(tripLogStatus) • \(time)"),
            CPInformationItem(title: "SPEED", detail: speed),
            CPInformationItem(title: "TRIP", detail: trip),
            CPInformationItem(title: "STOPS", detail: stops),
            CPInformationItem(title: "GPS ACCURACY", detail: accuracy)
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
                CPTextButton(title: "End Trip", textStyle: .cancel) { [weak self] _ in
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
            CPTextButton(title: "End Trip", textStyle: .cancel) { [weak self] _ in
                self?.confirmEndTripLog()
            }
        ]
    }

    // MARK: - Driving dashboard

    private func makeDriveTemplate() -> CPInformationTemplate {
        CPInformationTemplate(
            title: "",
            layout: .twoColumn,
            items: makeDriveInformationItems(),
            actions: []
        )
    }

    private func showDriveDashboard() {
        guard let driveTemplate else { return }
        rootTabTemplate?.select(driveTemplate)
    }

    private func makeDriveInformationItems() -> [CPInformationItem] {
        let location = effectiveLocation
        let day = breadcrumbs.activeDay ?? breadcrumbs.today
        let source = breadcrumbs.isRecording ? "Trip Log recorder" : "Live location"

        return [
            CPInformationItem(title: "GPS STATUS", detail: store.demoMode ? "Excellent • ±10 ft" : gpsStatusText(location)),
            CPInformationItem(title: "SPEED", detail: store.demoMode ? "64 mph" : currentSpeedText),
            CPInformationItem(title: "HEADING", detail: store.demoMode ? "NW • 315°" : currentHeadingText(location)),
            CPInformationItem(title: "ELEVATION", detail: store.demoMode ? "5,284 ft" : currentElevationText(location, day: day)),
            CPInformationItem(title: "VERTICAL", detail: store.demoMode ? "±16 ft" : currentVerticalAccuracyText(location)),
            CPInformationItem(title: "LAST FIX", detail: store.demoMode ? "Just now" : currentLocationAgeText(location)),
            CPInformationItem(title: "SOURCE", detail: "\(source) • \(breadcrumbs.isRecording ? "Recording" : "Standby")"),
            CPInformationItem(title: "LOCATION ACCESS", detail: locationAuthorizationText)
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

    private func presentAlert(title: String, actionTitle: String) {
        guard let interfaceController else { return }
        let dismiss = CPAlertAction(title: actionTitle, style: .default) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        interfaceController.presentTemplate(
            CPAlertTemplate(titleVariants: [title], actions: [dismiss]),
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
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestMetricRefresh()
                }
            }
        tripLogLocationObservation?.cancel()
        tripLogLocationObservation = breadcrumbs.$latestLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                Task { @MainActor [weak self] in
                    self?.locationService.acceptTripLogLocation(location)
                    self?.requestMetricRefresh()
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
            locationService.stopLiveNearbyUpdates(consumer: .carPlay)
        } else {
            locationService.startLiveNearbyUpdates(
                highAccuracy: settings.gps.highAccuracy,
                consumer: .carPlay
            )
        }
    }

    private func beginLiveRefresh() {
        liveRefreshTask?.cancel()
        liveRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: .seconds(FireVaultCarPlayRefreshPolicy.minimumInterfaceInterval)
                    )
                } catch {
                    return
                }
                self?.requestMetricRefresh(refreshAccounts: true)
            }
        }
    }

    private func requestMetricRefresh(refreshAccounts: Bool = false) {
        let minimumInterval = FireVaultCarPlayRefreshPolicy.minimumInterfaceInterval
        let elapsed = Date().timeIntervalSince(lastMetricRefreshAt)
        if elapsed >= minimumInterval {
            lastMetricRefreshAt = Date()
            refreshCarPlayState(refreshAccounts: refreshAccounts)
            return
        }
        guard metricRefreshTask == nil else { return }
        metricRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(minimumInterval - elapsed))
            } catch {
                return
            }
            guard let self else { return }
            metricRefreshTask = nil
            lastMetricRefreshAt = Date()
            refreshCarPlayState(refreshAccounts: refreshAccounts)
        }
    }

    private func refreshCarPlayState(refreshAccounts: Bool = true) {
        if refreshAccounts {
            metricRefreshTask?.cancel()
            metricRefreshTask = nil
        }
        lastMetricRefreshAt = Date()
        if refreshAccounts {
            nearbyTemplate?.updateSections(makeNearbySections())
        }
        tripLogTemplate?.items = makeTripLogInformationItems()
        tripLogTemplate?.actions = makeTripLogActions()
        driveTemplate?.items = makeDriveInformationItems()
        checkForArrival()
        refreshTabAppearance()
    }

    private func refreshTabAppearance() {
        let signature = "\(breadcrumbs.isRecording)|\(effectiveLocation == nil)"
        guard signature != tabAppearanceSignature else { return }
        tabAppearanceSignature = signature

        tripLogTemplate?.tabImage = requiredCarPlayIcon(
            breadcrumbs.isRecording ? "record.circle.fill" : "gauge.with.dots.needle.50percent",
            color: breadcrumbs.isRecording ? .systemRed : .systemTeal
        )
        driveTemplate?.tabImage = requiredCarPlayIcon(
            effectiveLocation == nil ? "location.slash.fill" : "location.north.line.fill",
            color: effectiveLocation == nil ? .systemOrange : .systemTeal
        )

        if let rootTabTemplate {
            rootTabTemplate.updateTemplates(rootTabTemplate.templates)
        }
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

    private func accountDetailComponents(_ account: FireVaultWorkspaceAccount) -> [String?] {
        var details: [String?] = []
        let accountID = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = account.category.trimmingCharacters(in: .whitespacesAndNewlines)
        details.append(accountID.isEmpty ? (category.isEmpty ? nil : category) : "#\(accountID)")
        if let location = effectiveLocation {
            let miles = distance(from: location, to: account) / 1_609.344
            details.append(String(format: "%.1f mi", miles))
        }
        return details
    }

    private func accountSummaryText(_ account: FireVaultWorkspaceAccount) -> String {
        let accountID = account.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = account.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return FireVaultCarPlayPresentation.joined([
            accountID.isEmpty ? nil : "#\(accountID)",
            category.isEmpty ? nil : category,
            account.address
        ])
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
        if breadcrumbs.isRecording { return "Recording" }
        if breadcrumbs.activeDay?.isPaused == true { return "Paused" }
        if breadcrumbs.activeDay == nil { return "Ready" }
        return "Complete"
    }

    private var arrivedAccount: FireVaultWorkspaceAccount? {
        guard let arrivedAccountID else { return nil }
        return store.accounts.first { $0.id == arrivedAccountID }
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
    }

    private var currentSpeedText: String {
        let speed = locationService.liveSpeedMetersPerSecond
        guard let speed else { return "— mph" }
        return "\(Int((speed * 2.236_936).rounded())) mph"
    }

    private func gpsStatusText(_ location: CLLocation?) -> String {
        switch breadcrumbs.isRecording ? breadcrumbs.authorizationStatus : locationService.authorizationStatus {
        case .denied, .restricted:
            return "Location access unavailable"
        default:
            break
        }
        guard let location else { return "Acquiring signal" }
        return currentGPSAccuracyText(location)
    }

    private func currentHeadingText(_ location: CLLocation?) -> String {
        guard let location else { return "Unavailable" }
        return FireVaultCarPlayPresentation.heading(course: location.course)
    }

    private func currentVerticalAccuracyText(_ location: CLLocation?) -> String {
        guard let location, location.verticalAccuracy >= 0 else { return "Unavailable" }
        return "±\(max(1, Int((location.verticalAccuracy * 3.280_84).rounded())).formatted()) ft"
    }

    private func currentLocationAgeText(_ location: CLLocation?) -> String {
        guard let location else { return "No location" }
        return FireVaultCarPlayPresentation.locationAge(
            seconds: Date().timeIntervalSince(location.timestamp)
        )
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
