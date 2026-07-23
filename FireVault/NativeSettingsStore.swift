//
//  NativeSettingsStore.swift
//  FireVault
//
//  Native settings persistence introduced in Build 1.04.00.
//

import Foundation
import Combine

struct FireVaultGPSPreferences: Codable, Equatable {
    static let allowedRadius = 0.25...25.0

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
}

@MainActor
final class FireVaultNativeSettingsStore: ObservableObject {
    private enum Key {
        static let gps = "firevault.native.settings.gps.v1"
        static let importedLegacyGPS = "firevault.native.settings.gps.legacy-imported.v1"
    }

    @Published private(set) var gps: FireVaultGPSPreferences

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.gps),
           let saved = try? decoder.decode(FireVaultGPSPreferences.self, from: data) {
            gps = saved.normalized
        } else {
            gps = FireVaultGPSPreferences()
        }
    }

    func saveGPS(_ preferences: FireVaultGPSPreferences) {
        gps = preferences.normalized
        persistGPS()
    }

    @discardableResult
    func importLegacyGPSIfNeeded(_ raw: Any?) -> Bool {
        guard !defaults.bool(forKey: Key.importedLegacyGPS),
              defaults.data(forKey: Key.gps) == nil,
              let dictionary = raw as? [String: Any] else { return false }

        var imported = FireVaultGPSPreferences()
        if let radius = Self.number(dictionary["nearbyRadiusMiles"]) {
            imported.nearbyRadiusMiles = radius
        }
        if let value = dictionary["highAccuracy"] as? Bool { imported.highAccuracy = value }
        if let value = dictionary["enabled"] as? Bool { imported.gpsToolsEnabled = value }
        if let value = dictionary["includeInReports"] as? Bool { imported.includeCoordinatesInReports = value }
        if let value = dictionary["addressAssist"] as? Bool { imported.addressAssistanceEnabled = value }

        gps = imported.normalized
        persistGPS()
        defaults.set(true, forKey: Key.importedLegacyGPS)
        return true
    }

    private func persistGPS() {
        guard let data = try? encoder.encode(gps) else { return }
        defaults.set(data, forKey: Key.gps)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
