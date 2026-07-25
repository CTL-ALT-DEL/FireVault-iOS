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
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.28), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.38), radius: 6, y: 3)
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

    private var titleFont: Font {
        switch preferences.fontSize {
        case "small": .system(size: 9.5, weight: .bold, design: .rounded)
        case "large": .system(size: 13, weight: .bold, design: .rounded)
        default: .system(size: 11, weight: .bold, design: .rounded)
        }
    }

    private var detailFont: Font {
        switch preferences.fontSize {
        case "small": .system(size: 8, weight: .medium, design: .rounded)
        case "large": .system(size: 11, weight: .medium, design: .rounded)
        default: .system(size: 9.5, weight: .medium, design: .rounded)
        }
    }

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
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(width: panelWidth, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black.opacity(glassOpacity * 0.76))
                LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.36), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.32), radius: 8, y: 4)
    }

    private var formattedTimestamp: String {
        timestamp.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }
}

struct FireVaultOverlayPreview: View {
    let preferences: FireVaultOverlayPreferences
    let technicianName: String
    let siteName: String
    let address: String
    let accountID: String
    let category: String

    @State private var editedPreferences: FireVaultOverlayPreferences
    @GestureState private var overlayDrag: CGSize = .zero
    @GestureState private var logoDrag: CGSize = .zero

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
        VStack(spacing: 10) {
            GeometryReader { geometry in
                let designWidth: CGFloat = 430
                let designHeight: CGFloat = 322.5
                let previewScale = geometry.size.width / designWidth

                ZStack {
                    Image("NotifierPanelSample")
                        .resizable().scaledToFill()
                        .frame(width: designWidth, height: designHeight).clipped()

                    overlayEditorLayer(size: CGSize(width: designWidth, height: designHeight))
                }
                .frame(width: designWidth, height: designHeight)
                .scaleEffect(previewScale, anchor: .topLeading)
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12), lineWidth: 1) }

            HStack(spacing: 10) {
                Image(systemName: "arrow.down.right.and.arrow.up.left").foregroundStyle(NativeShellPalette.blue)
                Text("Overlay").font(.caption.bold())
                Slider(value: $editedPreferences.scale, in: 0.45...1.35, step: 0.05)
                    .onChange(of: editedPreferences.scale) { _, _ in stageEdits() }
                Text("\(Int((editedPreferences.scale * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }

            if editedPreferences.showLogo {
                HStack(spacing: 10) {
                    Image(systemName: "f.square").foregroundStyle(NativeShellPalette.red)
                    Text("Logo").font(.caption.bold())
                    Slider(value: $editedPreferences.logoScale, in: 0.45...1.8, step: 0.05)
                        .onChange(of: editedPreferences.logoScale) { _, _ in stageEdits() }
                    Text("\(Int((editedPreferences.logoScale * 100).rounded()))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
                }
            }

            Text("Drag the glass overlay and the FireVault logo independently anywhere on the photo.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onChange(of: preferences) { _, newValue in editedPreferences = newValue }
        .onAppear { stageEdits() }
        .accessibilityIdentifier("overlay-interactive-preview")
    }

    @ViewBuilder
    private func overlayEditorLayer(size: CGSize) -> some View {
        ZStack {
            FireVaultPhotoOverlayView(
                preferences: previewPreferences(overlayTranslation: overlayDrag, logoTranslation: .zero, size: size, hideLogo: true),
                technicianName: technicianName,
                siteName: siteName,
                address: address,
                accountID: accountID,
                category: category,
                timestamp: .now
            )
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(overlayGesture(in: size))

            if editedPreferences.showLogo {
                FireVaultBrandMark()
                    .scaleEffect(editedPreferences.logoScale)
                    .position(
                        x: size.width * (0.5 + CGFloat(editedPreferences.logoPositionX) * 0.36) + logoDrag.width,
                        y: size.height * (0.5 + CGFloat(editedPreferences.logoPositionY) * 0.36) + logoDrag.height
                    )
                    .contentShape(Rectangle())
                    .gesture(logoGesture(in: size))
            }
        }
    }

    private func previewPreferences(overlayTranslation: CGSize, logoTranslation: CGSize, size: CGSize, hideLogo: Bool) -> FireVaultOverlayPreferences {
        var value = editedPreferences
        value.positionX += Double(overlayTranslation.width / max(size.width * 0.36, 1))
        value.positionY += Double(overlayTranslation.height / max(size.height * 0.36, 1))
        value.logoPositionX += Double(logoTranslation.width / max(size.width * 0.36, 1))
        value.logoPositionY += Double(logoTranslation.height / max(size.height * 0.36, 1))
        if hideLogo { value.showLogo = false }
        return value.normalized
    }

    private func overlayGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($overlayDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                editedPreferences.positionX += Double(value.translation.width / max(size.width * 0.36, 1))
                editedPreferences.positionY += Double(value.translation.height / max(size.height * 0.36, 1))
                editedPreferences = editedPreferences.normalized
                stageEdits()
                UISelectionFeedbackGenerator().selectionChanged()
            }
    }

    private func logoGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($logoDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                editedPreferences.logoPositionX += Double(value.translation.width / max(size.width * 0.36, 1))
                editedPreferences.logoPositionY += Double(value.translation.height / max(size.height * 0.36, 1))
                editedPreferences = editedPreferences.normalized
                stageEdits()
                UISelectionFeedbackGenerator().selectionChanged()
            }
    }

    private func stageEdits() { FireVaultOverlayEditorBridge.stage(editedPreferences) }
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
