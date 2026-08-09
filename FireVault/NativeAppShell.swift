//
//  NativeAppShell.swift
//  FireVault
//
//  Native everyday navigation for Build 1.08.05.
//

import SwiftUI
import Combine
import Charts
import MapKit
import PhotosUI
import UIKit
import VisionKit

struct FireVaultAppPayload: Codable, Equatable {
    let build: String
    let initialTab: String
    let demoMode: Bool
    let todayWeekday: String
    let todayDate: String
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

enum FireVaultNearbyListLayout {
    /// Non-selectable space that lets the final account align with the top.
    static func bottomRunway(for viewportHeight: CGFloat) -> CGFloat {
        max(0, viewportHeight - 72)
    }
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
    case nearby, accounts, trip, photo, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nearby: "Nearby"
        case .accounts: "Accounts"
        case .trip: "Trip Log"
        case .photo: "Photo"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .nearby: "location.fill"
        case .accounts: "magnifyingglass"
        case .trip: "truck.box.fill"
        case .photo: "camera.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct NativeAppShellView: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            NativeShellPalette.background.ignoresSafeArea()
            Group {
                switch store.selectedTab {
                case .nearby:
                    NativeNearbyView(
                        payload: payload,
                        store: store,
                        settings: settings,
                        locationService: locationService,
                        breadcrumbs: breadcrumbs
                    )
                case .accounts:
                    NativeAccountsView(
                        payload: payload,
                        store: store,
                        settings: settings
                    )
                case .trip:
                    FireVaultTripLogPortraitView(
                        breadcrumbs: breadcrumbs,
                        store: store,
                        technicianName: settings.preferences.technician.name,
                        companyName: settings.preferences.technician.company,
                        includeCoordinatesInReports: settings.gps.includeCoordinatesInReports,
                        showsCloseButton: false
                    )
                case .photo: NativePhotoView(store: store, settings: settings)
                case .settings:
                    NativeSettingsView(
                        payload: payload,
                        store: store,
                        settings: settings,
                        locationService: locationService,
                        breadcrumbs: breadcrumbs
                    )
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) { keyboardVisible = false }
        }
    }

    private var nativeNavigation: some View {
        HStack(spacing: 0) {
            ForEach(FireVaultShellTab.allCases.filter(isTabVisible)) { tab in
                let isSelected = store.selectedTab == tab
                let isTripRecording = tab == .trip && breadcrumbs.isRecording
                Button {
                    if tab == .nearby {
                        store.requestNearbyReset()
                        if !payload.demoMode {
                            locationService.requestMapRecenter(
                                highAccuracy: settings.gps.highAccuracy
                            )
                        }
                    }
                    withAnimation(.snappy(duration: 0.25)) { store.selectedTab = tab }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: isSelected ? .bold : .semibold))
                            .symbolVariant(isSelected ? .fill : .none)
                            .foregroundStyle(
                                isTripRecording
                                    ? NativeShellPalette.green
                                    : (isSelected
                                        ? NativeShellPalette.blue
                                        : NativeShellPalette.navigationInactive)
                            )
                            .frame(width: 34, height: 26)
                            .shadow(
                                color: .black.opacity(isSelected || isTripRecording ? 0.52 : 0.18),
                                radius: isSelected || isTripRecording ? 2.5 : 1.5,
                                x: 0,
                                y: isSelected || isTripRecording ? 3 : 2
                            )
                        Text(tab.title)
                            .font(.caption2.weight(isSelected ? .bold : .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(
                                isSelected
                                    ? NativeShellPalette.blue
                                    : NativeShellPalette.navigationInactive
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: NativeShellMetrics.navigationItemHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("main-navigation-\(tab.rawValue)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            NativeShellPalette.navigationBackground,
            in: RoundedRectangle(cornerRadius: NativeShellMetrics.navigationRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NativeShellMetrics.navigationRadius, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 10)
        .padding(.top, 5)
        .padding(.bottom, 2)
        .background(NativeShellPalette.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Capsule()
                .fill(NativeShellPalette.navigationDivider)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
        .accessibilityIdentifier("main-navigation")
    }

    private func isTabVisible(_ tab: FireVaultShellTab) -> Bool {
        switch tab {
        case .nearby: settings.isFeatureVisible("tab.nearby")
        case .accounts: settings.isFeatureVisible("tab.accounts")
        case .trip: settings.isFeatureVisible("tab.trip")
        case .photo: settings.isFeatureVisible("tab.photo")
        case .settings: true
        }
    }
}

private enum FireVaultMapLayer: String, CaseIterable, Identifiable {
    case standard
    case satellite
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.americas.fill"
        case .hybrid: "square.3.layers.3d"
        }
    }
}

private enum FireVaultTripLogDetail: String, CaseIterable, Identifiable {
    case speed = "SPEED"
    case trip = "TRIP"
    case direction = "DIRECTION"
    case elevation = "ELEVATION"
    case gps = "GPS"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .speed: "speedometer"
        case .trip: "road.lanes"
        case .direction: "location.north.fill"
        case .elevation: "mountain.2.fill"
        case .gps: "scope"
        }
    }
}

private struct NativeNearbyView: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedID: String?
    @State private var showGeocodingConsent = false
    @State private var showMappingDetails = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var scrollAccountID: String?
    @State private var accountScrollWasActive = false
    @State private var mapLayer: FireVaultMapLayer = .standard
    @State private var mapIs3D = false
    @State private var hasCenteredOnInitialLiveLocation = false
    @State private var radiusPickerExpanded = false
    @State private var radiusCollapseTask: Task<Void, Never>?
    @State private var showsTripLogControls = false
    @State private var tripLogControlsCollapseTask: Task<Void, Never>?
    @State private var tripLogDetailIndex = 0
    @State private var selectedTripLogDetail: FireVaultTripLogDetail?
    @State private var showsTripLogDetailPicker = false
    @State private var showsAutoRotateEditor = false
    @AppStorage("tripLog.autoRotateDetails") private var storedAutoRotateTripLogDetails = FireVaultTripLogDetail.allCases.map(\.rawValue).joined(separator: ",")

    private var nearbyRows: [FireVaultNativeNearbyAccount] {
        let maximumMeters = settings.gps.nearbyRadiusMiles * 1_609.344
        return payload.nearby
            .filter { $0.distanceMeters <= maximumMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    private var selected: FireVaultNativeNearbyAccount? {
        guard let selectedID else { return nil }
        return nearbyRows.first(where: { $0.id == selectedID })
    }

    private var selectedWorkspaceAccount: FireVaultWorkspaceAccount? {
        guard let selected else { return nil }
        return store.accounts.first(where: { $0.id == selected.account.id })
    }

    private var selectedHasPhone: Bool {
        guard let selected else { return false }
        return selected.account.phone.contains(where: \.isNumber)
    }

    private var canDisplayMap: Bool {
        !nearbyRows.isEmpty || (!payload.demoMode && locationService.coordinate != nil)
    }

    private var shouldShowCoordinateSetup: Bool {
        guard !payload.demoMode, store.unmappedAccountCount > 0 else { return false }
        if store.geocodingProgress?.isRunning == true { return true }
        if store.mappedAccountCount == 0 { return true }
        return showMappingDetails
    }

    private var overviewRegion: MKCoordinateRegion {
        var coordinates = nearbyRows.compactMap(\.account.coordinate)
        if !payload.demoMode, let currentLocation = locationService.coordinate {
            coordinates.append(currentLocation)
        }
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
        VStack(spacing: 8) {
            statusHeader
                .padding(.horizontal, 16)

            if showsTripLogControls {
                tripLogQuickControls
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if shouldShowCoordinateSetup {
                coordinateSetup
                    .padding(.horizontal, 16)
            }
            if !payload.demoMode,
               locationService.coordinate == nil,
               locationService.authorizationStatus == .denied {
                locationAccessSetup
                    .padding(.horizontal, 16)
            }

            if settings.isFeatureVisible("nearby.map") {
                map
                    .padding(.horizontal, 16)
            }

            if settings.isFeatureVisible("nearby.list") {
                accountList
            }
        }
        .padding(.top, 4)
        .task {
            mapLayer = FireVaultMapLayer(rawValue: settings.gps.resolvedDefaultMapLayer) ?? .standard
            scrollAccountID = nearbyRows.first?.id
            if payload.demoMode {
                cameraPosition = overviewCameraPosition
            } else {
                if locationService.coordinate != nil {
                    centerMapOnUser()
                    hasCenteredOnInitialLiveLocation = true
                }
                locationService.startLiveNearbyUpdates(
                    highAccuracy: settings.gps.highAccuracy
                )
            }
        }
        .task {
            await cycleTripLogDetails()
        }
        .onDisappear {
            radiusCollapseTask?.cancel()
            tripLogControlsCollapseTask?.cancel()
            guard !payload.demoMode else { return }
            locationService.stopLiveNearbyUpdates()
        }
        .onChange(of: store.nearbyResetRequestID) { _, _ in
            resetNearby()
        }
        .onChange(of: locationService.mapRecenterRequestID) { _, _ in
            guard !payload.demoMode else { return }
            resetNearby()
        }
        .onChange(of: locationService.coordinate?.latitude) { _, latitude in
            guard !payload.demoMode,
                  latitude != nil,
                  !hasCenteredOnInitialLiveLocation else { return }
            hasCenteredOnInitialLiveLocation = true
            centerMapOnUser()
        }
        .onChange(of: store.geocodingProgress?.phase) { _, phase in
            if phase == .complete {
                showMappingDetails = false
            }
        }
        .alert("Map Imported Addresses?", isPresented: $showGeocodingConsent) {
            Button("Cancel", role: .cancel) {}
            Button("Map Accounts") {
                showGeocodingConsent = false
                Task { @MainActor in
                    await Task.yield()
                    store.startGeocodingMissingAccounts()
                }
            }
        } message: {
            Text("FireVault Pro sends only street, city, state, and ZIP fields to the U.S. Census Geocoder, then uses Apple Maps for unmatched addresses. Account names, IDs, notes, photos, and files remain on this iPhone. Returned coordinates are saved locally.")
        }
        .sheet(isPresented: $showsAutoRotateEditor) {
            autoRotateEditor
        }
        .sheet(isPresented: $showsTripLogDetailPicker) {
            tripLogDetailPicker
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 0) {
            Button {
            if showsTripLogControls {
                closeTripLogControls()
            } else {
                withAnimation(.snappy(duration: 0.24)) {
                    showsTripLogControls = true
                }
                scheduleTripLogControlsClose()
            }
            } label: {
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(tripLogStatusTint.opacity(0.14))
                        Image(systemName: breadcrumbs.isRecording ? "location.fill" : "location")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(tripLogStatusTint)
                            .symbolEffect(.pulse, options: .repeating, isActive: breadcrumbs.isRecording)
                    }
                    .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("TRIP LOG")
                            .font(.caption2.bold())
                            .tracking(1.05)
                            .foregroundStyle(.secondary)
                        Text(tripLogStateText)
                            .font(.subheadline.bold())
                            .foregroundStyle(tripLogStatusTint)
                    }

                    Image(systemName: showsTripLogControls ? "chevron.up" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 9)
                .padding(.trailing, 7)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trip Log, \(tripLogStateText)")
            .accessibilityHint("Shows start, pause, resume, and stop controls")

            Divider()
                .frame(height: 28)

            tripLogDetailMenu
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 44)
        .background(NativeShellPalette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.black.opacity(0.58), lineWidth: 3)
                .blur(radius: 1.25)
                .offset(y: 1.6)
                .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.black.opacity(0.24), lineWidth: 1.5)
                .blur(radius: 2.2)
                .padding(2)
                .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.32), lineWidth: 1)
                .offset(y: 1.5)
                .mask(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .shadow(color: .white.opacity(0.18), radius: 1, y: 1)
    }

    private var tripLogDetailMenu: some View {
        Button {
            showsTripLogDetailPicker = true
        } label: {
            ZStack {
                HStack(spacing: 7) {
                    Image(systemName: displayedTripLogDetail.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NativeShellPalette.blue)
                        .frame(width: 23)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayedTripLogDetail.rawValue)
                            .font(.caption2.bold())
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 5) {
                            Text(tripLogDetailPrimaryText)
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(.primary)
                            Text(tripLogDetailSecondaryText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .contentTransition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)

                HStack {
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Trip Log detail, \(displayedTripLogDetail.rawValue), \(tripLogDetailPrimaryText), \(tripLogDetailSecondaryText)")
        .accessibilityHint("Choose which Trip Log detail to display")
    }

    private var tripLogDetailPicker: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTripLogDetail = nil
                        }
                        showsTripLogDetailPicker = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.title3.bold())
                                .foregroundStyle(NativeShellPalette.blue)
                                .frame(width: 42, height: 42)
                                .background(NativeShellPalette.blue.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto Rotate")
                                    .font(.headline)
                                Text("Cycle through your selected live details")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedTripLogDetail == nil ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTripLogDetail == nil ? NativeShellPalette.blue : .secondary)
                        }
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(FireVaultTripLogDetail.allCases) { detail in
                            tripLogDetailChoice(detail)
                        }
                    }

