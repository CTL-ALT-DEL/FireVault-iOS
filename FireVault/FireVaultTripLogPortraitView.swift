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
        .task(id: selectedDay?.id) {
            guard let dayID = selectedDay?.id else { return }
            breadcrumbs.resolveMissingBoundaryAddresses(for: dayID)
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
            .nativeMapFrame()
            .overlay(alignment: .topLeading) {
                compactMapDate(day)
                    .padding(12)
            }
        }
        .accessibilityIdentifier("trip-log-portrait-static-map")
    }

    private func compactMapDate(_ day: FireVaultBreadcrumbDay) -> some View {
        VStack(alignment: .center, spacing: 3) {
            Text(day.startedAt.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.caption2.bold())
                .tracking(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(NativeShellPalette.red, in: Capsule())
            Text(day.startedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }

    private func controlDock(_ day: FireVaultBreadcrumbDay) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                recordingIndicator(day)
                Spacer(minLength: 8)
                recordingMenu
            }

            HStack(spacing: 10) {
                historyMenu
                reportButton
            }
            .padding(9)
            .background {
                LinearGradient(
                    colors: [NativeShellPalette.blue.opacity(0.17), NativeShellPalette.blue.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(NativeShellPalette.blue.opacity(0.32), lineWidth: 1)
            }

            if breadcrumbs.permissionState.requiresSettings {
                Button("Open Location Settings", systemImage: "gearshape") {
                    breadcrumbs.openLocationSettings()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
            VStack(spacing: 3) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 25, weight: .bold))
                Text("HISTORY").font(.caption.bold())
            }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.bordered)
        .disabled(breadcrumbs.days.isEmpty)
        .accessibilityLabel("Trip Log history")
    }

    private var reportButton: some View {
        Button {
            showsReport = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 25, weight: .bold))
                Text("REPORT").font(.caption.bold())
            }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedDay == nil)
        .accessibilityHint("Previews and exports the selected Trip Log report")
    }

    private var recordingMenu: some View {
        Menu {
            if breadcrumbs.activeDay == nil {
                Button("Start Trip Log", systemImage: "play.fill") {
                    breadcrumbs.startWorkday(accounts: store.accounts)
                    selectedDayID = breadcrumbs.activeDay?.id
                }
            } else if breadcrumbs.isRecording {
                Button("Pause Recording", systemImage: "pause.fill") {
                    breadcrumbs.pauseWorkday()
                }
                Button("Stop Trip Log", systemImage: "stop.fill", role: .destructive) {
                    confirmsEnd = true
                }
            } else {
                Button("Resume Recording", systemImage: "play.fill") {
                    breadcrumbs.resumeWorkday(accounts: store.accounts)
                }
                Button("Stop Trip Log", systemImage: "stop.fill", role: .destructive) {
                    confirmsEnd = true
                }
            }
        } label: {
            Label("Recording", systemImage: "slider.horizontal.3")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(indicatorTint)
        .accessibilityLabel("Trip Log recording controls")
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
            Divider().frame(height: 26)
            portraitMetric(title: "STOPS", value: "\(day.stops.count)", symbol: "mappin.and.ellipse")
            Divider().frame(height: 26)
            portraitMetric(title: "TIME", value: day.elapsedTime.tripLogDuration, symbol: "clock")
        }
        .padding(.vertical, 4)
        .nativeSurfaceCard(cornerRadius: 14)
    }

    private func portraitMetric(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.caption).foregroundStyle(NativeShellPalette.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                Text(value).font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 7)
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
                        timeText: day.startedAt.formatted(date: .omitted, time: .shortened),
                        title: "Trip Started",
                        subtitle: day.startedAddress
                            ?? day.points.first.map { "Near \($0.coordinate.fireVaultCoordinateLabel)" }
                            ?? "Waiting for starting address",
                        symbol: "play.fill",
                        tint: NativeShellPalette.green
                    )

                    ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                        Divider().padding(.leading, 48)
                        Button {
                            editingStop = .init(dayID: day.id, stopID: stop.id)
                        } label: {
                            portraitTimelineRow(
                                timeText: stopTimeRange(stop, in: day),
                                title: stop.title,
                                subtitle: stopSubtitle(stop, in: day),
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
                            timeText: endedAt.formatted(date: .omitted, time: .shortened),
                            title: "Trip Ended",
                            subtitle: [day.endedAddress, day.totalDistanceMeters.tripLogMiles]
                                .compactMap { $0 }
                                .joined(separator: " • "),
                            symbol: "stop.fill",
                            tint: NativeShellPalette.red
                        )
                    }
                }
            }
        }
    }

    private func portraitTimelineRow(
        timeText: String,
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        showsDisclosure: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(timeText)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func stopTimeRange(_ stop: FireVaultBreadcrumbStop, in day: FireVaultBreadcrumbDay) -> String {
        let arrival = stop.arrival.formatted(date: .omitted, time: .shortened)
        let departure = day.effectiveDeparture(for: stop).formatted(date: .omitted, time: .shortened)
        return "\(arrival) – \(departure)"
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
            HStack(spacing: 10) {
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

                Button {
                    breadcrumbs.startWorkday(accounts: store.accounts)
                    selectedDayID = breadcrumbs.activeDay?.id
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeShellPalette.green)
            }

            HStack(spacing: 10) {
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
        if stop.needsReview { return NativeShellPalette.amber }
        return stop.accountID == nil ? NativeShellPalette.green : NativeShellPalette.blue
    }

    private func stopSubtitle(
        _ stop: FireVaultBreadcrumbStop,
        in day: FireVaultBreadcrumbDay
    ) -> String {
        let review = stop.needsReview ? "Needs review • " : ""
        return "\(review)\(stop.subtitle) • \(day.stopDuration(for: stop).tripLogDuration)"
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
