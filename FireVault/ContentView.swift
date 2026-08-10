//
//  ContentView.swift
//  FireVault
//
//  Pure SwiftUI application root for Build 1.08.07.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var store = FireVaultStore()
    @StateObject private var settings = FireVaultNativeSettingsStore()
    @StateObject private var locationService = FireVaultLocationService()
    @StateObject private var liveBreadcrumbs = FireVaultBreadcrumbStore()
    @StateObject private var quickActions = FireVaultQuickActionCenter.shared
    @StateObject private var widgetDeepLinks = FireVaultWidgetDeepLinkCenter.shared
    @StateObject private var privacyLock = FireVaultPrivacyLockController()
    @State private var demoBreadcrumbs: FireVaultBreadcrumbStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsSplash = true

    init() {
        _demoBreadcrumbs = State(initialValue: FireVaultDemoShowroom.makeBreadcrumbStore())
    }

    private var activeBreadcrumbs: FireVaultBreadcrumbStore {
        store.demoMode ? demoBreadcrumbs : liveBreadcrumbs
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                applicationContent(availableSize: geometry.size)
                    .accessibilityHidden(showsSplash || isPrivacyLocked)

                if showsSplash {
                    FireVaultSplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }

                if isPrivacyLocked {
                    FireVaultPrivacyLockView(controller: privacyLock)
                        .transition(.opacity)
                        .zIndex(2)
                } else if scenePhase != .active,
                          settings.preferences.privacy.hideInAppSwitcher {
                    FireVaultPrivacyShieldView()
                        .zIndex(3)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.selectedAccountID)
        .preferredColorScheme(preferredColorScheme)
        .task {
            prepareActiveVault()
            store.configureCategoryRules(settings.preferences.categoryRules ?? [])
            privacyLock.configure(enabled: settings.preferences.privacy.enabled)
            handlePendingQuickAction()
            handlePendingWidgetDeepLink()
            updateWidgetSnapshot()
            guard showsSplash else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.15 : 3.65))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.18 : 0.5)) {
                showsSplash = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                prepareActiveVault()
                privacyLock.lockIfNeeded(settings.preferences.privacy)
                if isPrivacyLocked {
                    privacyLock.authenticate()
                } else {
                    handlePendingQuickAction()
                    handlePendingWidgetDeepLink()
                }
            case .background:
                privacyLock.enteredBackground()
            default:
                break
            }
        }
        .onChange(of: privacyLock.isUnlocked) { _, unlocked in
            if unlocked {
                handlePendingQuickAction()
                handlePendingWidgetDeepLink()
            }
        }
        .onChange(of: quickActions.pendingAction) { _, _ in
            handlePendingQuickAction()
        }
        .onChange(of: widgetDeepLinks.pendingLink) { _, _ in
            handlePendingWidgetDeepLink()
        }
        .onChange(of: settings.preferences.privacy.enabled) { _, enabled in
            privacyLock.configure(enabled: enabled)
            if enabled { privacyLock.authenticate() }
        }
        .onChange(of: settings.preferences.categoryRules) { _, rules in
            store.configureCategoryRules(rules ?? [])
        }
        .onChange(of: store.demoMode) { _, _ in
            prepareActiveVault()
            updateWidgetSnapshot()
        }
        .onChange(of: store.selectedAccountID) { _, _ in
            updateWidgetSnapshot()
        }
        .onChange(of: activeBreadcrumbs.days) { _, _ in
            updateWidgetSnapshot()
        }
        .onChange(of: activeBreadcrumbs.isRecording) { _, _ in
            updateWidgetSnapshot()
        }
        .onChange(of: store.accounts.count) { _, count in
            guard store.demoMode, count <= 4 else { return }
            FireVaultDemoShowroom.installAccountsIfNeeded(into: store, force: true)
            demoBreadcrumbs = FireVaultDemoShowroom.makeBreadcrumbStore(forceReset: true)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch settings.appearance {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    private func applicationContent(availableSize: CGSize) -> some View {
        let isLandscapeWindow = availableSize.width > availableSize.height
        let isIPadDevice = UIDevice.current.userInterfaceIdiom == .pad
        let usesRegularIPad = (horizontalSizeClass == .regular || isIPadDevice)
            && availableSize.width >= 600
        let usesWideWorkspace = usesRegularIPad
            && isLandscapeWindow
            && availableSize.width >= 900
        let usesPortraitIPadWorkspace = usesRegularIPad
            && !isLandscapeWindow
            && store.selectedAccount == nil
        let payload = store.appPayload(
            userCoordinate: locationService.coordinate,
            liveLocationStatus: locationService.statusText
        )

        return VStack(spacing: 0) {
            FireVaultBrandHeader()

            ZStack {
                NativeShellPalette.background.ignoresSafeArea()

                if usesWideWorkspace {
                    FireVaultIPadWorkspaceV3(
                        payload: payload,
                        store: store,
                        settings: settings,
                        locationService: locationService,
                        breadcrumbs: activeBreadcrumbs
                    )
                    .transition(.opacity)
                } else if let account = store.selectedAccount, usesRegularIPad {
                    FireVaultAdaptiveAccountDetailsView(
                        account: account,
                        store: store,
                        locationService: locationService,
                        returnTab: store.selectedTab,
                        returnTitle: store.selectedTab == .nearby ? "Nearby" : "Account List"
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else if let account = store.selectedAccount {
                    FieldWorkspaceView(
                        account: account,
                        store: store,
                        settings: settings,
                        locationService: locationService
                    )
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else if usesPortraitIPadWorkspace {
                    FireVaultIPadPortraitWorkspace(
                        payload: payload,
                        store: store,
                        settings: settings,
                        locationService: locationService,
                        breadcrumbs: activeBreadcrumbs
                    )
                    .transition(.opacity)
                } else {
                    NativeAppShellView(
                        payload: payload,
                        store: store,
                        settings: settings,
                        locationService: locationService,
                        breadcrumbs: activeBreadcrumbs
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    private func prepareActiveVault() {
        if store.demoMode {
            FireVaultDemoShowroom.installAccountsIfNeeded(into: store)
        }
        activeBreadcrumbs.restoreActiveWorkday(accounts: store.accounts)
    }

    private var isPrivacyLocked: Bool {
        settings.preferences.privacy.enabled && !privacyLock.isUnlocked
    }

    private func handlePendingQuickAction() {
        guard !isPrivacyLocked, let action = quickActions.consume() else { return }

        switch action {
        case .startLog:
            store.closeAccount(to: .nearby)
            if let day = activeBreadcrumbs.activeDay, day.isPaused {
                activeBreadcrumbs.resumeWorkday(accounts: store.accounts)
            } else if activeBreadcrumbs.activeDay == nil {
                activeBreadcrumbs.startWorkday(accounts: store.accounts)
            }
        case .stopLog:
            store.closeAccount(to: .nearby)
            if activeBreadcrumbs.activeDay != nil {
                activeBreadcrumbs.endWorkday()
            }
        case .photo:
            store.closeAccount(to: .photo)
            store.requestCapture(.photo)
        case .scan:
            store.closeAccount(to: .photo)
            store.requestCapture(.scan)
        }
        updateWidgetSnapshot()
    }

    private func handlePendingWidgetDeepLink() {
        guard !isPrivacyLocked, let link = widgetDeepLinks.consume() else { return }

        switch link {
        case .tripLog:
            store.closeAccount(to: .trip)
        case .startTripLog:
            store.closeAccount(to: .trip)
            if let day = activeBreadcrumbs.activeDay, day.isPaused {
                activeBreadcrumbs.resumeWorkday(accounts: store.accounts)
            } else if activeBreadcrumbs.activeDay == nil {
                activeBreadcrumbs.startWorkday(accounts: store.accounts)
            }
        case .accounts:
            store.closeAccount(to: .accounts)
        case .photo:
            store.closeAccount(to: .photo)
            store.requestCapture(.photo)
        }
        updateWidgetSnapshot()
    }

    private func updateWidgetSnapshot() {
        let existing = FireVaultWidgetSharedStore.load()
        let day = activeBreadcrumbs.activeDay ?? activeBreadcrumbs.today
        let account = store.selectedAccount

        let state: FireVaultWidgetSnapshot.TripState
        if activeBreadcrumbs.isRecording {
            state = .recording
        } else if activeBreadcrumbs.activeDay?.isPaused == true {
            state = .paused
        } else if day?.endedAt != nil {
            state = .complete
        } else {
            state = .ready
        }

        FireVaultWidgetSharedStore.save(
            FireVaultWidgetSnapshot(
                updatedAt: Date(),
                tripState: state,
                tripStartedAt: day?.startedAt,
                elapsedSeconds: day?.elapsedTime ?? 0,
                distanceMiles: (day?.totalDistanceMeters ?? 0) / 1_609.344,
                stopCount: day?.stops.count ?? 0,
                accountName: account?.name ?? existing.accountName,
                accountID: account?.accountId ?? existing.accountID,
                accountCategory: account?.category ?? existing.accountCategory
            )
        )
    }
}

private struct FireVaultPrivacyShieldView: View {
    var body: some View {
        ZStack {
            NativeShellPalette.background.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(NativeShellPalette.blue)
                Text("FireVault Pro")
                    .font(.title2.bold())
                Text("Workspace hidden")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("firevault-app-switcher-shield")
    }
}

private struct FireVaultBrandHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    private var weekday: String {
        Date().formatted(.dateTime.weekday(.wide))
    }

    private var displayDate: String {
        let today = Date()
        let components = Calendar.current.dateComponents([.day, .year], from: today)
        return "\(today.formatted(.dateTime.month(.wide))) \(components.day ?? 0) \(components.year ?? 0)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            FireVaultProWordmark(
                vaultColor: colorScheme == .light ? .black : .white,
                proColor: colorScheme == .light ? .black : .white,
                fontSize: 15,
                proFontSize: 6.8,
                tracking: 1.35,
                hasBackground: false
            )
            .shadow(color: .black.opacity(colorScheme == .light ? 0.12 : 0.55), radius: 2, x: 0, y: 1)

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(weekday.uppercased())
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(1.15)
                    .foregroundStyle(NativeShellPalette.red)
                    .shadow(color: colorScheme == .light ? .black.opacity(0.32) : .black.opacity(0.92), radius: 2, y: 1)
                    .lineLimit(1)

                Text(displayDate.uppercased())
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .tracking(0.55)
                    .foregroundStyle(.primary)
                    .shadow(color: colorScheme == .light ? .white.opacity(0.75) : .black.opacity(0.8), radius: 2, y: 1)
                    .lineLimit(1)
            }
            .frame(height: 36, alignment: .center)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today, \(weekday), \(displayDate)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .frame(height: 43, alignment: .top)
        .background(NativeShellPalette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 1)
        }
        .accessibilityIdentifier("firevault-brand-header")
    }
}

private struct FireVaultSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoIsVisible = false
    @State private var titleIsVisible = false
    @State private var detailIsVisible = false
    @State private var shineOffset: CGFloat = -220

    var body: some View {
        ZStack {
            NativeShellPalette.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    NativeShellPalette.red.opacity(detailIsVisible ? 0.15 : 0.04),
                    NativeShellPalette.background.opacity(0)
                ],
                center: .center,
                startRadius: 15,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                ZStack {
                    FireVaultSplashAtmosphere(isAnimated: !reduceMotion)
                        .frame(width: 300, height: 286)
                        .opacity(logoIsVisible ? 1 : 0)

                    FireVaultProIconBadge(size: 176, cornerRadius: 39)
                        .overlay {
                            RoundedRectangle(cornerRadius: 39, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                        .overlay {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.38),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(width: 54, height: 250)
                            .rotationEffect(.degrees(18))
                            .offset(x: shineOffset)
                            .blendMode(.screen)
                            .mask {
                                RoundedRectangle(cornerRadius: 39, style: .continuous)
                                    .frame(width: 176, height: 176)
                            }
                        }
                        .shadow(color: NativeShellPalette.red.opacity(0.34), radius: 30, y: 14)
                }
                .scaleEffect(logoIsVisible ? 1 : 0.76)
                .opacity(logoIsVisible ? 1 : 0)

                VStack(spacing: 8) {
                    FireVaultProWordmark(fontSize: 40, proFontSize: 13, tracking: 0.4)
                    .shadow(color: .black.opacity(0.42), radius: 8, y: 4)

                    Text("FIELD WORKSPACE")
                        .font(.caption.bold())
                        .tracking(3.6)
                        .foregroundStyle(.secondary)
                }
                .offset(y: titleIsVisible ? 0 : 18)
                .opacity(titleIsVisible ? 1 : 0)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                NativeShellPalette.red.opacity(0.2),
                                NativeShellPalette.red,
                                NativeShellPalette.red.opacity(0.2)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: detailIsVisible ? 132 : 0, height: 3)
                    .opacity(detailIsVisible ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FireVault Pro")
        .accessibilityValue("Loading field workspace")
        .accessibilityIdentifier("firevault-splash")
        .task {
            if reduceMotion {
                logoIsVisible = true
                titleIsVisible = true
                detailIsVisible = true
            } else {
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }

                withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                    logoIsVisible = true
                }

                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.7)) {
                    titleIsVisible = true
                }

                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.75)) {
                    detailIsVisible = true
                }
                withAnimation(.easeInOut(duration: 1.15)) {
                    shineOffset = 220
                }
            }
        }
    }
}

