//
//  NativeCaptureViews.swift
//  FireVault
//
//  Native camera, document scanning, and field-photo overlay support.
//

import SwiftUI
import UIKit
import VisionKit

struct FireVaultResolvedOverlayField: Identifiable, Equatable {
    let field: FireVaultOverlayField
    let value: String
    var id: String { field.rawValue }
}

struct FireVaultOverlayPreviewGeometry {
    /// UIImagePickerController's native still-photo canvas is 3:4 in portrait.
    /// Keep the logical width at 430 so the preview uses the same typography
    /// scale as FireVaultPhotoOverlayRenderer.
    static let designSize = CGSize(width: 430, height: 430.0 * 4.0 / 3.0)

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

struct FireVaultBrandMark: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("FireVaultLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            HStack(spacing: 0) {
                Text("FIRE").foregroundStyle(NativeShellPalette.red)
                Text("VAULT").foregroundStyle(.white)
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .tracking(0.9)
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

    private var informationWidth: CGFloat {
        let longest = max(siteName.count, informationFields.map(\.value.count).max() ?? 0)
        return min(300, max(145, CGFloat(longest) * 5.9))
    }

    private var panelWidth: CGFloat {
        let technicianAllowance: CGFloat = technicianField == nil ? 0 : 76
        return min(410, informationWidth + technicianAllowance + 28)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                glassPanel
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
        .accessibilityLabel(["FireVault photo overlay", siteName, address, technicianName, formattedTimestamp].joined(separator: ", "))
    }

    private var glassPanel: some View {
        HStack(alignment: .bottom, spacing: 8) {
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
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: informationWidth, alignment: .leading)

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
        }
        .padding(.horizontal, isThickGlass ? 11 : 9)
        .padding(.vertical, isThickGlass ? 9 : 7)
        .frame(width: panelWidth, alignment: .leading)
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
                        timestamp: .now
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
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12), lineWidth: 1) }
        .onChange(of: preferences) { _, newValue in
            editedPreferences = newValue
            activeDragTarget = nil
            dragTranslation = .zero
        }
        .onAppear { stageEdits() }
        .accessibilityIdentifier("overlay-interactive-preview")
        .accessibilityHint("Drag the glass overlay or FireVault logo to place it on the photo")
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
        let overlayRect = CGRect(
            x: overlayCenter(in: size).x - estimatedPanelWidth * editedPreferences.scale / 2,
            y: overlayCenter(in: size).y - estimatedPanelHeight * editedPreferences.scale / 2,
            width: estimatedPanelWidth * editedPreferences.scale,
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

    private var estimatedPanelWidth: CGFloat {
        let fields = FireVaultOverlayTemplateFormatter.resolvedFields(
            preferences: editedPreferences,
            siteName: siteName,
            address: address,
            accountID: accountID,
            category: category,
            technicianName: technicianName,
            timestamp: .now
        )
        let longest = max(siteName.count, fields.filter { $0.field != .technician }.map(\.value.count).max() ?? 0)
        let informationWidth = min(300, max(145, CGFloat(longest) * 5.9))
        let hasTechnician = fields.contains { $0.field == .technician }
        return min(410, informationWidth + (hasTechnician ? 76 : 0) + 28)
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
                    timestamp: .now
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
        .overlay(alignment: .top) {
            instructionPill
                .padding(.top, 10)
        }
        .overlay(alignment: .leading) {
            if controlsAreVisible, let selectedTarget {
                verticalSizeControl(for: selectedTarget)
                    .padding(.leading, 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                finishAndDismiss()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(12)
        }
        .animation(.easeInOut(duration: 0.2), value: controlsAreVisible)
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
                Text("Use the full-width camera preview to position the overlay and FireVault logo.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: 340)
            }
        }
        .padding(30)
    }

    private func verticalSizeControl(for target: PlacementTarget) -> some View {
        VStack(spacing: 8) {
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
            .frame(width: 180)
            .rotationEffect(.degrees(-90))
            .frame(width: 44, height: 180)

            Text("\(Int((sizeValue(for: target) * 100).rounded()))%")
                .font(.caption.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 16))
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
            width: estimatedPanelWidth * editedPreferences.scale,
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

    private var estimatedPanelWidth: CGFloat {
        let fields = resolvedFields
        let longest = max(
            siteName.count,
            fields.filter { $0.field != .technician }.map(\.value.count).max() ?? 0
        )
        let informationWidth = min(300, max(145, CGFloat(longest) * 5.9))
        return min(
            410,
            informationWidth + (fields.contains { $0.field == .technician } ? 76 : 0) + 28
        )
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
                timestamp: timestamp
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