                    Button {
                        showsTripLogDetailPicker = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            showsAutoRotateEditor = true
                        }
                    } label: {
                        Label("Choose Auto Rotate Items", systemImage: "checklist")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(16)
            }
            .background(NativeShellPalette.background)
            .navigationTitle("Trip Log Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsTripLogDetailPicker = false }
                }
            }
        }
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
    }

    private func tripLogDetailChoice(_ detail: FireVaultTripLogDetail) -> some View {
        let selected = selectedTripLogDetail == detail
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTripLogDetail = detail
            }
            showsTripLogDetailPicker = false
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: detail.symbol)
                        .font(.title3.bold())
                        .foregroundStyle(selected ? Color.white : NativeShellPalette.blue)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.white : Color.secondary.opacity(0.5))
                }
                Text(detail.rawValue.capitalized)
                    .font(.subheadline.bold())
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(
                selected ? NativeShellPalette.blue : NativeShellPalette.navigationBackground,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(NativeShellPalette.blue.opacity(selected ? 0 : 0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var displayedTripLogDetail: FireVaultTripLogDetail {
        guard selectedTripLogDetail == nil else { return selectedTripLogDetail! }
        let choices = activeAutoRotateTripLogDetails
        return choices[tripLogDetailIndex % choices.count]
    }

    private var activeAutoRotateTripLogDetails: [FireVaultTripLogDetail] {
        let selectedIDs = Set(storedAutoRotateTripLogDetails.split(separator: ",").map(String.init))
        let choices = FireVaultTripLogDetail.allCases.filter { selectedIDs.contains($0.rawValue) }
        return choices.isEmpty ? FireVaultTripLogDetail.allCases : choices
    }

    private func toggleAutoRotateDetail(_ detail: FireVaultTripLogDetail) {
        var choices = Set(activeAutoRotateTripLogDetails)
        if choices.contains(detail) {
            guard choices.count > 1 else { return }
            choices.remove(detail)
        } else {
            choices.insert(detail)
        }
        storedAutoRotateTripLogDetails = FireVaultTripLogDetail.allCases
            .filter(choices.contains)
            .map(\.rawValue)
            .joined(separator: ",")
        tripLogDetailIndex = 0
    }

    private var autoRotateEditor: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FireVaultTripLogDetail.allCases) { detail in
                        Button {
                            toggleAutoRotateDetail(detail)
                        } label: {
                            HStack {
                                Label(detail.rawValue.capitalized, systemImage: detail.symbol)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if activeAutoRotateTripLogDetails.contains(detail) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NativeShellPalette.blue)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Select any combination of details to cycle. Your choices save automatically.")
                }
            }
            .navigationTitle("Auto Rotate Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsAutoRotateEditor = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var tripLogDetailPrimaryText: String {
        if payload.demoMode {
            return switch displayedTripLogDetail {
            case .speed: "64 mph"
            case .trip: "42.6 mi"
            case .direction: "NW"
            case .elevation: "5,284 ft"
            case .gps: "±10 ft"
            }
        } else {
            switch displayedTripLogDetail {
            case .speed:
                guard let speed = locationService.latestLocation?.speed, speed >= 0 else { return "— mph" }
                return "\(Int((speed * 2.236_936).rounded())) mph"
            case .trip:
                guard let day = breadcrumbs.today else { return "0.0 mi" }
                return String(format: "%.1f mi", day.totalDistanceMeters / 1_609.344)
            case .direction:
                guard let course = locationService.latestLocation?.course, course >= 0 else { return "—" }
                return cardinalDirection(for: course)
            case .elevation:
                guard let altitude = currentAltitudeMeters else { return "— ft" }
                return "\(Int((altitude * 3.280_84).rounded()).formatted()) ft"
            case .gps:
                guard let accuracy = locationService.latestLocation?.horizontalAccuracy, accuracy >= 0 else { return "±— ft" }
                return "±\(Int((accuracy * 3.280_84).rounded()).formatted()) ft"
            }
        }
    }

    private var tripLogDetailSecondaryText: String {
        if payload.demoMode {
            return switch displayedTripLogDetail {
            case .speed: "Avg 57 · Max 71"
            case .trip: "00:48:17"
            case .direction: "312°"
            case .elevation: "Gain +327 ft"
            case .gps: "Excellent"
            }
        } else {
            switch displayedTripLogDetail {
            case .speed:
                let speeds = breadcrumbs.today?.points.compactMap(\.speedMetersPerSecond).filter { $0 >= 0 } ?? []
                guard !speeds.isEmpty else { return "Avg — · Max —" }
                let average = speeds.reduce(0, +) / Double(speeds.count) * 2.236_936
                let maximum = (speeds.max() ?? 0) * 2.236_936
                return "Avg \(Int(average.rounded())) · Max \(Int(maximum.rounded()))"
            case .trip:
                return clockDuration(breadcrumbs.today?.elapsedTime ?? 0)
            case .direction:
                guard let course = locationService.latestLocation?.course, course >= 0 else { return "—°" }
                return "\(Int(course.rounded()))°"
            case .elevation:
                let gain = elevationGainMeters * 3.280_84
                return "Gain +\(Int(gain.rounded()).formatted()) ft"
            case .gps:
                guard let accuracy = locationService.latestLocation?.horizontalAccuracy, accuracy >= 0 else { return "Unavailable" }
                if accuracy <= 5 { return "Excellent" }
                if accuracy <= 15 { return "Good" }
                if accuracy <= 35 { return "Fair" }
                return "Weak"
            }
        }
    }

    private var currentAltitudeMeters: Double? {
        if let location = locationService.latestLocation, location.verticalAccuracy >= 0 {
            return location.altitude
        }
        return breadcrumbs.today?.points.compactMap(\.altitude).last
    }

    private var elevationGainMeters: Double {
        let values = breadcrumbs.today?.points.compactMap(\.altitude) ?? []
        return zip(values, values.dropFirst()).reduce(0) { total, pair in
            total + max(0, pair.1 - pair.0)
        }
    }

    private func clockDuration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    private func cardinalDirection(for course: CLLocationDirection) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = course.truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45.0) % directions.count
        return directions[index]
    }

    private func cycleTripLogDetails() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.55)) {
                tripLogDetailIndex = (tripLogDetailIndex + 1) % activeAutoRotateTripLogDetails.count
            }
        }
    }

    private func scheduleTripLogControlsClose() {
        tripLogControlsCollapseTask?.cancel()
        tripLogControlsCollapseTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            closeTripLogControls()
        }
    }

    private func closeTripLogControls() {
        tripLogControlsCollapseTask?.cancel()
        tripLogControlsCollapseTask = nil
        withAnimation(.snappy(duration: 0.24)) {
            showsTripLogControls = false
        }
    }

    private var tripLogQuickControls: some View {
        HStack(spacing: 10) {
            if breadcrumbs.activeDay == nil {
                tripLogControl(title: "Start", symbol: "play.fill", tint: NativeShellPalette.green) {
                    breadcrumbs.startWorkday(accounts: store.accounts)
                }
            } else if breadcrumbs.activeDay?.isPaused == true {
                tripLogControl(title: "Resume", symbol: "play.fill", tint: NativeShellPalette.green) {
                    breadcrumbs.resumeWorkday(accounts: store.accounts)
                }
                tripLogControl(title: "Stop", symbol: "stop.fill", tint: NativeShellPalette.red) {
                    breadcrumbs.endWorkday()
                }
            } else {
                tripLogControl(title: "Pause", symbol: "pause.fill", tint: NativeShellPalette.amber) {
                    breadcrumbs.pauseWorkday()
                }
                tripLogControl(title: "Stop", symbol: "stop.fill", tint: NativeShellPalette.red) {
                    breadcrumbs.endWorkday()
                }
            }
        }
        .padding(10)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func tripLogControl(
        title: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var tripLogStateText: String {
        if breadcrumbs.isRecording { return "RECORDING" }
        if breadcrumbs.activeDay?.isPaused == true { return "PAUSED" }
        return "STOPPED"
    }

    private var tripLogStatusTint: Color {
        if breadcrumbs.isRecording { return NativeShellPalette.green }
        if breadcrumbs.activeDay?.isPaused == true { return NativeShellPalette.amber }
        return .secondary
    }

    private var locationAccessSetup: some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Location Access Needed", systemImage: "location.slash.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Nearby uses this iPhone’s current location to calculate which mapped accounts are inside your selected radius.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Location Settings", systemImage: "gearshape") {
                    locationService.openAppSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var coordinateSetup: some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Map Imported Accounts", systemImage: "mappin.and.ellipse")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    if store.mappedAccountCount > 0,
                       store.geocodingProgress?.isRunning != true {
                        Button {
                            showMappingDetails = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close address mapping")
                    }
                }

                HStack {
                    LabeledContent("Mapped", value: "\(store.mappedAccountCount)")
                    Divider().frame(height: 22)
                    LabeledContent("Need coordinates", value: "\(store.unmappedAccountCount)")
                }
                .font(.subheadline)

                if let progress = store.geocodingProgress {
                    if progress.isRunning {
                        ProgressView(value: progress.fractionComplete)
                            .accessibilityLabel("Mapping imported addresses")
                            .accessibilityValue("\(progress.completed) of \(progress.total)")
                    }
                    Text(progress.message)
                        .font(.footnote)
                        .foregroundStyle(progress.phase == .failed ? .orange : .secondary)
                } else {
                    Text("Nearby needs coordinates because the imported CSV contains postal addresses but no latitude or longitude.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if store.geocodingProgress?.isRunning == true {
                    Button("Stop Mapping", role: .cancel) {
                        store.cancelGeocoding()
                    }
                    .buttonStyle(.bordered)
                } else if store.geocodableAccountCount > 0 {
                    Button(
                        store.geocodingProgress?.phase == .failed ? "Retry Address Mapping" : "Map \(store.geocodableAccountCount) Addresses",
                        systemImage: "location.magnifyingglass"
                    ) {
                        showGeocodingConsent = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var map: some View {
        Group {
            if !canDisplayMap {
                NativeShellCard {
                    ContentUnavailableView(
                        emptyMapTitle,
                        systemImage: "map",
                        description: Text(emptyMapDescription)
                    )
                }
            } else {
                styledMap
                .frame(height: 270)
                .nativeMapFrame()
                .overlay(alignment: .topLeading) {
                    if let selected {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selected.account.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(selected.account.address)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 260, alignment: .leading)
                        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .padding(10)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(selected.account.name), \(selected.account.address)")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    mapOptionsMenu
                        .padding(10)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let selected {
                        FireVaultMapActionStrip {
                            FireVaultMapControlButton(
                                role: .note,
                                label: "Open \(selected.account.name) details"
                            ) {
                                store.openAccount(selected.account.id)
                            }
                            .accessibilityIdentifier("nearby-map-note")

                            FireVaultMapControlButton(
                                role: .call,
                                label: "Call \(selected.account.name)",
                                disabled: !selectedHasPhone
                            ) {
                                store.call(selected.account.phone)
                            }
                            .accessibilityValue(selectedHasPhone ? selected.account.phone : "No phone number")
                            .accessibilityIdentifier("nearby-map-call")

                            FireVaultMapControlButton(
                                role: .route,
                                label: "Route to \(selected.account.name)",
                                disabled: selectedWorkspaceAccount == nil
                            ) {
                                guard let account = selectedWorkspaceAccount else { return }
                                store.openRoute(for: account)
                            }
                            .accessibilityIdentifier("nearby-map-route")
                        }
                        .padding(10)
                    }
                }
                .accessibilityIdentifier("nearby-fixed-map")
            }
        }
    }

    @ViewBuilder
    private var styledMap: some View {
        switch mapLayer {
        case .standard:
            configuredMap(.standard(elevation: .realistic))
        case .satellite:
            configuredMap(.imagery(elevation: .realistic))
        case .hybrid:
            configuredMap(.hybrid(elevation: .realistic))
        }
    }

    private func configuredMap(_ style: MapStyle) -> some View {
        Map(position: $cameraPosition) {
            if !payload.demoMode, let currentLocation = locationService.coordinate {
                Annotation("Your Location", coordinate: currentLocation) {
                    ZStack {
                        Circle()
                            .fill(NativeShellPalette.blue.opacity(0.22))
                            .frame(width: 38, height: 38)
                        Circle()
                            .fill(.white)
                            .frame(width: 22, height: 22)
                        Circle()
                            .fill(NativeShellPalette.blue)
                            .frame(width: 14, height: 14)
                    }
                    .shadow(radius: 4)
                    .accessibilityElement()
                    .accessibilityLabel("Your current location")
                    .accessibilityIdentifier("nearby-current-location")
                }
            }

            ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
                if let coordinate = row.account.coordinate {
                    Annotation(row.account.name, coordinate: coordinate) {
                        Button {
                            selectAccount(row, scrollToCard: true)
                        } label: {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    selected?.id == row.id
                                        ? NativeShellPalette.red
                                        : NativeShellPalette.blue,
                                    in: Circle()
                                )
                                .overlay {
                                    Circle().stroke(.white.opacity(0.85), lineWidth: 2)
                                }
                                .shadow(radius: 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapStyle(style)
        .onChange(of: mapIs3D) { _, _ in
            updateMapPerspective()
        }
    }

    private var mapOptionsMenu: some View {
        Menu {
            Picker("Map Layer", selection: $mapLayer) {
                ForEach(FireVaultMapLayer.allCases) { layer in
                    Label(layer.title, systemImage: layer.symbol)
                        .tag(layer)
                }
            }

            Divider()

            Toggle(isOn: $mapIs3D) {
                Label("3D View", systemImage: "view.3d")
            }
        } label: {
            FireVaultMapControlGlyph(role: .layers)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map options")
        .accessibilityValue("\(mapLayer.title), \(mapIs3D ? "3D" : "2D")")
        .accessibilityIdentifier("nearby-map-options")
    }

    private var nearbyRadiusBinding: Binding<Double> {
        Binding(
            get: { settings.gps.nearbyRadiusMiles },
            set: updateNearbyRadius
        )
    }

    private func updateNearbyRadius(_ radius: Double) {
        guard radius != settings.gps.nearbyRadiusMiles else { return }
        scheduleRadiusCollapse()

        var updated = settings.gps
        updated.nearbyRadiusMiles = radius
        settings.saveGPS(updated)

        accountScrollWasActive = false
        selectedID = nil
        scrollAccountID = nearbyRows.first?.id

        withAnimation(.easeInOut(duration: 0.35)) {
            if payload.demoMode {
                cameraPosition = overviewCameraPosition
            } else if locationService.coordinate != nil {
                centerMapOnUser()
            }
        }
    }

    private var emptyMapTitle: String {
        if !payload.demoMode, store.mappedAccountCount == 0 { return "Account Coordinates Needed" }
        if !payload.demoMode, locationService.coordinate == nil { return "Current Location Needed" }
        return payload.nearby.isEmpty ? "No Mapped Accounts" : "No Accounts in Range"
    }

    private var emptyMapDescription: String {
        if !payload.demoMode, store.mappedAccountCount == 0 {
            return "Use Map Imported Accounts above to calculate coordinates from the imported postal addresses."
        }
        if !payload.demoMode, locationService.coordinate == nil {
            return "Allow location access or tap the location button to compare mapped accounts with this iPhone."
        }
        if payload.nearby.isEmpty {
            return payload.demoMode
                ? "Refresh location to display GPS-ready accounts on Apple Maps."
                : "No accounts currently have usable map coordinates."
        }
        return "Increase the Nearby Radius in Settings to include more accounts."
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "\(nearbyRows.count) NEARBY ACCOUNT\(nearbyRows.count == 1 ? "" : "S") • " +
                "\(settings.gps.nearbyRadiusMiles.formatted(.number.precision(.fractionLength(0...2)))) MI RANGE"
            )
            .font(.caption.bold())
            .tracking(1.05)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)

            if nearbyRows.isEmpty {
                ContentUnavailableView(
                    emptyMapTitle,
                    systemImage: "location.slash",
                    description: Text(emptyMapDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
            } else {
                GeometryReader { listGeometry in
                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
                                    accountCard(row, index: index)
                                        .id(row.id)
                                }
                            }
                            .padding(.top, 10)
                            .scrollTargetLayout()

                            Color.clear
                                .frame(
                                    height: FireVaultNearbyListLayout.bottomRunway(
                                        for: listGeometry.size.height
                                    )
                                )
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        store.reloadAccounts()
                        try? await Task.sleep(for: .milliseconds(350))
                    }
                    .scrollPosition(id: $scrollAccountID, anchor: .top)
                    .scrollTargetBehavior(
                        .viewAligned(limitBehavior: .never, anchor: .top)
                    )
                    .onScrollPhaseChange { _, newPhase in
                        if newPhase.isScrolling {
                            accountScrollWasActive = true
                        } else if newPhase == .idle, accountScrollWasActive {
                            accountScrollWasActive = false
                            focusScrolledAccount()
                        }
                    }
                    .onChange(of: scrollAccountID) { _, newID in
                        guard accountScrollWasActive, newID != nil,
                              settings.gps.hapticsAreEnabled else { return }
                        let feedback = UISelectionFeedbackGenerator()
                        feedback.prepare()
                        feedback.selectionChanged()
                    }
                    .accessibilityIdentifier("nearby-account-scroll")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func accountCard(
        _ row: FireVaultNativeNearbyAccount,
        index: Int
    ) -> some View {
        return Button {
            selectAccount(row, scrollToCard: true, haptic: true)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        selectedID == row.id ? NativeShellPalette.red : NativeShellPalette.blue,
                        in: Circle()
                    )
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.account.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(row.account.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        HStack(spacing: 10) {
                            Label(
                                row.account.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "No Account ID"
                                    : row.account.accountId,
                                systemImage: "number"
                            )
                            .lineLimit(1)

                            Label(
                                row.account.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? "Uncategorized"
                                    : row.account.category,
                                systemImage: "tag.fill"
                            )
                            .lineLimit(1)
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                        Spacer(minLength: 6)

                        Text(row.distanceLabel)
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(NativeShellPalette.green)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nativeSurfaceCard(
                cornerRadius: NativeShellMetrics.cardRadius,
                emphasized: selectedID == row.id
            )
            .scaleEffect(selectedID == row.id ? 1.006 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(selectedID == nil || selectedID == row.id ? 1 : 0.58)
        .saturation(selectedID == nil || selectedID == row.id ? 1 : 0.72)
        .animation(.easeOut(duration: 0.24), value: selectedID)
        .onLongPressGesture(minimumDuration: 0.55, maximumDistance: 24) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            store.openAccount(row.account.id)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                row.account.name,
                row.account.address,
                row.account.accountId.isEmpty ? "No account ID" : "Account ID \(row.account.accountId)",
                row.account.category.isEmpty ? "Uncategorized" : "Category \(row.account.category)",
                row.distanceLabel
            ].joined(separator: ", ")
        )
        .accessibilityHint("Tap to select on the map. Long press to open account details.")
        .accessibilityValue(selectedID == row.id ? "Selected" : "Not selected")
        .accessibilityAddTraits(selectedID == row.id ? .isSelected : [])
        .accessibilityAction(named: "Open Account Details") {
            store.openAccount(row.account.id)
        }
        .accessibilityIdentifier("nearby-account-\(row.id)")
    }

    private func expandRadiusPicker() {
        radiusCollapseTask?.cancel()
        withAnimation(.snappy(duration: 0.24)) {
            radiusPickerExpanded = true
        }
        scheduleRadiusCollapse()
    }

    private func scheduleRadiusCollapse() {
        radiusCollapseTask?.cancel()
        radiusCollapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.24)) {
                radiusPickerExpanded = false
            }
        }
    }

    private func focusScrolledAccount() {
        guard let scrollAccountID,
              selectedID != scrollAccountID,
              let row = nearbyRows.first(where: { $0.id == scrollAccountID }) else {
            return
        }
        selectAccount(row, scrollToCard: false, haptic: false)
    }

    private func selectAccount(
        _ row: FireVaultNativeNearbyAccount,
        scrollToCard: Bool,
        haptic: Bool = false
    ) {
        if haptic, settings.gps.hapticsAreEnabled {
            let feedback = UIImpactFeedbackGenerator(style: .rigid)
            feedback.prepare()
            feedback.impactOccurred(intensity: 0.72)
        }
        guard let coordinate = row.account.coordinate else { return }
        selectedID = row.id
        store.selectCaptureAccount(row.account.id)
        if scrollToCard {
            // Update the scroll anchor without animating through intermediate
            // cards, which previously let the old top card reclaim selection.
            scrollAccountID = row.id
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = accountCameraPosition(coordinate)
        }
    }

    private func centerMapOnUser() {
        guard let coordinate = locationService.coordinate else { return }
        selectedID = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = userCameraPosition(coordinate)
        }
    }

    private var overviewCameraPosition: MapCameraPosition {
        guard mapIs3D else {
            return .region(overviewRegion)
        }

        let latitudeDistance = overviewRegion.span.latitudeDelta * 111_000
        let longitudeDistance = overviewRegion.span.longitudeDelta * 85_000
        return .camera(
            MapCamera(
                centerCoordinate: overviewRegion.center,
                distance: max(1_500, max(latitudeDistance, longitudeDistance) * 1.8),
                heading: 0,
                pitch: 55
            )
        )
    }

    private func accountCameraPosition(_ coordinate: CLLocationCoordinate2D) -> MapCameraPosition {
        guard mapIs3D else {
            return .region(
                FireVaultNearbyMapCamera.accountRegion(coordinate: coordinate)
            )
        }

        return .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: 900,
                heading: 0,
                pitch: 58
            )
        )
    }

    private func userCameraPosition(_ coordinate: CLLocationCoordinate2D) -> MapCameraPosition {
        guard mapIs3D else {
            return .region(
                FireVaultNearbyMapCamera.userRegion(
                    coordinate: coordinate,
                    radiusMiles: settings.gps.nearbyRadiusMiles
                )
            )
        }

        return .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: max(900, settings.gps.nearbyRadiusMiles * 1_609.344 * 2.2),
                heading: 0,
                pitch: 55
            )
        )
    }

    private func updateMapPerspective() {
        withAnimation(.easeInOut(duration: 0.35)) {
            if let selected,
               let coordinate = selected.account.coordinate {
                cameraPosition = accountCameraPosition(coordinate)
            } else if !payload.demoMode,
                      let coordinate = locationService.coordinate {
                cameraPosition = userCameraPosition(coordinate)
            } else {
                cameraPosition = overviewCameraPosition
            }
        }
    }

    private func resetNearby() {
        accountScrollWasActive = false
        selectedID = nil

        if let closestID = nearbyRows.first?.id {
            scrollAccountID = closestID
        } else {
            scrollAccountID = nil
        }

        if payload.demoMode {
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraPosition = overviewCameraPosition
            }
        } else {
            centerMapOnUser()
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
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var search = ""
    @State private var sort: NativeAccountSort = .alphabetic
    @State private var topAccountID: String?
    @State private var accountScrollIsActive = false

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
            GeometryReader { geometry in
                if accounts.isEmpty {
                    Group {
                        if search.isEmpty {
                            ContentUnavailableView(
                                "No Accounts",
                                systemImage: "building.2",
                                description: Text("Add an account here or import a CSV from Settings.")
                            )
                        } else {
                            ContentUnavailableView.search(text: search)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            Text("\(accounts.count) ACCOUNT\(accounts.count == 1 ? "" : "S")")
                                .font(.caption.bold())
                                .tracking(1.1)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(accounts) { account in
                                Button {
                                    topAccountID = account.id
                                    store.openAccount(account.id)
                                } label: {
                                    NativeAccountRow(account: account)
                                        .padding(.horizontal, 12)
                                        .nativeSurfaceCard(cornerRadius: NativeShellMetrics.cardRadius)
                                }
                                .buttonStyle(.plain)
                                .id(account.id)
                            }

                            Color.clear
                                .frame(height: max(0, geometry.size.height - 92))
                                .allowsHitTesting(false)
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        store.reloadAccounts()
                        try? await Task.sleep(for: .milliseconds(350))
                    }
                    .scrollPosition(id: $topAccountID, anchor: .top)
                    .scrollTargetBehavior(.viewAligned(limitBehavior: .never, anchor: .top))
                    .onScrollPhaseChange { _, phase in
                        accountScrollIsActive = phase.isScrolling
                    }
                    .onChange(of: topAccountID) { _, newID in
                        guard accountScrollIsActive, newID != nil,
                              settings.gps.hapticsAreEnabled else { return }
                        let feedback = UISelectionFeedbackGenerator()
                        feedback.prepare()
                        feedback.selectionChanged()
                    }
                    .accessibilityIdentifier("accounts-snapping-scroll")
                }
            }
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

struct NativePhotoView: View {
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var scannedPages: [UIImage] = []
    @State private var captureRoute: CaptureRoute?
    @State private var mediaKind: MediaKind = .photo
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showsAlert = false
    @State private var showsAccountPicker = false
    @State private var showsPhotoPicker = false
    @State private var pendingCaptureIntent: CaptureIntent?
    @State private var mediaAccountID: String?
    @State private var saveStatus = ""

    private enum CaptureRoute: String, Identifiable {
        case camera
        case scanner
        var id: String { rawValue }
    }

    private enum MediaKind {
        case photo
        case scan
    }

    private enum CaptureIntent {
        case camera
        case scanner
        case photoLibrary
    }

    private var destinationAccount: FireVaultWorkspaceAccount? {
        store.captureAccount
    }

    private var mediaAccount: FireVaultWorkspaceAccount? {
        guard let mediaAccountID else { return nil }
        return store.accounts.first { $0.id == mediaAccountID }
    }

    private var technicianName: String {
        let savedName = settings.preferences.technician.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return savedName.isEmpty ? "Field Technician" : savedName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    destinationAccountCard

                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: 18) {
                            previewColumn
                                .frame(maxWidth: .infinity)

                            ipadCapturePanel
                                .frame(width: 340)
                        }
                    } else {
                        previewColumn
                        captureControls
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeShellPalette.background)
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                handleCaptureQuickAction()
            }
            .onChange(of: store.pendingCaptureQuickAction) { _, _ in
                handleCaptureQuickAction()
            }
            .onChange(of: selectedItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    acceptPhoto(image)
                    selectedItem = nil
                }
            }
            .photosPicker(
                isPresented: $showsPhotoPicker,
                selection: $selectedItem,
                matching: .images
            )
            .sheet(isPresented: $showsAccountPicker) {
                NativeCaptureAccountPicker(
                    accounts: store.accounts,
                    selectedID: store.captureAccountID
                ) { accountID in
                    store.selectCaptureAccount(accountID)
                    showsAccountPicker = false
                    if let pendingCaptureIntent {
                        self.pendingCaptureIntent = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(220))
                            launchCapture(pendingCaptureIntent)
                        }
                    }
                }
            }
            .fullScreenCover(item: $captureRoute) { route in
                switch route {
                case .camera:
                    NativeCameraCaptureView(
                        preferences: settings.preferences.overlay,
                        technicianName: technicianName,
                        account: destinationAccount,
                        onCapture: acceptPhoto,
                        onCancel: { captureRoute = nil }
                    )
                    .ignoresSafeArea()
                case .scanner:
                    NativeDocumentScannerView(
                        onScan: acceptScan,
                        onCancel: { captureRoute = nil },
                        onFailure: showCaptureFailure
                    )
                    .ignoresSafeArea()
                }
            }
            .alert(alertTitle, isPresented: $showsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    @ViewBuilder
    private var previewColumn: some View {
        VStack(spacing: 10) {
            if let selectedImage {
                imagePreview(selectedImage)

                if scannedPages.count > 1 {
                    scannedPageStrip
                }

                HStack(spacing: 8) {
                    Label(
                        mediaKind == .scan
                            ? "\(scannedPages.count) page\(scannedPages.count == 1 ? "" : "s")"
                            : "Overlay applied",
                        systemImage: mediaKind == .scan
                            ? "doc.viewfinder.fill"
                            : "camera.filters"
                    )
                    .foregroundStyle(.secondary)

                    if !saveStatus.isEmpty {
                        Spacer(minLength: 4)
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(NativeShellPalette.green)
                            .accessibilityIdentifier("native-media-save-status")
                    }
                }
                .font(.caption.bold())
                .padding(.horizontal, 4)
            } else {
                captureReadyCard
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxHeight: 650)
            }
        }
    }

    private var ipadCapturePanel: some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("FIELD CAPTURE", systemImage: "camera.aperture")
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(NativeShellPalette.blue)

                Text("Capture a field photo, scan a document, or import an existing image into the selected account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(spacing: 10) {
                    captureButton(
                        title: "PHOTO",
                        subtitle: "Camera",
                        symbol: "camera.fill",
                        tint: NativeShellPalette.red,
                        intent: .camera
                    )
                    captureButton(
                        title: "SCAN",
                        subtitle: "Document",
                        symbol: "doc.viewfinder",
                        tint: NativeShellPalette.blue,
                        intent: .scanner
                    )
                    captureButton(
                        title: "IMPORT",
                        subtitle: "Photo Library",
                        symbol: "photo.on.rectangle",
                        tint: NativeShellPalette.green,
                        intent: .photoLibrary
                    )
                }
            }
        }
    }

    private func imagePreview(_ image: UIImage) -> some View {
        let aspectRatio = max(0.35, image.size.width / max(image.size.height, 1))

        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: 420)
        .nativeSurfaceCard(cornerRadius: NativeShellMetrics.mapRadius)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            [
                mediaKind == .scan
                    ? "Scanned document preview"
                    : "Field photo with baked FireVault Pro overlay",
                mediaAccount.map { "Saved to \($0.name)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
        .accessibilityIdentifier("native-photo-preview")
    }

    private var destinationAccountCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "building.2.fill")
                .font(.subheadline.bold())
                .foregroundStyle(NativeShellPalette.blue)
                .frame(width: 36, height: 36)
                .background(NativeShellPalette.blue.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("DESTINATION ACCOUNT")
                    .font(.caption2.bold())
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                if let destinationAccount {
                    Text(destinationAccount.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(destinationAccount.address)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !destinationAccount.accountId.isEmpty {
                        Text("Account ID: \(destinationAccount.accountId)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Choose an account before capturing")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 6)

            Button(destinationAccount == nil ? "Choose" : "Change") {
                pendingCaptureIntent = nil
                showsAccountPicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeSurfaceCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-capture-destination")
    }

    private var scannedPageStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(scannedPages.enumerated()), id: \.offset) { index, page in
                    Button {
                        selectedImage = page
                    } label: {
                        Image(uiImage: page)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        selectedImage === page
                                            ? NativeShellPalette.blue
                                            : .white.opacity(0.12),
                                        lineWidth: selectedImage === page ? 3 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scanned page \(index + 1)")
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("native-scanned-pages")
    }

    private var captureControls: some View {
        HStack(spacing: 10) {
            captureButton(
                title: "PHOTO",
                subtitle: "Camera",
                symbol: "camera.fill",
                tint: NativeShellPalette.red,
                intent: .camera
            )
            .accessibilityIdentifier("native-take-photo")

            captureButton(
                title: "SCAN",
                subtitle: "Document",
                symbol: "doc.viewfinder",
                tint: NativeShellPalette.blue,
                intent: .scanner
            )
            .accessibilityIdentifier("native-scan-document")

            captureButton(
                title: "IMPORT",
                subtitle: "Library",
                symbol: "photo.on.rectangle",
                tint: NativeShellPalette.green,
                intent: .photoLibrary
            )
            .accessibilityIdentifier("native-choose-photo")
        }
    }

    private func captureButton(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        intent: CaptureIntent
    ) -> some View {
        Button {
            beginCapture(intent)
        } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .bold))
                VStack(spacing: 1) {
                    Text(title)
                        .font(.caption.bold())
                        .tracking(0.7)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 94)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.92), tint.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .shadow(color: tint.opacity(0.18), radius: 8, y: 4)
    }

    private var captureReadyCard: some View {
        ZStack {
            LinearGradient(
                colors: [NativeShellPalette.blue.opacity(0.14), NativeShellPalette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(NativeShellPalette.blue.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [7, 7]))
                .padding(16)

            VStack(spacing: 14) {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(NativeShellPalette.blue)
                    .frame(width: 82, height: 82)
                    .background(NativeShellPalette.blue.opacity(0.12), in: Circle())
                    .overlay {
                        Circle().stroke(NativeShellPalette.blue.opacity(0.24), lineWidth: 1)
                    }

                VStack(spacing: 5) {
                    Text("FIELD CAPTURE")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .tracking(1.1)
                    Text("Photo • Scan • Import")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 8) {
                    Label("Account linked", systemImage: "building.2.fill")
                    Label("Overlay ready", systemImage: "camera.filters")
                }
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity)
        .nativeSurfaceCard(cornerRadius: NativeShellMetrics.mapRadius)
        .accessibilityElement(children: .combine)
    }

    private func beginCapture(_ intent: CaptureIntent) {
        guard destinationAccount != nil else {
            pendingCaptureIntent = intent
            showsAccountPicker = true
            return
        }
        launchCapture(intent)
    }

    private func handleCaptureQuickAction() {
        guard let action = store.consumeCaptureQuickAction() else { return }
        switch action {
        case .photo:
            beginCapture(.camera)
        case .scan:
            beginCapture(.scanner)
        }
    }

    private func launchCapture(_ intent: CaptureIntent) {
        switch intent {
        case .camera:
            openCamera()
        case .scanner:
            openScanner()
        case .photoLibrary:
            showsPhotoPicker = true
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCaptureFailure(
                "A camera is not available on this device. Use Photo Library instead."
            )
            return
        }
        captureRoute = .camera
    }

    private func openScanner() {
        guard VNDocumentCameraViewController.isSupported else {
            showCaptureFailure(
                "Document scanning is not available on this device."
            )
            return
        }
        captureRoute = .scanner
    }

    private func acceptPhoto(_ image: UIImage) {
        guard let account = destinationAccount else {
            showCaptureFailure("Choose the account that should receive this photo.")
            return
        }

        let timestamp = Date()
        let renderedImage = FireVaultPhotoOverlayRenderer.render(
            image: image,
            preferences: settings.preferences.overlay,
            technicianName: technicianName,
            account: account,
            timestamp: timestamp
        )

        do {
            try store.attachCapturedPhoto(renderedImage, to: account.id)
            selectedImage = renderedImage
            scannedPages = []
            mediaKind = .photo
            mediaAccountID = account.id
            saveStatus = "Photo saved to \(account.name)"
            captureRoute = nil
        } catch {
            showCaptureFailure(error.localizedDescription)
        }
    }

    private func acceptScan(_ pages: [UIImage]) {
        guard let firstPage = pages.first else {
            showCaptureFailure("The scanner did not return any pages.")
            return
        }
        guard let account = destinationAccount else {
            showCaptureFailure("Choose the account that should receive this scan.")
            return
        }

        do {
            try store.attachScannedDocument(pages, to: account.id)
            selectedImage = firstPage
            scannedPages = pages
            mediaKind = .scan
            mediaAccountID = account.id
            saveStatus = "Scan saved to \(account.name)"
            captureRoute = nil
        } catch {
            showCaptureFailure(error.localizedDescription)
        }
    }

    private func showCaptureFailure(_ message: String) {
        captureRoute = nil
        alertTitle = "Capture Unavailable"
        alertMessage = message
        showsAlert = true
    }
}

private struct NativeCaptureAccountPicker: View {
    let accounts: [FireVaultWorkspaceAccount]
    let selectedID: String?
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredAccounts: [FireVaultWorkspaceAccount] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? accounts : accounts.filter {
            [$0.name, $0.address, $0.accountId, $0.category]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
        return filtered.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredAccounts.isEmpty {
                    if accounts.isEmpty {
                        ContentUnavailableView(
                            "No Accounts Available",
                            systemImage: "building.2",
                            description: Text(
                                "Add an account or import the account CSV before capturing media."
                            )
                        )
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                } else {
                    Section("Photo or scan destination") {
                        ForEach(filteredAccounts) { account in
                            Button {
                                onSelect(account.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedID == account.id
                                          ? "checkmark.circle.fill"
                                          : "building.2")
                                        .font(.title3)
                                        .foregroundStyle(
                                            selectedID == account.id
                                                ? NativeShellPalette.green
                                                : NativeShellPalette.blue
                                        )
                                        .frame(width: 34)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(account.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(account.address)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                        if !account.accountId.isEmpty {
                                            Text("Account ID: \(account.accountId)")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                [
                                    account.name,
                                    account.address,
                                    account.accountId.isEmpty
                                        ? nil
                                        : "Account ID \(account.accountId)"
                                ]
                                .compactMap { $0 }
                                .joined(separator: ", ")
                            )
                            .accessibilityIdentifier("capture-account-\(account.id)")
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Name, address, or account ID")
            .navigationTitle("Choose Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

struct NativeSettingsView: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @State private var search = ""
    @State private var expandedSettingGroupID: String?
    @State private var isTechnicianGroupExpanded = false
    private let versionInfo = FireVaultVersionInfo()

    private var viewPreferences: FireVaultSettingsViewPreferences { settings.settingsView }
    private var usesCollapsibleSections: Bool { search.isEmpty }
    private var showsDescriptions: Bool {
        viewPreferences.mode == .advanced && viewPreferences.advancedShowDescriptions
    }
    private var showsStatus: Bool {
        viewPreferences.mode != .simple
            && (viewPreferences.mode != .advanced || viewPreferences.advancedShowStatus)
    }
    private var showsIcons: Bool {
        viewPreferences.mode != .simple
            && (viewPreferences.mode != .advanced || viewPreferences.advancedShowIcons)
    }
    private var showsSectionDescriptions: Bool {
        viewPreferences.mode == .advanced && viewPreferences.advancedShowSectionDescriptions
    }

    private var groups: [FireVaultNativeSettingsGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nativeGroups = NativeSettingsCatalog.groups.filter {
            settings.isFeatureVisible("settings.\($0.id)")
        }
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
                        if usesCollapsibleSections {
                            collapsibleSettingsSection(group)
                        } else {
                            settingsSection(group)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(NativeShellPalette.background)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .searchable(text: $search, prompt: "Search settings")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NativeShellPalette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .accessibilityIdentifier("native-settings-list")
            .animation(.snappy(duration: 0.24), value: expandedSettingGroupID)
            .animation(.snappy(duration: 0.24), value: isTechnicianGroupExpanded)
        }
        .listRowBackground(NativeShellPalette.surface)
        .listRowSeparatorTint(NativeShellPalette.hairline)
    }

    private var profileSection: some View {
        Section {
            DisclosureGroup(isExpanded: Binding(
                get: { isTechnicianGroupExpanded },
                set: { isExpanded in
                    withAnimation(.snappy(duration: 0.22)) {
                        isTechnicianGroupExpanded = isExpanded
                        if isExpanded { expandedSettingGroupID = nil }
                    }
                }
            )) {
                NavigationLink {
                    NativeTechnicianSettingsView(settings: settings)
                } label: {
                    Label("Technician Profile", systemImage: "person.text.rectangle")
                }

                NavigationLink {
                    NativeSettingsViewPreferencesView(settings: settings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preferred Settings View")
                            Text(settings.settingsView.mode.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "rectangle.3.group")
                            .foregroundStyle(NativeShellPalette.blue)
                    }
                }

                NavigationLink {
                    NativeAppearanceSettingsView(settings: settings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Appearance")
                            Text(settings.appearance.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: settings.appearance == .light ? "sun.max.fill" : "circle.lefthalf.filled")
                            .foregroundStyle(NativeShellPalette.amber)
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(NativeShellPalette.blue)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.preferences.technician.name.isEmpty ? "Technician Profile" : settings.preferences.technician.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text("FireVault Pro FREE TRIAL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NativeShellPalette.blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(payload.demoMode ? "Demo Mode" : "Field technician profile")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(settings.preferences.technician.name.isEmpty ? "Technician Profile" : settings.preferences.technician.name)
            .accessibilityValue(payload.demoMode ? "Demo Mode" : "Field technician profile")
            .accessibilityHint(isTechnicianGroupExpanded ? "Collapses technician settings" : "Expands technician settings")
        }
    }

    private func collapsibleSettingsSection(_ group: FireVaultNativeSettingsGroup) -> some View {
        Section {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedSettingGroupID == group.id },
                    set: { isExpanded in
                        withAnimation(.snappy(duration: 0.22)) {
                            expandedSettingGroupID = isExpanded ? group.id : nil
                            if isExpanded { isTechnicianGroupExpanded = false }
                        }
                    }
                )
            ) {
                ForEach(group.items) { item in
                    let status = item.displayStatus(nativeVersion: versionInfo.version)
                    settingsRow(item, group: group, status: status)
                }
            } label: {
                Label(group.title, systemImage: group.symbol)
                    .font(.headline)
                    .foregroundStyle(NativeShellPalette.tint(group.tint))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .listSectionSpacing(.compact)
        .listRowBackground(NativeShellPalette.surface)
        .listRowSeparatorTint(NativeShellPalette.hairline)
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
            if showsSectionDescriptions && !group.subtitle.isEmpty {
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
            status: showsStatus ? nativeStatus(for: item, fallback: status) : "",
            tint: NativeShellPalette.tint(group.tint),
            showsSubtitle: showsDescriptions,
            showsIcon: showsIcons
        )

        NavigationLink {
            nativeDestination(item.id)
        } label: { row }
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityValue(nativeStatus(for: item, fallback: status))
            .accessibilityHint("Opens \(item.title)")
    }

    private func nativeStatus(for item: FireVaultNativeSettingItem, fallback: String) -> String {
        switch item.id {
        case "gps": settings.gps.radiusStatus
        case "tech": settings.preferences.technician.name.isEmpty ? "Not configured" : settings.preferences.technician.name
        case "email": settings.preferences.email.defaultTo.isEmpty ? "Not configured" : "Configured"
        case "reports": settings.preferences.reports.format.capitalized
        case "overlay": "Configured"
        case "plusCodes": settings.preferences.plusCodes.enabled ? "On" : "Off"
        case "notifications": (settings.preferences.notifications?.isEnabled ?? true) ? "On" : "Off"
        case "webdav": settings.preferences.webDAV.enabled ? "Configured" : "Off"
        case "privacy": settings.preferences.privacy.enabled ? "On" : "Off"
        case "customerImport": "CSV"
        case "demo": store.demoMode ? "Active" : "Off"
        case "about": "Version \(versionInfo.version)"
        default: fallback
        }
    }

    @ViewBuilder
    private func nativeDestination(_ id: String) -> some View {
        switch id {
        case "tech": NativeTechnicianSettingsView(settings: settings)
        case "overlay": NativeOverlaySettingsView(settings: settings)
        case "gps": NativeGPSSettingsView(settings: settings, locationService: locationService)
        case "plusCodes": NativePlusCodeSettingsView(settings: settings, locationService: locationService)
        case "notifications": NativeNotificationSettingsView(settings: settings)
        case "reports": NativeReportSettingsView(settings: settings)
        case "email": NativeEmailSettingsView(settings: settings)
        case "cloudFiles": NativeStorageSettingsView(settings: settings)
        case "microsoftStorage": NativeMicrosoftStorageSettingsView(settings: settings)
        case "sync": NativeSyncSettingsView(settings: settings)
        case "customerImport": NativeCSVImportView(store: store)
        case "categories": NativeCategoriesSettingsView(settings: settings, store: store)
        case "backup": NativeBackupRestoreView(store: store)
        case "webdav": NativeWebDAVSettingsView(settings: settings)
        case "privacy": NativePrivacySettingsView(settings: settings)
        case "security": NativeSecuritySettingsView(settings: settings)
        case "manual": NativeManualView()
        case "demo": NativeDemoSettingsView(store: store)
        case "about":
            NativeAboutFireVaultView(
                versionInfo: versionInfo,
                payload: payload,
                store: store,
                settings: settings,
                breadcrumbs: breadcrumbs
            )
        default: NativeMigrationStatusView(
            title: "Setting Unavailable",
            symbol: "gearshape",
            message: "This setting is not available."
        )
        }
    }

}

struct FireVaultIPadSettingsWorkspace: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    @State private var selection = "tech"
    @State private var search = ""
    private let versionInfo = FireVaultVersionInfo()

    private var groups: [FireVaultNativeSettingsGroup] {
        let visible = NativeSettingsCatalog.groups.filter {
            settings.isFeatureVisible("settings.\($0.id)")
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visible }
        return visible.compactMap { group in
            let items = group.items.filter {
                [$0.title, $0.subtitle, group.title]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(query)
            }
            guard !items.isEmpty else { return nil }
            return .init(
                id: group.id,
                title: group.title,
                subtitle: group.subtitle,
                symbol: group.symbol,
                tint: group.tint,
                status: group.status,
                items: items
            )
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsNavigator
                .frame(width: 340)

            Rectangle()
                .fill(NativeShellPalette.hairline)
                .frame(width: 1)

            NavigationStack {
                destination(selection)
                    .id(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(NativeShellPalette.background)
        .tint(NativeShellPalette.blue)
        .accessibilityIdentifier("ipad-settings-workspace")
    }

    private var settingsNavigator: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SETTINGS")
                            .font(.caption2.bold())
                            .tracking(1.3)
                            .foregroundStyle(NativeShellPalette.blue)
                        Text("FireVault Pro")
                            .font(.title2.bold())
                    }
                    Spacer()
                    Text(versionInfo.version)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search settings", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .padding(16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if search.isEmpty {
                        settingsGroup(
                            title: "Technician",
                            symbol: "person.crop.circle.fill",
                            tint: NativeShellPalette.blue,
                            items: [
                                ("tech", "Technician Profile", "person.text.rectangle"),
                                ("settingsView", "Preferred Settings View", "rectangle.3.group"),
                                ("appearance", "Appearance", "circle.lefthalf.filled")
                            ]
                        )
                    }

                    ForEach(groups) { group in
                        settingsGroup(
                            title: group.title,
                            symbol: group.symbol,
                            tint: NativeShellPalette.tint(group.tint),
                            items: group.items.map { ($0.id, $0.title, $0.symbol) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(NativeShellPalette.navigationBackground.opacity(0.40))
    }

    private func settingsGroup(
        title: String,
        symbol: String,
        tint: Color,
        items: [(id: String, title: String, symbol: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.caption2.bold())
                .tracking(0.9)
                .foregroundStyle(tint)
                .padding(.horizontal, 8)

            ForEach(items, id: \.id) { item in
                let selected = selection == item.id
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = item.id
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(selected ? tint : .secondary)
                            .frame(width: 30, height: 30)
                            .background(tint.opacity(selected ? 0.17 : 0.07), in: RoundedRectangle(cornerRadius: 8))
                        Text(item.title)
                            .font(.subheadline.weight(selected ? .bold : .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if selected {
                            Image(systemName: "chevron.right")
                                .font(.caption2.bold())
                                .foregroundStyle(tint)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(minHeight: 44)
                    .background(
                        selected ? tint.opacity(0.11) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(tint.opacity(0.45), lineWidth: 1)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func destination(_ id: String) -> some View {
        switch id {
        case "tech": NativeTechnicianSettingsView(settings: settings)
        case "settingsView": NativeSettingsViewPreferencesView(settings: settings)
        case "appearance": NativeAppearanceSettingsView(settings: settings)
        case "overlay": NativeOverlaySettingsView(settings: settings)
        case "gps": NativeGPSSettingsView(settings: settings, locationService: locationService)
        case "plusCodes": NativePlusCodeSettingsView(settings: settings, locationService: locationService)
        case "notifications": NativeNotificationSettingsView(settings: settings)
        case "reports": NativeReportSettingsView(settings: settings)
        case "email": NativeEmailSettingsView(settings: settings)
        case "cloudFiles": NativeStorageSettingsView(settings: settings)
        case "microsoftStorage": NativeMicrosoftStorageSettingsView(settings: settings)
        case "sync": NativeSyncSettingsView(settings: settings)
        case "customerImport": NativeCSVImportView(store: store)
        case "categories": NativeCategoriesSettingsView(settings: settings, store: store)
        case "backup": NativeBackupRestoreView(store: store)
        case "webdav": NativeWebDAVSettingsView(settings: settings)
        case "privacy": NativePrivacySettingsView(settings: settings)
        case "security": NativeSecuritySettingsView(settings: settings)
        case "manual": NativeManualView()
        case "demo": NativeDemoSettingsView(store: store)
        case "about":
            NativeAboutFireVaultView(
                versionInfo: versionInfo,
                payload: payload,
                store: store,
                settings: settings,
                breadcrumbs: breadcrumbs
            )
        default:
            ContentUnavailableView(
                "Choose a Setting",
                systemImage: "slider.horizontal.3",
                description: Text("Select a settings page from the list.")
            )
        }
    }
}

private struct NativeGPSSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @State private var draft: FireVaultGPSPreferences
    @State private var saved = false

    init(settings: FireVaultNativeSettingsStore, locationService: FireVaultLocationService) {
        self.settings = settings
        self.locationService = locationService
        let current = settings.gps
        _draft = State(initialValue: current)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Map provider", value: "Apple Maps")

                Picker("Default map layer", selection: Binding(
                    get: { draft.defaultMapLayer ?? "standard" },
                    set: { draft.defaultMapLayer = $0 }
                )) {
                    Label("Standard", systemImage: "map").tag("standard")
                    Label("Satellite", systemImage: "globe.americas.fill").tag("satellite")
                    Label("Hybrid", systemImage: "square.3.layers.3d").tag("hybrid")
                }

                Toggle("High-accuracy GPS", isOn: $draft.highAccuracy)

                VStack(spacing: 8) {
                    HStack {
                        Text("Nearby radius")
                            .font(.headline)
                        Spacer()
                        Text(FireVaultGPSPreferences.radiusLabel(draft.nearbyRadiusMiles))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(NativeShellPalette.blue)
                            .contentTransition(.numericText())
                    }

                    FVRadiusWheelPicker(
                        selection: $draft.nearbyRadiusMiles
                    )
                }
            } header: {
                Text("Map Preferences")
            } footer: {
                Text("This distance controls the accounts displayed on the Nearby map and list.")
            }

            Section("GPS Tools") {
                Toggle("Show GPS capture controls", isOn: $draft.gpsToolsEnabled)
                Toggle("Include coordinates in reports", isOn: $draft.includeCoordinatesInReports)
                Toggle("Address assistance", isOn: $draft.addressAssistanceEnabled)
            }

            Section {
                Picker(
                    "Minimum unrecognized stop",
                    selection: Binding(
                        get: { draft.resolvedTripLogMinimumUnknownStopMinutes },
                        set: { draft.tripLogMinimumUnknownStopMinutes = $0 }
                    )
                ) {
                    Text("5 minutes").tag(5)
                    Text("7 minutes").tag(7)
                    Text("10 minutes").tag(10)
                }

                Toggle(
                    "Reject poor GPS readings",
                    isOn: Binding(
                        get: { draft.rejectsPoorAccuracyStops },
                        set: { draft.tripLogRejectPoorAccuracyStops = $0 }
                    )
                )

                Toggle(
                    "Merge nearby duplicate stops",
                    isOn: Binding(
                        get: { draft.mergesNearbyStops },
                        set: { draft.tripLogMergeNearbyStops = $0 }
                    )
                )
            } header: {
                Text("Trip Log Stop Detection")
            } footer: {
                Text("Five minutes is recommended. GPS filtering prevents signal loss from creating false stops. Duplicate merging combines repeated detections at the same place within 15 minutes.")
            }

            Section("Diagnostics") {
                NavigationLink {
                    FireVaultGPSDiagnosticsView(
                        locationService: locationService,
                        highAccuracy: draft.highAccuracy
                    )
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GPS Diagnostics")
                                .font(.headline)
                            Text("Live accuracy, speed, direction, altitude, and signal charts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.title3)
                            .foregroundStyle(NativeShellPalette.blue)
                    }
                }
            }

            if saved {
                Section {
                    Label("GPS & Maps settings saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NativeShellPalette.green)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
        }
        .navigationTitle("GPS & Maps")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 82)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: save)
            }
        }
        .onChange(of: draft) { _, _ in saved = false }
        .onDisappear {
            save()
        }
    }

    private func save() {
        settings.saveGPS(draft)
        saved = true
    }
}

private struct FireVaultGPSDiagnosticSample: Identifiable {
    let id = UUID()
    let time: Date
    let horizontalAccuracyFeet: Double
    let altitudeFeet: Double
    let speedMPH: Double
}

private struct FireVaultGPSDiagnosticsView: View {
    @ObservedObject var locationService: FireVaultLocationService
    let highAccuracy: Bool
    @State private var samples: [FireVaultGPSDiagnosticSample] = []

    private var location: CLLocation? { locationService.latestLocation }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                statusCard
                liveMetrics
                signalChart
                altitudeChart
                speedChart
                systemDetails
            }
            .padding(16)
            .padding(.bottom, 90)
        }
        .background(NativeShellPalette.background)
        .navigationTitle("GPS Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    locationService.requestCurrentLocation(highAccuracy: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh GPS reading")
            }
        }
        .onAppear {
            locationService.startDiagnosticsUpdates(highAccuracy: highAccuracy)
            append(locationService.latestLocation)
        }
        .onDisappear {
            locationService.stopDiagnosticsUpdates()
        }
        .onReceive(locationService.$latestLocation.compactMap { $0 }) { updated in
            append(updated)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusTint.opacity(0.15))
                Image(systemName: "location.fill")
                    .font(.title2.bold())
                    .foregroundStyle(statusTint)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(locationService.isDiagnosticsTracking ? "LIVE GPS SIGNAL" : "GPS STATUS")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(.secondary)
                Text(locationService.statusText)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Text(highAccuracy ? "High-accuracy preference enabled" : "Balanced-accuracy preference enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var liveMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            diagnosticHeader("Live Measurements", symbol: "dot.radiowaves.left.and.right")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                metric("Latitude", coordinate(location?.coordinate.latitude), "location.north")
                metric("Longitude", coordinate(location?.coordinate.longitude), "location.north")
                metric("Accuracy", feet(location?.horizontalAccuracy, prefix: "±"), "scope")
                metric("Vertical Accuracy", feet(location?.verticalAccuracy, prefix: "±"), "arrow.up.and.down")
                metric("Altitude", feet(location?.altitude), "mountain.2")
                metric("Speed", speed(location?.speed), "speedometer")
                metric("Direction", course(location?.course), "location.north.fill")
                metric("Reading Age", readingAge, "clock")
            }
        }
        .diagnosticPanel()
    }

    private var signalChart: some View {
        chartPanel("Horizontal Accuracy", subtitle: "Lower is better", symbol: "scope") {
            Chart(samples) { sample in
                AreaMark(x: .value("Time", sample.time), y: .value("Feet", sample.horizontalAccuracyFeet))
                    .foregroundStyle(NativeShellPalette.blue.opacity(0.18))
                LineMark(x: .value("Time", sample.time), y: .value("Feet", sample.horizontalAccuracyFeet))
                    .foregroundStyle(NativeShellPalette.blue)
                    .interpolationMethod(.catmullRom)
            }
        }
    }

    private var altitudeChart: some View {
        chartPanel("Elevation", subtitle: "GPS altitude in feet", symbol: "mountain.2.fill") {
            Chart(samples) { sample in
                LineMark(x: .value("Time", sample.time), y: .value("Feet", sample.altitudeFeet))
                    .foregroundStyle(NativeShellPalette.green)
                    .interpolationMethod(.catmullRom)
            }
        }
    }

    private var speedChart: some View {
        chartPanel("Speed", subtitle: "Live movement in miles per hour", symbol: "speedometer") {
            Chart(samples) { sample in
                BarMark(x: .value("Time", sample.time), y: .value("MPH", sample.speedMPH))
                    .foregroundStyle(NativeShellPalette.amber.gradient)
            }
        }
    }

    private var systemDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            diagnosticHeader("Receiver & Source", symbol: "antenna.radiowaves.left.and.right")
            detailRow("Permission", authorizationText)
            detailRow("Floor", location?.floor.map { "Level \($0.level)" } ?? "Unavailable")
            detailRow("Timestamp", location?.timestamp.formatted(date: .abbreviated, time: .standard) ?? "Waiting for GPS")
            detailRow("Simulated by software", sourceText(software: true))
            detailRow("External accessory", sourceText(software: false))
        }
        .diagnosticPanel()
    }

    private func append(_ location: CLLocation?) {
        guard let location, location.horizontalAccuracy >= 0 else { return }
        guard samples.last?.time != location.timestamp else { return }
        samples.append(.init(
            time: location.timestamp,
            horizontalAccuracyFeet: location.horizontalAccuracy * 3.28084,
            altitudeFeet: location.altitude * 3.28084,
            speedMPH: max(0, location.speed) * 2.236_936
        ))
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(10)
        .background(NativeShellPalette.navigationBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func diagnosticHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).fontWeight(.semibold).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func chartPanel<Content: View>(
        _ title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            diagnosticHeader(title, symbol: symbol)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content().frame(height: 130)
            if samples.count < 2 {
                Text("Collecting live samples…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .diagnosticPanel()
    }

    private var statusTint: Color {
        locationService.isDiagnosticsTracking ? NativeShellPalette.green : NativeShellPalette.amber
    }

    private var authorizationText: String {
        switch locationService.authorizationStatus {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using App"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not Requested"
        @unknown default: "Unknown"
        }
    }

    private var readingAge: String {
        guard let timestamp = location?.timestamp else { return "—" }
        return String(format: "%.1f sec", max(0, Date().timeIntervalSince(timestamp)))
    }

    private func coordinate(_ value: CLLocationDegrees?) -> String {
        guard let value else { return "—" }
        return String(format: "%.6f°", value)
    }

    private func feet(_ meters: CLLocationDistance?, prefix: String = "") -> String {
        guard let meters, meters >= 0 else { return "—" }
        return "\(prefix)\(Int((meters * 3.28084).rounded())) ft"
    }

    private func speed(_ metersPerSecond: CLLocationSpeed?) -> String {
        guard let metersPerSecond, metersPerSecond >= 0 else { return "—" }
        return String(format: "%.1f mph", metersPerSecond * 2.236_936)
    }

    private func course(_ degrees: CLLocationDirection?) -> String {
        guard let degrees, degrees >= 0 else { return "—" }
        return "\(Int(degrees.rounded()))°"
    }

    private func sourceText(software: Bool) -> String {
        guard let source = location?.sourceInformation else { return "Unavailable" }
        return (software ? source.isSimulatedBySoftware : source.isProducedByAccessory) ? "Yes" : "No"
    }
}

private extension View {
    func diagnosticPanel() -> some View {
        padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FVRadiusWheelPicker: View {
    @Binding var selection: Double

    private var options: [Double] {
        guard !FireVaultGPSPreferences.radiusOptions.contains(selection) else {
            return FireVaultGPSPreferences.radiusOptions
        }
        return (FireVaultGPSPreferences.radiusOptions + [selection]).sorted()
    }

    var body: some View {
        Picker("Nearby radius", selection: $selection.animation(.snappy(duration: 0.22))) {
            ForEach(options, id: \.self) { radius in
                Text(FireVaultGPSPreferences.radiusLabel(radius))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .tag(radius)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipped()
        .background(.black.opacity(0.18))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityLabel("Nearby radius")
        .accessibilityValue(FireVaultGPSPreferences.radiusLabel(selection))
        .accessibilityHint("Swipe up or down to change the map radius")
        .accessibilityIdentifier("settings-radius-wheel")
    }
}

struct FVHorizontalRadiusPicker: View {
    @Binding var selection: Double
    var hapticsEnabled = true
    @State private var centeredRadius: Double?

    private var options: [Double] {
        guard !FireVaultGPSPreferences.radiusOptions.contains(selection) else {
            return FireVaultGPSPreferences.radiusOptions
        }
        return (FireVaultGPSPreferences.radiusOptions + [selection]).sorted()
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Text("RANGE • MI")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.05)
                    .foregroundStyle(NativeShellPalette.amber.opacity(0.86))
            }
                .accessibilityHidden(true)

            ZStack {
                HStack(spacing: 15) {
                    ForEach(0..<9, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(index == 4 ? 0.35 : 0.12))
                            .frame(width: 1, height: index == 4 ? 24 : 12)
                    }
                }
                .allowsHitTesting(false)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 7) {
                        ForEach(options, id: \.self) { radius in
                            Button {
                                select(radius)
                            } label: {
                                Text(FireVaultGPSPreferences.radiusWheelLabel(radius))
                                    .font(.system(size: 15, weight: radius == selection ? .bold : .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(NativeShellPalette.amber.opacity(radius == selection ? 1 : 0.62))
                                    .frame(minWidth: 32, minHeight: 28)
                                    .background {
                                        if radius == selection {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(NativeShellPalette.amber, lineWidth: 1.5)
                                                .shadow(color: NativeShellPalette.amber.opacity(0.45), radius: 5)
                                        }
                                    }
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .id(radius)
                            .accessibilityLabel("\(FireVaultGPSPreferences.radiusLabel(radius)) radius")
                            .accessibilityAddTraits(radius == selection ? .isSelected : [])
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 66, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $centeredRadius, anchor: .center)
                .frame(width: 165, height: 32)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.15),
                            .init(color: .black, location: 0.85),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }

                Capsule()
                    .fill(NativeShellPalette.amber)
                    .frame(width: 2, height: 5)
                    .offset(y: 15)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.09, blue: 0.035),
                    Color(red: 0.035, green: 0.042, blue: 0.050),
                    Color.black.opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(NativeShellPalette.amber.opacity(0.46), lineWidth: 1)
        }
        .shadow(color: NativeShellPalette.amber.opacity(0.14), radius: 6, y: 3)
        .sensoryFeedback(.selection, trigger: selection) { oldValue, newValue in
            hapticsEnabled && oldValue != newValue
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nearby radius")
        .accessibilityValue(FireVaultGPSPreferences.radiusLabel(selection))
        .accessibilityHint("Swipe left or right to change the map radius")
        .accessibilityIdentifier("nearby-horizontal-radius-picker")
        .task {
            centeredRadius = selection
        }
        .onChange(of: centeredRadius) { _, radius in
            guard let radius, radius != selection else { return }
            selection = radius
        }
        .onChange(of: selection) { _, radius in
            guard centeredRadius != radius else { return }
            withAnimation(.snappy(duration: 0.22)) {
                centeredRadius = radius
            }
        }
    }

    private func select(_ radius: Double) {
        withAnimation(.snappy(duration: 0.22)) {
            centeredRadius = radius
            selection = radius
        }
    }
}

private struct NativeAboutFireVaultView: View {
    let versionInfo: FireVaultVersionInfo
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @State private var showsDeveloperCenter = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    FireVaultBrandMark()
                        .scaleEffect(1.32)
                        .padding(.vertical, 8)
                    Text("Field information, organized around the service call.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .accessibilityElement(children: .combine)
            }

            Section("Purpose") {
                FireVaultJustifiedText(
                    "FireVault Pro is a field workspace for organizing customer accounts, equipment, arrival points, service notes, photographs, scanned documents, and Trip Log records. It is intended to reduce time spent searching for site information before and during a service visit."
                )
                FireVaultJustifiedText(
                    "The application supports both iPhone and iPad workflows, keeps demonstration records separate from live data, and provides configurable reporting, mapping, storage, privacy, and photo-overlay tools."
                )
            }

            Section("Data & Privacy") {
                Label("Live and Demo workspaces remain separate.", systemImage: "square.stack.3d.up.fill")
                Label("Location access is used for Nearby, Arrival Maps, and Trip Log features.", systemImage: "location.fill")
                Label("Storage and report-delivery services operate only when configured.", systemImage: "externaldrive.fill")
                Text("Review individual permissions and service connections in Settings. FireVault does not treat a configured destination as connected until its authentication is complete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Developer") {
                LabeledContent("Designed and developed by", value: "David Bannerman")
                LabeledContent("Professional background", value: "Fire alarm technician")
                Link("Contact David Bannerman", destination: URL(string: "mailto:David@Bannerman.us")!)
            }

            Section("Application") {
                LabeledContent("Version", value: versionInfo.version)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 4) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showsDeveloperCenter = true
                    }
                    .accessibilityHint("Version information")
                LabeledContent("Build", value: versionInfo.build)
                LabeledContent("Updated", value: updatedAtText)
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("About FireVault Pro")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .navigationDestination(isPresented: $showsDeveloperCenter) {
            FireVaultDeveloperCenterView(
                versionInfo: versionInfo,
                payload: payload,
                store: store,
                settings: settings,
                breadcrumbs: breadcrumbs
            )
        }
    }

    private var updatedAtText: String {
        let date = Bundle.main.executableURL
            .flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            ?? Date()
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct FireVaultJustifiedText: UIViewRepresentable {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineSpacing = 2
        view.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraph
            ]
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let size = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: size.height)
    }
}

private struct FireVaultDeveloperCenterView: View {
    let versionInfo: FireVaultVersionInfo
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @StateObject private var runner = FireVaultDiagnosticRunner()
    @State private var copiedDiagnostics = false
    @State private var confirmsAITest = false

    private var enabledFeatureCount: Int {
        FireVaultDeveloperFeatureCatalog.features.filter {
            settings.developer.isEnabled($0.id)
        }.count
    }

    private var diagnosticHeader: String {
        return """
        FireVault \(versionInfo.displayText)
        Mode: \(payload.demoMode ? "Demo" : "Production")
        Settings view: \(settings.settingsView.mode.title)
        Accounts: \(store.accounts.count)
        Selected tab: \(store.selectedTab.title)
        Location: \(payload.locationStatus)
        Simple features: \(enabledFeatureCount)/\(FireVaultDeveloperFeatureCatalog.features.count) enabled
        """
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task {
                        await runner.runSafeChecks(
                            accounts: store.accounts,
                            preferences: settings.preferences
                        )
                    }
                } label: {
                    Label(
                        runner.isRunning ? "Running Diagnostics…" : "Run All Safe Diagnostics",
                        systemImage: runner.isRunning ? "hourglass" : "stethoscope"
                    )
                }
                .disabled(runner.isRunning)

                Button("Test AI Edge Function", systemImage: "sparkles") {
                    confirmsAITest = true
                }
                .disabled(runner.isRunning)
            } header: {
                Text("Test Console")
            } footer: {
                Text("Safe diagnostics test the local vault, account integrity, storage, authentication, and read access to both Supabase Trip Log tables.")
            }

            if runner.results.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Test Results",
                        systemImage: "waveform.path.ecg",
                        description: Text("Run diagnostics to test FireVault Pro's local vault and connected services.")
                    )
                }
            } else {
                Section("Results") {
                    ForEach(runner.results) { result in
                        FireVaultDiagnosticResultRow(result: result)
                    }
                }
            }

            Section("Runtime") {
                LabeledContent("Version", value: versionInfo.displayText)
                LabeledContent("Environment", value: payload.demoMode ? "Demo" : "Production")
                LabeledContent("Accounts loaded", value: "\(store.accounts.count)")
                LabeledContent("Settings view", value: settings.settingsView.mode.title)
                LabeledContent("Mapped accounts", value: "\(store.mappedAccountCount)")
                LabeledContent("Unmapped accounts", value: "\(store.unmappedAccountCount)")

                Button(copiedDiagnostics ? "Diagnostics Copied" : "Copy Diagnostics", systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = diagnosticHeader + "\n\n" + runner.report
                    copiedDiagnostics = true
                }
            }

            Section {
                NavigationLink {
                    FireVaultFieldTestDashboard(
                        versionInfo: versionInfo,
                        demoMode: payload.demoMode,
                        store: store,
                        settings: settings,
                        breadcrumbs: breadcrumbs
                    )
                } label: {
                    Label("Field Test Dashboard", systemImage: "gauge.with.dots.needle.50percent")
                }

                NavigationLink {
                    FireVaultSimpleTemplateDeveloperView(settings: settings)
                } label: {
                    Label("Simple Mode Template", systemImage: "switch.2")
                }

                Button("Clear Test Results", systemImage: "clear") {
                    runner.clear()
                }
                .disabled(runner.results.isEmpty || runner.isRunning)
            } header: {
                Text("Developer Tools")
            } footer: {
                Text("A production database write test will require a dedicated diagnostic table migration. FireVault Pro does not write test records into customer or Trip Log tables.")
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Developer Center")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Run AI Endpoint Test?", isPresented: $confirmsAITest) {
            Button("Cancel", role: .cancel) {}
            Button("Run Test") {
                Task { await runner.runAIEndpointCheck() }
            }
        } message: {
            Text("This sends a diagnostic request containing no customer data. It uses a small amount of OpenAI API credit.")
        }
    }
}

private struct FireVaultSimpleTemplateDeveloperView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var showsResetConfirmation = false

    var body: some View {
        List {
            ForEach(FireVaultDeveloperFeatureCatalog.pages, id: \.self) { page in
                Section(page) {
                    ForEach(FireVaultDeveloperFeatureCatalog.features.filter { $0.page == page }) { feature in
                        developerFeatureToggle(feature)
                    }
                }
            }

            Section {
                Button("Reset Simple Template", systemImage: "arrow.counterclockwise", role: .destructive) {
                    showsResetConfirmation = true
                }
            } footer: {
                Text("Resetting enables every Simple-mode feature without deleting FireVault Pro data.")
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Simple Template")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset Simple Template?", isPresented: $showsResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { settings.resetSimpleFeatures() }
        } message: {
            Text("Every feature will be enabled in Simple mode.")
        }
    }

    private func developerFeatureToggle(_ feature: FireVaultDeveloperFeature) -> some View {
        let enabled = Binding<Bool>(
            get: { settings.developer.isEnabled(feature.id) },
            set: { newValue in
                settings.setSimpleFeature(feature.id, enabled: newValue)
            }
        )
        return Toggle(feature.title, isOn: enabled)
    }
}

private struct FireVaultDiagnosticResultRow: View {
    let result: FireVaultDiagnosticResult

    private var color: Color {
        switch result.status {
        case .running: NativeShellPalette.blue
        case .passed: NativeShellPalette.green
        case .warning: NativeShellPalette.amber
        case .failed: NativeShellPalette.red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: result.status.symbol)
                .foregroundStyle(color)
                .frame(width: 24)
                .symbolEffect(.pulse, isActive: result.status == .running)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.title)
                        .font(.subheadline.bold())
                    Spacer()
                    if result.durationMilliseconds > 0 {
                        Text("\(result.durationMilliseconds) ms")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct FVSettingsRow: View {
    let item: FireVaultNativeSettingItem
    let status: String
    let tint: Color
    let showsSubtitle: Bool
    let showsIcon: Bool

    var body: some View {
        HStack(spacing: 13) {
            if showsIcon {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if showsSubtitle && !item.subtitle.isEmpty {
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

struct NativeShellCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .nativeSurfaceCard()
    }
}

extension View {
    func nativeSurfaceCard(
        cornerRadius: CGFloat = NativeShellMetrics.cardRadius,
        emphasized: Bool = false
    ) -> some View {
        background(
            NativeShellPalette.surface,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    emphasized ? NativeShellPalette.blue.opacity(0.7) : NativeShellPalette.hairline,
                    lineWidth: emphasized ? 1.5 : 1
                )
        }
        .shadow(
            color: .black.opacity(emphasized ? 0.31 : 0.18),
            radius: emphasized ? 9 : 7,
            x: 0,
            y: emphasized ? 5 : 3
        )
    }

    func nativeMapFrame(cornerRadius: CGFloat = NativeShellMetrics.mapRadius) -> some View {
        clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(NativeShellPalette.mapEdge, lineWidth: 2)
                    .shadow(color: .black.opacity(0.52), radius: 3, x: 0, y: 2)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 5)
    }

    func nativeMetadataPill(tint: Color) -> some View {
        self.font(.caption2.bold()).foregroundStyle(tint).padding(.horizontal, 7).padding(.vertical, 3).background(tint.opacity(0.12), in: Capsule())
    }
}

enum NativeShellMetrics {
    static let cardRadius: CGFloat = 18
    static let mapRadius: CGFloat = 22
    static let navigationRadius: CGFloat = 20
    static let navigationItemHeight: CGFloat = 50
    static let pageHorizontalPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 10
}

enum NativeShellPalette {
    static let background = adaptive(
        light: UIColor(red: 0.957, green: 0.941, blue: 0.902, alpha: 1),
        dark: UIColor(red: 0.028, green: 0.043, blue: 0.061, alpha: 1)
    )
    static let surface = adaptive(
        light: UIColor(red: 1.000, green: 0.992, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.070, green: 0.095, blue: 0.125, alpha: 1)
    )
    static let blue = adaptive(
        light: UIColor(red: 0.08, green: 0.39, blue: 0.68, alpha: 1),
        dark: UIColor(red: 0.24, green: 0.67, blue: 1.0, alpha: 1)
    )
    static let green = adaptive(
        light: UIColor(red: 0.08, green: 0.48, blue: 0.31, alpha: 1),
        dark: UIColor(red: 0.23, green: 0.86, blue: 0.58, alpha: 1)
    )
    static let amber = adaptive(
        light: UIColor(red: 0.66, green: 0.39, blue: 0.04, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.69, blue: 0.26, alpha: 1)
    )
    static let red = adaptive(
        light: UIColor(red: 0.76, green: 0.12, blue: 0.16, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.34, blue: 0.40, alpha: 1)
    )
    static let purple = adaptive(
        light: UIColor(red: 0.42, green: 0.23, blue: 0.68, alpha: 1),
        dark: UIColor(red: 0.68, green: 0.48, blue: 1.0, alpha: 1)
    )
    static let navigationBackground = adaptive(
        light: UIColor(red: 0.925, green: 0.894, blue: 0.835, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.061, blue: 0.082, alpha: 1)
    )
    static let navigationInactive = adaptive(
        light: UIColor(red: 0.36, green: 0.34, blue: 0.30, alpha: 1),
        dark: UIColor(red: 0.60, green: 0.65, blue: 0.72, alpha: 1)
    )
    static let navigationDivider = adaptive(
        light: UIColor(red: 0.45, green: 0.39, blue: 0.31, alpha: 0.22),
        dark: UIColor(white: 1, alpha: 0.14)
    )
    static let hairline = adaptive(
        light: UIColor(white: 0.16, alpha: 0.12),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    static let mapEdge = adaptive(
        light: UIColor(white: 0.10, alpha: 0.62),
        dark: UIColor(white: 0, alpha: 0.78)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
    static func tint(_ name: String) -> Color {
        switch name { case "green": green; case "amber": amber; case "red": red; case "purple": purple; default: blue }
    }
}