private struct FireVaultSplashAtmosphere: View {
    let isAnimated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimated)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawFirelight(in: &context, size: size, time: time)
                drawSmoke(in: &context, size: size, time: time)
                drawFlames(in: &context, size: size, time: time)
                drawEmbers(in: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawFirelight(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let pulse = CGFloat(0.92 + sin(time * 4.1) * 0.08)
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.70)
        let radius = size.width * 0.45 * pulse
        let glow = Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius * 0.55,
            width: radius * 2,
            height: radius * 1.1
        ))
        context.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [
                    Color.orange.opacity(0.23),
                    NativeShellPalette.red.opacity(0.10),
                    .clear
                ]),
                center: center,
                startRadius: 2,
                endRadius: radius
            )
        )
    }

    private func drawSmoke(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        for index in 0..<10 {
            let seed = Double(index) * 0.137
            let progress = positiveRemainder(time * (0.075 + seed * 0.018) + seed, 1)
            let rise = CGFloat(progress)
            let drift = sin(time * 0.42 + Double(index) * 1.73) * 20
            let x = size.width * 0.5 + CGFloat(drift) + CGFloat(index - 5) * 3.2
            let y = size.height * 0.60 - rise * size.height * 0.48
            let width = 28 + rise * 66
            let height = width * 0.56
            let life = sin(.pi * progress)
            let opacity = 0.025 + life * 0.09
            let center = CGPoint(x: x, y: y)
            let smoke = Path(ellipseIn: CGRect(
                x: x - width * 0.5,
                y: y - height * 0.5,
                width: width,
                height: height
            ))
            context.fill(
                smoke,
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(opacity * 0.52),
                        Color.gray.opacity(opacity),
                        Color.black.opacity(opacity * 0.38),
                        .clear
                    ]),
                    center: center,
                    startRadius: 1,
                    endRadius: width * 0.52
                )
            )
        }
    }

    private func drawFlames(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let baseY = size.height * 0.84
        let flameCount = 9

        for index in 0..<flameCount {
            let normalized = CGFloat(index) / CGFloat(flameCount - 1)
            let x = size.width * (0.25 + normalized * 0.50)
            let flicker = CGFloat(sin(time * (5.1 + Double(index) * 0.17) + Double(index) * 0.91))
            let width: CGFloat = 22 + CGFloat(index % 3) * 3
            let height: CGFloat = 34 + CGFloat((index * 13) % 24) + flicker * 9
            let lean = CGFloat(sin(time * 3.3 + Double(index) * 1.21)) * 8
            let tip = CGPoint(x: x + lean, y: baseY - height)

            var flame = Path()
            flame.move(to: CGPoint(x: x - width * 0.52, y: baseY))
            flame.addCurve(
                to: tip,
                control1: CGPoint(x: x - width * 0.72, y: baseY - height * 0.34),
                control2: CGPoint(x: tip.x - width * 0.18, y: tip.y + height * 0.22)
            )
            flame.addCurve(
                to: CGPoint(x: x + width * 0.52, y: baseY),
                control1: CGPoint(x: tip.x + width * 0.22, y: tip.y + height * 0.28),
                control2: CGPoint(x: x + width * 0.70, y: baseY - height * 0.30)
            )
            flame.closeSubpath()

            context.fill(
                flame,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.yellow.opacity(0.92),
                        Color.orange.opacity(0.82),
                        NativeShellPalette.red.opacity(0.20)
                    ]),
                    startPoint: CGPoint(x: x, y: baseY),
                    endPoint: tip
                )
            )

            let innerHeight = height * 0.55
            var innerFlame = Path()
            innerFlame.move(to: CGPoint(x: x - width * 0.18, y: baseY))
            innerFlame.addQuadCurve(
                to: CGPoint(x: x + lean * 0.35, y: baseY - innerHeight),
                control: CGPoint(x: x - width * 0.28, y: baseY - innerHeight * 0.45)
            )
            innerFlame.addQuadCurve(
                to: CGPoint(x: x + width * 0.18, y: baseY),
                control: CGPoint(x: x + width * 0.30, y: baseY - innerHeight * 0.42)
            )
            innerFlame.closeSubpath()
            context.fill(innerFlame, with: .color(.white.opacity(0.72)))
        }
    }

    private func drawEmbers(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        for index in 0..<14 {
            let progress = positiveRemainder(time * 0.18 + Double(index) * 0.071, 1)
            let rise = CGFloat(progress)
            let x = size.width * 0.5
                + CGFloat(sin(time * 1.7 + Double(index) * 2.11)) * (34 + rise * 34)
            let y = size.height * 0.82 - rise * size.height * 0.62
            let radius = max(0.8, 2.7 - rise * 1.8)
            let ember = Path(ellipseIn: CGRect(
                x: x - radius,
                y: y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(
                ember,
                with: .color(Color.orange.opacity(sin(.pi * progress) * 0.85))
            )
        }
    }

    private func positiveRemainder(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
