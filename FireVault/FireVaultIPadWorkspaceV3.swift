//
//  FireVaultIPadWorkspaceV3.swift
//  FireVault
//
//  Stable entry point for the consolidated adaptive iPad workspace.
//

import SwiftUI

struct FireVaultIPadWorkspaceV3: View {
    let payload: FireVaultAppPayload
    @ObservedObject var store: FireVaultStore
    @ObservedObject var settings: FireVaultNativeSettingsStore
    @ObservedObject var locationService: FireVaultLocationService
    @ObservedObject var breadcrumbs: FireVaultBreadcrumbStore
    @ObservedObject var unifiedSync: FireVaultUnifiedSyncService

    var body: some View {
        FireVaultIPadWorkspaceV2(
            payload: payload,
            store: store,
            settings: settings,
            locationService: locationService,
            breadcrumbs: breadcrumbs,
            unifiedSync: unifiedSync
        )
        .accessibilityIdentifier("ipad-adaptive-workspace-v3")
    }
}
