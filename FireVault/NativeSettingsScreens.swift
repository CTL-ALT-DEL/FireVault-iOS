//
//  NativeSettingsScreens.swift
//  FireVault
//
//  Pure SwiftUI Settings destinations for Build 1.05.02.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

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

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FIREVAULT FIELD NOTES").font(.caption.bold()).foregroundStyle(.red)
                    Text("Demo Account • Demo Technician").font(.headline)
                    Text("Native photo overlay preview").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            }
            Section("Layout") {
                Picker("Position", selection: $draft.overlay.alignment) {
                    Text("Top").tag("top"); Text("Center").tag("middle"); Text("Bottom").tag("bottom")
                }
                Picker("Style", selection: $draft.overlay.backgroundStyle) {
                    Text("Full bar").tag("bar"); Text("Card").tag("card"); Text("Minimal").tag("minimal")
                }
                Picker("Text size", selection: $draft.overlay.fontSize) {
                    Text("Small").tag("small"); Text("Medium").tag("medium"); Text("Large").tag("large")
                }
                VStack(alignment: .leading) {
                    Text("Opacity: \(draft.overlay.opacity)%")
                    Slider(value: Binding(
                        get: { Double(draft.overlay.opacity) },
                        set: { draft.overlay.opacity = Int($0.rounded()) }
                    ), in: 35...100, step: 5)
                }
            }
            Section("Branding") {
                Toggle("Show FireVault logo", isOn: $draft.overlay.showLogo)
                Toggle("Show category tagline", isOn: $draft.overlay.showTagline)
                Picker("Accent", selection: $draft.overlay.accentColor) {
                    Text("Red").tag("red"); Text("Blue").tag("blue"); Text("Amber").tag("amber"); Text("White").tag("white")
                }
            }
        }
        .nativeSettingsForm(title: "Photo Overlay") { settings.save(draft) }
    }
}

struct NativePlusCodeSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section("Availability") {
                Toggle("Show Plus Code tools", isOn: $draft.plusCodes.enabled)
                Toggle("Generate automatically from GPS", isOn: $draft.plusCodes.autoGenerate)
                Toggle("Allow account search", isOn: $draft.plusCodes.searchable)
                Toggle("Include in reports", isOn: $draft.plusCodes.includeInReports)
            }
            Section("Precision") {
                Picker("Account precision", selection: $draft.plusCodes.accountLength) {
                    Text("10 digits").tag(10); Text("11 digits").tag(11)
                }
                Picker("Location precision", selection: $draft.plusCodes.locationLength) {
                    Text("10 digits").tag(10); Text("11 digits").tag(11)
                }
                Picker("Reverify", selection: $draft.plusCodes.verifyAfterDays) {
                    Text("90 days").tag(90); Text("180 days").tag(180); Text("1 year").tag(365)
                }
            }
        }
        .nativeSettingsForm(title: "Plus Codes") { settings.save(draft) }
    }
}

struct NativeReportSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section("Defaults") {
                TextField("Report title", text: $draft.reports.title).focused($focused)
                Picker("Format", selection: $draft.reports.format) {
                    Text("Detailed").tag("detailed"); Text("Compact").tag("compact")
                }
            }
            Section("Included Content") {
                Toggle("Technician profile", isOn: $draft.reports.includeTechnician)
                Toggle("Tasks", isOn: $draft.reports.includeTasks)
                Toggle("Deficiencies", isOn: $draft.reports.includeDeficiencies)
            }
        }
        .nativeSettingsForm(title: "Report Settings", focused: $focused) { settings.save(draft) }
    }
}

struct NativeEmailSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section("Recipients") {
                TextField("Default recipient", text: $draft.email.defaultTo).keyboardType(.emailAddress).textInputAutocapitalization(.never).focused($focused)
                TextField("CC", text: $draft.email.cc).keyboardType(.emailAddress).textInputAutocapitalization(.never).focused($focused)
            }
            Section("Template") {
                TextField("Subject", text: $draft.email.defaultSubject).focused($focused)
                TextField("Signature", text: $draft.email.signature, axis: .vertical).lineLimit(3...8).focused($focused)
            }
        }
        .nativeSettingsForm(title: "Email Settings", focused: $focused) { settings.save(draft) }
    }
}

struct NativeStorageSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section("Photos") {
                Picker("Destination", selection: $draft.storage.photoProvider) {
                    Text("On this iPhone").tag("local"); Text("Microsoft profile").tag("microsoft")
                }
                TextField("Folder", text: $draft.storage.photoFolder).focused($focused)
            }
            Section("Documents") {
                Picker("Destination", selection: $draft.storage.documentProvider) {
                    Text("On this iPhone").tag("local"); Text("Microsoft profile").tag("microsoft")
                }
                TextField("Folder", text: $draft.storage.documentFolder).focused($focused)
            }
        }
        .nativeSettingsForm(title: "File Storage", focused: $focused) { settings.save(draft) }
    }
}

