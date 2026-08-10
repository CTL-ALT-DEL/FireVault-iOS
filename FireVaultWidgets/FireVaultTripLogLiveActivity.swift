//
//  FireVaultTripLogLiveActivity.swift
//  FireVaultWidgets
//


import ActivityKit
import SwiftUI
import WidgetKit

struct FireVaultTripLogLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FireVaultTripLogActivityAttributes.self) { context in
            FireVaultTripLogLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.035, green: 0.055, blue: 0.075))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "firevault://triplog"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    liveStatus(context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(context.state, compact: false)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("TRIP LOG")
                        .font(.caption.bold())
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.68))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        metric(
                            title: "MILES",
                            value: String(format: "%.1f", context.state.distanceMiles),
                            symbol: "road.lanes"
                        )
                        metric(
                            title: "STOPS",
                            value: "\(context.state.stopCount)",
                            symbol: "mappin.and.ellipse"
                        )
                    }
                }
            } compactLeading: {
                Image(systemName: statusSymbol(context.state.status))
                    .foregroundStyle(statusColor(context.state.status))
            } compactTrailing: {
                elapsed(context.state, compact: true)
                    .frame(maxWidth: 58)
            } minimal: {
                Image(systemName: statusSymbol(context.state.status))
                    .foregroundStyle(statusColor(context.state.status))
            }
            .widgetURL(URL(string: "firevault://triplog"))
            .keylineTint(statusColor(context.state.status))
        }
    }

    private func liveStatus(
        _ state: FireVaultTripLogActivityAttributes.ContentState
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: statusSymbol(state.status))
            Text(state.status.title.uppercased())
                .font(.caption.bold())
        }
        .foregroundStyle(statusColor(state.status))
    }

    @ViewBuilder
    private func elapsed(
        _ state: FireVaultTripLogActivityAttributes.ContentState,
        compact: Bool
    ) -> some View {
        if state.status == .recording {
            Text(state.timerReferenceDate, style: .timer)
                .monospacedDigit()
                .font(compact ? .caption2.bold() : .headline.bold())
                .foregroundStyle(.white)
        } else {
            Text(compact ? shortElapsed(state.elapsedSeconds) : state.formattedElapsedTime)
                .monospacedDigit()
                .font(compact ? .caption2.bold() : .headline.bold())
                .foregroundStyle(.white)
        }
    }

    private func metric(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Text(value)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
    }

    private func shortElapsed(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func statusSymbol(_ status: FireVaultTripLogActivityAttributes.Status) -> String {
        switch status {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .complete: "checkmark.circle.fill"
        }
    }

    private func statusColor(_ status: FireVaultTripLogActivityAttributes.Status) -> Color {
        switch status {
        case .recording: .red
        case .paused: .orange
        case .complete: .green
        }
    }
}

private struct FireVaultTripLogLockScreenView: View {
    let context: ActivityViewContext<FireVaultTripLogActivityAttributes>

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 10) {
                brand
                Spacer()
                statusCapsule
            }

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ELAPSED")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.52))
                    elapsed
                }
                Spacer()
                lockMetric(
                    value: String(format: "%.1f", context.state.distanceMiles),
                    label: "MILES"
                )
                lockMetric(value: "\(context.state.stopCount)", label: "STOPS")
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
    }

    private var brand: some View {
        HStack(spacing: 0) {
            Text("FIRE").foregroundStyle(.red)
            Text("VAULT").foregroundStyle(.white)
            Text("  PRO")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
        }
        .font(.system(size: 14, weight: .black, design: .rounded))
        .tracking(1.0)
    }

    private var statusCapsule: some View {
        Label(context.state.status.title.uppercased(), systemImage: statusSymbol)
            .font(.caption2.bold())
            .foregroundStyle(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private var elapsed: some View {
        if context.state.status == .recording {
            Text(context.state.timerReferenceDate, style: .timer)
                .monospacedDigit()
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        } else {
            Text(context.state.formattedElapsedTime)
                .monospacedDigit()
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func lockMetric(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(minWidth: 55, alignment: .trailing)
    }

    private var statusSymbol: String {
        switch context.state.status {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .complete: "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch context.state.status {
        case .recording: .red
        case .paused: .orange
        case .complete: .green
        }
    }
}
