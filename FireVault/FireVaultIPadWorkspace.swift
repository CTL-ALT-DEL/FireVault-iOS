//
//  FireVaultIPadWorkspace.swift
//  FireVault
//
//  Landscape-first iPad workspace introduced in Build 1.08.07.
//

import MapKit
import SwiftUI

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
                    .foregroundStyle(.secondary.opacity(0.72))
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
                    .foregroundStyle(
                        tab == .trip && breadcrumbs.isRecording
                            ? NativeShellPalette.green
                            : (selected ? .white : NativeShellPalette.navigationInactive)
                    )
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
                FireVaultIPadAccountWorkspace(
                    account: account,
                    store: store,
                    closeTab: .nearby,
                    showsCloseButton: true
                )
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

        case .trip:
            FireVaultIPadBreadcrumbsView(
                breadcrumbs: breadcrumbs,
                store: store,
                technicianName: settings.preferences.technician.name,
                companyName: settings.preferences.technician.company,
                includeCoordinatesInReports: settings.gps.includeCoordinatesInReports
            )

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
        if !payload.demoMode, let current = locationService.coordinate {
            coordinates.append(current)
        }

        guard let first = coordinates.first else {
            return .init(
                center: .init(latitude: 43.615, longitude: -116.202),
                span: .init(latitudeDelta: 0.18, longitudeDelta: 0.18)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? first.latitude
        let maximumLatitude = latitudes.max() ?? first.latitude
        let minimumLongitude = longitudes.min() ?? first.longitude
        let maximumLongitude = longitudes.max() ?? first.longitude

        return .init(
            center: .init(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: .init(
                latitudeDelta: max(0.018, (maximumLatitude - minimumLatitude) * 1.5),
                longitudeDelta: max(0.018, (maximumLongitude - minimumLongitude) * 1.5)
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let panelWidth = max(330, min(390, geometry.size.width * 0.32))
            let availableMapWidth = max(420, geometry.size.width - panelWidth - 46)
            let availableMapHeight = max(420, geometry.size.height - 86)
            let mapSide = min(availableMapWidth, availableMapHeight)

            VStack(spacing: 12) {
                header

                HStack(alignment: .top, spacing: 14) {
                    mapPanel
                        .frame(width: mapSide, height: mapSide)
                        .layoutPriority(2)

                    accountPanel
                        .frame(width: panelWidth, height: mapSide)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
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
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("NEARBY FIELD MAP")
                    .font(.caption2.bold())
                    .tracking(1.3)
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)

                Text("Large hybrid map with the closest accounts beside it")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            Spacer()

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
                    if !payload.demoMode, let current = locationService.coordinate {
                        Annotation("Your Location", coordinate: current) {
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
                .mapStyle(.hybrid(elevation: .realistic))
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
                .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .padding(14)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityIdentifier("ipad-nearby-square-map")
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
        .background(NativeShellPalette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: 950,
                    heading: 0,
                    pitch: 52
                )
            )
        }
    }

    private func resetMapSelection() {
        selectedID = nearbyRows.first?.id
        let latitudeDistance = overviewRegion.span.latitudeDelta * 111_000
        let longitudeDistance = overviewRegion.span.longitudeDelta * 85_000
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: overviewRegion.center,
                distance: max(1_600, max(latitudeDistance, longitudeDistance) * 1.8),
                heading: 0,
                pitch: 42
            )
        )
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
    private let plusCodeSearchIsEnabled = FireVaultNativeSettingsStore().preferences.plusCodes.searchable

    private var accounts: [FireVaultNativeAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? payload.accounts
            : payload.accounts.filter { account in
                let locationCodes = plusCodeSearchIsEnabled
                    ? store.accounts.first(where: { $0.id == account.id })?.locations.map(\.plusCode).joined(separator: " ") ?? ""
                    : ""
                return [account.name, account.address, account.accountId, account.category, locationCodes]
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
                .frame(width: 340)

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

                Button {
                    store.addAccount()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.glassProminent)
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
                            .foregroundStyle(.secondary.opacity(0.72))
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(selected ? NativeShellPalette.blue : .secondary)
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
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var accountDetail: some View {
        if let account = store.selectedAccount {
            FireVaultIPadAccountWorkspace(
                account: account,
                store: store,
                closeTab: .accounts,
                showsCloseButton: false
            )
        } else {
            ZStack {
                NativeShellPalette.background.ignoresSafeArea()
                ContentUnavailableView(
                    "Select an Account",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Choose an account to show its map, saved pin locations, notes, files, and equipment beside the directory.")
                )
                .frame(maxWidth: 520)
            }
        }
    }
}

private struct FireVaultIPadAccountWorkspace: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    let closeTab: FireVaultShellTab
    let showsCloseButton: Bool

    private var validLocations: [FireVaultWorkspaceLocation] {
        account.locations.filter { $0.coordinate != nil }
    }

    private var mapRegion: MKCoordinateRegion {
        let coordinates = [account.coordinate].compactMap { $0 } + validLocations.compactMap(\.coordinate)
        guard let first = coordinates.first else {
            return .init(
                center: .init(latitude: 39.5, longitude: -98.35),
                span: .init(latitudeDelta: 35, longitudeDelta: 35)
            )
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? first.latitude
        let maximumLatitude = latitudes.max() ?? first.latitude
        let minimumLongitude = longitudes.min() ?? first.longitude
        let maximumLongitude = longitudes.max() ?? first.longitude

        return .init(
            center: .init(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: .init(
                latitudeDelta: max(0.005, (maximumLatitude - minimumLatitude) * 1.8),
                longitudeDelta: max(0.005, (maximumLongitude - minimumLongitude) * 1.8)
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let mapColumn = max(330, min(460, geometry.size.width * 0.46))
            let mapSide = min(mapColumn - 28, max(300, geometry.size.height * 0.57))

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if showsCloseButton {
                            Button("Back", systemImage: "chevron.left") {
                                store.closeAccount(to: closeTab)
                            }
                            .buttonStyle(.glass)
                        }

                        Spacer()

                        Button {
                            store.toggleFavorite(account.id)
                        } label: {
                            Image(systemName: account.favorite ? "star.fill" : "star")
                                .foregroundStyle(account.favorite ? NativeShellPalette.amber : .white)
                        }
                        .buttonStyle(.glass)
                    }

                    locationMap
                        .frame(width: mapSide, height: mapSide)
                        .frame(maxWidth: .infinity)

                    HStack {
                        Text("SAVED PIN LOCATIONS")
                            .font(.caption.bold())
                            .tracking(1.1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Add", systemImage: "plus") {
                            store.addLocation(to: account.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if account.locations.isEmpty {
                        ContentUnavailableView(
                            "No Saved Locations",
                            systemImage: "mappin.slash",
                            description: Text("Add parking, entrance, panel, riser, or other exact field points.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(account.locations) { location in
                                    locationRow(location)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(14)
                .frame(width: mapColumn, maxHeight: .infinity, alignment: .top)
                .background(NativeShellPalette.navigationBackground.opacity(0.72))

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        accountIdentity
                        quickActions
                        equipmentSection
                        notesSection
                        documentsSection
                        recentSection
                    }
                    .padding(.trailing, 16)
                    .padding(.vertical, 16)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(NativeShellPalette.background)
        .accessibilityIdentifier("ipad-account-workspace")
    }

    private var locationMap: some View {
        Map(initialPosition: .region(mapRegion), interactionModes: [.pan, .zoom, .rotate]) {
            if let coordinate = account.coordinate {
                Marker(account.name, systemImage: "shield.fill", coordinate: coordinate)
                    .tint(NativeShellPalette.red)
            }

            ForEach(validLocations) { location in
                if let coordinate = location.coordinate {
                    Marker(location.label, systemImage: "mappin", coordinate: coordinate)
                        .tint(NativeShellPalette.purple)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityIdentifier("ipad-account-hybrid-location-map")
    }

    private func locationRow(_ location: FireVaultWorkspaceLocation) -> some View {
        Button {
            guard let coordinate = location.coordinate else { return }
            let item = MKMapItem(
                location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                address: nil
            )
            item.name = location.label
            item.openInMaps(
                launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(NativeShellPalette.purple)

                VStack(alignment: .leading, spacing: 3) {
                    Text(location.label)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text([location.subtitle, location.plusCode].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if location.coordinate != nil {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .foregroundStyle(NativeShellPalette.blue)
                }
            }
            .padding(11)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(location.coordinate == nil)
    }

    private var accountIdentity: some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    if !account.category.isEmpty {
                        Text(account.category.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(NativeShellPalette.blue)
                    }
                    if !account.accountId.isEmpty {
                        Text(account.accountId)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(account.name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                Label(account.address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button("Note", systemImage: "square.and.pencil") {
                store.addNote(to: account.id)
            }
            .buttonStyle(.borderedProminent)

            Button("Scan", systemImage: "doc.viewfinder") {
                store.addDocument(to: account.id, scan: true)
            }
            .buttonStyle(.bordered)

            Button("Photo", systemImage: "camera.fill") {
                store.closeAccount(to: .photo)
            }
            .buttonStyle(.bordered)

            Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                store.openRoute(for: account)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var equipmentSection: some View {
        if !account.equipment.isEmpty {
            accountSection(title: "EQUIPMENT", symbol: "wrench.and.screwdriver") {
                ForEach(account.equipment.prefix(8)) { equipment in
                    LabeledContent(equipment.title, value: equipment.subtitle)
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if !account.notes.isEmpty {
            accountSection(title: "FIELD NOTES", symbol: "note.text") {
                ForEach(account.notes.prefix(6)) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(NativeShellPalette.amber)
                        Text(note.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var documentsSection: some View {
        if !account.documents.isEmpty {
            accountSection(title: "FILES & SCANS", symbol: "doc.viewfinder") {
                ForEach(account.documents.prefix(6)) { document in
                    LabeledContent(document.title, value: document.subtitle)
                        .font(.subheadline)
                }
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !account.recent.isEmpty {
            accountSection(title: "RECENT ACTIVITY", symbol: "clock.arrow.circlepath") {
                ForEach(account.recent.prefix(6)) { item in
                    LabeledContent(item.title, value: item.date)
                        .font(.subheadline)
                }
            }
        }
    }

    private func accountSection<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(NativeShellPalette.blue)
                content()
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
