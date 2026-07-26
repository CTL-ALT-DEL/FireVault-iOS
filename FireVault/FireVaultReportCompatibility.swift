//
//  FireVaultReportCompatibility.swift
//  FireVault
//
//  Compatibility helpers for Trip Log report formatting.
//

import Foundation

extension Date.FormatStyle.Symbol.Month {
    /// Swift's long month-name style is named `wide`.
    /// This compatibility alias keeps report-formatting call sites readable.
    static var long: Self { .wide }
}
