//
//  FireVaultTripLogControlIntents.swift
//  FireVault
//
//  App-process controls used by the Trip Log Live Activity.
//

import AppIntents
import Foundation

enum FireVaultTripLogControlCommand: String, Codable, Equatable {
    case pause
    case resume
    case end
}

extension Notification.Name {
    nonisolated static let fireVaultTripLogControlRequested = Notification.Name(
        "us.bannerman.firevault.trip-log-control-requested"
    )
}

enum FireVaultTripLogControlMailbox {
    nonisolated private static let commandKey = "firevault.trip-log.control.pending.v1"

    nonisolated static func send(_ command: FireVaultTripLogControlCommand) {
        guard let defaults = UserDefaults(suiteName: FireVaultWidgetSharedStore.appGroup) else {
            return
        }
        defaults.set(command.rawValue, forKey: commandKey)
        NotificationCenter.default.post(name: .fireVaultTripLogControlRequested, object: nil)
    }

    nonisolated static func consume() -> FireVaultTripLogControlCommand? {
        guard let defaults = UserDefaults(suiteName: FireVaultWidgetSharedStore.appGroup),
              let rawValue = defaults.string(forKey: commandKey) else {
            return nil
        }
        defaults.removeObject(forKey: commandKey)
        return FireVaultTripLogControlCommand(rawValue: rawValue)
    }
}

struct FireVaultPauseTripLogIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Trip Log"
    static let description = IntentDescription("Pause the active FireVault Trip Log.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        FireVaultTripLogControlMailbox.send(.pause)
        return .result()
    }
}

struct FireVaultResumeTripLogIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Trip Log"
    static let description = IntentDescription("Resume the paused FireVault Trip Log.")
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        FireVaultTripLogControlMailbox.send(.resume)
        return .result()
    }
}

struct FireVaultEndTripLogIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Trip Log"
    static let description = IntentDescription("Finish and save the active FireVault Trip Log.")
    static let isDiscoverable = false
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        FireVaultTripLogControlMailbox.send(.end)
        var snapshot = FireVaultWidgetSharedStore.load()
        let now = Date()
        snapshot.elapsedSeconds = snapshot.elapsedTime(at: now)
        snapshot.updatedAt = now
        snapshot.tripState = .complete
        FireVaultWidgetSharedStore.save(snapshot)
        return .result()
    }
}
