//
//  FireVaultBreadcrumbs.swift
//  FireVault
//
//  Native daily travel and editable technician-stop history for Build 1.08.03.
//

import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct FireVaultBreadcrumbPoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        .init(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
    }
}

struct FireVaultBreadcrumbStop: Codable, Identifiable, Equatable {
    var id = UUID()
    var arrival: Date
    var departure: Date?
    var latitude: Double
    var longitude: Double
    var accountID: String?
    var accountName: String?
    var accountAddress: String?
    var technicianNote: String?
    var isPersonal: Bool?

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }

    var title: String {
        if isPersonalStop { return "Personal Stop" }
        return accountName ?? "Unrecognized Stop"
    }

    var subtitle: String {
        if isPersonalStop { return "Not associated with an account" }
        return accountAddress ?? "Tap to review and identify this location"
    }

    var duration: TimeInterval {
        max(0, (departure ?? Date()).timeIntervalSince(arrival))
    }

    var isPersonalStop: Bool {
        isPersonal ?? false
    }

    mutating func assign(to account: FireVaultWorkspaceAccount?) {
        isPersonal = false
        accountID = account?.id
        accountName = account?.name
        accountAddress = account?.address
    }

    mutating func markPersonal(_ personal: Bool) {
        isPersonal = personal
        guard personal else { return }
        accountID = nil
        accountName = nil
        accountAddress = nil
    }

    mutating func updateVisit(
        arrival: Date,
        departure: Date?,
        technicianNote: String
    ) {
        let interval = FireVaultBreadcrumbRules.normalizedVisit(
            arrival: arrival,
            departure: departure
        )
        self.arrival = interval.arrival
        self.departure = interval.departure
        let trimmedNote = technicianNote.trimmingCharacters(in: .whitespacesAndNewlines)
        self.technicianNote = trimmedNote.isEmpty ? nil : trimmedNote
    }
}

struct FireVaultBreadcrumbDay: Codable, Identifiable, Equatable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
    var isPaused = false
    var points: [FireVaultBreadcrumbPoint] = []
    var stops: [FireVaultBreadcrumbStop] = []

    var isActive: Bool { endedAt == nil }

    var totalDistanceMeters: Double {
        zip(points, points.dropFirst()).reduce(0) { result, pair in
            result + pair.0.location.distance(from: pair.1.location)
        }
    }

    var elapsedTime: TimeInterval {
        max(0, (endedAt ?? Date()).timeIntervalSince(startedAt))
    }
}

enum FireVaultBreadcrumbRules {
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 100
    static let minimumPointDistance: CLLocationDistance = 12
    static let maximumPointInterval: TimeInterval = 30
    static let stopRadius: CLLocationDistance = 85
    static let minimumStopDuration: TimeInterval = 180
    static let accountMatchRadius: CLLocationDistance = 175

    static func normalizedVisit(
        arrival: Date,
        departure: Date?
    ) -> (arrival: Date, departure: Date?) {
        guard let departure else { return (arrival, nil) }
        return (arrival, max(arrival, departure))
    }

    static func accepts(_ location: CLLocation, after previous: CLLocation?) -> Bool {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumHorizontalAccuracy,
              abs(location.timestamp.timeIntervalSinceNow) <= 60 else {
            return false
        }
        guard let previous else { return true }
        return location.distance(from: previous) >= minimumPointDistance
            || location.timestamp.timeIntervalSince(previous.timestamp) >= maximumPointInterval
    }

