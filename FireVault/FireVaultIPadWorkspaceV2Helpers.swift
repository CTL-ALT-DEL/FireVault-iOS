//
//  FireVaultIPadWorkspaceV2Helpers.swift
//  FireVault
//
//  Shared helpers for the adaptive iPad workspace.
//

import MapKit
import SwiftUI

struct FireVaultIPadPortraitWorkspace: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    var body: some View {
        Group {
            switch store.selectedTab {
            case .nearby:
                FireVaultIPadPortraitNearbyViewV2(
                    payload: payload,
                    store: store,
                    settings: settings,
                    locationService: locationService,
                    breadcrumbs: breadcrumbs,
                    showsBottomNavigation: false
                )
            case .accounts:
                FireVaultIPadAccountsWorkspaceV2(payload: payload, store: store)
            case .trip:
                FireVaultTripLogPortraitView(
                    breadcrumbs: breadcrumbs,
                    store: store,
                    technicianName: settings.preferences.technician.name,
                    companyName: settings.preferences.technician.company,
                    includeCoordinatesInReports: settings.gps.includeCoordinatesInReports,
                    showsCloseButton: false
                )
            case .photo:
                NativePhotoView(store: store, settings: settings)
            case .settings:
                FireVaultIPadSettingsWorkspace(
                    payload: payload,
                    store: store,
                    settings: settings,
                    locationService: locationService,
                    breadcrumbs: breadcrumbs
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeShellPalette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            portraitNavigation
        }
        .accessibilityIdentifier("ipad-portrait-workspace")
    }

    private var portraitNavigation: some View {
        HStack(spacing: 0) {
            ForEach(FireVaultShellTab.allCases) { tab in
                let selected = tab == store.selectedTab
                Button {
                    if tab == .nearby { store.requestNearbyReset() }
                    withAnimation(.snappy(duration: 0.25)) {
                        store.closeAccount(to: tab)
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: selected ? .bold : .semibold))
                            .symbolVariant(selected ? .fill : .none)
                            .foregroundStyle(
                                tab == .trip && breadcrumbs.isRecording
                                    ? NativeShellPalette.green
                                    : (selected ? NativeShellPalette.blue : NativeShellPalette.navigationInactive)
                            )
                            .frame(width: 38, height: 29)
                            .background(
                                selected ? NativeShellPalette.blue.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        Text(tab.title)
                            .font(.caption.weight(selected ? .bold : .semibold))
                    }
                    .foregroundStyle(selected ? NativeShellPalette.blue : NativeShellPalette.navigationInactive)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 5)
        .padding(.bottom, 2)
        .background(NativeShellPalette.navigationBackground.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(NativeShellPalette.navigationDivider).frame(height: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 10, y: -3)
    }
}

struct FireVaultIPadUtilityWorkspaceV2: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore

    var body: some View {
        Group {
            switch store.selectedTab {
            case .photo:
                NativePhotoView(store: store, settings: settings)
            case .settings:
                FireVaultIPadSettingsWorkspace(
                    payload: payload,
                    store: store,
                    settings: settings,
                    locationService: locationService,
                    breadcrumbs: breadcrumbs
                )
            default:
                ContentUnavailableView(
                    "Workspace Unavailable",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Choose a workspace from the sidebar.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NativeShellPalette.background)
        .accessibilityIdentifier("ipad-utility-workspace")
    }
}

enum FireVaultIPadMapRegionV2 {
    static func region(
        for coordinates: [CLLocationCoordinate2D],
        fallbackDelta: CLLocationDegrees = 0.18
    ) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return .init(
                center: .init(latitude: 43.615, longitude: -116.202),
                span: .init(latitudeDelta: fallbackDelta, longitudeDelta: fallbackDelta)
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
                latitudeDelta: max(fallbackDelta, (maximumLatitude - minimumLatitude) * 1.8),
                longitudeDelta: max(fallbackDelta, (maximumLongitude - minimumLongitude) * 1.8)
            )
        )
    }
}

struct FireVaultIPadCurrentLocationMarkerV2: View {
    var body: some View {
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
