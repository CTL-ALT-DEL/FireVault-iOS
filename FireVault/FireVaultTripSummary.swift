//
//  FireVaultTripSummary.swift
//  FireVault
//
//  Persisted, one-time Trip Log endpoint resolution and factual narrative.
//

import CoreLocation
import Foundation

struct FireVaultTripEndpoint: Codable, Equatable {
    enum Source: String, Codable {
        case account
        case recordedStop
        case coordinate
        case unavailable
        case privateLocation
    }

    var timestamp: Date
    var latitude: Double?
    var longitude: Double?
    var title: String
    var address: String
    var city: String
    var category: String?
    var source: Source
    var isPrivate: Bool

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let value = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(value) ? value : nil
    }

    var displayTitle: String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Location unavailable" : normalized
    }

    var displayAddress: String {
        let normalized = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Approximate location" : normalized
    }

    func reportAddress(includesCoordinates: Bool) -> String {
        if isPrivate { return "Location details redacted" }
        if source == .coordinate {
            guard includesCoordinates, let latitude, let longitude else {
                return "Approximate recorded location"
            }
            return String(
                format: "%.6f, %.6f",
                locale: Locale(identifier: "en_US_POSIX"),
                latitude,
                longitude
            )
        }
        return displayAddress
    }
}

struct FireVaultTripStopCategorySummary: Codable, Equatable {
    var name: String
    var count: Int
}

enum FireVaultTripSummaryGenerationSource: String, Codable, Equatable {
    case localAnalysis
    case onDeviceAI
}

struct FireVaultTripReportSummary: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var generatedAt: Date
    var paragraph: String
    var start: FireVaultTripEndpoint
    var end: FireVaultTripEndpoint
    var averageSpeedMPH: Double?
    var minimumElevationFeet: Double?
    var maximumElevationFeet: Double?
    var stopCategories: [FireVaultTripStopCategorySummary]
    /// Optional so Trip Log archives created before the intelligent-summary
    /// feature continue to decode without a migration.
    var generationSource: FireVaultTripSummaryGenerationSource? = .localAnalysis
    /// Written before the model request begins. A persisted timestamp prevents
    /// report previews, exports, and app relaunches from generating it again.
    var intelligenceAttemptedAt: Date? = nil
    /// Monotonically changes whenever FireVault rebuilds the authoritative
    /// factual summary. Async model results are accepted only when their saved
    /// revision still matches, preventing a delayed rewrite from overwriting
    /// later stop edits, deletions, or trip merges.
    var factualRevision: Int? = 1
}

@MainActor
enum FireVaultTripSummaryBuilder {
    private static let endpointMatchRadius: CLLocationDistance = 175
    private static let maximumEndpointEvidenceInterval: TimeInterval = 15 * 60

    static func generate(
        day: FireVaultBreadcrumbDay,
        accounts: [FireVaultWorkspaceAccount],
        generatedAt: Date = Date()
    ) -> FireVaultTripReportSummary? {
        guard day.endedAt != nil else { return nil }

        let points = day.points
            .filter { CLLocationCoordinate2DIsValid($0.coordinate) }
            .sorted { $0.timestamp < $1.timestamp }
        let sortedStops = day.stops.sorted { $0.arrival < $1.arrival }
        let endTimestamp = day.endedAt ?? generatedAt
        let startEvidence = endpointEvidence(
            boundary: day.startedAt,
            point: points.first,
            stop: sortedStops.first,
            stopTimestamp: sortedStops.first?.arrival
        )
        let lastStop = sortedStops.last
        let endEvidence = endpointEvidence(
            boundary: endTimestamp,
            point: points.last,
            stop: lastStop,
            stopTimestamp: lastStop.map { day.effectiveDeparture(for: $0, asOf: endTimestamp) }
        )
        let start = resolveEndpoint(
            evidence: startEvidence,
            stops: sortedStops,
            accounts: accounts,
            fallbackTimestamp: day.startedAt
        )
        let end = resolveEndpoint(
            evidence: endEvidence,
            stops: sortedStops,
            accounts: accounts,
            fallbackTimestamp: day.endedAt ?? generatedAt
        )
        let averageSpeed = averageTravelSpeedMPH(day: day, asOf: generatedAt)
        let elevations = robustElevationRangeFeet(points: points)
        let categories = stopCategorySummary(stops: sortedStops, accounts: accounts)
        return .init(
            generatedAt: generatedAt,
            paragraph: narrative(
                day: day,
                stops: sortedStops,
                start: start,
                end: end,
                averageSpeedMPH: averageSpeed,
                elevationRange: elevations,
                generatedAt: generatedAt
            ),
            start: start,
            end: end,
            averageSpeedMPH: averageSpeed,
            minimumElevationFeet: elevations?.minimum,
            maximumElevationFeet: elevations?.maximum,
            stopCategories: categories
        )
    }

