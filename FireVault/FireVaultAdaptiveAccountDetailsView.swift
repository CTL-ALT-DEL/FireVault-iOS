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

struct FireVaultAdaptiveAccountDetailsView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    let returnTab: FireVaultShellTab
    let returnTitle: String

    @State private var addressCamera: MapCameraPosition = .automatic
    @State private var pinsCamera: MapCameraPosition = .automatic
    @State private var selectedSection: FireVaultAccountDetailSection = .notes

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
                let mapHeightLimit = max(210, geometry.size.height * 0.46)
                let mapSide = min((availableWidth - 12) / 2, mapHeightLimit)

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

                        sectionSelector
                        selectedSectionContent
                        compactAccountSummary
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
        .mapStyle(.hybrid(elevation: .realistic))
        .accessibilityIdentifier("account-all-pin-locations-map")
    }

    private var sectionSelector: some View {
        HStack(spacing: 7) {
            ForEach(FireVaultAccountDetailSection.allCases) { section in
                Button {
                    selectedSection = section
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: section.symbol)
                                .font(.caption.bold())
                                .foregroundStyle(section.tint)
                            Text(section.rawValue)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        Text("\(count(for: section))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 6)
                    .background(
                        selectedSection == section
                            ? section.tint.opacity(0.18)
                            : NativeShellPalette.surface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                selectedSection == section ? section.tint.opacity(0.8) : .white.opacity(0.07),
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
                    .font(.caption.bold())
                    .tracking(0.9)
                    .foregroundStyle(selectedSection.tint)
                Spacer()
                Text("\(count(for: selectedSection)) total")
                    .font(.caption.monospacedDigit())
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
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
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
                Label("Favorite", systemImage: account.favorite ? "star.fill" : "star")
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
