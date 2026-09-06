//
//  FireVaultUnifiedSync.swift
//  FireVault
//
//  One user-facing sync operation coordinating account records, metadata-only
//  Cloud Vault recovery points, and the existing field-media upload queue.
//

import Combine
import Foundation
import SwiftUI
import UIKit

enum FireVaultUnifiedSyncPhase: Equatable {
    case idle
    case accountRecords
    case fieldData
    case files

    var statusText: String {
        switch self {
        case .idle: "Ready"
        case .accountRecords: "Syncing account data"
        case .fieldData: "Protecting notes and field data"
        case .files: "Uploading photos and documents"
        }
    }
}

struct FireVaultUnifiedSyncStatus: Equatable {
    let hasSubscriptionAccess: Bool
    let isDemoMode: Bool
    let isSyncing: Bool
    let phase: FireVaultUnifiedSyncPhase
    let pendingAccountCount: Int
    let fieldDataNeedsSync: Bool
    let waitingFileCount: Int
    let failedFileCount: Int
    let conflictCount: Int
    let hasAccountError: Bool
    let fileBackupEnabled: Bool
    let lastCompletedAt: Date?

    var needsAction: Bool {
        guard !isDemoMode, hasSubscriptionAccess else { return false }
        return pendingAccountCount > 0
            || fieldDataNeedsSync
            || waitingFileCount > 0
            || failedFileCount > 0
            || conflictCount > 0
            || hasAccountError
    }

    var needsAttention: Bool {
        failedFileCount > 0 || conflictCount > 0 || hasAccountError
    }

    var title: String {
        if isDemoMode { return "Demo data stays on this iPhone" }
        if !hasSubscriptionAccess { return "Subscription Required" }
        if isSyncing { return phase.statusText }
        if needsAttention { return "Sync needs attention" }
        if needsAction { return "Changes are waiting to sync" }
        return "Everything is up to date"
    }

    var detail: String {
        if isDemoMode { return "Cloud sync is available outside Demo Mode." }
        if !hasSubscriptionAccess {
            return "Your records stay on this iPhone. Subscribe to sync data, files, photos, and documents."
        }
        if isSyncing { return "Accounts, notes, files, photos, and documents are handled together." }

        var parts: [String] = []
        if pendingAccountCount > 0 {
            parts.append("\(pendingAccountCount) account change\(pendingAccountCount == 1 ? "" : "s")")
        }
        if fieldDataNeedsSync { parts.append("notes and field data") }
        if waitingFileCount > 0 {
            parts.append("\(waitingFileCount) file\(waitingFileCount == 1 ? "" : "s")")
        }
        if failedFileCount > 0 {
            parts.append("\(failedFileCount) failed file\(failedFileCount == 1 ? "" : "s")")
        }
        if conflictCount > 0 {
            parts.append("\(conflictCount) conflict\(conflictCount == 1 ? "" : "s")")
        }
        if hasAccountError { parts.append("sync error") }

        if !parts.isEmpty { return parts.joined(separator: " • ") }
        if !fileBackupEnabled { return "Account and field data are current • File backup is off" }
        return "Accounts, notes, photos, and documents are protected. Videos stay local."
    }
}

@MainActor
final class FireVaultUnifiedSyncService: ObservableObject {
    static let shared = FireVaultUnifiedSyncService()

    @Published private(set) var isSyncing = false
    @Published private(set) var phase = FireVaultUnifiedSyncPhase.idle
    @Published private(set) var fieldDataNeedsSync = true
    @Published private(set) var lastCompletedAt: Date?
    @Published private(set) var errorMessage: String?

    private enum Key {
        static let fieldDataSHA256 = "firevault.unified-sync.field-data-sha256.v1"
        static let lastCompletedAt = "firevault.unified-sync.last-completed-at.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastCompletedAt = defaults.object(forKey: Key.lastCompletedAt) as? Date
    }

