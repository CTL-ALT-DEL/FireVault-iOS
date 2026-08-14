//
//  FireVaultHelpPresentations.swift
//  FireVault
//
//  Illustrated, replayable walkthroughs for the in-app Help center.
//

import SwiftUI

enum FireVaultHelpSection: String, CaseIterable, Identifiable {
    case gettingAround = "Getting Around"
    case accounts = "Accounts & Arrival Maps"
    case tripLog = "Trip Log & Reports"
    case location = "Photos, Maps & Location"
    case safety = "Storage, Privacy & Demonstration"

    var id: String { rawValue }
}

enum FireVaultHelpTopic: String, CaseIterable, Identifiable {
    case nearby, accounts, tripLog, photo
    case accountWorkspace, arrivalMap, categoryRules, csvImport
    case record, liveDetails, history, reports
    case photoOverlays, mapLayers, gpsDiagnostics, plusCodes
    case fileStorage, privacy, demoMode, resetDemoData

    var id: String { rawValue }

    var section: FireVaultHelpSection {
        switch self {
        case .nearby, .accounts, .tripLog, .photo: .gettingAround
        case .accountWorkspace, .arrivalMap, .categoryRules, .csvImport: .accounts
        case .record, .liveDetails, .history, .reports: .tripLog
        case .photoOverlays, .mapLayers, .gpsDiagnostics, .plusCodes: .location
        case .fileStorage, .privacy, .demoMode, .resetDemoData: .safety
        }
    }

    var title: String {
        switch self {
        case .nearby: "Nearby"
        case .accounts: "Accounts"
        case .tripLog: "Trip Log"
        case .photo: "Photo"
        case .accountWorkspace: "Account workspace"
        case .arrivalMap: "Arrival Map"
        case .categoryRules: "Category rules"
        case .csvImport: "CSV import"
        case .record: "Record"
        case .liveDetails: "Live details"
        case .history: "History"
        case .reports: "Reports"
        case .photoOverlays: "Photo overlays"
        case .mapLayers: "Map layers"
        case .gpsDiagnostics: "GPS Diagnostics"
        case .plusCodes: "Plus Codes"
        case .fileStorage: "File Storage"
        case .privacy: "Privacy"
        case .demoMode: "Demo Mode"
        case .resetDemoData: "Reset Demo Data"
        }
    }

    var summary: String {
        switch self {
        case .nearby: "Find the closest mapped accounts and act without leaving the map."
        case .accounts: "Search every saved account and open its complete field workspace."
        case .tripLog: "Record the workday, review stops, and create polished reports."
        case .photo: "Capture, scan, or import field images into the right account."
        case .accountWorkspace: "Keep notes, files, equipment, and locations together."
        case .arrivalMap: "Save the exact parking, entrance, panel, and riser locations."
        case .categoryRules: "Apply consistent category tags automatically with IF/THEN rules."
        case .csvImport: "Bring account records into FireVault with a review step before saving."
        case .record: "Start, pause, resume, and end a reliable Trip Log session."
        case .liveDetails: "Choose the live driving and GPS measurements that matter to you."
        case .history: "Reopen any recorded day to review its route and stops."
        case .reports: "Export clean daily or weekly Trip Log reports as PDF files."
        case .photoOverlays: "Place readable account information on a photo without hiding the work."
        case .mapLayers: "Switch between Standard, Satellite, and Hybrid map views."
        case .gpsDiagnostics: "Understand location accuracy, speed, elevation, and GPS health."
        case .plusCodes: "Create a compact location code directly from GPS coordinates."
        case .fileStorage: "Control where photos and scans are stored and how they are organized."
        case .privacy: "Protect customer information when FireVault is locked or backgrounded."
        case .demoMode: "Explore a realistic sample workspace without touching live records."
        case .resetDemoData: "Return the showroom to its original sample condition safely."
        }
    }

