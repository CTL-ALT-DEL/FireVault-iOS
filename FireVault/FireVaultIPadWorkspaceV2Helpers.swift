//
//  FireVaultIPadWorkspaceV2Helpers.swift
//  FireVault
//
//  Shared helpers for the adaptive iPad workspace.
//

import MapKit
import SwiftUI

struct FireVaultIPadLegacyDetailHostV2: View {
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
