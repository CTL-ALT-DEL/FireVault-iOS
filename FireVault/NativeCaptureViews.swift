//
//  NativeCaptureViews.swift
//  FireVault
//
//  Native camera, document scanning, and field-photo overlay support.
//

import SwiftUI
import UIKit
import AVFoundation
import AVKit
import VisionKit
import CoreImage.CIFilterBuiltins
import CoreLocation

struct FireVaultResolvedOverlayField: Identifiable, Equatable {
    let field: FireVaultOverlayField
    let value: String
    var id: String { field.rawValue }
}

struct FireVaultOverlayPreviewGeometry {
    /// The settings sample mirrors the full-screen editor's native 4:3
    /// landscape camera canvas, even while Settings is shown in portrait.
    static let designSize = CGSize(width: 430.0 * 4.0 / 3.0, height: 430)

    let previewSize: CGSize

    var scale: CGFloat {
        min(
            previewSize.width / Self.designSize.width,
            previewSize.height / Self.designSize.height
        )
    }

    var scaledDesignSize: CGSize {
        CGSize(
            width: Self.designSize.width * scale,
            height: Self.designSize.height * scale
        )
    }

    var designOrigin: CGPoint {
        CGPoint(
            x: (previewSize.width - scaledDesignSize.width) / 2,
            y: (previewSize.height - scaledDesignSize.height) / 2
        )
    }

    func designPoint(from previewPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: (previewPoint.x - designOrigin.x) / max(scale, 0.0001),
            y: (previewPoint.y - designOrigin.y) / max(scale, 0.0001)
        )
    }

    func designTranslation(from previewTranslation: CGSize) -> CGSize {
        CGSize(
            width: previewTranslation.width / max(scale, 0.0001),
            height: previewTranslation.height / max(scale, 0.0001)
        )
    }
}

struct FireVaultOverlayPanelSizing {
    struct Metrics: Equatable {
        let informationWidth: CGFloat
        let panelWidth: CGFloat
    }

    static func metrics(
        siteName: String,
        maximumFieldLength: Int,
        hasTechnician: Bool,
        hasQRCode: Bool = false,
        canvasWidth: CGFloat,
        scale: Double
    ) -> Metrics {
        let technicianAllowance: CGFloat = hasTechnician ? 76 : 0
        let qrAllowance: CGFloat = hasQRCode ? 52 : 0
        let maximumPanelWidth = max(
            180,
            min(560, (canvasWidth - 20) / max(scale, 0.45))
        )
        let desiredInformationWidth = max(
            145,
            CGFloat(siteName.count) * 6.7,
            CGFloat(maximumFieldLength) * 5.9
        )
        let availableInformationWidth = max(
            145,
            maximumPanelWidth - technicianAllowance - qrAllowance - 28
        )
        let informationWidth = min(
            availableInformationWidth,
            desiredInformationWidth
        )
        return Metrics(
            informationWidth: informationWidth,
            panelWidth: min(
                maximumPanelWidth,
                informationWidth + technicianAllowance + qrAllowance + 28
            )
        )
    }
}

enum FireVaultOverlayCanvasConstraints {
    static func constrained(
        _ preferences: FireVaultOverlayPreferences,
        canvasSize: CGSize,
        technicianName: String,
        siteName: String,
        address: String,
        accountID: String,
        category: String
    ) -> FireVaultOverlayPreferences {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return preferences.normalized }
        var value = preferences.normalized
        let fields = FireVaultOverlayTemplateFormatter.resolvedFields(
            preferences: value,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category,
            technicianName: technicianName,
            timestamp: .now
        )
        let informationFields = fields.filter { $0.field != .technician }
        let metrics = FireVaultOverlayPanelSizing.metrics(
            siteName: siteName,
            maximumFieldLength: informationFields.map(\.value.count).max() ?? 0,
            hasTechnician: fields.contains { $0.field == .technician },
            hasQRCode: value.showLocationQRCode,
            canvasWidth: canvasSize.width,
            scale: value.scale
        )
        let visibleLines = informationFields.count + (value.showTagline ? 1 : 0)
        let unscaledPanelHeight = max(
            value.showLocationQRCode ? 58 : 48,
            CGFloat(visibleLines) * 12 + 18 + (value.glassThickness == "thick" ? 4 : 0)
        )
        value.positionX = normalizedPosition(
            current: value.positionX,
            canvasLength: canvasSize.width,
            elementLength: metrics.panelWidth * value.scale
        )
        value.positionY = normalizedPosition(
            current: value.positionY,
            canvasLength: canvasSize.height,
            elementLength: unscaledPanelHeight * value.scale
        )
        value.logoPositionX = normalizedPosition(
            current: value.logoPositionX,
            canvasLength: canvasSize.width,
            elementLength: 118 * value.logoScale
        )
        value.logoPositionY = normalizedPosition(
            current: value.logoPositionY,
            canvasLength: canvasSize.height,
            elementLength: 44 * value.logoScale
        )
        return value.normalized
    }

    private static func normalizedPosition(
        current: Double,
        canvasLength: CGFloat,
        elementLength: CGFloat
    ) -> Double {
        let margin: CGFloat = 6
        let halfElement = min(canvasLength / 2, elementLength / 2 + margin)
        let proposedCenter = canvasLength * (0.5 + CGFloat(current) * 0.36)
        let center = min(max(proposedCenter, halfElement), canvasLength - halfElement)
        return Double((center / canvasLength - 0.5) / 0.36)
    }
}

enum FireVaultLocationQRCode {
    static func payload(for account: FireVaultWorkspaceAccount) -> String? {
        guard let coordinate = account.coordinate else { return nil }
        return payload(latitude: coordinate.latitude, longitude: coordinate.longitude, name: account.name)
    }

    static func payload(latitude: Double, longitude: Double, name: String) -> String {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name)
        ]
        return components.url?.absoluteString ?? "https://maps.apple.com/?ll=\(latitude),\(longitude)"
    }
}

enum FireVaultQRCodeRenderer {
    static func image(from payload: String, scale: CGFloat = 8) -> UIImage? {
        guard let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct FireVaultOverlayDragSurface: UIViewRepresentable {
    let canBegin: (CGPoint) -> Bool
    let onBegan: (CGPoint) -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let recognizer = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = true
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: FireVaultOverlayDragSurface

        init(parent: FireVaultOverlayDragSurface) {
            self.parent = parent
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let view = gestureRecognizer.view else { return false }
            return parent.canBegin(gestureRecognizer.location(in: view))
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let translatedSize = CGSize(width: translation.x, height: translation.y)

            switch recognizer.state {
            case .began:
                parent.onBegan(recognizer.location(in: view))
            case .changed:
                parent.onChanged(translatedSize)
            case .ended:
                parent.onEnded(translatedSize)
            case .cancelled, .failed:
                parent.onEnded(.zero)
            default:
                break
            }
        }
    }
}

enum FireVaultOverlayTemplateFormatter {
    static func resolvedFields(
        preferences: FireVaultOverlayPreferences,
        siteName: String,
        address: String,
        accountID: String,
        category: String,
        technicianName: String,
        timestamp: Date
    ) -> [FireVaultResolvedOverlayField] {
        let values: [FireVaultOverlayField: String] = [
            .site: siteName,
            .address: address,
            .accountID: accountID.isEmpty ? "" : "Account ID: \(accountID)",
            .category: category.isEmpty ? "" : "Category: \(category)",
            .technician: technicianName,
            .timestamp: timestamp.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
        ]
        let hidden = Set(preferences.hiddenFields)
        return preferences.fieldOrder.compactMap { fieldID in
            guard let field = FireVaultOverlayField(rawValue: fieldID),
                  field.isRequired || !hidden.contains(fieldID),
                  let value = values[field], !value.isEmpty else { return nil }
            return FireVaultResolvedOverlayField(field: field, value: value)
        }
    }

