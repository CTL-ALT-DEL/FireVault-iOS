import AVFoundation
import SwiftUI
import UIKit

enum FireVaultVideoOverlayError: LocalizedError {
    case missingVideoTrack
    case cannotCreateExportSession
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            "The recorded movie does not contain a usable video track."
        case .cannotCreateExportSession:
            "FireVault Pro could not prepare the video export."
        case .exportFailed(let detail):
            "The customer overlay could not be applied to the video. \(detail)"
        }
    }
}

@MainActor
enum FireVaultVideoOverlayRenderer {
    static func render(
        sourceURL: URL,
        preferences: FireVaultOverlayPreferences,
        technicianName: String,
        account: FireVaultWorkspaceAccount,
        timestamp: Date
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw FireVaultVideoOverlayError.missingVideoTrack
        }
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let renderSize = FireVaultVideoDisplayGeometry.displaySize(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        let duration = try await asset.load(.duration)

        var layerConfiguration = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        let normalizedTransform = preferredTransform.concatenating(
            CGAffineTransform(
                translationX: -transformedRect.minX,
                y: -transformedRect.minY
            )
        )
        layerConfiguration.setTransform(normalizedTransform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfiguration)
        let instruction = AVVideoCompositionInstruction(
            configuration: .init(
                layerInstructions: [layerInstruction],
                timeRange: CMTimeRange(start: .zero, duration: duration)
            )
        )

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        let overlayLayer = CALayer()
        overlayLayer.frame = videoLayer.frame
        overlayLayer.contents = overlayImage(
            size: renderSize,
            preferences: preferences,
            technicianName: technicianName,
            account: account,
            timestamp: timestamp
        ).cgImage
        overlayLayer.contentsGravity = .resizeAspect

        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        let animationTool = AVVideoCompositionCoreAnimationTool(
            configuration: .init(
                postProcessingAsVideoLayer: videoLayer,
                containingLayer: parentLayer
            )
        )
        let videoComposition = AVVideoComposition(
            configuration: .init(
                animationTool: animationTool,
                frameDuration: CMTime(value: 1, timescale: 30),
                instructions: [instruction],
                renderSize: renderSize
            )
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FireVault-Overlay-\(UUID().uuidString).mp4")
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw FireVaultVideoOverlayError.cannotCreateExportSession
        }
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition

        do {
            try await exporter.export(to: outputURL, as: .mp4)
        } catch {
            throw FireVaultVideoOverlayError.exportFailed(
                error.localizedDescription.isEmpty
                    ? "The export did not complete."
                    : error.localizedDescription
            )
        }
        return outputURL
    }

    private static func overlayImage(
        size: CGSize,
        preferences: FireVaultOverlayPreferences,
        technicianName: String,
        account: FireVaultWorkspaceAccount,
        timestamp: Date
    ) -> UIImage {
        let logicalWidth: CGFloat = 430
        let outputScale = max(size.width / logicalWidth, 1)
        let logicalSize = CGSize(width: size.width / outputScale, height: size.height / outputScale)
        let adjusted = FireVaultOverlayCanvasConstraints.constrained(
            preferences,
            canvasSize: logicalSize,
            technicianName: technicianName,
            siteName: account.name,
            address: account.address,
            accountID: account.accountId,
            category: account.category
        )
        let content = FireVaultPhotoOverlayView(
            preferences: adjusted,
            technicianName: technicianName,
            siteName: account.name,
            address: account.address,
            accountID: account.accountId,
            category: account.category,
            timestamp: timestamp,
            locationQRCodePayload: adjusted.showLocationQRCode
                ? FireVaultLocationQRCode.payload(for: account)
                : nil
        )
        .frame(width: logicalSize.width, height: logicalSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(logicalSize)
        renderer.scale = outputScale
        renderer.isOpaque = false
        return renderer.uiImage ?? UIImage()
    }
}
