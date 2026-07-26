//
//  FireVaultIPadPortraitNearbyViewV2.swift
//  FireVault
//
//  iPad portrait Nearby screen with a fixed map and snapping account list.
//

import MapKit
import SwiftUI
import UIKit

private enum FireVaultNearbyMapLayer: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case hybrid = "Hybrid"
    case imagery = "Satellite"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .hybrid: "map.fill"
        case .imagery: "globe.americas.fill"
        }
    }
}

struct FireVaultIPadPortraitNearbyViewV2: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    @State private var selectedID: String?
    @State private var scrollingID: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showsBreadcrumbs = false
    @State private var mapLayer: FireVaultNearbyMapLayer = .standard
    @State private var zoomLevel = 0.72
    @State private var showsZoomSlider = false
    @State private var zoomVisibilityToken = UUID()

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
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 32)
            let availableHeight = max(0, geometry.size.height)
            let mapSide = min(availableWidth, max(300, availableHeight * 0.50))

            VStack(spacing: 8) {
                statusHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                FireVaultBreadcrumbCompactBar(
                    breadcrumbs: breadcrumbs,
                    accounts: store.accounts,
                    open: { showsBreadcrumbs = true }
                )
                .padding(.horizontal, 16)

                squareMap
                    .frame(width: mapSide, height: mapSide)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)

                accountList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)

                bottomNavigation
            }
        }
        .background(NativeShellPalette.background)
        .task { resetMap() }
        .onChange(of: settings.gps.nearbyRadiusMiles) { _, _ in resetMap() }
        .onChange(of: store.nearbyResetRequestID) { _, _ in resetMap() }
        .onChange(of: scrollingID) { _, newID in
            guard let newID, let row = nearbyRows.first(where: { $0.id == newID }) else { return }
            select(row, haptic: true, updateScrollPosition: false)
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
        .accessibilityIdentifier("ipad-portrait-nearby-fixed-map")
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
                        Text(FireVaultGPSPreferences.radiusLabel(radius)).tag(radius)
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
                styledMap
            }

            if let selectedRow {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedRow.account.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(selectedRow.account.address)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                    Text(selectedRow.distanceLabel)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(NativeShellPalette.green)
                }
                .padding(11)
                .frame(maxWidth: 330, alignment: .leading)
                .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(12)
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 7) {
                Menu {
                    Picker("Map Layer", selection: $mapLayer) {
                        ForEach(FireVaultNearbyMapLayer.allCases) { layer in
                            Label(layer.rawValue, systemImage: layer.symbol).tag(layer)
                        }
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d.top.filled")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.black.opacity(0.78), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Map layers")

                if showsZoomSlider {
                    Slider(value: $zoomLevel, in: 0...1, step: 0.02)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 92, height: 30)
                        .onChange(of: zoomLevel) { _, _ in
                            applyZoom()
                            revealZoomSlider()
                        }
                        .padding(.vertical, 31)
                        .background(.black.opacity(0.72), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: UnitPoint.top)))
                        .accessibilityLabel("Map zoom")
                }
            }
            .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            if let selectedRow {
                HStack(spacing: 10) {
                    mapAction(symbol: "note.text", label: "Open account details") {
                        store.openAccount(selectedRow.account.id)
                    }
                    mapAction(
                        symbol: "phone.fill",
                        label: "Call account",
                        disabled: !selectedRow.account.phone.contains(where: \.isNumber),
                        tint: NativeShellPalette.green
                    ) {
                        store.call(selectedRow.account.phone)
                    }
                    mapAction(
                        symbol: "arrow.triangle.turn.up.right.diamond.fill",
                        label: "Route to account",
                        disabled: selectedRow.account.coordinate == nil
                    ) {
                        if let account = store.accounts.first(where: { $0.id == selectedRow.account.id }) {
                            store.openRoute(for: account)
                        }
                    }
                }
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

    @ViewBuilder
    private var styledMap: some View {
        switch mapLayer {
        case .standard:
            baseMap.mapStyle(.standard(elevation: .realistic))
        case .hybrid:
            baseMap.mapStyle(.hybrid(elevation: .realistic))
        case .imagery:
            baseMap.mapStyle(.imagery(elevation: .realistic))
        }
    }

    private var baseMap: some View {
        Map(position: $cameraPosition) {
            if !payload.demoMode, let coordinate = locationService.coordinate {
                Annotation("Your Location", coordinate: coordinate) {
                    ZStack {
                        Circle().fill(NativeShellPalette.blue.opacity(0.22)).frame(width: 42, height: 42)
                        Circle().fill(.white).frame(width: 23, height: 23)
                        Circle().fill(NativeShellPalette.blue).frame(width: 15, height: 15)
                    }
                    .shadow(radius: 4)
                }
            }
            ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
                if let coordinate = row.account.coordinate {
                    Annotation(row.account.name, coordinate: coordinate) {
                        Button {
                            select(row, haptic: false, updateScrollPosition: true)
                        } label: {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(selectedID == row.id ? NativeShellPalette.red : NativeShellPalette.blue, in: Circle())
                                .overlay { Circle().stroke(.white.opacity(0.88), lineWidth: 2) }
                                .shadow(radius: 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded { revealZoomSlider() })
    }

    private func mapAction(
        symbol: String,
        label: String,
        disabled: Bool = false,
        tint: Color = .black,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background((disabled ? Color.black.opacity(0.45) : tint.opacity(tint == .black ? 0.80 : 1)), in: Circle())
                .overlay { Circle().stroke(.white.opacity(disabled ? 0.28 : 0.72), lineWidth: 1.5) }
                .shadow(color: .black.opacity(0.55), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("NEARBY ACCOUNTS")
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(nearbyRows.count)").foregroundStyle(.secondary)
            }

            if nearbyRows.isEmpty {
                ContentUnavailableView(
                    "No Accounts in Range",
                    systemImage: "location.slash",
                    description: Text("Increase the radius or map more accounts.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { listGeometry in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
                                accountRow(row, index: index)
                                    .id(row.id)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.bottom, max(0, listGeometry.size.height - 68))
                    }
                    .scrollIndicators(.hidden)
                    .scrollPosition(id: $scrollingID, anchor: UnitPoint.top)
                    .scrollTargetBehavior(.viewAligned)
                }
            }
        }
    }

    private func accountRow(_ row: FireVaultNativeNearbyAccount, index: Int) -> some View {
        let isSelected = selectedID == row.id

        return Button {
            select(row, haptic: true, updateScrollPosition: true)
        } label: {
            HStack(spacing: 11) {
                Text("\(index + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? NativeShellPalette.red : NativeShellPalette.blue, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.account.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                    Text(row.account.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(row.distanceLabel)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(NativeShellPalette.green)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(isSelected ? NativeShellPalette.blue.opacity(0.18) : NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? NativeShellPalette.blue.opacity(0.9) : .white.opacity(0.07), lineWidth: isSelected ? 1.7 : 1)
            }
            .opacity(selectedID == nil || isSelected ? 1 : 0.38)
            .animation(.easeOut(duration: 0.18), value: selectedID)
        }
        .buttonStyle(.plain)
    }

    private var bottomNavigation: some View {
        HStack(spacing: 0) {
            ForEach(FireVaultShellTab.allCases) { tab in
                let selected = tab == .nearby
                Button {
                    if tab == .nearby { store.requestNearbyReset() }
                    withAnimation(.snappy(duration: 0.25)) { store.selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: selected ? .bold : .semibold))
                            .symbolVariant(selected ? .fill : .none)
                        Text(tab.title).font(.caption2.weight(selected ? .bold : .semibold))
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
        .overlay(alignment: UnitPoint.top) {
            Rectangle().fill(NativeShellPalette.navigationDivider).frame(height: 1)
        }
    }

    private func select(
        _ row: FireVaultNativeNearbyAccount,
        haptic: Bool,
        updateScrollPosition: Bool
    ) {
        guard selectedID != row.id else {
            if updateScrollPosition { scrollingID = row.id }
            return
        }
        selectedID = row.id
        if updateScrollPosition { scrollingID = row.id }
        store.selectCaptureAccount(row.account.id)
        zoomLevel = 0.72
        if haptic, settings.gps.hapticsAreEnabled {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        applyZoom()
    }

    private func applyZoom() {
        let center = selectedRow?.account.coordinate ?? overviewRegion.center
        let minimumDistance = 500.0
        let maximumDistance = 22_000.0
        let distance = maximumDistance - (zoomLevel * (maximumDistance - minimumDistance))
        withAnimation(.easeInOut(duration: 0.22)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: center,
                    distance: distance,
                    heading: 0,
                    pitch: selectedRow == nil ? 38 : 48
                )
            )
        }
    }

    private func revealZoomSlider() {
        let token = UUID()
        zoomVisibilityToken = token
        withAnimation(.easeOut(duration: 0.18)) { showsZoomSlider = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard zoomVisibilityToken == token else { return }
            withAnimation(.easeIn(duration: 0.2)) { showsZoomSlider = false }
        }
    }

    private func resetMap() {
        mapLayer = .standard
        selectedID = nearbyRows.first?.id
        scrollingID = selectedID
        zoomLevel = selectedID == nil ? 0.35 : 0.72
        let latitudeDistance = overviewRegion.span.latitudeDelta * 111_000
        let longitudeDistance = overviewRegion.span.longitudeDelta * 85_000
        if selectedID == nil {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: overviewRegion.center,
                    distance: max(1_600, max(latitudeDistance, longitudeDistance) * 1.8),
                    heading: 0,
                    pitch: 38
                )
            )
        } else {
            applyZoom()
        }
    }
}
