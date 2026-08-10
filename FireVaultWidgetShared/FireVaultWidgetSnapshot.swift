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

    var updatedAt: Date
    var tripState: TripState
    var tripStartedAt: Date?
    var elapsedSeconds: TimeInterval
    var distanceMiles: Double
    var stopCount: Int
    var accountName: String?
    var accountID: String?
    var accountCategory: String?

    static let placeholder = FireVaultWidgetSnapshot(
        updatedAt: Date(),
        tripState: .ready,
        tripStartedAt: nil,
        elapsedSeconds: 0,
        distanceMiles: 0,
        stopCount: 0,
        accountName: "Mountain View Medical Center",
        accountID: "DEMO-1003",
        accountCategory: "Healthcare"
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
        accountCategory: nil
    )

    func elapsedTime(at date: Date) -> TimeInterval {
        guard tripState == .recording, let tripStartedAt else {
            return max(0, elapsedSeconds)
        }
        return max(elapsedSeconds, date.timeIntervalSince(tripStartedAt))
    }
}

enum FireVaultWidgetSharedStore {
    static let appGroup = "group.us.bannerman.firevault"
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
        WidgetCenter.shared.reloadTimelines(ofKind: "FireVaultFieldWidget")
#endif
    }
}
