//
//  FireVaultAccountReport.swift
//  FireVault
//
//  Account-focused report templates, media selection, PDF generation, and preview.
//

import SwiftUI
import UIKit
import PDFKit

enum FireVaultAccountReportTemplate: String, CaseIterable, Identifiable {
    case serviceCall = "Service Call"
    case photoDocumentation = "Photo Documentation"
    case deficiencySummary = "Deficiency Summary"
    case inspectionSummary = "Inspection Summary"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .serviceCall: "wrench.and.screwdriver.fill"
        case .photoDocumentation: "photo.on.rectangle.angled"
        case .deficiencySummary: "exclamationmark.triangle.fill"
        case .inspectionSummary: "checklist.checked"
        }
    }

    var summary: String {
        switch self {
        case .serviceCall:
            "Lead with the reason for the call, work performed, findings, and next steps."
        case .photoDocumentation:
            "Lead with selected photo evidence and concise factual captions."
        case .deficiencySummary:
            "Emphasize deficiencies, supporting evidence, and recommended corrective action."
        case .inspectionSummary:
            "Summarize inspection scope, completed work, findings, and supporting records."
        }
    }

    var defaultTitle: String { "\(rawValue) Report" }
}

struct FireVaultAccountReportConfiguration: Equatable {
    var template: FireVaultAccountReportTemplate
    var title: String
    var callSummary: String
    var workPerformed: String
    var findings: String
    var recommendations: String
    var includeTechnician: Bool
    var includeAccountContact: Bool
    var includeAccountNotes: Bool
    var includeEquipment: Bool
    var includeMediaDates: Bool
}

struct FireVaultGeneratedAccountReport: Identifiable {
    let id = UUID()
    let document: FireVaultWorkspaceDocument
    let url: URL
}

private enum FireVaultReportEvidencePicker: String, Identifiable {
    case photos
    case documents

    var id: String { rawValue }
}

struct FireVaultAccountReportBuilderView: View {
    let account: FireVaultWorkspaceAccount
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore

    @State private var template: FireVaultAccountReportTemplate
    @State private var reportTitle: String
    @State private var callSummary = ""
    @State private var workPerformed = ""
    @State private var findings = ""
    @State private var recommendations = ""
    @State private var includeTechnician: Bool
    @State private var includeAccountContact = true
    @State private var includeAccountNotes = false
    @State private var includeEquipment = false
    @State private var includeMediaDates = true
    @State private var selectedDocumentIDs: Set<String>
    @State private var evidencePicker: FireVaultReportEvidencePicker?
    @State private var showsTemplatePicker = false
    @State private var generatedReport: FireVaultGeneratedAccountReport?
    @State private var isGenerating = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: ReportField?

    private enum ReportField: Hashable {
        case title, callSummary, workPerformed, findings, recommendations
    }

    init(
        account: FireVaultWorkspaceAccount,
        store: FireVaultStore,
        settings: FireVaultNativeSettingsStore,
        preselectedPhotoIDs: Set<String> = []
    ) {
        self.account = account
        self.store = store
        self.settings = settings
        let initialTemplate: FireVaultAccountReportTemplate = preselectedPhotoIDs.isEmpty
            ? .serviceCall
            : .photoDocumentation
        _template = State(initialValue: initialTemplate)
        let savedTitle = settings.preferences.reports.title.trimmingCharacters(in: .whitespacesAndNewlines)
        _reportTitle = State(initialValue: savedTitle.isEmpty ? initialTemplate.defaultTitle : savedTitle)
        _includeTechnician = State(initialValue: settings.preferences.reports.includeTechnician)
        _selectedDocumentIDs = State(initialValue: preselectedPhotoIDs)
    }

    private var currentAccount: FireVaultWorkspaceAccount {
        store.accounts.first(where: { $0.id == account.id }) ?? account
    }

    private var photos: [FireVaultWorkspaceDocument] {
        currentAccount.documents.filter { $0.kind == "photo" }
    }

    private var supportingDocuments: [FireVaultWorkspaceDocument] {
        currentAccount.documents.filter {
            $0.kind != "photo" && $0.kind != "video" && $0.kind != "report"
        }
    }

    private var selectedDocuments: [FireVaultWorkspaceDocument] {
        currentAccount.documents.filter { selectedDocumentIDs.contains($0.id) }
    }

    private var hasFactualContent: Bool {
        [callSummary, workPerformed, findings, recommendations]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !selectedDocumentIDs.isEmpty
            || (includeAccountNotes && !currentAccount.notes.isEmpty)
            || (includeEquipment && !currentAccount.equipment.isEmpty)
    }

