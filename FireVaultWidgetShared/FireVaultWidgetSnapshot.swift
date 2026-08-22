//
//  FireVaultWidgetSnapshot.swift
//  FireVault
//
//  Privacy-conscious state shared by the app and its WidgetKit extension.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

enum FireVaultWidgetKind: String, CaseIterable {
    case dashboard = "FireVaultFieldWidget"
    case tripLog = "FireVaultTripLogWidget"
    case account = "FireVaultAccountWidget"
    case cloud = "FireVaultCloudStatusWidget"
}

struct FireVaultWidgetAccountSummary: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let accountID: String
    let category: String
    let address: String
    let dropPinCount: Int
}

struct FireVaultWidgetSnapshot: Codable, Equatable {
    enum TripState: String, Codable {
        case ready
        case recording
        case paused
        case complete

        var title: String {
            switch self {
            case .ready: "Ready"
            case .recording: "Recording"
            case .paused: "Paused"
            case .complete: "Stopped"
            }
        }
    }

    enum CloudState: String, Codable {
        case notSynced
        case syncing
        case upToDate
        case needsAttention

        var title: String {
            switch self {
            case .notSynced: "Not Synced"
            case .syncing: "Syncing"
            case .upToDate: "Up to Date"
            case .needsAttention: "Needs Attention"
            }
        }
    }

    enum GPSQuality: String, Codable {
        case unavailable
        case excellent
        case good
        case fair
        case poor

        var title: String {
            switch self {
            case .unavailable: "Waiting"
            case .excellent: "Excellent"
            case .good: "Good"
            case .fair: "Fair"
            case .poor: "Poor"
            }
        }
    }

    var updatedAt: Date
    var tripState: TripState
    var tripStartedAt: Date?
    var elapsedSeconds: TimeInterval
    var distanceMiles: Double
    var stopCount: Int
    var accountName: String?
    var accountID: String?
    var accountCategory: String?
    // Optional additions preserve decoding for widgets saved by older builds.
    // Account notes, phone numbers, documents, and exact coordinates are never
    // copied into the shared widget container.
    var accountRecordID: String? = nil
    var accountAddress: String? = nil
    var accountDropPinCount: Int? = nil
    var accountCount: Int? = nil
    var mappedAccountCount: Int? = nil
    var cloudState: CloudState? = nil
    var cloudLastSyncedAt: Date? = nil
    var pendingCloudAccountCount: Int? = nil
    var gpsQuality: GPSQuality? = nil
    var gpsAccuracyFeet: Double? = nil
    var gpsUpdatedAt: Date? = nil
    var accountChoices: [FireVaultWidgetAccountSummary]? = nil

    static let placeholder = FireVaultWidgetSnapshot(
        updatedAt: Date(),
        tripState: .ready,
        tripStartedAt: nil,
        elapsedSeconds: 0,
        distanceMiles: 0,
        stopCount: 0,
        accountName: "Mountain View Medical Center",
        accountID: "DEMO-1003",
        accountCategory: "Healthcare",
        accountRecordID: "demo-account-3",
        accountAddress: "100 Demo Avenue, Casper, WY",
        accountDropPinCount: 3,
        accountCount: 30,
        mappedAccountCount: 28,
        cloudState: .upToDate,
        cloudLastSyncedAt: Date().addingTimeInterval(-240),
        pendingCloudAccountCount: 0,
        gpsQuality: .excellent,
        gpsAccuracyFeet: 12,
        gpsUpdatedAt: Date(),
        accountChoices: [
            FireVaultWidgetAccountSummary(
                id: "demo-account-3",
                name: "Mountain View Medical Center",
                accountID: "DEMO-1003",
                category: "Healthcare",
                address: "100 Demo Avenue, Casper, WY",
                dropPinCount: 3
            )
        ]
    )

    static let empty = FireVaultWidgetSnapshot(
        updatedAt: Date(),
        tripState: .ready,
        tripStartedAt: nil,
        elapsedSeconds: 0,
        distanceMiles: 0,
        stopCount: 0,
        accountName: nil,
        accountID: nil,
        accountCategory: nil,
        accountCount: 0,
        mappedAccountCount: 0,
        cloudState: .notSynced,
        pendingCloudAccountCount: 0,
        gpsQuality: .unavailable
    )

    func elapsedTime(at date: Date) -> TimeInterval {
        guard tripState == .recording else {
            return max(0, elapsedSeconds)
        }
        // `elapsedSeconds` is already the complete elapsed value captured at
        // `updatedAt`. Advance from that snapshot boundary so a timeline
        // refresh never adds the full trip duration a second time.
        return max(0, elapsedSeconds + max(0, date.timeIntervalSince(updatedAt)))
    }
}

enum FireVaultWidgetSharedStore {
    nonisolated static let appGroup = "group.us.bannerman.firevault"
    private static let snapshotKey = "firevault.widget.snapshot.v1"

    static func load() -> FireVaultWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(FireVaultWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: FireVaultWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
#if canImport(WidgetKit)
        for kind in FireVaultWidgetKind.allCases {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
#endif
    }
}