    static func lines(
        preferences: FireVaultOverlayPreferences,
        siteName: String,
        address: String,
        accountID: String,
        category: String,
        technicianName: String,
        timestamp: Date
    ) -> [String] {
        resolvedFields(
            preferences: preferences,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category,
            technicianName: technicianName,
            timestamp: timestamp
        ).map(\.value)
    }

    static func lines(
        template: String,
        siteName: String,
        address: String,
        accountID: String,
        technicianName: String,
        timestamp: Date
    ) -> [String] {
        let replacements = [
            "{site}": siteName,
            "{address}": address,
            "{accountID}": accountID,
            "{technician}": technicianName,
            "{date}": timestamp.formatted(.dateTime.month(.abbreviated).day().year()),
            "{time}": timestamp.formatted(date: .omitted, time: .shortened)
        ]
        return template.components(separatedBy: .newlines).compactMap { sourceLine in
            if accountID.isEmpty, sourceLine.contains("{accountID}") { return nil }
            let resolved = replacements.reduce(sourceLine) { partial, replacement in
                partial.replacingOccurrences(of: replacement.key, with: replacement.value)
            }
            let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

struct FireVaultProWordmark: View {
    var fireColor: Color = NativeShellPalette.red
    var vaultColor: Color = .white
    var proColor: Color = .white
    var proBackground: Color = NativeShellPalette.red
    var fontSize: CGFloat = 15
    var proFontSize: CGFloat = 7
    var tracking: CGFloat = 0.9
    var hasBackground = true

    var body: some View {
        VStack(alignment: .leading, spacing: max(2, fontSize * 0.08)) {
            HStack(spacing: 0) {
                Text("FIRE").foregroundStyle(fireColor)
                Text("VAULT").foregroundStyle(vaultColor)
            }
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .tracking(tracking)

            HStack(spacing: max(4, fontSize * 0.18)) {
                Rectangle()
                    .fill(vaultColor.opacity(0.72))
                    .frame(
                        width: max(18, fontSize * 4.75),
                        height: max(0.75, fontSize * 0.045)
                    )

                Text("PRO")
                    .font(.system(size: proFontSize, weight: .black, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(proColor)
            }
        }
        .padding(.horizontal, hasBackground ? max(7, fontSize * 0.42) : 0)
        .padding(.vertical, hasBackground ? max(5, fontSize * 0.3) : 0)
        .background(
            hasBackground ? Color.black : Color.clear,
            in: RoundedRectangle(cornerRadius: max(7, fontSize * 0.42), style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: max(7, fontSize * 0.42), style: .continuous)
                .stroke(hasBackground ? .white.opacity(0.13) : .clear, lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(hasBackground ? 0.28 : 0.14), radius: max(2, fontSize * 0.16), y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FireVault Pro")
    }
}

struct FireVaultProIconBadge: View {
    var size: CGFloat = 30
    var cornerRadius: CGFloat? = nil

    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? size * 0.23
    }

    var body: some View {
        Image("FireVaultLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.42), radius: size * 0.1, y: size * 0.05)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct FireVaultBrandMark: View {
    var body: some View {
        FireVaultProWordmark()
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
        .shadow(color: .gray.opacity(0.78), radius: 2, x: 1, y: 2)
        .shadow(color: .black.opacity(0.34), radius: 4, x: 1, y: 3)
    }
}

struct FireVaultPhotoOverlayView: View {
    let preferences: FireVaultOverlayPreferences
    let technicianName: String
    let siteName: String
    let address: String
    let accountID: String
    let category: String
    let timestamp: Date
    let locationQRCodePayload: String?

    private var accent: Color {
        switch preferences.accentColor {
        case "red": NativeShellPalette.red
        case "amber": NativeShellPalette.amber
        case "white": .white
        default: NativeShellPalette.blue
        }
    }

    private var titleFont: Font { .system(size: 11, weight: .bold, design: .rounded) }
    private var detailFont: Font { .system(size: 9.5, weight: .medium, design: .rounded) }

    private var resolvedFields: [FireVaultResolvedOverlayField] {
        FireVaultOverlayTemplateFormatter.resolvedFields(
            preferences: preferences,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category,
            technicianName: technicianName,
            timestamp: timestamp
        )
    }

    private var informationFields: [FireVaultResolvedOverlayField] { resolvedFields.filter { $0.field != .technician } }
    private var technicianField: FireVaultResolvedOverlayField? { resolvedFields.first { $0.field == .technician } }
    private var glassOpacity: Double { min(0.88, max(0.38, Double(preferences.opacity) / 100)) }
    private var isClearGlass: Bool { preferences.glassStyle == "clear" }
    private var isThickGlass: Bool { preferences.glassThickness == "thick" }
    private var glassCornerRadius: CGFloat { isThickGlass ? 15 : 13 }
    private var glassTintOpacity: Double {
        let styleMultiplier = isClearGlass ? 0.28 : 0.64
        let thicknessBoost = isThickGlass ? 0.13 : 0
        return min(0.82, glassOpacity * styleMultiplier + thicknessBoost)
    }
    private var glassStrokeOpacity: Double { isClearGlass ? (isThickGlass ? 0.48 : 0.34) : (isThickGlass ? 0.52 : 0.36) }
    private var glassLineWidth: CGFloat { isThickGlass ? 1.35 : 0.8 }
    private var glassShadowRadius: CGFloat { isThickGlass ? 12 : 8 }
    private var glassShadowOpacity: Double { isClearGlass ? 0.22 : 0.32 }

    private func panelMetrics(canvasWidth: CGFloat) -> FireVaultOverlayPanelSizing.Metrics {
        FireVaultOverlayPanelSizing.metrics(
            siteName: siteName,
            maximumFieldLength: informationFields.map(\.value.count).max() ?? 0,
            hasTechnician: technicianField != nil,
            hasQRCode: locationQRCodePayload != nil,
            canvasWidth: canvasWidth,
            scale: preferences.scale
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                glassPanel(metrics: panelMetrics(canvasWidth: geometry.size.width))
                    .scaleEffect(preferences.scale)
                    .position(
                        x: geometry.size.width * (0.5 + CGFloat(preferences.positionX) * 0.36),
                        y: geometry.size.height * (0.5 + CGFloat(preferences.positionY) * 0.36)
                    )

                if preferences.showLogo {
                    FireVaultBrandMark()
                        .scaleEffect(preferences.logoScale)
                        .position(
                            x: geometry.size.width * (0.5 + CGFloat(preferences.logoPositionX) * 0.36),
                            y: geometry.size.height * (0.5 + CGFloat(preferences.logoPositionY) * 0.36)
                        )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(["FireVault Pro photo overlay", siteName, address, technicianName, formattedTimestamp].joined(separator: ", "))
    }

    private func glassPanel(metrics: FireVaultOverlayPanelSizing.Metrics) -> some View {
        return HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 1.5) {
                if preferences.showTagline, !preferences.tagline.isEmpty {
                    Text(preferences.tagline)
                        .font(detailFont.bold())
                        .foregroundStyle(accent)
                        .tracking(0.45)
                        .lineLimit(1)
                }

                ForEach(Array(informationFields.enumerated()), id: \.element.id) { index, entry in
                    Text(entry.value)
                        .font(index == 0 ? titleFont : detailFont)
                        .foregroundStyle(index == 0 ? .white : .white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(index == 0 ? 0.66 : 0.78)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: metrics.informationWidth, alignment: .leading)

            if let technicianField {
                Rectangle().fill(.white.opacity(0.23)).frame(width: 1, height: 32)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("TECH")
                        .font(.system(size: 6.5, weight: .bold, design: .rounded))
                        .tracking(0.65)
                        .foregroundStyle(.white.opacity(0.62))
                    Text(technicianField.value)
                        .font(detailFont.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 66, alignment: .trailing)
            }

            if let locationQRCodePayload,
               let qrImage = FireVaultQRCodeRenderer.image(from: locationQRCodePayload, scale: 5) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .padding(3)
                    .background(.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityLabel("Scannable map location QR code")
            }
        }
        .padding(.horizontal, isThickGlass ? 11 : 9)
        .padding(.vertical, isThickGlass ? 9 : 7)
        .frame(width: metrics.panelWidth, alignment: .leading)
        .background {
            ZStack {
                if isThickGlass {
                    RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                } else if isClearGlass {
                    RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }

                RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous)
                    .fill(.black.opacity(glassTintOpacity))

                LinearGradient(
                    colors: [
                        .white.opacity(isClearGlass ? 0.12 : 0.07),
                        .clear,
                        .black.opacity(isClearGlass ? 0.04 : 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: glassCornerRadius, style: .continuous)
                .stroke(.white.opacity(glassStrokeOpacity), lineWidth: glassLineWidth)
        }
        .shadow(color: .black.opacity(glassShadowOpacity), radius: glassShadowRadius, y: isThickGlass ? 6 : 4)
    }

    private var formattedTimestamp: String {
        timestamp.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }
}

struct FireVaultOverlayPreview: View {
    private enum DragTarget {
        case overlay
        case logo
    }

    let preferences: FireVaultOverlayPreferences
    let technicianName: String
    let siteName: String
    let address: String
    let accountID: String
    let category: String

    @State private var editedPreferences: FireVaultOverlayPreferences
    @State private var activeDragTarget: DragTarget?
    @State private var dragTranslation: CGSize = .zero

    init(
        preferences: FireVaultOverlayPreferences,
        technicianName: String,
        siteName: String,
        address: String,
        accountID: String,
        category: String
    ) {
        self.preferences = preferences
        self.technicianName = technicianName
        self.siteName = siteName
        self.address = address
        self.accountID = accountID
        self.category = category
        _editedPreferences = State(initialValue: preferences)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = FireVaultOverlayPreviewGeometry(previewSize: geometry.size)
            let designSize = FireVaultOverlayPreviewGeometry.designSize

            ZStack {
                ZStack {
                    Image("NotifierPanelSample")
                        .resizable()
                        .scaledToFill()
                        .frame(width: designSize.width, height: designSize.height)
                        .clipped()

                    FireVaultPhotoOverlayView(
                        preferences: previewPreferences(size: designSize),
                        technicianName: technicianName,
                        siteName: siteName,
                        address: address,
                        accountID: accountID,
                        category: category,
                        timestamp: .now,
                        locationQRCodePayload: previewPreferences(size: designSize).showLocationQRCode
                            ? FireVaultLocationQRCode.payload(latitude: 43.6177, longitude: -116.1968, name: siteName)
                            : nil
                    )
                    .frame(width: designSize.width, height: designSize.height)
                    .allowsHitTesting(false)
                }
                .frame(width: designSize.width, height: designSize.height)
                .scaleEffect(metrics.scale)
                // scaleEffect changes drawing but not SwiftUI's layout size.
                // Collapse the layout frame to the visible camera canvas so
                // the UIKit hit surface and rendered elements share bounds.
                .frame(
                    width: metrics.scaledDesignSize.width,
                    height: metrics.scaledDesignSize.height
                )
                .allowsHitTesting(false)

                // UIKit owns the pan so the surrounding Form cannot steal a
                // drag that begins directly on the logo or glass panel.
                // Touches elsewhere fail immediately and continue scrolling.
                FireVaultOverlayDragSurface(
                    canBegin: { previewPoint in
                        dragTarget(
                            at: metrics.designPoint(from: previewPoint),
                            size: designSize
                        ) != nil
                    },
                    onBegan: { previewPoint in
                        activeDragTarget = dragTarget(
                            at: metrics.designPoint(from: previewPoint),
                            size: designSize
                        )
                        dragTranslation = .zero
                    },
                    onChanged: { previewTranslation in
                        guard activeDragTarget != nil else { return }
                        dragTranslation = metrics.designTranslation(from: previewTranslation)
                    },
                    onEnded: { previewTranslation in
                        finishDrag(
                            translation: metrics.designTranslation(from: previewTranslation),
                            designSize: designSize
                        )
                    }
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12), lineWidth: 1) }
        .onChange(of: preferences) { _, newValue in
            editedPreferences = constrainedPreferences(newValue, size: FireVaultOverlayPreviewGeometry.designSize)
            activeDragTarget = nil
            dragTranslation = .zero
        }
        .onAppear {
            editedPreferences = constrainedPreferences(editedPreferences, size: FireVaultOverlayPreviewGeometry.designSize)
            stageEdits()
        }
        .accessibilityIdentifier("overlay-interactive-preview")
        .accessibilityHint("Drag the glass overlay or FireVault Pro logo to place it on the photo")
    }

    private func finishDrag(translation: CGSize, designSize: CGSize) {
        defer {
            activeDragTarget = nil
            dragTranslation = .zero
        }

        guard let activeDragTarget else { return }
        let xChange = Double(translation.width / max(designSize.width * 0.36, 1))
        let yChange = Double(translation.height / max(designSize.height * 0.36, 1))

        switch activeDragTarget {
        case .overlay:
            editedPreferences.positionX += xChange
            editedPreferences.positionY += yChange
        case .logo:
            editedPreferences.logoPositionX += xChange
            editedPreferences.logoPositionY += yChange
        }

        editedPreferences = constrainedPreferences(editedPreferences, size: designSize)
        stageEdits()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func dragTarget(at location: CGPoint, size: CGSize) -> DragTarget? {
        let resolvedPanelWidth = estimatedPanelWidth(in: size)
        let overlayRect = CGRect(
            x: overlayCenter(in: size).x - resolvedPanelWidth * editedPreferences.scale / 2,
            y: overlayCenter(in: size).y - estimatedPanelHeight * editedPreferences.scale / 2,
            width: resolvedPanelWidth * editedPreferences.scale,
            height: estimatedPanelHeight * editedPreferences.scale
        )

        let logoRect = CGRect(
            x: logoCenter(in: size).x - 59 * editedPreferences.logoScale,
            y: logoCenter(in: size).y - 22 * editedPreferences.logoScale,
            width: 118 * editedPreferences.logoScale,
            height: 44 * editedPreferences.logoScale
        )

        let isInOverlay = overlayRect.contains(location)
        let isInLogo = editedPreferences.showLogo && logoRect.contains(location)

        if isInOverlay && isInLogo {
            let overlayDistance = normalizedDistance(from: location, to: overlayRect)
            let logoDistance = normalizedDistance(from: location, to: logoRect)
            return overlayDistance <= logoDistance ? .overlay : .logo
        }
        if isInOverlay { return .overlay }
        if isInLogo { return .logo }
        return nil
    }

    private func normalizedDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let x = (point.x - rect.midX) / max(rect.width, 1)
        let y = (point.y - rect.midY) / max(rect.height, 1)
        return sqrt(x * x + y * y)
    }

    private func overlayCenter(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * (0.5 + CGFloat(editedPreferences.positionX) * 0.36),
            y: size.height * (0.5 + CGFloat(editedPreferences.positionY) * 0.36)
        )
    }

    private func logoCenter(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * (0.5 + CGFloat(editedPreferences.logoPositionX) * 0.36),
            y: size.height * (0.5 + CGFloat(editedPreferences.logoPositionY) * 0.36)
        )
    }

    private func estimatedPanelWidth(in size: CGSize) -> CGFloat {
        let fields = FireVaultOverlayTemplateFormatter.resolvedFields(
            preferences: editedPreferences,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category,
            technicianName: technicianName,
            timestamp: .now
        )
        return FireVaultOverlayPanelSizing.metrics(
            siteName: siteName,
            maximumFieldLength: fields
                .filter { $0.field != .technician }
                .map(\.value.count)
                .max() ?? 0,
            hasTechnician: fields.contains { $0.field == .technician },
            canvasWidth: size.width,
            scale: editedPreferences.scale
        ).panelWidth
    }

    private var estimatedPanelHeight: CGFloat {
        let fields = FireVaultOverlayTemplateFormatter.resolvedFields(
            preferences: editedPreferences,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category,
            technicianName: technicianName,
            timestamp: .now
        )
        let visibleLines = fields.filter { $0.field != .technician }.count + (editedPreferences.showTagline ? 1 : 0)
        let baseHeight = max(48, CGFloat(visibleLines) * 12 + 18)
        return editedPreferences.glassThickness == "thick" ? baseHeight + 4 : baseHeight
    }

    private func previewPreferences(size: CGSize) -> FireVaultOverlayPreferences {
        var value = editedPreferences
        guard let activeDragTarget else { return constrainedPreferences(value, size: size) }

        let xChange = Double(dragTranslation.width / max(size.width * 0.36, 1))
        let yChange = Double(dragTranslation.height / max(size.height * 0.36, 1))
        switch activeDragTarget {
        case .overlay:
            value.positionX += xChange
            value.positionY += yChange
        case .logo:
            value.logoPositionX += xChange
            value.logoPositionY += yChange
        }
        return constrainedPreferences(value, size: size)
    }

    private func constrainedPreferences(
        _ value: FireVaultOverlayPreferences,
        size: CGSize
    ) -> FireVaultOverlayPreferences {
        FireVaultOverlayCanvasConstraints.constrained(
            value,
            canvasSize: size,
            technicianName: technicianName,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category
        )
    }

    private func stageEdits() { FireVaultOverlayEditorBridge.stage(editedPreferences) }
}

struct FireVaultOverlayPlacementEditor: View {
    private enum PlacementTarget: Equatable {
        case overlay
        case logo

        var title: String {
            switch self {
            case .overlay: "Overlay Size"
            case .logo: "Logo Size"
            }
        }
    }

    static let landscapeDesignSize = CGSize(
        width: 430.0 * 4.0 / 3.0,
        height: 430
    )

    @Environment(\.dismiss) private var dismiss
    @State private var editedPreferences: FireVaultOverlayPreferences
    @State private var activeDragTarget: PlacementTarget?
    @State private var selectedTarget: PlacementTarget?
    @State private var dragTranslation: CGSize = .zero
    @State private var controlsAreVisible = false
    @State private var instructionsAreVisible = true
    @State private var hasEnteredLandscape = false
    @State private var hasFinished = false
    @State private var hideControlsTask: Task<Void, Never>?

    let technicianName: String
    let siteName: String
    let address: String
    let accountID: String
    let category: String
    let onSave: (FireVaultOverlayPreferences) -> Void

    init(
        preferences: FireVaultOverlayPreferences,
        technicianName: String,
        siteName: String,
        address: String,
        accountID: String,
        category: String,
        onSave: @escaping (FireVaultOverlayPreferences) -> Void
    ) {
        _editedPreferences = State(initialValue: preferences.normalized)
        self.technicianName = technicianName
        self.siteName = siteName
        self.address = address
        self.accountID = accountID
        self.category = category
        self.onSave = onSave
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if isLandscape {
                    landscapeEditor(in: geometry.size)
                } else {
                    rotatePrompt
                }
            }
            .onAppear {
                FireVaultOrientationCoordinator.beginOverlayPlacement()
                editedPreferences = constrainedPreferences(editedPreferences, size: Self.landscapeDesignSize)
                hasEnteredLandscape = isLandscape
            }
            .onChange(of: isLandscape) { _, nowLandscape in
                if nowLandscape {
                    hasEnteredLandscape = true
                } else if hasEnteredLandscape {
                    finishAndDismiss()
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onDisappear {
            hideControlsTask?.cancel()
            FireVaultOrientationCoordinator.finishOverlayPlacement()
        }
    }

    private func landscapeEditor(in availableSize: CGSize) -> some View {
        let designSize = Self.landscapeDesignSize
        let horizontalInset: CGFloat = 18
        let verticalInset: CGFloat = 12
        let scale = min(
            (availableSize.width - horizontalInset * 2) / designSize.width,
            (availableSize.height - verticalInset * 2) / designSize.height
        )
        let canvasSize = CGSize(
            width: designSize.width * scale,
            height: designSize.height * scale
        )

        return ZStack {
            ZStack {
                Image("NotifierPanelSample")
                    .resizable()
                    .scaledToFill()
                    .frame(width: designSize.width, height: designSize.height)
                    .clipped()

                FireVaultPhotoOverlayView(
                    preferences: previewPreferences(in: designSize),
                    technicianName: technicianName,
                    siteName: siteName,
                    address: address,
                    accountID: accountID,
                    category: category,
                    timestamp: .now,
                    locationQRCodePayload: previewPreferences(in: designSize).showLocationQRCode
                        ? FireVaultLocationQRCode.payload(latitude: 43.6177, longitude: -116.1968, name: siteName)
                        : nil
                )
                .frame(width: designSize.width, height: designSize.height)
            }
            .frame(width: designSize.width, height: designSize.height)
            .scaleEffect(scale)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .allowsHitTesting(false)

            FireVaultOverlayDragSurface(
                canBegin: { visiblePoint in
                    placementTarget(
                        at: CGPoint(
                            x: visiblePoint.x / max(scale, 0.0001),
                            y: visiblePoint.y / max(scale, 0.0001)
                        ),
                        size: designSize
                    ) != nil
                },
                onBegan: { visiblePoint in
                    let target = placementTarget(
                        at: CGPoint(
                            x: visiblePoint.x / max(scale, 0.0001),
                            y: visiblePoint.y / max(scale, 0.0001)
                        ),
                        size: designSize
                    )
                    activeDragTarget = target
                    selectedTarget = target
                    dragTranslation = .zero
                    instructionsAreVisible = false
                    showControls()
                },
                onChanged: { visibleTranslation in
                    guard activeDragTarget != nil else { return }
                    dragTranslation = CGSize(
                        width: visibleTranslation.width / max(scale, 0.0001),
                        height: visibleTranslation.height / max(scale, 0.0001)
                    )
                },
                onEnded: { visibleTranslation in
                    finishDrag(
                        translation: CGSize(
                            width: visibleTranslation.width / max(scale, 0.0001),
                            height: visibleTranslation.height / max(scale, 0.0001)
                        ),
                        designSize: designSize
                    )
                }
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .overlay {
            if instructionsAreVisible {
                instructionPill
                    .transition(.opacity)
            }
        }
        .overlay {
            if controlsAreVisible, let selectedTarget {
                horizontalSizeControl(for: selectedTarget)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsAreVisible)
        .animation(.easeOut(duration: 0.2), value: instructionsAreVisible)
    }

    private var instructionPill: some View {
        Text("Drag the logo or overlay • Rotate to portrait to save")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.7), in: Capsule())
    }

    private var rotatePrompt: some View {
        VStack(spacing: 18) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(NativeShellPalette.blue)
            Text(hasEnteredLandscape ? "Saving placement…" : "Rotate iPhone to Landscape")
                .font(.title2.bold())
                .foregroundStyle(.white)
            if !hasEnteredLandscape {
                Text("Use the full-width camera preview to position the overlay and FireVault Pro logo.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: 340)
            }
        }
        .padding(30)
    }

    private func horizontalSizeControl(for target: PlacementTarget) -> some View {
        HStack(spacing: 12) {
            Text(target.title)
                .font(.caption.bold())
                .foregroundStyle(.white)
            Slider(
                value: sizeBinding(for: target),
                in: target == .overlay ? 0.45...1.35 : 0.45...1.8,
                step: 0.05,
                onEditingChanged: { isEditing in
                    if isEditing {
                        showControls()
                    } else {
                        scheduleControlsHide()
                    }
                }
            )
            .tint(NativeShellPalette.blue)
            .frame(width: 220)

            Text("\(Int((sizeValue(for: target) * 100).rounded()))%")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.78), in: Capsule())
    }

    private func sizeBinding(for target: PlacementTarget) -> Binding<Double> {
        Binding(
            get: { sizeValue(for: target) },
            set: { newValue in
                switch target {
                case .overlay: editedPreferences.scale = newValue
                case .logo: editedPreferences.logoScale = newValue
                }
                editedPreferences = constrainedPreferences(editedPreferences, size: Self.landscapeDesignSize)
                showControls()
            }
        )
    }

    private func sizeValue(for target: PlacementTarget) -> Double {
        switch target {
        case .overlay: editedPreferences.scale
        case .logo: editedPreferences.logoScale
        }
    }

    private func placementTarget(at point: CGPoint, size: CGSize) -> PlacementTarget? {
        let overlaySize = CGSize(
            width: estimatedPanelWidth(in: size) * editedPreferences.scale,
            height: estimatedPanelHeight * editedPreferences.scale
        )
        let overlayRect = CGRect(
            x: overlayCenter(in: size).x - overlaySize.width / 2,
            y: overlayCenter(in: size).y - overlaySize.height / 2,
            width: overlaySize.width,
            height: overlaySize.height
        ).insetBy(dx: -12, dy: -12)

        let logoRect = CGRect(
            x: logoCenter(in: size).x - 59 * editedPreferences.logoScale,
            y: logoCenter(in: size).y - 22 * editedPreferences.logoScale,
            width: 118 * editedPreferences.logoScale,
            height: 44 * editedPreferences.logoScale
        ).insetBy(dx: -12, dy: -12)

        if editedPreferences.showLogo, logoRect.contains(point) { return .logo }
        if overlayRect.contains(point) { return .overlay }
        return nil
    }

    private func finishDrag(translation: CGSize, designSize: CGSize) {
        defer {
            activeDragTarget = nil
            dragTranslation = .zero
            scheduleControlsHide()
        }
        guard let activeDragTarget else { return }

        let xChange = Double(translation.width / max(designSize.width * 0.36, 1))
        let yChange = Double(translation.height / max(designSize.height * 0.36, 1))
        switch activeDragTarget {
        case .overlay:
            editedPreferences.positionX += xChange
            editedPreferences.positionY += yChange
        case .logo:
            editedPreferences.logoPositionX += xChange
            editedPreferences.logoPositionY += yChange
        }
        editedPreferences = constrainedPreferences(editedPreferences, size: designSize)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func previewPreferences(in size: CGSize) -> FireVaultOverlayPreferences {
        var value = editedPreferences
        guard let activeDragTarget else { return constrainedPreferences(value, size: size) }

        let xChange = Double(dragTranslation.width / max(size.width * 0.36, 1))
        let yChange = Double(dragTranslation.height / max(size.height * 0.36, 1))
        switch activeDragTarget {
        case .overlay:
            value.positionX += xChange
            value.positionY += yChange
        case .logo:
            value.logoPositionX += xChange
            value.logoPositionY += yChange
        }
        return constrainedPreferences(value, size: size)
    }

    private func constrainedPreferences(
        _ value: FireVaultOverlayPreferences,
        size: CGSize
    ) -> FireVaultOverlayPreferences {
        FireVaultOverlayCanvasConstraints.constrained(
            value,
            canvasSize: size,
            technicianName: technicianName,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category
        )
    }

    private func overlayCenter(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * (0.5 + CGFloat(editedPreferences.positionX) * 0.36),
            y: size.height * (0.5 + CGFloat(editedPreferences.positionY) * 0.36)
        )
    }

    private func logoCenter(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * (0.5 + CGFloat(editedPreferences.logoPositionX) * 0.36),
            y: size.height * (0.5 + CGFloat(editedPreferences.logoPositionY) * 0.36)
        )
    }

    private func estimatedPanelWidth(in size: CGSize) -> CGFloat {
        let fields = resolvedFields
        return FireVaultOverlayPanelSizing.metrics(
            siteName: siteName,
            maximumFieldLength: fields
                .filter { $0.field != .technician }
                .map(\.value.count)
                .max() ?? 0,
            hasTechnician: fields.contains { $0.field == .technician },
            canvasWidth: size.width,
            scale: editedPreferences.scale
        ).panelWidth
    }

    private var estimatedPanelHeight: CGFloat {
        let visibleLines = resolvedFields.filter { $0.field != .technician }.count
            + (editedPreferences.showTagline ? 1 : 0)
        let baseHeight = max(48, CGFloat(visibleLines) * 12 + 18)
        return editedPreferences.glassThickness == "thick" ? baseHeight + 4 : baseHeight
    }

    private var resolvedFields: [FireVaultResolvedOverlayField] {
        FireVaultOverlayTemplateFormatter.resolvedFields(
            preferences: editedPreferences,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category,
            technicianName: technicianName,
            timestamp: .now
        )
    }

    private func showControls() {
        hideControlsTask?.cancel()
        controlsAreVisible = true
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            controlsAreVisible = false
        }
    }

    private func finishAndDismiss() {
        guard !hasFinished else { return }
        hasFinished = true
        hideControlsTask?.cancel()
        onSave(editedPreferences.normalized)
        FireVaultOrientationCoordinator.finishOverlayPlacement()
        dismiss()
    }
}

@MainActor
enum FireVaultPhotoOverlayRenderer {
    static func render(
        image: UIImage,
        preferences: FireVaultOverlayPreferences,
        technicianName: String,
        account: FireVaultWorkspaceAccount,
        timestamp: Date
    ) -> UIImage {
        let pixelWidth = max(image.size.width, 1)
        let outputScale = max(pixelWidth / 430, 1)
        let logicalSize = CGSize(width: image.size.width / outputScale, height: image.size.height / outputScale)
        let adjustedPreferences = FireVaultOverlayCanvasConstraints.constrained(
            preferences,
            canvasSize: logicalSize,
            technicianName: technicianName,
            siteName: account.name,
            address: account.address,
            accountID: account.accountId,
            category: account.category
        )
        let content = ZStack {
            Image(uiImage: image).resizable().scaledToFill().frame(width: logicalSize.width, height: logicalSize.height).clipped()
            FireVaultPhotoOverlayView(
                preferences: adjustedPreferences,
                technicianName: technicianName,
                siteName: account.name,
                address: account.address,
                accountID: account.accountId,
                category: account.category,
                timestamp: timestamp,
                locationQRCodePayload: adjustedPreferences.showLocationQRCode
                    ? FireVaultLocationQRCode.payload(for: account)
                    : nil
            ).frame(width: logicalSize.width, height: logicalSize.height)
        }.frame(width: logicalSize.width, height: logicalSize.height)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(logicalSize)
        renderer.scale = outputScale
        renderer.isOpaque = true
        return renderer.uiImage ?? image
    }
}

struct NativeCameraCaptureView: UIViewControllerRepresentable {
    let preferences: FireVaultOverlayPreferences
    let technicianName: String
    let account: FireVaultWorkspaceAccount?
    var startsInVideoMode = false
    let onCapture: (UIImage) -> Void
    let onVideoCapture: (URL) -> Void
    let onCancel: () -> Void
    func makeUIViewController(context: Context) -> FireVaultCameraViewController {
        FireVaultCameraViewController(
            preferences: preferences,
            technicianName: technicianName,
            account: account,
            startsInVideoMode: startsInVideoMode,
            onCapture: onCapture,
            onVideoCapture: onVideoCapture,
            onCancel: onCancel
        )
    }
    func updateUIViewController(_ uiViewController: FireVaultCameraViewController, context: Context) {}
}

public enum FireVaultVideoDisplayGeometry {
    public static func displaySize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    public static func aspectRatio(for url: URL) async -> CGFloat? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform) else { return nil }
        let size = displaySize(naturalSize: naturalSize, preferredTransform: preferredTransform)
        guard size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }
}

struct FireVaultAspectCorrectVideoPlayer: View {
    let url: URL
    var maximumHeight: CGFloat? = nil
    @State private var displayAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .aspectRatio(displayAspectRatio, contentMode: .fit)
            .frame(maxHeight: maximumHeight)
            .task(id: url) {
                if let resolved = await FireVaultVideoDisplayGeometry.aspectRatio(for: url) {
                    displayAspectRatio = resolved
                }
            }
    }
}

private struct FireVaultCameraLiveOverlay: View {
    let preferences: FireVaultOverlayPreferences
    let technicianName: String
    let account: FireVaultWorkspaceAccount

    var body: some View {
        GeometryReader { geometry in
            let adjusted = FireVaultOverlayCanvasConstraints.constrained(
                preferences,
                canvasSize: geometry.size,
                technicianName: technicianName,
                siteName: account.name,
                address: account.address,
                accountID: account.accountId,
                category: account.category
            )
            FireVaultPhotoOverlayView(
                preferences: adjusted,
                technicianName: technicianName,
                siteName: account.name,
                address: account.address,
                accountID: account.accountId,
                category: account.category,
                timestamp: .now,
                locationQRCodePayload: adjusted.showLocationQRCode
                    ? FireVaultLocationQRCode.payload(for: account)
                    : nil
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

final class FireVaultCameraViewController: UIViewController,
    AVCapturePhotoCaptureDelegate,
    AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "us.bannerman.firevault.camera")
    private let topControls = UIView()
    private let portraitPreviewArea = UILayoutGuide()
    private let landscapePreviewArea = UILayoutGuide()
    private let photoCanvas = UIView()
    private let bottomControls = UIView()
    private let landscapeControls = UIView()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let onCapture: (UIImage) -> Void
    private let onVideoCapture: (URL) -> Void
    private let startsInVideoMode: Bool
    private let onCancel: () -> Void
    private var overlayHost: UIHostingController<AnyView>?
    private var configured = false
    private var videoInput: AVCaptureDeviceInput?
    private var activeCamera: AVCaptureDevice?
    private var availableLenses: [(title: String, device: AVCaptureDevice)] = []
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    private var videoTorchEnabled = false
    private var beginningZoomFactor: CGFloat = 1
    private var usesLandscapeLayout: Bool?
    private var portraitConstraints: [NSLayoutConstraint] = []
    private var landscapeConstraints: [NSLayoutConstraint] = []
    private let cancelButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let zoomSlider = UISlider()
    private let lensControl = UISegmentedControl()
    private let shutter = UIButton(type: .system)

    init(
        preferences: FireVaultOverlayPreferences,
        technicianName: String,
        account: FireVaultWorkspaceAccount?,
        startsInVideoMode: Bool,
        onCapture: @escaping (UIImage) -> Void,
        onVideoCapture: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onCapture = onCapture
        self.onVideoCapture = onVideoCapture
        self.startsInVideoMode = startsInVideoMode
        self.onCancel = onCancel
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(nibName: nil, bundle: nil)

        if let account {
            let overlay = FireVaultCameraLiveOverlay(
                preferences: preferences,
                technicianName: technicianName,
                account: account
            )
            .allowsHitTesting(false)
            let host = UIHostingController(rootView: AnyView(overlay))
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            overlayHost = host
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addLayoutGuide(portraitPreviewArea)
        view.addLayoutGuide(landscapePreviewArea)

        topControls.backgroundColor = .black
        topControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topControls)

        photoCanvas.backgroundColor = .black
        photoCanvas.clipsToBounds = true
        photoCanvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(photoCanvas)
        previewLayer.videoGravity = .resizeAspectFill
        photoCanvas.layer.addSublayer(previewLayer)
        photoCanvas.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:))))

        bottomControls.backgroundColor = .black
        bottomControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomControls)

        landscapeControls.backgroundColor = .black
        landscapeControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(landscapeControls)

        if let overlayView = overlayHost?.view {
            photoCanvas.addSubview(overlayView)
        }

        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.tintColor = .white
        cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        cancelButton.layer.cornerRadius = 22
        cancelButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        cancelButton.accessibilityLabel = startsInVideoMode ? "Cancel video" : "Cancel photo"
        view.addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        shutter.layer.cornerRadius = 34
        shutter.layer.borderWidth = 4
        shutter.layer.borderColor = UIColor.white.withAlphaComponent(0.42).cgColor
        shutter.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(shutter)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        updateShutterAppearance()

        configureCameraControls()
        configureLayoutConstraints()
        updateControlLayout(for: view.bounds.size)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        FireVaultOrientationCoordinator.beginCameraCapture()
        requestCameraAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        FireVaultOrientationCoordinator.finishCameraCapture()
        turnOffVideoTorch()
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        updateControlLayout(for: size)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
            self?.updateVideoRotation()
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateControlLayout(for: view.bounds.size)
        previewLayer.frame = photoCanvas.bounds
        overlayHost?.view.frame = photoCanvas.bounds
        updateVideoRotation()
    }

    private func configureCameraControls() {
        let candidates: [(String, AVCaptureDevice.DeviceType)] = [
            ("0.5×", .builtInUltraWideCamera),
            ("1×", .builtInWideAngleCamera),
            ("2×", .builtInTelephotoCamera)
        ]
        availableLenses = candidates.compactMap { title, type in
            AVCaptureDevice.default(type, for: .video, position: .back).map { (title, $0) }
        }
        for lens in availableLenses { lensControl.insertSegment(withTitle: lens.title, at: lensControl.numberOfSegments, animated: false) }
        lensControl.selectedSegmentIndex = availableLenses.firstIndex { $0.title == "1×" } ?? 0
        lensControl.selectedSegmentTintColor = .white
        lensControl.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        lensControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        lensControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        lensControl.addTarget(self, action: #selector(changeLens(_:)), for: .valueChanged)
        lensControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(lensControl)

        zoomSlider.minimumValue = 1
        zoomSlider.maximumValue = 5
        zoomSlider.value = 1
        zoomSlider.minimumTrackTintColor = .white
        zoomSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.34)
        zoomSlider.thumbTintColor = .white
        zoomSlider.addTarget(self, action: #selector(changeZoom(_:)), for: .valueChanged)
        zoomSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomSlider)

        flashButton.tintColor = .white
        flashButton.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        flashButton.layer.cornerRadius = 22
        flashButton.addTarget(self, action: #selector(changeFlashMode), for: .touchUpInside)
        flashButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(flashButton)
        updateFlashButton()
    }

    private func configureLayoutConstraints() {
        NSLayoutConstraint.activate([
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44),
            shutter.widthAnchor.constraint(equalToConstant: 68),
            shutter.heightAnchor.constraint(equalToConstant: 68)
        ])

        let portraitPreviewAspect = photoCanvas.widthAnchor.constraint(
            equalTo: photoCanvas.heightAnchor,
            multiplier: startsInVideoMode ? 9.0 / 16.0 : 3.0 / 4.0
        )
        let portraitPreviewWidth = photoCanvas.widthAnchor.constraint(equalTo: portraitPreviewArea.widthAnchor)
        portraitPreviewWidth.priority = .init(999)
        let portraitPreviewHeight = photoCanvas.heightAnchor.constraint(equalTo: portraitPreviewArea.heightAnchor)
        portraitPreviewHeight.priority = .init(998)

        portraitConstraints = [
            topControls.topAnchor.constraint(equalTo: view.topAnchor),
            topControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            bottomControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomControls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomControls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -84),
            portraitPreviewArea.topAnchor.constraint(equalTo: topControls.bottomAnchor),
            portraitPreviewArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            portraitPreviewArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            portraitPreviewArea.bottomAnchor.constraint(equalTo: bottomControls.topAnchor),
            photoCanvas.centerXAnchor.constraint(equalTo: portraitPreviewArea.centerXAnchor),
            photoCanvas.centerYAnchor.constraint(equalTo: portraitPreviewArea.centerYAnchor),
            photoCanvas.widthAnchor.constraint(lessThanOrEqualTo: portraitPreviewArea.widthAnchor),
            photoCanvas.heightAnchor.constraint(lessThanOrEqualTo: portraitPreviewArea.heightAnchor),
            portraitPreviewAspect,
            portraitPreviewWidth,
            portraitPreviewHeight,
            cancelButton.leadingAnchor.constraint(equalTo: topControls.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.bottomAnchor.constraint(equalTo: topControls.bottomAnchor, constant: -8),
            flashButton.trailingAnchor.constraint(equalTo: topControls.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            flashButton.bottomAnchor.constraint(equalTo: topControls.bottomAnchor, constant: -8),
            shutter.trailingAnchor.constraint(equalTo: bottomControls.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            shutter.centerYAnchor.constraint(equalTo: bottomControls.safeAreaLayoutGuide.centerYAnchor),
            lensControl.leadingAnchor.constraint(equalTo: bottomControls.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            lensControl.centerYAnchor.constraint(equalTo: bottomControls.safeAreaLayoutGuide.centerYAnchor),
            lensControl.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            zoomSlider.leadingAnchor.constraint(equalTo: lensControl.trailingAnchor, constant: 14),
            zoomSlider.trailingAnchor.constraint(equalTo: shutter.leadingAnchor, constant: -16),
            zoomSlider.centerYAnchor.constraint(equalTo: bottomControls.safeAreaLayoutGuide.centerYAnchor),
            zoomSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ]

        let landscapePreviewAspect = photoCanvas.widthAnchor.constraint(
            equalTo: photoCanvas.heightAnchor,
            multiplier: startsInVideoMode ? 16.0 / 9.0 : 4.0 / 3.0
        )
        let landscapePreviewWidth = photoCanvas.widthAnchor.constraint(equalTo: landscapePreviewArea.widthAnchor)
        landscapePreviewWidth.priority = .init(999)
        let landscapePreviewHeight = photoCanvas.heightAnchor.constraint(equalTo: landscapePreviewArea.heightAnchor)
        landscapePreviewHeight.priority = .init(998)
        let landscapeControlsWidth = landscapeControls.widthAnchor.constraint(equalToConstant: 250)
        landscapeControlsWidth.priority = .init(999)

        landscapeConstraints = [
            landscapePreviewArea.topAnchor.constraint(equalTo: view.topAnchor),
            landscapePreviewArea.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            landscapePreviewArea.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            landscapePreviewArea.trailingAnchor.constraint(equalTo: landscapeControls.leadingAnchor),
            photoCanvas.centerXAnchor.constraint(equalTo: landscapePreviewArea.centerXAnchor),
            photoCanvas.centerYAnchor.constraint(equalTo: landscapePreviewArea.centerYAnchor),
            photoCanvas.widthAnchor.constraint(lessThanOrEqualTo: landscapePreviewArea.widthAnchor),
            photoCanvas.heightAnchor.constraint(lessThanOrEqualTo: landscapePreviewArea.heightAnchor),
            landscapePreviewAspect,
            landscapePreviewWidth,
            landscapePreviewHeight,
            landscapeControls.topAnchor.constraint(equalTo: view.topAnchor),
            landscapeControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            landscapeControls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            landscapeControlsWidth,
            landscapeControls.widthAnchor.constraint(greaterThanOrEqualToConstant: 210),
            landscapeControls.widthAnchor.constraint(lessThanOrEqualToConstant: 330),
            cancelButton.leadingAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.topAnchor, constant: 14),
            flashButton.trailingAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            flashButton.topAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.topAnchor, constant: 14),
            lensControl.leadingAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            lensControl.trailingAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            lensControl.topAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 24),
            zoomSlider.leadingAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            zoomSlider.trailingAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            zoomSlider.topAnchor.constraint(equalTo: lensControl.bottomAnchor, constant: 18),
            shutter.centerXAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.centerXAnchor),
            shutter.bottomAnchor.constraint(equalTo: landscapeControls.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ]
    }

    private func updateControlLayout(for size: CGSize) {
        let useLandscape = size.width > size.height
        guard usesLandscapeLayout != useLandscape else { return }
        usesLandscapeLayout = useLandscape

        NSLayoutConstraint.deactivate(useLandscape ? portraitConstraints : landscapeConstraints)
        NSLayoutConstraint.activate(useLandscape ? landscapeConstraints : portraitConstraints)
        topControls.isHidden = useLandscape
        bottomControls.isHidden = useLandscape
        landscapeControls.isHidden = !useLandscape
    }

    private func preferredCamera() -> AVCaptureDevice? {
        availableLenses.first(where: { $0.title == "1×" })?.device
            ?? availableLenses.first?.device
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    @objc private func changeLens(_ sender: UISegmentedControl) {
        guard availableLenses.indices.contains(sender.selectedSegmentIndex) else { return }
        let device = availableLenses[sender.selectedSegmentIndex].device
        sessionQueue.async { [weak self] in
            guard let self, let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            if let videoInput { session.removeInput(videoInput) }
            if session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
                activeCamera = device
                videoTorchEnabled = false
            }
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.updateZoomControls()
                self?.updateFlashButton()
            }
        }
    }

    @objc private func changeZoom(_ sender: UISlider) {
        setZoomFactor(CGFloat(sender.value))
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { beginningZoomFactor = activeCamera?.videoZoomFactor ?? 1 }
        let proposed = beginningZoomFactor * gesture.scale
        setZoomFactor(proposed)
        if gesture.state == .ended || gesture.state == .cancelled { beginningZoomFactor = activeCamera?.videoZoomFactor ?? 1 }
    }

    private func setZoomFactor(_ factor: CGFloat) {
        guard let camera = activeCamera else { return }
        let resolved = min(max(factor, camera.minAvailableVideoZoomFactor), min(camera.maxAvailableVideoZoomFactor, 5))
        do {
            try camera.lockForConfiguration()
            camera.videoZoomFactor = resolved
            camera.unlockForConfiguration()
            zoomSlider.value = Float(resolved)
        } catch { }
    }

    private func updateZoomControls() {
        guard let camera = activeCamera else { return }
        zoomSlider.minimumValue = Float(camera.minAvailableVideoZoomFactor)
        zoomSlider.maximumValue = Float(min(camera.maxAvailableVideoZoomFactor, 5))
        zoomSlider.value = Float(camera.videoZoomFactor)
    }

    @objc private func changeFlashMode() {
        if startsInVideoMode {
            toggleVideoTorch()
            return
        }

        flashMode = switch flashMode {
        case .off: .auto
        case .auto: .on
        case .on: .off
        @unknown default: .auto
        }
        updateFlashButton()
    }

    private func updateFlashButton() {
        if startsInVideoMode {
            let torchAvailable = activeCamera?.hasTorch == true
            flashButton.isEnabled = torchAvailable
            flashButton.alpha = torchAvailable ? 1 : 0.42
            flashButton.setImage(
                UIImage(systemName: videoTorchEnabled ? "bolt.fill" : "bolt.slash.fill"),
                for: .normal
            )
            flashButton.accessibilityLabel = torchAvailable
                ? "Video light \(videoTorchEnabled ? "on" : "off")"
                : "Video light unavailable"
            return
        }

        let flashAvailable = activeCamera?.hasFlash ?? true
        flashButton.isEnabled = flashAvailable
        flashButton.alpha = flashAvailable ? 1 : 0.42
        let symbol = switch flashMode {
        case .off: "bolt.slash.fill"
        case .auto: "bolt.badge.automatic.fill"
        case .on: "bolt.fill"
        @unknown default: "bolt.badge.automatic.fill"
        }
        flashButton.setImage(UIImage(systemName: symbol), for: .normal)
        flashButton.accessibilityLabel = "Flash \(flashMode == .off ? "off" : flashMode == .on ? "on" : "automatic")"
    }

    private func toggleVideoTorch() {
        guard let camera = activeCamera,
              camera.hasTorch,
              camera.isTorchModeSupported(.on) else {
            videoTorchEnabled = false
            updateFlashButton()
            return
        }

        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            if videoTorchEnabled {
                camera.torchMode = .off
                videoTorchEnabled = false
            } else {
                try camera.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                videoTorchEnabled = true
            }
        } catch {
            videoTorchEnabled = false
        }
        updateFlashButton()
    }

