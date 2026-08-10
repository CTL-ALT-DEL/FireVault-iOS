//
//  FireVaultIPadAccountsWorkspaceV2.swift
//  FireVault
//
//  Focused account-list navigation and locations/details workspace.
//

import MapKit
import SwiftUI

private enum FireVaultIPadAccountSortV2: String, CaseIterable, Identifiable {
    case alphabetic = "A–Z"
    case favorites = "Favorites"
    case recent = "Recent"

    var id: String { rawValue }
}

struct FireVaultIPadAccountsWorkspaceV2: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore

    @State private var searchText = ""
    @State private var sort: FireVaultIPadAccountSortV2 = .alphabetic

    private var favoriteCount: Int { payload.accounts.filter(\.favorite).count }
    private var mappedCount: Int { payload.accounts.filter { $0.coordinate != nil }.count }

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
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
                FireVaultIPadAccountLocationsDetailsViewV2(
                    account: account,
                    store: store,
                    returnTab: .accounts,
                    returnTitle: "Account List"
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                accountList
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: store.selectedAccountID)
        .background(NativeShellPalette.background)
        .accessibilityIdentifier("ipad-account-list-navigation")
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACCOUNT DIRECTORY")
                        .font(.caption2.bold())
                        .tracking(1.25)
                        .foregroundStyle(NativeShellPalette.blue)
                    Text(searchText.isEmpty ? "All Accounts" : "Search Results")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                directoryMetric("TOTAL", value: payload.accounts.count, symbol: "building.2.fill", tint: NativeShellPalette.blue)
                directoryMetric("FAVORITES", value: favoriteCount, symbol: "star.fill", tint: NativeShellPalette.amber)
                directoryMetric("MAPPED", value: mappedCount, symbol: "map.fill", tint: NativeShellPalette.green)

                Menu {
                    Picker("Sort Accounts", selection: $sort) {
                        ForEach(FireVaultIPadAccountSortV2.allCases) { option in
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
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)

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
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)

            if accounts.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 14, alignment: .top),
                            GridItem(.flexible(), spacing: 14, alignment: .top)
                        ],
                        alignment: .center,
                        spacing: 14
                    ) {
                        ForEach(accounts) { account in
                            accountRow(account)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    store.reloadAccounts()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeShellPalette.background)
    }

    private func directoryMetric(_ title: String, value: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline.bold().monospacedDigit())
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
    }

    private func accountRow(_ account: FireVaultNativeAccount) -> some View {
        Button {
            store.openAccount(account.id)
        } label: {
            HStack(spacing: 15) {
                Image(systemName: account.favorite ? "star.fill" : "building.2")
                    .foregroundStyle(account.favorite ? NativeShellPalette.amber : NativeShellPalette.blue)
                    .font(.title3.bold())
                    .frame(width: 48, height: 48)
                    .background(
                        (account.favorite ? NativeShellPalette.amber : NativeShellPalette.blue).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(account.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        if !account.accountId.isEmpty {
                            Label(account.accountId, systemImage: "number")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(NativeShellPalette.blue.opacity(0.08), in: Capsule())
                        }
                        if !account.category.isEmpty {
                            Label(account.category, systemImage: "tag.fill")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(NativeShellPalette.amber.opacity(0.08), in: Capsule())
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 132)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(NativeShellPalette.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.13), radius: 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.name), \(account.address)")
        .accessibilityHint("Opens locations and account details")
    }
}

struct FireVaultIPadAccountLocationsDetailsViewV2: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    let returnTab: FireVaultShellTab
    let returnTitle: String

    @State private var cameraPosition: MapCameraPosition = .automatic

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
            cameraPosition = .region(mapRegion)
        }
        .accessibilityIdentifier("ipad-account-locations-details")
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(returnTitle, systemImage: "chevron.left") {
                store.closeAccount(to: returnTab)
            }
            .buttonStyle(.glass)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("LOCATIONS & DETAILS")
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
        .background(NativeShellPalette.navigationBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                        .tint(NativeShellPalette.purple)
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
        .accessibilityIdentifier("ipad-account-hybrid-location-map")
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
                        Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
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
}
