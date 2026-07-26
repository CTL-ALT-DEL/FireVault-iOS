//
//  FireVaultUnitPointOverlayCompatibility.swift
//  FireVault
//
//  Allows an explicitly typed UnitPoint to be used for simple overlay placement
//  without competing with SwiftUI's native Alignment overload.
//

import SwiftUI

extension View {
    @_disfavoredOverload
    @ViewBuilder
    func overlay<Overlay: View>(
        alignment point: UnitPoint,
        @ViewBuilder content: () -> Overlay
    ) -> some View {
        let horizontal: HorizontalAlignment
        if point.x <= 0.25 {
            horizontal = HorizontalAlignment.leading
        } else if point.x >= 0.75 {
            horizontal = HorizontalAlignment.trailing
        } else {
            horizontal = HorizontalAlignment.center
        }

        let vertical: VerticalAlignment
        if point.y <= 0.25 {
            vertical = VerticalAlignment.top
        } else if point.y >= 0.75 {
            vertical = VerticalAlignment.bottom
        } else {
            vertical = VerticalAlignment.center
        }

        self.overlay(
            alignment: Alignment(horizontal: horizontal, vertical: vertical),
            content: content
        )
    }
}
