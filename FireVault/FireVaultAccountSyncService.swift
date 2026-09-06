import Foundation
import Supabase

struct FireVaultCloudImportResult: Equatable {
    let importedRows: Int
    let skippedRows: Int
}

struct FireVaultLegacyBackfillResult: Equatable {
    let uploaded: Int
    let matched: Int
    let mappings: [String: UUID]
}

enum FireVaultRemoteAccountDeletionResult: Equatable {
    case noCloudRecord
    case deleted(UUID)
}

enum FireVaultRemoteAccountDeletionError: LocalizedError, Equatable {
    case linkedToDifferentLogin
    case cloudRecordUnavailable
    case invalidCloudFileReference
    case deletionNotConfirmed

    var errorDescription: String? {
        switch self {
        case .linkedToDifferentLogin:
            "This iPhone's vault belongs to a different FireVault login. Nothing was deleted."
        case .cloudRecordUnavailable:
            "FireVault could not confirm that this cloud record belongs to the signed-in user. Nothing was deleted."
        case .invalidCloudFileReference:
            "FireVault could not safely verify every cloud file for this account. Nothing was deleted from this iPhone."
        case .deletionNotConfirmed:
            "FireVault Cloud did not confirm the deletion. The account remains saved on this iPhone."
        }
    }
}

struct FireVaultCloudAccountRow: Decodable, Equatable, Identifiable {
    let id: UUID
    let accountName: String
    let accountNumber: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let archived: Bool
    let updatedAt: Date
    let syncVersion: Int

    enum CodingKeys: String, CodingKey {
        case id
        case accountName = "account_name"
        case accountNumber = "account_number"
        case addressLine1 = "address_line_1"
        case addressLine2 = "address_line_2"
        case city
        case state
        case postalCode = "postal_code"
        case country
        case latitude
        case longitude
        case phone
        case archived
        case updatedAt = "updated_at"
        case syncVersion = "sync_version"
    }

    var workspaceAccount: FireVaultWorkspaceAccount {
        let combinedAddress = [addressLine1, addressLine2, city, state, postalCode]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: ", ")

        return .init(
            id: id.uuidString,
            name: accountName,
            address: combinedAddress.isEmpty ? "No address supplied" : combinedAddress,
            category: "Uncategorized",
            accountId: accountNumber ?? "",
            phone: phone ?? "",
            favorite: false,
            latitude: latitude,
            longitude: longitude,
            tags: ["Cloud Sync"],
            notes: [],
            documents: [],
            equipment: [],
            locations: [],
            recent: [],
            cloudID: id.uuidString,
            cloudSyncedAt: Date(),
            cloudSyncVersion: syncVersion
        )
    }

    var combinedAddress: String {
        [addressLine1, addressLine2, city, state, postalCode]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: ", ")
    }

    var identityKey: String {
        Self.identityKey(name: accountName, address: [
            addressLine1,
            addressLine2,
            city,
            state,
            postalCode
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: ", "))
    }

    private static func identityKey(name: String, address: String) -> String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

enum FireVaultAccountReconciliationAction: Equatable {
    case acceptRemoteBaseline
    case downloadRemote
    case uploadLocal(expectedVersion: Int)
    case conflict
}

struct FireVaultAccountSyncConflict: Identifiable, Equatable {
    let localAccountID: String
    let remote: FireVaultCloudAccountRow

    var id: String { localAccountID }
}

enum FireVaultAccountSyncConflictChoice {
    case keepIPhone
    case usePortal
}

enum FireVaultAccountSyncError: LocalizedError, Equatable {
    case concurrentModification
    case cloudImportFailed

    var errorDescription: String? {
        switch self {
        case .concurrentModification:
            "An account changed in the portal while FireVault was syncing. Review the two versions before choosing which one to keep."
        case .cloudImportFailed:
            "FireVault Cloud could not save an imported account. Your iPhone copy is still preserved."
        }
    }
}

