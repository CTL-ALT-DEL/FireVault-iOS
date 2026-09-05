//
//  FireVaultTripLogLiveActivity.swift
//  FireVault
//
//  Keeps the Lock Screen and Dynamic Island synchronized with Trip Log.
//

import ActivityKit
import CoreLocation
import Foundation

@MainActor
enum FireVaultTripLogLiveActivityController {
    typealias Attributes = FireVaultTripLogActivityAttributes

    static func synchronize(
        day: FireVaultBreadcrumbDay,
        status: Attributes.Status,
        showsMetrics: Bool,
        liveLocation: CLLocation? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = activityContent(
            for: day,
            status: status,
            showsMetrics: showsMetrics,
            liveLocation: liveLocation
        )
        let attributes = Attributes(tripID: day.id, startedAt: day.startedAt)

        Task {
            if let current = Activity<Attributes>.activities.first(where: {
                $0.attributes.tripID == day.id
            }) {
                await current.update(content)
                return
            }

            for staleActivity in Activity<Attributes>.activities {
                await staleActivity.end(nil, dismissalPolicy: .immediate)
            }

            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                // Trip Log recording must continue even if the system declines
                // a Live Activity request.
            }
        }
    }

    static func end(day: FireVaultBreadcrumbDay, showsMetrics: Bool) {
        let content = activityContent(
            for: day,
            status: .complete,
            showsMetrics: showsMetrics,
            liveLocation: nil
        )
        Task {
            for activity in Activity<Attributes>.activities where activity.attributes.tripID == day.id {
                await activity.end(
                    content,
                    dismissalPolicy: .after(Date().addingTimeInterval(15 * 60))
                )
            }
        }
    }

    static func dismissAll() {
        Task {
            for activity in Activity<Attributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func activityContent(
        for day: FireVaultBreadcrumbDay,
        status: Attributes.Status,
        showsMetrics: Bool,
        liveLocation: CLLocation?
    ) -> ActivityContent<Attributes.ContentState> {
        let activeStop = status == .recording
            ? day.stops.last(where: { $0.departure == nil })
            : nil
        return ActivityContent(
            state: Attributes.ContentState(
                status: status,
                updatedAt: Date(),
                elapsedSeconds: day.elapsedTime,
                distanceMiles: FireVaultLiveLocationPresentation.displayedDistanceMeters(
                    for: day,
                    liveLocation: liveLocation
                ) / 1_609.344,
                stopCount: day.stops.count,
                showsMetrics: showsMetrics,
                activeStopStartedAt: activeStop?.arrival,
                activeStopIsKnown: activeStop?.accountID != nil,
                activeAccountName: activeStop?.accountName
            ),
            staleDate: Date().addingTimeInterval(status == .recording ? 10 * 60 : 60 * 60)
        )
    }
}
