//
//  FireVaultBreadcrumbReport.swift
//  FireVault
//
//  Design 3 summary-card Trip Log reports with daily and weekly PDF export.
//

import MapKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FireVaultTripLogRoutePoint: Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitudeFeet: Double?
    let speedMPH: Double?

    init(
        timestamp: Date = .distantPast,
        latitude: Double,
        longitude: Double,
        altitudeFeet: Double?,
        speedMPH: Double? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitudeFeet = altitudeFeet
        self.speedMPH = speedMPH
    }

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}

struct FireVaultTripLogMapStop: Identifiable, Equatable {
    let id: UUID
    let sequence: Int
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}

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
        let mapLatitude: Double
        let mapLongitude: Double

        var timeText: String {
            let start = arrival.formatted(date: .omitted, time: .shortened)
            guard let departure else { return "\(start) - In progress" }
            return "\(start) - \(departure.formatted(date: .omitted, time: .shortened))"
        }

        var arrivalText: String {
            arrival.formatted(date: .omitted, time: .shortened)
        }

        var departureText: String {
            departure?.formatted(date: .omitted, time: .shortened) ?? "In progress"
        }

        var reportTimeText: String {
            "Arr \(arrivalText)\nDep \(departureText)"
        }

        var durationText: String {
            FireVaultBreadcrumbReport.durationText(duration)
        }

        var title: String {
            switch classification {
            case .account:
                accountName.isEmpty ? "Account Visit" : accountName
            case .unassigned:
                accountName.isEmpty ? "Unrecognized Stop" : accountName
            case .personal:
                "Personal Stop"
            }
        }

        var addressText: String {
            switch classification {
            case .account:
                if !accountAddress.isEmpty { accountAddress }
                else { "Approx. \(mapLatitude.formatted(.number.precision(.fractionLength(5)))), \(mapLongitude.formatted(.number.precision(.fractionLength(5))))" }
            case .unassigned:
                if !accountAddress.isEmpty { accountAddress }
                else { "Approx. \(mapLatitude.formatted(.number.precision(.fractionLength(5)))), \(mapLongitude.formatted(.number.precision(.fractionLength(5))))" }
            case .personal:
                "Private location"
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

        var mapStop: FireVaultTripLogMapStop {
            .init(
                id: id,
                sequence: sequence,
                latitude: mapLatitude,
                longitude: mapLongitude
            )
        }
    }

    let sourceDay: FireVaultBreadcrumbDay
    let dayID: UUID
    let startedAt: Date
    let endedAt: Date?
    let generatedAt: Date
    let technicianName: String
    let companyName: String
    let totalDistanceMeters: Double
    let elapsedTime: TimeInterval
    let visits: [Visit]
    let routePoints: [FireVaultTripLogRoutePoint]

    init(
        day: FireVaultBreadcrumbDay,
        technicianName: String,
        companyName: String,
        includeCoordinates: Bool,
        generatedAt: Date = Date()
    ) {
        sourceDay = day
        dayID = day.id
        startedAt = day.startedAt
        endedAt = day.endedAt
        self.generatedAt = generatedAt
        self.technicianName = technicianName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        totalDistanceMeters = day.totalDistanceMeters
        elapsedTime = max(0, (day.endedAt ?? generatedAt).timeIntervalSince(day.startedAt))
        routePoints = day.points.map {
            .init(
                timestamp: $0.timestamp,
                latitude: $0.latitude,
                longitude: $0.longitude,
                altitudeFeet: $0.altitude.map { $0 * 3.280_84 },
                speedMPH: $0.speedMetersPerSecond.map { max(0, $0) * 2.236_94 }
            )
        }
        visits = day.stops
            .sorted { $0.arrival < $1.arrival }
            .enumerated()
            .map { offset, stop in
                let classification: VisitClassification
                if stop.isPersonalStop {
                    classification = .personal
                } else if stop.accountID != nil {
                    classification = .account
                } else {
                    classification = .unassigned
                }

                let redactsPrivateDetails = classification == .personal
                return Visit(
                    id: stop.id,
                    sequence: offset + 1,
                    arrival: stop.arrival,
                    departure: day.effectiveDeparture(for: stop, asOf: generatedAt),
                    duration: day.stopDuration(for: stop, asOf: generatedAt),
                    classification: classification,
                    accountName: redactsPrivateDetails ? "" : stop.title,
                    accountAddress: redactsPrivateDetails ? "" : (stop.accountAddress ?? ""),
                    accountID: redactsPrivateDetails ? "" : (stop.accountID ?? ""),
                    technicianNote: redactsPrivateDetails ? "" : (stop.technicianNote ?? ""),
                    latitude: includeCoordinates && !redactsPrivateDetails ? stop.latitude : nil,
                    longitude: includeCoordinates && !redactsPrivateDetails ? stop.longitude : nil,
                    mapLatitude: stop.latitude,
                    mapLongitude: stop.longitude
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

    var monthText: String {
        startedAt.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    var dayText: String {
        startedAt.formatted(.dateTime.day())
    }

    var yearText: String {
        startedAt.formatted(.dateTime.year())
    }

    var workdayTimeText: String {
        let start = startedAt.formatted(date: .omitted, time: .shortened)
        guard let endedAt else { return "\(start) - In progress" }
        return "\(start) - \(endedAt.formatted(date: .omitted, time: .shortened))"
    }

    var startTimeText: String {
        startedAt.formatted(date: .omitted, time: .shortened)
    }

    var endTimeText: String {
        endedAt?.formatted(date: .omitted, time: .shortened) ?? "In progress"
    }

    var distanceText: String {
        Self.distanceText(totalDistanceMeters)
    }

    var elapsedText: String {
        Self.durationText(elapsedTime)
    }

    var mapStops: [FireVaultTripLogMapStop] {
        visits.map(\.mapStop)
    }

    var mapRegion: MKCoordinateRegion {
        Self.region(for: routePoints.map(\.coordinate) + mapStops.map(\.coordinate))
    }

    var elevationProfileFeet: [Double] {
        let recorded = routePoints.compactMap(\.altitudeFeet)
        if recorded.count >= 2 { return recorded }

        let isDemo = sourceDay.stops.contains {
            ($0.accountID ?? "").hasPrefix("demo-") || ($0.technicianNote ?? "").hasPrefix("DEMO:")
        }
        guard isDemo, routePoints.count >= 2 else { return [] }
        return routePoints.indices.map { index in
            let progress = Double(index) / Double(max(1, routePoints.count - 1))
            return 2_730 + sin(progress * .pi * 2) * 115 + sin(progress * .pi * 7) * 38
        }
    }

    var speedProfileMPH: [Double] {
        routePoints.compactMap(\.speedMPH).map { max(0, $0) }
    }

    var averageSpeedMPH: Double? {
        let samples = routePoints.compactMap(\.speedMPH).map { max(0, $0) }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    var stopProgressFractions: [Double] {
        guard routePoints.count > 1 else { return [] }
        return visits.map { visit in
            let stopLocation = CLLocation(latitude: visit.mapLatitude, longitude: visit.mapLongitude)
            let nearestIndex = routePoints.indices.min { lhs, rhs in
                let left = CLLocation(latitude: routePoints[lhs].latitude, longitude: routePoints[lhs].longitude)
                let right = CLLocation(latitude: routePoints[rhs].latitude, longitude: routePoints[rhs].longitude)
                return left.distance(from: stopLocation) < right.distance(from: stopLocation)
            } ?? 0
            return Double(nearestIndex) / Double(routePoints.count - 1)
        }
    }

    var filenameStem: String {
        let day = startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "FireVault-Trip-Log-Daily-\(day)"
    }

    var plainText: String {
        var lines = [
            "FIREVAULT TRIP LOG DAILY REPORT",
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
            if !visit.technicianNote.isEmpty { lines.append("Visit note: \(visit.technicianNote)") }
            if let coordinateText = visit.coordinateText { lines.append("Coordinates: \(coordinateText)") }
            lines.append("")
        }

        if visits.isEmpty { lines.append("No stops were recorded.") }
        lines.append("Generated by FireVault Pro \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
        return lines.joined(separator: "\n")
    }

    // Retained for existing exports and regression tests. The interactive report
    // screen uses the richer daily/weekly renderer below.
    var csvData: Data {
        func quoted(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

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
                visit.arrival.formatted(.iso8601.year().month().day().dateSeparator(.dash)),
                visit.arrival.formatted(.iso8601.time(includingFractionalSeconds: false)),
                visit.departure?.formatted(.iso8601.time(includingFractionalSeconds: false)) ?? "",
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
            .map { $0.map(quoted).joined(separator: ",") }
            .joined(separator: "\r\n")
            + "\r\n"
        return Data(source.utf8)
    }

    var pdfData: Data {
        FireVaultTripLogPDFRenderer.daily(
            report: self,
            detail: .detailed,
            mapImage: nil
        )
    }

    static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return .init(
                center: .init(latitude: 42.8501, longitude: -106.3252),
                span: .init(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }
        let minimumLatitude = coordinates.map(\.latitude).min() ?? first.latitude
        let maximumLatitude = coordinates.map(\.latitude).max() ?? first.latitude
        let minimumLongitude = coordinates.map(\.longitude).min() ?? first.longitude
        let maximumLongitude = coordinates.map(\.longitude).max() ?? first.longitude
        return .init(
            center: .init(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: .init(
                latitudeDelta: max(0.012, (maximumLatitude - minimumLatitude) * 1.35),
                longitudeDelta: max(0.012, (maximumLongitude - minimumLongitude) * 1.35)
            )
        )
    }

    static func distanceText(_ meters: Double) -> String {
        let miles = meters / 1_609.344
        return "\(miles.formatted(.number.precision(.fractionLength(miles < 10 ? 1 : 0)))) mi"
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}

struct FireVaultTripLogWeeklyReport: Equatable {
    let weekStart: Date
    let weekEnd: Date
    let generatedAt: Date
    let technicianName: String
    let companyName: String
    let dailyReports: [FireVaultBreadcrumbReport]

    init(
        days: [FireVaultBreadcrumbDay],
        anchorDate: Date,
        technicianName: String,
        companyName: String,
        includeCoordinates: Bool,
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) {
        let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDate)
        let start = interval?.start ?? calendar.startOfDay(for: anchorDate)
        let endExclusive = interval?.end ?? calendar.date(byAdding: .day, value: 7, to: start) ?? start
        weekStart = start
        weekEnd = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
        self.generatedAt = generatedAt
        self.technicianName = technicianName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        dailyReports = days
            .filter { $0.startedAt >= start && $0.startedAt < endExclusive }
            .sorted { $0.startedAt < $1.startedAt }
            .map {
                FireVaultBreadcrumbReport(
                    day: $0,
                    technicianName: technicianName,
                    companyName: companyName,
                    includeCoordinates: includeCoordinates,
                    generatedAt: generatedAt
                )
            }
    }

    var totalDistanceMeters: Double {
        dailyReports.reduce(0) { $0 + $1.totalDistanceMeters }
    }

    var totalElapsedTime: TimeInterval {
        dailyReports.reduce(0) { $0 + $1.elapsedTime }
    }

    var accountVisitCount: Int {
        dailyReports.reduce(0) { $0 + $1.accountVisitCount }
    }

    var unassignedVisitCount: Int {
        dailyReports.reduce(0) { $0 + $1.unassignedVisitCount }
    }

    var personalStopCount: Int {
        dailyReports.reduce(0) { $0 + $1.personalStopCount }
    }

    var totalStopCount: Int {
        dailyReports.reduce(0) { $0 + $1.visits.count }
    }

    var distanceText: String {
        FireVaultBreadcrumbReport.distanceText(totalDistanceMeters)
    }

    var elapsedText: String {
        FireVaultBreadcrumbReport.durationText(totalElapsedTime)
    }

    var dateRangeText: String {
        let start = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let end = weekEnd.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start)–\(end)"
    }

    var routeSets: [[FireVaultTripLogRoutePoint]] {
        dailyReports.map(\.routePoints).filter { !$0.isEmpty }
    }

    var elevationSetsFeet: [[Double]] {
        dailyReports.map(\.elevationProfileFeet).filter { $0.count >= 2 }
    }

    var speedSetsMPH: [[Double]] {
        dailyReports.map(\.speedProfileMPH).filter { $0.count >= 2 }
    }

    var averageSpeedMPH: Double? {
        let values = dailyReports.compactMap(\.averageSpeedMPH)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var mapStops: [FireVaultTripLogMapStop] {
        var sequence = 0
        return dailyReports.flatMap { daily in
            daily.mapStops.map { stop in
                sequence += 1
                return .init(
                    id: stop.id,
                    sequence: sequence,
                    latitude: stop.latitude,
                    longitude: stop.longitude
                )
            }
        }
    }

    var mapRegion: MKCoordinateRegion {
        FireVaultBreadcrumbReport.region(
            for: routeSets.flatMap { $0.map(\.coordinate) } + mapStops.map(\.coordinate)
        )
    }

    var filenameStem: String {
        let start = weekStart.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "FireVault-Trip-Log-Weekly-\(start)"
    }

    var plainText: String {
        var lines = [
            "FIREVAULT TRIP LOG WEEKLY REPORT",
            dateRangeText,
            companyName.isEmpty ? "" : companyName,
            technicianName.isEmpty ? "Technician: Not configured" : "Technician: \(technicianName)",
            "Workdays: \(dailyReports.count) • Distance: \(distanceText) • Elapsed: \(elapsedText)",
            "Account visits: \(accountVisitCount) • Needs review: \(unassignedVisitCount) • Personal: \(personalStopCount)",
            ""
        ]
        for day in dailyReports {
            lines.append(day.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            lines.append("\(day.distanceText) • \(day.elapsedText) • \(day.visits.count) stops")
            for visit in day.visits {
                lines.append("  \(visit.arrivalText)  \(visit.title)  \(visit.durationText)")
            }
            lines.append("")
        }
        if dailyReports.isEmpty { lines.append("No Trip Log workdays were recorded for this week.") }
        return lines.joined(separator: "\n")
    }
}

private enum FireVaultTripLogReportScope: String, CaseIterable, Identifiable {
    case daily = "Daily"
    case weekly = "Weekly"
    var id: String { rawValue }
}

enum FireVaultTripLogReportDetail: String, CaseIterable, Identifiable {
    case detailed = "Detailed"
    case compact = "Compact"
    var id: String { rawValue }
}

private enum FireVaultTripLogReportPalette {
    static let navy = Color(red: 0.04, green: 0.18, blue: 0.31)
    static let blue = Color(red: 0.05, green: 0.35, blue: 0.68)
    static let red = Color(red: 0.82, green: 0.12, blue: 0.10)
    static let green = Color(red: 0.18, green: 0.58, blue: 0.28)
    static let paleBlue = Color(red: 0.93, green: 0.97, blue: 1.00)
    static let line = Color.black.opacity(0.10)
}

struct FireVaultBreadcrumbReportView: View {
    let report: FireVaultBreadcrumbReport
    let availableDays: [FireVaultBreadcrumbDay]

    @Environment(\.dismiss) private var dismiss
    @State private var scope: FireVaultTripLogReportScope = .daily
    @State private var detail: FireVaultTripLogReportDetail = .detailed
    @State private var exportDocument: FireVaultBreadcrumbExportDocument?
    @State private var showsExporter = false
    @State private var exportStatus: String?
    @State private var isGeneratingPDF = false
    @State private var isGeneratingImages = false
    @State private var imageSharePayload: FireVaultImageSharePayload?

    init(
        report: FireVaultBreadcrumbReport,
        availableDays: [FireVaultBreadcrumbDay] = []
    ) {
        self.report = report
        self.availableDays = availableDays.isEmpty ? [report.sourceDay] : availableDays
    }

    private var weeklyReport: FireVaultTripLogWeeklyReport {
        .init(
            days: availableDays,
            anchorDate: report.startedAt,
            technicianName: report.technicianName,
            companyName: report.companyName,
            includeCoordinates: report.visits.contains { $0.coordinateText != nil },
            generatedAt: report.generatedAt
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    reportControls
                    reportPaper
                    exportActions
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .background(NativeShellPalette.background)
            .navigationTitle("Trip Log Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showsExporter,
                document: exportDocument,
                contentType: .pdf,
                defaultFilename: scope == .daily ? report.filenameStem : weeklyReport.filenameStem
            ) { result in
                switch result {
                case .success:
                    exportStatus = "Trip Log PDF exported successfully."
                case .failure(let error):
                    exportStatus = "The Trip Log PDF could not be exported. \(error.localizedDescription)"
                }
            }
            .alert(
                "Trip Log Export",
                isPresented: .init(
                    get: { exportStatus != nil },
                    set: { if !$0 { exportStatus = nil } }
                )
            ) {
                Button("OK") { exportStatus = nil }
            } message: {
                Text(exportStatus ?? "")
            }
            .sheet(item: $imageSharePayload) { payload in
                FireVaultActivityView(
                    items: [
                        FireVaultMailSubjectItemSource(subject: payload.subject),
                        payload.body
                    ] + payload.images
                )
            }
        }
        .tint(NativeShellPalette.blue)
    }

    private var reportControls: some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("REPORT TEMPLATE")
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(.secondary)

                Picker("Report period", selection: $scope) {
                    ForEach(FireVaultTripLogReportScope.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Report detail", selection: $detail) {
                    ForEach(FireVaultTripLogReportDetail.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Text(
                    scope == .daily
                        ? "Daily shows the selected workday, route, metrics, and stop details."
                        : "Weekly creates a visual overview followed by a complete page for each recorded workday."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var reportPaper: some View {
        VStack(alignment: .leading, spacing: 18) {
            if scope == .daily {
                dailyHeader
                reportDivider
                dailyMetricStrip
                routeMap(
                    routeSets: [report.routePoints],
                    stops: report.mapStops,
                    region: report.mapRegion,
                    aspectRatio: 1
                )
                routePerformanceProfile(
                    elevationSets: [report.elevationProfileFeet],
                    speedSets: [report.speedProfileMPH],
                    stopFractions: report.stopProgressFractions,
                    averageSpeed: report.averageSpeedMPH
                )
                dailyStopDetails
                reportFooter(generatedAt: report.generatedAt)
            } else {
                weeklyHeader
                reportDivider
                weeklyMetricStrip
                routeMap(
                    routeSets: weeklyReport.routeSets,
                    stops: detail == .detailed ? weeklyReport.mapStops : [],
                    region: weeklyReport.mapRegion,
                    aspectRatio: 1.9
                )
                weeklyDaySummary
                if detail == .detailed {
                    weeklyStopDetails
                }
                reportFooter(generatedAt: weeklyReport.generatedAt)
            }
        }
        .padding(18)
        .foregroundStyle(.black)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
        .accessibilityIdentifier("trip-log-report-preview")
    }

    private var dailyHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            brandBlock(
                title: "TRIP LOG DAILY REPORT",
                technician: report.technicianName,
                company: report.companyName
            )
            Spacer(minLength: 8)
            dateBadge(month: report.monthText, day: report.dayText, year: report.yearText)
        }
    }

    private var weeklyHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            brandBlock(
                title: "TRIP LOG WEEKLY REPORT",
                technician: weeklyReport.technicianName,
                company: weeklyReport.companyName
            )
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text("WEEK OF")
                    .font(.caption2.bold())
                    .foregroundStyle(FireVaultTripLogReportPalette.blue)
                Text(weeklyReport.dateRangeText)
                    .font(.subheadline.bold())
                    .foregroundStyle(FireVaultTripLogReportPalette.navy)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(FireVaultTripLogReportPalette.paleBlue, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func brandBlock(title: String, technician: String, company: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FireVaultProWordmark(
                    fireColor: FireVaultTripLogReportPalette.red,
                    vaultColor: .white,
                    proColor: .white,
                    proBackground: FireVaultTripLogReportPalette.red,
                    fontSize: 18,
                    proFontSize: 7.5
                )
            }

            Text(title)
                .font(.caption.bold())
                .tracking(0.7)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(FireVaultTripLogReportPalette.navy, in: Capsule())

            VStack(alignment: .leading, spacing: 2) {
                if !company.isEmpty {
                    Text(company).font(.caption.bold())
                }
                Text(technician.isEmpty ? "Technician not configured" : technician)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dateBadge(month: String, day: String, year: String) -> some View {
        VStack(spacing: 1) {
            Text(month)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(FireVaultTripLogReportPalette.blue)
            Text(day)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(FireVaultTripLogReportPalette.navy)
            Text(year)
                .font(.caption2.bold().monospacedDigit())
                .foregroundStyle(FireVaultTripLogReportPalette.navy)
                .padding(.bottom, 5)
        }
        .frame(width: 58)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(FireVaultTripLogReportPalette.blue.opacity(0.65), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var reportDivider: some View {
        Rectangle()
            .fill(FireVaultTripLogReportPalette.line)
            .frame(height: 1)
    }

    private func reportFooter(generatedAt: Date) -> some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(FireVaultTripLogReportPalette.line)
                .frame(height: 1)
            HStack {
                Text("FIREVAULT PRO • BANNERMAN US LLC")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(FireVaultTripLogReportPalette.navy)
                Spacer()
                Text("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private var dailyMetricStrip: some View {
        metricStrip([
            ("DISTANCE", report.distanceText, "road.lanes"),
            ("TIME", report.elapsedText, "clock"),
            ("STOPS", "\(report.visits.count)", "mappin.and.ellipse"),
            ("START", report.startTimeText, "play.circle"),
            ("END", report.endTimeText, "stop.circle")
        ])
    }

    private var weeklyMetricStrip: some View {
        metricStrip([
            ("DISTANCE", weeklyReport.distanceText, "road.lanes"),
            ("TIME", weeklyReport.elapsedText, "clock"),
            ("STOPS", "\(weeklyReport.totalStopCount)", "mappin.and.ellipse"),
            ("WORKDAYS", "\(weeklyReport.dailyReports.count)", "calendar"),
            ("VISITS", "\(weeklyReport.accountVisitCount)", "building.2")
        ])
    }

    private func metricStrip(_ metrics: [(String, String, String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                VStack(spacing: 4) {
                    Image(systemName: metric.2)
                        .font(.caption)
                        .foregroundStyle(FireVaultTripLogReportPalette.blue)
                    Text(metric.1)
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(FireVaultTripLogReportPalette.navy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text(metric.0)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)

                if index < metrics.count - 1 {
                    Rectangle()
                        .fill(FireVaultTripLogReportPalette.line)
                        .frame(width: 1, height: 42)
                }
            }
        }
        .background(FireVaultTripLogReportPalette.paleBlue, in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(FireVaultTripLogReportPalette.blue.opacity(0.15), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func routeMap(
        routeSets: [[FireVaultTripLogRoutePoint]],
        stops: [FireVaultTripLogMapStop],
        region: MKCoordinateRegion,
        aspectRatio: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ROUTE MAP")
                .font(.caption.bold())
                .tracking(0.9)
                .foregroundStyle(FireVaultTripLogReportPalette.navy)

            if routeSets.flatMap({ $0 }).isEmpty {
                ZStack {
                    FireVaultTripLogReportPalette.paleBlue
                    Label("No route points recorded", systemImage: "map")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                Map(initialPosition: .region(region), interactionModes: []) {
                    ForEach(Array(routeSets.enumerated()), id: \.offset) { _, route in
                        MapPolyline(coordinates: route.map(\.coordinate))
                            .stroke(
                                FireVaultTripLogReportPalette.blue,
                                style: .init(lineWidth: 4, lineCap: .round, lineJoin: .round)
                            )
                    }
                    ForEach(stops) { stop in
                        Annotation("Stop \(stop.sequence)", coordinate: stop.coordinate) {
                            Text("\(stop.sequence)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(FireVaultTripLogReportPalette.blue, in: Circle())
                                .overlay { Circle().stroke(.white, lineWidth: 1.5) }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FireVaultTripLogReportPalette.line, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func routePerformanceProfile(
        elevationSets: [[Double]],
        speedSets: [[Double]],
        stopFractions: [Double],
        averageSpeed: Double?
    ) -> some View {
        let validSets = elevationSets.filter { $0.count >= 2 }
        let elevations = validSets.flatMap { $0 }

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("TRIP PROFILE")
                    .font(.caption.bold())
                    .tracking(0.9)
                    .foregroundStyle(FireVaultTripLogReportPalette.navy)
                Spacer()
                if let minimum = elevations.min(), let maximum = elevations.max() {
                    Text("\(Int(minimum.rounded()).formatted())–\(Int(maximum.rounded()).formatted()) FT")
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if elevations.count >= 2 {
                Canvas { context, size in
                    let minimum = elevations.min() ?? 0
                    let maximum = elevations.max() ?? minimum + 1
                    let range = max(1, maximum - minimum)
                    let topInset: CGFloat = 10
                    let bottomInset: CGFloat = 17
                    let drawableHeight = max(1, size.height - topInset - bottomInset)

                    for gridIndex in 0...3 {
                        let y = topInset + drawableHeight * CGFloat(gridIndex) / 3
                        var grid = Path()
                        grid.move(to: .init(x: 0, y: y))
                        grid.addLine(to: .init(x: size.width, y: y))
                        context.stroke(grid, with: .color(FireVaultTripLogReportPalette.line), lineWidth: 0.7)
                    }

                    let segmentWidth = size.width / CGFloat(max(1, validSets.count))
                    for (setIndex, set) in validSets.enumerated() {
                        var line = Path()
                        for (pointIndex, elevation) in set.enumerated() {
                            let fraction = CGFloat(pointIndex) / CGFloat(max(1, set.count - 1))
                            let x = CGFloat(setIndex) * segmentWidth + fraction * segmentWidth
                            let y = topInset + CGFloat((maximum - elevation) / range) * drawableHeight
                            if pointIndex == 0 { line.move(to: .init(x: x, y: y)) }
                            else { line.addLine(to: .init(x: x, y: y)) }
                        }
                        context.stroke(
                            line,
                            with: .linearGradient(
                                .init(colors: [FireVaultTripLogReportPalette.blue, FireVaultTripLogReportPalette.red]),
                                startPoint: .zero,
                                endPoint: .init(x: size.width, y: 0)
                            ),
                            style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                    }

                    let validSpeeds = speedSets.filter { $0.count >= 2 }
                    let maximumSpeed = max(1, validSpeeds.flatMap { $0 }.max() ?? 1)
                    for (setIndex, set) in validSpeeds.enumerated() {
                        let speedSegmentWidth = size.width / CGFloat(max(1, validSpeeds.count))
                        var speedLine = Path()
                        for (pointIndex, speed) in set.enumerated() {
                            let fraction = CGFloat(pointIndex) / CGFloat(max(1, set.count - 1))
                            let x = CGFloat(setIndex) * speedSegmentWidth + fraction * speedSegmentWidth
                            let y = topInset + CGFloat(1 - speed / maximumSpeed) * drawableHeight
                            if pointIndex == 0 { speedLine.move(to: .init(x: x, y: y)) }
                            else { speedLine.addLine(to: .init(x: x, y: y)) }
                        }
                        context.stroke(speedLine, with: .color(FireVaultTripLogReportPalette.red), style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    }

                    if let averageSpeed {
                        let averageY = topInset + CGFloat(1 - min(averageSpeed, maximumSpeed) / maximumSpeed) * drawableHeight
                        var averageLine = Path()
                        averageLine.move(to: .init(x: 0, y: averageY))
                        averageLine.addLine(to: .init(x: size.width, y: averageY))
                        context.stroke(averageLine, with: .color(FireVaultTripLogReportPalette.green), style: .init(lineWidth: 1.2, dash: [5, 4]))
                    }

                    let markerFractions = [0.0] + stopFractions + [1.0]
                    for (index, fraction) in markerFractions.enumerated() {
                        let x = CGFloat(min(1, max(0, fraction))) * size.width
                        var marker = Path()
                        marker.move(to: .init(x: x, y: topInset))
                        marker.addLine(to: .init(x: x, y: topInset + drawableHeight))
                        let markerColor = index == 0
                            ? FireVaultTripLogReportPalette.green
                            : (index == markerFractions.count - 1 ? FireVaultTripLogReportPalette.navy : FireVaultTripLogReportPalette.red)
                        context.stroke(marker, with: .color(markerColor.opacity(0.75)), style: .init(lineWidth: 1, dash: [2, 3]))
                    }
                }
                .frame(height: 105)
                .padding(.horizontal, 10)
                .padding(.top, 5)
                .background(FireVaultTripLogReportPalette.paleBlue, in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(FireVaultTripLogReportPalette.line, lineWidth: 1)
                }

                HStack(spacing: 12) {
                    Label("Elevation", systemImage: "waveform.path")
                        .foregroundStyle(FireVaultTripLogReportPalette.blue)
                    Label("Speed", systemImage: "speedometer")
                        .foregroundStyle(FireVaultTripLogReportPalette.red)
                    if let averageSpeed {
                        Text("AVG \(Int(averageSpeed.rounded())) MPH")
                            .foregroundStyle(FireVaultTripLogReportPalette.green)
                    }
                    Spacer()
                    Text("START • STOPS • END")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 8, weight: .bold))
            } else {
                Label("Elevation was not recorded for this saved Trip Log", systemImage: "mountain.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(FireVaultTripLogReportPalette.paleBlue, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }

    private var dailyStopDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STOP DETAILS")
                    .font(.caption.bold())
                    .tracking(0.9)
                    .foregroundStyle(FireVaultTripLogReportPalette.navy)
                Spacer()
                if report.unassignedVisitCount > 0 {
                    Label("\(report.unassignedVisitCount) need review", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }

            stopTableHeader
            if report.visits.isEmpty {
                Text("No stops were recorded for this workday.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                let visibleVisits = detail == .compact ? Array(report.visits.prefix(8)) : report.visits
                ForEach(visibleVisits) { visit in
                    stopTableRow(visit)
                }
                if detail == .compact, report.visits.count > visibleVisits.count {
                    Text("+ \(report.visits.count - visibleVisits.count) additional stops included in the detailed report")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                }
            }
        }
    }

    private var stopTableHeader: some View {
        HStack(spacing: 8) {
            Text("#").frame(width: 22, alignment: .leading)
            Text("ARRIVE / DEPART").frame(width: 76, alignment: .leading)
            Text("LOCATION / ACCOUNT").frame(maxWidth: .infinity, alignment: .leading)
            Text("DURATION").frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(FireVaultTripLogReportPalette.navy)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(FireVaultTripLogReportPalette.paleBlue)
    }

    private func stopTableRow(_ visit: FireVaultBreadcrumbReport.Visit) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(visit.sequence)")
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("Arr \(visit.arrivalText)")
                Text("Dep \(visit.departureText)")
            }
                .font(.caption2.monospacedDigit())
                .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.title).fontWeight(.semibold)
                if !visit.addressText.isEmpty {
                    Text(visit.addressText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if detail == .detailed, !visit.technicianNote.isEmpty {
                    Label(visit.technicianNote, systemImage: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(visit.durationText)
                .frame(width: 58, alignment: .trailing)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FireVaultTripLogReportPalette.line).frame(height: 1)
        }
    }

    private var weeklyDaySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WEEKLY SUMMARY")
                .font(.caption.bold())
                .tracking(0.9)
                .foregroundStyle(FireVaultTripLogReportPalette.navy)

            HStack(spacing: 8) {
                Text("DAY").frame(maxWidth: .infinity, alignment: .leading)
                Text("MILES").frame(width: 52, alignment: .trailing)
                Text("TIME").frame(width: 58, alignment: .trailing)
                Text("STOPS").frame(width: 42, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(FireVaultTripLogReportPalette.navy)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(FireVaultTripLogReportPalette.paleBlue)

            if weeklyReport.dailyReports.isEmpty {
                Text("No Trip Log workdays were recorded in this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                ForEach(weeklyReport.dailyReports, id: \.dayID) { day in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.startedAt.formatted(.dateTime.weekday(.wide)))
                                .fontWeight(.semibold)
                            Text(day.startedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(day.distanceText).frame(width: 52, alignment: .trailing)
                        Text(day.elapsedText).frame(width: 58, alignment: .trailing)
                        Text("\(day.visits.count)").frame(width: 42, alignment: .trailing)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(FireVaultTripLogReportPalette.line).frame(height: 1)
                    }
                }
            }
        }
    }

    private var weeklyStopDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAILY STOP DETAILS")
                .font(.caption.bold())
                .tracking(0.9)
                .foregroundStyle(FireVaultTripLogReportPalette.navy)

            ForEach(weeklyReport.dailyReports, id: \.dayID) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.subheadline.bold())
                        .foregroundStyle(FireVaultTripLogReportPalette.blue)
                    if day.visits.isEmpty {
                        Text("No stops recorded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(day.visits) { visit in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Arr \(visit.arrivalText)")
                                    Text("Dep \(visit.departureText)")
                                }
                                    .font(.caption2.monospacedDigit())
                                    .frame(width: 82, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(visit.title).font(.caption.bold())
                                    Text(visit.addressText)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(visit.durationText)
                                    .font(.caption.monospacedDigit())
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding(10)
                .background(FireVaultTripLogReportPalette.paleBlue.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
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

                Button {
                    Task { await exportPDF() }
                } label: {
                    HStack {
                        if isGeneratingPDF {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "doc.richtext.fill")
                        }
                        Text(isGeneratingPDF ? "Building PDF…" : "Export PDF")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingPDF)

                Button {
                    Task { await shareJPG() }
                } label: {
                    HStack {
                        if isGeneratingImages {
                            ProgressView()
                        } else {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                        Text(isGeneratingImages ? "Building Images…" : "Share JPG in Email")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingImages)

                ShareLink(
                    item: scope == .daily ? report.plainText : weeklyReport.plainText,
                    subject: Text(scope == .daily ? "FireVault Pro Trip Log Daily Report" : "FireVault Pro Trip Log Weekly Report"),
                    preview: SharePreview(
                        scope == .daily ? "Trip Log Daily Report" : "Trip Log Weekly Report",
                        image: Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    )
                ) {
                    Label("Share Text Summary", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("JPG pages are shared as images so compatible email apps can display them directly in the message. Personal stops remain redacted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("trip-log-report-export")
    }

    @MainActor
    private func exportPDF() async {
        guard !isGeneratingPDF else { return }
        isGeneratingPDF = true
        defer { isGeneratingPDF = false }

        if scope == .daily {
            let mapImage = await FireVaultTripLogMapSnapshot.image(
                routeSets: [report.routePoints],
                stops: report.mapStops,
                region: report.mapRegion,
                size: .init(width: 528, height: 148)
            )
            let data = FireVaultTripLogPDFRenderer.daily(
                report: report,
                detail: detail,
                mapImage: mapImage
            )
            exportDocument = .init(data: data)
        } else {
            let mapImage = await FireVaultTripLogMapSnapshot.image(
                routeSets: weeklyReport.routeSets,
                stops: detail == .detailed ? weeklyReport.mapStops : [],
                region: weeklyReport.mapRegion,
                size: .init(width: 528, height: 160)
            )
            let data = FireVaultTripLogPDFRenderer.weekly(
                report: weeklyReport,
                detail: detail,
                mapImage: mapImage
            )
            exportDocument = .init(data: data)
        }
        showsExporter = true
    }

    @MainActor
    private func shareJPG() async {
        guard !isGeneratingImages else { return }
        isGeneratingImages = true
        defer { isGeneratingImages = false }

        let pdfData: Data
        if scope == .daily {
            let mapImage = await FireVaultTripLogMapSnapshot.image(
                routeSets: [report.routePoints],
                stops: report.mapStops,
                region: report.mapRegion,
                size: .init(width: 528, height: 148)
            )
            pdfData = FireVaultTripLogPDFRenderer.daily(
                report: report,
                detail: detail,
                mapImage: mapImage
            )
        } else {
            let mapImage = await FireVaultTripLogMapSnapshot.image(
                routeSets: weeklyReport.routeSets,
                stops: detail == .detailed ? weeklyReport.mapStops : [],
                region: weeklyReport.mapRegion,
                size: .init(width: 528, height: 160)
            )
            pdfData = FireVaultTripLogPDFRenderer.weekly(
                report: weeklyReport,
                detail: detail,
                mapImage: mapImage
            )
        }

        let images = FireVaultTripLogImageRenderer.images(from: pdfData)
        guard !images.isEmpty else {
            exportStatus = "The Trip Log images could not be created."
            return
        }
        imageSharePayload = .init(
            subject: scope == .daily
                ? "FireVault Pro Trip Log Daily Report"
                : "FireVault Pro Trip Log Weekly Report",
            body: scope == .daily
                ? "FireVault Pro Trip Log for \(report.dateText)"
                : "FireVault Pro Trip Log for \(weeklyReport.dateRangeText)",
            images: images
        )
    }
}

private enum FireVaultTripLogMapSnapshot {
    static func image(
        routeSets: [[FireVaultTripLogRoutePoint]],
        stops: [FireVaultTripLogMapStop],
        region: MKCoordinateRegion,
        size: CGSize
    ) async -> UIImage? {
        guard !routeSets.flatMap({ $0 }).isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = 2
        options.mapType = .standard
        options.showsBuildings = true
        options.pointOfInterestFilter = .excludingAll

        let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, _ in
                continuation.resume(returning: snapshot)
            }
        }

        guard let snapshot else {
            return fallbackImage(routeSets: routeSets, stops: stops, size: size)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))

            for route in routeSets where route.count > 1 {
                let path = UIBezierPath()
                for (index, point) in route.enumerated() {
                    let mapped = snapshot.point(for: point.coordinate)
                    if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
                }
                UIColor(red: 0.05, green: 0.35, blue: 0.68, alpha: 0.95).setStroke()
                path.lineWidth = 4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }

            for stop in stops.prefix(99) {
                let point = snapshot.point(for: stop.coordinate)
                let circle = CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)
                UIColor(red: 0.05, green: 0.35, blue: 0.68, alpha: 1).setFill()
                UIBezierPath(ovalIn: circle).fill()
                UIColor.white.setStroke()
                let outline = UIBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
                outline.lineWidth = 1.5
                outline.stroke()
                let number = "\(stop.sequence)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: stop.sequence > 9 ? 7 : 9, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let textSize = number.size(withAttributes: attributes)
                number.draw(
                    at: .init(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2),
                    withAttributes: attributes
                )
            }
        }
    }

    private static func fallbackImage(
        routeSets: [[FireVaultTripLogRoutePoint]],
        stops: [FireVaultTripLogMapStop],
        size: CGSize
    ) -> UIImage {
        let allPoints = routeSets.flatMap { $0 }
        let minimumLatitude = allPoints.map(\.latitude).min() ?? 0
        let maximumLatitude = allPoints.map(\.latitude).max() ?? 1
        let minimumLongitude = allPoints.map(\.longitude).min() ?? 0
        let maximumLongitude = allPoints.map(\.longitude).max() ?? 1
        let latitudeRange = max(0.0001, maximumLatitude - minimumLatitude)
        let longitudeRange = max(0.0001, maximumLongitude - minimumLongitude)
        let inset: CGFloat = 18

        func mapped(_ point: FireVaultTripLogRoutePoint) -> CGPoint {
            let x = inset + CGFloat((point.longitude - minimumLongitude) / longitudeRange) * (size.width - inset * 2)
            let y = inset + CGFloat((maximumLatitude - point.latitude) / latitudeRange) * (size.height - inset * 2)
            return .init(x: x, y: y)
        }

        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.93, green: 0.97, blue: 1, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.82, alpha: 0.55).setStroke()
            context.cgContext.setLineWidth(0.5)
            for column in 1..<8 {
                let x = CGFloat(column) * size.width / 8
                context.cgContext.move(to: .init(x: x, y: 0))
                context.cgContext.addLine(to: .init(x: x, y: size.height))
            }
            for row in 1..<4 {
                let y = CGFloat(row) * size.height / 4
                context.cgContext.move(to: .init(x: 0, y: y))
                context.cgContext.addLine(to: .init(x: size.width, y: y))
            }
            context.cgContext.strokePath()

            for route in routeSets where route.count > 1 {
                let path = UIBezierPath()
                for (index, point) in route.enumerated() {
                    if index == 0 { path.move(to: mapped(point)) } else { path.addLine(to: mapped(point)) }
                }
                UIColor(red: 0.05, green: 0.35, blue: 0.68, alpha: 1).setStroke()
                path.lineWidth = 4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }
    }
}

enum FireVaultTripLogPDFRenderer {
    private static let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let navy = UIColor(red: 0.04, green: 0.18, blue: 0.31, alpha: 1)
    private static let blue = UIColor(red: 0.05, green: 0.35, blue: 0.68, alpha: 1)
    private static let red = UIColor(red: 0.82, green: 0.12, blue: 0.10, alpha: 1)
    private static let paleBlue = UIColor(red: 0.93, green: 0.97, blue: 1, alpha: 1)
    private static let lightLine = UIColor(white: 0.87, alpha: 1)
    private static let paper = UIColor(red: 0.985, green: 0.988, blue: 0.992, alpha: 1)

    private struct WeeklyDetailPage {
        let day: FireVaultBreadcrumbReport
        let visits: [FireVaultBreadcrumbReport.Visit]
        let part: Int
        let partCount: Int
    }

    static func daily(
        report: FireVaultBreadcrumbReport,
        detail: FireVaultTripLogReportDetail,
        mapImage: UIImage?
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            var y: CGFloat = 0

            func beginPage() {
                context.beginPage()
                y = drawHeader(
                        title: "TRIP LOG DAILY REPORT",
                        dateTitle: report.monthText,
                        dateMain: report.dayText,
                        dateFooter: report.yearText,
                        technician: report.technicianName,
                        company: report.companyName,
                        page: 1,
                        generatedAt: report.generatedAt
                    )
            }

            beginPage()
            y = drawMetrics(
                [
                    ("DISTANCE", report.distanceText),
                    ("TIME", report.elapsedText),
                    ("STOPS", "\(report.visits.count)"),
                    ("START", report.startTimeText),
                    ("END", report.endTimeText)
                ],
                y: y
            )
            y += 8
            y = drawMap(mapImage, y: y, size: .init(width: 528, height: 148))
            y += 8
            y = drawRoutePerformance(
                elevationSets: [report.elevationProfileFeet],
                speedSets: [report.speedProfileMPH],
                stopFractions: report.stopProgressFractions,
                averageSpeed: report.averageSpeedMPH,
                y: y
            )
            y += 8
            y = drawSectionTitle("STOP DETAILS", y: y)
            y = drawStopTableHeader(y: y)

            if report.visits.isEmpty {
                y += drawText("No stops were recorded for this workday.", font: .systemFont(ofSize: 10), color: .darkGray, x: 42, y: y + 12, width: 528)
            } else {
                let availableHeight = max(30, 742 - y)
                let rowBudget = max(1, Int(availableHeight / 30))
                let visits = Array(report.visits.prefix(rowBudget))
                let rowHeight = min(48, max(30, availableHeight / CGFloat(max(1, visits.count))))
                for visit in visits {
                    y = drawStopRow(visit, note: "", y: y, height: rowHeight)
                }
                if report.visits.count > visits.count {
                    _ = drawText(
                        "+ \(report.visits.count - visits.count) additional stops summarized in the Trip Log archive.",
                        font: .italicSystemFont(ofSize: 9),
                        color: .darkGray,
                        x: 42,
                        y: y + 10,
                        width: 528
                    )
                }
            }
        }
    }

    static func weekly(
        report: FireVaultTripLogWeeklyReport,
        detail: FireVaultTripLogReportDetail,
        mapImage: UIImage?
    ) -> Data {
        let detailSections = detail == .detailed ? makeWeeklyDetailPages(report.dailyReports) : []
        let detailPages = packWeeklyDetailPages(detailSections)
        let totalPages = 1 + detailPages.count
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            context.beginPage()
            var y = drawHeader(
                title: "TRIP LOG WEEKLY REPORT",
                dateTitle: "WEEK OF",
                dateMain: report.weekStart.formatted(.dateTime.month(.abbreviated).day()),
                dateFooter: report.weekEnd.formatted(.dateTime.month(.abbreviated).day().year()),
                technician: report.technicianName,
                company: report.companyName,
                page: 1,
                totalPages: totalPages,
                generatedAt: report.generatedAt
            )
            y = drawMetrics(
                [
                    ("DISTANCE", report.distanceText),
                    ("ON DUTY", report.elapsedText),
                    ("STOPS", "\(report.totalStopCount)"),
                    ("WORKDAYS", "\(report.dailyReports.count)"),
                    ("ACCOUNT VISITS", "\(report.accountVisitCount)")
                ],
                y: y
            )
            y += 8
            y = drawMap(mapImage, y: y, size: .init(width: 528, height: 160))
            y += 10
            y = drawSectionTitle("WEEK AT A GLANCE", y: y)
            y = drawWeeklyHeader(y: y)
            for day in report.dailyReports {
                y = drawWeeklyRow(day, y: y)
            }
            if report.dailyReports.isEmpty {
                y += drawText("No Trip Log workdays were recorded in this week.", font: .systemFont(ofSize: 10), color: .darkGray, x: 42, y: y + 12, width: 528)
            } else if y < 650 {
                y += 12
                y = drawWeeklyInsights(report, y: y)
            }

            for (index, pageSections) in detailPages.enumerated() {
                let pageNumber = index + 2
                context.beginPage()
                y = drawContinuationHeader(
                    title: "WEEKLY DAILY BREAKDOWN",
                    date: report.dateRangeText,
                    page: pageNumber,
                    totalPages: totalPages,
                    generatedAt: report.generatedAt
                )
                for (sectionIndex, detailPage) in pageSections.enumerated() {
                    if sectionIndex > 0 { y += 16 }
                    y = drawWeeklyDaySpotlight(detailPage, y: y)
                    y += 10
                    y = drawSectionTitle(
                        detailPage.partCount > 1
                            ? "STOP DETAILS • PART \(detailPage.part) OF \(detailPage.partCount)"
                            : "STOP DETAILS",
                        y: y
                    )
                    y = drawStopTableHeader(y: y)

                    if detailPage.visits.isEmpty {
                        y += drawText(
                            "No stops were recorded for this workday.",
                            font: .systemFont(ofSize: 11, weight: .medium),
                            color: .darkGray,
                            x: 48,
                            y: y + 18,
                            width: 516
                        ) + 30
                    } else {
                        for visit in detailPage.visits {
                            y = drawStopRow(visit, note: visit.technicianNote, y: y, height: 38)
                        }
                    }
                }
            }
        }
    }

    private static func makeWeeklyDetailPages(
        _ reports: [FireVaultBreadcrumbReport]
    ) -> [WeeklyDetailPage] {
        let rowsPerPage = 13
        return reports.flatMap { day in
            guard !day.visits.isEmpty else {
                return [WeeklyDetailPage(day: day, visits: [], part: 1, partCount: 1)]
            }
            let partCount = Int(ceil(Double(day.visits.count) / Double(rowsPerPage)))
            return stride(from: 0, to: day.visits.count, by: rowsPerPage).enumerated().map { partIndex, start in
                let end = min(day.visits.count, start + rowsPerPage)
                return WeeklyDetailPage(
                    day: day,
                    visits: Array(day.visits[start..<end]),
                    part: partIndex + 1,
                    partCount: partCount
                )
            }
        }
    }

    private static func packWeeklyDetailPages(
        _ sections: [WeeklyDetailPage]
    ) -> [[WeeklyDetailPage]] {
        let availableHeight: CGFloat = 742 - 97
        var pages: [[WeeklyDetailPage]] = []
        var current: [WeeklyDetailPage] = []
        var usedHeight: CGFloat = 0

        for section in sections {
            let rowsHeight = section.visits.isEmpty ? 48 : CGFloat(section.visits.count) * 38
            let sectionHeight: CGFloat = 78 + 10 + 22 + 24 + rowsHeight
            let spacing: CGFloat = current.isEmpty ? 0 : 16
            if !current.isEmpty, usedHeight + spacing + sectionHeight > availableHeight {
                pages.append(current)
                current = []
                usedHeight = 0
            }
            current.append(section)
            usedHeight += (current.count == 1 ? 0 : spacing) + sectionHeight
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    private static func drawHeader(
        title: String,
        dateTitle: String,
        dateMain: String,
        dateFooter: String,
        technician: String,
        company: String,
        page: Int,
        totalPages: Int = 1,
        generatedAt: Date
    ) -> CGFloat {
        paper.setFill()
        pageBounds.fill()

        let masthead = CGRect(x: 24, y: 22, width: 564, height: 100)
        navy.setFill()
        UIBezierPath(roundedRect: masthead, cornerRadius: 18).fill()

        drawFireVaultProWordmark(x: 42, y: 35, fontSize: 25)
        drawText(title, font: .systemFont(ofSize: 11.5, weight: .bold), color: .white, x: 42, y: 78, width: 374)

        let identity = [
            company,
            technician.isEmpty ? "Technician not configured" : technician
        ].filter { !$0.isEmpty }.joined(separator: "  |  ")
        drawText(identity, font: .systemFont(ofSize: 9.5, weight: .medium), color: UIColor.white.withAlphaComponent(0.76), x: 42, y: 98, width: 414)

        let badge = CGRect(x: 476, y: 34, width: 90, height: 76)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: badge, cornerRadius: 13).fill()
        UIColor.white.withAlphaComponent(0.35).setStroke()
        let badgeOutline = UIBezierPath(roundedRect: badge, cornerRadius: 10)
        badgeOutline.lineWidth = 1
        badgeOutline.stroke()
        let cap = CGRect(x: badge.minX, y: badge.minY, width: badge.width, height: 24)
        red.setFill()
        UIBezierPath(roundedRect: cap, byRoundingCorners: [.topLeft, .topRight], cornerRadii: .init(width: 13, height: 13)).fill()
        drawCenteredText(dateTitle.uppercased(), font: .systemFont(ofSize: 8.5, weight: .bold), color: .white, rect: cap)
        drawCenteredText(dateMain, font: .systemFont(ofSize: 17, weight: .bold), color: navy, rect: CGRect(x: badge.minX, y: badge.minY + 28, width: badge.width, height: 25))
        drawCenteredText(dateFooter, font: .systemFont(ofSize: 8, weight: .bold), color: navy, rect: CGRect(x: badge.minX, y: badge.minY + 56, width: badge.width, height: 15))

        red.setFill()
        CGRect(x: masthead.minX + 18, y: masthead.maxY - 3, width: 88, height: 3).fill()
        drawFooter(page: page, totalPages: totalPages, generatedAt: generatedAt)
        return 139
    }

    private static func drawContinuationHeader(
        title: String,
        date: String,
        page: Int,
        totalPages: Int,
        generatedAt: Date
    ) -> CGFloat {
        paper.setFill()
        pageBounds.fill()
        let bar = CGRect(x: 24, y: 22, width: 564, height: 58)
        navy.setFill()
        UIBezierPath(roundedRect: bar, cornerRadius: 16).fill()
        drawFireVaultProWordmark(x: 38, y: 33, fontSize: 16)
        drawText(title, font: .systemFont(ofSize: 8.5, weight: .bold), color: UIColor.white.withAlphaComponent(0.78), x: 38, y: 55, width: 274)
        drawText(date, font: .systemFont(ofSize: 8.5, weight: .semibold), color: .white, x: 352, y: 45, width: 214, alignment: .right)
        drawFooter(page: page, totalPages: totalPages, generatedAt: generatedAt)
        return 97
    }

    private static func drawMetrics(_ metrics: [(String, String)], y: CGFloat) -> CGFloat {
        let rect = CGRect(x: 42, y: y, width: 528, height: 50)
        paleBlue.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
        let width = rect.width / CGFloat(metrics.count)
        for (index, metric) in metrics.enumerated() {
            let metricRect = CGRect(x: rect.minX + CGFloat(index) * width, y: rect.minY, width: width, height: rect.height)
            drawCenteredText(metric.1, font: .systemFont(ofSize: 12.5, weight: .bold), color: navy, rect: CGRect(x: metricRect.minX + 4, y: metricRect.minY + 7, width: metricRect.width - 8, height: 19))
            drawCenteredText(metric.0, font: .systemFont(ofSize: 7.5, weight: .bold), color: .darkGray, rect: CGRect(x: metricRect.minX + 4, y: metricRect.minY + 29, width: metricRect.width - 8, height: 14))
            if index < metrics.count - 1 {
                lightLine.setStroke()
                let line = UIBezierPath()
                line.move(to: .init(x: metricRect.maxX, y: rect.minY + 10))
                line.addLine(to: .init(x: metricRect.maxX, y: rect.maxY - 10))
                line.lineWidth = 0.7
                line.stroke()
            }
        }
        return rect.maxY
    }

    private static func drawMap(_ image: UIImage?, y: CGFloat, size: CGSize) -> CGFloat {
        _ = drawSectionTitle("ROUTE MAP", y: y)
        let imageY = y + 19
        let resolvedHeight: CGFloat = image == nil ? 62 : size.height
        let resolvedWidth: CGFloat = image == nil ? 528 : size.width
        let rect = CGRect(x: (pageBounds.width - resolvedWidth) / 2, y: imageY, width: resolvedWidth, height: resolvedHeight)
        if let image {
            UIGraphicsGetCurrentContext()?.saveGState()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).addClip()
            let scale = max(rect.width / max(1, image.size.width), rect.height / max(1, image.size.height))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let drawRect = CGRect(
                x: rect.midX - drawSize.width / 2,
                y: rect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            image.draw(in: drawRect)
            UIGraphicsGetCurrentContext()?.restoreGState()
        } else {
            paleBlue.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
            drawCenteredText("No GPS route points were recorded", font: .systemFont(ofSize: 10, weight: .medium), color: .darkGray, rect: rect)
        }
        lightLine.setStroke()
        let outline = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        outline.lineWidth = 0.8
        outline.stroke()
        return rect.maxY
    }

    private static func drawRoutePerformance(
        elevationSets: [[Double]],
        speedSets: [[Double]],
        stopFractions: [Double],
        averageSpeed: Double?,
        y: CGFloat
    ) -> CGFloat {
        _ = drawSectionTitle("TRIP PROFILE", y: y)
        let graphY = y + 19
        let rect = CGRect(x: 42, y: graphY, width: 528, height: 98)
        paleBlue.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 10).fill()
        lightLine.setStroke()
        let outline = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        outline.lineWidth = 0.8
        outline.stroke()

        let validSets = elevationSets.filter { $0.count >= 2 }
        let elevations = validSets.flatMap { $0 }
        let validSpeeds = speedSets.filter { $0.count >= 2 }
        let speeds = validSpeeds.flatMap { $0 }
        let maximumSpeed = max(1, speeds.max() ?? 1)
        guard elevations.count >= 2 || speeds.count >= 2 else {
            drawCenteredText(
                "Elevation and speed samples were not recorded for this Trip Log",
                font: .systemFont(ofSize: 9, weight: .medium),
                color: .darkGray,
                rect: rect
            )
            return rect.maxY
        }

        let minimum = elevations.min() ?? 0
        let maximum = elevations.max() ?? minimum + 1
        let plotX = rect.minX + 66
        let plotWidth = rect.width - 80
        let elevationPlot = CGRect(x: plotX, y: rect.minY + 20, width: plotWidth, height: 28)
        let speedPlot = CGRect(x: plotX, y: rect.minY + 57, width: plotWidth, height: 18)
        let range = max(1, maximum - minimum)

        drawText("ELEVATION", font: .systemFont(ofSize: 7.4, weight: .bold), color: blue, x: rect.minX + 8, y: elevationPlot.midY - 9, width: 54)
        drawText("FEET", font: .systemFont(ofSize: 6.4, weight: .semibold), color: .gray, x: rect.minX + 8, y: elevationPlot.midY + 2, width: 54)
        drawText("SPEED", font: .systemFont(ofSize: 7.4, weight: .bold), color: red, x: rect.minX + 8, y: speedPlot.midY - 9, width: 54)
        drawText("0–\(Int(maximumSpeed.rounded())) MPH", font: .systemFont(ofSize: 6.2, weight: .semibold), color: .gray, x: rect.minX + 8, y: speedPlot.midY + 2, width: 54)

        UIColor(white: 0.78, alpha: 0.65).setStroke()
        for plot in [elevationPlot, speedPlot] {
            for gridIndex in 0...2 {
                let gridY = plot.minY + plot.height * CGFloat(gridIndex) / 2
                let grid = UIBezierPath()
                grid.move(to: .init(x: plot.minX, y: gridY))
                grid.addLine(to: .init(x: plot.maxX, y: gridY))
                grid.lineWidth = 0.4
                grid.stroke()
            }
        }

        let segmentWidth = elevationPlot.width / CGFloat(max(1, validSets.count))
        for (setIndex, set) in validSets.enumerated() {
            let path = UIBezierPath()
            for (pointIndex, elevation) in set.enumerated() {
                let fraction = CGFloat(pointIndex) / CGFloat(max(1, set.count - 1))
                let x = elevationPlot.minX + CGFloat(setIndex) * segmentWidth + fraction * segmentWidth
                let graphY = elevationPlot.minY + CGFloat((maximum - elevation) / range) * elevationPlot.height
                if pointIndex == 0 { path.move(to: .init(x: x, y: graphY)) }
                else { path.addLine(to: .init(x: x, y: graphY)) }
            }
            blue.setStroke()
            path.lineWidth = 2.3
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        let speedSegmentWidth = speedPlot.width / CGFloat(max(1, validSpeeds.count))
        for (setIndex, set) in validSpeeds.enumerated() {
            let path = UIBezierPath()
            for (pointIndex, speed) in set.enumerated() {
                let fraction = CGFloat(pointIndex) / CGFloat(max(1, set.count - 1))
                let x = speedPlot.minX + CGFloat(setIndex) * speedSegmentWidth + fraction * speedSegmentWidth
                let graphY = speedPlot.minY + CGFloat(1 - speed / maximumSpeed) * speedPlot.height
                if pointIndex == 0 { path.move(to: .init(x: x, y: graphY)) }
                else { path.addLine(to: .init(x: x, y: graphY)) }
            }
            red.setStroke()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        if validSpeeds.isEmpty {
            drawCenteredText("Speed samples unavailable", font: .systemFont(ofSize: 7.2, weight: .medium), color: .gray, rect: speedPlot)
        }

        if let averageSpeed {
            let averageY = speedPlot.minY + CGFloat(1 - min(averageSpeed, maximumSpeed) / maximumSpeed) * speedPlot.height
            let averagePath = UIBezierPath()
            averagePath.move(to: .init(x: speedPlot.minX, y: averageY))
            averagePath.addLine(to: .init(x: speedPlot.maxX, y: averageY))
            UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1).setStroke()
            averagePath.lineWidth = 1
            averagePath.setLineDash([4, 3], count: 2, phase: 0)
            averagePath.stroke()
            drawText("AVG \(Int(averageSpeed.rounded())) MPH", font: .systemFont(ofSize: 7.5, weight: .bold), color: UIColor(red: 0.18, green: 0.58, blue: 0.28, alpha: 1), x: rect.midX - 55, y: rect.minY + 5, width: 110, alignment: .center)
        }

        let markerFractions = [0.0] + stopFractions + [1.0]
        for (index, fraction) in markerFractions.enumerated() {
            let x = elevationPlot.minX + CGFloat(min(1, max(0, fraction))) * elevationPlot.width
            let marker = UIBezierPath()
            marker.move(to: .init(x: x, y: elevationPlot.minY))
            marker.addLine(to: .init(x: x, y: speedPlot.maxY))
            (index == 0 ? UIColor.systemGreen : (index == markerFractions.count - 1 ? navy : red)).setStroke()
            marker.lineWidth = 0.8
            marker.setLineDash([2, 2], count: 2, phase: 0)
            marker.stroke()
        }

        drawText(
            "HIGH \(Int(maximum.rounded()).formatted()) FT",
            font: .systemFont(ofSize: 7.2, weight: .bold),
            color: navy,
            x: elevationPlot.minX,
            y: rect.minY + 4,
            width: 125
        )
        drawText(
            "LOW \(Int(minimum.rounded()).formatted()) FT",
            font: .systemFont(ofSize: 7.2, weight: .bold),
            color: navy,
            x: elevationPlot.maxX - 135,
            y: rect.minY + 4,
            width: 125,
            alignment: .right
        )
        drawText("START", font: .systemFont(ofSize: 7, weight: .bold), color: .systemGreen, x: elevationPlot.minX, y: rect.maxY - 14, width: 48)
        drawText("STOPS", font: .systemFont(ofSize: 6.3, weight: .bold), color: red, x: rect.midX - 30, y: rect.maxY - 12, width: 60, alignment: .center)
        drawText("END", font: .systemFont(ofSize: 7, weight: .bold), color: navy, x: elevationPlot.maxX - 48, y: rect.maxY - 14, width: 48, alignment: .right)
        return rect.maxY
    }

    private static func drawSectionTitle(_ title: String, y: CGFloat) -> CGFloat {
        red.setFill()
        UIBezierPath(roundedRect: CGRect(x: 42, y: y + 1, width: 4, height: 12), cornerRadius: 2).fill()
        let height = drawText(title.uppercased(), font: .systemFont(ofSize: 10, weight: .bold), color: navy, x: 54, y: y, width: 516)
        return y + height + 8
    }

    private static func drawStopTableHeader(y: CGFloat) -> CGFloat {
        let rect = CGRect(x: 42, y: y, width: 528, height: 24)
        navy.setFill()
        rect.fill()
        drawText("#", font: .systemFont(ofSize: 8, weight: .bold), color: .white, x: 48, y: y + 6, width: 20)
        drawText("TIME RANGE", font: .systemFont(ofSize: 8, weight: .bold), color: .white, x: 76, y: y + 6, width: 88)
        drawText("LOCATION / ACCOUNT", font: .systemFont(ofSize: 8, weight: .bold), color: .white, x: 170, y: y + 6, width: 305)
        drawText("DURATION", font: .systemFont(ofSize: 8, weight: .bold), color: .white, x: 488, y: y + 6, width: 76)
        return rect.maxY
    }

    private static func drawFooter(
        page: Int,
        totalPages: Int = 1,
        generatedAt: Date = Date()
    ) {
        lightLine.setStroke()
        let line = UIBezierPath()
        line.move(to: .init(x: 42, y: 758))
        line.addLine(to: .init(x: 570, y: 758))
        line.lineWidth = 0.7
        line.stroke()
        drawText("FIREVAULT PRO  •  BANNERMAN US LLC", font: .systemFont(ofSize: 7, weight: .bold), color: navy, x: 42, y: 766, width: 245)
        drawText("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))", font: .systemFont(ofSize: 6.7, weight: .medium), color: .gray, x: 235, y: 766, width: 220, alignment: .center)
        drawText("PAGE \(page) OF \(totalPages)", font: .monospacedSystemFont(ofSize: 7, weight: .semibold), color: .gray, x: 470, y: 766, width: 100, alignment: .right)
    }

    private static func drawFireVaultProWordmark(x: CGFloat, y: CGFloat, fontSize: CGFloat) {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .black)
        let fireWidth = ceil(NSString(string: "FIRE").size(withAttributes: [.font: font]).width)
        let vaultWidth = ceil(NSString(string: "VAULT").size(withAttributes: [.font: font]).width)
        let letterGap: CGFloat = 3
        let wordmarkWidth = fireWidth + letterGap + vaultWidth
        drawText("FIRE", font: font, color: red, x: x, y: y, width: fireWidth + 2)
        drawText("VAULT", font: font, color: .white, x: x + fireWidth + letterGap, y: y, width: vaultWidth + 3)

        let baselineY = y + fontSize + 6
        let proWidth = max(25, fontSize * 1.32)
        let proRect = CGRect(x: x + wordmarkWidth - proWidth, y: baselineY - 6, width: proWidth, height: 12)
        UIColor.white.withAlphaComponent(0.78).setStroke()
        let underline = UIBezierPath()
        underline.move(to: CGPoint(x: x, y: baselineY))
        underline.addLine(to: CGPoint(x: proRect.minX - 7, y: baselineY))
        underline.lineWidth = max(1, fontSize * 0.055)
        underline.stroke()

        drawCenteredText("PRO", font: .systemFont(ofSize: max(7, fontSize * 0.34), weight: .black), color: .white, rect: proRect)
    }

    private static func stopRowHeight(visit: FireVaultBreadcrumbReport.Visit, note: String) -> CGFloat {
        var height: CGFloat = 30
        if !visit.addressText.isEmpty { height += 6 }
        if !note.isEmpty { height += min(18, CGFloat(note.count / 70 + 1) * 7) }
        if visit.coordinateText != nil { height += 6 }
        return height
    }

    private static func drawStopRow(
        _ visit: FireVaultBreadcrumbReport.Visit,
        note: String,
        y: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        if visit.sequence.isMultiple(of: 2) {
            UIColor(red: 0.975, green: 0.985, blue: 0.995, alpha: 1).setFill()
            CGRect(x: 42, y: y, width: 528, height: height).fill()
        }

        let contentTop = y + max(6, (height - 30) / 2)
        let badge = CGRect(x: 47, y: y + (height - 20) / 2, width: 20, height: 20)
        blue.setFill()
        UIBezierPath(ovalIn: badge).fill()
        drawCenteredText("\(visit.sequence)", font: .systemFont(ofSize: 8.5, weight: .bold), color: .white, rect: badge)

        drawText(visit.reportTimeText, font: .monospacedSystemFont(ofSize: height >= 40 ? 8.2 : 7.5, weight: .medium), color: .darkGray, x: 76, y: contentTop, width: 88)
        var locationY = contentTop
        locationY += drawText(visit.title, font: .systemFont(ofSize: height >= 40 ? 10.5 : 9.5, weight: .semibold), color: navy, x: 170, y: locationY, width: 305) + 1
        if !visit.addressText.isEmpty {
            locationY += drawText(visit.addressText, font: .systemFont(ofSize: height >= 40 ? 8.4 : 7.5), color: .darkGray, x: 170, y: locationY, width: 305) + 1
        }
        if !note.isEmpty {
            locationY += drawText("Note: \(note)", font: .italicSystemFont(ofSize: 7.2), color: .darkGray, x: 170, y: locationY, width: 305) + 1
        }
        if height >= 44, let coordinates = visit.coordinateText {
            _ = drawText("GPS: \(coordinates)", font: .monospacedSystemFont(ofSize: 6.7, weight: .regular), color: .gray, x: 170, y: locationY, width: 305)
        }
        let durationRect = CGRect(x: 492, y: y + (height - 22) / 2, width: 68, height: 22)
        paleBlue.setFill()
        UIBezierPath(roundedRect: durationRect, cornerRadius: 10).fill()
        drawCenteredText(visit.durationText, font: .monospacedSystemFont(ofSize: 8.5, weight: .semibold), color: navy, rect: durationRect)

        lightLine.setStroke()
        let line = UIBezierPath()
        line.move(to: .init(x: 42, y: y + height))
        line.addLine(to: .init(x: 570, y: y + height))
        line.lineWidth = 0.6
        line.stroke()
        return y + height
    }

    private static func drawWeeklyDaySpotlight(
        _ page: WeeklyDetailPage,
        y: CGFloat
    ) -> CGFloat {
        let rect = CGRect(x: 42, y: y, width: 528, height: 78)
        paleBlue.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 14).fill()
        lightLine.setStroke()
        let outline = UIBezierPath(roundedRect: rect, cornerRadius: 14)
        outline.lineWidth = 0.8
        outline.stroke()

        red.setFill()
        UIBezierPath(
            roundedRect: CGRect(x: rect.minX, y: rect.minY, width: 6, height: rect.height),
            byRoundingCorners: [.topLeft, .bottomLeft],
            cornerRadii: .init(width: 14, height: 14)
        ).fill()

        let day = page.day
        drawText(
            day.startedAt.formatted(.dateTime.weekday(.wide)).uppercased(),
            font: .systemFont(ofSize: 15, weight: .black),
            color: navy,
            x: 58,
            y: y + 10,
            width: 222
        )
        let savedName = day.sourceDay.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        drawText(
            savedName.isEmpty ? day.startedAt.formatted(date: .long, time: .omitted) : savedName,
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: blue,
            x: 58,
            y: y + 33,
            width: 222
        )
        drawText(
            "\(day.startTimeText) – \(day.endTimeText)",
            font: .monospacedSystemFont(ofSize: 8.5, weight: .medium),
            color: .darkGray,
            x: 58,
            y: y + 51,
            width: 222
        )
        if page.partCount > 1 {
            drawText(
                "PAGE SECTION \(page.part) OF \(page.partCount)",
                font: .systemFont(ofSize: 6.8, weight: .bold),
                color: red,
                x: 176,
                y: y + 53,
                width: 104,
                alignment: .right
            )
        }

        let metrics = [
            ("DISTANCE", day.distanceText),
            ("ON DUTY", day.elapsedText),
            ("STOPS", "\(day.visits.count)")
        ]
        let metricStartX: CGFloat = 302
        let metricWidth: CGFloat = 84
        for (index, metric) in metrics.enumerated() {
            let x = metricStartX + CGFloat(index) * metricWidth
            drawCenteredText(
                metric.1,
                font: .systemFont(ofSize: 11.5, weight: .bold),
                color: navy,
                rect: CGRect(x: x, y: y + 20, width: metricWidth, height: 20)
            )
            drawCenteredText(
                metric.0,
                font: .systemFont(ofSize: 6.8, weight: .bold),
                color: .darkGray,
                rect: CGRect(x: x, y: y + 43, width: metricWidth, height: 14)
            )
            if index > 0 {
                lightLine.setStroke()
                let line = UIBezierPath()
                line.move(to: .init(x: x, y: y + 17))
                line.addLine(to: .init(x: x, y: y + 61))
                line.lineWidth = 0.7
                line.stroke()
            }
        }
        return rect.maxY
    }

    private static func drawWeeklyInsights(
        _ report: FireVaultTripLogWeeklyReport,
        y: CGFloat
    ) -> CGFloat {
        var cursor = drawSectionTitle("WEEKLY INSIGHTS", y: y)
        let rect = CGRect(x: 42, y: cursor, width: 528, height: 62)
        paleBlue.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
        lightLine.setStroke()
        let outline = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        outline.lineWidth = 0.8
        outline.stroke()

        let longestDay = report.dailyReports.max { $0.totalDistanceMeters < $1.totalDistanceMeters }
        let averageDistance = report.dailyReports.isEmpty
            ? 0
            : report.totalDistanceMeters / Double(report.dailyReports.count)
        let insights: [(String, String, String)] = [
            (
                "LONGEST ROUTE",
                longestDay?.startedAt.formatted(.dateTime.weekday(.wide)) ?? "—",
                longestDay?.distanceText ?? "No route"
            ),
            (
                "AVERAGE / WORKDAY",
                FireVaultBreadcrumbReport.distanceText(averageDistance),
                "Across \(report.dailyReports.count) recorded day\(report.dailyReports.count == 1 ? "" : "s")"
            ),
            (
                "NEEDS REVIEW",
                "\(report.unassignedVisitCount)",
                report.unassignedVisitCount == 0 ? "All stops identified" : "Unrecognized stops"
            )
        ]
        let width = rect.width / CGFloat(insights.count)
        for (index, insight) in insights.enumerated() {
            let item = CGRect(x: rect.minX + CGFloat(index) * width, y: rect.minY, width: width, height: rect.height)
            drawCenteredText(insight.0, font: .systemFont(ofSize: 6.8, weight: .bold), color: .darkGray, rect: CGRect(x: item.minX + 6, y: item.minY + 8, width: item.width - 12, height: 12))
            drawCenteredText(insight.1, font: .systemFont(ofSize: 11, weight: .bold), color: navy, rect: CGRect(x: item.minX + 6, y: item.minY + 23, width: item.width - 12, height: 17))
            drawCenteredText(insight.2, font: .systemFont(ofSize: 6.8, weight: .medium), color: .gray, rect: CGRect(x: item.minX + 6, y: item.minY + 42, width: item.width - 12, height: 12))
            if index > 0 {
                lightLine.setStroke()
                let line = UIBezierPath()
                line.move(to: .init(x: item.minX, y: item.minY + 9))
                line.addLine(to: .init(x: item.minX, y: item.maxY - 9))
                line.lineWidth = 0.7
                line.stroke()
            }
        }
        cursor = rect.maxY
        return cursor
    }

    private static func drawWeeklyHeader(y: CGFloat) -> CGFloat {
        let rect = CGRect(x: 42, y: y, width: 528, height: 26)
        navy.setFill()
        rect.fill()
        drawText("WORKDAY / ROUTE WINDOW", font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, x: 48, y: y + 8, width: 252)
        drawText("DISTANCE", font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, x: 315, y: y + 8, width: 70, alignment: .right)
        drawText("ON DUTY", font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, x: 405, y: y + 8, width: 75, alignment: .right)
        drawText("STOPS", font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, x: 520, y: y + 8, width: 40, alignment: .right)
        return rect.maxY
    }

    private static func drawWeeklyRow(_ day: FireVaultBreadcrumbReport, y: CGFloat) -> CGFloat {
        let rowHeight: CGFloat = 40
        drawText(day.startedAt.formatted(.dateTime.weekday(.wide)), font: .systemFont(ofSize: 10, weight: .bold), color: navy, x: 48, y: y + 6, width: 252)
        drawText(
            "\(day.startedAt.formatted(.dateTime.month(.abbreviated).day())) • \(day.startTimeText)–\(day.endTimeText)",
            font: .monospacedSystemFont(ofSize: 7.2, weight: .medium),
            color: .darkGray,
            x: 48,
            y: y + 22,
            width: 252
        )
        drawText(day.distanceText, font: .monospacedSystemFont(ofSize: 8.5, weight: .semibold), color: navy, x: 315, y: y + 13, width: 70, alignment: .right)
        drawText(day.elapsedText, font: .monospacedSystemFont(ofSize: 8.5, weight: .semibold), color: navy, x: 405, y: y + 13, width: 75, alignment: .right)
        drawText("\(day.visits.count)", font: .monospacedSystemFont(ofSize: 8.5, weight: .semibold), color: navy, x: 520, y: y + 13, width: 40, alignment: .right)
        lightLine.setStroke()
        let line = UIBezierPath()
        line.move(to: .init(x: 42, y: y + rowHeight))
        line.addLine(to: .init(x: 570, y: y + rowHeight))
        line.lineWidth = 0.6
        line.stroke()
        return y + rowHeight
    }

    @discardableResult
    private static func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5
        paragraph.alignment = alignment
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

    private static func drawCenteredText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        NSString(string: text).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

struct FireVaultBreadcrumbExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
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

struct FireVaultImageSharePayload: Identifiable {
    let id = UUID()
    let subject: String
    let body: String
    let images: [UIImage]
}

enum FireVaultTripLogImageRenderer {
    static func images(from pdfData: Data) -> [UIImage] {
        guard let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider) else {
            return []
        }

        return (1...document.numberOfPages).compactMap { pageNumber in
            guard let page = document.page(at: pageNumber) else { return nil }
            let bounds = page.getBoxRect(.mediaBox)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: bounds.size))
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: bounds.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                context.cgContext.drawPDFPage(page)
                context.cgContext.restoreGState()
            }
            guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return image }
            return UIImage(data: jpeg) ?? image
        }
    }
}

struct FireVaultActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

final class FireVaultMailSubjectItemSource: NSObject, UIActivityItemSource {
    private let subject: String

    init(subject: String) {
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        ""
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        nil
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject
    }
}

private extension CGRect {
    func fill() {
        UIBezierPath(rect: self).fill()
    }
}