enum FireVaultAccountSyncService {
    private static let bucket = "csv-imports"
    private static let accountSelect = "id,account_name,account_number,address_line_1,address_line_2,city,state,postal_code,country,latitude,longitude,phone,archived,updated_at,sync_version"
    private static let cloudFileDeleteBatchSize = 100
    private static let concurrentImportUpdateLimit = 8

    static func fetchAccounts() async throws -> [FireVaultCloudAccountRow] {
        try await SupabaseManager.client
            .from("accounts")
            .select(accountSelect)
            .eq("archived", value: false)
            .order("account_name", ascending: true)
            .execute()
            .value
    }

    static func fetchAccount(id: UUID, userID: UUID) async throws -> FireVaultCloudAccountRow? {
        let rows: [FireVaultCloudAccountRow] = try await SupabaseManager.client
            .from("accounts")
            .select(accountSelect)
            .eq("id", value: id)
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func reconciliationAction(
        local: FireVaultWorkspaceAccount,
        remote: FireVaultCloudAccountRow
    ) -> FireVaultAccountReconciliationAction {
        if cloudValuesMatch(local: local, remote: remote) {
            return .acceptRemoteBaseline
        }

        guard let acceptedVersion = local.cloudSyncVersion else {
            return .conflict
        }

        if local.locallyModifiedAt != nil {
            return acceptedVersion == remote.syncVersion
                ? .uploadLocal(expectedVersion: acceptedVersion)
                : .conflict
        }

        return acceptedVersion == remote.syncVersion ? .conflict : .downloadRemote
    }

    static func cloudValuesMatch(
        local: FireVaultWorkspaceAccount,
        remote: FireVaultCloudAccountRow
    ) -> Bool {
        normalized(local.name) == normalized(remote.accountName)
            && canonicalAccountID(local.accountId) == canonicalAccountID(remote.accountNumber ?? "")
            && normalizedAddress(local.address) == normalizedAddress(remote.combinedAddress)
            && normalized(local.phone) == normalized(remote.phone ?? "")
            && local.latitude == remote.latitude
            && local.longitude == remote.longitude
    }

    static func cloudValuesMatch(
        _ lhs: FireVaultWorkspaceAccount,
        _ rhs: FireVaultWorkspaceAccount
    ) -> Bool {
        normalized(lhs.name) == normalized(rhs.name)
            && canonicalAccountID(lhs.accountId) == canonicalAccountID(rhs.accountId)
            && normalizedAddress(lhs.address) == normalizedAddress(rhs.address)
            && normalized(lhs.phone) == normalized(rhs.phone)
            && lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude
    }

    static func updateAccount(
        _ account: FireVaultWorkspaceAccount,
        remoteID: UUID,
        expectedVersion: Int,
        userID: UUID
    ) async throws -> FireVaultCloudAccountRow? {
        let rows: [FireVaultCloudAccountRow] = try await SupabaseManager.client
            .from("accounts")
            .update(CloudAccountUpdate(account: account))
            .eq("id", value: remoteID)
            .eq("user_id", value: userID)
            .eq("sync_version", value: expectedVersion)
            .select(accountSelect)
            .execute()
            .value
        return rows.first
    }

    /// Permanently deletes one user-owned customer account. The explicit
    /// `user_id` filter supplements RLS, and the verification query prevents a
    /// successful-looking zero-row delete from removing the on-device copy.
    static func deleteCustomerAccount(
        _ account: FireVaultWorkspaceAccount,
        expectedOwnerUserID: UUID?
    ) async throws -> FireVaultRemoteAccountDeletionResult {
        let session = try await SupabaseManager.client.auth.session
        if let expectedOwnerUserID, expectedOwnerUserID != session.user.id {
            throw FireVaultRemoteAccountDeletionError.linkedToDifferentLogin
        }

        let visibleRows: [FireVaultCloudAccountRow] = try await SupabaseManager.client
            .from("accounts")
            .select(accountSelect)
            .order("account_name", ascending: true)
            .execute()
            .value
        let number = canonicalAccountID(account.accountId)
        let identity = identityKey(name: account.name, address: account.address)
        let linkedID = account.cloudID.flatMap(UUID.init(uuidString:))
        let remote: FireVaultCloudAccountRow?
        if let linkedID {
            remote = visibleRows.first { $0.id == linkedID }
            // A linked UUID that is invisible may belong to another login, or
            // the DELETE policy may not permit access. Preserve the local copy.
            if remote == nil {
                throw FireVaultRemoteAccountDeletionError.cloudRecordUnavailable
            }
        } else if let localUUID = UUID(uuidString: account.id),
                  let exact = visibleRows.first(where: { $0.id == localUUID }) {
            remote = exact
        } else {
            let numberMatches = number.isEmpty
                ? []
                : visibleRows.filter { canonicalAccountID($0.accountNumber ?? "") == number }
            let identityMatches = visibleRows.filter { $0.identityKey == identity }
            if numberMatches.count > 1 || (numberMatches.isEmpty && identityMatches.count > 1) {
                throw FireVaultRemoteAccountDeletionError.cloudRecordUnavailable
            }
            remote = numberMatches.first ?? identityMatches.first
        }

        guard let remote else { return .noCloudRecord }

        let cloudFiles: [FireVaultCloudAccountFileReference] = try await SupabaseManager.client
            .from("account_files")
            .select("bucket_id,storage_path")
            .eq("user_id", value: session.user.id)
            .eq("account_id", value: remote.id)
            .execute()
            .value
        let storagePaths = try validatedCloudFilePaths(
            cloudFiles,
            userID: session.user.id,
            accountID: remote.id
        )

        // Storage policies require the parent account to still exist, while the
        // account_files foreign key deliberately blocks deleting a parent that
        // still has metadata. Remove objects first, then metadata, then the
        // account. Any failure preserves the on-device account for a safe retry.
        for start in stride(from: 0, to: storagePaths.count, by: cloudFileDeleteBatchSize) {
            let end = min(start + cloudFileDeleteBatchSize, storagePaths.count)
            let batch = Array(storagePaths[start..<end])
            try await withRetry {
                try await SupabaseManager.client.storage
                    .from(FireVaultSupabaseFieldMediaUploader.bucketID)
                    .remove(paths: batch)
            }
        }

        if !cloudFiles.isEmpty {
            try await withRetry {
                try await SupabaseManager.client
                    .from("account_files")
                    .delete()
                    .eq("user_id", value: session.user.id)
                    .eq("account_id", value: remote.id)
                    .execute()
            }

            let remainingFiles: [FireVaultCloudAccountFileIdentity] = try await SupabaseManager.client
                .from("account_files")
                .select("id")
                .eq("user_id", value: session.user.id)
                .eq("account_id", value: remote.id)
                .execute()
                .value
            guard remainingFiles.isEmpty else {
                throw FireVaultRemoteAccountDeletionError.deletionNotConfirmed
            }
        }

        try await withRetry {
            try await SupabaseManager.client
                .from("accounts")
                .delete()
                .eq("id", value: remote.id)
                .eq("user_id", value: session.user.id)
                .execute()
        }

        let remaining: [CloudAccountIdentity] = try await SupabaseManager.client
            .from("accounts")
            .select("id")
            .eq("id", value: remote.id)
            .eq("user_id", value: session.user.id)
            .execute()
            .value
        guard remaining.isEmpty else {
            throw FireVaultRemoteAccountDeletionError.deletionNotConfirmed
        }
        return .deleted(remote.id)
    }

    static func validatedCloudFilePaths(
        _ files: [FireVaultCloudAccountFileReference],
        userID: UUID,
        accountID: UUID
    ) throws -> [String] {
        let expectedPrefix = "\(userID.uuidString.lowercased())/accounts/\(accountID.uuidString.lowercased())/"
        var paths = Set<String>()
        for file in files {
            guard file.bucketID == FireVaultSupabaseFieldMediaUploader.bucketID,
                  file.storagePath.lowercased().hasPrefix(expectedPrefix),
                  file.storagePath.count > expectedPrefix.count else {
                throw FireVaultRemoteAccountDeletionError.invalidCloudFileReference
            }
            paths.insert(file.storagePath)
        }
        return paths.sorted()
    }

    static func backfillLegacyAccounts(
        _ accounts: [FireVaultWorkspaceAccount],
        progress: @escaping (Int, Int) async -> Void
    ) async throws -> FireVaultLegacyBackfillResult {
        let session = try await SupabaseManager.client.auth.session
        let remote = try await fetchAccounts()
        var byNumber: [String: FireVaultCloudAccountRow] = [:]
        var byIdentity: [String: FireVaultCloudAccountRow] = [:]
        for row in remote {
            let number = canonicalAccountID(row.accountNumber ?? "")
            if !number.isEmpty, byNumber[number] == nil { byNumber[number] = row }
            if byIdentity[row.identityKey] == nil { byIdentity[row.identityKey] = row }
        }
        var mappings: [String: UUID] = [:]
        var uploaded = 0
        var matched = 0
        let candidates = accounts.filter { $0.cloudID == nil || $0.cloudSyncedAt == nil }

        for (offset, account) in candidates.enumerated() {
            try Task.checkCancellation()
            let number = canonicalAccountID(account.accountId)
            let identity = identityKey(name: account.name, address: account.address)
            let existing = account.cloudID.flatMap(UUID.init(uuidString:)).flatMap { id in
                remote.first { $0.id == id }
            } ?? (!number.isEmpty ? byNumber[number] : nil) ?? byIdentity[identity]
            // Supabase uses one global primary-key namespace for this table.
            // Never reuse the device-local UUID when creating a cloud row: an
            // older vault may already have uploaded that UUID under another
            // user, and an upsert would then attempt a forbidden cross-user
            // update instead of a safe insert.
            let remoteID = existing?.id ?? UUID()

            if existing == nil {
                let row = CloudAccountUpsert(
                    id: remoteID, userID: session.user.id, importID: nil,
                    accountName: account.name, accountNumber: number.nilIfEmpty,
                    addressLine1: account.address.nilIfEmpty, addressLine2: nil,
                    city: nil, state: nil, postalCode: nil, country: "US",
                    latitude: account.latitude, longitude: account.longitude,
                    phone: account.phone.nilIfEmpty, archived: false
                )
                try await withRetry {
                    try await SupabaseManager.client.from("accounts").upsert(row).execute()
                }
                uploaded += 1
                let synthesized = FireVaultCloudAccountRow(
                    id: remoteID, accountName: account.name, accountNumber: number.nilIfEmpty,
                    addressLine1: account.address.nilIfEmpty, addressLine2: nil, city: nil,
                    state: nil, postalCode: nil, country: "US", latitude: account.latitude,
                    longitude: account.longitude, phone: account.phone.nilIfEmpty, archived: false,
                    updatedAt: Date(), syncVersion: 1
                )
                if !number.isEmpty { byNumber[number] = synthesized }
                byIdentity[identity] = synthesized
            } else {
                matched += 1
            }
            mappings[account.id] = remoteID
            await progress(offset + 1, candidates.count)
        }
        return .init(uploaded: uploaded, matched: matched, mappings: mappings)
    }

    private static func withRetry(_ operation: () async throws -> Void) async throws {
        var lastError: Error?
        for attempt in 0..<3 {
            do { try await operation(); return } catch {
                lastError = error
                if attempt < 2 { try await Task.sleep(for: .milliseconds(400 * (attempt + 1))) }
            }
        }
        throw lastError!
    }

    static func importCSV(
        data: Data,
        fileName: String,
        analysis: FireVaultCSVAnalysis
    ) async throws -> FireVaultCloudImportResult {
        let session = try await SupabaseManager.client.auth.session
        let userID = session.user.id
        let jobID = UUID()
        let safeFileName = sanitizedFileName(fileName)
        let storagePath = "\(userID.uuidString.lowercased())/\(jobID.uuidString.lowercased())/\(safeFileName)"
        var seenAccountNumbers = Set<String>()
        let acceptedRecords = analysis.records.filter { record in
            guard record.rowResult.status != .rejected else { return false }
            let number = canonicalAccountID(record.accountID)
            return number.isEmpty || seenAccountNumbers.insert(number).inserted
        }
        var skippedRows = analysis.records.count - acceptedRecords.count

        try await SupabaseManager.client
            .from("csv_import_jobs")
            .insert(
                CSVImportJobInsert(
                    id: jobID,
                    userID: userID,
                    originalFilename: String(fileName.prefix(180)),
                    storagePath: storagePath,
                    status: "processing",
                    totalRows: analysis.records.count,
                    skippedRows: skippedRows
                )
            )
            .execute()

        var importedRows = 0

        do {
            try await SupabaseManager.client.storage
                .from(bucket)
                .upload(
                    storagePath,
                    data: data,
                    options: FileOptions(contentType: "text/csv")
                )

            let existingRows = try await fetchAccounts()
            let plans = makeAccountImportPlans(
                records: acceptedRecords,
                existingRows: existingRows,
                userID: userID,
                jobID: jobID
            )
            skippedRows += acceptedRecords.count - plans.count

            for start in stride(from: 0, to: plans.count, by: concurrentImportUpdateLimit) {
                let end = min(start + concurrentImportUpdateLimit, plans.count)
                let batch = Array(plans[start..<end])
                let outcomes = await withTaskGroup(
                    of: CloudAccountImportMutationOutcome.self,
                    returning: [CloudAccountImportMutationOutcome].self
                ) { group in
                    for plan in batch {
                        group.addTask {
                            await applyAccountImportPlan(plan, userID: userID)
                        }
                    }
                    var results: [CloudAccountImportMutationOutcome] = []
                    for await outcome in group {
                        results.append(outcome)
                    }
                    return results
                }

                importedRows += outcomes.filter { $0 == .applied }.count
                if outcomes.contains(.conflict) {
                    throw FireVaultAccountSyncError.concurrentModification
                }
                if outcomes.contains(.failed) {
                    throw FireVaultAccountSyncError.cloudImportFailed
                }
            }

            try await SupabaseManager.client
                .from("csv_import_jobs")
                .update(
                    CSVImportJobCompletion(
                        status: "completed",
                        importedRows: importedRows,
                        skippedRows: skippedRows,
                        failedRows: 0,
                        errorMessage: nil,
                        completedAt: ISO8601DateFormatter().string(from: Date())
                    )
                )
                .eq("id", value: jobID)
                .execute()

            return .init(importedRows: importedRows, skippedRows: skippedRows)
        } catch {
            let remainingRows = max(0, acceptedRecords.count - importedRows)
            _ = try? await SupabaseManager.client
                .from("csv_import_jobs")
                .update(
                    CSVImportJobCompletion(
                        status: "failed",
                        importedRows: importedRows,
                        skippedRows: skippedRows,
                        failedRows: remainingRows,
                        errorMessage: String(error.localizedDescription.prefix(500)),
                        completedAt: ISO8601DateFormatter().string(from: Date())
                    )
                )
                .eq("id", value: jobID)
                .execute()
            throw error
        }
    }

    private static func makeAccountImportPlans(
        records: [FireVaultCSVParsedRecord],
        existingRows: [FireVaultCloudAccountRow],
        userID: UUID,
        jobID: UUID
    ) -> [CloudAccountImportPlan] {
        var existingByNumber: [String: FireVaultCloudAccountRow] = [:]
        var existingByIdentity: [String: FireVaultCloudAccountRow] = [:]

        for row in existingRows {
            let number = canonicalAccountID(row.accountNumber ?? "")
            if !number.isEmpty, existingByNumber[number] == nil {
                existingByNumber[number] = row
            }
            if existingByIdentity[row.identityKey] == nil {
                existingByIdentity[row.identityKey] = row
            }
        }

        var plansByID: [UUID: CloudAccountImportPlan] = [:]
        var orderedIDs: [UUID] = []
        for record in records {
            let accountNumber = canonicalAccountID(record.accountID)
            let identity = identityKey(name: record.name, address: record.address)
            let existing = accountNumber.isEmpty
                ? existingByIdentity[identity]
                : existingByNumber[accountNumber]
            let hasImportedAddress = !record.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let addressChanged = hasImportedAddress
                && normalizedAddress(record.address) != normalizedAddress(existing?.combinedAddress ?? "")
            let latitude = record.latitude ?? (addressChanged ? nil : existing?.latitude)
            let longitude = record.longitude ?? (addressChanged ? nil : existing?.longitude)
            // Cloud primary keys are global. A new random UUID avoids turning a
            // device-local UUID collision from another login into a forbidden
            // cross-user update.
            let accountID = existing?.id ?? UUID()

            let plan = CloudAccountImportPlan(
                row: .init(
                    id: accountID,
                    userID: userID,
                    importID: jobID,
                    accountName: record.name,
                    accountNumber: accountNumber.nilIfEmpty ?? existing?.accountNumber,
                    addressLine1: hasImportedAddress
                        ? record.addressLine1.nilIfEmpty
                        : existing?.addressLine1,
                    addressLine2: hasImportedAddress ? nil : existing?.addressLine2,
                    city: hasImportedAddress ? record.city.nilIfEmpty : existing?.city,
                    state: hasImportedAddress ? record.state.nilIfEmpty : existing?.state,
                    postalCode: hasImportedAddress ? record.postalCode.nilIfEmpty : existing?.postalCode,
                    country: existing?.country ?? "US",
                    latitude: latitude,
                    longitude: longitude,
                    phone: record.phone.nilIfEmpty ?? existing?.phone,
                    archived: false
                ),
                expectedVersion: existing?.syncVersion
            )
            if plansByID[accountID] == nil { orderedIDs.append(accountID) }
            plansByID[accountID] = plan
        }
        return orderedIDs.compactMap { plansByID[$0] }
    }

    private static func applyAccountImportPlan(
        _ plan: CloudAccountImportPlan,
        userID: UUID
    ) async -> CloudAccountImportMutationOutcome {
        do {
            if let expectedVersion = plan.expectedVersion {
                let updated: [FireVaultCloudAccountRow] = try await SupabaseManager.client
                    .from("accounts")
                    .update(CloudAccountImportUpdate(row: plan.row))
                    .eq("id", value: plan.row.id)
                    .eq("user_id", value: userID)
                    .eq("sync_version", value: expectedVersion)
                    .select(accountSelect)
                    .execute()
                    .value
                return updated.isEmpty ? .conflict : .applied
            }

            try await SupabaseManager.client
                .from("accounts")
                .insert(plan.row)
                .execute()
            return .applied
        } catch {
            return .failed
        }
    }

    private static func sanitizedFileName(_ fileName: String) -> String {
        let source = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = source.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        let clipped = String(safe.prefix(120))
        return clipped.isEmpty ? "accounts.csv" : clipped
    }

    private static func canonicalAccountID(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { !$0.isWhitespace }
    }

    private static func identityKey(name: String, address: String) -> String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedAddress(_ value: String) -> String {
        let result = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        return result == "no address supplied" ? "" : result
    }
}

private struct CloudAccountIdentity: Decodable {
    let id: UUID
}

struct FireVaultCloudAccountFileReference: Decodable, Equatable {
    let bucketID: String
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case bucketID = "bucket_id"
        case storagePath = "storage_path"
    }
}

