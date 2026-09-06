//
//  FireVaultFieldMediaBackup.swift
//  FireVault
//
//  Durable, local-first automatic backup for account-linked field media.
//

import Combine
import CryptoKit
import Foundation
import Network
import Supabase
import UniformTypeIdentifiers

enum FireVaultFieldMediaCategory: String, Codable, CaseIterable, Sendable {
    case documents
    case photos
    case scans
    case reports
    case other
}

enum FireVaultFieldMediaBackupState: String, Codable, Hashable, Sendable {
    case waiting
    case uploading
    case backedUp
    case failed
}

struct FireVaultFieldMediaUploadReceipt: Codable, Hashable, Sendable {
    let storagePath: String
    let sha256: String
    let fileSizeBytes: Int64
    let duplicate: Bool
}

struct FireVaultFieldMediaBackupItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// Device-local account identifier. This is retained so a queued item can
    /// acquire its cloud UUID after account sync completes.
    let localAccountID: String
    var userID: UUID?
    /// public.accounts.id. Never substitute the displayed account number.
    var accountID: UUID?
    var accountNumber: String?
    let localFileURL: URL
    let originalFilename: String
    let category: FireVaultFieldMediaCategory
    let mimeType: String?
    let fileModifiedAt: Date?
    let variant: String
    let createdAt: Date

    var state: FireVaultFieldMediaBackupState
    var retryCount: Int
    var nextAttemptAt: Date?
    var lastError: String?
    var receipt: FireVaultFieldMediaUploadReceipt?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        localAccountID: String,
        userID: UUID?,
        accountID: UUID?,
        accountNumber: String? = nil,
        localFileURL: URL,
        originalFilename: String,
        category: FireVaultFieldMediaCategory,
        mimeType: String? = nil,
        fileModifiedAt: Date? = nil,
        variant: String = "original",
        createdAt: Date = Date(),
        state: FireVaultFieldMediaBackupState = .waiting,
        retryCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastError: String? = nil,
        receipt: FireVaultFieldMediaUploadReceipt? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.localAccountID = localAccountID
        self.userID = userID
        self.accountID = accountID
        self.accountNumber = accountNumber
        self.localFileURL = localFileURL
        self.originalFilename = originalFilename
        self.category = category
        self.mimeType = mimeType
        self.fileModifiedAt = fileModifiedAt
        self.variant = variant
        self.createdAt = createdAt
        self.state = state
        self.retryCount = retryCount
        self.nextAttemptAt = nextAttemptAt
        self.lastError = lastError
        self.receipt = receipt
        self.completedAt = completedAt
    }
}

enum FireVaultFieldMediaUploadError: LocalizedError, Sendable {
    case fileMissing
    case fileTooLarge(Int64)
    case unsupportedMimeType(String?)
    case accountNotSynced
    case signedInUserMismatch

    var errorDescription: String? {
        switch self {
        case .fileMissing:
            "The local media file is no longer available."
        case .fileTooLarge(let bytes):
            "The media file is \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)); FireVault Cloud allows up to 50 MB per file."
        case .unsupportedMimeType(let mime):
            "This file type is not supported for Field Media backup: \(mime ?? "unknown")."
        case .accountNotSynced:
            "Waiting for this account to finish cloud sync."
        case .signedInUserMismatch:
            "This backup belongs to a different FireVault sign-in."
        }
    }

    var automaticallyRetryable: Bool {
        switch self {
        case .fileMissing, .fileTooLarge, .unsupportedMimeType, .signedInUserMismatch:
            false
        case .accountNotSynced:
            true
        }
    }
}

