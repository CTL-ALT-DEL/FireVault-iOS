//
//  FireVaultIPadWorkspaceV2.swift
//  FireVault
//
//  Landscape-first iPad workspace introduced in Build 1.08.07.
//

import MapKit
import SwiftUI

private enum FireVaultIPadNearbyMapLayer: String, CaseIterable, Identifiable {
    case standard
    case hybrid
    case imagery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .hybrid: "Hybrid"
        case .imagery: "Satellite"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .hybrid: "map.fill"
        case .imagery: "globe.americas.fill"
        }
    }
}

struct FireVaultIPadWorkspaceV2: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    private let sidebarWidth: CGFloat = 216

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)

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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(payload.demoMode ? "DEMO WORKSPACE" : "FIELD WORKSPACE")
                    .font(.caption2.bold())
                    .tracking(1.35)
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)

                Text(payload.locationStatus)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: 9) {
                Text("WORKSPACE")
                    .font(.caption2.bold())
                    .tracking(1.25)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)

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
        .background {
            LinearGradient(
                colors: [
                    NativeShellPalette.navigationBackground,
                    NativeShellPalette.navigationBackground.opacity(0.92),
                    NativeShellPalette.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func sidebarButton(_ tab: FireVaultShellTab) -> some View {
        let selected = store.selectedTab == tab

        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                store.closeAccount(to: tab)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? NativeShellPalette.blue.opacity(0.16) : .white.opacity(0.04))
                    Image(systemName: tab.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolVariant(selected ? .fill : .none)
                        .symbolEffect(
                            .pulse,
                            options: .repeating,
                            isActive: tab == .trip && breadcrumbs.isRecording
                        )
                        .foregroundStyle(
                            tab == .trip && breadcrumbs.isRecording
                                ? NativeShellPalette.green
                                : (selected ? NativeShellPalette.blue : NativeShellPalette.navigationInactive)
                        )
                }
                .frame(width: 38, height: 38)

                Text(tab.title)
                    .font(.body.weight(selected ? .bold : .semibold))

                Spacer()

                if selected {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
            }
            .foregroundStyle(selected ? .primary : NativeShellPalette.navigationInactive)
            .padding(.horizontal, 10)
            .frame(minHeight: 54)
            .background(
                selected ? NativeShellPalette.surface : .clear,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(NativeShellPalette.blue.opacity(0.55), lineWidth: 1)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(NativeShellPalette.blue)
                                .frame(width: 4, height: 28)
                                .offset(x: -2)
                        }
                }
            }
            .shadow(
                color: .black.opacity(selected ? 0.20 : 0),
                radius: selected ? 8 : 0,
                y: selected ? 4 : 0
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                FireVaultAdaptiveAccountDetailsView(
                    account: account,
                    store: store,
                    settings: settings,
                    locationService: locationService,
                    returnTab: .nearby,
                    returnTitle: "Nearby"
                )
            } else {
                FireVaultIPadNearbyWorkspaceV2(
                    payload: payload,
                    store: store,
                    settings: settings,
                    locationService: locationService,
                    breadcrumbs: breadcrumbs
                )
            }

        case .accounts:
            if let account = store.selectedAccount {
                FireVaultAdaptiveAccountDetailsView(
                    account: account,
                    store: store,
                    settings: settings,
                    locationService: locationService,
                    returnTab: .accounts,
                    returnTitle: "Account List"
                )
            } else {
                FireVaultIPadAccountsWorkspaceV2(payload: payload, store: store)
            }

        case .trip:
            FireVaultIPadBreadcrumbsView(
                breadcrumbs: breadcrumbs,
                store: store,
                technicianName: settings.preferences.technician.name,
                companyName: settings.preferences.technician.company,
                includeCoordinatesInReports: settings.gps.includeCoordinatesInReports
            )

        case .photo, .settings:
            FireVaultIPadUtilityWorkspaceV2(
                payload: payload,
                store: store,
                settings: settings,
                locationService: locationService,
                breadcrumbs: breadcrumbs
            )
        }
    }
}

