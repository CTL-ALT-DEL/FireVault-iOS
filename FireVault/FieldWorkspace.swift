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
import UIKit
import AVKit
import VisionKit

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
    /// Added after the original on-device vault shipped. Optional fields keep
    /// existing archives decodable and identify records needing backfill.
    var cloudID: String? = nil
    var cloudSyncedAt: Date? = nil
    var cloudSyncError: String? = nil

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
    var showOnArrival: Bool? = nil
    var updatedAt: Date? = nil

    var showsOnArrival: Bool { showOnArrival ?? false }
}

struct FireVaultWorkspaceDocument: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var kind: String
    var date: String
    var mediaFileName: String? = nil
    var updatedAt: Date? = nil
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
    var directionsMode: String? = nil

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude,
              CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    var resolvedPinColor: FireVaultMapPinColor {
        FireVaultMapPinColor(rawValue: pinColor ?? "") ?? .purple
    }

    var resolvedDirectionsMode: FireVaultDirectionsMode {
        isParkingLocation ? .driving : .walking
    }
}

enum FireVaultDirectionsMode: String, Codable, CaseIterable, Identifiable {
    case walking = "Walking"
    case driving = "Driving"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .driving: "car.fill"
        }
    }

    var mapKitValue: String {
        switch self {
        case .walking: MKLaunchOptionsDirectionsModeWalking
        case .driving: MKLaunchOptionsDirectionsModeDriving
        }
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
    var updatedAt: Date? = nil
}

enum FireVaultAccountTimestamp {
    static func display(legacy value: String, timestamp: Date? = nil) -> String {
        guard let resolved = timestamp ?? parseLegacy(value) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(resolved)
            ? "'TODAY' HH:mm"
            : "MM/dd/yyyy HH:mm"
        return formatter.string(from: resolved)
    }

    static func dateOnly(legacy value: String, timestamp: Date? = nil) -> String {
        guard let resolved = timestamp ?? parseLegacy(value) else {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = Calendar.current.isDateInToday(resolved)
            ? "'TODAY'"
            : "MM/dd/yyyy"
        return formatter.string(from: resolved)
    }

    private static func parseLegacy(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "today", "now":
            return Date()
        case "yesterday":
            return Calendar.current.date(byAdding: .day, value: -1, to: Date())
        default:
            break
        }

        let localized = DateFormatter()
        localized.locale = .current
        localized.dateStyle = .medium
        localized.timeStyle = .short
        if let date = localized.date(from: trimmed) { return date }

        let short = DateFormatter()
        short.locale = .current
        short.dateStyle = .short
        short.timeStyle = .short
        if let date = short.date(from: trimmed) { return date }

        let monthDay = DateFormatter()
        monthDay.locale = Locale(identifier: "en_US_POSIX")
        monthDay.dateFormat = "MMM d yyyy"
        let year = Calendar.current.component(.year, from: Date())
        return monthDay.date(from: "\(trimmed) \(year)")
    }
}

enum FireVaultAccountSearch {
    static func matches(_ query: String, values: [String]) -> Bool {
        values.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func highlighted(_ value: String, query: String) -> AttributedString {
        guard !query.isEmpty else { return AttributedString(value) }

        var result = AttributedString()
        var remainder = value[value.startIndex...]
        while let match = remainder.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            result.append(AttributedString(String(remainder[..<match.lowerBound])))
            var highlightedMatch = AttributedString(String(remainder[match]))
            highlightedMatch.backgroundColor = .yellow
            highlightedMatch.foregroundColor = .black
            result.append(highlightedMatch)
            remainder = remainder[match.upperBound...]
        }
        result.append(AttributedString(String(remainder)))
        return result
    }
}

