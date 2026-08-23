//
//  FireVaultAccountArchive.swift
//  FireVault
//
//  Scalable Application Support persistence for account records. UserDefaults
//  remains a read-only migration fallback for existing installations.
//

import Foundation

enum FireVaultAccountArchive {
    static func primaryURL(demoMode: Bool) -> URL? {
        rootURL()?.appendingPathComponent(
            demoMode ? "demo-accounts-v1.json" : "accounts-v1.json"
        )
    }

    static func backupURL(for primaryURL: URL) -> URL {
        primaryURL.deletingPathExtension().appendingPathExtension("backup.json")
    }

    static func load(from primaryURL: URL) -> [FireVaultWorkspaceAccount]? {
        decode(primaryURL) ?? decode(backupURL(for: primaryURL))
    }

    private static func decode(_ url: URL) -> [FireVaultWorkspaceAccount]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? JSONDecoder().decode([FireVaultWorkspaceAccount].self, from: data)
    }

    private static func rootURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FireVault", isDirectory: true)
            .appendingPathComponent("Vault", isDirectory: true)
    }
}

actor FireVaultAccountArchiveWriter {
    static let shared = FireVaultAccountArchiveWriter()
    private var latestGenerations: [URL: Int] = [:]

    @discardableResult
    func write(
        _ data: Data,
        to primaryURL: URL,
        generation: Int,
        immediate: Bool = false
    ) async throws -> Bool {
        guard generation >= (latestGenerations[primaryURL] ?? -1) else { return false }
        latestGenerations[primaryURL] = generation
        if !immediate {
            try await Task.sleep(for: .milliseconds(300))
        }
        guard generation == latestGenerations[primaryURL] else { return false }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: primaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: primaryURL.path) {
            let backupURL = primaryURL.deletingPathExtension().appendingPathExtension("backup.json")
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: primaryURL, to: backupURL)
        }
        try data.write(
            to: primaryURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        return true
    }
}
