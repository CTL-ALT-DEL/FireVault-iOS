//
//  FireVaultDemoShowroomTests.swift
//  FireVaultTests
//
//  Demo showroom validation for Build 1.08.06.
//

import XCTest
@testable import FireVault

@MainActor
final class FireVaultDemoShowroomTests: XCTestCase {
    func testShowroomContainsExactlyThirtyAccounts() {
        XCTAssertEqual(FireVaultDemoShowroom.accounts.count, 30)
        XCTAssertEqual(Set(FireVaultDemoShowroom.accounts.map(\.id)).count, 30)
    }

    func testEveryDemoAccountContainsFeatureSamples() {
        for account in FireVaultDemoShowroom.accounts {
            XCTAssertGreaterThanOrEqual(account.equipment.count, 4, account.name)
            XCTAssertGreaterThanOrEqual(account.notes.count, 2, account.name)
            XCTAssertGreaterThanOrEqual(account.documents.count, 2, account.name)

            let locationText = account.locations
                .map { "\($0.label) \($0.type)".lowercased() }
                .joined(separator: " ")
            XCTAssertTrue(locationText.contains("panel"), account.name)
            XCTAssertTrue(locationText.contains("riser"), account.name)
            XCTAssertTrue(locationText.contains("parking"), account.name)
        }
    }

    func testDemoBreadcrumbsContainsSevenCompleteWorkdays() {
        let days = FireVaultDemoShowroom.breadcrumbDays
        XCTAssertEqual(days.count, 7)

        for day in days {
            XCTAssertNotNil(day.endedAt)
            XCTAssertFalse(day.isActive)
            XCTAssertGreaterThanOrEqual(day.stops.count, 3)
            XCTAssertGreaterThan(day.points.count, day.stops.count)
            XCTAssertGreaterThan(day.totalDistanceMeters, 1_000)
            XCTAssertTrue(day.stops.allSatisfy { $0.accountID?.hasPrefix("demo-showroom-") == true })
        }
    }

    func testShowroomSummaryMatchesGeneratedRecords() {
        let summary = FireVaultDemoShowroom.summary
        XCTAssertGreaterThanOrEqual(summary.equipment, 180)
        XCTAssertGreaterThanOrEqual(summary.locations, 120)
        XCTAssertGreaterThanOrEqual(summary.notes, 60)
        XCTAssertGreaterThan(summary.routePoints, 200)
    }
}
