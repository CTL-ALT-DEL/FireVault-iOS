//
//  FireVaultTripLogArchiveWriter.swift
//  FireVault
//
//  Serial, coalescing Trip Log disk writer. File I/O stays off the main actor
//  while critical lifecycle saves can bypass the short debounce.
//

import Foundation

actor FireVaultTripLogArchiveWriter {
    static let shared = FireVaultTripLogArchiveWriter()
    private var generations: [URL: Int] = [:]

    func write(_ data: Data, to archiveURL: URL, immediate: Bool) async throws -> Bool {
        let requestedGeneration = (generations[archiveURL] ?? 0) + 1
        generations[archiveURL] = requestedGeneration
        if !immediate {
            try await Task.sleep(for: .milliseconds(750))
        }
        guard requestedGeneration == generations[archiveURL] else { return false }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: archiveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: archiveURL.path) {
            let backupURL = archiveURL.deletingPathExtension().appendingPathExtension("backup.json")
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.copyItem(at: archiveURL, to: backupURL)
        }
        try data.write(
            to: archiveURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        return true
    }
}
