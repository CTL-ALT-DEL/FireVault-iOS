//
//  NativeSettingsScreens.swift
//  FireVault
//
//  Core settings screens and freeform Photo Overlay editor.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import UIKit

enum NativeSettingsCatalog {
    static let groups: [FireVaultNativeSettingsGroup] = [
        group("field", "Field Tools", "Photos, maps, GPS, and alerts", "wrench.and.screwdriver", "green", [
            item("overlay", "Photo Overlay", "Configure photo and video labels", "camera.filters"),
            item("gps", "GPS & Maps", "Apple Maps, accuracy, and Nearby radius", "location"),
            item("notifications", "Notifications", "Trip Log, service, and system alerts", "bell.badge")
        ]),
        group("reports", "Reports", "Reports and customer email", "doc.text", "blue", [
            item("reports", "Report Settings", "Content, delivery, and email defaults", "doc.text")
        ]),
        group("data", "Storage & Data", "Storage, account import, categories, and backup", "externaldrive", "amber", [
            item("cloudFiles", "File Storage", "Local photos, scans, and files", "folder"),
            item("customerImport", "Import Accounts", "Review and import account data from CSV", "square.and.arrow.down"),
            item("categories", "Account Categories", "Manage account classifications", "tag"),
            item("backup", "Backup & Restore", "Export or safely merge a vault backup", "externaldrive.badge.timemachine")
        ]),
        group("help", "Privacy & Support", "Privacy, security, help, and application information", "shield.checkered", "red", [
            item("security", "Security", "Face ID, app privacy, and data protection", "shield.checkered"),
            item("appearance", "Appearance", "Theme and display preferences", "circle.lefthalf.filled"),
            item("manual", "Help Center", "Task guides and troubleshooting", "questionmark.bubble"),
            item("demo", "Demo Mode", "Enter, exit, or reset the fictional vault", "theatermasks"),
            item("about", "About FireVault Pro", "Version and application information", "info.circle")
        ])
    ]

    private static func item(_ id: String, _ title: String, _ subtitle: String, _ symbol: String) -> FireVaultNativeSettingItem {
        .init(id: id, title: title, subtitle: subtitle, symbol: symbol, status: "Ready")
    }

    private static func group(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ tint: String,
        _ items: [FireVaultNativeSettingItem]
    ) -> FireVaultNativeSettingsGroup {
        .init(id: id, title: title, subtitle: subtitle, symbol: symbol, tint: tint, status: "Ready", items: items)
    }
}

struct NativeAppearanceSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore

    var body: some View {
        Form {
            Section {
                ForEach(FireVaultAppearanceMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            settings.saveAppearance(mode)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: symbol(for: mode))
                                .font(.title3)
                                .foregroundStyle(accent(for: mode))
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .foregroundStyle(.primary)
                                Text(detail(for: mode))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.appearance == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(NativeShellPalette.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Light uses FireVault Pro's Warm Ivory palette. System Default follows the iPhone appearance automatically.")
            }
        }
        .fireVaultThemedCollection()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func symbol(for mode: FireVaultAppearanceMode) -> String {
        switch mode {
        case .dark: "moon.stars.fill"
        case .light: "sun.max.fill"
        case .system: "iphone"
        }
    }

    private func accent(for mode: FireVaultAppearanceMode) -> Color {
        switch mode {
        case .dark: NativeShellPalette.blue
        case .light: NativeShellPalette.amber
        case .system: NativeShellPalette.blue
        }
    }

    private func detail(for mode: FireVaultAppearanceMode) -> String {
        switch mode {
        case .dark: "Original high-contrast FireVault Pro theme"
        case .light: "Warm Ivory canvas and soft cream surfaces"
        case .system: "Match the current iPhone setting"
        }
    }
}

struct NativeTechnicianSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var store: FireVaultStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore, store: FireVaultStore) {
        self.settings = settings
        self.store = store
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section {
                TextField("Technician name", text: $draft.technician.name).focused($focused)
                TextField("Company", text: $draft.technician.company).focused($focused)
                TextField("License / employee ID", text: $draft.technician.license).focused($focused)
            } header: {
                Text("Technician Details")
            } footer: {
                Text("These details identify the technician on photo overlays and service reports.")
            }
            Section {
                TextField("Phone", text: $draft.technician.phone).keyboardType(.phonePad).focused($focused)
                TextField("Email", text: $draft.technician.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).focused($focused)
            } header: {
                Text("Contact")
            } footer: {
                Text("Technician contact details stay separate from the signed-in FireVault account below.")
            }

