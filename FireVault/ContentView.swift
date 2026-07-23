//
//  ContentView.swift
//  FireVault
//
//  Pure SwiftUI application root for Build 1.06.08.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = FireVaultStore()
    @StateObject private var settings = FireVaultNativeSettingsStore()
    @StateObject private var locationService = FireVaultLocationService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSplash = true

    var body: some View {
        ZStack {
            applicationContent
                .accessibilityHidden(showsSplash)

            if showsSplash {
                FireVaultSplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.selectedAccountID)
        .preferredColorScheme(.dark)
        .task {
            guard showsSplash else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.15 : 3.65))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.18 : 0.5)) {
                showsSplash = false
            }
        }
    }

    @ViewBuilder
    private var applicationContent: some View {
        VStack(spacing: 0) {
            FireVaultBrandHeader()

            ZStack {
                NativeShellPalette.background.ignoresSafeArea()

                if let account = store.selectedAccount {
                    FieldWorkspaceView(account: account, store: store)
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else {
                    NativeAppShellView(
                        payload: store.appPayload(
                            userCoordinate: locationService.coordinate,
                            liveLocationStatus: locationService.statusText
                        ),
                        store: store,
                        settings: settings,
                        locationService: locationService
                    )
                    .transition(.opacity)
                }
            }
        }
    }
}

private struct FireVaultBrandHeader: View {
    var body: some View {
        HStack(spacing: 9) {
            Image("FireVaultLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            (
                Text("FIRE")
                    .foregroundColor(NativeShellPalette.red)
                + Text("VAULT")
                    .foregroundColor(.white)
            )
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .tracking(1.35)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(NativeShellPalette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.07))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FireVault")
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
                    (
                        Text("FIRE")
                            .foregroundColor(NativeShellPalette.red)
                        + Text("VAULT")
                            .foregroundColor(.white)
                    )
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .tracking(0.4)

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
