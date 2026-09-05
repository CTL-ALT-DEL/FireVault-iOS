//
//  FireVaultWidgetPortfolio.swift
//  FireVaultWidgets
//
//  Focused, state-aware widgets for Trip Log, account access, and cloud health.
//

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

struct FireVaultTripLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: FireVaultWidgetKind.tripLog.rawValue,
            provider: FireVaultWidgetProvider()
        ) { entry in
            FireVaultTripLogWidgetView(entry: entry)
        }
        .configurationDisplayName("FireVault Trip Log")
        .description("Control your active trip and see elapsed time, mileage, stops, and GPS quality.")
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

struct FireVaultAccountWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: FireVaultWidgetKind.account.rawValue,
            intent: FireVaultAccountWidgetConfigurationIntent.self,
            provider: FireVaultAccountWidgetProvider()
        ) { entry in
            FireVaultAccountWidgetView(entry: entry)
        }
        .configurationDisplayName("FireVault Account")
        .description("Open a selected account and see its address and saved arrival locations.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(true)
    }
}

private struct FireVaultAccountWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: FireVaultWidgetSnapshot
    let account: FireVaultWidgetAccountSummary?
}

private struct FireVaultAccountWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FireVaultAccountWidgetEntry {
        makeEntry(snapshot: .placeholder, configuredAccount: nil, date: Date())
    }

    func snapshot(
        for configuration: FireVaultAccountWidgetConfigurationIntent,
        in context: Context
    ) async -> FireVaultAccountWidgetEntry {
        makeEntry(
            snapshot: context.isPreview ? .placeholder : FireVaultWidgetSharedStore.load(),
            configuredAccount: configuration.account?.summary,
            date: Date()
        )
    }

    func timeline(
        for configuration: FireVaultAccountWidgetConfigurationIntent,
        in context: Context
    ) async -> Timeline<FireVaultAccountWidgetEntry> {
        let now = Date()
        let snapshot = FireVaultWidgetSharedStore.load()
        let entry = makeEntry(
            snapshot: snapshot,
            configuredAccount: configuration.account?.summary,
            date: now
        )
        let refresh = Calendar.current.date(byAdding: .minute, value: 60, to: now)
            ?? now.addingTimeInterval(3_600)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func makeEntry(
        snapshot: FireVaultWidgetSnapshot,
        configuredAccount: FireVaultWidgetAccountSummary?,
        date: Date
    ) -> FireVaultAccountWidgetEntry {
        let account = configuredAccount
            ?? snapshot.accountRecordID.flatMap { recordID in
                snapshot.accountChoices?.first(where: { $0.id == recordID })
            }
            ?? snapshot.accountChoices?.first
        return FireVaultAccountWidgetEntry(date: date, snapshot: snapshot, account: account)
    }
}

struct FireVaultCloudStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: FireVaultWidgetKind.cloud.rawValue,
            provider: FireVaultWidgetProvider()
        ) { entry in
            FireVaultCloudStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("FireVault Cloud Status")
        .description("See whether your field records are synced and need attention.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
        .containerBackgroundRemovable(true)
    }
}

// MARK: - Trip Log