    static func closestAccount(
        to coordinate: CLLocationCoordinate2D,
        accounts: [FireVaultWorkspaceAccount],
        maximumDistance: CLLocationDistance = accountMatchRadius
    ) -> FireVaultWorkspaceAccount? {
        let stopLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return accounts
            .compactMap { account -> (FireVaultWorkspaceAccount, CLLocationDistance)? in
                guard let accountCoordinate = account.coordinate else { return nil }
                let distance = stopLocation.distance(
                    from: CLLocation(
                        latitude: accountCoordinate.latitude,
                        longitude: accountCoordinate.longitude
                    )
                )
                guard distance <= maximumDistance else { return nil }
                return (account, distance)
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}

@MainActor
final class FireVaultBreadcrumbStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var days: [FireVaultBreadcrumbDay]
    @Published private(set) var isRecording = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var statusText = "Ready to start today’s route"

    private let manager: CLLocationManager
    private let archiveURL: URL
    private var accounts: [FireVaultWorkspaceAccount] = []
    private var candidateLocations: [CLLocation] = []
    private var activeStopID: UUID?

    var activeDay: FireVaultBreadcrumbDay? {
        days.first(where: \.isActive)
    }

    var today: FireVaultBreadcrumbDay? {
        activeDay ?? days.first(where: { Calendar.current.isDateInToday($0.startedAt) })
    }

    init(archiveURL: URL? = nil) {
        let manager = CLLocationManager()
        self.manager = manager
        self.archiveURL = archiveURL ?? Self.defaultArchiveURL
        days = Self.load(from: archiveURL ?? Self.defaultArchiveURL)
        authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = FireVaultBreadcrumbRules.minimumPointDistance
        manager.pausesLocationUpdatesAutomatically = true

        if activeDay != nil {
            statusText = "Workday saved — tap Resume to continue"
        }
    }

    func startWorkday(accounts: [FireVaultWorkspaceAccount]) {
        self.accounts = accounts
        if activeDay == nil {
            days.insert(.init(startedAt: Date()), at: 0)
            persist()
        } else {
            updateActiveDay { $0.isPaused = false }
        }
        beginLocationUpdates()
    }

    func pauseWorkday() {
        guard activeDay != nil else { return }
        manager.stopUpdatingLocation()
        isRecording = false
        updateActiveDay { $0.isPaused = true }
        statusText = "Breadcrumbs paused"
    }

    func resumeWorkday(accounts: [FireVaultWorkspaceAccount]) {
        guard activeDay != nil else {
            startWorkday(accounts: accounts)
            return
        }
        self.accounts = accounts
        updateActiveDay { $0.isPaused = false }
        beginLocationUpdates()
    }

    func endWorkday() {
        guard let index = activeDayIndex else { return }
        let end = Date()
        finalizeStopIfNeeded(in: index, at: end)
        days[index].endedAt = end
        days[index].isPaused = false
        manager.stopUpdatingLocation()
        isRecording = false
        candidateLocations.removeAll()
        activeStopID = nil
        statusText = "Workday complete"
        persist()
    }

    func deleteDay(_ id: UUID) {
        guard days.first(where: { $0.id == id })?.isActive != true else { return }
        days.removeAll { $0.id == id }
        persist()
    }

    func stop(dayID: UUID, stopID: UUID) -> FireVaultBreadcrumbStop? {
        days.first(where: { $0.id == dayID })?
            .stops.first(where: { $0.id == stopID })
    }

    @discardableResult
    func updateStop(
        dayID: UUID,
        stopID: UUID,
        arrival: Date,
        departure: Date?,
        account: FireVaultWorkspaceAccount?,
        technicianNote: String,
        isPersonal: Bool
    ) -> Bool {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              let stopIndex = days[dayIndex].stops.firstIndex(where: { $0.id == stopID }) else {
            return false
        }

        var stop = days[dayIndex].stops[stopIndex]
        stop.updateVisit(
            arrival: arrival,
            departure: departure,
            technicianNote: technicianNote
        )
        if isPersonal {
            stop.markPersonal(true)
        } else {
            stop.assign(to: account)
        }
        days[dayIndex].stops[stopIndex] = stop
        days[dayIndex].stops.sort { $0.arrival < $1.arrival }
        persist()
        return true
    }

    @discardableResult
    func deleteStop(dayID: UUID, stopID: UUID) -> Bool {
        guard let dayIndex = days.firstIndex(where: { $0.id == dayID }),
              days[dayIndex].stops.contains(where: { $0.id == stopID }) else {
            return false
        }

        days[dayIndex].stops.removeAll { $0.id == stopID }
        if activeStopID == stopID {
            activeStopID = nil
            candidateLocations.removeAll()
        }
        persist()
        return true
    }

    func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        guard activeDay != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startAuthorizedUpdates()
        case .denied:
            isRecording = false
            statusText = "Location access is off for Breadcrumbs"
        case .restricted:
            isRecording = false
            statusText = "Location access is restricted"
        case .notDetermined:
            statusText = "Waiting for location permission…"
        @unknown default:
            isRecording = false
            statusText = "Location is unavailable"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            record(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .denied {
            isRecording = false
            statusText = "Location access is off for Breadcrumbs"
        } else {
            statusText = "Waiting for a reliable GPS position…"
        }
    }

    private var activeDayIndex: Int? {
        days.firstIndex(where: \.isActive)
    }

    private func beginLocationUpdates() {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .notDetermined:
            statusText = "Waiting for location permission…"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startAuthorizedUpdates()
        case .denied:
            isRecording = false
            statusText = "Location access is off for Breadcrumbs"
        case .restricted:
            isRecording = false
            statusText = "Location access is restricted"
        @unknown default:
            isRecording = false
            statusText = "Location is unavailable"
        }
    }

