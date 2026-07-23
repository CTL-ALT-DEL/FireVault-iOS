//
//  NativeAppShell.swift
//  FireVault
//
//  Native everyday navigation for Build 1.03.34.
//

import SwiftUI
import Combine
import MapKit
import WebKit

@MainActor
final class FireVaultAppShellBridge: ObservableObject {
    @Published private(set) var payload: FireVaultAppPayload?
    weak var webView: WKWebView?

    func present(_ rawPayload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(rawPayload),
              let data = try? JSONSerialization.data(withJSONObject: rawPayload),
              let decoded = try? JSONDecoder().decode(FireVaultAppPayload.self, from: data) else { return }
        payload = decoded
    }

    func hide() { payload = nil }

    func perform(_ action: String, payload extra: [String: Any] = [:], hideShell: Bool = false) {
        guard let webView else { return }
        var message = extra
        message["action"] = action
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              var json = String(data: data, encoding: .utf8) else { return }
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        if hideShell { hide() }
        webView.evaluateJavaScript("window.fireVaultNativeAppAction?.(\(json));")
    }
}

struct FireVaultAppPayload: Codable, Equatable {
    let build: String
    let initialTab: String
    let demoMode: Bool
    let today: String
    let technicianName: String
    let locationStatus: String
    let accounts: [FireVaultNativeAccount]
    let nearby: [FireVaultNativeNearbyAccount]
    let settingsGroups: [FireVaultNativeSettingsGroup]
}

struct FireVaultNativeAccount: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let accountId: String
    let category: String
    let phone: String
    let favorite: Bool
    let latitude: Double?
    let longitude: Double?
    let recentText: String

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
}

struct FireVaultNativeNearbyAccount: Codable, Identifiable, Equatable {
    let id: String
    let account: FireVaultNativeAccount
    let distanceMeters: Double
    let distanceLabel: String
}

struct FireVaultNativeSettingsGroup: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: String
    let status: String
    let items: [FireVaultNativeSettingItem]
}

