//
//  FireVaultAIService.swift
//  FireVault
//
//  Authenticated access to FireVault's Supabase-hosted AI features.
//

import Foundation
import Supabase
import SwiftUI

struct FireVaultAccountBriefRequest: Encodable, Equatable {
    let accountName: String
    let technicianRequest: String
}

struct FireVaultAccountBriefResponse: Decodable, Equatable {
    let assistantText: String
}

struct FireVaultAccountBriefSection: Identifiable, Equatable {
    let title: String
    let items: [String]

    var id: String { title }
}

struct FireVaultAccountBriefDocument: Equatable {
    let sections: [FireVaultAccountBriefSection]

    init(text: String) {
        var parsedSections: [FireVaultAccountBriefSection] = []
        var currentTitle = "Quick Summary"
        var currentItems: [String] = []

        func appendCurrentSection() {
            guard !currentItems.isEmpty else { return }
            parsedSections.append(.init(title: currentTitle, items: currentItems))
            currentItems = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                appendCurrentSection()
                currentTitle = line
                    .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                    .replacingOccurrences(of: "**", with: "")
            } else if line.hasPrefix("**"), line.hasSuffix("**") {
                appendCurrentSection()
                currentTitle = line.replacingOccurrences(of: "**", with: "")
            } else {
                let item = line
                    .replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "**", with: "")
                if !item.isEmpty {
                    currentItems.append(item)
                }
            }
        }
        appendCurrentSection()

        if parsedSections.isEmpty {
            let fallback = text.trimmingCharacters(in: .whitespacesAndNewlines)
            parsedSections = fallback.isEmpty
                ? []
                : [.init(title: "Quick Summary", items: [fallback])]
        }
        sections = parsedSections
    }
}

enum FireVaultAIError: LocalizedError {
    case emptyResponse
    case notAuthenticated
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            "FireVault AI returned an empty account brief. Please try again."
        case .notAuthenticated:
            "Your FireVault session has expired. Sign in again, then retry."
        case .requestFailed:
            "FireVault could not generate the account brief. Check your connection and try again."
        }
    }
}

protocol FireVaultAIProviding {
    func generateAccountBrief(for account: FireVaultWorkspaceAccount) async throws -> String
}

final class FireVaultAIService: FireVaultAIProviding {
    static let shared = FireVaultAIService()

    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseManager.client) {
        self.client = client
    }

    func generateAccountBrief(for account: FireVaultWorkspaceAccount) async throws -> String {
        do {
            _ = try await client.auth.session
        } catch {
            throw FireVaultAIError.notAuthenticated
        }

        do {
            let response: FireVaultAccountBriefResponse = try await client.functions.invoke(
                "firevault-ai",
                options: FunctionInvokeOptions(body: Self.makeRequest(for: account))
            )
            let brief = response.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !brief.isEmpty else {
                throw FireVaultAIError.emptyResponse
            }
            return brief
        } catch let error as FireVaultAIError {
            throw error
        } catch {
            throw FireVaultAIError.requestFailed
        }
    }

    static func makeRequest(for account: FireVaultWorkspaceAccount) -> FireVaultAccountBriefRequest {
        let notes = account.notes.prefix(20).map {
            "- \($0.date): \($0.title) — \($0.text)"
        }
        let equipment = account.equipment.prefix(20).map {
            "- \($0.title): \($0.subtitle)" + ($0.deviceAddress.isEmpty ? "" : " [Device address: \($0.deviceAddress)]")
        }
        let documents = account.documents.prefix(20).map {
            "- \($0.date): \($0.title) — \($0.subtitle)"
        }
        let recent = account.recent.prefix(20).map {
            "- \($0.date): \($0.title) — \($0.subtitle)"
        }

        let sections = [
            """
            Prepare a concise account brief for a fire-alarm technician. Identify recurring issues only when supported by the supplied records. Cite relevant record dates or titles and clearly state when history is insufficient.

            Return only these Markdown sections, omitting a section when it has nothing useful to say:
            ## Quick Summary
            ## Recurring Issues
            ## Relevant History
            ## Suggested Checks

            Put each finding on its own bullet. Do not add an introduction or conclusion.
            """,
            "Account ID: \(account.accountId.isEmpty ? "Not provided" : account.accountId)",
            "Address: \(account.address)",
            "Category: \(account.category.isEmpty ? "Not provided" : account.category)",
            "Tags: \(account.tags.isEmpty ? "None" : account.tags.joined(separator: ", "))",
            "Notes:\n\(notes.isEmpty ? "- None" : notes.joined(separator: "\n"))",
            "Equipment:\n\(equipment.isEmpty ? "- None" : equipment.joined(separator: "\n"))",
            "Files and scans:\n\(documents.isEmpty ? "- None" : documents.joined(separator: "\n"))",
            "Recent activity:\n\(recent.isEmpty ? "- None" : recent.joined(separator: "\n"))"
        ]

        return FireVaultAccountBriefRequest(
            accountName: account.name,
            technicianRequest: sections.joined(separator: "\n\n")
        )
    }
}

struct FireVaultAccountBriefSheet: View {
    let accountName: String
    let isLoading: Bool
    let brief: String?
    let errorMessage: String?
    let retry: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Reviewing \(accountName)’s history…")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("FireVault is checking the account records for useful patterns.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                } else if let brief {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(FireVaultAccountBriefDocument(text: brief).sections) { section in
                                accountBriefSection(section)
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Brief Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage ?? "FireVault could not generate an account brief.")
                    } actions: {
                        Button("Try Again", action: retry)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Account Brief")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func accountBriefSection(_ section: FireVaultAccountBriefSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.title, systemImage: symbol(for: section.title))
                .font(.headline)
                .foregroundStyle(tint(for: section.title))

            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(tint(for: section.title))
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    Text(item)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func symbol(for title: String) -> String {
        let value = title.lowercased()
        if value.contains("recurring") { return "arrow.trianglehead.2.clockwise.rotate.90" }
        if value.contains("history") { return "clock.arrow.circlepath" }
        if value.contains("check") { return "checklist" }
        return "sparkles"
    }

    private func tint(for title: String) -> Color {
        let value = title.lowercased()
        if value.contains("recurring") { return .orange }
        if value.contains("history") { return .blue }
        if value.contains("check") { return .green }
        return .purple
    }
}
