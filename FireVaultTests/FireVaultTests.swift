//
//  FireVaultTests.swift
//  FireVaultTests
//
//  Created by David Bannerman on 7/20/26.
//

import XCTest
@testable import FireVault

@MainActor
final class FireVaultTests: XCTestCase {
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

    func testNativeSettingsVersionStatusesUseInstalledVersion() {
        let about = FireVaultNativeSettingItem(
            id: "about",
            title: "About FireVault",
            subtitle: "Application information",
            symbol: "info.circle",
            status: "Version 1.03.30"
        )
        let updates = FireVaultNativeSettingItem(
            id: "updates",
            title: "App Updates",
            subtitle: "Application files",
            symbol: "arrow.down.circle",
            status: "Build 1.03.30"
        )

        XCTAssertEqual(about.displayStatus(nativeVersion: "1.05.00"), "Version 1.05.00")
        XCTAssertEqual(updates.displayStatus(nativeVersion: "1.05.00"), "Build 1.05.00")
    }

    func testNativeGPSPreferencesClampRadiusToSupportedRange() {
        var low = FireVaultGPSPreferences()
        low.nearbyRadiusMiles = 0.1
        XCTAssertEqual(low.normalized.nearbyRadiusMiles, 0.25)

        var high = FireVaultGPSPreferences()
        high.nearbyRadiusMiles = 80
        XCTAssertEqual(high.normalized.nearbyRadiusMiles, 25)
    }

    func testNativeGPSSettingsPersistAndReload() throws {
        let suite = "FireVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = FireVaultNativeSettingsStore(defaults: defaults)
        var preferences = FireVaultGPSPreferences()
        preferences.nearbyRadiusMiles = 3.5
        preferences.highAccuracy = false
        store.saveGPS(preferences)

        let reloaded = FireVaultNativeSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.gps.nearbyRadiusMiles, 3.5)
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

    func testNativeCSVParserSupportsQuotedCommasAndEscapedQuotes() {
        let csv = "Account Name,Address,Note\n\"Acme, Inc.\",\"12 Main St, Boise\",\"Panel says \"\"East\"\"\""

        let rows = FireVaultStore.parseCSV(csv)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][0], "Acme, Inc.")
        XCTAssertEqual(rows[1][1], "12 Main St, Boise")
        XCTAssertEqual(rows[1][2], "Panel says \"East\"")
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

    func testEverySettingsCatalogRowHasANativeDestinationIdentifier() {
        let expected = Set([
            "overlay", "gps", "plusCodes", "reports", "email", "cloudFiles",
            "microsoftStorage", "sync", "customerImport", "categories", "backup",
            "webdav", "privacy", "security", "manual", "updates", "demo", "about"
        ])

        XCTAssertEqual(Set(NativeSettingsCatalog.groups.flatMap(\.items).map(\.id)), expected)
    }
}
