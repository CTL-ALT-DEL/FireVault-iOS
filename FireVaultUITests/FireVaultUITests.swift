//
//  FireVaultUITests.swift
//  FireVaultUITests
//
//  Created by David Bannerman on 7/20/26.
//

import XCTest

final class FireVaultUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testNativeSettingsControlsAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsTab = app.buttons["main-navigation-settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["firevault-brand-header"].exists)
        settingsTab.tap()

        let technicianRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Technician Profile")
        ).firstMatch
        XCTAssertTrue(technicianRow.waitForExistence(timeout: 3))
        technicianRow.tap()

        let technicianName = app.textFields["Technician name"]
        XCTAssertTrue(technicianName.waitForExistence(timeout: 3))
        technicianName.tap()
        technicianName.typeText("Native Test")
        app.buttons["Done"].tap()
        app.buttons["Save"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let gpsRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "GPS & Maps")
        ).firstMatch
        XCTAssertTrue(gpsRow.waitForExistence(timeout: 3))
        gpsRow.tap()

        let radiusWheel = app.descendants(matching: .any)["settings-radius-wheel"]
        XCTAssertTrue(radiusWheel.waitForExistence(timeout: 3))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.webViews.firstMatch.exists, "Native Settings must never display a web view")
    }

    @MainActor
    func testNativePhotoCaptureChoicesAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let photoTab = app.buttons["main-navigation-photo"]
        XCTAssertTrue(photoTab.waitForExistence(timeout: 8))
        photoTab.tap()

        XCTAssertTrue(app.buttons["native-take-photo"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["native-scan-document"].exists)
        XCTAssertTrue(app.buttons["native-choose-photo"].exists)
        XCTAssertTrue(app.otherElements["native-capture-destination"].exists)

        app.buttons["native-scan-document"].tap()
        XCTAssertTrue(app.navigationBars["Choose Account"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.webViews.firstMatch.exists, "Native Photo must never display a web view")
    }

    @MainActor
    func testPhotoOverlayEditorShowsSampleAndStructuredFields() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["main-navigation-settings"].waitForExistence(timeout: 8))
        app.buttons["main-navigation-settings"].tap()

        let overlayRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Photo Overlay")
        ).firstMatch
        XCTAssertTrue(overlayRow.waitForExistence(timeout: 3))
        overlayRow.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["overlay-sample-preview"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["overlay-accent-picker"].exists
        )

        app.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any)["overlay-field-site"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    @MainActor
    func testNearbyMapOptionsAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let nearbyTab = app.buttons["main-navigation-nearby"]
        XCTAssertTrue(nearbyTab.waitForExistence(timeout: 8))
        nearbyTab.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["nearby-horizontal-radius-picker"]
                .waitForExistence(timeout: 5)
        )
        let mapOptions = app.buttons["nearby-map-options"]
        XCTAssertTrue(mapOptions.waitForExistence(timeout: 5))
        XCTAssertTrue(mapOptions.label.contains("Map options"))
        XCTAssertFalse(app.webViews.firstMatch.exists, "Native Nearby must never display a web view")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