struct FireVaultNativeSettingItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let status: String

    var accessibilityLabel: String {
        [title, subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    func displayStatus(nativeVersion: String) -> String {
        switch id {
        case "about": "Version \(nativeVersion)"
        case "updates": "Build \(nativeVersion)"
        default: status
        }
    }
}

struct FireVaultVersionInfo: Equatable {
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var displayText: String { "Version \(version) (\(build))" }
}

private enum FireVaultShellTab: String, CaseIterable, Identifiable {
    case nearby, accounts, photo, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nearby: "Nearby"
        case .accounts: "Accounts"
        case .photo: "Photo"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .nearby: "location.fill"
        case .accounts: "magnifyingglass"
        case .photo: "camera.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct NativeAppShellView: View {
    let payload: FireVaultAppPayload
    @ObservedObject var bridge: FireVaultAppShellBridge
    @State private var selection: FireVaultShellTab = .nearby

    var body: some View {
        ZStack {
            NativeShellPalette.background.ignoresSafeArea()
            Group {
                switch selection {
                case .nearby: NativeNearbyView(payload: payload, bridge: bridge)
                case .accounts, .photo: NativeAccountsView(payload: payload, bridge: bridge)
                case .settings: NativeSettingsView(payload: payload, bridge: bridge)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            nativeNavigation
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        .tint(NativeShellPalette.blue)
        .preferredColorScheme(.dark)
        .onAppear { selection = FireVaultShellTab(rawValue: payload.initialTab) ?? .nearby }
    }

    private var nativeNavigation: some View {
        HStack(spacing: 2) {
            ForEach(FireVaultShellTab.allCases) { tab in
                Button {
                    if tab == .photo {
                        bridge.perform("photo", hideShell: true)
                    } else {
                        withAnimation(.snappy(duration: 0.25)) { selection = tab }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 18, weight: .semibold))
                        Text(tab.title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selection == tab ? NativeShellPalette.blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(selection == tab ? NativeShellPalette.blue.opacity(0.14) : .clear, in: Capsule())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(5)
        .background(NativeShellPalette.surface.opacity(0.92), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.10), lineWidth: 1) }
    }
}

private struct NativeNearbyView: View {
    let payload: FireVaultAppPayload
    @ObservedObject var bridge: FireVaultAppShellBridge
    @State private var selectedID: String?

    private var selected: FireVaultNativeNearbyAccount? {
        payload.nearby.first(where: { $0.id == selectedID }) ?? payload.nearby.first
    }

    private var mapRegion: MKCoordinateRegion {
        let coordinates = payload.nearby.compactMap(\.account.coordinate)
        guard let first = coordinates.first else {
            return .init(center: .init(latitude: 43.615, longitude: -116.202), span: .init(latitudeDelta: 0.18, longitudeDelta: 0.18))
        }
        let minLat = coordinates.map(\.latitude).min() ?? first.latitude
        let maxLat = coordinates.map(\.latitude).max() ?? first.latitude
        let minLng = coordinates.map(\.longitude).min() ?? first.longitude
        let maxLng = coordinates.map(\.longitude).max() ?? first.longitude
        return .init(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: .init(latitudeDelta: max(0.018, (maxLat - minLat) * 1.45), longitudeDelta: max(0.018, (maxLng - minLng) * 1.45))
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    statusHeader
                    map
                    if let selected { selectedCard(selected) }
                    accountList
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { bridge.perform("refreshNearby") } label: { Image(systemName: "location.circle.fill") }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Refresh nearby accounts")
                }
            }
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(payload.demoMode ? "DEMO VAULT" : "FIELD VAULT")
                    .font(.caption2.bold()).tracking(1.2)
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)
                Text(payload.locationStatus).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(payload.today).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private var map: some View {
        Group {
            if payload.nearby.isEmpty {
                NativeShellCard {
                    ContentUnavailableView(
                        "No Nearby Map Yet",
                        systemImage: "map",
                        description: Text("Refresh location to display GPS-ready accounts on Apple Maps.")
                    )
                }
            } else {
                Map(initialPosition: .region(mapRegion)) {
                    ForEach(Array(payload.nearby.enumerated()), id: \.element.id) { index, row in
                        if let coordinate = row.account.coordinate {
                            Annotation(row.account.name, coordinate: coordinate) {
                                Button { selectedID = row.id } label: {
                                    Text("\(index + 1)")
                                        .font(.caption.bold()).foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(selected?.id == row.id ? NativeShellPalette.red : NativeShellPalette.blue, in: Circle())
                                        .overlay { Circle().stroke(.white.opacity(0.85), lineWidth: 2) }
                                        .shadow(radius: 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1) }
            }
        }
    }

    private func selectedCard(_ row: FireVaultNativeNearbyAccount) -> some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.account.name).font(.title3.bold()).foregroundStyle(.white)
                        Text(row.account.address).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(row.distanceLabel).font(.headline).foregroundStyle(NativeShellPalette.green)
                }
                HStack(spacing: 10) {
                    Button("Open", systemImage: "arrow.up.right") {
                        bridge.perform("openAccount", payload: ["id": row.account.id, "source": "nearby"], hideShell: true)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        bridge.perform("routeAccount", payload: ["id": row.account.id])
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CLOSEST ACCOUNTS").font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                Text("\(payload.nearby.count)").foregroundStyle(.secondary)
            }
            if payload.nearby.isEmpty {
                ContentUnavailableView("Location Check Needed", systemImage: "location.slash", description: Text("Tap the location button to compare this iPhone with GPS-ready accounts."))
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                NativeShellCard {
                    VStack(spacing: 0) {
                        ForEach(Array(payload.nearby.prefix(12).enumerated()), id: \.element.id) { index, row in
                            Button { selectedID = row.id } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.caption.bold()).frame(width: 30, height: 30).background(NativeShellPalette.blue.opacity(0.14), in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.account.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                        Text(row.account.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Text(row.distanceLabel).font(.subheadline.bold()).foregroundStyle(NativeShellPalette.green)
                                }
                                .padding(.vertical, 12).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < min(payload.nearby.count, 12) - 1 { Divider().padding(.leading, 42) }
                        }
                    }
                }
            }
        }
    }
}

private enum NativeAccountSort: String, CaseIterable, Identifiable {
    case alphabetic = "A–Z"
    case favorites = "Favorites"
    case recent = "Recent"
    var id: String { rawValue }
}

private struct NativeAccountsView: View {
    let payload: FireVaultAppPayload
    @ObservedObject var bridge: FireVaultAppShellBridge
    @State private var search = ""
    @State private var sort: NativeAccountSort = .alphabetic

    private var accounts: [FireVaultNativeAccount] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? payload.accounts : payload.accounts.filter {
            [$0.name, $0.address, $0.accountId, $0.category].joined(separator: " ").lowercased().contains(query)
        }
        switch sort {
        case .alphabetic: return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .favorites:
            return filtered.sorted {
                if $0.favorite != $1.favorite { return $0.favorite && !$1.favorite }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recent: return filtered.sorted { $0.recentText > $1.recentText }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if accounts.isEmpty {
                    ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(accounts) { account in
                            Button {
                                bridge.perform("openAccount", payload: ["id": account.id, "source": "accounts"], hideShell: true)
                            } label: { NativeAccountRow(account: account) }
                            .buttonStyle(.plain)
                            .listRowBackground(NativeShellPalette.surface)
                        }
                    } header: { Text("\(accounts.count) account\(accounts.count == 1 ? "" : "s")") }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NativeShellPalette.background)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, address, or account ID")
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort Accounts", selection: $sort) {
                            ForEach(NativeAccountSort.allCases) { option in Text(option.rawValue).tag(option) }
                        }
                    } label: { Label(sort.rawValue, systemImage: "arrow.up.arrow.down") }
                    .buttonStyle(.glass)
                    Button { bridge.perform("addAccount", hideShell: true) } label: { Image(systemName: "plus") }
                        .buttonStyle(.glassProminent).accessibilityLabel("Add Account")
                }
            }
        }
    }
}

