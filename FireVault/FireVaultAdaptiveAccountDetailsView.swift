//
//  FireVaultAdaptiveAccountDetailsView.swift
//  FireVault
//
//  Dual-map account workspace for regular-width iPad layouts.
//

import MapKit
import SwiftUI

struct FireVaultAdaptiveAccountDetailsView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    let returnTab: FireVaultShellTab
    let returnTitle: String

    @State private var addressCamera: MapCameraPosition = .automatic
    @State private var pinsCamera: MapCameraPosition = .automatic

    private var mappedPins: [FireVaultWorkspaceLocation] {
        account.locations.filter { $0.coordinate != nil }
    }

    private var addressRegion: MKCoordinateRegion {
        guard let coordinate = account.coordinate else {
            return .init(
                center: .init(latitude: 43.615, longitude: -116.202),
                span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        return .init(
            center: coordinate,
            span: .init(latitudeDelta: 0.0045, longitudeDelta: 0.0045)
        )
    }

    private var pinRegion: MKCoordinateRegion {
        let coordinates = mappedPins.compactMap(\.coordinate)
        if coordinates.isEmpty { return addressRegion }
        return FireVaultIPadMapRegionV2.region(for: coordinates, fallbackDelta: 0.0025)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { geometry in
                let availableWidth = max(0, geometry.size.width - 36)
                let availableMapHeight = max(220, geometry.size.height * 0.48)
                let mapSide = min((availableWidth - 12) / 2, availableMapHeight)

                ScrollView {
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            mapCard(
                                title: "ADDRESS",
                                subtitle: account.address,
                                map: AnyView(addressMap)
                            )
                            .frame(width: mapSide, height: mapSide)

                            mapCard(
                                title: "PIN LOCATIONS",
                                subtitle: "\(mappedPins.count) mapped",
                                map: AnyView(pinMap)
                            )
                            .frame(width: mapSide, height: mapSide)
                        }
                        .frame(maxWidth: .infinity)

                        compactActions
                        compactAccountSummary
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(NativeShellPalette.background)
        .task(id: account.id) {
            addressCamera = .region(addressRegion)
            pinsCamera = .region(pinRegion)
        }
        .accessibilityIdentifier("adaptive-account-dual-map-details")
    }

    private var header: some View {
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
                Text(account.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                store.call(account.phone)
            } label: {
                Image(systemName: "phone.fill")
            }
            .buttonStyle(.glass)
            .disabled(!account.phone.contains(where: \.isNumber))
            .accessibilityLabel("Call account")

            Button {
                store.openRoute(for: account)
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
            }
            .buttonStyle(.glassProminent)
            .disabled(account.coordinate == nil)
            .accessibilityLabel("Route to account")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func mapCard(title: String, subtitle: String, map: AnyView) -> some View {
        ZStack(alignment: .topLeading) {
            map

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.bold())
                    .tracking(1.1)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(9)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var addressMap: some View {
        Map(position: $addressCamera, interactionModes: [.pan, .zoom, .rotate]) {
            if let coordinate = account.coordinate {
                Marker(account.name, systemImage: "building.2.fill", coordinate: coordinate)
                    .tint(NativeShellPalette.red)
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .accessibilityIdentifier("account-address-zoom-map")
    }

    private var pinMap: some View {
        Map(position: $pinsCamera, interactionModes: [.pan, .zoom, .rotate]) {
            ForEach(mappedPins) { location in
                if let coordinate = location.coordinate {
                    Marker(location.label, systemImage: "mappin", coordinate: coordinate)
                        .tint(NativeShellPalette.purple)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .accessibilityIdentifier("account-all-pin-locations-map")
    }

    private var compactActions: some View {
        HStack(spacing: 8) {
            compactAction(
                title: "NOTES",
                count: account.notes.count,
                symbol: "note.text",
                tint: NativeShellPalette.amber
            ) { store.addNote(to: account.id) }

            compactAction(
                title: "FILES & SCANS",
                count: account.documents.count,
                symbol: "doc.viewfinder",
                tint: NativeShellPalette.blue
            ) { store.addDocument(to: account.id, scan: true) }

            compactAction(
                title: "EQUIPMENT",
                count: account.equipment.count,
                symbol: "wrench.and.screwdriver.fill",
                tint: NativeShellPalette.green
            ) { store.addEquipment(to: account.id) }

            compactAction(
                title: "LOCATIONS",
                count: account.locations.count,
                symbol: "mappin.and.ellipse",
                tint: NativeShellPalette.purple
            ) {
                store.addLocation(to: account.id)
                pinsCamera = .region(pinRegion)
            }
        }
    }

    private func compactAction(
        title: String,
        count: Int,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var compactAccountSummary: some View {
        HStack(spacing: 14) {
            summaryItem("ACCOUNT", account.accountId.isEmpty ? "Not entered" : account.accountId)
            Divider().frame(height: 30)
            summaryItem("CATEGORY", account.category.isEmpty ? "Not entered" : account.category)
            Divider().frame(height: 30)
            summaryItem("PHONE", account.phone.isEmpty ? "Not entered" : account.phone)
            Spacer(minLength: 0)
            Button {
                store.toggleFavorite(account.id)
            } label: {
                Label(account.favorite ? "Favorite" : "Favorite", systemImage: account.favorite ? "star.fill" : "star")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(NativeShellPalette.navigationBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.bold())
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
