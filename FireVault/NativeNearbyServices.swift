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
    static let liveNearbyDistanceFilter: CLLocationDistance = 50

    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var statusText = "Tap the location button to find nearby accounts"
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isLocating = false
    @Published private(set) var isLiveNearbyTracking = false
    @Published private(set) var isDiagnosticsTracking = false
    @Published private(set) var mapRecenterRequestID = UUID()

    private let manager: CLLocationManager
    private var wantsLiveNearbyTracking = false
    private var wantsDiagnosticsTracking = false

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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
        manager.activityType = .automotiveNavigation
        manager.distanceFilter = Self.liveNearbyDistanceFilter
        manager.desiredAccuracy = highAccuracy
            ? kCLLocationAccuracyNearestTenMeters
            : kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
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
        manager.stopUpdatingLocation()
        isLiveNearbyTracking = false
        isLocating = false
        statusText = coordinate == nil
            ? "Tap the location button to find nearby accounts"
            : "Nearby live updates paused"
    }

    func startDiagnosticsUpdates(highAccuracy: Bool) {
        wantsDiagnosticsTracking = true
        manager.activityType = .other
        manager.distanceFilter = kCLDistanceFilterNone
        manager.desiredAccuracy = highAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
        manager.pausesLocationUpdatesAutomatically = false
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
            manager.stopUpdatingLocation()
            isLocating = false
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
        guard let location = locations
            .filter({ $0.horizontalAccuracy >= 0 })
            .max(by: { $0.timestamp < $1.timestamp }) else {
            isLocating = false
            statusText = "Location could not be determined"
            return
        }

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
        isLocating = true
        isLiveNearbyTracking = true
        statusText = coordinate == nil ? "Starting live Nearby…" : "Nearby updating live"
        manager.startUpdatingLocation()
    }

    private func beginDiagnosticsUpdates() {
        guard wantsDiagnosticsTracking else { return }
        isLocating = true
        isDiagnosticsTracking = true
        isLiveNearbyTracking = false
        statusText = "Starting GPS diagnostics…"
        manager.startUpdatingLocation()
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}
