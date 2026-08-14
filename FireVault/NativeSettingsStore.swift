//
//  NativeSettingsStore.swift
//  FireVault
//
//  Native Settings authority introduced in Build 1.05.00.
//

import Foundation
import Combine

enum FireVaultOverlayField: String, CaseIterable, Identifiable {
    case site, address, accountID, category, technician, timestamp
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
    var isRequired: Bool { self == .site || self == .address || self == .accountID }
}

struct FireVaultTechnicianPreferences: Codable, Equatable {
    var name = ""; var company = ""; var phone = ""; var email = ""; var license = ""
}

enum FireVaultCategoryRuleField: String, Codable, CaseIterable, Identifiable {
    case accountName, address, accountID, category, phone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accountName: "Account name"
        case .address: "Address"
        case .accountID: "Account ID"
        case .category: "Category"
        case .phone: "Phone"
        }
    }
}

enum FireVaultCategoryRuleCondition: String, Codable, CaseIterable, Identifiable {
    case contains, beginsWith, equals
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contains: "contains"
        case .beginsWith: "begins with"
        case .equals: "equals"
        }
    }
}

struct FireVaultCategoryRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var isEnabled = true
    var field = FireVaultCategoryRuleField.accountName
    var condition = FireVaultCategoryRuleCondition.contains
    var value = ""
    var categoryTag = ""
}

enum FireVaultCategoryTagDesign: String, Codable, CaseIterable, Identifiable {
    case label, hashtag
    var id: String { rawValue }
    var title: String { self == .label ? "Tag Label" : "Hashtag" }
}

struct FireVaultCategoryStyle: Codable, Equatable, Identifiable {
    var id: String { category.lowercased() }
    var category: String
    var symbol = "tag.fill"
    var color = "blue"
    var design = FireVaultCategoryTagDesign.label
}