private struct FireVaultIPadNearbyWorkspaceV2: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    @State private var selectedID: String?
    @State private var scrollingID: String?
    @State private var accountScrollIsActive = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapLayer: FireVaultIPadNearbyMapLayer = .standard
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
        if !payload.demoMode, let current = locationService.coordinate {
            coordinates.append(current)
        }
        return FireVaultIPadMapRegionV2.region(for: coordinates)
    }

    var body: some View {
        GeometryReader { geometry in
            let panelWidth = max(330, min(390, geometry.size.width * 0.32))
            let availableMapWidth = max(420, geometry.size.width - panelWidth - 46)
            let availableMapHeight = max(420, geometry.size.height - 72)
            let mapSide = min(availableMapWidth, availableMapHeight)

            VStack(spacing: 10) {
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
        .task { resetMapSelection() }
        .onChange(of: settings.gps.nearbyRadiusMiles) { _, _ in resetMapSelection() }
        .onChange(of: store.nearbyResetRequestID) { _, _ in resetMapSelection() }
        .onChange(of: scrollingID) { _, newID in
            guard accountScrollIsActive,
                  let newID,
                  let row = nearbyRows.first(where: { $0.id == newID }) else {
                return
            }
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
    }

    private var header: some View {
        VStack(spacing: 9) {
            HStack(spacing: 14) {
                Text("NEARBY FIELD MAP")
                    .font(.caption2.bold())
                    .tracking(1.3)
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)
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
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
            tripLogStatusBar
            if showsTripLogControls {
                tripLogQuickControls
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var tripLogStatusBar: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { showsTripLogControls.toggle() }
            if showsTripLogControls { scheduleTripLogControlsClose() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tripLogStatusTint.opacity(0.14))
                    Image(systemName: breadcrumbs.isRecording ? "location.fill" : "location")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tripLogStatusTint)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TRIP LOG").font(.caption2.bold()).tracking(1).foregroundStyle(.secondary)
                    Text(tripLogStatusTitle).font(.subheadline.bold()).foregroundStyle(tripLogStatusTint)
                }
                Divider().frame(height: 30)
                tripMetric("MILES", value: tripMiles, symbol: "road.lanes")
                tripMetric("STOPS", value: "\(tripDay?.stops.count ?? 0)", symbol: "mappin.and.ellipse")
                tripMetric("ELAPSED", value: tripElapsed, symbol: "clock")
                Spacer(minLength: 8)
                Image(systemName: showsTripLogControls ? "chevron.up" : "chevron.down")
                    .font(.caption.bold()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.black.opacity(0.34), lineWidth: 2)
                    .blur(radius: 0.8)
                    .mask(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var tripLogQuickControls: some View {
        HStack(spacing: 10) {
            if breadcrumbs.activeDay == nil {
                Button("Start Trip Log", systemImage: "play.fill") {
                    breadcrumbs.startWorkday(accounts: store.accounts)
                    closeTripLogControls()
                }
                .buttonStyle(.borderedProminent)
            } else if breadcrumbs.isRecording {
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
            Text("Controls close automatically after five seconds")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }

    private var tripDay: FireVaultBreadcrumbDay? { breadcrumbs.activeDay ?? breadcrumbs.today }
    private var tripLogStatusTitle: String {
        if breadcrumbs.isRecording { return "RECORDING" }
        if breadcrumbs.activeDay?.isPaused == true { return "PAUSED" }
        if breadcrumbs.activeDay == nil { return "READY" }
        return "COMPLETE"
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
        return String(format: "%02d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }
    private func tripMetric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.caption.bold()).foregroundStyle(NativeShellPalette.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.bold().monospacedDigit())
                Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 92, alignment: .leading)
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
                landscapeMap
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

                    Label(selectedRow.distanceLabel, systemImage: "location.fill")
                        .font(.caption.bold())
                        .foregroundStyle(NativeShellPalette.green)
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
        .overlay(alignment: .topTrailing) {
            Menu {
                Picker("Map Layer", selection: $mapLayer) {
                    ForEach(FireVaultIPadNearbyMapLayer.allCases) { layer in
                        Label(layer.title, systemImage: layer.symbol).tag(layer)
                    }
                }
            } label: {
                FireVaultMapControlGlyph(role: .layers)
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel("Map layers")
        }
        .overlay(alignment: .bottomTrailing) {
            if let selectedRow {
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
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityIdentifier("ipad-nearby-square-map")
    }

    @ViewBuilder
    private var landscapeMap: some View {
        switch mapLayer {
        case .standard:
            baseLandscapeMap.mapStyle(.standard(elevation: .realistic))
        case .hybrid:
            baseLandscapeMap.mapStyle(.hybrid(elevation: .realistic))
        case .imagery:
            baseLandscapeMap.mapStyle(.imagery(elevation: .realistic))
        }
    }

    private var baseLandscapeMap: some View {
        Map(position: $cameraPosition) {
                    if !payload.demoMode, let current = locationService.coordinate {
                        Annotation("Your Location", coordinate: current) {
                            FireVaultIPadCurrentLocationMarkerV2()
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
                                .id(row.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .scrollPosition(id: $scrollingID, anchor: .top)
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.bottom, 280, for: .scrollContent)
                .onScrollPhaseChange { _, phase in
                    accountScrollIsActive = phase.isScrolling
                }
            }
        }
        .padding(14)
        .background(NativeShellPalette.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func nearbyCard(_ row: FireVaultNativeNearbyAccount, index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                select(row, haptic: true, updateScrollPosition: true)
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
            selectedID == row.id ? NativeShellPalette.blue.opacity(0.14) : .black.opacity(0.15),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    selectedID == row.id ? NativeShellPalette.blue.opacity(0.8) : .white.opacity(0.06),
                    lineWidth: selectedID == row.id ? 1.5 : 1
                )
        }
    }

    private func select(
        _ row: FireVaultNativeNearbyAccount,
        haptic: Bool = false,
        updateScrollPosition: Bool = false
    ) {
        let selectionChanged = selectedID != row.id
        selectedID = row.id
        if updateScrollPosition { scrollingID = row.id }
        store.selectCaptureAccount(row.account.id)

        if selectionChanged, haptic, settings.gps.hapticsAreEnabled {
            let feedback = UISelectionFeedbackGenerator()
            feedback.prepare()
            feedback.selectionChanged()
        }

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
        mapLayer = switch settings.gps.resolvedDefaultMapLayer {
        case "satellite": .imagery
        case "hybrid": .hybrid
        default: .standard
        }
        selectedID = nearbyRows.first?.id
        scrollingID = selectedID
        accountScrollIsActive = false
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
