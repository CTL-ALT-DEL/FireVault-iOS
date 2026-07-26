//
//  FireVaultTripLogAutomationService.swift
//  FireVault
//
//  Secure Trip Log report scheduling and completed-day synchronization.
//

import Foundation
import Supabase

@MainActor
final class FireVaultTripLogAutomationService {
    static let shared = FireVaultTripLogAutomationService()
    private let pendingDaysKey = "firevault.trip-log-report.pending-days.v1"

    private struct PreferenceRow: Encodable {
        let userID: UUID
        let dailyEnabled: Bool
        let dailyHour: Int
        let dailyMinute: Int
        let weeklyEnabled: Bool
        let weeklyWeekday: Int
        let weeklyHour: Int
        let weeklyMinute: Int
        let timeZone: String
        let recipients: [String]
        let cc: [String]
        let reportDetail: String
        let includeCoordinates: Bool
        let includeTechnician: Bool
        let technicianName: String
        let companyName: String
        let replyTo: String?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case dailyEnabled = "daily_enabled"
            case dailyHour = "daily_hour"
            case dailyMinute = "daily_minute"
            case weeklyEnabled = "weekly_enabled"
            case weeklyWeekday = "weekly_weekday"
            case weeklyHour = "weekly_hour"
            case weeklyMinute = "weekly_minute"
            case timeZone = "time_zone"
            case recipients, cc
            case reportDetail = "report_detail"
            case includeCoordinates = "include_coordinates"
            case includeTechnician = "include_technician"
            case technicianName = "technician_name"
            case companyName = "company_name"
            case replyTo = "reply_to"
            case updatedAt = "updated_at"
        }
    }

    private struct DayRow: Encodable {
        let id: UUID
        let userID: UUID
        let startedAt: Date
        let endedAt: Date
        let payload: FireVaultBreadcrumbDay
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case userID = "user_id"
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case payload
            case updatedAt = "updated_at"
        }
    }

    func syncPreferences(_ preferences: FireVaultNativePreferences) async throws {
        let session = try await SupabaseManager.client.auth.session
        let recipients = Self.addresses(
            preferences.email.defaultTo.isEmpty
                ? preferences.technician.email
                : preferences.email.defaultTo
        )
        let row = PreferenceRow(
            userID: session.user.id,
            dailyEnabled: preferences.reports.dailyEmailEnabled,
            dailyHour: preferences.reports.dailyEmailHour,
            dailyMinute: preferences.reports.dailyEmailMinute,
            weeklyEnabled: preferences.reports.weeklyEmailEnabled,
            weeklyWeekday: preferences.reports.weeklyEmailWeekday,
            weeklyHour: preferences.reports.weeklyEmailHour,
            weeklyMinute: preferences.reports.weeklyEmailMinute,
            timeZone: preferences.reports.reportTimeZone,
            recipients: recipients,
            cc: Self.addresses(preferences.email.cc),
            reportDetail: preferences.reports.format,
            includeCoordinates: preferences.gps.includeCoordinatesInReports,
            includeTechnician: preferences.reports.includeTechnician,
            technicianName: preferences.technician.name,
            companyName: preferences.technician.company,
            replyTo: Self.addresses(preferences.technician.email).first,
            updatedAt: Date()
        )

        try await SupabaseManager.client
            .from("trip_log_report_preferences")
            .upsert(row, onConflict: "user_id", returning: .minimal)
            .execute()

        if preferences.reports.dailyEmailEnabled || preferences.reports.weeklyEmailEnabled {
            try await flushPendingDays(userID: session.user.id)
        } else {
            savePendingDays([])
        }
    }

    func syncCompletedDay(
        _ day: FireVaultBreadcrumbDay,
        preferences: FireVaultNativePreferences
    ) async {
        guard day.endedAt != nil else { return }
        guard preferences.reports.dailyEmailEnabled || preferences.reports.weeklyEmailEnabled else {
            return
        }
        queue(day)
        do {
            try await syncPreferences(preferences)
        } catch {
            // The on-device Trip Log remains authoritative. The queued day is
            // retried after a later settings save or completed workday.
        }
    }

    private func queue(_ day: FireVaultBreadcrumbDay) {
        var days = pendingDays()
        days.removeAll { $0.id == day.id }
        days.append(day)
        savePendingDays(days)
    }

    private func flushPendingDays(userID: UUID) async throws {
        var remaining = pendingDays()
        for day in remaining {
            guard let endedAt = day.endedAt else {
                remaining.removeAll { $0.id == day.id }
                continue
            }
            let row = DayRow(
                id: day.id,
                userID: userID,
                startedAt: day.startedAt,
                endedAt: endedAt,
                payload: day,
                updatedAt: Date()
            )
            try await SupabaseManager.client
                .from("trip_log_days")
                .upsert(row, onConflict: "id", returning: .minimal)
                .execute()
            remaining.removeAll { $0.id == day.id }
            savePendingDays(remaining)
        }
    }

    private func pendingDays() -> [FireVaultBreadcrumbDay] {
        guard let data = UserDefaults.standard.data(forKey: pendingDaysKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([FireVaultBreadcrumbDay].self, from: data)) ?? []
    }

    private func savePendingDays(_ days: [FireVaultBreadcrumbDay]) {
        guard !days.isEmpty else {
            UserDefaults.standard.removeObject(forKey: pendingDaysKey)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(days) {
            UserDefaults.standard.set(data, forKey: pendingDaysKey)
        }
    }

    private static func addresses(_ value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.contains("@") && $0.contains(".") }
    }
}