    var symbol: String {
        switch self {
        case .nearby: "location.fill"
        case .accounts: "magnifyingglass"
        case .tripLog: "truck.box.fill"
        case .photo: "camera.fill"
        case .accountWorkspace: "building.2"
        case .arrivalMap: "figure.walk"
        case .categoryRules: "tag.fill"
        case .csvImport: "tablecells"
        case .record: "record.circle"
        case .liveDetails: "gauge.with.dots.needle.50percent"
        case .history: "clock.arrow.circlepath"
        case .reports: "doc.richtext"
        case .photoOverlays: "camera.filters"
        case .mapLayers: "square.3.layers.3d"
        case .gpsDiagnostics: "waveform.path.ecg.rectangle"
        case .plusCodes: "plus.square.dashed"
        case .fileStorage: "folder.fill"
        case .privacy: "lock.shield.fill"
        case .demoMode: "theatermasks.fill"
        case .resetDemoData: "arrow.counterclockwise"
        }
    }

    var steps: [String] {
        switch self {
        case .nearby: ["Open Nearby to center the map on your current position.", "Select an account card or map pin.", "Call, route, or open the account details from the map controls."]
        case .accounts: ["Search by name, address, ID, category, or saved information.", "Choose the matching account.", "Open its notes, files, equipment, or locations."]
        case .tripLog: ["Start Trip Log at the beginning of the workday.", "Review detected stops as the day is recorded.", "End the day, then open History or Report."]
        case .photo: ["Choose the destination account.", "Take a photo, scan a document, or choose an existing image.", "Review the preview and save it to the account."]
        case .accountWorkspace: ["Open an account from Nearby or Accounts.", "Choose Notes, Files & Scans, Equipment, or Locations.", "Add or review the field record you need."]
        case .arrivalMap: ["Open Locations inside an account.", "Add a parking, entrance, panel, or riser pin.", "Select Route for walking directions to the saved point."]
        case .categoryRules: ["Create an IF condition that identifies matching accounts.", "Choose the category to apply when the condition matches.", "Preview, run, and review the rule results."]
        case .csvImport: ["Choose a CSV containing account records.", "Map and validate the imported columns.", "Review warnings, then approve the accounts to save."]
        case .record: ["Tap Start when the workday begins.", "Pause only when route tracking should temporarily stop.", "Resume as needed, then End Day when work is complete."]
        case .liveDetails: ["Open the live-detail selector.", "Choose Speed, Trip, Direction, Elevation, or GPS.", "Enable Auto Rotate to cycle through your selected details."]
        case .history: ["Open History from Trip Log.", "Choose a saved workday.", "Inspect the route, account visits, stop times, and classifications."]
        case .reports: ["Open a recorded day and choose Report.", "Select Daily or Weekly and Compact or Detailed.", "Export the finished PDF to Files or the share sheet."]
        case .photoOverlays: ["Open Settings, then Photo Overlay.", "Resize and drag the information panel into position.", "Preview and save before capturing the next field photo."]
        case .mapLayers: ["Tap the layers button on a map.", "Choose Standard, Satellite, or Hybrid.", "Set the default under Settings, GPS & Maps when desired."]
        case .gpsDiagnostics: ["Open GPS Diagnostics from Settings.", "Check the accuracy value and signal status first.", "Review coordinates, speed, elevation, direction, and rolling charts."]
        case .plusCodes: ["Open an account or saved location with coordinates.", "Generate its Plus Code locally.", "Copy, search, or include the code in reports as configured."]
        case .fileStorage: ["Open Settings, then File Storage.", "Choose photo quality, scan format, and destinations.", "Set folder organization and upload behavior, then Save."]
        case .privacy: ["Open Settings, then Privacy Lock.", "Choose the locking and background protections you need.", "Confirm the app hides protected content when it leaves the foreground."]
        case .demoMode: ["Open Demo Mode from Settings.", "Enter the isolated sample workspace.", "Explore its accounts, equipment, locations, notes, and Trip Log history."]
        case .resetDemoData: ["Open Demo Mode settings.", "Choose Reset Demo Data and review the confirmation.", "Confirm Reset Demo; live records and authentication remain untouched."]
        }
    }

