//
//  FireVaultIPadBreadcrumbsView.swift
//  FireVault
//
//  Landscape-first Breadcrumbs workspace for Build 1.08.07.
//

import CoreLocation
import MapKit
import SwiftUI

struct FireVaultIPadBreadcrumbsView: View {
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @ObservedObject var store: FireVaultStore
    let technicianName: String
    let companyName: String
    let includeCoordinatesInReports: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDayID: UUID?
    @State private var selectedStop: FireVaultIPadStopSelection?
    @State private var confirmsEnd = false
    @State private var showsReport = false
    @State private var showsHistory = false

    private var selectedDay: FireVaultBreadcrumbDay? {
        if let selectedDayID {
            return breadcrumbs.days.first { $0.id == selectedDayID }
        }
        return breadcrumbs.today ?? breadcrumbs.days.first
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let rightColumnWidth = max(360, min(440, geometry.size.width * 0.34))
                let mapLimit = max(420, geometry.size.width - rightColumnWidth - 48)
                let mapSide = min(max(420, geometry.size.height - 48), mapLimit)

                HStack(alignment: .top, spacing: 16) {
                    if let day = selectedDay {
                        VStack(alignment: .leading, spacing: 6) {
                            routeMap(day)
                                .frame(width: mapSide, height: mapSide)
                        }
                        .frame(width: mapSide)
                    } else {
                        ContentUnavailableView(
                            "No Trip Log Yet",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text("Start your workday to record today’s route and account stops.")
                        )
                        .frame(width: mapSide, height: mapSide)
                        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        daySelector
                        trackingControls

                        if let day = selectedDay {
                            summary(day)

                            ScrollView {
                                timeline(day)
                                    .padding(.bottom, 24)
                            }
                            .scrollIndicators(.visible)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: rightColumnWidth)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(NativeShellPalette.background)
            .navigationTitle("Trip Log")
            .navigationBarTitleDisplayMode(.inline)
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
        .onAppear {
            selectedDayID = breadcrumbs.today?.id ?? breadcrumbs.days.first?.id
        }
        .sheet(item: $selectedStop) { selection in
            FireVaultBreadcrumbStopEditor(
                breadcrumbs: breadcrumbs,
                store: store,
                dayID: selection.dayID,
                stopID: selection.stopID
            ) { accountID in
                store.openAccount(accountID)
                selectedStop = nil
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
        .sheet(isPresented: $showsHistory) {
            FireVaultTripLogHistoryCalendarView(
                days: breadcrumbs.days,
                selectedDayID: selectedDayID
            ) { dayID in
                selectedDayID = dayID
                showsHistory = false
            }
        }
        .accessibilityIdentifier("ipad-breadcrumbs-workspace")
    }

    private var daySelector: some View {
        NativeShellCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDay?.startedAt.formatted(.dateTime.weekday(.wide)) ?? "TODAY")
                        .font(.caption.bold())
                        .tracking(1.1)
                        .foregroundStyle(NativeShellPalette.red)
                    Text(selectedDay?.startedAt.formatted(date: .long, time: .omitted)
                        ?? Date().formatted(date: .long, time: .omitted))
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(indicatorTitle)
                        .font(.caption.bold())
                        .tracking(0.8)
                        .foregroundStyle(indicatorTint)
                    Text(breadcrumbs.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var trackingControls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                historyMenu
                reportButton
            }
            .padding(9)
            .background(
                NativeShellPalette.blue.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(NativeShellPalette.blue.opacity(0.32), lineWidth: 1)
            }

            HStack(spacing: 10) {
                Label(indicatorTitle, systemImage: breadcrumbs.isRecording ? "location.fill" : "location")
                    .font(.caption.bold())
                    .foregroundStyle(indicatorTint)
                Spacer()
                recordingMenu
            }

            if breadcrumbs.permissionState.requiresSettings {
                Button("Open Location Settings", systemImage: "gearshape") {
                    breadcrumbs.openLocationSettings()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

    private var historyMenu: some View {
        Button {
            showsHistory = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 27, weight: .bold))
                Text("HISTORY").font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.bordered)
        .disabled(breadcrumbs.days.isEmpty)
    }

    private var reportButton: some View {
        Button {
            showsReport = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 27, weight: .bold))
                Text("REPORT").font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedDay == nil)
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
            Label("Recording Controls", systemImage: "slider.horizontal.3")
                .font(.caption.bold())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(indicatorTint)
    }

    @ViewBuilder
    private func routeMap(_ day: FireVaultBreadcrumbDay) -> some View {
        if day.points.isEmpty {
            ContentUnavailableView(
                "Waiting for Route",
                systemImage: "map",
                description: Text(
                    day.isActive
                        ? "Keep the workday active while FireVault Pro collects reliable GPS positions."
                        : "No reliable GPS points were recorded for this workday."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NativeShellPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(
                color: colorScheme == .light ? .black.opacity(0.22) : .clear,
                radius: 12,
                y: 6
            )
        } else {
            Map(initialPosition: .automatic, interactionModes: [.pan, .zoom, .rotate]) {
                MapPolyline(coordinates: day.points.map(\.coordinate))
                    .stroke(
                        NativeShellPalette.red,
                        style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )

                if let first = day.points.first {
                    Marker("Workday Start", systemImage: "play.fill", coordinate: first.coordinate)
                        .tint(NativeShellPalette.green)
                }

                ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                    Annotation(stop.title, coordinate: stop.coordinate) {
                        Button {
                            selectedStop = .init(dayID: day.id, stopID: stop.id)
                        } label: {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(stopTint(stop), in: Circle())
                                .overlay {
                                    Circle().stroke(.white.opacity(0.9), lineWidth: 2)
                                }
                                .shadow(radius: 5)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let last = day.points.last, !day.isActive {
                    Marker("Workday End", systemImage: "stop.fill", coordinate: last.coordinate)
                        .tint(NativeShellPalette.red)
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(
                color: colorScheme == .light ? .black.opacity(0.22) : .clear,
                radius: 12,
                y: 6
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(day.startedAt.formatted(.dateTime.weekday(.wide)))
                        .font(.caption.bold())
                        .tracking(1.1)
                        .foregroundStyle(NativeShellPalette.red)
                    Text(day.startedAt.formatted(date: .long, time: .omitted))
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .padding(12)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(12)
                .allowsHitTesting(false)
            }
            .accessibilityIdentifier("ipad-breadcrumbs-square-map")
        }
    }

    private func summary(_ day: FireVaultBreadcrumbDay) -> some View {
        HStack(spacing: 1) {
            metric(title: "MILES", value: miles(day.totalDistanceMeters), symbol: "road.lanes")
            Divider().frame(height: 44)
            metric(title: "STOPS", value: "\(day.stops.count)", symbol: "mappin.and.ellipse")
            Divider().frame(height: 44)
            metric(title: "ELAPSED", value: duration(day.elapsedTime), symbol: "clock")
        }
        .padding(.vertical, 12)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metric(title: String, value: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(NativeShellPalette.blue)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2.bold())
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeline(_ day: FireVaultBreadcrumbDay) -> some View {
        NativeShellCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("DAILY LOG")
                    .font(.caption.bold())
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)

                timelineRow(
                    time: day.startedAt,
                    title: "Workday Started",
                    subtitle: "Route recording began",
                    symbol: "play.fill",
                    tint: NativeShellPalette.green
                )

                ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                    Divider().padding(.leading, 44)
                    Button {
                        selectedStop = .init(dayID: day.id, stopID: stop.id)
                    } label: {
                        timelineRow(
                            time: stop.arrival,
                            title: stop.title,
                            subtitle: "\(stop.subtitle) • \(duration(day.stopDuration(for: stop)))",
                            symbol: "\(index + 1).circle.fill",
                            tint: stopTint(stop)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let endedAt = day.endedAt {
                    Divider().padding(.leading, 44)
                    timelineRow(
                        time: endedAt,
                        title: "Workday Ended",
                        subtitle: miles(day.totalDistanceMeters),
                        symbol: "stop.fill",
                        tint: NativeShellPalette.red
                    )
                }
            }
        }
    }

    private func timelineRow(
        time: Date,
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(time.formatted(date: .omitted, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func stopTint(_ stop: FireVaultBreadcrumbStop) -> Color {
        if stop.isPersonalStop { return .secondary }
        return stop.accountID == nil ? NativeShellPalette.amber : NativeShellPalette.blue
    }

    private func miles(_ meters: Double) -> String {
        String(format: "%.1f mi", meters / 1_609.344)
    }

    private func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

private struct FireVaultIPadStopSelection: Identifiable {
    let dayID: UUID
    let stopID: UUID
    var id: UUID { stopID }
}
