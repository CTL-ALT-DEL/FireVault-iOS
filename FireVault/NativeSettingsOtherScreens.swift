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
                Toggle("Include in reports", isOn: $draft.plusCodes.includeInReports)
            }
            Section("Precision") {
                Picker("Account precision", selection: $draft.plusCodes.accountLength) { Text("10 digits").tag(10); Text("11 digits").tag(11) }
                Picker("Location precision", selection: $draft.plusCodes.locationLength) { Text("10 digits").tag(10); Text("11 digits").tag(11) }
                Picker("Reverify", selection: $draft.plusCodes.verifyAfterDays) { Text("90 days").tag(90); Text("180 days").tag(180); Text("1 year").tag(365) }
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
                Text("The full Plus Code is generated locally from the current GPS coordinate. No address lookup is required.")
            }
        }
        .nativeSettingsForm(title: "Plus Codes") { settings.save(draft) }
    }

    private var currentPlusCode: String {
        guard let coordinate = locationService.coordinate else { return "Waiting for GPS…" }
        return FireVaultPlusCodeEncoder.encode(coordinate, length: draft.plusCodes.accountLength)
    }
}

private enum FireVaultPlusCodeEncoder {
    private static let alphabet = Array("23456789CFGHJMPQRVWX")
    private static let pairResolutions = [20.0, 1.0, 0.05, 0.0025, 0.000125]

    static func encode(_ coordinate: CLLocationCoordinate2D, length: Int = 10) -> String {
        var latitude = min(90, max(-90, coordinate.latitude))
        if latitude == 90 { latitude -= 0.000000001 }
        var longitude = coordinate.longitude
        while longitude < -180 { longitude += 360 }
        while longitude >= 180 { longitude -= 360 }
        latitude += 90
        longitude += 180

        var code = ""
        for resolution in pairResolutions {
            let latitudeDigit = min(19, Int(latitude / resolution))
            let longitudeDigit = min(19, Int(longitude / resolution))
            code.append(alphabet[latitudeDigit])
            code.append(alphabet[longitudeDigit])
            latitude -= Double(latitudeDigit) * resolution
            longitude -= Double(longitudeDigit) * resolution
        }

        if length > 10 {
            let latitudeDigit = min(4, Int(latitude / (0.000125 / 5)))
            let longitudeDigit = min(3, Int(longitude / (0.000125 / 4)))
            code.append(alphabet[latitudeDigit * 4 + longitudeDigit])
        }

        code.insert("+", at: code.index(code.startIndex, offsetBy: 8))
        let requested = min(11, max(8, length))
        let charactersWithoutSeparator = code.filter { $0 != "+" }
        let end = charactersWithoutSeparator.index(charactersWithoutSeparator.startIndex, offsetBy: requested)
        let trimmed = String(charactersWithoutSeparator[..<end])
        let separator = trimmed.index(trimmed.startIndex, offsetBy: 8)
        return String(trimmed[..<separator]) + "+" + String(trimmed[separator...])
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
                storageDestinationPicker("Photo destination", selection: $draft.storage.photoProvider)
                TextField("Photo folder", text: $draft.storage.photoFolder)
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                Picker("Photo quality", selection: optionalString(\.photoQuality, default: "original")) {
                    Text("Original quality").tag("original")
                    Text("Storage optimized").tag("optimized")
                    Text("Small file").tag("compact")
                }
            } header: {
                Label("Photos", systemImage: "photo.fill")
            } footer: {
                providerDescription(draft.storage.photoProvider)
            }

            Section {
                storageDestinationPicker("Document destination", selection: $draft.storage.documentProvider)
                TextField("Document folder", text: $draft.storage.documentFolder)
                    .textInputAutocapitalization(.never)
                    .focused($focused)
                Picker("Scanned document format", selection: optionalString(\.scanFormat, default: "pdf")) {
                    Text("Searchable PDF").tag("pdf")
                    Text("Individual images").tag("images")
                }
            } header: {
                Label("Documents & Scans", systemImage: "doc.text.fill")
            } footer: {
                providerDescription(draft.storage.documentProvider)
            }

