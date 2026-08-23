//
//  FireVaultWidgetPortfolio.swift
//  FireVaultWidgets
//
//  Focused, state-aware widgets for Trip Log, account access, and cloud health.
//

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
        .description("See recording status, elapsed time, mileage, stops, and GPS quality.")
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
        .configurationDisplayName("FireVault Field Account")
        .description("Return to the most recently selected account and its saved field locations.")
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
        .description("Monitor account coverage, pending cloud records, and the latest successful sync.")
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

private enum FireVaultPortfolioPalette {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.025, green: 0.045, blue: 0.065),
            Color(red: 0.045, green: 0.12, blue: 0.16)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let red = Color(red: 0.94, green: 0.12, blue: 0.14)
    static let cyan = Color(red: 0.18, green: 0.78, blue: 0.9)
}

private struct FireVaultPortfolioBrand: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("FIRE").foregroundStyle(FireVaultPortfolioPalette.red)
            Text("VAULT").foregroundStyle(.white)
            Text("  PRO")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
        }
        .font(.system(size: 12, weight: .black, design: .rounded))
        .tracking(0.9)
    }
}

private struct FireVaultCompactFact: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = FireVaultPortfolioPalette.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(label, systemImage: symbol)
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(tint)
                .frame(width: 2)
                .offset(x: -7)
        }
        .padding(.leading, 7)
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
                Label(
                    "Trip Log \(stateTitle) • \(shortDuration) • \(milesText)",
                    systemImage: stateSymbol
                )
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Image(systemName: stateSymbol)
                        .font(.headline)
                    Text(entry.snapshot.tripState == .recording ? shortDuration : stateTitle.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: stateSymbol).font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trip Log • \(stateTitle)").font(.headline)
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
        .widgetURL(URL(string: tripDestination))
        .containerBackground(for: .widget) { FireVaultPortfolioPalette.background }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            FireVaultPortfolioBrand()
            Label(stateTitle.uppercased(), systemImage: stateSymbol)
                .font(.caption2.bold())
                .foregroundStyle(stateColor)
            Spacer(minLength: 0)
            Text(durationText)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            HStack(spacing: 8) {
                Label(milesText, systemImage: "road.lanes")
                Label("\(entry.snapshot.stopCount)", systemImage: "mappin.and.ellipse")
            }
            .font(.caption2.bold())
            .foregroundStyle(.white.opacity(0.68))
            Label(actionTitle, systemImage: actionSymbol)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(stateColor.opacity(0.74), in: Capsule())
        }
    }

    private var medium: some View {
        VStack(spacing: 7) {
            HStack {
                FireVaultPortfolioBrand()
                Spacer()
                Label(stateTitle.uppercased(), systemImage: stateSymbol)
                    .font(.caption2.bold())
                    .foregroundStyle(stateColor)
            }
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ELAPSED")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.48))
                    Text(durationText)
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FireVaultCompactFact(value: milesText, label: "MILES", symbol: "road.lanes")
                FireVaultCompactFact(
                    value: "\(entry.snapshot.stopCount)",
                    label: "STOPS",
                    symbol: "mappin.and.ellipse"
                )
                FireVaultCompactFact(
                    value: gpsText,
                    label: "GPS",
                    symbol: "scope",
                    tint: gpsColor
                )
            }
            Divider().overlay(.white.opacity(0.12))
            HStack {
                Label(
                    entry.snapshot.accountName ?? "No active account",
                    systemImage: "building.2.fill"
                )
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
                .privacySensitive()
                Spacer(minLength: 8)
                Label(actionTitle, systemImage: actionSymbol)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(stateColor.opacity(0.78), in: Capsule())
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                FireVaultPortfolioBrand()
                Spacer()
                Label(stateTitle.uppercased(), systemImage: stateSymbol)
                    .font(.caption.bold())
                    .foregroundStyle(stateColor)
            }
            Text(durationText)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            HStack(spacing: 12) {
                largeFact(milesText, "MILES", "road.lanes")
                largeFact("\(entry.snapshot.stopCount)", "STOPS", "mappin.and.ellipse")
                largeFact(gpsText, "GPS", "scope")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("CURRENT FIELD CONTEXT")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.48))
                Label(entry.snapshot.accountName ?? "No account selected", systemImage: "building.2.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .privacySensitive()
                Text(entry.snapshot.accountAddress ?? "Open FireVault to select an account")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .privacySensitive()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            Spacer(minLength: 0)
            Label(actionTitle, systemImage: actionSymbol)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(stateColor.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(3)
    }

    private func largeFact(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: symbol)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
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
        case .recording: .green
        case .paused: .orange
        case .complete: FireVaultPortfolioPalette.cyan
        case .ready: FireVaultPortfolioPalette.cyan
        }
    }

    private var actionTitle: String {
        switch entry.snapshot.tripState {
        case .recording: "Open Trip Log"
        case .paused: "Resume"
        case .complete, .ready: "Start Trip Log"
        }
    }

    private var actionSymbol: String {
        switch entry.snapshot.tripState {
        case .recording: "arrow.right.circle.fill"
        case .paused: "play.fill"
        case .complete, .ready: "record.circle"
        }
    }

    private var tripDestination: String {
        entry.snapshot.tripState == .recording
            ? "firevault://triplog"
            : "firevault://triplog/start"
    }

    private var gpsText: String {
        guard let updatedAt = entry.snapshot.gpsUpdatedAt,
              entry.date.timeIntervalSince(updatedAt) < 300,
              let quality = entry.snapshot.gpsQuality else { return "Waiting" }
        return quality.title
    }

    private var gpsColor: Color {
        switch entry.snapshot.gpsQuality {
        case .excellent, .good: .green
        case .fair: .orange
        case .poor: .red
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
        .containerBackground(for: .widget) { FireVaultPortfolioPalette.background }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FireVaultPortfolioBrand()
                Spacer()
                Image(systemName: "building.2.crop.circle.fill")
                    .foregroundStyle(FireVaultPortfolioPalette.cyan)
            }
            Spacer(minLength: 0)
            Text(accountName)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .privacySensitive()
            Text(accountDetail)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
                .privacySensitive()
            Label("\(dropPinCount) drop pins", systemImage: "mappin.and.ellipse")
                .font(.caption2.bold())
                .foregroundStyle(FireVaultPortfolioPalette.cyan)
        }
    }

    private var medium: some View {
        VStack(spacing: 8) {
            HStack {
                FireVaultPortfolioBrand()
                Spacer()
                Text("FIELD ACCOUNT")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.48))
            }
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 31))
                    .foregroundStyle(FireVaultPortfolioPalette.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountName)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .privacySensitive()
                    Text(accountAddress)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .privacySensitive()
                }
                Spacer(minLength: 0)
            }
            Divider().overlay(.white.opacity(0.12))
            HStack(spacing: 14) {
                FireVaultCompactFact(value: accountNumber, label: "ACCOUNT", symbol: "number")
                FireVaultCompactFact(value: accountCategory, label: "CATEGORY", symbol: "tag.fill")
                FireVaultCompactFact(
                    value: "\(dropPinCount)",
                    label: "DROP PINS",
                    symbol: "mappin.and.ellipse"
                )
                Label("Open", systemImage: "arrow.right.circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(FireVaultPortfolioPalette.cyan.opacity(0.62), in: Capsule())
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                FireVaultPortfolioBrand()
                Spacer()
                Label("FIELD ACCOUNT", systemImage: "building.2.fill")
                    .font(.caption.bold())
                    .foregroundStyle(FireVaultPortfolioPalette.cyan)
            }
            Text(accountName)
                .font(.system(size: 27, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .privacySensitive()
            Text(accountAddress)
                .font(.body)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
                .privacySensitive()
            HStack(spacing: 12) {
                largeInfo(accountNumber, "ACCOUNT", "number")
                largeInfo(accountCategory, "CATEGORY", "tag.fill")
                largeInfo("\(dropPinCount)", "DROP PINS", "mappin.and.ellipse")
            }
            VStack(alignment: .leading, spacing: 7) {
                Label(
                    dropPinCount > 0 ? "Saved field locations are available" : "No drop pins saved yet",
                    systemImage: dropPinCount > 0 ? "checkmark.circle.fill" : "mappin.slash"
                )
                .font(.headline)
                .foregroundStyle(dropPinCount > 0 ? .green : .orange)
                Text("Open this account to view notes, equipment, documents, and location details.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
            }
            .padding(12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            Spacer(minLength: 0)
            Label("Open Account", systemImage: "arrow.right.circle.fill")
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(FireVaultPortfolioPalette.cyan.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(3)
    }

    private func largeInfo(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: symbol)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .privacySensitive()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var accountName: String {
        entry.account?.name ?? entry.snapshot.accountName ?? "Select an Account"
    }

    private var accountNumber: String {
        entry.account?.accountID ?? entry.snapshot.accountID ?? "—"
    }

    private var accountCategory: String {
        entry.account?.category ?? entry.snapshot.accountCategory ?? "Unassigned"
    }

    private var accountAddress: String {
        guard let value = entry.account?.address ?? entry.snapshot.accountAddress,
              !value.isEmpty else { return "Open FireVault to select an account" }
        return value
    }

    private var dropPinCount: Int {
        entry.account?.dropPinCount ?? entry.snapshot.accountDropPinCount ?? 0
    }

    private var accountDetail: String {
        [accountNumber, accountCategory]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
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
                VStack(spacing: 1) {
                    Image(systemName: cloudSymbol).font(.headline)
                    Text(pendingCount == 0 ? "OK" : "\(pendingCount)")
                        .font(.caption2.bold())
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: cloudSymbol).font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FireVault Cloud • \(cloudTitle)").font(.headline)
                        Text("\(accountCount) accounts • \(pendingCount) pending")
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
        .containerBackground(for: .widget) { FireVaultPortfolioPalette.background }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            FireVaultPortfolioBrand()
            Spacer(minLength: 0)
            Image(systemName: cloudSymbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(cloudColor)
            Text(cloudTitle)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(lastSyncText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            HStack {
                Label("\(accountCount)", systemImage: "building.2.fill")
                Spacer()
                Label("\(pendingCount)", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption2.bold())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var medium: some View {
        VStack(spacing: 8) {
            HStack {
                FireVaultPortfolioBrand()
                Spacer()
                Label(cloudTitle.uppercased(), systemImage: cloudSymbol)
                    .font(.caption2.bold())
                    .foregroundStyle(cloudColor)
            }
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("LAST SUCCESSFUL SYNC")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.48))
                    Text(lastSyncText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FireVaultCompactFact(value: "\(accountCount)", label: "ACCOUNTS", symbol: "building.2.fill")
                FireVaultCompactFact(value: "\(mappedCount)", label: "MAPPED", symbol: "map.fill")
                FireVaultCompactFact(
                    value: "\(pendingCount)",
                    label: "PENDING",
                    symbol: "arrow.triangle.2.circlepath",
                    tint: pendingCount == 0 ? .green : .orange
                )
            }
            Divider().overlay(.white.opacity(0.12))
            HStack {
                Text(cloudDetail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Label("Sync", systemImage: "arrow.clockwise")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 27)
                    .background(cloudColor.opacity(0.7), in: Capsule())
            }
        }
    }

    private var cloudState: FireVaultWidgetSnapshot.CloudState {
        entry.snapshot.cloudState ?? .notSynced
    }

    private var cloudTitle: String { cloudState.title }
    private var accountCount: Int { entry.snapshot.accountCount ?? 0 }
    private var mappedCount: Int { entry.snapshot.mappedAccountCount ?? 0 }
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
        case .syncing: FireVaultPortfolioPalette.cyan
        case .upToDate: .green
        case .needsAttention: .orange
        }
    }

    private var lastSyncText: String {
        guard let date = entry.snapshot.cloudLastSyncedAt else { return "Not yet synced" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var cloudDetail: String {
        switch cloudState {
        case .notSynced: "Open FireVault to complete the first cloud sync."
        case .syncing: "FireVault is checking and updating account records."
        case .upToDate: pendingCount == 0 ? "All known account records are linked." : "Some records still need upload."
        case .needsAttention: "Open Sync settings to review the latest error."
        }
    }
}

#Preview("Trip Log Medium", as: .systemMedium) {
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

#Preview("Cloud Medium", as: .systemMedium) {
    FireVaultCloudStatusWidget()
} timeline: {
    FireVaultWidgetEntry(date: Date(), snapshot: .placeholder)
}