    func refreshPendingFieldData(_ payload: FireVaultCloudVaultPayload, isDemoMode: Bool) {
        guard !isDemoMode else {
            fieldDataNeedsSync = false
            return
        }
        guard let fingerprint = fingerprint(for: payload) else {
            fieldDataNeedsSync = true
            return
        }
        fieldDataNeedsSync = defaults.string(forKey: Key.fieldDataSHA256) != fingerprint
    }

    func acknowledgeFieldData(_ payload: FireVaultCloudVaultPayload) {
        guard let fingerprint = fingerprint(for: payload) else {
            fieldDataNeedsSync = true
            return
        }
        defaults.set(fingerprint, forKey: Key.fieldDataSHA256)
        fieldDataNeedsSync = false
    }

    func status(
        store: FireVaultStore,
        mediaBackup: FireVaultFieldMediaBackupService,
        hasSubscriptionAccess: Bool? = nil
    ) -> FireVaultUnifiedSyncStatus {
        let hasSubscriptionAccess = hasSubscriptionAccess
            ?? FireVaultSubscriptionStore.cachedRecordChangesAreAllowed()
        return .init(
            hasSubscriptionAccess: hasSubscriptionAccess,
            isDemoMode: store.demoMode,
            isSyncing: isSyncing || store.isCloudSyncing || mediaBackup.isProcessing,
            phase: resolvedPhase(store: store, mediaBackup: mediaBackup),
            pendingAccountCount: store.pendingCloudAccountCount,
            fieldDataNeedsSync: fieldDataNeedsSync,
            waitingFileCount: mediaBackup.waitingCount,
            failedFileCount: mediaBackup.failedCount,
            conflictCount: store.accountSyncConflicts.count,
            hasAccountError: store.cloudSyncErrorMessage != nil || errorMessage != nil,
            fileBackupEnabled: mediaBackup.isEnabled,
            lastCompletedAt: lastCompletedAt
        )
    }

