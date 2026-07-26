//
//  FireVaultQuickActions.swift
//  FireVault
//
//  Home Screen Quick Actions shared by iPhone and iPad.
//

import Combine
import UIKit

enum FireVaultQuickAction: String, CaseIterable, Equatable {
    case startLog = "start-log"
    case stopLog = "stop-log"
    case photo
    case scan

    private static let typePrefix = "com.davidbannerman.FireVault.quick-action."

    var shortcutType: String {
        Self.typePrefix + rawValue
    }

    init?(shortcutType: String) {
        guard shortcutType.hasPrefix(Self.typePrefix) else { return nil }
        self.init(rawValue: String(shortcutType.dropFirst(Self.typePrefix.count)))
    }

    var title: String {
        switch self {
        case .startLog: "Start Log"
        case .stopLog: "Stop Log"
        case .photo: "Photo"
        case .scan: "Scan"
        }
    }

    var symbol: String {
        switch self {
        case .startLog: "location.fill"
        case .stopLog: "stop.circle.fill"
        case .photo: "camera.fill"
        case .scan: "doc.viewfinder"
        }
    }

    var shortcutItem: UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: shortcutType,
            localizedTitle: title,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: symbol),
            userInfo: nil
        )
    }
}

@MainActor
final class FireVaultQuickActionCenter: ObservableObject {
    static let shared = FireVaultQuickActionCenter()

    @Published private(set) var pendingAction: FireVaultQuickAction?

    func receive(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = FireVaultQuickAction(shortcutType: shortcutItem.type) else {
            return false
        }
        pendingAction = action
        return true
    }

    func consume() -> FireVaultQuickAction? {
        defer { pendingAction = nil }
        return pendingAction
    }

    func installShortcutItems(on application: UIApplication) {
        application.shortcutItems = FireVaultQuickAction.allCases.map(\.shortcutItem)
    }
}

final class FireVaultAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        FireVaultOrientationCoordinator.supportedOrientations
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            FireVaultQuickActionCenter.shared.installShortcutItems(on: application)
            if #unavailable(iOS 26.0),
               let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
                _ = FireVaultQuickActionCenter.shared.receive(shortcutItem)
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        Task { @MainActor in
            if let shortcutItem = options.shortcutItem {
                _ = FireVaultQuickActionCenter.shared.receive(shortcutItem)
            }
        }

        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = FireVaultSceneDelegate.self
        }
        return configuration
    }
}

@MainActor
enum FireVaultOrientationCoordinator {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func beginOverlayPlacement() {
        supportedOrientations = .allButUpsideDown
        updateSupportedOrientations(preferred: .landscape)
    }

    static func finishOverlayPlacement() {
        supportedOrientations = .portrait
        updateSupportedOrientations(preferred: .portrait)
    }

    private static func updateSupportedOrientations(
        preferred: UIInterfaceOrientationMask? = nil
    ) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        scene.keyWindow?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()

        guard let preferred else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: preferred))
    }
}

final class FireVaultSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        Task { @MainActor in
            _ = FireVaultQuickActionCenter.shared.receive(shortcutItem)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
        await MainActor.run {
            FireVaultQuickActionCenter.shared.receive(shortcutItem)
        }
    }
}
