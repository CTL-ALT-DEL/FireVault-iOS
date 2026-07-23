//
//  FieldWorkspace.swift
//  FireVault
//
//  Native, field-first Account workspace for Build 1.04.01.
//

import SwiftUI
import Combine
import MapKit
import WebKit

@MainActor
final class FireVaultWorkspaceBridge: ObservableObject {
    @Published private(set) var account: FireVaultWorkspaceAccount?
    weak var webView: WKWebView?

    func present(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let decoded = try? JSONDecoder().decode(FireVaultWorkspaceAccount.self, from: data) else {
            return
        }
        account = decoded
    }

    func hide() {
        account = nil
    }

    func perform(_ action: String, payload: [String: Any] = [:], dismiss: Bool = true) {
        guard let webView else { return }
        var message = payload
        message["action"] = action
        if let accountID = account?.id { message["accountId"] = accountID }
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              var json = String(data: data, encoding: .utf8) else { return }
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        if dismiss { hide() }
        webView.evaluateJavaScript("window.fireVaultNativeWorkspaceAction?.(\(json));")
    }
}

struct FireVaultWorkspaceAccount: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let category: String
    let accountId: String
    let phone: String
    let favorite: Bool
    let latitude: Double?
    let longitude: Double?
    let tags: [String]
    let notes: [FireVaultWorkspaceNote]
    let documents: [FireVaultWorkspaceDocument]
    let equipment: [FireVaultWorkspaceEquipment]
    let locations: [FireVaultWorkspaceLocation]
    let recent: [FireVaultWorkspaceRecent]

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
}

struct FireVaultWorkspaceNote: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let text: String
    let date: String
}

struct FireVaultWorkspaceDocument: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let kind: String
    let date: String
}

struct FireVaultWorkspaceEquipment: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let status: String
}

struct FireVaultWorkspaceLocation: Codable, Identifiable, Equatable {
    let id: String
    let label: String
    let subtitle: String
    let type: String
    let plusCode: String
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
}

struct FireVaultWorkspaceRecent: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let kind: String
    let date: String
}