    private func startAuthorizedUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        isRecording = true
        statusText = "Recording today’s route"
    }

    private func record(_ location: CLLocation) {
        guard let index = activeDayIndex, !days[index].isPaused else { return }
        let previous = days[index].points.last?.location
        guard FireVaultBreadcrumbRules.accepts(location, after: previous) else { return }

        days[index].points.append(
            .init(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy
            )
        )
        updateStopDetection(with: location, dayIndex: index)
        statusText = "Recording • \(days[index].points.count) GPS points"
        persist()
    }

    private func updateStopDetection(with location: CLLocation, dayIndex: Int) {
        guard let anchor = candidateLocations.first else {
            candidateLocations = [location]
            return
        }

        if location.distance(from: anchor) <= FireVaultBreadcrumbRules.stopRadius {
            candidateLocations.append(location)
            let duration = location.timestamp.timeIntervalSince(anchor.timestamp)
            if duration >= FireVaultBreadcrumbRules.minimumStopDuration, activeStopID == nil {
                let coordinate = candidateCoordinate
                let account = FireVaultBreadcrumbRules.closestAccount(to: coordinate, accounts: accounts)
                let stop = FireVaultBreadcrumbStop(
                    arrival: anchor.timestamp,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    accountID: account?.id,
                    accountName: account?.name,
                    accountAddress: account?.address
                )
                activeStopID = stop.id
                days[dayIndex].stops.append(stop)
            }
            return
        }

        if let activeStopID,
           let stopIndex = days[dayIndex].stops.firstIndex(where: { $0.id == activeStopID }) {
            days[dayIndex].stops[stopIndex].departure = candidateLocations.last?.timestamp ?? location.timestamp
        } else if location.timestamp.timeIntervalSince(anchor.timestamp)
                    >= FireVaultBreadcrumbRules.minimumStopDuration {
            let coordinate = candidateCoordinate
            let account = FireVaultBreadcrumbRules.closestAccount(to: coordinate, accounts: accounts)
            days[dayIndex].stops.append(
                .init(
                    arrival: anchor.timestamp,
                    departure: location.timestamp,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    accountID: account?.id,
                    accountName: account?.name,
                    accountAddress: account?.address
                )
            )
        }
        candidateLocations = [location]
        activeStopID = nil
    }

    private var candidateCoordinate: CLLocationCoordinate2D {
        guard !candidateLocations.isEmpty else { return .init() }
        let latitude = candidateLocations.map(\.coordinate.latitude).reduce(0, +)
            / Double(candidateLocations.count)
        let longitude = candidateLocations.map(\.coordinate.longitude).reduce(0, +)
            / Double(candidateLocations.count)
        return .init(latitude: latitude, longitude: longitude)
    }

    private func finalizeStopIfNeeded(in dayIndex: Int, at end: Date) {
        if let activeStopID,
           let stopIndex = days[dayIndex].stops.firstIndex(where: { $0.id == activeStopID }) {
            days[dayIndex].stops[stopIndex].departure = end
            return
        }

        guard let first = candidateLocations.first,
              end.timeIntervalSince(first.timestamp) >= FireVaultBreadcrumbRules.minimumStopDuration else {
            return
        }
        let coordinate = candidateCoordinate
        let account = FireVaultBreadcrumbRules.closestAccount(to: coordinate, accounts: accounts)
        days[dayIndex].stops.append(
            .init(
                arrival: first.timestamp,
                departure: end,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                accountID: account?.id,
                accountName: account?.name,
                accountAddress: account?.address
            )
        )
    }

    private func updateActiveDay(_ change: (inout FireVaultBreadcrumbDay) -> Void) {
        guard let index = activeDayIndex else { return }
        change(&days[index])
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: archiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.fireVaultBreadcrumbs.encode(days)
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            statusText = "Route is active, but its history could not be saved"
        }
    }

    private static func load(from url: URL) -> [FireVaultBreadcrumbDay] {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder.fireVaultBreadcrumbs.decode(
                [FireVaultBreadcrumbDay].self,
                from: data
              ) else {
            return []
        }
        return saved.sorted { $0.startedAt > $1.startedAt }
    }

    private static var defaultArchiveURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("FireVault", isDirectory: true)
            .appendingPathComponent("breadcrumbs-v1.json")
    }
}

