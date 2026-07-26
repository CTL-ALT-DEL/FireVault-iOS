//
//  FireVaultIPadColorCompatibility.swift
//  FireVault
//
//  Small compatibility helpers used by the adaptive iPad workspace.
//

import SwiftUI

extension Color {
    /// A subdued semantic color for metadata and unselected controls.
    static var tertiary: Color {
        Color.secondary.opacity(0.62)
    }
}

extension View {
    /// Applies a fixed width and an independent maximum height.
    /// SwiftUI does not provide these arguments in one built-in frame overload.
    func frame(
        width: CGFloat,
        maxHeight: CGFloat,
        alignment: Alignment = .center
    ) -> some View {
        self
            .frame(width: width)
            .frame(maxHeight: maxHeight, alignment: alignment)
    }
}