actor FireVaultFieldMediaBackupStore {
    private let fileURL: URL
    private var items: [FireVaultFieldMediaBackupItem]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) throws {
        let resolvedURL: URL
        if let fileURL {
            resolvedURL = fileURL
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } else {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let folder = base.appendingPathComponent("FireVault", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            resolvedURL = folder.appendingPathComponent("field-media-backup-queue.json")
        }
        self.fileURL = resolvedURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        var recoveredInterruptedUpload = false
        if let data = try? Data(contentsOf: resolvedURL), !data.isEmpty {
            var decoded = try decoder.decode([FireVaultFieldMediaBackupItem].self, from: data)
            for index in decoded.indices where decoded[index].state == .uploading {
                decoded[index].state = .waiting
                decoded[index].retryCount += 1
                decoded[index].nextAttemptAt = Date()
                decoded[index].lastError = "Upload interrupted; queued for retry."
                recoveredInterruptedUpload = true
            }
            items = decoded
        } else {
            items = []
        }

        if recoveredInterruptedUpload {
            let data = try encoder.encode(items)
            try data.write(
                to: resolvedURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        }
    }

    @discardableResult
    func enqueueIfNeeded(_ item: FireVaultFieldMediaBackupItem) throws -> UUID {
        let targetPath = item.localFileURL.standardizedFileURL.path
        if let existing = items.first(where: {
            $0.localAccountID == item.localAccountID
                && $0.localFileURL.standardizedFileURL.path == targetPath
                && $0.variant == item.variant
                && $0.fileModifiedAt == item.fileModifiedAt
        }) {
            return existing.id
        }
        items.append(item)
        try persist()
        return item.id
    }

    func allItems() -> [FireVaultFieldMediaBackupItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    func pendingItems(activeUserID: UUID, now: Date = Date()) -> [FireVaultFieldMediaBackupItem] {
        items
            .filter { item in
                guard item.userID == activeUserID, item.accountID != nil else { return false }
                switch item.state {
                case .waiting:
                    return item.nextAttemptAt == nil || item.nextAttemptAt! <= now
                case .failed:
                    return item.nextAttemptAt.map { $0 <= now } ?? false
                case .uploading, .backedUp:
                    return false
                }
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func claimUnownedItems(for userID: UUID) throws {
        var changed = false
        for index in items.indices where items[index].userID == nil {
            items[index].userID = userID
            changed = true
        }
        if changed { try persist() }
    }

    func linkAccounts(_ links: [String: UUID], accountNumbers: [String: String]) throws {
        var changed = false
        for index in items.indices {
            if let accountID = links[items[index].localAccountID], items[index].accountID != accountID {
                items[index].accountID = accountID
                items[index].lastError = nil
                changed = true
            }
            if let number = accountNumbers[items[index].localAccountID], items[index].accountNumber != number {
                items[index].accountNumber = number
                changed = true
            }
        }
        if changed { try persist() }
    }

    func markUploading(_ id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .uploading
        items[index].lastError = nil
        try persist()
    }

    func markBackedUp(_ id: UUID, receipt: FireVaultFieldMediaUploadReceipt) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .backedUp
        items[index].receipt = receipt
        items[index].completedAt = Date()
        items[index].nextAttemptAt = nil
        items[index].lastError = nil
        try persist()
    }

    func markFailed(
        _ id: UUID,
        message: String,
        retryCount: Int,
        nextAttemptAt: Date?
    ) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .failed
        items[index].retryCount = retryCount
        items[index].nextAttemptAt = nextAttemptAt
        items[index].lastError = message
        try persist()
    }

    func retryNow(_ id: UUID) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .waiting
        items[index].nextAttemptAt = Date()
        items[index].lastError = nil
        try persist()
    }

    func retryAllFailed() throws {
        var changed = false
        for index in items.indices where items[index].state == .failed {
            items[index].state = .waiting
            items[index].nextAttemptAt = Date()
            items[index].lastError = nil
            changed = true
        }
        if changed { try persist() }
    }

    func removePending(localFileURLs: [URL]) throws {
        let paths = Set(localFileURLs.map { $0.standardizedFileURL.path })
        items.removeAll {
            paths.contains($0.localFileURL.standardizedFileURL.path) && $0.state != .backedUp
        }
        try persist()
    }

    func removePending(variant: String) throws {
        items.removeAll { $0.variant == variant && $0.state != .backedUp }
        try persist()
    }

    func removePending(localAccountID: String) throws {
        items.removeAll { $0.localAccountID == localAccountID && $0.state != .backedUp }
        try persist()
    }

    func removeAll() throws {
        items.removeAll()
        try persist()
    }

    func pruneBackedUp(olderThan days: Int = 7) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        items.removeAll {
            $0.state == .backedUp && ($0.completedAt ?? .distantFuture) < cutoff
        }
        try persist()
    }

    private func persist() throws {
        let data = try encoder.encode(items)
        try data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

protocol FireVaultFieldMediaUploader: Sendable {
    func upload(_ item: FireVaultFieldMediaBackupItem) async throws -> FireVaultFieldMediaUploadReceipt
}

actor FireVaultFieldMediaBackupCoordinator {
    private let store: FireVaultFieldMediaBackupStore
    private let uploader: any FireVaultFieldMediaUploader
    private var isProcessing = false

    init(store: FireVaultFieldMediaBackupStore, uploader: any FireVaultFieldMediaUploader) {
        self.store = store
        self.uploader = uploader
    }

    func processPending(activeUserID: UUID) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        for item in await store.pendingItems(activeUserID: activeUserID) {
            do {
                try Task.checkCancellation()
                try await store.markUploading(item.id)
                let receipt = try await uploader.upload(item)
                try await store.markBackedUp(item.id, receipt: receipt)
            } catch is CancellationError {
                try? await store.markFailed(
                    item.id,
                    message: "Upload paused; it will resume automatically.",
                    retryCount: item.retryCount,
                    nextAttemptAt: Date()
                )
                return
            } catch {
                let retryCount = item.retryCount + 1
                let uploadError = error as? FireVaultFieldMediaUploadError
                let shouldRetry = uploadError?.automaticallyRetryable ?? true
                let nextAttempt = shouldRetry
                    ? Date().addingTimeInterval(Self.backoffSeconds(for: retryCount))
                    : nil
                try? await store.markFailed(
                    item.id,
                    message: error.localizedDescription,
                    retryCount: retryCount,
                    nextAttemptAt: nextAttempt
                )
            }
        }
    }

    static func backoffSeconds(for retryCount: Int) -> TimeInterval {
        switch retryCount {
        case ...1: 60
        case 2: 5 * 60
        case 3: 15 * 60
        case 4: 60 * 60
        default: 4 * 60 * 60
        }
    }
}

final class FireVaultSupabaseFieldMediaUploader: FireVaultFieldMediaUploader, @unchecked Sendable {
    static let bucketID = "firevault-user-files"
    static let maxFileSizeBytes: Int64 = 50 * 1024 * 1024

    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseManager.client) {
        self.supabase = supabase
    }

    func upload(_ item: FireVaultFieldMediaBackupItem) async throws -> FireVaultFieldMediaUploadReceipt {
        guard let userID = item.userID else {
            throw FireVaultFieldMediaUploadError.signedInUserMismatch
        }
        guard let accountID = item.accountID else {
            throw FireVaultFieldMediaUploadError.accountNotSynced
        }
        let session = try await supabase.auth.session
        guard session.user.id == userID else {
            throw FireVaultFieldMediaUploadError.signedInUserMismatch
        }
        guard FileManager.default.fileExists(atPath: item.localFileURL.path) else {
            throw FireVaultFieldMediaUploadError.fileMissing
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: item.localFileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize <= Self.maxFileSizeBytes else {
            throw FireVaultFieldMediaUploadError.fileTooLarge(fileSize)
        }

        let mimeType = item.mimeType ?? FireVaultFieldMediaMIME.detect(for: item.localFileURL)
        guard Self.allowedMimeTypes.contains(mimeType ?? "") else {
            throw FireVaultFieldMediaUploadError.unsupportedMimeType(mimeType)
        }
        let sha256 = try FireVaultFieldMediaHash.sha256Hex(of: item.localFileURL)

        let existingFile = try await findExisting(
            userID: userID,
            accountID: accountID,
            sha256: sha256
        )
        if let existing = existingFile {
            return .init(
                storagePath: existing.storagePath,
                sha256: sha256,
                fileSizeBytes: fileSize,
                duplicate: true
            )
        }

        let storagePath = Self.makeStoragePath(
            userID: userID,
            accountID: accountID,
            category: item.category,
            queueID: item.id,
            originalFilename: item.originalFilename
        )

        // The path is deterministic for this queue item. If the process was
        // interrupted after object upload but before metadata registration,
        // clear that unregistered object before attempting the same upload.
        // A completed metadata row is detected by SHA-256 above and is never
        // removed here.
        if item.retryCount > 0 {
            try? await supabase.storage
                .from(Self.bucketID)
                .remove(paths: [storagePath])
        }

        try await supabase.storage
            .from(Self.bucketID)
            .upload(
                storagePath,
                fileURL: item.localFileURL,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: mimeType,
                    upsert: false
                )
            )

        do {
            try await supabase
                .from("account_files")
                .insert(
                    FireVaultAccountFileInsert(
                        userID: userID,
                        accountID: accountID,
                        bucketID: Self.bucketID,
                        storagePath: storagePath,
                        originalFilename: item.originalFilename,
                        category: item.category.rawValue,
                        mimeType: mimeType,
                        fileSizeBytes: fileSize,
                        fileModifiedAt: item.fileModifiedAt.map(Self.timestamp),
                        sha256: sha256,
                        source: "ios_app",
                        metadata: [
                            "queue_id": item.id.uuidString.lowercased(),
                            "variant": item.variant,
                            "account_number": item.accountNumber ?? ""
                        ]
                    )
                )
                .execute()
        } catch {
            let registrationError = error

            // A lost response can look like a failed insert even when the row
            // committed. Verify by SHA before cleaning anything. If another
            // device won the duplicate race, remove only this queue item's
            // unregistered object and adopt the existing receipt.
            let existingAfterFailure: FireVaultExistingAccountFile?
            do {
                existingAfterFailure = try await findExisting(
                    userID: userID,
                    accountID: accountID,
                    sha256: sha256
                )
            } catch {
                existingAfterFailure = nil
            }
            if let existing = existingAfterFailure {
                if existing.storagePath != storagePath {
                    try? await supabase.storage
                        .from(Self.bucketID)
                        .remove(paths: [storagePath])
                }
                return .init(
                    storagePath: existing.storagePath,
                    sha256: sha256,
                    fileSizeBytes: fileSize,
                    duplicate: existing.storagePath != storagePath
                )
            }

            // If verification is also unavailable, preserve the object. The
            // next queued attempt checks metadata first, then removes this
            // deterministic path only when no registration row exists.
            throw registrationError
        }

        return .init(
            storagePath: storagePath,
            sha256: sha256,
            fileSizeBytes: fileSize,
            duplicate: false
        )
    }

    private func findExisting(
        userID: UUID,
        accountID: UUID,
        sha256: String
    ) async throws -> FireVaultExistingAccountFile? {
        let rows: [FireVaultExistingAccountFile] = try await supabase
            .from("account_files")
            .select("id,storage_path")
            .eq("user_id", value: userID)
            .eq("account_id", value: accountID)
            .eq("sha256", value: sha256)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private static func makeStoragePath(
        userID: UUID,
        accountID: UUID,
        category: FireVaultFieldMediaCategory,
        queueID: UUID,
        originalFilename: String
    ) -> String {
        let safeName = sanitizeFilename(originalFilename)
        let uniqueName = "\(queueID.uuidString.lowercased())-\(safeName)"
        return "\(userID.uuidString.lowercased())/accounts/\(accountID.uuidString.lowercased())/\(category.rawValue)/\(uniqueName)"
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "-",
            options: .regularExpression
        )
        return safe.isEmpty ? "field-media" : safe
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static let allowedMimeTypes: Set<String> = [
        "application/pdf",
        "application/msword",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.ms-excel",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "text/csv",
        "text/plain",
        "application/rtf",
        "text/rtf",
        "image/jpeg",
        "image/png",
        "image/heic",
        "image/heif",
        "image/webp"
    ]
}

private struct FireVaultExistingAccountFile: Decodable {
    let id: UUID
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case storagePath = "storage_path"
    }
}

