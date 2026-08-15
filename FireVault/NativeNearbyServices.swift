//
//  NativeNearbyServices.swift
//  FireVault
//
//  Native location and imported-address geocoding for Build 1.06.00.
//

import Combine
import CoreLocation
import Foundation
import MapKit
import UIKit

enum FireVaultNearbyMapCamera {
    static func userRegion(
        coordinate: CLLocationCoordinate2D,
        radiusMiles: Double
    ) -> MKCoordinateRegion {
        let latitudeDelta = max(0.024, min(1.2, radiusMiles / 69 * 2.4))
        let latitudeRadians = coordinate.latitude * .pi / 180
        let longitudeScale = max(0.2, abs(cos(latitudeRadians)))
        return .init(
            center: coordinate,
            span: .init(
                latitudeDelta: latitudeDelta,
                longitudeDelta: latitudeDelta / longitudeScale
            )
        )
    }

    static func accountRegion(coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        .init(
            center: coordinate,
            span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    }
}

struct FireVaultPostalAddress: Equatable {
    let street: String
    let city: String
    let state: String
    let zip: String

    var singleLine: String {
        [street, city, state, zip]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    init?(combinedAddress: String) {
        let value = combinedAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.caseInsensitiveCompare("No address supplied") != .orderedSame else {
            return nil
        }

        let components = value
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        switch components.count {
        case 4...:
            street = components.dropLast(3).joined(separator: ", ")
            city = components[components.count - 3]
            state = components[components.count - 2]
            zip = components[components.count - 1]
        case 3:
            street = components[0]
            city = components[1]
            state = components[2]
            zip = ""
        case 2:
            street = components[0]
            city = components[1]
            state = ""
            zip = ""
        default:
            street = value
            city = ""
            state = ""
            zip = ""
        }

        guard !street.isEmpty else { return nil }
    }
}

struct FireVaultGeocodingRequest: Equatable {
    let token: String
    let accountID: String
    let address: FireVaultPostalAddress
}

struct FireVaultGeocodingMatch: Equatable {
    let token: String
    let latitude: Double
    let longitude: Double
}

struct FireVaultGeocodingProgress: Equatable {
    enum Phase: Equatable {
        case preparing
        case submitting
        case appleFallback
        case saving
        case complete
        case cancelled
        case failed
    }

    var phase: Phase
    var completed: Int
    var total: Int
    var matched: Int
    var message: String

    var isRunning: Bool {
        phase == .preparing || phase == .submitting || phase == .appleFallback || phase == .saving
    }

    var fractionComplete: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

enum FireVaultGeocodingError: LocalizedError {
    case invalidResponse
    case serviceError(Int)
    case noUsableAddresses

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The U.S. Census Geocoder returned an unreadable response. Try again."
        case .serviceError(let status):
            "The U.S. Census Geocoder could not process the request (HTTP \(status)). Try again later."
        case .noUsableAddresses:
            "No imported accounts have a usable street address."
        }
    }
}

struct FireVaultCensusGeocoder {
    private let session: URLSession
    private let endpoint = URL(string: "https://geocoding.geo.census.gov/geocoder/locations/addressbatch")!
    static let maximumBatchSize = 5_000

    init(session: URLSession = .shared) {
        self.session = session
    }

    func geocode(_ records: [FireVaultGeocodingRequest]) async throws -> [FireVaultGeocodingMatch] {
        guard !records.isEmpty else { return [] }
        var matches: [FireVaultGeocodingMatch] = []

        for start in stride(from: 0, to: records.count, by: Self.maximumBatchSize) {
            try Task.checkCancellation()
            let end = min(start + Self.maximumBatchSize, records.count)
            let batch = Array(records[start..<end])
            let request = Self.urlRequest(endpoint: endpoint, records: batch)
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FireVaultGeocodingError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw FireVaultGeocodingError.serviceError(httpResponse.statusCode)
            }
            matches.append(contentsOf: try Self.parseResponse(data))
        }
        return matches
    }

    static func batchCSV(for records: [FireVaultGeocodingRequest]) -> String {
        records.map { record in
            [
                record.token,
                record.address.street,
                record.address.city,
                record.address.state,
                record.address.zip
            ]
            .map(csvField)
            .joined(separator: ",")
        }
        .joined(separator: "\n")
    }

