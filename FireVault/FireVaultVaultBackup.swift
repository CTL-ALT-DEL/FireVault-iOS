//
//  FireVaultVaultBackup.swift
//  FireVault
//
//  Versioned, self-contained backup format for accounts, preferences,
//  Trip Log history, and referenced field media.
//

import CryptoKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let fireVaultBackup = UTType(
        exportedAs: "us.bannerman.firevault.backup",
        conformingTo: .data
    )
}

struct FireVaultVaultMediaRecord: Codable, Equatable {
    var accountID: String
    var fileName: String
    var data: Data
    var sha256: String

    init(accountID: String, fileName: String, data: Data) {
        self.accountID = accountID
        self.fileName = fileName
        self.data = data
        sha256 = Self.digest(data)
    }

    var isValid: Bool {
        !accountID.isEmpty
            && fileName == URL(fileURLWithPath: fileName).lastPathComponent
            && !fileName.isEmpty
            && sha256 == Self.digest(data)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct FireVaultVaultBackupPayload: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let formatIdentifier = "FireVault.FullVault"

    var format = Self.formatIdentifier
    var schemaVersion = Self.currentSchemaVersion
    var createdAt = Date()
    var appVersion: String
    var accounts: [FireVaultWorkspaceAccount]
    var preferences: FireVaultNativePreferences
    var settingsView: FireVaultSettingsViewPreferences
    var appearance: FireVaultAppearanceMode
    var tripLogDays: [FireVaultBreadcrumbDay]
    var media: [FireVaultVaultMediaRecord]

    func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        let payload = try PropertyListDecoder().decode(Self.self, from: data)
        guard payload.format == formatIdentifier,
              payload.schemaVersion > 0,
              payload.schemaVersion <= currentSchemaVersion else {
            throw FireVaultVaultBackupError.unsupportedFormat
        }
        guard payload.media.allSatisfy(\.isValid) else {
            throw FireVaultVaultBackupError.damagedMedia
        }
        let mediaByteCount = payload.media.reduce(into: Int64(0)) { total, record in
            total += Int64(record.data.count)
        }
        guard payload.media.count <= 20_000,
              payload.media.allSatisfy({ $0.data.count <= 250_000_000 }),
              mediaByteCount <= 20_000_000_000 else {
            throw FireVaultVaultBackupError.backupTooLarge
        }
        return payload
    }
}

struct FireVaultFullRestoreResult: Equatable {
    var accountsAdded: Int
    var accountsPreserved: Int
    var tripLogDaysAdded: Int
    var tripLogDaysPreserved: Int
    var mediaFilesRestored: Int
}

enum FireVaultVaultBackupError: LocalizedError {
    case unsupportedFormat
    case damagedMedia
    case backupTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "This is not a supported FireVault full-vault backup."
        case .damagedMedia:
            "The backup contains damaged or unsafe media files and was not restored."
        case .backupTooLarge:
            "The backup exceeds FireVault's safe restore limits."
        }
    }
}

@MainActor
enum FireVaultVaultBackupCoordinator {
    static func export(
        store: FireVaultStore,
        settings: FireVaultNativeSettingsStore,
        breadcrumbs: FireVaultBreadcrumbStore
    ) throws -> Data {
        try FireVaultVaultBackupPayload(
            appVersion: FireVaultVersionInfo().version,
            accounts: store.accounts,
            preferences: settings.preferences,
            settingsView: settings.settingsView,
            appearance: settings.appearance,
            tripLogDays: breadcrumbs.days,
            media: store.backupMediaRecords()
        ).encoded()
    }

    static func restore(
        _ data: Data,
        store: FireVaultStore,
        settings: FireVaultNativeSettingsStore,
        breadcrumbs: FireVaultBreadcrumbStore
    ) throws -> FireVaultFullRestoreResult {
        let payload = try FireVaultVaultBackupPayload.decode(data)
        let accountData = try JSONEncoder().encode(payload.accounts)
        let accountResult = try store.mergeAccountsBackup(accountData)
        let restoredAccountIDs = Set(payload.accounts.map(\.id))
        let mediaCount = try store.installBackupMedia(
            payload.media,
            allowedAccountIDs: restoredAccountIDs
        )
        let tripResult = breadcrumbs.mergeBackupDays(payload.tripLogDays, restoredAt: payload.createdAt)
        settings.restore(
            payload.preferences,
            settingsView: payload.settingsView,
            appearance: payload.appearance
        )
        store.configureCategoryRules(payload.preferences.categoryRules ?? [])
        return .init(
            accountsAdded: accountResult.added,
            accountsPreserved: accountResult.preserved,
            tripLogDaysAdded: tripResult.added,
            tripLogDaysPreserved: tripResult.preserved,
            mediaFilesRestored: mediaCount
        )
    }
}
