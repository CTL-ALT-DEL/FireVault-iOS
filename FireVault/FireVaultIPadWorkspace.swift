//
//  FireVaultIPadWorkspace.swift
//  FireVault
//
//  Wide-window iPad workspace introduced in Build 1.08.07.
//

import SwiftUI
import MapKit

struct FireVaultIPadWorkspace: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 218)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NativeShellPalette.background)
        .tint(NativeShellPalette.blue)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("ipad-adaptive-workspace")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(payload.demoMode ? "DEMO WORKSPACE" : "FIELD WORKSPACE")
                    .font(.caption2.bold())
                    .tracking(1.35)
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)

                Text(payload.locationStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            VStack(spacing: 8) {
                ForEach(FireVaultShellTab.allCases) { tab in
                    sidebarButton(tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 8) {
                Label(
                    payload.demoMode ? "Sample data isolated" : "Live vault active",
                    systemImage: payload.demoMode ? "sparkles.rectangle.stack" : "lock.shield.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Text(FireVaultVersionInfo().displayText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(NativeShellPalette.navigationBackground)
    }

    private func sidebarButton(_ tab: FireVaultShellTab) -> some View {
        let selected = store.selectedTab == tab

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                store.closeAccount(to: tab)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolVariant(selected ? .fill : .none)
                    .frame(width: 26)

                Text(tab.title)
                    .font(.body.weight(selected ? .bold : .semibold))

                Spacer()

                if selected {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
            }
            .foregroundStyle(selected ? .white : NativeShellPalette.navigationInactive)
            .padding(.horizontal, 13)
            .frame(minHeight: 48)
            .background(
                selected ? NativeShellPalette.blue.opacity(0.18) : .clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NativeShellPalette.blue.opacity(0.72), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("ipad-navigation-\(tab.rawValue)")
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selectedTab {
        case .nearby:
            if let account = store.selectedAccount {
                FieldWorkspaceView(account: account, store: store)
            } else {
                FireVaultIPadNearbyWorkspace(
                    payload: payload,
                    store: store,
                    settings: settings,
                    locationService: locationService,
                    breadcrumbs: breadcrumbs
                )
            }

        case .accounts:
            FireVaultIPadAccountsWorkspace(payload: payload, store: store)

        case .photo, .settings:
            FireVaultIPadLegacyDetailHost(
                payload: payload,
                store: store,
                settings: settings,
                locationService: locationService,
                breadcrumbs: breadcrumbs
            )
        }
    }
}

private struct FireVaultIPadNearbyWorkspace: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    @State private var selectedID: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showsBreadcrumbs = false

    private var nearbyRows: [FireVaultNativeNearbyAccount] {
        let maximumMeters = settings.gps.nearbyRadiusMiles * 1_609.344
        return payload.nearby
            .filter { $0.distanceMeters <= maximumMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    private var selectedRow: FireVaultNativeNearbyAccount? {
        guard let selectedID else { return nil }
        return nearbyRows.first { $0.id == selectedID }
    }

    private var overviewRegion: MKCoordinateRegion {
        var coordinates = nearbyRows.compactMap(\.account.coordinate)
        if !payload.demoMode, let userCoordinate = locationService.coordinate {
            coordinates.append(userCoordinate)
        }

        guard let first = coordinates.first else {
            return .init(
                center: .init(latitude: 43.615, longitude: -116.202),
                span: .init(latitudeDelta: 0.18, longitudeDelta: 0.18)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? first.latitude
        let maxLatitude = latitudes.max() ?? first.latitude
        let minLongitude = longitudes.min() ?? first.longitude
        let maxLongitude = longitudes.max() ?? first.longitude

        return .init(
            center: .init(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: .init(
                latitudeDelta: max(0.02, (maxLatitude - minLatitude) * 1.45),
                longitudeDelta: max(0.02, (maxLongitude - minLongitude) * 1.45)
            )
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            HStack(spacing: 14) {
                mapPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(2)

                accountPanel
                    .frame(width: 360)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.top, 12)
        .background(NativeShellPalette.background)
        .task {
            resetMapSelection()
        }
        .onChange(of: settings.gps.nearbyRadiusMiles) { _, _ in
            resetMapSelection()
        }
        .onChange(of: store.nearbyResetRequestID) { _, _ in
            resetMapSelection()
        }
        .fullScreenCover(isPresented: $showsBreadcrumbs) {
            FireVaultBreadcrumbsView(
                breadcrumbs: breadcrumbs,
                store: store,
                technicianName: settings.preferences.technician.name,
                companyName: settings.preferences.technician.company,
                includeCoordinatesInReports: settings.gps.includeCoordinatesInReports
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("NEARBY FIELD MAP")
                    .font(.caption2.bold())
                    .tracking(1.3)
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)

                Text("Map and closest accounts stay visible together")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            Spacer()

            FireVaultBreadcrumbCompactBar(
                breadcrumbs: breadcrumbs,
                accounts: store.accounts,
                open: { showsBreadcrumbs = true }
            )
            .frame(maxWidth: 360)

            Menu {
                Picker("Nearby Radius", selection: radiusBinding) {
                    ForEach(FireVaultGPSPreferences.radiusOptions, id: \.self) { radius in
                        Text(FireVaultGPSPreferences.radiusLabel(radius))
                            .tag(radius)
                    }
                }
            } label: {
                Label(settings.gps.radiusStatus, systemImage: "scope")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 13)
                    .frame(minHeight: 44)
                    .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nearby radius")
            .accessibilityValue(settings.gps.radiusStatus)
        }
        .padding(.horizontal, 16)
    }

    private var radiusBinding: Binding<Double> {
        Binding(
            get: { settings.gps.nearbyRadiusMiles },
            set: { radius in
                var updated = settings.gps
                updated.nearbyRadiusMiles = radius
                settings.saveGPS(updated)
            }
        )
    }

    private var mapPanel: some View {
        ZStack(alignment: .topLeading) {
            if nearbyRows.isEmpty && locationService.coordinate == nil {
                ContentUnavailableView(
                    "No Mapped Accounts",
                    systemImage: "map",
                    description: Text("Map account addresses or increase the nearby radius to populate this workspace.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NativeShellPalette.surface)
            } else {
                Map(position: $cameraPosition) {
                    if !payload.demoMode, let userCoordinate = locationService.coordinate {
                        Annotation("Your Location", coordinate: userCoordinate) {
                            ZStack {
                                Circle()
                                    .fill(NativeShellPalette.blue.opacity(0.22))
                                    .frame(width: 42, height: 42)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 23, height: 23)
                                Circle()
                                    .fill(NativeShellPalette.blue)
                                    .frame(width: 15, height: 15)
                            }
                            .shadow(radius: 4)
                        }
                    }

                    ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
                        if let coordinate = row.account.coordinate {
                            Annotation(row.account.name, coordinate: coordinate) {
                                Button {
                                    select(row)
                                } label: {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(
                                            selectedID == row.id
                                                ? NativeShellPalette.red
                                                : NativeShellPalette.blue,
                                            in: Circle()
                                        )
                                        .overlay {
                                            Circle().stroke(.white.opacity(0.88), lineWidth: 2)
                                        }
                                        .shadow(radius: 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
            }

            if let selectedRow {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedRow.account.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(selectedRow.account.address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack {
                        Label(selectedRow.distanceLabel, systemImage: "location.fill")
                            .font(.caption.bold())
                            .foregroundStyle(NativeShellPalette.green)

                        Spacer()

                        Button("Open Account", systemImage: "arrow.up.right.square") {
                            store.openAccount(selectedRow.account.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .frame(maxWidth: 330, alignment: .leading)
                .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
                .padding(14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityIdentifier("ipad-nearby-map")
    }

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CLOSEST ACCOUNTS")
                        .font(.caption.bold())
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Text("\(nearbyRows.count) within \(settings.gps.radiusStatus)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.requestNearbyReset()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Refresh nearby accounts")
            }

            if nearbyRows.isEmpty {
                ContentUnavailableView(
                    "No Accounts in Range",
                    systemImage: "location.slash",
                    description: Text("Increase the radius or map more account addresses.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
                            nearbyCard(row, index: index)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .background(NativeShellPalette.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func nearbyCard(
        _ row: FireVaultNativeNearbyAccount,
        index: Int
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                select(row)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 27, height: 27)
                        .background(
                            selectedID == row.id ? NativeShellPalette.red : NativeShellPalette.blue,
                            in: Circle()
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.account.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(row.account.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Text(row.distanceLabel)
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(NativeShellPalette.green)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                store.openAccount(row.account.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .frame(width: 34, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Open \(row.account.name)")
        }
        .padding(11)
        .background(
            selectedID == row.id
                ? NativeShellPalette.blue.opacity(0.14)
                : .black.opacity(0.15),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    selectedID == row.id
                        ? NativeShellPalette.blue.opacity(0.8)
                        : .white.opacity(0.06),
                    lineWidth: selectedID == row.id ? 1.5 : 1
                )
        }
    }

    private func select(_ row: FireVaultNativeNearbyAccount) {
        selectedID = row.id
        store.selectCaptureAccount(row.account.id)

        guard let coordinate = row.account.coordinate else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(
                .init(
                    center: coordinate,
                    span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
        }
    }

    private func resetMapSelection() {
        selectedID = nearbyRows.first?.id
        cameraPosition = .region(overviewRegion)
    }
}

private enum FireVaultIPadAccountSort: String, CaseIterable, Identifiable {
    case alphabetic = "A–Z"
    case favorites = "Favorites"
    case recent = "Recent"

    var id: String { rawValue }
}

private struct FireVaultIPadAccountsWorkspace: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore

    @State private var searchText = ""
    @State private var sort: FireVaultIPadAccountSort = .alphabetic

    private var accounts: [FireVaultNativeAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? payload.accounts
            : payload.accounts.filter {
                [$0.name, $0.address, $0.accountId, $0.category]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }

        switch sort {
        case .alphabetic:
            return filtered.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .favorites:
            return filtered.sorted {
                if $0.favorite != $1.favorite { return $0.favorite && !$1.favorite }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .recent:
            return filtered.sorted { $0.recentText > $1.recentText }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            directory
                .frame(width: 360)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)

            accountDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NativeShellPalette.background)
        .accessibilityIdentifier("ipad-account-master-detail")
    }

    private var directory: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACCOUNT DIRECTORY")
                        .font(.caption2.bold())
                        .tracking(1.25)
                        .foregroundStyle(NativeShellPalette.blue)
                    Text("\(accounts.count) accounts")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }

                Spacer()

                Menu {
                    Picker("Sort Accounts", selection: $sort) {
                        ForEach(FireVaultIPadAccountSort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Sort accounts")

                Button {
                    store.addAccount()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("Add account")
            }
            .padding(16)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Name, address, ID, or category", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear account search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            if accounts.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(accounts) { account in
                            directoryRow(account)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(NativeShellPalette.navigationBackground.opacity(0.72))
    }

    private func directoryRow(_ account: FireVaultNativeAccount) -> some View {
        let selected = store.selectedAccountID == account.id

        return Button {
            store.openAccount(account.id)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: account.favorite ? "star.fill" : "building.2")
                    .foregroundStyle(account.favorite ? NativeShellPalette.amber : NativeShellPalette.blue)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(account.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !account.accountId.isEmpty {
                        Text(account.accountId)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(selected ? NativeShellPalette.blue : .tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? NativeShellPalette.blue.opacity(0.16) : NativeShellPalette.surface,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        selected ? NativeShellPalette.blue.opacity(0.78) : .white.opacity(0.06),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.name), \(account.address)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var accountDetail: some View {
        if let account = store.selectedAccount {
            FieldWorkspaceView(account: account, store: store)
        } else {
            ZStack {
                NativeShellPalette.background.ignoresSafeArea()

                ContentUnavailableView(
                    "Select an Account",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Choose an account from the directory to keep the list visible while working with its notes, files, equipment, and saved locations.")
                )
                .frame(maxWidth: 520)
            }
        }
    }
}

private struct FireVaultIPadLegacyDetailHost: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    var body: some View {
        GeometryReader { geometry in
            NativeAppShellView(
                payload: payload,
                store: store,
                settings: settings,
                locationService: locationService,
                breadcrumbs: breadcrumbs
            )
            // The iPad sidebar owns navigation. Extending the legacy detail below
            // the visible viewport places its phone tab bar outside the clipping area.
            .frame(
                width: geometry.size.width,
                height: geometry.size.height + 76,
                alignment: .top
            )
        }
        .clipped()
        .background(NativeShellPalette.background)
        .accessibilityIdentifier("ipad-adapted-detail-host")
    }
}