            FireVaultAccountProfileSections(store: store)
        }
        .nativeSettingsForm(title: "Technician Profile", focused: $focused) { saveTechnician() }
    }

    private func saveTechnician() {
        var updated = settings.preferences
        updated.technician = draft.technician
        settings.save(updated)
    }
}

struct NativeOverlaySettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @State private var isPlacementEditorPresented = false
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section {
                ZStack {
                    FireVaultOverlayPreview(
                        preferences: draft.overlay,
                        technicianName: draft.technician.name.isEmpty ? "Demo Technician" : draft.technician.name,
                        siteName: "North Riverside Fire and Life Safety Operations Center",
                        address: "100 FireVault Way, Boise, ID 83702",
                        accountID: "FV-1001",
                        category: "Commercial"
                    )
                    .allowsHitTesting(false)

                    VStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.title2.bold())
                        Text("Tap to position")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.66), in: Capsule())
                }
                .contentShape(Rectangle())
                .onTapGesture { isPlacementEditorPresented = true }
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .accessibilityIdentifier("overlay-sample-preview")
                .accessibilityLabel("Open full-screen Photo Overlay placement editor")
            } header: {
                Text("Preview")
            } footer: {
                Text("Tap the photo to position and resize the overlay and FireVault Pro logo in a full-screen landscape editor.")
            }

            Section("Appearance") {
                overlaySizeControl
                logoSizeControl

                VStack(alignment: .leading, spacing: 6) {
                    Text("Glass darkness: \(draft.overlay.opacity)%")
                    Slider(
                        value: Binding(
                            get: { Double(draft.overlay.opacity) },
                            set: { newValue in
                                updateOverlayPreservingPlacement {
                                    $0.opacity = Int(newValue.rounded())
                                }
                            }
                        ),
                        in: 35...100,
                        step: 5
                    )
                }
            }

            Section {
                Toggle(
                    "Show FireVault Pro logo",
                    isOn: overlayBinding(\.showLogo)
                )
                Toggle(
                    "Show tagline",
                    isOn: overlayBinding(\.showTagline)
                )
                Toggle(
                    "Show location QR code",
                    isOn: overlayBinding(\.showLocationQRCode)
                )
                if draft.overlay.showTagline {
                    TextField(
                        "Tagline",
                        text: overlayBinding(\.tagline)
                    )
                    .focused($focused)
                }
                Picker("Accent", selection: overlayBinding(\.accentColor)) {
                    Text("Red").tag("red")
                    Text("Blue").tag("blue")
                    Text("Amber").tag("amber")
                    Text("White").tag("white")
                }
                .accessibilityIdentifier("overlay-accent-picker")
            } header: {
                Text("Branding")
            } footer: {
                Text("The photo logo uses FIRE in red, VAULT in white, and the PRO stamp. The flame icon remains reserved for app launch and the Home Screen.")
            }

            Section {
                DisclosureGroup("Choose Fields and Order") {
                    ForEach(orderedFields) { field in
                        fieldControl(field)
                    }
                }
            } header: {
                Text("Fields and Order")
            } footer: {
                Text("Site, address, and account ID are required. The overlay automatically grows horizontally for longer visible data.")
            }

            Section {
                Button("Reset Overlay and Logo Placement", systemImage: "arrow.counterclockwise") {
                    draft.overlay.scale = 0.50
                    draft.overlay.positionX = -0.78
                    draft.overlay.positionY = 0.78
                    draft.overlay.logoScale = 0.70
                    draft.overlay.logoPositionX = 0.78
                    draft.overlay.logoPositionY = -0.78
                    FireVaultOverlayEditorBridge.stage(draft.overlay)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Restore Defaults")
            } footer: {
                Text("Restores the default overlay and logo positions without changing your selected fields or branding text.")
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .nativeSettingsForm(title: "Photo Overlay", focused: $focused) {
            preservePlacedElements()
            draft.overlay.backgroundStyle = "frosted"
            settings.save(draft)
        }
        .fullScreenCover(isPresented: $isPlacementEditorPresented) {
            FireVaultOverlayPlacementEditor(
                preferences: draft.overlay,
                technicianName: draft.technician.name.isEmpty ? "Demo Technician" : draft.technician.name,
                siteName: "North Riverside Fire and Life Safety Operations Center",
                address: "100 FireVault Way, Boise, ID 83702",
                accountID: "FV-1001",
                category: "Commercial",
                onSave: { placedOverlay in
                    draft.overlay = placedOverlay.normalized
                    FireVaultOverlayEditorBridge.stage(draft.overlay)
                    settings.save(draft)
                }
            )
        }
    }

    private var overlaySizeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Overlay size")
                Spacer()
                Text("\(Int((draft.overlay.scale * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { draft.overlay.scale },
                    set: { newValue in
                        updateOverlayPreservingPlacement { $0.scale = newValue }
                    }
                ),
                in: 0.45...1.35,
                step: 0.05
            )
        }
    }

    private var logoSizeControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Logo size")
                Spacer()
                Text("\(Int((draft.overlay.logoScale * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { draft.overlay.logoScale },
                    set: { newValue in
                        updateOverlayPreservingPlacement { $0.logoScale = newValue }
                    }
                ),
                in: 0.45...1.8,
                step: 0.05
            )
            .disabled(!draft.overlay.showLogo)
        }
    }

    private func updateOverlayPreservingPlacement(
        _ change: (inout FireVaultOverlayPreferences) -> Void
    ) {
        var latest = FireVaultOverlayEditorBridge.merge(into: draft.overlay)
        change(&latest)
        draft.overlay = latest.normalized
        FireVaultOverlayEditorBridge.stage(draft.overlay)
    }

    private func overlayBinding<Value>(
        _ keyPath: WritableKeyPath<FireVaultOverlayPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { draft.overlay[keyPath: keyPath] },
            set: { newValue in
                updateOverlayPreservingPlacement {
                    $0[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func preservePlacedElements() {
        draft.overlay = FireVaultOverlayEditorBridge.merge(into: draft.overlay)
    }

    private var orderedFields: [FireVaultOverlayField] {
        draft.overlay.fieldOrder.compactMap(FireVaultOverlayField.init(rawValue:))
    }

    @ViewBuilder
    private func fieldControl(_ field: FireVaultOverlayField) -> some View {
        let index = draft.overlay.fieldOrder.firstIndex(of: field.rawValue) ?? 0
        let lastIndex = max(0, draft.overlay.fieldOrder.count - 1)

        HStack(spacing: 10) {
            Image(systemName: field.symbol)
                .foregroundStyle(NativeShellPalette.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.title)
                Text(field.isRequired ? "Required" : "Optional")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if field.isRequired {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("", isOn: fieldVisibilityBinding(field)).labelsHidden()
            }

            HStack(spacing: 2) {
                Button { moveField(at: index, by: -1) } label: {
                    Image(systemName: "chevron.up").frame(width: 28, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)

                Button { moveField(at: index, by: 1) } label: {
                    Image(systemName: "chevron.down").frame(width: 28, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(index == lastIndex)
            }
        }
        .accessibilityIdentifier("overlay-field-\(field.rawValue)")
    }

    private func fieldVisibilityBinding(_ field: FireVaultOverlayField) -> Binding<Bool> {
        Binding(
            get: { !draft.overlay.hiddenFields.contains(field.rawValue) },
            set: { isVisible in
                updateOverlayPreservingPlacement { overlay in
                    if isVisible {
                        overlay.hiddenFields.removeAll { $0 == field.rawValue }
                    } else if !overlay.hiddenFields.contains(field.rawValue) {
                        overlay.hiddenFields.append(field.rawValue)
                    }
                }
            }
        )
    }

    private func moveField(at index: Int, by offset: Int) {
        let destination = index + offset
        guard draft.overlay.fieldOrder.indices.contains(index),
              draft.overlay.fieldOrder.indices.contains(destination) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            updateOverlayPreservingPlacement {
                $0.fieldOrder.swapAt(index, destination)
            }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

extension View {
    func nativeSettingsForm(
        title: String,
        focused: FocusState<Bool>.Binding? = nil,
        save: @escaping () -> Void
    ) -> some View {
        modifier(NativeSettingsFormModifier(title: title, focused: focused, save: save))
    }
}

struct NativeSettingsFormModifier: ViewModifier {
    let title: String
    let focused: FocusState<Bool>.Binding?
    let save: () -> Void

    func body(content: Content) -> some View {
        content
            .fireVaultThemedCollection()
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear(perform: save)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Save", action: save) }
                if let focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused.wrappedValue = false }
                    }
                }
            }
    }
}