private struct FireVaultAccountFileInsert: Encodable {
    let userID: UUID
    let accountID: UUID
    let bucketID: String
    let storagePath: String
    let originalFilename: String
    let category: String
    let mimeType: String?
    let fileSizeBytes: Int64
    let fileModifiedAt: String?
    let sha256: String
    let source: String
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case accountID = "account_id"
        case bucketID = "bucket_id"
        case storagePath = "storage_path"
        case originalFilename = "original_filename"
        case category
        case mimeType = "mime_type"
        case fileSizeBytes = "file_size_bytes"
        case fileModifiedAt = "file_modified_at"
        case sha256
        case source
        case metadata
    }
}

enum FireVaultFieldMediaHash {
    static func sha256Hex(of fileURL: URL, chunkSize: Int = 1_048_576) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum FireVaultFieldMediaMIME {
    static func detect(for fileURL: URL) -> String? {
        let ext = fileURL.pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        return switch ext {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "heic": "image/heic"
        case "heif": "image/heif"
        case "webp": "image/webp"
        case "pdf": "application/pdf"
        case "txt": "text/plain"
        case "csv": "text/csv"
        case "rtf": "application/rtf"
        case "doc": "application/msword"
        case "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": "application/vnd.ms-excel"
        case "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        default: nil
        }
    }
}

@MainActor
final class FireVaultFieldMediaBackupService: ObservableObject {
    static let shared = FireVaultFieldMediaBackupService()

