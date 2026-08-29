//
//  FireVaultBreadcrumbs.swift
//  FireVault
//
//  Native daily travel and editable technician-stop history for Build 1.08.04.
//

import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct FireVaultBreadcrumbPoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var altitude: Double? = nil
    var speedMetersPerSecond: Double? = nil

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        .init(
            coordinate: coordinate,
            altitude: altitude ?? 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: altitude == nil ? -1 : 10,
            timestamp: timestamp
        )
    }
}

struct FireVaultBreadcrumbStop: Codable, Identifiable, Equatable {
    var id = UUID()
    var arrival: Date
    var departure: Date?
    var latitude: Double
    var longitude: Double
    var accountID: String?
    var accountName: String?
    var accountAddress: String?
    var customTitle: String?
    var technicianNote: String?
    var isPersonal: Bool?
    var reviewedAt: Date? = nil

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    var title: String {
        if isPersonalStop { return "Personal Stop" }
        return accountName ?? normalizedCustomTitle ?? "Unrecognized Stop"
    }

    var subtitle: String {
        if isPersonalStop { return "Not associated with an account" }
        if let accountAddress, !accountAddress.isEmpty { return accountAddress }
        return "Tap to review and identify this location"
    }

    var duration: TimeInterval {
        duration(asOf: Date())
    }

    func duration(asOf referenceDate: Date) -> TimeInterval {
        max(0, (departure ?? referenceDate).timeIntervalSince(arrival))
    }

    var isPersonalStop: Bool {
        isPersonal ?? false
    }

    var needsReview: Bool {
        let hasIdentifyingDetails = normalizedCustomTitle != nil
            || accountAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return accountID == nil
            && !isPersonalStop
            && reviewedAt == nil
            && !hasIdentifyingDetails
    }

    mutating func assign(to account: FireVaultWorkspaceAccount?) {
        isPersonal = false
        accountID = account?.id
        accountName = account?.name
        accountAddress = account?.address
        if account != nil {
            customTitle = nil
        }
    }

    mutating func markPersonal(_ personal: Bool) {
        isPersonal = personal
        guard personal else { return }
        accountID = nil
        accountName = nil
        accountAddress = nil
        customTitle = nil
        reviewedAt = Date()
    }

    mutating func rename(_ title: String) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        customTitle = normalized.isEmpty ? nil : normalized
    }

    mutating func markReviewed(at date: Date = Date()) {
        reviewedAt = date
    }

    mutating func updateVisit(
        arrival: Date,
        departure: Date?,
        technicianNote: String
    ) {
        let interval = FireVaultBreadcrumbRules.normalizedVisit(
            arrival: arrival,
            departure: departure
        )
        self.arrival = interval.arrival
        self.departure = interval.departure
        let trimmedNote = technicianNote.trimmingCharacters(in: .whitespacesAndNewlines)
        self.technicianNote = trimmedNote.isEmpty ? nil : trimmedNote
    }

    private var normalizedCustomTitle: String? {
        let normalized = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }
}

struct FireVaultBreadcrumbDay: Codable, Identifiable, Equatable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
    var isPaused = false
    var points: [FireVaultBreadcrumbPoint] = []
    var stops: [FireVaultBreadcrumbStop] = []
    var startedAddress: String? = nil
    var endedAddress: String? = nil
    var startedLatitude: Double? = nil
    var startedLongitude: Double? = nil
    var endedLatitude: Double? = nil
    var endedLongitude: Double? = nil

    var isActive: Bool { endedAt == nil }

    var totalDistanceMeters: Double {
        zip(points, points.dropFirst()).reduce(0) { result, pair in
            result + pair.0.location.distance(from: pair.1.location)
        }
    }

    var elapsedTime: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }

    func effectiveDeparture(
        for stop: FireVaultBreadcrumbStop,
        asOf referenceDate: Date = Date()
    ) -> Date {
        let resolved: Date
        if let departure = stop.departure {
            resolved = max(stop.arrival, departure)
        } else {
            let nextArrival = stops
                .lazy
                .filter { $0.id != stop.id && $0.arrival > stop.arrival }
                .map(\.arrival)
                .min()
            let boundary = nextArrival ?? endedAt ?? referenceDate
            let stopLocation = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
            let lastNearbyPoint = points
                .lazy
                .filter { $0.timestamp >= stop.arrival && $0.timestamp <= boundary }
                .filter { $0.location.distance(from: stopLocation) <= FireVaultBreadcrumbRules.stopRadius }
                .map(\.timestamp)
                .max()
            resolved = max(stop.arrival, lastNearbyPoint ?? boundary)
        }

        guard let endedAt else { return resolved }
        return min(resolved, max(stop.arrival, endedAt))
    }

    func stopDuration(
        for stop: FireVaultBreadcrumbStop,
        asOf referenceDate: Date = Date()
    ) -> TimeInterval {
        max(0, effectiveDeparture(for: stop, asOf: referenceDate).timeIntervalSince(stop.arrival))
    }
}

enum FireVaultTripLogIntegrity {
    nonisolated static func normalized(_ source: [FireVaultBreadcrumbDay]) -> [FireVaultBreadcrumbDay] {
        var seenDayIDs = Set<UUID>()
        var days = source
            .filter { seenDayIDs.insert($0.id).inserted }
            .map(normalizeDay)
            .sorted { $0.startedAt > $1.startedAt }

        var keptActiveDay = false
        for index in days.indices {
            guard days[index].endedAt == nil else { continue }
            if !keptActiveDay {
                keptActiveDay = true
            } else {
                let lastTimestamp = days[index].points.last?.timestamp
                    ?? days[index].stops.compactMap(\.departure).max()
                    ?? days[index].startedAt
                days[index].endedAt = max(days[index].startedAt, lastTimestamp)
                days[index].isPaused = false
                days[index].stops = days[index].stops.map { stop in
                    var closed = stop
                    if closed.departure == nil { closed.departure = max(closed.arrival, lastTimestamp) }
                    return closed
                }
            }
        }
        return days
    }

    nonisolated private static func normalizeDay(_ source: FireVaultBreadcrumbDay) -> FireVaultBreadcrumbDay {
        var day = source
        if let endedAt = day.endedAt, endedAt < day.startedAt { day.endedAt = day.startedAt }

        var seenPointIDs = Set<UUID>()
        day.points = day.points
            .filter { point in
                seenPointIDs.insert(point.id).inserted
                    && CLLocationCoordinate2DIsValid(
                        .init(latitude: point.latitude, longitude: point.longitude)
                    )
                    && point.horizontalAccuracy >= 0
            }
            .sorted { $0.timestamp < $1.timestamp }

        var seenStopIDs = Set<UUID>()
        day.stops = day.stops
            .filter { stop in
                seenStopIDs.insert(stop.id).inserted
                    && CLLocationCoordinate2DIsValid(
                        .init(latitude: stop.latitude, longitude: stop.longitude)
                    )
            }
            .map { stop in
                var normalized = stop
                if let departure = normalized.departure, departure < normalized.arrival {
                    normalized.departure = normalized.arrival
                }
                return normalized
            }
            .sorted { $0.arrival < $1.arrival }
        return day
    }
}

enum FireVaultTripLogTelemetry {
    static func recentWaypointCount(
        in day: FireVaultBreadcrumbDay,
        endingAt date: Date,
        interval: TimeInterval = 60
    ) -> Int {
        let cutoff = date.addingTimeInterval(-max(0, interval))
        return day.points.count { point in
            point.timestamp >= cutoff && point.timestamp <= date
        }
    }
}

enum FireVaultBreadcrumbRules {
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 100
    // Route geometry is persisted at a practical field-work density while
    // every delivered location still participates in stop detection.
    static let minimumPointDistance: CLLocationDistance = 75
    static let maximumPointInterval: TimeInterval = 120
    static let stopRadius: CLLocationDistance = 85
    static let minimumAccountStopDuration: TimeInterval = 180
    static let minimumUnrecognizedStopDuration: TimeInterval = 300
    // Background location delivery can become sparse after the vehicle stops.
    // Keep a stationary candidate long enough to satisfy the longest supported
    // stop threshold instead of resetting it before it can qualify.
    static let maximumCandidateGap: TimeInterval = 12 * 60
    static let maximumUnrecognizedAccuracy: CLLocationAccuracy = 50
    static let maximumStationarySpeed: CLLocationSpeed = 2.5
    static let minimumConfirmationSamples = 2
    static let minimumDepartureSamples = 2
    static let minimumDepartureEvidenceDuration: TimeInterval = 20
    static let maximumDepartureClusterRadius: CLLocationDistance = 110
    static let duplicateStopRadius: CLLocationDistance = 125
    static let duplicateStopInterval: TimeInterval = 15 * 60
    static let accountMatchRadius: CLLocationDistance = 175
    static let maximumLiveSpeedAge: TimeInterval = 8
    static let maximumDerivedStationarySpeed: CLLocationSpeed = 1.5
    // Live CarPlay telemetry must not inherit the much wider route-archive
    // spacing. Core Location is configured to deliver roughly 12 m updates
    // while driving, so 8 m confirms motion without treating ordinary GPS
    // drift as vehicle speed.
    static let minimumLiveMovementDistance: CLLocationDistance = 8
    static let minimumLiveMovementSpeed: CLLocationSpeed = 0.75

    static func normalizedVisit(
        arrival: Date,
        departure: Date?
    ) -> (arrival: Date, departure: Date?) {
        guard let departure else { return (arrival, nil) }
        return (arrival, max(arrival, departure))
    }