private struct FireVaultCloudAccountFileIdentity: Decodable {
    let id: UUID
}

private struct CSVImportJobInsert: Encodable {
    let id: UUID
    let userID: UUID
    let originalFilename: String
    let storagePath: String
    let status: String
    let totalRows: Int
    let skippedRows: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case originalFilename = "original_filename"
        case storagePath = "storage_path"
        case status
        case totalRows = "total_rows"
        case skippedRows = "skipped_rows"
    }
}

private struct CSVImportJobCompletion: Encodable {
    let status: String
    let importedRows: Int
    let skippedRows: Int
    let failedRows: Int
    let errorMessage: String?
    let completedAt: String

    enum CodingKeys: String, CodingKey {
        case status
        case importedRows = "imported_rows"
        case skippedRows = "skipped_rows"
        case failedRows = "failed_rows"
        case errorMessage = "error_message"
        case completedAt = "completed_at"
    }
}

private struct CloudAccountImportPlan: Sendable {
    let row: CloudAccountUpsert
    let expectedVersion: Int?
}

private enum CloudAccountImportMutationOutcome: Equatable, Sendable {
    case applied
    case conflict
    case failed
}

private struct CloudAccountUpsert: Encodable, Sendable {
    let id: UUID
    let userID: UUID
    let importID: UUID?
    let accountName: String
    let accountNumber: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case importID = "import_id"
        case accountName = "account_name"
        case accountNumber = "account_number"
        case addressLine1 = "address_line_1"
        case addressLine2 = "address_line_2"
        case city
        case state
        case postalCode = "postal_code"
        case country
        case latitude
        case longitude
        case phone
        case archived
    }
}