struct FireVaultOverlayPreferences: Codable, Equatable {
    var alignment = "bottom"
    var horizontalPosition = "left"
    var scale = 0.50
    var positionX = -0.78
    var positionY = 0.78
    var logoScale = 0.70
    var logoPositionX = 0.78
    var logoPositionY = -0.78
    var logoPlacement = "freeform"
    var fontSize = "medium"
    var backgroundStyle = "frosted"
    var glassStyle = "regular"
    var glassThickness = "regular"
    var opacity = 85
    var showLogo = true
    var showTagline = true
    var showLocationQRCode = false
    var accentColor = "blue"
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
        copy.scale = min(1.35, max(0.45, scale))
        copy.positionX = min(1.35, max(-1.35, positionX))
        copy.positionY = min(1.35, max(-1.35, positionY))
        copy.logoScale = min(1.8, max(0.45, logoScale))
        copy.logoPositionX = min(1.35, max(-1.35, logoPositionX))
        copy.logoPositionY = min(1.35, max(-1.35, logoPositionY))
        copy.logoPlacement = "freeform"
        if !["top", "bottom"].contains(copy.alignment) { copy.alignment = "bottom" }
        if !["left", "right"].contains(copy.horizontalPosition) { copy.horizontalPosition = "left" }
        copy.fontSize = "medium"
        copy.backgroundStyle = "frosted"
        copy.glassStyle = "regular"
        copy.glassThickness = "regular"
        if !["red", "blue", "amber", "white"].contains(copy.accentColor) { copy.accentColor = "blue" }
        copy.tagline = String(copy.tagline.prefix(80))
        let allowedFields = Set(FireVaultOverlayField.allCases.map(\.rawValue))
        var seenFields = Set<String>()
        copy.fieldOrder = copy.fieldOrder.filter { allowedFields.contains($0) && seenFields.insert($0).inserted }
        for field in FireVaultOverlayField.allCases where !seenFields.contains(field.rawValue) { copy.fieldOrder.append(field.rawValue) }
        let requiredFields = Set(FireVaultOverlayField.allCases.filter(\.isRequired).map(\.rawValue))
        copy.hiddenFields = Array(Set(copy.hiddenFields).intersection(allowedFields).subtracting(requiredFields))
        copy.fieldTemplate = Self.requiredFieldTemplate(copy.fieldTemplate)
        return copy
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case alignment, horizontalPosition, scale, positionX, positionY
        case logoScale, logoPositionX, logoPositionY, logoPlacement
        case fontSize, backgroundStyle, glassStyle, glassThickness, opacity, showLogo, showTagline
        case showLocationQRCode, accentColor, tagline, fieldOrder, hiddenFields, fieldTemplate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        alignment = try values.decodeIfPresent(String.self, forKey: .alignment) ?? "bottom"
        horizontalPosition = try values.decodeIfPresent(String.self, forKey: .horizontalPosition) ?? "left"
        scale = try values.decodeIfPresent(Double.self, forKey: .scale) ?? 0.50
        positionX = try values.decodeIfPresent(Double.self, forKey: .positionX) ?? -0.78
        positionY = try values.decodeIfPresent(Double.self, forKey: .positionY) ?? 0.78
        logoScale = try values.decodeIfPresent(Double.self, forKey: .logoScale) ?? 0.70
        logoPositionX = try values.decodeIfPresent(Double.self, forKey: .logoPositionX) ?? 0.78
        logoPositionY = try values.decodeIfPresent(Double.self, forKey: .logoPositionY) ?? -0.78
        logoPlacement = "freeform"
        fontSize = "medium"
        backgroundStyle = "frosted"
        glassStyle = "regular"
        glassThickness = "regular"
        opacity = try values.decodeIfPresent(Int.self, forKey: .opacity) ?? 85
        showLogo = try values.decodeIfPresent(Bool.self, forKey: .showLogo) ?? true
        showTagline = try values.decodeIfPresent(Bool.self, forKey: .showTagline) ?? true
        showLocationQRCode = try values.decodeIfPresent(Bool.self, forKey: .showLocationQRCode) ?? false
        accentColor = try values.decodeIfPresent(String.self, forKey: .accentColor) ?? "blue"
        tagline = try values.decodeIfPresent(String.self, forKey: .tagline) ?? "FIREVAULT FIELD DOCUMENTATION"
        fieldOrder = try values.decodeIfPresent([String].self, forKey: .fieldOrder) ?? FireVaultOverlayField.allCases.map(\.rawValue)
        hiddenFields = try values.decodeIfPresent([String].self, forKey: .hiddenFields) ?? [FireVaultOverlayField.category.rawValue]
        fieldTemplate = try values.decodeIfPresent(String.self, forKey: .fieldTemplate) ?? """
        {site}
        {address}
        Account ID: {accountID}
        {technician} • {date} {time}
        """
    }

    private static func requiredFieldTemplate(_ value: String) -> String {
        var result = String(value.prefix(500))
        for token in ["{site}", "{address}", "{accountID}"] where !result.contains(token) {
            if !result.isEmpty, !result.hasSuffix("\n") { result.append("\n") }
            result.append(token)
        }
        return result
    }
}

@MainActor
enum FireVaultOverlayEditorBridge {
    private static var pending: FireVaultOverlayPreferences?

    static func stage(_ overlay: FireVaultOverlayPreferences) {
        pending = overlay.normalized
    }

