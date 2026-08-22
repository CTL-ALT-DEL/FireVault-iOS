//
//  NativeSettingsOtherScreens.swift
//  FireVault
//
//  Settings destinations separated from the Photo Overlay editor.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import LocalAuthentication
import CoreLocation

struct NativePlusCodeSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @State private var draft: FireVaultNativePreferences
    init(settings: FireVaultNativeSettingsStore, locationService: FireVaultLocationService) {
        self.settings = settings
        self.locationService = locationService
        _draft = State(initialValue: settings.preferences)
    }
    var body: some View {
        Form {
            Section("Availability") {
                Toggle("Show Plus Code tools", isOn: $draft.plusCodes.enabled)
                Toggle("Generate automatically from GPS", isOn: $draft.plusCodes.autoGenerate)
                Toggle("Allow account search", isOn: $draft.plusCodes.searchable)
            }
            Section("Precision") {
                Picker("Account precision", selection: $draft.plusCodes.accountLength) { Text("10 digits").tag(10); Text("11 digits").tag(11) }
                Picker("Location precision", selection: $draft.plusCodes.locationLength) { Text("10 digits").tag(10); Text("11 digits").tag(11) }
            }
            Section {
                LabeledContent("CURRENT LOCATION") {
                    Text(currentPlusCode)
                        .font(.headline.monospaced())
                        .foregroundStyle(NativeShellPalette.blue)
                        .textSelection(.enabled)
                }
                Button {
                    locationService.requestCurrentLocation(highAccuracy: true)
                } label: {
                    Label("Refresh Current Location", systemImage: "location.fill")
                }
            } footer: {
                Text("Full Plus Codes are generated locally from GPS coordinates. No address lookup, Google API key, or paid Google request is required.")
            }
        }
        .nativeSettingsForm(title: "Plus Codes") { settings.save(draft) }
    }

    private var currentPlusCode: String {
        guard let coordinate = locationService.coordinate else { return "Waiting for GPS…" }
        return FireVaultPlusCode.encode(coordinate, length: draft.plusCodes.accountLength)
    }
}

