import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class FireVaultNotificationService {
    static let shared = FireVaultNotificationService()

    private enum Identifier {
        static let recording = "firevault.triplog.recording"
        static let paused = "firevault.triplog.paused"
    }

    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func tripLogStarted(preferences: FireVaultNotificationPreferences) {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.recording, Identifier.paused])
        guard preferences.isEnabled, preferences.recordingReminderEnabled else { return }

        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = preferences.resolvedEndOfDayHour
        components.minute = 0
        var reminderDate = Calendar.current.date(from: components) ?? now.addingTimeInterval(8 * 60 * 60)
        if reminderDate <= now { reminderDate = now.addingTimeInterval(2 * 60 * 60) }

        let content = UNMutableNotificationContent()
        content.title = "Trip Log is still recording"
        content.body = preferences.hidesSensitiveDetails
            ? "Review your active workday and end Trip Log when you are finished."
            : "FireVault Pro is still recording today’s Trip Log."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
            repeats: false
        )
        center.add(.init(identifier: Identifier.recording, content: content, trigger: trigger))
    }

    func tripLogPaused(preferences: FireVaultNotificationPreferences) {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.recording, Identifier.paused])
        guard preferences.isEnabled, preferences.pausedReminderEnabled else { return }
        schedule(
            identifier: Identifier.paused,
            title: "Trip Log is paused",
            body: "Resume Trip Log before continuing your route.",
            after: 15 * 60
        )
    }

    func tripLogEnded() {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.recording, Identifier.paused])
    }

    private func schedule(identifier: String, title: String, body: String, after interval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(.init(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        ))
    }
}

struct NativeNotificationSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNotificationPreferences
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Environment(\.openURL) private var openURL

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences.notifications ?? FireVaultNotificationPreferences())
    }

    var body: some View {
        Form {
            Section {
                Toggle("Allow FireVault notifications", isOn: optionalBinding(\.enabled, default: true))
                LabeledContent("iOS permission", value: authorizationLabel)
                if authorizationStatus == .notDetermined {
                    Button("Enable Notifications", systemImage: "bell.badge.fill") {
                        Task { await requestPermission() }
                    }
                } else if authorizationStatus == .denied {
                    Button("Open iOS Notification Settings", systemImage: "gearshape") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            } footer: {
                Text("FireVault asks for permission only when you choose Enable Notifications.")
            }

            Section("Trip Log") {
                Toggle("Still recording reminder", isOn: optionalBinding(\.tripLogStillRecording, default: true))
                Toggle("Paused reminder", isOn: optionalBinding(\.tripLogPaused, default: true))
                Toggle("Arrival notifications", isOn: optionalBinding(\.arrivalAlerts, default: false))
                Toggle("Unknown stop review", isOn: optionalBinding(\.unknownStopReview, default: false))
                Picker("End-of-day reminder", selection: optionalIntBinding(\.endOfDayHour, default: 18)) {
                    ForEach(15...22, id: \.self) { hour in Text(hourLabel(hour)).tag(hour) }
                }
            }

            Section("Service") {
                Toggle("Upcoming inspections", isOn: optionalBinding(\.upcomingInspections, default: true))
                Toggle("Shared account updates", isOn: optionalBinding(\.sharedAccountUpdates, default: false))
            }

            Section("Reports, Storage & Security") {
                Toggle("Report, sync, and backup failures", isOn: optionalBinding(\.deliveryFailures, default: true))
                Toggle("Sign-in and security alerts", isOn: optionalBinding(\.securityAlerts, default: true))
            }

            Section {
                Toggle("Hide customer details on Lock Screen", isOn: optionalBinding(\.hideSensitiveDetails, default: true))
                Toggle("Quiet hours", isOn: optionalBinding(\.quietHoursEnabled, default: true))
                if draft.usesQuietHours {
                    Picker("Begin", selection: optionalIntBinding(\.quietHoursStart, default: 20)) {
                        ForEach(0..<24, id: \.self) { hour in Text(hourLabel(hour)).tag(hour) }
                    }
                    Picker("End", selection: optionalIntBinding(\.quietHoursEnd, default: 7)) {
                        ForEach(0..<24, id: \.self) { hour in Text(hourLabel(hour)).tag(hour) }
                    }
                }
            } header: {
                Text("Privacy & Schedule")
            } footer: {
                Text("Security and failure alerts may still appear during quiet hours when action is needed.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 82)
        .task { authorizationStatus = await FireVaultNotificationService.shared.authorizationStatus() }
        .onDisappear { save() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Save", action: save) } }
    }

    private var authorizationLabel: String {
        switch authorizationStatus {
        case .authorized: "Allowed"
        case .denied: "Off"
        case .provisional: "Provisional"
        case .ephemeral: "Temporary"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<FireVaultNotificationPreferences, Bool?>, default fallback: Bool) -> Binding<Bool> {
        .init(get: { draft[keyPath: keyPath] ?? fallback }, set: { draft[keyPath: keyPath] = $0 })
    }

    private func optionalIntBinding(_ keyPath: WritableKeyPath<FireVaultNotificationPreferences, Int?>, default fallback: Int) -> Binding<Int> {
        .init(get: { draft[keyPath: keyPath] ?? fallback }, set: { draft[keyPath: keyPath] = $0 })
    }

    private func hourLabel(_ hour: Int) -> String {
        DateComponents(calendar: .current, hour: hour).date?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }

    private func requestPermission() async {
        _ = try? await FireVaultNotificationService.shared.requestAuthorization()
        authorizationStatus = await FireVaultNotificationService.shared.authorizationStatus()
    }

    private func save() {
        var preferences = settings.preferences
        preferences.notifications = draft
        settings.save(preferences)
    }
}
