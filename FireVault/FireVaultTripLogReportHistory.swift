//
//  FireVaultTripLogReportHistory.swift
//  FireVault
//
//  Resolves the complete saved Trip Log archive for weekly report templates
//  without changing the existing on-device archive names or data format.
//

import Foundation

extension FireVaultBreadcrumbReportView {
    init(report: FireVaultBreadcrumbReport) {
        self.init(
            report: report,
            availableDays: FireVaultTripLogReportHistory.days(
                containing: report.dayID,
                fallback: report.sourceDay
            )
        )
    }
}

private enum FireVaultTripLogReportHistory {
    static func days(
        containing selectedDayID: UUID,
        fallback: FireVaultBreadcrumbDay
    ) -> [FireVaultBreadcrumbDay] {
        let fileManager = FileManager.default
        let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("FireVault", isDirectory: true)

        guard let root,
              let files = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return [fallback]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archives = files
            .filter {
                $0.pathExtension.lowercased() == "json"
                    && $0.lastPathComponent.lowercased().contains("breadcrumb")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for archive in archives {
            guard let data = try? Data(contentsOf: archive),
                  let days = try? decoder.decode([FireVaultBreadcrumbDay].self, from: data),
                  days.contains(where: { $0.id == selectedDayID }) else {
                continue
            }

            return days.sorted { $0.startedAt > $1.startedAt }
        }

        return [fallback]
    }
}
