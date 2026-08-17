//
//  FireVaultAccountMediaView.swift
//  FireVault
//
//  Account-scoped photo and document browsing, preview, sharing, and removal.
//

import QuickLook
import ImageIO
import SwiftUI
import UIKit

private enum FireVaultAccountMediaFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case photos = "Photos"
    case documents = "Documents"

    var id: String { rawValue }
}

struct FireVaultAccountMediaLibraryView: View {
    let accountID: String
    @ObservedObject var store: FireVaultStore
    var embedded = false

    @State private var filter: FireVaultAccountMediaFilter = .all
    @State private var selectedDocument: FireVaultWorkspaceDocument?
    @State private var pendingDeletion: FireVaultWorkspaceDocument?
    @State private var deletionError: String?

    private var account: FireVaultWorkspaceAccount? {
        store.accounts.first { $0.id == accountID }
    }

    private var documents: [FireVaultWorkspaceDocument] {
        let allDocuments = account?.documents ?? []
        switch filter {
        case .all:
            return allDocuments
        case .photos:
            return allDocuments.filter { $0.kind.lowercased() == "photo" }
        case .documents:
            return allDocuments.filter { $0.kind.lowercased() != "photo" }
        }
    }

    private var photoCount: Int {
        account?.documents.filter { $0.kind.lowercased() == "photo" }.count ?? 0
    }

    private var documentCount: Int {
        (account?.documents.count ?? 0) - photoCount
    }

