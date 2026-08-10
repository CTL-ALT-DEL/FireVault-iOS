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
        var showsMetrics: Bool

        init(
            status: Status,
            updatedAt: Date,
            elapsedSeconds: TimeInterval,
            distanceMiles: Double,
            stopCount: Int,
            showsMetrics: Bool
        ) {
            self.status = status
            self.updatedAt = updatedAt
            self.elapsedSeconds = elapsedSeconds
            self.distanceMiles = distanceMiles
            self.stopCount = stopCount
            self.showsMetrics = showsMetrics
        }

        private enum CodingKeys: String, CodingKey {
            case status, updatedAt, elapsedSeconds, distanceMiles, stopCount, showsMetrics
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            status = try values.decode(Status.self, forKey: .status)
            updatedAt = try values.decode(Date.self, forKey: .updatedAt)
            elapsedSeconds = try values.decode(TimeInterval.self, forKey: .elapsedSeconds)
            distanceMiles = try values.decode(Double.self, forKey: .distanceMiles)
            stopCount = try values.decode(Int.self, forKey: .stopCount)
            showsMetrics = try values.decodeIfPresent(Bool.self, forKey: .showsMetrics) ?? true
        }

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
