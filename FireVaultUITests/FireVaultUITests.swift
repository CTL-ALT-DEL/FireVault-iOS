//
//  FireVaultUITests.swift
//  FireVaultUITests
//
//  Created by David Bannerman on 7/20/26.
//

import XCTest

final class FireVaultUITests: XCTestCase {

    @MainActor
    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"),
                object: element
            )],
            timeout: timeout
        ) == .completed
    }

    @MainActor
    private func waitForAppReady(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        app.descendants(matching: .any)["firevault-splash"]
            .waitForNonExistence(timeout: timeout)
    }

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
        app.launchArguments += ["-FireVaultUITesting", "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.launch()
        XCTAssertTrue(waitForAppReady(app))

        let settingsTab = app.buttons["main-navigation-settings"]
        XCTAssertTrue(waitForHittable(settingsTab))
        XCTAssertTrue(app.otherElements["firevault-brand-header"].exists)
        settingsTab.tap()

        let technicianRow = app.descendants(matching: .any)["settings-technician-profile"]
        XCTAssertTrue(technicianRow.waitForExistence(timeout: 3))
        technicianRow.tap()

        let technicianName = app.textFields["Technician name"]
        XCTAssertTrue(technicianName.waitForExistence(timeout: 3))
        // This is a reachability test. Do not edit or save the technician's
        // persisted profile, because UI tests can share the simulator's app data.
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
        app.launchArguments += ["-FireVaultUITesting", "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.launch()
        XCTAssertTrue(waitForAppReady(app))

        let photoTab = app.buttons["main-navigation-photo"]
        XCTAssertTrue(waitForHittable(photoTab))
        photoTab.tap()

        let takePhoto = app.buttons["native-take-photo"]
        if !takePhoto.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 3))
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
        app.launchArguments += ["-FireVaultUITesting", "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.launch()
        XCTAssertTrue(waitForAppReady(app))

        XCTAssertTrue(waitForHittable(app.buttons["main-navigation-settings"]))
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
        app.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any)["overlay-accent-picker"]
                .waitForExistence(timeout: 3)
        )

        app.swipeUp()
        let fieldsDisclosure = app.buttons["Choose Fields and Order"]
        XCTAssertTrue(fieldsDisclosure.waitForExistence(timeout: 3))
        fieldsDisclosure.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["overlay-field-site"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    @MainActor
    func testNearbyMapOptionsAreReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-FireVaultUITesting", "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.launch()
        XCTAssertTrue(waitForAppReady(app))

        let nearbyTab = app.buttons["main-navigation-nearby"]
        XCTAssertTrue(waitForHittable(nearbyTab))
        nearbyTab.tap()

        let mapOptions = app.buttons["nearby-map-options"]
        XCTAssertTrue(mapOptions.waitForExistence(timeout: 5))
        XCTAssertTrue(mapOptions.label.contains("Map options"))
        XCTAssertTrue(app.scrollViews["nearby-account-scroll"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists, "Native Nearby must never display a web view")
    }

    @MainActor
    func testBreadcrumbTrackingPrivacyAndPermissionStateAreReachable() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-FireVaultUITesting", "-UIAccessibilityReduceMotionEnabled", "YES"]
        app.launch()
        XCTAssertTrue(waitForAppReady(app))

        XCTAssertTrue(waitForHittable(app.buttons["main-navigation-nearby"]))
        app.buttons["main-navigation-nearby"].tap()

        let tripLogStatus = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Trip Log,")
        ).firstMatch
        XCTAssertTrue(tripLogStatus.waitForExistence(timeout: 5))
        tripLogStatus.tap()

        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.webViews.firstMatch.exists,
            "Breadcrumbs must remain a fully native iOS workflow"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testWarmIvorySettingsVisualReference() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-FireVaultUITesting",
            "-firevault.native.settings.appearance.v1", "light",
            "-UIAccessibilityReduceMotionEnabled", "YES"
        ]
        app.launch()
        XCTAssertTrue(waitForAppReady(app))
        let settingsTab = app.buttons["main-navigation-settings"]
        XCTAssertTrue(waitForHittable(settingsTab))
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "hittable == true"),
                    object: settingsTab
                )],
                timeout: 8
            ),
            .completed
        )
        settingsTab.tap()
        XCTAssertTrue(settingsTab.exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Warm Ivory - Settings Overview"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSettingsRemainReachableAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-FireVaultUITesting",
            "-UIAccessibilityReduceMotionEnabled", "YES",
            "-firevault.native.settings.appearance.v1", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()
        XCTAssertTrue(waitForAppReady(app))
        let settings = app.buttons["main-navigation-settings"]
        XCTAssertTrue(waitForHittable(settings))
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "hittable == true"),
                    object: settings
                )],
                timeout: 8
            ),
            .completed
        )
        settings.tap()
        app.swipeUp()
        XCTAssertTrue(settings.exists)
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }
}
