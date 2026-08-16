//
//  FireVaultTripEndpoints.swift
//  FireVault
//
//  Persisted start and end locations used by Trip Log reports.
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

struct FireVaultTripReportEndpoints: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var resolvedAt: Date
    var start: FireVaultTripEndpoint
    var end: FireVaultTripEndpoint
}

@MainActor
enum FireVaultTripEndpointResolver {
    private static let endpointMatchRadius: CLLocationDistance = 175
    private static let maximumEndpointEvidenceInterval: TimeInterval = 15 * 60

    static func resolve(
        day: FireVaultBreadcrumbDay,
        accounts: [FireVaultWorkspaceAccount],
        resolvedAt: Date = Date()
    ) -> FireVaultTripReportEndpoints? {
        guard day.endedAt != nil else { return nil }
        return endpoints(day: day, accounts: accounts, resolvedAt: resolvedAt)
    }

    static func fallback(
        day: FireVaultBreadcrumbDay,
        resolvedAt: Date = Date()
    ) -> FireVaultTripReportEndpoints {
        endpoints(day: day, accounts: [], resolvedAt: resolvedAt)
    }

    private static func endpoints(
        day: FireVaultBreadcrumbDay,
        accounts: [FireVaultWorkspaceAccount],
        resolvedAt: Date
    ) -> FireVaultTripReportEndpoints {
        let points = day.points
            .filter { CLLocationCoordinate2DIsValid($0.coordinate) }
            .sorted { $0.timestamp < $1.timestamp }
        let stops = day.stops.sorted { $0.arrival < $1.arrival }
        let endTimestamp = day.endedAt ?? resolvedAt
        let firstStop = stops.first
        let lastStop = stops.last
        let startEvidence = endpointEvidence(
            boundary: day.startedAt,
            point: points.first,
            stop: firstStop,
            stopTimestamp: firstStop?.arrival
        )
        let endEvidence = endpointEvidence(
            boundary: endTimestamp,
            point: points.last,
            stop: lastStop,
            stopTimestamp: lastStop.map { day.effectiveDeparture(for: $0, asOf: endTimestamp) }
        )
        return .init(
            resolvedAt: resolvedAt,
            start: resolveEndpoint(
                evidence: startEvidence,
                stops: stops,
                accounts: accounts,
                fallbackTimestamp: day.startedAt
            ),
            end: resolveEndpoint(
                evidence: endEvidence,
                stops: stops,
                accounts: accounts,
                fallbackTimestamp: endTimestamp
            )
        )
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

    private static func resolveEndpoint(
        evidence: (Date, CLLocationCoordinate2D)?,
        stops: [FireVaultBreadcrumbStop],
        accounts: [FireVaultWorkspaceAccount],
        fallbackTimestamp: Date
    ) -> FireVaultTripEndpoint {
        guard let evidence else { return unavailableEndpoint(timestamp: fallbackTimestamp) }
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
                    location.distance(
                        from: CLLocation(latitude: stop.latitude, longitude: stop.longitude)
                    )
                )
            }
            .min { $0.1 < $1.1 }
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