    static func fallback(
        day: FireVaultBreadcrumbDay,
        generatedAt: Date = Date()
    ) -> FireVaultTripReportSummary {
        let points = day.points
            .filter { CLLocationCoordinate2DIsValid($0.coordinate) }
            .sorted { $0.timestamp < $1.timestamp }
        let stops = day.stops.sorted { $0.arrival < $1.arrival }
        let endTimestamp = day.endedAt ?? generatedAt
        let startEvidence = endpointEvidence(
            boundary: day.startedAt,
            point: points.first,
            stop: stops.first,
            stopTimestamp: stops.first?.arrival
        )
        let lastStop = stops.last
        let endEvidence = endpointEvidence(
            boundary: endTimestamp,
            point: points.last,
            stop: lastStop,
            stopTimestamp: lastStop.map { day.effectiveDeparture(for: $0, asOf: endTimestamp) }
        )
        let start = coordinateEndpoint(
            timestamp: day.startedAt,
            coordinate: startEvidence?.1
        )
        let end = coordinateEndpoint(
            timestamp: endTimestamp,
            coordinate: endEvidence?.1
        )
        let averageSpeed = averageTravelSpeedMPH(day: day, asOf: generatedAt)
        let elevations = robustElevationRangeFeet(points: points)
        let categories = stopCategorySummary(stops: day.stops, accounts: [])
        let paragraph = day.endedAt == nil
            ? "This Trip Log is still recording. FireVault will create and save its final intelligent summary once the trip ends."
            : narrative(
                day: day,
                stops: day.stops.sorted { $0.arrival < $1.arrival },
                start: start,
                end: end,
                averageSpeedMPH: averageSpeed,
                elevationRange: elevations,
                generatedAt: generatedAt
            )
        return .init(
            generatedAt: generatedAt,
            paragraph: paragraph,
            start: start,
            end: end,
            averageSpeedMPH: averageSpeed,
            minimumElevationFeet: elevations?.minimum,
            maximumElevationFeet: elevations?.maximum,
            stopCategories: categories
        )
    }

    /// Rebuilds deterministic report facts after a completed trip changes.
    /// The one-shot attempt markers are retained, while an accepted AI rewrite
    /// is intentionally replaced with the newly correct local paragraph.
    static func refreshed(
        day: FireVaultBreadcrumbDay,
        accounts: [FireVaultWorkspaceAccount],
        preserving previous: FireVaultTripReportSummary?,
        generatedAt: Date = Date()
    ) -> FireVaultTripReportSummary? {
        guard var refreshed = generate(
            day: day,
            accounts: accounts,
            generatedAt: generatedAt
        ) else { return nil }

        if let previous {
            refreshed.intelligenceAttemptedAt = previous.intelligenceAttemptedAt
            refreshed.factualRevision = max(1, previous.factualRevision ?? 1) + 1
            refreshed.paragraph = narrative(
                day: day,
                stops: day.stops.sorted { $0.arrival < $1.arrival },
                start: refreshed.start,
                end: refreshed.end,
                averageSpeedMPH: refreshed.averageSpeedMPH,
                elevationRange: elevationRange(from: refreshed),
                generatedAt: generatedAt
            )
        }
        refreshed.generationSource = .localAnalysis
        return refreshed
    }

    private static func endpointEvidence(
        boundary: Date,
        point: FireVaultBreadcrumbPoint?,
        stop: FireVaultBreadcrumbStop?,
        stopTimestamp: Date?
    ) -> (Date, CLLocationCoordinate2D)? {
        if let point,
           abs(point.timestamp.timeIntervalSince(boundary)) <= maximumEndpointEvidenceInterval {
            return (boundary, point.coordinate)
        }
        if let stop, let stopTimestamp,
           abs(stopTimestamp.timeIntervalSince(boundary)) <= maximumEndpointEvidenceInterval {
            return (boundary, stop.coordinate)
        }
        return nil
    }

