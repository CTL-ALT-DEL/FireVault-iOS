//
//  FireVaultTripSummaryAIValidationTests.swift
//  FireVaultTests
//

import XCTest
@testable import FireVault

@MainActor
final class FireVaultTripSummaryAIValidationTests: XCTestCase {
    private let source = """
    The trip started at FireVault Office, 100 Main Street at 7:35 AM and ended at Service Yard, 900 West Avenue at 12:45 PM. It covered 42.6 mi in 5h 10m, averaging 57 mph. The trip included 3 recorded stops. Elevation ranged from about 2,619 to 2,923 feet.
    """

    func testTripSummaryValidatorAcceptsUnchangedAuthoritativeFacts() {
        XCTAssertTrue(
            FireVaultTripSummaryAIService.validatesFactualRewrite(source, source: source)
        )
    }

    func testTripSummaryValidatorAcceptsUnavailableOptionalMetrics() {
        let factual = """
        The trip started at Recorded GPS location at 07:35 and ended at Location unavailable at 07:40. It covered 0 ft in 5m. Average speed was unavailable. No stops were recorded. Elevation data was unavailable.
        """

        XCTAssertTrue(
            FireVaultTripSummaryAIService.validatesFactualRewrite(factual, source: factual)
        )
    }

    func testTripSummaryValidatorRejectsSwappedEndpointTimes() {
        let candidate = source
            .replacingOccurrences(of: "at 7:35 AM and ended", with: "at 12:45 PM and ended")
            .replacingOccurrences(of: "at 12:45 PM.", with: "at 7:35 AM.")

        XCTAssertFalse(
            FireVaultTripSummaryAIService.validatesFactualRewrite(candidate, source: source)
        )
    }

    func testTripSummaryValidatorRejectsSwappedEndpointLocations() {
        let candidate = source
            .replacingOccurrences(
                of: "FireVault Office, 100 Main Street at 7:35 AM",
                with: "Service Yard, 900 West Avenue at 7:35 AM"
            )
            .replacingOccurrences(
                of: "Service Yard, 900 West Avenue at 12:45 PM",
                with: "FireVault Office, 100 Main Street at 12:45 PM"
            )

        XCTAssertFalse(
            FireVaultTripSummaryAIService.validatesFactualRewrite(candidate, source: source)
        )
    }

    func testTripSummaryValidatorRejectsSpeedElevationValueSwap() {
        let candidate = source
            .replacingOccurrences(of: "averaging 57 mph", with: "averaging 2,619 mph")
            .replacingOccurrences(
                of: "from about 2,619 to 2,923 feet",
                with: "from about 57 to 2,923 feet"
            )

        XCTAssertFalse(
            FireVaultTripSummaryAIService.validatesFactualRewrite(candidate, source: source)
        )
    }

    func testTripSummaryValidatorRejectsSwappedStopTotalAndSpeed() {
        let candidate = source
            .replacingOccurrences(of: "averaging 57 mph", with: "averaging 3 mph")
            .replacingOccurrences(of: "included 3 recorded stops", with: "included 57 recorded stops")

        XCTAssertFalse(
            FireVaultTripSummaryAIService.validatesFactualRewrite(candidate, source: source)
        )
    }

    func testTripSummaryValidatorRejectsDistanceDurationValueSwap() {
        let factual = source.replacingOccurrences(
            of: "42.6 mi in 5h 10m",
            with: "5 mi in 42h 10m"
        )
        let candidate = factual.replacingOccurrences(
            of: "5 mi in 42h 10m",
            with: "42 mi in 5h 10m"
        )

        XCTAssertFalse(
            FireVaultTripSummaryAIService.validatesFactualRewrite(candidate, source: factual)
        )
    }
}
