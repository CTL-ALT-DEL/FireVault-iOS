//
//  FireVaultWidgetDesign.swift
//  FireVaultWidgets
//
//  Shared visual language for every FireVault widget family.
//

import SwiftUI
import WidgetKit

enum FireVaultWidgetDesign {
    static let ivory = Color(red: 0.965, green: 0.945, blue: 0.895)
    static let paper = Color(red: 0.995, green: 0.985, blue: 0.955)
    static let navy = Color(red: 0.035, green: 0.27, blue: 0.40)
    static let red = Color(red: 0.80, green: 0.075, blue: 0.11)
    static let green = Color(red: 0.02, green: 0.50, blue: 0.30)
    static let amber = Color(red: 0.76, green: 0.38, blue: 0.02)
    static let line = Color.black.opacity(0.10)
}

struct FireVaultWidgetBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if renderingMode == .fullColor {
                ZStack {
                    FireVaultWidgetDesign.ivory
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.56),
                            FireVaultWidgetDesign.ivory.opacity(0.15),
                            FireVaultWidgetDesign.navy.opacity(0.055)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else {
                Color.clear
            }
        }
        .widgetAccentable(false)
    }
}

struct FireVaultWidgetBrand: View {
    var section: String? = nil

    var body: some View {
        Text(section?.uppercased() ?? "FIREVAULT")
            .font(.caption.weight(.bold))
            .tracking(0.55)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(section.map { "FireVault \($0)" } ?? "FireVault")
    }
}

struct FireVaultWidgetStatusPill: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .widgetAccentable()
    }
}

struct FireVaultWidgetMetric: View {
    let value: String
    let title: String
    let symbol: String
    var color: Color = FireVaultWidgetDesign.navy
    var compact = false
    var showsSymbol = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
            Group {
                if showsSymbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Text(value)
                .font(compact ? .subheadline.bold() : .headline.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 0 : 9)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FireVaultWidgetDesign.paper.opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FireVaultWidgetDesign.line, lineWidth: 1)
                    }
                    .widgetAccentable(false)
            }
        }
        .overlay(alignment: .leading) {
            if compact {
                Capsule()
                    .fill(color)
                    .frame(width: 3)
                    .offset(x: -7)
                    .widgetAccentable()
            }
        }
        .padding(.leading, compact ? 7 : 0)
    }
}

struct FireVaultWidgetActionLabel: View {
    let title: String
    let symbol: String
    var color: Color = FireVaultWidgetDesign.navy
    var compact = false

    var body: some View {
        Label(title, systemImage: symbol)
            .font(compact ? .caption.bold() : .subheadline.bold())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 30 : 38)
            .background(color, in: RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))
            .widgetAccentable()
    }
}

struct FireVaultWidgetAccountRow: View {
    let name: String
    let detail: String
    var showChevron = true

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "building.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FireVaultWidgetDesign.navy)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .privacySensitive()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
            Spacer(minLength: 2)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            FireVaultWidgetDesign.paper.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