    private static func elevationRange(
        from summary: FireVaultTripReportSummary
    ) -> (minimum: Double, maximum: Double)? {
        guard let minimum = summary.minimumElevationFeet,
              let maximum = summary.maximumElevationFeet else { return nil }
        return (minimum, maximum)
    }

    private static func resolveEndpoint(
        evidence: (Date, CLLocationCoordinate2D)?,
        stops: [FireVaultBreadcrumbStop],
        accounts: [FireVaultWorkspaceAccount],
        fallbackTimestamp: Date
    ) -> FireVaultTripEndpoint {
        guard let evidence else {
            return unavailableEndpoint(timestamp: fallbackTimestamp)
        }
        let timestamp = evidence.0
        let coordinate = evidence.1
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        if let personal = nearestStop(to: location, in: stops),
           personal.stop.isPersonalStop,
           personal.distance <= endpointMatchRadius {
            return .init(
                timestamp: timestamp,
                latitude: nil,
                longitude: nil,
                title: "Private location",
                address: "Location details redacted",
                city: "",
                category: "Personal",
                source: .privateLocation,
                isPrivate: true
            )
        }

        if let account = FireVaultBreadcrumbRules.closestAccount(
            to: coordinate,
            accounts: accounts,
            maximumDistance: endpointMatchRadius
        ) {
            return .init(
                timestamp: timestamp,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                title: account.name,
                address: account.address,
                city: cityName(from: account.address),
                category: normalized(account.category),
                source: .account,
                isPrivate: false
            )
        }

        if let nearby = nearestStop(to: location, in: stops),
           nearby.distance <= endpointMatchRadius,
           nearby.stop.title != "Unrecognized Stop" {
            let stop = nearby.stop
            let category = normalized(stop.accountCategory)
                ?? stop.accountID.flatMap { id in
                    accounts.first(where: { $0.id == id })?.category
                }
            return .init(
                timestamp: timestamp,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                title: stop.title,
                address: stop.accountAddress ?? "",
                city: cityName(from: stop.accountAddress ?? ""),
                category: normalized(category),
                source: .recordedStop,
                isPrivate: false
            )
        }
        return coordinateEndpoint(timestamp: timestamp, coordinate: coordinate)
    }

    private static func coordinateEndpoint(
        timestamp: Date,
        coordinate: CLLocationCoordinate2D?
    ) -> FireVaultTripEndpoint {
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else {
            return unavailableEndpoint(timestamp: timestamp)
        }
        return .init(
            timestamp: timestamp,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            title: "Recorded GPS location",
            address: "Approximate recorded location",
            city: "",
            category: nil,
            source: .coordinate,
            isPrivate: false
        )
    }

    private static func unavailableEndpoint(timestamp: Date) -> FireVaultTripEndpoint {
        .init(
            timestamp: timestamp,
            latitude: nil,
            longitude: nil,
            title: "Location unavailable",
            address: "No reliable GPS endpoint was recorded",
            city: "",
            category: nil,
            source: .unavailable,
            isPrivate: false
        )
    }

    private static func nearestStop(
        to location: CLLocation,
        in stops: [FireVaultBreadcrumbStop]
    ) -> (stop: FireVaultBreadcrumbStop, distance: CLLocationDistance)? {
        stops
            .map { stop in
                (
                    stop,
                    location.distance(from: CLLocation(latitude: stop.latitude, longitude: stop.longitude))
                )
            }
            .min { $0.1 < $1.1 }
    }

    private static func averageTravelSpeedMPH(
        day: FireVaultBreadcrumbDay,
        asOf referenceDate: Date
    ) -> Double? {
        let elapsed = max(0, (day.endedAt ?? referenceDate).timeIntervalSince(day.startedAt))
        let stopped = day.stops.reduce(0) { partial, stop in
            partial + day.stopDuration(for: stop, asOf: referenceDate)
        }
        let travelTime = max(0, elapsed - min(elapsed, stopped))
        guard travelTime >= 60, day.totalDistanceMeters > 0 else { return nil }
        let mph = (day.totalDistanceMeters / 1_609.344) / (travelTime / 3_600)
        guard mph.isFinite, mph >= 0, mph <= 150 else { return nil }
        return mph
    }

