//
//  FieldWorkspace.swift
//  FireVault
//
//  Native, field-first Account workspace for Build 1.06.00.
//

import SwiftUI
import Combine
import MapKit
import UniformTypeIdentifiers

struct FireVaultWorkspaceAccount: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
    var category: String
    var accountId: String
    var phone: String
    var favorite: Bool
    var latitude: Double?
    var longitude: Double?
    var tags: [String]
    var notes: [FireVaultWorkspaceNote]
    var documents: [FireVaultWorkspaceDocument]
    var equipment: [FireVaultWorkspaceEquipment]
    var locations: [FireVaultWorkspaceLocation]
    var recent: [FireVaultWorkspaceRecent]

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
}

struct FireVaultWorkspaceNote: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var text: String
    var date: String
}

struct FireVaultWorkspaceDocument: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var kind: String
    var date: String
    var mediaFileName: String? = nil
}

struct FireVaultWorkspaceEquipment: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var status: String
    var latitude: Double? = nil
    var longitude: Double? = nil
    var pinColor: String? = nil

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    var deviceAddress: String {
        let legacyStatuses = ["active", "draft", "monitor", "normal", "enabled"]
        return legacyStatuses.contains(status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ? ""
            : status
    }

    var resolvedPinColor: FireVaultMapPinColor {
        FireVaultMapPinColor(rawValue: pinColor ?? "") ?? .green
    }
}

enum FireVaultEquipmentComponentCatalog {
    static let types = [
        "Fire Alarm Control Panel (FACP)",
        "Remote Annunciator",
        "Graphic Annunciator",
        "Network Control Node",
        "Fire Alarm Communicator",
        "Cellular Communicator",
        "Radio Communicator",
        "Booster Panel",
        "NAC Power Supply",
        "Auxiliary Power Supply",
        "Battery Cabinet",
        "Smoke Detector",
        "Duct Smoke Detector",
        "Heat Detector",
        "Beam Smoke Detector",
        "Multi-Criteria Detector",
        "CO Detector",
        "Manual Pull Station",
        "Monitor Module",
        "Control Module",
        "Relay Module",
        "Input/Output Module",
        "Isolation Module",
        "Notification Appliance Circuit",
        "Horn/Strobe",
        "Strobe",
        "Speaker/Strobe",
        "Speaker",
        "Bell",
        "Sprinkler Waterflow Switch",
        "Sprinkler Tamper Switch",
        "Low-Air Switch",
        "Pressure Switch",
        "Fire Pump Controller",
        "Elevator Recall Interface",
        "Door Release Interface",
        "Smoke Control Interface",
        "Kitchen Hood Interface",
        "Suppression/Releasing Panel",
        "Remote Test Station",
        "Other Fire Alarm Component"
    ]
}

struct FireVaultWorkspaceLocation: Codable, Identifiable, Equatable {
    var id: String
    var label: String
    var subtitle: String
    var type: String
    var plusCode: String
    var latitude: Double?
    var longitude: Double?
    var pinColor: String?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    var resolvedPinColor: FireVaultMapPinColor {
        FireVaultMapPinColor(rawValue: pinColor ?? "") ?? .purple
    }
}

enum FireVaultMapPinColor: String, CaseIterable, Identifiable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }
}

struct FireVaultWorkspaceRecent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var kind: String
    var date: String
}

private extension FireVaultWorkspaceLocation {
    var arrivalMapSymbol: String {
        let value = "\(label) \(type)".lowercased()
        if value.contains("parking") || value.contains("park here") { return "parkingsign.circle.fill" }
        if value.contains("entrance") || value.contains("door") { return "door.left.hand.open" }
        if value.contains("panel") { return "rectangle.3.group.bubble.left.fill" }
        if value.contains("riser") || value.contains("pump") { return "drop.fill" }
        return "mappin.circle.fill"
    }
}

