//
//  FireVaultCloudVaultBackup.swift
//  FireVault
//
//  Small, metadata-only cloud recovery points. Field-media bytes are backed
//  up separately and are intentionally excluded from these snapshots.
//

import CryptoKit
import Foundation
import Supabase

struct FireVaultCloudVaultPayload: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let formatIdentifier = "FireVault.CloudVault"

    var format = Self.formatIdentifier
    var schemaVersion = Self.currentSchemaVersion
    var accounts: [FireVaultWorkspaceAccount]
    var preferences: FireVaultNativePreferences
    var settingsView: FireVaultSettingsViewPreferences
    var appearance: FireVaultAppearanceMode
    var tripLogDays: [FireVaultBreadcrumbDay]

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
            throw FireVaultCloudVaultError.unsupportedFormat
        }
        return payload
    }
}

struct FireVaultCloudVaultSnapshot: Decodable, Identifiable, Equatable {
    let id: UUID
    let deviceLabel: String
    let schemaVersion: Int
    let sha256: String
    let accountCount: Int
    let tripLogDayCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceLabel = "device_label"
        case schemaVersion = "schema_version"
        case sha256
        case accountCount = "account_count"
        case tripLogDayCount = "trip_log_day_count"
        case createdAt = "created_at"
    }
}

enum FireVaultCloudVaultBackupResult: Equatable {
    case created(FireVaultCloudVaultSnapshot)
    case unchanged(FireVaultCloudVaultSnapshot)
}

enum FireVaultCloudVaultError: LocalizedError {
    case unsupportedFormat
    case damagedSnapshot
    case snapshotTooLarge
    case snapshotUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "This cloud recovery point was created by an unsupported FireVault version."
        case .damagedSnapshot:
            "The cloud recovery point failed its SHA-256 integrity check and was not restored."
        case .snapshotTooLarge:
            "This field-data recovery point is too large to upload safely. Field media remains backed up separately."
        case .snapshotUnavailable:
            "The selected cloud recovery point is no longer available."
        }
    }
}

enum FireVaultCloudVaultBackupService {
    static let maximumSnapshotBytes = 25 * 1_024 * 1_024
    static let retainedSnapshotCount = 3
    private static let summarySelect = "id,device_label,schema_version,sha256,account_count,trip_log_day_count,created_at"

    static func listSnapshots() async throws -> [FireVaultCloudVaultSnapshot] {
        let session = try await SupabaseManager.client.auth.session
        return try await SupabaseManager.client
            .from("cloud_vault_snapshots")
            .select(summarySelect)
            .eq("user_id", value: session.user.id)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func createSnapshot(
        payload: FireVaultCloudVaultPayload,
        deviceLabel: String = "iPhone"
    ) async throws -> FireVaultCloudVaultBackupResult {
        let data = try payload.encoded()
        guard data.count <= maximumSnapshotBytes else {
            throw FireVaultCloudVaultError.snapshotTooLarge
        }
        let digest = sha256(data)
        let existing = try await listSnapshots()
        if let matching = existing.first(where: { $0.sha256 == digest }) {
            return .unchanged(matching)
        }

        let session = try await SupabaseManager.client.auth.session
        let rows: [FireVaultCloudVaultSnapshot] = try await SupabaseManager.client
            .from("cloud_vault_snapshots")
            .insert(CloudVaultSnapshotInsert(
                userID: session.user.id,
                deviceLabel: normalizedDeviceLabel(deviceLabel),
                schemaVersion: payload.schemaVersion,
                payload: .init(archive: data.base64EncodedString()),
                sha256: digest,
                accountCount: payload.accounts.count,
                tripLogDayCount: payload.tripLogDays.count
            ))
            .select(summarySelect)
            .execute()
            .value
        guard let created = rows.first else { throw FireVaultCloudVaultError.snapshotUnavailable }

        let refreshed = try await listSnapshots()
        for stale in refreshed.dropFirst(retainedSnapshotCount) {
            try await SupabaseManager.client
                .from("cloud_vault_snapshots")
                .delete()
                .eq("id", value: stale.id)
                .eq("user_id", value: session.user.id)
                .execute()
        }
        return .created(created)
    }

    static func downloadSnapshot(id: UUID) async throws -> FireVaultCloudVaultPayload {
        let session = try await SupabaseManager.client.auth.session
        let rows: [CloudVaultSnapshotDownload] = try await SupabaseManager.client
            .from("cloud_vault_snapshots")
            .select("id,sha256,payload")
            .eq("id", value: id)
            .eq("user_id", value: session.user.id)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first,
              let data = Data(base64Encoded: row.payload.archive) else {
            throw FireVaultCloudVaultError.snapshotUnavailable
        }
        guard sha256(data) == row.sha256 else { throw FireVaultCloudVaultError.damagedSnapshot }
        return try FireVaultCloudVaultPayload.decode(data)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedDeviceLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? "iPhone" : trimmed).prefix(80))
    }
}

@MainActor
enum FireVaultCloudVaultBackupCoordinator {
    static func payload(
        store: FireVaultStore,
        settings: FireVaultNativeSettingsStore,
        breadcrumbs: FireVaultBreadcrumbStore
    ) -> FireVaultCloudVaultPayload {
        .init(
            accounts: store.accounts,
            preferences: settings.preferences,
            settingsView: settings.settingsView,
            appearance: settings.appearance,
            tripLogDays: breadcrumbs.days
        )
    }

    static func restore(
        _ payload: FireVaultCloudVaultPayload,
        store: FireVaultStore,
        settings: FireVaultNativeSettingsStore,
        breadcrumbs: FireVaultBreadcrumbStore
    ) throws -> FireVaultFullRestoreResult {
        let accountResult = try store.mergeCloudVaultAccounts(payload.accounts)
        let tripResult = breadcrumbs.mergeBackupDays(payload.tripLogDays, restoredAt: Date())
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
            mediaFilesRestored: 0
        )
    }
}

private struct CloudVaultSnapshotEnvelope: Codable {
    let archive: String
}

private struct CloudVaultSnapshotInsert: Encodable {
    let userID: UUID
    let deviceLabel: String
    let schemaVersion: Int
    let payload: CloudVaultSnapshotEnvelope
    let sha256: String
    let accountCount: Int
    let tripLogDayCount: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case deviceLabel = "device_label"
        case schemaVersion = "schema_version"
        case payload
        case sha256
        case accountCount = "account_count"
        case tripLogDayCount = "trip_log_day_count"
    }
}

private struct CloudVaultSnapshotDownload: Decodable {
    let id: UUID
    let sha256: String
    let payload: CloudVaultSnapshotEnvelope
}