struct FieldWorkspaceView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var bridge: FireVaultWorkspaceBridge

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private var previewCoordinate: CLLocationCoordinate2D? {
        account.coordinate ?? account.locations.compactMap(\.coordinate).first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FieldWorkspacePalette.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        identity
                        mapPreview
                        destinations
                        recentActivity
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 184)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        bridge.perform("back")
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.glass)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        bridge.perform("favorite", dismiss: false)
                    } label: {
                        Image(systemName: account.favorite ? "star.fill" : "star")
                            .foregroundStyle(account.favorite ? FieldWorkspacePalette.amber : .primary)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(account.favorite ? "Remove Favorite" : "Add Favorite")

                    Menu {
                        Button("Edit Account", systemImage: "pencil") { bridge.perform("edit") }
                        if !account.phone.isEmpty {
                            Button("Call", systemImage: "phone") { bridge.perform("call", dismiss: false) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Account actions")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    fieldActionDock
                    appNavigation
                }
                .padding(.top, 10)
                .background(FieldWorkspacePalette.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .tint(FieldWorkspacePalette.blue)
        .preferredColorScheme(.dark)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if !account.category.isEmpty {
                    Text(account.category.uppercased())
                        .workspacePill(color: FieldWorkspacePalette.blue)
                }
                if !account.accountId.isEmpty {
                    Text(account.accountId)
                        .workspacePill(color: .secondary)
                }
            }

            Text(account.name)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Label(account.address, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var mapPreview: some View {
        NavigationLink {
            MapArrivalView(account: account, bridge: bridge)
        } label: {
            WorkspaceCard {
                ZStack(alignment: .bottomLeading) {
                    if let coordinate = previewCoordinate {
                        Map(
                            initialPosition: .region(.init(
                                center: coordinate,
                                span: .init(latitudeDelta: 0.008, longitudeDelta: 0.008)
                            )),
                            interactionModes: []
                        ) {
                            Marker(account.name, systemImage: "shield.fill", coordinate: coordinate)
                                .tint(FieldWorkspacePalette.red)
                        }
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
                            Text("MAP & ARRIVAL")
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
        .accessibilityLabel("Open Map and Arrival")
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionTitle(title: "FIELD WORKSPACE", subtitle: "Everything for this location")
            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink {
                    NotesWorkspaceView(account: account, bridge: bridge)
                } label: {
                    WorkspaceDestinationTile(
                        title: "Notes",
                        count: account.notes.count,
                        symbol: "note.text",
                        color: FieldWorkspacePalette.amber
                    )
                }

                NavigationLink {
                    FilesScansView(account: account, bridge: bridge)
                } label: {
                    WorkspaceDestinationTile(
                        title: "Files & Scans",
                        count: account.documents.count,
                        symbol: "doc.viewfinder",
                        color: FieldWorkspacePalette.blue
                    )
                }

                NavigationLink {
                    EquipmentWorkspaceView(account: account, bridge: bridge)
                } label: {
                    WorkspaceDestinationTile(
                        title: "Equipment",
                        count: account.equipment.count,
                        symbol: "wrench.and.screwdriver",
                        color: FieldWorkspacePalette.green
                    )
                }

                NavigationLink {
                    MapArrivalView(account: account, bridge: bridge)
                } label: {
                    WorkspaceDestinationTile(
                        title: "Locations",
                        count: account.locations.count,
                        symbol: "map.fill",
                        color: FieldWorkspacePalette.purple
                    )
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

    private var fieldActionDock: some View {
        HStack(spacing: 6) {
            WorkspaceDockButton(title: "Scan", symbol: "doc.viewfinder", tint: FieldWorkspacePalette.blue) {
                bridge.perform("scan")
            }
            WorkspaceDockButton(title: "Note", symbol: "square.and.pencil", tint: FieldWorkspacePalette.amber) {
                bridge.perform("note")
            }
            WorkspaceDockButton(title: "Camera", symbol: "camera.fill", tint: FieldWorkspacePalette.red) {
                bridge.perform("photo")
            }
            WorkspaceDockButton(title: "Route", symbol: "arrow.triangle.turn.up.right.diamond.fill", tint: FieldWorkspacePalette.green) {
                bridge.perform("route", dismiss: false)
            }
        }
        .padding(7)
        .background(FieldWorkspacePalette.actionSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FieldWorkspacePalette.actionDivider, lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Field actions")
    }

    private var appNavigation: some View {
        HStack(spacing: 0) {
            WorkspaceNavButton(title: "Nearby", symbol: "location.circle") { bridge.perform("nearby") }
            WorkspaceNavButton(title: "Search", symbol: "magnifyingglass") { bridge.perform("search") }
            WorkspaceNavButton(title: "Photo", symbol: "photo") { bridge.perform("photo") }
            WorkspaceNavButton(title: "Settings", symbol: "slider.horizontal.3") { bridge.perform("settings") }
        }
        .padding(.horizontal, 8)
        .padding(.top, 5)
        .padding(.bottom, 2)
        .background(FieldWorkspacePalette.navigationBackground.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FieldWorkspacePalette.navigationDivider)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
        .accessibilityIdentifier("workspace-main-navigation")
    }
}

private struct MapArrivalView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var bridge: FireVaultWorkspaceBridge

    var body: some View {
        List {
            Section {
                WorkspaceMap(account: account)
                    .frame(height: 300)
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            Section("Saved arrival points") {
                if account.locations.isEmpty {
                    ContentUnavailableView(
                        "No Saved Locations",
                        systemImage: "mappin.slash",
                        description: Text("Add an entrance, parking area, panel, riser, FDC, or other exact field location.")
                    )
                } else {
                    ForEach(account.locations) { location in
                        Button {
                            if location.coordinate != nil {
                                bridge.perform("routeLocation", payload: ["id": location.id], dismiss: false)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: locationSymbol(location.type))
                                    .font(.headline)
                                    .foregroundStyle(FieldWorkspacePalette.purple)
                                    .frame(width: 34, height: 34)
                                    .background(FieldWorkspacePalette.purple.opacity(0.14), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(location.label).font(.headline).foregroundStyle(.primary)
                                    Text([location.subtitle, location.plusCode].filter { !$0.isEmpty }.joined(separator: " • "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if location.coordinate != nil {
                                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                                        .foregroundStyle(FieldWorkspacePalette.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Map & Arrival")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("Add Location", systemImage: "plus") { bridge.perform("addLocation") }
                    .buttonStyle(.glass)
                Button("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill") { bridge.perform("route", dismiss: false) }
                    .buttonStyle(.glassProminent)
            }
            .padding(12)
            .glassEffect()
        }
    }

    private func locationSymbol(_ type: String) -> String {
        let value = type.lowercased()
        if value.contains("entrance") || value.contains("door") { return "door.left.hand.open" }
        if value.contains("parking") { return "parkingsign.circle" }
        if value.contains("panel") { return "rectangle.3.group.bubble.left" }
        if value.contains("riser") || value.contains("pump") { return "drop.fill" }
        return "mappin"
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
                latitudeDelta: max(0.006, (latitudes.max()! - latitudes.min()!) * 1.7),
                longitudeDelta: max(0.006, (longitudes.max()! - longitudes.min()!) * 1.7)
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
                    Marker(location.label, systemImage: "mappin", coordinate: coordinate)
                        .tint(FieldWorkspacePalette.purple)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }
}

private struct NotesWorkspaceView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var bridge: FireVaultWorkspaceBridge

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
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Field Notes")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Add Note", systemImage: "square.and.pencil") { bridge.perform("note") }
                .buttonStyle(.glassProminent)
                .padding(12)
                .glassEffect()
        }
    }
}

private struct FilesScansView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var bridge: FireVaultWorkspaceBridge

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
                    Button {
                        bridge.perform("openFile", payload: ["id": document.id])
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
                Button("Add File", systemImage: "plus") { bridge.perform("addFile") }
                    .buttonStyle(.glass)
                Button("Scan Document", systemImage: "doc.viewfinder") { bridge.perform("scan") }
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

private struct EquipmentWorkspaceView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var bridge: FireVaultWorkspaceBridge

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
                        bridge.perform("openEquipment", payload: ["id": equipment.id])
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
                            Text(equipment.status)
                                .font(.caption2.bold())
                                .foregroundStyle(equipment.status.lowercased().contains("attention") ? FieldWorkspacePalette.red : FieldWorkspacePalette.green)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Add Equipment", systemImage: "plus") { bridge.perform("addEquipment") }
                .buttonStyle(.glassProminent)
                .padding(12)
                .glassEffect()
        }
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3.bold())
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Text("\(count)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(title).font(.headline).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.82)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(FieldWorkspacePalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        }
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

private struct WorkspaceDockButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

private struct WorkspaceNavButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(FieldWorkspacePalette.navigationInactive)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
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
    static let background = Color(red: 0.027, green: 0.043, blue: 0.061)
    static let surface = Color(red: 0.070, green: 0.095, blue: 0.122)
    static let surfaceRaised = Color(red: 0.092, green: 0.123, blue: 0.154)
    static let red = Color(red: 1.00, green: 0.29, blue: 0.32)
    static let blue = Color(red: 0.28, green: 0.66, blue: 1.00)
    static let green = Color(red: 0.27, green: 0.86, blue: 0.57)
    static let amber = Color(red: 1.00, green: 0.72, blue: 0.28)
    static let purple = Color(red: 0.70, green: 0.49, blue: 1.00)
    static let actionSurface = Color(red: 0.082, green: 0.108, blue: 0.138)
    static let actionDivider = Color.white.opacity(0.12)
    static let navigationBackground = Color(red: 0.045, green: 0.061, blue: 0.082)
    static let navigationInactive = Color(red: 0.60, green: 0.65, blue: 0.72)
    static let navigationDivider = Color.white.opacity(0.14)
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
            bridge: FireVaultWorkspaceBridge()
        )
    }
}
