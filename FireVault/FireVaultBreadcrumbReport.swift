//
//  FireVaultBreadcrumbReport.swift
//  FireVault
//
//  Polished Trip Log reports with daily and weekly PDF export.
//

import MapKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FireVaultTripLogRoutePoint: Equatable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double

    init(
        timestamp: Date = .distantPast,
        latitude: Double,
        longitude: Double
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}

struct FireVaultTripLogMapStop: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case start
        case stop
        case end
    }

    let id: UUID
    let sequence: Int
    let latitude: Double
    let longitude: Double
    let kind: Kind

    init(
        id: UUID,
        sequence: Int,
        latitude: Double,
        longitude: Double,
        kind: Kind = .stop
    ) {
        self.id = id
        self.sequence = sequence
        self.latitude = latitude
        self.longitude = longitude
        self.kind = kind
    }

    var markerText: String {
        switch kind {
        case .start: "S"
        case .stop: "\(sequence)"
        case .end: "E"
        }
    }

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
                else if let latitude, let longitude {
                    "Approx. \(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))"
                } else {
                    "Approximate recorded location"
                }
            case .unassigned:
                if !accountAddress.isEmpty { accountAddress }
                else if let latitude, let longitude {
                    "Approx. \(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))"
                } else {
                    "Approximate recorded location"
                }
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

        var mapStop: FireVaultTripLogMapStop? {
            guard let latitude, let longitude else { return nil }
            return .init(
                id: id,
                sequence: sequence,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    let dayID: UUID
    let tripName: String?
    let startedAt: Date
    let endedAt: Date?
    let generatedAt: Date
    let technicianName: String
    let companyName: String
    let includesCoordinates: Bool
    let totalDistanceMeters: Double
    let elapsedTime: TimeInterval
    let visits: [Visit]
    let routePoints: [FireVaultTripLogRoutePoint]
    let endpoints: FireVaultTripReportEndpoints

    init(
        day: FireVaultBreadcrumbDay,
        technicianName: String,
        companyName: String,
        includeCoordinates: Bool,
        generatedAt: Date = Date()
    ) {
        dayID = day.id
        tripName = day.name
        startedAt = day.startedAt
        endedAt = day.endedAt
        self.generatedAt = generatedAt
        self.technicianName = technicianName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        includesCoordinates = includeCoordinates
        totalDistanceMeters = day.totalDistanceMeters
        elapsedTime = max(0, (day.endedAt ?? generatedAt).timeIntervalSince(day.startedAt))
        var preparedEndpoints = day.reportEndpoints ?? FireVaultTripEndpointResolver.fallback(
            day: day,
            resolvedAt: generatedAt
        )
        if !includeCoordinates {
            preparedEndpoints.start.latitude = nil
            preparedEndpoints.start.longitude = nil
            preparedEndpoints.end.latitude = nil
            preparedEndpoints.end.longitude = nil
        }
        endpoints = preparedEndpoints
        routePoints = includeCoordinates ? day.points.map {
            .init(timestamp: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude)
        } : []
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

    var cityRouteText: String {
        let start = endpoints.start.city.isEmpty ? endpoints.start.displayTitle : endpoints.start.city
        let end = endpoints.end.city.isEmpty ? endpoints.end.displayTitle : endpoints.end.city
        return "\(start) – \(end)"
    }

    var mapStops: [FireVaultTripLogMapStop] {
        visits
            .filter { $0.classification != .personal }
            .compactMap(\.mapStop)
    }

    var mapMarkers: [FireVaultTripLogMapStop] {
        var markers: [FireVaultTripLogMapStop] = []
        if !endpoints.start.isPrivate, let coordinate = endpoints.start.coordinate {
            markers.append(
                .init(
                    id: endpointMarkerID(suffix: "1"),
                    sequence: 0,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    kind: .start
                )
            )
        }
        markers.append(contentsOf: mapStops)
        if !endpoints.end.isPrivate, let coordinate = endpoints.end.coordinate {
            markers.append(
                .init(
                    id: endpointMarkerID(suffix: "2"),
                    sequence: visits.count + 1,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    kind: .end
                )
            )
        }
        return markers
    }

    func endpointAddress(_ endpoint: FireVaultTripEndpoint) -> String {
        endpoint.reportAddress(includesCoordinates: includesCoordinates)
    }

    private func endpointMarkerID(suffix: Character) -> UUID {
        let value = String(dayID.uuidString.dropLast()) + String(suffix)
        return UUID(uuidString: value) ?? dayID
    }

    var mapRegion: MKCoordinateRegion {
        Self.region(for: routePoints.map(\.coordinate) + mapMarkers.map(\.coordinate))
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
            "TRIP LOCATIONS",
            "Start: \(endpoints.start.displayTitle) — \(endpointAddress(endpoints.start))",
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
        lines.append("End: \(endpoints.end.displayTitle) — \(endpointAddress(endpoints.end))")
        lines.append("")
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

        func endpointRow(_ label: String, endpoint: FireVaultTripEndpoint) -> [String] {
            [
                label,
                endpoint.timestamp.formatted(.iso8601.year().month().day().dateSeparator(.dash)),
                endpoint.timestamp.formatted(.iso8601.time(includingFractionalSeconds: false)),
                "",
                "",
                label == "START" ? "Trip Start" : "Trip End",
                endpoint.displayTitle,
                endpointAddress(endpoint),
                "",
                "",
                includesCoordinates ? endpoint.latitude.map { String(format: "%.6f", $0) } ?? "" : "",
                includesCoordinates ? endpoint.longitude.map { String(format: "%.6f", $0) } ?? "" : ""
            ]
        }

        rows.append(endpointRow("START", endpoint: endpoints.start))

        for visit in visits {
            rows.append([
                "STOP \(visit.sequence)",
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
        rows.append(endpointRow("END", endpoint: endpoints.end))

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

    private static func cityName(from address: String) -> String? {
        let city = FireVaultPostalAddress(combinedAddress: address)?.city
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return city.isEmpty ? nil : city
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

    var mapStops: [FireVaultTripLogMapStop] {
        var sequence = 0
        return dailyReports.flatMap { daily in
            daily.mapMarkers.map { marker in
                if marker.kind == .stop { sequence += 1 }
                return .init(
                    id: marker.id,
                    sequence: marker.kind == .stop ? sequence : marker.sequence,
                    latitude: marker.latitude,
                    longitude: marker.longitude,
                    kind: marker.kind
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
            "Distance: \(distanceText) • Elapsed: \(elapsedText) • Stops: \(totalStopCount)",
            "Needs review: \(unassignedVisitCount) • Personal: \(personalStopCount)",
            ""
        ]
        for day in dailyReports {
            lines.append(day.startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            lines.append(day.cityRouteText)
            lines.append("\(day.distanceText) • \(day.elapsedText) • \(day.visits.count) stops")
            lines.append("Start: \(day.endpoints.start.displayTitle) — \(day.endpointAddress(day.endpoints.start))")
            for visit in day.visits {
                lines.append("  \(visit.arrivalText)  \(visit.title)  \(visit.durationText)")
            }
            if day.visits.isEmpty { lines.append("  No stops were recorded.") }
            lines.append("End: \(day.endpoints.end.displayTitle) — \(day.endpointAddress(day.endpoints.end))")
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
        availableDays: [FireVaultBreadcrumbDay]
    ) {
        self.report = report
        self.availableDays = availableDays
    }

    private var weeklyReport: FireVaultTripLogWeeklyReport {
        .init(
            days: availableDays,
            anchorDate: report.startedAt,
            technicianName: report.technicianName,
            companyName: report.companyName,
            includeCoordinates: report.includesCoordinates,
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
                        : "Weekly creates a paginated overview followed by complete trip and stop details."
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
                    stops: report.mapMarkers,
                    region: report.mapRegion,
                    aspectRatio: 1
                )
                dailyStopDetails
                reportFooter(generatedAt: report.generatedAt)
            } else {
                weeklyHeader
                reportDivider
                weeklyMetricStrip
                routeMap(
                    routeSets: weeklyReport.routeSets,
                    stops: weeklyReport.mapStops,
                    region: weeklyReport.mapRegion,
                    aspectRatio: 1.9
                )
                weeklyDaySummary
                weeklyStopDetails
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
            ("STOPS", "\(weeklyReport.totalStopCount)", "mappin.and.ellipse")
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

            if routeSets.flatMap({ $0 }).isEmpty, stops.isEmpty {
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
                        Annotation(stop.kind == .stop ? "Stop \(stop.sequence)" : stop.markerText, coordinate: stop.coordinate) {
                            Text(stop.markerText)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(markerColor(stop.kind), in: Circle())
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

    private func markerColor(_ kind: FireVaultTripLogMapStop.Kind) -> Color {
        switch kind {
        case .start: FireVaultTripLogReportPalette.green
        case .stop: FireVaultTripLogReportPalette.blue
        case .end: FireVaultTripLogReportPalette.red
        }
    }

    private var dailyStopDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRIP LOCATIONS")
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

            weeklyEndpointRow(
                label: "START",
                endpoint: report.endpoints.start,
                address: report.endpointAddress(report.endpoints.start),
                color: FireVaultTripLogReportPalette.green
            )
            if report.visits.isEmpty {
                Text("No stops were recorded for this workday.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                stopTableHeader
                ForEach(report.visits) { visit in
                    stopTableRow(visit)
                }
            }
            weeklyEndpointRow(
                label: "END",
                endpoint: report.endpoints.end,
                address: report.endpointAddress(report.endpoints.end),
                color: FireVaultTripLogReportPalette.red
            )
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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.startedAt.formatted(.dateTime.weekday(.wide)))
                                    .fontWeight(.semibold)
                                Text(day.startedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Label(day.cityRouteText, systemImage: "arrow.trianglehead.turn.up.right.diamond.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(FireVaultTripLogReportPalette.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(day.distanceText).frame(width: 52, alignment: .trailing)
                            Text(day.elapsedText).frame(width: 58, alignment: .trailing)
                            Text("\(day.visits.count)").frame(width: 42, alignment: .trailing)
                        }
                        .font(.caption)
                    }
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
                    weeklyEndpointRow(
                        label: "START",
                        endpoint: day.endpoints.start,
                        address: day.endpointAddress(day.endpoints.start),
                        color: FireVaultTripLogReportPalette.green
                    )
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
                    weeklyEndpointRow(
                        label: "END",
                        endpoint: day.endpoints.end,
                        address: day.endpointAddress(day.endpoints.end),
                        color: FireVaultTripLogReportPalette.red
                    )
                }
                .padding(10)
                .background(FireVaultTripLogReportPalette.paleBlue.opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    private func weeklyEndpointRow(
        label: String,
        endpoint: FireVaultTripEndpoint,
        address: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 40, height: 18)
                .background(color, in: Capsule())
            VStack(alignment: .leading, spacing: 1) {
                Text(endpoint.displayTitle).font(.caption.bold())
                Text(address)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                        Text(isGeneratingImages ? "Building Images…" : "Share JPG")
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

                Text("Every JPG report page is shared as a separate image. Personal stops remain redacted.")
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
                stops: report.mapMarkers,
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
                stops: weeklyReport.mapStops,
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
                stops: report.mapMarkers,
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
                stops: weeklyReport.mapStops,
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
        guard !routeSets.flatMap({ $0 }).isEmpty || !stops.isEmpty else { return nil }

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
                drawMarker(stop, at: point)
            }
        }
    }

    private static func fallbackImage(
        routeSets: [[FireVaultTripLogRoutePoint]],
        stops: [FireVaultTripLogMapStop],
        size: CGSize
    ) -> UIImage {
        let allCoordinates = routeSets.flatMap { $0.map(\.coordinate) } + stops.map(\.coordinate)
        let minimumLatitude = allCoordinates.map(\.latitude).min() ?? 0
        let maximumLatitude = allCoordinates.map(\.latitude).max() ?? 1
        let minimumLongitude = allCoordinates.map(\.longitude).min() ?? 0
        let maximumLongitude = allCoordinates.map(\.longitude).max() ?? 1
        let latitudeRange = max(0.0001, maximumLatitude - minimumLatitude)
        let longitudeRange = max(0.0001, maximumLongitude - minimumLongitude)
        let inset: CGFloat = 18

        func mapped(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            let x = inset + CGFloat((coordinate.longitude - minimumLongitude) / longitudeRange) * (size.width - inset * 2)
            let y = inset + CGFloat((maximumLatitude - coordinate.latitude) / latitudeRange) * (size.height - inset * 2)
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
                    if index == 0 { path.move(to: mapped(point.coordinate)) }
                    else { path.addLine(to: mapped(point.coordinate)) }
                }
                UIColor(red: 0.05, green: 0.35, blue: 0.68, alpha: 1).setStroke()
                path.lineWidth = 4
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }

            for stop in stops.prefix(99) {
                drawMarker(stop, at: mapped(stop.coordinate))
            }
        }
    }

    private static func drawMarker(
        _ marker: FireVaultTripLogMapStop,
        at point: CGPoint
    ) {
        let circle = CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)
        switch marker.kind {
        case .start: UIColor.systemGreen.setFill()
        case .stop: UIColor(red: 0.05, green: 0.35, blue: 0.68, alpha: 1).setFill()
        case .end: UIColor(red: 0.82, green: 0.12, blue: 0.10, alpha: 1).setFill()
        }
        UIBezierPath(ovalIn: circle).fill()
        UIColor.white.setStroke()
        let outline = UIBezierPath(ovalIn: circle.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 1.5
        outline.stroke()
        let text = marker.markerText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: marker.sequence > 9 ? 7 : 9, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: .init(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2),
            withAttributes: attributes
        )
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
        let stopPages = makeDailyStopPages(report, detail: detail)
        let totalPages = stopPages.count
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            var y: CGFloat = 0

            func beginSummaryPage() {
                context.beginPage()
                y = drawHeader(
                        title: "TRIP LOG DAILY REPORT",
                        dateTitle: report.monthText,
                        dateMain: report.dayText,
                        dateFooter: report.yearText,
                        technician: report.technicianName,
                        company: report.companyName,
                        page: 1,
                        totalPages: totalPages,
                        generatedAt: report.generatedAt
                    )
            }

            beginSummaryPage()
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
            y = drawSectionTitle("TRIP LOCATIONS", y: y)
            y = drawTripEndpointRow(
                label: "START",
                endpoint: report.endpoints.start,
                report: report,
                color: .systemGreen,
                y: y
            )
            y += 8
            y = drawStopTableHeader(y: y)

            if report.visits.isEmpty {
                y += drawText("No stops were recorded for this workday.", font: .systemFont(ofSize: 10), color: .darkGray, x: 42, y: y + 12, width: 528)
            } else {
                for visit in stopPages[0] {
                    let presentation = dailyStopPresentation(visit, detail: detail)
                    y = drawStopRow(
                        visit,
                        note: presentation.note,
                        y: y,
                        height: presentation.height
                    )
                }
            }

            if stopPages.count == 1 {
                y += 8
                y = drawTripEndpointRow(
                    label: "END",
                    endpoint: report.endpoints.end,
                    report: report,
                    color: red,
                    y: y
                )
            }

            for pageIndex in stopPages.indices.dropFirst() {
                context.beginPage()
                y = drawContinuationHeader(
                    title: "DAILY TRIP LOCATIONS",
                    date: report.dateText,
                    page: pageIndex + 1,
                    totalPages: totalPages,
                    generatedAt: report.generatedAt
                )
                y = drawSectionTitle("TRIP LOCATIONS • CONTINUED", y: y)
                if !stopPages[pageIndex].isEmpty {
                    y = drawStopTableHeader(y: y)
                    for visit in stopPages[pageIndex] {
                        let presentation = dailyStopPresentation(visit, detail: detail)
                        y = drawStopRow(
                            visit,
                            note: presentation.note,
                            y: y,
                            height: presentation.height
                        )
                    }
                }
                if pageIndex == stopPages.indices.last {
                    y += 8
                    y = drawTripEndpointRow(
                        label: "END",
                        endpoint: report.endpoints.end,
                        report: report,
                        color: red,
                        y: y
                    )
                }
            }
        }
    }

    private static func makeDailyStopPages(
        _ report: FireVaultBreadcrumbReport,
        detail: FireVaultTripLogReportDetail
    ) -> [[FireVaultBreadcrumbReport.Visit]] {
        let visits = report.visits
        guard !visits.isEmpty else { return [[]] }

        let firstRowsY: CGFloat = 139
            + 50
            + 8
            + 167
            + 8
            + 20
            + tripEndpointRowHeight(report, endpoint: report.endpoints.start)
            + 8
            + 24
        let pageBudgets: [CGFloat] = [max(0, 746 - firstRowsY), 590]
        var pages: [[FireVaultBreadcrumbReport.Visit]] = [[]]
        var pageIndex = 0
        var usedHeight: CGFloat = 0

        for visit in visits {
            let height = dailyStopPresentation(visit, detail: detail).height
            let budget = pageBudgets[min(pageIndex, pageBudgets.count - 1)]
            if usedHeight + height > budget,
               (!pages[pageIndex].isEmpty || pageIndex == 0) {
                pages.append([])
                pageIndex += 1
                usedHeight = 0
            }
            pages[pageIndex].append(visit)
            usedHeight += height
        }

        let finalBudget = pageBudgets[min(pageIndex, pageBudgets.count - 1)]
        let endHeight = tripEndpointRowHeight(report, endpoint: report.endpoints.end) + 8
        if usedHeight + endHeight > finalBudget {
            pages.append([])
        }
        return pages
    }

    private static func dailyStopPresentation(
        _ visit: FireVaultBreadcrumbReport.Visit,
        detail: FireVaultTripLogReportDetail
    ) -> (note: String, height: CGFloat) {
        let note = detail == .detailed
            ? visit.technicianNote.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return (note, stopRowHeight(visit: visit, note: note))
    }

    static func weekly(
        report: FireVaultTripLogWeeklyReport,
        detail: FireVaultTripLogReportDetail,
        mapImage: UIImage?
    ) -> Data {
        let summaryPages = makeWeeklySummaryPages(report.dailyReports)
        let detailSections = makeWeeklyDetailPages(report.dailyReports)
        let detailPages = packWeeklyDetailPages(detailSections, detail: detail)
        let totalPages = summaryPages.count + detailPages.count
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            var y: CGFloat = 0
            for (summaryIndex, trips) in summaryPages.enumerated() {
                let pageNumber = summaryIndex + 1
                context.beginPage()
                if summaryIndex == 0 {
                    y = drawHeader(
                        title: "TRIP LOG WEEKLY REPORT",
                        dateTitle: "WEEK OF",
                        dateMain: report.weekStart.formatted(.dateTime.month(.abbreviated).day()),
                        dateFooter: report.weekEnd.formatted(.dateTime.month(.abbreviated).day().year()),
                        technician: report.technicianName,
                        company: report.companyName,
                        page: pageNumber,
                        totalPages: totalPages,
                        generatedAt: report.generatedAt
                    )
                    y = drawMetrics(
                        [
                            ("DISTANCE", report.distanceText),
                            ("ON DUTY", report.elapsedText),
                            ("STOPS", "\(report.totalStopCount)")
                        ],
                        y: y
                    )
                    y += 8
                    y = drawMap(mapImage, y: y, size: .init(width: 528, height: 160))
                    y += 10
                } else {
                    y = drawContinuationHeader(
                        title: "WEEK AT A GLANCE",
                        date: report.dateRangeText,
                        page: pageNumber,
                        totalPages: totalPages,
                        generatedAt: report.generatedAt
                    )
                }
                y = drawSectionTitle(
                    summaryPages.count > 1
                        ? "WEEK AT A GLANCE • PAGE \(summaryIndex + 1) OF \(summaryPages.count)"
                        : "WEEK AT A GLANCE",
                    y: y
                )
                y = drawWeeklyHeader(y: y)
                for trip in trips {
                    y = drawWeeklyRow(trip, y: y)
                }
                if report.dailyReports.isEmpty {
                    y += drawText("No Trip Logs were recorded in this week.", font: .systemFont(ofSize: 10), color: .darkGray, x: 42, y: y + 12, width: 528)
                } else if summaryIndex == summaryPages.count - 1, y < 650 {
                    y += 12
                    y = drawWeeklyInsights(report, y: y)
                }
            }

            for (index, pageSections) in detailPages.enumerated() {
                let pageNumber = summaryPages.count + index + 1
                context.beginPage()
                y = drawContinuationHeader(
                    title: "WEEKLY TRIP BREAKDOWN",
                    date: report.dateRangeText,
                    page: pageNumber,
                    totalPages: totalPages,
                    generatedAt: report.generatedAt
                )
                for (sectionIndex, detailPage) in pageSections.enumerated() {
                    if sectionIndex > 0 { y += 16 }
                    y = drawWeeklyDaySpotlight(detailPage, y: y)
                    y += 10
                    if detailPage.part == 1 {
                        y = drawTripEndpointRow(
                            label: "START",
                            endpoint: detailPage.day.endpoints.start,
                            report: detailPage.day,
                            color: .systemGreen,
                            y: y
                        )
                        y += 8
                    }
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
                            let presentation = dailyStopPresentation(visit, detail: detail)
                            y = drawStopRow(
                                visit,
                                note: presentation.note,
                                y: y,
                                height: presentation.height
                            )
                        }
                    }
                    if detailPage.part == detailPage.partCount {
                        y += 8
                        y = drawTripEndpointRow(
                            label: "END",
                            endpoint: detailPage.day.endpoints.end,
                            report: detailPage.day,
                            color: red,
                            y: y
                        )
                    }
                }
            }
        }
    }

    private static func makeWeeklySummaryPages(
        _ reports: [FireVaultBreadcrumbReport]
    ) -> [[FireVaultBreadcrumbReport]] {
        guard !reports.isEmpty else { return [[]] }
        let budgets: [CGFloat] = [300, 590]
        var pages: [[FireVaultBreadcrumbReport]] = [[]]
        var pageIndex = 0
        var usedHeight: CGFloat = 0
        for report in reports {
            let height = weeklyRowHeight(report)
            let budget = budgets[min(pageIndex, budgets.count - 1)]
            if usedHeight + height > budget, !pages[pageIndex].isEmpty {
                pages.append([])
                pageIndex += 1
                usedHeight = 0
            }
            pages[pageIndex].append(report)
            usedHeight += height
        }
        return pages
    }

    private static func makeWeeklyDetailPages(
        _ reports: [FireVaultBreadcrumbReport]
    ) -> [WeeklyDetailPage] {
        let rowsPerPage = 10
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
        _ sections: [WeeklyDetailPage],
        detail: FireVaultTripLogReportDetail
    ) -> [[WeeklyDetailPage]] {
        let availableHeight: CGFloat = 742 - 97
        var pages: [[WeeklyDetailPage]] = []
        var current: [WeeklyDetailPage] = []
        var usedHeight: CGFloat = 0

        for section in sections {
            let rowsHeight = section.visits.isEmpty
                ? 48
                : section.visits.reduce(CGFloat.zero) { partial, visit in
                    partial + dailyStopPresentation(visit, detail: detail).height
                }
            let startHeight = section.part == 1
                ? tripEndpointRowHeight(section.day, endpoint: section.day.endpoints.start) + 8
                : 0
            let endHeight = section.part == section.partCount
                ? tripEndpointRowHeight(section.day, endpoint: section.day.endpoints.end) + 8
                : 0
            let sectionHeight: CGFloat = 86 + 10 + startHeight + 22 + 24 + rowsHeight + endHeight
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

    private static func tripEndpointRowHeight(
        _ report: FireVaultBreadcrumbReport,
        endpoint: FireVaultTripEndpoint
    ) -> CGFloat {
        let titleHeight = measuredTextHeight(
            endpoint.displayTitle,
            font: .systemFont(ofSize: 10, weight: .bold),
            width: 360
        )
        let addressHeight = measuredTextHeight(
            report.endpointAddress(endpoint),
            font: .systemFont(ofSize: 8, weight: .medium),
            width: 360
        )
        return max(38, titleHeight + addressHeight + 15)
    }

    private static func drawTripEndpointRow(
        label: String,
        endpoint: FireVaultTripEndpoint,
        report: FireVaultBreadcrumbReport,
        color: UIColor,
        y: CGFloat
    ) -> CGFloat {
        let height = tripEndpointRowHeight(report, endpoint: endpoint)
        let rect = CGRect(x: 42, y: y, width: 528, height: height)
        UIColor(white: 0.97, alpha: 1).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 9).fill()
        color.setFill()
        let badge = CGRect(x: 50, y: y + 9, width: 44, height: 18)
        UIBezierPath(roundedRect: badge, cornerRadius: 9).fill()
        drawCenteredText(label, font: .systemFont(ofSize: 7, weight: .black), color: .white, rect: badge)
        drawText(
            endpoint.timestamp.formatted(date: .omitted, time: .shortened),
            font: .monospacedSystemFont(ofSize: 8.2, weight: .semibold),
            color: .darkGray,
            x: 102,
            y: y + 9,
            width: 70
        )
        let titleHeight = drawText(
            endpoint.displayTitle,
            font: .systemFont(ofSize: 10, weight: .bold),
            color: navy,
            x: 178,
            y: y + 7,
            width: 382
        )
        drawText(
            report.endpointAddress(endpoint),
            font: .systemFont(ofSize: 8, weight: .medium),
            color: .darkGray,
            x: 178,
            y: y + 9 + titleHeight,
            width: 382
        )
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
        var locationHeight = measuredTextHeight(
            visit.title,
            font: .systemFont(ofSize: 10.5, weight: .semibold),
            width: 305
        )
        let detailText = stopDetailText(visit)
        if !detailText.isEmpty {
            locationHeight += 1 + measuredTextHeight(
                detailText,
                font: .systemFont(ofSize: 7.5),
                width: 305
            )
        }
        if !note.isEmpty {
            locationHeight += 1 + measuredTextHeight(
                "Note: \(note)",
                font: .italicSystemFont(ofSize: 7.2),
                width: 305
            )
        }
        let timeHeight = measuredTextHeight(
            visit.reportTimeText,
            font: .monospacedSystemFont(ofSize: 8.2, weight: .medium),
            width: 88
        )
        return ceil(max(22, max(locationHeight, timeHeight)) + 12)
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

        let contentTop = y + 6
        let badge = CGRect(x: 47, y: y + (height - 20) / 2, width: 20, height: 20)
        blue.setFill()
        UIBezierPath(ovalIn: badge).fill()
        drawCenteredText("\(visit.sequence)", font: .systemFont(ofSize: 8.5, weight: .bold), color: .white, rect: badge)

        drawText(visit.reportTimeText, font: .monospacedSystemFont(ofSize: 8.2, weight: .medium), color: .darkGray, x: 76, y: contentTop, width: 88)
        var locationY = contentTop
        locationY += drawText(visit.title, font: .systemFont(ofSize: 10.5, weight: .semibold), color: navy, x: 170, y: locationY, width: 305) + 1
        let detailText = stopDetailText(visit)
        if !detailText.isEmpty {
            locationY += drawText(detailText, font: .systemFont(ofSize: 7.5), color: .darkGray, x: 170, y: locationY, width: 305) + 1
        }
        if !note.isEmpty {
            locationY += drawText("Note: \(note)", font: .italicSystemFont(ofSize: 7.2), color: .darkGray, x: 170, y: locationY, width: 305) + 1
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

    private static func stopDetailText(_ visit: FireVaultBreadcrumbReport.Visit) -> String {
        [
            visit.addressText,
            visit.coordinateText.map { "GPS: \($0)" } ?? ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "  •  ")
    }

    private static func measuredTextHeight(
        _ text: String,
        font: UIFont,
        width: CGFloat
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5
        return ceil(
            NSString(string: text).boundingRect(
                with: CGSize(width: width, height: 1_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: font,
                    .paragraphStyle: paragraph
                ],
                context: nil
            ).height
        )
    }

    private static func drawWeeklyDaySpotlight(
        _ page: WeeklyDetailPage,
        y: CGFloat
    ) -> CGFloat {
        let rect = CGRect(x: 42, y: y, width: 528, height: 86)
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
        let savedName = day.tripName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        drawText(
            savedName.isEmpty ? day.startedAt.formatted(date: .long, time: .omitted) : savedName,
            font: .systemFont(ofSize: 9.5, weight: .semibold),
            color: blue,
            x: 58,
            y: y + 33,
            width: 222
        )
        drawText(
            day.cityRouteText,
            font: .systemFont(ofSize: 8.5, weight: .bold),
            color: navy,
            x: 58,
            y: y + 50,
            width: 222
        )
        drawText(
            "\(day.startTimeText) – \(day.endTimeText)",
            font: .monospacedSystemFont(ofSize: 8.5, weight: .medium),
            color: .darkGray,
            x: 58,
            y: y + 67,
            width: 222
        )
        if page.partCount > 1 {
            drawText(
                "PAGE SECTION \(page.part) OF \(page.partCount)",
                font: .systemFont(ofSize: 6.8, weight: .bold),
                color: red,
                x: 176,
                y: y + 69,
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
                rect: CGRect(x: x, y: y + 24, width: metricWidth, height: 20)
            )
            drawCenteredText(
                metric.0,
                font: .systemFont(ofSize: 6.8, weight: .bold),
                color: .darkGray,
                rect: CGRect(x: x, y: y + 47, width: metricWidth, height: 14)
            )
            if index > 0 {
                lightLine.setStroke()
                let line = UIBezierPath()
                line.move(to: .init(x: x, y: y + 21))
                line.addLine(to: .init(x: x, y: y + 65))
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
                "AVERAGE / TRIP",
                FireVaultBreadcrumbReport.distanceText(averageDistance),
                "Across \(report.dailyReports.count) recorded trip\(report.dailyReports.count == 1 ? "" : "s")"
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
        drawText("TRIP / ROUTE WINDOW", font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, x: 48, y: y + 8, width: 252)
        drawText("DISTANCE", font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, x: 315, y: y + 8, width: 70, alignment: .right)
        drawText("ON DUTY", font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, x: 405, y: y + 8, width: 75, alignment: .right)
        drawText("STOPS", font: .systemFont(ofSize: 7.5, weight: .bold), color: .white, x: 520, y: y + 8, width: 40, alignment: .right)
        return rect.maxY
    }

    private static func drawWeeklyRow(_ day: FireVaultBreadcrumbReport, y: CGFloat) -> CGFloat {
        let rowHeight = weeklyRowHeight(day)
        let savedName = day.tripName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let primaryTitle = savedName.isEmpty
            ? day.startedAt.formatted(.dateTime.weekday(.wide))
            : savedName
        drawText(primaryTitle, font: .systemFont(ofSize: 10, weight: .bold), color: navy, x: 48, y: y + 5, width: 252)
        drawText(
            "\(day.startedAt.formatted(.dateTime.month(.abbreviated).day())) • \(day.startTimeText)–\(day.endTimeText)",
            font: .monospacedSystemFont(ofSize: 7.2, weight: .medium),
            color: .darkGray,
            x: 48,
            y: y + 20,
            width: 252
        )
        drawText(day.cityRouteText, font: .systemFont(ofSize: 7.5, weight: .bold), color: blue, x: 48, y: y + 34, width: 252)
        drawText(day.distanceText, font: .monospacedSystemFont(ofSize: 8.5, weight: .semibold), color: navy, x: 315, y: y + 18, width: 70, alignment: .right)
        drawText(day.elapsedText, font: .monospacedSystemFont(ofSize: 8.5, weight: .semibold), color: navy, x: 405, y: y + 18, width: 75, alignment: .right)
        drawText("\(day.visits.count)", font: .monospacedSystemFont(ofSize: 8.5, weight: .semibold), color: navy, x: 520, y: y + 18, width: 40, alignment: .right)
        lightLine.setStroke()
        let line = UIBezierPath()
        line.move(to: .init(x: 42, y: y + rowHeight))
        line.addLine(to: .init(x: 570, y: y + rowHeight))
        line.lineWidth = 0.6
        line.stroke()
        return y + rowHeight
    }

    private static func weeklyRowHeight(_ day: FireVaultBreadcrumbReport) -> CGFloat {
        58
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
