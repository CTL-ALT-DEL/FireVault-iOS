//
//  FireVaultTripLogPortraitView.swift
//  FireVault
//
//  Clean portrait Trip Log workspace with a fixed map and scrollable stop history.
//

import MapKit
import SwiftUI

struct FireVaultTripLogPortraitView: View {
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @ObservedObject var store: FireVaultStore
    let technicianName: String
    let companyName: String
    let includeCoordinatesInReports: Bool
    var showsCloseButton = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDayID: UUID?
    @State private var editingStop: FireVaultTripLogPortraitStopSelection?
    @State private var confirmsEnd = false
    @State private var showsReport = false
    @State private var waypointPulse = false
    @State private var waypointPulseTask: Task<Void, Never>?

    private var selectedDay: FireVaultBreadcrumbDay? {
        if let selectedDayID {
            return breadcrumbs.days.first { $0.id == selectedDayID }
        }
        return breadcrumbs.today ?? breadcrumbs.days.first
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 8) {
                    if let day = selectedDay {
                        let availableWidth = max(0, geometry.size.width - 28)
                        let mapHeight = min(availableWidth, max(190, geometry.size.height * 0.34))

                        squareMap(day)
                            .frame(height: mapHeight)

                        controlDock(day)
                        summary(day)

                        ScrollView {
                            timeline(day)
                                .padding(.bottom, 24)
                        }
                        .scrollIndicators(.visible)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, showsCloseButton ? 8 : 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(NativeShellPalette.background)
            .navigationTitle(showsCloseButton ? "Trip Log" : "")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(!showsCloseButton)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
            }
            .confirmationDialog(
                "End Today’s Trip Log?",
                isPresented: $confirmsEnd,
                titleVisibility: .visible
            ) {
                Button("End Trip Log", role: .destructive) {
                    breadcrumbs.endWorkday()
                    selectedDayID = breadcrumbs.today?.id
                }
                Button("Keep Recording", role: .cancel) {}
            } message: {
                Text("The route and detected stops will remain in your saved Trip Log history.")
            }
        }
        .tint(NativeShellPalette.blue)
        .onAppear {
            selectedDayID = breadcrumbs.today?.id ?? breadcrumbs.days.first?.id
        }
        .onChange(of: selectedDay?.points.count ?? 0) { previousCount, newCount in
            guard newCount > previousCount, breadcrumbs.isRecording else { return }
            flashWaypointLED()
        }
        .onDisappear {
            waypointPulseTask?.cancel()
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
                    ),
                    availableDays: breadcrumbs.days
                )
            }
        }
    }

    private func flashWaypointLED() {
        waypointPulseTask?.cancel()
        waypointPulse = true
        waypointPulseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            waypointPulse = false
        }
    }

    @ViewBuilder
    private func squareMap(_ day: FireVaultBreadcrumbDay) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Group {
                if day.points.isEmpty {
                    ZStack {
                        NativeShellPalette.surface
                        ContentUnavailableView(
                            "Waiting for Route",
                            systemImage: "map",
                            description: Text(
                                day.isActive
                                    ? "Trip Log is ready and will draw the route after reliable GPS points arrive."
                                    : "No reliable GPS route was recorded for this day."
                            )
                        )
                        .padding(24)
                    }
                } else {
                    Map(initialPosition: .automatic, interactionModes: []) {
                        MapPolyline(coordinates: day.points.map(\.coordinate))
                            .stroke(
                                NativeShellPalette.red,
                                style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round)
                            )

                        if let first = day.points.first {
                            Marker("Start", systemImage: "play.fill", coordinate: first.coordinate)
                                .tint(NativeShellPalette.green)
                        }

                        ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                            Annotation(stop.title, coordinate: stop.coordinate) {
                                Button {
                                    editingStop = .init(dayID: day.id, stopID: stop.id)
                                } label: {
                                    Text("\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(stopTint(stop), in: Circle())
                                        .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: 2) }
                                        .shadow(radius: 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let last = day.points.last, !day.isActive {
                            Marker("Stop", systemImage: "stop.fill", coordinate: last.coordinate)
                                .tint(NativeShellPalette.red)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(
                color: colorScheme == .light ? .black.opacity(0.22) : .clear,
                radius: 12,
                y: 6
            )
            .overlay(alignment: .topLeading) {
                compactMapDate(day)
                    .padding(12)
            }
        }
        .accessibilityIdentifier("trip-log-portrait-static-map")
    }

    private func compactMapDate(_ day: FireVaultBreadcrumbDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.startedAt.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.caption2.bold())
                .tracking(1)
                .foregroundStyle(NativeShellPalette.red)
            Text(day.startedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }

    private func controlDock(_ day: FireVaultBreadcrumbDay) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                recordingIndicator(day)
                Spacer(minLength: 2)

                if breadcrumbs.activeDay == nil {
                    compactTripAction(
                        title: "START",
                        symbol: "play.fill",
                        tint: NativeShellPalette.green
                    ) {
                        breadcrumbs.startWorkday(accounts: store.accounts)
                        selectedDayID = breadcrumbs.activeDay?.id
                    }
                } else if breadcrumbs.isRecording {
                    compactTripAction(
                        title: "PAUSE",
                        symbol: "pause.fill",
                        tint: NativeShellPalette.amber
                    ) {
                        breadcrumbs.pauseWorkday()
                    }
                } else {
                    compactTripAction(
                        title: "RESUME",
                        symbol: "play.fill",
                        tint: NativeShellPalette.green
                    ) {
                        breadcrumbs.resumeWorkday(accounts: store.accounts)
                    }
                }

                compactTripAction(
                    title: "STOP",
                    symbol: "stop.fill",
                    tint: NativeShellPalette.red
                ) {
                    confirmsEnd = true
                }
                .disabled(breadcrumbs.activeDay == nil)
                .opacity(breadcrumbs.activeDay == nil ? 0.38 : 1)

                historyMenu
                reportButton
            }

            if breadcrumbs.permissionState.requiresSettings {
                Button("Open Location Settings", systemImage: "gearshape") {
                    breadcrumbs.openLocationSettings()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .background {
            LinearGradient(
                colors: [
                    indicatorTint.opacity(0.16),
                    NativeShellPalette.surface,
                    NativeShellPalette.blue.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(indicatorTint.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: indicatorTint.opacity(0.10), radius: 9, y: 4)
        .accessibilityIdentifier("trip-log-portrait-controls")
    }

    private func recordingIndicator(_ day: FireVaultBreadcrumbDay) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(indicatorTitle)
                .font(.caption.bold())
                .tracking(0.8)
                .foregroundStyle(indicatorTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(indicatorDetail(day))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: 145, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var indicatorTitle: String {
        if breadcrumbs.isRecording { return "RECORDING" }
        if breadcrumbs.activeDay?.isPaused == true { return "PAUSED" }
        if breadcrumbs.activeDay == nil { return "READY" }
        return "COMPLETE"
    }

    private var indicatorTint: Color {
        if breadcrumbs.isRecording { return NativeShellPalette.green }
        if breadcrumbs.activeDay?.isPaused == true { return NativeShellPalette.amber }
        return NativeShellPalette.blue
    }

    private func indicatorDetail(_ day: FireVaultBreadcrumbDay) -> String {
        if breadcrumbs.isRecording { return "\(day.stops.count) stops • route active" }
        if day.isActive { return "\(day.stops.count) stops • tap Resume" }
        return "\(day.stops.count) stops • \(day.totalDistanceMeters.tripLogMiles)"
    }

    private var historyMenu: some View {
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
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(breadcrumbs.days.isEmpty)
        .accessibilityLabel("Trip Log history")
    }

    private var reportButton: some View {
        Button {
            showsReport = true
        } label: {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(selectedDay == nil)
        .accessibilityHint("Previews and exports the selected Trip Log report")
    }

    private func compactTripAction(
        title: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.caption.bold())
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.25)
            }
            .foregroundStyle(.white)
            .frame(width: 42, height: 38)
            .background(tint.opacity(0.86), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) Trip Log")
    }

    @ViewBuilder
    private func tripActionButton(
        title: String,
        symbol: String,
        tint: Color,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        } else {
            Button(action: action) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.bordered)
            .tint(tint)
        }
    }

    private func summary(_ day: FireVaultBreadcrumbDay) -> some View {
        HStack(spacing: 1) {
            portraitMetric(title: "MILES", value: day.totalDistanceMeters.tripLogMiles, symbol: "road.lanes")
            Divider().frame(height: 36)
            portraitMetric(title: "STOPS", value: "\(day.stops.count)", symbol: "mappin.and.ellipse")
            Divider().frame(height: 36)
            portraitMetric(title: "TIME", value: day.elapsedTime.tripLogDuration, symbol: "clock")
        }
        .padding(.vertical, 8)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func portraitMetric(title: String, value: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(NativeShellPalette.blue)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeline(_ day: FireVaultBreadcrumbDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOGGED STOPS")
                .font(.caption.bold())
                .tracking(1.1)
                .foregroundStyle(.secondary)

            NativeShellCard {
                VStack(spacing: 0) {
                    portraitTimelineRow(
                        time: day.startedAt,
                        title: "Trip Started",
                        subtitle: "Route recording began",
                        symbol: "play.fill",
                        tint: NativeShellPalette.green
                    )

                    ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                        Divider().padding(.leading, 48)
                        Button {
                            editingStop = .init(dayID: day.id, stopID: stop.id)
                        } label: {
                            portraitTimelineRow(
                                time: stop.arrival,
                                title: stop.title,
                                subtitle: "\(stop.subtitle) • \(day.stopDuration(for: stop).tripLogDuration)",
                                symbol: "\(index + 1).circle.fill",
                                tint: stopTint(stop),
                                showsDisclosure: true
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let endedAt = day.endedAt {
                        Divider().padding(.leading, 48)
                        portraitTimelineRow(
                            time: endedAt,
                            title: "Trip Ended",
                            subtitle: day.totalDistanceMeters.tripLogMiles,
                            symbol: "stop.fill",
                            tint: NativeShellPalette.red
                        )
                    }
                }
            }
        }
    }

    private func portraitTimelineRow(
        time: Date,
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.subheadline.bold())
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 20)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                NativeShellPalette.surface
                ContentUnavailableView(
                    "Ready to Start",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Start Trip Log to record today’s route and account stops.")
                )
                .padding(24)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(
                color: colorScheme == .light ? .black.opacity(0.22) : .clear,
                radius: 12,
                y: 6
            )

            emptyControlDock

            NativeShellCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Trip Log Features", systemImage: "truck.box.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Label("Pause and resume route recording during the workday.", systemImage: "pause.circle")
                    Label("Review detected account stops and daily history.", systemImage: "calendar.badge.clock")
                    Label("Preview and export completed Trip Log reports.", systemImage: "doc.text")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("trip-log-empty-workspace")
    }

    private var emptyControlDock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("READY")
                        .font(.caption.bold())
                        .tracking(0.8)
                        .foregroundStyle(NativeShellPalette.blue)
                    Text("Tap Start to begin today’s route")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 145, alignment: .leading)

                Spacer(minLength: 2)

                compactTripAction(
                    title: "START",
                    symbol: "play.fill",
                    tint: NativeShellPalette.green
                ) {
                    breadcrumbs.startWorkday(accounts: store.accounts)
                    selectedDayID = breadcrumbs.activeDay?.id
                }

                compactTripAction(
                    title: "STOP",
                    symbol: "stop.fill",
                    tint: NativeShellPalette.red
                ) {}
                .disabled(true)
                .opacity(0.38)

                historyMenu
                reportButton
            }

            if breadcrumbs.permissionState.requiresSettings {
                Button("Open Location Settings", systemImage: "gearshape") {
                    breadcrumbs.openLocationSettings()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("History and report controls become available after a Trip Log has been created.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(9)
        .background {
            LinearGradient(
                colors: [
                    NativeShellPalette.blue.opacity(0.16),
                    NativeShellPalette.surface,
                    NativeShellPalette.green.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(NativeShellPalette.blue.opacity(0.34), lineWidth: 1)
        }
        .accessibilityIdentifier("trip-log-empty-controls")
    }

    private func stopTint(_ stop: FireVaultBreadcrumbStop) -> Color {
        if stop.isPersonalStop { return .secondary }
        return stop.accountID == nil ? NativeShellPalette.amber : NativeShellPalette.blue
    }
}

private struct FireVaultTripLogPortraitStopSelection: Identifiable {
    let dayID: UUID
    let stopID: UUID
    var id: UUID { stopID }
}

private extension Double {
    var tripLogMiles: String {
        let miles = self / 1_609.344
        return "\(miles.formatted(.number.precision(.fractionLength(miles < 10 ? 1 : 0)))) mi"
    }
}

private extension TimeInterval {
    var tripLogDuration: String {
        let totalMinutes = max(0, Int(self / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