private struct CloudAccountImportUpdate: Encodable, Sendable {
    let importID: UUID?
    let accountName: String
    let accountNumber: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let archived: Bool

    init(row: CloudAccountUpsert) {
        importID = row.importID
        accountName = row.accountName
        accountNumber = row.accountNumber
        addressLine1 = row.addressLine1
        addressLine2 = row.addressLine2
        city = row.city
        state = row.state
        postalCode = row.postalCode
        country = row.country
        latitude = row.latitude
        longitude = row.longitude
        phone = row.phone
        archived = row.archived
    }

    enum CodingKeys: String, CodingKey {
        case importID = "import_id"
        case accountName = "account_name"
        case accountNumber = "account_number"
        case addressLine1 = "address_line_1"
        case addressLine2 = "address_line_2"
        case city
        case state
        case postalCode = "postal_code"
        case country
        case latitude
        case longitude
        case phone
        case archived
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(importID, forKey: .importID)
        try container.encode(accountName, forKey: .accountName)
        try container.encode(accountNumber, forKey: .accountNumber)
        try container.encode(addressLine1, forKey: .addressLine1)
        try container.encode(addressLine2, forKey: .addressLine2)
        try container.encode(city, forKey: .city)
        try container.encode(state, forKey: .state)
        try container.encode(postalCode, forKey: .postalCode)
        try container.encode(country, forKey: .country)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(phone, forKey: .phone)
        try container.encode(archived, forKey: .archived)
    }
}