extension FireVaultWorkspaceLocation {
    var isParkingLocation: Bool {
        let value = "\(label) \(type)".lowercased()
        return value.contains("parking") || value.contains("park here")
    }

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
    @State private var isConfirmingAccountDeletion = false
    @State private var isDeletingAccount = false
    @State private var accountDeletionError: String?

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]
    private let recentActivityDisplayLimit = 20

    private var photoVideoCount: Int {
        account.documents.filter { $0.kind == "photo" || $0.kind == "video" }.count
    }

    private var fileScanCount: Int {
        account.documents.filter { $0.kind != "photo" && $0.kind != "video" }.count
    }

    private var recentActivityItems: [FireVaultWorkspaceRecent] {
        let currentAccount = store.accounts.first(where: { $0.id == account.id }) ?? account
        return Array(currentAccount.recent.prefix(recentActivityDisplayLimit))
    }

    private var classificationTags: [String] {
        let category = account.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return account.tags.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.localizedCaseInsensitiveCompare(category) != .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FieldWorkspacePalette.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        identity
                        accountQuickActions
                        accountClassifications
                        reportBuilderLink
                        mapPreview
                        destinations
                        recentActivity
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 104)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit Customer Account", systemImage: "pencil") {
                            isShowingAccountEditor = true
                        }
                        Divider()
                        Button("Delete Customer Account", systemImage: "trash", role: .destructive) {
                            isConfirmingAccountDeletion = true
                        }
                        .disabled(isDeletingAccount)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Customer account actions")
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
                store.addNote(
                    to: account.id,
                    title: draft.title,
                    text: draft.text,
                    showOnArrival: draft.showOnArrival
                ) != nil
            }
        }
        .alert("Delete Customer Account?", isPresented: $isConfirmingAccountDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Customer Account", role: .destructive) {
                deleteCustomerAccount()
            }
        } message: {
            Text("This permanently deletes \(account.name) and its notes, files, equipment, and saved locations from this iPhone and FireVault Cloud. This cannot be undone.")
        }
        .alert("Customer Account Not Deleted", isPresented: Binding(
            get: { accountDeletionError != nil },
            set: { if !$0 { accountDeletionError = nil } }
        )) {
            Button("OK", role: .cancel) { accountDeletionError = nil }
        } message: {
            Text(accountDeletionError ?? "Nothing was deleted.")
        }
    }

    private var identity: some View {
        HStack(spacing: 0) {
            VStack {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 15)
            .frame(width: 58)
            .frame(maxHeight: .infinity)
            .background(FieldWorkspacePalette.red)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                if !account.accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("ACCOUNT ID  ·  \(account.accountId)")
                        .font(.caption2.weight(.semibold).monospaced())
                        .tracking(0.7)
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(account.name)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "mappin.and.ellipse")
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(addressLines.street)
                            .font(.subheadline)
                            .lineLimit(2)
                        if let locality = addressLines.locality {
                            Text(locality)
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }
                .foregroundStyle(FieldWorkspacePalette.secondaryText)
                .accessibilityElement(children: .combine)

                if !formattedPhone.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "phone")
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text(formattedPhone)
                            .font(.subheadline)
                    }
                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                    .accessibilityElement(children: .combine)
                }

            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FieldWorkspacePalette.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(FieldWorkspacePalette.navigationDivider, lineWidth: 1)
        }
        .shadow(color: NativeShellPalette.cardShadow, radius: 9, y: 4)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var accountClassifications: some View {
        let category = account.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if !category.isEmpty || !classificationTags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("ACCOUNT CLASSIFICATION")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(FieldWorkspacePalette.secondaryText)

                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        if !category.isEmpty {
                            Text(category).workspacePill(color: FieldWorkspacePalette.red)
                        }
                        ForEach(classificationTags, id: \.self) { tag in
                            Text(tag).workspacePill(color: FieldWorkspacePalette.blue)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 2)
        }
    }

    private var accountQuickActions: some View {
        HStack(spacing: 0) {
            WorkspaceQuickAction(
                title: "Call",
                symbol: "phone.fill",
                tint: FieldWorkspacePalette.red,
                disabled: account.phone.isEmpty
            ) {
                store.call(account.phone)
            }
            actionDivider
            WorkspaceQuickAction(
                title: "Route",
                symbol: "arrow.triangle.turn.up.right.diamond.fill",
                tint: FieldWorkspacePalette.red,
                disabled: account.coordinate == nil
            ) {
                store.openRoute(for: account)
            }
            actionDivider
            WorkspaceQuickAction(
                title: "Note",
                symbol: "square.and.pencil",
                tint: FieldWorkspacePalette.red
            ) {
                isShowingNoteEditor = true
            }
            actionDivider
            WorkspaceQuickAction(
                title: "Edit",
                symbol: "pencil",
                tint: FieldWorkspacePalette.red
            ) {
                isShowingAccountEditor = true
            }
        }
        .padding(.vertical, 7)
        .background(
            FieldWorkspacePalette.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(FieldWorkspacePalette.navigationDivider, lineWidth: 1)
        }
        .shadow(color: NativeShellPalette.cardShadow, radius: 7, y: 3)
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(FieldWorkspacePalette.navigationDivider)
            .frame(width: 1, height: 42)
            .accessibilityHidden(true)
    }

    private func deleteCustomerAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        Task {
            do {
                try await store.deleteCustomerAccount(id: account.id)
            } catch {
                accountDeletionError = error.localizedDescription.isEmpty
                    ? "Nothing was deleted. Check your connection and try again."
                    : error.localizedDescription
            }
            isDeletingAccount = false
        }
    }

    private var mapPreview: some View {
        NavigationLink {
            MapArrivalView(account: account, store: store, settings: settings, locationService: locationService)
        } label: {
            WorkspaceCard {
                HStack(spacing: 13) {
                    Image(systemName: "map.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FieldWorkspacePalette.blue)
                        .frame(width: 42, height: 42)
                        .background(FieldWorkspacePalette.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Arrival Map")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Open map and manage site locations")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FieldWorkspacePalette.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                }
                .padding(13)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Arrival Map")
    }

    private var reportBuilderLink: some View {
        NavigationLink {
            FireVaultAccountReportBuilderView(
                account: account,
                store: store,
                settings: settings
            )
        } label: {
            WorkspaceCard {
                HStack(spacing: 13) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FieldWorkspacePalette.red)
                        .frame(width: 42, height: 42)
                        .background(
                            FieldWorkspacePalette.red.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Generate Report")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Choose a template, facts, photos, and documents")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FieldWorkspacePalette.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                }
                .padding(13)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Generate an account report")
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: 9) {
            WorkspaceSectionTitle(title: "Field Workspace", subtitle: "Everything for this location")
            LazyVGrid(columns: columns, spacing: 9) {
                NavigationLink {
                    NotesWorkspaceView(account: account, store: store)
                } label: {
                    WorkspaceDestinationTile(
                        title: "Notes", count: account.notes.count,
                        symbol: "note.text", color: FieldWorkspacePalette.amber
                    )
                }

                NavigationLink {
                    FilesScansView(account: account, store: store)
                } label: {
                    WorkspaceDestinationTile(
                        title: "Files & Scans", count: fileScanCount,
                        symbol: "doc.viewfinder", color: FieldWorkspacePalette.blue
                    )
                }

                NavigationLink {
                    PhotoVideoLibraryView(account: account, store: store, settings: settings)
                } label: {
                    WorkspaceDestinationTile(
                        title: "Photo / Video", count: photoVideoCount,
                        symbol: "camera.fill", color: FieldWorkspacePalette.purple
                    )
                }

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
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var recentActivity: some View {
        if !recentActivityItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                WorkspaceSectionTitle(
                    title: "Recent Activity",
                    subtitle: "Latest \(recentActivityItems.count) items"
                )
                WorkspaceCard {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(recentActivityItems.enumerated()), id: \.element.id) { index, item in
                                WorkspaceRecentRow(item: item)
                                if index < recentActivityItems.count - 1 {
                                    Divider().padding(.leading, 43)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .scrollIndicators(.visible)
                    .frame(height: 216)
                }
            }
        }
    }

    private var formattedPhone: String {
        let digits = account.phone.filter(\.isNumber)
        guard digits.count == 10 else { return account.phone.trimmingCharacters(in: .whitespacesAndNewlines) }
        let areaEnd = digits.index(digits.startIndex, offsetBy: 3)
        let exchangeEnd = digits.index(areaEnd, offsetBy: 3)
        return "(\(digits[..<areaEnd])) \(digits[areaEnd..<exchangeEnd])-\(digits[exchangeEnd...])"
    }

    private var addressLines: (street: String, locality: String?) {
        let normalized = account.address
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: "\r", with: ",")
        let components = normalized
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !components.isEmpty else { return ("No address saved", nil) }
        guard components.count >= 2 else { return (components[0], nil) }

        let localityStart = max(1, components.count - 2)
        let street = components[..<localityStart].joined(separator: ", ")
        let locality = components[localityStart...].joined(separator: ", ")
        return (street, locality)
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
                                .foregroundStyle(FieldWorkspacePalette.secondaryText)
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
                    if !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Remove Category", systemImage: "xmark.circle", role: .destructive) {
                            category = ""
                        }
                        .accessibilityHint("Clears this account category and prevents category rules from immediately restoring it")
                    } else {
                        Label("No category assigned", systemImage: "tag.slash")
                            .foregroundStyle(FieldWorkspacePalette.secondaryText)
                    }
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
                                .foregroundStyle(FieldWorkspacePalette.secondaryText)
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
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
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
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FieldWorkspacePalette.background)
            .navigationTitle("Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    WorkspaceEditorToolbarButton(kind: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    WorkspaceEditorToolbarButton(kind: .save) {
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
                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
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
    @State private var searchText = ""
    @State private var expandedLocationIDs: Set<String> = []

    private var sortedLocations: [FireVaultWorkspaceLocation] {
        account.locations.sorted { lhs, rhs in
            let leftRank = locationSortRank(lhs)
            let rightRank = locationSortRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredLocations: [FireVaultWorkspaceLocation] {
        guard !searchQuery.isEmpty else { return sortedLocations }
        return sortedLocations.filter { location in
            FireVaultAccountSearch.matches(
                searchQuery,
                values: [location.label, location.subtitle, location.type, location.plusCode]
            )
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
                    Button {
                        editingLocation = nil
                        isShowingEditor = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Add Site Location")
                    editLocationsMenu
                }

                WorkspaceMap(
                    account: account,
                    mapLayer: settings.gps.resolvedArrivalPointMapLayer,
                    is3D: settings.gps.resolvedArrivalPointMapIs3D
                )
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
                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                    .padding(.horizontal, 16)

                WorkspaceSearchField(text: $searchText, prompt: "Search site locations")
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
                } else if filteredLocations.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                        .padding(.top, 30)
                } else {
                    ForEach(filteredLocations) { location in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                toggleLocation(location)
                            } label: {
                                HStack(spacing: 12) {
                                Image(systemName: location.arrivalMapSymbol)
                                    .font(.headline)
                                    .foregroundStyle(location.resolvedPinColor.color)
                                    .frame(width: 34, height: 34)
                                    .background(location.resolvedPinColor.color.opacity(0.14), in: Circle())
                                    Text(FireVaultAccountSearch.highlighted(location.label, query: searchQuery))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                Spacer()
                                    Text(location.resolvedDirectionsMode.rawValue)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                                    Image(systemName: expandedLocationIDs.contains(location.id) ? "chevron.up" : "chevron.down")
                                        .font(.caption2.bold())
                                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                                }
                                .padding(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if expandedLocationIDs.contains(location.id) {
                                Divider().padding(.leading, 58)
                                let details = [location.subtitle, location.type, location.plusCode]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " • ")
                                if !details.isEmpty {
                                    Text(FireVaultAccountSearch.highlighted(details, query: searchQuery))
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.top, 10)
                                }
                                HStack {
                                    if !searchQuery.isEmpty {
                                        Label("Search match", systemImage: "highlighter")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(FieldWorkspacePalette.secondaryText)
                                    }
                                    Spacer()
                                    Button("Edit", systemImage: "pencil") {
                                        editingLocation = location
                                        isShowingEditor = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    NavigationLink {
                                        ArrivalPointDetailView(
                                            account: account,
                                            location: location,
                                            store: store,
                                            settings: settings,
                                            locationService: locationService
                                        )
                                    } label: {
                                        Label("Open", systemImage: "arrow.up.right.square")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 10)
                                .padding(.bottom, 10)
                            }
                        }
                        .background(
                            FieldWorkspacePalette.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.07), lineWidth: 1)
                        }
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
        .onChange(of: searchText) { _, _ in
            expandedLocationIDs = searchQuery.isEmpty
                ? []
                : Set(filteredLocations.map(\.id))
        }
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
                        pinColor: draft.pinColor.rawValue,
                        directionsMode: draft.directionsMode.rawValue
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
                    pinColor: draft.pinColor.rawValue,
                    directionsMode: draft.directionsMode.rawValue
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

    private func toggleLocation(_ location: FireVaultWorkspaceLocation) {
        if expandedLocationIDs.contains(location.id) {
            expandedLocationIDs.remove(location.id)
        } else {
            expandedLocationIDs.insert(location.id)
        }
    }

    private var editLocationsMenu: some View {
        Menu {
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
            Label("Manage", systemImage: "pencil.and.list.clipboard")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityHint("Imports or edits saved site locations")
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
    @ObservedObject var settings: FireVaultNativeSettingsStore
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
        settings: FireVaultNativeSettingsStore,
        locationService: FireVaultLocationService
    ) {
        self.account = account
        self.store = store
        self.settings = settings
        self.locationService = locationService
        _location = State(initialValue: location)
        _coordinate = State(initialValue: location.coordinate)
        let center = location.coordinate ?? account.coordinate ?? .init(latitude: 39.5, longitude: -98.35)
        _mapPosition = State(initialValue: .camera(MapCamera(
            centerCoordinate: center,
            distance: 120,
            heading: 0,
            pitch: settings.gps.resolvedArrivalPointMapIs3D ? 55 : 0
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
                .modifier(FireVaultArrivalMapStyleModifier(
                    layer: settings.gps.resolvedArrivalPointMapLayer,
                    is3D: settings.gps.resolvedArrivalPointMapIs3D
                ))
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
                                .foregroundStyle(FieldWorkspacePalette.secondaryText)
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

                    Button(routeButtonTitle, systemImage: location.resolvedDirectionsMode.symbol) {
                        openRoute()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(coordinate == nil)
                }

                if !location.plusCode.isEmpty {
                    HStack(spacing: 10) {
                        Button("Copy Code", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = location.plusCode
                            positionStatus = "Plus Code copied"
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Google Maps", systemImage: "map.fill") {
                            openGoogleMaps()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }
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
                    pinColor: draft.pinColor.rawValue,
                    directionsMode: draft.directionsMode.rawValue
                )
                guard didSave else { return false }
                let preferences = FireVaultNativeSettingsStore().preferences.plusCodes
                location.label = draft.label
                location.subtitle = draft.subtitle
                location.type = draft.type
                location.plusCode = FireVaultPlusCode.codeForStorage(
                    enteredCode: draft.plusCode,
                    latitude: draft.latitude,
                    longitude: draft.longitude,
                    length: preferences.locationLength,
                    autoGenerate: preferences.autoGenerate
                ) ?? draft.plusCode
                location.latitude = draft.latitude
                location.longitude = draft.longitude
                location.pinColor = draft.pinColor.rawValue
                location.directionsMode = draft.directionsMode.rawValue
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
        let preferences = FireVaultNativeSettingsStore().preferences.plusCodes
        let didSave = store.updateLocation(
            accountID: account.id,
            locationID: location.id,
            label: location.label,
            subtitle: location.subtitle,
            type: location.type,
            plusCode: location.plusCode,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pinColor: location.resolvedPinColor.rawValue,
            directionsMode: location.resolvedDirectionsMode.rawValue
        )
        guard didSave else {
            positionStatus = "Pin position could not be saved"
            return
        }
        location.latitude = coordinate.latitude
        location.longitude = coordinate.longitude
        location.plusCode = FireVaultPlusCode.codeForStorage(
            enteredCode: location.plusCode,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            length: preferences.locationLength,
            autoGenerate: preferences.autoGenerate
        ) ?? location.plusCode
        positionStatus = "Pin position saved"
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func zoom(to coordinate: CLLocationCoordinate2D) {
        mapPosition = .region(.init(
            center: coordinate,
            span: .init(latitudeDelta: 0.00032, longitudeDelta: 0.00032)
        ))
    }

    private var routeButtonTitle: String {
        location.resolvedDirectionsMode == .walking ? "Walk Here" : "Drive Here"
    }

    private func openGoogleMaps() {
        guard let appURL = FireVaultPlusCode.googleMapsAppURL(for: location.plusCode) else { return }
        UIApplication.shared.open(appURL, options: [:]) { opened in
            guard !opened,
                  let webURL = FireVaultPlusCode.googleMapsURL(for: location.plusCode) else { return }
            UIApplication.shared.open(webURL, options: [:])
        }
    }

    private func openRoute() {
        guard let coordinate else { return }
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        item.name = location.label
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: location.resolvedDirectionsMode.mapKitValue,
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
    var directionsMode: FireVaultDirectionsMode
}

private enum FireVaultArrivalMapLayer: String, CaseIterable, Identifiable {
    case standard = "Standard 3D"
    case satellite = "Satellite 3D"
    case hybrid = "Hybrid 3D"

    var id: String { rawValue }

    init(storageValue: String) {
        switch storageValue {
        case "satellite": self = .satellite
        case "hybrid": self = .hybrid
        default: self = .standard
        }
    }

    var storageValue: String {
        switch self {
        case .standard: "standard"
        case .satellite: "satellite"
        case .hybrid: "hybrid"
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

private struct FireVaultArrivalMapStyleModifier: ViewModifier {
    let layer: String
    let is3D: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch (layer, is3D) {
        case ("satellite", true): content.mapStyle(.imagery(elevation: .realistic))
        case ("satellite", false): content.mapStyle(.imagery(elevation: .flat))
        case ("hybrid", true): content.mapStyle(.hybrid(elevation: .realistic))
        case ("hybrid", false): content.mapStyle(.hybrid(elevation: .flat))
        case (_, true): content.mapStyle(.standard(elevation: .realistic))
        default: content.mapStyle(.standard(elevation: .flat))
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
    @State private var mapLayer: FireVaultArrivalMapLayer = .standard
    @State private var mapIs3D = true
    @FocusState private var isTextInputFocused: Bool
    private let plusCodePreferences = FireVaultNativeSettingsStore().preferences.plusCodes

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
        let mapPreferences = FireVaultNativeSettingsStore().gps
        _mapLayer = State(initialValue: FireVaultArrivalMapLayer(
            storageValue: mapPreferences.resolvedArrivalPointMapLayer
        ))
        _mapIs3D = State(initialValue: mapPreferences.resolvedArrivalPointMapIs3D)
        let initialCoordinate = location?.coordinate
            ?? accountCoordinate
            ?? CLLocationCoordinate2D(latitude: 43.615, longitude: -116.202)
        _mapPosition = State(initialValue: .camera(MapCamera(
            centerCoordinate: initialCoordinate,
            distance: 120,
            heading: 0,
            pitch: mapPreferences.resolvedArrivalPointMapIs3D ? 55 : 0
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
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedCoordinates != nil
            && plusCodeEntryIsValid
    }

    private var automaticDirectionsMode: FireVaultDirectionsMode {
        let value = "\(label) \(type)".lowercased()
        return value.contains("parking") || value.contains("park here") ? .driving : .walking
    }

    private var plusCodeEntryIsValid: Bool {
        if locationCoordinate != nil && plusCodePreferences.autoGenerate { return true }
        let trimmed = plusCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || FireVaultPlusCode.normalizedFullCode(trimmed) != nil
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
                    if let locationCoordinate, plusCodePreferences.autoGenerate {
                        LabeledContent("Generated from pin") {
                            Text(FireVaultPlusCode.encode(locationCoordinate, length: plusCodePreferences.locationLength))
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(FieldWorkspacePalette.blue)
                                .textSelection(.enabled)
                        }
                    } else if !plusCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              FireVaultPlusCode.normalizedFullCode(plusCode) == nil {
                        Text("Enter a full Plus Code, such as 85M5JR93+4C. Short codes need nearby city context and are not saved by FireVault.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Picker("Pin Color", selection: $pinColor) {
                        ForEach(FireVaultMapPinColor.allCases) { option in
                            Label(option.rawValue, systemImage: "mappin").tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    LabeledContent("Routing") {
                        Label(automaticDirectionsMode.rawValue, systemImage: automaticDirectionsMode.symbol)
                            .foregroundStyle(FieldWorkspacePalette.blue)
                    }
                    Text("Parking locations route by car. Every other site location routes on foot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

                        Text("Pinch to zoom, drag to pan, or use two fingers to rotate and adjust the 3D view. Use the map-layer button on the map to switch layers.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FieldWorkspacePalette.secondaryText)
                }
            }
            .fireVaultThemedCollection()
            .navigationTitle(location == nil ? "New Location" : "Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    WorkspaceEditorToolbarButton(kind: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    WorkspaceEditorToolbarButton(kind: .save) {
                        guard let coordinates = parsedCoordinates else { return }
                        if save(.init(
                            label: label,
                            subtitle: subtitle,
                            type: type,
                            plusCode: plusCode,
                            latitude: coordinates.0,
                            longitude: coordinates.1,
                            pinColor: pinColor,
                            directionsMode: automaticDirectionsMode
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
                fallbackCoordinate: accountCoordinate ?? locationService.coordinate,
                initialMapLayer: mapLayer.storageValue,
                initialMapIs3D: mapIs3D
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
        if plusCodePreferences.autoGenerate {
            plusCode = FireVaultPlusCode.encode(coordinate, length: plusCodePreferences.locationLength)
        }
        mapPosition = .camera(MapCamera(
            centerCoordinate: coordinate,
            distance: 120,
            heading: 0,
            pitch: mapIs3D ? 55 : 0
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
                Divider()
                Toggle("3D View", isOn: $mapIs3D)
            } label: {
                Label(
                    "\(mapLayer.storageValue.capitalized) \(mapIs3D ? "3D" : "2D")",
                    systemImage: "square.3.layers.3d.top.filled"
                )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .frame(height: 40)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
            }
            .padding(10)
            .accessibilityLabel("Map Layer, \(mapLayer.storageValue.capitalized) \(mapIs3D ? "3D" : "2D")")
        }
        .onChange(of: mapIs3D) { _, _ in
            guard let locationCoordinate else { return }
            mapPosition = .camera(MapCamera(
                centerCoordinate: locationCoordinate,
                distance: 120,
                heading: 0,
                pitch: mapIs3D ? 55 : 0
            ))
        }
    }

    @ViewBuilder
    private var locationPinMapForSelectedLayer: some View {
        locationPinMapContent.modifier(
            FireVaultArrivalMapStyleModifier(layer: mapLayer.storageValue, is3D: mapIs3D)
        )
    }

    private var locationPinMapContent: some View {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
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
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
        }
        .accessibilityHint("Pinch to zoom, drag to pan, or use two fingers to rotate and adjust perspective")
    }
}

private struct WorkspaceMap: View {
    let account: FireVaultWorkspaceAccount
    let mapLayer: String
    let is3D: Bool

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

    private var camera: MapCamera {
        let widestSpan = max(region.span.latitudeDelta, region.span.longitudeDelta)
        return MapCamera(
            centerCoordinate: region.center,
            distance: max(120, min(widestSpan * 111_000 * 1.8, 12_000)),
            heading: 0,
            pitch: is3D ? 55 : 0
        )
    }

    @ViewBuilder
    var body: some View {
        switch (mapLayer, is3D) {
        case ("satellite", true):
            mapContent.mapStyle(.imagery(elevation: .realistic))
        case ("satellite", false):
            mapContent.mapStyle(.imagery(elevation: .flat))
        case ("hybrid", true):
            mapContent.mapStyle(.hybrid(elevation: .realistic))
        case ("hybrid", false):
            mapContent.mapStyle(.hybrid(elevation: .flat))
        case (_, true):
            mapContent.mapStyle(.standard(elevation: .realistic))
        default:
            mapContent.mapStyle(.standard(elevation: .flat))
        }
    }

    private var mapContent: some View {
        Map(initialPosition: .camera(camera)) {
            if let coordinate = account.coordinate {
                Marker(account.name, systemImage: "shield.fill", coordinate: coordinate)
                    .tint(FieldWorkspacePalette.red)
            }
            ForEach(validLocations) { location in
                if let coordinate = location.coordinate {
                    Annotation(location.label, coordinate: coordinate, anchor: .bottom) {
                        VStack(spacing: 3) {
                            Image(systemName: isParkingLocation(location) ? "parkingsign.circle.fill" : location.arrivalMapSymbol)
                                .font(.system(size: isParkingLocation(location) ? 28 : 21, weight: .bold))
                                .foregroundStyle(isParkingLocation(location) ? FieldWorkspacePalette.red : location.resolvedPinColor.color)
                                .frame(width: 32, height: 32)
                                .background(.white, in: Circle())
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(radius: 4, y: 2)
                            Text(location.label.isEmpty ? "Arrival point" : location.label)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .overlay {
                                    Capsule().stroke(.white.opacity(0.55), lineWidth: 0.5)
                                }
                        }
                        .accessibilityLabel(isParkingLocation(location) ? "Parking, \(location.label)" : location.label)
                    }
                }
            }
        }
    }

    private func isParkingLocation(_ location: FireVaultWorkspaceLocation) -> Bool {
        let searchable = "\(location.label) \(location.type)".lowercased()
        return searchable.contains("parking") || searchable.contains("park here")
    }
}

private struct NotesWorkspaceView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @State private var editorRoute: NoteEditorRoute?
    @State private var searchText = ""
    @State private var expandedNoteIDs: Set<String> = []

    private enum NoteEditorRoute: Identifiable {
        case new
        case edit(FireVaultWorkspaceNote)

        var id: String {
            switch self {
            case .new: "new-note"
            case let .edit(note): "edit-\(note.id)"
            }
        }

        var note: FireVaultWorkspaceNote? {
            switch self {
            case .new: nil
            case let .edit(note): note
            }
        }
    }

    private var currentAccount: FireVaultWorkspaceAccount {
        store.accounts.first(where: { $0.id == account.id }) ?? account
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredNotes: [FireVaultWorkspaceNote] {
        guard !searchQuery.isEmpty else { return currentAccount.notes }
        return currentAccount.notes.filter { note in
            FireVaultAccountSearch.matches(searchQuery, values: [note.title, note.text])
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                    TextField("Search note titles and text", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(FieldWorkspacePalette.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear note search")
                    }
                }
                .padding(.vertical, 4)
            }

            if currentAccount.notes.isEmpty {
                ContentUnavailableView(
                    "No Field Notes",
                    systemImage: "note.text.badge.plus",
                    description: Text("Add the first note for this account.")
                )
            } else if filteredNotes.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                ForEach(filteredNotes) { note in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            toggleNote(note)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(FireVaultAccountSearch.highlighted(note.title, query: searchQuery))
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(FieldWorkspacePalette.red)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .allowsTightening(true)
                                    .layoutPriority(1)
                                if note.showsOnArrival {
                                    Label("Arrival", systemImage: "bell.badge.fill")
                                        .font(.caption2.bold())
                                        .foregroundStyle(FieldWorkspacePalette.red)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(FieldWorkspacePalette.red.opacity(0.10), in: Capsule())
                                }
                                Spacer(minLength: 6)
                                Text(noteTimestamp(note))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                Image(systemName: expandedNoteIDs.contains(note.id) ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if expandedNoteIDs.contains(note.id) {
                            Divider()
                            Text(FireVaultAccountSearch.highlighted(note.text, query: searchQuery))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 10)

                            HStack {
                                if !searchQuery.isEmpty {
                                    Label("Search match", systemImage: "highlighter")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                                }
                                Spacer()
                                Button("Edit Note", systemImage: "pencil") {
                                    editorRoute = .edit(note)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 10)
                            .padding(.bottom, 5)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        FieldWorkspacePalette.surface,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(FieldWorkspacePalette.navigationDivider, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
        .onChange(of: searchText) { _, _ in
            if searchQuery.isEmpty {
                expandedNoteIDs.removeAll()
            } else {
                expandedNoteIDs = Set(filteredNotes.map(\.id))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Add Note", systemImage: "square.and.pencil") {
                editorRoute = .new
            }
                .buttonStyle(.glassProminent)
                .padding(12)
                .glassEffect()
        }
        .sheet(item: $editorRoute) { route in
            FireVaultNoteEditorSheet(accountName: currentAccount.name, note: route.note) { draft in
                if let editingNote = route.note {
                    return store.updateNote(
                        accountID: account.id,
                        noteID: editingNote.id,
                        title: draft.title,
                        text: draft.text,
                        showOnArrival: draft.showOnArrival
                    )
                }
                return store.addNote(
                    to: account.id,
                    title: draft.title,
                    text: draft.text,
                    showOnArrival: draft.showOnArrival
                ) != nil
            }
        }
    }

    private func noteTimestamp(_ note: FireVaultWorkspaceNote) -> String {
        FireVaultAccountTimestamp.dateOnly(legacy: note.date, timestamp: note.updatedAt)
    }

    private func toggleNote(_ note: FireVaultWorkspaceNote) {
        if expandedNoteIDs.contains(note.id) {
            expandedNoteIDs.remove(note.id)
        } else {
            expandedNoteIDs.insert(note.id)
        }
    }

}

struct FireVaultNoteDraft: Equatable {
    var title: String
    var text: String
    var showOnArrival: Bool
}

struct FireVaultNoteEditorSheet: View {
    let accountName: String
    let note: FireVaultWorkspaceNote?
    let save: (FireVaultNoteDraft) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var showOnArrival: Bool
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
        _showOnArrival = State(initialValue: note?.showsOnArrival ?? false)
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Text(accountName)
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                }
                Section("Note") {
                    TextField("Title (optional)", text: $title)
                        .focused($isTextInputFocused)
                    TextField("Field note", text: $text, axis: .vertical)
                        .lineLimit(6...14)
                        .focused($isTextInputFocused)
                }
                Section {
                    Toggle(isOn: $showOnArrival) {
                        Label("Show on arrival", systemImage: "bell.badge")
                    }
                    .onChange(of: showOnArrival) { _, isEnabled in
                        guard isEnabled else { return }
                        Task {
                            _ = try? await FireVaultNotificationService.shared.requestAuthorization()
                        }
                    }
                    Text("When Trip Log confirms arrival, this note appears in the arrival alert and on the CarPlay Arrived screen.")
                        .font(.caption)
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                } header: {
                    Text("Arrival")
                }
            }
            .fireVaultThemedCollection()
            .navigationTitle(note == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    WorkspaceEditorToolbarButton(kind: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    WorkspaceEditorToolbarButton(kind: .save) {
                        if save(.init(title: title, text: text, showOnArrival: showOnArrival)) {
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
        .presentationDragIndicator(.visible)
    }
}

private struct FilesScansView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @State private var searchText = ""
    @State private var expandedDocumentIDs: Set<String> = []
    @State private var showsDocumentScanner = false
    @State private var scannerError = ""
    @State private var showsScannerError = false

    private var currentAccount: FireVaultWorkspaceAccount {
        store.accounts.first(where: { $0.id == account.id }) ?? account
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fileDocuments: [FireVaultWorkspaceDocument] {
        currentAccount.documents.filter { $0.kind != "photo" && $0.kind != "video" }
    }

    private var filteredDocuments: [FireVaultWorkspaceDocument] {
        guard !searchQuery.isEmpty else { return fileDocuments }
        return fileDocuments.filter { document in
            FireVaultAccountSearch.matches(
                searchQuery,
                values: [document.title, document.subtitle, document.kind, document.date]
            )
        }
    }

    var body: some View {
        List {
            WorkspaceSearchField(text: $searchText, prompt: "Search files and scans")

            if fileDocuments.isEmpty {
                ContentUnavailableView(
                    "No Files or Scans",
                    systemImage: "doc.viewfinder",
                    description: Text("Scan a document or add a saved field file.")
                )
            } else if filteredDocuments.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                ForEach(filteredDocuments) { document in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            toggleDocument(document)
                        } label: {
                            HStack(spacing: 12) {
                            Image(systemName: documentSymbol(document.kind))
                                .font(.headline)
                                .foregroundStyle(documentTint(document.kind))
                                .frame(width: 38, height: 38)
                                .background(documentTint(document.kind).opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                                Text(FireVaultAccountSearch.highlighted(document.title, query: searchQuery))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            Spacer()
                                Text(FireVaultAccountTimestamp.display(legacy: document.date, timestamp: document.updatedAt))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                                    .fixedSize(horizontal: true, vertical: false)
                                Image(systemName: expandedDocumentIDs.contains(document.id) ? "chevron.up" : "chevron.down")
                                    .font(.caption2.bold())
                                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if expandedDocumentIDs.contains(document.id) {
                            Divider().padding(.leading, 50)
                            Text(FireVaultAccountSearch.highlighted(document.subtitle, query: searchQuery))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(.top, 10)

                            HStack {
                                if !searchQuery.isEmpty {
                                    Label("Search match", systemImage: "highlighter")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                                }
                                Spacer()
                                NavigationLink {
                                    documentDestination(document)
                                } label: {
                                    Label(document.kind == "video" ? "Open Video" : "Open File", systemImage: "arrow.up.right.square")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 10)
                            .padding(.bottom, 5)
                        }
                    }
                    .contextMenu {
                        Button("Delete File", systemImage: "trash", role: .destructive) {
                            store.deleteDocument(accountID: account.id, documentID: document.id)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            store.deleteDocument(accountID: account.id, documentID: document.id)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Files & Scans")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: searchText) { _, _ in
            expandedDocumentIDs = searchQuery.isEmpty
                ? []
                : Set(filteredDocuments.map(\.id))
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("Add File", systemImage: "plus") { store.addDocument(to: account.id, scan: false) }
                    .buttonStyle(.glass)
                Button("Scan Document", systemImage: "doc.viewfinder") { beginDocumentScan() }
                    .buttonStyle(.glassProminent)
            }
            .padding(12)
            .glassEffect()
        }
        .fullScreenCover(isPresented: $showsDocumentScanner) {
            NativeDocumentScannerView(
                onScan: saveScannedPages,
                onCancel: { showsDocumentScanner = false },
                onFailure: showScannerFailure
            )
            .ignoresSafeArea()
        }
        .alert("Scanner Unavailable", isPresented: $showsScannerError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scannerError)
        }
    }

    private func beginDocumentScan() {
        guard VNDocumentCameraViewController.isSupported else {
            showScannerFailure("Document scanning is not available on this device.")
            return
        }
        showsDocumentScanner = true
    }

    private func saveScannedPages(_ pages: [UIImage]) {
        do {
            try store.attachScannedDocument(pages, to: account.id)
            showsDocumentScanner = false
        } catch {
            showsDocumentScanner = false
            showScannerFailure(error.localizedDescription)
        }
    }

    private func showScannerFailure(_ message: String) {
        showsDocumentScanner = false
        scannerError = message
        showsScannerError = true
    }

    private func documentSymbol(_ kind: String) -> String {
        switch kind { case "scan": return "doc.viewfinder"; case "report": return "doc.richtext.fill"; case "photo": return "photo"; case "video": return "video.fill"; default: return "doc" }
    }

    private func documentTint(_ kind: String) -> Color {
        switch kind { case "scan": return FieldWorkspacePalette.blue; case "report": return FieldWorkspacePalette.red; case "photo", "video": return FieldWorkspacePalette.purple; default: return FieldWorkspacePalette.green }
    }

    private func toggleDocument(_ document: FireVaultWorkspaceDocument) {
        if expandedDocumentIDs.contains(document.id) {
            expandedDocumentIDs.remove(document.id)
        } else {
            expandedDocumentIDs.insert(document.id)
        }
    }

    @ViewBuilder
    private func documentDestination(_ document: FireVaultWorkspaceDocument) -> some View {
        if let url = store.mediaURL(accountID: account.id, documentID: document.id),
           url.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame {
            FireVaultStoredPDFDetailView(document: document, url: url)
        } else if document.kind == "video",
                  let url = store.mediaURL(accountID: account.id, documentID: document.id) {
            FireVaultVideoDetailView(
                accountID: account.id,
                document: document,
                url: url,
                store: store
            )
        } else {
            NativeRecordDetailView(
                title: document.title,
                subtitle: document.subtitle,
                symbol: documentSymbol(document.kind)
            )
        }
    }
}

private struct PhotoVideoLibraryView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var searchText = ""
    @State private var isSelectingPhotos = false
    @State private var selectedPhotoIDs: Set<String> = []
    @State private var showsReportBuilder = false

    private var currentAccount: FireVaultWorkspaceAccount {
        store.accounts.first(where: { $0.id == account.id }) ?? account
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mediaDocuments: [FireVaultWorkspaceDocument] {
        let media = currentAccount.documents.filter { $0.kind == "photo" || $0.kind == "video" }
        guard !searchQuery.isEmpty else { return media }
        return media.filter { document in
            FireVaultAccountSearch.matches(
                searchQuery,
                values: [document.title, document.subtitle, document.kind, document.date]
            )
        }
    }

    var body: some View {
        List {
            WorkspaceSearchField(text: $searchText, prompt: "Search photos and videos")

            if currentAccount.documents.allSatisfy({ $0.kind != "photo" && $0.kind != "video" }) {
                ContentUnavailableView(
                    "No Photos or Videos",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Captured account photos and videos will appear here.")
                )
            } else if mediaDocuments.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                ForEach(mediaDocuments) { document in
                    if isSelectingPhotos {
                        Button {
                            guard document.kind == "photo" else { return }
                            togglePhoto(document.id)
                        } label: {
                            HStack(spacing: 12) {
                                mediaRow(document)
                                Image(systemName: selectedPhotoIDs.contains(document.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(
                                        document.kind == "photo"
                                            ? (selectedPhotoIDs.contains(document.id) ? FieldWorkspacePalette.red : FieldWorkspacePalette.secondaryText)
                                            : Color.clear
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(document.kind != "photo")
                        .opacity(document.kind == "photo" ? 1 : 0.48)
                    } else {
                        NavigationLink {
                            mediaDestination(document)
                        } label: {
                            mediaRow(document)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.deleteDocument(accountID: account.id, documentID: document.id)
                            }
                        }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                store.deleteDocument(accountID: account.id, documentID: document.id)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Photos & Videos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mediaDocuments.contains(where: { $0.kind == "photo" }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelectingPhotos ? "Done" : "Select Photos") {
                        withAnimation {
                            isSelectingPhotos.toggle()
                            if !isSelectingPhotos { selectedPhotoIDs.removeAll() }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectingPhotos, !selectedPhotoIDs.isEmpty {
                Button {
                    showsReportBuilder = true
                } label: {
                    Label(
                        "Generate Report from \(selectedPhotoIDs.count) Photo\(selectedPhotoIDs.count == 1 ? "" : "s")",
                        systemImage: "doc.badge.plus"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(FieldWorkspacePalette.red)
                .padding(12)
                .background(.regularMaterial)
            }
        }
        .navigationDestination(isPresented: $showsReportBuilder) {
            FireVaultAccountReportBuilderView(
                account: account,
                store: store,
                settings: settings,
                preselectedPhotoIDs: selectedPhotoIDs
            )
        }
    }

    private func togglePhoto(_ documentID: String) {
        if selectedPhotoIDs.contains(documentID) {
            selectedPhotoIDs.remove(documentID)
        } else {
            selectedPhotoIDs.insert(documentID)
        }
    }

    private func mediaRow(_ document: FireVaultWorkspaceDocument) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.kind == "video" ? "video.fill" : "photo.fill")
                .font(.headline)
                .foregroundStyle(FieldWorkspacePalette.purple)
                .frame(width: 42, height: 42)
                .background(
                    FieldWorkspacePalette.purple.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(document.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(FireVaultAccountTimestamp.display(legacy: document.date, timestamp: document.updatedAt))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(FieldWorkspacePalette.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func mediaDestination(_ document: FireVaultWorkspaceDocument) -> some View {
        if let url = store.mediaURL(accountID: account.id, documentID: document.id) {
            if document.kind == "video" {
                FireVaultVideoDetailView(
                    accountID: account.id,
                    document: document,
                    url: url,
                    store: store
                )
            } else if let image = UIImage(contentsOfFile: url.path) {
                FireVaultPhotoDetailView(
                    accountID: account.id,
                    document: document,
                    url: url,
                    image: image,
                    store: store
                )
            } else {
                NativeRecordDetailView(
                    title: "Photo Unavailable",
                    subtitle: "The saved photo file could not be opened.",
                    symbol: "photo.badge.exclamationmark"
                )
            }
        } else {
            NativeRecordDetailView(
                title: "Media Unavailable",
                subtitle: "The saved media file could not be found.",
                symbol: "exclamationmark.triangle"
            )
        }
    }
}

private struct FireVaultPhotoDetailView: View {
    let accountID: String
    let document: FireVaultWorkspaceDocument
    let url: URL
    let image: UIImage
    @ObservedObject var store: FireVaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .nativeSurfaceCard(cornerRadius: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text(document.title).font(.headline)
                    Text([
                        document.subtitle,
                        FireVaultAccountTimestamp.display(legacy: document.date, timestamp: document.updatedAt)
                    ].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.subheadline)
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    ShareLink(item: url) {
                        Label("Share Photo", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        confirmsDeletion = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Field Photo")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this field photo?", isPresented: $confirmsDeletion) {
            Button("Delete Photo", role: .destructive) {
                if store.deleteDocument(accountID: accountID, documentID: document.id) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct FireVaultVideoDetailView: View {
    let accountID: String
    let document: FireVaultWorkspaceDocument
    let url: URL
    @ObservedObject var store: FireVaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false

    var body: some View {
        VStack(spacing: 18) {
            FireVaultAspectCorrectVideoPlayer(url: url)
                .nativeSurfaceCard(cornerRadius: 18)

            VStack(alignment: .leading, spacing: 5) {
                Text(document.title).font(.headline)
                Text([
                    document.subtitle,
                    FireVaultAccountTimestamp.display(legacy: document.date, timestamp: document.updatedAt)
                ].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.subheadline)
                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                ShareLink(item: url) {
                    Label("Share Video", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)

                Button("Delete", systemImage: "trash", role: .destructive) {
                    confirmsDeletion = true
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(16)
        .background(FieldWorkspacePalette.background)
        .navigationTitle("Field Video")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this field video?", isPresented: $confirmsDeletion) {
            Button("Delete Video", role: .destructive) {
                if store.deleteDocument(accountID: accountID, documentID: document.id) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
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
    @State private var searchText = ""
    @State private var expandedEquipmentIDs: Set<String> = []

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredEquipment: [FireVaultWorkspaceEquipment] {
        guard !searchQuery.isEmpty else { return account.equipment }
        return account.equipment.filter { equipment in
            FireVaultAccountSearch.matches(
                searchQuery,
                values: [equipment.title, equipment.subtitle, equipment.deviceAddress]
            )
        }
    }

    var body: some View {
        List {
            WorkspaceSearchField(text: $searchText, prompt: "Search equipment")

            if account.equipment.isEmpty {
                ContentUnavailableView(
                    "No Equipment Saved",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Add the panel, communicator, power supplies, and other serviceable equipment.")
                )
            } else if filteredEquipment.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                ForEach(filteredEquipment) { equipment in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            toggleEquipment(equipment)
                        } label: {
                            HStack(spacing: 12) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundStyle(FieldWorkspacePalette.green)
                                .frame(width: 38, height: 38)
                                .background(FieldWorkspacePalette.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                                Text(FireVaultAccountSearch.highlighted(equipment.title, query: searchQuery))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                            Spacer()
                            if !equipment.deviceAddress.isEmpty {
                                    Text(FireVaultAccountSearch.highlighted(equipment.deviceAddress, query: searchQuery))
                                    .font(.caption2.monospaced().bold())
                                    .foregroundStyle(FieldWorkspacePalette.green)
                            }
                                Image(systemName: expandedEquipmentIDs.contains(equipment.id) ? "chevron.up" : "chevron.down")
                                    .font(.caption2.bold())
                                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if expandedEquipmentIDs.contains(equipment.id) {
                            Divider().padding(.leading, 50)
                            if !equipment.subtitle.isEmpty {
                                Text(FireVaultAccountSearch.highlighted(equipment.subtitle, query: searchQuery))
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .padding(.top, 10)
                            }
                            HStack {
                                if !searchQuery.isEmpty {
                                    Label("Search match", systemImage: "highlighter")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                                }
                                Spacer()
                                Button("Edit Equipment", systemImage: "pencil") {
                                    editingEquipment = equipment
                                    isShowingEditor = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 10)
                            .padding(.bottom, 5)
                        }
                    }
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
        .onChange(of: searchText) { _, _ in
            expandedEquipmentIDs = searchQuery.isEmpty
                ? []
                : Set(filteredEquipment.map(\.id))
        }
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

    private func toggleEquipment(_ equipment: FireVaultWorkspaceEquipment) {
        if expandedEquipmentIDs.contains(equipment.id) {
            expandedEquipmentIDs.remove(equipment.id)
        } else {
            expandedEquipmentIDs.insert(equipment.id)
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
            .fireVaultThemedCollection()
            .navigationTitle(equipment == nil ? "New Equipment" : "Edit Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    WorkspaceEditorToolbarButton(kind: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    WorkspaceEditorToolbarButton(kind: .save) {
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
        case imagery = "Satellite"
        case hybrid = "Hybrid"

        var id: String { rawValue }

        init(storageValue: String) {
            switch storageValue {
            case "satellite": self = .imagery
            case "hybrid": self = .hybrid
            default: self = .standard
            }
        }

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
    @State private var is3DEnabled = true
    @GestureState private var pinDragTranslation: CGSize = .zero

    init(
        pinLabel: String,
        pinSystemImage: String,
        pinTint: Color,
        initialCoordinate: CLLocationCoordinate2D?,
        fallbackCoordinate: CLLocationCoordinate2D?,
        initialMapLayer: String = "standard",
        initialMapIs3D: Bool = true,
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
        _mapLayer = State(initialValue: MapLayer(storageValue: initialMapLayer))
        _is3DEnabled = State(initialValue: initialMapIs3D)
        _mapPosition = State(initialValue: .camera(MapCamera(
            centerCoordinate: start,
            distance: FireVaultAccountPinMapCamera.distance,
            heading: FireVaultAccountPinMapCamera.heading,
            pitch: initialMapIs3D ? FireVaultAccountPinMapCamera.pitch : 0
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
                                Label(
                                    "\(mapLayer.rawValue) \(is3DEnabled ? "3D" : "2D")",
                                    systemImage: "square.3.layers.3d.top.filled"
                                )
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
        if is3DEnabled {
            updatePerspective()
            return
        }
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

private struct WorkspaceSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FieldWorkspacePalette.secondaryText)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FieldWorkspacePalette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(FieldWorkspacePalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(FieldWorkspacePalette.navigationDivider, lineWidth: 1)
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
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FieldWorkspacePalette.navigationDivider, lineWidth: 1)
            }
            .shadow(color: NativeShellPalette.cardShadow, radius: 8, y: 4)
    }
}

private struct WorkspaceSectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.primary)
            Spacer()
            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(FieldWorkspacePalette.secondaryText)
        }
    }
}

private struct WorkspaceDestinationTile: View {
    let title: String
    let count: Int
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 44)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .allowsTightening(true)
                Text("\(count)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 23)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(FieldWorkspacePalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 1)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 9)
        }
        .shadow(color: NativeShellPalette.cardShadow, radius: 6, y: 3)
    }
}

private struct WorkspaceRecentRow: View {
    let item: FireVaultWorkspaceRecent

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: recentSymbol(item.kind))
                .font(.caption.bold())
                .foregroundStyle(recentColor(item.kind))
                .frame(width: 28, height: 28)
                .background(recentColor(item.kind).opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(FieldWorkspacePalette.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(FireVaultAccountTimestamp.display(legacy: item.date, timestamp: item.updatedAt))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(FieldWorkspacePalette.secondaryText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
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
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 24)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
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

private struct WorkspaceEditorToolbarButton: View {
    enum Kind {
        case cancel
        case save

        var title: String { self == .save ? "Save" : "Cancel" }
        var symbol: String { self == .save ? "checkmark" : "xmark" }
    }

    let kind: Kind
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(kind.title, systemImage: kind.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(kind == .save ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(buttonBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(buttonBorder, lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(kind.title)
    }

    private var buttonBackground: Color {
        kind == .save
            ? FieldWorkspacePalette.red
            : FieldWorkspacePalette.surfaceRaised
    }

    private var buttonBorder: Color {
        kind == .save
            ? FieldWorkspacePalette.red.opacity(0.7)
            : FieldWorkspacePalette.navigationDivider
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
    static let secondaryText = NativeShellPalette.navigationInactive
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
