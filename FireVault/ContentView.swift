//
//  ContentView.swift
//  FireVault
//
//  Pure SwiftUI application root for Build 1.06.03.
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
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.55 : 1.65))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.32)) {
                showsSplash = false
            }
        }
    }

    @ViewBuilder
    private var applicationContent: some View {
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

private struct FireVaultSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            NativeShellPalette.background.ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(NativeShellPalette.red.opacity(pulse ? 0.16 : 0.08))
                        .frame(width: 150, height: 150)
                        .scaleEffect(pulse ? 1.06 : 0.92)

                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    NativeShellPalette.red,
                                    NativeShellPalette.red.opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)
                        .shadow(color: NativeShellPalette.red.opacity(0.28), radius: 22, y: 10)

                    Image(systemName: "shield.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(NativeShellPalette.red)
                        .offset(y: 2)
                }
                .scaleEffect(revealed ? 1 : 0.72)
                .opacity(revealed ? 1 : 0)

                VStack(spacing: 5) {
                    Text("FireVault")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("FIELD WORKSPACE")
                        .font(.caption.bold())
                        .tracking(3.2)
                        .foregroundStyle(.secondary)
                }
                .offset(y: revealed ? 0 : 12)
                .opacity(revealed ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FireVault")
        .accessibilityValue("Loading field workspace")
        .accessibilityIdentifier("firevault-splash")
        .onAppear {
            if reduceMotion {
                revealed = true
                pulse = true
            } else {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
                    revealed = true
                }
                withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}
