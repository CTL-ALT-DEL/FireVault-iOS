//
//  FireVaultCloudVaultBackup.swift
//  FireVault
//
//  Small, metadata-only cloud recovery points. Field-media bytes are backed
//  up separately and are intentionally excluded from these snapshots.
//

import CryptoKit
import Compression
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
        try FireVaultPaidFeatureAccess.requireCached(.cloudStorage)
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
        try FireVaultPaidFeatureAccess.requireCached(.cloudStorage)
        let data = try payload.encoded()
        guard data.count <= maximumSnapshotBytes else {
            throw FireVaultCloudVaultError.snapshotTooLarge
        }
        let digest = sha256(data)
        let existing = try await listSnapshots()
        if let matching = existing.first(where: { $0.sha256 == digest }) {
            try await pruneSnapshots(existing)
            return .unchanged(matching)
        }

        let session = try await SupabaseManager.client.auth.session
        let insert = CloudVaultSnapshotInsert(
            userID: session.user.id,
            deviceLabel: normalizedDeviceLabel(deviceLabel),
            schemaVersion: payload.schemaVersion,
            payload: try FireVaultCloudVaultArchiveCodec.encode(data),
            sha256: digest,
            accountCount: payload.accounts.count,
            tripLogDayCount: payload.tripLogDays.count
        )
        let rows: [FireVaultCloudVaultSnapshot]
        do {
            rows = try await SupabaseManager.client
                .from("cloud_vault_snapshots")
                .insert(insert)
                .select(summarySelect)
                .execute()
                .value
        } catch {
            // A mobile upload can reach Postgres just before URLSession reports
            // a timeout. Confirm the SHA before surfacing a false failure; the
            // unique (user_id, sha256) constraint makes this retry-safe.
            if let confirmed = try? await listSnapshots(),
               let matching = confirmed.first(where: { $0.sha256 == digest }) {
                try? await pruneSnapshots(confirmed)
                return .unchanged(matching)
            }
            throw error
        }
        guard let created = rows.first else { throw FireVaultCloudVaultError.snapshotUnavailable }

        let refreshed = try await listSnapshots()
        try await pruneSnapshots(refreshed)
        return .created(created)
    }

    private static func pruneSnapshots(_ snapshots: [FireVaultCloudVaultSnapshot]) async throws {
        guard snapshots.count > retainedSnapshotCount else { return }
        let session = try await SupabaseManager.client.auth.session
        for stale in snapshots.dropFirst(retainedSnapshotCount) {
            try await SupabaseManager.client
                .from("cloud_vault_snapshots")
                .delete()
                .eq("id", value: stale.id)
                .eq("user_id", value: session.user.id)
                .execute()
        }
    }

    static func downloadSnapshot(id: UUID) async throws -> FireVaultCloudVaultPayload {
        try FireVaultPaidFeatureAccess.requireCached(.cloudStorage)
        let session = try await SupabaseManager.client.auth.session
        let rows: [CloudVaultSnapshotDownload] = try await SupabaseManager.client
            .from("cloud_vault_snapshots")
            .select("id,sha256,payload")
            .eq("id", value: id)
            .eq("user_id", value: session.user.id)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else {
            throw FireVaultCloudVaultError.snapshotUnavailable
        }
        let data = try FireVaultCloudVaultArchiveCodec.decode(row.payload)
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

struct CloudVaultSnapshotEnvelope: Codable, Equatable {
    let archive: String
    let compression: String?
    let uncompressedSize: Int?

    init(archive: String, compression: String? = nil, uncompressedSize: Int? = nil) {
        self.archive = archive
        self.compression = compression
        self.uncompressedSize = uncompressedSize
    }
}

enum FireVaultCloudVaultArchiveCodec {
    private static let lzfse = "lzfse"

    static func encode(_ data: Data) throws -> CloudVaultSnapshotEnvelope {
        guard !data.isEmpty, let compressed = compress(data), compressed.count < data.count else {
            return .init(archive: data.base64EncodedString())
        }
        return .init(
            archive: compressed.base64EncodedString(),
            compression: lzfse,
            uncompressedSize: data.count
        )
    }

    static func decode(_ envelope: CloudVaultSnapshotEnvelope) throws -> Data {
        guard let stored = Data(base64Encoded: envelope.archive) else {
            throw FireVaultCloudVaultError.snapshotUnavailable
        }
        guard let compression = envelope.compression else { return stored }
        guard compression == lzfse,
              let expectedSize = envelope.uncompressedSize,
              expectedSize >= 0,
              expectedSize <= FireVaultCloudVaultBackupService.maximumSnapshotBytes,
              let restored = decompress(stored, expectedSize: expectedSize) else {
            throw FireVaultCloudVaultError.damagedSnapshot
        }
        return restored
    }

    private static func compress(_ data: Data) -> Data? {
        var destination = Data(count: data.count + 65_536)
        let written = data.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let output = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(
                    output,
                    destinationBuffer.count,
                    source,
                    sourceBuffer.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard written > 0 else { return nil }
        destination.count = written
        return destination
    }

    private static func decompress(_ data: Data, expectedSize: Int) -> Data? {
        if expectedSize == 0 { return data.isEmpty ? Data() : nil }
        var destination = Data(count: expectedSize)
        let written = data.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let output = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    output,
                    destinationBuffer.count,
                    source,
                    sourceBuffer.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard written == expectedSize else { return nil }
        return destination
    }
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
