//
//  FireVaultBreadcrumbCoordinator.swift
//  FireVault
//
//  Keeps live and demo Breadcrumbs archives isolated for Build 1.08.06.
//

import Combine

@MainActor
final class FireVaultBreadcrumbCoordinator: ObservableObject {
    let live: FireVaultBreadcrumbStore
    @Published private(set) var demo: FireVaultBreadcrumbStore

    init() {
        live = FireVaultBreadcrumbStore()
        demo = FireVaultDemoShowroom.makeBreadcrumbStore()
    }

    func activeStore(demoMode: Bool) -> FireVaultBreadcrumbStore {
        demoMode ? demo : live
    }

    func resetDemoHistory() {
        demo = FireVaultDemoShowroom.makeBreadcrumbStore(forceReset: true)
    }
}
