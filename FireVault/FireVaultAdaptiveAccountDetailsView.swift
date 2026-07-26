//
//  FireVaultAdaptiveAccountDetailsView.swift
//  FireVault
//
//  Dual-map account workspace for regular-width iPad layouts.
//

import MapKit
import SwiftUI

private enum FireVaultAccountDetailSection: String, CaseIterable, Identifiable {
    case notes = "NOTES"
    case documents = "FILES & SCANS"
    case equipment = "EQUIPMENT"
    case locations = "LOCATIONS"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .notes: "note.text"
        case .documents: "doc.viewfinder"
        case .equipment: "wrench.and.screwdriver.fill"
        case .locations: "mappin.and.ellipse"
        }
    }

    var tint: Color {
        switch self {
        case .notes: NativeShellPalette.amber
        case .documents: NativeShellPalette.blue
        case .equipment: NativeShellPalette.green
        case .locations: NativeShellPalette.purple
        }
    }
}

private enum FireVaultAccountMapLayer: String, CaseIterable, Identifiable {
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

struct FireVaultAdaptiveAccountDetailsView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    let returnTab: FireVaultShellTab
    let returnTitle: String

    @State private var addressCamera: MapCameraPosition = .automatic
    @State private var pinsCamera: MapCameraPosition = .automatic
    @State private var selectedSection: FireVaultAccountDetailSection = .notes
    @State private var addressLayer: FireVaultAccountMapLayer = .standard
    @State private var pinsLayer: FireVaultAccountMapLayer = .standard

    private var mappedPins: [FireVaultWorkspaceLocation] {
        account.locations.filter { $0.coordinate != nil }
    }

    private var formattedPhone: String {
        Self.formatPhone(account.phone)
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
                let mapHeightLimit = max(210, geometry.size.height * 0.46)
                let mapSide = min((availableWidth - 12) / 2, mapHeightLimit)

                ScrollView {
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            mapCard(
                                title: "ADDRESS",
                                subtitle: account.address,
                                layer: $addressLayer,
                                map: AnyView(addressStyledMap)
                            )
                            .frame(width: mapSide, height: mapSide)

                            mapCard(
                                title: "PIN LOCATIONS",
                                subtitle: "\(mappedPins.count) mapped",
                                layer: $pinsLayer,
                                map: AnyView(pinsStyledMap)
                            )
                            .frame(width: mapSide, height: mapSide)
                        }
                        .frame(maxWidth: .infinity)

                        sectionSelector
                        selectedSectionContent
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(NativeShellPalette.background)
        .task(id: account.id) {
            addressCamera = .region(addressRegion)
            pinsCamera = .region(pinRegion)
            selectedSection = .notes
            addressLayer = .standard
            pinsLayer = .standard
        }
        .accessibilityIdentifier("adaptive-account-dual-map-details")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(returnTitle, systemImage: "chevron.left") {
                store.closeAccount(to: returnTab)
            }
            .buttonStyle(.glass)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(account.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if !account.accountId.isEmpty {
                        headerBadge("ACCOUNT", value: account.accountId)
                    }

                    if !account.category.isEmpty {
                        headerBadge("CATEGORY", value: account.category)
                    }
                }

                HStack(spacing: 10) {
                    Label(account.address, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        store.call(account.phone)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(NativeShellPalette.green, in: Circle())
                            Text(formattedPhone.isEmpty ? "No phone" : formattedPhone)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!account.phone.contains(where: \.isNumber))
                    .opacity(account.phone.contains(where: \.isNumber) ? 1 : 0.5)
                    .accessibilityLabel("Call \(formattedPhone)")
                }
            }

            Button {
                store.openRoute(for: account)
            } label: {
                Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
            }
            .buttonStyle(.glassProminent)
            .disabled(account.coordinate == nil)
            .accessibilityLabel("Route to account")

            Button {
                store.toggleFavorite(account.id)
            } label: {
                Image(systemName: account.favorite ? "star.fill" : "star")
                    .font(.title3.bold())
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Favorite account")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func headerBadge(_ label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(NativeShellPalette.surface, in: Capsule())
    }