    var body: some View {
        Group {
            if embedded {
                libraryContent
            } else {
                ScrollView {
                    libraryContent
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .background(NativeShellPalette.background)
            }
        }
        .navigationTitle("Photos & Documents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .topBarTrailing) {
                    captureMenu
                }
            }
        }
        .sheet(item: $selectedDocument) { document in
            NavigationStack {
                FireVaultAccountMediaPreviewView(
                    accountID: accountID,
                    documentID: document.id,
                    store: store
                )
            }
        }
        .confirmationDialog(
            "Delete from this account?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Photo or Document", role: .destructive) {
                guard let document = pendingDeletion else { return }
                delete(document)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This permanently removes the saved FireVault copy. This action cannot be undone.")
        }
        .alert("Couldn’t Delete Item", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "Please try again.")
        }
        .accessibilityIdentifier("account-photos-documents")
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            libraryHeader

            Picker("Media Filter", selection: $filter) {
                ForEach(FireVaultAccountMediaFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("account-media-filter")

            if documents.isEmpty {
                emptyState
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: embedded ? 190 : 152), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(documents) { document in
                        mediaCard(document)
                    }
                }
            }
        }
        .padding(.top, embedded ? 0 : 12)
    }

    private var libraryHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if embedded {
                    Text("PHOTOS & DOCUMENTS")
                        .font(.caption.bold())
                        .tracking(1.0)
                        .foregroundStyle(NativeShellPalette.blue)
                }
                Text(summaryText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            if embedded {
                captureMenu
            }
        }
        .padding(14)
        .nativeSurfaceCard(emphasized: embedded)
    }

    private var captureMenu: some View {
        Menu {
            Button("Take Photo", systemImage: "camera.fill") {
                openCapture(.photo)
            }
            Button("Scan Document", systemImage: "doc.viewfinder") {
                openCapture(.scan)
            }
        } label: {
            Label("Add", systemImage: "plus")
                .font(.subheadline.bold())
        }
        .buttonStyle(.glassProminent)
        .accessibilityLabel("Add photo or document")
        .accessibilityIdentifier("account-media-add")
    }

    private var summaryText: String {
        let photos = "\(photoCount) photo\(photoCount == 1 ? "" : "s")"
        let documents = "\(documentCount) document\(documentCount == 1 ? "" : "s")"
        return "\(photos) • \(documents)"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: filter == .photos ? "photo.on.rectangle.angled" : "folder.badge.plus")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(NativeShellPalette.blue)
            Text(filter == .all ? "No photos or documents yet" : "No \(filter.rawValue.lowercased()) yet")
                .font(.headline)
            Text("Use Add to take a field photo or scan a document directly into this account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(20)
        .nativeSurfaceCard()
    }

    private func mediaCard(_ document: FireVaultWorkspaceDocument) -> some View {
        let url = store.mediaURL(accountID: accountID, documentID: document.id)
        let isPhoto = document.kind.lowercased() == "photo"
        let isDemoSample = store.demoMode && document.mediaFileName == nil

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                selectedDocument = document
            } label: {
                ZStack(alignment: .bottomLeading) {
                    FireVaultAccountMediaArtwork(
                        document: document,
                        url: url,
                        isDemoSample: isDemoSample
                    )
                        .frame(maxWidth: .infinity)
                        .frame(height: isPhoto ? 128 : 104)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.68)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    Label(
                        url == nil
                            ? (isDemoSample ? "View sample" : "Preview unavailable")
                            : (isPhoto ? "View photo" : "Open document"),
                        systemImage: url == nil && !isDemoSample
                            ? "exclamationmark.triangle.fill"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(10)
                }
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 15,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 15
                ))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isPhoto ? "View photo" : "Open document"): \(document.title)")
            .accessibilityValue(url == nil && !isDemoSample ? "File unavailable" : "Available")

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(document.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text([document.subtitle, document.date].filter { !$0.isEmpty }.joined(separator: " • "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Menu {
                    Button("View", systemImage: "eye") {
                        selectedDocument = document
                    }
                    if let url {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        pendingDeletion = document
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(NativeShellPalette.blue)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Actions for \(document.title)")
            }
            .padding(11)
        }
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(NativeShellPalette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .contextMenu {
            Button("View", systemImage: "eye") { selectedDocument = document }
            if let url {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                pendingDeletion = document
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("account-media-item-\(document.id)")
    }

    private func openCapture(_ action: FireVaultCaptureQuickAction) {
        store.selectCaptureAccount(accountID)
        store.requestCapture(action)
        store.closeAccount(to: .photo)
    }

    private func delete(_ document: FireVaultWorkspaceDocument) {
        do {
            _ = try store.deleteDocument(accountID: accountID, documentID: document.id)
            pendingDeletion = nil
        } catch {
            pendingDeletion = nil
            deletionError = error.localizedDescription
        }
    }
}

private struct FireVaultAccountMediaArtwork: View {
    let document: FireVaultWorkspaceDocument
    let url: URL?
    let isDemoSample: Bool

    var body: some View {
        Group {
            if document.kind.lowercased() == "photo",
               let url {
                FireVaultMediaThumbnailView(url: url)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [mediaTint.opacity(0.28), mediaTint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: mediaSymbol)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(mediaTint)
                    if isDemoSample {
                        Text("DEMO SAMPLE")
                            .font(.caption2.bold())
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(9)
                    }
                }
            }
        }
        .clipped()
    }

    private var mediaSymbol: String {
        if url == nil && !isDemoSample { return "exclamationmark.triangle.fill" }
        switch document.kind.lowercased() {
        case "photo": return "photo.fill"
        case "scan": return "doc.viewfinder.fill"
        default: return "doc.fill"
        }
    }

    private var mediaTint: Color {
        if url == nil && !isDemoSample { return NativeShellPalette.amber }
        switch document.kind.lowercased() {
        case "photo": return NativeShellPalette.purple
        case "scan": return NativeShellPalette.blue
        default: return NativeShellPalette.green
        }
    }
}

struct FireVaultMediaThumbnailView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if didFail {
                ZStack {
                    NativeShellPalette.navigationBackground
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2.bold())
                        .foregroundStyle(NativeShellPalette.amber)
                }
            } else {
                ZStack {
                    NativeShellPalette.navigationBackground
                    ProgressView()
                        .controlSize(.small)
                        .tint(NativeShellPalette.blue)
                }
            }
        }
        .task(id: url) {
            image = nil
            didFail = false
            let loaded = await FireVaultMediaThumbnailLoader.shared.thumbnail(for: url)?.image
            guard !Task.isCancelled else { return }
            image = loaded
            didFail = loaded == nil
        }
    }
}

private struct FireVaultSendableThumbnail: @unchecked Sendable {
    let image: UIImage
}

private actor FireVaultMediaThumbnailLoader {
    static let shared = FireVaultMediaThumbnailLoader()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 48 * 1_024 * 1_024
    }

    func thumbnail(for url: URL) -> FireVaultSendableThumbnail? {
        image(for: url, maxPixelSize: 900)
    }

    func image(for url: URL, maxPixelSize: Int) -> FireVaultSendableThumbnail? {
        let constrainedSize = min(max(maxPixelSize, 320), 4_096)
        let key = "\(url.standardizedFileURL.path)#\(constrainedSize)" as NSString
        if let cached = cache.object(forKey: key) {
            return FireVaultSendableThumbnail(image: cached)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: constrainedSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return FireVaultSendableThumbnail(image: image)
    }
}

private struct FireVaultAccountMediaPreviewView: View {
    let accountID: String
    let documentID: String
    @ObservedObject var store: FireVaultStore

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false
    @State private var deletionError: String?

