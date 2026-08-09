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

    func sendDeveloperTest(title: String, body: String, delay: TimeInterval, sound: Bool) async throws -> String {
        let identifier = "firevault.developer.test.\(UUID().uuidString)"
        let content = UNMutableNotificationContent()
        content.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if sound { content.sound = .default }
        content.userInfo = ["source": "FireVault Notification Test"]
        try await center.add(.init(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        ))
        return identifier
    }

    func pendingRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func deliveredNotifications() async -> [UNNotification] {
        await center.deliveredNotifications()
    }

    func cancelDeveloperTests() {
        Task {
            let identifiers = await pendingRequests().map(\.identifier).filter { $0.hasPrefix("firevault.developer.test.") }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func clearDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
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

#if DEBUG
            Section {
                NavigationLink {
                    FireVaultNotificationDeveloperView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notification Test & Edit")
                                .font(.headline)
                            Text("Compose, schedule, inspect, and clear development alerts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Developer")
            } footer: {
                Text("This tool is included only in Debug builds and is not shown in release versions of FireVault.")
            }
#endif
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

#if DEBUG
private enum FireVaultNotificationTestTemplate: String, CaseIterable, Identifiable {
    case recording = "Trip Log Recording"
    case paused = "Trip Log Paused"
    case inspection = "Upcoming Inspection"
    case failure = "Report/Sync Failure"
    case security = "Security Alert"
    case custom = "Custom"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recording: "Trip Log is still recording"
        case .paused: "Trip Log is paused"
        case .inspection: "Inspection coming up"
        case .failure: "FireVault needs attention"
        case .security: "New FireVault sign-in"
        case .custom: "FireVault Test Notification"
        }
    }
    var body: String {
        switch self {
        case .recording: "Review your active workday and end Trip Log when you are finished."
        case .paused: "Resume Trip Log before continuing your route."
        case .inspection: "An upcoming inspection is ready for review."
        case .failure: "A report, sync, or backup operation could not be completed."
        case .security: "Review recent account activity in FireVault Pro."
        case .custom: "Edit this message to preview a custom FireVault alert."
        }
    }
}

private struct FireVaultNotificationDeveloperView: View {
    @State private var template = FireVaultNotificationTestTemplate.recording
    @State private var title = FireVaultNotificationTestTemplate.recording.title
    @State private var messageBody = FireVaultNotificationTestTemplate.recording.body
    @State private var delaySeconds = 5
    @State private var soundEnabled = true
    @State private var pendingCount = 0
    @State private var deliveredCount = 0
    @State private var statusMessage = "Ready"
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section("Test Message") {
                Picker("Template", selection: $template) {
                    ForEach(FireVaultNotificationTestTemplate.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Notification title", text: $title)
                TextField("Notification message", text: $messageBody, axis: .vertical)
                    .lineLimit(2...5)
                Picker("Delivery delay", selection: $delaySeconds) {
                    Text("1 second").tag(1)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                }
                Toggle("Play sound", isOn: $soundEnabled)
            }

            Section {
                Button("Schedule Test Notification", systemImage: "bell.and.waves.left.and.right.fill") {
                    Task { await sendTest() }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if authorizationStatus == .notDetermined {
                    Button("Enable Notification Permission", systemImage: "bell.badge.fill") {
                        Task { await requestPermission() }
                    }
                }
                LabeledContent("Status", value: statusMessage)
            }

            Section("Notification Queue") {
                LabeledContent("Pending", value: "\(pendingCount)")
                LabeledContent("Delivered", value: "\(deliveredCount)")
                Button("Refresh Counts", systemImage: "arrow.clockwise") { Task { await refreshCounts() } }
                Button("Cancel Pending Test Alerts", systemImage: "bell.slash", role: .destructive) {
                    FireVaultNotificationService.shared.cancelDeveloperTests()
                    Task { try? await Task.sleep(for: .milliseconds(200)); await refreshCounts() }
                }
                Button("Clear Delivered Alerts", systemImage: "trash", role: .destructive) {
                    FireVaultNotificationService.shared.clearDeliveredNotifications()
                    Task { await refreshCounts() }
                }
            }

            Section {
                Text("For the most realistic test, schedule an alert and immediately place FireVault in the background or lock the iPhone. iOS normally does not display a notification banner while its app is open in the foreground.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notification Lab")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 82)
        .onChange(of: template) { _, selection in
            guard selection != .custom else { return }
            title = selection.title
            messageBody = selection.body
        }
        .task {
            authorizationStatus = await FireVaultNotificationService.shared.authorizationStatus()
            await refreshCounts()
        }
    }

    private func requestPermission() async {
        let allowed = (try? await FireVaultNotificationService.shared.requestAuthorization()) ?? false
        authorizationStatus = await FireVaultNotificationService.shared.authorizationStatus()
        statusMessage = allowed ? "Permission allowed" : "Permission not allowed"
    }

    private func sendTest() async {
        authorizationStatus = await FireVaultNotificationService.shared.authorizationStatus()
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            statusMessage = "Enable notification permission first"
            return
        }
        do {
            _ = try await FireVaultNotificationService.shared.sendDeveloperTest(
                title: title,
                body: messageBody,
                delay: TimeInterval(delaySeconds),
                sound: soundEnabled
            )
            statusMessage = "Scheduled in \(delaySeconds) seconds"
            await refreshCounts()
        } catch {
            statusMessage = "Test failed: \(error.localizedDescription)"
        }
    }

    private func refreshCounts() async {
        pendingCount = await FireVaultNotificationService.shared.pendingRequests().count
        deliveredCount = await FireVaultNotificationService.shared.deliveredNotifications().count
    }
}
#endif
