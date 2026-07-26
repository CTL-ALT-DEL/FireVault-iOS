//
//  NativeSettingsOtherScreens.swift
//  FireVault
//
//  Settings destinations separated from the Photo Overlay editor.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct NativePlusCodeSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
    var body: some View {
        Form {
            Section("Availability") {
                Toggle("Show Plus Code tools", isOn: $draft.plusCodes.enabled)
                Toggle("Generate automatically from GPS", isOn: $draft.plusCodes.autoGenerate)
                Toggle("Allow account search", isOn: $draft.plusCodes.searchable)
                Toggle("Include in reports", isOn: $draft.plusCodes.includeInReports)
            }
            Section("Precision") {
                Picker("Account precision", selection: $draft.plusCodes.accountLength) { Text("10 digits").tag(10); Text("11 digits").tag(11) }
                Picker("Location precision", selection: $draft.plusCodes.locationLength) { Text("10 digits").tag(10); Text("11 digits").tag(11) }
                Picker("Reverify", selection: $draft.plusCodes.verifyAfterDays) { Text("90 days").tag(90); Text("180 days").tag(180); Text("1 year").tag(365) }
            }
        }
        .nativeSettingsForm(title: "Plus Codes") { settings.save(draft) }
    }
}

struct NativeReportSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @State private var deliveryStatus = ""
    @FocusState private var focused: Bool
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
    var body: some View {
        Form {
            Section("Trip Log Reports") {
                Toggle("Include GPS coordinates", isOn: $draft.gps.includeCoordinatesInReports)
                Toggle("Include technician profile", isOn: $draft.reports.includeTechnician)
                Picker("Trip Log report format", selection: $draft.reports.format) {
                    Text("Detailed").tag("detailed")
                    Text("Compact").tag("compact")
                }
                Text("Trip Log reports include the recorded route, detected stops, account visits, elapsed time, and distance for the selected workday.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Email reports to", text: $draft.email.defaultTo)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                TextField("CC (optional)", text: $draft.email.cc)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($focused)

                Toggle("Email daily report", isOn: $draft.reports.dailyEmailEnabled)
                if draft.reports.dailyEmailEnabled {
                    DatePicker(
                        "Daily delivery time",
                        selection: dailyDeliveryTime,
                        displayedComponents: .hourAndMinute
                    )
                }

                Toggle("Email weekly report", isOn: $draft.reports.weeklyEmailEnabled)
                if draft.reports.weeklyEmailEnabled {
                    Picker("Weekly delivery day", selection: $draft.reports.weeklyEmailWeekday) {
                        ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, day in
                            Text(day).tag(index + 1)
                        }
                    }
                    DatePicker(
                        "Weekly delivery time",
                        selection: weeklyDeliveryTime,
                        displayedComponents: .hourAndMinute
                    )
                }

                LabeledContent("Time zone", value: timeZoneLabel)

                if !deliveryStatus.isEmpty {
                    Label(deliveryStatus, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Automatic Email Delivery")
            } footer: {
                Text("Reports are generated and emailed securely through Supabase and Resend even when FireVault is closed. Multiple addresses may be separated with commas.")
            }
            Section("Service Report Defaults") {
                TextField("Report title", text: $draft.reports.title).focused($focused)
            }
            Section("Included Service Content") {
                Toggle("Tasks", isOn: $draft.reports.includeTasks)
                Toggle("Deficiencies", isOn: $draft.reports.includeDeficiencies)
            }
        }
        .nativeSettingsForm(title: "Trip Log Reports", focused: $focused) {
            draft.reports.reportTimeZone = TimeZone.current.identifier
            settings.save(draft)
            Task {
                do {
                    try await FireVaultTripLogAutomationService.shared.syncPreferences(settings.preferences)
                    deliveryStatus = "Automation settings saved"
                } catch {
                    deliveryStatus = "Saved on this device; cloud sync will retry"
                }
            }
        }
    }

    private var dailyDeliveryTime: Binding<Date> {
        deliveryTime(hour: $draft.reports.dailyEmailHour, minute: $draft.reports.dailyEmailMinute)
    }

    private var weeklyDeliveryTime: Binding<Date> {
        deliveryTime(hour: $draft.reports.weeklyEmailHour, minute: $draft.reports.weeklyEmailMinute)
    }

    private func deliveryTime(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: hour.wrappedValue,
                minute: minute.wrappedValue,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            hour.wrappedValue = components.hour ?? 18
            minute.wrappedValue = components.minute ?? 0
        }
    }

    private var timeZoneLabel: String {
        TimeZone.current.localizedName(for: .standard, locale: .current)
            ?? TimeZone.current.identifier
    }
}