    static func merge(into overlay: FireVaultOverlayPreferences) -> FireVaultOverlayPreferences {
        guard let pending else { return overlay }
        self.pending = nil
        var merged = overlay
        merged.scale = pending.scale
        merged.positionX = pending.positionX
        merged.positionY = pending.positionY
        merged.logoScale = pending.logoScale
        merged.logoPositionX = pending.logoPositionX
        merged.logoPositionY = pending.logoPositionY
        return merged.normalized
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
    var hapticsEnabled: Bool? = true
    var defaultMapLayer: String?
    var defaultMapIs3D: Bool?
    var tripLogMinimumUnknownStopMinutes: Int?
    var tripLogRejectPoorAccuracyStops: Bool?
    var tripLogMergeNearbyStops: Bool?
    var hapticsAreEnabled: Bool { hapticsEnabled ?? true }
    var resolvedDefaultMapLayer: String { defaultMapLayer ?? "standard" }
    var resolvedDefaultMapIs3D: Bool { defaultMapIs3D ?? true }
    var resolvedTripLogMinimumUnknownStopMinutes: Int {
        tripLogMinimumUnknownStopMinutes ?? 5
    }
    var rejectsPoorAccuracyStops: Bool { tripLogRejectPoorAccuracyStops ?? true }
    var mergesNearbyStops: Bool { tripLogMergeNearbyStops ?? true }
    var normalized: Self {
        var copy = self
        let clamped = min(Self.allowedRadius.upperBound, max(Self.allowedRadius.lowerBound, nearbyRadiusMiles))
        copy.nearbyRadiusMiles = Self.radiusOptions.min { abs($0 - clamped) < abs($1 - clamped) } ?? 1
        if copy.hapticsEnabled == nil { copy.hapticsEnabled = true }
        if !["standard", "satellite", "hybrid"].contains(copy.resolvedDefaultMapLayer) {
            copy.defaultMapLayer = "standard"
        }
        if copy.defaultMapIs3D == nil { copy.defaultMapIs3D = true }
        if ![5, 7, 10].contains(copy.resolvedTripLogMinimumUnknownStopMinutes) {
            copy.tripLogMinimumUnknownStopMinutes = 5
        }
        return copy
    }
    var radiusStatus: String { "\(nearbyRadiusMiles.formatted(.number.precision(.fractionLength(0...2)))) mi" }
    static func radiusLabel(_ value: Double) -> String { "\(value.formatted(.number.precision(.fractionLength(0...2)))) mi" }
    static func radiusWheelLabel(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
}

struct FireVaultPlusCodePreferences: Codable, Equatable { var enabled = true; var autoGenerate = true; var accountLength = 10; var locationLength = 11; var verifyAfterDays = 180; var searchable = true; var includeInReports = true }
struct FireVaultNotificationPreferences: Codable, Equatable {
    var enabled: Bool? = true
    var liveActivitiesEnabled: Bool? = true
    var liveActivityMetricsVisible: Bool? = true
    var tripLogStillRecording: Bool? = true
    var tripLogPaused: Bool? = true
    var upcomingInspections: Bool? = true
    var deliveryFailures: Bool? = true
    var arrivalAlerts: Bool? = false
    var unknownStopReview: Bool? = false
    var sharedAccountUpdates: Bool? = false
    var securityAlerts: Bool? = true
    var hideSensitiveDetails: Bool? = true
    var quietHoursEnabled: Bool? = true
    var quietHoursStart: Int? = 20
    var quietHoursEnd: Int? = 7
    var endOfDayHour: Int? = 18

    var isEnabled: Bool { enabled ?? true }
    var liveActivitiesAreEnabled: Bool { liveActivitiesEnabled ?? true }
    var showsLiveActivityMetrics: Bool { liveActivityMetricsVisible ?? true }
    var recordingReminderEnabled: Bool { tripLogStillRecording ?? true }
    var pausedReminderEnabled: Bool { tripLogPaused ?? true }
    var hidesSensitiveDetails: Bool { hideSensitiveDetails ?? true }
    var usesQuietHours: Bool { quietHoursEnabled ?? true }
    var resolvedQuietStart: Int { min(23, max(0, quietHoursStart ?? 20)) }
    var resolvedQuietEnd: Int { min(23, max(0, quietHoursEnd ?? 7)) }
    var resolvedEndOfDayHour: Int { min(23, max(0, endOfDayHour ?? 18)) }
}
struct FireVaultReportPreferences: Codable, Equatable {
    var title = "FireVault Pro Service Report"
    var format = "detailed"
    var includeTechnician = true
    var includeTasks = true
    var includeDeficiencies = true
    var dailyEmailEnabled = false
    var dailyEmailHour = 18
    var dailyEmailMinute = 0
    var weeklyEmailEnabled = false
    var weeklyEmailWeekday = 6
    var weeklyEmailHour = 18
    var weeklyEmailMinute = 15
    var reportTimeZone = TimeZone.current.identifier

    init() {}

    private enum CodingKeys: String, CodingKey {
        case title, format, includeTechnician, includeTasks, includeDeficiencies
        case dailyEmailEnabled, dailyEmailHour, dailyEmailMinute
        case weeklyEmailEnabled, weeklyEmailWeekday, weeklyEmailHour, weeklyEmailMinute
        case reportTimeZone
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? "FireVault Pro Service Report"
        format = try values.decodeIfPresent(String.self, forKey: .format) ?? "detailed"
        includeTechnician = try values.decodeIfPresent(Bool.self, forKey: .includeTechnician) ?? true
        includeTasks = try values.decodeIfPresent(Bool.self, forKey: .includeTasks) ?? true
        includeDeficiencies = try values.decodeIfPresent(Bool.self, forKey: .includeDeficiencies) ?? true
        dailyEmailEnabled = try values.decodeIfPresent(Bool.self, forKey: .dailyEmailEnabled) ?? false
        dailyEmailHour = try values.decodeIfPresent(Int.self, forKey: .dailyEmailHour) ?? 18
        dailyEmailMinute = try values.decodeIfPresent(Int.self, forKey: .dailyEmailMinute) ?? 0
        weeklyEmailEnabled = try values.decodeIfPresent(Bool.self, forKey: .weeklyEmailEnabled) ?? false
        weeklyEmailWeekday = try values.decodeIfPresent(Int.self, forKey: .weeklyEmailWeekday) ?? 6
        weeklyEmailHour = try values.decodeIfPresent(Int.self, forKey: .weeklyEmailHour) ?? 18
        weeklyEmailMinute = try values.decodeIfPresent(Int.self, forKey: .weeklyEmailMinute) ?? 15
        reportTimeZone = try values.decodeIfPresent(String.self, forKey: .reportTimeZone)
            ?? TimeZone.current.identifier
    }

    var normalized: Self {
        var copy = self
        copy.dailyEmailHour = min(23, max(0, dailyEmailHour))
        copy.dailyEmailMinute = min(59, max(0, dailyEmailMinute))
        copy.weeklyEmailWeekday = min(7, max(1, weeklyEmailWeekday))
        copy.weeklyEmailHour = min(23, max(0, weeklyEmailHour))
        copy.weeklyEmailMinute = min(59, max(0, weeklyEmailMinute))
        if TimeZone(identifier: copy.reportTimeZone) == nil {
            copy.reportTimeZone = TimeZone.current.identifier
        }
        if !["detailed", "compact"].contains(copy.format) {
            copy.format = "detailed"
        }
        return copy
    }
}
struct FireVaultEmailPreferences: Codable, Equatable { var defaultTo = ""; var cc = ""; var defaultSubject = "FireVault Pro Service Report"; var signature = "" }
struct FireVaultStoragePreferences: Codable, Equatable {
    var photoProvider = "local"
    var documentProvider = "local"
    var photoFolder = "FireVault/Photos"
    var documentFolder = "FireVault/Documents"
    var microsoftProfileLabel = ""
    var microsoftEmail = ""
    var sharePointSiteURL = ""
    var libraryName = "Documents"
    var useAccountFolders: Bool?
    var preserveOriginals: Bool?
    var wifiOnlyUploads: Bool?
    var photoQuality: String?
    var scanFormat: String?
}
struct FireVaultSyncPreferences: Codable, Equatable { var organization = ""; var workspace = "FireVault Pro Shared Vault"; var conflictPolicy = "review" }
struct FireVaultWebDAVPreferences: Codable, Equatable { var enabled = false; var serverURL = ""; var username = ""; var folder = "/FireVault" }
struct FireVaultPrivacyPreferences: Codable, Equatable { var enabled = false; var autoLockMinutes = 5; var lockOnBackground = true; var hideInAppSwitcher = true }

enum FireVaultSettingsViewMode: String, Codable, CaseIterable, Identifiable {
    case compact
    case simple
    case advanced

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var detail: String {
        switch self {
        case .compact: "Sections stay collapsed until opened."
        case .simple: "Shows every setting without descriptions."
        case .advanced: "Choose exactly how the Settings list is displayed."
        }
    }
}

enum FireVaultAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System Default"
        }
    }
}

