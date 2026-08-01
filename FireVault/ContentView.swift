//
//  ContentView.swift
//  FireVault
//
//  Pure SwiftUI application root for Build 1.08.07.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = FireVaultStore()
    @StateObject private var settings = FireVaultNativeSettingsStore()
    @StateObject private var locationService = FireVaultLocationService()
    @StateObject private var liveBreadcrumbs = FireVaultBreadcrumbStore()
    @StateObject private var quickActions = FireVaultQuickActionCenter.shared
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
            privacyLock.configure(enabled: settings.preferences.privacy.enabled)
            handlePendingQuickAction()
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
                }
            case .background:
                privacyLock.enteredBackground()
            default:
                break
            }
        }
        .onChange(of: privacyLock.isUnlocked) { _, unlocked in
            if unlocked { handlePendingQuickAction() }
        }
        .onChange(of: quickActions.pendingAction) { _, _ in
            handlePendingQuickAction()
        }
        .onChange(of: settings.preferences.privacy.enabled) { _, enabled in
            privacyLock.configure(enabled: enabled)
            if enabled { privacyLock.authenticate() }
        }
        .onChange(of: store.demoMode) { _, _ in
            prepareActiveVault()
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
        let usesRegularIPad = horizontalSizeClass == .regular && availableSize.width >= 600
        let usesWideWorkspace = usesRegularIPad
            && isLandscapeWindow
            && availableSize.width >= 900
        let usesPortraitIPadNearby = usesRegularIPad
            && !isLandscapeWindow
            && store.selectedTab == .nearby
            && store.selectedAccount == nil
        let payload = store.appPayload(
            userCoordinate: locationService.coordinate,
            liveLocationStatus: locationService.statusText
        )

        return VStack(spacing: 0) {
            FireVaultBrandHeader()

            ZStack {
                NativeShellPalette.background.ignoresSafeArea()

                if let account = store.selectedAccount, usesRegularIPad {
                    FireVaultAdaptiveAccountDetailsView(
                        account: account,
                        store: store,
                        locationService: locationService,
                        returnTab: store.selectedTab,
                        returnTitle: store.selectedTab == .nearby ? "Nearby" : "Account List"
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else if usesWideWorkspace {
                    FireVaultIPadWorkspaceV3(
                        payload: payload,
                        store: store,
                        settings: settings,
                        locationService: locationService,
                        breadcrumbs: activeBreadcrumbs
                    )
                    .transition(.opacity)
                } else if let account = store.selectedAccount {
                    FieldWorkspaceView(
                        account: account,
                        store: store,
                        settings: settings,
                        locationService: locationService
                    )
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else if usesPortraitIPadNearby {
                    FireVaultIPadPortraitNearbyViewV2(
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
                Text("FireVault")
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
            Image("FireVaultLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .padding(.top, 1)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Text("FIRE")
                    .foregroundColor(NativeShellPalette.red)
                    .tracking(1.35)
                Text("VAULT")
                    .foregroundColor(.white)
                    .tracking(1.35)
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .shadow(color: .black.opacity(0.78), radius: 2, x: 0, y: 1)
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("FireVault")

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(weekday)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.82), radius: 2, x: 0, y: 1)
                    .lineLimit(1)

                Text(displayDate)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today, \(weekday), \(displayDate)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .frame(height: 48, alignment: .top)
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
    @State private var haloIsExpanded = false
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
                    Circle()
                        .stroke(NativeShellPalette.red.opacity(haloIsExpanded ? 0.04 : 0.28), lineWidth: 2)
                        .frame(width: 218, height: 218)
                        .scaleEffect(haloIsExpanded ? 1.16 : 0.82)

                    Image("FireVaultLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 176, height: 176)
                        .clipShape(RoundedRectangle(cornerRadius: 39, style: .continuous))
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
                    HStack(spacing: 0) {
                        Text("FIRE")
                            .foregroundColor(NativeShellPalette.red)
                            .tracking(0.4)
                        Text("VAULT")
                            .foregroundColor(.white)
                            .tracking(0.4)
                    }
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .shadow(color: .black.opacity(0.42), radius: 8, y: 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("FireVault")

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
        .accessibilityLabel("FireVault")
        .accessibilityValue("Loading field workspace")
        .accessibilityIdentifier("firevault-splash")
        .task {
            if reduceMotion {
                logoIsVisible = true
                titleIsVisible = true
                detailIsVisible = true
                haloIsExpanded = true
            } else {
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }

                withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                    logoIsVisible = true
                }
                withAnimation(.easeOut(duration: 1.4)) {
                    haloIsExpanded = true
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
