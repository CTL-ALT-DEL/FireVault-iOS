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
    func testNativeSettingsTextFieldsAreReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsTab = app.buttons["main-navigation-settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
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

        let radius = app.textFields["Nearby radius in miles"]
        XCTAssertTrue(radius.waitForExistence(timeout: 3))
        radius.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.webViews.firstMatch.exists, "Native Settings must never display a web view")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