struct FireVaultSettingsViewPreferences: Codable, Equatable {
    var mode: FireVaultSettingsViewMode = .simple
    var advancedCollapseSections = false
    var advancedShowDescriptions = true
    var advancedShowStatus = true
    var advancedShowIcons = true
    var advancedShowSectionDescriptions = true
}

struct FireVaultDeveloperFeature: Identifiable, Equatable {
    let id: String
    let page: String
    let title: String
}

enum FireVaultDeveloperFeatureCatalog {
    static let features: [FireVaultDeveloperFeature] = [
        .init(id: "tab.nearby", page: "Main Navigation", title: "Nearby"),
        .init(id: "tab.accounts", page: "Main Navigation", title: "Accounts"),
        .init(id: "tab.trip", page: "Main Navigation", title: "Trip Log"),
        .init(id: "tab.photo", page: "Main Navigation", title: "Photo"),
        .init(id: "nearby.map", page: "Nearby", title: "Map"),
        .init(id: "nearby.list", page: "Nearby", title: "Nearby Account List"),
        .init(id: "account.brief", page: "Account Detail", title: "Generate Account Brief"),
        .init(id: "account.map", page: "Account Detail", title: "Arrival Map"),
        .init(id: "account.notes", page: "Account Detail", title: "Notes"),
        .init(id: "account.files", page: "Account Detail", title: "Files & Scans"),
        .init(id: "account.equipment", page: "Account Detail", title: "Equipment"),
        .init(id: "account.locations", page: "Account Detail", title: "Locations"),
        .init(id: "account.action.scan", page: "Account Detail", title: "Scan Action"),
        .init(id: "account.action.note", page: "Account Detail", title: "Note Action"),
        .init(id: "account.action.camera", page: "Account Detail", title: "Camera Action"),
        .init(id: "account.action.route", page: "Account Detail", title: "Route Action"),
        .init(id: "settings.field", page: "Settings", title: "Field Tools"),
        .init(id: "settings.reports", page: "Settings", title: "Reports"),
        .init(id: "settings.data", page: "Settings", title: "Data & Security"),
        .init(id: "settings.help", page: "Settings", title: "Help & About")
    ]

