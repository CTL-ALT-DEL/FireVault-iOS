//
//  NativeSettingsStore.swift
//  FireVault
//
//  Native Settings authority introduced in Build 1.05.00.
//

import Foundation
import Combine

struct FireVaultTechnicianPreferences: Codable, Equatable {
    var name = ""
    var company = ""
    var phone = ""
    var email = ""
    var license = ""
}

struct FireVaultOverlayPreferences: Codable, Equatable {
    var alignment = "bottom"
    var fontSize = "medium"
    var backgroundStyle = "bar"
    var opacity = 85
    var showLogo = true
    var showTagline = true
    var accentColor = "red"

    var normalized: Self {
        var copy = self
        copy.opacity = min(100, max(35, opacity))
        if !["top", "middle", "bottom"].contains(copy.alignment) { copy.alignment = "bottom" }
        if !["small", "medium", "large"].contains(copy.fontSize) { copy.fontSize = "medium" }
        if !["bar", "card", "minimal"].contains(copy.backgroundStyle) { copy.backgroundStyle = "bar" }
        if !["red", "blue", "amber", "white"].contains(copy.accentColor) { copy.accentColor = "red" }
        return copy
    }
}

struct FireVaultGPSPreferences: Codable, Equatable {
    static let allowedRadius = 0.25...25.0
    static let radiusOptions: [Double] = (1...100).map { Double($0) / 4 }

    var nearbyRadiusMiles: Double = 1
    var highAccuracy = true
    var gpsToolsEnabled = true
    var includeCoordinatesInReports = true
    var addressAssistanceEnabled = true

    var normalized: Self {
        var copy = self
        copy.nearbyRadiusMiles = min(
            Self.allowedRadius.upperBound,
            max(Self.allowedRadius.lowerBound, nearbyRadiusMiles)
        )
        return copy
    }

    var radiusStatus: String {
        "\(nearbyRadiusMiles.formatted(.number.precision(.fractionLength(0...2)))) mi"
    }

    static func radiusLabel(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) mi"
    }
}

struct FireVaultPlusCodePreferences: Codable, Equatable {
    var enabled = true
    var autoGenerate = true
    var accountLength = 10
    var locationLength = 11
    var verifyAfterDays = 180
    var searchable = true
    var includeInReports = true
}

struct FireVaultReportPreferences: Codable, Equatable {
    var title = "FireVault Service Report"
    var format = "detailed"
    var includeTechnician = true
    var includeTasks = true
    var includeDeficiencies = true
}

struct FireVaultEmailPreferences: Codable, Equatable {
    var defaultTo = ""
    var cc = ""
    var defaultSubject = "FireVault Service Report"
    var signature = ""
}

struct FireVaultStoragePreferences: Codable, Equatable {
    var photoProvider = "local"
    var documentProvider = "local"
    var photoFolder = "FireVault/Photos"
    var documentFolder = "FireVault/Documents"
    var microsoftProfileLabel = ""
    var microsoftEmail = ""
    var sharePointSiteURL = ""
    var libraryName = "Documents"
}

struct FireVaultSyncPreferences: Codable, Equatable {
    var organization = ""
    var workspace = "FireVault Shared Vault"
    var conflictPolicy = "review"
}

struct FireVaultWebDAVPreferences: Codable, Equatable {
    var enabled = false
    var serverURL = ""
    var username = ""
    var folder = "/FireVault"
}

struct FireVaultPrivacyPreferences: Codable, Equatable {
    var enabled = false
    var autoLockMinutes = 5
    var lockOnBackground = true
    var hideInAppSwitcher = true
}

struct FireVaultNativePreferences: Codable, Equatable {
    var technician = FireVaultTechnicianPreferences()
    var overlay = FireVaultOverlayPreferences()
    var gps = FireVaultGPSPreferences()
    var plusCodes = FireVaultPlusCodePreferences()
    var reports = FireVaultReportPreferences()
    var email = FireVaultEmailPreferences()
    var storage = FireVaultStoragePreferences()
    var sync = FireVaultSyncPreferences()
    var webDAV = FireVaultWebDAVPreferences()
    var privacy = FireVaultPrivacyPreferences()
    var categories: [String] = ["Commercial", "Healthcare", "Education", "Government", "Residential"]

    var normalized: Self {
        var copy = self
        copy.gps = gps.normalized
        copy.overlay = overlay.normalized
        copy.categories = categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return copy
    }
}

@MainActor
final class FireVaultNativeSettingsStore: ObservableObject {
    private enum Key {
        static let preferences = "firevault.native.settings.all.v2"
    }

    @Published private(set) var preferences: FireVaultNativePreferences

    var gps: FireVaultGPSPreferences { preferences.gps }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.preferences),
           let saved = try? decoder.decode(FireVaultNativePreferences.self, from: data) {
            preferences = saved.normalized
        } else {
            preferences = FireVaultNativePreferences()
        }
    }

    func save(_ updated: FireVaultNativePreferences) {
        preferences = updated.normalized
        persist()
    }

    func saveGPS(_ updated: FireVaultGPSPreferences) {
        var next = preferences
        next.gps = updated
        save(next)
    }

    private func persist() {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: Key.preferences)
    }

}
