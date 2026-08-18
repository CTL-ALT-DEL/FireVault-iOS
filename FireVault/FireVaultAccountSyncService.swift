import Foundation
import Supabase

struct FireVaultCloudImportResult: Equatable {
    let importedRows: Int
    let skippedRows: Int
}

struct FireVaultCloudAccountRow: Decodable {
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
            recent: []
        )
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

enum FireVaultAccountSyncService {
    private static let bucket = "csv-imports"
    private static let accountSelect = "id,account_name,account_number,address_line_1,address_line_2,city,state,postal_code,country,latitude,longitude,phone,archived"

    static func fetchAccounts() async throws -> [FireVaultCloudAccountRow] {
        try await SupabaseManager.client
            .from("accounts")
            .select(accountSelect)
            .eq("archived", value: false)
            .order("account_name", ascending: true)
            .execute()
            .value
    }

    static func deleteAccount(id: UUID, name: String) async throws {
        let session = try await SupabaseManager.client.auth.session
        try await SupabaseManager.client
            .from("accounts")
            .delete()
            .eq("id", value: id)
            .eq("user_id", value: session.user.id)
            .execute()

        _ = try? await SupabaseManager.client
            .from("account_activity")
            .insert(AccountDeletionActivity(
                userID: session.user.id,
                accountName: name,
                metadata: ["deleted_account_id": id.uuidString.lowercased()]
            ))
            .execute()
    }

    static func importCSV(
        data: Data,
        fileName: String,
        analysis: FireVaultCSVAnalysis,
        localAccounts: [FireVaultWorkspaceAccount]
    ) async throws -> FireVaultCloudImportResult {
        let session = try await SupabaseManager.client.auth.session
        let userID = session.user.id
        let jobID = UUID()
        let safeFileName = sanitizedFileName(fileName)
        let storagePath = "\(userID.uuidString.lowercased())/\(jobID.uuidString.lowercased())/\(safeFileName)"
        let acceptedRecords = analysis.records.filter { $0.rowResult.status != .rejected }
        let skippedRows = analysis.records.count - acceptedRecords.count

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
            let rows = makeAccountRows(
                records: acceptedRecords,
                localAccounts: localAccounts,
                existingRows: existingRows,
                userID: userID,
                jobID: jobID
            )

            for start in stride(from: 0, to: rows.count, by: 200) {
                let end = min(start + 200, rows.count)
                let batch = Array(rows[start..<end])
                try await SupabaseManager.client
                    .from("accounts")
                    .upsert(batch)
                    .execute()
                importedRows += batch.count
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

    private static func makeAccountRows(
        records: [FireVaultCSVParsedRecord],
        localAccounts: [FireVaultWorkspaceAccount],
        existingRows: [FireVaultCloudAccountRow],
        userID: UUID,
        jobID: UUID
    ) -> [CloudAccountUpsert] {
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

        return records.map { record in
            let accountNumber = canonicalAccountID(record.accountID)
            let identity = identityKey(name: record.name, address: record.address)
            let existing = accountNumber.isEmpty
                ? existingByIdentity[identity]
                : existingByNumber[accountNumber]
            let local = localAccounts.first { account in
                if !accountNumber.isEmpty {
                    return canonicalAccountID(account.accountId) == accountNumber
                }
                return identityKey(name: account.name, address: account.address) == identity
            }
            let accountID = existing?.id
                ?? local.flatMap { UUID(uuidString: $0.id) }
                ?? UUID()

            return .init(
                id: accountID,
                userID: userID,
                importID: jobID,
                accountName: record.name,
                accountNumber: accountNumber.nilIfEmpty,
                addressLine1: record.addressLine1.nilIfEmpty,
                addressLine2: nil,
                city: record.city.nilIfEmpty,
                state: record.state.nilIfEmpty,
                postalCode: record.postalCode.nilIfEmpty,
                country: "US",
                latitude: record.latitude,
                longitude: record.longitude,
                phone: record.phone.nilIfEmpty,
                archived: false
            )
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
}

private struct AccountDeletionActivity: Encodable {
    let userID: UUID
    let accountName: String
    let eventType = "deleted"
    let source = "ios_app"
    let summary = "Account permanently deleted from iPhone"
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case accountName = "account_name"
        case eventType = "event_type"
        case source
        case summary
        case metadata
    }
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

private struct CloudAccountUpsert: Encodable {
    let id: UUID
    let userID: UUID
    let importID: UUID
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

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
