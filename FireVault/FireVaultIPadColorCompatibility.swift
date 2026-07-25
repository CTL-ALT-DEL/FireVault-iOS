//
//  FireVaultIPadColorCompatibility.swift
//  FireVault
//
//  Color fallback used by the adaptive iPad workspace.
//

import SwiftUI

extension Color {
    /// A subdued semantic color for metadata and unselected controls.
    static var tertiary: Color {
        Color.secondary.opacity(0.62)
    }
}