    static func parseResponse(_ data: Data) throws -> [FireVaultGeocodingMatch] {
        guard let source = String(data: data, encoding: .utf8) else {
            throw FireVaultGeocodingError.invalidResponse
        }

        return FireVaultStore.parseCSV(source).compactMap { row in
            guard row.count >= 6,
                  row[2].caseInsensitiveCompare("Match") == .orderedSame else {
                return nil
            }
            let coordinateParts = row[5]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard coordinateParts.count == 2,
                  let longitude = Double(coordinateParts[0]),
                  let latitude = Double(coordinateParts[1]),
                  CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else {
                return nil
            }
            return .init(token: row[0], latitude: latitude, longitude: longitude)
        }
    }

    private static func urlRequest(endpoint: URL, records: [FireVaultGeocodingRequest]) -> URLRequest {
        let boundary = "FireVault-\(UUID().uuidString)"
        var body = Data()

        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"benchmark\"\r\n\r\n")
        body.appendUTF8("Public_AR_Current\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"addressFile\"; filename=\"firevault-addresses.csv\"\r\n")
        body.appendUTF8("Content-Type: text/csv\r\n\r\n")
        body.appendUTF8(batchCSV(for: records))
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("text/csv", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }

    nonisolated private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

@MainActor
final class FireVaultLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    // Speed/course are live telemetry. A 50-meter filter can leave them at
    // zero after departure; route storage is throttled separately.
    static let liveNearbyDistanceFilter: CLLocationDistance = kCLDistanceFilterNone

    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var liveSpeedSnapshot = FireVaultLiveSpeedSnapshot.unavailable
    @Published private(set) var lastMeaningfulMovementAt: Date?
    @Published private(set) var lastLocationCallbackAt: Date?
    @Published private(set) var lastLocationReceivedAt: Date?
    @Published private(set) var lastLocationRecoveryAt: Date?
    @Published private(set) var locationRecoveryCount = 0
    @Published private(set) var statusText = "Tap the location button to find nearby accounts"
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization
    @Published private(set) var isLocating = false
    @Published private(set) var isLiveNearbyTracking = false
    @Published private(set) var isDiagnosticsTracking = false
    @Published private(set) var mapRecenterRequestID = UUID()

    private let manager: CLLocationManager
    private var wantsLiveNearbyTracking = false
    private var wantsDiagnosticsTracking = false
    private var liveNearbyUsesHighAccuracy = true
    private var diagnosticsUsesHighAccuracy = true
    private var speedReferenceLocation: CLLocation?
    private var liveSpeedReducer = FireVaultLiveSpeedReducer()
    private var trackingStartedAt: Date?
    private var locationWatchdogTask: Task<Void, Never>?
    private var consecutiveLocationRecoveryCount = 0
    private var serviceSession: CLServiceSession?

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var liveSpeedMetersPerSecond: CLLocationSpeed? {
        liveSpeedSnapshot.metersPerSecond
    }

    var diagnosticsDesiredAccuracy: CLLocationAccuracy { manager.desiredAccuracy }
    var diagnosticsDistanceFilter: CLLocationDistance { manager.distanceFilter }
    var diagnosticsAutomaticPausingEnabled: Bool { manager.pausesLocationUpdatesAutomatically }
    var diagnosticsServiceSessionActive: Bool { serviceSession != nil }

    var diagnosticsActivityTypeText: String {
        switch manager.activityType {
        case .automotiveNavigation: "Automotive navigation"
        case .fitness: "Fitness"
        case .otherNavigation: "Other navigation"
        case .airborne: "Airborne"
        case .other: "Other"
        @unknown default: "Unknown"
        }
    }

    func requestDiagnosticsReceiverCheck() {
        guard wantsLiveNearbyTracking || wantsDiagnosticsTracking else {
            requestCurrentLocation(highAccuracy: true)
            return
        }
        recoverLocationStream(force: true)
    }