private struct FireVaultTripLogWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FireVaultWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Trip Log \(stateTitle) • \(milesText)", systemImage: stateSymbol)
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
                        Text("Trip Log • \(stateTitle)")
                            .font(.headline)
                        Text("\(durationText) • \(milesText) • \(entry.snapshot.stopCount) stops")
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
        .widgetURL(URL(string: tripURL))
        .containerBackground(for: .widget) { FireVaultWidgetBackground() }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            FireVaultWidgetBrand(section: "Trip Log")
            FireVaultWidgetStatusPill(title: stateTitle, symbol: stateSymbol, color: stateColor)
            Spacer(minLength: 0)
            Text(durationText)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            HStack(spacing: 12) {
                Label(milesText, systemImage: "road.lanes")
                Label("\(entry.snapshot.stopCount)", systemImage: "mappin.and.ellipse")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            compactControl
        }
    }

    private var medium: some View {
        VStack(spacing: 9) {
            HStack {
                FireVaultWidgetBrand(section: "Trip Log")
                Spacer(minLength: 4)
                FireVaultWidgetStatusPill(title: stateTitle, symbol: stateSymbol, color: stateColor)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("ELAPSED")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(durationText)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                FireVaultWidgetMetric(value: milesText, title: "Miles", symbol: "road.lanes", compact: true)
                FireVaultWidgetMetric(
                    value: "\(entry.snapshot.stopCount)",
                    title: "Stops",
                    symbol: "mappin.and.ellipse",
                    compact: true
                )
                FireVaultWidgetMetric(
                    value: gpsText,
                    title: "GPS",
                    symbol: "scope",
                    color: gpsColor,
                    compact: true
                )
            }

            HStack(spacing: 9) {
                Label(accountName, systemImage: "building.2.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
                Spacer(minLength: 2)
                compactControl
                    .frame(maxWidth: 126)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FireVaultWidgetBrand(section: "Trip Log")
                Spacer()
                FireVaultWidgetStatusPill(title: stateTitle, symbol: stateSymbol, color: stateColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("ELAPSED TIME")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(durationText)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            HStack(spacing: 10) {
                FireVaultWidgetMetric(value: milesText, title: "Miles", symbol: "road.lanes")
                FireVaultWidgetMetric(
                    value: "\(entry.snapshot.stopCount)",
                    title: "Stops",
                    symbol: "mappin.and.ellipse"
                )
                FireVaultWidgetMetric(value: gpsText, title: "GPS", symbol: "scope", color: gpsColor)
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
                primaryControl
                Link(destination: URL(string: "firevault://triplog")!) {
                    FireVaultWidgetActionLabel(title: "Open Trip Log", symbol: "arrow.up.forward.app.fill")
                }
            }
        }
    }

    @ViewBuilder
    private var compactControl: some View {
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
            Link(destination: URL(string: "firevault://triplog/start")!) {
                FireVaultWidgetActionLabel(
                    title: "Start",
                    symbol: "record.circle",
                    color: FireVaultWidgetDesign.red,
                    compact: true
                )
            }
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        switch entry.snapshot.tripState {
        case .recording:
            Button(intent: FireVaultPauseTripLogIntent()) {
                FireVaultWidgetActionLabel(
                    title: "Pause Trip",
                    symbol: "pause.fill",
                    color: FireVaultWidgetDesign.amber
                )
            }
            .buttonStyle(.plain)
        case .paused:
            Button(intent: FireVaultResumeTripLogIntent()) {
                FireVaultWidgetActionLabel(
                    title: "Resume Trip",
                    symbol: "play.fill",
                    color: FireVaultWidgetDesign.green
                )
            }
            .buttonStyle(.plain)
        case .ready, .complete:
            Link(destination: URL(string: "firevault://triplog/start")!) {
                FireVaultWidgetActionLabel(
                    title: "Start Trip",
                    symbol: "record.circle",
                    color: FireVaultWidgetDesign.red
                )
            }
        }
    }

    private var accountName: String {
        entry.snapshot.accountName ?? "No active account"
    }

    private var accountDetail: String {
        let values = [entry.snapshot.accountID, entry.snapshot.accountAddress]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return values.isEmpty ? "Open FireVault to select an account" : values.joined(separator: " • ")
    }

    private var durationText: String {
        let seconds = Int(entry.snapshot.elapsedTime(at: entry.date))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private var shortDuration: String {
        let seconds = Int(entry.snapshot.elapsedTime(at: entry.date))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var milesText: String {
        entry.snapshot.distanceMiles.formatted(.number.precision(.fractionLength(1))) + " mi"
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

    private var tripURL: String {
        switch entry.snapshot.tripState {
        case .ready, .complete: "firevault://triplog/start"
        case .recording, .paused: "firevault://triplog"
        }
    }

    private var gpsText: String {
        guard let updatedAt = entry.snapshot.gpsUpdatedAt,
              entry.date.timeIntervalSince(updatedAt) < 300,
              let quality = entry.snapshot.gpsQuality else { return "Waiting" }
        return quality.title
    }

    private var gpsColor: Color {
        switch entry.snapshot.gpsQuality {
        case .excellent, .good: FireVaultWidgetDesign.green
        case .fair: FireVaultWidgetDesign.amber
        case .poor: FireVaultWidgetDesign.red
        case .unavailable, .none: .gray
        }
    }
}

// MARK: - Field Account

private struct FireVaultAccountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FireVaultAccountWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
        .widgetURL(accountURL)
        .containerBackground(for: .widget) { FireVaultWidgetBackground() }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            FireVaultWidgetBrand(section: "Account")
            Spacer(minLength: 0)
            Image(systemName: "building.2.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(FireVaultWidgetDesign.navy)
                .widgetAccentable()
            Text(accountName)
                .font(.headline.bold())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .privacySensitive()
            Text(accountAddress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .privacySensitive()
            Label(locationText, systemImage: "mappin.and.ellipse")
                .font(.caption.bold())
                .foregroundStyle(FireVaultWidgetDesign.navy)
                .widgetAccentable()
        }
    }

    private var medium: some View {
        VStack(spacing: 9) {
            HStack {
                FireVaultWidgetBrand(section: "Account")
                Spacer()
                Label(locationText, systemImage: "mappin.and.ellipse")
                    .font(.caption.bold())
                    .foregroundStyle(FireVaultWidgetDesign.navy)
                    .widgetAccentable()
            }

            HStack(spacing: 12) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(FireVaultWidgetDesign.navy)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountName)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .privacySensitive()
                    Text(accountAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .privacySensitive()
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                FireVaultWidgetMetric(value: accountNumber, title: "Account", symbol: "number", compact: true)
                FireVaultWidgetMetric(
                    value: "\(dropPinCount)",
                    title: "Locations",
                    symbol: "mappin.and.ellipse",
                    compact: true
                )
                FireVaultWidgetActionLabel(title: "Open", symbol: "arrow.right", compact: true)
                    .frame(maxWidth: 100)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FireVaultWidgetBrand(section: "Account")
                Spacer()
                FireVaultWidgetStatusPill(
                    title: dropPinCount > 0 ? "Locations Saved" : "Add Locations",
                    symbol: dropPinCount > 0 ? "checkmark.circle.fill" : "mappin.slash",
                    color: dropPinCount > 0 ? FireVaultWidgetDesign.green : FireVaultWidgetDesign.amber
                )
            }

            Text(accountName)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .privacySensitive()
            Text(accountAddress)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .privacySensitive()

            HStack(spacing: 10) {
                FireVaultWidgetMetric(value: accountNumber, title: "Account", symbol: "number")
                FireVaultWidgetMetric(
                    value: "\(dropPinCount)",
                    title: "Saved locations",
                    symbol: "mappin.and.ellipse"
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(
                    dropPinCount > 0 ? "Arrival details are ready" : "No arrival locations saved",
                    systemImage: dropPinCount > 0 ? "map.fill" : "map"
                )
                .font(.headline)
                .foregroundStyle(dropPinCount > 0 ? FireVaultWidgetDesign.green : FireVaultWidgetDesign.amber)
                .widgetAccentable()
                Text("Open this account for notes, equipment, files, photos, and arrival information.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FireVaultWidgetDesign.paper.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            Spacer(minLength: 0)
            FireVaultWidgetActionLabel(title: "Open Account", symbol: "arrow.right.circle.fill")
        }
    }

    private var accountName: String {
        entry.account?.name ?? entry.snapshot.accountName ?? "Select an Account"
    }

    private var accountNumber: String {
        entry.account?.accountID ?? entry.snapshot.accountID ?? "—"
    }

    private var accountAddress: String {
        guard let value = entry.account?.address ?? entry.snapshot.accountAddress,
              !value.isEmpty else { return "Open FireVault to select an account" }
        return value
    }

    private var dropPinCount: Int {
        entry.account?.dropPinCount ?? entry.snapshot.accountDropPinCount ?? 0
    }

    private var locationText: String {
        "\(dropPinCount) location\(dropPinCount == 1 ? "" : "s")"
    }

    private var accountURL: URL {
        guard let recordID = entry.account?.id ?? entry.snapshot.accountRecordID,
              !recordID.isEmpty else {
            return URL(string: "firevault://accounts")!
        }
        var components = URLComponents()
        components.scheme = "firevault"
        components.host = "account"
        components.queryItems = [URLQueryItem(name: "id", value: recordID)]
        return components.url ?? URL(string: "firevault://accounts")!
    }
}

// MARK: - Cloud Status

private struct FireVaultCloudStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FireVaultWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("FireVault Cloud • \(cloudTitle)", systemImage: cloudSymbol)
            case .accessoryCircular:
                AccessoryWidgetBackground()
                    .overlay {
                        VStack(spacing: 1) {
                            Image(systemName: cloudSymbol)
                                .font(.headline)
                            Text(pendingCount == 0 ? "OK" : "\(pendingCount)")
                                .font(.caption2.bold())
                        }
                    }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: cloudSymbol)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FireVault Cloud")
                            .font(.headline)
                        Text("\(cloudTitle) • \(lastSyncText)")
                            .font(.caption)
                    }
                }
            case .systemSmall:
                small
            default:
                medium
            }
        }
        .widgetURL(URL(string: "firevault://sync"))
        .containerBackground(for: .widget) { FireVaultWidgetBackground() }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            FireVaultWidgetBrand(section: "Cloud")
            Spacer(minLength: 0)
            Image(systemName: cloudSymbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(cloudColor)
                .widgetAccentable()
            Text(cloudTitle)
                .font(.headline.bold())
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(lastSyncText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(cloudSummary)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                FireVaultWidgetBrand(section: "Cloud")
                Spacer(minLength: 0)
                HStack(spacing: 9) {
                    Image(systemName: cloudSymbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(cloudColor)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cloudTitle)
                            .font(.headline.bold())
                            .foregroundStyle(.primary)
                        Text(lastSyncText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(cloudDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 9) {
                FireVaultWidgetMetric(value: "\(accountCount)", title: "Accounts", symbol: "building.2.fill")
                FireVaultWidgetMetric(
                    value: "\(pendingCount)",
                    title: "Pending",
                    symbol: "arrow.triangle.2.circlepath",
                    color: pendingCount == 0 ? FireVaultWidgetDesign.green : FireVaultWidgetDesign.amber
                )
            }
            .frame(maxWidth: 126)
        }
    }

    private var cloudState: FireVaultWidgetSnapshot.CloudState {
        entry.snapshot.cloudState ?? .notSynced
    }

    private var cloudTitle: String { cloudState.title }
    private var accountCount: Int { entry.snapshot.accountCount ?? 0 }
    private var pendingCount: Int { entry.snapshot.pendingCloudAccountCount ?? 0 }

    private var cloudSymbol: String {
        switch cloudState {
        case .notSynced: "icloud.slash"
        case .syncing: "arrow.triangle.2.circlepath.icloud.fill"
        case .upToDate: "checkmark.icloud.fill"
        case .needsAttention: "exclamationmark.icloud.fill"
        }
    }

    private var cloudColor: Color {
        switch cloudState {
        case .notSynced: .gray
        case .syncing: FireVaultWidgetDesign.navy
        case .upToDate: FireVaultWidgetDesign.green
        case .needsAttention: FireVaultWidgetDesign.amber
        }
    }

    private var lastSyncText: String {
        guard let date = entry.snapshot.cloudLastSyncedAt else { return "Not yet synced" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: entry.date)
    }

    private var cloudSummary: String {
        pendingCount == 0 ? "\(accountCount) accounts protected" : "\(pendingCount) records pending"
    }

    private var cloudDetail: String {
        switch cloudState {
        case .notSynced: "Open FireVault to complete your first cloud sync."
        case .syncing: "Checking and updating your field records."
        case .upToDate: pendingCount == 0 ? "All field records are protected." : "Finishing the last pending records."
        case .needsAttention: "Open FireVault to review pending records."
        }
    }
}

#Preview("Trip Log Small", as: .systemSmall) {
    FireVaultTripLogWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}

#Preview("Trip Log Medium", as: .systemMedium) {
    FireVaultTripLogWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}

#Preview("Trip Log Large", as: .systemLarge) {
    FireVaultTripLogWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}

#Preview("Account Medium", as: .systemMedium) {
    FireVaultAccountWidget()
} timeline: {
    FireVaultAccountWidgetEntry(
        date: Date(),
        snapshot: .placeholder,
        account: FireVaultWidgetSnapshot.placeholder.accountChoices?.first
    )
}

#Preview("Cloud Small", as: .systemSmall) {
    FireVaultCloudStatusWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}

#Preview("Cloud Medium", as: .systemMedium) {
    FireVaultCloudStatusWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}