    static func accepts(_ location: CLLocation, after previous: CLLocation?) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumHorizontalAccuracy,
              abs(location.timestamp.timeIntervalSinceNow) <= 60 else {
            return false
        }
        guard let previous else { return true }
        return location.distance(from: previous) >= minimumPointDistance
            || location.timestamp.timeIntervalSince(previous.timestamp) >= maximumPointInterval
    }

    /// Core Location can briefly retain the vehicle's last driving speed after
    /// the coordinates have stopped moving. Prefer measured displacement over
    /// that stale speed so arrival detection is not blocked by a frozen MPH.
    static func isStationary(
        _ location: CLLocation,
        comparedTo previous: CLLocation?
    ) -> Bool {
        if location.speed < 0 || location.speed <= maximumStationarySpeed {
            return true
        }
        guard let previous else { return false }
        let interval = location.timestamp.timeIntervalSince(previous.timestamp)
        guard interval >= 5 else { return false }
        return location.distance(from: previous) / interval <= maximumDerivedStationarySpeed
    }

    static func resolvedLiveSpeed(
        location: CLLocation?,
        lastMeaningfulMovementAt: Date?,
        now: Date = Date()
    ) -> CLLocationSpeed? {
        guard let location,
              isReliableLiveTelemetry(location, now: now),
              location.speed >= 0 else { return nil }
        guard now.timeIntervalSince(location.timestamp) <= maximumLiveSpeedAge,
              let lastMeaningfulMovementAt,
              now.timeIntervalSince(lastMeaningfulMovementAt) <= maximumLiveSpeedAge else {
            return 0
        }
        return location.speed
    }

    static func isReliableLiveTelemetry(
        _ location: CLLocation,
        now: Date = Date()
    ) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
            && abs(now.timeIntervalSince(location.timestamp)) <= maximumLiveSpeedAge
    }

    static func providesLiveMovementEvidence(
        _ location: CLLocation,
        comparedTo reference: CLLocation?
    ) -> Bool {
        guard isReliableLiveTelemetry(location, now: location.timestamp),
              let reference,
              reference.horizontalAccuracy >= 0,
              reference.horizontalAccuracy <= maximumHorizontalAccuracy else { return false }
        let interval = location.timestamp.timeIntervalSince(reference.timestamp)
        guard interval > 0 else { return false }
        let distance = location.distance(from: reference)
        let derivedSpeed = distance / interval
        return distance >= minimumLiveMovementDistance
            && (derivedSpeed >= minimumLiveMovementSpeed
                || location.speed >= minimumLiveMovementSpeed)
    }

    static func closestAccount(
        to coordinate: CLLocationCoordinate2D,
        accounts: [FireVaultWorkspaceAccount],
        maximumDistance: CLLocationDistance = accountMatchRadius
    ) -> FireVaultWorkspaceAccount? {
        let stopLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return accounts
            .compactMap { account -> (FireVaultWorkspaceAccount, CLLocationDistance)? in
                let siteCoordinates = [account.coordinate]
                    .compactMap { $0 }
                    + account.locations.compactMap(\.coordinate)
                let distances = siteCoordinates.map { accountCoordinate in
                    stopLocation.distance(
                        from: CLLocation(
                            latitude: accountCoordinate.latitude,
                            longitude: accountCoordinate.longitude
                        )
                    )
                }
                guard let distance = distances.min() else { return nil }
                guard distance <= maximumDistance else { return nil }
                return (account, distance)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    static func representativeCoordinate(
        for locations: [CLLocation]
    ) -> CLLocationCoordinate2D? {
        guard !locations.isEmpty else { return nil }
        let latitudes = locations.map(\.coordinate.latitude).sorted()
        let longitudes = locations.map(\.coordinate.longitude).sorted()

        func median(_ values: [Double]) -> Double {
            let middle = values.count / 2
            if values.count.isMultiple(of: 2) {
                return (values[middle - 1] + values[middle]) / 2
            }
            return values[middle]
        }

        return .init(
            latitude: median(latitudes),
            longitude: median(longitudes)
        )
    }

    static func confirmsStopCandidate(
        locations: [CLLocation],
        isKnownAccount: Bool,
        minimumUnknownStopMinutes: Int
    ) -> Bool {
        guard locations.count >= minimumConfirmationSamples,
              let first = locations.first,
              let last = locations.last else { return false }
        let requiredDuration = isKnownAccount
            ? minimumAccountStopDuration
            : TimeInterval(max(1, minimumUnknownStopMinutes) * 60)
        return last.timestamp.timeIntervalSince(first.timestamp) >= requiredDuration
    }

    static func confirmsStopDwell(
        arrival: Date,
        departure: Date,
        isKnownAccount: Bool,
        minimumUnknownStopMinutes: Int
    ) -> Bool {
        let requiredDuration = isKnownAccount
            ? minimumAccountStopDuration
            : TimeInterval(max(1, minimumUnknownStopMinutes) * 60)
        return departure.timeIntervalSince(arrival) >= requiredDuration
    }

    static func confirmsDeparture(
        from stopCoordinate: CLLocationCoordinate2D,
        with samples: [CLLocation]
    ) -> Bool {
        guard samples.count >= minimumDepartureSamples,
              let first = samples.first,
              let last = samples.last,
              last.timestamp.timeIntervalSince(first.timestamp) >= minimumDepartureEvidenceDuration,
              let nextCoordinate = representativeCoordinate(for: samples) else {
            return false
        }

        let stopLocation = CLLocation(
            latitude: stopCoordinate.latitude,
            longitude: stopCoordinate.longitude
        )
        let nextLocation = CLLocation(
            latitude: nextCoordinate.latitude,
            longitude: nextCoordinate.longitude
        )
        let clusterAnchor = CLLocation(
            latitude: first.coordinate.latitude,
            longitude: first.coordinate.longitude
        )

        return nextLocation.distance(from: stopLocation) > stopRadius
            && samples.allSatisfy { $0.distance(from: stopLocation) > stopRadius }
            && samples.allSatisfy {
                $0.distance(from: clusterAnchor) <= maximumDepartureClusterRadius
            }
    }

    static func shouldMergeStop(
        previous: FireVaultBreadcrumbStop,
        arrivingAt arrival: Date,
        coordinate: CLLocationCoordinate2D,
        accountID: String?
    ) -> Bool {
        guard !previous.isPersonalStop else { return false }
        let previousEnd = previous.departure ?? previous.arrival
        let gap = arrival.timeIntervalSince(previousEnd)
        guard gap >= 0, gap <= duplicateStopInterval else { return false }

        let identityIsCompatible = previous.accountID == accountID
            || previous.accountID == nil
            || accountID == nil
        guard identityIsCompatible else { return false }

        return CLLocation(latitude: previous.latitude, longitude: previous.longitude).distance(
            from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        ) <= duplicateStopRadius
    }
}

/// Stateful, source-agnostic live telemetry validation shared by the handset
/// and CarPlay. Route archive sampling remains independent from this tracker.
struct FireVaultLiveSpeedTracker {
    private(set) var referenceLocation: CLLocation?
    private(set) var lastMeaningfulMovementAt: Date?

    mutating func ingest(
        _ location: CLLocation,
        now: Date = Date()
    ) -> CLLocationSpeed? {
        guard FireVaultBreadcrumbRules.isReliableLiveTelemetry(location, now: now) else {
            return nil
        }

        if let referenceLocation {
            if FireVaultBreadcrumbRules.providesLiveMovementEvidence(
                location,
                comparedTo: referenceLocation
            ) {
                lastMeaningfulMovementAt = location.timestamp
                self.referenceLocation = location
            } else if location.timestamp.timeIntervalSince(referenceLocation.timestamp)
                        >= FireVaultBreadcrumbRules.maximumLiveSpeedAge {
                // Advance the window without accepting accumulated GPS drift
                // as proof that the vehicle is moving.
                self.referenceLocation = location
            }
        } else {
            referenceLocation = location
            // Core Location's first fresh speed reading is usable immediately;
            // displacement evidence will confirm or expire it within 8 seconds.
            lastMeaningfulMovementAt = location.timestamp
        }

        return FireVaultBreadcrumbRules.resolvedLiveSpeed(
            location: location,
            lastMeaningfulMovementAt: lastMeaningfulMovementAt,
            now: now
        )
    }

    mutating func reset() {
        referenceLocation = nil
        lastMeaningfulMovementAt = nil
    }
}

struct FireVaultBreadcrumbPermissionState: Equatable {
    let authorizationStatus: CLAuthorizationStatus
    let accuracyAuthorization: CLAccuracyAuthorization

    var isAuthorized: Bool {
        authorizationStatus == .authorizedAlways
            || authorizationStatus == .authorizedWhenInUse
    }

    var requiresSettings: Bool {
        authorizationStatus == .denied
            || (isAuthorized && accuracyAuthorization == .reducedAccuracy)
    }

    var title: String {
        switch authorizationStatus {
        case .authorizedAlways:
            accuracyAuthorization == .fullAccuracy
                ? "Background Tracking Ready"
                : "Approximate Location"
        case .authorizedWhenInUse:
            accuracyAuthorization == .fullAccuracy
                ? "Background Tracking Ready"
                : "Approximate Location"
        case .denied:
            "Location Access Off"
        case .restricted:
            "Location Restricted"
        case .notDetermined:
            "Location Permission Needed"
        @unknown default:
            "Location Unavailable"
        }
    }

    var detail: String {
        switch authorizationStatus {
        case .authorizedAlways:
            if accuracyAuthorization == .reducedAccuracy {
                return "Turn on Precise Location in iOS Settings so Trip Log can recognize short stops and nearby accounts."
            }
            return "Trip Log can continue an active workday while FireVault Pro is in the background."
        case .authorizedWhenInUse:
            if accuracyAuthorization == .reducedAccuracy {
                return "Turn on Precise Location in iOS Settings so Trip Log can recognize short stops and nearby accounts."
            }
            return "An active workday continues in the background and uses the visible iOS location indicator."
        case .denied:
            return "Allow location access in iOS Settings before starting or resuming a Trip Log workday."
        case .restricted:
            return "Location access is restricted by this iPhone’s system or management settings."
        case .notDetermined:
            return "FireVault Pro asks for location access only when you start your first Trip Log workday."
        @unknown default:
            return "This iPhone is not currently providing location access to FireVault Pro."
        }
    }

    var systemImage: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            accuracyAuthorization == .fullAccuracy
                ? "location.fill"
                : "location.circle"
        case .denied, .restricted:
            "location.slash.fill"
        case .notDetermined:
            "location"
        @unknown default:
            "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class FireVaultBreadcrumbStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// The single live archive owner shared by the iPhone/iPad scene and
    /// CarPlay. Demo stores continue to use their own isolated archive URLs.
    static let shared = FireVaultBreadcrumbStore()

    @Published private(set) var days: [FireVaultBreadcrumbDay]
    @Published private(set) var isRecording = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var statusText = "Ready to start today’s route"
    @Published private(set) var acceptedLocationCount = 0
    @Published private(set) var rejectedLocationCount = 0
    @Published private(set) var lastSuccessfulSaveAt: Date?
    @Published private(set) var lastRecoveryAt: Date?
    @Published private(set) var lastPersistenceError: String?
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var liveSpeedMetersPerSecond: CLLocationSpeed?

    private let manager: CLLocationManager
    private let archiveURL: URL
    private let liveActivitiesEnabled: Bool
    private var accounts: [FireVaultWorkspaceAccount] = []
    private var candidateLocations: [CLLocation] = []
    private var departureCandidateLocations: [CLLocation] = []
    private var disregardedStopCoordinate: CLLocationCoordinate2D?
    private var disregardedDepartureLocations: [CLLocation] = []
    private var activeStopID: UUID?
    private var previousDetectionLocation: CLLocation?
    private var liveSpeedTracker = FireVaultLiveSpeedTracker()
    private var sessionIsPrepared = false
    private var liveActivityControlObservation: AnyCancellable?
    private var gpsPreferences: FireVaultGPSPreferences
    private var notificationPreferences: FireVaultNotificationPreferences

    var activeDay: FireVaultBreadcrumbDay? {
        days.first(where: \.isActive)
    }

    var today: FireVaultBreadcrumbDay? {
        activeDay ?? days.first(where: { Calendar.current.isDateInToday($0.startedAt) })
    }

    var permissionState: FireVaultBreadcrumbPermissionState {
        .init(
            authorizationStatus: authorizationStatus,
            accuracyAuthorization: accuracyAuthorization
        )
    }

    init(
        archiveURL: URL? = nil,
        liveActivitiesEnabled: Bool? = nil
    ) {
        let manager = CLLocationManager()
        self.manager = manager
        self.archiveURL = archiveURL ?? Self.defaultArchiveURL
        self.liveActivitiesEnabled = liveActivitiesEnabled ?? (archiveURL == nil)
        let loaded = Self.load(from: archiveURL ?? Self.defaultArchiveURL)
        days = loaded.days
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        let settings = FireVaultNativeSettingsStore()
        gpsPreferences = settings.gps
        notificationPreferences = settings.preferences.notifications ?? FireVaultNotificationPreferences()
        super.init()

        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = FireVaultBreadcrumbRules.minimumPointDistance
        manager.pausesLocationUpdatesAutomatically = true

        if self.liveActivitiesEnabled {
            liveActivityControlObservation = NotificationCenter.default
                .publisher(for: .fireVaultTripLogControlRequested)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.consumeLiveActivityControl()
                    }
                }
            Task { @MainActor [weak self] in
                self?.consumeLiveActivityControl()
            }
        }

        if loaded.recoveredFromBackup {
            lastRecoveryAt = Date()
            statusText = "Trip Log restored from its last known-good backup"
        } else if activeDay != nil {
            statusText = "Workday saved — tap Resume to continue"
        }
    }

    func startWorkday(accounts: [FireVaultWorkspaceAccount]) {
        self.accounts = accounts
        refreshRuntimePreferences()
        sessionIsPrepared = true
        if activeDay == nil {
            days.insert(.init(startedAt: Date()), at: 0)
            persist(immediate: true)
        } else {
            updateActiveDay { $0.isPaused = false }
        }
        beginLocationUpdates()
        FireVaultNotificationService.shared.tripLogStarted(preferences: notificationPreferences)
    }

    func pauseWorkday() {
        guard let index = activeDayIndex else { return }
        finalizeStopIfNeeded(in: index, at: Date())
        stopLocationUpdates()
        candidateLocations.removeAll()
        departureCandidateLocations.removeAll()
        activeStopID = nil
        previousDetectionLocation = nil
        sessionIsPrepared = false
        updateActiveDay(immediate: true) { $0.isPaused = true }
        statusText = "Trip Log paused"
        FireVaultNotificationService.shared.tripLogPaused(preferences: notificationPreferences)
        synchronizeLiveActivity(status: .paused)
    }

    func resumeWorkday(accounts: [FireVaultWorkspaceAccount]) {
        guard activeDay != nil else {
            startWorkday(accounts: accounts)
            return
        }
        self.accounts = accounts
        refreshRuntimePreferences()
        sessionIsPrepared = true
        updateActiveDay(immediate: true) { $0.isPaused = false }
        beginLocationUpdates()
        FireVaultNotificationService.shared.tripLogStarted(preferences: notificationPreferences)
    }

    func restoreActiveWorkday(accounts: [FireVaultWorkspaceAccount]) {
        self.accounts = accounts
        refreshRuntimePreferences()
        // A Live Activity/widget intent can run outside the main app process.
        // Consume its durable App Group command every time the app becomes
        // active, not only once when this singleton is initialized.
        consumeLiveActivityControl()
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        guard let activeDay else {
            if liveActivitiesEnabled {
                FireVaultTripLogLiveActivityController.dismissAll()
            }
            return
        }
        guard !activeDay.isPaused else {
            sessionIsPrepared = false
            stopLocationUpdates()
            statusText = "Trip Log paused"
            synchronizeLiveActivity(status: .paused)
            return
        }
        guard !isRecording else { return }
        sessionIsPrepared = true
        restoreTrackingContext()
        beginLocationUpdates()
    }

    func endWorkday() {
        guard let index = activeDayIndex else { return }
        let end = Date()
        finalizeStopIfNeeded(in: index, at: end)
        days[index].endedAt = end
        let boundaryLocation = latestLocation ?? days[index].points.last?.location
        if let boundaryLocation {
            days[index].endedLatitude = boundaryLocation.coordinate.latitude
            days[index].endedLongitude = boundaryLocation.coordinate.longitude
            resolveBoundaryAddress(
                dayID: days[index].id,
                boundary: .ended,
                location: boundaryLocation
            )
        }
        days[index].isPaused = false
        stopLocationUpdates()
        candidateLocations.removeAll()
        departureCandidateLocations.removeAll()
        disregardedStopCoordinate = nil
        disregardedDepartureLocations.removeAll()
        activeStopID = nil
        previousDetectionLocation = nil
        sessionIsPrepared = false
        statusText = "Workday complete"
        FireVaultNotificationService.shared.tripLogEnded()
        persist(immediate: true)
        let completedDay = days[index]
        if liveActivitiesEnabled {
            FireVaultTripLogLiveActivityController.end(
                day: completedDay,
                showsMetrics: liveActivityPreferences.showsLiveActivityMetrics
            )
        }
        let preferences = FireVaultNativeSettingsStore().preferences
        Task {
            await FireVaultTripLogAutomationService.shared.syncCompletedDay(
                completedDay,
                preferences: preferences
            )
        }
    }

    func deleteDay(_ id: UUID) {
        guard days.first(where: { $0.id == id })?.isActive != true else { return }
        days.removeAll { $0.id == id }
        persist()
    }

    func resolveMissingBoundaryAddresses(for dayID: UUID) {
        guard let index = days.firstIndex(where: { $0.id == dayID }) else { return }
        var changed = false

        if days[index].startedAddress == nil, let first = days[index].points.first {
            days[index].startedLatitude = first.latitude
            days[index].startedLongitude = first.longitude
            changed = true
            resolveBoundaryAddress(
                dayID: dayID,
                boundary: .started,
                location: first.location
            )
        }

        if days[index].endedAt != nil,
           days[index].endedAddress == nil,
           let last = days[index].points.last {
            days[index].endedLatitude = last.latitude
            days[index].endedLongitude = last.longitude
            changed = true
            resolveBoundaryAddress(
                dayID: dayID,
                boundary: .ended,
                location: last.location
            )
        }

        if changed { persist(immediate: true) }
    }

    @discardableResult
    func mergeBackupDays(
        _ incoming: [FireVaultBreadcrumbDay],
        restoredAt: Date
    ) -> (added: Int, preserved: Int) {
        var existingIDs = Set(days.map(\.id))
        var added = 0
        var preserved = 0
        for original in FireVaultTripLogIntegrity.normalized(incoming) {
            guard existingIDs.insert(original.id).inserted else {
                preserved += 1
                continue
            }
            var restored = original
            if restored.isActive {
                restored.endedAt = max(restored.startedAt, restoredAt)
                restored.isPaused = false
            }
            days.append(restored)
            added += 1
        }
        days.sort { $0.startedAt > $1.startedAt }
        persist()
        return (added, preserved)
    }

    func stop(dayID: UUID, stopID: UUID) -> FireVaultBreadcrumbStop? {
        days.first(where: { $0.id == dayID })?
            .stops.first(where: { $0.id == stopID })
    }

    @discardableResult
    func updateStop(
        dayID: UUID,
        stopID: UUID,
        arrival: Date,
        departure: Date?,
        account: FireVaultWorkspaceAccount?,
        customTitle: String,
        customAddress: String,
        technicianNote: String,
        isPersonal: Bool
    ) -> Bool {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              let stopIndex = days[dayIndex].stops.firstIndex(where: { $0.id == stopID }) else {
            return false
        }

        var stop = days[dayIndex].stops[stopIndex]
        stop.updateVisit(
            arrival: arrival,
            departure: departure,
            technicianNote: technicianNote
        )
        if isPersonal {
            stop.markPersonal(true)
        } else {
            stop.assign(to: account)
            if account == nil {
                stop.rename(customTitle)
                let address = customAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                stop.accountAddress = address.isEmpty ? nil : address
            }
            stop.markReviewed()
        }
        days[dayIndex].stops[stopIndex] = stop
        days[dayIndex].stops.sort { $0.arrival < $1.arrival }
        FireVaultNotificationService.shared.stopReviewed(stopID: stopID)
        persist()
        if days[dayIndex].isActive {
            synchronizeLiveActivity(
                status: days[dayIndex].isPaused ? .paused : .recording
            )
        }
        return true
    }

    @discardableResult
    func confirmStop(dayID: UUID, stopID: UUID) -> Bool {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              let stopIndex = days[dayIndex].stops.firstIndex(where: { $0.id == stopID }) else {
            return false
        }
        days[dayIndex].stops[stopIndex].markReviewed()
        FireVaultNotificationService.shared.stopReviewed(stopID: stopID)
        persist()
        return true
    }

    @discardableResult
    func deleteStop(dayID: UUID, stopID: UUID) -> Bool {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              days[dayIndex].stops.contains(where: { $0.id == stopID }) else {
            return false
        }

        days[dayIndex].stops.removeAll { $0.id == stopID }
        FireVaultNotificationService.shared.stopReviewed(stopID: stopID)
        if activeStopID == stopID {
            activeStopID = nil
            candidateLocations.removeAll()
            departureCandidateLocations.removeAll()
        }
        persist()
        if days[dayIndex].isActive {
            synchronizeLiveActivity(
                status: days[dayIndex].isPaused ? .paused : .recording
            )
        }
        return true
    }

    @discardableResult
    func disregardStop(dayID: UUID, stopID: UUID) -> Bool {
        if activeStopID == stopID,
           let stop = stop(dayID: dayID, stopID: stopID) {
            disregardedStopCoordinate = stop.coordinate
            disregardedDepartureLocations.removeAll()
        }
        return deleteStop(dayID: dayID, stopID: stopID)
    }

    func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func refreshLiveActivityPreferences() {
        guard liveActivitiesEnabled else { return }
        let preferences = liveActivityPreferences
        guard preferences.liveActivitiesAreEnabled else {
            dismissLiveActivity()
            return
        }
        guard let activeDay else {
            dismissLiveActivity()
            return
        }
        synchronizeLiveActivity(status: activeDay.isPaused ? .paused : .recording)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        guard sessionIsPrepared, let activeDay else { return }
        guard !activeDay.isPaused else {
            stopLocationUpdates()
            statusText = "Trip Log paused"
            return
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startAuthorizedUpdates()
        case .denied:
            stopLocationUpdates()
            statusText = "Location access is off for Trip Log"
            dismissLiveActivity()
        case .restricted:
            stopLocationUpdates()
            statusText = "Location access is restricted"
            dismissLiveActivity()
        case .notDetermined:
            statusText = "Waiting for location permission…"
        @unknown default:
            stopLocationUpdates()
            statusText = "Location is unavailable"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard location.horizontalAccuracy >= 0 else { continue }
            latestLocation = location
            liveSpeedMetersPerSecond = liveSpeedTracker.ingest(location)
            record(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        recoverCompletedVisit(visit)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .denied {
            stopLocationUpdates()
            statusText = "Location access is off for Trip Log"
            dismissLiveActivity()
        } else {
            statusText = "Waiting for a reliable GPS position…"
        }
    }

    private var activeDayIndex: Int? {
        days.firstIndex(where: \.isActive)
    }

    private func refreshRuntimePreferences() {
        let settings = FireVaultNativeSettingsStore()
        gpsPreferences = settings.gps
        notificationPreferences = settings.preferences.notifications ?? FireVaultNotificationPreferences()
    }

    private func beginLocationUpdates() {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        switch manager.authorizationStatus {
        case .notDetermined:
            statusText = "Waiting for location permission…"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startAuthorizedUpdates()
        case .denied:
            stopLocationUpdates()
            statusText = "Location access is off for Trip Log"
            dismissLiveActivity()
        case .restricted:
            stopLocationUpdates()
            statusText = "Location access is restricted"
            dismissLiveActivity()
        @unknown default:
            stopLocationUpdates()
            statusText = "Location is unavailable"
        }
    }

    private func startAuthorizedUpdates() {
        guard sessionIsPrepared, activeDay?.isPaused == false else { return }
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = gpsPreferences.highAccuracy
            ? kCLLocationAccuracyBest
            : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 12
        // Automatic pausing can occur before a three- or five-minute stop has
        // enough samples to be confirmed. Trip Log already throttles persisted
        // points, so keep Core Location active for reliable arrival/departure
        // recognition during an explicitly started workday.
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startMonitoringVisits()
        manager.startUpdatingLocation()
        isRecording = true
        if activeStopID != nil {
            applyOnSiteEnergyProfile()
        }
        statusText = accuracyAuthorization == .fullAccuracy
            ? "Recording today’s route"
            : "Recording with approximate location"
        synchronizeLiveActivity(status: .recording)
    }

    private func stopLocationUpdates() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringVisits()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        liveSpeedTracker.reset()
        liveSpeedMetersPerSecond = nil
        isRecording = false
    }

    private func record(_ location: CLLocation) {
        guard let index = activeDayIndex, !days[index].isPaused else { return }
        let detectionPrevious = previousDetectionLocation
        previousDetectionLocation = location
        updateStopDetection(with: location, previous: detectionPrevious, dayIndex: index)
        let previous = days[index].points.last?.location
        guard FireVaultBreadcrumbRules.accepts(location, after: previous) else {
            rejectedLocationCount += 1
            return
        }
        acceptedLocationCount += 1

        if days[index].startedLatitude == nil || days[index].startedLongitude == nil {
            days[index].startedLatitude = location.coordinate.latitude
            days[index].startedLongitude = location.coordinate.longitude
            resolveBoundaryAddress(
                dayID: days[index].id,
                boundary: .started,
                location: location
            )
        }

        days[index].points.append(
            .init(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                speedMetersPerSecond: location.speed >= 0 ? location.speed : nil
            )
        )
        if let stop = days[index].stops.last(where: { $0.departure == nil }) {
            let state = stop.accountID == nil ? "Stop detected" : "On site"
            statusText = "\(state) • \(days[index].stopDuration(for: stop).fireVaultDuration)"
        } else {
            statusText = accuracyAuthorization == .fullAccuracy
                ? "Recording • \(days[index].points.count) GPS points"
                : "Recording approximate location • \(days[index].points.count) points"
        }
        persist()
        synchronizeLiveActivity(status: .recording)
    }

    private enum BoundaryAddress {
        case started
        case ended
    }

    private func resolveBoundaryAddress(
        dayID: UUID,
        boundary: BoundaryAddress,
        location: CLLocation
    ) {
        if let account = FireVaultBreadcrumbRules.closestAccount(
            to: location.coordinate,
            accounts: accounts
        ), !account.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyBoundaryAddress(account.address, to: dayID, boundary: boundary)
            return
        }

        Task { [weak self] in
            guard let request = MKReverseGeocodingRequest(location: location),
                  let mapItems = try? await request.mapItems,
                  let mapItem = mapItems.first else { return }
            let rawAddress = mapItem.addressRepresentations?.fullAddress(
                includingRegion: false,
                singleLine: true
            ) ?? mapItem.address?.fullAddress
            let address = rawAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !address.isEmpty else { return }
            self?.applyBoundaryAddress(address, to: dayID, boundary: boundary)
        }
    }

    private func applyBoundaryAddress(
        _ address: String,
        to dayID: UUID,
        boundary: BoundaryAddress
    ) {
        guard let index = days.firstIndex(where: { $0.id == dayID }) else { return }
        switch boundary {
        case .started:
            days[index].startedAddress = address
        case .ended:
            days[index].endedAddress = address
        }
        persist(immediate: true)
    }

    private func restoreTrackingContext() {
        guard candidateLocations.isEmpty, activeStopID == nil, let day = activeDay else {
            return
        }
        departureCandidateLocations.removeAll()

        if let openStop = day.stops.last(where: { $0.departure == nil }) {
            activeStopID = openStop.id
            candidateLocations = day.points
                .filter { $0.timestamp >= openStop.arrival }
                .map(\.location)
            if candidateLocations.isEmpty {
                candidateLocations = [
                    CLLocation(
                        coordinate: openStop.coordinate,
                        altitude: 0,
                        horizontalAccuracy: FireVaultBreadcrumbRules.maximumHorizontalAccuracy,
                        verticalAccuracy: -1,
                        timestamp: openStop.arrival
                    )
                ]
            }
            return
        }

        guard let lastPoint = day.points.last else { return }
        let lastLocation = lastPoint.location
        candidateLocations = day.points
            .reversed()
            .prefix { point in
                lastLocation.distance(from: point.location)
                    <= FireVaultBreadcrumbRules.stopRadius
            }
            .reversed()
            .map(\.location)
    }

    private func updateStopDetection(
        with location: CLLocation,
        previous: CLLocation?,
        dayIndex: Int
    ) {
        if suppressesDisregardedStop(at: location) {
            return
        }

        if let lastCandidate = candidateLocations.last,
           location.timestamp.timeIntervalSince(lastCandidate.timestamp) > FireVaultBreadcrumbRules.maximumCandidateGap {
            departureCandidateLocations.removeAll()
            if activeStopID == nil {
                let candidateLocation = CLLocation(
                    latitude: candidateCoordinate.latitude,
                    longitude: candidateCoordinate.longitude
                )
                // A delayed sample at the same place is useful dwell evidence.
                // Reset only when the first post-gap sample is somewhere else.
                if location.distance(from: candidateLocation) > FireVaultBreadcrumbRules.stopRadius {
                    candidateLocations.removeAll()
                }
            }
        }

        guard isReliableStopSample(location, previous: previous) else {
            collectMovingDepartureEvidence(location, dayIndex: dayIndex)
            return
        }

        guard let anchor = candidateLocations.first else {
            candidateLocations = [location]
            departureCandidateLocations.removeAll()
            return
        }

        let stopCoordinate = candidateCoordinate
        let distanceFromStop = CLLocation(
            latitude: stopCoordinate.latitude,
            longitude: stopCoordinate.longitude
        ).distance(from: location)

        if distanceFromStop <= FireVaultBreadcrumbRules.stopRadius {
            candidateLocations.append(location)
            departureCandidateLocations.removeAll()
            if activeStopID == nil, candidateCanBeConfirmed {
                let coordinate = candidateCoordinate
                let account = FireVaultBreadcrumbRules.closestAccount(to: coordinate, accounts: accounts)
                beginConfirmedStop(
                    dayIndex: dayIndex,
                    arrival: anchor.timestamp,
                    coordinate: coordinate,
                    account: account
                )
            }
            return
        }

        departureCandidateLocations.append(location)
        guard FireVaultBreadcrumbRules.confirmsDeparture(
            from: stopCoordinate,
            with: departureCandidateLocations
        ) else {
            return
        }

        closeActiveStopIfNeeded(
            dayIndex: dayIndex,
            departure: candidateLocations.last?.timestamp ?? anchor.timestamp
        )
        candidateLocations = departureCandidateLocations
        departureCandidateLocations.removeAll()
        activeStopID = nil
    }

    private func isReliableStopSample(
        _ location: CLLocation,
        previous: CLLocation?
    ) -> Bool {
        let account = FireVaultBreadcrumbRules.closestAccount(to: location.coordinate, accounts: accounts)
        let accuracyLimit = account == nil && gpsPreferences.rejectsPoorAccuracyStops
            ? FireVaultBreadcrumbRules.maximumUnrecognizedAccuracy
            : FireVaultBreadcrumbRules.maximumHorizontalAccuracy
        return location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= accuracyLimit
            && FireVaultBreadcrumbRules.isStationary(location, comparedTo: previous)
    }

    private func recoverCompletedVisit(_ visit: CLVisit) {
        guard let dayIndex = activeDayIndex,
              !days[dayIndex].isPaused,
              visit.arrivalDate != .distantPast,
              visit.departureDate != .distantFuture,
              visit.departureDate >= visit.arrivalDate,
              CLLocationCoordinate2DIsValid(visit.coordinate) else { return }

        let account = FireVaultBreadcrumbRules.closestAccount(
            to: visit.coordinate,
            accounts: accounts
        )
        guard FireVaultBreadcrumbRules.confirmsStopDwell(
            arrival: visit.arrivalDate,
            departure: visit.departureDate,
            isKnownAccount: account != nil,
            minimumUnknownStopMinutes: gpsPreferences.resolvedTripLogMinimumUnknownStopMinutes
        ) else { return }

        let visitLocation = CLLocation(
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude
        )
        let alreadyRecorded = days[dayIndex].stops.contains { stop in
            let stopLocation = CLLocation(
                latitude: stop.latitude,
                longitude: stop.longitude
            )
            let overlaps = stop.arrival <= visit.departureDate
                && (stop.departure ?? Date.distantFuture) >= visit.arrivalDate
            return overlaps
                && stopLocation.distance(from: visitLocation)
                    <= FireVaultBreadcrumbRules.duplicateStopRadius
        }
        guard !alreadyRecorded else { return }

        beginConfirmedStop(
            dayIndex: dayIndex,
            arrival: visit.arrivalDate,
            coordinate: visit.coordinate,
            account: account
        )
        closeActiveStopIfNeeded(dayIndex: dayIndex, departure: visit.departureDate)
        activeStopID = nil
        candidateLocations.removeAll()
        departureCandidateLocations.removeAll()
        persist()
        synchronizeLiveActivity(status: .recording)
    }

    private func collectMovingDepartureEvidence(_ location: CLLocation, dayIndex: Int) {
        guard !candidateLocations.isEmpty,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= FireVaultBreadcrumbRules.maximumHorizontalAccuracy,
              location.speed >= FireVaultBreadcrumbRules.maximumStationarySpeed else { return }

        let stopCoordinate = candidateCoordinate
        let stopLocation = CLLocation(
            latitude: stopCoordinate.latitude,
            longitude: stopCoordinate.longitude
        )
        // Ignore an isolated speed spike while the coordinate remains on site.
        guard location.distance(from: stopLocation) > FireVaultBreadcrumbRules.stopRadius else {
            departureCandidateLocations.removeAll()
            return
        }

        departureCandidateLocations.append(location)
        guard FireVaultBreadcrumbRules.confirmsDeparture(
            from: stopCoordinate,
            with: departureCandidateLocations
        ) else { return }

        let firstDeparture = departureCandidateLocations.first?.timestamp ?? location.timestamp
        if activeStopID == nil,
           let arrival = candidateLocations.first?.timestamp {
            let account = FireVaultBreadcrumbRules.closestAccount(
                to: stopCoordinate,
                accounts: accounts
            )
            if FireVaultBreadcrumbRules.confirmsStopDwell(
                arrival: arrival,
                departure: firstDeparture,
                isKnownAccount: account != nil,
                minimumUnknownStopMinutes: gpsPreferences.resolvedTripLogMinimumUnknownStopMinutes
            ) {
                // Core Location may provide one final stationary sample and
                // then remain quiet until the vehicle leaves. Recover that
                // legitimate visit from its arrival and departure evidence.
                beginConfirmedStop(
                    dayIndex: dayIndex,
                    arrival: arrival,
                    coordinate: stopCoordinate,
                    account: account
                )
            }
        }

        closeActiveStopIfNeeded(
            dayIndex: dayIndex,
            departure: firstDeparture
        )
        candidateLocations.removeAll()
        departureCandidateLocations.removeAll()
        activeStopID = nil
    }

    private func suppressesDisregardedStop(at location: CLLocation) -> Bool {
        guard let disregardedStopCoordinate else { return false }

        if location.speed >= FireVaultBreadcrumbRules.maximumStationarySpeed {
            self.disregardedStopCoordinate = nil
            disregardedDepartureLocations.removeAll()
            return false
        }

        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= FireVaultBreadcrumbRules.maximumHorizontalAccuracy else {
            return true
        }

        let disregardedLocation = CLLocation(
            latitude: disregardedStopCoordinate.latitude,
            longitude: disregardedStopCoordinate.longitude
        )
        if location.distance(from: disregardedLocation) <= FireVaultBreadcrumbRules.stopRadius {
            disregardedDepartureLocations.removeAll()
            return true
        }

        disregardedDepartureLocations.append(location)
        guard FireVaultBreadcrumbRules.confirmsDeparture(
            from: disregardedStopCoordinate,
            with: disregardedDepartureLocations
        ) else {
            return true
        }

        self.disregardedStopCoordinate = nil
        disregardedDepartureLocations.removeAll()
        return false
    }

    private var candidateCanBeConfirmed: Bool {
        let account = FireVaultBreadcrumbRules.closestAccount(to: candidateCoordinate, accounts: accounts)
        return FireVaultBreadcrumbRules.confirmsStopCandidate(
            locations: candidateLocations,
            isKnownAccount: account != nil,
            minimumUnknownStopMinutes: gpsPreferences.resolvedTripLogMinimumUnknownStopMinutes
        )
    }

    private func beginConfirmedStop(
        dayIndex: Int,
        arrival: Date,
        coordinate: CLLocationCoordinate2D,
        account: FireVaultWorkspaceAccount?
    ) {
        if gpsPreferences.mergesNearbyStops,
           let previousIndex = days[dayIndex].stops.lastIndex(where: { previous in
               FireVaultBreadcrumbRules.shouldMergeStop(
                   previous: previous,
                   arrivingAt: arrival,
                   coordinate: coordinate,
                   accountID: account?.id
               )
           }) {
            let wasUnassigned = days[dayIndex].stops[previousIndex].accountID == nil
            if days[dayIndex].stops[previousIndex].accountID == nil,
               days[dayIndex].stops[previousIndex].reviewedAt == nil,
               let account {
                days[dayIndex].stops[previousIndex].assign(to: account)
            }
            days[dayIndex].stops[previousIndex].departure = nil
            activeStopID = days[dayIndex].stops[previousIndex].id
            applyOnSiteEnergyProfile()
            if wasUnassigned, days[dayIndex].stops[previousIndex].accountID != nil {
                FireVaultNotificationService.shared.stopReviewed(
                    stopID: days[dayIndex].stops[previousIndex].id
                )
                notifyConfirmedStop(days[dayIndex].stops[previousIndex])
            }
            return
        }

        let stop = FireVaultBreadcrumbStop(
            arrival: arrival,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            accountID: account?.id,
            accountName: account?.name,
            accountAddress: account?.address
        )
        activeStopID = stop.id
        days[dayIndex].stops.append(stop)
        applyOnSiteEnergyProfile()
        notifyConfirmedStop(stop)
    }

    private func notifyConfirmedStop(_ stop: FireVaultBreadcrumbStop) {
        if let accountID = stop.accountID {
            let account = accounts.first(where: { $0.id == accountID })
            let arrivalNotes = account?.notes.filter(\.showsOnArrival) ?? []
            let parkingLocation = account?.locations.first { location in
                let value = "\(location.label) \(location.type)".lowercased()
                return value.contains("parking") || value.contains("park here")
            }
            FireVaultNotificationService.shared.accountArrivalDetected(
                stop: stop,
                preferences: notificationPreferences,
                arrivalNotes: arrivalNotes,
                parkingLocation: parkingLocation
            )
        } else if stop.needsReview {
            FireVaultNotificationService.shared.unknownStopDetected(
                stop: stop,
                preferences: notificationPreferences
            )
        }
    }

    private func closeActiveStopIfNeeded(dayIndex: Int, departure: Date) {
        guard let activeStopID,
              let stopIndex = days[dayIndex].stops.firstIndex(where: { $0.id == activeStopID }) else { return }
        days[dayIndex].stops[stopIndex].departure = max(
            days[dayIndex].stops[stopIndex].arrival,
            departure
        )
        applyDrivingEnergyProfile()
    }

    private func applyOnSiteEnergyProfile() {
        guard isRecording else { return }
        manager.activityType = .other
        manager.desiredAccuracy = gpsPreferences.highAccuracy
            ? kCLLocationAccuracyNearestTenMeters
            : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    private func applyDrivingEnergyProfile() {
        guard isRecording else { return }
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = gpsPreferences.highAccuracy
            ? kCLLocationAccuracyBest
            : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 12
    }

    private var candidateCoordinate: CLLocationCoordinate2D {
        FireVaultBreadcrumbRules.representativeCoordinate(for: candidateLocations) ?? .init()
    }

    private func finalizeStopIfNeeded(in dayIndex: Int, at end: Date) {
        if let activeStopID,
           let stopIndex = days[dayIndex].stops.firstIndex(where: { $0.id == activeStopID }) {
            days[dayIndex].stops[stopIndex].departure = max(
                days[dayIndex].stops[stopIndex].arrival,
                end
            )
            return
        }

        guard let first = candidateLocations.first else { return }
        let coordinate = candidateCoordinate
        let account = FireVaultBreadcrumbRules.closestAccount(to: coordinate, accounts: accounts)
        guard candidateCanBeConfirmed || FireVaultBreadcrumbRules.confirmsStopDwell(
            arrival: first.timestamp,
            departure: end,
            isKnownAccount: account != nil,
            minimumUnknownStopMinutes: gpsPreferences.resolvedTripLogMinimumUnknownStopMinutes
        ) else { return }
        beginConfirmedStop(
            dayIndex: dayIndex,
            arrival: first.timestamp,
            coordinate: coordinate,
            account: account
        )
        closeActiveStopIfNeeded(
            dayIndex: dayIndex,
            departure: end
        )
    }

    private func updateActiveDay(
        immediate: Bool = false,
        _ change: (inout FireVaultBreadcrumbDay) -> Void
    ) {
        guard let index = activeDayIndex else { return }
        change(&days[index])
        persist(immediate: immediate)
    }

    private func synchronizeLiveActivity(
        status: FireVaultTripLogActivityAttributes.Status
    ) {
        guard liveActivitiesEnabled, let day = activeDay else { return }
        let preferences = liveActivityPreferences
        guard preferences.liveActivitiesAreEnabled else {
            dismissLiveActivity()
            return
        }
        FireVaultTripLogLiveActivityController.synchronize(
            day: day,
            status: status,
            showsMetrics: preferences.showsLiveActivityMetrics
        )
    }

    private func dismissLiveActivity() {
        guard liveActivitiesEnabled else { return }
        FireVaultTripLogLiveActivityController.dismissAll()
    }

    private var liveActivityPreferences: FireVaultNotificationPreferences {
        FireVaultNativeSettingsStore().preferences.notifications
            ?? FireVaultNotificationPreferences()
    }

    private func consumeLiveActivityControl() {
        guard let command = FireVaultTripLogControlMailbox.consume() else { return }
        switch command {
        case .pause:
            guard activeDay?.isPaused == false else { return }
            pauseWorkday()
        case .resume:
            guard activeDay?.isPaused == true else { return }
            resumeWorkday(accounts: accounts)
        case .end:
            guard activeDay != nil else { return }
            endWorkday()
        }
    }

    private func persist(immediate: Bool = false) {
        do {
            let data = try JSONEncoder.fireVaultBreadcrumbs.encode(days)
            let url = archiveURL
            Task { [weak self] in
                do {
                    let wrote = try await FireVaultTripLogArchiveWriter.shared.write(
                        data,
                        to: url,
                        immediate: immediate
                    )
                    guard wrote else { return }
                    self?.lastSuccessfulSaveAt = Date()
                    self?.lastPersistenceError = nil
                } catch {
                    self?.lastPersistenceError = error.localizedDescription
                    self?.statusText = "Route is active, but its history could not be saved"
                }
            }
        } catch {
            lastPersistenceError = error.localizedDescription
            statusText = "Route is active, but its history could not be saved"
        }
    }

    private static func load(from url: URL) -> (days: [FireVaultBreadcrumbDay], recoveredFromBackup: Bool) {
        if let saved = decodeArchive(at: url) {
            return (FireVaultTripLogIntegrity.normalized(saved), false)
        }
        if let saved = decodeArchive(at: backupURL(for: url)) {
            return (FireVaultTripLogIntegrity.normalized(saved), true)
        }
        return ([], false)
    }

    private static func decodeArchive(at url: URL) -> [FireVaultBreadcrumbDay]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.fireVaultBreadcrumbs.decode([FireVaultBreadcrumbDay].self, from: data)
    }

    private static func backupURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("backup.json")
    }

    private static var defaultArchiveURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("FireVault", isDirectory: true)
            .appendingPathComponent("breadcrumbs-v1.json")
    }
}

