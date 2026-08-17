//
//  FireVaultTests.swift
//  FireVaultTests
//
//  Created by David Bannerman on 7/20/26.
//

import XCTest
import CoreLocation
import MapKit
@testable import FireVault

@MainActor
final class FireVaultTests: XCTestCase {
    func testRemoteFeatureControlDefaultsToEnabledWithoutConfiguration() throws {
        let suite = "FireVaultTests.RemoteFeatures.Defaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = FireVaultNativeSettingsStore(defaults: defaults)

        XCTAssertTrue(settings.isFeatureVisible("tab.nearby"))
    }

    func testCachedRemoteFeatureControlOverridesLocalVisibility() throws {
        let suite = "FireVaultTests.RemoteFeatures.Cache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONEncoder().encode(["tab.nearby": false]),
            forKey: "firevault.remote.features.v1"
        )

        let settings = FireVaultNativeSettingsStore(defaults: defaults)

        XCTAssertFalse(settings.isFeatureVisible("tab.nearby"))
        XCTAssertTrue(settings.isFeatureVisible("tab.accounts"))
    }

    func testBroadNearbyModuleDisablesRelatedIOSComponents() throws {
        let suite = "FireVaultTests.RemoteFeatures.Parent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONEncoder().encode(["nearby_accounts": false]),
            forKey: "firevault.remote.features.v1"
        )

        let settings = FireVaultNativeSettingsStore(defaults: defaults)

        XCTAssertFalse(settings.isFeatureVisible("tab.nearby"))
        XCTAssertFalse(settings.isFeatureVisible("nearby.map"))
        XCTAssertFalse(settings.isFeatureVisible("nearby.list"))
        XCTAssertTrue(settings.isFeatureVisible("tab.accounts"))
    }

    func testTripLogLiveActivityTimerReferencePreservesElapsedDuration() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_600)
        let state = FireVaultTripLogActivityAttributes.ContentState(
            status: .recording,
            updatedAt: updatedAt,
            elapsedSeconds: 600,
            distanceMiles: 8.5,
            stopCount: 2,
            showsMetrics: true
        )

        XCTAssertEqual(
            state.timerReferenceDate,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(state.formattedElapsedTime, "00:10:00")
    }

    func testTripLogLiveActivityContentStateRoundTripsWithoutPrivateSiteData() throws {
        let state = FireVaultTripLogActivityAttributes.ContentState(
            status: .paused,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_600),
            elapsedSeconds: 600,
            distanceMiles: 8.5,
            stopCount: 2,
            showsMetrics: true
        )

        let data = try JSONEncoder().encode(state)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(
            FireVaultTripLogActivityAttributes.ContentState.self,
            from: data
        )

        XCTAssertEqual(decoded, state)
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("account"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("address"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("longitude"))
    }

    func testLegacyLiveActivityStateDefaultsToVisibleMetrics() throws {
        let legacy = """
        {
          "status": "paused",
          "updatedAt": 700000000,
          "elapsedSeconds": 600,
          "distanceMiles": 8.5,
          "stopCount": 2
        }
        """
        let state = try JSONDecoder().decode(
            FireVaultTripLogActivityAttributes.ContentState.self,
            from: Data(legacy.utf8)
        )

        XCTAssertTrue(state.showsMetrics)
        XCTAssertEqual(state.status, .paused)
        XCTAssertEqual(state.stopCount, 2)
        XCTAssertNil(state.activeStopStartedAt)
        XCTAssertFalse(state.activeStopIsKnown)
    }

    func testLiveActivityTracksOnSiteTimeWithoutPrivateSiteIdentity() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_600)
        let arrival = now.addingTimeInterval(-300)
        let state = FireVaultTripLogActivityAttributes.ContentState(
            status: .recording,
            updatedAt: now,
            elapsedSeconds: 900,
            distanceMiles: 12.4,
            stopCount: 3,
            showsMetrics: true,
            activeStopStartedAt: arrival,
            activeStopIsKnown: true
        )

        let data = try JSONEncoder().encode(state)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(state.isOnSite)
        XCTAssertEqual(state.onSiteElapsedTime(at: now), 300, accuracy: 0.001)
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("account"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("address"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("latitude"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("longitude"))
    }

    func testLegacyNotificationPreferencesEnableLiveActivitiesSafely() throws {
        let legacy = """
        {
          "enabled": true,
          "tripLogStillRecording": true,
          "hideSensitiveDetails": true
        }
        """
        let preferences = try JSONDecoder().decode(
            FireVaultNotificationPreferences.self,
            from: Data(legacy.utf8)
        )

        XCTAssertTrue(preferences.liveActivitiesAreEnabled)
        XCTAssertTrue(preferences.showsLiveActivityMetrics)
    }

    func testRecordingWidgetElapsedTimeAdvancesFromSnapshotWithoutDoubleCounting() {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = FireVaultWidgetSnapshot(
            updatedAt: capturedAt,
            tripState: .recording,
            tripStartedAt: capturedAt.addingTimeInterval(-600),
            elapsedSeconds: 600,
            distanceMiles: 8.5,
            stopCount: 1,
            accountName: nil,
            accountID: nil,
            accountCategory: nil
        )

        XCTAssertEqual(
            snapshot.elapsedTime(at: capturedAt.addingTimeInterval(30)),
            630,
            accuracy: 0.001
        )
        XCTAssertEqual(
            snapshot.elapsedTime(at: capturedAt.addingTimeInterval(-30)),
            600,
            accuracy: 0.001
        )
    }

    func testStoppedWidgetElapsedTimeRemainsFrozen() {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = FireVaultWidgetSnapshot(
            updatedAt: capturedAt,
            tripState: .complete,
            tripStartedAt: capturedAt.addingTimeInterval(-600),
            elapsedSeconds: 600,
            distanceMiles: 8.5,
            stopCount: 1,
            accountName: nil,
            accountID: nil,
            accountCategory: nil
        )

        XCTAssertEqual(
            snapshot.elapsedTime(at: capturedAt.addingTimeInterval(3_600)),
            600,
            accuracy: 0.001
        )
    }

    func testTripLogIntegrityRemovesDuplicateRecordsAndRepairsTimes() {
        let dayID = UUID()
        let pointID = UUID()
        let stopID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let point = FireVaultBreadcrumbPoint(
            id: pointID,
            timestamp: start.addingTimeInterval(60),
            latitude: 43.615,
            longitude: -116.202,
            horizontalAccuracy: 12
        )
        let stop = FireVaultBreadcrumbStop(
            id: stopID,
            arrival: start.addingTimeInterval(120),
            departure: start.addingTimeInterval(90),
            latitude: 43.615,
            longitude: -116.202
        )
        let damaged = FireVaultBreadcrumbDay(
            id: dayID,
            startedAt: start,
            endedAt: start.addingTimeInterval(-20),
            points: [point, point],
            stops: [stop, stop]
        )

        let normalized = FireVaultTripLogIntegrity.normalized([damaged, damaged])

        XCTAssertEqual(normalized.count, 1)
        XCTAssertEqual(normalized[0].points.count, 1)
        XCTAssertEqual(normalized[0].stops.count, 1)
        XCTAssertEqual(normalized[0].endedAt, start)
        XCTAssertEqual(normalized[0].stops[0].departure, normalized[0].stops[0].arrival)
    }

    func testAccountStoreRecoversLastKnownGoodBackup() throws {
        let suite = "FireVaultTests.AccountRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "firevault.native.demo-mode.v1")
        let store = FireVaultStore(defaults: defaults)
        let original = store.addAccount()
        _ = store.addAccount()

        defaults.set(Data("damaged".utf8), forKey: "firevault.native.production-accounts.v1")
        let recovered = FireVaultStore(defaults: defaults)

        XCTAssertEqual(recovered.accounts.map(\.id), [original.id])
    }

    func testAccountBriefResponseDecodesAssistantText() throws {
        let data = try XCTUnwrap(#"{"success":true,"accountName":"ABC Medical","assistantText":"No recurring issues found."}"#.data(using: .utf8))

        let response = try JSONDecoder().decode(FireVaultAccountBriefResponse.self, from: data)

        XCTAssertEqual(response.assistantText, "No recurring issues found.")
    }

    func testAccountBriefRequestIncludesExistingAccountHistory() {
        let account = FireVaultWorkspaceAccount(
            id: "account-1",
            name: "ABC Medical",
            address: "100 Main Street",
            category: "Medical",
            accountId: "A-100",
            phone: "",
            favorite: false,
            latitude: nil,
            longitude: nil,
            tags: ["pull station"],
            notes: [
                .init(id: "note-1", title: "Pull station trouble", text: "Checked field wiring.", date: "2026-07-01")
            ],
            documents: [],
            equipment: [],
            locations: [],
            recent: []
        )

        let request = FireVaultAIService.makeRequest(for: account)

        XCTAssertEqual(request.accountName, "ABC Medical")
        XCTAssertTrue(request.technicianRequest.contains("A-100"))
        XCTAssertTrue(request.technicianRequest.contains("Pull station trouble"))
        XCTAssertTrue(request.technicianRequest.contains("Checked field wiring."))
        XCTAssertTrue(request.technicianRequest.contains("## Quick Summary"))
        XCTAssertTrue(request.technicianRequest.contains("each finding on its own bullet"))
    }

    func testAccountBriefDocumentParsesMarkdownSectionsAndBullets() {
        let document = FireVaultAccountBriefDocument(
            text: """
            ## Quick Summary
            - Pull station trouble was reported recently.

            ## Suggested Checks
            - Inspect field wiring before replacing the device.
            """
        )

        XCTAssertEqual(
            document.sections,
            [
                .init(title: "Quick Summary", items: ["Pull station trouble was reported recently."]),
                .init(title: "Suggested Checks", items: ["Inspect field wiring before replacing the device."])
            ]
        )
    }

    func testEveryHomeScreenQuickActionRoundTripsThroughItsShortcutType() {
        XCTAssertEqual(
            FireVaultQuickAction.allCases.map {
                FireVaultQuickAction(shortcutType: $0.shortcutType)
            },
            FireVaultQuickAction.allCases.map(Optional.some)
        )
        XCTAssertEqual(
            FireVaultQuickAction.allCases.map(\.title),
            ["Start Log", "Stop Log", "Photo", "Scan"]
        )
        XCTAssertTrue(FireVaultQuickAction.startLog.shortcutType.hasPrefix("us.bannerman.firevault.quick-action."))
        XCTAssertEqual(
            FireVaultQuickAction(shortcutType: "com.davidbannerman.FireVault.quick-action.photo"),
            .photo
        )
    }

    func testAddingProductionAccountSelectsItWithoutFakeLocationData() throws {
        let suite = "FireVaultTests.AddProductionAccount.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "firevault.native.demo-mode.v1")
        let store = FireVaultStore(defaults: defaults)

        let account = store.addAccount()

        XCTAssertEqual(store.selectedAccountID, account.id)
        XCTAssertEqual(store.selectedAccount?.id, account.id)
        XCTAssertEqual(account.name, "New Account 1")
        XCTAssertEqual(account.address, "")
        XCTAssertEqual(account.accountId, "")
        XCTAssertNil(account.latitude)
        XCTAssertNil(account.longitude)
    }

    func testUpdatingAccountDetailsPreservesFieldDataAndPersists() throws {
        let suite = "FireVaultTests.UpdateAccount.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "firevault.native.demo-mode.v1")
        let store = FireVaultStore(defaults: defaults)
        let account = store.addAccount()
        let index = try XCTUnwrap(store.accounts.firstIndex(where: { $0.id == account.id }))
        store.accounts[index].favorite = true
        store.accounts[index].latitude = 43.615
        store.accounts[index].longitude = -116.202
        store.accounts[index].tags = ["Priority"]
        store.accounts[index].notes = [.init(id: "note-1", title: "Panel", text: "Lobby", date: "Today")]
        store.accounts[index].documents = [.init(id: "doc-1", title: "Report", subtitle: "Annual", kind: "PDF", date: "Today")]
        store.accounts[index].equipment = [.init(id: "equipment-1", title: "FACP", subtitle: "Lobby", status: "Normal")]
        store.accounts[index].locations = [.init(id: "location-1", label: "Panel", subtitle: "Lobby", type: "Equipment", plusCode: "", latitude: 43.615, longitude: -116.202)]
        store.accounts[index].recent = [.init(id: "recent-1", title: "Created", subtitle: "Test", kind: "account", date: "Today")]

        XCTAssertTrue(
            store.updateAccount(
                id: account.id,
                name: "  Acme Fire Protection  ",
                address: "  100 Main Street  ",
                category: "  Commercial  ",
                accountId: "  ACME-100  ",
                phone: "  307-555-0100  "
            )
        )

        let updated = try XCTUnwrap(store.selectedAccount)
        XCTAssertEqual(updated.name, "Acme Fire Protection")
        XCTAssertEqual(updated.address, "100 Main Street")
        XCTAssertEqual(updated.category, "Commercial")
        XCTAssertEqual(updated.accountId, "ACME-100")
        XCTAssertEqual(updated.phone, "307-555-0100")
        XCTAssertTrue(updated.favorite)
        XCTAssertEqual(updated.latitude, 43.615)
        XCTAssertEqual(updated.longitude, -116.202)
        XCTAssertEqual(updated.tags, ["Priority"])
        XCTAssertEqual(updated.notes.map(\.id), ["note-1"])
        XCTAssertEqual(updated.documents.map(\.id), ["doc-1"])
        XCTAssertEqual(updated.equipment.map(\.id), ["equipment-1"])
        XCTAssertEqual(updated.locations.map(\.id), ["location-1"])
        XCTAssertEqual(updated.recent.map(\.id), ["recent-1"])

        let reloadedStore = FireVaultStore(defaults: defaults)
        let persisted = try XCTUnwrap(reloadedStore.accounts.first(where: { $0.id == account.id }))
        XCTAssertEqual(persisted, updated)
    }

    func testUpdatingAccountGPSRecalibratesCoordinateWithoutChangingFieldData() throws {
        let suite = "FireVaultTests.RecalibrateAccountGPS.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "firevault.native.demo-mode.v1")
        let store = FireVaultStore(defaults: defaults)
        let account = store.addAccount()
        let index = try XCTUnwrap(store.accounts.firstIndex(where: { $0.id == account.id }))
        store.accounts[index].notes = [
            .init(id: "note-1", title: "Access", text: "Call first", date: "Today")
        ]

        XCTAssertTrue(
            store.updateAccount(
                id: account.id,
                name: "API Systems Integrators",
                address: "7306 W Yellowstone Hwy, Casper, WY 82604",
                category: "Commercial",
                accountId: "AE230020",
                phone: "307-555-0100",
                latitude: 42.8734,
                longitude: -106.4431
            )
        )

        let updated = try XCTUnwrap(store.selectedAccount)
        XCTAssertEqual(updated.latitude, 42.8734)
        XCTAssertEqual(updated.longitude, -106.4431)
        XCTAssertEqual(updated.notes.map(\.id), ["note-1"])

        let reloaded = FireVaultStore(defaults: defaults)
        let persisted = try XCTUnwrap(reloaded.accounts.first(where: { $0.id == account.id }))
        XCTAssertEqual(persisted.latitude, 42.8734)
        XCTAssertEqual(persisted.longitude, -106.4431)
        XCTAssertEqual(persisted.notes.map(\.id), ["note-1"])
    }

    func testAccountNoteLifecyclePersistsWithoutChangingOtherAccountData() throws {
        let suite = "FireVaultTests.NoteLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "firevault.native.demo-mode.v1")
        let store = FireVaultStore(defaults: defaults)
        let account = store.addAccount()
        let accountIndex = try XCTUnwrap(store.accounts.firstIndex(where: { $0.id == account.id }))
        store.accounts[accountIndex].favorite = true
        store.accounts[accountIndex].latitude = 43.615
        store.accounts[accountIndex].equipment = [
            .init(id: "equipment-1", title: "FACP", subtitle: "Lobby", status: "Normal")
        ]

        let note = try XCTUnwrap(
            store.addNote(to: account.id, title: "  Panel trouble  ", text: "  Checked field wiring.  ")
        )
        XCTAssertEqual(note.title, "Panel trouble")
        XCTAssertEqual(note.text, "Checked field wiring.")

        XCTAssertTrue(
            store.updateNote(
                accountID: account.id,
                noteID: note.id,
                title: "   ",
                text: "  Replaced damaged conductor.  "
            )
        )

        let updatedAccount = try XCTUnwrap(store.accounts.first(where: { $0.id == account.id }))
        let updatedNote = try XCTUnwrap(updatedAccount.notes.first(where: { $0.id == note.id }))
        XCTAssertEqual(updatedNote.title, "Field note")
        XCTAssertEqual(updatedNote.text, "Replaced damaged conductor.")
        XCTAssertTrue(updatedAccount.favorite)
        XCTAssertEqual(updatedAccount.latitude, 43.615)
        XCTAssertEqual(updatedAccount.equipment.map(\.id), ["equipment-1"])

        let reloadedStore = FireVaultStore(defaults: defaults)
        let persisted = try XCTUnwrap(reloadedStore.accounts.first(where: { $0.id == account.id }))
        XCTAssertEqual(persisted.notes.first(where: { $0.id == note.id })?.text, "Replaced damaged conductor.")
        XCTAssertTrue(persisted.favorite)
        XCTAssertEqual(persisted.equipment.map(\.id), ["equipment-1"])

        XCTAssertTrue(reloadedStore.deleteNote(accountID: account.id, noteID: note.id))
        XCTAssertFalse(reloadedStore.accounts.first(where: { $0.id == account.id })?.notes.contains(where: { $0.id == note.id }) ?? true)
    }

    func testAccountEquipmentLifecyclePersistsWithoutChangingOtherAccountData() throws {
        let suite = "FireVaultTests.EquipmentLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "firevault.native.demo-mode.v1")
        let store = FireVaultStore(defaults: defaults)
        let account = store.addAccount()
        let accountIndex = try XCTUnwrap(store.accounts.firstIndex(where: { $0.id == account.id }))
        store.accounts[accountIndex].favorite = true
        store.accounts[accountIndex].notes = [
            .init(id: "note-1", title: "Panel", text: "Lobby", date: "Today")
        ]

        let equipment = try XCTUnwrap(
            store.addEquipment(
                to: account.id,
                title: "  Fire Alarm Control Panel (FACP)  ",
                subtitle: "  Notifier NFS2-3030  ",
                status: "  NODE 1  ",
                latitude: 43.615,
                longitude: -116.202
            )
        )
        XCTAssertEqual(equipment.title, "Fire Alarm Control Panel (FACP)")
        XCTAssertEqual(equipment.subtitle, "Notifier NFS2-3030")
        XCTAssertEqual(equipment.deviceAddress, "NODE 1")
        XCTAssertEqual(equipment.latitude, 43.615)
        XCTAssertEqual(equipment.longitude, -116.202)

        XCTAssertTrue(
            store.updateEquipment(
                accountID: account.id,
                equipmentID: equipment.id,
                title: "  Smoke Detector  ",
                subtitle: "  System Sensor  ",
                status: "  L1D042  ",
                latitude: 43.616,
                longitude: -116.203
            )
        )

        let updatedAccount = try XCTUnwrap(store.accounts.first(where: { $0.id == account.id }))
        let updatedEquipment = try XCTUnwrap(updatedAccount.equipment.first(where: { $0.id == equipment.id }))
        XCTAssertEqual(updatedEquipment.title, "Smoke Detector")
        XCTAssertEqual(updatedEquipment.subtitle, "System Sensor")
        XCTAssertEqual(updatedEquipment.deviceAddress, "L1D042")
        XCTAssertEqual(updatedEquipment.latitude, 43.616)
        XCTAssertEqual(updatedEquipment.longitude, -116.203)
        XCTAssertTrue(updatedAccount.favorite)
        XCTAssertEqual(updatedAccount.notes.map(\.id), ["note-1"])

        let reloadedStore = FireVaultStore(defaults: defaults)
        let persisted = try XCTUnwrap(reloadedStore.accounts.first(where: { $0.id == account.id }))
        XCTAssertEqual(persisted.equipment.first(where: { $0.id == equipment.id }), updatedEquipment)
        XCTAssertTrue(persisted.favorite)
        XCTAssertEqual(persisted.notes.map(\.id), ["note-1"])

        XCTAssertTrue(reloadedStore.deleteEquipment(accountID: account.id, equipmentID: equipment.id))
        XCTAssertFalse(reloadedStore.accounts.first(where: { $0.id == account.id })?.equipment.contains(where: { $0.id == equipment.id }) ?? true)
    }

    func testEquipmentCSVImportMapsDeviceTypeAndAddressColumns() throws {
        let csv = """
        DEVICE,TYPE,ADDRESS
        NFS2-3030,Fire Alarm Control Panel (FACP),01
        HPF-PS10,Booster Panel,02
        Missing Type,,03
        """

        let result = try FireVaultEquipmentCSVImporter.records(
            from: try XCTUnwrap(csv.data(using: .utf8))
        )

        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.records[0].device, "NFS2-3030")
        XCTAssertEqual(result.records[0].type, "Fire Alarm Control Panel (FACP)")
        XCTAssertEqual(result.records[0].address, "01")
        XCTAssertEqual(result.records[1].type, "Booster Panel")
    }

    func testAccountLocationLifecycleValidatesCoordinatesAndPreservesOtherData() throws {
        let suite = "FireVaultTests.LocationLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "firevault.native.demo-mode.v1")
        let store = FireVaultStore(defaults: defaults)
        let account = store.addAccount()
        let accountIndex = try XCTUnwrap(store.accounts.firstIndex(where: { $0.id == account.id }))
        store.accounts[accountIndex].favorite = true
        store.accounts[accountIndex].equipment = [
            .init(id: "equipment-1", title: "FACP", subtitle: "Lobby", status: "Active")
        ]

        XCTAssertNil(
            store.addLocation(
                to: account.id,
                label: "Invalid pin",
                latitude: 43.615,
                longitude: nil
            )
        )

        let location = try XCTUnwrap(
            store.addLocation(
                to: account.id,
                label: "  Main Entrance  ",
                subtitle: "  South doors  ",
                type: "  Entrance  ",
                plusCode: "  85m5jr93+4c  ",
                latitude: 43.6177,
                longitude: -116.1968
            )
        )
        XCTAssertEqual(location.label, "Main Entrance")
        XCTAssertEqual(location.plusCode, "85M5JR93+4C")

        XCTAssertTrue(
            store.updateLocation(
                accountID: account.id,
                locationID: location.id,
                label: "  Fire Panel  ",
                subtitle: "  Electrical room  ",
                type: "  Panel  ",
                plusCode: "  85m5jr94+5d  ",
                latitude: 43.618,
                longitude: -116.197
            )
        )

        let updatedAccount = try XCTUnwrap(store.accounts.first(where: { $0.id == account.id }))
        let updatedLocation = try XCTUnwrap(updatedAccount.locations.first(where: { $0.id == location.id }))
        XCTAssertEqual(updatedLocation.label, "Fire Panel")
        XCTAssertEqual(updatedLocation.subtitle, "Electrical room")
        XCTAssertEqual(updatedLocation.type, "Panel")
        XCTAssertEqual(updatedLocation.plusCode, "85M5JR94+5D")
        XCTAssertEqual(updatedLocation.latitude, 43.618)
        XCTAssertEqual(updatedLocation.longitude, -116.197)
        XCTAssertTrue(updatedAccount.favorite)
        XCTAssertEqual(updatedAccount.equipment.map(\.id), ["equipment-1"])

        let reloadedStore = FireVaultStore(defaults: defaults)
        let persisted = try XCTUnwrap(reloadedStore.accounts.first(where: { $0.id == account.id }))
        XCTAssertEqual(persisted.locations.first(where: { $0.id == location.id }), updatedLocation)
        XCTAssertTrue(persisted.favorite)
        XCTAssertEqual(persisted.equipment.map(\.id), ["equipment-1"])

        XCTAssertTrue(reloadedStore.deleteLocation(accountID: account.id, locationID: location.id))
        XCTAssertFalse(reloadedStore.accounts.first(where: { $0.id == account.id })?.locations.contains(where: { $0.id == location.id }) ?? true)
    }

    func testLocationCSVImportMapsFieldLocationColumns() throws {
        let csv = """
        NAME,TYPE,DETAILS,PLUSCODE,LATITUDE,LONGITUDE,COLOR
        Main Entrance,Entrance,South doors,85M5JR93+4C,43.617700,-116.196800,Blue
        Riser Room,Riser,Mechanical room,,43.618000,-116.197000,Red
        Bad Coordinates,Panel,Missing longitude,,43.619000,,Green
        """

        let result = try FireVaultLocationCSVImporter.records(
            from: try XCTUnwrap(csv.data(using: .utf8))
        )

        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(result.records[0].name, "Main Entrance")
        XCTAssertEqual(result.records[0].type, "Entrance")
        XCTAssertEqual(result.records[0].details, "South doors")
        XCTAssertEqual(result.records[0].plusCode, "85M5JR93+4C")
        XCTAssertEqual(result.records[0].latitude, 43.617700)
        XCTAssertEqual(result.records[0].longitude, -116.196800)
        XCTAssertEqual(result.records[0].color, "Blue")
        XCTAssertEqual(result.records[1].name, "Riser Room")
        XCTAssertEqual(result.records[1].color, "Red")
    }

    func testTripLogOccupiesCenterNavigationPosition() {
        XCTAssertEqual(FireVaultShellTab.allCases.count, 5)
        XCTAssertEqual(FireVaultShellTab.allCases[2], .trip)
        XCTAssertEqual(FireVaultShellTab.trip.title, "Trip Log")
        XCTAssertEqual(FireVaultShellTab.trip.symbol, "truck.box.fill")
    }

    func testTripLogTelemetryCountsOnlyWaypointsFromTheLastMinute() {
        let now = Date(timeIntervalSince1970: 10_000)
        let points = [
            FireVaultBreadcrumbPoint(
                timestamp: now.addingTimeInterval(-10),
                latitude: 42.85,
                longitude: -106.32,
                horizontalAccuracy: 12
            ),
            FireVaultBreadcrumbPoint(
                timestamp: now.addingTimeInterval(-59),
                latitude: 42.86,
                longitude: -106.31,
                horizontalAccuracy: 12
            ),
            FireVaultBreadcrumbPoint(
                timestamp: now.addingTimeInterval(-61),
                latitude: 42.87,
                longitude: -106.30,
                horizontalAccuracy: 12
            ),
            FireVaultBreadcrumbPoint(
                timestamp: now.addingTimeInterval(1),
                latitude: 42.88,
                longitude: -106.29,
                horizontalAccuracy: 12
            )
        ]
        let day = FireVaultBreadcrumbDay(startedAt: now.addingTimeInterval(-600), points: points)

        XCTAssertEqual(
            FireVaultTripLogTelemetry.recentWaypointCount(in: day, endingAt: now),
            2
        )
    }

    func testCaptureQuickActionIsConsumedOnlyOnce() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)

        store.requestCapture(.scan)

        XCTAssertEqual(store.consumeCaptureQuickAction(), .scan)
        XCTAssertNil(store.consumeCaptureQuickAction())
    }

    func testSettingsItemAccessibilityLabelIncludesUsefulContext() {
        let item = FireVaultNativeSettingItem(
            id: "photo-overlay",
            title: "Photo Overlay",
            subtitle: "Configure field photo labels",
            symbol: "camera.viewfinder",
            status: "Enabled"
        )

        XCTAssertEqual(item.accessibilityLabel, "Photo Overlay, Configure field photo labels")
    }

    func testSettingsItemAccessibilityLabelOmitsEmptySubtitle() {
        let item = FireVaultNativeSettingItem(
            id: "privacy",
            title: "Privacy",
            subtitle: "",
            symbol: "hand.raised",
            status: ""
        )

        XCTAssertEqual(item.accessibilityLabel, "Privacy")
    }

    func testVersionInfoReadsBundleValues() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "com.apple.Foundation"))
        let info = FireVaultVersionInfo(bundle: bundle)

        XCTAssertFalse(info.version.isEmpty)
        XCTAssertFalse(info.build.isEmpty)
        XCTAssertTrue(info.displayText.hasPrefix("Version "))
    }

    func testAboutSettingsStatusUsesInstalledVersion() {
        let about = FireVaultNativeSettingItem(
            id: "about",
            title: "About FireVault",
            subtitle: "Application information",
            symbol: "info.circle",
            status: "Version 1.03.30"
        )

        XCTAssertEqual(about.displayStatus(nativeVersion: "1.08.05"), "Version 1.08.05")
    }

    func testLegacyReportPreferencesGainSafeAutomationDefaults() throws {
        let legacy = """
        {
          "title": "Existing Report",
          "format": "compact",
          "includeTechnician": false,
          "includeTasks": true,
          "includeDeficiencies": false
        }
        """
        let preferences = try JSONDecoder().decode(
            FireVaultReportPreferences.self,
            from: try XCTUnwrap(legacy.data(using: .utf8))
        )

        XCTAssertEqual(preferences.title, "Existing Report")
        XCTAssertEqual(preferences.format, "compact")
        XCTAssertFalse(preferences.dailyEmailEnabled)
        XCTAssertFalse(preferences.weeklyEmailEnabled)
        XCTAssertEqual(preferences.dailyEmailHour, 18)
        XCTAssertEqual(preferences.weeklyEmailWeekday, 6)
        XCTAssertFalse(preferences.reportTimeZone.isEmpty)
    }

    func testReportAutomationScheduleNormalizesInvalidValues() {
        var preferences = FireVaultReportPreferences()
        preferences.dailyEmailHour = 29
        preferences.dailyEmailMinute = -4
        preferences.weeklyEmailWeekday = 12
        preferences.weeklyEmailHour = -2
        preferences.weeklyEmailMinute = 90
        preferences.reportTimeZone = "Not/A-Time-Zone"

        let normalized = preferences.normalized

        XCTAssertEqual(normalized.dailyEmailHour, 23)
        XCTAssertEqual(normalized.dailyEmailMinute, 0)
        XCTAssertEqual(normalized.weeklyEmailWeekday, 7)
        XCTAssertEqual(normalized.weeklyEmailHour, 0)
        XCTAssertEqual(normalized.weeklyEmailMinute, 59)
        XCTAssertNotNil(TimeZone(identifier: normalized.reportTimeZone))
    }

    func testNearbyListProvidesRunwayForFinalAccountToReachTop() {
        XCTAssertEqual(FireVaultNearbyListLayout.bottomRunway(for: 420), 348)
        XCTAssertEqual(FireVaultNearbyListLayout.bottomRunway(for: 60), 0)
    }

    func testBreadcrumbRulesRejectPoorAccuracyAndDuplicatePoints() {
        let timestamp = Date()
        let first = CLLocation(
            coordinate: .init(latitude: 43.615, longitude: -116.202),
            altitude: 0,
            horizontalAccuracy: 12,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
        let inaccurate = CLLocation(
            coordinate: .init(latitude: 43.616, longitude: -116.202),
            altitude: 0,
            horizontalAccuracy: 250,
            verticalAccuracy: -1,
            timestamp: timestamp
        )
        let duplicate = CLLocation(
            coordinate: first.coordinate,
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: -1,
            timestamp: timestamp.addingTimeInterval(5)
        )

        XCTAssertTrue(FireVaultBreadcrumbRules.accepts(first, after: nil))
        XCTAssertFalse(FireVaultBreadcrumbRules.accepts(inaccurate, after: first))
        XCTAssertFalse(FireVaultBreadcrumbRules.accepts(duplicate, after: first))
    }

    func testBreadcrumbRulesMatchNearestAccountInsideRadius() throws {
        let near = FireVaultWorkspaceAccount(
            id: "near",
            name: "Nearest Account",
            address: "100 Main Street",
            category: "Commercial",
            accountId: "A-1",
            phone: "",
            favorite: false,
            latitude: 43.615,
            longitude: -116.202,
            tags: [],
            notes: [],
            documents: [],
            equipment: [],
            locations: [],
            recent: []
        )
        var far = near
        far.id = "far"
        far.name = "Far Account"
        far.latitude = 43.7

        let match = FireVaultBreadcrumbRules.closestAccount(
            to: .init(latitude: 43.6151, longitude: -116.2021),
            accounts: [far, near]
        )

        XCTAssertEqual(try XCTUnwrap(match).id, "near")
    }

    func testBreadcrumbRulesMatchSavedArrivalPointWhenSiteCoordinateIsMissing() throws {
        let account = FireVaultWorkspaceAccount(
            id: "arrival-only",
            name: "Mapped Arrival Account",
            address: "100 Main Street",
            category: "Commercial",
            accountId: "A-2",
            phone: "",
            favorite: false,
            latitude: nil,
            longitude: nil,
            tags: [],
            notes: [],
            documents: [],
            equipment: [],
            locations: [
                .init(
                    id: "parking",
                    label: "Technician Parking",
                    subtitle: "South lot",
                    type: "Parking",
                    plusCode: "",
                    latitude: 43.615,
                    longitude: -116.202
                )
            ],
            recent: []
        )

        let match = FireVaultBreadcrumbRules.closestAccount(
            to: .init(latitude: 43.6151, longitude: -116.2021),
            accounts: [account]
        )

        XCTAssertEqual(try XCTUnwrap(match).id, account.id)
    }

    func testBreadcrumbRepresentativeCoordinateResistsOneGPSOutlier() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            testLocation(latitude: 43.61500, longitude: -116.20200, timestamp: timestamp),
            testLocation(latitude: 43.61502, longitude: -116.20202, timestamp: timestamp.addingTimeInterval(30)),
            testLocation(latitude: 43.62500, longitude: -116.21200, timestamp: timestamp.addingTimeInterval(60))
        ]

        let coordinate = try XCTUnwrap(
            FireVaultBreadcrumbRules.representativeCoordinate(for: samples)
        )

        XCTAssertEqual(coordinate.latitude, 43.61502, accuracy: 0.000_001)
        XCTAssertEqual(coordinate.longitude, -116.20202, accuracy: 0.000_001)
    }

    func testBreadcrumbStopCandidateAcceptsSparseBackgroundSamples() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = testLocation(
            latitude: 43.615,
            longitude: -116.202,
            timestamp: timestamp
        )
        let knownAccountSample = testLocation(
            latitude: 43.61502,
            longitude: -116.20202,
            timestamp: timestamp.addingTimeInterval(3 * 60)
        )
        let unknownTooSoon = testLocation(
            latitude: 43.61501,
            longitude: -116.20201,
            timestamp: timestamp.addingTimeInterval(4 * 60 + 59)
        )
        let unknownQualified = testLocation(
            latitude: 43.61501,
            longitude: -116.20201,
            timestamp: timestamp.addingTimeInterval(5 * 60)
        )

        XCTAssertTrue(
            FireVaultBreadcrumbRules.confirmsStopCandidate(
                locations: [first, knownAccountSample],
                isKnownAccount: true,
                minimumUnknownStopMinutes: 5
            )
        )
        XCTAssertFalse(
            FireVaultBreadcrumbRules.confirmsStopCandidate(
                locations: [first, unknownTooSoon],
                isKnownAccount: false,
                minimumUnknownStopMinutes: 5
            )
        )
        XCTAssertTrue(
            FireVaultBreadcrumbRules.confirmsStopCandidate(
                locations: [first, unknownQualified],
                isKnownAccount: false,
                minimumUnknownStopMinutes: 5
            )
        )
        XCTAssertGreaterThan(
            FireVaultBreadcrumbRules.maximumCandidateGap,
            FireVaultBreadcrumbRules.minimumUnrecognizedStopDuration
        )
    }

    func testBreadcrumbStopDwellRecoversVisitWhenGPSIsQuietUntilDeparture() {
        let arrival = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(
            FireVaultBreadcrumbRules.confirmsStopDwell(
                arrival: arrival,
                departure: arrival.addingTimeInterval(3 * 60),
                isKnownAccount: true,
                minimumUnknownStopMinutes: 5
            )
        )
        XCTAssertFalse(
            FireVaultBreadcrumbRules.confirmsStopDwell(
                arrival: arrival,
                departure: arrival.addingTimeInterval(4 * 60 + 59),
                isKnownAccount: false,
                minimumUnknownStopMinutes: 5
            )
        )
        XCTAssertTrue(
            FireVaultBreadcrumbRules.confirmsStopDwell(
                arrival: arrival,
                departure: arrival.addingTimeInterval(5 * 60),
                isKnownAccount: false,
                minimumUnknownStopMinutes: 5
            )
        )
    }

    func testBreadcrumbStationaryEvidenceOverridesFrozenDrivingSpeed() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = testLocation(latitude: 43.615, longitude: -116.202, timestamp: timestamp, speed: 15)
        let barelyMoved = testLocation(
            latitude: 43.61501,
            longitude: -116.202,
            timestamp: timestamp.addingTimeInterval(30),
            speed: 15
        )

        XCTAssertTrue(FireVaultBreadcrumbRules.isStationary(barelyMoved, comparedTo: first))
    }

    func testBreadcrumbMovingCoordinatesDoNotOverrideDrivingSpeed() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let first = testLocation(latitude: 43.615, longitude: -116.202, timestamp: timestamp, speed: 15)
        let moved = testLocation(
            latitude: 43.620,
            longitude: -116.202,
            timestamp: timestamp.addingTimeInterval(30),
            speed: 15
        )

        XCTAssertFalse(FireVaultBreadcrumbRules.isStationary(moved, comparedTo: first))
    }

    func testCarPlaySpeedFallsToZeroWhenMovementEvidenceIsStale() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let location = testLocation(
            latitude: 43.615,
            longitude: -116.202,
            timestamp: now,
            speed: 15
        )
        let speed = try XCTUnwrap(
            FireVaultBreadcrumbRules.resolvedLiveSpeed(
                location: location,
                lastMeaningfulMovementAt: now.addingTimeInterval(-9),
                now: now
            )
        )

        XCTAssertEqual(speed, 0)
    }

    func testBreadcrumbDepartureRequiresConsistentEvidence() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let origin = CLLocationCoordinate2D(latitude: 43.615, longitude: -116.202)
        let firstJump = testLocation(
            latitude: 43.6162,
            longitude: -116.202,
            timestamp: timestamp
        )
        let consistentSecond = testLocation(
            latitude: 43.61625,
            longitude: -116.20202,
            timestamp: timestamp.addingTimeInterval(30)
        )
        let scatteredSecond = testLocation(
            latitude: 43.614,
            longitude: -116.204,
            timestamp: timestamp.addingTimeInterval(30)
        )

        XCTAssertFalse(
            FireVaultBreadcrumbRules.confirmsDeparture(
                from: origin,
                with: [firstJump]
            )
        )
        XCTAssertTrue(
            FireVaultBreadcrumbRules.confirmsDeparture(
                from: origin,
                with: [firstJump, consistentSecond]
            )
        )
        XCTAssertFalse(
            FireVaultBreadcrumbRules.confirmsDeparture(
                from: origin,
                with: [firstJump, scatteredSecond]
            )
        )
    }

    func testBreadcrumbDuplicateMergingPreservesKnownAccountIdentity() {
        let arrival = Date(timeIntervalSince1970: 1_700_000_000)
        let previous = FireVaultBreadcrumbStop(
            arrival: arrival,
            departure: arrival.addingTimeInterval(10 * 60),
            latitude: 43.615,
            longitude: -116.202,
            accountID: "account-1",
            accountName: "Central Library"
        )
        let nearbyCoordinate = CLLocationCoordinate2D(latitude: 43.6152, longitude: -116.2021)

        XCTAssertTrue(
            FireVaultBreadcrumbRules.shouldMergeStop(
                previous: previous,
                arrivingAt: arrival.addingTimeInterval(18 * 60),
                coordinate: nearbyCoordinate,
                accountID: nil
            )
        )
        XCTAssertFalse(
            FireVaultBreadcrumbRules.shouldMergeStop(
                previous: previous,
                arrivingAt: arrival.addingTimeInterval(18 * 60),
                coordinate: nearbyCoordinate,
                accountID: "different-account"
            )
        )
    }

    func testUnrecognizedStopReviewStateIsBackwardCompatible() {
        var stop = FireVaultBreadcrumbStop(
            arrival: Date(timeIntervalSince1970: 1_700_000_000),
            latitude: 43.615,
            longitude: -116.202
        )

        XCTAssertTrue(stop.needsReview)
        stop.rename("Warehouse Loading Dock")
        XCTAssertFalse(stop.needsReview)
        stop.rename("")
        stop.markReviewed(at: Date(timeIntervalSince1970: 1_700_000_600))
        XCTAssertFalse(stop.needsReview)
    }

    func testBreadcrumbDayCalculatesRecordedDistance() {
        let start = Date()
        let points = [
            FireVaultBreadcrumbPoint(
                timestamp: start,
                latitude: 43.615,
                longitude: -116.202,
                horizontalAccuracy: 10
            ),
            FireVaultBreadcrumbPoint(
                timestamp: start.addingTimeInterval(60),
                latitude: 43.624,
                longitude: -116.202,
                horizontalAccuracy: 10
            )
        ]
        let day = FireVaultBreadcrumbDay(startedAt: start, points: points)

        XCTAssertGreaterThan(day.totalDistanceMeters, 900)
        XCTAssertLessThan(day.totalDistanceMeters, 1_100)
    }

    func testBreadcrumbVisitTimesNeverProduceNegativeDuration() {
        let arrival = Date()
        let earlierDeparture = arrival.addingTimeInterval(-600)
        let normalized = FireVaultBreadcrumbRules.normalizedVisit(
            arrival: arrival,
            departure: earlierDeparture
        )

        XCTAssertEqual(normalized.arrival, arrival)
        XCTAssertEqual(normalized.departure, arrival)
    }

    func testCompletedWorkdayUsesEndTimeForOpenStopDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(2 * 60 * 60)
        let stop = FireVaultBreadcrumbStop(
            arrival: start.addingTimeInterval(30 * 60),
            latitude: 43.615,
            longitude: -116.202
        )
        let day = FireVaultBreadcrumbDay(
            startedAt: start,
            endedAt: end,
            stops: [stop]
        )
        let report = FireVaultBreadcrumbReport(
            day: day,
            technicianName: "Technician",
            companyName: "FireVault",
            includeCoordinates: true,
            generatedAt: end.addingTimeInterval(7 * 24 * 60 * 60)
        )

        XCTAssertEqual(report.visits.first?.duration, 90 * 60)
        XCTAssertEqual(report.visits.first?.departure, end)
    }

    func testMissingStopDeparturesUseNextArrivalBeforeWorkdayEnd() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let first = FireVaultBreadcrumbStop(
            arrival: start.addingTimeInterval(30 * 60),
            latitude: 43.615,
            longitude: -116.202
        )
        let second = FireVaultBreadcrumbStop(
            arrival: start.addingTimeInterval(75 * 60),
            latitude: 43.617,
            longitude: -116.204
        )
        let end = start.addingTimeInterval(120 * 60)
        let day = FireVaultBreadcrumbDay(
            startedAt: start,
            endedAt: end,
            stops: [first, second]
        )
        let report = FireVaultBreadcrumbReport(
            day: day,
            technicianName: "Technician",
            companyName: "FireVault",
            includeCoordinates: false,
            generatedAt: end.addingTimeInterval(86_400)
        )

        XCTAssertEqual(day.stopDuration(for: first), 45 * 60)
        XCTAssertEqual(day.stopDuration(for: second), 45 * 60)
        XCTAssertEqual(try XCTUnwrap(report.visits.first).departure, second.arrival)
        XCTAssertEqual(try XCTUnwrap(report.visits.first).duration, 45 * 60)
    }

    func testTripLogStopCanBeRetitledWithoutBecomingAnAccountVisit() throws {
        var stop = FireVaultBreadcrumbStop(
            arrival: Date(timeIntervalSince1970: 1_700_000_000),
            latitude: 43.615,
            longitude: -116.202
        )
        stop.rename("Warehouse Loading Dock")
        let report = FireVaultBreadcrumbReport(
            day: .init(
                startedAt: stop.arrival,
                endedAt: stop.arrival.addingTimeInterval(900),
                stops: [stop]
            ),
            technicianName: "",
            companyName: "",
            includeCoordinates: false
        )

        XCTAssertEqual(stop.title, "Warehouse Loading Dock")
        XCTAssertEqual(try XCTUnwrap(report.visits.first).title, "Warehouse Loading Dock")
        XCTAssertEqual(try XCTUnwrap(report.visits.first).classification, .unassigned)
    }

    func testTripLogStopCanCreateMappedAccount() throws {
        let suite = "FireVaultTests.TripLogAccount.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let stop = FireVaultBreadcrumbStop(
            arrival: Date(timeIntervalSince1970: 1_700_000_000),
            latitude: 43.615,
            longitude: -116.202
        )

        let account = store.addAccount(from: stop, name: "Warehouse Loading Dock")

        XCTAssertEqual(account.name, "Warehouse Loading Dock")
        XCTAssertEqual(account.latitude, stop.latitude)
        XCTAssertEqual(account.longitude, stop.longitude)
        XCTAssertTrue(store.accounts.contains(where: { $0.id == account.id }))
    }

    func testRedesignedDailyPDFKeepsSixStandardStopsOnOnePage() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let stops = (0..<6).map { index in
            let arrival = start.addingTimeInterval(Double(index * 35 * 60))
            return FireVaultBreadcrumbStop(
                arrival: arrival,
                departure: arrival.addingTimeInterval(Double((index + 4) * 60)),
                latitude: 43.615 + Double(index) * 0.002,
                longitude: -116.202 - Double(index) * 0.002,
                accountID: "A-\(index + 1)",
                accountName: "Account \(index + 1)",
                accountAddress: "\(index + 1) Main Street"
            )
        }
        let day = FireVaultBreadcrumbDay(
            startedAt: start,
            endedAt: start.addingTimeInterval(5 * 60 * 60),
            stops: stops
        )
        let report = FireVaultBreadcrumbReport(
            day: day,
            technicianName: "David Bannerman",
            companyName: "Western States Fire Protection",
            includeCoordinates: true
        )
        let data = FireVaultTripLogPDFRenderer.daily(
            report: report,
            detail: .detailed,
            mapImage: nil
        )
        let document = try XCTUnwrap(
            CGPDFDocument(CGDataProvider(data: data as CFData)!)
        )

        XCTAssertEqual(document.numberOfPages, 1)
        let images = FireVaultTripLogImageRenderer.images(from: data)
        let image = try XCTUnwrap(images.first)
        XCTAssertEqual(images.count, 1)
        XCTAssertGreaterThan(image.size.width, 600)
        XCTAssertGreaterThan(image.size.height, 790)

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "FireVault-Redesigned-Daily-Trip-Log.pdf"
        attachment.lifetime = .keepAlways
        add(attachment)
        let imageAttachment = XCTAttachment(image: image)
        imageAttachment.name = "FireVault-Inline-Email-JPG"
        imageAttachment.lifetime = .keepAlways
        add(imageAttachment)
    }

    func testBreadcrumbPermissionExplainsContinuousBackgroundRecording() {
        let permission = FireVaultBreadcrumbPermissionState(
            authorizationStatus: .authorizedWhenInUse,
            accuracyAuthorization: .fullAccuracy
        )

        XCTAssertTrue(permission.isAuthorized)
        XCTAssertFalse(permission.requiresSettings)
        XCTAssertEqual(permission.title, "Background Tracking Ready")
        XCTAssertTrue(permission.detail.contains("background"))
        XCTAssertTrue(permission.detail.contains("iOS location indicator"))
    }

    func testBreadcrumbPermissionRecommendsPreciseLocation() {
        let permission = FireVaultBreadcrumbPermissionState(
            authorizationStatus: .authorizedWhenInUse,
            accuracyAuthorization: .reducedAccuracy
        )

        XCTAssertTrue(permission.isAuthorized)
        XCTAssertTrue(permission.requiresSettings)
        XCTAssertEqual(permission.title, "Approximate Location")
        XCTAssertTrue(permission.detail.contains("Precise Location"))
    }

    func testBreadcrumbPermissionDirectsDeniedUserToSettings() {
        let permission = FireVaultBreadcrumbPermissionState(
            authorizationStatus: .denied,
            accuracyAuthorization: .reducedAccuracy
        )

        XCTAssertFalse(permission.isAuthorized)
        XCTAssertTrue(permission.requiresSettings)
        XCTAssertEqual(permission.title, "Location Access Off")
        XCTAssertTrue(permission.detail.contains("iOS Settings"))
    }

    func testBreadcrumbStopCanBeAssignedAndMarkedPersonal() {
        let account = FireVaultWorkspaceAccount(
            id: "account-1",
            name: "Central Library",
            address: "100 Main Street",
            category: "Commercial",
            accountId: "FV-42",
            phone: "",
            favorite: false,
            latitude: 43.615,
            longitude: -116.202,
            tags: [],
            notes: [],
            documents: [],
            equipment: [],
            locations: [],
            recent: []
        )
        var stop = FireVaultBreadcrumbStop(
            arrival: Date(),
            latitude: 43.615,
            longitude: -116.202
        )

        stop.assign(to: account)
        XCTAssertEqual(stop.accountID, account.id)
        XCTAssertEqual(stop.title, account.name)

        stop.markPersonal(true)
        XCTAssertTrue(stop.isPersonalStop)
        XCTAssertNil(stop.accountID)
        XCTAssertEqual(stop.title, "Personal Stop")
    }

    func testBreadcrumbStopTrimsVisitNote() {
        let arrival = Date()
        var stop = FireVaultBreadcrumbStop(
            arrival: arrival,
            latitude: 43.615,
            longitude: -116.202
        )

        stop.updateVisit(
            arrival: arrival,
            departure: arrival.addingTimeInterval(300),
            technicianNote: "  Follow up with site contact.  "
        )

        XCTAssertEqual(stop.technicianNote, "Follow up with site contact.")
        XCTAssertEqual(stop.duration, 300, accuracy: 0.01)
    }

    func testBreadcrumbStopDecodesArchiveCreatedBeforeEditableFields() throws {
        let legacyJSON = """
        {
          "id": "B71AB6AE-F22E-46EC-97D7-43383A5B7132",
          "arrival": "2026-07-22T15:30:00Z",
          "departure": "2026-07-22T16:00:00Z",
          "latitude": 43.615,
          "longitude": -116.202,
          "accountID": "account-1",
          "accountName": "Central Library",
          "accountAddress": "100 Main Street"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let stop = try decoder.decode(
            FireVaultBreadcrumbStop.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(stop.accountName, "Central Library")
        XCTAssertNil(stop.technicianNote)
        XCTAssertFalse(stop.isPersonalStop)
    }

    func testBreadcrumbReportRedactsEveryPersonalStopDetail() throws {
        let start = Date(timeIntervalSince1970: 1_785_000_000)
        let accountStop = FireVaultBreadcrumbStop(
            arrival: start.addingTimeInterval(900),
            departure: start.addingTimeInterval(2_700),
            latitude: 43.615,
            longitude: -116.202,
            accountID: "FV-42",
            accountName: "Central Library",
            accountAddress: "100 Main Street",
            technicianNote: "Replaced detector.",
            isPersonal: false
        )
        let personalStop = FireVaultBreadcrumbStop(
            arrival: start.addingTimeInterval(3_600),
            departure: start.addingTimeInterval(4_200),
            latitude: 44.999,
            longitude: -115.999,
            accountID: "PRIVATE-ID",
            accountName: "Private Location Name",
            accountAddress: "Private Address",
            technicianNote: "Secret personal note",
            isPersonal: true
        )
        let day = FireVaultBreadcrumbDay(
            startedAt: start,
            endedAt: start.addingTimeInterval(7_200),
            stops: [accountStop, personalStop]
        )

        let report = FireVaultBreadcrumbReport(
            day: day,
            technicianName: "Taylor",
            companyName: "Bannerman",
            includeCoordinates: true,
            generatedAt: start.addingTimeInterval(7_200)
        )
        let redacted = try XCTUnwrap(
            report.visits.first(where: { $0.classification == .personal })
        )
        let csv = try XCTUnwrap(String(data: report.csvData, encoding: .utf8))

        XCTAssertEqual(report.accountVisitCount, 1)
        XCTAssertEqual(report.personalStopCount, 1)
        XCTAssertEqual(redacted.title, "Personal Stop")
        XCTAssertTrue(redacted.accountName.isEmpty)
        XCTAssertTrue(redacted.accountAddress.isEmpty)
        XCTAssertTrue(redacted.accountID.isEmpty)
        XCTAssertTrue(redacted.technicianNote.isEmpty)
        XCTAssertNil(redacted.latitude)
        XCTAssertNil(redacted.longitude)
        XCTAssertFalse(report.plainText.contains("Private Location Name"))
        XCTAssertFalse(report.plainText.contains("Secret personal note"))
        XCTAssertFalse(csv.contains("Private Address"))
        XCTAssertFalse(csv.contains("44.999"))
    }

    func testBreadcrumbReportCSVQuotesTechnicianContent() throws {
        let start = Date(timeIntervalSince1970: 1_785_000_000)
        let stop = FireVaultBreadcrumbStop(
            arrival: start,
            departure: start.addingTimeInterval(600),
            latitude: 43.615,
            longitude: -116.202,
            accountID: "A-1",
            accountName: "Acme, Inc.",
            accountAddress: "100 Main Street",
            technicianNote: "Panel says \"East\"",
            isPersonal: false
        )
        let report = FireVaultBreadcrumbReport(
            day: .init(
                startedAt: start,
                endedAt: start.addingTimeInterval(600),
                stops: [stop]
            ),
            technicianName: "Taylor",
            companyName: "",
            includeCoordinates: false,
            generatedAt: start.addingTimeInterval(600)
        )
        let csv = try XCTUnwrap(String(data: report.csvData, encoding: .utf8))

        XCTAssertTrue(csv.contains("\"Acme, Inc.\""))
        XCTAssertTrue(csv.contains("\"Panel says \"\"East\"\"\""))
        XCTAssertFalse(csv.contains("43.615000"))
    }

    func testBreadcrumbReportProducesValidPDFData() {
        let start = Date(timeIntervalSince1970: 1_785_000_000)
        let report = FireVaultBreadcrumbReport(
            day: .init(
                startedAt: start,
                endedAt: start.addingTimeInterval(3_600)
            ),
            technicianName: "Taylor",
            companyName: "Bannerman",
            includeCoordinates: false,
            generatedAt: start.addingTimeInterval(3_600)
        )

        XCTAssertGreaterThan(report.pdfData.count, 500)
        XCTAssertEqual(
            String(data: report.pdfData.prefix(4), encoding: .ascii),
            "%PDF"
        )
    }

    func testNativeGPSPreferencesClampRadiusToSupportedRange() {
        var low = FireVaultGPSPreferences()
        low.nearbyRadiusMiles = 0.1
        XCTAssertEqual(low.normalized.nearbyRadiusMiles, 0.25)

        var high = FireVaultGPSPreferences()
        high.nearbyRadiusMiles = 80
        XCTAssertEqual(high.normalized.nearbyRadiusMiles, 25)
    }

    func testNativeGPSRadiusWheelUsesQuarterMilesThroughOneThenWholeMiles() {
        XCTAssertEqual(FireVaultGPSPreferences.radiusOptions.first, 0.25)
        XCTAssertEqual(FireVaultGPSPreferences.radiusOptions.last, 25)
        XCTAssertEqual(FireVaultGPSPreferences.radiusOptions.count, 28)
        XCTAssertEqual(
            Array(FireVaultGPSPreferences.radiusOptions.prefix(4)),
            [0.25, 0.5, 0.75, 1]
        )
        XCTAssertTrue(FireVaultGPSPreferences.radiusOptions.contains(2))
        XCTAssertFalse(FireVaultGPSPreferences.radiusOptions.contains(3.5))
    }

    func testPhotoOverlayPreferencesNormalizeUnsupportedValues() {
        var preferences = FireVaultOverlayPreferences()
        preferences.alignment = "floating"
        preferences.fontSize = "enormous"
        preferences.backgroundStyle = "glass"
        preferences.accentColor = "purple"
        preferences.opacity = 5

        let normalized = preferences.normalized

        XCTAssertEqual(normalized.alignment, "bottom")
        XCTAssertEqual(normalized.fontSize, "medium")
        XCTAssertEqual(normalized.backgroundStyle, "frosted")
        XCTAssertEqual(normalized.accentColor, "blue")
        XCTAssertEqual(normalized.opacity, 35)
        XCTAssertFalse(normalized.showLocationQRCode)
    }

    func testPhotoOverlayPreviewGeometryUsesSameDesignCoordinatesOnIPhoneAndIPad() {
        let designPoint = CGPoint(x: 344, y: 120)
        let designTranslation = CGSize(width: 43, height: 57.333)

        for previewSize in [
            CGSize(width: 350, height: 350 * 4 / 3),
            CGSize(width: 700, height: 700 * 4 / 3)
        ] {
            let geometry = FireVaultOverlayPreviewGeometry(previewSize: previewSize)
            let previewPoint = CGPoint(
                x: geometry.designOrigin.x + designPoint.x * geometry.scale,
                y: geometry.designOrigin.y + designPoint.y * geometry.scale
            )
            let previewTranslation = CGSize(
                width: designTranslation.width * geometry.scale,
                height: designTranslation.height * geometry.scale
            )

            XCTAssertEqual(geometry.designPoint(from: previewPoint).x, designPoint.x, accuracy: 0.001)
            XCTAssertEqual(geometry.designPoint(from: previewPoint).y, designPoint.y, accuracy: 0.001)
            XCTAssertEqual(
                geometry.designTranslation(from: previewTranslation).width,
                designTranslation.width,
                accuracy: 0.001
            )
            XCTAssertEqual(
                geometry.designTranslation(from: previewTranslation).height,
                designTranslation.height,
                accuracy: 0.001
            )
        }
    }

    func testPhotoOverlayPreviewUsesNativeLandscapeCameraRatio() {
        let size = FireVaultOverlayPreviewGeometry.designSize

        XCTAssertEqual(size.width / size.height, 4.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(size.height, 430, accuracy: 0.000_001)
    }

    func testPhotoOverlayPlacementEditorUsesNativeLandscapeCameraRatio() {
        let size = FireVaultOverlayPlacementEditor.landscapeDesignSize

        XCTAssertEqual(size.width / size.height, 4.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(size.height, 430, accuracy: 0.000_001)
    }

    func testPhotoOverlayPanelExpandsForLongCustomerNameWithinCanvas() {
        let short = FireVaultOverlayPanelSizing.metrics(
            siteName: "City Hall",
            maximumFieldLength: 18,
            hasTechnician: true,
            canvasWidth: 573.333,
            scale: 1
        )
        let long = FireVaultOverlayPanelSizing.metrics(
            siteName: "North Riverside Fire and Life Safety Operations Center",
            maximumFieldLength: 54,
            hasTechnician: true,
            canvasWidth: 573.333,
            scale: 1
        )

        XCTAssertGreaterThan(long.panelWidth, short.panelWidth)
        XCTAssertLessThanOrEqual(long.panelWidth, 553.334)
        XCTAssertGreaterThan(long.informationWidth, short.informationWidth)
    }

    func testPhotoOverlayPreferencesPreserveRequiredAccountFields() {
        var preferences = FireVaultOverlayPreferences()
        preferences.fieldTemplate = "{technician}"

        let normalized = preferences.normalized

        XCTAssertTrue(normalized.fieldTemplate.contains("{site}"))
        XCTAssertTrue(normalized.fieldTemplate.contains("{address}"))
        XCTAssertTrue(normalized.fieldTemplate.contains("{accountID}"))
    }

    func testPhotoOverlayPreferencesDecodeSettingsSavedBeforeTemplates() throws {
        let legacyJSON = """
        {
          "alignment": "top",
          "fontSize": "large",
          "backgroundStyle": "card",
          "opacity": 70,
          "showLogo": false,
          "showTagline": true,
          "accentColor": "blue"
        }
        """

        let decoded = try JSONDecoder().decode(
            FireVaultOverlayPreferences.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(decoded.alignment, "top")
        XCTAssertEqual(decoded.tagline, "FIREVAULT FIELD DOCUMENTATION")
        XCTAssertFalse(decoded.showLocationQRCode)
        XCTAssertTrue(decoded.fieldTemplate.contains("{site}"))
    }

    func testPhotoOverlayLocationQRCodePayloadUsesAppleMapsCoordinate() {
        let payload = FireVaultLocationQRCode.payload(
            latitude: 43.6177,
            longitude: -116.1968,
            name: "Main Entrance"
        )

        XCTAssertTrue(payload.hasPrefix("https://maps.apple.com/"))
        XCTAssertTrue(payload.contains("ll=43.6177,-116.1968"))
        XCTAssertTrue(payload.contains("q=Main%20Entrance"))
    }

    func testPhotoOverlayQRCodeRendererCreatesImage() throws {
        let image = try XCTUnwrap(
            FireVaultQRCodeRenderer.image(from: "https://maps.apple.com/?ll=43.6177,-116.1968")
        )

        XCTAssertGreaterThan(image.size.width, 20)
        XCTAssertGreaterThan(image.size.height, 20)
    }

    func testPhotoOverlayFieldControlsKeepRequiredFieldsVisibleAndOrdered() {
        var preferences = FireVaultOverlayPreferences()
        preferences.fieldOrder = ["timestamp", "site", "timestamp", "address"]
        preferences.hiddenFields = ["site", "category", "technician"]

        let normalized = preferences.normalized

        XCTAssertEqual(normalized.fieldOrder.first, "timestamp")
        XCTAssertEqual(normalized.fieldOrder.filter { $0 == "timestamp" }.count, 1)
        XCTAssertFalse(normalized.hiddenFields.contains("site"))
        XCTAssertTrue(normalized.hiddenFields.contains("category"))
        XCTAssertTrue(normalized.hiddenFields.contains("technician"))
        XCTAssertEqual(Set(normalized.fieldOrder), Set(FireVaultOverlayField.allCases.map(\.rawValue)))
    }

    func testPhotoOverlayStructuredFieldsRespectOrderAndVisibility() {
        var preferences = FireVaultOverlayPreferences()
        preferences.fieldOrder = ["address", "site", "accountID", "category", "technician", "timestamp"]
        preferences.hiddenFields = ["category", "technician", "timestamp"]

        let lines = FireVaultOverlayTemplateFormatter.lines(
            preferences: preferences.normalized,
            siteName: "Central Library",
            address: "100 Main Street",
            accountID: "FV-42",
            category: "Commercial",
            technicianName: "Taylor",
            timestamp: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(lines, ["100 Main Street", "Central Library", "Account ID: FV-42"])
    }

    func testPhotoOverlayTemplateResolvesAccountFieldsAndOmitsMissingIDLine() {
        let timestamp = Date(timeIntervalSince1970: 0)
        let template = "{site}\n{address}\nAccount ID: {accountID}\n{technician}"

        let withID = FireVaultOverlayTemplateFormatter.lines(
            template: template,
            siteName: "Central Library",
            address: "100 Main Street",
            accountID: "FV-42",
            technicianName: "Taylor",
            timestamp: timestamp
        )
        XCTAssertEqual(
            withID,
            ["Central Library", "100 Main Street", "Account ID: FV-42", "Taylor"]
        )

        let withoutID = FireVaultOverlayTemplateFormatter.lines(
            template: template,
            siteName: "Central Library",
            address: "100 Main Street",
            accountID: "",
            technicianName: "Taylor",
            timestamp: timestamp
        )
        XCTAssertEqual(withoutID, ["Central Library", "100 Main Street", "Taylor"])
    }

    func testNativeGPSSettingsPersistAndReload() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FireVaultNativeSettingsStore(defaults: defaults)
        var preferences = FireVaultGPSPreferences()
        preferences.nearbyRadiusMiles = 4
        preferences.highAccuracy = false
        store.saveGPS(preferences)

        let reloaded = FireVaultNativeSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.gps.nearbyRadiusMiles, 4)
        XCTAssertFalse(reloaded.gps.highAccuracy)
    }

    func testNativeSettingsPersistTextFieldsAndReload() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FireVaultNativeSettingsStore(defaults: defaults)
        var preferences = store.preferences
        preferences.technician.name = "Taylor Technician"
        preferences.email.defaultTo = "service@example.com"
        preferences.storage.photoFolder = "FireVault/Native Photos"
        preferences.sync.organization = "Demo Company"
        preferences.webDAV.serverURL = "https://storage.example.com"
        store.save(preferences)

        let reloaded = FireVaultNativeSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferences.technician.name, "Taylor Technician")
        XCTAssertEqual(reloaded.preferences.email.defaultTo, "service@example.com")
        XCTAssertEqual(reloaded.preferences.storage.photoFolder, "FireVault/Native Photos")
        XCTAssertEqual(reloaded.preferences.sync.organization, "Demo Company")
        XCTAssertEqual(reloaded.preferences.webDAV.serverURL, "https://storage.example.com")
    }

    func testPreferredSettingsViewAndAdvancedOptionsPersist() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FireVaultNativeSettingsStore(defaults: defaults)
        var view = store.settingsView
        view.mode = .advanced
        view.advancedCollapseSections = true
        view.advancedShowDescriptions = false
        view.advancedShowStatus = false
        store.saveSettingsView(view)

        let reloaded = FireVaultNativeSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.settingsView.mode, .advanced)
        XCTAssertTrue(reloaded.settingsView.advancedCollapseSections)
        XCTAssertFalse(reloaded.settingsView.advancedShowDescriptions)
        XCTAssertFalse(reloaded.settingsView.advancedShowStatus)
    }

    func testAppearanceThemePersistsAndDefaultsToDark() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FireVaultNativeSettingsStore(defaults: defaults)
        XCTAssertEqual(store.appearance, .dark)
        store.saveAppearance(.light)

        let reloaded = FireVaultNativeSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, .light)
    }

    func testDeveloperSimpleTemplateFlagsPersistAndOnlyApplyToSimpleMode() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FireVaultNativeSettingsStore(defaults: defaults)
        store.setSimpleFeature("account.brief", enabled: false)
        XCTAssertFalse(store.isFeatureVisible("account.brief"))

        var view = store.settingsView
        view.mode = .advanced
        store.saveSettingsView(view)
        XCTAssertTrue(store.isFeatureVisible("account.brief"))

        let reloaded = FireVaultNativeSettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.developer.isEnabled("account.brief"))
        XCTAssertTrue(reloaded.isFeatureVisible("account.brief"))
    }

    func testDeveloperFeatureCatalogHasUniquePersistentIdentifiers() {
        let features = FireVaultDeveloperFeatureCatalog.features
        XCTAssertFalse(features.isEmpty)
        XCTAssertEqual(Set(features.map(\.id)).count, features.count)
        XCTAssertTrue(features.allSatisfy { !$0.page.isEmpty && !$0.title.isEmpty })
    }

    func testNativeCSVParserSupportsQuotedCommasAndEscapedQuotes() {
        let csv = "Account Name,Address,Note\n\"Acme, Inc.\",\"12 Main St, Boise\",\"Panel says \"\"East\"\"\""

        let rows = FireVaultStore.parseCSV(csv)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][0], "Acme, Inc.")
        XCTAssertEqual(rows[1][1], "12 Main St, Boise")
        XCTAssertEqual(rows[1][2], "Panel says \"East\"")
    }

    func testNativeCSVParserRecognizesWindowsCRLFRecords() {
        let csv = "Account Id,Account Name,Address\r\nA-1,First Account,100 Main St\r\nA-2,Second Account,200 Main St\r\n"

        let rows = FireVaultStore.parseCSV(csv)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].count, 3)
        XCTAssertEqual(rows[1][0], "A-1")
        XCTAssertEqual(rows[2][0], "A-2")
    }

    func testNativeCSVImportAddsAccountsAndSkipsDuplicateAccountID() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "Account Name,Address,Account ID,Category,Phone\nNative Customer,100 Test Way,NATIVE-1,Commercial,2085550199\nDuplicate,200 Test Way,NATIVE-1,Commercial,2085550188"

        let result = try store.importAccountsCSV(Data(csv.utf8))

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertTrue(store.accounts.contains { $0.accountId == "NATIVE-1" })
    }

    func testBackupMergeAddsMissingAccountsWithoutOverwritingExistingAccount() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let existing = try XCTUnwrap(store.accounts.first)
        var missing = existing
        missing.id = UUID().uuidString
        missing.accountId = "RESTORE-\(UUID().uuidString)"
        missing.name = "Restored Account"
        let originalName = existing.name

        var conflicting = existing
        conflicting.name = "Must Not Replace Existing"
        let data = try JSONEncoder().encode([conflicting, missing])
        let result = try store.mergeAccountsBackup(data)

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.preserved, 1)
        XCTAssertEqual(store.accounts.first(where: { $0.id == existing.id })?.name, originalName)
        XCTAssertTrue(store.accounts.contains { $0.id == missing.id })
    }

    func testNativeCSVImportSupportsUTF16AndCamelCaseNameHeader() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "customerName,address,accountId\nUTF16 Customer,300 Native Way,UTF16-1"
        let data = try XCTUnwrap(csv.data(using: .utf16))

        let result = try store.importAccountsCSV(data)

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertTrue(store.accounts.contains { $0.name == "UTF16 Customer" })
    }

    func testNativeCSVImportDetectsSemicolonDelimiterAndLikelyNameColumn() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "sep=;\nCompany Title;Service Address;Account Number\nSemicolon Customer;400 Native Way;SEMI-1"

        let result = try store.importAccountsCSV(Data(csv.utf8))

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertTrue(store.accounts.contains {
            $0.name == "Semicolon Customer" &&
            $0.address == "400 Native Way" &&
            $0.accountId == "SEMI-1"
        })
    }

    func testNativeCSVImportFallsBackToFirstColumnForUnknownHeaders() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "Organization Label|Street Detail|Reference\nFallback Customer|500 Native Way|FALLBACK-1"

        let result = try store.importAccountsCSV(Data(csv.utf8))

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(store.accounts.last?.name, "Fallback Customer")
        XCTAssertTrue(result.messages.contains { $0.contains("Organization Label") })
    }

    func testCSVImportRecognizesReorderedBOMLatLongAliases() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "\u{feff}lng,Account ID, LAT ,Account Name,Address\n-116.2023,COORD-1,43.6150,Coordinate Customer,100 Main St"

        let result = try store.importAccountsCSV(Data(csv.utf8))
        let account = try XCTUnwrap(store.accounts.first { $0.accountId == "COORD-1" })

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(try XCTUnwrap(account.latitude), 43.6150, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(account.longitude), -116.2023, accuracy: 0.000_001)
    }

    func testCSVImportRecognizesXYCoordinatesAndQuotedPipeFields() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "Account Name|Address|x|y\n\"Acme | West\"|\"12 Main St, Boise\"|-116.21|43.62"

        let result = try store.importAccountsCSV(Data(csv.utf8))
        let account = try XCTUnwrap(store.accounts.first { $0.name == "Acme | West" })

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(try XCTUnwrap(account.latitude), 43.62, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(account.longitude), -116.21, accuracy: 0.000_001)
    }

    func testCSVPreviewFlagsInvalidAndPartialCoordinatesForReview() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "Account Name,Latitude,Longitude\nOut of Range,95,-200\nPartial,43.61,"

        let analysis = try store.previewAccountsCSV(Data(csv.utf8))

        XCTAssertEqual(analysis.preview.review, 2)
        XCTAssertTrue(analysis.records.allSatisfy { $0.latitude == nil && $0.longitude == nil })
    }

    func testCSVPreviewPromptsThenCorrectsLikelySwappedCoordinates() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "Account Name,Latitude,Longitude\nSwapped Site,-116.2023,43.6150"

        let preview = try store.previewAccountsCSV(Data(csv.utf8))
        XCTAssertEqual(preview.preview.review, 1)
        XCTAssertTrue(preview.preview.rows[0].message.localizedCaseInsensitiveContains("swapped"))

        let corrected = try store.previewAccountsCSV(Data(csv.utf8), correctSwappedCoordinates: true)
        XCTAssertEqual(corrected.preview.successful, 1)
        XCTAssertEqual(try XCTUnwrap(corrected.records[0].latitude), 43.6150, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(corrected.records[0].longitude), -116.2023, accuracy: 0.000_001)
    }

    func testCSVAmbiguousHeadersRequireMappingReviewWithoutMutatingAccounts() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let csv = "Organization Label;Street Detail;Reference\nMapped Customer;500 Native Way;MAP-1"
        let accountCountBeforePreview = store.accounts.count

        let analysis = try store.previewAccountsCSV(Data(csv.utf8))

        XCTAssertTrue(analysis.preview.requiresMappingReview)
        XCTAssertEqual(store.accounts.count, accountCountBeforePreview)
        XCTAssertEqual(analysis.preview.delimiterName, "Semicolon")
    }

    func testPWACompatibleCSVAddsThenUpdatesByCanonicalAccountID() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let headers = "Account Id,Account Name,SiteID1,SiteID2,SiteLanguage,DeviceType,Site Phone,Device Phone,Device Phone Comment,Address,City,State,ZipCode,SiteGroupNum"
        let firstCSV = headers + "\nG7C1234-01,Original Customer,S1,S2,English,Cell,2085550100,2085550199,Primary communicator,100 Main St,Boise,ID,83702,12"

        let firstResult = try store.importAccountsCSV(Data(firstCSV.utf8))

        XCTAssertEqual(firstResult.added, 1)
        XCTAssertEqual(firstResult.updated, 0)
        let imported = try XCTUnwrap(store.accounts.first { $0.accountId == "G7C1234-01" })
        store.addNote(to: imported.id)

        let secondCSV = headers + "\n'g7c1234–01,Updated Customer,S1,S2,English,Cell,2085550101,2085550199,Primary communicator,200 Main St,Boise,ID,83702,12"
        let secondResult = try store.importAccountsCSV(Data(secondCSV.utf8))

        XCTAssertEqual(secondResult.added, 0)
        XCTAssertEqual(secondResult.updated, 1)
        XCTAssertEqual(secondResult.skipped, 0)
        let updated = try XCTUnwrap(store.accounts.first { $0.accountId == "G7C1234-01" })
        XCTAssertEqual(updated.name, "Updated Customer")
        XCTAssertEqual(updated.address, "200 Main St, Boise, ID, 83702")
        XCTAssertFalse(updated.notes.isEmpty, "CSV updates must preserve native field notes")
    }

    func testCSVAnalysisPreservesStructuredAddressFieldsForCloudSync() throws {
        let csv = "Account Name,Address,City,State,ZipCode,Account Id\nCloud Customer,100 Main St,Boise,ID,83702,CLOUD-1"

        let analysis = try FireVaultCSVImporter.analyze(Data(csv.utf8))
        let record = try XCTUnwrap(analysis.records.first)

        XCTAssertEqual(record.addressLine1, "100 Main St")
        XCTAssertEqual(record.city, "Boise")
        XCTAssertEqual(record.state, "ID")
        XCTAssertEqual(record.postalCode, "83702")
        XCTAssertEqual(record.address, "100 Main St, Boise, ID, 83702")
    }

    func testDemoAndProductionVaultsStaySeparate() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)

        XCTAssertTrue(store.demoMode)
        XCTAssertFalse(store.accounts.isEmpty)

        store.exitDemoMode()
        XCTAssertFalse(store.demoMode)
        XCTAssertTrue(store.accounts.isEmpty)

        let csv = "Account Name,Address,Account ID\nProduction Account,1 Main Street,PROD-1"
        _ = try store.importAccountsCSV(Data(csv.utf8))
        XCTAssertEqual(store.accounts.map(\.accountId), ["PROD-1"])

        store.enterDemoMode()
        XCTAssertTrue(store.demoMode)
        XCTAssertFalse(store.accounts.contains { $0.accountId == "PROD-1" })

        store.exitDemoMode()
        XCTAssertEqual(store.accounts.map(\.accountId), ["PROD-1"])
    }

    func testImportedCombinedAddressProducesCensusComponents() throws {
        let address = try XCTUnwrap(
            FireVaultPostalAddress(combinedAddress: "100 Main St, Boise, ID, 83702")
        )

        XCTAssertEqual(address.street, "100 Main St")
        XCTAssertEqual(address.city, "Boise")
        XCTAssertEqual(address.state, "ID")
        XCTAssertEqual(address.zip, "83702")
        XCTAssertEqual(address.singleLine, "100 Main St, Boise, ID, 83702")
    }

    func testCensusBatchPayloadUsesOpaqueTokenAndOmitsAccountIdentity() throws {
        let request = FireVaultGeocodingRequest(
            token: "fv-7",
            accountID: "private-native-id",
            address: try XCTUnwrap(
                FireVaultPostalAddress(combinedAddress: "100 Main St, Boise, ID, 83702")
            )
        )

        let payload = FireVaultCensusGeocoder.batchCSV(for: [request])

        XCTAssertTrue(payload.contains("\"fv-7\",\"100 Main St\",\"Boise\",\"ID\",\"83702\""))
        XCTAssertFalse(payload.contains("private-native-id"))
    }

    func testCensusResponseParserReadsLongitudeThenLatitude() throws {
        let response = """
        "fv-0","100 Main St, Boise, ID, 83702","Match","Exact","100 MAIN ST, BOISE, ID, 83702","-116.2023,43.6150","123","L"
        "fv-1","Missing Address, Boise, ID, 83702","No_Match"
        """

        let matches = try FireVaultCensusGeocoder.parseResponse(Data(response.utf8))

        XCTAssertEqual(matches, [
            .init(token: "fv-0", latitude: 43.6150, longitude: -116.2023)
        ])
    }

    func testGeocodedImportedAccountAppearsInNearbyUsingDeviceLocation() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        store.exitDemoMode()
        _ = try store.importAccountsCSV(
            Data("Account Name,Address,City,State,ZipCode,Account Id\nMapped Customer,100 Main St,Boise,ID,83702,MAP-1".utf8)
        )
        let account = try XCTUnwrap(store.accounts.first)
        let address = try XCTUnwrap(FireVaultPostalAddress(combinedAddress: account.address))
        let request = FireVaultGeocodingRequest(token: "fv-0", accountID: account.id, address: address)

        store.applyGeocodingMatches(
            [.init(token: "fv-0", latitude: 43.6150, longitude: -116.2023)],
            requests: [request]
        )
        let payload = store.appPayload(
            userCoordinate: .init(latitude: 43.6150, longitude: -116.2023),
            liveLocationStatus: "Updated"
        )

        XCTAssertEqual(store.mappedAccountCount, 1)
        XCTAssertEqual(store.unmappedAccountCount, 0)
        XCTAssertEqual(payload.nearby.map(\.account.accountId), ["MAP-1"])
        XCTAssertEqual(try XCTUnwrap(payload.nearby.first?.distanceMeters), 0, accuracy: 0.01)
    }

    func testNearbyUserCameraStaysCenteredOnCurrentLocation() {
        let coordinate = CLLocationCoordinate2D(latitude: 43.615, longitude: -116.2023)

        let region = FireVaultNearbyMapCamera.userRegion(
            coordinate: coordinate,
            radiusMiles: 2
        )

        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 0.000_001)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 0.000_001)
        XCTAssertGreaterThan(region.span.latitudeDelta, 0)
        XCTAssertGreaterThan(region.span.longitudeDelta, 0)
    }

    func testLiveNearbyUsesDrivingDistanceRefreshThreshold() {
        XCTAssertEqual(FireVaultLocationService.liveNearbyDistanceFilter, 50)
    }

    func testNearbyAccountCameraUsesTightAccountZoom() {
        let coordinate = CLLocationCoordinate2D(latitude: 43.6178, longitude: -116.197)

        let region = FireVaultNearbyMapCamera.accountRegion(coordinate: coordinate)

        XCTAssertEqual(region.center.latitude, coordinate.latitude, accuracy: 0.000_001)
        XCTAssertEqual(region.center.longitude, coordinate.longitude, accuracy: 0.000_001)
        XCTAssertEqual(region.span.latitudeDelta, 0.012, accuracy: 0.000_001)
        XCTAssertEqual(region.span.longitudeDelta, 0.012, accuracy: 0.000_001)
    }

    func testNearbyPayloadIsSortedClosestFirstAndResetIsObservable() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        let initialResetID = store.nearbyResetRequestID
        let payload = store.appPayload(
            userCoordinate: nil,
            liveLocationStatus: "Testing"
        )

        XCTAssertEqual(
            payload.nearby.map(\.distanceMeters),
            payload.nearby.map(\.distanceMeters).sorted()
        )

        store.requestNearbyReset()

        XCTAssertNotEqual(store.nearbyResetRequestID, initialResetID)
    }

    func testClearedCategoryStaysClearedWhenRulesRunAgain() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        store.exitDemoMode()
        let account = store.addAccount()
        let rule = FireVaultCategoryRule(
            field: .accountName,
            condition: .contains,
            value: "New Account",
            categoryTag: "Commercial"
        )

        store.configureCategoryRules([rule])
        XCTAssertEqual(store.accounts.first(where: { $0.id == account.id })?.category, "Commercial")

        XCTAssertTrue(store.updateAccount(
            id: account.id,
            name: account.name,
            address: account.address,
            category: "",
            accountId: account.accountId,
            phone: account.phone
        ))
        store.configureCategoryRules([rule])

        XCTAssertEqual(store.accounts.first(where: { $0.id == account.id })?.category, "")
        XCTAssertFalse(store.accounts.first(where: { $0.id == account.id })?.tags.contains("Commercial") == true)
    }

    func testAssigningCategoryAgainReenablesCategoryRules() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FireVaultStore(defaults: defaults)
        store.exitDemoMode()
        let account = store.addAccount()
        let rule = FireVaultCategoryRule(
            field: .accountName,
            condition: .contains,
            value: "New Account",
            categoryTag: "Commercial"
        )

        XCTAssertTrue(store.updateAccount(
            id: account.id,
            name: account.name,
            address: account.address,
            category: "Healthcare",
            accountId: account.accountId,
            phone: account.phone
        ))
        store.configureCategoryRules([rule])

        XCTAssertEqual(store.accounts.first(where: { $0.id == account.id })?.category, "Commercial")
    }

    func testEverySettingsCatalogRowHasANativeDestinationIdentifier() {
        let expected = Set([
            "overlay", "gps", "plusCodes", "notifications", "reports", "email", "cloudFiles",
            "microsoftStorage", "sync", "customerImport", "categories", "backup",
            "webdav", "privacy", "security", "manual", "demo", "about"
        ])

        XCTAssertEqual(Set(NativeSettingsCatalog.groups.flatMap(\.items).map(\.id)), expected)
    }

    func testGooglePlaceMatchDecodesProtectedLookupResponse() throws {
        let data = try XCTUnwrap(
            """
            {
              "placeID": "sample-place",
              "name": "Mountain View Medical Center",
              "address": "100 Demo Avenue, Casper, WY 82601",
              "distanceMeters": 42.5,
              "primaryType": "hospital"
            }
            """.data(using: .utf8)
        )

        let match = try JSONDecoder().decode(FireVaultGooglePlaceMatch.self, from: data)

        XCTAssertEqual(match.id, "sample-place")
        XCTAssertEqual(match.name, "Mountain View Medical Center")
        XCTAssertEqual(match.address, "100 Demo Avenue, Casper, WY 82601")
        XCTAssertEqual(match.distanceMeters, 42.5)
        XCTAssertEqual(match.primaryType, "hospital")
    }

    func testGooglePlacesErrorsGiveActionableMessages() {
        XCTAssertTrue(FireVaultGooglePlacesError.notAuthenticated.localizedDescription.contains("Sign in"))
        XCTAssertTrue(FireVaultGooglePlacesError.noMatches.localizedDescription.contains("manually"))
        XCTAssertTrue(FireVaultGooglePlacesError.unavailable.localizedDescription.contains("try again"))
    }

    private func testLocation(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        accuracy: CLLocationAccuracy = 10,
        speed: CLLocationSpeed = 0
    ) -> CLLocation {
        CLLocation(
            coordinate: .init(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: -1,
            course: -1,
            speed: speed,
            timestamp: timestamp
        )
    }
}
