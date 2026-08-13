//
//  FireVaultGooglePlacesService.swift
//  FireVault
//
//  Protected Google Places lookup for unclassified Trip Log stops.
//

import Foundation
import Supabase

struct FireVaultGooglePlaceMatch: Decodable, Equatable, Identifiable, Sendable {
    let placeID: String
    let name: String
    let address: String
    let distanceMeters: Double
    let primaryType: String?

    var id: String { placeID }

    var distanceText: String {
        let measurement = Measurement(value: distanceMeters, unit: UnitLength.meters)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .road,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
        )
    }
}

private struct FireVaultGooglePlacesRequest: Encodable, Sendable {
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
}

private struct FireVaultGooglePlacesResponse: Decodable, Sendable {
    let matches: [FireVaultGooglePlaceMatch]
}

enum FireVaultGooglePlacesError: LocalizedError, Equatable {
    case notAuthenticated
    case noMatches
    case unavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Your FireVault session has expired. Sign in again, then retry."
        case .noMatches:
            "Google Places did not find a nearby business. You can enter the stop name and address manually."
        case .unavailable:
            "Google Places is unavailable right now. Check your connection and try again."
        }
    }
}

protocol FireVaultGooglePlacesProviding: Sendable {
    func matches(latitude: Double, longitude: Double) async throws -> [FireVaultGooglePlaceMatch]
}

final class FireVaultGooglePlacesService: FireVaultGooglePlacesProviding, @unchecked Sendable {
    static let shared = FireVaultGooglePlacesService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func matches(latitude: Double, longitude: Double) async throws -> [FireVaultGooglePlaceMatch] {
        do {
            _ = try await client.auth.session
        } catch {
            throw FireVaultGooglePlacesError.notAuthenticated
        }

        do {
            let response: FireVaultGooglePlacesResponse = try await client.functions.invoke(
                "google-places-stop-lookup",
                options: FunctionInvokeOptions(
                    body: FireVaultGooglePlacesRequest(
                        latitude: latitude,
                        longitude: longitude,
                        radiusMeters: 125
                    )
                )
            )
            guard !response.matches.isEmpty else {
                throw FireVaultGooglePlacesError.noMatches
            }
            return response.matches
        } catch let error as FireVaultGooglePlacesError {
            throw error
        } catch {
            throw FireVaultGooglePlacesError.unavailable
        }
    }
}
