#if DEBUG
import AVFoundation
import CoreLocation
import Foundation
import Photos
import SwiftUI
import Supabase
import UIKit
import UserNotifications

struct FireVaultFieldTestDashboard: View {
    let versionInfo: FireVaultVersionInfo
    let demoMode: Bool
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    @State private var pendingNotificationCount = 0
    @State private var deliveredNotificationCount = 0
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    @State private var storageBytes: Int64 = 0
    @State private var supabaseStatus = "Checking…"
    @State private var copied = false
    @State private var refreshedAt: Date?

    private var activeDay: FireVaultBreadcrumbDay? { breadcrumbs.activeDay }
    private var latestPoint: FireVaultBreadcrumbPoint? { activeDay?.points.last }

    var body: some View {
        List {
            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 12) {
                        Image(systemName: breadcrumbs.isRecording ? "location.fill" : "location.slash")
                            .font(.title2.bold())
                            .foregroundStyle(breadcrumbs.isRecording ? NativeShellPalette.green : NativeShellPalette.amber)
                            .frame(width: 42, height: 42)
                            .background(
                                (breadcrumbs.isRecording ? NativeShellPalette.green : NativeShellPalette.amber).opacity(0.13),
                                in: Circle()
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tripStatus)
                                .font(.headline)
                            Text(activeDuration(at: context.date))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                LabeledContent("Status message", value: breadcrumbs.statusText)
            } header: {
                Text("Trip Log Runtime")
            }

            Section("GPS Pipeline") {
                metric("Accepted this session", "\(breadcrumbs.acceptedLocationCount)", "checkmark.circle.fill", NativeShellPalette.green)
                metric("Rejected this session", "\(breadcrumbs.rejectedLocationCount)", "xmark.circle.fill", NativeShellPalette.amber)
                LabeledContent("Saved route points", value: "\(activeDay?.points.count ?? 0)")
                LabeledContent("Detected stops", value: "\(activeDay?.stops.count ?? 0)")
                LabeledContent("Horizontal accuracy", value: accuracyText)
                LabeledContent("Last waypoint", value: latestPoint?.timestamp.formatted(date: .omitted, time: .standard) ?? "None")
                LabeledContent("Location permission", value: breadcrumbs.permissionState.title)
            }

            Section("Persistence") {
                LabeledContent("Last successful save", value: breadcrumbs.lastSuccessfulSaveAt?.formatted(date: .omitted, time: .standard) ?? "Not this session")
                LabeledContent("Last backup recovery", value: breadcrumbs.lastRecoveryAt?.formatted(date: .abbreviated, time: .standard) ?? "None this session")
                LabeledContent("Persistence error", value: breadcrumbs.lastPersistenceError ?? "None")
                LabeledContent("Application Support", value: ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                LabeledContent("Accounts loaded", value: "\(store.accounts.count)")
                LabeledContent("Mapped accounts", value: "\(store.mappedAccountCount)")
            }

            Section("Notifications & Services") {
                LabeledContent("Notification permission", value: notificationAuthorization.label)
                LabeledContent("Pending notifications", value: "\(pendingNotificationCount)")
                LabeledContent("Delivered notifications", value: "\(deliveredNotificationCount)")
                LabeledContent("Supabase", value: supabaseStatus)
            }

            Section("Device & Permissions") {
                LabeledContent("Camera", value: AVCaptureDevice.authorizationStatus(for: .video).label)
                LabeledContent("Photos", value: PHPhotoLibrary.authorizationStatus(for: .readWrite).label)
                LabeledContent("Low Power Mode", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
                LabeledContent("Thermal state", value: ProcessInfo.processInfo.thermalState.label)
                LabeledContent("Battery", value: batteryText)
            }

            Section("Build") {
                LabeledContent("Version", value: versionInfo.version)
                LabeledContent("Build", value: versionInfo.build)
                LabeledContent("Workspace", value: demoMode ? "Demo" : "Production")
                LabeledContent("Last refreshed", value: refreshedAt?.formatted(date: .omitted, time: .standard) ?? "Never")
            }

            Section {
                Button("Refresh Dashboard", systemImage: "arrow.clockwise") {
                    Task { await refresh() }
                }
                Button(copied ? "Diagnostic Report Copied" : "Copy Field Test Report", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = report
                    copied = true
                }
            } footer: {
                Text("Runtime counters restart when FireVault is relaunched. Saved Trip Log totals remain in the local archive.")
            }
        }
        .fireVaultThemedCollection()
        .navigationTitle("Field Test Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 96, for: .scrollContent)
        .task {
            UIDevice.current.isBatteryMonitoringEnabled = true
            await refresh()
        }
        .onDisappear { UIDevice.current.isBatteryMonitoringEnabled = false }
    }

    private var tripStatus: String {
        if breadcrumbs.isRecording { return "Recording" }
        if breadcrumbs.activeDay?.isPaused == true { return "Paused" }
        return breadcrumbs.activeDay == nil ? "No active workday" : "Saved"
    }

    private func activeDuration(at date: Date) -> String {
        guard let activeDay else { return "00:00:00" }
        return max(0, date.timeIntervalSince(activeDay.startedAt)).fieldTestDuration
    }

    private var accuracyText: String {
        guard let accuracy = latestPoint?.horizontalAccuracy else { return "Waiting" }
        return "±\(Int(accuracy.rounded())) m"
    }

    private var batteryText: String {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return "Unavailable" }
        return "\(Int((level * 100).rounded()))% • \(UIDevice.current.batteryState.label)"
    }

    private func metric(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(tint)
            Spacer()
            Text(value).font(.body.bold().monospacedDigit())
        }
    }

