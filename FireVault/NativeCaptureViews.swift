//
//  NativeCaptureViews.swift
//  FireVault
//
//  Native camera, document scanning, and field-photo overlay support.
//

import SwiftUI
import UIKit
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
        HStack(spacing: 6) {
            FireVaultProIconBadge(size: 30)

            FireVaultProWordmark()
        }
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
            editedPreferences = newValue
            activeDragTarget = nil
            dragTranslation = .zero
        }
        .onAppear { stageEdits() }
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

        editedPreferences = editedPreferences.normalized
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
        guard let activeDragTarget else { return value.normalized }

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
        return value.normalized
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
                editedPreferences = editedPreferences.normalized
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
        editedPreferences = editedPreferences.normalized
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func previewPreferences(in size: CGSize) -> FireVaultOverlayPreferences {
        var value = editedPreferences
        guard let activeDragTarget else { return value.normalized }

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
        return value.normalized
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
        let content = ZStack {
            Image(uiImage: image).resizable().scaledToFill().frame(width: logicalSize.width, height: logicalSize.height).clipped()
            FireVaultPhotoOverlayView(
                preferences: preferences,
                technicianName: technicianName,
                siteName: account.name,
                address: account.address,
                accountID: account.accountId,
                category: account.category,
                timestamp: timestamp,
                locationQRCodePayload: preferences.showLocationQRCode
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
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage) -> Void; let onCancel: () -> Void
        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) { self.onCapture = onCapture; self.onCancel = onCancel }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { onCancel(); return }
            onCapture(image)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
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
