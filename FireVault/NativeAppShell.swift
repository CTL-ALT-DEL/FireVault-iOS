//
//  NativeAppShell.swift
//  FireVault
//
//  Native everyday navigation for Build 1.05.01.
//

import SwiftUI
import Combine
import MapKit
import PhotosUI
import UIKit

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

enum FireVaultShellTab: String, CaseIterable, Identifiable {
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
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            NativeShellPalette.background.ignoresSafeArea()
            Group {
                switch store.selectedTab {
                case .nearby: NativeNearbyView(payload: payload, store: store, settings: settings)
                case .accounts: NativeAccountsView(payload: payload, store: store)
                case .photo: NativePhotoView(store: store)
                case .settings: NativeSettingsView(payload: payload, store: store, settings: settings)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                nativeNavigation
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(NativeShellPalette.blue)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) { keyboardVisible = false }
        }
    }

    private var nativeNavigation: some View {
        HStack(spacing: 0) {
            ForEach(FireVaultShellTab.allCases) { tab in
                let isSelected = store.selectedTab == tab
                Button {
                    withAnimation(.snappy(duration: 0.25)) { store.selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: isSelected ? .bold : .semibold))
                            .symbolVariant(isSelected ? .fill : .none)
                        Text(tab.title)
                            .font(.caption2.weight(isSelected ? .bold : .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isSelected ? NativeShellPalette.blue : NativeShellPalette.navigationInactive)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("main-navigation-\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 2)
        .background(NativeShellPalette.navigationBackground.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NativeShellPalette.navigationDivider)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
        .accessibilityIdentifier("main-navigation")
    }
}

private struct NativeNearbyView: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var selectedID: String?

    private var nearbyRows: [FireVaultNativeNearbyAccount] {
        let maximumMeters = settings.gps.nearbyRadiusMiles * 1_609.344
        return payload.nearby.filter { $0.distanceMeters <= maximumMeters }
    }

    private var selected: FireVaultNativeNearbyAccount? {
        nearbyRows.first(where: { $0.id == selectedID }) ?? nearbyRows.first
    }

    private var mapRegion: MKCoordinateRegion {
        let coordinates = nearbyRows.compactMap(\.account.coordinate)
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
                    Button { store.refreshNearby() } label: { Image(systemName: "location.circle.fill") }
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
            if nearbyRows.isEmpty {
                NativeShellCard {
                    ContentUnavailableView(
                        payload.nearby.isEmpty ? "No Mapped Accounts" : "No Accounts in Range",
                        systemImage: "map",
                        description: Text(
                            payload.nearby.isEmpty
                                ? (payload.demoMode
                                    ? "Refresh location to display GPS-ready accounts on Apple Maps."
                                    : "Import accounts with latitude and longitude, or add locations to native accounts.")
                                : "Increase the Nearby Radius in Settings to include more accounts."
                        )
                    )
                }
            } else {
                Map(initialPosition: .region(mapRegion)) {
                    ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
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
                        store.openAccount(row.account.id)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        if let account = store.accounts.first(where: { $0.id == row.account.id }) {
                            store.openRoute(for: account)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WITHIN \(settings.gps.nearbyRadiusMiles.formatted(.number.precision(.fractionLength(0...2)))) MILES")
                    .font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                Text("\(nearbyRows.count)").foregroundStyle(.secondary)
            }
            if nearbyRows.isEmpty {
                ContentUnavailableView(
                    payload.nearby.isEmpty ? "No Mapped Accounts" : "No Accounts in Range",
                    systemImage: "location.slash",
                    description: Text(
                        payload.nearby.isEmpty
                            ? (payload.demoMode
                                ? "Tap the location button to compare this iPhone with GPS-ready accounts."
                                : "Import accounts through Settings, then add GPS coordinates for Nearby.")
                            : "Change the native Nearby Radius in Settings."
                    )
                )
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                NativeShellCard {
                    VStack(spacing: 0) {
                        ForEach(Array(nearbyRows.prefix(12).enumerated()), id: \.element.id) { index, row in
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
                            if index < min(nearbyRows.count, 12) - 1 { Divider().padding(.leading, 42) }
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
    @ObservedObject var store: FireVaultStore
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
                    if search.isEmpty {
                        ContentUnavailableView(
                            "No Accounts",
                            systemImage: "building.2",
                            description: Text("Add an account here or import a CSV from Settings.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ContentUnavailableView.search(text: search)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(accounts) { account in
                            Button {
                                store.openAccount(account.id)
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
                    Button { store.addAccount() } label: { Image(systemName: "plus") }
                        .buttonStyle(.glassProminent).accessibilityLabel("Add Account")
                }
            }
        }
    }
}

private struct NativePhotoView: View {
    @ObservedObject var store: FireVaultStore
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                } else {
                    ContentUnavailableView(
                        "Select a Field Photo",
                        systemImage: "camera.fill",
                        description: Text("The native photo workspace uses the iOS photo picker. Camera capture and account attachment will be added to this native workflow next.")
                    )
                }

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeShellPalette.background)
            .navigationTitle("Photo")
            .onChange(of: selectedItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    selectedImage = image
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
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var search = ""
    private let versionInfo = FireVaultVersionInfo()

    private var groups: [FireVaultNativeSettingsGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nativeGroups = NativeSettingsCatalog.groups
        guard !query.isEmpty else { return nativeGroups }

        return nativeGroups.compactMap { group in
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
            NavigationLink {
                NativeTechnicianSettingsView(settings: settings)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(NativeShellPalette.blue)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.preferences.technician.name.isEmpty ? "Technician Profile" : settings.preferences.technician.name)
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
            .accessibilityLabel(settings.preferences.technician.name.isEmpty ? "Technician Profile" : settings.preferences.technician.name)
            .accessibilityValue(payload.demoMode ? "Demo Mode" : "Field technician profile")
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens technician profile settings")
        }
    }

    private func settingsSection(_ group: FireVaultNativeSettingsGroup) -> some View {
        Section {
            ForEach(group.items) { item in
                let status = item.displayStatus(nativeVersion: versionInfo.version)
                settingsRow(item, group: group, status: status)
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

    @ViewBuilder
    private func settingsRow(
        _ item: FireVaultNativeSettingItem,
        group: FireVaultNativeSettingsGroup,
        status: String
    ) -> some View {
        let row = FVSettingsRow(
            item: item,
            status: nativeStatus(for: item, fallback: status),
            tint: NativeShellPalette.tint(group.tint)
        )

        NavigationLink {
            nativeDestination(item.id)
        } label: { row }
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityValue(nativeStatus(for: item, fallback: status))
            .accessibilityHint("Opens native \(item.title)")
    }

    private func nativeStatus(for item: FireVaultNativeSettingItem, fallback: String) -> String {
        switch item.id {
        case "gps": settings.gps.radiusStatus
        case "tech": settings.preferences.technician.name.isEmpty ? "Not configured" : settings.preferences.technician.name
        case "email": settings.preferences.email.defaultTo.isEmpty ? "Not configured" : "Configured"
        case "reports": settings.preferences.reports.format.capitalized
        case "overlay": "Native"
        case "plusCodes": settings.preferences.plusCodes.enabled ? "On" : "Off"
        case "webdav": settings.preferences.webDAV.enabled ? "Configured" : "Off"
        case "privacy": settings.preferences.privacy.enabled ? "On" : "Off"
        case "customerImport": "Native CSV"
        case "demo": store.demoMode ? "Active" : "Off"
        case "about": "Version \(versionInfo.version)"
        case "updates": "Build \(versionInfo.version)"
        default: fallback
        }
    }

    @ViewBuilder
    private func nativeDestination(_ id: String) -> some View {
        switch id {
        case "tech": NativeTechnicianSettingsView(settings: settings)
        case "overlay": NativeOverlaySettingsView(settings: settings)
        case "gps": NativeGPSSettingsView(settings: settings)
        case "plusCodes": NativePlusCodeSettingsView(settings: settings)
        case "reports": NativeReportSettingsView(settings: settings)
        case "email": NativeEmailSettingsView(settings: settings)
        case "cloudFiles": NativeStorageSettingsView(settings: settings)
        case "microsoftStorage": NativeMicrosoftStorageSettingsView(settings: settings)
        case "sync": NativeSyncSettingsView(settings: settings)
        case "customerImport": NativeCSVImportView(store: store)
        case "categories": NativeCategoriesSettingsView(settings: settings)
        case "backup": NativeMigrationStatusView(title: "Backup & Restore", symbol: "externaldrive.badge.timemachine", message: "Native full-vault backup will be enabled after accounts, media, notes, and equipment share the native repository.")
        case "webdav": NativeWebDAVSettingsView(settings: settings)
        case "privacy": NativePrivacySettingsView(settings: settings)
        case "security": NativeMigrationStatusView(title: "Security", symbol: "shield.checkered", message: "FireVault now uses the iOS application sandbox. Native Face ID and protected-export controls are the next security milestone.")
        case "manual": NativeManualView()
        case "updates": NativeUpdatesView(versionInfo: versionInfo)
        case "demo": NativeDemoSettingsView(store: store)
        case "about": NativeAboutFireVaultView(versionInfo: versionInfo)
        default: NativeMigrationStatusView(title: "Native Settings", symbol: "gearshape", message: "This setting has moved out of the web application and is being rebuilt for iOS.")
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

private struct NativeGPSSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultGPSPreferences
    @State private var radiusText: String
    @State private var saved = false
    @FocusState private var radiusFocused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        let current = settings.gps
        _draft = State(initialValue: current)
        _radiusText = State(
            initialValue: current.nearbyRadiusMiles.formatted(
                .number.precision(.fractionLength(0...2))
            )
        )
    }

    private var enteredRadius: Double? {
        Double(radiusText.replacingOccurrences(of: ",", with: "."))
    }

    private var radiusIsValid: Bool {
        guard let enteredRadius else { return false }
        return FireVaultGPSPreferences.allowedRadius.contains(enteredRadius)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Default map", value: "Apple Maps")

                Toggle("High-accuracy GPS", isOn: $draft.highAccuracy)

                LabeledContent {
                    TextField("Miles", text: $radiusText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($radiusFocused)
                        .frame(maxWidth: 100)
                        .accessibilityLabel("Nearby radius in miles")
                } label: {
                    Text("Nearby radius")
                }

                if !radiusIsValid {
                    Label("Enter a distance from 0.25 to 25 miles.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Map Preferences")
            } footer: {
                Text("This native distance controls the accounts displayed on the Nearby map and list.")
            }

            Section("GPS Tools") {
                Toggle("Show GPS capture controls", isOn: $draft.gpsToolsEnabled)
                Toggle("Include coordinates in reports", isOn: $draft.includeCoordinatesInReports)
                Toggle("Address assistance", isOn: $draft.addressAssistanceEnabled)
            }

            if saved {
                Section {
                    Label("GPS & Maps settings saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NativeShellPalette.green)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("GPS & Maps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: save)
                    .disabled(!radiusIsValid)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { radiusFocused = false }
            }
        }
        .onChange(of: radiusText) { _, _ in saved = false }
        .onChange(of: draft) { _, _ in saved = false }
        .onDisappear {
            if radiusIsValid { save() }
        }
    }

    private func save() {
        guard let enteredRadius, radiusIsValid else { return }
        draft.nearbyRadiusMiles = enteredRadius
        settings.saveGPS(draft)
        radiusFocused = false
        saved = true
    }
}

private struct NativeAboutFireVaultView: View {
    let versionInfo: FireVaultVersionInfo

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(NativeShellPalette.red)
                        .accessibilityHidden(true)
                    Text("FireVault")
                        .font(.largeTitle.bold())
                    Text("A field workspace for fire alarm technicians, combining account information, notes, files, document scans, photos, equipment records, and site mapping.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .accessibilityElement(children: .combine)
            }

            Section("Application") {
                LabeledContent("Version", value: versionInfo.version)
                LabeledContent("Build", value: versionInfo.build)
            }
        }
        .navigationTitle("About FireVault")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NativeUpdatesView: View {
    let versionInfo: FireVaultVersionInfo

    var body: some View {
        List {
            Section {
                Label("FireVault is installed", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(NativeShellPalette.green)
                LabeledContent("Version", value: versionInfo.version)
                LabeledContent("Build", value: versionInfo.build)
            } footer: {
                Text("Native FireVault updates are delivered with the installed iOS application. This screen no longer manages PWA files or browser caches.")
            }
        }
        .navigationTitle("App Updates")
        .navigationBarTitleDisplayMode(.inline)
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

enum NativeShellPalette {
    static let background = Color(red: 0.028, green: 0.043, blue: 0.061)
    static let surface = Color(red: 0.070, green: 0.095, blue: 0.125)
    static let blue = Color(red: 0.24, green: 0.67, blue: 1.0)
    static let green = Color(red: 0.23, green: 0.86, blue: 0.58)
    static let amber = Color(red: 1.0, green: 0.69, blue: 0.26)
    static let red = Color(red: 1.0, green: 0.34, blue: 0.40)
    static let purple = Color(red: 0.68, green: 0.48, blue: 1.0)
    static let navigationBackground = Color(red: 0.045, green: 0.061, blue: 0.082)
    static let navigationInactive = Color(red: 0.60, green: 0.65, blue: 0.72)
    static let navigationDivider = Color.white.opacity(0.14)
    static func tint(_ name: String) -> Color {
        switch name { case "green": green; case "amber": amber; case "red": red; case "purple": purple; default: blue }
    }
}