    private static func robustElevationRangeFeet(
        points: [FireVaultBreadcrumbPoint]
    ) -> (minimum: Double, maximum: Double)? {
        let values = points
            .compactMap(\.altitude)
            .map { $0 * 3.280_84 }
            .filter { $0.isFinite && $0 >= -1_500 && $0 <= 30_000 }
            .sorted()
        guard !values.isEmpty else { return nil }
        if values.count < 10 {
            return (values.first ?? 0, values.last ?? 0)
        }
        let lowIndex = Int((Double(values.count - 1) * 0.05).rounded(.down))
        let highIndex = Int((Double(values.count - 1) * 0.95).rounded(.up))
        return (values[lowIndex], values[min(values.count - 1, highIndex)])
    }

    private static func stopCategorySummary(
        stops: [FireVaultBreadcrumbStop],
        accounts: [FireVaultWorkspaceAccount]
    ) -> [FireVaultTripStopCategorySummary] {
        var counts: [String: Int] = [:]
        for stop in stops {
            let category: String
            if stop.isPersonalStop {
                category = "Personal"
            } else if let saved = normalized(stop.accountCategory) {
                category = saved
            } else if let id = stop.accountID,
                      let account = accounts.first(where: { $0.id == id }),
                      let accountCategory = normalized(account.category) {
                category = accountCategory
            } else if stop.accountID != nil {
                category = "Account"
            } else if stop.title != "Unrecognized Stop" {
                category = "Identified Place"
            } else {
                category = "Unrecognized"
            }
            counts[category, default: 0] += 1
        }
        return counts
            .map { .init(name: $0.key, count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private static func narrative(
        day: FireVaultBreadcrumbDay,
        stops: [FireVaultBreadcrumbStop],
        start: FireVaultTripEndpoint,
        end: FireVaultTripEndpoint,
        averageSpeedMPH: Double?,
        elevationRange: (minimum: Double, maximum: Double)?,
        generatedAt: Date
    ) -> String {
        let endDate = day.endedAt ?? generatedAt
        let startTime = day.startedAt.formatted(date: .omitted, time: .shortened)
        let endTime = endDate.formatted(date: .omitted, time: .shortened)
        var sentences = [
            "The trip started at \(endpointDescription(start)) at \(startTime) and ended at \(endpointDescription(end)) at \(endTime)."
        ]
        var travel = "It covered \(FireVaultBreadcrumbReport.distanceText(day.totalDistanceMeters)) in \(FireVaultBreadcrumbReport.durationText(max(0, endDate.timeIntervalSince(day.startedAt))))"
        if let averageSpeedMPH {
            travel += ", averaging \(Int(averageSpeedMPH.rounded())) mph"
        } else {
            travel += ". Average speed was unavailable"
        }
        sentences.append(travel + ".")
        if stops.isEmpty {
            sentences.append("No stops were recorded.")
        } else {
            sentences.append("The trip included \(stops.count) recorded stop\(stops.count == 1 ? "" : "s").")
        }
        if let elevationRange {
            let low = Int(elevationRange.minimum.rounded())
            let high = Int(elevationRange.maximum.rounded())
            if abs(high - low) < 10 {
                sentences.append("Elevation stayed near \(high.formatted()) feet.")
            } else {
                sentences.append("Elevation ranged from about \(low.formatted()) to \(high.formatted()) feet.")
            }
        } else {
            sentences.append("Elevation data was unavailable.")
        }
        return sentences.joined(separator: " ")
    }

    private static func endpointDescription(_ endpoint: FireVaultTripEndpoint) -> String {
        if endpoint.source == .coordinate || endpoint.source == .unavailable {
            return endpoint.displayTitle
        }
        let address = endpoint.displayAddress
        if address == "Approximate location" || address == endpoint.displayTitle {
            return endpoint.displayTitle
        }
        return "\(endpoint.displayTitle), \(address)"
    }

    private static func cityName(from address: String) -> String {
        FireVaultPostalAddress(combinedAddress: address)?.city
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalized(_ value: String?) -> String? {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? nil : result
    }
}
