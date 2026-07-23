//
//  ContentView.swift
//  FireVault
//
//  Pure SwiftUI application root for Build 1.05.02.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = FireVaultStore()
    @StateObject private var settings = FireVaultNativeSettingsStore()

    var body: some View {
        ZStack {
            NativeShellPalette.background.ignoresSafeArea()

            if let account = store.selectedAccount {
                FieldWorkspaceView(account: account, store: store)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                NativeAppShellView(
                    payload: store.appPayload,
                    store: store,
                    settings: settings
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.selectedAccountID)
        .preferredColorScheme(.dark)
    }
}