    static var pages: [String] {
        features.map(\.page).reduce(into: []) { result, page in
            if !result.contains(page) { result.append(page) }
        }
    }
}

struct FireVaultDeveloperPreferences: Codable, Equatable {
    var simpleFeatureVisibility: [String: Bool] = [:]

    func isEnabled(_ id: String) -> Bool {
        simpleFeatureVisibility[id] ?? true
    }
}

struct FireVaultNativePreferences: Codable, Equatable {
    var technician = FireVaultTechnicianPreferences()
    var overlay = FireVaultOverlayPreferences()
    var gps = FireVaultGPSPreferences()
    var notifications: FireVaultNotificationPreferences? = FireVaultNotificationPreferences()
    var plusCodes = FireVaultPlusCodePreferences()
    var reports = FireVaultReportPreferences()
    var email = FireVaultEmailPreferences()
    var storage = FireVaultStoragePreferences()
    var sync = FireVaultSyncPreferences()
    var webDAV = FireVaultWebDAVPreferences()
    var privacy = FireVaultPrivacyPreferences()
    var categories: [String] = ["Commercial", "Healthcare", "Education", "Government", "Residential"]
    var categoryRules: [FireVaultCategoryRule]? = []
    var categoryStyles: [FireVaultCategoryStyle]? = []
    var normalized: Self {
        var copy = self
        copy.gps = gps.normalized
        copy.overlay = overlay.normalized
        copy.reports = reports.normalized
        if copy.notifications == nil { copy.notifications = FireVaultNotificationPreferences() }
        copy.categories = categories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        copy.categoryRules = (categoryRules ?? []).map {
            var rule = $0
            rule.value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            rule.categoryTag = rule.categoryTag.trimmingCharacters(in: .whitespacesAndNewlines)
            return rule
        }
        copy.categoryStyles = categoryStyles ?? []
        return copy
    }
}

