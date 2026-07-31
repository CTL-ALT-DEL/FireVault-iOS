import Foundation
import Combine
import Supabase

enum FireVaultDiagnosticStatus: String, Codable {
    case running
    case passed
    case warning
    case failed

    var symbol: String {
        switch self {
        case .running: "hourglass"
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }
}

struct FireVaultDiagnosticResult: Identifiable, Equatable {
    let id: String
    let title: String
    let status: FireVaultDiagnosticStatus
    let detail: String
    let durationMilliseconds: Int
}

@MainActor
final class FireVaultDiagnosticRunner: ObservableObject {
    @Published private(set) var results: [FireVaultDiagnosticResult] = []
    @Published private(set) var isRunning = false

    func runSafeChecks(
        accounts: [FireVaultWorkspaceAccount],
        preferences: FireVaultNativePreferences
    ) async {
        guard !isRunning else { return }
        isRunning = true
        results = []

        await run("local-vault", title: "Local account vault") {
            let data = try JSONEncoder().encode(accounts)
            let decoded = try JSONDecoder().decode([FireVaultWorkspaceAccount].self, from: data)
            guard decoded.count == accounts.count else {
                return (.failed, "Encoded \(accounts.count) accounts but decoded \(decoded.count).")
            }
            return (.passed, "\(accounts.count) accounts encode and decode successfully (\(data.count) bytes).")
        }

        await run("account-integrity", title: "Account integrity") {
            let duplicateIDs = Dictionary(grouping: accounts, by: \.id).filter { $0.value.count > 1 }
            let invalidCoordinates = accounts.filter {
                guard $0.latitude != nil || $0.longitude != nil else { return false }
                return $0.coordinate == nil
            }
            if !duplicateIDs.isEmpty || !invalidCoordinates.isEmpty {
                return (
                    .warning,
                    "\(duplicateIDs.count) duplicate IDs; \(invalidCoordinates.count) invalid or partial coordinates."
                )
            }
            return (.passed, "Account IDs are unique and all saved coordinates are valid.")
        }

        await run("settings", title: "Settings serialization") {
            let data = try JSONEncoder().encode(preferences)
            _ = try JSONDecoder().decode(FireVaultNativePreferences.self, from: data)
            return (.passed, "Settings encode and decode successfully.")
        }

        await run("storage", title: "Application Support storage") {
            let manager = FileManager.default
            guard let root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                return (.failed, "Application Support directory is unavailable.")
            }
            let directory = root.appendingPathComponent("FireVault/Diagnostics", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("write-test-\(UUID().uuidString).tmp")
            let marker = Data("FireVault diagnostic".utf8)
            try marker.write(to: file, options: .atomic)
            let readback = try Data(contentsOf: file)
            try manager.removeItem(at: file)
            return readback == marker
                ? (.passed, "Temporary write, read, and cleanup succeeded.")
                : (.failed, "Temporary storage readback did not match.")
        }

        await runSupabaseChecks()
        isRunning = false
    }

    func runSupabaseChecks() async {
        await run("supabase-session", title: "Supabase session") {
            let session = try await SupabaseManager.client.auth.session
            guard !session.isExpired else { return (.failed, "The saved session is expired.") }
            return (.passed, "Authenticated as \(session.user.email ?? session.user.id.uuidString).")
        }

        await run("database-preferences", title: "Database: report preferences") {
            _ = try await SupabaseManager.client
                .from("trip_log_report_preferences")
                .select("user_id")
                .limit(1)
                .execute()
            return (.passed, "Table is reachable and row-level security accepted the query.")
        }

        await run("database-days", title: "Database: Trip Log days") {
            _ = try await SupabaseManager.client
                .from("trip_log_days")
                .select("id")
                .limit(1)
                .execute()
            return (.passed, "Table is reachable and row-level security accepted the query.")
        }
    }

    func runAIEndpointCheck() async {
        await run("ai-endpoint", title: "AI Edge Function") {
            let account = FireVaultWorkspaceAccount(
                id: "diagnostic",
                name: "FireVault Diagnostic",
                address: "No customer data",
                category: "",
                accountId: "",
                phone: "",
                favorite: false,
                latitude: nil,
                longitude: nil,
                tags: [],
                notes: [],
                documents: [],
                equipment: [],
                locations: [],
                recent: []
            )
            let response = try await FireVaultAIService.shared.generateAccountBrief(for: account)
            return response.isEmpty
                ? (.failed, "The function returned an empty response.")
                : (.passed, "Authenticated Edge Function call returned \(response.count) characters.")
        }
    }

    func clear() {
        guard !isRunning else { return }
        results = []
    }

    var report: String {
        results.map {
            "[\($0.status.rawValue.uppercased())] \($0.title) (\($0.durationMilliseconds) ms)\n\($0.detail)"
        }.joined(separator: "\n\n")
    }

    private func run(
        _ id: String,
        title: String,
        operation: () async throws -> (FireVaultDiagnosticStatus, String)
    ) async {
        let started = ContinuousClock.now
        upsert(.init(id: id, title: title, status: .running, detail: "Running…", durationMilliseconds: 0))
        do {
            let (status, detail) = try await operation()
            upsert(.init(
                id: id,
                title: title,
                status: status,
                detail: detail,
                durationMilliseconds: Self.milliseconds(since: started)
            ))
        } catch {
            upsert(.init(
                id: id,
                title: title,
                status: .failed,
                detail: error.localizedDescription,
                durationMilliseconds: Self.milliseconds(since: started)
            ))
        }
    }

    private func upsert(_ result: FireVaultDiagnosticResult) {
        if let index = results.firstIndex(where: { $0.id == result.id }) {
            results[index] = result
        } else {
            results.append(result)
        }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now)
        return Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
