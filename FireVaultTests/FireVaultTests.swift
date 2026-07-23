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

        XCTAssertEqual(about.displayStatus(nativeVersion: "1.08.01"), "Version 1.08.01")
        XCTAssertEqual(updates.displayStatus(nativeVersion: "1.08.01"), "Build 1.08.01")
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
        XCTAssertEqual(normalized.backgroundStyle, "bar")
        XCTAssertEqual(normalized.accentColor, "red")
        XCTAssertEqual(normalized.opacity, 35)
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
        XCTAssertTrue(decoded.fieldTemplate.contains("{site}"))
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

    func testEverySettingsCatalogRowHasANativeDestinationIdentifier() {
        let expected = Set([
            "overlay", "gps", "plusCodes", "reports", "email", "cloudFiles",
            "microsoftStorage", "sync", "customerImport", "categories", "backup",
            "webdav", "privacy", "security", "manual", "updates", "demo", "about"
        ])

        XCTAssertEqual(Set(NativeSettingsCatalog.groups.flatMap(\.items).map(\.id)), expected)
    }
}