struct FieldWorkspaceView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService

    @State private var isShowingAccountEditor = false
    @State private var isShowingNoteEditor = false

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]
    private var previewCoordinate: CLLocationCoordinate2D? {
        account.coordinate ?? account.locations.compactMap(\.coordinate).first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FieldWorkspacePalette.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        identity
                        if settings.isFeatureVisible("account.map") {
                            mapPreview
                        }
                        destinations
                        recentActivity
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 104)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.closeAccount()
                    } label: {
                        Label("Accounts", systemImage: "chevron.left")
                    }
                    .buttonStyle(.glass)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.toggleFavorite(account.id)
                    } label: {
                        Image(systemName: account.favorite ? "star.fill" : "star")
                            .foregroundStyle(account.favorite ? FieldWorkspacePalette.amber : .primary)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(account.favorite ? "Remove Favorite" : "Add Favorite")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                appNavigation
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .tint(FieldWorkspacePalette.blue)
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
            FireVaultNoteEditorSheet(accountName: account.name, note: nil) { draft in
                store.addNote(to: account.id, title: draft.title, text: draft.text) != nil
            }
        }
    }

    private var identity: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "building.2.crop.circle.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(FieldWorkspacePalette.blue)
                        .frame(width: 48, height: 48)
                        .background(FieldWorkspacePalette.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(account.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Label(account.address, systemImage: "mappin.and.ellipse")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    if !account.category.isEmpty {
                        Text(account.category.uppercased())
                            .workspacePill(color: FieldWorkspacePalette.blue)
                    }
                    if !account.accountId.isEmpty {
                        Label(account.accountId, systemImage: "number")
                            .workspacePill(color: .secondary)
                    }
                    Spacer()
                }

                accountQuickActions

                if !account.tags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(account.tags, id: \.self) { tag in
                                Text(tag).workspacePill(color: FieldWorkspacePalette.green)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(15)
        }
        .padding(.top, 4)
    }

    private var accountQuickActions: some View {
        HStack(spacing: 8) {
            WorkspaceQuickAction(
                title: "Call",
                symbol: "phone.fill",
                tint: FieldWorkspacePalette.green,
                disabled: account.phone.isEmpty
            ) {
                store.call(account.phone)
            }
            WorkspaceQuickAction(
                title: "Route",
                symbol: "arrow.triangle.turn.up.right.diamond.fill",
                tint: FieldWorkspacePalette.blue,
                disabled: account.coordinate == nil
            ) {
                store.openRoute(for: account)
            }
            WorkspaceQuickAction(
                title: "Note",
                symbol: "square.and.pencil",
                tint: FieldWorkspacePalette.amber
            ) {
                isShowingNoteEditor = true
            }
            WorkspaceQuickAction(
                title: "Edit",
                symbol: "pencil",
                tint: FieldWorkspacePalette.purple
            ) {
                isShowingAccountEditor = true
            }
        }
    }

    private var mapPreview: some View {
        NavigationLink {
            MapArrivalView(account: account, store: store, settings: settings, locationService: locationService)
        } label: {
            WorkspaceCard {
                ZStack(alignment: .bottomLeading) {
                    if previewCoordinate != nil || account.locations.contains(where: { $0.coordinate != nil }) {
                        WorkspaceMap(account: account)
                            .allowsHitTesting(false)
                    } else {
                        Rectangle()
                            .fill(FieldWorkspacePalette.surfaceRaised)
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "map")
                                        .font(.title)
                                    Text("Add GPS to show this account on Apple Maps")
                                        .font(.subheadline)
                                }
                                .foregroundStyle(.secondary)
                            }
                    }

                    LinearGradient(
                        colors: [.clear, FieldWorkspacePalette.surface.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ARRIVAL MAP")
                                .font(.caption2.bold())
                                .tracking(1.2)
                                .foregroundStyle(FieldWorkspacePalette.blue)
                            Text(account.locations.isEmpty ? "Account location" : "\(account.locations.count) precise locations")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
                .frame(height: 190)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Arrival Map")
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: 9) {
            WorkspaceSectionTitle(title: "FIELD WORKSPACE", subtitle: "Everything for this location")
            LazyVGrid(columns: columns, spacing: 9) {
                if settings.isFeatureVisible("account.notes") {
                    NavigationLink {
                        NotesWorkspaceView(account: account, store: store)
                    } label: {
                        WorkspaceDestinationTile(
                            title: "Notes", count: account.notes.count,
                            symbol: "note.text", color: FieldWorkspacePalette.amber
                        )
                    }
                }

                if settings.isFeatureVisible("account.files") {
                    NavigationLink {
                        FilesScansView(account: account, store: store)
                    } label: {
                        WorkspaceDestinationTile(
                            title: "Files & Scans", count: account.documents.count,
                            symbol: "doc.viewfinder", color: FieldWorkspacePalette.blue
                        )
                    }
                }

                if settings.isFeatureVisible("account.equipment") {
                    NavigationLink {
                        EquipmentWorkspaceView(
                            account: account,
                            store: store,
                            locationService: locationService
                        )
                    } label: {
                        WorkspaceDestinationTile(
                            title: "Equipment", count: account.equipment.count,
                            symbol: "wrench.and.screwdriver", color: FieldWorkspacePalette.green
                        )
                    }
                }

                if settings.isFeatureVisible("account.locations") {
                    NavigationLink {
                        MapArrivalView(account: account, store: store, settings: settings, locationService: locationService)
                    } label: {
                        WorkspaceDestinationTile(
                            title: "Locations", count: account.locations.count,
                            symbol: "map.fill", color: FieldWorkspacePalette.purple
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var recentActivity: some View {
        if !account.recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WorkspaceSectionTitle(title: "RECENT FIELD ACTIVITY", subtitle: "Latest saved work")
                WorkspaceCard {
                    VStack(spacing: 0) {
                        ForEach(Array(account.recent.prefix(6).enumerated()), id: \.element.id) { index, item in
                            WorkspaceRecentRow(item: item)
                            if index < min(account.recent.count, 6) - 1 {
                                Divider().padding(.leading, 50)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var appNavigation: some View {
        HStack(spacing: 0) {
            if settings.isFeatureVisible("tab.nearby") {
                WorkspaceNavButton(title: "Nearby", symbol: "location.fill") { store.closeAccount(to: .nearby) }
            }
            if settings.isFeatureVisible("tab.accounts") {
                WorkspaceNavButton(title: "Accounts", symbol: "magnifyingglass") { store.closeAccount(to: .accounts) }
            }
            if settings.isFeatureVisible("tab.trip") {
                WorkspaceNavButton(title: "Trip Log", symbol: "truck.box.fill") { store.closeAccount(to: .trip) }
            }
            if settings.isFeatureVisible("tab.photo") {
                WorkspaceNavButton(title: "Photo", symbol: "camera.fill") { store.closeAccount(to: .photo) }
            }
            WorkspaceNavButton(title: "Settings", symbol: "slider.horizontal.3") { store.closeAccount(to: .settings) }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 3)
        .background(FieldWorkspacePalette.navigationBackground)
        .overlay(alignment: Alignment.top) {
            Rectangle()
                .fill(FieldWorkspacePalette.navigationDivider)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: -3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
        .accessibilityIdentifier("workspace-main-navigation")
    }
}

struct FireVaultAccountEditDraft: Equatable {
    var name: String
    var address: String
    var category: String
    var accountId: String
    var phone: String
    var latitude: Double?
    var longitude: Double?
}

struct FireVaultEditAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let accountID: String
    @ObservedObject private var locationService: FireVaultLocationService
    private let save: (FireVaultAccountEditDraft) -> Bool

    @State private var name: String
    @State private var address: String
    @State private var category: String
    @State private var accountId: String
    @State private var phone: String
    @State private var latitudeText: String
    @State private var longitudeText: String
    @State private var mapPosition: MapCameraPosition
    @State private var isShowingPinEditor = false
    @State private var isWaitingForCurrentLocation = false
    @State private var gpsStatus: String?
    @FocusState private var isTextInputFocused: Bool

    init(
        account: FireVaultWorkspaceAccount,
        locationService: FireVaultLocationService,
        save: @escaping (FireVaultAccountEditDraft) -> Bool
    ) {
        accountID = account.id
        self.locationService = locationService
        self.save = save
        _name = State(initialValue: account.name)
        _address = State(initialValue: account.address)
        _category = State(initialValue: account.category)
        _accountId = State(initialValue: account.accountId)
        _phone = State(initialValue: account.phone)
        _latitudeText = State(initialValue: account.latitude.map { String($0) } ?? "")
        _longitudeText = State(initialValue: account.longitude.map { String($0) } ?? "")
        let initialCoordinate = account.coordinate
            ?? CLLocationCoordinate2D(latitude: 43.615, longitude: -116.202)
        _mapPosition = State(initialValue: .region(.init(
            center: initialCoordinate,
            span: .init(latitudeDelta: 0.0012, longitudeDelta: 0.0012)
        )))
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedCoordinatePair: (Double?, Double?)? {
        let latitudeValue = latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeValue = longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if latitudeValue.isEmpty && longitudeValue.isEmpty { return (nil, nil) }
        guard let latitude = Double(latitudeValue),
              let longitude = Double(longitudeValue),
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else {
            return nil
        }
        return (latitude, longitude)
    }

    private var accountCoordinate: CLLocationCoordinate2D? {
        guard let parsedCoordinatePair,
              let latitude = parsedCoordinatePair.0,
              let longitude = parsedCoordinatePair.1 else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    private var canSave: Bool {
        !normalizedName.isEmpty && parsedCoordinatePair != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 13) {
                        Image(systemName: "building.2.crop.circle.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(FieldWorkspacePalette.blue, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ACCOUNT DETAILS")
                                .font(.caption.bold())
                                .tracking(1.1)
                                .foregroundStyle(FieldWorkspacePalette.blue)
                            Text(normalizedName.isEmpty ? "Unnamed Account" : normalizedName)
                                .font(.title3.bold())
                                .lineLimit(2)
                            Text("Update the site identity and contact information below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 7)
                }
                .listRowBackground(
                    LinearGradient(
                        colors: [FieldWorkspacePalette.blue.opacity(0.13), FieldWorkspacePalette.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                Section("Site Identity") {
                    accountEditField("Account Name", symbol: "building.2.fill", text: $name)
                    accountEditField("Street Address", symbol: "mappin.and.ellipse", text: $address, lineLimit: 3)
                    accountEditField("Category", symbol: "tag.fill", text: $category)
                    accountEditField("Account ID", symbol: "number", text: $accountId)
                }

                Section("Contact") {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(FieldWorkspacePalette.green)
                            .frame(width: 32, height: 32)
                            .background(FieldWorkspacePalette.green.opacity(0.13), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PHONE NUMBER")
                                .font(.caption2.bold())
                                .tracking(0.65)
                                .foregroundStyle(.secondary)
                            TextField("(xxx) xxx-xxxx", text: $phone)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .font(.body.weight(.semibold))
                                .focused($isTextInputFocused)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    accountGPSMap
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        }

                    Button("Adjust Pin on Map", systemImage: "mappin.and.ellipse") {
                        isTextInputFocused = false
                        isShowingPinEditor = true
                    }
                    .disabled(accountCoordinate == nil && locationService.coordinate == nil)

                    Button("Use Current Location", systemImage: "location.fill") {
                        isTextInputFocused = false
                        isWaitingForCurrentLocation = true
                        gpsStatus = "Finding this iPhone…"
                        locationService.requestCurrentLocation(highAccuracy: true)
                    }

                    HStack(spacing: 10) {
                        TextField("Latitude", text: $latitudeText)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                            .focused($isTextInputFocused)
                        TextField("Longitude", text: $longitudeText)
                            .keyboardType(.numbersAndPunctuation)
                            .textFieldStyle(.roundedBorder)
                            .focused($isTextInputFocused)
                    }

                    if parsedCoordinatePair == nil {
                        Label("Enter both valid coordinates, or clear both fields.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let gpsStatus {
                        Label(gpsStatus, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(FieldWorkspacePalette.green)
                    }

                    Text("This site coordinate controls Nearby distance, account routing, and automatic Trip Log account matching. Saved Arrival Points remain separate and are also considered by Trip Log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Account GPS Position")
                } footer: {
                    Text("For the most accurate result, stand at the site or drag the pin to the building entrance or parking area used by technicians.")
                }

                Section {
                    Label(
                        "Field records, files, equipment, saved arrival points, and history remain unchanged.",
                        systemImage: "checkmark.shield.fill"
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FieldWorkspacePalette.background)
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let draft = FireVaultAccountEditDraft(
                            name: name,
                            address: address,
                            category: category,
                            accountId: accountId,
                            phone: phone,
                            latitude: parsedCoordinatePair?.0,
                            longitude: parsedCoordinatePair?.1
                        )
                        if save(draft) { dismiss() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextInputFocused = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("edit-account-\(accountID)")
        .fullScreenCover(isPresented: $isShowingPinEditor) {
            FireVaultFullScreenPinEditor(
                pinLabel: normalizedName.isEmpty ? "Account" : normalizedName,
                pinSystemImage: "building.2.fill",
                pinTint: FieldWorkspacePalette.red,
                initialCoordinate: accountCoordinate,
                fallbackCoordinate: locationService.coordinate
            ) { coordinate in
                apply(coordinate, status: "Account pin adjusted")
            }
        }
        .onReceive(locationService.$coordinate.compactMap { $0 }) { coordinate in
            guard isWaitingForCurrentLocation else { return }
            isWaitingForCurrentLocation = false
            apply(coordinate, status: "Using this iPhone’s current position")
        }
        .onChange(of: latitudeText) { _, _ in refreshMapFromFields() }
        .onChange(of: longitudeText) { _, _ in refreshMapFromFields() }
    }

    private func accountEditField(
        _ title: String,
        symbol: String,
        text: Binding<String>,
        lineLimit: Int = 1
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(FieldWorkspacePalette.blue)
                .frame(width: 32, height: 32)
                .background(FieldWorkspacePalette.blue.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.caption2.bold())
                    .tracking(0.65)
                    .foregroundStyle(.secondary)
                TextField(title, text: text, axis: lineLimit > 1 ? .vertical : .horizontal)
                    .lineLimit(1...lineLimit)
                    .font(.body.weight(.semibold))
                    .focused($isTextInputFocused)
            }
        }
        .padding(.vertical, 4)
    }

    private var accountGPSMap: some View {
        Map(position: $mapPosition, interactionModes: []) {
            if let accountCoordinate {
                Annotation("", coordinate: accountCoordinate) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(FieldWorkspacePalette.red, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .overlay {
            if accountCoordinate == nil {
                ContentUnavailableView(
                    "GPS Position Needed",
                    systemImage: "mappin.slash",
                    description: Text("Use the current location, adjust the pin, or enter coordinates.")
                )
                .background(.regularMaterial)
            }
        }
    }

    private func apply(_ coordinate: CLLocationCoordinate2D, status: String) {
        latitudeText = String(format: "%.6f", coordinate.latitude)
        longitudeText = String(format: "%.6f", coordinate.longitude)
        mapPosition = .region(.init(
            center: coordinate,
            span: .init(latitudeDelta: 0.0012, longitudeDelta: 0.0012)
        ))
        gpsStatus = status
    }

    private func refreshMapFromFields() {
        guard let accountCoordinate else { return }
        mapPosition = .region(.init(
            center: accountCoordinate,
            span: .init(latitudeDelta: 0.0012, longitudeDelta: 0.0012)
        ))
    }
}

private struct MapArrivalView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @State private var editingLocation: FireVaultWorkspaceLocation?
    @State private var isShowingEditor = false
    @State private var isImportingCSV = false
    @State private var importNotice: FireVaultLocationImportNotice?
    @State private var isShowingAccountBrief = false
    @State private var isLoadingAccountBrief = false
    @State private var accountBrief: String?
    @State private var accountBriefError: String?

    private var sortedLocations: [FireVaultWorkspaceLocation] {
        account.locations.sorted { lhs, rhs in
            let leftRank = locationSortRank(lhs)
            let rightRank = locationSortRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                if settings.isFeatureVisible("account.brief") {
                    accountBriefAction
                }

                HStack {
                    Label("ARRIVAL MAP", systemImage: "mappin.and.ellipse")
                        .font(.caption.bold())
                        .tracking(0.8)
                        .foregroundStyle(FieldWorkspacePalette.blue)
                    Spacer()
                    editLocationsMenu
                }

                WorkspaceMap(account: account)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityLabel("Static arrival map showing all saved locations")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(FieldWorkspacePalette.background)

            VStack(alignment: .leading, spacing: 8) {
                Text("SAVED ARRIVAL POINTS")
                    .font(.caption.bold())
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 8) {
                if account.locations.isEmpty {
                    ContentUnavailableView(
                        "No Saved Locations",
                        systemImage: "mappin.slash",
                        description: Text("Add an entrance, parking area, panel, riser, FDC, or other exact field location.")
                    )
                    .padding(.top, 30)
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
                            HStack(spacing: 12) {
                                Image(systemName: location.arrivalMapSymbol)
                                    .font(.headline)
                                    .foregroundStyle(location.resolvedPinColor.color)
                                    .frame(width: 34, height: 34)
                                    .background(location.resolvedPinColor.color.opacity(0.14), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(location.label).font(.headline).foregroundStyle(.primary)
                                    Text([location.subtitle, location.plusCode].filter { !$0.isEmpty }.joined(separator: " • "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if location.coordinate != nil {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(FieldWorkspacePalette.blue)
                                }
                            }
                            .padding(12)
                            .background(
                                FieldWorkspacePalette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.white.opacity(0.07), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.deleteLocation(accountID: account.id, locationID: location.id)
                            }
                        }
                    }
                }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxHeight: .infinity)
        }
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Arrival Map")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingAccountBrief) {
            FireVaultAccountBriefSheet(
                accountName: account.name,
                isLoading: isLoadingAccountBrief,
                brief: accountBrief,
                errorMessage: accountBriefError,
                retry: generateAccountBrief
            )
        }
        .sheet(isPresented: $isShowingEditor) {
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
        .fileImporter(
            isPresented: $isImportingCSV,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { selection in
            importLocations(from: selection)
        }
        .alert(item: $importNotice) { notice in
            Alert(
                title: Text("Locations CSV Import"),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var editLocationsMenu: some View {
        Menu {
            Button("Add Location", systemImage: "plus") {
                editingLocation = nil
                isShowingEditor = true
            }
            Button("Import CSV", systemImage: "square.and.arrow.down") {
                isImportingCSV = true
            }

            if !account.locations.isEmpty {
                Divider()
                Section("Edit Saved Locations") {
                    ForEach(sortedLocations) { location in
                        Button(location.label, systemImage: location.arrivalMapSymbol) {
                            editingLocation = location
                            isShowingEditor = true
                        }
                    }
                }
            }
        } label: {
            Label("Edit Locations", systemImage: "pencil.and.list.clipboard")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityHint("Adds, imports, or edits saved arrival points")
    }

    private func locationSortRank(_ location: FireVaultWorkspaceLocation) -> Int {
        let searchable = "\(location.label) \(location.type)".lowercased()
        if searchable.contains("parking") || searchable.contains("park here") { return 0 }
        if searchable.contains("front entrance") || searchable.contains("main entrance") { return 1 }
        if searchable.contains("entrance") { return 2 }
        return 3
    }

    private func importLocations(from selection: Result<[URL], Error>) {
        do {
            guard let url = try selection.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let result = try FireVaultLocationCSVImporter.records(from: data)
            var imported = 0
            for record in result.records {
                if store.addLocation(
                    to: account.id,
                    label: record.name,
                    subtitle: record.details,
                    type: record.type,
                    plusCode: record.plusCode,
                    latitude: record.latitude,
                    longitude: record.longitude,
                    pinColor: record.color
                ) != nil {
                    imported += 1
                }
            }
            let skippedText = result.skipped == 0 ? "" : " \(result.skipped) row(s) were skipped because NAME was blank or coordinates were incomplete."
            importNotice = .init(message: "Imported \(imported) location record(s).\(skippedText)")
        } catch {
            importNotice = .init(message: error.localizedDescription)
        }
    }

    private var accountBriefAction: some View {
        Button(action: generateAccountBrief) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.headline.bold())
                    .foregroundStyle(FieldWorkspacePalette.blue)
                Text("Generate Account Brief")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FieldWorkspacePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FieldWorkspacePalette.blue.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.20), radius: 7, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isLoadingAccountBrief)
        .accessibilityIdentifier("generate-account-brief")
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
}

private struct ArrivalPointDetailView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @ObservedObject var locationService: FireVaultLocationService

    @State private var location: FireVaultWorkspaceLocation
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var mapPosition: MapCameraPosition
    @State private var isShowingEditor = false
    @State private var positionStatus = "Drag on the map to move this pin"

    init(
        account: FireVaultWorkspaceAccount,
        location: FireVaultWorkspaceLocation,
        store: FireVaultStore,
        locationService: FireVaultLocationService
    ) {
        self.account = account
        self.store = store
        self.locationService = locationService
        _location = State(initialValue: location)
        _coordinate = State(initialValue: location.coordinate)
        let center = location.coordinate ?? account.coordinate ?? .init(latitude: 39.5, longitude: -98.35)
        _mapPosition = State(initialValue: .region(.init(
            center: center,
            span: .init(latitudeDelta: 0.00032, longitudeDelta: 0.00032)
        )))
    }

    var body: some View {
        VStack(spacing: 12) {
            MapReader { proxy in
                Map(position: $mapPosition, interactionModes: []) {
                    if let coordinate {
                        Annotation("", coordinate: coordinate) {
                            Image(systemName: location.arrivalMapSymbol)
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(location.resolvedPinColor.color)
                                .background(.white, in: Circle())
                                .shadow(radius: 5, y: 3)
                                .allowsHitTesting(false)
                                .accessibilityLabel(location.label)
                        }
                    }
                }
                .mapStyle(.imagery(elevation: .realistic))
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .local)
                        .onChanged { value in
                            guard let updated = proxy.convert(value.location, from: .local) else { return }
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                coordinate = updated
                            }
                            positionStatus = "Release to save pin position"
                        }
                        .onEnded { _ in
                            savePinPosition()
                        }
                )
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "hand.draw.fill")
                        .foregroundStyle(FieldWorkspacePalette.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(positionStatus)
                            .font(.subheadline.bold())
                        if let coordinate {
                            Text(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Button("Edit Point", systemImage: "pencil") {
                        isShowingEditor = true
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Walk Here", systemImage: "figure.walk") {
                        openWalkingRoute()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(coordinate == nil)
                }
            }
            .padding(14)
            .background(FieldWorkspacePalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(FieldWorkspacePalette.background.ignoresSafeArea())
        .navigationTitle(location.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingEditor) {
            FireVaultLocationEditorSheet(
                accountName: account.name,
                accountCoordinate: account.coordinate,
                location: location,
                locationService: locationService
            ) { draft in
                let didSave = store.updateLocation(
                    accountID: account.id,
                    locationID: location.id,
                    label: draft.label,
                    subtitle: draft.subtitle,
                    type: draft.type,
                    plusCode: draft.plusCode,
                    latitude: draft.latitude,
                    longitude: draft.longitude,
                    pinColor: draft.pinColor.rawValue
                )
                guard didSave else { return false }
                location.label = draft.label
                location.subtitle = draft.subtitle
                location.type = draft.type
                location.plusCode = draft.plusCode
                location.latitude = draft.latitude
                location.longitude = draft.longitude
                location.pinColor = draft.pinColor.rawValue
                coordinate = location.coordinate
                if let coordinate {
                    zoom(to: coordinate)
                }
                positionStatus = "Location details saved"
                return true
            }
        }
    }

    private func savePinPosition() {
        guard let coordinate else { return }
        let didSave = store.updateLocation(
            accountID: account.id,
            locationID: location.id,
            label: location.label,
            subtitle: location.subtitle,
            type: location.type,
            plusCode: location.plusCode,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pinColor: location.resolvedPinColor.rawValue
        )
        guard didSave else {
            positionStatus = "Pin position could not be saved"
            return
        }
        location.latitude = coordinate.latitude
        location.longitude = coordinate.longitude
        positionStatus = "Pin position saved"
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func zoom(to coordinate: CLLocationCoordinate2D) {
        mapPosition = .region(.init(
            center: coordinate,
            span: .init(latitudeDelta: 0.00032, longitudeDelta: 0.00032)
        ))
    }

    private func openWalkingRoute() {
        guard let coordinate else { return }
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        item.name = location.label
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking,
            MKLaunchOptionsMapTypeKey: MKMapType.hybrid.rawValue
        ])
    }
}

struct FireVaultLocationCSVRecord {
    let name: String
    let details: String
    let type: String
    let plusCode: String
    let latitude: Double?
    let longitude: Double?
    let color: String
}

enum FireVaultLocationCSVError: LocalizedError {
    case unreadable
    case empty
    case missingNameColumn
    case noValidRows

    var errorDescription: String? {
        switch self {
        case .unreadable: "The selected CSV file could not be read."
        case .empty: "The selected CSV file is empty."
        case .missingNameColumn: "The CSV needs a NAME or LOCATION column."
        case .noValidRows: "No location rows with a name were found."
        }
    }
}

struct FireVaultLocationCSVImporter {
    static func records(from data: Data) throws -> (records: [FireVaultLocationCSVRecord], skipped: Int) {
        guard let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16) else { throw FireVaultLocationCSVError.unreadable }
        let table = FireVaultStore.parseCSV(source)
        guard let headers = table.first, !headers.isEmpty else { throw FireVaultLocationCSVError.empty }
        let normalized = headers.map(normalize)

        guard let nameIndex = column(in: normalized, aliases: ["name", "location", "label", "locationname"]) else {
            throw FireVaultLocationCSVError.missingNameColumn
        }
        let detailsIndex = column(in: normalized, aliases: ["details", "detail", "description", "notes", "subtitle"])
        let typeIndex = column(in: normalized, aliases: ["type", "locationtype", "category"])
        let plusCodeIndex = column(in: normalized, aliases: ["pluscode", "googlepluscode"])
        let latitudeIndex = column(in: normalized, aliases: ["latitude", "lat"])
        let longitudeIndex = column(in: normalized, aliases: ["longitude", "long", "lng", "lon"])
        let colorIndex = column(in: normalized, aliases: ["color", "pincolor", "pin"])

        var records: [FireVaultLocationCSVRecord] = []
        var skipped = 0
        for row in table.dropFirst() where row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let name = value(at: nameIndex, in: row)
            guard !name.isEmpty else {
                skipped += 1
                continue
            }

            let latitude = latitudeIndex.flatMap { Double(value(at: $0, in: row)) }
            let longitude = longitudeIndex.flatMap { Double(value(at: $0, in: row)) }
            guard (latitude == nil && longitude == nil) || (latitude != nil && longitude != nil) else {
                skipped += 1
                continue
            }

            records.append(.init(
                name: name,
                details: detailsIndex.map { value(at: $0, in: row) } ?? "",
                type: typeIndex.map { value(at: $0, in: row) } ?? "Other",
                plusCode: plusCodeIndex.map { value(at: $0, in: row) } ?? "",
                latitude: latitude,
                longitude: longitude,
                color: colorIndex.map { value(at: $0, in: row) } ?? FireVaultMapPinColor.purple.rawValue
            ))
        }
        guard !records.isEmpty else { throw FireVaultLocationCSVError.noValidRows }
        return (records, skipped)
    }

    private static func column(in headers: [String], aliases: Set<String>) -> Int? {
        headers.firstIndex(where: aliases.contains)
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func value(at index: Int, in row: [String]) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FireVaultLocationImportNotice: Identifiable {
    let id = UUID()
    let message: String
}

struct FireVaultLocationDraft: Equatable {
    var label: String
    var subtitle: String
    var type: String
    var plusCode: String
    var latitude: Double?
    var longitude: Double?
    var pinColor: FireVaultMapPinColor
}

private enum FireVaultArrivalMapLayer: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.americas.fill"
        case .hybrid: "square.3.layers.3d"
        }
    }
}

struct FireVaultLocationEditorSheet: View {
    let accountName: String
    let accountCoordinate: CLLocationCoordinate2D?
    let location: FireVaultWorkspaceLocation?
    @ObservedObject var locationService: FireVaultLocationService
    let save: (FireVaultLocationDraft) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var subtitle: String
    @State private var type: String
    @State private var plusCode: String
    @State private var latitudeText: String
    @State private var longitudeText: String
    @State private var pinColor: FireVaultMapPinColor
    @State private var isShowingFullScreenPinEditor = false
    @State private var mapPosition: MapCameraPosition
    @State private var mapLayer: FireVaultArrivalMapLayer = .satellite
    @FocusState private var isTextInputFocused: Bool

    init(
        accountName: String,
        accountCoordinate: CLLocationCoordinate2D?,
        location: FireVaultWorkspaceLocation?,
        locationService: FireVaultLocationService,
        save: @escaping (FireVaultLocationDraft) -> Bool
    ) {
        self.accountName = accountName
        self.accountCoordinate = accountCoordinate
        self.location = location
        self.locationService = locationService
        self.save = save
        _label = State(initialValue: location?.label ?? "")
        _subtitle = State(initialValue: location?.subtitle ?? "")
        _type = State(initialValue: location?.type ?? "Other")
        _plusCode = State(initialValue: location?.plusCode ?? "")
        _latitudeText = State(initialValue: location?.latitude.map { String($0) } ?? "")
        _longitudeText = State(initialValue: location?.longitude.map { String($0) } ?? "")
        _pinColor = State(initialValue: location?.resolvedPinColor ?? .purple)
        let initialCoordinate = location?.coordinate
            ?? accountCoordinate
            ?? CLLocationCoordinate2D(latitude: 43.615, longitude: -116.202)
        _mapPosition = State(initialValue: .region(.init(
            center: initialCoordinate,
            span: .init(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
        )))
    }

    private var parsedCoordinates: (Double?, Double?)? {
        let latitudeValue = latitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let longitudeValue = longitudeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if latitudeValue.isEmpty && longitudeValue.isEmpty { return (nil, nil) }
        guard let latitude = Double(latitudeValue), let longitude = Double(longitudeValue),
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return (latitude, longitude)
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedCoordinates != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Text(accountName).foregroundStyle(.secondary)
                }
                Section("Location") {
                    TextField("Location name", text: $label)
                        .focused($isTextInputFocused)
                    TextField("Details", text: $subtitle, axis: .vertical).lineLimit(2...4)
                        .focused($isTextInputFocused)
                    TextField("Type (Entrance, Panel, Riser…)", text: $type)
                        .focused($isTextInputFocused)
                    TextField("Plus Code", text: $plusCode)
                        .textInputAutocapitalization(.characters)
                        .focused($isTextInputFocused)

                    Picker("Pin Color", selection: $pinColor) {
                        ForEach(FireVaultMapPinColor.allCases) { option in
                            Label(option.rawValue, systemImage: "mappin").tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Exact Location") {
                        locationPinMap
                            .frame(height: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button("Edit Pin Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                            isTextInputFocused = false
                            isShowingFullScreenPinEditor = true
                        }
                        .buttonStyle(.borderedProminent)

                        TextField("Latitude", text: $latitudeText)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($isTextInputFocused)
                        TextField("Longitude", text: $longitudeText)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($isTextInputFocused)
                        if parsedCoordinates == nil {
                            Text("Enter both valid coordinates, or leave both blank.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button("Use Current Location", systemImage: "location.fill") {
                            if let coordinate = locationService.coordinate {
                                apply(coordinate)
                            }
                            locationService.requestCurrentLocation(highAccuracy: true)
                        }
                        if locationService.isLocating {
                            HStack {
                                ProgressView()
                                Text(locationService.statusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if locationService.authorizationStatus == .denied {
                            Button("Open Location Settings", systemImage: "gear") {
                                locationService.openAppSettings()
                            }
                        }

                        Button("Use Account Location", systemImage: "building.2.fill") {
                            if let accountCoordinate {
                                apply(accountCoordinate)
                            }
                        }
                        .disabled(accountCoordinate == nil)

                        if locationCoordinate != nil {
                            Button("Remove Location Pin", systemImage: "mappin.slash", role: .destructive) {
                                latitudeText = ""
                                longitudeText = ""
                            }
                        }

                        Text("Open the full-screen map for landscape editing, map layers, and 3D view.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(location == nil ? "New Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let coordinates = parsedCoordinates else { return }
                        if save(.init(
                            label: label,
                            subtitle: subtitle,
                            type: type,
                            plusCode: plusCode,
                            latitude: coordinates.0,
                            longitude: coordinates.1,
                            pinColor: pinColor
                        )) {
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextInputFocused = false }
                }
            }
        }
        .presentationDetents([.large])
        .fullScreenCover(isPresented: $isShowingFullScreenPinEditor) {
            FireVaultFullScreenPinEditor(
                pinLabel: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Location" : label,
                pinSystemImage: "circle.fill",
                pinTint: pinColor.color,
                initialCoordinate: locationCoordinate,
                fallbackCoordinate: accountCoordinate ?? locationService.coordinate
            ) { coordinate in
                apply(coordinate)
            }
        }
        .onReceive(locationService.$coordinate.compactMap { $0 }) { coordinate in
            if locationService.isLocating {
                apply(coordinate)
            }
        }
    }

    private func apply(_ coordinate: CLLocationCoordinate2D) {
        latitudeText = String(format: "%.6f", coordinate.latitude)
        longitudeText = String(format: "%.6f", coordinate.longitude)
        mapPosition = .region(.init(
            center: coordinate,
            span: .init(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
        ))
    }

    private var locationCoordinate: CLLocationCoordinate2D? {
        guard let parsedCoordinates,
              let latitude = parsedCoordinates.0,
              let longitude = parsedCoordinates.1 else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    private var locationPinMap: some View {
        ZStack(alignment: .topTrailing) {
            locationPinMapForSelectedLayer

            Menu {
                Picker("Map Layer", selection: $mapLayer) {
                    ForEach(FireVaultArrivalMapLayer.allCases) { layer in
                        Label(layer.rawValue, systemImage: layer.symbol).tag(layer)
                    }
                }
            } label: {
                Image(systemName: "square.3.layers.3d.top.filled")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
            }
            .padding(10)
            .accessibilityLabel("Map Layer")
        }
    }

    @ViewBuilder
    private var locationPinMapForSelectedLayer: some View {
        switch mapLayer {
        case .standard:
            locationPinMapContent.mapStyle(.standard(elevation: .realistic))
        case .satellite:
            locationPinMapContent.mapStyle(.imagery(elevation: .realistic))
        case .hybrid:
            locationPinMapContent.mapStyle(.hybrid(elevation: .realistic))
        }
    }

    private var locationPinMapContent: some View {
        Map(position: $mapPosition, interactionModes: []) {
            if let locationCoordinate {
                Annotation("", coordinate: locationCoordinate) {
                    VStack(spacing: 3) {
                        Image(systemName: location?.arrivalMapSymbol ?? "mappin.circle.fill")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(pinColor.color)
                            .background(.white, in: Circle())
                            .shadow(radius: 4, y: 2)
                        Text(label.isEmpty ? "Location" : label)
                            .font(.caption2.bold())
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
            }
        }
    }
}

private struct WorkspaceMap: View {
    let account: FireVaultWorkspaceAccount

    private var validLocations: [FireVaultWorkspaceLocation] {
        account.locations.filter { $0.coordinate != nil }
    }

    private var region: MKCoordinateRegion {
        let coordinates = [account.coordinate].compactMap { $0 } + validLocations.compactMap(\.coordinate)
        guard !coordinates.isEmpty else {
            return .init(center: .init(latitude: 39.5, longitude: -98.35), span: .init(latitudeDelta: 35, longitudeDelta: 35))
        }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (latitudes.min()! + latitudes.max()!) / 2,
            longitude: (longitudes.min()! + longitudes.max()!) / 2
        )
        return .init(
            center: center,
            span: .init(
                latitudeDelta: max(0.00055, (latitudes.max()! - latitudes.min()!) * 1.28),
                longitudeDelta: max(0.00055, (longitudes.max()! - longitudes.min()!) * 1.28)
            )
        )
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            if let coordinate = account.coordinate {
                Marker(account.name, systemImage: "shield.fill", coordinate: coordinate)
                    .tint(FieldWorkspacePalette.red)
            }
            ForEach(validLocations) { location in
                if let coordinate = location.coordinate {
                    Annotation(location.label, coordinate: coordinate, anchor: .bottom) {
                        if isParkingLocation(location) {
                            Image(systemName: "parkingsign.circle.fill")
                                .font(.system(size: 32, weight: .black))
                                .foregroundStyle(FieldWorkspacePalette.red)
                                .background(.white, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 4, y: 2)
                            .accessibilityLabel("Parking, \(location.label)")
                        } else {
                            Image(systemName: location.arrivalMapSymbol)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(location.resolvedPinColor.color)
                                .background(.white, in: Circle())
                                .shadow(radius: 3, y: 1)
                                .accessibilityLabel(location.label)
                        }
                    }
                }
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
    }

    private func isParkingLocation(_ location: FireVaultWorkspaceLocation) -> Bool {
        let searchable = "\(location.label) \(location.type)".lowercased()
        return searchable.contains("parking") || searchable.contains("park here")
    }
}

private struct NotesWorkspaceView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @State private var editingNote: FireVaultWorkspaceNote?
    @State private var isShowingEditor = false

    var body: some View {
        List {
            if account.notes.isEmpty {
                ContentUnavailableView(
                    "No Field Notes",
                    systemImage: "note.text.badge.plus",
                    description: Text("Add the first note for this account.")
                )
            } else {
                ForEach(account.notes) { note in
                    Button {
                        editingNote = note
                        isShowingEditor = true
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(note.title).font(.caption.bold()).foregroundStyle(FieldWorkspacePalette.amber)
                                Spacer()
                                Text(note.date).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text(note.text)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.deleteNote(accountID: account.id, noteID: note.id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Field Notes")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Add Note", systemImage: "square.and.pencil") {
                editingNote = nil
                isShowingEditor = true
            }
                .buttonStyle(.glassProminent)
                .padding(12)
                .glassEffect()
        }
        .sheet(isPresented: $isShowingEditor) {
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
    }
}

struct FireVaultNoteDraft: Equatable {
    var title: String
    var text: String
}

struct FireVaultNoteEditorSheet: View {
    let accountName: String
    let note: FireVaultWorkspaceNote?
    let save: (FireVaultNoteDraft) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @FocusState private var isTextInputFocused: Bool

    init(
        accountName: String,
        note: FireVaultWorkspaceNote?,
        save: @escaping (FireVaultNoteDraft) -> Bool
    ) {
        self.accountName = accountName
        self.note = note
        self.save = save
        _title = State(initialValue: note?.title ?? "")
        _text = State(initialValue: note?.text ?? "")
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Text(accountName)
                        .foregroundStyle(.secondary)
                }
                Section("Note") {
                    TextField("Title (optional)", text: $title)
                        .focused($isTextInputFocused)
                    TextField("Field note", text: $text, axis: .vertical)
                        .lineLimit(6...14)
                        .focused($isTextInputFocused)
                }
            }
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if save(.init(title: title, text: text)) {
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextInputFocused = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct FilesScansView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore

    var body: some View {
        List {
            if account.documents.isEmpty {
                ContentUnavailableView(
                    "No Files or Scans",
                    systemImage: "doc.viewfinder",
                    description: Text("Scan a document or add a saved field file.")
                )
            } else {
                ForEach(account.documents) { document in
                    NavigationLink {
                        NativeRecordDetailView(
                            title: document.title,
                            subtitle: document.subtitle,
                            symbol: documentSymbol(document.kind)
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: documentSymbol(document.kind))
                                .font(.headline)
                                .foregroundStyle(documentTint(document.kind))
                                .frame(width: 38, height: 38)
                                .background(documentTint(document.kind).opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                Text([document.subtitle, document.date].filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Files & Scans")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("Add File", systemImage: "plus") { store.addDocument(to: account.id, scan: false) }
                    .buttonStyle(.glass)
                Button("Scan Document", systemImage: "doc.viewfinder") { store.addDocument(to: account.id, scan: true) }
                    .buttonStyle(.glassProminent)
            }
            .padding(12)
            .glassEffect()
        }
    }

    private func documentSymbol(_ kind: String) -> String {
        switch kind { case "scan": return "doc.viewfinder"; case "photo": return "photo"; default: return "doc" }
    }

    private func documentTint(_ kind: String) -> Color {
        switch kind { case "scan": return FieldWorkspacePalette.blue; case "photo": return FieldWorkspacePalette.purple; default: return FieldWorkspacePalette.green }
    }
}

struct FireVaultEquipmentCSVRecord {
    let device: String
    let type: String
    let address: String
}

enum FireVaultEquipmentCSVError: LocalizedError {
    case unreadable
    case empty
    case missingTypeColumn
    case noValidRows

    var errorDescription: String? {
        switch self {
        case .unreadable: "The selected CSV file could not be read."
        case .empty: "The selected CSV file is empty."
        case .missingTypeColumn: "The CSV needs a TYPE or DEVICE TYPE column."
        case .noValidRows: "No equipment rows with a device type were found."
        }
    }
}

struct FireVaultEquipmentCSVImporter {
    static func records(from data: Data) throws -> (records: [FireVaultEquipmentCSVRecord], skipped: Int) {
        guard let source = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16) else { throw FireVaultEquipmentCSVError.unreadable }
        let table = FireVaultStore.parseCSV(source)
        guard let headers = table.first, !headers.isEmpty else { throw FireVaultEquipmentCSVError.empty }
        let normalized = headers.map(normalize)

        let deviceIndex = column(in: normalized, aliases: ["device", "model", "description", "devicedescription"])
        guard let typeIndex = column(
            in: normalized,
            aliases: ["type", "devicetype", "componenttype", "equipmenttype"]
        ) else { throw FireVaultEquipmentCSVError.missingTypeColumn }
        let addressIndex = column(
            in: normalized,
            aliases: ["address", "deviceaddress", "pointaddress", "addressnumber"]
        )

        var records: [FireVaultEquipmentCSVRecord] = []
        var skipped = 0
        for row in table.dropFirst() where row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            let type = value(at: typeIndex, in: row)
            guard !type.isEmpty else {
                skipped += 1
                continue
            }
            records.append(.init(
                device: deviceIndex.map { value(at: $0, in: row) } ?? "",
                type: type,
                address: addressIndex.map { value(at: $0, in: row) } ?? ""
            ))
        }
        guard !records.isEmpty else { throw FireVaultEquipmentCSVError.noValidRows }
        return (records, skipped)
    }

    private static func column(in headers: [String], aliases: Set<String>) -> Int? {
        headers.firstIndex(where: aliases.contains)
    }

    nonisolated private static func normalize(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func value(at index: Int, in row: [String]) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FireVaultEquipmentImportNotice: Identifiable {
    let id = UUID()
    let message: String
}

private struct EquipmentWorkspaceView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @ObservedObject var locationService: FireVaultLocationService
    @State private var editingEquipment: FireVaultWorkspaceEquipment?
    @State private var isShowingEditor = false
    @State private var isImportingCSV = false
    @State private var importNotice: FireVaultEquipmentImportNotice?

    var body: some View {
        List {
            if account.equipment.isEmpty {
                ContentUnavailableView(
                    "No Equipment Saved",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Add the panel, communicator, power supplies, and other serviceable equipment.")
                )
            } else {
                ForEach(account.equipment) { equipment in
                    Button {
                        editingEquipment = equipment
                        isShowingEditor = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundStyle(FieldWorkspacePalette.green)
                                .frame(width: 38, height: 38)
                                .background(FieldWorkspacePalette.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(equipment.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                Text(equipment.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            if !equipment.deviceAddress.isEmpty {
                                Text(equipment.deviceAddress)
                                    .font(.caption2.monospaced().bold())
                                    .foregroundStyle(FieldWorkspacePalette.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.deleteEquipment(accountID: account.id, equipmentID: equipment.id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("Import CSV", systemImage: "square.and.arrow.down") {
                    isImportingCSV = true
                }
                .buttonStyle(.glass)

                Button("Add Equipment", systemImage: "plus") {
                    editingEquipment = nil
                    isShowingEditor = true
                }
                .buttonStyle(.glassProminent)
            }
            .padding(12)
            .glassEffect()
        }
        .sheet(isPresented: $isShowingEditor) {
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
        .fileImporter(
            isPresented: $isImportingCSV,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { selection in
            importEquipment(from: selection)
        }
        .alert(item: $importNotice) { notice in
            Alert(
                title: Text("Equipment CSV Import"),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func importEquipment(from selection: Result<[URL], Error>) {
        do {
            guard let url = try selection.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let result = try FireVaultEquipmentCSVImporter.records(from: data)
            var imported = 0
            for record in result.records {
                if store.addEquipment(
                    to: account.id,
                    title: record.type,
                    subtitle: record.device,
                    status: record.address
                ) != nil {
                    imported += 1
                }
            }
            let skippedText = result.skipped == 0 ? "" : " \(result.skipped) row(s) were skipped because TYPE was blank."
            importNotice = .init(message: "Imported \(imported) equipment record(s).\(skippedText)")
        } catch {
            importNotice = .init(message: error.localizedDescription)
        }
    }
}

struct FireVaultEquipmentDraft: Equatable {
    var title: String
    var subtitle: String
    var deviceAddress: String
    var latitude: Double?
    var longitude: Double?
    var pinColor: FireVaultMapPinColor
}

struct FireVaultEquipmentEditorSheet: View {
    let accountName: String
    let accountCoordinate: CLLocationCoordinate2D?
    let equipment: FireVaultWorkspaceEquipment?
    @ObservedObject var locationService: FireVaultLocationService
    let save: (FireVaultEquipmentDraft) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var subtitle: String
    @State private var deviceAddress: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var mapPosition: MapCameraPosition
    @State private var mapSpan: CLLocationDegrees = 0.0005
    @State private var isShowingComponentPicker = false
    @State private var isShowingFullScreenPinEditor = false
    @State private var showsLocation: Bool
    @State private var pinColor: FireVaultMapPinColor
    @FocusState private var isTextInputFocused: Bool

    init(
        accountName: String,
        accountCoordinate: CLLocationCoordinate2D?,
        equipment: FireVaultWorkspaceEquipment?,
        locationService: FireVaultLocationService,
        save: @escaping (FireVaultEquipmentDraft) -> Bool
    ) {
        self.accountName = accountName
        self.accountCoordinate = accountCoordinate
        self.equipment = equipment
        self.locationService = locationService
        self.save = save
        _title = State(initialValue: equipment?.title ?? FireVaultEquipmentComponentCatalog.types[0])
        _subtitle = State(initialValue: equipment?.subtitle ?? "")
        _deviceAddress = State(initialValue: equipment?.deviceAddress ?? "")
        _latitude = State(initialValue: equipment?.latitude)
        _longitude = State(initialValue: equipment?.longitude)
        _showsLocation = State(initialValue: equipment?.coordinate != nil)
        _pinColor = State(initialValue: equipment?.resolvedPinColor ?? .green)
        let initialCoordinate = equipment?.coordinate
            ?? accountCoordinate
            ?? CLLocationCoordinate2D(latitude: 43.615, longitude: -116.202)
        _mapPosition = State(initialValue: .region(.init(
            center: initialCoordinate,
            span: .init(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
        )))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Text(accountName).foregroundStyle(.secondary)
                }
                Section("Equipment") {
                    Button {
                        isTextInputFocused = false
                        isShowingComponentPicker = true
                    } label: {
                        HStack {
                            Text("Component Type")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(title)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)

                    TextField("Model or description", text: $subtitle, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($isTextInputFocused)
                    TextField("Device Address", text: $deviceAddress)
                        .focused($isTextInputFocused)
                        .textInputAutocapitalization(.characters)

                    Toggle("Show Location", isOn: $showsLocation)

                    Picker("Pin Color", selection: $pinColor) {
                        ForEach(FireVaultMapPinColor.allCases) { option in
                            Label(option.rawValue, systemImage: "circle.fill").tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                if showsLocation {
                    Section("Exact Equipment Location") {
                        equipmentPinMap
                            .frame(height: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button("Edit Pin Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                            isTextInputFocused = false
                            isShowingFullScreenPinEditor = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Use Current Location", systemImage: "location.fill") {
                            if let coordinate = locationService.coordinate {
                                apply(coordinate)
                            }
                            locationService.requestCurrentLocation(highAccuracy: true)
                        }
                        if locationService.isLocating {
                            HStack {
                                ProgressView()
                                Text(locationService.statusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if locationService.authorizationStatus == .denied {
                            Button("Open Location Settings", systemImage: "gear") {
                                locationService.openAppSettings()
                            }
                        }

                        Button("Use Account Location", systemImage: "building.2.fill") {
                            if let accountCoordinate { apply(accountCoordinate) }
                        }
                        .disabled(accountCoordinate == nil)

                        if latitude != nil && longitude != nil {
                            Button("Remove Equipment Pin", systemImage: "mappin.slash", role: .destructive) {
                                latitude = nil
                                longitude = nil
                            }
                        }

                        Text("For precise placement, open the full-screen map and rotate the iPhone to landscape.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(equipment == nil ? "New Equipment" : "Edit Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if save(.init(
                            title: title,
                            subtitle: subtitle,
                            deviceAddress: deviceAddress,
                            latitude: latitude,
                            longitude: longitude,
                            pinColor: pinColor
                        )) {
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextInputFocused = false }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $isShowingComponentPicker) {
            FireVaultComponentTypePickerSheet(selection: $title, componentTypes: componentTypes)
        }
        .fullScreenCover(isPresented: $isShowingFullScreenPinEditor) {
            FireVaultFullScreenPinEditor(
                pinLabel: title,
                pinSystemImage: "circle.fill",
                pinTint: pinColor.color,
                initialCoordinate: equipmentCoordinate,
                fallbackCoordinate: accountCoordinate ?? locationService.coordinate
            ) { coordinate in
                apply(coordinate)
            }
        }
        .onReceive(locationService.$coordinate.compactMap { $0 }) { coordinate in
            apply(coordinate)
        }
    }

    private var equipmentCoordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    private var componentTypes: [String] {
        FireVaultEquipmentComponentCatalog.types.contains(title)
            ? FireVaultEquipmentComponentCatalog.types
            : [title] + FireVaultEquipmentComponentCatalog.types
    }

    private var equipmentPinMap: some View {
        Map(position: $mapPosition, interactionModes: []) {
            if let equipmentCoordinate {
                Annotation("", coordinate: equipmentCoordinate) {
                    Circle()
                        .fill(pinColor.color)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .frame(width: 24, height: 24)
                        .shadow(radius: 4, y: 2)
                        .accessibilityLabel(title)
                }
            }
        }
    }

    private func apply(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        mapSpan = 0.0005
        recenterMap(on: coordinate)
    }

    private func recenterMap() {
        guard let equipmentCoordinate else { return }
        recenterMap(on: equipmentCoordinate)
    }

    private func recenterMap(on coordinate: CLLocationCoordinate2D) {
        mapPosition = .region(.init(
            center: coordinate,
            span: .init(latitudeDelta: mapSpan, longitudeDelta: mapSpan)
        ))
    }
}

private struct FireVaultComponentTypePickerSheet: View {
    @Binding var selection: String
    let componentTypes: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var pendingSelection: String

    init(selection: Binding<String>, componentTypes: [String]) {
        _selection = selection
        self.componentTypes = componentTypes
        _pendingSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text("Component Type").font(.headline)
                Spacer()
                Button("Select") {
                    selection = pendingSelection
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            Picker("Component Type", selection: $pendingSelection) {
                ForEach(componentTypes, id: \.self) { component in
                    Text(component).tag(component)
                }
            }
            .pickerStyle(.wheel)
        }
        .presentationDetents([.height(260)])
    }
}

private struct FireVaultFullScreenPinEditor: View {
    private enum MapLayer: String, CaseIterable, Identifiable {
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

    let pinLabel: String
    let pinSystemImage: String
    let pinTint: Color
    let save: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var coordinate: CLLocationCoordinate2D
    @State private var mapSpan: CLLocationDegrees = 0.0005
    @State private var mapPosition: MapCameraPosition
    @State private var mapLayer: MapLayer = .standard
    @State private var is3DEnabled = false
    @GestureState private var pinDragTranslation: CGSize = .zero

    init(
        pinLabel: String,
        pinSystemImage: String,
        pinTint: Color,
        initialCoordinate: CLLocationCoordinate2D?,
        fallbackCoordinate: CLLocationCoordinate2D?,
        save: @escaping (CLLocationCoordinate2D) -> Void
    ) {
        let start = initialCoordinate
            ?? fallbackCoordinate
            ?? CLLocationCoordinate2D(latitude: 43.615, longitude: -116.202)
        self.pinLabel = pinLabel
        self.pinSystemImage = pinSystemImage
        self.pinTint = pinTint
        self.save = save
        _coordinate = State(initialValue: start)
        _mapPosition = State(initialValue: .region(.init(
            center: start,
            span: .init(latitudeDelta: 0.0005, longitudeDelta: 0.0005)
        )))
    }

    var body: some View {
        GeometryReader { geometry in
            MapReader { proxy in
                ZStack {
                    styledMap(proxy: proxy)

                    VStack(spacing: 10) {
                        HStack {
                            Button("Cancel") { dismiss() }
                                .buttonStyle(.borderedProminent)
                                .tint(.secondary)

                            Spacer()

                            VStack(spacing: 2) {
                                Text("Location Pin").font(.headline)
                                Text("Press and drag the pin • Pinch to zoom")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())

                            Spacer()

                            Button("Save Pin") {
                                save(coordinate)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if geometry.size.height > geometry.size.width {
                            Label("Rotate iPhone to landscape for precise placement", systemImage: "iphone.gen3.radiowaves.left.and.right")
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())
                        }

                        Spacer()

                        HStack {
                            Menu {
                                Picker("Map Layer", selection: $mapLayer) {
                                    ForEach(MapLayer.allCases) { layer in
                                        Label(layer.rawValue, systemImage: layer.symbol).tag(layer)
                                    }
                                }
                                Divider()
                                Button {
                                    is3DEnabled.toggle()
                                    updatePerspective()
                                } label: {
                                    Label(
                                        is3DEnabled ? "Return to 2D" : "3D View",
                                        systemImage: is3DEnabled ? "view.2d" : "view.3d"
                                    )
                                }
                            } label: {
                                Label(mapLayer.rawValue, systemImage: "square.3.layers.3d.top.filled")
                            }
                            .buttonStyle(.borderedProminent)

                            Spacer()
                            VStack(spacing: 8) {
                                Button {
                                    mapSpan = max(mapSpan / 2, 0.00005)
                                    recenterMap()
                                } label: {
                                    Image(systemName: "plus.magnifyingglass")
                                }
                                Button {
                                    mapSpan = min(mapSpan * 2, 0.02)
                                    recenterMap()
                                } label: {
                                    Image(systemName: "minus.magnifyingglass")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.black)
        .onAppear {
            FireVaultOrientationCoordinator.beginOverlayPlacement()
        }
        .onDisappear {
            FireVaultOrientationCoordinator.finishOverlayPlacement()
        }
    }

    @ViewBuilder
    private func styledMap(proxy: MapProxy) -> some View {
        switch mapLayer {
        case .standard:
            equipmentMap(proxy: proxy).mapStyle(.standard(elevation: .realistic))
        case .hybrid:
            equipmentMap(proxy: proxy).mapStyle(.hybrid(elevation: .realistic))
        case .imagery:
            equipmentMap(proxy: proxy).mapStyle(.imagery(elevation: .realistic))
        }
    }

    private func equipmentMap(proxy: MapProxy) -> some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
            Annotation("", coordinate: coordinate) {
                VStack(spacing: 3) {
                    if pinSystemImage == "circle.fill" {
                        Circle()
                            .fill(pinTint)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                            .frame(width: 26, height: 26)
                            .shadow(radius: 6, y: 3)
                    } else {
                        Image(systemName: pinSystemImage)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(13)
                            .background(pinTint, in: Circle())
                            .shadow(radius: 6, y: 3)
                    }
                    Text(equipmentDisplayLabel)
                        .font(.caption2.bold())
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                }
                .contentShape(Rectangle())
                .offset(pinDragTranslation)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .local)
                        .updating($pinDragTranslation) { drag, translation, _ in
                            translation = drag.translation
                        }
                        .onEnded { drag in
                            guard let startPoint = proxy.convert(coordinate, to: .local) else { return }
                            let destination = CGPoint(
                                x: startPoint.x + drag.translation.width,
                                y: startPoint.y + drag.translation.height
                            )
                            if let converted = proxy.convert(destination, from: .local) {
                                coordinate = converted
                            }
                        }
                )
            }
        }
        .ignoresSafeArea()
    }

    private var equipmentDisplayLabel: String {
        if let openingParenthesis = pinLabel.firstIndex(of: "("),
           let closingParenthesis = pinLabel.firstIndex(of: ")"),
           openingParenthesis < closingParenthesis {
            let acronym = pinLabel[pinLabel.index(after: openingParenthesis)..<closingParenthesis]
            if !acronym.isEmpty { return String(acronym) }
        }
        return pinLabel
    }

    private func recenterMap() {
        mapPosition = .region(.init(
            center: coordinate,
            span: .init(latitudeDelta: mapSpan, longitudeDelta: mapSpan)
        ))
    }

    private func updatePerspective() {
        let distance = max(80, min(mapSpan * 222_000, 4_000))
        mapPosition = .camera(MapCamera(
            centerCoordinate: coordinate,
            distance: distance,
            heading: 0,
            pitch: is3DEnabled ? 55 : 0
        ))
    }
}

private struct NativeRecordDetailView: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(subtitle))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkspaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(FieldWorkspacePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.075), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.20), radius: 9, y: 5)
    }
}

private struct WorkspaceSectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption.bold()).tracking(1.15).foregroundStyle(.secondary)
            Spacer()
            Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct WorkspaceDestinationTile: View {
    let title: String
    let count: Int
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                Spacer()
                Text("\(count)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.78)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(FieldWorkspacePalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

private struct WorkspaceRecentRow: View {
    let item: FireVaultWorkspaceRecent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: recentSymbol(item.kind))
                .font(.subheadline.bold())
                .foregroundStyle(recentColor(item.kind))
                .frame(width: 34, height: 34)
                .background(recentColor(item.kind).opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(item.date).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func recentSymbol(_ kind: String) -> String {
        switch kind { case "document": return "doc"; case "location": return "mappin"; case "visit": return "checkmark.circle"; case "note": return "note.text"; default: return "clock" }
    }

    private func recentColor(_ kind: String) -> Color {
        switch kind { case "document": return FieldWorkspacePalette.blue; case "location": return FieldWorkspacePalette.purple; case "visit": return FieldWorkspacePalette.green; case "note": return FieldWorkspacePalette.amber; default: return FieldWorkspacePalette.amber }
    }
}

private struct WorkspaceQuickAction: View {
    let title: String
    let symbol: String
    let tint: Color
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.14), in: Circle())
                Text(title).font(.caption2.bold()).lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                FieldWorkspacePalette.surfaceRaised.opacity(0.48),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .contentShape(Rectangle())
    }
}

private struct WorkspaceNavButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 34, height: 26)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 2)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(FieldWorkspacePalette.navigationInactive)
            .frame(maxWidth: .infinity)
            .frame(height: NativeShellMetrics.navigationItemHeight)
            .offset(y: NativeShellMetrics.navigationContentOffset)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityHint("Leaves the account workspace and opens \(title)")
        .accessibilityIdentifier("workspace-navigation-\(title.lowercased())")
    }
}

private extension View {
    func workspacePill(color: Color) -> some View {
        self
            .font(.caption2.bold())
            .tracking(0.55)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .overlay { Capsule().stroke(color.opacity(0.25), lineWidth: 1) }
    }
}

private enum FieldWorkspacePalette {
    static let background = NativeShellPalette.background
    static let surface = NativeShellPalette.surface
    static let surfaceRaised = NativeShellPalette.navigationBackground
    static let red = NativeShellPalette.red
    static let blue = NativeShellPalette.blue
    static let green = NativeShellPalette.green
    static let amber = NativeShellPalette.amber
    static let purple = NativeShellPalette.purple
    static let actionSurface = NativeShellPalette.surface
    static let actionDivider = NativeShellPalette.navigationDivider
    static let navigationBackground = NativeShellPalette.navigationBackground
    static let navigationInactive = NativeShellPalette.navigationInactive
    static let navigationDivider = NativeShellPalette.navigationDivider
}

private struct FieldWorkspaceView_Previews: PreviewProvider {
    static var previews: some View {
        FieldWorkspaceView(
            account: .init(
                id: "demo", name: "Boise River Medical Center",
                address: "1550 Demo Medical Way, Boise, ID 83702",
                category: "CLSS", accountId: "G7CB01-01", phone: "2085550100", favorite: true,
                latitude: 43.6178, longitude: -116.197,
                tags: ["Healthcare", "Multi-Building"],
                notes: [.init(id: "n1", title: "Today, 9:15 AM", text: "Verified panel room access and updated the equipment map.", date: "Today")],
                documents: [.init(id: "d1", title: "Fire alarm riser diagram", subtitle: "3-page scan", kind: "scan", date: "Jul 21")],
                equipment: [.init(id: "e1", title: "Notifier NFS2-3030", subtitle: "Main electrical room", status: "Active")],
                locations: [.init(id: "l1", label: "Main Entrance", subtitle: "South doors", type: "Entrance", plusCode: "JRM3+4C", latitude: 43.6177, longitude: -116.1968)],
                recent: [.init(id: "r1", title: "Fire alarm riser diagram", subtitle: "3-page scan added", kind: "document", date: "Today")]
            ),
            store: FireVaultStore(),
            settings: FireVaultNativeSettingsStore(),
            locationService: FireVaultLocationService()
        )
    }
}