    private func mapCard(
        title: String,
        subtitle: String,
        layer: Binding<FireVaultAccountMapLayer>,
        map: AnyView
    ) -> some View {
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
        .overlay(alignment: .topTrailing) {
            Menu {
                Picker("Map Layer", selection: layer) {
                    ForEach(FireVaultAccountMapLayer.allCases) { option in
                        Label(option.rawValue, systemImage: option.symbol).tag(option)
                    }
                }
            } label: {
                Image(systemName: "square.3.layers.3d.top.filled")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.76), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(9)
            .accessibilityLabel("Map layers")
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var addressStyledMap: some View {
        switch addressLayer {
        case .standard:
            addressMap.mapStyle(.standard(elevation: .realistic))
        case .hybrid:
            addressMap.mapStyle(.hybrid(elevation: .realistic))
        case .imagery:
            addressMap.mapStyle(.imagery(elevation: .realistic))
        }
    }

    private var addressMap: some View {
        Map(position: $addressCamera, interactionModes: [.pan, .zoom, .rotate]) {
            if let coordinate = account.coordinate {
                Marker(account.name, systemImage: "building.2.fill", coordinate: coordinate)
                    .tint(NativeShellPalette.red)
            }
        }
        .accessibilityIdentifier("account-address-zoom-map")
    }

    @ViewBuilder
    private var pinsStyledMap: some View {
        switch pinsLayer {
        case .standard:
            pinMap.mapStyle(.standard(elevation: .realistic))
        case .hybrid:
            pinMap.mapStyle(.hybrid(elevation: .realistic))
        case .imagery:
            pinMap.mapStyle(.imagery(elevation: .realistic))
        }
    }

    private var pinMap: some View {
        Map(position: $pinsCamera, interactionModes: [.pan, .zoom, .rotate]) {
            if mappedPins.isEmpty, let coordinate = account.coordinate {
                Marker(account.name, systemImage: "building.2.fill", coordinate: coordinate)
                    .tint(NativeShellPalette.red)
            }
            ForEach(mappedPins) { location in
                if let coordinate = location.coordinate {
                    Marker(location.label, systemImage: "mappin", coordinate: coordinate)
                        .tint(NativeShellPalette.purple)
                }
            }
        }
        .accessibilityIdentifier("account-all-pin-locations-map")
    }

    private var sectionSelector: some View {
        HStack(spacing: 8) {
            ForEach(FireVaultAccountDetailSection.allCases) { section in
                Button {
                    selectedSection = section
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(section.tint)
                        Text(section.rawValue)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(count(for: section))")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(selectedSection == section ? .white : .secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .padding(.horizontal, 10)
                    .background(
                        selectedSection == section ? section.tint.opacity(0.20) : NativeShellPalette.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                selectedSection == section ? section.tint.opacity(0.85) : .white.opacity(0.07),
                                lineWidth: selectedSection == section ? 1.5 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.rawValue), \(count(for: section)) items")
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(selectedSection.rawValue, systemImage: selectedSection.symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(selectedSection.tint)
                Spacer()
                Text("\(count(for: selectedSection)) total")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            switch selectedSection {
            case .notes:
                if account.notes.isEmpty {
                    emptyRow("No notes saved", symbol: "note.text")
                } else {
                    ForEach(account.notes) { note in
                        dataRow(title: note.title, subtitle: note.text, trailing: note.date, symbol: "note.text")
                    }
                }
            case .documents:
                if account.documents.isEmpty {
                    emptyRow("No files or scans saved", symbol: "doc.viewfinder")
                } else {
                    ForEach(account.documents) { document in
                        dataRow(title: document.title, subtitle: document.subtitle, trailing: document.date, symbol: document.kind == "scan" ? "doc.viewfinder" : "doc")
                    }
                }
            case .equipment:
                if account.equipment.isEmpty {
                    emptyRow("No equipment saved", symbol: "wrench.and.screwdriver")
                } else {
                    ForEach(account.equipment) { equipment in
                        dataRow(title: equipment.title, subtitle: equipment.subtitle, trailing: equipment.status, symbol: "wrench.and.screwdriver.fill")
                    }
                }
            case .locations:
                if account.locations.isEmpty {
                    emptyRow("No locations saved", symbol: "mappin.slash")
                } else {
                    ForEach(account.locations) { location in
                        dataRow(
                            title: location.label,
                            subtitle: [location.subtitle, location.plusCode].filter { !$0.isEmpty }.joined(separator: " • "),
                            trailing: location.type,
                            symbol: "mappin.circle.fill"
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(NativeShellPalette.navigationBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func dataRow(title: String, subtitle: String, trailing: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(selectedSection.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing).lineLimit(2)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func emptyRow(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, 10)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func count(for section: FireVaultAccountDetailSection) -> Int {
        switch section {
        case .notes: account.notes.count
        case .documents: account.documents.count
        case .equipment: account.equipment.count
        case .locations: account.locations.count
        }
    }

    private static func formatPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        if digits.count == 10 {
            let area = digits.prefix(3)
            let middle = digits.dropFirst(3).prefix(3)
            let last = digits.suffix(4)
            return "(\(area)) \(middle)-\(last)"
        }
        if digits.count == 11, digits.first == "1" {
            let ten = String(digits.dropFirst())
            let area = ten.prefix(3)
            let middle = ten.dropFirst(3).prefix(3)
            let last = ten.suffix(4)
            return "(\(area)) \(middle)-\(last)"
        }
        return raw
    }
}