    private var canGenerate: Bool {
        !reportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && hasFactualContent
            && !isGenerating
    }

    var body: some View {
        Form {
            templateSection
            evidenceSection
            factsSection
            includedFactsSection
        }
        .fireVaultThemedCollection()
        .navigationTitle("Generate Report")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            generateBar
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .sheet(item: $generatedReport) { report in
            FireVaultGeneratedReportPreview(report: report)
        }
        .sheet(isPresented: $showsTemplatePicker) {
            NavigationStack {
                FireVaultReportTemplatePickerView(selectedTemplate: template) { option in
                    selectTemplate(option)
                    showsTemplatePicker = false
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $evidencePicker) { picker in
            NavigationStack {
                FireVaultReportEvidencePickerView(
                    kind: picker,
                    documents: picker == .photos ? photos : supportingDocuments,
                    selectedDocumentIDs: $selectedDocumentIDs
                )
            }
        }
        .alert("Report Not Generated", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

    private var templateSection: some View {
        Section {
            Button {
                showsTemplatePicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: template.symbol)
                        .font(.headline)
                        .foregroundStyle(NativeShellPalette.red)
                        .frame(width: 36, height: 36)
                        .background(
                            NativeShellPalette.red.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    Text(template.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Report template")
            .accessibilityValue(template.rawValue)

            Label(template.summary, systemImage: template.symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Report title", text: $reportTitle)
                .focused($focusedField, equals: .title)
        } header: {
            Text("Template")
        } footer: {
            Text("Templates set the report emphasis. You can still customize every factual section below.")
        }
    }

    private var evidenceSection: some View {
        Section {
            evidenceButton(
                title: "Choose Photos",
                subtitle: photos.isEmpty
                    ? "No saved photos"
                    : selectionSummary(for: photos, itemName: "photo"),
                symbol: "photo.on.rectangle.angled",
                tint: NativeShellPalette.purple,
                picker: .photos
            )
            evidenceButton(
                title: "Choose Files & Scans",
                subtitle: supportingDocuments.isEmpty
                    ? "No saved files or scans"
                    : selectionSummary(for: supportingDocuments, itemName: "file or scan"),
                symbol: "doc.viewfinder",
                tint: NativeShellPalette.blue,
                picker: .documents
            )
        } header: {
            Text("Report Evidence")
        } footer: {
            Text("Photos become evidence pages. Selected PDF scans are appended to the finished report.")
        }
    }

    private func evidenceButton(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        picker: FireVaultReportEvidencePicker
    ) -> some View {
        Button {
            evidencePicker = picker
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectionSummary(
        for documents: [FireVaultWorkspaceDocument],
        itemName: String
    ) -> String {
        let selectedCount = documents.filter { selectedDocumentIDs.contains($0.id) }.count
        guard selectedCount > 0 else {
            return "None selected • \(documents.count) available"
        }
        return "\(selectedCount) \(itemName)\(selectedCount == 1 ? "" : "s") selected"
    }

    private func selectTemplate(_ option: FireVaultAccountReportTemplate) {
        let oldTemplate = template
        let trimmed = reportTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        template = option
        if trimmed.isEmpty || trimmed == oldTemplate.defaultTitle {
            reportTitle = option.defaultTitle
        }
    }

    private var factsSection: some View {
        Section("Facts of the Call") {
            reportTextField(
                "Reason for call and site conditions",
                text: $callSummary,
                field: .callSummary
            )
            reportTextField(
                "Work performed",
                text: $workPerformed,
                field: .workPerformed
            )
            reportTextField(
                "Findings or deficiencies",
                text: $findings,
                field: .findings
            )
            reportTextField(
                "Recommendations and follow-up",
                text: $recommendations,
                field: .recommendations
            )
        }
    }

    private var includedFactsSection: some View {
        Section("Report Content") {
            Toggle("Technician information", isOn: $includeTechnician)
            Toggle("Account contact information", isOn: $includeAccountContact)
            Toggle("Saved account notes", isOn: $includeAccountNotes)
                .disabled(currentAccount.notes.isEmpty)
            Toggle("Equipment list", isOn: $includeEquipment)
                .disabled(currentAccount.equipment.isEmpty)
            Toggle("Photo and document dates", isOn: $includeMediaDates)
        }
    }

    private func reportTextField(
        _ prompt: String,
        text: Binding<String>,
        field: ReportField
    ) -> some View {
        TextField(prompt, text: text, axis: .vertical)
            .lineLimit(3...8)
            .focused($focusedField, equals: field)
    }

    private var generateBar: some View {
        VStack(spacing: 7) {
            if !hasFactualContent {
                Text("Add call facts or select at least one photo or document.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                generateReport()
            } label: {
                HStack {
                    if isGenerating { ProgressView().tint(.white) }
                    Label(isGenerating ? "Generating PDF…" : "Generate PDF Report", systemImage: "doc.badge.plus")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(NativeShellPalette.red)
            .disabled(!canGenerate)
            .accessibilityIdentifier("generate-account-report")
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private func generateReport() {
        guard canGenerate else { return }
        isGenerating = true
        defer { isGenerating = false }

        let configuration = FireVaultAccountReportConfiguration(
            template: template,
            title: reportTitle,
            callSummary: callSummary,
            workPerformed: workPerformed,
            findings: findings,
            recommendations: recommendations,
            includeTechnician: includeTechnician,
            includeAccountContact: includeAccountContact,
            includeAccountNotes: includeAccountNotes,
            includeEquipment: includeEquipment,
            includeMediaDates: includeMediaDates
        )
        let urls = Dictionary(uniqueKeysWithValues: selectedDocuments.compactMap { document in
            store.mediaURL(accountID: account.id, documentID: document.id).map { (document.id, $0) }
        })

        do {
            let data = FireVaultAccountReportPDFRenderer.render(
                account: currentAccount,
                configuration: configuration,
                technician: settings.preferences.technician,
                documents: selectedDocuments,
                mediaURLs: urls,
                generatedAt: Date()
            )
            let document = try store.attachGeneratedReport(
                data,
                title: reportTitle,
                templateName: template.rawValue,
                to: account.id
            )
            guard let url = store.mediaURL(accountID: account.id, documentID: document.id) else {
                throw FireVaultMediaError.storageUnavailable
            }
            generatedReport = .init(document: document, url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FireVaultReportTemplatePickerView: View {
    let selectedTemplate: FireVaultAccountReportTemplate
    let onSelect: (FireVaultAccountReportTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(FireVaultAccountReportTemplate.allCases) { option in
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.symbol)
                            .font(.headline)
                            .foregroundStyle(NativeShellPalette.blue)
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.rawValue)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Text(option.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: selectedTemplate == option ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selectedTemplate == option ? NativeShellPalette.red : .secondary)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fireVaultThemedCollection()
        .navigationTitle("Choose Report Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

private struct FireVaultReportEvidencePickerView: View {
    let kind: FireVaultReportEvidencePicker
    let documents: [FireVaultWorkspaceDocument]
    @Binding var selectedDocumentIDs: Set<String>
    @Environment(\.dismiss) private var dismiss

    private var selectedCount: Int {
        documents.filter { selectedDocumentIDs.contains($0.id) }.count
    }

    private var title: String {
        kind == .photos ? "Choose Photos" : "Choose Files & Scans"
    }

    var body: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView(
                    kind == .photos ? "No Saved Photos" : "No Saved Files or Scans",
                    systemImage: kind == .photos ? "photo.badge.plus" : "doc.badge.plus",
                    description: Text(
                        kind == .photos
                            ? "Capture or save account photos before generating the report."
                            : "Add a file or scan a document before generating the report."
                    )
                )
            } else {
                List {
                    Section {
                        ForEach(documents) { document in
                            Button {
                                toggle(document.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: symbol(for: document))
                                        .font(.headline)
                                        .foregroundStyle(kind == .photos ? NativeShellPalette.purple : NativeShellPalette.blue)
                                        .frame(width: 38, height: 38)
                                        .background(
                                            (kind == .photos ? NativeShellPalette.purple : NativeShellPalette.blue).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(document.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(FireVaultAccountTimestamp.display(legacy: document.date, timestamp: document.updatedAt))
                                            .font(.caption.weight(.medium).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: selectedDocumentIDs.contains(document.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedDocumentIDs.contains(document.id) ? NativeShellPalette.red : .secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(selectedCount) selected")
                    }
                }
                .fireVaultThemedCollection()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Select All", systemImage: "checkmark.circle") {
                        selectedDocumentIDs.formUnion(documents.map(\.id))
                    }
                    Button("Clear Selection", systemImage: "xmark.circle") {
                        selectedDocumentIDs.subtract(documents.map(\.id))
                    }
                    .disabled(selectedCount == 0)
                } label: {
                    Text("Select")
                }
                .disabled(documents.isEmpty)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
    }

    private func toggle(_ documentID: String) {
        if selectedDocumentIDs.contains(documentID) {
            selectedDocumentIDs.remove(documentID)
        } else {
            selectedDocumentIDs.insert(documentID)
        }
    }

    private func symbol(for document: FireVaultWorkspaceDocument) -> String {
        if kind == .photos { return "photo.fill" }
        return document.kind == "scan" ? "doc.viewfinder" : "doc.fill"
    }
}

private struct FireVaultGeneratedReportPreview: View {
    let report: FireVaultGeneratedAccountReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FireVaultPDFView(url: report.url)
                .background(NativeShellPalette.background)
                .navigationTitle("Report Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: report.url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Label("Saved to \(report.document.title)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NativeShellPalette.green)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(.regularMaterial)
                }
        }
    }
}

struct FireVaultStoredPDFDetailView: View {
    let document: FireVaultWorkspaceDocument
    let url: URL

    var body: some View {
        FireVaultPDFView(url: url)
            .background(NativeShellPalette.background)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                }
            }
    }
}

struct FireVaultPDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

enum FireVaultAccountReportPDFRenderer {
    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let contentBounds = CGRect(x: 42, y: 82, width: 528, height: 650)
    private static let navy = UIColor(red: 0.04, green: 0.16, blue: 0.27, alpha: 1)
    private static let red = UIColor(red: 0.80, green: 0.10, blue: 0.15, alpha: 1)
    private static let blue = UIColor(red: 0.05, green: 0.31, blue: 0.48, alpha: 1)
    private static let pale = UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1)
    private static let line = UIColor(white: 0.84, alpha: 1)

    static func render(
        account: FireVaultWorkspaceAccount,
        configuration: FireVaultAccountReportConfiguration,
        technician: FireVaultTechnicianPreferences,
        documents: [FireVaultWorkspaceDocument],
        mediaURLs: [String: URL],
        generatedAt: Date
    ) -> Data {
        let photos = documents.filter { $0.kind == "photo" }
        let supportingDocuments = documents.filter { $0.kind != "photo" }
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        return renderer.pdfData { context in
            var pageNumber = 0
            var y = contentBounds.minY

            func beginPage(section: String? = nil) {
                context.beginPage()
                pageNumber += 1
                drawPageHeader(
                    title: configuration.title,
                    template: configuration.template.rawValue,
                    account: account,
                    section: section,
                    generatedAt: generatedAt,
                    pageNumber: pageNumber
                )
                y = contentBounds.minY
            }

            func ensure(_ requiredHeight: CGFloat, continuation: String? = nil) {
                if y + requiredHeight > contentBounds.maxY {
                    beginPage(section: continuation ?? "Continued")
                }
            }

            func section(_ title: String, body: String) {
                let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return }
                let bodyHeight = textHeight(normalized, font: .systemFont(ofSize: 10), width: contentBounds.width - 24)
                ensure(bodyHeight + 48, continuation: title)
                y = drawSection(title, body: normalized, y: y)
                y += 12
            }

            beginPage()
            y = drawAccountSummary(
                account: account,
                configuration: configuration,
                technician: technician,
                generatedAt: generatedAt,
                y: y
            )
            y += 16

            let orderedSections: [(String, String)] = switch configuration.template {
            case .serviceCall:
                [
                    ("CALL SUMMARY", configuration.callSummary),
                    ("WORK PERFORMED", configuration.workPerformed),
                    ("FINDINGS / DEFICIENCIES", configuration.findings),
                    ("RECOMMENDATIONS / FOLLOW-UP", configuration.recommendations)
                ]
            case .photoDocumentation:
                [
                    ("PHOTO DOCUMENTATION SUMMARY", configuration.callSummary),
                    ("OBSERVATIONS", configuration.findings),
                    ("WORK PERFORMED", configuration.workPerformed),
                    ("FOLLOW-UP", configuration.recommendations)
                ]
            case .deficiencySummary:
                [
                    ("DEFICIENCIES", configuration.findings),
                    ("RECOMMENDED CORRECTIVE ACTION", configuration.recommendations),
                    ("CALL CONTEXT", configuration.callSummary),
                    ("WORK PERFORMED", configuration.workPerformed)
                ]
            case .inspectionSummary:
                [
                    ("INSPECTION SCOPE", configuration.callSummary),
                    ("COMPLETED WORK", configuration.workPerformed),
                    ("INSPECTION FINDINGS", configuration.findings),
                    ("RECOMMENDATIONS", configuration.recommendations)
                ]
            }
            for (title, body) in orderedSections { section(title, body: body) }

            if configuration.includeAccountNotes, !account.notes.isEmpty {
                let notes = account.notes.map { "• \($0.title): \($0.text)" }.joined(separator: "\n")
                section("SAVED ACCOUNT NOTES", body: notes)
            }

            if configuration.includeEquipment, !account.equipment.isEmpty {
                let equipment = account.equipment.map {
                    ["• \($0.title)", $0.subtitle, $0.deviceAddress].filter { !$0.isEmpty }.joined(separator: " - ")
                }.joined(separator: "\n")
                section("EQUIPMENT", body: equipment)
            }

            if !documents.isEmpty {
                let indexText = documents.map { document in
                    let date = configuration.includeMediaDates
                        ? " - \(FireVaultAccountTimestamp.display(legacy: document.date, timestamp: document.updatedAt))"
                        : ""
                    return "• \(document.title)\(date)"
                }.joined(separator: "\n")
                section("INCLUDED EVIDENCE AND DOCUMENTS", body: indexText)
            }

            for (index, photo) in photos.enumerated() {
                guard let url = mediaURLs[photo.id], let image = UIImage(contentsOfFile: url.path) else { continue }
                context.beginPage()
                pageNumber += 1
                drawPhotoEvidence(
                    image: image,
                    document: photo,
                    index: index + 1,
                    count: photos.count,
                    includeDate: configuration.includeMediaDates
                )
                drawPageHeader(
                    title: configuration.title,
                    template: configuration.template.rawValue,
                    account: account,
                    section: "Photo Evidence \(index + 1) of \(photos.count)",
                    generatedAt: generatedAt,
                    pageNumber: pageNumber
                )
            }

            for document in supportingDocuments {
                guard let url = mediaURLs[document.id], url.pathExtension.lowercased() == "pdf",
                      let source = PDFDocument(url: url) else { continue }
                for pageIndex in 0..<source.pageCount {
                    guard let page = source.page(at: pageIndex) else { continue }
                    context.beginPage()
                    pageNumber += 1
                    drawPDFPage(page, in: context.cgContext)
                    drawPageHeader(
                        title: configuration.title,
                        template: configuration.template.rawValue,
                        account: account,
                        section: "Source Document - \(document.title) - Page \(pageIndex + 1)",
                        generatedAt: generatedAt,
                        pageNumber: pageNumber
                    )
                }
            }
        }
    }

    private static func drawPageHeader(
        title: String,
        template: String,
        account: FireVaultWorkspaceAccount,
        section: String?,
        generatedAt: Date,
        pageNumber: Int
    ) {
        red.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: 11, height: pageBounds.height)).fill()
        drawText("FIRE", font: .systemFont(ofSize: 16, weight: .bold), color: red, rect: CGRect(x: 42, y: 26, width: 38, height: 22))
        drawText("VAULT PRO", font: .systemFont(ofSize: 16, weight: .bold), color: navy, rect: CGRect(x: 80, y: 26, width: 110, height: 22))
        drawText(template.uppercased(), font: .systemFont(ofSize: 7.5, weight: .semibold), color: blue, rect: CGRect(x: 42, y: 50, width: 220, height: 12))
        drawRightText(
            generatedAt.formatted(date: .abbreviated, time: .shortened),
            font: .monospacedSystemFont(ofSize: 8, weight: .regular),
            color: .darkGray,
            rect: CGRect(x: 330, y: 29, width: 240, height: 14)
        )
        line.setFill()
        UIBezierPath(rect: CGRect(x: 42, y: 68, width: 528, height: 1)).fill()
        if let section {
            drawRightText(section, font: .systemFont(ofSize: 8, weight: .semibold), color: navy, rect: CGRect(x: 270, y: 50, width: 300, height: 12))
        }
        drawText(
            "\(account.name)  •  \(title)",
            font: .systemFont(ofSize: 7.5, weight: .regular),
            color: .darkGray,
            rect: CGRect(x: 42, y: 751, width: 430, height: 12)
        )
        drawRightText("PAGE \(pageNumber)", font: .monospacedSystemFont(ofSize: 7.5, weight: .semibold), color: navy, rect: CGRect(x: 480, y: 751, width: 90, height: 12))
    }

    private static func drawAccountSummary(
        account: FireVaultWorkspaceAccount,
        configuration: FireVaultAccountReportConfiguration,
        technician: FireVaultTechnicianPreferences,
        generatedAt: Date,
        y: CGFloat
    ) -> CGFloat {
        let height: CGFloat = configuration.includeTechnician ? 142 : 114
        pale.setFill()
        UIBezierPath(roundedRect: CGRect(x: 42, y: y, width: 528, height: height), cornerRadius: 14).fill()
        drawText(configuration.title, font: .systemFont(ofSize: 22, weight: .bold), color: navy, rect: CGRect(x: 58, y: y + 15, width: 496, height: 31))
        drawText(account.name, font: .systemFont(ofSize: 13, weight: .semibold), color: red, rect: CGRect(x: 58, y: y + 49, width: 496, height: 19))

        var detail = account.address
        if configuration.includeAccountContact, !account.phone.isEmpty {
            detail += detail.isEmpty ? account.phone : "  •  \(account.phone)"
        }
        if !account.accountId.isEmpty {
            detail += detail.isEmpty ? "Account ID: \(account.accountId)" : "  •  Account ID: \(account.accountId)"
        }
        drawText(detail, font: .systemFont(ofSize: 9.5), color: .darkGray, rect: CGRect(x: 58, y: y + 72, width: 496, height: 28))

        if configuration.includeTechnician {
            let technicianLine = [technician.name, technician.company, technician.license]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "  •  ")
            drawText(
                technicianLine.isEmpty ? "Technician: Not specified" : "Technician: \(technicianLine)",
                font: .systemFont(ofSize: 9, weight: .medium),
                color: blue,
                rect: CGRect(x: 58, y: y + 108, width: 496, height: 18)
            )
        }
        return y + height
    }

    private static func drawSection(_ title: String, body: String, y: CGFloat) -> CGFloat {
        drawText(title, font: .systemFont(ofSize: 9, weight: .bold), color: red, rect: CGRect(x: 42, y: y, width: 528, height: 16))
        let bodyHeight = textHeight(body, font: .systemFont(ofSize: 10), width: 504)
        drawText(body, font: .systemFont(ofSize: 10), color: navy, rect: CGRect(x: 54, y: y + 21, width: 504, height: bodyHeight + 4))
        line.setFill()
        UIBezierPath(rect: CGRect(x: 42, y: y + bodyHeight + 31, width: 528, height: 1)).fill()
        return y + bodyHeight + 32
    }

    private static func drawPhotoEvidence(
        image: UIImage,
        document: FireVaultWorkspaceDocument,
        index: Int,
        count: Int,
        includeDate: Bool
    ) {
        let target = CGRect(x: 42, y: 102, width: 528, height: 570)
        UIColor(white: 0.94, alpha: 1).setFill()
        UIBezierPath(roundedRect: target, cornerRadius: 12).fill()
        image.draw(in: aspectFit(image.size, inside: target.insetBy(dx: 10, dy: 10)))
        drawText("PHOTO \(index) OF \(count)", font: .systemFont(ofSize: 8, weight: .bold), color: red, rect: CGRect(x: 42, y: 690, width: 120, height: 14))
        let date = includeDate
            ? FireVaultAccountTimestamp.display(legacy: document.date, timestamp: document.updatedAt)
            : ""
        drawText(
            [document.title, document.subtitle, date].filter { !$0.isEmpty }.joined(separator: "  •  "),
            font: .systemFont(ofSize: 9.5),
            color: navy,
            rect: CGRect(x: 42, y: 707, width: 528, height: 28)
        )
    }

    private static func drawPDFPage(_ page: PDFPage, in context: CGContext) {
        let sourceBounds = page.bounds(for: .mediaBox)
        let target = CGRect(x: 42, y: 88, width: 528, height: 646)
        let fitted = aspectFit(sourceBounds.size, inside: target)
        context.saveGState()
        context.translateBy(x: fitted.minX, y: fitted.maxY)
        let scale = min(fitted.width / sourceBounds.width, fitted.height / sourceBounds.height)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -sourceBounds.minX, y: -sourceBounds.minY)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
        line.setStroke()
        UIBezierPath(rect: fitted).stroke()
    }

    private static func aspectFit(_ size: CGSize, inside bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        ceil(NSString(string: text).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height)
    }

    private static func drawText(_ text: String, font: UIFont, color: UIColor, rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        NSString(string: text).draw(
            in: rect,
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        )
    }

    private static func drawRightText(_ text: String, font: UIFont, color: UIColor, rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byTruncatingTail
        NSString(string: text).draw(
            in: rect,
            withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        )
    }
}