struct NativeMicrosoftStorageSettingsView: View {
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
                TextField("Profile label", text: $draft.storage.microsoftProfileLabel).focused($focused)
                TextField("Microsoft email", text: $draft.storage.microsoftEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).focused($focused)
                TextField("SharePoint site URL", text: $draft.storage.sharePointSiteURL).keyboardType(.URL).textInputAutocapitalization(.never).focused($focused)
                TextField("Library", text: $draft.storage.libraryName).focused($focused)
            } header: {
                Text("Connection Profile")
            } footer: {
                Text("This stores the native profile. Microsoft sign-in and file transfer require the future native OAuth service.")
            }
        }
        .nativeSettingsForm(title: "Microsoft Storage", focused: $focused) { settings.save(draft) }
    }
}

struct NativeSyncSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section("Shared Vault") {
                TextField("Organization or team", text: $draft.sync.organization).focused($focused)
                TextField("Workspace name", text: $draft.sync.workspace).focused($focused)
                Picker("Conflict handling", selection: $draft.sync.conflictPolicy) {
                    Text("Require review").tag("review"); Text("Newest wins").tag("newest"); Text("Imported copy wins").tag("server")
                }
            }
        }
        .nativeSettingsForm(title: "Shared Vault", focused: $focused) { settings.save(draft) }
    }
}

struct NativeCategoriesSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @State private var newCategory = ""
    @FocusState private var focused: Bool

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        List {
            Section("Categories") {
                ForEach(draft.categories, id: \.self) { Text($0) }
                    .onDelete { draft.categories.remove(atOffsets: $0) }
            }
            Section("Add Category") {
                TextField("Category name", text: $newCategory).focused($focused)
                Button("Add", systemImage: "plus") {
                    let value = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, !draft.categories.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
                    draft.categories.append(value); newCategory = ""
                }
            }
        }
        .nativeSettingsForm(title: "Account Categories", focused: $focused) { settings.save(draft) }
    }
}

struct NativeWebDAVSettingsView: View {
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
                Toggle("Enable WebDAV profile", isOn: $draft.webDAV.enabled)
                TextField("Server URL", text: $draft.webDAV.serverURL).keyboardType(.URL).textInputAutocapitalization(.never).focused($focused)
                TextField("Username", text: $draft.webDAV.username).textInputAutocapitalization(.never).focused($focused)
                TextField("Remote folder", text: $draft.webDAV.folder).focused($focused)
            } header: {
                Text("WebDAV Server")
            } footer: {
                Text("Credentials are not stored yet. Native WebDAV authentication will use Keychain in the backup milestone.")
            }
        }
        .nativeSettingsForm(title: "WebDAV Backup", focused: $focused) { settings.save(draft) }
    }
}

struct NativePrivacySettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable native privacy lock", isOn: $draft.privacy.enabled)
                Picker("Auto-lock", selection: $draft.privacy.autoLockMinutes) {
                    Text("Immediately").tag(0); Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15)
                }
                Toggle("Lock when app enters background", isOn: $draft.privacy.lockOnBackground)
                Toggle("Hide content in app switcher", isOn: $draft.privacy.hideInAppSwitcher)
            } header: {
                Text("Privacy")
            } footer: {
                Text("The preference is native. Face ID enforcement will be connected after the native data repository is finalized.")
            }
        }
        .nativeSettingsForm(title: "Privacy Lock") { settings.save(draft) }
    }
}

struct NativeCSVImportView: View {
    @ObservedObject var store: FireVaultStore
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var result: FireVaultCSVImportResult?
    @State private var errorMessage = ""
    @State private var showFeedback = false
    @State private var feedbackTitle = ""
    @State private var feedbackMessage = ""