struct NativeReportSettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @EnvironmentObject private var authentication: FireVaultAuthentication
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
                Text("Reports are generated and emailed securely through Supabase and Resend even when FireVault Pro is closed. Multiple addresses may be separated with commas.")
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
        .task {
            applySignedInEmailIfNeeded(authentication.signedInEmail)
        }
        .onChange(of: authentication.signedInEmail) { _, email in
            applySignedInEmailIfNeeded(email)
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

    private func applySignedInEmailIfNeeded(_ email: String) {
        let current = draft.email.defaultTo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.isEmpty, !email.isEmpty else { return }
        draft.email.defaultTo = email
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
            Section {
                storagePlanOverview
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)

            Section {
                destinationRow(
                    title: "Photos",
                    detail: "Field photos and imported images",
                    symbol: "photo.on.rectangle.angled",
                    selection: $draft.storage.photoProvider
                )
                folderField("Photo folder", text: $draft.storage.photoFolder)
            } header: {
                Text("Photo Storage")
            } footer: {
                providerDescription(draft.storage.photoProvider)
            }

            Section {
                destinationRow(
                    title: "Files & Scans",
                    detail: "Documents, reports, and scanned pages",
                    symbol: "doc.on.doc.fill",
                    selection: $draft.storage.documentProvider
                )
                folderField("Document folder", text: $draft.storage.documentFolder)
            } header: {
                Text("Document Storage")
            } footer: {
                providerDescription(draft.storage.documentProvider)
            }

            Section {
                Picker("Photo quality", selection: optionalString(\.photoQuality, default: "original")) {
                    Text("Original quality").tag("original")
                    Text("Storage optimized").tag("optimized")
                    Text("Small file").tag("compact")
                }
                Picker("Scanned document format", selection: optionalString(\.scanFormat, default: "pdf")) {
                    Text("Searchable PDF").tag("pdf")
                    Text("Individual images").tag("images")
                }
            } header: {
                Label("File Quality & Format", systemImage: "slider.horizontal.3")
            } footer: {
                Text("Original photos preserve maximum detail. Searchable PDF keeps a multi-page scan together as one document.")
            }

            Section {
                settingsToggle(
                    "Account folders",
                    detail: "Keep each customer's files together",
                    symbol: "folder.badge.person.crop",
                    isOn: optionalBool(\.useAccountFolders, default: true)
                )
                settingsToggle(
                    "Keep device originals",
                    detail: "Retain a local copy after upload",
                    symbol: "iphone",
                    isOn: optionalBool(\.preserveOriginals, default: true)
                )
                settingsToggle(
                    "Wi-Fi uploads only",
                    detail: "Avoid using cellular data for files",
                    symbol: "wifi",
                    isOn: optionalBool(\.wifiOnlyUploads, default: false)
                )
            } header: {
                Text("Organization & Uploads")
            } footer: {
                Text(uploadSummary)
            }

            Section {
                NavigationLink {
                    NativeMicrosoftStorageSettingsView(settings: settings)
                } label: {
                    storageConnectionRow(
                        "Microsoft OneDrive & SharePoint",
                        symbol: "cloud.fill",
                        configured: !draft.storage.microsoftEmail.isEmpty || !draft.storage.sharePointSiteURL.isEmpty
                    )
                }
                NavigationLink {
                    NativeWebDAVSettingsView(settings: settings)
                } label: {
                    storageConnectionRow(
                        "WebDAV Server",
                        symbol: "server.rack",
                        configured: draft.webDAV.enabled
                    )
                }
                storageConnectionRow("iCloud Drive", symbol: "icloud.fill", configured: true)
                storageConnectionRow("FireVault Cloud", symbol: "shield.lefthalf.filled", configured: false)
            } header: {
                Text("Connected Services")
            } footer: {
                Text("Set up a service here before selecting it as a save destination. FireVault Cloud requires a Pro subscription.")
            }
        }
        .nativeSettingsForm(title: "File Storage", focused: $focused) { settings.save(draft) }
    }

    private var storagePlanOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(NativeShellPalette.blue)
                    .frame(width: 44, height: 44)
                    .background(NativeShellPalette.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Storage Plan")
                        .font(.headline)
                    Text("Choose where field records are saved and how files are prepared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                destinationSummary(
                    title: "PHOTOS",
                    provider: draft.storage.photoProvider,
                    symbol: "photo.fill"
                )
                destinationSummary(
                    title: "FILES & SCANS",
                    provider: draft.storage.documentProvider,
                    symbol: "doc.fill"
                )
            }
        }
        .padding(16)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NativeShellPalette.blue.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: NativeShellPalette.cardShadow, radius: 10, y: 4)
    }

    private func destinationSummary(title: String, provider: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(NativeShellPalette.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(providerName(provider))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeShellPalette.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func destinationRow(title: String, detail: String, symbol: String, selection: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(NativeShellPalette.blue)
                .frame(width: 32, height: 32)
                .background(NativeShellPalette.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            storageDestinationPicker(selection: selection)
        }
        .padding(.vertical, 3)
    }

    private func storageDestinationPicker(selection: Binding<String>) -> some View {
        Picker("Destination", selection: selection) {
            Text("On this iPhone or iPad").tag("local")
            Text("FireVault Cloud").tag("firevault")
            Text("iCloud Drive").tag("icloud")
            Text("Microsoft OneDrive").tag("onedrive")
            Text("Microsoft SharePoint").tag("sharepoint")
            Text("WebDAV Server").tag("webdav")
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .font(.subheadline.weight(.semibold))
    }

    private func folderField(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(NativeShellPalette.amber)
                .frame(width: 24)
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .multilineTextAlignment(.trailing)
        }
    }

    private func settingsToggle(_ title: String, detail: String, symbol: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .foregroundStyle(NativeShellPalette.blue)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func providerDescription(_ provider: String) -> Text {
        switch provider {
        case "firevault": Text("Pro storage keeps FireVault files available in the cloud for the configured retention period.")
        case "icloud": Text("Files are organized in FireVault folders in iCloud Drive.")
        case "onedrive", "sharepoint", "microsoft": Text("Complete the Microsoft connection profile before uploading files.")
        case "webdav": Text("Complete the WebDAV server profile before uploading files.")
        default: Text("Files remain stored locally in FireVault on this device.")
        }
    }

    private func optionalBool(_ keyPath: WritableKeyPath<FireVaultStoragePreferences, Bool?>, default defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: { draft.storage[keyPath: keyPath] ?? defaultValue },
            set: { draft.storage[keyPath: keyPath] = $0 }
        )
    }

    private func optionalString(_ keyPath: WritableKeyPath<FireVaultStoragePreferences, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { draft.storage[keyPath: keyPath] ?? defaultValue },
            set: { draft.storage[keyPath: keyPath] = $0 }
        )
    }

    private func storageConnectionRow(_ title: String, symbol: String, configured: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(configured ? NativeShellPalette.green : NativeShellPalette.blue)
                .frame(width: 32, height: 32)
                .background(
                    (configured ? NativeShellPalette.green : NativeShellPalette.blue).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(configured ? "Available as a destination" : "Connection required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(configured ? "Ready" : "Setup")
                .font(.caption.bold())
                .foregroundStyle(configured ? NativeShellPalette.green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (configured ? NativeShellPalette.green : Color.secondary).opacity(0.10),
                    in: Capsule()
                )
        }
    }

    private var uploadSummary: String {
        let connection = (draft.storage.wifiOnlyUploads ?? false) ? "Uploads wait for Wi-Fi." : "Uploads may use Wi-Fi or cellular data."
        let originals = (draft.storage.preserveOriginals ?? true) ? "Device originals are retained." : "Device originals may be removed after upload."
        return "\(connection) \(originals)"
    }

    private func providerName(_ provider: String) -> String {
        switch provider {
        case "firevault": "FireVault Cloud"
        case "icloud": "iCloud Drive"
        case "onedrive", "microsoft": "OneDrive"
        case "sharepoint": "SharePoint"
        case "webdav": "WebDAV"
        default: "This Device"
        }
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
    @ObservedObject var store: FireVaultStore
    @State private var draft: FireVaultNativePreferences
    @State private var newCategory = ""
    @State private var editingOriginalCategory: String?
    @State private var editingCategoryName = ""
    @State private var editingCategorySymbol = "tag.fill"
    @State private var editingCategoryColor = "blue"
    @State private var editingCategoryDesign = FireVaultCategoryTagDesign.label
    @State private var ruleCreatingCategoryIndex: Int?
    @State private var ruleNewCategory = ""
    @State private var runResult: String?
    @FocusState private var focused: Bool
    init(settings: FireVaultNativeSettingsStore, store: FireVaultStore) {
        self.settings = settings
        self.store = store
        _draft = State(initialValue: settings.preferences)
    }
    var body: some View {
        List {
            Section("Category Tags") {
                ForEach(draft.categories, id: \.self) { category in
                    Button { beginEditing(category) } label: {
                        HStack(spacing: 11) {
                            categoryPreview(category)
                            Text(category)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer()
                            Text("\(accountCount(for: category))")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteCategories)
            }
            Section("Add Category") {
                TextField("Category tag", text: $newCategory).focused($focused)
                Button("Add", systemImage: "plus") {
                    let value = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, !draft.categories.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
                    draft.categories.append(value); newCategory = ""
                }
            }

            Section {
                ForEach(ruleIndices, id: \.self) { index in
                    categoryRule(at: index)
                }
                .onDelete { offsets in
                    var rules = draft.categoryRules ?? []
                    rules.remove(atOffsets: offsets)
                    draft.categoryRules = rules
                }

                Button("Create Rule", systemImage: "plus.circle.fill") {
                    var rules = draft.categoryRules ?? []
                    rules.append(FireVaultCategoryRule(categoryTag: draft.categories.first ?? ""))
                    draft.categoryRules = rules
                }
                .disabled(draft.categories.isEmpty)

                Button("Run Rules Now", systemImage: "play.circle.fill") {
                    save()
                    let additions = store.configureCategoryRules(draft.categoryRules ?? [])
                    runResult = additions == 1 ? "1 category tag was added." : "\(additions) category tags were added."
                }
                .disabled((draft.categoryRules ?? []).isEmpty)
            } header: {
                Text("Automatic IF / THEN Rules")
            } footer: {
                Text("Enabled rules add matching category tags to accounts automatically. Existing tags are preserved.")
            }
        }
        .nativeSettingsForm(title: "Account Categories", focused: $focused) { save() }
        .sheet(isPresented: Binding(get: { editingOriginalCategory != nil }, set: { if !$0 { editingOriginalCategory = nil } })) {
            categoryEditor
        }
        .alert("Create New Category", isPresented: Binding(get: { ruleCreatingCategoryIndex != nil }, set: { if !$0 { ruleCreatingCategoryIndex = nil } })) {
            TextField("Category name", text: $ruleNewCategory)
            Button("Cancel", role: .cancel) { ruleNewCategory = "" }
            Button("Create") { createCategoryForRule() }
        } message: {
            Text("The new category will be created and selected for this rule.")
        }
        .alert("Rules Complete", isPresented: Binding(get: { runResult != nil }, set: { if !$0 { runResult = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(runResult ?? "")
        }
    }

    private var ruleIndices: [Int] { Array((draft.categoryRules ?? []).indices) }

    private func ruleBinding(at index: Int) -> Binding<FireVaultCategoryRule> {
        Binding(
            get: { (draft.categoryRules ?? [])[index] },
            set: { value in
                var rules = draft.categoryRules ?? []
                guard rules.indices.contains(index) else { return }
                rules[index] = value
                draft.categoryRules = rules
            }
        )
    }

    @ViewBuilder
    private func categoryRule(at index: Int) -> some View {
        let rule = ruleBinding(at: index)
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Rule \(index + 1)", isOn: rule.isEnabled)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text("IF FIELD")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Picker("Field", selection: rule.field) {
                    ForEach(FireVaultCategoryRuleField.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("CONDITION")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Picker("Condition", selection: rule.condition) {
                    ForEach(FireVaultCategoryRuleCondition.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("Match text", text: rule.value)
                .textInputAutocapitalization(.words)
                .focused($focused)

            VStack(alignment: .leading, spacing: 5) {
                Text("THEN ADD CATEGORY")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Picker("Category tag", selection: ruleCategoryBinding(at: index)) {
                    ForEach(draft.categories, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("Create New Category…").tag("__CREATE_NEW_CATEGORY__")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        var cleanedDraft = draft
        let configuredCategories = cleanedDraft.categories
        let isConfigured: (String) -> Bool = { candidate in
            configuredCategories.contains {
                $0.caseInsensitiveCompare(candidate) == .orderedSame
            }
        }
        let removedFromList = settings.preferences.categories.filter { existing in
            !draft.categories.contains {
                $0.caseInsensitiveCompare(existing) == .orderedSame
            }
        }
        let retiredRuleCategories = (cleanedDraft.categoryRules ?? [])
            .map(\.categoryTag)
            .filter { !isConfigured($0) }
        let retiredStyleCategories = (cleanedDraft.categoryStyles ?? [])
            .map(\.category)
            .filter { !isConfigured($0) }
        let removedCategories = removedFromList + retiredRuleCategories + retiredStyleCategories

        cleanedDraft.categoryRules = (cleanedDraft.categoryRules ?? []).filter {
            isConfigured($0.categoryTag)
        }
        cleanedDraft.categoryStyles = (cleanedDraft.categoryStyles ?? []).filter {
            isConfigured($0.category)
        }
        if !removedCategories.isEmpty {
            store.removeCategories(removedCategories)
        }
        draft = cleanedDraft
        settings.save(cleanedDraft)
        store.configureCategoryRules(cleanedDraft.categoryRules ?? [])
    }

    private func deleteCategories(at offsets: IndexSet) {
        let removed = offsets.compactMap { index in
            draft.categories.indices.contains(index) ? draft.categories[index] : nil
        }
        guard !removed.isEmpty else { return }

        draft.categories.remove(atOffsets: offsets)
        draft.categoryRules = (draft.categoryRules ?? []).filter { rule in
            !removed.contains {
                $0.caseInsensitiveCompare(rule.categoryTag) == .orderedSame
            }
        }
        draft.categoryStyles = (draft.categoryStyles ?? []).filter { style in
            !removed.contains {
                $0.caseInsensitiveCompare(style.category) == .orderedSame
            }
        }
    }

    private func ruleCategoryBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { (draft.categoryRules ?? [])[index].categoryTag },
            set: { value in
                if value == "__CREATE_NEW_CATEGORY__" {
                    ruleCreatingCategoryIndex = index
                    return
                }
                var rules = draft.categoryRules ?? []
                guard rules.indices.contains(index) else { return }
                rules[index].categoryTag = value
                draft.categoryRules = rules
            }
        )
    }

    private func accountCount(for category: String) -> Int {
        store.accounts.filter { account in
            account.category.caseInsensitiveCompare(category) == .orderedSame
                || account.tags.contains { $0.caseInsensitiveCompare(category) == .orderedSame }
        }.count
    }

    private func style(for category: String) -> FireVaultCategoryStyle {
        (draft.categoryStyles ?? []).first { $0.category.caseInsensitiveCompare(category) == .orderedSame }
            ?? FireVaultCategoryStyle(category: category)
    }

    private func categoryPreview(_ category: String) -> some View {
        let style = style(for: category)
        return Image(systemName: style.design == .hashtag ? "number" : style.symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(categoryColor(style.color))
            .frame(width: 30, height: 30)
            .background(categoryColor(style.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
    }

    private func categoryColor(_ name: String) -> Color {
        switch name {
        case "red": .red
        case "green": .green
        case "orange": .orange
        case "purple": .purple
        case "pink": .pink
        case "teal": .teal
        default: .blue
        }
    }

    private func beginEditing(_ category: String) {
        let style = style(for: category)
        editingOriginalCategory = category
        editingCategoryName = category
        editingCategorySymbol = style.symbol
        editingCategoryColor = style.color
        editingCategoryDesign = style.design
    }

    private var categoryEditor: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Category name", text: $editingCategoryName)
                    Picker("Tag design", selection: $editingCategoryDesign) {
                        ForEach(FireVaultCategoryTagDesign.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Icon Style") {
                    Picker("Icon", selection: $editingCategorySymbol) {
                        Label("Tag", systemImage: "tag.fill").tag("tag.fill")
                        Label("Building", systemImage: "building.2.fill").tag("building.2.fill")
                        Label("Shield", systemImage: "shield.fill").tag("shield.fill")
                        Label("Star", systemImage: "star.fill").tag("star.fill")
                        Label("Wrench", systemImage: "wrench.and.screwdriver.fill").tag("wrench.and.screwdriver.fill")
                    }
                    .disabled(editingCategoryDesign == .hashtag)
                    Picker("Icon color", selection: $editingCategoryColor) {
                        ForEach(["blue", "red", "green", "orange", "purple", "pink", "teal"], id: \.self) { color in
                            Text(color.capitalized).tag(color)
                        }
                    }
                }
                Section("Preview") {
                    HStack {
                        Image(systemName: editingCategoryDesign == .hashtag ? "number" : editingCategorySymbol)
                        Text(editingCategoryDesign == .hashtag ? "#\(editingCategoryName.replacingOccurrences(of: " ", with: ""))" : editingCategoryName)
                            .font(.subheadline.bold())
                    }
                    .foregroundStyle(categoryColor(editingCategoryColor))
                }
            }
            .fireVaultThemedCollection()
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingOriginalCategory = nil } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveCategoryEdit() } }
            }
        }
    }

    private func saveCategoryEdit() {
        guard let original = editingOriginalCategory else { return }
        let updated = editingCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.isEmpty else { return }
        if let index = draft.categories.firstIndex(where: { $0.caseInsensitiveCompare(original) == .orderedSame }) {
            draft.categories[index] = updated
        }
        var rules = draft.categoryRules ?? []
        for index in rules.indices where rules[index].categoryTag.caseInsensitiveCompare(original) == .orderedSame {
            rules[index].categoryTag = updated
        }
        draft.categoryRules = rules
        var styles = (draft.categoryStyles ?? []).filter { $0.category.caseInsensitiveCompare(original) != .orderedSame }
        styles.append(.init(category: updated, symbol: editingCategorySymbol, color: editingCategoryColor, design: editingCategoryDesign))
        draft.categoryStyles = styles
        store.renameCategory(from: original, to: updated)
        save()
        editingOriginalCategory = nil
    }

    private func createCategoryForRule() {
        guard let index = ruleCreatingCategoryIndex else { return }
        let value = ruleNewCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !draft.categories.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
            draft.categories.append(value)
        }
        var rules = draft.categoryRules ?? []
        if rules.indices.contains(index) { rules[index].categoryTag = value }
        draft.categoryRules = rules
        ruleNewCategory = ""
        ruleCreatingCategoryIndex = nil
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
                Toggle(
                    "Require Face ID",
                    isOn: Binding(
                        get: { draft.privacy.enabled },
                        set: { enabled in
                            draft.privacy.enabled = enabled
                            settings.save(draft)
                        }
                    )
                )
                Picker("Auto-lock", selection: $draft.privacy.autoLockMinutes) { Text("Immediately").tag(0); Text("1 minute").tag(1); Text("5 minutes").tag(5); Text("15 minutes").tag(15) }
                Toggle("Lock when app enters background", isOn: $draft.privacy.lockOnBackground)
                Toggle("Hide content in app switcher", isOn: $draft.privacy.hideInAppSwitcher)
                Text("Face ID protects the signed-in FireVault Pro workspace. Your device passcode remains available as Apple’s secure fallback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .nativeSettingsForm(title: "Privacy & Interaction") { settings.save(draft) }
    }
}

struct NativeSecuritySettingsView: View {
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @State private var draft: FireVaultNativePreferences

    init(settings: FireVaultNativeSettingsStore) {
        self.settings = settings
        _draft = State(initialValue: settings.preferences)
    }

    private var biometricStatus: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "Not configured on this device"
        }
        switch context.biometryType {
        case .faceID: return "Face ID available"
        case .touchID: return "Touch ID available"
        case .opticID: return "Optic ID available"
        default: return "Biometrics available"
        }
    }

    var body: some View {
        Form {
            Section("Device Protection") {
                Label(biometricStatus, systemImage: "faceid")
                LabeledContent("Application data", value: "iOS protected")
                LabeledContent("OpenAI key", value: "Stored on server")
            }

            Section("Workspace Lock") {
                Toggle("Require device authentication", isOn: $draft.privacy.enabled)
                Picker("Auto-lock", selection: $draft.privacy.autoLockMinutes) {
                    Text("Immediately").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                }
                Toggle("Lock in background", isOn: $draft.privacy.lockOnBackground)
                Toggle("Hide app-switcher content", isOn: $draft.privacy.hideInAppSwitcher)
            }

            Section {
                Text("FireVault Pro stores its local vault inside the iOS application sandbox. Device authentication uses Apple’s secure system interface; FireVault Pro never receives or stores biometric data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .nativeSettingsForm(title: "Security") { settings.save(draft) }
    }
}

struct FireVaultVaultBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.fireVaultBackup, .json] }
    var data: Data

    init(data: Data = Data("[]".utf8)) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NativeBackupRestoreView: View {
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @State private var exportDocument = FireVaultVaultBackupDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var statusMessage = ""
    @State private var errorMessage = ""
    @State private var storageReport = FireVaultMediaStorageReport(
        referencedFiles: 0,
        orphanedFiles: 0,
        totalBytes: 0
    )
    @State private var confirmsMediaCleanup = false

    var body: some View {
        List {
            Section {
                Label(
                    "\(store.accounts.count) accounts and \(breadcrumbs.days.count) Trip Log days ready",
                    systemImage: "checkmark.shield.fill"
                )
                    .foregroundStyle(NativeShellPalette.green)
                Button("Export Complete Vault", systemImage: "square.and.arrow.up") {
                    do {
                        exportDocument = .init(
                            data: try FireVaultVaultBackupCoordinator.export(
                                store: store,
                                settings: settings,
                                breadcrumbs: breadcrumbs
                            )
                        )
                        errorMessage = ""
                        isExporting = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Restore From Backup", systemImage: "square.and.arrow.down") {
                    errorMessage = ""
                    isImporting = true
                }
            } header: {
                Text("Complete Vault")
            } footer: {
                Text("The protected backup includes accounts, settings, Trip Log history, and referenced photos and scans. Restore merges missing records without overwriting an existing account or workday.")
            }

            Section("Local Media") {
                LabeledContent("Storage used", value: storageReport.formattedSize)
                LabeledContent("Referenced files", value: "\(storageReport.referencedFiles)")
                LabeledContent("Orphaned files", value: "\(storageReport.orphanedFiles)")
                Button("Clean Orphaned Media", systemImage: "trash", role: .destructive) {
                    confirmsMediaCleanup = true
                }
                .disabled(storageReport.orphanedFiles == 0)
            }

            if !statusMessage.isEmpty {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(NativeShellPalette.green)
                }
            }
            if !errorMessage.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(NativeShellPalette.amber)
                }
            }
        }
        .fireVaultThemedCollection()
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { storageReport = store.mediaStorageReport() }
        .confirmationDialog(
            "Remove orphaned media?",
            isPresented: $confirmsMediaCleanup,
            titleVisibility: .visible
        ) {
            Button("Remove Orphaned Files", role: .destructive) {
                let removed = store.removeOrphanedMedia()
                storageReport = store.mediaStorageReport()
                statusMessage = "Removed \(removed) orphaned media file\(removed == 1 ? "" : "s")."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only files that are not referenced by any account record will be removed.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .fireVaultBackup,
            defaultFilename: "FireVault-Complete-\(Date().formatted(.iso8601.year().month().day()))"
        ) { result in
            switch result {
            case .success:
                statusMessage = "Vault backup exported successfully."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.fireVaultBackup, .json],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                if url.pathExtension.lowercased() == "json" {
                    let merge = try store.mergeAccountsBackup(data)
                    statusMessage = "Legacy backup: \(merge.added) accounts restored; \(merge.preserved) preserved."
                } else {
                    let restored = try FireVaultVaultBackupCoordinator.restore(
                        data,
                        store: store,
                        settings: settings,
                        breadcrumbs: breadcrumbs
                    )
                    statusMessage = "Restored \(restored.accountsAdded) accounts, \(restored.tripLogDaysAdded) Trip Log days, and \(restored.mediaFilesRestored) media files."
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}

struct NativeCSVImportView: View {
    @ObservedObject var store: FireVaultStore
    @State private var showImporter = false
    @State private var result: FireVaultCSVImportResult?
    @State private var errorMessage = ""
    @State private var confirmExitDemo = false
    @State private var importData: Data?
    @State private var analysis: FireVaultCSVAnalysis?
    @State private var showReview = false
    @State private var activity: ImportActivity?
    @State private var selectedFileName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                NativeShellCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "tablecells.badge.ellipsis")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(NativeShellPalette.blue)
                                .frame(width: 52, height: 52)
                                .background(NativeShellPalette.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Smart Account Import")
                                    .font(.title3.bold())
                                Text("Flexible layouts, automatic column matching, and coordinate checks.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            beginChoosingFile()
                        } label: {
                            Label(result == nil ? "Choose CSV File" : "Import Another File", systemImage: "doc.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(activity != nil)
                    }
                }

                if let activity {
                    NativeShellCard {
                        HStack(spacing: 13) {
                            ProgressView()
                                .controlSize(.large)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(activity.title)
                                    .font(.headline)
                                Text(activity.detail(fileName: selectedFileName))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let result {
                    NativeShellCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Label("Import Complete", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(NativeShellPalette.green)
                            HStack(spacing: 8) {
                                importMetric("Added", result.added, NativeShellPalette.green)
                                importMetric("Updated", result.updated, NativeShellPalette.blue)
                                importMetric("Skipped", result.skipped, NativeShellPalette.amber)
                            }
                            Text("\(result.totalRows) rows processed. Your existing account records and field history were preserved.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ForEach(Array(result.messages.prefix(4).enumerated()), id: \.offset) { _, message in
                                Label(message, systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    NativeShellCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("Import Needs Attention", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(NativeShellPalette.amber)
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Choose a Different File", systemImage: "arrow.counterclockwise") {
                                beginChoosingFile()
                            }
                        }
                    }
                }

                NativeShellCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Recognized Information", systemImage: "checklist")
                            .font(.headline)
                            .foregroundStyle(NativeShellPalette.blue)
                        Text("Account name, address, city, state, ZIP code, account ID, category, phone number, latitude, and longitude.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Nothing is changed until you review the detected layout and tap Import.")
                            .font(.footnote.bold())
                            .foregroundStyle(NativeShellPalette.green)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Customer CSV Import")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Exit Demo Mode and import?", isPresented: $confirmExitDemo) {
            Button("Exit Demo Mode and Choose CSV") { store.exitDemoMode(); showImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText, .data], allowsMultipleSelection: false) { selection in
            handleFileSelection(selection)
        }
        .sheet(isPresented: $showReview) {
            if let importData, let analysis {
                NavigationStack {
                    NativeCSVImportReviewView(
                        store: store,
                        data: importData,
                        fileName: selectedFileName,
                        initialAnalysis: analysis
                    ) { importResult in
                        result = importResult
                        self.analysis = nil
                        self.importData = nil
                        showReview = false
                    }
                }
            }
        }
    }

    private enum ImportActivity {
        case reading
        case analyzing

        var title: String {
            switch self {
            case .reading: "Reading CSV File"
            case .analyzing: "Analyzing Columns and Rows"
            }
        }

        func detail(fileName: String) -> String {
            switch self {
            case .reading: fileName.isEmpty ? "Opening the selected document…" : "Opening \(fileName)…"
            case .analyzing: "Matching fields, validating coordinates, and preparing row results…"
            }
        }
    }

    private func beginChoosingFile() {
        result = nil
        errorMessage = ""
        selectedFileName = ""
        if store.demoMode {
            confirmExitDemo = true
        } else {
            showImporter = true
        }
    }

    private func handleFileSelection(_ selection: Result<[URL], Error>) {
        Task { @MainActor in
            do {
                guard let url = try selection.get().first else { return }
                selectedFileName = url.lastPathComponent
                activity = .reading
                await Task.yield()

                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)

                activity = .analyzing
                await Task.yield()
                let preview = try store.previewAccountsCSV(data)

                importData = data
                analysis = preview
                activity = nil
                showReview = true
            } catch {
                activity = nil
                errorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func importMetric(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct NativeCSVImportReviewView: View {
    @ObservedObject var store: FireVaultStore
    let data: Data
    let fileName: String
    let onImport: (FireVaultCSVImportResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var analysis: FireVaultCSVAnalysis
    @State private var mapping: FireVaultCSVMapping
    @State private var correctSwappedCoordinates = false
    @State private var errorMessage = ""
    @State private var showAllRows = false
    @State private var isImporting = false

    init(
        store: FireVaultStore,
        data: Data,
        fileName: String,
        initialAnalysis: FireVaultCSVAnalysis,
        onImport: @escaping (FireVaultCSVImportResult) -> Void
    ) {
        self.store = store
        self.data = data
        self.fileName = fileName
        self.onImport = onImport
        _analysis = State(initialValue: initialAnalysis)
        _mapping = State(initialValue: initialAnalysis.preview.mapping)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: analysis.preview.requiresMappingReview ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(analysis.preview.requiresMappingReview ? NativeShellPalette.amber : NativeShellPalette.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(analysis.preview.requiresMappingReview ? "Mapping Review Required" : "Layout Recognized")
                            .font(.headline)
                        Text("\(analysis.preview.rows.count) rows • \(analysis.preview.headers.count) columns • \(analysis.preview.delimiterName) separated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Detected Layout") {
                LabeledContent("Delimiter", value: analysis.preview.delimiterName)
                LabeledContent("Columns", value: "\(analysis.preview.headers.count)")
                if analysis.preview.requiresMappingReview {
                    Label("Confirm the highlighted field mapping before importing.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                ForEach(analysis.preview.mappingMessages, id: \.self) {
                    Text($0).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Column Mapping") {
                ForEach(FireVaultCSVField.allCases) { field in
                    Picker(field.title, selection: mappingBinding(field)) {
                        Text("Not imported").tag(Int?.none)
                        ForEach(analysis.preview.headers.indices, id: \.self) { index in
                            Text(analysis.preview.headers[index].isEmpty ? "Column \(index + 1)" : analysis.preview.headers[index])
                                .tag(Int?.some(index))
                        }
                    }
                }
                Button("Apply Mapping") { refreshAnalysis() }
                    .buttonStyle(.bordered)
            }

            if analysis.preview.swappedCoordinateRows > 0 {
                Section("Coordinate Correction") {
                    Toggle("Correct likely swapped latitude/longitude", isOn: $correctSwappedCoordinates)
                        .onChange(of: correctSwappedCoordinates) { _, _ in refreshAnalysis() }
                    Text("FireVault Pro only offers this correction when the supplied pair is invalid but becomes valid after swapping.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Row Results") {
                HStack {
                    resultCount("Successful", analysis.preview.successful, .green)
                    Spacer()
                    resultCount("Review", analysis.preview.review, .orange)
                    Spacer()
                    resultCount("Rejected", analysis.preview.rejected, .red)
                }
                ForEach(Array(visibleRows)) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Row \(row.rowNumber): \(row.accountName)").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(row.status.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(row.status))
                        }
                        Text(row.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if analysis.preview.rows.count > 75 {
                    Button(showAllRows ? "Show First 75 Rows" : "Show All \(analysis.preview.rows.count) Rows") {
                        showAllRows.toggle()
                    }
                }
            }

            if isImporting {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Importing Accounts")
                                .font(.headline)
                            Text("Saving on this iPhone and syncing to your FireVault account…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !errorMessage.isEmpty {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
        }
        .fireVaultThemedCollection()
        .navigationTitle("Review CSV Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    refreshAnalysis()
                    guard errorMessage.isEmpty else { return }
                    isImporting = true
                    Task { @MainActor in
                        await Task.yield()
                        let result = await store.applyCSVImportAndSync(
                            analysis,
                            csvData: data,
                            fileName: fileName
                        )
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        isImporting = false
                        onImport(result)
                    }
                }
                .disabled(mapping[.accountName] == nil || analysis.preview.rows.isEmpty || isImporting)
            }
        }
    }

    private var visibleRows: ArraySlice<FireVaultCSVRowResult> {
        showAllRows ? analysis.preview.rows[...] : analysis.preview.rows.prefix(75)
    }

    private func mappingBinding(_ field: FireVaultCSVField) -> Binding<Int?> {
        .init(get: { mapping[field] }, set: { mapping[field] = $0 })
    }

    private func refreshAnalysis() {
        do {
            analysis = try store.previewAccountsCSV(
                data,
                mapping: mapping,
                correctSwappedCoordinates: correctSwappedCoordinates
            )
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resultCount(_ title: String, _ count: Int, _ color: Color) -> some View {
        VStack {
            Text("\(count)").font(.title3.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func color(_ status: FireVaultCSVRowStatus) -> Color {
        switch status {
        case .successful: .green
        case .review: .orange
        case .rejected: .red
        }
    }
}

struct NativeDemoSettingsView: View {
    @ObservedObject var store: FireVaultStore
    var body: some View {
        List {
            Section("What Demo Mode Does") {
                Text("Demo Mode opens a separate sample workspace populated with fictional accounts, equipment, notes, saved locations, and Trip Log history. It is designed for learning FireVault and demonstrating its workflows without changing live customer records.")
                    .font(.subheadline)
                Label("Demo records remain separate from your live vault.", systemImage: "lock.shield")
                Label("You can edit sample content and reset it afterward.", systemImage: "arrow.counterclockwise")
                Label("Location permission is not required to review sample Trip Log routes.", systemImage: "location.slash")
            }

            Section {
                Label(store.demoMode ? "Demo Mode is active" : "Demo Mode is off", systemImage: store.demoMode ? "theatermasks.fill" : "checkmark.shield.fill")
                if store.demoMode {
                    Button("Exit Demo Mode") { store.exitDemoMode() }
                    Button("Reset Demo Data", role: .destructive) { store.resetDemo() }
                } else {
                    Button("Enter Demo Mode") { store.enterDemoMode() }
                }
            } header: {
                Text("Controls")
            } footer: {
                Text(store.demoMode
                    ? "Exit Demo Mode to return to your live workspace. Reset restores the original sample data only."
                    : "Enter Demo Mode to explore the complete sample workspace. Your live FireVault records are not modified.")
            }
        }
        .fireVaultThemedCollection()
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Demo Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NativeManualView: View {
    @State private var search = ""

    private var topics: [FireVaultHelpTopic] {
        FireVaultHelpCatalog.matching(search)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if search.isEmpty {
                    helpHero
                    FireVaultHelpVisualView(kind: .quickStart, tint: NativeShellPalette.green)
                        .nativeSurfaceCard(cornerRadius: 20, emphasized: true)
                }

                if topics.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .frame(minHeight: 300)
                } else {
                    Text(search.isEmpty ? "CHOOSE WHAT YOU WANT TO DO" : "MATCHING HELP")
                        .font(.caption.bold())
                        .tracking(1.15)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(topics) { topic in
                            NavigationLink {
                                FireVaultHelpTopicView(topic: topic)
                            } label: {
                                FireVaultHelpTopicCard(topic: topic)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if search.isEmpty {
                    supportCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 104)
        }
        .background(NativeShellPalette.background)
        .searchable(text: $search, prompt: "Search help")
        .navigationTitle("Help Center")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var helpHero: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(
                        colors: [NativeShellPalette.red, NativeShellPalette.amber],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("HELP THAT GETS YOU MOVING")
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(NativeShellPalette.red)
                Text("What are you trying to do?")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("Short, verified guides for the field—without a wall of manual text.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .nativeSurfaceCard(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }

    private var supportCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "envelope.badge.fill")
                .font(.title2)
                .foregroundStyle(NativeShellPalette.blue)
                .frame(width: 44, height: 44)
                .background(NativeShellPalette.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Still need a hand?")
                    .font(.headline)
                Text("Send the exact message and a screenshot. Those two details save the most time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Link(destination: URL(string: "mailto:David@Bannerman.us?subject=FireVault%20Pro%20Help")!) {
                Text("Email")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(NativeShellPalette.blue, in: Capsule())
            }
            .accessibilityLabel("Email FireVault support")
        }
        .padding(16)
        .nativeSurfaceCard(cornerRadius: 20)
    }
}

private struct FireVaultHelpTopicCard: View {
    let topic: FireVaultHelpTopic

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: topic.symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(topic.eyebrow)
                    .font(.caption2.bold())
                    .tracking(1)
                    .foregroundStyle(tint)
                Text(topic.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(topic.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
                .accessibilityHidden(true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .nativeSurfaceCard(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.title). \(topic.summary)")
        .accessibilityHint("Opens step-by-step help")
    }

    private var tint: Color { NativeShellPalette.tint(topic.tint) }
}

private struct FireVaultHelpTopicView: View {
    let topic: FireVaultHelpTopic

    private var tint: Color { NativeShellPalette.tint(topic.tint) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                topicHeader

                FireVaultHelpVisualView(kind: topic.visual, tint: tint)
                    .nativeSurfaceCard(cornerRadius: 20, emphasized: true)

                helpSectionTitle("DO THIS", symbol: "checklist")
                VStack(spacing: 0) {
                    ForEach(Array(topic.steps.enumerated()), id: \.element.id) { index, step in
                        FireVaultHelpStepRow(number: index + 1, step: step, tint: tint)
                        if index < topic.steps.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .padding(.vertical, 4)
                .nativeSurfaceCard(cornerRadius: 20)

                successCard

                if !topic.notes.isEmpty {
                    helpSectionTitle("GOOD TO KNOW", symbol: "lightbulb.fill")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(topic.notes, id: \.self) { note in
                            Label {
                                Text(note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(tint)
                            }
                        }
                    }
                    .padding(16)
                    .nativeSurfaceCard(cornerRadius: 20)
                }

                if !topic.resources.isEmpty {
                    helpSectionTitle("OFFICIAL GUIDES", symbol: "safari.fill")
                    VStack(spacing: 0) {
                        ForEach(Array(topic.resources.enumerated()), id: \.element.id) { index, resource in
                            Link(destination: resource.url) {
                                HStack(spacing: 12) {
                                    Image(systemName: "apple.logo")
                                        .foregroundStyle(.primary)
                                        .frame(width: 28)
                                    Text(resource.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(tint)
                                }
                                .padding(15)
                            }
                            if index < topic.resources.count - 1 { Divider().padding(.leading, 55) }
                        }
                    }
                    .nativeSurfaceCard(cornerRadius: 20)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 104)
        }
        .background(NativeShellPalette.background)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var topicHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(topic.eyebrow, systemImage: topic.symbol)
                .font(.caption.bold())
                .tracking(1.05)
                .foregroundStyle(tint)
            Text(topic.title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
            Text(topic.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var successCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(NativeShellPalette.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.successTitle)
                    .font(.headline)
                Text(topic.successDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeShellPalette.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NativeShellPalette.green.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func helpSectionTitle(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.bold())
            .tracking(1.1)
            .foregroundStyle(.secondary)
    }
}

private struct FireVaultHelpStepRow: View {
    let number: Int
    let step: FireVaultHelpStep
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(step.title). \(step.detail)")
    }
}

private struct FireVaultHelpVisualView: View {
    let kind: FireVaultHelpVisual
    let tint: Color

    var body: some View {
        Group {
            switch kind {
            case .quickStart:
                flow([("person.crop.circle.fill", "SIGN IN"), ("arrow.triangle.2.circlepath", "SYNC"), ("truck.box.fill", "RECORD")])
            case .account:
                branchVisual(
                    leading: ("building.2.fill", "ONE CUSTOMER"),
                    trailing: ("person.crop.circle.fill", "YOUR SIGN-IN"),
                    footer: "Delete Customer Account leaves your FireVault login intact"
                )
            case .cloudSync:
                flow([("iphone", "IPHONE"), ("lock.icloud.fill", "PRIVATE VAULT"), ("globe", "PORTAL")])
            case .tripLog:
                flow([("circle", "READY"), ("record.circle.fill", "RECORDING"), ("checkmark.circle.fill", "SAVED")])
            case .carPlay:
                carPlayVisual
            case .fieldCapture:
                flow([("camera.fill", "CAPTURE"), ("building.2.fill", "CUSTOMER"), ("folder.fill", "FILES")])
            case .widgets:
                widgetVisual
            case .privacy:
                branchVisual(
                    leading: ("building.2.fill", "CUSTOMER"),
                    trailing: ("person.crop.circle.fill", "FIREVAULT ACCOUNT"),
                    footer: "Two separate deletion paths with separate confirmations"
                )
            case .troubleshooting:
                flow([("exclamationmark.triangle.fill", "READ STATUS"), ("wrench.adjustable.fill", "FIX CAUSE"), ("checkmark.circle.fill", "RECHECK")])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112)
        .accessibilityElement(children: .combine)
    }

    private func flow(_ items: [(String, String)]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 7) {
                    Image(systemName: item.0)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(index == items.count - 1 ? .white : tint)
                        .frame(width: 44, height: 44)
                        .background(index == items.count - 1 ? tint : tint.opacity(0.12), in: Circle())
                    Text(item.1)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.65)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity)

                if index < items.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(tint.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func branchVisual(
        leading: (String, String),
        trailing: (String, String),
        footer: String
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                visualPill(leading.0, leading.1, tint: tint)
                Text("≠")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("is different from")
                visualPill(trailing.0, trailing.1, tint: NativeShellPalette.red)
            }
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func visualPill(_ symbol: String, _ title: String, tint: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var carPlayVisual: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                visualPill("truck.box.fill", "TRIP LOG", tint: NativeShellPalette.red)
                visualPill("location.fill", "NEARBY", tint: NativeShellPalette.blue)
                visualPill("location.north.fill", "DRIVE", tint: NativeShellPalette.green)
            }
            Label("ARRIVED adds saved drop pins when available", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var widgetVisual: some View {
        HStack(spacing: 7) {
            widgetTile("gauge.with.dots.needle.67percent", "DASH")
            widgetTile("truck.box.fill", "TRIP")
            widgetTile("building.2.fill", "ACCOUNT")
            widgetTile("icloud.fill", "CLOUD")
        }
    }

    private func widgetTile(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.055, blue: 0.075), tint.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
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
