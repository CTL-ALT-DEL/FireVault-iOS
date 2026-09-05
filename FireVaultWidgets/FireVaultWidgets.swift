//
//  FireVaultWidgets.swift
//  FireVaultWidgets
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct FireVaultWidgetBundle: WidgetBundle {
    var body: some Widget {
        FireVaultFieldWidget()
        FireVaultTripLogWidget()
        FireVaultAccountWidget()
        FireVaultCloudStatusWidget()
        FireVaultTripLogLiveActivity()
    }
}

struct FireVaultFieldWidget: Widget {
    let kind = FireVaultWidgetKind.dashboard.rawValue

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireVaultWidgetProvider()) { entry in
            FireVaultFieldDashboardView(entry: entry)
        }
        .configurationDisplayName("FireVault Overview")
        .description("Your trip, current account, and most-used actions at a glance.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .containerBackgroundRemovable(true)
    }
}

struct FireVaultWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FireVaultWidgetSnapshot
}

struct FireVaultWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FireVaultWidgetEntry {
        .init(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FireVaultWidgetEntry) -> Void) {
        completion(.init(
            date: Date(),
            snapshot: context.isPreview ? .placeholder : FireVaultWidgetSharedStore.load()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FireVaultWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = FireVaultWidgetSharedStore.load()
        let dates: [Date]
        if snapshot.tripState == .recording {
            dates = (0...12).compactMap {
                Calendar.current.date(byAdding: .minute, value: $0 * 5, to: now)
            }
        } else {
            dates = [now]
        }
        let entries = dates.map { FireVaultWidgetEntry(date: $0, snapshot: snapshot) }
        let refresh = Calendar.current.date(
            byAdding: .minute,
            value: snapshot.tripState == .recording ? 15 : 60,
            to: now
        ) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

private struct FireVaultFieldDashboardView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FireVaultWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label(
                    "\(stateTitle) • \(milesText) • \(entry.snapshot.stopCount) stops",
                    systemImage: stateSymbol
                )
            case .accessoryCircular:
                AccessoryWidgetBackground()
                    .overlay {
                        VStack(spacing: 1) {
                            Image(systemName: stateSymbol)
                                .font(.headline)
                            Text(entry.snapshot.tripState == .recording ? shortDuration : stateTitle)
                                .font(.caption2.bold())
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.68)
                        }
                    }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: stateSymbol)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FireVault • \(stateTitle)")
                            .font(.headline)
                        Text("\(milesText) • \(durationText) • \(entry.snapshot.stopCount) stops")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            case .systemSmall:
                small
            case .systemMedium:
                medium
            default:
                large
            }
        }
        .widgetURL(URL(string: dashboardDestination))
        .containerBackground(for: .widget) { FireVaultWidgetBackground() }
    }

    private var small: some View {
        Group {
            switch entry.snapshot.tripState {
            case .recording, .paused:
                activeSmall
            case .ready, .complete:
                idleSmall
            }
        }
    }

    private var idleSmall: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("TRIP LOG", systemImage: "truck.box.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FireVaultWidgetDesign.navy)
                    .widgetAccentable()
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("Start Trip")
                .font(.system(size: 31, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("Track mileage, route, and stops")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Divider()
            Text(idleSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var activeSmall: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(entry.snapshot.tripState == .recording ? "RECORDING" : "PAUSED", systemImage: stateSymbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                    .widgetAccentable()
                Spacer()
                Text("TRIP LOG")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(durationText)
                .font(.system(size: 29, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            HStack(spacing: 6) {
                Text(smallMilesText)
                Spacer(minLength: 2)
                Text(smallStopsText)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            smallTripControl
        }
    }

    @ViewBuilder
    private var smallTripControl: some View {
        switch entry.snapshot.tripState {
        case .recording:
            Button(intent: FireVaultPauseTripLogIntent()) {
                FireVaultWidgetActionLabel(
                    title: "Pause",
                    symbol: "pause.fill",
                    color: FireVaultWidgetDesign.amber,
                    compact: true
                )
            }
            .buttonStyle(.plain)
        case .paused:
            Button(intent: FireVaultResumeTripLogIntent()) {
                FireVaultWidgetActionLabel(
                    title: "Resume",
                    symbol: "play.fill",
                    color: FireVaultWidgetDesign.green,
                    compact: true
                )
            }
            .buttonStyle(.plain)
        case .ready, .complete:
            EmptyView()
        }
    }

    private var medium: some View {
        VStack(spacing: 9) {
            HStack {
                FireVaultWidgetStatusPill(title: stateTitle, symbol: stateSymbol, color: stateColor)
                Spacer(minLength: 4)
                Text("Updated \(entry.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tripHeadline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(primaryHeadline)
                        .font(.title2.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                FireVaultWidgetMetric(
                    value: milesText,
                    title: "Miles",
                    symbol: "road.lanes",
                    compact: true,
                    showsSymbol: false
                )
                .frame(width: 55)
                FireVaultWidgetMetric(
                    value: "\(entry.snapshot.stopCount)",
                    title: "Stops",
                    symbol: "mappin.and.ellipse",
                    compact: true,
                    showsSymbol: false
                )
                .frame(width: 48)
            }

            FireVaultWidgetAccountRow(name: accountName, detail: accountDetail)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FireVaultWidgetStatusPill(title: stateTitle, symbol: stateSymbol, color: stateColor)
                Spacer()
                Text("Updated \(entry.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tripHeadline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(primaryHeadline)
                        .font(.system(size: 35, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 10)
            }

            HStack(spacing: 10) {
                FireVaultWidgetMetric(value: milesText, title: "Miles", symbol: "road.lanes")
                FireVaultWidgetMetric(value: durationText, title: "Elapsed", symbol: "timer")
                FireVaultWidgetMetric(
                    value: "\(entry.snapshot.stopCount)",
                    title: "Stops",
                    symbol: "mappin.and.ellipse"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT ACCOUNT")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                FireVaultWidgetAccountRow(name: accountName, detail: accountDetail)
            }

            Spacer(minLength: 0)

            HStack(spacing: 9) {
                Link(destination: URL(string: dashboardDestination)!) {
                    FireVaultWidgetActionLabel(
                        title: tripActionTitle,
                        symbol: tripActionSymbol,
                        color: stateColor,
                        compact: true
                    )
                }
                Link(destination: URL(string: "firevault://accounts")!) {
                    FireVaultWidgetActionLabel(title: "Accounts", symbol: "building.2.fill", compact: true)
                }
                Link(destination: URL(string: "firevault://photo")!) {
                    FireVaultWidgetActionLabel(title: "Camera", symbol: "camera.fill", compact: true)
                }
            }
        }
    }

    private var accountName: String {
        entry.snapshot.accountName ?? "No account selected"
    }

    private var accountDetail: String {
        let values = [entry.snapshot.accountID, entry.snapshot.accountAddress]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return values.isEmpty ? "Open Accounts to choose a field location" : values.joined(separator: " • ")
    }

    private var tripHeadline: String {
        switch entry.snapshot.tripState {
        case .recording: "ACTIVE TRIP"
        case .paused: "TRIP PAUSED"
        case .complete: "LAST TRIP SAVED"
        case .ready: "TRIP LOG"
        }
    }

    private var primaryHeadline: String {
        switch entry.snapshot.tripState {
        case .recording, .paused: durationText
        case .ready, .complete: "Start Trip Log"
        }
    }

    private var idleSummary: String {
        guard entry.snapshot.tripState == .complete else {
            return entry.snapshot.accountName ?? "Open FireVault to begin"
        }
        return "Last trip  •  \(smallMilesText)  •  \(smallStopsText)"
    }

    private var smallMilesText: String {
        if entry.snapshot.tripState == .ready {
            return "0.0 MILES"
        }
        return "\(entry.snapshot.distanceMiles.formatted(.number.precision(.fractionLength(1)))) MILES"
    }

    private var smallStopsText: String {
        let count = entry.snapshot.stopCount
        return "\(count) STOP\(count == 1 ? "" : "S")"
    }

    private var stateTitle: String { entry.snapshot.tripState.title }

    private var stateSymbol: String {
        switch entry.snapshot.tripState {
        case .recording: "location.fill"
        case .paused: "pause.fill"
        case .complete: "checkmark.circle.fill"
        case .ready: "location"
        }
    }

    private var stateColor: Color {
        switch entry.snapshot.tripState {
        case .recording: FireVaultWidgetDesign.green
        case .paused: FireVaultWidgetDesign.amber
        case .complete, .ready: FireVaultWidgetDesign.navy
        }
    }

    private var tripActionTitle: String {
        switch entry.snapshot.tripState {
        case .recording: "Trip Log"
        case .paused: "Resume Trip"
        case .complete, .ready: "Start Trip"
        }
    }

    private var tripActionSymbol: String {
        switch entry.snapshot.tripState {
        case .recording: "arrow.right.circle.fill"
        case .paused: "play.fill"
        case .complete, .ready: "record.circle"
        }
    }

    private var dashboardDestination: String {
        switch entry.snapshot.tripState {
        case .ready, .complete: "firevault://triplog/start"
        case .recording, .paused: "firevault://triplog"
        }
    }

    private var milesText: String {
        entry.snapshot.distanceMiles.formatted(.number.precision(.fractionLength(1))) + " mi"
    }

    private var durationText: String {
        let seconds = Int(entry.snapshot.elapsedTime(at: entry.date))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private var shortDuration: String {
        let seconds = Int(entry.snapshot.elapsedTime(at: entry.date))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview("Dashboard Small", as: .systemSmall) {
    FireVaultFieldWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}

#Preview("Dashboard Medium", as: .systemMedium) {
    FireVaultFieldWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}

#Preview("Dashboard Large", as: .systemLarge) {
    FireVaultFieldWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}