@MainActor
final class FireVaultNativeSettingsStore: ObservableObject {
    private enum Key {
        static let preferences = "firevault.native.settings.all.v2"
        static let settingsView = "firevault.native.settings.view.v1"
        static let developer = "firevault.native.settings.developer.v1"
        static let appearance = "firevault.native.settings.appearance.v1"
    }
    @Published private(set) var preferences: FireVaultNativePreferences
    @Published private(set) var settingsView: FireVaultSettingsViewPreferences
    @Published private(set) var developer: FireVaultDeveloperPreferences
    @Published private(set) var appearance: FireVaultAppearanceMode
    var gps: FireVaultGPSPreferences { preferences.gps }
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.settingsView),
           let saved = try? decoder.decode(FireVaultSettingsViewPreferences.self, from: data) {
            settingsView = saved
        } else {
            settingsView = FireVaultSettingsViewPreferences()
        }
        if let data = defaults.data(forKey: Key.developer),
           let saved = try? decoder.decode(FireVaultDeveloperPreferences.self, from: data) {
            developer = saved
        } else {
            developer = FireVaultDeveloperPreferences()
        }
        appearance = defaults.string(forKey: Key.appearance)
            .flatMap(FireVaultAppearanceMode.init(rawValue:)) ?? .dark
        if let data = defaults.data(forKey: Key.preferences), let saved = try? decoder.decode(FireVaultNativePreferences.self, from: data) {
            preferences = saved.normalized
        } else {
            preferences = FireVaultNativePreferences()
        }
    }

    func save(_ updated: FireVaultNativePreferences) {
        var merged = updated
        merged.overlay = FireVaultOverlayEditorBridge.merge(into: updated.overlay)
        preferences = merged.normalized
        persist()
    }

    func restore(
        _ backup: FireVaultNativePreferences,
        settingsView backupSettingsView: FireVaultSettingsViewPreferences? = nil,
        appearance backupAppearance: FireVaultAppearanceMode? = nil
    ) {
        preferences = backup.normalized
        persist()
        if let backupSettingsView {
            saveSettingsView(backupSettingsView)
        }
        if let backupAppearance {
            saveAppearance(backupAppearance)
        }
    }

    func saveGPS(_ updated: FireVaultGPSPreferences) {
        var next = preferences; next.gps = updated; save(next)
    }

    func saveSettingsView(_ updated: FireVaultSettingsViewPreferences) {
        settingsView = updated
        guard let data = try? encoder.encode(updated) else { return }
        defaults.set(data, forKey: Key.settingsView)
    }

    func saveAppearance(_ updated: FireVaultAppearanceMode) {
        appearance = updated
        defaults.set(updated.rawValue, forKey: Key.appearance)
    }

    func isFeatureVisible(_ id: String) -> Bool {
        settingsView.mode != .simple || developer.isEnabled(id)
    }

    func setSimpleFeature(_ id: String, enabled: Bool) {
        developer.simpleFeatureVisibility[id] = enabled
        persistDeveloper()
    }

    func resetSimpleFeatures() {
        developer = FireVaultDeveloperPreferences()
        persistDeveloper()
    }

    private func persistDeveloper() {
        guard let data = try? encoder.encode(developer) else { return }
        defaults.set(data, forKey: Key.developer)
    }

    private func persist() {
        guard let data = try? encoder.encode(preferences) else { return }
        defaults.set(data, forKey: Key.preferences)
    }
}