    var body: some View {
        List {
            Section("Native CSV Import") {
                Button("Choose CSV File", systemImage: "doc.badge.plus") {
                    result = nil
                    errorMessage = ""
                    showImporter = true
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(isImporting)
                if isImporting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Reading and importing CSV…")
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Recognized columns include Account Name, Address, City, State, ZIP, Account ID, Category, Phone, Latitude, and Longitude.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let result {
                Section("Import Result") {
                    LabeledContent("Rows", value: "\(result.totalRows)")
                    LabeledContent("Added", value: "\(result.added)")
                    LabeledContent("Skipped", value: "\(result.skipped)")
                    ForEach(result.messages, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            if !errorMessage.isEmpty {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
        }
        .navigationTitle("Customer CSV Import")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .data],
            allowsMultipleSelection: false
        ) { selection in
            switch selection {
            case .success(let urls):
                guard let url = urls.first else {
                    presentError("No file was returned by the document picker.")
                    return
                }
                isImporting = true
                Task { @MainActor in
                    await Task.yield()
                    importCSV(from: url)
                }
            case .failure(let error):
                presentError(error.localizedDescription)
            }
        }
        .alert(feedbackTitle, isPresented: $showFeedback) {
            Button("OK") {}
        } message: {
            Text(feedbackMessage)
        }
    }

    private func importCSV(from url: URL) {
        do {
            let data = try readCoordinatedData(from: url)
            let imported = try store.importAccountsCSV(data)
            result = imported
            errorMessage = ""
            feedbackTitle = imported.added > 0 ? "CSV Import Complete" : "No Accounts Imported"
            var details = [
                "File: \(url.lastPathComponent)",
                "Size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))",
                "Rows found: \(imported.totalRows)",
                "Added: \(imported.added) • Skipped: \(imported.skipped)"
            ]
            details.append(contentsOf: imported.messages.prefix(5))
            feedbackMessage = details.joined(separator: "\n")
            showFeedback = true
        } catch {
            presentError(error.localizedDescription)
        }
        isImporting = false
    }

    private func readCoordinatedData(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        var coordinationError: NSError?
        var readResult: Result<Data, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinationError
        ) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
            }
        }

        if let coordinationError { throw coordinationError }
        guard let readResult else {
            throw CocoaError(.fileReadUnknown)
        }
        return try readResult.get()
    }

    private func presentError(_ message: String) {
        isImporting = false
        errorMessage = message
        feedbackTitle = "CSV Import Failed"
        feedbackMessage = message
        showFeedback = true
    }
}

struct NativeDemoSettingsView: View {
    @ObservedObject var store: FireVaultStore
    @State private var confirmReset = false
    @State private var confirmExit = false
    @State private var confirmEnter = false

    var body: some View {
        List {
            Section {
                Label(
                    store.demoMode ? "Native Demo Mode is active" : "Demo Mode is off",
                    systemImage: store.demoMode ? "theatermasks.fill" : "checkmark.shield.fill"
                )
                .foregroundStyle(store.demoMode ? .orange : .green)
                LabeledContent("Accounts", value: "\(store.accounts.count)")
                if store.demoMode {
                    Button("Exit Demo Mode", systemImage: "rectangle.portrait.and.arrow.forward") {
                        confirmExit = true
                    }
                    .foregroundStyle(.blue)
                    Button("Reset Native Demo Data", role: .destructive) {
                        confirmReset = true
                    }
                } else {
                    Button("Enter Demo Mode", systemImage: "theatermasks") {
                        confirmEnter = true
                    }
                }
            } footer: {
                Text(
                    store.demoMode
                        ? "Exit switches to your separate production vault. Demo accounts remain available if you return."
                        : "Production and demo accounts are stored separately. Entering Demo Mode will not change production accounts."
                )
            }
        }
        .navigationTitle("Demo Mode")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Exit Demo Mode?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Exit Demo Mode") { store.exitDemoMode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("FireVault will open the production vault. It starts empty until you add or import accounts.")
        }
        .confirmationDialog("Enter Demo Mode?", isPresented: $confirmEnter, titleVisibility: .visible) {
            Button("Enter Demo Mode") { store.enterDemoMode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("FireVault will switch to the separate fictional demo vault.")
        }
        .confirmationDialog("Reset all native demo changes?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset Demo Data", role: .destructive) { store.resetDemo() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct NativeManualView: View {
    var body: some View {
        List {
            Section("Quick Start") {
                Label("Use Nearby to locate mapped accounts.", systemImage: "location")
                Label("Search Accounts by name, address, or ID.", systemImage: "magnifyingglass")
                Label("Open an account for notes, files, equipment, and locations.", systemImage: "building.2")
                Label("Use Settings for native preferences and CSV import.", systemImage: "gearshape")
            }
            Section("Native Transition") {
                Text("FireVault 1.05 removes the hosted web runtime. Features are rebuilt with SwiftUI, MapKit, PhotosUI, and native iOS storage.")
            }
        }
        .navigationTitle("Help & User Manual")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NativeMigrationStatusView: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func nativeSettingsForm(
        title: String,
        focused: FocusState<Bool>.Binding? = nil,
        save: @escaping () -> Void
    ) -> some View {
        modifier(NativeSettingsFormModifier(title: title, focused: focused, save: save))
    }
}

private struct NativeSettingsFormModifier: ViewModifier {
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
