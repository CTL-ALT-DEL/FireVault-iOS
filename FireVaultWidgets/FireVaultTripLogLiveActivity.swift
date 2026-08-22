//
//  FireVaultTripLogLiveActivity.swift
//  FireVaultWidgets
//


import ActivityKit
import AppIntents
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
                    VStack(spacing: 8) {
                        if context.state.isOnSite,
                           let activeStopStartedAt = context.state.activeStopStartedAt {
                            HStack {
                                Label(
                                    context.state.activeStopIsKnown ? "On Site" : "Stop Detected",
                                    systemImage: "mappin.circle.fill"
                                )
                                .font(.caption.bold())
                                .foregroundStyle(.cyan)
                                Spacer()
                                Text(activeStopStartedAt, style: .timer)
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(.white)
                            }
                        }
                        if context.state.showsMetrics {
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
                        } else {
                            Label("Mileage and stops hidden", systemImage: "eye.slash.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.white.opacity(0.58))
                        }
                        FireVaultTripLogActivityControls(
                            status: context.state.status,
                            compact: true
                        )
                    }
                }
            } compactLeading: {
                Image(systemName: displayStatusSymbol(context.state))
                    .foregroundStyle(displayStatusColor(context.state))
            } compactTrailing: {
                elapsed(context.state, compact: true)
                    .frame(maxWidth: 58)
            } minimal: {
                Image(systemName: displayStatusSymbol(context.state))
                    .foregroundStyle(displayStatusColor(context.state))
            }
            .widgetURL(URL(string: "firevault://triplog"))
            .keylineTint(displayStatusColor(context.state))
        }
        .supplementalActivityFamilies([.small])
    }

    private func liveStatus(
        _ state: FireVaultTripLogActivityAttributes.ContentState
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: state.isOnSite ? "mappin.circle.fill" : statusSymbol(state.status))
            Text(liveStatusTitle(state))
                .font(.caption.bold())
        }
        .foregroundStyle(state.isOnSite ? .cyan : statusColor(state.status))
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

    private func liveStatusTitle(
        _ state: FireVaultTripLogActivityAttributes.ContentState
    ) -> String {
        if state.isOnSite {
            return state.activeStopIsKnown ? "ON SITE" : "STOP DETECTED"
        }
        return state.status.title.uppercased()
    }

    private func displayStatusSymbol(
        _ state: FireVaultTripLogActivityAttributes.ContentState
    ) -> String {
        state.isOnSite ? "mappin.circle.fill" : statusSymbol(state.status)
    }

    private func displayStatusColor(
        _ state: FireVaultTripLogActivityAttributes.ContentState
    ) -> Color {
        state.isOnSite ? .cyan : statusColor(state.status)
    }
}

private struct FireVaultTripLogLockScreenView: View {
    @Environment(\.activityFamily) private var activityFamily
    let context: ActivityViewContext<FireVaultTripLogActivityAttributes>

    @ViewBuilder
    var body: some View {
        if activityFamily == .small {
            carPlayView
        } else {
            lockScreenView
        }
    }

    private var carPlayView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(statusTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            elapsed

            if context.state.showsMetrics {
                HStack(spacing: 10) {
                    Label(
                        String(format: "%.1f mi", context.state.distanceMiles),
                        systemImage: "road.lanes"
                    )
                    Label(
                        "\(context.state.stopCount) stops",
                        systemImage: "mappin.and.ellipse"
                    )
                }
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            }
        }
        .padding(4)
    }

    private var lockScreenView: some View {
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
                if context.state.showsMetrics {
                    if context.state.isOnSite,
                       let activeStopStartedAt = context.state.activeStopStartedAt {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(activeStopStartedAt, style: .timer)
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.white)
                            Text(context.state.activeStopIsKnown ? "ON SITE" : "STOPPED")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(.cyan)
                        }
                        .frame(minWidth: 70, alignment: .trailing)
                    }
                    lockMetric(
                        value: String(format: "%.1f", context.state.distanceMiles),
                        label: "MILES"
                    )
                    if !context.state.isOnSite {
                        lockMetric(value: "\(context.state.stopCount)", label: "STOPS")
                    }
                } else {
                    Label("Metrics hidden", systemImage: "eye.slash.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            FireVaultTripLogActivityControls(
                status: context.state.status,
                compact: false
            )
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
        Label(statusTitle, systemImage: statusSymbol)
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
                .foregroundStyle(activityFamily == .small ? Color.primary : Color.white)
        } else {
            Text(context.state.formattedElapsedTime)
                .monospacedDigit()
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(activityFamily == .small ? Color.primary : Color.white)
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
        if context.state.isOnSite { return "mappin.circle.fill" }
        return switch context.state.status {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .complete: "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        if context.state.isOnSite { return .cyan }
        return switch context.state.status {
        case .recording: .red
        case .paused: .orange
        case .complete: .green
        }
    }

    private var statusTitle: String {
        if context.state.isOnSite {
            return context.state.activeStopIsKnown ? "ON SITE" : "STOP DETECTED"
        }
        return context.state.status.title.uppercased()
    }
}

private struct FireVaultTripLogActivityControls: View {
    let status: FireVaultTripLogActivityAttributes.Status
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            if status == .recording {
                Button(intent: FireVaultPauseTripLogIntent()) {
                    controlLabel("Pause", symbol: "pause.fill", color: .orange)
                }
                .buttonStyle(.plain)
            } else if status == .paused {
                Button(intent: FireVaultResumeTripLogIntent()) {
                    controlLabel("Resume", symbol: "play.fill", color: .green)
                }
                .buttonStyle(.plain)
            }

            if status != .complete {
                Button(intent: FireVaultEndTripLogIntent()) {
                    controlLabel("End", symbol: "stop.fill", color: .red)
                }
                .buttonStyle(.plain)
            }

            Link(destination: URL(string: "firevault://triplog")!) {
                controlLabel("Open", symbol: "arrow.up.right", color: .blue)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func controlLabel(
        _ title: String,
        symbol: String,
        color: Color
    ) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, compact ? 9 : 11)
            .frame(height: compact ? 28 : 31)
            .background(color.opacity(0.82), in: Capsule())
    }
}