    func requestCurrentLocation(highAccuracy: Bool) {
        manager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            statusText = "Waiting for location permission…"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = true
            statusText = "Finding this iPhone…"
            manager.requestLocation()
        case .denied:
            isLocating = false
            statusText = "Location access is off for FireVault Pro"
        case .restricted:
            isLocating = false
            statusText = "Location access is restricted"
        @unknown default:
            isLocating = false
            statusText = "Location is unavailable"
        }
    }

    func requestMapRecenter(highAccuracy: Bool) {
        mapRecenterRequestID = UUID()
        requestCurrentLocation(highAccuracy: highAccuracy)
    }

    func startLiveNearbyUpdates(highAccuracy: Bool) {
        wantsLiveNearbyTracking = true
        liveNearbyUsesHighAccuracy = highAccuracy
        configureLiveNearbyManager()
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            statusText = "Waiting for location permission…"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginLiveNearbyUpdates()
        case .denied:
            isLiveNearbyTracking = false
            statusText = "Location access is off for FireVault Pro"
        case .restricted:
            isLiveNearbyTracking = false
            statusText = "Location access is restricted"
        @unknown default:
            isLiveNearbyTracking = false
            statusText = "Location is unavailable"
        }
    }

    func stopLiveNearbyUpdates() {
        wantsLiveNearbyTracking = false
        guard isLiveNearbyTracking else { return }
        isLiveNearbyTracking = false
        if wantsDiagnosticsTracking {
            beginDiagnosticsUpdates()
        } else {
            stopContinuousUpdates()
            statusText = coordinate == nil
                ? "Tap the location button to find nearby accounts"
                : "Nearby live updates paused"
        }
    }

    func startDiagnosticsUpdates(highAccuracy: Bool) {
        wantsDiagnosticsTracking = true
        diagnosticsUsesHighAccuracy = highAccuracy
        configureDiagnosticsManager()
        authorizationStatus = manager.authorizationStatus

        switch manager.authorizationStatus {
        case .notDetermined:
            isLocating = true
            statusText = "Waiting for location permission…"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginDiagnosticsUpdates()
        case .denied:
            statusText = "Location access is off for FireVault Pro"
        case .restricted:
            statusText = "Location access is restricted"
        @unknown default:
            statusText = "Location is unavailable"
        }
    }

    func stopDiagnosticsUpdates() {
        wantsDiagnosticsTracking = false
        isDiagnosticsTracking = false
        if wantsLiveNearbyTracking {
            beginLiveNearbyUpdates()
        } else {
            stopContinuousUpdates()
            statusText = coordinate == nil
                ? "Tap the location button to find nearby accounts"
                : "GPS diagnostics stopped"
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if wantsDiagnosticsTracking {
                beginDiagnosticsUpdates()
            } else if wantsLiveNearbyTracking {
                beginLiveNearbyUpdates()
            } else if isLocating {
                statusText = "Finding this iPhone…"
                manager.requestLocation()
            }
        case .denied:
            isLocating = false
            statusText = "Location access is off for FireVault Pro"
        case .restricted:
            isLocating = false
            statusText = "Location access is restricted"
        case .notDetermined:
            break
        @unknown default:
            isLocating = false
            statusText = "Location is unavailable"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let callbackAt = Date()
        lastLocationCallbackAt = callbackAt
        guard let location = locations
            .filter({
                FireVaultBreadcrumbRules.shouldAcceptLiveTelemetry(
                    $0,
                    after: latestLocation,
                    now: callbackAt
                )
            })
            .max(by: { $0.timestamp < $1.timestamp }) else {
            isLocating = false
            statusText = "Location could not be determined"
            return
        }

        lastLocationReceivedAt = location.timestamp
        consecutiveLocationRecoveryCount = 0
        liveSpeedSnapshot = liveSpeedReducer.ingest(location, receivedAt: callbackAt)
        updateMotionEvidence(with: location)
        latestLocation = location
        coordinate = location.coordinate
        FireVaultSiriLocationCache.store(location)
        isLocating = false
        statusText = isDiagnosticsTracking
            ? "Diagnostics live • updated \(Date().formatted(date: .omitted, time: .standard))"
            : (isLiveNearbyTracking
                ? "Live • updated \(Date().formatted(date: .omitted, time: .shortened))"
                : "Updated \(Date().formatted(date: .omitted, time: .shortened))")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard wantsLiveNearbyTracking || wantsDiagnosticsTracking else { return }
        recoverLocationStream(force: true)
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        guard wantsLiveNearbyTracking || wantsDiagnosticsTracking else { return }
        statusText = wantsDiagnosticsTracking
            ? "GPS diagnostics resumed"
            : "Nearby live updates resumed"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLocating = false
        if let locationError = error as? CLError, locationError.code == .denied {
            statusText = "Location access is off for FireVault Pro"
        } else {
            statusText = "Location could not be updated"
        }
    }

    private func beginLiveNearbyUpdates() {
        guard wantsLiveNearbyTracking else { return }
        configureLiveNearbyManager()
        if !isLiveNearbyTracking && !isDiagnosticsTracking {
            trackingStartedAt = Date()
            lastLocationCallbackAt = nil
            lastLocationReceivedAt = nil
            lastLocationRecoveryAt = nil
            consecutiveLocationRecoveryCount = 0
        }
        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .whenInUse)
        }
        isLocating = true
        isLiveNearbyTracking = true
        isDiagnosticsTracking = false
        statusText = coordinate == nil ? "Starting live Nearby…" : "Nearby updating live"
        manager.startUpdatingLocation()
        startLocationWatchdog()
    }

    private func beginDiagnosticsUpdates() {
        guard wantsDiagnosticsTracking else { return }
        configureDiagnosticsManager()
        if !isLiveNearbyTracking && !isDiagnosticsTracking {
            trackingStartedAt = Date()
            lastLocationCallbackAt = nil
            lastLocationReceivedAt = nil
            lastLocationRecoveryAt = nil
            consecutiveLocationRecoveryCount = 0
        }
        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .whenInUse)
        }
        isLocating = true
        isDiagnosticsTracking = true
        isLiveNearbyTracking = false
        statusText = "Starting GPS diagnostics…"
        manager.startUpdatingLocation()
        startLocationWatchdog()
    }

    private func configureLiveNearbyManager() {
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = Self.liveNearbyDistanceFilter
        manager.desiredAccuracy = liveNearbyUsesHighAccuracy
            ? kCLLocationAccuracyBestForNavigation
            : kCLLocationAccuracyHundredMeters
        // Nearby and CarPlay use this feed for live telemetry. Allowing the
        // legacy standard service to pause can leave the last speed/course fix
        // frozen until the app is launched again.
        manager.pausesLocationUpdatesAutomatically = false
    }

    private func configureDiagnosticsManager() {
        manager.activityType = .other
        manager.distanceFilter = kCLDistanceFilterNone
        manager.desiredAccuracy = diagnosticsUsesHighAccuracy
            ? kCLLocationAccuracyBest
            : kCLLocationAccuracyNearestTenMeters
        manager.pausesLocationUpdatesAutomatically = false
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
        guard wantsLiveNearbyTracking || wantsDiagnosticsTracking else { return }
        let now = Date()
        guard force || FireVaultBreadcrumbRules.shouldRecoverLocationStream(
            trackingStartedAt: trackingStartedAt,
            lastLocationReceivedAt: lastLocationReceivedAt,
            lastRecoveryAt: lastLocationRecoveryAt,
            now: now
        ) else { return }

        if let lastLocationRecoveryAt,
           now.timeIntervalSince(lastLocationRecoveryAt)
            < FireVaultBreadcrumbRules.minimumLocationRecoverySpacing {
            return
        }

        lastLocationRecoveryAt = now
        locationRecoveryCount += 1
        consecutiveLocationRecoveryCount += 1
        statusText = "GPS signal delayed • rearming receiver…"
        // Preserve Core Location's warm acquisition state. Repeatedly stopping
        // the manager after every brief silence can extend reacquisition.
        manager.startUpdatingLocation()
    }

    private func stopContinuousUpdates() {
        locationWatchdogTask?.cancel()
        locationWatchdogTask = nil
        manager.stopUpdatingLocation()
        serviceSession?.invalidate()
        serviceSession = nil
        isLocating = false
        isLiveNearbyTracking = false
        isDiagnosticsTracking = false
        trackingStartedAt = nil
        lastLocationCallbackAt = nil
        lastLocationReceivedAt = nil
        lastLocationRecoveryAt = nil
        consecutiveLocationRecoveryCount = 0
        liveSpeedReducer.reset()
        liveSpeedSnapshot = .unavailable
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}