    @Published private(set) var items: [FireVaultFieldMediaBackupItem] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var networkStatusText = "Checking connection"
    @Published private(set) var initializationError: String?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "us.bannerman.firevault.field-media-network")
    private let store: FireVaultFieldMediaBackupStore?
    private let coordinator: FireVaultFieldMediaBackupCoordinator?
    private var storagePreferences = FireVaultStoragePreferences()
    private var isDemoMode = true
    private var networkAvailable = false
    private var usingWiFi = false
    private var retryTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    private init() {
        do {
            let store = try FireVaultFieldMediaBackupStore()
            self.store = store
            coordinator = FireVaultFieldMediaBackupCoordinator(
                store: store,
                uploader: FireVaultSupabaseFieldMediaUploader()
            )
        } catch {
            store = nil
            coordinator = nil
            initializationError = error.localizedDescription
        }

        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in
                guard let self else { return }
                networkAvailable = available
                usingWiFi = wifi
                networkStatusText = available ? (wifi ? "Wi-Fi" : "Cellular or wired") : "Offline"
                if networkAllowsUploads { await processPending() }
            }
        }
        monitor.start(queue: monitorQueue)
        Task { await refreshItems() }
    }

    var isEnabled: Bool {
        !isDemoMode && (storagePreferences.automaticFieldMediaBackup ?? false)
    }

    var waitingCount: Int { items.filter { $0.state == .waiting }.count }
    var failedCount: Int { items.filter { $0.state == .failed }.count }
    var backedUpCount: Int { items.filter { $0.state == .backedUp }.count }

    var summaryText: String {
        if let initializationError { return "Backup queue unavailable: \(initializationError)" }
        if isDemoMode { return "Demo media stays on this iPhone" }
        if !isEnabled { return "Automatic cloud backup is off" }
        if isProcessing { return "Uploading field media" }
        if failedCount > 0 { return "\(failedCount) backup\(failedCount == 1 ? "" : "s") need attention" }
        if waitingCount > 0 {
            if !networkAllowsUploads { return storagePreferences.wifiOnlyUploads == true ? "Waiting for Wi-Fi" : "Waiting for a connection" }
            return "\(waitingCount) backup\(waitingCount == 1 ? "" : "s") waiting"
        }
        return backedUpCount > 0 ? "Field media is backed up" : "Ready for new field media"
    }

    func configure(
        storagePreferences: FireVaultStoragePreferences,
        accounts: [FireVaultWorkspaceAccount],
        isDemoMode: Bool
    ) async {
        self.storagePreferences = storagePreferences
        self.isDemoMode = isDemoMode
        if storagePreferences.backupOverlayCopies != true, let store {
            try? await store.removePending(variant: "overlay")
        }
        await linkAccounts(accounts)
        await refreshItems()
        if isEnabled, networkAllowsUploads { await processPending() }
    }

    @discardableResult
    func enqueueSavedMedia(
        account: FireVaultWorkspaceAccount,
        localFileURL: URL,
        category: FireVaultFieldMediaCategory,
        variant: String,
        mimeType: String? = nil
    ) async -> UUID? {
        guard isEnabled, let store else { return nil }
        if variant == "overlay", storagePreferences.backupOverlayCopies != true { return nil }

        let attributes = try? FileManager.default.attributesOfItem(atPath: localFileURL.path)
        let modified = attributes?[.modificationDate] as? Date
        let session = try? await SupabaseManager.client.auth.session
        let userID = session?.user.id
        let cloudAccountID = account.cloudID.flatMap(UUID.init(uuidString:))
        let item = FireVaultFieldMediaBackupItem(
            localAccountID: account.id,
            userID: userID,
            accountID: cloudAccountID,
            accountNumber: account.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : account.accountId.trimmingCharacters(in: .whitespacesAndNewlines),
            localFileURL: localFileURL,
            originalFilename: localFileURL.lastPathComponent,
            category: category,
            mimeType: mimeType ?? FireVaultFieldMediaMIME.detect(for: localFileURL),
            fileModifiedAt: modified,
            variant: variant,
            lastError: cloudAccountID == nil
                ? FireVaultFieldMediaUploadError.accountNotSynced.localizedDescription
                : nil
        )
        do {
            let id = try await store.enqueueIfNeeded(item)
            await refreshItems()
            if networkAllowsUploads { await processPending() }
            return id
        } catch {
            initializationError = error.localizedDescription
            return nil
        }
    }

    func processPending() async {
        guard isEnabled, networkAllowsUploads, !isProcessing,
              let store, let coordinator else { return }
        guard let session = try? await SupabaseManager.client.auth.session else {
            await refreshItems()
            return
        }
        let userID = session.user.id

        do {
            try await store.claimUnownedItems(for: userID)
        } catch {
            initializationError = error.localizedDescription
            return
        }
        isProcessing = true
        let processing = Task {
            await coordinator.processPending(activeUserID: userID)
        }
        processingTask = processing
        try? await Task.sleep(for: .milliseconds(75))
        await refreshItems()
        await processing.value
        processingTask = nil
        isProcessing = false
        await refreshItems()
        scheduleNextRetry()
    }

    func retryNow(_ id: UUID) async {
        guard let store else { return }
        try? await store.retryNow(id)
        await refreshItems()
        await processPending()
    }

    func retryAllFailed() async {
        guard let store else { return }
        try? await store.retryAllFailed()
        await refreshItems()
        await processPending()
    }

    func removePending(localFileURLs: [URL]) async {
        guard let store else { return }
        try? await store.removePending(localFileURLs: localFileURLs)
        await refreshItems()
    }

    func removePending(localAccountID: String) async {
        guard let store else { return }
        try? await store.removePending(localAccountID: localAccountID)
        await refreshItems()
    }

    func removeAll() async {
        guard let store else { return }
        retryTask?.cancel()
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        try? await store.removeAll()
        await refreshItems()
    }

    private var networkAllowsUploads: Bool {
        networkAvailable && (storagePreferences.wifiOnlyUploads != true || usingWiFi)
    }

    private func linkAccounts(_ accounts: [FireVaultWorkspaceAccount]) async {
        guard let store else { return }
        let links = accounts.reduce(into: [String: UUID]()) { result, account in
            if let id = account.cloudID.flatMap(UUID.init(uuidString:)) { result[account.id] = id }
        }
        let numbers = accounts.reduce(into: [String: String]()) { result, account in
            result[account.id] = account.accountId
        }
        try? await store.linkAccounts(links, accountNumbers: numbers)
    }

    private func refreshItems() async {
        guard let store else { return }
        items = await store.allItems()
    }

    private func scheduleNextRetry() {
        retryTask?.cancel()
        guard isEnabled,
              let nextAttempt = items
                .filter({ $0.state == .failed })
                .compactMap(\.nextAttemptAt)
                .min() else { return }
        retryTask = Task { @MainActor [weak self] in
            let delay = max(0, nextAttempt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.processPending()
        }
    }
}