private struct NativeAccountRow: View {
    let account: FireVaultNativeAccount
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.favorite ? "building.2.crop.circle.fill" : "building.2.crop.circle")
                .font(.title2)
                .foregroundStyle(account.favorite ? NativeShellPalette.amber : NativeShellPalette.blue)
                .frame(width: 42, height: 42)
                .background((account.favorite ? NativeShellPalette.amber : NativeShellPalette.blue).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(account.address).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 7) {
                    if !account.category.isEmpty { Text(account.category.uppercased()).nativeMetadataPill(tint: NativeShellPalette.blue) }
                    if !account.accountId.isEmpty { Text(account.accountId).nativeMetadataPill(tint: .secondary) }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7).contentShape(Rectangle())
    }
}

private struct NativeSettingsView: View {
    let payload: FireVaultAppPayload
    @ObservedObject var bridge: FireVaultAppShellBridge
    @State private var search = ""
    private let versionInfo = FireVaultVersionInfo()

    private var groups: [FireVaultNativeSettingsGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return payload.settingsGroups }

        return payload.settingsGroups.compactMap { group in
            let matchingItems = group.items.filter {
                [$0.title, $0.subtitle, $0.status, group.title, group.subtitle]
                    .joined(separator: " ")
                    .lowercased()
                    .contains(query)
            }
            guard !matchingItems.isEmpty else { return nil }
            return .init(
                id: group.id,
                title: group.title,
                subtitle: group.subtitle,
                symbol: group.symbol,
                tint: group.tint,
                status: group.status,
                items: matchingItems
            )
        }
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection

                if groups.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(groups) { group in
                        settingsSection(group)
                    }
                }

                aboutFooter
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(NativeShellPalette.background)
            .searchable(text: $search, prompt: "Search settings")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .accessibilityIdentifier("native-settings-list")
        }
    }

    private var profileSection: some View {
        Section {
            Button {
                bridge.perform("openSetting", payload: ["id": "technician-profile", "group": "profile"], hideShell: true)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(NativeShellPalette.blue)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(payload.technicianName.isEmpty ? "Technician Profile" : payload.technicianName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(payload.demoMode ? "Demo Mode" : "Field technician profile")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(payload.technicianName.isEmpty ? "Technician Profile" : payload.technicianName)
            .accessibilityValue(payload.demoMode ? "Demo Mode" : "Field technician profile")
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens technician profile settings")
        }
    }

    private func settingsSection(_ group: FireVaultNativeSettingsGroup) -> some View {
        Section {
            ForEach(group.items) { item in
                let status = item.displayStatus(nativeVersion: versionInfo.version)
                Button {
                    bridge.perform(
                        "openSetting",
                        payload: ["id": item.id, "group": group.id],
                        hideShell: true
                    )
                } label: {
                    FVSettingsRow(
                        item: item,
                        status: status,
                        tint: NativeShellPalette.tint(group.tint)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityValue(status)
                .accessibilityHint("Opens \(item.title)")
            }
        } header: {
            Label(group.title, systemImage: group.symbol)
                .foregroundStyle(NativeShellPalette.tint(group.tint))
        } footer: {
            if !group.subtitle.isEmpty {
                Text(group.subtitle)
            }
        }
    }

    private var aboutFooter: some View {
        Section {
            HStack {
                Text("FireVault")
                Spacer()
                Text(versionInfo.displayText)
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .accessibilityElement(children: .combine)
        } footer: {
            Text("A field workspace for notes, files, scans, photos, equipment, and account maps.")
        }
    }
}

private struct FVSettingsRow: View {
    let item: FireVaultNativeSettingItem
    let status: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: item.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }
}

private struct NativeShellCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1) }
    }
}

private extension View {
    func nativeMetadataPill(tint: Color) -> some View {
        self.font(.caption2.bold()).foregroundStyle(tint).padding(.horizontal, 7).padding(.vertical, 3).background(tint.opacity(0.12), in: Capsule())
    }
}

private enum NativeShellPalette {
    static let background = Color(red: 0.028, green: 0.043, blue: 0.061)
    static let surface = Color(red: 0.070, green: 0.095, blue: 0.125)
    static let blue = Color(red: 0.24, green: 0.67, blue: 1.0)
    static let green = Color(red: 0.23, green: 0.86, blue: 0.58)
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.26)
    static let red = Color(red: 1.0, green: 0.34, blue: 0.40)
    static let purple = Color(red: 0.68, green: 0.48, blue: 1.0)
    static func tint(_ name: String) -> Color {
        switch name { case "green": green; case "amber": amber; case "red": red; case "purple": purple; default: blue }
    }
}
