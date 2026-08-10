//
//  FireVaultTripLogActivityAttributes.swift
//  FireVault
//
//  Shared ActivityKit contract for the app and widget extension.
//

import ActivityKit
import Foundation

struct FireVaultTripLogActivityAttributes: ActivityAttributes {
    enum Status: String, Codable, Hashable {
        case recording
        case paused
        case complete

        var title: String {
            switch self {
            case .recording: "Recording"
            case .paused: "Paused"
            case .complete: "Complete"
            }
        }
    }

    struct ContentState: Codable, Hashable {
        var status: Status
        var updatedAt: Date
        var elapsedSeconds: TimeInterval
        var distanceMiles: Double
        var stopCount: Int

        var timerReferenceDate: Date {
            updatedAt.addingTimeInterval(-max(0, elapsedSeconds))
        }

        var formattedElapsedTime: String {
            let seconds = max(0, Int(elapsedSeconds.rounded()))
            return String(
                format: "%02d:%02d:%02d",
                seconds / 3_600,
                (seconds % 3_600) / 60,
                seconds % 60
            )
        }
    }

    var tripID: UUID
    var startedAt: Date
}