struct FireVaultBreadcrumbsView: View {
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @ObservedObject var store: FireVaultStore
    let technicianName: String
    let companyName: String
    let includeCoordinatesInReports: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDayID: UUID?
    @State private var confirmsEnd = false
    @State private var editingStop: BreadcrumbStopSelection?
    @State private var showsReport = false

    private var selectedDay: FireVaultBreadcrumbDay? {
        if let selectedDayID {
            return breadcrumbs.days.first(where: { $0.id == selectedDayID })
        }
        return breadcrumbs.today ?? breadcrumbs.days.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    daySelector
                    trackingControls

                    if let day = selectedDay {
                        routeMap(day)
                        summary(day)
                        timeline(day)
                    } else {
                        ContentUnavailableView(
                            "No Trip Log Yet",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text("Start your workday to record today’s route and account stops.")
                        )
                        .frame(minHeight: 300)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(NativeShellPalette.background)
            .navigationTitle("Trip Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedDay != nil {
                        Button("Report", systemImage: "doc.text") {
                            showsReport = true
                        }
                        .accessibilityHint("Previews and exports this workday report")
                    }
                }
            }
            .confirmationDialog(
                "End Today’s Workday?",
                isPresented: $confirmsEnd,
                titleVisibility: .visible
            ) {
                Button("End Workday", role: .destructive) {
                    breadcrumbs.endWorkday()
                    selectedDayID = breadcrumbs.today?.id
                }
                Button("Keep Recording", role: .cancel) {}
            } message: {
                Text("The route and detected stops will remain in your local daily history.")
            }
        }
        .tint(NativeShellPalette.blue)
        .onAppear {
            selectedDayID = breadcrumbs.today?.id ?? breadcrumbs.days.first?.id
        }
        .task(id: selectedDay?.id) {
            guard let dayID = selectedDay?.id else { return }
            breadcrumbs.resolveMissingBoundaryAddresses(for: dayID)
        }
        .sheet(item: $editingStop) { selection in
            FireVaultBreadcrumbStopEditor(
                breadcrumbs: breadcrumbs,
                store: store,
                dayID: selection.dayID,
                stopID: selection.stopID
            ) { accountID in
                store.openAccount(accountID)
                editingStop = nil
                dismiss()
            }
        }
        .sheet(isPresented: $showsReport) {
            if let selectedDay {
                FireVaultBreadcrumbReportView(
                    report: .init(
                        day: selectedDay,
                        technicianName: technicianName,
                        companyName: companyName,
                        includeCoordinates: includeCoordinatesInReports
                    )
                )
            }
        }
    }

    private var daySelector: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay?.startedAt.formatted(.dateTime.weekday(.wide)) ?? "TODAY")
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(NativeShellPalette.red)
                Text(selectedDay?.startedAt.formatted(date: .long, time: .omitted) ?? Date().formatted(date: .long, time: .omitted))
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            Spacer()
            if !breadcrumbs.days.isEmpty {
                Menu {
                    ForEach(breadcrumbs.days) { day in
                        Button {
                            selectedDayID = day.id
                        } label: {
                            Label(
                                day.startedAt.formatted(date: .abbreviated, time: .omitted),
                                systemImage: day.isActive ? "record.circle" : "calendar"
                            )
                        }
                    }
                } label: {
                    Label("History", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 8)
    }

    private var trackingControls: some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            breadcrumbs.isRecording ? "Workday Recording" : "Workday Tracking",
                            systemImage: breadcrumbs.isRecording ? "location.fill" : "location"
                        )
                        .font(.headline)
                        .foregroundStyle(breadcrumbs.isRecording ? NativeShellPalette.green : .white)
                        Text(breadcrumbs.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if breadcrumbs.isRecording {
                        Circle()
                            .fill(NativeShellPalette.green)
                            .frame(width: 10, height: 10)
                            .shadow(color: NativeShellPalette.green.opacity(0.7), radius: 5)
                            .accessibilityLabel("Recording")
                    }
                }

                Divider()

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(breadcrumbs.permissionState.title)
                            .font(.subheadline.weight(.semibold))
                        Text(breadcrumbs.permissionState.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: breadcrumbs.permissionState.systemImage)
                        .foregroundStyle(
                            breadcrumbs.permissionState.isAuthorized
                                ? NativeShellPalette.green
                                : NativeShellPalette.amber
                        )
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("breadcrumbs-location-permission")

                if breadcrumbs.permissionState.requiresSettings {
                    Button("Open Location Settings", systemImage: "gearshape") {
                        breadcrumbs.openLocationSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if breadcrumbs.activeDay == nil {
                    if breadcrumbs.authorizationStatus != .denied,
                       breadcrumbs.authorizationStatus != .restricted {
                        Button("Start Workday", systemImage: "play.fill") {
                            breadcrumbs.startWorkday(accounts: store.accounts)
                            selectedDayID = breadcrumbs.activeDay?.id
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    HStack {
                        if breadcrumbs.isRecording {
                            Button("Pause", systemImage: "pause.fill") {
                                breadcrumbs.pauseWorkday()
                            }
                            .buttonStyle(.bordered)
                        } else if breadcrumbs.permissionState.isAuthorized
                                    || breadcrumbs.authorizationStatus == .notDetermined {
                            Button("Resume", systemImage: "play.fill") {
                                breadcrumbs.resumeWorkday(accounts: store.accounts)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                        Button("End Day", systemImage: "stop.fill", role: .destructive) {
                            confirmsEnd = true
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("Trip Log starts only when you choose Start Workday. Route history stays in FireVault Pro on this device unless you explicitly export a report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("breadcrumbs-tracking-controls")
    }

    @ViewBuilder
    private func routeMap(_ day: FireVaultBreadcrumbDay) -> some View {
        if day.points.isEmpty {
            NativeShellCard {
                ContentUnavailableView(
                    "Waiting for Route",
                    systemImage: "map",
                    description: Text(
                        day.isActive
                            ? "Keep the workday active while FireVault Pro collects the first reliable GPS positions. Recording can continue while you use other apps."
                            : "No reliable GPS points were recorded for this workday."
                    )
                )
                .frame(height: 210)
            }
        } else {
            Map(initialPosition: .automatic, interactionModes: [.pan, .zoom, .rotate]) {
                MapPolyline(coordinates: day.points.map(\.coordinate))
                    .stroke(NativeShellPalette.red, style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))

                if let first = day.points.first {
                    Marker("Workday Start", systemImage: "play.fill", coordinate: first.coordinate)
                        .tint(NativeShellPalette.green)
                }

                ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                    Annotation(stop.title, coordinate: stop.coordinate) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(stopTint(stop), in: Circle())
                            .overlay { Circle().stroke(.white.opacity(0.85), lineWidth: 2) }
                    }
                }

                if let last = day.points.last, !day.isActive {
                    Marker("Workday End", systemImage: "stop.fill", coordinate: last.coordinate)
                        .tint(NativeShellPalette.red)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .accessibilityIdentifier("breadcrumbs-route-map")
        }
    }

    private func summary(_ day: FireVaultBreadcrumbDay) -> some View {
        HStack(spacing: 1) {
            BreadcrumbMetric(
                title: "MILES",
                value: day.totalDistanceMeters.fireVaultMiles,
                symbol: "road.lanes"
            )
            Divider().frame(height: 45)
            BreadcrumbMetric(
                title: "STOPS",
                value: "\(day.stops.count)",
                symbol: "mappin.and.ellipse"
            )
            Divider().frame(height: 45)
            BreadcrumbMetric(
                title: "ELAPSED",
                value: day.elapsedTime.fireVaultDuration,
                symbol: "clock"
            )
        }
        .padding(.vertical, 13)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottom) {
            if day.stops.contains(where: \.needsReview) {
                Text("\(day.stops.filter(\.needsReview).count) need review")
                    .font(.caption2.bold())
                    .foregroundStyle(NativeShellPalette.amber)
                    .offset(y: 20)
            }
        }
        .padding(.bottom, day.stops.contains(where: \.needsReview) ? 16 : 0)
    }

    private func timeline(_ day: FireVaultBreadcrumbDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAILY LOG")
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.secondary)

            NativeShellCard {
                VStack(spacing: 0) {
                    BreadcrumbTimelineRow(
                        time: day.startedAt,
                        title: "Workday Started",
                        subtitle: day.startedAddress
                            ?? day.points.first.map { "Near \($0.coordinate.fireVaultCoordinateLabel)" },
                        symbol: "play.fill",
                        tint: NativeShellPalette.green
                    )

                    ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                        Divider().padding(.leading, 52)
                        Button {
                            editingStop = .init(dayID: day.id, stopID: stop.id)
                        } label: {
                            BreadcrumbTimelineRow(
                                time: stop.arrival,
                                title: stop.title,
                                subtitle: stopTimelineSubtitle(stop),
                                symbol: "\(index + 1).circle.fill",
                                tint: stopTint(stop),
                                showsDisclosure: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this stop for review and editing")
                    }

                    if let endedAt = day.endedAt {
                        Divider().padding(.leading, 52)
                        BreadcrumbTimelineRow(
                            time: endedAt,
                            title: "Workday Ended",
                            subtitle: [day.endedAddress, day.totalDistanceMeters.fireVaultMiles]
                                .compactMap { $0 }
                                .joined(separator: " • "),
                            symbol: "stop.fill",
                            tint: NativeShellPalette.red
                        )
                    } else {
                        Divider().padding(.leading, 52)
                        BreadcrumbTimelineRow(
                            time: Date(),
                            title: day.isPaused ? "Tracking Paused" : "Workday in Progress",
                            subtitle: breadcrumbs.statusText,
                            symbol: day.isPaused ? "pause.fill" : "location.fill",
                            tint: day.isPaused ? NativeShellPalette.amber : NativeShellPalette.green
                        )
                    }
                }
            }
        }
    }

    private func stopTint(_ stop: FireVaultBreadcrumbStop) -> Color {
        if stop.isPersonalStop { return .secondary }
        if stop.needsReview { return NativeShellPalette.amber }
        return stop.accountID == nil ? NativeShellPalette.green : NativeShellPalette.blue
    }

    private func stopTimelineSubtitle(_ stop: FireVaultBreadcrumbStop) -> String {
        var parts = [
            stop.subtitle,
            (selectedDay?.stopDuration(for: stop) ?? stop.duration).fireVaultDuration
        ]
        if stop.needsReview {
            parts.insert("Needs review", at: 0)
        }
        if stop.technicianNote?.isEmpty == false {
            parts.append("Note added")
        }
        return parts.joined(separator: " • ")
    }
}

private struct BreadcrumbStopSelection: Identifiable {
    let dayID: UUID
    let stopID: UUID
    var id: UUID { stopID }
}

struct FireVaultBreadcrumbStopEditor: View {
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @ObservedObject var store: FireVaultStore
    @Environment(\.dismiss) private var dismiss

    let dayID: UUID
    let stopID: UUID
    let openAccount: (String) -> Void

    @State private var arrival: Date
    @State private var departure: Date
    @State private var hasDeparture: Bool
    @State private var selectedAccountID: String?
    @State private var customTitle: String
    @State private var customAddress: String
    @State private var technicianNote: String
    @State private var isPersonal: Bool
    @State private var showsAccountPicker = false
    @State private var confirmsDelete = false
    @State private var isCheckingGooglePlaces = false
    @State private var googlePlacesMatches: [FireVaultGooglePlaceMatch] = []
    @State private var showsGooglePlacesMatches = false
    @State private var googlePlacesError: String?

    init(
        breadcrumbs: FireVaultBreadcrumbStore,
        store: FireVaultStore,
        dayID: UUID,
        stopID: UUID,
        openAccount: @escaping (String) -> Void
    ) {
        self.breadcrumbs = breadcrumbs
        self.store = store
        self.dayID = dayID
        self.stopID = stopID
        self.openAccount = openAccount

        let stop = breadcrumbs.stop(dayID: dayID, stopID: stopID)
        let arrival = stop?.arrival ?? Date()
        _arrival = State(initialValue: arrival)
        _departure = State(initialValue: stop?.departure ?? arrival.addingTimeInterval(15 * 60))
        _hasDeparture = State(initialValue: stop?.departure != nil)
        _selectedAccountID = State(initialValue: stop?.accountID)
        _customTitle = State(initialValue: stop?.customTitle ?? "")
        _customAddress = State(initialValue: stop?.accountAddress ?? "")
        _technicianNote = State(initialValue: stop?.technicianNote ?? "")
        _isPersonal = State(initialValue: stop?.isPersonalStop ?? false)
    }

    private var selectedAccount: FireVaultWorkspaceAccount? {
        guard let selectedAccountID else { return nil }
        return store.accounts.first(where: { $0.id == selectedAccountID })
    }

    var body: some View {
        NavigationStack {
            Form {
                visitSection
                classificationSection
                if let account = selectedAccount, !isPersonal {
                    activitySection(account)
                }
                noteSection
                locationSection
                if breadcrumbs.stop(dayID: dayID, stopID: stopID)?.needsReview == true {
                    reviewSection
                }
                deleteSection
            }
            .fireVaultThemedCollection()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showsAccountPicker) {
                FireVaultBreadcrumbAccountPicker(
                    accounts: store.accounts,
                    selectedAccountID: selectedAccountID
                ) { accountID in
                    selectedAccountID = accountID
                    isPersonal = false
                    showsAccountPicker = false
                }
            }
            .confirmationDialog(
                "Disregard This Stop?",
                isPresented: $confirmsDelete,
                titleVisibility: .visible
            ) {
                Button("Disregard Stop", role: .destructive) {
                    breadcrumbs.disregardStop(dayID: dayID, stopID: stopID)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The route remains intact, but this false stop will be removed from the daily log.")
            }
            .sheet(isPresented: $showsGooglePlacesMatches) {
                FireVaultGooglePlacesMatchPicker(matches: googlePlacesMatches) { match in
                    customTitle = match.name
                    customAddress = match.address
                    selectedAccountID = nil
                    isPersonal = false
                    showsGooglePlacesMatches = false
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .alert("Google Places", isPresented: googlePlacesErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(googlePlacesError ?? "Google Places is unavailable right now.")
            }
        }
        .tint(NativeShellPalette.blue)
    }

    private var visitSection: some View {
        Section {
            DatePicker(
                "Arrived",
                selection: $arrival,
                displayedComponents: [.date, .hourAndMinute]
            )
            Toggle("Departure recorded", isOn: $hasDeparture)
            if hasDeparture {
                DatePicker(
                    "Departed",
                    selection: $departure,
                    displayedComponents: [.date, .hourAndMinute]
                )
            } else {
                LabeledContent("Status", value: "Still at this stop")
            }
            LabeledContent(
                "Duration",
                value: previewDuration.fireVaultDuration
            )
        } header: {
            Text("Visit Time")
        } footer: {
            Text("Correct the arrival or departure time when GPS stop detection was early or late.")
        }
    }

    private var classificationSection: some View {
        Section {
            Toggle(isOn: $isPersonal) {
                Label("Personal Stop", systemImage: "person.crop.circle")
            }
            .onChange(of: isPersonal) { _, personal in
                if personal {
                    selectedAccountID = nil
                }
            }

            if isPersonal {
                LabeledContent("Account", value: "Not associated")
            } else {
                if selectedAccount == nil {
                    TextField("Stop title", text: $customTitle)
                        .textInputAutocapitalization(.words)

                    TextField("Address or location description", text: $customAddress)
                        .textInputAutocapitalization(.words)

                    Button {
                        checkGooglePlaces()
                    } label: {
                        if isCheckingGooglePlaces {
                            Label("Checking Google Places…", systemImage: "mappin.and.ellipse")
                        } else {
                            Label("Check Google Places", systemImage: "mappin.and.ellipse")
                        }
                    }
                    .disabled(isCheckingGooglePlaces)

                    Button("Add as New Account", systemImage: "building.2.crop.circle.badge.plus") {
                        createAccountFromStop()
                    }
                    .disabled(normalizedCustomTitle.isEmpty)
                }

                Button {
                    showsAccountPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Label("Account", systemImage: "building.2")
                            .foregroundStyle(.primary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(selectedAccount?.name ?? "Choose Account")
                                .foregroundStyle(
                                    selectedAccount == nil
                                        ? NativeShellPalette.amber
                                        : .secondary
                                )
                                .lineLimit(1)
                            if let accountID = selectedAccount?.accountId, !accountID.isEmpty {
                                Text(accountID)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Account, \(selectedAccount?.name ?? "not assigned")"
                )
                .accessibilityHint("Opens the searchable account directory")
            }
        } header: {
            Text("Stop Classification")
        } footer: {
            Text(
                isPersonal
                    ? "Personal stops remain in the route but are not associated with customer activity."
                    : "Assigning an account turns this detected location into a technician visit."
            )
        }
    }

    private func activitySection(_ account: FireVaultWorkspaceAccount) -> some View {
        Section {
            HStack {
                BreadcrumbActivityCount(
                    title: "NOTES",
                    value: account.notes.count,
                    symbol: "note.text"
                )
                BreadcrumbActivityCount(
                    title: "FILES",
                    value: account.documents.count,
                    symbol: "doc"
                )
                BreadcrumbActivityCount(
                    title: "EQUIPMENT",
                    value: account.equipment.count,
                    symbol: "wrench.and.screwdriver"
                )
            }
            .listRowInsets(.init(top: 12, leading: 8, bottom: 12, trailing: 8))

            Button("Open Account Workspace", systemImage: "arrow.up.right.square") {
                save(openingAccount: account.id)
            }
        } header: {
            Text("Technician Activity")
        } footer: {
            Text("Current records for \(account.name).")
        }
    }

    private var noteSection: some View {
        Section {
            TextField(
                "Reason for visit, work performed, or follow-up needed",
                text: $technicianNote,
                axis: .vertical
            )
            .lineLimit(3...7)
            .textInputAutocapitalization(.sentences)
            .accessibilityLabel("Technician visit note")
        } header: {
            Text("Visit Note")
        } footer: {
            Text("This note belongs to the Trip Log visit and does not create a separate account note.")
        }
    }

    private var locationSection: some View {
        Section("Detected Location") {
            if let stop = breadcrumbs.stop(dayID: dayID, stopID: stopID) {
                LabeledContent("Latitude", value: stop.latitude.formatted(.number.precision(.fractionLength(5))))
                LabeledContent("Longitude", value: stop.longitude.formatted(.number.precision(.fractionLength(5))))
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Disregard False Stop", systemImage: "trash", role: .destructive) {
                confirmsDelete = true
            }
        } footer: {
            Text("Disregarding removes only this detected stop. The recorded route remains intact.")
        }
    }

    private var reviewSection: some View {
        Section {
            Button("Confirm This Stop", systemImage: "checkmark.seal.fill") {
                save()
            }
            .fontWeight(.semibold)
            .foregroundStyle(NativeShellPalette.green)
        } header: {
            Text("Review")
        } footer: {
            Text("Confirm keeps this stop in Trip Log. You can name it now or leave it unassigned for later.")
        }
    }

    private var previewDuration: TimeInterval {
        guard hasDeparture else {
            guard let day = breadcrumbs.days.first(where: { $0.id == dayID }),
                  let stop = day.stops.first(where: { $0.id == stopID }) else {
                return max(0, Date().timeIntervalSince(arrival))
            }
            return day.stopDuration(for: stop)
        }
        return max(0, departure.timeIntervalSince(arrival))
    }

    private var normalizedCustomTitle: String {
        customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var googlePlacesErrorBinding: Binding<Bool> {
        Binding(
            get: { googlePlacesError != nil },
            set: { presented in
                if !presented { googlePlacesError = nil }
            }
        )
    }

    private func checkGooglePlaces() {
        guard !isCheckingGooglePlaces,
              let stop = breadcrumbs.stop(dayID: dayID, stopID: stopID) else {
            return
        }
        isCheckingGooglePlaces = true
        googlePlacesError = nil

        Task {
            do {
                let matches = try await FireVaultGooglePlacesService.shared.matches(
                    latitude: stop.latitude,
                    longitude: stop.longitude
                )
                await MainActor.run {
                    googlePlacesMatches = matches
                    isCheckingGooglePlaces = false
                    showsGooglePlacesMatches = true
                }
            } catch {
                await MainActor.run {
                    isCheckingGooglePlaces = false
                    googlePlacesError = error.localizedDescription
                }
            }
        }
    }

    private func createAccountFromStop() {
        guard !normalizedCustomTitle.isEmpty,
              let stop = breadcrumbs.stop(dayID: dayID, stopID: stopID) else {
            return
        }
        let account = store.addAccount(
            from: stop,
            name: normalizedCustomTitle,
            address: customAddress
        )
        selectedAccountID = account.id
        isPersonal = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func save(openingAccount accountID: String? = nil) {
        breadcrumbs.updateStop(
            dayID: dayID,
            stopID: stopID,
            arrival: arrival,
            departure: hasDeparture ? departure : nil,
            account: isPersonal ? nil : selectedAccount,
            customTitle: isPersonal || selectedAccount != nil ? "" : normalizedCustomTitle,
            customAddress: isPersonal || selectedAccount != nil ? "" : customAddress,
            technicianNote: technicianNote,
            isPersonal: isPersonal
        )

        if let accountID {
            openAccount(accountID)
        } else {
            dismiss()
        }
    }
}

private struct FireVaultGooglePlacesMatchPicker: View {
    let matches: [FireVaultGooglePlaceMatch]
    let select: (FireVaultGooglePlaceMatch) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(matches) { match in
                Button {
                    select(match)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "building.2.crop.circle")
                            .font(.title2)
                            .foregroundStyle(NativeShellPalette.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(match.name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(match.address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(match.distanceText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NativeShellPalette.amber)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Uses this place for the stop name and address")
            }
            .navigationTitle("Nearby Google Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(NativeShellPalette.blue)
    }
}

private struct FireVaultBreadcrumbAccountPicker: View {
    let accounts: [FireVaultWorkspaceAccount]
    let selectedAccountID: String?
    let select: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    private let plusCodeSearchIsEnabled = FireVaultNativeSettingsStore().preferences.plusCodes.searchable

    private var filteredAccounts: [FireVaultWorkspaceAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return accounts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return accounts
            .filter { account in
                [
                    account.name,
                    account.address,
                    account.accountId,
                    account.category,
                    plusCodeSearchIsEnabled ? account.locations.map(\.plusCode).joined(separator: " ") : ""
                ]
                .contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    select(nil)
                } label: {
                    accountRow(
                        title: "Leave Unassigned",
                        subtitle: "Review this stop later",
                        symbol: "questionmark.circle",
                        isSelected: selectedAccountID == nil
                    )
                }
                .buttonStyle(.plain)

                ForEach(filteredAccounts) { account in
                    Button {
                        select(account.id)
                    } label: {
                        accountRow(
                            title: account.name,
                            subtitle: accountPickerSubtitle(account),
                            symbol: "building.2",
                            isSelected: selectedAccountID == account.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .fireVaultThemedCollection()
            .searchable(text: $searchText, prompt: "Name, address, ID, or category")
            .navigationTitle("Choose Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if !searchText.isEmpty && filteredAccounts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .tint(NativeShellPalette.blue)
    }

    private func accountRow(
        title: String,
        subtitle: String,
        symbol: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(isSelected ? NativeShellPalette.blue : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NativeShellPalette.blue)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accountPickerSubtitle(_ account: FireVaultWorkspaceAccount) -> String {
        [account.address, account.accountId, account.category]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private struct BreadcrumbActivityCount: View {
    let title: String
    let value: Int
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(NativeShellPalette.blue)
            Text(value, format: .number)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct BreadcrumbMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BreadcrumbTimelineRow: View {
    let time: Date
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    var showsDisclosure = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 24)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private extension JSONEncoder {
    static var fireVaultBreadcrumbs: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var fireVaultBreadcrumbs: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Double {
    var fireVaultMiles: String {
        let miles = self / 1_609.344
        return "\(miles.formatted(.number.precision(.fractionLength(miles < 10 ? 1 : 0)))) mi"
    }
}

private extension TimeInterval {
    var fireVaultDuration: String {
        let totalMinutes = max(0, Int(self / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

extension CLLocationCoordinate2D {
    var fireVaultCoordinateLabel: String {
        "\(latitude.formatted(.number.precision(.fractionLength(3)))), \(longitude.formatted(.number.precision(.fractionLength(3))))"
    }
}