    static func topics(in section: FireVaultHelpSection) -> [FireVaultHelpTopic] {
        allCases.filter { $0.section == section }
    }
}

struct FireVaultHelpPresentationView: View {
    let topic: FireVaultHelpTopic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    @State private var replayID = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FireVaultHelpIllustration(topic: topic, phase: phase)
                    .frame(height: 220)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Animated illustration for \(topic.title)")

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: topic.symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(NativeShellPalette.blue, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.title)
                            .font(.title2.bold())
                        Text(topic.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack {
                    Text("HOW IT WORKS")
                        .font(.caption.weight(.heavy))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        replayID += 1
                    } label: {
                        Label("Replay", systemImage: "arrow.clockwise")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Replays the illustrated walkthrough")
                }

                VStack(spacing: 10) {
                    ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.bold())
                                .foregroundStyle(phase > index ? .white : NativeShellPalette.blue)
                                .frame(width: 30, height: 30)
                                .background(phase > index ? NativeShellPalette.blue : NativeShellPalette.blue.opacity(0.12), in: Circle())
                            Text(step)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if phase > index {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(NativeShellPalette.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(14)
                        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(phase > index ? NativeShellPalette.blue.opacity(0.30) : Color.primary.opacity(0.08))
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 84)
        }
        .background(NativeShellPalette.background.ignoresSafeArea())
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: replayID) { await playPresentation() }
    }

    @MainActor
    private func playPresentation() async {
        if reduceMotion {
            phase = 4
            return
        }
        phase = 0
        for nextPhase in 1...4 {
            try? await Task.sleep(nanoseconds: nextPhase == 1 ? 240_000_000 : 520_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.78)) {
                phase = nextPhase
            }
        }
    }
}

private struct FireVaultHelpIllustration: View {
    let topic: FireVaultHelpTopic
    let phase: Int

