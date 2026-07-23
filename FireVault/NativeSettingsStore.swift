//
//  NativeSettingsStore.swift
//  FireVault
//
//  Native Settings authority introduced in Build 1.05.00.
//

import Foundation
import Combine

enum FireVaultOverlayField: String, CaseIterable, Identifiable {
    case site
    case address
    case accountID
    case category
    case technician
    case timestamp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .site: "Site name"
        case .address: "Address"
        case .accountID: "Account ID"
        case .category: "Category"
        case .technician: "Technician"
        case .timestamp: "Date and time"
        }
    }

    var symbol: String {
        switch self {
        case .site: "building.2"
        case .address: "mappin.and.ellipse"
        case .accountID: "number"
        case .category: "tag"
        case .technician: "person.crop.circle"
        case .timestamp: "calendar.badge.clock"
        }
    }

    var isRequired: Bool {
        self == .site || self == .address || self == .accountID
    }
}

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
    var tagline = "FIREVAULT FIELD DOCUMENTATION"
    var fieldOrder = FireVaultOverlayField.allCases.map(\.rawValue)
    var hiddenFields = [FireVaultOverlayField.category.rawValue]
    var fieldTemplate = """
    {site}
    {address}
    Account ID: {accountID}
    {technician} • {date} {time}
    """

    var normalized: Self {
        var copy = self
        copy.opacity = min(100, max(35, opacity))
        if !["top", "middle", "bottom"].contains(copy.alignment) { copy.alignment = "bottom" }
        if !["small", "medium", "large"].contains(copy.fontSize) { copy.fontSize = "medium" }
        if !["bar", "card", "minimal"].contains(copy.backgroundStyle) { copy.backgroundStyle = "bar" }
        if !["red", "blue", "amber", "white"].contains(copy.accentColor) { copy.accentColor = "red" }
        copy.tagline = String(copy.tagline.prefix(80))
        let allowedFields = Set(FireVaultOverlayField.allCases.map(\.rawValue))
        var seenFields = Set<String>()
        copy.fieldOrder = copy.fieldOrder.filter {
            allowedFields.contains($0) && seenFields.insert($0).inserted
        }
        for field in FireVaultOverlayField.allCases where !seenFields.contains(field.rawValue) {
            copy.fieldOrder.append(field.rawValue)
        }
        let requiredFields = Set(
            FireVaultOverlayField.allCases.filter(\.isRequired).map(\.rawValue)
        )
        copy.hiddenFields = Array(
            Set(copy.hiddenFields)
                .intersection(allowedFields)
                .subtracting(requiredFields)
        )
        copy.fieldTemplate = Self.requiredFieldTemplate(copy.fieldTemplate)
        return copy
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case alignment
        case fontSize
        case backgroundStyle
        case opacity
        case showLogo
        case showTagline
        case accentColor
        case tagline
        case fieldOrder
        case hiddenFields
        case fieldTemplate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        alignment = try values.decodeIfPresent(String.self, forKey: .alignment) ?? "bottom"
        fontSize = try values.decodeIfPresent(String.self, forKey: .fontSize) ?? "medium"
        backgroundStyle = try values.decodeIfPresent(String.self, forKey: .backgroundStyle) ?? "bar"
        opacity = try values.decodeIfPresent(Int.self, forKey: .opacity) ?? 85
        showLogo = try values.decodeIfPresent(Bool.self, forKey: .showLogo) ?? true
        showTagline = try values.decodeIfPresent(Bool.self, forKey: .showTagline) ?? true
        accentColor = try values.decodeIfPresent(String.self, forKey: .accentColor) ?? "red"
        tagline = try values.decodeIfPresent(String.self, forKey: .tagline)
            ?? "FIREVAULT FIELD DOCUMENTATION"
        fieldOrder = try values.decodeIfPresent([String].self, forKey: .fieldOrder)
            ?? FireVaultOverlayField.allCases.map(\.rawValue)
        hiddenFields = try values.decodeIfPresent([String].self, forKey: .hiddenFields)
            ?? [FireVaultOverlayField.category.rawValue]
        fieldTemplate = try values.decodeIfPresent(String.self, forKey: .fieldTemplate)
            ?? """
            {site}
            {address}
            Account ID: {accountID}
            {technician} • {date} {time}
            """
    }

    private static func requiredFieldTemplate(_ value: String) -> String {
        var result = String(value.prefix(500))
        let requiredTokens = ["{site}", "{address}", "{accountID}"]

        for token in requiredTokens where !result.contains(token) {
            if !result.isEmpty, !result.hasSuffix("\n") {
                result.append("\n")
            }
            result.append(token)
        }
        return result
    }
}

struct FireVaultGPSPreferences: Codable, Equatable {
    static let allowedRadius = 0.25...25.0
    static let radiusOptions: [Double] = [0.25, 0.5, 0.75, 1] + (2...25).map(Double.init)

    var nearbyRadiusMiles: Double = 1
    var highAccuracy = true
    var gpsToolsEnabled = true
    var includeCoordinatesInReports = true
    var addressAssistanceEnabled = true

    var normalized: Self {
        var copy = self
        let clamped = min(
            Self.allowedRadius.upperBound,
            max(Self.allowedRadius.lowerBound, nearbyRadiusMiles)
        )
        copy.nearbyRadiusMiles = Self.radiusOptions.min {
            abs($0 - clamped) < abs($1 - clamped)
        } ?? 1
        return copy
    }

    var radiusStatus: String {
        "\(nearbyRadiusMiles.formatted(.number.precision(.fractionLength(0...2)))) mi"
    }

    static func radiusLabel(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) mi"
    }

    static func radiusWheelLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
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
