//
//  FireVaultFieldMediaRecovery.swift
//  FireVault
//
//  Browse, verify, preview, download, and restore cloud-backed field media.
//

import Combine
import Foundation
import QuickLook
import Supabase
import SwiftUI
import UIKit

struct FireVaultBackedUpMediaFile: Identifiable, Decodable, Hashable, Sendable {
    let id: UUID
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
    let metadata: [String: String]?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
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
        case metadata
        case createdAt = "created_at"
    }

    var variant: String {
        let value = metadata?["variant"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value?.isEmpty == false ? value! : "original"
    }

    var accountNumber: String? {
        let value = metadata?["account_number"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    var categoryLabel: String {
        switch category.lowercased() {
        case FireVaultFieldMediaCategory.photos.rawValue: "Photo"
        case FireVaultFieldMediaCategory.scans.rawValue: "Scan"
        case FireVaultFieldMediaCategory.reports.rawValue: "Report"
        case FireVaultFieldMediaCategory.documents.rawValue: "Document"
        default: "File"
        }
    }

    var categorySymbol: String {
        switch category.lowercased() {
        case FireVaultFieldMediaCategory.photos.rawValue: "photo.fill"
        case FireVaultFieldMediaCategory.scans.rawValue: "doc.viewfinder.fill"
        case FireVaultFieldMediaCategory.reports.rawValue: "doc.text.fill"
        case FireVaultFieldMediaCategory.documents.rawValue: "doc.fill"
        default: "paperclip"
        }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    nonisolated var uploadedDate: Date? {
        Self.parseTimestamp(createdAt) ?? Self.parseTimestamp(fileModifiedAt)
    }

    nonisolated var modifiedDate: Date? {
        Self.parseTimestamp(fileModifiedAt)
    }

    nonisolated private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct FireVaultBackedUpMediaGroup: Identifiable, Equatable {
    let id: UUID
    let title: String
    let subtitle: String?
    let localAccountID: String?
    let files: [FireVaultBackedUpMediaFile]
}

struct FireVaultFieldMediaRestoreTarget: Equatable {
    let localAccountID: String
    let documentID: String
    let fileName: String
}

enum FireVaultBackedUpMediaLocalStatus: Equatable {
    case available
    case missingOriginal
    case notReferenced
}

enum FireVaultBackedUpMediaCatalog {
    static func groups(
        files: [FireVaultBackedUpMediaFile],
        accounts: [FireVaultWorkspaceAccount]
    ) -> [FireVaultBackedUpMediaGroup] {
        let accountsByCloudID = Dictionary(
            accounts.compactMap { account in
                account.cloudID.flatMap(UUID.init(uuidString:)).map { ($0, account) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        return Dictionary(grouping: files, by: \.accountID)
            .map { accountID, groupedFiles in
                let account = accountsByCloudID[accountID]
                let metadataNumber = groupedFiles.compactMap(\.accountNumber).first
                let accountName = account?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let title: String
                if let accountName, !accountName.isEmpty {
                    title = accountName
                } else if let metadataNumber {
                    title = "Account \(metadataNumber)"
                } else {
                    title = "Cloud Account"
                }
                let localNumber = account?.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
                let accountNumber = localNumber?.isEmpty == false ? localNumber : metadataNumber
                return FireVaultBackedUpMediaGroup(
                    id: accountID,
                    title: title,
                    subtitle: accountNumber,
                    localAccountID: account?.id,
                    files: groupedFiles.sorted(by: filesSortBefore)
                )
            }
            .sorted { lhs, rhs in
                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                return titleOrder == .orderedSame
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : titleOrder == .orderedAscending
            }
    }

    static func restoreTarget(
        for file: FireVaultBackedUpMediaFile,
        accounts: [FireVaultWorkspaceAccount]
    ) -> FireVaultFieldMediaRestoreTarget? {
        guard let account = localAccount(for: file, accounts: accounts) else { return nil }

        for document in account.documents {
            if document.originalMediaFileName == file.originalFilename
                || document.mediaFileName == file.originalFilename {
                return .init(
                    localAccountID: account.id,
                    documentID: document.id,
                    fileName: file.originalFilename
                )
            }
        }
        return nil
    }

    static func localAccount(
        for file: FireVaultBackedUpMediaFile,
        accounts: [FireVaultWorkspaceAccount]
    ) -> FireVaultWorkspaceAccount? {
        guard file.variant == "original",
              !file.originalFilename.isEmpty,
              file.originalFilename == URL(fileURLWithPath: file.originalFilename).lastPathComponent else {
            return nil
        }
        return accounts.first {
            $0.cloudID.flatMap(UUID.init(uuidString:)) == file.accountID
        }
    }

    nonisolated private static func filesSortBefore(
        _ lhs: FireVaultBackedUpMediaFile,
        _ rhs: FireVaultBackedUpMediaFile
    ) -> Bool {
        switch (lhs.uploadedDate, rhs.uploadedDate) {
        case let (left?, right?) where left != right:
            return left > right
        default:
            return lhs.originalFilename.localizedCaseInsensitiveCompare(rhs.originalFilename) == .orderedAscending
        }
    }
}

enum FireVaultFieldMediaRecoveryError: LocalizedError, Equatable {
    case notSignedIn
    case signedInUserMismatch
    case invalidStorageReference
    case checksumMismatch
    case originalNotReferenced
    case originalAlreadyAvailable
    case localFileConflict

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Sign in to view backed-up media."
        case .signedInUserMismatch:
            "This backed-up file belongs to a different FireVault sign-in."
        case .invalidStorageReference:
            "The cloud backup has an invalid storage reference."
        case .checksumMismatch:
            "The downloaded file did not match its SHA-256 checksum, so FireVault did not use it."
        case .originalNotReferenced:
            "This backup is not an original associated with a synced account on this iPhone."
        case .originalAlreadyAvailable:
            "The original is already available on this iPhone."
        case .localFileConflict:
            "A different local file already uses this backup's filename. FireVault left both files unchanged."
        }
    }
}

protocol FireVaultFieldMediaRecoveryClient: Sendable {
    func listFiles() async throws -> [FireVaultBackedUpMediaFile]
    func download(_ file: FireVaultBackedUpMediaFile) async throws -> Data
}

final class FireVaultSupabaseFieldMediaRecoveryClient: FireVaultFieldMediaRecoveryClient, @unchecked Sendable {
    private let supabase: SupabaseClient
    private let pageSize = 500

    init(supabase: SupabaseClient = SupabaseManager.client) {
        self.supabase = supabase
    }

    func listFiles() async throws -> [FireVaultBackedUpMediaFile] {
        try FireVaultPaidFeatureAccess.requireCached(.cloudStorage)
        let session: Session
        do {
            session = try await supabase.auth.session
        } catch {
            throw FireVaultFieldMediaRecoveryError.notSignedIn
        }

        var files: [FireVaultBackedUpMediaFile] = []
        var offset = 0
        while true {
            let page: [FireVaultBackedUpMediaFile] = try await supabase
                .from("account_files")
                .select(
                    "id,user_id,account_id,bucket_id,storage_path,original_filename,category,mime_type,file_size_bytes,file_modified_at,sha256,metadata,created_at"
                )
                .eq("user_id", value: session.user.id)
                .order("created_at", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value
            guard page.allSatisfy({ $0.userID == session.user.id }) else {
                throw FireVaultFieldMediaRecoveryError.signedInUserMismatch
            }
            files.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }
        return files
    }

    func download(_ file: FireVaultBackedUpMediaFile) async throws -> Data {
        try FireVaultPaidFeatureAccess.requireCached(.cloudStorage)
        let session: Session
        do {
            session = try await supabase.auth.session
        } catch {
            throw FireVaultFieldMediaRecoveryError.notSignedIn
        }
        guard file.userID == session.user.id else {
            throw FireVaultFieldMediaRecoveryError.signedInUserMismatch
        }
        let ownerPrefix = session.user.id.uuidString.lowercased() + "/"
        guard file.bucketID == FireVaultSupabaseFieldMediaUploader.bucketID,
              file.storagePath.lowercased().hasPrefix(ownerPrefix) else {
            throw FireVaultFieldMediaRecoveryError.invalidStorageReference
        }
        return try await supabase.storage
            .from(file.bucketID)
            .download(path: file.storagePath)
    }
}

enum FireVaultFieldMediaRecoveryVerifier {
    static func verify(_ data: Data, expectedSHA256: String) throws {
        let expected = expectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard expected.count == 64,
              expected.allSatisfy({ $0.isHexDigit }),
              FireVaultFieldMediaHash.sha256Hex(of: data) == expected else {
            throw FireVaultFieldMediaRecoveryError.checksumMismatch
        }
    }

    static func verify(_ fileURL: URL, expectedSHA256: String) throws {
        let expected = expectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard expected.count == 64,
              expected.allSatisfy({ $0.isHexDigit }),
              try FireVaultFieldMediaHash.sha256Hex(of: fileURL) == expected else {
            throw FireVaultFieldMediaRecoveryError.checksumMismatch
        }
    }
}

struct FireVaultFieldMediaRecoveryCache {
    let directory: URL

    init(directory: URL? = nil) throws {
        let resolved = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("FireVault-Backed-Up-Media", isDirectory: true)
        try FileManager.default.createDirectory(at: resolved, withIntermediateDirectories: true)
        self.directory = resolved
    }

    func storeVerified(_ data: Data, for file: FireVaultBackedUpMediaFile) throws -> URL {
        try FireVaultFieldMediaRecoveryVerifier.verify(data, expectedSHA256: file.sha256)
        let itemDirectory = directory.appendingPathComponent(file.id.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        let safeName = file.originalFilename == URL(fileURLWithPath: file.originalFilename).lastPathComponent
            ? file.originalFilename
            : "backed-up-media"
        let destination = itemDirectory.appendingPathComponent(safeName)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        do {
            try FireVaultFieldMediaRecoveryVerifier.verify(destination, expectedSHA256: file.sha256)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }
}

@MainActor
final class FireVaultFieldMediaRecoveryViewModel: ObservableObject {
    @Published private(set) var files: [FireVaultBackedUpMediaFile] = []
    @Published private(set) var isLoading = false
    @Published private(set) var activeFileID: UUID?
    @Published var errorMessage: String?

    private let client: any FireVaultFieldMediaRecoveryClient
    private let cache: FireVaultFieldMediaRecoveryCache?
    private var cachedURLs: [UUID: URL] = [:]

    init(
        client: (any FireVaultFieldMediaRecoveryClient)? = nil,
        cacheDirectory: URL? = nil
    ) {
        self.client = client ?? FireVaultSupabaseFieldMediaRecoveryClient()
        cache = try? FireVaultFieldMediaRecoveryCache(directory: cacheDirectory)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            files = try await client.listFiles()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func localVerifiedFile(for file: FireVaultBackedUpMediaFile) async throws -> URL {
        if let cachedURL = cachedURLs[file.id], FileManager.default.fileExists(atPath: cachedURL.path) {
            do {
                try FireVaultFieldMediaRecoveryVerifier.verify(cachedURL, expectedSHA256: file.sha256)
                return cachedURL
            } catch {
                try? FileManager.default.removeItem(at: cachedURL)
                cachedURLs[file.id] = nil
            }
        }
        guard let cache else { throw FireVaultMediaError.storageUnavailable }
        activeFileID = file.id
        defer { activeFileID = nil }
        let data = try await client.download(file)
        let url = try cache.storeVerified(data, for: file)
        cachedURLs[file.id] = url
        return url
    }

    func restore(_ file: FireVaultBackedUpMediaFile, into store: FireVaultStore) async throws -> URL {
        let verifiedURL = try await localVerifiedFile(for: file)
        let data = try Data(contentsOf: verifiedURL, options: .mappedIfSafe)
        return try store.restoreBackedUpOriginal(file, data: data)
    }
}

extension FireVaultStore {
    func backedUpMediaLocalStatus(
        _ file: FireVaultBackedUpMediaFile
    ) -> FireVaultBackedUpMediaLocalStatus {
        guard let account = FireVaultBackedUpMediaCatalog.localAccount(for: file, accounts: accounts) else {
            return .notReferenced
        }
        guard let target = FireVaultBackedUpMediaCatalog.restoreTarget(for: file, accounts: accounts) else {
            // A clean install can have the synced account but no local document
            // record yet. Restoring reconnects that record after verification.
            return .missingOriginal
        }
        guard let url = try? mediaURL(accountID: account.id, fileName: target.fileName) else {
            return .notReferenced
        }
        return FileManager.default.fileExists(atPath: url.path) ? .available : .missingOriginal
    }
}

struct FireVaultBackedUpMediaRecoveryView: View {
    @ObservedObject var store: FireVaultStore
    @StateObject private var recovery: FireVaultFieldMediaRecoveryViewModel
    @EnvironmentObject private var subscriptions: FireVaultSubscriptionStore

    init(
        store: FireVaultStore,
        client: (any FireVaultFieldMediaRecoveryClient)? = nil
    ) {
        self.store = store
        _recovery = StateObject(wrappedValue: FireVaultFieldMediaRecoveryViewModel(client: client))
    }

    private var groups: [FireVaultBackedUpMediaGroup] {
        FireVaultBackedUpMediaCatalog.groups(files: recovery.files, accounts: store.accounts)
    }

    private var missingCount: Int {
        recovery.files.filter { store.backedUpMediaLocalStatus($0) == .missingOriginal }.count
    }

    var body: some View {
        List {
            if !subscriptions.access.grantsFullAccess {
                ContentUnavailableView {
                    Label("Subscription Required", systemImage: "lock.fill")
                } description: {
                    Text("Subscribe to preview, download, or restore cloud-backed media. Local files remain on this iPhone.")
                } actions: {
                    Button("View Plans") { store.requestSubscriptionForPaidFeature() }
                        .buttonStyle(.borderedProminent)
                }
            } else if recovery.isLoading, recovery.files.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading backed-up media…")
                        Spacer()
                    }
                    .padding(.vertical, 18)
                }
            } else if recovery.files.isEmpty, recovery.errorMessage == nil {
                ContentUnavailableView(
                    "No Backed-Up Media",
                    systemImage: "externaldrive.badge.checkmark",
                    description: Text("Eligible account media appears here after automatic cloud backup completes.")
                )
            } else {
                Section {
                    LabeledContent("Cloud files", value: "\(recovery.files.count)")
                    LabeledContent("Missing originals", value: "\(missingCount)")
                } footer: {
                    Text("Preview and downloaded copies are checksum-verified. Missing originals can be restored to a synced local account, and FireVault reconnects the media record when needed.")
                }

                ForEach(groups) { group in
                    Section {
                        ForEach(group.files) { file in
                            NavigationLink {
                                FireVaultBackedUpMediaDetailView(
                                    file: file,
                                    store: store,
                                    recovery: recovery
                                )
                            } label: {
                                FireVaultBackedUpMediaRow(
                                    file: file,
                                    status: store.backedUpMediaLocalStatus(file)
                                )
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.title)
                            if let subtitle = group.subtitle {
                                Text(subtitle).font(.caption2)
                            }
                        }
                    }
                }
            }

            if let error = recovery.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(NativeShellPalette.amber)
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        Task { await recovery.load() }
                    }
                }
            }
        }
        .fireVaultThemedCollection()
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Backed-Up Media")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if subscriptions.access.grantsFullAccess { await recovery.load() }
        }
        .task {
            if subscriptions.access.grantsFullAccess, recovery.files.isEmpty {
                await recovery.load()
            }
        }
    }
}

private struct FireVaultBackedUpMediaRow: View {
    let file: FireVaultBackedUpMediaFile
    let status: FireVaultBackedUpMediaLocalStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.categorySymbol)
                .foregroundStyle(NativeShellPalette.blue)
                .frame(width: 34, height: 34)
                .background(NativeShellPalette.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(file.originalFilename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(file.categoryLabel)
                    Text("•")
                    Text(file.formattedSize)
                    if file.variant != "original" {
                        Text("•")
                        Text("Stamped copy")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if status == .missingOriginal {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(NativeShellPalette.amber)
                    .accessibilityLabel("Original missing from this iPhone")
            } else if status == .available {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NativeShellPalette.green)
                    .accessibilityLabel("Available on this iPhone")
            }
        }
        .padding(.vertical, 3)
    }
}

private struct FireVaultBackedUpMediaDetailView: View {
    let file: FireVaultBackedUpMediaFile
    @ObservedObject var store: FireVaultStore
    @ObservedObject var recovery: FireVaultFieldMediaRecoveryViewModel
    @State private var presentedPreview: FireVaultRecoveryPresentedURL?
    @State private var presentedDownload: FireVaultRecoveryPresentedURL?
    @State private var confirmsRestore = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var localStatus: FireVaultBackedUpMediaLocalStatus {
        store.backedUpMediaLocalStatus(file)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: file.categorySymbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(NativeShellPalette.blue)
                        .frame(width: 48, height: 48)
                        .background(NativeShellPalette.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.originalFilename)
                            .font(.headline)
                            .lineLimit(2)
                        Text("\(file.categoryLabel) • \(file.formattedSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Actions") {
                Button("Preview", systemImage: "eye") { preparePreview() }
                    .disabled(recovery.activeFileID != nil)
                Button("Download Copy", systemImage: "square.and.arrow.down") { prepareDownload() }
                    .disabled(recovery.activeFileID != nil)

                switch localStatus {
                case .missingOriginal:
                    Button("Restore Missing Original", systemImage: "arrow.clockwise.icloud") {
                        confirmsRestore = true
                    }
                    .disabled(recovery.activeFileID != nil)
                case .available:
                    Label("Original available on this iPhone", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NativeShellPalette.green)
                case .notReferenced:
                    Text("Restore is unavailable because this is not an original associated with a synced account on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if recovery.activeFileID == file.id {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Downloading and verifying…")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Backup Details") {
                LabeledContent("Variant", value: file.variant == "original" ? "Original" : "Stamped copy")
                LabeledContent("SHA-256", value: String(file.sha256.prefix(12)) + "…")
                if let date = file.uploadedDate {
                    LabeledContent("Backed up", value: date.formatted(date: .abbreviated, time: .shortened))
                }
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NativeShellPalette.green)
                }
            }
        }
        .fireVaultThemedCollection()
        .navigationTitle("Cloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Restore this missing original?",
            isPresented: $confirmsRestore,
            titleVisibility: .visible
        ) {
            Button("Restore Original") { restoreOriginal() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("FireVault will download the cloud copy, verify its SHA-256 checksum, install it in the account's media library, reconnect its record if needed, and verify the installed file again.")
        }
        .sheet(item: $presentedPreview) { item in
            NavigationStack {
                FireVaultRecoveryQuickLook(url: item.url)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(file.originalFilename)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(item: $presentedDownload) { item in
            FireVaultRecoveryShareSheet(url: item.url)
        }
        .alert("Backed-Up Media", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "The operation could not be completed.")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func preparePreview() {
        Task {
            do {
                let url = try await recovery.localVerifiedFile(for: file)
                presentedPreview = .init(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareDownload() {
        Task {
            do {
                let url = try await recovery.localVerifiedFile(for: file)
                presentedDownload = .init(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restoreOriginal() {
        Task {
            do {
                _ = try await recovery.restore(file, into: store)
                statusMessage = "Original restored and verified."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

private struct FireVaultRecoveryPresentedURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct FireVaultRecoveryQuickLook: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

private struct FireVaultRecoveryShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