    private func turnOffVideoTorch() {
        guard videoTorchEnabled, let camera = activeCamera, camera.hasTorch else { return }
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            camera.torchMode = .off
        } catch { }
        videoTorchEnabled = false
        updateFlashButton()
    }

    private func requestCameraAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            requestMicrophoneAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else {
                    DispatchQueue.main.async { self?.onCancel() }
                    return
                }
                self?.requestMicrophoneAndStart()
            }
        default:
            onCancel()
        }
    }

    private func requestMicrophoneAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                self?.configureAndStart()
            }
        default:
            configureAndStart()
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !configured {
                session.beginConfiguration()
                let preferredPreset: AVCaptureSession.Preset = startsInVideoMode
                    ? .hd1920x1080
                    : .photo
                session.sessionPreset = session.canSetSessionPreset(preferredPreset)
                    ? preferredPreset
                    : .high
                defer { session.commitConfiguration() }
                guard let camera = preferredCamera(),
                      let input = try? AVCaptureDeviceInput(device: camera),
                      session.canAddInput(input),
                      session.canAddOutput(photoOutput),
                      session.canAddOutput(movieOutput) else { return }
                session.addInput(input)
                session.addOutput(photoOutput)
                session.addOutput(movieOutput)
                if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                   let microphone = AVCaptureDevice.default(for: .audio),
                   let audioInput = try? AVCaptureDeviceInput(device: microphone),
                   session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
                videoInput = input
                activeCamera = camera
                configured = true
                DispatchQueue.main.async { [weak self] in
                    self?.updateZoomControls()
                    self?.updateFlashButton()
                }
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                view.setNeedsLayout()
                view.layoutIfNeeded()
                updateVideoRotation()
            }
        }
    }

    @objc private func cancelCapture() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        } else {
            onCancel()
        }
    }

    private func updateShutterAppearance() {
        shutter.setImage(UIImage(systemName: startsInVideoMode ? "video.fill" : "camera.fill"), for: .normal)
        shutter.backgroundColor = startsInVideoMode ? .systemRed : .white
        shutter.tintColor = startsInVideoMode ? .white : .black
        shutter.accessibilityLabel = startsInVideoMode ? "Record video" : "Take photo"
    }

    @objc private func capturePhoto() {
        if startsInVideoMode {
            toggleVideoRecording()
            return
        }
        updateVideoRotation()
        let settings = AVCapturePhotoSettings()
        settings.flashMode = photoOutput.supportedFlashModes.contains(flashMode) ? flashMode : .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func updateVideoRotation() {
        let angle: CGFloat = switch view.window?.windowScene?.effectiveGeometry.interfaceOrientation {
        case .landscapeLeft: 180
        case .landscapeRight: 0
        case .portraitUpsideDown: 270
        default: 90
        }
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        if let connection = movieOutput.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func toggleVideoRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
            return
        }
        updateVideoRotation()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FireVault-Capture-\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        lensControl.isEnabled = false
        shutter.setImage(UIImage(systemName: "stop.fill"), for: .normal)
        shutter.accessibilityLabel = "Stop recording"
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            onCancel()
            return
        }
        onCapture(image)
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        lensControl.isEnabled = true
        updateShutterAppearance()
        guard error == nil else {
            try? FileManager.default.removeItem(at: outputFileURL)
            onCancel()
            return
        }
        onVideoCapture(outputFileURL)
    }
}

struct NativeDocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onFailure: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onCancel: onCancel, onFailure: onFailure) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void; let onCancel: () -> Void; let onFailure: (String) -> Void
        init(onScan: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
            self.onScan = onScan; self.onCancel = onCancel; self.onFailure = onFailure
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onScan((0..<scan.pageCount).map(scan.imageOfPage))
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFailure(error.localizedDescription) }
    }
}