    func syncNow(
        store: FireVaultStore,
        settings: FireVaultNativeSettingsStore,
        breadcrumbs: FireVaultBreadcrumbStore,
        mediaBackup: FireVaultFieldMediaBackupService
    ) async {
        guard !isSyncing, !store.demoMode, store.beginRecordChange() else { return }
        do {
            try FireVaultPaidFeatureAccess.requireCached(.cloudStorage)
        } catch {
            errorMessage = error.localizedDescription
            store.requestSubscriptionForPaidFeature()
            return
        }
        isSyncing = true
        errorMessage = nil
        var failures: [String] = []
        defer {
            phase = .idle
            isSyncing = false
        }

        phase = .accountRecords
        await store.syncAccountsNow()
        if let accountError = store.cloudSyncErrorMessage {
            failures.append(accountError)
        }

        phase = .fieldData
        let payload = FireVaultCloudVaultBackupCoordinator.payload(
            store: store,
            settings: settings,
            breadcrumbs: breadcrumbs
        )
        do {
            _ = try await FireVaultCloudVaultBackupService.createSnapshot(
                payload: payload,
                deviceLabel: UIDevice.current.name
            )
            acknowledgeFieldData(payload)
        } catch {
            failures.append(error.localizedDescription)
            refreshPendingFieldData(payload, isDemoMode: false)
        }

        phase = .files
        if mediaBackup.isEnabled {
            await store.enqueueExistingFieldMediaBackupsForUnifiedSync()
            await mediaBackup.processPending()
            if mediaBackup.failedCount > 0 {
                failures.append("\(mediaBackup.failedCount) file backup\(mediaBackup.failedCount == 1 ? "" : "s") need attention.")
            }
        }

        // If the technician changed anything while this pass was running,
        // leave the unified status pending instead of claiming full success.
        refreshPendingFieldData(
            FireVaultCloudVaultBackupCoordinator.payload(
                store: store,
                settings: settings,
                breadcrumbs: breadcrumbs
            ),
            isDemoMode: false
        )

        let remainingAccountCount = store.pendingCloudAccountCount
        if failures.isEmpty, remainingAccountCount > 0 {
            failures.append(
                "\(remainingAccountCount) account change\(remainingAccountCount == 1 ? "" : "s") could not be finalized. Your iPhone copies remain safe; tap Sync All to retry."
            )
        }

        if failures.isEmpty, remainingAccountCount == 0,
           !fieldDataNeedsSync, store.accountSyncConflicts.isEmpty,
           mediaBackup.waitingCount == 0, mediaBackup.failedCount == 0 {
            let completedAt = Date()
            lastCompletedAt = completedAt
            defaults.set(completedAt, forKey: Key.lastCompletedAt)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            errorMessage = failures.first
            if let failure = failures.first {
                FireVaultNotificationService.shared.unifiedSyncFailed(
                    detail: failure,
                    preferences: settings.preferences.notifications ?? FireVaultNotificationPreferences()
                )
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func resolvedPhase(
        store: FireVaultStore,
        mediaBackup: FireVaultFieldMediaBackupService
    ) -> FireVaultUnifiedSyncPhase {
        if phase != .idle { return phase }
        if store.isCloudSyncing { return .accountRecords }
        if mediaBackup.isProcessing { return .files }
        return .idle
    }

    private func fingerprint(for payload: FireVaultCloudVaultPayload) -> String? {
        (try? payload.encoded()).map(FireVaultCloudVaultBackupService.sha256)
    }
}

struct FireVaultUnifiedSyncCard: View {
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @ObservedObject var unifiedSync: FireVaultUnifiedSyncService
    @ObservedObject private var mediaBackup = FireVaultFieldMediaBackupService.shared
    @EnvironmentObject private var subscriptions: FireVaultSubscriptionStore

    private var status: FireVaultUnifiedSyncStatus {
        unifiedSync.status(
            store: store,
            mediaBackup: mediaBackup,
            hasSubscriptionAccess: subscriptions.access.grantsFullAccess
        )
    }

    private var tint: Color {
        if !status.hasSubscriptionAccess { return .secondary }
        if status.needsAttention { return .orange }
        if status.isSyncing || status.needsAction { return NativeShellPalette.blue }
        return NativeShellPalette.green
    }

    private var symbol: String {
        if !status.hasSubscriptionAccess { return "lock.fill" }
        if status.needsAttention { return "exclamationmark.arrow.triangle.2.circlepath" }
        if status.isSyncing { return "arrow.triangle.2.circlepath" }
        if status.needsAction { return "arrow.triangle.2.circlepath.circle.fill" }
        return "checkmark.icloud.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .symbolEffect(.rotate, options: .repeating, isActive: status.isSyncing)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Data & File Sync")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text(status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 4)

                Button {
                    if status.hasSubscriptionAccess {
                        Task {
                            await unifiedSync.syncNow(
                                store: store,
                                settings: settings,
                                breadcrumbs: breadcrumbs,
                                mediaBackup: mediaBackup
                            )
                        }
                    } else {
                        store.requestSubscriptionForPaidFeature()
                    }
                } label: {
                    if status.isSyncing {
                        ProgressView()
                            .frame(minWidth: 58)
                    } else {
                        Text(status.hasSubscriptionAccess ? "Sync All" : "View Plans")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(status.isSyncing || store.demoMode)
            }

            Text(status.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let lastCompletedAt = status.lastCompletedAt {
                    Label(
                        "Last sync \(lastCompletedAt.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "clock"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if !store.demoMode {
                    Label("Not synced yet", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if !store.accountSyncConflicts.isEmpty {
                    NavigationLink {
                        FireVaultAccountSyncConflictsView(store: store)
                    } label: {
                        Text("Review Conflicts")
                            .font(.caption2.bold())
                    }
                }
            }

            if let message = unifiedSync.errorMessage ?? store.cloudSyncErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("accounts-unified-sync")
    }
}

extension View {
    func fireVaultNavigationActionStyle() -> some View {
        font(.system(.subheadline, design: .rounded, weight: .bold))
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
    }
}
