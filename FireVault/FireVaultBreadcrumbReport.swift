//
//  FireVaultBreadcrumbReport.swift
//  FireVault
//
//  Native Breadcrumbs daily reporting and export for Build 1.08.04.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FireVaultBreadcrumbReport: Equatable {
    enum VisitClassification: String, Equatable {
        case account = "Account Visit"
        case unassigned = "Needs Review"
        case personal = "Personal Stop"
    }

    struct Visit: Identifiable, Equatable {
        let id: UUID
        let sequence: Int
        let arrival: Date
        let departure: Date?
        let duration: TimeInterval
        let classification: VisitClassification
        let accountName: String
        let accountAddress: String
        let accountID: String
        let technicianNote: String
        let latitude: Double?
        let longitude: Double?

        var timeText: String {
            let start = arrival.formatted(date: .omitted, time: .shortened)
            guard let departure else { return "\(start)–In progress" }
            return "\(start)–\(departure.formatted(date: .omitted, time: .shortened))"
        }

        var durationText: String {
            FireVaultBreadcrumbReport.durationText(duration)
        }

        var title: String {
            switch classification {
            case .account:
                accountName
            case .unassigned:
                "Unrecognized Stop"
            case .personal:
                "Personal Stop"
            }
        }

        var detailText: String {
            switch classification {
            case .account:
                [accountAddress, accountID.isEmpty ? "" : "Account ID: \(accountID)"]
                    .filter { !$0.isEmpty }
                    .joined(separator: " • ")
            case .unassigned:
                "Review and assign this stop before using the report as a final work record."
            case .personal:
                "Private location and notes redacted."
            }
        }

        var coordinateText: String? {
            guard let latitude, let longitude else { return nil }
            return "\(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))"
        }
    }

    let dayID: UUID
    let startedAt: Date
    let endedAt: Date?
    let generatedAt: Date
    let technicianName: String
    let companyName: String
    let totalDistanceMeters: Double
    let elapsedTime: TimeInterval
    let visits: [Visit]

    init(
        day: FireVaultBreadcrumbDay,
        technicianName: String,
        companyName: String,
        includeCoordinates: Bool,
        generatedAt: Date = Date()
    ) {
        dayID = day.id
        startedAt = day.startedAt
        endedAt = day.endedAt
        self.generatedAt = generatedAt
        self.technicianName = technicianName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        totalDistanceMeters = day.totalDistanceMeters
        elapsedTime = max(0, (day.endedAt ?? generatedAt).timeIntervalSince(day.startedAt))
        visits = day.stops
            .sorted { $0.arrival < $1.arrival }
            .enumerated()
            .map { offset, stop in
                let classification: VisitClassification
                if stop.isPersonalStop {
                    classification = .personal
                } else if stop.accountID != nil || stop.accountName != nil {
                    classification = .account
                } else {
                    classification = .unassigned
                }

                let redactsPrivateDetails = classification == .personal
                return Visit(
                    id: stop.id,
                    sequence: offset + 1,
                    arrival: stop.arrival,
                    departure: stop.departure,
                    duration: max(
                        0,
                        (stop.departure ?? generatedAt).timeIntervalSince(stop.arrival)
                    ),
                    classification: classification,
                    accountName: redactsPrivateDetails ? "" : (stop.accountName ?? ""),
                    accountAddress: redactsPrivateDetails ? "" : (stop.accountAddress ?? ""),
                    accountID: redactsPrivateDetails ? "" : (stop.accountID ?? ""),
                    technicianNote: redactsPrivateDetails ? "" : (stop.technicianNote ?? ""),
                    latitude: includeCoordinates && !redactsPrivateDetails ? stop.latitude : nil,
                    longitude: includeCoordinates && !redactsPrivateDetails ? stop.longitude : nil
                )
            }
    }

    var accountVisitCount: Int {
        visits.lazy.filter { $0.classification == .account }.count
    }

    var unassignedVisitCount: Int {
        visits.lazy.filter { $0.classification == .unassigned }.count
    }

    var personalStopCount: Int {
        visits.lazy.filter { $0.classification == .personal }.count
    }

    var dateText: String {
        startedAt.formatted(date: .long, time: .omitted)
    }

    var workdayTimeText: String {
        let start = startedAt.formatted(date: .omitted, time: .shortened)
        guard let endedAt else { return "\(start)–In progress" }
        return "\(start)–\(endedAt.formatted(date: .omitted, time: .shortened))"
    }

    var distanceText: String {
        Self.distanceText(totalDistanceMeters)
    }

    var elapsedText: String {
        Self.durationText(elapsedTime)
    }

    var filenameStem: String {
        let day = startedAt.formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
        )
        return "FireVault-Breadcrumbs-\(day)"
    }

    var plainText: String {
        var lines = [
            "FIREVAULT BREADCRUMBS DAILY REPORT",
            dateText,
            companyName.isEmpty ? "" : companyName,
            technicianName.isEmpty ? "Technician: Not configured" : "Technician: \(technicianName)",
            "Workday: \(workdayTimeText)",
            "Distance: \(distanceText) • Elapsed: \(elapsedText)",
            "Account visits: \(accountVisitCount) • Needs review: \(unassignedVisitCount) • Personal: \(personalStopCount)",
            ""
        ]

        for visit in visits {
            lines.append("\(visit.sequence). \(visit.title)")
            lines.append("\(visit.timeText) • \(visit.durationText) • \(visit.classification.rawValue)")
            if !visit.detailText.isEmpty { lines.append(visit.detailText) }
            if !visit.technicianNote.isEmpty {
                lines.append("Visit note: \(visit.technicianNote)")
            }
            if let coordinateText = visit.coordinateText {
                lines.append("Coordinates: \(coordinateText)")
            }
            lines.append("")
        }

        if visits.isEmpty {
            lines.append("No stops were recorded.")
        }
        lines.append("Generated by FireVault \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
        return lines.joined(separator: "\n")
    }

    var csvData: Data {
        var rows = [[
            "Sequence",
            "Date",
            "Arrival",
            "Departure",
            "Duration Minutes",
            "Classification",
            "Account Name",
            "Address",
            "Account ID",
            "Technician Note",
            "Latitude",
            "Longitude"
        ]]

        for visit in visits {
            rows.append([
                "\(visit.sequence)",
                Self.isoDate(visit.arrival),
                Self.isoTime(visit.arrival),
                visit.departure.map { Self.isoTime($0) } ?? "",
                "\(Int(visit.duration / 60))",
                visit.classification.rawValue,
                visit.accountName,
                visit.accountAddress,
                visit.accountID,
                visit.technicianNote,
                visit.latitude.map { String(format: "%.6f", $0) } ?? "",
                visit.longitude.map { String(format: "%.6f", $0) } ?? ""
            ])
        }

        let source = rows
            .map { row in row.map { Self.csvCell($0) }.joined(separator: ",") }
            .joined(separator: "\r\n")
            + "\r\n"
        return Data(source.utf8)
    }

    var pdfData: Data {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)

        return renderer.pdfData { context in
            var pageNumber = 0
            var y: CGFloat = 0

            func drawText(
                _ text: String,
                font: UIFont,
                color: UIColor = .black,
                x: CGFloat = 48,
                width: CGFloat = 516,
                spacing: CGFloat = 2
            ) -> CGFloat {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = spacing
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                let bounds = NSString(string: text).boundingRect(
                    with: CGSize(width: width, height: 1_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                let height = ceil(bounds.height)
                NSString(string: text).draw(
                    in: CGRect(x: x, y: y, width: width, height: height),
                    withAttributes: attributes
                )
                return height
            }

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                UIColor(red: 0.12, green: 0.02, blue: 0.03, alpha: 1).setFill()
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 612, height: 72))
                y = 22
                _ = drawText(
                    "FIREVAULT",
                    font: .systemFont(ofSize: 25, weight: .black),
                    color: .white
                )
                y = 49
                _ = drawText(
                    "BREADCRUMBS DAILY REPORT",
                    font: .systemFont(ofSize: 9, weight: .bold),
                    color: UIColor.white.withAlphaComponent(0.75)
                )
                y = 750
                _ = drawText(
                    "Generated by FireVault  •  Page \(pageNumber)",
                    font: .systemFont(ofSize: 8),
                    color: .darkGray
                )
                y = 94
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > 730 {
                    beginPage()
                }
            }

            beginPage()
            y += drawText(
                dateText,
                font: .systemFont(ofSize: 22, weight: .bold)
            ) + 5
            if !companyName.isEmpty {
                y += drawText(companyName, font: .systemFont(ofSize: 11, weight: .semibold)) + 2
            }
            y += drawText(
                technicianName.isEmpty ? "Technician: Not configured" : "Technician: \(technicianName)",
                font: .systemFont(ofSize: 11),
                color: .darkGray
            ) + 16

            let summary = [
                "WORKDAY  \(workdayTimeText)",
                "DISTANCE  \(distanceText)",
                "ELAPSED  \(elapsedText)",
                "ACCOUNT VISITS  \(accountVisitCount)",
                "NEEDS REVIEW  \(unassignedVisitCount)",
                "PERSONAL  \(personalStopCount)"
            ].joined(separator: "    ")
            y += drawText(
                summary,
                font: .monospacedSystemFont(ofSize: 10, weight: .semibold),
                color: UIColor(red: 0.45, green: 0.04, blue: 0.06, alpha: 1)
            ) + 22
            y += drawText("VISIT LOG", font: .systemFont(ofSize: 11, weight: .bold)) + 8

            if visits.isEmpty {
                y += drawText(
                    "No stops were recorded.",
                    font: .systemFont(ofSize: 11),
                    color: .darkGray
                )
            }

            for visit in visits {
                var details = "\(visit.timeText)  •  \(visit.durationText)  •  \(visit.classification.rawValue)"
                if !visit.detailText.isEmpty {
                    details += "\n\(visit.detailText)"
                }
                if !visit.technicianNote.isEmpty {
                    details += "\nVisit note: \(visit.technicianNote)"
                }
                if let coordinateText = visit.coordinateText {
                    details += "\nCoordinates: \(coordinateText)"
                }

                let estimatedHeight = CGFloat(58 + details.count / 75 * 14)
                ensureSpace(estimatedHeight)
                UIColor(white: 0.92, alpha: 1).setStroke()
                context.cgContext.setLineWidth(0.75)
                context.cgContext.move(to: CGPoint(x: 48, y: y))
                context.cgContext.addLine(to: CGPoint(x: 564, y: y))
                context.cgContext.strokePath()
                y += 10
                y += drawText(
                    "\(visit.sequence). \(visit.title)",
                    font: .systemFont(ofSize: 13, weight: .bold)
                ) + 4
                y += drawText(
                    details,
                    font: .systemFont(ofSize: 9.5),
                    color: .darkGray
                ) + 14
            }
        }
    }

    private static func csvCell(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func isoDate(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private static func isoTime(_ date: Date) -> String {
        date.formatted(
            .iso8601
                .time(includingFractionalSeconds: false)
                .timeSeparator(.colon)
        )
    }

    private static func distanceText(_ meters: Double) -> String {
        let miles = meters / 1_609.344
        return "\(miles.formatted(.number.precision(.fractionLength(miles < 10 ? 1 : 0)))) mi"
    }

    private static func durationText(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

struct FireVaultBreadcrumbReportView: View {
    let report: FireVaultBreadcrumbReport

    @Environment(\.dismiss) private var dismiss
    @State private var exportDocument: FireVaultBreadcrumbExportDocument?
    @State private var exportType: UTType = .pdf
    @State private var showsExporter = false
    @State private var exportStatus: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    reportHeader
                    reportSummary
                    visitPreview
                    exportActions
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(NativeShellPalette.background)
            .navigationTitle("Daily Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .fileExporter(
                isPresented: $showsExporter,
                document: exportDocument,
                contentType: exportType,
                defaultFilename: report.filenameStem
            ) { result in
                switch result {
                case .success:
                    exportStatus = "Report exported successfully."
                case .failure(let error):
                    exportStatus = "The report could not be exported. \(error.localizedDescription)"
                }
            }
            .alert(
                "Report Export",
                isPresented: .init(
                    get: { exportStatus != nil },
                    set: { if !$0 { exportStatus = nil } }
                )
            ) {
                Button("OK") {
                    exportStatus = nil
                }
            } message: {
                Text(exportStatus ?? "")
            }
        }
        .tint(NativeShellPalette.blue)
        .preferredColorScheme(.dark)
    }

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FIREVAULT")
                .font(.caption.bold())
                .tracking(1.5)
                .foregroundStyle(NativeShellPalette.red)
            Text(report.dateText)
                .font(.title.bold())
                .foregroundStyle(.white)
            if !report.companyName.isEmpty {
                Text(report.companyName)
                    .font(.subheadline.weight(.semibold))
            }
            Text(
                report.technicianName.isEmpty
                    ? "Technician not configured"
                    : report.technicianName
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var reportSummary: some View {
        NativeShellCard {
            VStack(spacing: 14) {
                HStack {
                    BreadcrumbReportMetric(title: "MILES", value: report.distanceText)
                    BreadcrumbReportMetric(title: "ELAPSED", value: report.elapsedText)
                    BreadcrumbReportMetric(title: "VISITS", value: "\(report.accountVisitCount)")
                }
                Divider()
                HStack {
                    Label(report.workdayTimeText, systemImage: "clock")
                    Spacer()
                    if report.endedAt == nil {
                        Text("IN PROGRESS")
                            .font(.caption2.bold())
                            .foregroundStyle(NativeShellPalette.green)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if report.unassignedVisitCount > 0 {
                    Label(
                        "\(report.unassignedVisitCount) stop\(report.unassignedVisitCount == 1 ? "" : "s") need review before this is a final work record.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(NativeShellPalette.amber)
                }
            }
        }
        .accessibilityIdentifier("breadcrumbs-report-summary")
    }

    private var visitPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VISIT LOG")
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.secondary)

            if report.visits.isEmpty {
                NativeShellCard {
                    ContentUnavailableView(
                        "No Stops Recorded",
                        systemImage: "mappin.slash",
                        description: Text("This workday does not contain any detected stops.")
                    )
                }
            } else {
                ForEach(report.visits) { visit in
                    NativeShellCard {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(visit.sequence). \(visit.title)")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(visit.classification.rawValue.uppercased())
                                    .font(.caption2.bold())
                                    .foregroundStyle(classificationTint(visit.classification))
                            }
                            Text("\(visit.timeText) • \(visit.durationText)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(visit.detailText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if !visit.technicianNote.isEmpty {
                                Label(visit.technicianNote, systemImage: "note.text")
                                    .font(.footnote)
                            }
                            if let coordinateText = visit.coordinateText {
                                Label(coordinateText, systemImage: "location")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var exportActions: some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("SHARE & EXPORT", systemImage: "square.and.arrow.up")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(.secondary)

                ShareLink(
                    item: report.plainText,
                    subject: Text("FireVault Breadcrumbs — \(report.dateText)"),
                    preview: SharePreview(
                        "FireVault Breadcrumbs — \(report.dateText)",
                        image: Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    )
                ) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack {
                    Button("Export PDF", systemImage: "doc.richtext") {
                        beginExport(data: report.pdfData, type: .pdf)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button("Export CSV", systemImage: "tablecells") {
                        beginExport(data: report.csvData, type: .commaSeparatedText)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }

                Text("Personal stops always redact their location, account information, and notes in every shared format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("breadcrumbs-report-export")
    }

    private func classificationTint(
        _ classification: FireVaultBreadcrumbReport.VisitClassification
    ) -> Color {
        switch classification {
        case .account: NativeShellPalette.blue
        case .unassigned: NativeShellPalette.amber
        case .personal: .secondary
        }
    }

    private func beginExport(data: Data, type: UTType) {
        exportDocument = .init(data: data)
        exportType = type
        showsExporter = true
    }
}

private struct BreadcrumbReportMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct FireVaultBreadcrumbExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.pdf, .commaSeparatedText]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