struct NativeEmailSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
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
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
    var body: some View {
        Form {
            Section("Photos") {
                Picker("Destination", selection: $draft.storage.photoProvider) { Text("On this iPhone").tag("local"); Text("Microsoft profile").tag("microsoft") }
                TextField("Folder", text: $draft.storage.photoFolder).focused($focused)
            }
            Section("Documents") {
                Picker("Destination", selection: $draft.storage.documentProvider) { Text("On this iPhone").tag("local"); Text("Microsoft profile").tag("microsoft") }
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
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
    var body: some View {
        Form {
            Section("Connection Profile") {
                TextField("Profile label", text: $draft.storage.microsoftProfileLabel).focused($focused)
                TextField("Microsoft email", text: $draft.storage.microsoftEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).focused($focused)
                TextField("SharePoint site URL", text: $draft.storage.sharePointSiteURL).keyboardType(.URL).textInputAutocapitalization(.never).focused($focused)
                TextField("Library", text: $draft.storage.libraryName).focused($focused)
            }
        }
        .nativeSettingsForm(title: "Microsoft Storage", focused: $focused) { settings.save(draft) }
    }
}

struct NativeSyncSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    @FocusState private var focused: Bool
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
    var body: some View {
        Form {
            Section("Shared Vault") {
                TextField("Organization or team", text: $draft.sync.organization).focused($focused)
                TextField("Workspace name", text: $draft.sync.workspace).focused($focused)
                Picker("Conflict handling", selection: $draft.sync.conflictPolicy) { Text("Require review").tag("review"); Text("Newest wins").tag("newest"); Text("Imported copy wins").tag("server") }
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
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
    var body: some View {
        List {
            Section("Categories") { ForEach(draft.categories, id: \.self) { Text($0) }.onDelete { draft.categories.remove(atOffsets: $0) } }
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
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
    var body: some View {
        Form {
            Section("WebDAV Server") {
                Toggle("Enable WebDAV profile", isOn: $draft.webDAV.enabled)
                TextField("Server URL", text: $draft.webDAV.serverURL).keyboardType(.URL).textInputAutocapitalization(.never).focused($focused)
                TextField("Username", text: $draft.webDAV.username).textInputAutocapitalization(.never).focused($focused)
                TextField("Remote folder", text: $draft.webDAV.folder).focused($focused)
            }
        }
        .nativeSettingsForm(title: "WebDAV Backup", focused: $focused) { settings.save(draft) }
    }
}

struct NativePrivacySettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences
    init(settings: FireVaultNativeSettingsStore) { self.settings = settings; _draft = State(initialValue: settings.preferences) }
    var body: some View {
        Form {
            Section("Interaction") {
                Toggle("Scrolling haptics", isOn: Binding(
                    get: { draft.gps.hapticsEnabled ?? true },
                    set: { draft.gps.hapticsEnabled = $0 }
                ))
                Text("Provides a light click as Nearby accounts snap into position.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Toggle("Enable native privacy lock", isOn: $draft.privacy.enabled)
                Picker("Auto-lock", selection: $draft.privacy.autoLockMinutes) { Text("Immediately").tag(0); Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15) }
                Toggle("Lock when app enters background", isOn: $draft.privacy.lockOnBackground)
                Toggle("Hide content in app switcher", isOn: $draft.privacy.hideInAppSwitcher)
            }
        }
        .nativeSettingsForm(title: "Privacy & Interaction") { settings.save(draft) }
    }
}

struct NativeCSVImportView: View {
    @ObservedObject var store: FireVaultStore
    @State private var showImporter = false
    @State private var result: FireVaultCSVImportResult?
    @State private var errorMessage = ""
    @State private var confirmExitDemo = false

    var body: some View {
        List {
            Section("Native CSV Import") {
                Button("Choose CSV File", systemImage: "doc.badge.plus") {
                    result = nil; errorMessage = ""
                    if store.demoMode { confirmExitDemo = true } else { showImporter = true }
                }
                .buttonStyle(.borderedProminent)
                Text("Recognized columns include Account Name, Address, City, State, ZIP, Account ID, Category, Phone, Latitude, and Longitude.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let result {
                Section("Import Result") {
                    LabeledContent("Rows", value: "\(result.totalRows)")
                    LabeledContent("Added", value: "\(result.added)")
                    LabeledContent("Updated", value: "\(result.updated)")
                    LabeledContent("Skipped", value: "\(result.skipped)")
                }
            }
            if !errorMessage.isEmpty { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }
        }
        .navigationTitle("Customer CSV Import")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Exit Demo Mode and import?", isPresented: $confirmExitDemo) {
            Button("Exit Demo Mode and Choose CSV") { store.exitDemoMode(); showImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .data], allowsMultipleSelection: false) { selection in
            do {
                guard let url = try selection.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                result = try store.importAccountsCSV(Data(contentsOf: url))
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct NativeDemoSettingsView: View {
    @ObservedObject var store: FireVaultStore
    var body: some View {
        List {
            Section {
                Label(store.demoMode ? "Native Demo Mode is active" : "Demo Mode is off", systemImage: store.demoMode ? "theatermasks.fill" : "checkmark.shield.fill")
                if store.demoMode {
                    Button("Exit Demo Mode") { store.exitDemoMode() }
                    Button("Reset Native Demo Data", role: .destructive) { store.resetDemo() }
                } else {
                    Button("Enter Demo Mode") { store.enterDemoMode() }
                }
            }
        }
        .navigationTitle("Demo Mode")
        .navigationBarTitleDisplayMode(.inline)
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
            Section("Trip Log") {
                Label("Start Trip Log at the beginning of the workday to record your route and detected stops.", systemImage: "play.circle")
                Label("Pause or resume Trip Log when route recording should temporarily stop.", systemImage: "pause.circle")
                Label("Review each detected stop before exporting the final Trip Log report.", systemImage: "checklist")
                Label("Trip Log Reports can be configured in Settings under Reports.", systemImage: "doc.text")
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
