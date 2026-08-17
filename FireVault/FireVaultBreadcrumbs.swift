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
    var accountCategory: String? = nil
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
        accountCategory = account?.category
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
        accountCategory = nil
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
    var name: String? = nil
    var startedAt: Date
    var endedAt: Date?
    var isPaused = false
    var points: [FireVaultBreadcrumbPoint] = []
    var stops: [FireVaultBreadcrumbStop] = []
    var reportEndpoints: FireVaultTripReportEndpoints? = nil

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

    /// Combines completed recordings from one calendar day without changing
    /// the persisted schema. The earliest trip ID is retained so links to the
    /// first recording continue to resolve after the merge.
    static func mergedDay(
        _ source: [FireVaultBreadcrumbDay],
        calendar: Calendar = .autoupdatingCurrent
    ) -> FireVaultBreadcrumbDay? {
        let trips = source.sorted { $0.startedAt < $1.startedAt }
        guard trips.count >= 2,
              trips.allSatisfy({ !$0.isActive }),
              let first = trips.first,
              trips.allSatisfy({ calendar.isDate($0.startedAt, inSameDayAs: first.startedAt) }) else {
            return nil
        }

        var seenPointIDs = Set<UUID>()
        let points = trips
            .flatMap(\.points)
            .filter { seenPointIDs.insert($0.id).inserted }
            .sorted { $0.timestamp < $1.timestamp }

        var seenStopIDs = Set<UUID>()
        let closedStops = trips.flatMap { trip in
            trip.stops.map { stop in
                var closed = stop
                closed.departure = trip.effectiveDeparture(for: stop, asOf: trip.endedAt ?? stop.arrival)
                return closed
            }
        }
        .filter { seenStopIDs.insert($0.id).inserted }
        .sorted { $0.arrival < $1.arrival }

        var stops: [FireVaultBreadcrumbStop] = []
        for stop in closedStops {
            guard var previous = stops.last,
                  shouldCoalesce(previous, stop) else {
                stops.append(stop)
                continue
            }
            previous.arrival = min(previous.arrival, stop.arrival)
            previous.departure = [previous.departure, stop.departure]
                .compactMap { $0 }
                .max()
            previous.accountID = previous.accountID ?? stop.accountID
            previous.accountName = previous.accountName ?? stop.accountName
            previous.accountAddress = previous.accountAddress ?? stop.accountAddress
            previous.accountCategory = previous.accountCategory ?? stop.accountCategory
            previous.customTitle = previous.customTitle ?? stop.customTitle
            previous.reviewedAt = [previous.reviewedAt, stop.reviewedAt]
                .compactMap { $0 }
                .max()
            let notes = [previous.technicianNote, stop.technicianNote]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            previous.technicianNote = Array(Set(notes)).sorted().joined(separator: " • ")
            if previous.technicianNote?.isEmpty == true { previous.technicianNote = nil }
            stops[stops.count - 1] = previous
        }

        let savedNames = trips
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let mergedName: String
        if Set(savedNames).count == 1, let name = savedNames.first {
            mergedName = name
        } else if !savedNames.isEmpty {
            mergedName = String(savedNames.joined(separator: " + ").prefix(80))
        } else {
            mergedName = "Merged Trip"
        }

        return normalizeDay(
            .init(
                id: first.id,
                name: mergedName,
                startedAt: trips.map(\.startedAt).min() ?? first.startedAt,
                endedAt: trips.compactMap(\.endedAt).max(),
                isPaused: false,
                points: points,
                stops: stops
            )
        )
    }

    private static func shouldCoalesce(
        _ first: FireVaultBreadcrumbStop,
        _ second: FireVaultBreadcrumbStop
    ) -> Bool {
        let distance = CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: second.latitude, longitude: second.longitude))
        let firstDeparture = first.departure ?? first.arrival
        let gap = second.arrival.timeIntervalSince(firstDeparture)
        guard gap <= 15 * 60, distance <= FireVaultBreadcrumbRules.stopRadius else { return false }

        let sameAccount = first.accountID?.isEmpty == false && first.accountID == second.accountID
        let samePersonalStop = first.isPersonalStop && second.isPersonalStop
        let firstLabel = (first.accountName ?? first.customTitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let secondLabel = (second.accountName ?? second.customTitle ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let sameNamedPlace = !firstLabel.isEmpty && firstLabel == secondLabel
        let bothUnrecognized = firstLabel.isEmpty
            && secondLabel.isEmpty
            && !first.isPersonalStop
            && !second.isPersonalStop
            && distance <= 35
        return sameAccount || samePersonalStop || sameNamedPlace || bothUnrecognized
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
    // Keep live telemetry visible while GPS is still converging. Route and
    // stop persistence continue to use the stricter 100-meter threshold.
    static let maximumLiveHorizontalAccuracy: CLLocationAccuracy = 500
    static let minimumPointDistance: CLLocationDistance = 12
    static let maximumPointInterval: TimeInterval = 30
    static let stopEvaluationInterval: TimeInterval = 10
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
    static let maximumLiveTelemetryAge: TimeInterval = 60
    // Route and stop processing may receive a short delayed batch after iOS
    // wakes the app. Preserve that history without allowing an old sample to
    // drive live telemetry or reset the receiver watchdog.
    static let maximumRouteLocationAge: TimeInterval = 15 * 60
    static let maximumDerivedStationarySpeed: CLLocationSpeed = 1.5
    static let maximumFutureLocationSkew: TimeInterval = 5
    // An active automotive-navigation session normally delivers fixes every
    // few seconds. Recover promptly when that usable stream goes silent rather
    // than leaving every FireVault surface frozen for one or two minutes.
    static let maximumLocationSilenceBeforeRecovery: TimeInterval = 15
    static let minimumLocationRecoverySpacing: TimeInterval = 15

    static func isUsableLiveLocation(
        _ location: CLLocation,
        now: Date = Date(),
        maximumAge: TimeInterval = maximumLiveTelemetryAge
    ) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumLiveHorizontalAccuracy
            && CLLocationCoordinate2DIsValid(location.coordinate)
            && age >= -maximumFutureLocationSkew
            && age <= maximumAge
    }

    static func newestLocation(_ first: CLLocation?, _ second: CLLocation?) -> CLLocation? {
        switch (first, second) {
        case let (first?, second?):
            return first.timestamp >= second.timestamp ? first : second
        case let (first?, nil):
            return first
        case let (nil, second?):
            return second
        case (nil, nil):
            return nil
        }
    }

    static func shouldAcceptLiveTelemetry(
        _ candidate: CLLocation,
        after previous: CLLocation?,
        now: Date = Date()
    ) -> Bool {
        guard isUsableLiveLocation(
            candidate,
            now: now,
            maximumAge: maximumLiveSpeedAge
        ) else { return false }
        guard let previous else { return true }
        return candidate.timestamp > previous.timestamp
    }

    static func shouldAcceptNavigationTelemetry(
        _ candidate: CLLocation,
        after previous: CLLocation?,
        now: Date = Date()
    ) -> Bool {
        // Speed, heading, altitude, CarPlay, and Diagnostics should become
        // responsive while GPS is still converging. Route and stop storage
        // remain protected by the stricter 100-meter checks in
        // `shouldAcceptRouteLocation`, `accepts`, and `shouldEvaluateStop`.
        candidate.horizontalAccuracy >= 0
            && candidate.horizontalAccuracy <= maximumLiveHorizontalAccuracy
            && shouldAcceptLiveTelemetry(candidate, after: previous, now: now)
    }

    static func hasNavigationQualityAccuracy(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= maximumHorizontalAccuracy
    }

    static func shouldAcceptRouteLocation(
        _ candidate: CLLocation,
        after previousTimestamp: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isUsableLiveLocation(
            candidate,
            now: now,
            maximumAge: maximumRouteLocationAge
        ),
        candidate.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return false
        }
        guard let previousTimestamp else { return true }
        return candidate.timestamp > previousTimestamp
    }

    static func normalizedVisit(
        arrival: Date,
        departure: Date?
    ) -> (arrival: Date, departure: Date?) {
        guard let departure else { return (arrival, nil) }
        return (arrival, max(arrival, departure))
    }

    static func accepts(
        _ location: CLLocation,
        after previous: CLLocation?,
        now: Date = Date()
    ) -> Bool {
        guard isUsableLiveLocation(
            location,
            now: now,
            maximumAge: maximumRouteLocationAge
        ),
              location.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return false
        }
        guard let previous else { return true }
        return location.distance(from: previous) >= minimumPointDistance
            || location.timestamp.timeIntervalSince(previous.timestamp) >= maximumPointInterval
    }

    static func shouldEvaluateStop(
        _ location: CLLocation,
        after previous: CLLocation?,
        now: Date = Date()
    ) -> Bool {
        guard isUsableLiveLocation(
            location,
            now: now,
            maximumAge: maximumRouteLocationAge
        ),
              location.horizontalAccuracy <= maximumHorizontalAccuracy else { return false }
        guard let previous else { return true }
        let interval = location.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0 else { return false }
        return location.distance(from: previous) >= minimumPointDistance
            || interval >= stopEvaluationInterval
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
        now: Date = Date()
    ) -> CLLocationSpeed? {
        guard let location else { return nil }
        let locationAge = now.timeIntervalSince(location.timestamp)
        guard locationAge >= -maximumFutureLocationSkew,
              locationAge <= maximumLiveSpeedAge else {
            return 0
        }
        // A negative Core Location speed means unavailable, not stationary.
        // Never turn an unknown reading into a false 0 mph value.
        guard location.speed >= 0 else { return nil }
        // Core Location already fuses GPS, Wi-Fi, cellular, and motion data
        // into CLLocation.speed. Requiring a second coordinate-displacement
        // proof delayed valid speed after launch and after every stop. Trust a
        // fresh nonnegative speed; freshness still forces a frozen reading to
        // zero when callbacks stop.
        return location.speed
    }

    static func updatedMeaningfulMovementDate(
        for location: CLLocation,
        reference: CLLocation?,
        previousMeaningfulMovementAt: Date?,
        now: Date = Date()
    ) -> Date? {
        guard isUsableLiveLocation(location, now: now),
              location.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return previousMeaningfulMovementAt
        }
        guard let reference,
              reference.horizontalAccuracy >= 0,
              reference.horizontalAccuracy <= maximumHorizontalAccuracy,
              CLLocationCoordinate2DIsValid(reference.coordinate) else {
            return previousMeaningfulMovementAt
        }

        let interval = location.timestamp.timeIntervalSince(reference.timestamp)
        guard interval > 0 else { return previousMeaningfulMovementAt }
        let distance = location.distance(from: reference)
        let derivedSpeed = distance / interval
        let uncertaintyFloor = min(
            20,
            max(location.horizontalAccuracy, reference.horizontalAccuracy)
        )
        guard distance >= max(minimumPointDistance, uncertaintyFloor),
              derivedSpeed > maximumDerivedStationarySpeed else {
            return previousMeaningfulMovementAt
        }
        return location.timestamp
    }

    static func shouldRecoverLocationStream(
        trackingStartedAt: Date?,
        lastLocationReceivedAt: Date?,
        lastRecoveryAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let baseline = lastLocationReceivedAt ?? trackingStartedAt,
              now.timeIntervalSince(baseline) >= maximumLocationSilenceBeforeRecovery else {
            return false
        }
        guard let lastRecoveryAt else { return true }
        return now.timeIntervalSince(lastRecoveryAt) >= minimumLocationRecoverySpacing
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

        // An 85-meter jump is not convincing departure evidence when the
        // reported fixes themselves may be tens of meters uncertain. Require
        // the complete departure cluster to clear an accuracy-aware buffer so
        // ordinary parking-lot or indoor GPS drift cannot erase a valid dwell.
        let maximumSampleAccuracy = samples
            .map(\.horizontalAccuracy)
            .filter { $0 >= 0 }
            .max() ?? 0
        let departureUncertainty = min(80, max(30, maximumSampleAccuracy))
        let requiredExitDistance = stopRadius + departureUncertainty

        return nextLocation.distance(from: stopLocation) > requiredExitDistance
            && samples.allSatisfy {
                $0.distance(from: stopLocation) > requiredExitDistance
            }
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

enum FireVaultLiveSpeedSource: String, Equatable {
    case coreLocation
    case derived
    case stationary
    case stale
    case unavailable
}

struct FireVaultLiveSpeedSnapshot: Equatable {
    static let unavailable = FireVaultLiveSpeedSnapshot(
        metersPerSecond: nil,
        source: .unavailable,
        sampleTimestamp: nil,
        receivedAt: nil,
        rawMetersPerSecond: nil,
        derivedMetersPerSecond: nil
    )

    let metersPerSecond: CLLocationSpeed?
    let source: FireVaultLiveSpeedSource
    let sampleTimestamp: Date?
    let receivedAt: Date?
    let rawMetersPerSecond: CLLocationSpeed?
    let derivedMetersPerSecond: CLLocationSpeed?
}

/// Converts Core Location fixes into one live speed value shared by the app,
/// CarPlay, and GPS Diagnostics. Route-point persistence and stop detection
/// intentionally do not participate in this reducer.
struct FireVaultLiveSpeedReducer {
    private static let maximumDerivedSpeed: CLLocationSpeed = 80
    private static let maximumDerivedInterval: TimeInterval = 10
    private static let minimumDerivedInterval: TimeInterval = 1
    private static let stationaryDerivedSpeed: CLLocationSpeed = 0.8
    private static let movingDerivedSpeed: CLLocationSpeed = 1.5
    private static let minimumMovingDistance: CLLocationDistance = 5
    private static let requiredStationaryPairs = 2
    private static let requiredStationaryDuration: TimeInterval = 3

    private var previousReliableFix: CLLocation?
    private var stationaryPairCount = 0
    private var stationaryEvidenceDuration: TimeInterval = 0
    private(set) var snapshot = FireVaultLiveSpeedSnapshot.unavailable

    mutating func ingest(
        _ location: CLLocation,
        receivedAt: Date = Date()
    ) -> FireVaultLiveSpeedSnapshot {
        guard FireVaultBreadcrumbRules.isUsableLiveLocation(
            location,
            now: receivedAt,
            maximumAge: FireVaultBreadcrumbRules.maximumLocationSilenceBeforeRecovery
        ) else {
            return snapshot
        }

        let rawSpeed = location.speed >= 0 ? location.speed : nil
        var derivedSpeed: CLLocationSpeed?
        var comparablePair = false
        var pairIsMoving = false
        var pairIsStationary = false
        var conservativeDisplacementProvesMovement = false
        var pairDuration: TimeInterval = 0

        let hasReliableCoordinate = location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= FireVaultBreadcrumbRules.maximumHorizontalAccuracy
        if hasReliableCoordinate, let previousReliableFix {
            let interval = location.timestamp.timeIntervalSince(previousReliableFix.timestamp)
            if interval > 0 {
                let distance = location.distance(from: previousReliableFix)
                let uncertainty = min(
                    20,
                    max(location.horizontalAccuracy, previousReliableFix.horizontalAccuracy)
                )
                let effectiveDistance = max(
                    0,
                    distance - uncertainty
                )
                let candidate = effectiveDistance / interval
                // Releasing a stale/stationary latch must be more conservative
                // than ordinary short-interval speed derivation. Subtract the
                // full reported uncertainty so a 30–100 m accuracy cloud
                // cannot revive a frozen positive MPH reading while parked.
                let conservativeEffectiveDistance = max(
                    0,
                    distance - max(
                        location.horizontalAccuracy,
                        previousReliableFix.horizontalAccuracy
                    )
                )
                conservativeDisplacementProvesMovement =
                    conservativeEffectiveDistance >= Self.minimumMovingDistance
                    && conservativeEffectiveDistance / interval > Self.stationaryDerivedSpeed
                if interval >= Self.minimumDerivedInterval,
                   interval <= Self.maximumDerivedInterval,
                   candidate <= Self.maximumDerivedSpeed {
                    comparablePair = true
                    pairDuration = interval
                    derivedSpeed = candidate
                    pairIsMoving = candidate > Self.movingDerivedSpeed
                        && effectiveDistance >= Self.minimumMovingDistance
                    pairIsStationary = candidate <= Self.stationaryDerivedSpeed
                }
            }
        }

        let wasKnownStationary = snapshot.metersPerSecond == 0
        let previousRawWasStationary = snapshot.rawMetersPerSecond.map {
            $0 <= FireVaultBreadcrumbRules.maximumStationarySpeed
        } == true
        let rawShowsDeparture = (rawSpeed ?? 0) > FireVaultBreadcrumbRules.maximumStationarySpeed
            && wasKnownStationary
            && previousRawWasStationary
        let sparseCoordinateDeparture = wasKnownStationary
            && conservativeDisplacementProvesMovement
            && (rawSpeed ?? 0) > FireVaultBreadcrumbRules.maximumStationarySpeed
        let movementIsConfirmed = pairIsMoving
            || rawShowsDeparture
            || sparseCoordinateDeparture

        if movementIsConfirmed {
            stationaryPairCount = 0
            stationaryEvidenceDuration = 0
        } else if pairIsStationary {
            stationaryPairCount += 1
            stationaryEvidenceDuration += pairDuration
        } else if rawSpeed.map({ $0 > FireVaultBreadcrumbRules.maximumStationarySpeed }) == true,
                  !comparablePair,
                  !wasKnownStationary {
            // A first moving fix after launch or a signal gap must display
            // immediately. Do not carry an old stationary latch across it.
            // Once stationary was proven against a frozen positive sensor,
            // however, an expired coordinate anchor must not resurrect that
            // same stale speed. Movement coordinates will release the latch.
            stationaryPairCount = 0
            stationaryEvidenceDuration = 0
        }

        let stationaryIsConfirmed = stationaryPairCount >= Self.requiredStationaryPairs
            && stationaryEvidenceDuration >= Self.requiredStationaryDuration

        let resolvedSpeed: CLLocationSpeed?
        let source: FireVaultLiveSpeedSource
        if stationaryIsConfirmed, !movementIsConfirmed {
            resolvedSpeed = 0
            source = .stationary
        } else if pairIsMoving,
                  let derivedSpeed,
                  rawSpeed.map({ $0 <= FireVaultBreadcrumbRules.maximumStationarySpeed }) ?? true {
            // Core Location can briefly retain 0 after departure. Clear
            // coordinate movement must also beat a stale low-positive value so
            // every surface resumes promptly.
            resolvedSpeed = derivedSpeed
            source = .derived
        } else if let rawSpeed, rawSpeed > 0 {
            resolvedSpeed = rawSpeed
            source = .coreLocation
        } else if rawSpeed == 0 {
            resolvedSpeed = 0
            source = .stationary
        } else {
            resolvedSpeed = nil
            source = .unavailable
        }

        snapshot = FireVaultLiveSpeedSnapshot(
            metersPerSecond: resolvedSpeed,
            source: source,
            sampleTimestamp: location.timestamp,
            receivedAt: receivedAt,
            rawMetersPerSecond: rawSpeed,
            derivedMetersPerSecond: derivedSpeed
        )
        if hasReliableCoordinate {
            if let previousReliableFix {
                let interval = location.timestamp.timeIntervalSince(previousReliableFix.timestamp)
                // Retain the anchor while raw speed is zero/unavailable and no
                // movement is proven. This lets departure displacement build
                // across several small or sub-second fixes instead of resetting
                // the evidence on every callback.
                if movementIsConfirmed
                    || interval > Self.maximumDerivedInterval {
                    self.previousReliableFix = location
                }
            } else {
                previousReliableFix = location
            }
        }
        return snapshot
    }

    mutating func markStationary(at date: Date = Date()) -> FireVaultLiveSpeedSnapshot {
        stationaryPairCount = Self.requiredStationaryPairs
        stationaryEvidenceDuration = Self.requiredStationaryDuration
        snapshot = FireVaultLiveSpeedSnapshot(
            metersPerSecond: 0,
            source: .stationary,
            sampleTimestamp: snapshot.sampleTimestamp ?? date,
            receivedAt: date,
            rawMetersPerSecond: snapshot.rawMetersPerSecond,
            derivedMetersPerSecond: 0
        )
        return snapshot
    }

    mutating func refresh(at now: Date = Date()) -> FireVaultLiveSpeedSnapshot {
        guard let sampleTimestamp = snapshot.sampleTimestamp,
              snapshot.metersPerSecond != nil,
              now.timeIntervalSince(sampleTimestamp)
                > FireVaultBreadcrumbRules.maximumLiveSpeedAge,
              snapshot.source != .stale else {
            return snapshot
        }
        // Latch the stale reading at zero. A later callback that repeats the
        // old positive sensor speed at the same coordinate must not resurrect
        // a phantom MPH value; coordinate movement will release this latch.
        stationaryPairCount = Self.requiredStationaryPairs
        stationaryEvidenceDuration = Self.requiredStationaryDuration
        snapshot = FireVaultLiveSpeedSnapshot(
            metersPerSecond: 0,
            source: .stale,
            sampleTimestamp: sampleTimestamp,
            receivedAt: snapshot.receivedAt,
            rawMetersPerSecond: snapshot.rawMetersPerSecond,
            derivedMetersPerSecond: snapshot.derivedMetersPerSecond
        )
        return snapshot
    }

    mutating func reset() {
        previousReliableFix = nil
        stationaryPairCount = 0
        stationaryEvidenceDuration = 0
        snapshot = .unavailable
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
    @Published private(set) var liveSpeedSnapshot = FireVaultLiveSpeedSnapshot.unavailable
    @Published private(set) var lastMeaningfulMovementAt: Date?
    /// Time Core Location most recently invoked the delegate, whether or not
    /// the payload was current and accurate enough for FireVault to use.
    @Published private(set) var lastLocationCallbackAt: Date?
    /// Time FireVault most recently accepted a fresh live-telemetry fix. This
    /// can be a temporarily coarse fix while GPS is converging.
    @Published private(set) var lastLocationReceivedAt: Date?
    /// Time FireVault most recently accepted a navigation-quality fix.
    @Published private(set) var lastNavigationLocationReceivedAt: Date?
    @Published private(set) var lastLocationRecoveryAt: Date?
    @Published private(set) var locationRecoveryCount = 0
    @Published private(set) var locationProviderText = "Inactive"
    @Published private(set) var locationProviderDiagnostic = "Waiting to start"

    private let manager: CLLocationManager
    private let archiveURL: URL
    private let liveActivitiesEnabled: Bool
    private var accounts: [FireVaultWorkspaceAccount] = []
    private var accountsAreLoaded = false
    private var deferredControlCommand: FireVaultTripLogControlCommand?
    private var candidateLocations: [CLLocation] = []
    private var departureCandidateLocations: [CLLocation] = []
    private var disregardedStopCoordinate: CLLocationCoordinate2D?
    private var disregardedDepartureLocations: [CLLocation] = []
    private var activeStopID: UUID?
    private var sessionIsPrepared = false
    private var liveActivityControlObservation: AnyCancellable?
    private var gpsPreferences: FireVaultGPSPreferences
    private var notificationPreferences: FireVaultNotificationPreferences
    private var speedReferenceLocation: CLLocation?
    private var liveSpeedReducer = FireVaultLiveSpeedReducer()
    private var lastStopEvaluationLocation: CLLocation?
    private var lastRouteInputTimestamp: Date?
    private var trackingStartedAt: Date?
    private var locationWatchdogTask: Task<Void, Never>?
    private var liveUpdateTask: Task<Void, Never>?
    private var consecutiveLocationRecoveryCount = 0
    private var legacyFallbackIsActive = false
    private var lastModernUpdateAt: Date?
    private var modernNavigationFixStreak = 0
    private var systemReportedStationary = false
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var serviceSession: CLServiceSession?
    private var pendingRoutePersistenceTask: Task<Void, Never>?

    private static let routePersistenceInterval: TimeInterval = 5

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

    var liveSpeedMetersPerSecond: CLLocationSpeed? {
        liveSpeedSnapshot.metersPerSecond
    }

    /// Read-only receiver state used by the GPS Diagnostics console. These
    /// values describe FireVault's active Core Location pipeline; they are not
    /// estimates of satellite count or radio signal strength.
    var diagnosticsSystemStationary: Bool { systemReportedStationary }
    var diagnosticsLegacyFallbackActive: Bool { legacyFallbackIsActive }
    var diagnosticsModernStreamActive: Bool { liveUpdateTask != nil }
    var diagnosticsBackgroundSessionActive: Bool { backgroundActivitySession != nil }
    var diagnosticsServiceSessionActive: Bool { serviceSession != nil }

    func requestDiagnosticsReceiverCheck() {
        guard isRecording else { return }
        recoverLocationStream(force: true)
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
        manager.pausesLocationUpdatesAutomatically = false

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
        accountsAreLoaded = true
        refreshRuntimePreferences()
        sessionIsPrepared = true
        if activeDay == nil {
            days.insert(.init(startedAt: Date()), at: 0)
            persist()
        } else {
            updateActiveDay { $0.isPaused = false }
        }
        beginLocationUpdates()
        FireVaultNotificationService.shared.tripLogStarted(preferences: notificationPreferences)
    }

    func resumeWorkday(accounts: [FireVaultWorkspaceAccount]) {
        guard activeDay != nil else {
            startWorkday(accounts: accounts)
            return
        }
        self.accounts = accounts
        accountsAreLoaded = true
        refreshRuntimePreferences()
        sessionIsPrepared = true
        updateActiveDay { $0.isPaused = false }
        beginLocationUpdates()
        FireVaultNotificationService.shared.tripLogStarted(preferences: notificationPreferences)
    }

    func restoreActiveWorkday(accounts: [FireVaultWorkspaceAccount]) {
        self.accounts = accounts
        accountsAreLoaded = true
        restoreActiveReceiver()
    }

    func attachAccountsToActiveReceiver(_ accounts: [FireVaultWorkspaceAccount]) {
        self.accounts = accounts
        accountsAreLoaded = true
        refreshRuntimePreferences()
        consumeLiveActivityControl()
    }

    /// Reinstates location interest before account storage is loaded. This is
    /// intentionally lightweight so a background relaunch can recreate its
    /// Core Location sessions before iOS suspends the process again.
    func restoreActiveReceiver() {
        refreshRuntimePreferences()
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization

        // Recreate any open-stop/candidate state before consuming an End
        // command from a widget or Live Activity. A cold launch otherwise had
        // no in-memory stop ID and could finish the trip without closing its
        // final persisted stop.
        if activeDay != nil {
            restoreTrackingContext()
        }
        // A Live Activity/widget intent can run outside the main app process.
        // Consume its durable App Group command every time the app becomes
        // active, not only once when this singleton is initialized.
        consumeLiveActivityControl()
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
        sessionIsPrepared = true
        if isRecording {
            rearmActiveLocationReceiverIfNeeded()
            return
        }
        beginLocationUpdates()
    }

    func endWorkday() {
        guard let index = activeDayIndex else { return }
        let end = Date()
        finalizeStopIfNeeded(in: index, at: end)
        days[index].endedAt = end
        days[index].isPaused = false
        stopLocationUpdates()
        candidateLocations.removeAll()
        departureCandidateLocations.removeAll()
        disregardedStopCoordinate = nil
        disregardedDepartureLocations.removeAll()
        activeStopID = nil
        speedReferenceLocation = nil
        lastMeaningfulMovementAt = nil
        lastStopEvaluationLocation = nil
        sessionIsPrepared = false
        statusText = "Workday complete"
        FireVaultNotificationService.shared.tripLogEnded()
        prepareReportData(at: index, accounts: accounts)
        persist()
        let completedDay = days[index]
        if liveActivitiesEnabled {
            FireVaultTripLogLiveActivityController.end(
                day: completedDay,
                showsMetrics: liveActivityPreferences.showsLiveActivityMetrics
            )
        }
        let preferences = FireVaultNativeSettingsStore().preferences
        if liveActivitiesEnabled {
            Task {
                await FireVaultTripLogAutomationService.shared.syncCompletedDay(
                    completedDay,
                    preferences: preferences
                )
            }
        }
    }

    func deleteDay(_ id: UUID) {
        guard days.first(where: { $0.id == id })?.isActive != true else { return }
        days.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    func mergeDays(_ ids: Set<UUID>) -> UUID? {
        let selected = days.filter { ids.contains($0.id) }
        guard selected.count == ids.count,
              var merged = FireVaultTripLogIntegrity.mergedDay(selected) else {
            return nil
        }
        if let endpoints = FireVaultTripEndpointResolver.resolve(
            day: merged,
            accounts: accounts
        ) {
            merged.reportEndpoints = endpoints
        }
        days.removeAll { ids.contains($0.id) }
        days.append(merged)
        days = FireVaultTripLogIntegrity.normalized(days)
        persist()
        return merged.id
    }

    @discardableResult
    func renameDay(_ id: UUID, name: String) -> Bool {
        guard let index = days.firstIndex(where: { $0.id == id }) else { return false }
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        days[index].name = normalized.isEmpty ? nil : String(normalized.prefix(80))
        persist()
        return true
    }

    /// Resolves the saved Start and End labels for every completed trip in the
    /// selected calendar week before a report is created.
    @discardableResult
    func prepareReportDays(
        anchorDayID: UUID,
        accounts: [FireVaultWorkspaceAccount],
        calendar: Calendar = .autoupdatingCurrent
    ) -> [FireVaultBreadcrumbDay] {
        guard let anchor = days.first(where: { $0.id == anchorDayID }) else { return days }
        self.accounts = accounts
        accountsAreLoaded = true
        let interval = calendar.dateInterval(of: .weekOfYear, for: anchor.startedAt)
        let indices = days.indices.filter { index in
            guard days[index].endedAt != nil else { return false }
            guard let interval else { return days[index].id == anchorDayID }
            return interval.contains(days[index].startedAt)
        }
        var changed = false
        for index in indices {
            changed = prepareReportData(at: index, accounts: accounts) || changed
        }
        if changed { persist() }
        return days
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
        customCategory: String = "",
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
                let category = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                stop.accountCategory = category.isEmpty ? nil : category
            }
            stop.markReviewed()
        }
        days[dayIndex].stops[stopIndex] = stop
        days[dayIndex].stops.sort { $0.arrival < $1.arrival }
        refreshCompletedReportData(at: dayIndex, accounts: accounts)
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
        refreshCompletedReportData(at: dayIndex, accounts: accounts)
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
        let callbackAt = Date()
        lastLocationCallbackAt = callbackAt
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            ingestLocation(location, receivedAt: callbackAt, fromModernStream: false)
        }
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard isRecording else { return }
        locationProviderDiagnostic = "Legacy fallback paused by iOS"
        recoverLocationStream(force: true)
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        guard isRecording else { return }
        statusText = accuracyAuthorization == .fullAccuracy
            ? "Recording today’s route"
            : "Recording with approximate location"
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
            locationProviderDiagnostic = "Legacy fallback error: \(error.localizedDescription)"
            statusText = "Waiting for a reliable GPS position…"
            recoverLocationStream(force: true)
        }
    }

    private func handleLiveUpdate(_ update: CLLocationUpdate) {
        guard isRecording, sessionIsPrepared, activeDay?.isPaused == false else { return }
        let callbackAt = Date()
        lastLocationCallbackAt = callbackAt
        lastModernUpdateAt = callbackAt

        if update.authorizationDenied || update.authorizationDeniedGlobally {
            locationProviderDiagnostic = "Location authorization is denied"
            statusText = "Location access is off for Trip Log"
            return
        }
        if update.authorizationRestricted {
            locationProviderDiagnostic = "Location authorization is restricted"
            statusText = "Location access is restricted"
            return
        }
        if update.serviceSessionRequired {
            locationProviderDiagnostic = "Core Location needs an active service session"
            retainActiveLocationSessions()
        } else if update.insufficientlyInUse {
            locationProviderDiagnostic = "Background location session is not active"
            startLegacyLocationFallback(reason: "background session unavailable")
        } else if update.accuracyLimited {
            locationProviderDiagnostic = "Precise GPS is temporarily limited"
        } else if update.locationUnavailable {
            locationProviderDiagnostic = "GPS position is temporarily unavailable"
        } else {
            locationProviderDiagnostic = "Automotive live updates active"
        }

        if update.stationary {
            systemReportedStationary = true
            liveSpeedSnapshot = liveSpeedReducer.markStationary(at: callbackAt)
            // Apple's automotive stream may intentionally suspend while the
            // vehicle is stationary. Keep the legacy standard service alive as
            // a no-distance-filter fallback so departure is noticed promptly.
            startLegacyLocationFallback(reason: "stationary continuity")
        }

        guard let location = update.location else { return }
        ingestLocation(location, receivedAt: callbackAt, fromModernStream: true)
    }

    private func ingestLocation(
        _ location: CLLocation,
        receivedAt callbackAt: Date,
        fromModernStream: Bool
    ) {
        let routeWasAccepted = FireVaultBreadcrumbRules.shouldAcceptRouteLocation(
            location,
            after: lastRouteInputTimestamp,
            now: callbackAt
        )
        if routeWasAccepted {
            lastRouteInputTimestamp = location.timestamp
            updateMotionEvidence(with: location)
            record(location)
        }

        guard FireVaultBreadcrumbRules.shouldAcceptNavigationTelemetry(
                  location,
                  after: latestLocation,
                  now: callbackAt
              ) else {
            if fromModernStream {
                modernNavigationFixStreak = 0
            }
            if !routeWasAccepted {
                rejectedLocationCount += 1
            }
            // Delayed route batches and coarse network fixes must never replace
            // live telemetry or make the GPS watchdog appear healthy.
            return
        }

        lastLocationReceivedAt = location.timestamp
        liveSpeedSnapshot = liveSpeedReducer.ingest(location, receivedAt: callbackAt)
        let navigationQualityAccepted = FireVaultBreadcrumbRules
            .hasNavigationQualityAccuracy(location)
        if navigationQualityAccepted {
            lastNavigationLocationReceivedAt = location.timestamp
            consecutiveLocationRecoveryCount = 0
            if fromModernStream {
                modernNavigationFixStreak += 1
            }
        } else if fromModernStream {
            // Coarse fixes may feed the visible speed/heading/elevation while
            // GPS converges, but they must not silence the recovery watchdog
            // or retire the high-accuracy continuity receiver.
            modernNavigationFixStreak = 0
        }

        if let speed = liveSpeedSnapshot.metersPerSecond,
           speed > FireVaultBreadcrumbRules.maximumStationarySpeed {
            systemReportedStationary = false
        } else if liveSpeedSnapshot.source == .stationary {
            systemReportedStationary = true
        }

        if fromModernStream {
            locationProviderText = legacyFallbackIsActive
                ? "Automotive + fallback"
                : "Automotive live"
            if navigationQualityAccepted,
               modernNavigationFixStreak >= 3,
               !systemReportedStationary {
                stopLegacyLocationFallback()
                locationProviderText = "Automotive live"
            }
        } else {
            locationProviderText = "Legacy GPS fallback"
        }

        latestLocation = location
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
        configureActiveLocationManager()
        retainActiveLocationSessions()
        if !isRecording {
            trackingStartedAt = Date()
            lastLocationCallbackAt = nil
            lastLocationReceivedAt = nil
            lastNavigationLocationReceivedAt = nil
            lastLocationRecoveryAt = nil
            lastModernUpdateAt = nil
            lastRouteInputTimestamp = activeDay?.points.last?.timestamp
                ?? activeDay?.startedAt
            consecutiveLocationRecoveryCount = 0
            modernNavigationFixStreak = 0
            systemReportedStationary = false
            liveSpeedReducer.reset()
            liveSpeedSnapshot = .unavailable
        }
        // Durable recording intent must be visible before the asynchronous
        // live-update sequence can deliver its first event.
        isRecording = true
        manager.startMonitoringVisits()
        startModernLocationUpdates()
        // Keep a standard receiver active during acquisition and while parked.
        // This catches departure immediately if the automotive stream is
        // stationary or still warming, then retires after modern movement is
        // established.
        startLegacyLocationFallback(reason: "initial acquisition")
        startLocationWatchdog()
        if accuracyAuthorization == .reducedAccuracy {
            manager.requestTemporaryFullAccuracyAuthorization(
                withPurposeKey: "TripLogPreciseLocation"
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.accuracyAuthorization = self.manager.accuracyAuthorization
                    if self.accuracyAuthorization == .fullAccuracy {
                        self.statusText = "Recording today’s route"
                    }
                }
            }
        }
        statusText = accuracyAuthorization == .fullAccuracy
            ? "Recording today’s route"
            : "Trip Log needs Precise Location for reliable recording"
        synchronizeLiveActivity(status: .recording)
    }

    private func configureActiveLocationManager() {
        // The modern live-update stream is configured for automotive
        // navigation. This manager is the continuity fallback used if that
        // stream is stationary or temporarily unavailable, so use the broader
        // navigation activity type to avoid duplicating an automotive pause.
        manager.activityType = .otherNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // Dwell recognition needs periodic stationary fixes. A positive
        // distance filter can suppress every sample after the vehicle stops,
        // preventing an otherwise valid three- or five-minute visit from ever
        // accumulating confirmation evidence. Route persistence remains
        // throttled separately by `FireVaultBreadcrumbRules.accepts`.
        manager.distanceFilter = kCLDistanceFilterNone
        // Automatic pausing can occur before a three- or five-minute stop has
        // enough samples to be confirmed. Trip Log already throttles persisted
        // points, so keep Core Location active for reliable arrival/departure
        // recognition during an explicitly started workday.
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    private func retainActiveLocationSessions() {
        // Service and background sessions describe the active Trip Log job to
        // modern Core Location. They are required independently of whether
        // the user chose to display a Live Activity.
        if serviceSession == nil {
            serviceSession = CLServiceSession(
                authorization: .whenInUse,
                fullAccuracyPurposeKey: "TripLogPreciseLocation"
            )
        }
        if backgroundActivitySession == nil {
            backgroundActivitySession = CLBackgroundActivitySession()
        }
    }

    private func stopLocationUpdates() {
        locationWatchdogTask?.cancel()
        locationWatchdogTask = nil
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        manager.stopUpdatingLocation()
        manager.stopMonitoringVisits()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        serviceSession?.invalidate()
        serviceSession = nil
        trackingStartedAt = nil
        lastLocationCallbackAt = nil
        lastLocationReceivedAt = nil
        lastNavigationLocationReceivedAt = nil
        lastLocationRecoveryAt = nil
        lastModernUpdateAt = nil
        lastRouteInputTimestamp = nil
        consecutiveLocationRecoveryCount = 0
        legacyFallbackIsActive = false
        modernNavigationFixStreak = 0
        systemReportedStationary = false
        liveSpeedReducer.reset()
        liveSpeedSnapshot = .unavailable
        locationProviderText = "Inactive"
        locationProviderDiagnostic = "Trip Log is not recording"
        isRecording = false
    }

    private func startModernLocationUpdates() {
        guard isRecording, liveUpdateTask == nil else { return }
        locationProviderText = legacyFallbackIsActive
            ? "Automotive + fallback"
            : "Automotive live"
        locationProviderDiagnostic = "Starting automotive live updates…"
        liveUpdateTask = Task { @MainActor [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard !Task.isCancelled, let self else { return }
                    self.handleLiveUpdate(update)
                }
                guard !Task.isCancelled, let self, self.isRecording else { return }
                self.liveUpdateTask = nil
                self.locationProviderDiagnostic = "Automotive stream ended unexpectedly"
                self.startLegacyLocationFallback(reason: "automotive stream ended")
            } catch {
                guard !Task.isCancelled, let self, self.isRecording else { return }
                self.liveUpdateTask = nil
                self.locationProviderDiagnostic = "Automotive stream error: \(error.localizedDescription)"
                self.startLegacyLocationFallback(reason: "automotive stream error")
            }
        }
    }

    private func restartModernLocationUpdates() {
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        lastModernUpdateAt = nil
        modernNavigationFixStreak = 0
        startModernLocationUpdates()
    }

    private func startLegacyLocationFallback(reason: String) {
        guard isRecording, sessionIsPrepared, activeDay?.isPaused == false else { return }
        configureActiveLocationManager()
        if !legacyFallbackIsActive {
            legacyFallbackIsActive = true
            locationProviderText = "Automotive + fallback"
            locationProviderDiagnostic = "Fallback active • \(reason)"
        }
        // Repeating startUpdatingLocation is intentionally idempotent. Do not
        // stop the receiver during ordinary recovery because that discards its
        // warm GPS state and can lengthen reacquisition after a stop.
        manager.startUpdatingLocation()
    }

    private func stopLegacyLocationFallback() {
        guard legacyFallbackIsActive else { return }
        manager.stopUpdatingLocation()
        legacyFallbackIsActive = false
    }

    private func record(_ location: CLLocation) {
        guard let index = activeDayIndex, !days[index].isPaused else { return }
        if FireVaultBreadcrumbRules.shouldEvaluateStop(
            location,
            after: lastStopEvaluationLocation
        ) {
            let previousEvaluation = lastStopEvaluationLocation
            lastStopEvaluationLocation = location
            updateStopDetection(
                with: location,
                previous: previousEvaluation,
                dayIndex: index
            )
        }

        let previous = days[index].points.last?.location
        guard FireVaultBreadcrumbRules.accepts(location, after: previous) else {
            rejectedLocationCount += 1
            return
        }
        acceptedLocationCount += 1

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
        persistRouteProgress()
        synchronizeLiveActivity(status: .recording)
    }

    private func updateMotionEvidence(with location: CLLocation) {
        lastMeaningfulMovementAt = FireVaultBreadcrumbRules.updatedMeaningfulMovementDate(
            for: location,
            reference: speedReferenceLocation,
            previousMeaningfulMovementAt: lastMeaningfulMovementAt,
            now: location.timestamp
        )

        guard let reference = speedReferenceLocation else {
            speedReferenceLocation = location
            return
        }

        let interval = location.timestamp.timeIntervalSince(reference.timestamp)
        if interval >= FireVaultBreadcrumbRules.maximumLiveSpeedAge {
            speedReferenceLocation = location
        }
    }

    private func startLocationWatchdog() {
        guard locationWatchdogTask == nil else { return }
        locationWatchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let self else { return }
                let refreshed = self.liveSpeedReducer.refresh()
                if refreshed != self.liveSpeedSnapshot {
                    self.liveSpeedSnapshot = refreshed
                }
                self.recoverLocationStream(force: false)
            }
        }
    }

    private func recoverLocationStream(force: Bool) {
        guard isRecording, sessionIsPrepared, activeDay?.isPaused == false else { return }
        let now = Date()
        let telemetryIsSilent = FireVaultBreadcrumbRules.shouldRecoverLocationStream(
            trackingStartedAt: trackingStartedAt,
            lastLocationReceivedAt: lastNavigationLocationReceivedAt,
            lastRecoveryAt: lastLocationRecoveryAt,
            now: now
        )
        let modernBaseline = lastModernUpdateAt ?? trackingStartedAt
        let modernIsSilent = modernBaseline.map {
            now.timeIntervalSince($0)
                >= FireVaultBreadcrumbRules.maximumLocationSilenceBeforeRecovery * 2
        } ?? false
        guard force || telemetryIsSilent || (modernIsSilent && !systemReportedStationary) else {
            return
        }

        if let lastLocationRecoveryAt,
           now.timeIntervalSince(lastLocationRecoveryAt)
            < FireVaultBreadcrumbRules.minimumLocationRecoverySpacing {
            return
        }

        lastLocationRecoveryAt = now
        locationRecoveryCount += 1
        consecutiveLocationRecoveryCount += 1
        retainActiveLocationSessions()
        if telemetryIsSilent || force {
            statusText = "GPS signal delayed • continuity receiver active…"
            startLegacyLocationFallback(reason: force ? "receiver paused" : "live fixes delayed")
        }
        if modernIsSilent && !systemReportedStationary {
            locationProviderDiagnostic = "Restarting silent automotive update stream"
            restartModernLocationUpdates()
        } else if liveUpdateTask == nil {
            startModernLocationUpdates()
        }
    }

    private func rearmActiveLocationReceiverIfNeeded() {
        configureActiveLocationManager()
        retainActiveLocationSessions()
        manager.startMonitoringVisits()
        startModernLocationUpdates()
        startLocationWatchdog()

        let now = Date()
        let lastUsableAge = lastNavigationLocationReceivedAt.map { now.timeIntervalSince($0) }
        if lastUsableAge == nil
            || lastUsableAge! >= FireVaultBreadcrumbRules.maximumLocationSilenceBeforeRecovery {
            startLegacyLocationFallback(reason: "restoring active Trip Log")
        }
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

        // CLVisit callbacks can arrive well after a visit ended. Only recover
        // the portion that actually overlaps the current recording so a visit
        // from an earlier trip cannot be attached to (or disrupt) a new one.
        let recordingStart = days[dayIndex].startedAt
        let recordingEnd = min(days[dayIndex].endedAt ?? Date(), Date())
        guard visit.departureDate >= recordingStart,
              visit.arrivalDate <= recordingEnd else { return }
        let arrival = max(visit.arrivalDate, recordingStart)
        let departure = min(visit.departureDate, recordingEnd)

        let account = FireVaultBreadcrumbRules.closestAccount(
            to: visit.coordinate,
            accounts: accounts
        )
        guard FireVaultBreadcrumbRules.confirmsStopDwell(
            arrival: arrival,
            departure: departure,
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
            let overlaps = stop.arrival <= departure
                && (stop.departure ?? Date.distantFuture) >= arrival
            return overlaps
                && stopLocation.distance(from: visitLocation)
                    <= FireVaultBreadcrumbRules.duplicateStopRadius
        }
        guard !alreadyRecorded else { return }

        var recoveredStop = FireVaultBreadcrumbStop(
            arrival: arrival,
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            accountID: account?.id,
            accountName: account?.name,
            accountAddress: account?.address
        )
        recoveredStop.departure = departure
        days[dayIndex].stops.append(recoveredStop)
        days[dayIndex].stops.sort { $0.arrival < $1.arrival }
        notifyConfirmedStop(recoveredStop)
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
            accountAddress: account?.address,
            accountCategory: account?.category
        )
        activeStopID = stop.id
        days[dayIndex].stops.append(stop)
        notifyConfirmedStop(stop)
    }

    private func notifyConfirmedStop(_ stop: FireVaultBreadcrumbStop) {
        if stop.accountID != nil {
            FireVaultNotificationService.shared.accountArrivalDetected(
                stop: stop,
                preferences: notificationPreferences
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

        // Defensive cold-launch path: a persisted open stop is authoritative
        // even if its in-memory activeStopID has not yet been rebuilt.
        if let stopIndex = days[dayIndex].stops.lastIndex(where: { $0.departure == nil }) {
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

    private func updateActiveDay(_ change: (inout FireVaultBreadcrumbDay) -> Void) {
        guard let index = activeDayIndex else { return }
        change(&days[index])
        persist()
    }

    @discardableResult
    private func prepareReportData(
        at dayIndex: Int,
        accounts: [FireVaultWorkspaceAccount]
    ) -> Bool {
        guard days.indices.contains(dayIndex), days[dayIndex].endedAt != nil else { return false }
        var changed = false
        for stopIndex in days[dayIndex].stops.indices {
            guard days[dayIndex].stops[stopIndex].accountCategory == nil,
                  let accountID = days[dayIndex].stops[stopIndex].accountID,
                  let category = accounts.first(where: { $0.id == accountID })?.category
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !category.isEmpty else { continue }
            days[dayIndex].stops[stopIndex].accountCategory = category
            changed = true
        }
        if days[dayIndex].reportEndpoints == nil || changed {
            if let endpoints = FireVaultTripEndpointResolver.resolve(
                day: days[dayIndex],
                accounts: accounts
            ) {
                days[dayIndex].reportEndpoints = endpoints
                changed = true
            }
        }
        return changed
    }

    /// Completed-trip stop edits immediately refresh the report endpoints.
    @discardableResult
    private func refreshCompletedReportData(
        at dayIndex: Int,
        accounts: [FireVaultWorkspaceAccount]
    ) -> Bool {
        guard days.indices.contains(dayIndex),
              days[dayIndex].endedAt != nil,
              let refreshed = FireVaultTripEndpointResolver.resolve(
                  day: days[dayIndex],
                  accounts: accounts
              ) else { return false }
        days[dayIndex].reportEndpoints = refreshed
        return true
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
        guard let command = deferredControlCommand
                ?? FireVaultTripLogControlMailbox.consume() else { return }
        deferredControlCommand = nil
        if activeDay != nil, !accountsAreLoaded {
            // A widget/Live Activity can wake the process before the account
            // repository has loaded. Keep the command in memory until known
            // account coordinates are available for final stop recognition.
            deferredControlCommand = command
            return
        }
        switch command {
        case .resume:
            guard activeDay?.isPaused == true else { return }
            resumeWorkday(accounts: accounts)
        case .end:
            guard activeDay != nil else { return }
            endWorkday()
        }
    }

    private func persist() {
        pendingRoutePersistenceTask?.cancel()
        pendingRoutePersistenceTask = nil
        do {
            try FileManager.default.createDirectory(
                at: archiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.fireVaultBreadcrumbs.encode(days)
            if FileManager.default.fileExists(atPath: archiveURL.path),
               let existing = try? Data(contentsOf: archiveURL),
               (try? JSONDecoder.fireVaultBreadcrumbs.decode([FireVaultBreadcrumbDay].self, from: existing)) != nil {
                let backupURL = Self.backupURL(for: archiveURL)
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: archiveURL, to: backupURL)
            }
            try data.write(to: archiveURL, options: .atomic)
            lastSuccessfulSaveAt = Date()
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
            statusText = "Route is active, but its history could not be saved"
        }
    }

    func flushPendingRoutePersistence() {
        guard pendingRoutePersistenceTask != nil else { return }
        persist()
    }

    private func persistRouteProgress() {
        let now = Date()
        let elapsed = lastSuccessfulSaveAt.map { now.timeIntervalSince($0) }
            ?? Self.routePersistenceInterval
        let remaining = Self.routePersistenceInterval - elapsed

        guard remaining > 0 else {
            persist()
            return
        }
        guard pendingRoutePersistenceTask == nil else { return }

        pendingRoutePersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            self.pendingRoutePersistenceTask = nil
            self.persist()
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
    @State private var showsHistory = false

    private var selectedDay: FireVaultBreadcrumbDay? {
        if let selectedDayID,
           let selected = breadcrumbs.days.first(where: { $0.id == selectedDayID }) {
            return selected
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
                            if let selectedDay {
                                breadcrumbs.prepareReportDays(
                                    anchorDayID: selectedDay.id,
                                    accounts: store.accounts
                                )
                            }
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
                    ),
                    availableDays: breadcrumbs.days
                )
            }
        }
        .sheet(isPresented: $showsHistory) {
            FireVaultTripLogHistoryCalendarView(
                breadcrumbs: breadcrumbs,
                selectedDayID: selectedDayID
            ) { dayID in
                selectedDayID = dayID
                showsHistory = false
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
                Button {
                    showsHistory = true
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
                        if !breadcrumbs.isRecording,
                           breadcrumbs.permissionState.isAuthorized
                                    || breadcrumbs.authorizationStatus == .notDetermined {
                            Button("Resume", systemImage: "play.fill") {
                                breadcrumbs.resumeWorkday(accounts: store.accounts)
                            }
                            .buttonStyle(.borderedProminent)
                        } else if breadcrumbs.isRecording {
                            Label("Recording continuously", systemImage: "location.fill")
                                .font(.caption.bold())
                                .foregroundStyle(NativeShellPalette.green)
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
                        subtitle: day.points.first.map { "Route began near \($0.coordinate.fireVaultCoordinateLabel)" },
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
                            subtitle: day.totalDistanceMeters.fireVaultMiles,
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

struct FireVaultTripLogHistoryCalendarView: View {
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    let selectedDayID: UUID?
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth: Date
    @State private var selectedDate: Date
    @State private var renamingTripID: UUID?
    @State private var renameText = ""
    @State private var pendingDeletionID: UUID?
    @State private var isSelectingTripsToMerge = false
    @State private var mergeSelection = Set<UUID>()
    @State private var confirmsMerge = false

    private let calendar = Calendar.autoupdatingCurrent
    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    init(
        breadcrumbs: FireVaultBreadcrumbStore,
        selectedDayID: UUID?,
        onSelect: @escaping (UUID) -> Void
    ) {
        self.breadcrumbs = breadcrumbs
        self.selectedDayID = selectedDayID
        self.onSelect = onSelect
        let days = breadcrumbs.days
        let initialDate = days.first(where: { $0.id == selectedDayID })?.startedAt
            ?? days.first?.startedAt
            ?? Date()
        _displayedMonth = State(initialValue: initialDate)
        _selectedDate = State(initialValue: initialDate)
    }

    private var selectedTrips: [FireVaultBreadcrumbDay] {
        days.filter { calendar.isDate($0.startedAt, inSameDayAs: selectedDate) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var mergeableTrips: [FireVaultBreadcrumbDay] {
        selectedTrips.filter { !$0.isActive }
    }

    private var days: [FireVaultBreadcrumbDay] { breadcrumbs.days }

    var body: some View {
        NavigationStack {
            List {
                calendarCard
                    .listRowInsets(.init(top: 12, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                tripsForSelectedDate
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NativeShellPalette.background)
            .navigationTitle("Trip Log History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectingTripsToMerge {
                    mergeActionBar
                }
            }
        }
        .tint(NativeShellPalette.blue)
        .alert("Rename Trip", isPresented: Binding(
            get: { renamingTripID != nil },
            set: { if !$0 { renamingTripID = nil } }
        )) {
            TextField("Trip name", text: $renameText)
            Button("Save") {
                if let renamingTripID {
                    _ = breadcrumbs.renameDay(renamingTripID, name: renameText)
                }
                renamingTripID = nil
            }
            Button("Cancel", role: .cancel) { renamingTripID = nil }
        } message: {
            Text("Give this recorded trip a recognizable name.")
        }
        .confirmationDialog(
            "Delete this Trip Log?",
            isPresented: Binding(
                get: { pendingDeletionID != nil },
                set: { if !$0 { pendingDeletionID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Trip", role: .destructive) {
                if let pendingDeletionID {
                    breadcrumbs.deleteDay(pendingDeletionID)
                }
                pendingDeletionID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletionID = nil }
        } message: {
            Text("This permanently removes the trip route, stops, and associated history. Account records are not deleted.")
        }
        .confirmationDialog(
            "Merge \(mergeSelection.count) Trips?",
            isPresented: $confirmsMerge,
            titleVisibility: .visible
        ) {
            Button("Merge Trips") {
                if let mergedID = breadcrumbs.mergeDays(mergeSelection) {
                    onSelect(mergedID)
                    if let merged = breadcrumbs.days.first(where: { $0.id == mergedID }) {
                        selectedDate = merged.startedAt
                        displayedMonth = merged.startedAt
                    }
                }
                mergeSelection.removeAll()
                isSelectingTripsToMerge = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("FireVault will combine the selected routes, stops, times, and names into one Trip Log. A safety copy of the current archive is retained before it is saved.")
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    changeMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)

                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()

                Button {
                    changeMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
            }

            LazyVGrid(columns: weekdayColumns, spacing: 7) {
                ForEach(weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthDates.enumerated()), id: \.offset) { _, date in
                    if let date {
                        calendarDay(date)
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }

            HStack(spacing: 16) {
                Label("Trip history", systemImage: "circle.fill")
                    .foregroundStyle(NativeShellPalette.red)
                Label("No trips", systemImage: "circle.fill")
                    .foregroundStyle(.secondary.opacity(0.42))
            }
            .font(.caption2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .nativeSurfaceCard()
    }

    private func calendarDay(_ date: Date) -> some View {
        let trips = days.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
        let hasTrips = !trips.isEmpty
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)

        return Button {
            selectedDate = date
            mergeSelection.removeAll()
            isSelectingTripsToMerge = false
        } label: {
            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.bold().monospacedDigit())
                if hasTrips {
                    Text("\(trips.count) trip\(trips.count == 1 ? "" : "s")")
                        .font(.system(size: 8, weight: .bold))
                } else {
                    Text(" ").font(.system(size: 8))
                }
            }
            .foregroundStyle(hasTrips ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                hasTrips ? NativeShellPalette.red : Color.secondary.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? NativeShellPalette.blue : Color.clear,
                        lineWidth: isSelected ? 3 : 0
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(date.formatted(date: .complete, time: .omitted)), \(trips.count) trip\(trips.count == 1 ? "" : "s")"
        )
    }

    @ViewBuilder
    private var tripsForSelectedDate: some View {
        Section {
            if selectedTrips.isEmpty {
                ContentUnavailableView(
                    "No Trips Recorded",
                    systemImage: "calendar.badge.minus",
                    description: Text("Choose a red date to review its Trip Log history.")
                )
                .frame(minHeight: 170)
                .nativeSurfaceCard()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(Array(selectedTrips.enumerated()), id: \.element.id) { index, trip in
                    HStack(spacing: 8) {
                        Button {
                            if isSelectingTripsToMerge {
                                toggleMergeSelection(trip)
                            } else {
                                onSelect(trip.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                            Image(systemName: isSelectingTripsToMerge
                                  ? (mergeSelection.contains(trip.id) ? "checkmark.circle.fill" : "circle")
                                  : (trip.isActive ? "record.circle.fill" : "point.topleft.down.to.point.bottomright.curvepath"))
                                .font(.title3.bold())
                                .foregroundStyle(
                                    isSelectingTripsToMerge
                                        ? (mergeSelection.contains(trip.id) ? NativeShellPalette.blue : Color.secondary)
                                        : (trip.isActive ? NativeShellPalette.green : NativeShellPalette.red)
                                )
                                .frame(width: 38, height: 38)
                                .background(
                                    (isSelectingTripsToMerge
                                        ? NativeShellPalette.blue
                                        : (trip.isActive ? NativeShellPalette.green : NativeShellPalette.red)
                                    ).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(tripDisplayName(trip, index: index))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text(tripTimeRange(trip))
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text("\(trip.stops.count) stops • \(trip.totalDistanceMeters.fireVaultMiles)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            if !isSelectingTripsToMerge {
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSelectingTripsToMerge && trip.isActive)

                        if !isSelectingTripsToMerge {
                            Menu {
                                Button("Rename Trip", systemImage: "pencil") {
                                    beginRename(trip, index: index)
                                }
                                if mergeableTrips.count >= 2, !trip.isActive {
                                    Button("Merge Trips…", systemImage: "arrow.triangle.merge") {
                                        withAnimation(.snappy(duration: 0.22)) {
                                            mergeSelection = [trip.id]
                                            isSelectingTripsToMerge = true
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .frame(width: 38, height: 38)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !trip.isActive {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDeletionID = trip.id
                            }
                        }
                    }
                    .accessibilityIdentifier("trip-history-entry-\(trip.id.uuidString)")
                    .opacity(isSelectingTripsToMerge && trip.isActive ? 0.45 : 1)
                }
            }
        } header: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                        .font(.caption.bold())
                        .tracking(0.9)
                        .foregroundStyle(NativeShellPalette.red)
                    Text(selectedDate.formatted(date: .long, time: .omitted))
                        .font(.title3.bold())
                        .textCase(nil)
                        .foregroundStyle(.primary)
                }
                Spacer()
                Text("\(selectedTrips.count) TRIP\(selectedTrips.count == 1 ? "" : "S")")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthDates: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var result = Array<Date?>(repeating: nil, count: leading)
        result.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start)
        })
        while !result.count.isMultiple(of: 7) { result.append(nil) }
        return result
    }

    private func changeMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = next
        mergeSelection.removeAll()
        isSelectingTripsToMerge = false
        if let monthStart = calendar.dateInterval(of: .month, for: next)?.start {
            selectedDate = monthStart
        }
    }

    private func tripTimeRange(_ trip: FireVaultBreadcrumbDay) -> String {
        let start = trip.startedAt.formatted(date: .omitted, time: .shortened)
        let end = trip.endedAt?.formatted(date: .omitted, time: .shortened) ?? "Recording"
        return "\(start) – \(end)"
    }

    private func tripDisplayName(_ trip: FireVaultBreadcrumbDay, index: Int) -> String {
        let savedName = trip.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !savedName.isEmpty { return savedName }
        return selectedTrips.count > 1 ? "Trip \(index + 1)" : "Recorded Trip"
    }

    private func beginRename(_ trip: FireVaultBreadcrumbDay, index: Int) {
        renameText = tripDisplayName(trip, index: index)
        renamingTripID = trip.id
    }

    private var mergeActionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SELECT TRIPS")
                    .font(.caption2.bold())
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("\(mergeSelection.count) selected")
                    .font(.subheadline.bold())
            }
            Spacer()
            Button("Cancel") {
                withAnimation(.snappy(duration: 0.22)) {
                    mergeSelection.removeAll()
                    isSelectingTripsToMerge = false
                }
            }
            .buttonStyle(.bordered)
            Button("Merge Selected", systemImage: "arrow.triangle.merge") {
                confirmsMerge = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(mergeSelection.count < 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func toggleMergeSelection(_ trip: FireVaultBreadcrumbDay) {
        guard !trip.isActive else { return }
        if mergeSelection.contains(trip.id) {
            mergeSelection.remove(trip.id)
        } else {
            mergeSelection.insert(trip.id)
        }
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
    @State private var customCategory: String
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
        _customCategory = State(initialValue: stop?.accountID == nil ? (stop?.accountCategory ?? "") : "")
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
                    customCategory = Self.categoryLabel(match.primaryType)
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
            customCategory: isPersonal || selectedAccount != nil ? "" : customCategory,
            technicianNote: technicianNote,
            isPersonal: isPersonal
        )

        if let accountID {
            openAccount(accountID)
        } else {
            dismiss()
        }
    }

    private static func categoryLabel(_ primaryType: String?) -> String {
        let words = primaryType?
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return words.isEmpty ? "Identified Place" : words.capitalized
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
                    account.category
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

private extension CLLocationCoordinate2D {
    var fireVaultCoordinateLabel: String {
        "\(latitude.formatted(.number.precision(.fractionLength(3)))), \(longitude.formatted(.number.precision(.fractionLength(3))))"
    }
}
