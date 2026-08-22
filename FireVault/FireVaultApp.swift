//
//  FireVaultApp.swift
//  FireVault
//
//  Created by David Bannerman on 7/20/26.
//

import SwiftUI

@main
struct FireVaultApp: App {
    @UIApplicationDelegateAdaptor(FireVaultAppDelegate.self) private var appDelegate

    init() {
        FireVaultThemeAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            FireVaultAuthGate()
        }
    }
}