    private var accent: Color {
        switch topic.section {
        case .gettingAround: NativeShellPalette.blue
        case .accounts: NativeShellPalette.green
        case .tripLog: NativeShellPalette.red
        case .location: NativeShellPalette.amber
        case .safety: NativeShellPalette.purple
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(
                    LinearGradient(
                        colors: [NativeShellPalette.surfaceRaised, accent.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 26)
                .stroke(accent.opacity(0.34), lineWidth: 1.5)
            scene
                .padding(20)
        }
        .shadow(color: NativeShellPalette.cardShadow, radius: 12, y: 7)
        .clipped()
    }

    @ViewBuilder
    private var scene: some View {
        switch topic {
        case .nearby: mapScene
        case .accounts: searchScene
        case .tripLog: tripScene
        case .photo: photoScene
        case .accountWorkspace: workspaceScene
        case .arrivalMap: arrivalScene
        case .categoryRules: rulesScene
        case .csvImport: importScene
        case .record: recordScene
        case .liveDetails: telemetryScene
        case .history: historyScene
        case .reports: reportScene
        case .photoOverlays: overlayScene
        case .mapLayers: layersScene
        case .gpsDiagnostics: diagnosticsScene
        case .plusCodes: plusCodeScene
        case .fileStorage: storageScene
        case .privacy: privacyScene
        case .demoMode: demoScene
        case .resetDemoData: resetScene
        }
    }

    private var mapScene: some View {
        ZStack {
            HelpRouteShape().trim(from: 0, to: phase >= 2 ? 1 : 0.05)
                .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                .animation(.easeInOut(duration: 0.8), value: phase)
            helpPin("building.2.fill", x: -100, y: 45, visible: phase >= 2)
            helpPin("cross.case.fill", x: 35, y: -45, visible: phase >= 3)
            helpPin("location.fill", x: 115, y: 35, visible: phase >= 4)
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(accent)
                .offset(x: phase >= 2 ? 42 : -115, y: phase >= 2 ? 12 : 55)
        }
    }

    private var searchScene: some View {
        VStack(spacing: 9) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text(phase >= 2 ? "Central" : "Search accounts")
                    .foregroundStyle(phase >= 2 ? .primary : .secondary)
                Spacer()
            }
            .padding(12)
            .background(.thinMaterial, in: Capsule())
            ForEach(0..<3) { index in
                HStack {
                    Image(systemName: index == 0 ? "building.2.fill" : "building.fill")
                        .foregroundStyle(index == 0 ? accent : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        RoundedRectangle(cornerRadius: 3).frame(width: CGFloat(125 - index * 15), height: 8)
                        RoundedRectangle(cornerRadius: 3).frame(width: CGFloat(82 + index * 10), height: 5).opacity(0.35)
                    }
                    Spacer()
                    if index == 0 && phase >= 3 { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                }
                .padding(9)
                .background(index == 0 && phase >= 3 ? accent.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                .opacity(phase >= index + 1 ? 1 : 0.18)
            }
        }
        .foregroundStyle(.secondary)
    }

    private var tripScene: some View {
        ZStack {
            HelpRouteShape().trim(from: 0, to: phase >= 3 ? 1 : phase >= 2 ? 0.52 : 0.12)
                .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [10, 7]))
            Image(systemName: "truck.box.fill")
                .font(.system(size: 40))
                .foregroundStyle(accent)
                .offset(x: phase >= 3 ? 105 : phase >= 2 ? 5 : -105, y: phase >= 3 ? 32 : phase >= 2 ? -15 : 48)
            VStack {
                HStack {
                    metric("TRIP", phase >= 3 ? "18.4 mi" : "0.0 mi")
                    Spacer()
                    metric("STOPS", phase >= 4 ? "3" : "0")
                }
                Spacer()
            }
        }
    }

