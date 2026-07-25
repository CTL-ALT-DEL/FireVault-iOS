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
        group("field", "Field Tools", "Photos, maps, GPS, and Plus Codes", "wrench.and.screwdriver", "green", [
            item("overlay", "Photo Overlay", "Configure native field-photo labels", "camera.filters"),
            item("gps", "GPS & Maps", "Apple Maps, accuracy, and Nearby radius", "location"),
            item("plusCodes", "Plus Codes", "Offline location-code preferences", "plus.square.dashed")
        ]),
        group("reports", "Reports", "Reports and customer email", "doc.text", "purple", [
            item("reports", "Report Settings", "Native report defaults", "doc.text"),
            item("email", "Email Settings", "Recipients, subject, and signature", "envelope")
        ]),
        group("data", "Data & Security", "Native storage, import, backup, and protection", "externaldrive", "amber", [
            item("cloudFiles", "File Storage", "Photo and document destinations", "folder"),
            item("microsoftStorage", "Microsoft Storage", "OneDrive and SharePoint profile", "cloud"),
            item("sync", "Shared Vault", "Team and conflict preferences", "arrow.triangle.2.circlepath"),
            item("customerImport", "Customer CSV Import", "Import accounts using the iOS document picker", "square.and.arrow.down"),
            item("categories", "Account Categories", "Manage native account classifications", "tag"),
            item("backup", "Backup & Restore", "Native vault migration status", "externaldrive.badge.timemachine"),
            item("webdav", "WebDAV Backup", "Remote-server preferences", "server.rack"),
            item("privacy", "Privacy Lock", "Native privacy preferences", "lock"),
            item("security", "Security", "iOS sandbox and protection status", "shield.checkered")
        ]),
        group("help", "Help & About", "Native documentation and application information", "questionmark.circle", "red", [
            item("manual", "Help & User Manual", "Native quick-start instructions", "book.closed"),
            item("updates", "App Updates", "Installed native version", "arrow.down.circle"),
            item("demo", "Demo Mode", "Enter, exit, or reset the fictional vault", "theatermasks"),
            item("about", "About FireVault", "Version and application information", "info.circle")
        ])
    ]

    private static func item(_ id: String, _ title: String, _ subtitle: String, _ symbol: String) -> FireVaultNativeSettingItem {
        .init(id: id, title: title, subtitle: subtitle, symbol: symbol, status: "Native")
    }

    private static func group(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        _ tint: String,
        _ items: [FireVaultNativeSettingItem]
    ) -> FireVaultNativeSettingsGroup {
        .init(id: id, title: title, subtitle: subtitle, symbol: symbol, tint: tint, status: "Native", items: items)
    }
}

struct NativeTechnicianSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Technician name", text: $draft.technician.name).focused($focused)
                TextField("Company", text: $draft.technician.company).focused($focused)
                TextField("License / employee ID", text: $draft.technician.license).focused($focused)
            }
            Section("Contact") {
                TextField("Phone", text: $draft.technician.phone).keyboardType(.phonePad).focused($focused)
                TextField("Email", text: $draft.technician.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).focused($focused)
            }
        }
        .nativeSettingsForm(title: "Technician Profile", focused: $focused) { settings.save(draft) }
    }
}

struct NativeOverlaySettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section {
                FireVaultOverlayPreview(
                    preferences: draft.overlay,
                    technicianName: draft.technician.name.isEmpty ? "Demo Technician" : draft.technician.name,
                    siteName: "North Riverside Fire and Life Safety Operations Center",
                    address: "100 FireVault Way, Boise, ID 83702",
                    accountID: "FV-1001",
                    category: "Commercial"
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .accessibilityIdentifier("overlay-sample-preview")
            } header: {
                Text("Preview")
            } footer: {
                Text("Touch and drag the logo or dark glass overlay directly. Releasing your finger locks that item in its new position and releases control for the other item.")
            }

            Section("Appearance") {
                LabeledContent("Style", value: "Dark Frosted Glass")
                overlaySizeControl
                logoSizeControl

                Picker("Text size", selection: $draft.overlay.fontSize) {
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Glass darkness: \(draft.overlay.opacity)%")
                    Slider(
                        value: Binding(
                            get: { Double(draft.overlay.opacity) },
                            set: { draft.overlay.opacity = Int($0.rounded()) }
                        ),
                        in: 35...100,
                        step: 5
                    )
                }
            }

            Section {
                Toggle("Show FireVault brand", isOn: $draft.overlay.showLogo)
                Toggle("Show tagline", isOn: $draft.overlay.showTagline)
                TextField("Tagline", text: $draft.overlay.tagline).focused($focused)
                Picker("Accent", selection: $draft.overlay.accentColor) {
                    Text("Red").tag("red")
                    Text("Blue").tag("blue")
                    Text("Amber").tag("amber")
                    Text("White").tag("white")
                }
            } header: {
                Text("Branding")
            } footer: {
                Text("The FireVault brand includes the app icon plus FIRE in red and VAULT in white.")
            }

            Section {
                ForEach(orderedFields) { field in
                    fieldControl(field)
                }
            } header: {
                Text("Fields and Order")
            } footer: {
                Text("Site, address, and account ID are required. The overlay automatically grows horizontally for longer visible data.")
            }

            Section {
                Button("Reset Overlay and Logo Placement", systemImage: "arrow.counterclockwise") {
                    draft.overlay.scale = 0.78
                    draft.overlay.positionX = 0
                    draft.overlay.positionY = 0.45
                    draft.overlay.logoScale = 0.8
                    draft.overlay.logoPositionX = -0.62
                    draft.overlay.logoPositionY = -0.7
                    FireVaultOverlayEditorBridge.stage(draft.overlay)
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
        .contentMargins(.bottom, 100, for: .scrollContent)
        .nativeSettingsForm(title: "Photo Overlay", focused: $focused) {
            draft.overlay.backgroundStyle = "frosted"
            settings.save(draft)
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
            Slider(value: $draft.overlay.scale, in: 0.45...1.35, step: 0.05)
                .onChange(of: draft.overlay.scale) { _, _ in
                    FireVaultOverlayEditorBridge.stage(draft.overlay)
                }
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
            Slider(value: $draft.overlay.logoScale, in: 0.45...1.8, step: 0.05)
                .disabled(!draft.overlay.showLogo)
                .onChange(of: draft.overlay.logoScale) { _, _ in
                    FireVaultOverlayEditorBridge.stage(draft.overlay)
                }
        }
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
                if isVisible {
                    draft.overlay.hiddenFields.removeAll { $0 == field.rawValue }
                } else if !draft.overlay.hiddenFields.contains(field.rawValue) {
                    draft.overlay.hiddenFields.append(field.rawValue)
                }
            }
        )
    }

    private func moveField(at index: Int, by offset: Int) {
        let destination = index + offset
        guard draft.overlay.fieldOrder.indices.contains(index),
              draft.overlay.fieldOrder.indices.contains(destination) else { return }
        withAnimation(.snappy(duration: 0.22)) {
            draft.overlay.fieldOrder.swapAt(index, destination)
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
            .scrollDismissesKeyboard(.interactively)
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
