//
//  NativeCaptureViews.swift
//  FireVault
//
//  Native camera, document scanning, and field-photo overlay support.
//

import SwiftUI
import UIKit
import VisionKit

private struct FireVaultResolvedOverlayField: Identifiable, Equatable {
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
            .timestamp: timestamp.formatted(
                .dateTime.month(.abbreviated).day().year().hour().minute()
            )
        ]
        let hidden = Set(preferences.hiddenFields)

        return preferences.fieldOrder.compactMap { fieldID in
            guard let field = FireVaultOverlayField(rawValue: fieldID),
                  field.isRequired || !hidden.contains(fieldID),
                  let value = values[field],
                  !value.isEmpty else {
                return nil
            }
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
        )
        .map(\.value)
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

        return template
            .components(separatedBy: .newlines)
            .compactMap { sourceLine in
                if accountID.isEmpty, sourceLine.contains("{accountID}") {
                    return nil
                }

                let resolved = replacements.reduce(sourceLine) { partial, replacement in
                    partial.replacingOccurrences(of: replacement.key, with: replacement.value)
                }
                let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
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

    private var titleFont: Font {
        switch preferences.fontSize {
        case "small": .caption.bold()
        case "large": .title3.bold()
        default: .headline
        }
    }

    private var detailFont: Font {
        switch preferences.fontSize {
        case "small": .caption2
        case "large": .subheadline
        default: .caption
        }
    }

    private var logoSize: CGFloat {
        switch preferences.fontSize {
        case "small": 24
        case "large": 40
        default: 32
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

    private var leftFields: [FireVaultResolvedOverlayField] {
        resolvedFields.filter { $0.field != .technician }
    }

    private var technicianField: FireVaultResolvedOverlayField? {
        resolvedFields.first { $0.field == .technician }
    }

    private var leftBlockAlignment: Alignment {
        switch preferences.alignment {
        case "top": .topLeading
        case "center": .leading
        default: .bottomLeading
        }
    }

    var body: some View {
        ZStack {
            leftOverlayContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leftBlockAlignment)

            if let technicianField {
                glowingText(
                    technicianField.value,
                    font: detailFont.bold(),
                    alignment: .trailing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [
                "FireVault photo overlay",
                siteName,
                address,
                accountID.isEmpty ? nil : "Account ID \(accountID)",
                technicianName,
                formattedTimestamp
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        )
    }

    private var leftOverlayContent: some View {
        HStack(alignment: .top, spacing: 10) {
            if preferences.showLogo {
                Image("FireVaultLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.22, style: .continuous))
                    .shadow(color: .white.opacity(0.95), radius: 2)
                    .shadow(color: .white.opacity(0.65), radius: 5)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                if preferences.showTagline, !preferences.tagline.isEmpty {
                    glowingText(
                        preferences.tagline,
                        font: detailFont.bold(),
                        alignment: .leading
                    )
                    .tracking(0.7)
                }

                ForEach(Array(leftFields.enumerated()), id: \.element.id) { index, entry in
                    glowingText(
                        entry.value,
                        font: index == 0 ? titleFont : detailFont,
                        alignment: .leading
                    )
                }
            }
            .frame(maxWidth: 330, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func glowingText(
        _ value: String,
        font: Font,
        alignment: TextAlignment
    ) -> some View {
        Text(value)
            .font(font)
            .foregroundStyle(.black)
            .multilineTextAlignment(alignment)
            .lineLimit(1)
            .shadow(color: .white, radius: 1)
            .shadow(color: .white.opacity(0.95), radius: 3)
            .shadow(color: .white.opacity(0.72), radius: 6)
    }

    private var formattedTimestamp: String {
        timestamp.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .year()
                .hour()
                .minute()
        )
    }
}

struct FireVaultOverlayPreview: View {
    let preferences: FireVaultOverlayPreferences
    let technicianName: String
    let siteName: String
    let address: String
    let accountID: String
    let category: String

    var body: some View {
        GeometryReader { geometry in
            let designWidth: CGFloat = 430
            let designHeight: CGFloat = 322.5
            let previewScale = geometry.size.width / designWidth

            ZStack {
                Image("NotifierPanelSample")
                    .resizable()
                    .scaledToFill()
                    .frame(width: designWidth, height: designHeight)
                    .clipped()

                FireVaultPhotoOverlayView(
                    preferences: preferences,
                    technicianName: technicianName,
                    siteName: siteName,
                    address: address,
                    accountID: accountID,
                    category: category,
                    timestamp: .now
                )
                .frame(width: designWidth, height: designHeight)
            }
            .frame(width: designWidth, height: designHeight)
            .scaleEffect(previewScale, anchor: .topLeading)
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
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
        let logicalSize = CGSize(
            width: image.size.width / outputScale,
            height: image.size.height / outputScale
        )

        let content = ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: logicalSize.width, height: logicalSize.height)
                .clipped()

            FireVaultPhotoOverlayView(
                preferences: preferences,
                technicianName: technicianName,
                siteName: account.name,
                address: account.address,
                accountID: account.accountId,
                category: account.category,
                timestamp: timestamp
            )
            .frame(width: logicalSize.width, height: logicalSize.height)
        }
        .frame(width: logicalSize.width, height: logicalSize.height)

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

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

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
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

struct NativeDocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: VNDocumentCameraViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let onCancel: () -> Void
        let onFailure: (String) -> Void

        init(
            onScan: @escaping ([UIImage]) -> Void,
            onCancel: @escaping () -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.onScan = onScan
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            onScan((0..<scan.pageCount).map(scan.imageOfPage))
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onFailure(error.localizedDescription)
        }
    }
}