private struct CloudAccountUpdate: Encodable {
    let accountName: String
    let accountNumber: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let archived: Bool

    init(account: FireVaultWorkspaceAccount) {
        accountName = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        accountNumber = account.accountId.nilIfEmpty
        let address = account.address.trimmingCharacters(in: .whitespacesAndNewlines)
        addressLine1 = address.caseInsensitiveCompare("No address supplied") == .orderedSame
            ? nil
            : address.nilIfEmpty
        addressLine2 = nil
        city = nil
        state = nil
        postalCode = nil
        country = "US"
        latitude = account.latitude
        longitude = account.longitude
        phone = account.phone.nilIfEmpty
        archived = false
    }

    enum CodingKeys: String, CodingKey {
        case accountName = "account_name"
        case accountNumber = "account_number"
        case addressLine1 = "address_line_1"
        case addressLine2 = "address_line_2"
        case city
        case state
        case postalCode = "postal_code"
        case country
        case latitude
        case longitude
        case phone
        case archived
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountName, forKey: .accountName)
        try container.encode(accountNumber, forKey: .accountNumber)
        try container.encode(addressLine1, forKey: .addressLine1)
        try container.encode(addressLine2, forKey: .addressLine2)
        try container.encode(city, forKey: .city)
        try container.encode(state, forKey: .state)
        try container.encode(postalCode, forKey: .postalCode)
        try container.encode(country, forKey: .country)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(phone, forKey: .phone)
        try container.encode(archived, forKey: .archived)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
