//
//  FireVaultUnitPointOverlayCompatibility.swift
//  FireVault
//
//  Allows an explicitly typed UnitPoint to be used for simple overlay placement.
//

import SwiftUI

extension View {
    @_disfavoredOverload
    @ViewBuilder
    func overlay<OverlayContent: View>(
        alignment point: UnitPoint,
        @ViewBuilder content: @escaping () -> OverlayContent
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
            alignment: Alignment(horizontal: horizontal, vertical: vertical)
        ) {
            content()
        }
    }
}
