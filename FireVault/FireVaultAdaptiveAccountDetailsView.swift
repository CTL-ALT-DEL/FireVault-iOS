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
    case documents = "PHOTOS & DOCUMENTS"
    case equipment = "EQUIPMENT"
    case locations = "ARRIVAL MAP"

    var id: String { rawValue }

    var selectorTitle: String {
        switch self {
        case .documents: "MEDIA"
        case .locations: "ARRIVAL"
        default: rawValue
        }
    }

    var symbol: String {
        switch self {
        case .notes: "note.text"
        case .documents: "photo.on.rectangle.angled"
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
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let returnTab: FireVaultShellTab
    let returnTitle: String

    @State private var addressCamera: MapCameraPosition = .automatic
    @State private var pinsCamera: MapCameraPosition = .automatic
    @State private var selectedSection: FireVaultAccountDetailSection = .notes
    @State private var addressLayer: FireVaultAccountMapLayer = .standard
    @State private var pinsLayer: FireVaultAccountMapLayer = .standard
    @State private var isShowingAccountBrief = false
    @State private var isShowingAccountEditor = false
    @State private var editingNote: FireVaultWorkspaceNote?
    @State private var isShowingNoteEditor = false
    @State private var editingEquipment: FireVaultWorkspaceEquipment?
    @State private var isShowingEquipmentEditor = false
    @State private var editingLocation: FireVaultWorkspaceLocation?
    @State private var isShowingLocationEditor = false
    @State private var isLoadingAccountBrief = false
    @State private var accountBrief: String?
    @State private var accountBriefError: String?

    private var visibleSections: [FireVaultAccountDetailSection] {
        FireVaultAccountDetailSection.allCases.filter { section in
            switch section {
            case .notes:
                settings.isFeatureVisible("account.notes")
            case .documents:
                settings.isFeatureVisible("account.files")
            case .equipment:
                settings.isFeatureVisible("account.equipment")
            case .locations:
                settings.isFeatureVisible("account.map")
                    || settings.isFeatureVisible("account.locations")
            }
        }
    }

    private var mappedPins: [FireVaultWorkspaceLocation] {
        account.locations.filter { $0.coordinate != nil }
    }

    private var sortedLocations: [FireVaultWorkspaceLocation] {
        account.locations.sorted { lhs, rhs in
            let leftRank = locationSortRank(lhs)
            let rightRank = locationSortRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private var formattedPhone: String {
        Self.formatPhone(account.phone)
    }

    private var hasPhone: Bool {
        account.phone.contains(where: \.isNumber)
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
        NavigationStack {
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height
                let horizontalPadding: CGFloat = isLandscape ? 12 : 16
                let availableWidth = max(0, geometry.size.width - (horizontalPadding * 2))
                let mapWidth = max(240, (availableWidth - 10) / 2)
                let mapHeight: CGFloat = {
                    if isLandscape {
                        return min(mapWidth, max(230, geometry.size.height * 0.48))
                    }
                    return min(mapWidth, max(210, geometry.size.height * 0.34))
                }()

            VStack(spacing: 0) {
                header(isLandscape: isLandscape)

                if selectedSection == .locations {
                    HStack(alignment: .top, spacing: isLandscape ? 10 : 12) {
                        mapCard(
                            title: "ACCOUNT ADDRESS",
                            subtitle: account.address,
                            layer: $addressLayer,
                            map: AnyView(addressStyledMap)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: mapHeight)

                        mapCard(
                            title: "ARRIVAL POINTS",
                            subtitle: "\(mappedPins.count) mapped",
                            layer: $pinsLayer,
                            map: AnyView(pinsStyledMap)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: mapHeight)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, isLandscape ? 8 : 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if visibleSections.isEmpty {
                    ContentUnavailableView(
                        "Account Content Hidden",
                        systemImage: "rectangle.slash",
                        description: Text("Account Detail sections are currently hidden in Developer Settings.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    sectionSelector
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, isLandscape ? 6 : 10)

                    ScrollView {
                        VStack(spacing: 12) {
                            selectedSectionContent
                            recentActivitySection
                        }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.bottom, isLandscape ? 16 : 28)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        }
        .background(NativeShellPalette.background)
        .task(id: account.id) {
            addressCamera = .region(addressRegion)
            pinsCamera = .region(pinRegion)
            if let firstSection = visibleSections.first {
                selectedSection = firstSection
            }
            addressLayer = .standard
            pinsLayer = .standard
        }
        .onChange(of: visibleSections.map(\.id)) { _, _ in
            guard !visibleSections.contains(selectedSection),
                  let firstSection = visibleSections.first else { return }
            selectedSection = firstSection
        }
        .accessibilityIdentifier("adaptive-account-dual-map-details")
        .sheet(isPresented: $isShowingAccountBrief) {
            FireVaultAccountBriefSheet(
                accountName: account.name,
                isLoading: isLoadingAccountBrief,
                brief: accountBrief,
                errorMessage: accountBriefError,
                retry: generateAccountBrief
            )
        }
        .sheet(isPresented: $isShowingAccountEditor) {
            FireVaultEditAccountSheet(account: account, locationService: locationService) { draft in
                store.updateAccount(
                    id: account.id,
                    name: draft.name,
                    address: draft.address,
                    category: draft.category,
                    accountId: draft.accountId,
                    phone: draft.phone,
                    latitude: draft.latitude,
                    longitude: draft.longitude
                )
            }
        }
        .sheet(isPresented: $isShowingNoteEditor) {
            FireVaultNoteEditorSheet(accountName: account.name, note: editingNote) { draft in
                if let editingNote {
                    return store.updateNote(
                        accountID: account.id,
                        noteID: editingNote.id,
                        title: draft.title,
                        text: draft.text
                    )
                }
                return store.addNote(to: account.id, title: draft.title, text: draft.text) != nil
            }
        }
        .sheet(isPresented: $isShowingEquipmentEditor) {
            FireVaultEquipmentEditorSheet(
                accountName: account.name,
                accountCoordinate: account.coordinate,
                equipment: editingEquipment,
                locationService: locationService
            ) { draft in
                if let editingEquipment {
                    return store.updateEquipment(
                        accountID: account.id,
                        equipmentID: editingEquipment.id,
                        title: draft.title,
                        subtitle: draft.subtitle,
                        status: draft.deviceAddress,
                        latitude: draft.latitude,
                        longitude: draft.longitude,
                        pinColor: draft.pinColor.rawValue
                    )
                }
                return store.addEquipment(
                    to: account.id,
                    title: draft.title,
                    subtitle: draft.subtitle,
                    status: draft.deviceAddress,
                    latitude: draft.latitude,
                    longitude: draft.longitude,
                    pinColor: draft.pinColor.rawValue
                ) != nil
            }
        }
        .sheet(isPresented: $isShowingLocationEditor) {
            FireVaultLocationEditorSheet(
                accountName: account.name,
                accountCoordinate: account.coordinate,
                location: editingLocation,
                locationService: locationService
            ) { draft in
                if let editingLocation {
                    return store.updateLocation(
                        accountID: account.id,
                        locationID: editingLocation.id,
                        label: draft.label,
                        subtitle: draft.subtitle,
                        type: draft.type,
                        plusCode: draft.plusCode,
                        latitude: draft.latitude,
                        longitude: draft.longitude,
                        pinColor: draft.pinColor.rawValue
                    )
                }
                return store.addLocation(
                    to: account.id,
                    label: draft.label,
                    subtitle: draft.subtitle,
                    type: draft.type,
                    plusCode: draft.plusCode,
                    latitude: draft.latitude,
                    longitude: draft.longitude,
                    pinColor: draft.pinColor.rawValue
                ) != nil
            }
        }
    }

    private func header(isLandscape: Bool) -> some View {
        VStack(spacing: isLandscape ? 8 : 12) {
            HStack(spacing: 12) {
                Button(returnTitle, systemImage: "chevron.left") {
                    store.closeAccount(to: returnTab)
                }
                .buttonStyle(.glass)

                Spacer()

                Button {
                    store.toggleFavorite(account.id)
                } label: {
                    Image(systemName: account.favorite ? "star.fill" : "star")
                        .font(.title3.bold())
                        .frame(width: isLandscape ? 42 : 46, height: isLandscape ? 42 : 46)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Favorite account")

                Menu {
                    Button("Edit Account", systemImage: "pencil") {
                        isShowingAccountEditor = true
                    }
                    if hasPhone {
                        Button("Call", systemImage: "phone") {
                            store.call(account.phone)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.bold())
                        .frame(width: isLandscape ? 42 : 46, height: isLandscape ? 42 : 46)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Account actions")
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        accountIdentity(isLandscape: isLandscape)
                        accountContactActions
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    HStack(alignment: .center, spacing: isLandscape ? 14 : 18) {
                        accountIdentity(isLandscape: isLandscape)
                        accountContactActions
                    }
                }
            }
            .padding(isLandscape ? 12 : 16)
            .background(
                NativeShellPalette.navigationBackground.opacity(0.78),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.20), radius: 9, y: 5)
        }
        .padding(.horizontal, isLandscape ? 12 : 16)
        .padding(.top, isLandscape ? 8 : 18)
        .padding(.bottom, isLandscape ? 8 : 14)
    }

    private func accountIdentity(isLandscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: isLandscape ? 5 : 8) {
            Text(account.name)
                .font(.system(size: isLandscape ? 21 : 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Label(account.address, systemImage: "mappin.and.ellipse")
                .font(isLandscape ? .subheadline.weight(.medium) : .body.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if !account.accountId.isEmpty {
                    headerBadge("ACCOUNT", value: account.accountId)
                }
                if !account.category.isEmpty {
                    headerBadge("CATEGORY", value: account.category)
                }
            }

            if !account.tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(account.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.bold())
                                .foregroundStyle(NativeShellPalette.green)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(NativeShellPalette.green.opacity(0.12), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountContactActions: some View {
        HStack(spacing: 12) {
            Button {
                store.call(account.phone)
            } label: {
                HStack(spacing: 10) {
                    Text(formattedPhone.isEmpty ? "No phone" : formattedPhone)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Image(systemName: "phone.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(NativeShellPalette.green, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .disabled(!hasPhone)
            .opacity(hasPhone ? 1 : 0.5)
            .accessibilityLabel("Call \(formattedPhone)")

            Button {
                store.openRoute(for: account)
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(NativeShellPalette.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(account.coordinate == nil)
            .opacity(account.coordinate == nil ? 0.5 : 1)
            .accessibilityLabel("Route to account")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func generateAccountBrief() {
        guard !isLoadingAccountBrief else { return }
        accountBrief = nil
        accountBriefError = nil
        isLoadingAccountBrief = true
        isShowingAccountBrief = true

        Task {
            do {
                accountBrief = try await FireVaultAIService.shared.generateAccountBrief(for: account)
            } catch {
                accountBriefError = error.localizedDescription
            }
            isLoadingAccountBrief = false
        }
    }

    private func headerBadge(_ label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.primary)
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
        .shadow(
            color: colorScheme == .light ? .black.opacity(0.22) : .clear,
            radius: 12,
            y: 6
        )
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
                    Annotation("", coordinate: coordinate) {
                        Circle()
                            .fill(location.resolvedPinColor.color)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .frame(width: 18, height: 18)
                            .shadow(radius: 3, y: 1)
                            .accessibilityLabel(location.label)
                    }
                }
            }
        }
        .accessibilityIdentifier("account-all-pin-locations-map")
    }

    @ViewBuilder
    private var sectionSelector: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(visibleSections) { section in
                    sectionButton(section)
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(visibleSections) { section in
                    sectionButton(section)
                }
            }
        }
    }

    private func sectionButton(_ section: FireVaultAccountDetailSection) -> some View {
        Button {
            selectedSection = section
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(section.tint)
                Text(section.selectorTitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("\(count(for: section))")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
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
            .shadow(
                color: .black.opacity(selectedSection == section ? 0.26 : 0.16),
                radius: selectedSection == section ? 7 : 5,
                y: selectedSection == section ? 4 : 3
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(section.rawValue), \(count(for: section)) items")
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        if selectedSection == .documents {
            FireVaultAccountMediaLibraryView(
                accountID: account.id,
                store: store,
                embedded: true
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
            selectedSectionToolbar

            switch selectedSection {
            case .notes:
                if account.notes.isEmpty {
                    emptyRow("No notes saved", symbol: "note.text")
                } else {
                    ForEach(account.notes) { note in
                        Button {
                            editingNote = note
                            isShowingNoteEditor = true
                        } label: {
                            dataRow(title: note.title, subtitle: note.text, trailing: note.date, symbol: "note.text")
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete Note", systemImage: "trash", role: .destructive) {
                                store.deleteNote(accountID: account.id, noteID: note.id)
                            }
                        }
                    }
                }
            case .documents:
                EmptyView()
            case .equipment:
                if account.equipment.isEmpty {
                    emptyRow("No equipment saved", symbol: "wrench.and.screwdriver")
                } else {
                    ForEach(account.equipment) { equipment in
                        Button {
                            editingEquipment = equipment
                            isShowingEquipmentEditor = true
                        } label: {
                            dataRow(title: equipment.title, subtitle: equipment.subtitle, trailing: equipment.deviceAddress, symbol: "wrench.and.screwdriver.fill")
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete Equipment", systemImage: "trash", role: .destructive) {
                                store.deleteEquipment(accountID: account.id, equipmentID: equipment.id)
                            }
                        }
                    }
                }
            case .locations:
                if account.locations.isEmpty {
                    emptyRow("No locations saved", symbol: "mappin.slash")
                } else {
                    ForEach(sortedLocations) { location in
                        NavigationLink {
                            ArrivalPointDetailView(
                                account: account,
                                location: location,
                                store: store,
                                locationService: locationService
                            )
                        } label: {
                            dataRow(
                                title: location.label,
                                subtitle: [location.subtitle, location.plusCode].filter { !$0.isEmpty }.joined(separator: " • "),
                                trailing: location.type,
                                symbol: "mappin.circle.fill"
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit Location", systemImage: "pencil") {
                                editingLocation = location
                                isShowingLocationEditor = true
                            }
                            Button("Delete Location", systemImage: "trash", role: .destructive) {
                                store.deleteLocation(accountID: account.id, locationID: location.id)
                            }
                        }
                    }
                }
            }
            }
            .padding(12)
            .background(NativeShellPalette.navigationBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.20), radius: 7, y: 4)
        }
    }

    @ViewBuilder
    private var selectedSectionToolbar: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    selectedSectionTitle
                    Spacer()
                    selectedSectionTotal
                }
                HStack(spacing: 8) {
                    Spacer()
                    selectedSectionActions
                }
            }
        } else {
            HStack(spacing: 8) {
                selectedSectionTitle
                Spacer()
                selectedSectionActions
                selectedSectionTotal
            }
        }
    }

    private var selectedSectionTitle: some View {
        Label(selectedSection.rawValue, systemImage: selectedSection.symbol)
            .font(.subheadline.bold())
            .foregroundStyle(selectedSection.tint)
    }

    private var selectedSectionTotal: some View {
        Text("\(count(for: selectedSection)) total")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var selectedSectionActions: some View {
        if selectedSection == .notes {
            Button("Add Note", systemImage: "square.and.pencil") {
                editingNote = nil
                isShowingNoteEditor = true
            }
            .buttonStyle(.glass)
        } else if selectedSection == .equipment {
            Button("Add Equipment", systemImage: "plus") {
                editingEquipment = nil
                isShowingEquipmentEditor = true
            }
            .buttonStyle(.glass)
        } else if selectedSection == .locations {
            if settings.isFeatureVisible("account.brief") {
                Button("Account Brief", systemImage: "sparkles") {
                    generateAccountBrief()
                }
                .buttonStyle(.glass)
                .disabled(isLoadingAccountBrief)
                .accessibilityIdentifier("generate-account-brief")
            }
            Button("Add Location", systemImage: "plus") {
                editingLocation = nil
                isShowingLocationEditor = true
            }
            .buttonStyle(.glass)
        }
    }

    private func dataRow(title: String, subtitle: String, trailing: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(selectedSection.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
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
        .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
    }

    @ViewBuilder
    private var recentActivitySection: some View {
        if !account.recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("RECENT FIELD ACTIVITY", systemImage: "clock.arrow.circlepath")
                        .font(.caption.bold())
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Latest \(min(account.recent.count, 5))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ForEach(Array(account.recent.prefix(5))) { item in
                    HStack(spacing: 10) {
                        Image(systemName: recentSymbol(item.kind))
                            .font(.subheadline.bold())
                            .foregroundStyle(recentTint(item.kind))
                            .frame(width: 32, height: 32)
                            .background(recentTint(item.kind).opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Text(item.date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            .padding(12)
            .background(NativeShellPalette.navigationBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
        }
    }

    private func recentSymbol(_ kind: String) -> String {
        switch kind.lowercased() {
        case "photo": "photo.fill"
        case "scan", "document", "file": "doc.fill"
        case "equipment": "wrench.and.screwdriver.fill"
        case "location": "mappin.circle.fill"
        default: "note.text"
        }
    }

    private func recentTint(_ kind: String) -> Color {
        switch kind.lowercased() {
        case "photo": NativeShellPalette.purple
        case "scan", "document", "file": NativeShellPalette.blue
        case "equipment": NativeShellPalette.green
        case "location": NativeShellPalette.red
        default: NativeShellPalette.amber
        }
    }

    private func locationSortRank(_ location: FireVaultWorkspaceLocation) -> Int {
        let searchable = "\(location.label) \(location.type)".lowercased()
        if searchable.contains("parking") || searchable.contains("park here") { return 0 }
        if searchable.contains("front entrance") || searchable.contains("main entrance") { return 1 }
        if searchable.contains("entrance") { return 2 }
        return 3
    }

    private func emptyRow(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .padding(.horizontal, 10)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 5, y: 3)
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