    private var document: FireVaultWorkspaceDocument? {
        store.accounts
            .first(where: { $0.id == accountID })?
            .documents.first(where: { $0.id == documentID })
    }

    private var url: URL? {
        store.mediaURL(accountID: accountID, documentID: documentID)
    }

    var body: some View {
        Group {
            if let document, let url {
                if document.kind.lowercased() == "photo" {
                    FireVaultZoomablePhotoFileView(url: url)
                } else {
                    FireVaultQuickLookView(url: url)
                }
            } else if let document,
                      store.demoMode,
                      document.mediaFileName == nil {
                FireVaultDemoMediaPreviewView(document: document)
            } else {
                ContentUnavailableView(
                    "File Unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("The account record exists, but its saved file is not available on this device. You can remove the broken record from the Delete menu.")
                )
            }
        }
        .background(Color.black.opacity(document?.kind.lowercased() == "photo" ? 1 : 0).ignoresSafeArea())
        .navigationTitle(document?.title ?? "Photos & Documents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share through Messages, Mail, or another app")
                    .accessibilityIdentifier("account-media-share")
                }
                Button(role: .destructive) {
                    confirmsDeletion = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete photo or document")
                .accessibilityIdentifier("account-media-delete")
            }
        }
        .confirmationDialog("Delete from this account?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete Photo or Document", role: .destructive) { deleteDocument() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the saved FireVault copy. This action cannot be undone.")
        }
        .alert("Couldn’t Delete Item", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "Please try again.")
        }
        .accessibilityIdentifier("account-media-preview")
    }

    private func deleteDocument() {
        do {
            if try store.deleteDocument(accountID: accountID, documentID: documentID) {
                dismiss()
            }
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

private struct FireVaultDemoMediaPreviewView: View {
    let document: FireVaultWorkspaceDocument

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [NativeShellPalette.navigationBackground, NativeShellPalette.blue.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 18) {
                Image(systemName: document.kind.lowercased() == "photo" ? "photo.fill" : "doc.text.fill")
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(NativeShellPalette.blue)
                    .frame(width: 112, height: 112)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                VStack(spacing: 7) {
                    Text(document.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(document.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("DEMONSTRATION PREVIEW")
                        .font(.caption.bold())
                        .tracking(1.1)
                        .foregroundStyle(NativeShellPalette.amber)
                }
            }
            .padding(28)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo preview: \(document.title), \(document.subtitle)")
    }
}

private struct FireVaultZoomablePhotoFileView: View {
    let url: URL
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    FireVaultZoomablePhotoView(image: image)
                } else if didFail {
                    ContentUnavailableView(
                        "Photo Unavailable",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("FireVault could not decode this saved photo.")
                    )
                } else {
                    ProgressView("Opening photo…")
                        .tint(.white)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: "\(url.standardizedFileURL.path)#\(Int(geometry.size.width))x\(Int(geometry.size.height))") {
                image = nil
                didFail = false
                let longestSide = max(geometry.size.width, geometry.size.height)
                let requestedPixels = Int(max(1, longestSide * displayScale * 1.35))
                let loaded = await FireVaultMediaThumbnailLoader.shared.image(
                    for: url,
                    maxPixelSize: requestedPixels
                )?.image
                guard !Task.isCancelled else { return }
                image = loaded
                didFail = loaded == nil
            }
        }
        .background(Color.black)
    }
}

private struct FireVaultZoomablePhotoView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Saved account photo"
        imageView.accessibilityHint = "Pinch or double tap to zoom"
        scrollView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.scrollView = scrollView
        imageView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Zoom In",
                target: context.coordinator,
                selector: #selector(Coordinator.zoomIn)
            ),
            UIAccessibilityCustomAction(
                name: "Reset Zoom",
                target: context.coordinator,
                selector: #selector(Coordinator.resetZoom)
            )
        ]
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        if context.coordinator.imageView.image !== image {
            context.coordinator.imageView.image = image
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        weak var scrollView: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }
            let point = recognizer.location(in: imageView)
            let targetScale: CGFloat = 2
            let width = scrollView.bounds.width / targetScale
            let height = scrollView.bounds.height / targetScale
            scrollView.zoom(
                to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
                animated: true
            )
        }

        @objc func zoomIn() -> Bool {
            guard let scrollView else { return false }
            scrollView.setZoomScale(min(scrollView.zoomScale + 1, scrollView.maximumZoomScale), animated: true)
            return true
        }

        @objc func resetZoom() -> Bool {
            guard let scrollView else { return false }
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return true
        }
    }
}

private struct FireVaultQuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