            Section("Organization") {
                Toggle("Create a folder for each account", isOn: optionalBool(\.useAccountFolders, default: true))
                Toggle("Keep originals on this device", isOn: optionalBool(\.preserveOriginals, default: true))
                Toggle("Upload using Wi-Fi only", isOn: optionalBool(\.wifiOnlyUploads, default: false))
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
                Text("Storage Connections")
            } footer: {
                Text("FireVault Cloud storage requires a Pro subscription. External services must be configured before they can receive uploads.")
            }
        }
        .nativeSettingsForm(title: "File Storage", focused: $focused) { settings.save(draft) }
    }

    private func storageDestinationPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("On this iPhone or iPad").tag("local")
            Text("FireVault Cloud").tag("firevault")
            Text("iCloud Drive").tag("icloud")
            Text("Microsoft OneDrive").tag("onedrive")
            Text("Microsoft SharePoint").tag("sharepoint")
            Text("WebDAV Server").tag("webdav")
        }
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
                .frame(width: 24)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(configured ? "Ready" : "Setup")
                .font(.caption.bold())
                .foregroundStyle(configured ? NativeShellPalette.green : .secondary)
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
                .onDelete { draft.categories.remove(atOffsets: $0) }
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
        settings.save(draft)
        store.configureCategoryRules(draft.categoryRules ?? [])
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
    static var readableContentTypes: [UTType] { [.json] }
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
    @State private var exportDocument = FireVaultVaultBackupDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var statusMessage = ""
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section {
                Label("\(store.accounts.count) accounts ready to protect", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(NativeShellPalette.green)
                Button("Export Vault Backup", systemImage: "square.and.arrow.up") {
                    do {
                        exportDocument = .init(data: try store.accountsBackupData())
                        errorMessage = ""
                        isExporting = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Merge From Backup", systemImage: "square.and.arrow.down") {
                    errorMessage = ""
                    isImporting = true
                }
            } header: {
                Text("Account Vault")
            } footer: {
                Text("A restore merge adds accounts that are missing. Existing accounts and their field history are never overwritten.")
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
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "FireVault-Accounts-\(Date().formatted(.iso8601.year().month().day()))"
        ) { result in
            switch result {
            case .success:
                statusMessage = "Vault backup exported successfully."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let merge = try store.mergeAccountsBackup(Data(contentsOf: url, options: .mappedIfSafe))
                statusMessage = "\(merge.added) accounts restored; \(merge.preserved) existing accounts preserved."
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
        initialAnalysis: FireVaultCSVAnalysis,
        onImport: @escaping (FireVaultCSVImportResult) -> Void
    ) {
        self.store = store
        self.data = data
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
                            Text("Updating the local vault and preserving existing field records…")
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
                        let result = store.applyCSVImport(analysis)
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
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Demo Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NativeManualView: View {
    var body: some View {
        List {
            Section("Getting Around") {
                manualItem("Nearby", "Review mapped accounts, select a site, call it, open its details, or begin a route.", "location.fill")
                manualItem("Accounts", "Search the vault by name, address, account ID, category, or saved information. Pull down to refresh.", "magnifyingglass")
                manualItem("Trip Log", "Record a workday, review detected stops, and create daily or weekly PDF reports.", "truck.box.fill")
                manualItem("Photo", "Capture field images with optional live account information and logo overlays.", "camera.fill")
            }

            Section("Accounts & Arrival Maps") {
                manualItem("Account workspace", "Keep service notes, photos and documents, equipment records, and arrival locations together.", "building.2")
                manualItem("Arrival Map", "Review parking and entrance points, edit saved locations, or start walking directions to a selected point.", "figure.walk")
                manualItem("Category rules", "Create IF/THEN rules, run them immediately, and automatically apply category labels to matching accounts.", "tag.fill")
                manualItem("CSV import", "Import account records, review the results, and map usable addresses before adding them to the vault.", "tablecells")
            }

            Section("Trip Log & Reports") {
                manualItem("Record", "Start at the beginning of the workday. Pause when tracking should stop temporarily and finish the session when the day is complete.", "record.circle")
                manualItem("Live details", "Choose Speed, Trip, Direction, Elevation, or GPS. Auto Rotate can cycle through any selected combination.", "gauge.with.dots.needle.50percent")
                manualItem("History", "Open a saved day to review route geometry, account visits, detected stops, and recorded times.", "clock.arrow.circlepath")
                manualItem("Reports", "Export clean daily or weekly PDFs with route maps, stop summaries, mileage, elapsed time, and elevation information.", "doc.richtext")
            }

            Section("Photos, Maps & Location") {
                manualItem("Photo overlays", "Resize and position the account-information overlay inside the 4:3 capture area. Configure the FireVault logo separately.", "camera.filters")
                manualItem("Map layers", "Choose Standard, Satellite, or Hybrid as the default layer under GPS & Maps.", "square.3.layers.3d")
                manualItem("GPS Diagnostics", "Inspect live coordinates, accuracy, elevation, speed, direction, source data, and rolling charts.", "waveform.path.ecg.rectangle")
                manualItem("Plus Codes", "Generate compact location codes from GPS coordinates for accounts and saved arrival points.", "plus.square.dashed")
            }

            Section("Storage, Privacy & Demonstration") {
                manualItem("File Storage", "Choose photo and document destinations, quality, folder organization, scan format, and upload behavior.", "folder.fill")
                manualItem("Privacy", "Configure application locking, background behavior, and app-switcher protection.", "lock.shield.fill")
                manualItem("Demo Mode", "Explore fictional accounts and seven days of sample history in a workspace isolated from live data.", "theatermasks.fill")
                manualItem("Reset Demo Data", "Restore the sample workspace without changing live accounts or authentication.", "arrow.counterclockwise")
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .navigationTitle("Help & User Manual")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func manualItem(_ title: String, _ detail: String, _ symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } icon: {
            Image(systemName: symbol).foregroundStyle(NativeShellPalette.blue)
        }
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
