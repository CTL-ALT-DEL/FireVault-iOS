//
//  FireVaultIPadWorkspaceV3.swift
//  FireVault
//
//  Build 1.08.07 refinements for focused Accounts navigation and walking pin routes.
//

import MapKit
import SwiftUI

struct FireVaultIPadWorkspaceV3: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    var body: some View {
        ZStack {
            FireVaultIPadWorkspaceV2(
                payload: payload,
                store: store,
                settings: settings,
                locationService: locationService,
                breadcrumbs: breadcrumbs
            )

            if store.selectedTab == .accounts {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: 219)
                        .allowsHitTesting(false)

                    FireVaultIPadAccountsWorkspaceV3(
                        payload: payload,
                        store: store
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.selectedTab)
        .accessibilityIdentifier("ipad-adaptive-workspace-v3")
    }
}

private enum FireVaultIPadAccountSortV3: String, CaseIterable, Identifiable {
    case alphabetic = "A–Z"
    case favorites = "Favorites"
    case recent = "Recent"

    var id: String { rawValue }
}

private struct FireVaultIPadAccountsWorkspaceV3: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore

    @State private var searchText = ""
    @State private var sort: FireVaultIPadAccountSortV3 = .alphabetic

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
        Group {
            if let account = store.selectedAccount {
                FireVaultIPadPinLocationsViewV3(
                    account: account,
                    store: store
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                accountList
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: store.selectedAccountID)
        .background(NativeShellPalette.background)
        .accessibilityIdentifier("ipad-account-list-navigation-v3")
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACCOUNT LIST")
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
                        ForEach(FireVaultIPadAccountSortV3.allCases) { option in
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
            .padding(18)

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
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)

            if accounts.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(accounts) { account in
                            accountRow(account)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeShellPalette.background)
    }

    private func accountRow(_ account: FireVaultNativeAccount) -> some View {
        Button {
            store.openAccount(account.id)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: account.favorite ? "star.fill" : "building.2")
                    .foregroundStyle(account.favorite ? NativeShellPalette.amber : NativeShellPalette.blue)
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(NativeShellPalette.surface, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(account.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        if !account.accountId.isEmpty {
                            Label(account.accountId, systemImage: "number")
                        }
                        if !account.category.isEmpty {
                            Label(account.category, systemImage: "tag.fill")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.name), \(account.address)")
        .accessibilityHint("Opens pin locations and account details")
    }
}

private struct FireVaultIPadPinLocationsViewV3: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var focusedLocationID: String?

    private var validLocations: [FireVaultWorkspaceLocation] {
        account.locations.filter { $0.coordinate != nil }
    }

    private var mapRegion: MKCoordinateRegion {
        let coordinates = [account.coordinate].compactMap { $0 } + validLocations.compactMap(\.coordinate)
        return FireVaultIPadMapRegionV2.region(for: coordinates, fallbackDelta: 0.006)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            GeometryReader { geometry in
                let locationWidth = max(400, min(560, geometry.size.width * 0.52))
                let mapSide = min(locationWidth - 32, max(330, geometry.size.height * 0.60))

                HStack(alignment: .top, spacing: 16) {
                    locationsColumn(mapSide: mapSide)
                        .frame(width: locationWidth)
                        .frame(maxHeight: .infinity, alignment: .top)

                    detailsColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(NativeShellPalette.background)
        .task(id: account.id) {
            focusedLocationID = nil
            cameraPosition = .region(mapRegion)
        }
        .accessibilityIdentifier("ipad-account-pin-locations-v3")
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button("Account List", systemImage: "chevron.left") {
                store.closeAccount(to: .accounts)
            }
            .buttonStyle(.glass)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("PIN LOCATIONS & DETAILS")
                    .font(.caption2.bold())
                    .tracking(1.15)
                    .foregroundStyle(NativeShellPalette.blue)
            }

            Spacer()

            Button {
                store.toggleFavorite(account.id)
            } label: {
                Label(
                    account.favorite ? "Favorite" : "Add Favorite",
                    systemImage: account.favorite ? "star.fill" : "star"
                )
            }
            .buttonStyle(.glass)
        }
        .padding(16)
    }

    private func locationsColumn(mapSide: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    description: Text("Add parking, entrance, panel, riser, or another exact field point.")
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
        .background(
            NativeShellPalette.navigationBackground.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var locationMap: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
            if let coordinate = account.coordinate {
                Marker(account.name, systemImage: "shield.fill", coordinate: coordinate)
                    .tint(NativeShellPalette.red)
            }

            ForEach(validLocations) { location in
                if let coordinate = location.coordinate {
                    Marker(location.label, systemImage: "mappin", coordinate: coordinate)
                        .tint(
                            focusedLocationID == location.id
                                ? NativeShellPalette.green
                                : NativeShellPalette.purple
                        )
                }
            }
        }
        .id(account.id)
        .mapStyle(.hybrid(elevation: .realistic))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityIdentifier("ipad-account-hybrid-walking-map")
    }

    private var detailsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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

                NativeShellCard {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("ACCOUNT DETAILS", systemImage: "info.circle.fill")
                            .font(.caption.bold())
                            .tracking(1.1)
                            .foregroundStyle(NativeShellPalette.blue)

                        detailRow("Account ID", value: account.accountId.isEmpty ? "Not entered" : account.accountId)
                        Divider()
                        detailRow("Category", value: account.category.isEmpty ? "Not entered" : account.category)
                        Divider()
                        detailRow("Phone", value: account.phone.isEmpty ? "Not entered" : account.phone)
                        Divider()
                        detailRow("Saved Locations", value: "\(account.locations.count)")
                        detailRow("Equipment", value: "\(account.equipment.count)")
                        detailRow("Notes", value: "\(account.notes.count)")
                        detailRow("Files & Scans", value: "\(account.documents.count)")
                    }
                }

                NativeShellCard {
                    HStack(spacing: 10) {
                        Button("Drive to Account", systemImage: "car.fill") {
                            store.openRoute(for: account)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Call", systemImage: "phone.fill") {
                            store.call(account.phone)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!account.phone.contains(where: \.isNumber))
                    }
                }
            }
            .padding(.trailing, 2)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.subheadline)
    }

    private func locationRow(_ location: FireVaultWorkspaceLocation) -> some View {
        HStack(spacing: 10) {
            Button {
                focusMap(on: location)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(
                            focusedLocationID == location.id
                                ? NativeShellPalette.green
                                : NativeShellPalette.purple
                        )

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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                openWalkingRoute(to: location)
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "figure.walk")
                        .font(.headline)
                    Text("Route")
                        .font(.caption2.bold())
                }
                .frame(width: 54, height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(location.coordinate == nil)
            .accessibilityLabel("Walking route to \(location.label)")
        }
        .padding(11)
        .background(
            focusedLocationID == location.id
                ? NativeShellPalette.blue.opacity(0.14)
                : NativeShellPalette.surface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    focusedLocationID == location.id
                        ? NativeShellPalette.blue.opacity(0.75)
                        : .white.opacity(0.06),
                    lineWidth: focusedLocationID == location.id ? 1.5 : 1
                )
        }
    }

    private func focusMap(on location: FireVaultWorkspaceLocation) {
        guard let coordinate = location.coordinate else { return }
        focusedLocationID = location.id
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: 180,
                    heading: 0,
                    pitch: 48
                )
            )
        }
    }

    private func openWalkingRoute(to location: FireVaultWorkspaceLocation) {
        guard let coordinate = location.coordinate else { return }
        focusMap(on: location)

        let mapItem = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        mapItem.name = location.label

        let walkingSpan = MKCoordinateSpan(
            latitudeDelta: 0.0025,
            longitudeDelta: 0.0025
        )
        let launchOptions: [String: Any] = [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking,
            MKLaunchOptionsMapTypeKey: NSNumber(value: MKMapType.hybrid.rawValue),
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: walkingSpan)
        ]

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            mapItem.openInMaps(launchOptions: launchOptions)
        }
    }
}
