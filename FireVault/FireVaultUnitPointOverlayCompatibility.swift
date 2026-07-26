//
//  FireVaultUnitPointOverlayCompatibility.swift
//  FireVault
//
//  Allows an explicitly typed UnitPoint to be used for simple overlay placement.
//

import SwiftUI

extension View {
    @ViewBuilder
    func overlay<Overlay: View>(
        alignment point: UnitPoint,
        @ViewBuilder content: () -> Overlay
    ) -> some View {
        let horizontal: HorizontalAlignment
        if point.x <= 0.25 {
            horizontal = .leading
        } else if point.x >= 0.75 {
            horizontal = .trailing
        } else {
            horizontal = .center
        }

        let vertical: VerticalAlignment
        if point.y <= 0.25 {
            vertical = .top
        } else if point.y >= 0.75 {
            vertical = .bottom
        } else {
            vertical = .center
        }

        self.overlay(
            alignment: Alignment(horizontal: horizontal, vertical: vertical),
            content: content
        )
    }
}