    private func refresh() async {
        notificationAuthorization = await FireVaultNotificationService.shared.authorizationStatus()
        pendingNotificationCount = await FireVaultNotificationService.shared.pendingRequests().count
        deliveredNotificationCount = await FireVaultNotificationService.shared.deliveredNotifications().count
        storageBytes = Self.applicationSupportSize()
        do {
            let session = try await SupabaseManager.client.auth.session
            supabaseStatus = session.isExpired ? "Session expired" : "Connected"
        } catch {
            supabaseStatus = "Not connected"
        }
        refreshedAt = Date()
        copied = false
    }

    private var report: String {
        """
        FireVault Field Test Report
        Version: \(versionInfo.displayText)
        Workspace: \(demoMode ? "Demo" : "Production")
        Trip Log: \(tripStatus)
        Status: \(breadcrumbs.statusText)
        Accepted GPS: \(breadcrumbs.acceptedLocationCount)
        Rejected GPS: \(breadcrumbs.rejectedLocationCount)
        Route points: \(activeDay?.points.count ?? 0)
        Stops: \(activeDay?.stops.count ?? 0)
        Accuracy: \(accuracyText)
        Last save: \(breadcrumbs.lastSuccessfulSaveAt?.formatted(date: .abbreviated, time: .standard) ?? "None this session")
        Last recovery: \(breadcrumbs.lastRecoveryAt?.formatted(date: .abbreviated, time: .standard) ?? "None this session")
        Persistence error: \(breadcrumbs.lastPersistenceError ?? "None")
        Accounts: \(store.accounts.count) (\(store.mappedAccountCount) mapped)
        Storage: \(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
        Notifications: \(notificationAuthorization.label), \(pendingNotificationCount) pending
        Supabase: \(supabaseStatus)
        Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
        Thermal state: \(ProcessInfo.processInfo.thermalState.label)
        Battery: \(batteryText)
        Generated: \(Date().formatted(date: .abbreviated, time: .standard))
        """
    }

    nonisolated private static func applicationSupportSize() -> Int64 {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let enumerator = FileManager.default.enumerator(
                at: root.appendingPathComponent("FireVault", isDirectory: true),
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
              ) else { return 0 }
        return enumerator.compactMap { $0 as? URL }.reduce(0) { total, url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { return total }
            return total + Int64(values.fileSize ?? 0)
        }
    }
}

private extension TimeInterval {
    var fieldTestDuration: String {
        let seconds = max(0, Int(self.rounded()))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

private extension UNAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: "Not requested"
        case .denied: "Off"
        case .authorized: "Allowed"
        case .provisional: "Provisional"
        case .ephemeral: "Temporary"
        @unknown default: "Unknown"
        }
    }
}

private extension AVAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Off"
        case .authorized: "Allowed"
        @unknown default: "Unknown"
        }
    }
}

private extension PHAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Off"
        case .authorized: "Allowed"
        case .limited: "Limited"
        @unknown default: "Unknown"
        }
    }
}

private extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

private extension UIDevice.BatteryState {
    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .unplugged: "Unplugged"
        case .charging: "Charging"
        case .full: "Full"
        @unknown default: "Unknown"
        }
    }
}
#endif
