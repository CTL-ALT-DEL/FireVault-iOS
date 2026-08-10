//
//  FireVaultWidgets.swift
//  FireVaultWidgets
//

import SwiftUI
import WidgetKit

@main
struct FireVaultWidgetBundle: WidgetBundle {
    var body: some Widget {
        FireVaultFieldWidget()
    }
}

struct FireVaultFieldWidget: Widget {
    let kind = "FireVaultFieldWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FireVaultWidgetProvider()) { entry in
            FireVaultWidgetView(entry: entry)
        }
        .configurationDisplayName("FireVault Field Dashboard")
        .description("See Trip Log status and return quickly to your field workspace.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
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
        completion(.init(date: Date(), snapshot: context.isPreview ? .placeholder : FireVaultWidgetSharedStore.load()))
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
        let refresh = Calendar.current.date(byAdding: .minute, value: snapshot.tripState == .recording ? 15 : 60, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

private struct FireVaultWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FireVaultWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                accessoryInline
            case .accessoryCircular:
                accessoryCircular
            case .accessoryRectangular:
                accessoryRectangular
            case .systemSmall:
                smallWidget
            case .systemMedium:
                mediumWidget
            default:
                largeWidget
            }
        }
        .widgetURL(URL(string: "firevault://triplog"))
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.055, blue: 0.075), Color(red: 0.055, green: 0.13, blue: 0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 9) {
            brand
            statusRow
            Spacer(minLength: 0)
            Text(durationText)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
            HStack(spacing: 8) {
                Label(milesText, systemImage: "road.lanes")
                Label("\(entry.snapshot.stopCount)", systemImage: "mappin.and.ellipse")
            }
            .font(.caption2.bold())
            .foregroundStyle(.white.opacity(0.76))
        }
        .padding(3)
    }

    private var mediumWidget: some View {
        VStack(spacing: 10) {
            HStack {
                brand
                Spacer()
                statusCapsule
            }
            HStack(spacing: 8) {
                metric(title: "MILES", value: milesText, symbol: "road.lanes")
                metric(title: "TIME", value: durationText, symbol: "timer")
                metric(title: "STOPS", value: "\(entry.snapshot.stopCount)", symbol: "mappin.and.ellipse")
            }
            accountStrip
            HStack(spacing: 12) {
                widgetLink("Accounts", symbol: "building.2.fill", destination: "firevault://accounts")
                widgetLink("Photo", symbol: "camera.fill", destination: "firevault://photo")
                widgetLink(tripActionTitle, symbol: "truck.box.fill", destination: tripActionDestination)
            }
        }
        .padding(2)
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                brand
                Spacer()
                statusCapsule
            }
            Text("FIELD DASHBOARD")
                .font(.caption.bold())
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.56))
            HStack(spacing: 10) {
                metric(title: "MILES", value: milesText, symbol: "road.lanes")
                metric(title: "ELAPSED", value: durationText, symbol: "timer")
                metric(title: "STOPS", value: "\(entry.snapshot.stopCount)", symbol: "mappin.and.ellipse")
            }
            accountStrip
            VStack(spacing: 9) {
                widgetLink("Open Trip Log", symbol: "truck.box.fill", destination: "firevault://triplog")
                widgetLink("Open Accounts", symbol: "building.2.fill", destination: "firevault://accounts")
                widgetLink("Capture Field Photo", symbol: "camera.fill", destination: "firevault://photo")
            }
            Spacer(minLength: 0)
            Text("Updated \(entry.snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(4)
    }

    private var accessoryInline: some View {
        Label("Trip Log \(entry.snapshot.tripState.title) • \(milesText) • \(entry.snapshot.stopCount) stops", systemImage: statusSymbol)
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: statusSymbol)
                    .font(.headline)
                Text(entry.snapshot.tripState == .recording ? durationShortText : entry.snapshot.tripState.title.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
            }
        }
    }

    private var accessoryRectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Trip Log • \(entry.snapshot.tripState.title)")
                    .font(.headline)
                Text("\(milesText)  •  \(durationText)  •  \(entry.snapshot.stopCount) stops")
                    .font(.caption)
                    .monospacedDigit()
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 0) {
            Text("FIRE")
                .foregroundStyle(Color(red: 0.94, green: 0.12, blue: 0.14))
            Text("VAULT")
                .foregroundStyle(.white)
            Text("  PRO")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
        }
        .font(.system(size: 13, weight: .black, design: .rounded))
        .tracking(1.0)
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text("TRIP LOG")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.62))
            Text(entry.snapshot.tripState.title.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
    }

    private var statusCapsule: some View {
        Label(entry.snapshot.tripState.title.uppercased(), systemImage: statusSymbol)
            .font(.caption2.bold())
            .foregroundStyle(statusColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.14), in: Capsule())
    }

    private func metric(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var accountStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2.fill")
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.snapshot.accountName ?? "Open FireVault Accounts")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .privacySensitive()
                Text(accountDetail)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
                    .privacySensitive()
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func widgetLink(_ title: String, symbol: String, destination: String) -> some View {
        Link(destination: URL(string: destination)!) {
            Label(title, systemImage: symbol)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var accountDetail: String {
        let detail = [entry.snapshot.accountID, entry.snapshot.accountCategory]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " • ")
        return detail.isEmpty ? "Account workspace" : detail
    }

    private var tripActionTitle: String {
        switch entry.snapshot.tripState {
        case .recording: "Trip Log"
        case .paused: "Resume"
        case .ready, .complete: "Start"
        }
    }

    private var tripActionDestination: String {
        entry.snapshot.tripState == .recording
            ? "firevault://triplog"
            : "firevault://triplog/start"
    }

    private var statusSymbol: String {
        switch entry.snapshot.tripState {
        case .recording: "location.fill"
        case .paused: "pause.fill"
        case .complete: "stop.fill"
        case .ready: "location"
        }
    }

    private var statusColor: Color {
        switch entry.snapshot.tripState {
        case .recording: .green
        case .paused: .orange
        case .complete: .red
        case .ready: .cyan
        }
    }

    private var milesText: String {
        entry.snapshot.distanceMiles.formatted(.number.precision(.fractionLength(1))) + " mi"
    }

    private var durationText: String {
        let seconds = Int(entry.snapshot.elapsedTime(at: entry.date))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private var durationShortText: String {
        let seconds = Int(entry.snapshot.elapsedTime(at: entry.date))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview(as: .systemMedium) {
    FireVaultFieldWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}
