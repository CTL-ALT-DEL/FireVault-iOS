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

        XCTAssertEqual(about.displayStatus(nativeVersion: "1.05.03"), "Version 1.05.03")
        XCTAssertEqual(updates.displayStatus(nativeVersion: "1.05.03"), "Build 1.05.03")
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

    func testEverySettingsCatalogRowHasANativeDestinationIdentifier() {
        let expected = Set([
            "overlay", "gps", "plusCodes", "reports", "email", "cloudFiles",
            "microsoftStorage", "sync", "customerImport", "categories", "backup",
            "webdav", "privacy", "security", "manual", "updates", "demo", "about"
        ])

        XCTAssertEqual(Set(NativeSettingsCatalog.groups.flatMap(\.items).map(\.id)), expected)
    }
}
