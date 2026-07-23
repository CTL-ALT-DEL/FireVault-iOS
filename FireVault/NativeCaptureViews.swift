//
//  NativeCaptureViews.swift
//  FireVault
//
//  Native camera, document scanning, and field-photo overlay support.
//

import SwiftUI
import UIKit
import VisionKit

enum FireVaultOverlayTemplateFormatter {
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
    let timestamp: Date

    private var accent: Color {
        switch preferences.accentColor {
        case "blue": NativeShellPalette.blue
        case "amber": NativeShellPalette.amber
        case "white": .white
        default: NativeShellPalette.red
        }
    }

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

    var body: some View {
        VStack(spacing: 0) {
            if preferences.alignment != "top" { Spacer(minLength: 0) }
            overlayContent
            if preferences.alignment != "bottom" { Spacer(minLength: 0) }
        }
        .padding(preferences.backgroundStyle == "bar" ? 0 : 10)
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

    private var resolvedLines: [String] {
        FireVaultOverlayTemplateFormatter.lines(
            template: preferences.fieldTemplate,
            siteName: siteName,
            address: address,
            accountID: accountID,
            technicianName: technicianName,
            timestamp: timestamp
        )
    }

    private var overlayContent: some View {
        HStack(alignment: .center, spacing: 10) {
            if preferences.showLogo {
                Image("FireVaultLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.22, style: .continuous))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                if preferences.showTagline, !preferences.tagline.isEmpty {
                    Text(preferences.tagline)
                    .font(detailFont.bold())
                    .foregroundStyle(accent)
                    .tracking(0.7)
                    .lineLimit(1)
                }

                ForEach(Array(resolvedLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(index == 0 ? titleFont : detailFont)
                        .foregroundStyle(index == 0 ? .white : .white.opacity(0.82))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(
            maxWidth: preferences.backgroundStyle == "bar" ? .infinity : 360,
            alignment: .leading
        )
        .background {
            if preferences.backgroundStyle != "minimal" {
                Color.black.opacity(Double(preferences.opacity) / 100)
            }
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: preferences.backgroundStyle == "card" ? 14 : 0,
                style: .continuous
            )
        )
        .overlay {
            if preferences.backgroundStyle == "card" {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.55), lineWidth: 1)
            }
        }
        .shadow(
            color: preferences.backgroundStyle == "minimal" ? .black.opacity(0.85) : .clear,
            radius: 4,
            y: 2
        )
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

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.18, blue: 0.20),
                    Color(red: 0.05, green: 0.06, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "building.2.fill")
                .font(.system(size: 92, weight: .light))
                .foregroundStyle(.white.opacity(0.12))

            FireVaultPhotoOverlayView(
                preferences: preferences,
                technicianName: technicianName,
                siteName: siteName,
                address: address,
                accountID: accountID,
                timestamp: .now
            )
        }
        .frame(height: 220)
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
