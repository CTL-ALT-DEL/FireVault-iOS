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
    case imagery = "Satellite"
    case hybrid = "Hybrid"

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
    var showsBottomNavigation = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedID: String?
    @State private var scrollingID: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapLayer: FireVaultNearbyMapLayer = .standard
    @State private var mapIs3D = true
    @State private var zoomLevel = 0.72
    @State private var showsZoomSlider = false
    @State private var zoomVisibilityToken = UUID()
    @State private var showsTripLogControls = false
    @State private var confirmsTripLogEnd = false
    @State private var tripLogControlsTask: Task<Void, Never>?

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
            let usesMapRails = geometry.size.width >= 900
            let railWidth = usesMapRails ? min(170, max(142, geometry.size.width * 0.125)) : 0
            let mapWidth = usesMapRails
                ? max(420, availableWidth - (railWidth * 2) - 28)
                : availableWidth
            let mapSide = min(mapWidth, max(300, geometry.size.height * 0.50))

            VStack(spacing: 8) {
                statusHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                tripLogStatusBar
                    .padding(.horizontal, 16)

                if showsTripLogControls {
                    tripLogQuickControls
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if usesMapRails {
                    HStack(alignment: .top, spacing: 14) {
                        mapContextRail
                            .frame(width: railWidth, height: mapSide)

                        squareMap(usesExternalControls: true)
                            .frame(width: mapSide, height: mapSide)

                        mapActionRail
                            .frame(width: railWidth, height: mapSide)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                } else {
                    squareMap(usesExternalControls: false)
                        .frame(width: mapSide, height: mapSide)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                }

                accountList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)

                if showsBottomNavigation {
                    bottomNavigation
                }
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
        .onDisappear { tripLogControlsTask?.cancel() }
        .confirmationDialog(
            "End Today’s Trip Log?",
            isPresented: $confirmsTripLogEnd,
            titleVisibility: .visible
        ) {
            Button("End Trip Log", role: .destructive) {
                breadcrumbs.endWorkday()
                closeTripLogControls()
            }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("The recorded route and stops will remain in Trip Log history.")
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

    private var tripLogStatusBar: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                showsTripLogControls.toggle()
            }
            if showsTripLogControls { scheduleTripLogControlsClose() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tripLogStatusTint.opacity(0.14))
                    Image(systemName: breadcrumbs.isRecording ? "location.fill" : "location")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tripLogStatusTint)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("TRIP LOG")
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(NativeShellPalette.red)
                    Text(tripLogStatusTitle)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(tripLogStatusTint)
                }

                Divider().frame(height: 32)
                tripMetric("MILES", value: tripMiles, symbol: "road.lanes")
                tripMetric("STOPS", value: "\(tripDay?.stops.count ?? 0)", symbol: "mappin.and.ellipse")
                tripMetric("ELAPSED", value: tripElapsed, symbol: "clock")
                Spacer(minLength: 8)

                Image(systemName: showsTripLogControls ? "chevron.up" : "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(NativeShellPalette.blue)
            }
            .padding(.horizontal, 15)
            .frame(height: 58)
            .background(
                LinearGradient(
                    colors: [NativeShellPalette.tripLogLeading, NativeShellPalette.tripLogTrailing],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(NativeShellPalette.tripLogBorder, lineWidth: 1.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trip Log, \(tripLogStatusTitle)")
        .accessibilityHint("Shows Trip Log recording controls")
    }

    private var tripLogQuickControls: some View {
        HStack(spacing: 12) {
            if breadcrumbs.activeDay == nil {
                Button("Start Trip Log", systemImage: "play.fill") {
                    breadcrumbs.startWorkday(accounts: store.accounts)
                    closeTripLogControls()
                }
                .buttonStyle(.borderedProminent)
            } else if breadcrumbs.isRecording {
                Button("Pause", systemImage: "pause.fill") {
                    breadcrumbs.pauseWorkday()
                    closeTripLogControls()
                }
                .buttonStyle(.bordered)
                Button("Stop", systemImage: "stop.fill", role: .destructive) {
                    confirmsTripLogEnd = true
                }
                .buttonStyle(.bordered)
            } else {
                Button("Resume", systemImage: "play.fill") {
                    breadcrumbs.resumeWorkday(accounts: store.accounts)
                    closeTripLogControls()
                }
                .buttonStyle(.borderedProminent)
                Button("Stop", systemImage: "stop.fill", role: .destructive) {
                    confirmsTripLogEnd = true
                }
                .buttonStyle(.bordered)
            }

            Spacer()
            Text("Closes automatically")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }

    private var tripDay: FireVaultBreadcrumbDay? { breadcrumbs.activeDay ?? breadcrumbs.today }

    private var tripLogStatusTitle: String {
        if breadcrumbs.isRecording { return "RECORDING" }
        if breadcrumbs.activeDay?.isPaused == true { return "PAUSED" }
        return breadcrumbs.activeDay == nil ? "READY" : "COMPLETE"
    }

    private var tripLogStatusTint: Color {
        if breadcrumbs.isRecording { return NativeShellPalette.green }
        if breadcrumbs.activeDay?.isPaused == true { return NativeShellPalette.amber }
        return NativeShellPalette.blue
    }

    private var tripMiles: String {
        String(format: "%.1f", (tripDay?.totalDistanceMeters ?? 0) / 1_609.344)
    }

    private var tripElapsed: String {
        let seconds = max(0, Int((tripDay?.elapsedTime ?? 0).rounded()))
        return String(format: "%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60)
    }

    private func tripMetric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(NativeShellPalette.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.bold().monospacedDigit())
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 104, alignment: .leading)
    }

    private func scheduleTripLogControlsClose() {
        tripLogControlsTask?.cancel()
        tripLogControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { showsTripLogControls = false }
        }
    }

    private func closeTripLogControls() {
        tripLogControlsTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { showsTripLogControls = false }
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

    private var mapContextRail: some View {
        VStack(spacing: 12) {
            portraitRailMetric(
                title: "IN RANGE",
                value: "\(nearbyRows.count)",
                subtitle: "accounts",
                symbol: "building.2.fill",
                tint: NativeShellPalette.blue
            )

            portraitRailMetric(
                title: "RADIUS",
                value: settings.gps.radiusStatus,
                subtitle: "field area",
                symbol: "scope",
                tint: NativeShellPalette.amber
            )

            if let selectedRow,
               let selectedIndex = nearbyRows.firstIndex(where: { $0.id == selectedRow.id }) {
                portraitRailMetric(
                    title: "SELECTED",
                    value: "#\(selectedIndex + 1)",
                    subtitle: selectedRow.distanceLabel,
                    symbol: "mappin.circle.fill",
                    tint: NativeShellPalette.red
                )
            }

            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Image(systemName: payload.demoMode ? "sparkles.rectangle.stack" : "location.fill")
                    .font(.title3.bold())
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)
                Text(payload.demoMode ? "DEMO DATA" : "LIVE LOCATION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(payload.locationStatus)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
    }

    private func portraitRailMetric(
        title: String,
        value: String,
        subtitle: String,
        symbol: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var mapActionRail: some View {
        VStack(spacing: 12) {
            VStack(spacing: 9) {
                Text("MAP TOOLS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)

                Menu {
                    Picker("Map Layer", selection: $mapLayer) {
                        ForEach(FireVaultNearbyMapLayer.allCases) { layer in
                            Label(layer.rawValue, systemImage: layer.symbol).tag(layer)
                        }
                    }
                } label: {
                    Label(mapLayer.rawValue, systemImage: "square.3.layers.3d")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                VStack(spacing: 8) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.caption.bold())
                        .foregroundStyle(NativeShellPalette.blue)
                    Slider(value: $zoomLevel, in: 0...1, step: 0.02)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 112, height: 34)
                        .padding(.vertical, 40)
                        .onChange(of: zoomLevel) { _, _ in applyZoom() }
                    Text("ZOOM")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

            Spacer(minLength: 4)

            if let selectedRow {
                VStack(spacing: 9) {
                    Text("ACCOUNT ACTIONS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)

                    portraitRailAction("Details", symbol: "note.text", tint: NativeShellPalette.amber) {
                        store.openAccount(selectedRow.account.id)
                    }
                    portraitRailAction(
                        "Call",
                        symbol: "phone.fill",
                        tint: NativeShellPalette.green,
                        disabled: !selectedRow.account.phone.contains(where: \.isNumber)
                    ) {
                        store.call(selectedRow.account.phone)
                    }
                    portraitRailAction(
                        "Route",
                        symbol: "arrow.triangle.turn.up.right.diamond.fill",
                        tint: NativeShellPalette.blue,
                        disabled: selectedRow.account.coordinate == nil
                    ) {
                        if let account = store.accounts.first(where: { $0.id == selectedRow.account.id }) {
                            store.openRoute(for: account)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
        }
    }

    private func portraitRailAction(
        _ title: String,
        symbol: String,
        tint: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption.bold())
                    .frame(width: 25, height: 25)
                    .background(tint.opacity(0.16), in: Circle())
                Text(title)
                    .font(.caption.bold())
                Spacer(minLength: 0)
            }
            .foregroundStyle(disabled ? Color.secondary : tint)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(NativeShellPalette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func squareMap(usesExternalControls: Bool) -> some View {
        ZStack(alignment: Alignment.topLeading) {
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
                .frame(maxWidth: 330, alignment: Alignment.leading)
                .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .padding(12)
            }
        }
        .overlay(alignment: Alignment.topTrailing) {
            if !usesExternalControls {
                VStack(spacing: 7) {
                Menu {
                    Picker("Map Layer", selection: $mapLayer) {
                        ForEach(FireVaultNearbyMapLayer.allCases) { layer in
                            Label(layer.rawValue, systemImage: layer.symbol).tag(layer)
                        }
                    }
                } label: {
                    FireVaultMapControlGlyph(role: .layers)
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
        }
        .overlay(alignment: Alignment.bottomTrailing) {
            if !usesExternalControls, let selectedRow {
                FireVaultMapActionStrip {
                    FireVaultMapControlButton(role: .note, label: "Open account details") {
                        store.openAccount(selectedRow.account.id)
                    }
                    FireVaultMapControlButton(
                        role: .call,
                        label: "Call account",
                        disabled: !selectedRow.account.phone.contains(where: \.isNumber)
                    ) {
                        store.call(selectedRow.account.phone)
                    }
                    FireVaultMapControlButton(
                        role: .route,
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
        .shadow(
            color: colorScheme == .light ? .black.opacity(0.22) : .clear,
            radius: 12,
            y: 6
        )
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
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                isSelected ? NativeShellPalette.blue.opacity(0.18) : NativeShellPalette.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? NativeShellPalette.blue.opacity(0.9) : .white.opacity(0.07),
                        lineWidth: isSelected ? 1.7 : 1
                    )
            }
            .shadow(
                color: .black.opacity(isSelected ? 0.32 : 0.20),
                radius: isSelected ? 9 : 6,
                y: isSelected ? 5 : 3
            )
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
                            .symbolEffect(
                                .pulse,
                                options: .repeating,
                                isActive: tab == .trip && breadcrumbs.isRecording
                            )
                            .foregroundStyle(
                                tab == .trip && breadcrumbs.isRecording
                                    ? NativeShellPalette.green
                                    : (selected
                                        ? NativeShellPalette.blue
                                        : NativeShellPalette.navigationInactive)
                            )
                            .frame(width: 34, height: 28)
                            .background(
                                selected ? NativeShellPalette.blue.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .shadow(
                                color: .black.opacity(selected ? 0.34 : 0.20),
                                radius: selected ? 6 : 4,
                                y: 3
                            )
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
        .overlay(alignment: Alignment.top) {
            Rectangle()
                .fill(NativeShellPalette.navigationDivider)
                .frame(height: 1)
        }
    }

    private func select(
        _ row: FireVaultNativeNearbyAccount,
        haptic: Bool,
        updateScrollPosition: Bool
    ) {
        if haptic, settings.gps.hapticsAreEnabled {
            let feedback = UIImpactFeedbackGenerator(style: .rigid)
            feedback.prepare()
            feedback.impactOccurred(intensity: 0.72)
        }
        guard selectedID != row.id else {
            if updateScrollPosition { scrollingID = row.id }
            return
        }

        selectedID = row.id
        if updateScrollPosition { scrollingID = row.id }
        store.selectCaptureAccount(row.account.id)
        zoomLevel = 0.72

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
                    pitch: mapIs3D ? (selectedRow == nil ? 38 : 48) : 0
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
        mapLayer = switch settings.gps.resolvedDefaultMapLayer {
        case "satellite": .imagery
        case "hybrid": .hybrid
        default: .standard
        }
        mapIs3D = settings.gps.resolvedDefaultMapIs3D
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
                    pitch: mapIs3D ? 38 : 0
                )
            )
        } else {
            applyZoom()
        }
    }
}
