//
//  NativeAppShell.swift
//  FireVault
//
//  Native everyday navigation for Build 1.07.01.
//

import SwiftUI
import Combine
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
    @ObservedObject var locationService: FireVaultLocationService
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
                        locationService: locationService
                    )
                case .accounts: NativeAccountsView(payload: payload, store: store)
                case .photo: NativePhotoView(store: store, settings: settings)
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
    @ObservedObject var locationService: FireVaultLocationService
    @State private var selectedID: String?
    @State private var showGeocodingConsent = false
    @State private var showMappingDetails = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var scrollAccountID: String?
    @State private var accountScrollWasActive = false
    @State private var suppressNextIdleFocus = false
    @State private var delayedMapFocusTask: Task<Void, Never>?

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

            map
                .padding(.horizontal, 16)

            accountList
        }
        .padding(.top, 4)
        .task {
            scrollAccountID = nearbyRows.first?.id
            if payload.demoMode {
                cameraPosition = .region(overviewRegion)
            } else if locationService.coordinate != nil {
                centerMapOnUser()
            } else {
                locationService.requestMapRecenter(highAccuracy: settings.gps.highAccuracy)
            }
        }
        .onChange(of: store.nearbyResetRequestID) { _, _ in
            resetNearby()
        }
        .onChange(of: locationService.mapRecenterRequestID) { _, _ in
            guard !payload.demoMode else { return }
            resetNearby()
        }
        .onChange(of: store.geocodingProgress?.phase) { _, phase in
            if phase == .complete {
                showMappingDetails = false
            }
        }
        .onDisappear {
            delayedMapFocusTask?.cancel()
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
            Text("FireVault sends only street, city, state, and ZIP fields to the U.S. Census Geocoder, then uses Apple Maps for unmatched addresses. Account names, IDs, notes, photos, and files remain on this iPhone. Returned coordinates are saved locally.")
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(payload.demoMode ? "DEMO VAULT" : "FIELD VAULT")
                    .font(.caption2.bold()).tracking(1.2)
                    .foregroundStyle(payload.demoMode ? NativeShellPalette.amber : NativeShellPalette.green)
                Text(payload.locationStatus).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(payload.todayWeekday)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(payload.todayDate)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today, \(payload.todayWeekday), \(payload.todayDate)")
        }
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
                .frame(height: 270)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1) }
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
                .overlay(alignment: .bottomTrailing) {
                    if let selected {
                        HStack(spacing: 8) {
                            Button {
                                store.call(selected.account.phone)
                            } label: {
                                Image(systemName: "phone.fill")
                                    .font(.headline)
                                    .foregroundStyle(selectedHasPhone ? NativeShellPalette.green : .secondary)
                                    .frame(width: 44, height: 44)
                                    .background(NativeShellPalette.surface, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!selectedHasPhone)
                            .accessibilityLabel("Call \(selected.account.name)")
                            .accessibilityValue(selectedHasPhone ? selected.account.phone : "No phone number")
                            .accessibilityIdentifier("nearby-map-call")

                            Button {
                                guard let account = selectedWorkspaceAccount else { return }
                                store.openRoute(for: account)
                            } label: {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.headline)
                                    .foregroundStyle(NativeShellPalette.blue)
                                    .frame(width: 44, height: 44)
                                    .background(NativeShellPalette.surface, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedWorkspaceAccount == nil)
                            .accessibilityLabel("Route to \(selected.account.name)")
                            .accessibilityIdentifier("nearby-map-route")
                        }
                        .padding(7)
                        .background(Color.black.opacity(0.88), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.16), lineWidth: 1)
                        }
                        .padding(10)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    FVRadiusWheelPicker(
                        selection: nearbyRadiusBinding,
                        presentation: .map
                    )
                    .padding(10)
                }
                .accessibilityIdentifier("nearby-fixed-map")
            }
        }
    }

    private var nearbyRadiusBinding: Binding<Double> {
        Binding(
            get: { settings.gps.nearbyRadiusMiles },
            set: updateNearbyRadius
        )
    }

    private func updateNearbyRadius(_ radius: Double) {
        guard radius != settings.gps.nearbyRadiusMiles else { return }

        var updated = settings.gps
        updated.nearbyRadiusMiles = radius
        settings.saveGPS(updated)

        delayedMapFocusTask?.cancel()
        accountScrollWasActive = false
        selectedID = nil
        scrollAccountID = nearbyRows.first?.id

        withAnimation(.easeInOut(duration: 0.35)) {
            if payload.demoMode {
                cameraPosition = .region(overviewRegion)
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
            HStack {
                Text("NEARBY ACCOUNTS • \(settings.gps.nearbyRadiusMiles.formatted(.number.precision(.fractionLength(0...2)))) MI")
                    .font(.caption.bold()).tracking(1.2).foregroundStyle(.secondary)
                Spacer()
                Text("\(nearbyRows.count)").foregroundStyle(.secondary)
            }
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
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(nearbyRows.enumerated()), id: \.element.id) { index, row in
                            accountCard(row, index: index)
                                .id(row.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .scrollPosition(id: $scrollAccountID, anchor: .top)
                .scrollTargetBehavior(
                    .viewAligned(limitBehavior: .never, anchor: .top)
                )
                .onScrollPhaseChange { _, newPhase in
                    if newPhase.isScrolling {
                        accountScrollWasActive = true
                        delayedMapFocusTask?.cancel()
                    } else if newPhase == .idle, accountScrollWasActive {
                        accountScrollWasActive = false
                        if suppressNextIdleFocus {
                            suppressNextIdleFocus = false
                        } else {
                            scheduleTopAccountFocus()
                        }
                    }
                }
                .accessibilityIdentifier("nearby-account-scroll")
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func accountCard(
        _ row: FireVaultNativeNearbyAccount,
        index: Int
    ) -> some View {
        Button {
            selectAccount(row, scrollToCard: false)
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
            .background(
                selectedID == row.id
                    ? NativeShellPalette.blue.opacity(0.12)
                    : NativeShellPalette.surface,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        selectedID == row.id
                            ? NativeShellPalette.blue.opacity(0.82)
                            : .white.opacity(0.07),
                        lineWidth: selectedID == row.id ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.55, maximumDistance: 24) {
            delayedMapFocusTask?.cancel()
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

    private func scheduleTopAccountFocus() {
        delayedMapFocusTask?.cancel()
        guard let requestedID = scrollAccountID else { return }

        delayedMapFocusTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  !accountScrollWasActive,
                  scrollAccountID == requestedID,
                  let row = nearbyRows.first(where: { $0.id == requestedID }) else {
                return
            }
            selectAccount(row, scrollToCard: false)
        }
    }

    private func selectAccount(
        _ row: FireVaultNativeNearbyAccount,
        scrollToCard: Bool
    ) {
        guard let coordinate = row.account.coordinate else { return }
        selectedID = row.id
        store.selectCaptureAccount(row.account.id)
        if scrollToCard {
            withAnimation(.snappy(duration: 0.28)) {
                scrollAccountID = row.id
            }
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(
                FireVaultNearbyMapCamera.accountRegion(coordinate: coordinate)
            )
        }
    }

    private func centerMapOnUser() {
        guard let coordinate = locationService.coordinate else { return }
        selectedID = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(
                FireVaultNearbyMapCamera.userRegion(
                    coordinate: coordinate,
                    radiusMiles: settings.gps.nearbyRadiusMiles
                )
            )
        }
    }

    private func resetNearby() {
        delayedMapFocusTask?.cancel()
        accountScrollWasActive = false
        selectedID = nil

        if let closestID = nearbyRows.first?.id {
            if scrollAccountID != closestID {
                suppressNextIdleFocus = true
                withAnimation(.smooth(duration: 0.35)) {
                    scrollAccountID = closestID
                }
            }
        } else {
            scrollAccountID = nil
        }

        if payload.demoMode {
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraPosition = .region(overviewRegion)
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
    @ObservedObject var settings: FireVaultNativeSettingsStore
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
                VStack(spacing: 18) {
                    destinationAccountCard

                    if let selectedImage {
                        imagePreview(selectedImage)

                        if scannedPages.count > 1 {
                            scannedPageStrip
                        }

                        Label(
                            mediaKind == .scan
                                ? "\(scannedPages.count) scanned page\(scannedPages.count == 1 ? "" : "s")"
                                : "Photo overlay applied",
                            systemImage: mediaKind == .scan
                                ? "doc.viewfinder.fill"
                                : "camera.filters"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                        if !saveStatus.isEmpty {
                            Label(saveStatus, systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NativeShellPalette.green)
                                .accessibilityIdentifier("native-media-save-status")
                        }
                    } else {
                        ContentUnavailableView(
                            "Capture Field Media",
                            systemImage: "camera.fill",
                            description: Text(
                                "Take a photo, scan a multi-page document, or choose an existing image."
                            )
                        )
                        .frame(minHeight: 300)
                    }

                    captureControls
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeShellPalette.background)
            .navigationTitle("Photo")
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

    private func imagePreview(_ image: UIImage) -> some View {
        let aspectRatio = max(0.35, image.size.width / max(image.size.height, 1))

        return Image(uiImage: image)
            .resizable()
            .scaledToFit()
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: 470)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            [
                mediaKind == .scan
                    ? "Scanned document preview"
                    : "Field photo with baked FireVault overlay",
                mediaAccount.map { "Saved to \($0.name)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
        .accessibilityIdentifier("native-photo-preview")
    }

    private var destinationAccountCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.fill")
                .font(.title3)
                .foregroundStyle(NativeShellPalette.blue)
                .frame(width: 42, height: 42)
                .background(NativeShellPalette.blue.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("DESTINATION ACCOUNT")
                    .font(.caption2.bold())
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                if let destinationAccount {
                    Text(destinationAccount.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(destinationAccount.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !destinationAccount.accountId.isEmpty {
                        Text("Account ID: \(destinationAccount.accountId)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Choose an account before capturing")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }

            Spacer(minLength: 6)

            Button(destinationAccount == nil ? "Choose" : "Change") {
                pendingCaptureIntent = nil
                showsAccountPicker = true
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
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
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    beginCapture(.camera)
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeShellPalette.red)
                .accessibilityIdentifier("native-take-photo")

                Button {
                    beginCapture(.scanner)
                } label: {
                    Label("Scan", systemImage: "doc.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeShellPalette.blue)
                .accessibilityIdentifier("native-scan-document")
            }

            Button {
                beginCapture(.photoLibrary)
            } label: {
                Label("Choose from Photo Library", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("native-choose-photo")
        }
    }

    private func beginCapture(_ intent: CaptureIntent) {
        guard destinationAccount != nil else {
            pendingCaptureIntent = intent
            showsAccountPicker = true
            return
        }
        launchCapture(intent)
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
    @State private var saved = false

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        let current = settings.gps
        _draft = State(initialValue: current)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Default map", value: "Apple Maps")

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
                        selection: $draft.nearbyRadiusMiles,
                        presentation: .settings
                    )
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
        .navigationTitle("GPS & Maps")
        .navigationBarTitleDisplayMode(.inline)
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

private struct FVRadiusWheelPicker: View {
    enum Presentation {
        case settings
        case map
    }

    @Binding var selection: Double
    let presentation: Presentation

    private var options: [Double] {
        guard !FireVaultGPSPreferences.radiusOptions.contains(selection) else {
            return FireVaultGPSPreferences.radiusOptions
        }
        return (FireVaultGPSPreferences.radiusOptions + [selection]).sorted()
    }

    var body: some View {
        VStack(spacing: presentation == .map ? -7 : 0) {
            if presentation == .map {
                Text("Miles")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }

            Picker("Nearby radius", selection: $selection.animation(.snappy(duration: 0.22))) {
                ForEach(options, id: \.self) { radius in
                    Text(
                        presentation == .map
                            ? FireVaultGPSPreferences.radiusWheelLabel(radius)
                            : FireVaultGPSPreferences.radiusLabel(radius)
                    )
                    .font(presentation == .map ? .caption.bold() : .body.weight(.semibold))
                    .monospacedDigit()
                    .tag(radius)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: presentation == .map ? 88 : 150)
            .clipped()
        }
        .frame(
            width: presentation == .map ? 62 : nil,
            height: presentation == .map ? 104 : 150
        )
        .frame(maxWidth: presentation == .settings ? .infinity : nil)
        .clipped()
        .background(.black.opacity(presentation == .map ? 0.84 : 0.18))
        .clipShape(
            RoundedRectangle(
                cornerRadius: presentation == .map ? 16 : 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: presentation == .map ? 16 : 18,
                style: .continuous
            )
            .stroke(.white.opacity(presentation == .map ? 0.18 : 0.10), lineWidth: 1)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityLabel("Nearby radius")
        .accessibilityValue(FireVaultGPSPreferences.radiusLabel(selection))
        .accessibilityHint("Swipe up or down to change the map radius")
        .accessibilityIdentifier(
            presentation == .map ? "nearby-map-radius-wheel" : "settings-radius-wheel"
        )
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
