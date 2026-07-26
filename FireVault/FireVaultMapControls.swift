//
//  FireVaultMapControls.swift
//  FireVault
//
//  Shared map controls used across compact and regular-width workspaces.
//

import SwiftUI

enum FireVaultMapControlRole {
    case layers
    case note
    case call
    case route

    var symbol: String {
        switch self {
        case .layers: "square.3.layers.3d.top.filled"
        case .note: "note.text"
        case .call: "phone.fill"
        case .route: "arrow.triangle.turn.up.right.diamond.fill"
        }
    }

    var tint: Color {
        switch self {
        case .layers, .route: NativeShellPalette.blue
        case .note: NativeShellPalette.amber
        case .call: NativeShellPalette.green
        }
    }
}

struct FireVaultMapControlGlyph: View {
    let role: FireVaultMapControlRole
    var disabled = false

    var body: some View {
        Image(systemName: role.symbol)
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(disabled ? Color.secondary : Color.white)
            .frame(width: 48, height: 48)
            .background(
                disabled ? Color.black.opacity(0.60) : role.tint.opacity(0.94),
                in: Circle()
            )
            .overlay {
                Circle().stroke(.white.opacity(disabled ? 0.18 : 0.68), lineWidth: 1.25)
            }
            .shadow(color: .black.opacity(0.42), radius: 6, y: 3)
            .contentShape(Circle())
    }
}

struct FireVaultMapControlButton: View {
    let role: FireVaultMapControlRole
    let label: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FireVaultMapControlGlyph(role: role, disabled: disabled)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

struct FireVaultMapActionStrip<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 9) {
            content
        }
        .padding(7)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.16), lineWidth: 1)
        }
    }
}
