//
//  FireVaultTests.swift
//  FireVaultTests
//
//  Created by David Bannerman on 7/20/26.
//

import XCTest
@testable import FireVault

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

    func testWebIntegrationTargetsSharedKeyboardAndNavigationLayers() {
        let source = FireVaultWebIntegration.source(version: "1.03.34")

        XCTAssertTrue(source.contains("fvNativeKeyboard10334 main#app"))
        XCTAssertTrue(source.contains("fvNativeIOS10334 #appNav"))
        XCTAssertTrue(source.contains(".nearbyBottomNav069"))
        XCTAssertTrue(source.contains("body.fvNativeIOS10334::after"))
        XCTAssertTrue(source.contains("event.stopImmediatePropagation()"))
        XCTAssertTrue(source.contains("nearestScrollContainer"))
        XCTAssertFalse(source.contains("scrollIntoView"))
    }

    func testWebIntegrationSynchronizesVisibleVersionAndPhotoOverlayHeader() {
        let source = FireVaultWebIntegration.source(version: "1.03.34")

        XCTAssertTrue(source.contains(".splashBuild492"))
        XCTAssertTrue(source.contains(".aboutGrid540"))
        XCTAssertTrue(source.contains("photoOverlayDetailHeader1032"))
        XCTAssertTrue(source.contains("1.03.34"))
    }

    func testNativeSettingsVersionStatusesOverrideOlderWebPayload() {
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

        XCTAssertEqual(about.displayStatus(nativeVersion: "1.03.34"), "Version 1.03.34")
        XCTAssertEqual(updates.displayStatus(nativeVersion: "1.03.34"), "Build 1.03.34")
    }
}
