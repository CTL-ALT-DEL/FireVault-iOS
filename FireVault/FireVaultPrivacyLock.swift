//
//  FireVaultPrivacyLock.swift
//  FireVault
//
//  Local Face ID / device-owner protection for a valid Supabase session.
//

import Combine
import LocalAuthentication
import SwiftUI

@MainActor
final class FireVaultPrivacyLockController: ObservableObject {
    @Published private(set) var isUnlocked = true
    @Published private(set) var isAuthenticating = false
    @Published private(set) var message = ""

    private var backgroundedAt: Date?

    func configure(enabled: Bool) {
        if enabled {
            isUnlocked = false
        } else {
            isUnlocked = true
            message = ""
        }
    }

    func enteredBackground() {
        backgroundedAt = Date()
    }

    func lockIfNeeded(_ preferences: FireVaultPrivacyPreferences) {
        guard preferences.enabled else {
            isUnlocked = true
            backgroundedAt = nil
            return
        }
        guard preferences.lockOnBackground else { return }
        guard let backgroundedAt else {
            // Face ID temporarily makes the scene inactive. Only a real
            // background transition should start an auto-lock interval.
            return
        }
        self.backgroundedAt = nil
        let elapsed = Date().timeIntervalSince(backgroundedAt)
        if preferences.autoLockMinutes == 0
            || elapsed >= Double(preferences.autoLockMinutes * 60) {
            isUnlocked = false
        }
    }

    func authenticate() {
        guard !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        message = ""

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isAuthenticating = false
            message = error?.localizedDescription
                ?? "Face ID or the device passcode is not available."
            return
        }

        Task {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Unlock your signed-in FireVault workspace."
                )
                isUnlocked = success
                message = success ? "" : "FireVault remains locked."
            } catch {
                message = error.localizedDescription
            }
            isAuthenticating = false
        }
    }
}

struct FireVaultPrivacyLockView: View {
    @ObservedObject var controller: FireVaultPrivacyLockController

    var body: some View {
        ZStack {
            NativeShellPalette.background.ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "faceid")
                    .font(.system(size: 62, weight: .medium))
                    .foregroundStyle(NativeShellPalette.blue)

                VStack(spacing: 7) {
                    Text("FireVault Locked")
                        .font(.title2.bold())
                    Text("Use Face ID or your device passcode to open the signed-in workspace.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !controller.message.isEmpty {
                    Text(controller.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    controller.authenticate()
                } label: {
                    Label(
                        controller.isAuthenticating ? "Unlocking…" : "Unlock FireVault",
                        systemImage: "faceid"
                    )
                    .font(.headline)
                    .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .tint(NativeShellPalette.blue)
                .disabled(controller.isAuthenticating)
            }
            .padding(30)
        }
        .accessibilityIdentifier("firevault-privacy-lock")
        .task {
            controller.authenticate()
        }
    }
}