    private var photoScene: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.35), Color.orange.opacity(0.38)], startPoint: .top, endPoint: .bottom))
                .frame(width: 245, height: 150)
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "mountain.2.fill").font(.system(size: 68)).foregroundStyle(.white.opacity(0.75)).padding(12)
                }
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.68))
                .frame(width: phase >= 3 ? 150 : 72, height: phase >= 3 ? 58 : 28)
                .overlay(Text(phase >= 3 ? "CENTRAL CLINIC\nPANEL ROOM" : "SITE").font(.caption2.bold()).foregroundStyle(.white))
                .offset(x: -28, y: 35)
            Image(systemName: phase >= 4 ? "checkmark.circle.fill" : "camera.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(phase >= 4 ? NativeShellPalette.green : accent)
                .offset(x: 118, y: 62)
                .scaleEffect(phase >= 2 ? 1 : 0.72)
        }
    }

    private var workspaceScene: some View {
        ZStack {
            Image(systemName: "building.2.crop.circle.fill").font(.system(size: 76)).foregroundStyle(accent)
            workspaceChip("note.text", "Notes", x: -105, y: -62, step: 1)
            workspaceChip("folder.fill", "Files", x: 105, y: -62, step: 2)
            workspaceChip("wrench.and.screwdriver.fill", "Equipment", x: -105, y: 64, step: 3)
            workspaceChip("mappin.and.ellipse", "Locations", x: 105, y: 64, step: 4)
        }
    }

    private var arrivalScene: some View {
        ZStack {
            HelpRouteShape().trim(from: 0, to: phase >= 3 ? 1 : 0.08)
                .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [7, 6]))
            helpPin("car.fill", x: -105, y: 48, visible: phase >= 1)
            helpPin("door.left.hand.open", x: 5, y: -35, visible: phase >= 2)
            helpPin("bell.and.waves.left.and.right.fill", x: 110, y: 42, visible: phase >= 3)
            if phase >= 4 {
                Label("Walking route", systemImage: "figure.walk").font(.caption.bold()).padding(8).background(.thinMaterial, in: Capsule()).offset(y: 75)
            }
        }
    }

    private var rulesScene: some View {
        HStack(spacing: 14) {
            ruleCard("IF", "Account type\nis Hospital", step: 1)
            Image(systemName: "arrow.right").font(.title.bold()).foregroundStyle(accent).opacity(phase >= 2 ? 1 : 0.2)
            ruleCard("THEN", "Add category\nMedical", step: 3)
            Image(systemName: "tag.circle.fill").font(.system(size: 48)).foregroundStyle(accent).scaleEffect(phase >= 4 ? 1 : 0.3)
        }
    }

    private var importScene: some View {
        HStack(spacing: 28) {
            Image(systemName: "tablecells.fill").font(.system(size: 72)).foregroundStyle(accent).offset(x: phase >= 2 ? 0 : -25)
            Image(systemName: "arrow.right.circle.fill").font(.title).foregroundStyle(accent).opacity(phase >= 2 ? 1 : 0)
            VStack(spacing: 8) {
                ForEach(0..<3) { index in
                    Label(["Central Clinic", "Summit School", "Ridge Office"][index], systemImage: "building.fill")
                        .font(.caption.bold()).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
                        .opacity(phase >= index + 2 ? 1 : 0.18)
                }
            }.frame(width: 145)
        }
    }

    private var recordScene: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(accent.opacity(0.22), lineWidth: 18).frame(width: 92, height: 92).scaleEffect(phase >= 2 ? 1.28 : 0.82)
                Circle().fill(phase >= 2 ? accent : Color.secondary).frame(width: 58, height: 58)
                Image(systemName: phase >= 4 ? "checkmark" : phase >= 2 ? "pause.fill" : "play.fill").font(.title.bold()).foregroundStyle(.white)
            }
            HStack(spacing: 16) {
                statePill("START", active: phase >= 1)
                statePill("RECORD", active: phase >= 2)
                statePill("PAUSE", active: phase >= 3)
                statePill("END", active: phase >= 4)
            }
        }
    }

    private var telemetryScene: some View {
        HStack(spacing: 12) {
            metricCard("SPEED", phase >= 2 ? "42 mph" : "—", "speedometer")
            metricCard("TRIP", phase >= 3 ? "12.8 mi" : "—", "road.lanes")
            metricCard("GPS", phase >= 4 ? "± 16 ft" : "—", "location.fill")
        }
    }

    private var historyScene: some View {
        ZStack {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 18)
                    .fill(NativeShellPalette.surface)
                    .frame(width: 240, height: 118)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(["TODAY", "YESTERDAY", "MONDAY"][index]).font(.caption.bold()).foregroundStyle(accent)
                            Text(["42.6 mi • 4 stops", "31.2 mi • 3 stops", "56.8 mi • 5 stops"][index]).font(.headline)
                            Label("Recorded Trip Log", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                        }.padding()
                    }
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 4)
                    .offset(x: CGFloat(index * 18), y: CGFloat(index * -16))
                    .opacity(phase >= index + 1 ? 1 : 0)
            }
        }
    }

    private var reportScene: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.white).frame(width: 185, height: 175).shadow(radius: 8)
                .overlay {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { Image(systemName: "flame.fill").foregroundStyle(.red); Text("TRIP LOG").font(.caption.bold()) }
                        Divider()
                        HelpRouteShape().trim(from: 0, to: phase >= 2 ? 1 : 0.08).stroke(accent, lineWidth: 3).frame(height: 50)
                        HStack { metric("MILES", "42.6"); Spacer(); metric("STOPS", "4") }
                        RoundedRectangle(cornerRadius: 2).fill(.gray.opacity(0.25)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 2).fill(.gray.opacity(0.18)).frame(width: 112, height: 6)
                    }.padding(16).foregroundStyle(.black)
                }
            Image(systemName: "square.and.arrow.up.circle.fill").font(.system(size: 52)).foregroundStyle(accent).offset(x: 105, y: 70).scaleEffect(phase >= 4 ? 1 : 0.45)
        }
    }

    private var overlayScene: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(LinearGradient(colors: [.blue.opacity(0.55), .green.opacity(0.28)], startPoint: .top, endPoint: .bottom)).frame(width: 255, height: 155)
            Image(systemName: "building.columns.fill").font(.system(size: 72)).foregroundStyle(.white.opacity(0.65)).offset(y: 20)
            VStack(alignment: .leading, spacing: 2) { Text("COUNTY ANNEX").bold(); Text("Main panel • Level 1").font(.caption) }
                .foregroundStyle(.white).padding(10).background(.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 10))
                .scaleEffect(phase >= 3 ? 0.82 : 1.05).offset(x: phase >= 2 ? -35 : 25, y: phase >= 2 ? 44 : -35)
        }
    }

    private var layersScene: some View {
        ZStack {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 16)
                    .fill([Color.blue.opacity(0.38), Color.green.opacity(0.42), Color.orange.opacity(0.38)][index])
                    .frame(width: 220, height: 120)
                    .overlay(Text(["STANDARD", "SATELLITE", "HYBRID"][index]).font(.caption.bold()).foregroundStyle(.white).padding(), alignment: .bottomLeading)
                    .rotationEffect(.degrees(Double(index - 1) * 4))
                    .offset(x: CGFloat(index * 12 - 12), y: phase >= index + 1 ? CGFloat(index * -18 + 18) : 70)
                    .opacity(phase >= index + 1 ? 1 : 0)
            }
        }
    }

    private var diagnosticsScene: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                metricCard("ACCURACY", phase >= 2 ? "± 12 ft" : "—", "scope")
                metricCard("SPEED", phase >= 3 ? "38 mph" : "—", "speedometer")
                metricCard("ELEVATION", phase >= 4 ? "5,284 ft" : "—", "mountain.2")
            }
            HelpWaveShape().trim(from: 0, to: phase >= 2 ? 1 : 0).stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(height: 55)
        }
    }

    private var plusCodeScene: some View {
        VStack(spacing: 18) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 64)).foregroundStyle(accent).scaleEffect(phase >= 2 ? 1 : 0.45)
            Text(phase >= 3 ? "85M6+7Q BOISE, ID" : "••••+••")
                .font(.title3.monospaced().bold()).padding(.horizontal, 18).padding(.vertical, 12).background(.thinMaterial, in: Capsule())
            if phase >= 4 { Label("Generated locally", systemImage: "checkmark.shield.fill").font(.caption.bold()).foregroundStyle(NativeShellPalette.green) }
        }
    }

    private var storageScene: some View {
        ZStack {
            Image(systemName: "folder.fill").font(.system(size: 118)).foregroundStyle(accent)
            HStack(spacing: 13) {
                Image(systemName: "photo.fill").offset(y: phase >= 2 ? 45 : -55)
                Image(systemName: "doc.text.fill").offset(y: phase >= 3 ? 45 : -55)
                Image(systemName: "scanner.fill").offset(y: phase >= 4 ? 45 : -55)
            }.font(.system(size: 34)).foregroundStyle(.white)
        }
    }

    private var privacyScene: some View {
        ZStack {
            Image(systemName: "shield.fill").font(.system(size: 135)).foregroundStyle(accent.opacity(0.25)).scaleEffect(phase >= 2 ? 1 : 0.7)
            Image(systemName: phase >= 3 ? "lock.fill" : "lock.open.fill").font(.system(size: 54)).foregroundStyle(accent)
            if phase >= 4 { Image(systemName: "checkmark.circle.fill").font(.system(size: 34)).foregroundStyle(NativeShellPalette.green).offset(x: 55, y: 55) }
        }
    }

    private var demoScene: some View {
        ZStack {
            ForEach(0..<5) { index in
                Image(systemName: ["building.2.fill", "cross.case.fill", "graduationcap.fill", "shippingbox.fill", "hotel.fill"][index])
                    .font(.system(size: 34)).foregroundStyle(index.isMultiple(of: 2) ? accent : NativeShellPalette.blue)
                    .offset(x: CGFloat((index % 3) * 92 - 92), y: CGFloat((index / 3) * 78 - 38))
                    .scaleEffect(phase >= min(index + 1, 4) ? 1 : 0.15)
            }
            Text("DEMO").font(.caption.bold()).padding(8).background(accent, in: Capsule()).foregroundStyle(.white).offset(y: 78)
        }
    }

    private var resetScene: some View {
        ZStack {
            Image(systemName: "archivebox.fill").font(.system(size: 90)).foregroundStyle(accent)
            Image(systemName: "arrow.counterclockwise.circle.fill").font(.system(size: 58)).foregroundStyle(NativeShellPalette.blue)
                .offset(x: 80, y: -55).rotationEffect(.degrees(phase >= 4 ? 360 : 0))
            if phase >= 4 { Label("Live data safe", systemImage: "checkmark.shield.fill").font(.caption.bold()).padding(9).background(.thinMaterial, in: Capsule()).offset(y: 82) }
        }
    }

    private func helpPin(_ symbol: String, x: CGFloat, y: CGFloat, visible: Bool) -> some View {
        Image(systemName: symbol).font(.title2.bold()).foregroundStyle(.white).frame(width: 44, height: 44).background(accent, in: Circle()).shadow(radius: 4)
            .offset(x: x, y: y).scaleEffect(visible ? 1 : 0.15).opacity(visible ? 1 : 0)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption2.bold()).foregroundStyle(.secondary); Text(value).font(.headline.monospacedDigit()) }
    }

    private func workspaceChip(_ symbol: String, _ label: String, x: CGFloat, y: CGFloat, step: Int) -> some View {
        Label(label, systemImage: symbol).font(.caption.bold()).padding(9).background(.thinMaterial, in: Capsule()).offset(x: x, y: y).scaleEffect(phase >= step ? 1 : 0.2).opacity(phase >= step ? 1 : 0)
    }

    private func ruleCard(_ heading: String, _ detail: String, step: Int) -> some View {
        VStack(spacing: 7) { Text(heading).font(.caption.bold()).foregroundStyle(accent); Text(detail).font(.caption).multilineTextAlignment(.center) }
            .padding(12).frame(width: 92, height: 95).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14)).scaleEffect(phase >= step ? 1 : 0.45).opacity(phase >= step ? 1 : 0.2)
    }

    private func statePill(_ label: String, active: Bool) -> some View {
        Text(label).font(.caption2.bold()).foregroundStyle(active ? .white : .secondary).padding(.horizontal, 10).padding(.vertical, 6).background(active ? accent : Color.secondary.opacity(0.12), in: Capsule())
    }

    private func metricCard(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(accent)
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold().monospacedDigit()).minimumScaleFactor(0.65).lineLimit(1)
        }.frame(maxWidth: .infinity).padding(.vertical, 14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct HelpRouteShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 18, y: rect.maxY - 30))
        path.addCurve(
            to: CGPoint(x: rect.maxX - 18, y: rect.maxY - 42),
            control1: CGPoint(x: rect.width * 0.30, y: rect.minY + 8),
            control2: CGPoint(x: rect.width * 0.62, y: rect.maxY + 6)
        )
        return path
    }
}

private struct HelpWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        let points: [CGFloat] = [0.12, 0.34, 0.44, 0.54, 0.66, 0.78, 1]
        let values: [CGFloat] = [0.48, 0.44, 0.05, 0.92, 0.47, 0.38, 0.50]
        for (x, y) in zip(points, values) {
            path.addLine(to: CGPoint(x: rect.width * x, y: rect.height * y))
        }
        return path
    }
}
