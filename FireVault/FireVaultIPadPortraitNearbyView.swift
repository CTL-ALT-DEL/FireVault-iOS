//
//  FireVaultIPadPortraitNearbyView.swift
//  FireVault
//
//  iPhone-style Nearby screen for iPad portrait with a square map.
//

import MapKit
import SwiftUI

struct FireVaultIPadPortraitNearbyView: View {
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
        if !payload.demoMode, let coordinate = locationService.coordinate {
            coordinates.append(coordinate)
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
                latitudeDelta: max(0.018, (maximumLatitude - minimumLatitude) * 1.6),
                longitudeDelta: max(0.018, (maximumLongitude - minimumLongitude) * 1.6)
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    statusHeader

                    FireVaultBreadcrumbCompactBar(
                        breadcrumbs: breadcrumbs,
                        accounts: store.accounts,
                        open: { showsBreadcrumbs = true }
                    )

                    squareMap
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity)

                    accountList
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            bottomNavigation
        }
        .background(NativeShellPalette.background)
        .task { resetMap() }
        .onChange(of: settings.gps.nearbyRadiusMiles) { _, _ in resetMap() }
        .onChange(of: store.nearbyResetRequestID) { _, _ in resetMap() }
        .fullScreenCover(isPresented: $showsBreadcrumbs) {
            FireVaultTripLogPortraitView(
                breadcrumbs: breadcrumbs,
                store: store,
                technicianName: settings.preferences.technician.name,
                companyName: settings.preferences.technician.company,
                includeCoordinatesInReports: settings.gps.includeCoordinatesInReports
            )
        }
        .accessibilityIdentifier("ipad-portrait-nearby-square-map-screen")
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(payload.demoMode ? "DEMO VAULT" : "FIELD VAULT")
                    .font(.caption2.bold())
                    .tracking(1.2)
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)

                Text(payload.locationStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
            }
            .buttonStyle(.bordered)
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

    private var squareMap: some View {
        ZStack(alignment: .topLeading) {
            if nearbyRows.isEmpty && locationService.coordinate == nil {
                ContentUnavailableView(
                    "No Mapped Accounts",
                    systemImage: "map",
                    description: Text("Map account addresses or increase the nearby radius.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NativeShellPalette.surface)
            } else {
                Map(position: $cameraPosition) {
                    if !payload.demoMode, let coordinate = locationService.coordinate {
                        Annotation("Your Location", coordinate: coordinate) {
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
                                            selectedID == row.id ? NativeShellPalette.red : NativeShellPalette.blue,
                                            in: Circle()
                                        )
                                        .overlay { Circle().stroke(.white.opacity(0.88), lineWidth: 2) }
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
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedRow.account.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(selectedRow.account.address)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                    HStack {
                        Text(selectedRow.distanceLabel)
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(NativeShellPalette.green)
                        Spacer()
                        Button("Open", systemImage: "arrow.up.right.square") {
                            store.openAccount(selectedRow.account.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .frame(maxWidth: 330, alignment: .leading)
                .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityIdentifier("ipad-portrait-nearby-square-map")
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("NEARBY ACCOUNTS")
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(nearbyRows.count)")
                    .foregroundStyle(.secondary)
            }

            if nearbyRows.isEmpty {
                ContentUnavailableView(
                    "No Accounts in Range",
                    systemImage: "location.slash",
                    description: Text("Increase the radius or map more accounts.")
                )
                .frame(minHeight: 180)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
                        accountRow(row, index: index)
                    }
                }
            }
        }
    }

    private func accountRow(_ row: FireVaultNativeNearbyAccount, index: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                select(row)
            } label: {
                HStack(spacing: 11) {
                    Text("\(index + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(
                            selectedID == row.id ? NativeShellPalette.red : NativeShellPalette.blue,
                            in: Circle()
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.account.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(row.account.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(row.distanceLabel)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(NativeShellPalette.green)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                store.openAccount(row.account.id)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 38, height: 44)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            selectedID == row.id ? NativeShellPalette.blue.opacity(0.14) : NativeShellPalette.surface,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    selectedID == row.id ? NativeShellPalette.blue.opacity(0.8) : .white.opacity(0.07),
                    lineWidth: selectedID == row.id ? 1.5 : 1
                )
        }
    }

    private var bottomNavigation: some View {
        HStack(spacing: 0) {
            ForEach(FireVaultShellTab.allCases) { tab in
                let selected = tab == .nearby
                Button {
                    if tab == .nearby {
                        store.requestNearbyReset()
                    }
                    withAnimation(.snappy(duration: 0.25)) {
                        store.selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: selected ? .bold : .semibold))
                            .symbolVariant(selected ? .fill : .none)
                        Text(tab.title)
                            .font(.caption2.weight(selected ? .bold : .semibold))
                    }
                    .foregroundStyle(selected ? NativeShellPalette.blue : NativeShellPalette.navigationInactive)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                    pitch: 48
                )
            )
        }
    }

    private func resetMap() {
        selectedID = nearbyRows.first?.id
        let latitudeDistance = overviewRegion.span.latitudeDelta * 111_000
        let longitudeDistance = overviewRegion.span.longitudeDelta * 85_000
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: overviewRegion.center,
                distance: max(1_600, max(latitudeDistance, longitudeDistance) * 1.8),
                heading: 0,
                pitch: 38
            )
        )
    }
}