struct FireVaultBreadcrumbCompactBar: View {
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    let accounts: [FireVaultWorkspaceAccount]
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 9) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .foregroundStyle(
                            breadcrumbs.isRecording
                                ? NativeShellPalette.green
                                : NativeShellPalette.blue
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text("BREADCRUMBS")
                            .font(.caption2.bold())
                            .tracking(1)
                        Text(compactStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if breadcrumbs.activeDay == nil {
                Button("Start") {
                    breadcrumbs.startWorkday(accounts: accounts)
                    open()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if !breadcrumbs.isRecording {
                Button("Resume") {
                    breadcrumbs.resumeWorkday(accounts: accounts)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("breadcrumbs-compact-bar")
    }

    private var compactStatus: String {
        guard let day = breadcrumbs.today else { return "Start today’s travel log" }
        if breadcrumbs.isRecording { return "Recording • \(day.stops.count) stops" }
        if day.isActive { return "Paused • \(day.stops.count) stops" }
        return "\(day.stops.count) stops • \(day.totalDistanceMeters.fireVaultMiles)"
    }
}

struct FireVaultBreadcrumbsView: View {
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @ObservedObject var store: FireVaultStore
    let technicianName: String
    let companyName: String
    let includeCoordinatesInReports: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDayID: UUID?
    @State private var confirmsEnd = false
    @State private var editingStop: BreadcrumbStopSelection?
    @State private var showsReport = false

    private var selectedDay: FireVaultBreadcrumbDay? {
        if let selectedDayID {
            return breadcrumbs.days.first(where: { $0.id == selectedDayID })
        }
        return breadcrumbs.today ?? breadcrumbs.days.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    daySelector
                    trackingControls

                    if let day = selectedDay {
                        routeMap(day)
                        summary(day)
                        timeline(day)
                    } else {
                        ContentUnavailableView(
                            "No Breadcrumbs Yet",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text("Start your workday to record today’s route and account stops.")
                        )
                        .frame(minHeight: 300)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(NativeShellPalette.background)
            .navigationTitle("Breadcrumbs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if selectedDay != nil {
                        Button("Report", systemImage: "doc.text") {
                            showsReport = true
                        }
                        .accessibilityHint("Previews and exports this workday report")
                    }
                }
            }
            .confirmationDialog(
                "End Today’s Workday?",
                isPresented: $confirmsEnd,
                titleVisibility: .visible
            ) {
                Button("End Workday", role: .destructive) {
                    breadcrumbs.endWorkday()
                    selectedDayID = breadcrumbs.today?.id
                }
                Button("Keep Recording", role: .cancel) {}
            } message: {
                Text("The route and detected stops will remain in your local daily history.")
            }
        }
        .tint(NativeShellPalette.blue)
        .preferredColorScheme(.dark)
        .onAppear {
            selectedDayID = breadcrumbs.today?.id ?? breadcrumbs.days.first?.id
        }
        .sheet(item: $editingStop) { selection in
            FireVaultBreadcrumbStopEditor(
                breadcrumbs: breadcrumbs,
                store: store,
                dayID: selection.dayID,
                stopID: selection.stopID
            ) { accountID in
                store.openAccount(accountID)
                editingStop = nil
                dismiss()
            }
        }
        .sheet(isPresented: $showsReport) {
            if let selectedDay {
                FireVaultBreadcrumbReportView(
                    report: .init(
                        day: selectedDay,
                        technicianName: technicianName,
                        companyName: companyName,
                        includeCoordinates: includeCoordinatesInReports
                    )
                )
            }
        }
    }

    private var daySelector: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDay?.startedAt.formatted(.dateTime.weekday(.wide)) ?? "TODAY")
                    .font(.caption.bold())
                    .tracking(1.1)
                    .foregroundStyle(NativeShellPalette.red)
                Text(selectedDay?.startedAt.formatted(date: .long, time: .omitted) ?? Date().formatted(date: .long, time: .omitted))
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            Spacer()
            if !breadcrumbs.days.isEmpty {
                Menu {
                    ForEach(breadcrumbs.days) { day in
                        Button {
                            selectedDayID = day.id
                        } label: {
                            Label(
                                day.startedAt.formatted(date: .abbreviated, time: .omitted),
                                systemImage: day.isActive ? "record.circle" : "calendar"
                            )
                        }
                    }
                } label: {
                    Label("History", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.top, 8)
    }

    private var trackingControls: some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            breadcrumbs.isRecording ? "Workday Recording" : "Workday Tracking",
                            systemImage: breadcrumbs.isRecording ? "location.fill" : "location"
                        )
                        .font(.headline)
                        .foregroundStyle(breadcrumbs.isRecording ? NativeShellPalette.green : .white)
                        Text(breadcrumbs.statusText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if breadcrumbs.isRecording {
                        Circle()
                            .fill(NativeShellPalette.green)
                            .frame(width: 10, height: 10)
                            .shadow(color: NativeShellPalette.green.opacity(0.7), radius: 5)
                            .accessibilityLabel("Recording")
                    }
                }

                if breadcrumbs.authorizationStatus == .denied {
                    Button("Open Location Settings", systemImage: "gearshape") {
                        breadcrumbs.openLocationSettings()
                    }
                    .buttonStyle(.borderedProminent)
                } else if breadcrumbs.activeDay == nil {
                    Button("Start Workday", systemImage: "play.fill") {
                        breadcrumbs.startWorkday(accounts: store.accounts)
                        selectedDayID = breadcrumbs.activeDay?.id
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack {
                        if breadcrumbs.isRecording {
                            Button("Pause", systemImage: "pause.fill") {
                                breadcrumbs.pauseWorkday()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Resume", systemImage: "play.fill") {
                                breadcrumbs.resumeWorkday(accounts: store.accounts)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                        Button("End Day", systemImage: "stop.fill", role: .destructive) {
                            confirmsEnd = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func routeMap(_ day: FireVaultBreadcrumbDay) -> some View {
        if day.points.isEmpty {
            NativeShellCard {
                ContentUnavailableView(
                    "Waiting for Route",
                    systemImage: "map",
                    description: Text(
                        day.isActive
                            ? "Keep FireVault running while the first reliable GPS positions are collected."
                            : "No reliable GPS points were recorded for this workday."
                    )
                )
                .frame(height: 210)
            }
        } else {
            Map(initialPosition: .automatic, interactionModes: [.pan, .zoom, .rotate]) {
                MapPolyline(coordinates: day.points.map(\.coordinate))
                    .stroke(NativeShellPalette.red, style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))

                if let first = day.points.first {
                    Marker("Workday Start", systemImage: "play.fill", coordinate: first.coordinate)
                        .tint(NativeShellPalette.green)
                }

                ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                    Annotation(stop.title, coordinate: stop.coordinate) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(stopTint(stop), in: Circle())
                            .overlay { Circle().stroke(.white.opacity(0.85), lineWidth: 2) }
                    }
                }

                if let last = day.points.last, !day.isActive {
                    Marker("Workday End", systemImage: "stop.fill", coordinate: last.coordinate)
                        .tint(NativeShellPalette.red)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .accessibilityIdentifier("breadcrumbs-route-map")
        }
    }

    private func summary(_ day: FireVaultBreadcrumbDay) -> some View {
        HStack(spacing: 1) {
            BreadcrumbMetric(
                title: "MILES",
                value: day.totalDistanceMeters.fireVaultMiles,
                symbol: "road.lanes"
            )
            Divider().frame(height: 45)
            BreadcrumbMetric(
                title: "STOPS",
                value: "\(day.stops.count)",
                symbol: "mappin.and.ellipse"
            )
            Divider().frame(height: 45)
            BreadcrumbMetric(
                title: "ELAPSED",
                value: day.elapsedTime.fireVaultDuration,
                symbol: "clock"
            )
        }
        .padding(.vertical, 13)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottom) {
            if day.stops.contains(where: { $0.accountID == nil && !$0.isPersonalStop }) {
                Text("\(day.stops.filter { $0.accountID == nil && !$0.isPersonalStop }.count) need review")
                    .font(.caption2.bold())
                    .foregroundStyle(NativeShellPalette.amber)
                    .offset(y: 20)
            }
        }
        .padding(.bottom, day.stops.contains(where: { $0.accountID == nil && !$0.isPersonalStop }) ? 16 : 0)
    }

    private func timeline(_ day: FireVaultBreadcrumbDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAILY LOG")
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.secondary)

            NativeShellCard {
                VStack(spacing: 0) {
                    BreadcrumbTimelineRow(
                        time: day.startedAt,
                        title: "Workday Started",
                        subtitle: day.points.first.map { "Route began near \($0.coordinate.fireVaultCoordinateLabel)" },
                        symbol: "play.fill",
                        tint: NativeShellPalette.green
                    )

                    ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                        Divider().padding(.leading, 52)
                        Button {
                            editingStop = .init(dayID: day.id, stopID: stop.id)
                        } label: {
                            BreadcrumbTimelineRow(
                                time: stop.arrival,
                                title: stop.title,
                                subtitle: stopTimelineSubtitle(stop),
                                symbol: "\(index + 1).circle.fill",
                                tint: stopTint(stop),
                                showsDisclosure: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this stop for review and editing")
                    }

                    if let endedAt = day.endedAt {
                        Divider().padding(.leading, 52)
                        BreadcrumbTimelineRow(
                            time: endedAt,
                            title: "Workday Ended",
                            subtitle: day.totalDistanceMeters.fireVaultMiles,
                            symbol: "stop.fill",
                            tint: NativeShellPalette.red
                        )
                    } else {
                        Divider().padding(.leading, 52)
                        BreadcrumbTimelineRow(
                            time: Date(),
                            title: day.isPaused ? "Tracking Paused" : "Workday in Progress",
                            subtitle: breadcrumbs.statusText,
                            symbol: day.isPaused ? "pause.fill" : "location.fill",
                            tint: day.isPaused ? NativeShellPalette.amber : NativeShellPalette.green
                        )
                    }
                }
            }
        }
    }

    private func stopTint(_ stop: FireVaultBreadcrumbStop) -> Color {
        if stop.isPersonalStop { return .secondary }
        return stop.accountID == nil ? NativeShellPalette.amber : NativeShellPalette.blue
    }

    private func stopTimelineSubtitle(_ stop: FireVaultBreadcrumbStop) -> String {
        var parts = [stop.subtitle, stop.duration.fireVaultDuration]
        if stop.technicianNote?.isEmpty == false {
            parts.append("Note added")
        }
        return parts.joined(separator: " • ")
    }
}

private struct BreadcrumbStopSelection: Identifiable {
    let dayID: UUID
    let stopID: UUID
    var id: UUID { stopID }
}

private struct FireVaultBreadcrumbStopEditor: View {
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @ObservedObject var store: FireVaultStore
    @Environment(\.dismiss) private var dismiss

    let dayID: UUID
    let stopID: UUID
    let openAccount: (String) -> Void

    @State private var arrival: Date
    @State private var departure: Date
    @State private var hasDeparture: Bool
    @State private var selectedAccountID: String?
    @State private var technicianNote: String
    @State private var isPersonal: Bool
    @State private var showsAccountPicker = false
    @State private var confirmsDelete = false

    init(
        breadcrumbs: FireVaultBreadcrumbStore,
        store: FireVaultStore,
        dayID: UUID,
        stopID: UUID,
        openAccount: @escaping (String) -> Void
    ) {
        self.breadcrumbs = breadcrumbs
        self.store = store
        self.dayID = dayID
        self.stopID = stopID
        self.openAccount = openAccount

        let stop = breadcrumbs.stop(dayID: dayID, stopID: stopID)
        let arrival = stop?.arrival ?? Date()
        _arrival = State(initialValue: arrival)
        _departure = State(initialValue: stop?.departure ?? arrival.addingTimeInterval(15 * 60))
        _hasDeparture = State(initialValue: stop?.departure != nil)
        _selectedAccountID = State(initialValue: stop?.accountID)
        _technicianNote = State(initialValue: stop?.technicianNote ?? "")
        _isPersonal = State(initialValue: stop?.isPersonalStop ?? false)
    }

    private var selectedAccount: FireVaultWorkspaceAccount? {
        guard let selectedAccountID else { return nil }
        return store.accounts.first(where: { $0.id == selectedAccountID })
    }

    var body: some View {
        NavigationStack {
            Form {
                visitSection
                classificationSection
                if let account = selectedAccount, !isPersonal {
                    activitySection(account)
                }
                noteSection
                locationSection
                deleteSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showsAccountPicker) {
                FireVaultBreadcrumbAccountPicker(
                    accounts: store.accounts,
                    selectedAccountID: selectedAccountID
                ) { accountID in
                    selectedAccountID = accountID
                    isPersonal = false
                    showsAccountPicker = false
                }
            }
            .confirmationDialog(
                "Delete This Stop?",
                isPresented: $confirmsDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Stop", role: .destructive) {
                    breadcrumbs.deleteStop(dayID: dayID, stopID: stopID)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The route remains intact, but this stop will be removed from the daily log.")
            }
        }
        .tint(NativeShellPalette.blue)
        .preferredColorScheme(.dark)
    }

    private var visitSection: some View {
        Section {
            DatePicker(
                "Arrived",
                selection: $arrival,
                displayedComponents: [.date, .hourAndMinute]
            )
            Toggle("Departure recorded", isOn: $hasDeparture)
            if hasDeparture {
                DatePicker(
                    "Departed",
                    selection: $departure,
                    displayedComponents: [.date, .hourAndMinute]
                )
            } else {
                LabeledContent("Status", value: "Still at this stop")
            }
            LabeledContent(
                "Duration",
                value: previewDuration.fireVaultDuration
            )
        } header: {
            Text("Visit Time")
        } footer: {
            Text("Correct the arrival or departure time when GPS stop detection was early or late.")
        }
    }

    private var classificationSection: some View {
        Section {
            Toggle(isOn: $isPersonal) {
                Label("Personal Stop", systemImage: "person.crop.circle")
            }
            .onChange(of: isPersonal) { _, personal in
                if personal {
                    selectedAccountID = nil
                }
            }

            if isPersonal {
                LabeledContent("Account", value: "Not associated")
            } else {
                Button {
                    showsAccountPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Label("Account", systemImage: "building.2")
                            .foregroundStyle(.primary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(selectedAccount?.name ?? "Choose Account")
                                .foregroundStyle(
                                    selectedAccount == nil
                                        ? NativeShellPalette.amber
                                        : .secondary
                                )
                                .lineLimit(1)
                            if let accountID = selectedAccount?.accountId, !accountID.isEmpty {
                                Text(accountID)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Account, \(selectedAccount?.name ?? "not assigned")"
                )
                .accessibilityHint("Opens the searchable account directory")
            }
        } header: {
            Text("Stop Classification")
        } footer: {
            Text(
                isPersonal
                    ? "Personal stops remain in the route but are not associated with customer activity."
                    : "Assigning an account turns this detected location into a technician visit."
            )
        }
    }

    private func activitySection(_ account: FireVaultWorkspaceAccount) -> some View {
        Section {
            HStack {
                BreadcrumbActivityCount(
                    title: "NOTES",
                    value: account.notes.count,
                    symbol: "note.text"
                )
                BreadcrumbActivityCount(
                    title: "FILES",
                    value: account.documents.count,
                    symbol: "doc"
                )
                BreadcrumbActivityCount(
                    title: "EQUIPMENT",
                    value: account.equipment.count,
                    symbol: "wrench.and.screwdriver"
                )
            }
            .listRowInsets(.init(top: 12, leading: 8, bottom: 12, trailing: 8))

            Button("Open Account Workspace", systemImage: "arrow.up.right.square") {
                save(openingAccount: account.id)
            }
        } header: {
            Text("Technician Activity")
        } footer: {
            Text("Current native records for \(account.name).")
        }
    }

    private var noteSection: some View {
        Section {
            TextField(
                "Reason for visit, work performed, or follow-up needed",
                text: $technicianNote,
                axis: .vertical
            )
            .lineLimit(3...7)
            .textInputAutocapitalization(.sentences)
            .accessibilityLabel("Technician visit note")
        } header: {
            Text("Visit Note")
        } footer: {
            Text("This note belongs to the Breadcrumbs visit and does not create a separate account note.")
        }
    }

    private var locationSection: some View {
        Section("Detected Location") {
            if let stop = breadcrumbs.stop(dayID: dayID, stopID: stopID) {
                LabeledContent("Latitude", value: stop.latitude.formatted(.number.precision(.fractionLength(5))))
                LabeledContent("Longitude", value: stop.longitude.formatted(.number.precision(.fractionLength(5))))
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Incorrect Stop", systemImage: "trash", role: .destructive) {
                confirmsDelete = true
            }
        }
    }

    private var previewDuration: TimeInterval {
        guard hasDeparture else {
            return max(0, Date().timeIntervalSince(arrival))
        }
        return max(0, departure.timeIntervalSince(arrival))
    }

    private func save(openingAccount accountID: String? = nil) {
        breadcrumbs.updateStop(
            dayID: dayID,
            stopID: stopID,
            arrival: arrival,
            departure: hasDeparture ? departure : nil,
            account: isPersonal ? nil : selectedAccount,
            technicianNote: technicianNote,
            isPersonal: isPersonal
        )

        if let accountID {
            openAccount(accountID)
        } else {
            dismiss()
        }
    }
}

private struct FireVaultBreadcrumbAccountPicker: View {
    let accounts: [FireVaultWorkspaceAccount]
    let selectedAccountID: String?
    let select: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredAccounts: [FireVaultWorkspaceAccount] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return accounts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return accounts
            .filter { account in
                [
                    account.name,
                    account.address,
                    account.accountId,
                    account.category
                ]
                .contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    select(nil)
                } label: {
                    accountRow(
                        title: "Leave Unassigned",
                        subtitle: "Review this stop later",
                        symbol: "questionmark.circle",
                        isSelected: selectedAccountID == nil
                    )
                }
                .buttonStyle(.plain)

                ForEach(filteredAccounts) { account in
                    Button {
                        select(account.id)
                    } label: {
                        accountRow(
                            title: account.name,
                            subtitle: accountPickerSubtitle(account),
                            symbol: "building.2",
                            isSelected: selectedAccountID == account.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Name, address, ID, or category")
            .navigationTitle("Choose Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if !searchText.isEmpty && filteredAccounts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(NativeShellPalette.blue)
    }

    private func accountRow(
        title: String,
        subtitle: String,
        symbol: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(isSelected ? NativeShellPalette.blue : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NativeShellPalette.blue)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accountPickerSubtitle(_ account: FireVaultWorkspaceAccount) -> String {
        [account.address, account.accountId, account.category]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}

private struct BreadcrumbActivityCount: View {
    let title: String
    let value: Int
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .foregroundStyle(NativeShellPalette.blue)
            Text(value, format: .number)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct BreadcrumbMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BreadcrumbTimelineRow: View {
    let time: Date
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    var showsDisclosure = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 24)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private extension JSONEncoder {
    static var fireVaultBreadcrumbs: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var fireVaultBreadcrumbs: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Double {
    var fireVaultMiles: String {
        let miles = self / 1_609.344
        return "\(miles.formatted(.number.precision(.fractionLength(miles < 10 ? 1 : 0)))) mi"
    }
}

private extension TimeInterval {
    var fireVaultDuration: String {
        let totalMinutes = max(0, Int(self / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

private extension CLLocationCoordinate2D {
    var fireVaultCoordinateLabel: String {
        "\(latitude.formatted(.number.precision(.fractionLength(3)))), \(longitude.formatted(.number.precision(.fractionLength(3))))"
    }
}
