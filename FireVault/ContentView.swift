//
//  ContentView.swift
//  FireVault
//
//  Native container for the working FireVault field application.
//

import SwiftUI
import UIKit
import WebKit
import MapKit
import CoreLocation
import VisionKit

struct ContentView: View {
    @State private var loadState: FireVaultLoadState = .loading
    @State private var reloadToken = UUID()
    @StateObject private var appShellBridge = FireVaultAppShellBridge()
    @StateObject private var workspaceBridge = FireVaultWorkspaceBridge()

    var body: some View {
        ZStack {
            FireVaultTheme.background.ignoresSafeArea()

            FireVaultWebView(
                loadState: $loadState,
                reloadToken: reloadToken,
                appShellBridge: appShellBridge,
                workspaceBridge: workspaceBridge
            )
                .ignoresSafeArea(.container, edges: .bottom)

            if loadState == .loading {
                loadingView
                    .transition(.opacity)
            }

            if case .failed(let message) = loadState {
                recoveryView(message: message)
                    .transition(.opacity)
            }

            if let payload = appShellBridge.payload, loadState == .ready {
                NativeAppShellView(payload: payload, bridge: appShellBridge)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if let account = workspaceBridge.account, loadState == .ready {
                FieldWorkspaceView(account: account, bridge: workspaceBridge)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(5)
            }
        }
        .animation(.easeOut(duration: 0.25), value: loadState)
        .animation(.easeOut(duration: 0.2), value: appShellBridge.payload?.build)
        .animation(.easeOut(duration: 0.2), value: workspaceBridge.account?.id)
        .preferredColorScheme(.dark)
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(FireVaultTheme.accent.opacity(0.12))
                    .frame(width: 86, height: 86)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(FireVaultTheme.accent)
            }

            VStack(spacing: 6) {
                Text("FIREVAULT")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .tracking(1.5)
                Text("Opening your field vault…")
                    .font(.subheadline)
                    .foregroundStyle(FireVaultTheme.secondaryText)
            }

            ProgressView()
                .tint(FireVaultTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FireVaultTheme.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening FireVault")
    }

    private func recoveryView(message: String) -> some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(FireVaultTheme.warning.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(FireVaultTheme.warning)
            }

            VStack(spacing: 8) {
                Text("FireVault couldn’t open")
                    .font(.title2.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(FireVaultTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Button {
                loadState = .loading
                reloadToken = UUID()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(FireVaultTheme.accent)
                    .foregroundStyle(FireVaultTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
        .padding(24)
        .frame(maxWidth: 390)
        .background(FireVaultTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .padding(22)
    }
}

private struct FireVaultWebView: UIViewRepresentable {
    @Binding var loadState: FireVaultLoadState
    let reloadToken: UUID
    @ObservedObject var appShellBridge: FireVaultAppShellBridge
    @ObservedObject var workspaceBridge: FireVaultWorkspaceBridge

    private let appURL = URL(string: "https://ctl-alt-del.github.io/FireVault2/")!

    func makeCoordinator() -> Coordinator {
        Coordinator(
            loadState: $loadState,
            allowedHost: appURL.host,
            appShellBridge: appShellBridge,
            workspaceBridge: workspaceBridge
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(context.coordinator, name: "fireVaultMaps")
        configuration.userContentController.add(context.coordinator, name: "fireVaultScanner")
        configuration.userContentController.add(context.coordinator, name: "fireVaultAppShell")
        configuration.userContentController.add(context.coordinator, name: "fireVaultWorkspace")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(FireVaultTheme.background)
        webView.scrollView.backgroundColor = UIColor(FireVaultTheme.background)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "FireVault-iOS/1.03.31"

        context.coordinator.webView = webView
        appShellBridge.webView = webView
        workspaceBridge.webView = webView
        context.coordinator.lastReloadToken = reloadToken
        load(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastReloadToken != reloadToken else { return }
        context.coordinator.lastReloadToken = reloadToken
        load(webView)
    }

    private func load(_ webView: WKWebView) {
        var request = URLRequest(url: appURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 25
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, CLLocationManagerDelegate, VNDocumentCameraViewControllerDelegate {
        @Binding private var loadState: FireVaultLoadState
        private let allowedHost: String?
        private let appShellBridge: FireVaultAppShellBridge
        private let workspaceBridge: FireVaultWorkspaceBridge
        private let locationManager = CLLocationManager()
        private var pendingLocationRequestID: String?
        private var activeSearches: [String: MKLocalSearch] = [:]
        private var activeReverseRequests: [String: MKReverseGeocodingRequest] = [:]
        private var activeSnapshots: [String: MKMapSnapshotter] = [:]
        private var pendingScannerRequestID: String?
        weak var webView: WKWebView?
        var lastReloadToken: UUID?

        init(
            loadState: Binding<FireVaultLoadState>,
            allowedHost: String?,
            appShellBridge: FireVaultAppShellBridge,
            workspaceBridge: FireVaultWorkspaceBridge
        ) {
            _loadState = loadState
            self.allowedHost = allowedHost
            self.appShellBridge = appShellBridge
            self.workspaceBridge = workspaceBridge
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadState = .ready
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            showFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            showFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let isFireVaultPage = url.host == allowedHost
            let isWebLink = url.scheme == "http" || url.scheme == "https"

            if isFireVaultPage || !isWebLink {
                if let scheme = url.scheme, ["tel", "mailto", "maps"].contains(scheme) {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
                return
            }

            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  let url = navigationAction.request.url else { return nil }

            if url.host == allowedHost {
                webView.load(URLRequest(url: url))
            } else {
                UIApplication.shared.open(url)
            }
            return nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            if message.name == "fireVaultWorkspace" {
                if action == "present", let account = body["account"] as? [String: Any] {
                    workspaceBridge.present(account)
                } else if action == "dismiss" {
                    workspaceBridge.hide()
                }
                return
            }

            if message.name == "fireVaultAppShell" {
                if action == "present", let payload = body["payload"] as? [String: Any] {
                    appShellBridge.present(payload)
                } else if action == "dismiss" {
                    appShellBridge.hide()
                }
                return
            }

            guard let requestID = body["requestId"] as? String else { return }

            if message.name == "fireVaultScanner" {
                guard action == "scan" else {
                    sendScannerFailure(requestID, message: "Unsupported document scanner request.")
                    return
                }
                presentDocumentScanner(requestID: requestID)
                return
            }

            guard message.name == "fireVaultMaps" else { return }
            switch action {
            case "currentLocation": requestCurrentLocation(requestID: requestID)
            case "reverse": reverseGeocode(body, requestID: requestID)
            case "search": searchMap(body, requestID: requestID)
            case "route": openRoute(body, requestID: requestID)
            case "snapshot": createSnapshot(body, requestID: requestID)
            default: sendFailure(requestID, message: "Unsupported Apple Maps request.")
            }
        }

        private func presentDocumentScanner(requestID: String) {
            guard VNDocumentCameraViewController.isSupported else {
                sendScannerFailure(requestID, message: "Apple Document Scanner is not available on this device.")
                return
            }
            guard pendingScannerRequestID == nil else {
                sendScannerFailure(requestID, message: "A document scan is already open.")
                return
            }
            guard let webView,
                  let presenter = presentingViewController(for: webView) else {
                sendScannerFailure(requestID, message: "FireVault could not open the document camera.")
                return
            }

            pendingScannerRequestID = requestID
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = self
            scanner.modalPresentationStyle = .fullScreen
            presenter.present(scanner, animated: true)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            guard let requestID = pendingScannerRequestID else {
                controller.dismiss(animated: true)
                return
            }
            pendingScannerRequestID = nil
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            controller.dismiss(animated: true) { [weak self] in
                self?.prepareScannerPages(images, requestID: requestID)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            let requestID = pendingScannerRequestID
            pendingScannerRequestID = nil
            controller.dismiss(animated: true) { [weak self] in
                if let requestID {
                    self?.sendScannerFailure(requestID, message: "Document scan cancelled.", cancelled: true)
                }
            }
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            let requestID = pendingScannerRequestID
            pendingScannerRequestID = nil
            controller.dismiss(animated: true) { [weak self] in
                if let requestID {
                    self?.sendScannerFailure(requestID, message: "Apple Document Scanner could not finish. \(error.localizedDescription)")
                }
            }
        }

        private func prepareScannerPages(_ images: [UIImage], requestID: String) {
            guard !images.isEmpty else {
                sendScannerFailure(requestID, message: "No document pages were captured.")
                return
            }
            prepareAndDeliverScannerPage(images, requestID: requestID, index: 0)
        }

        private func prepareAndDeliverScannerPage(
            _ images: [UIImage],
            requestID: String,
            index: Int
        ) {
            guard index < images.count else {
                sendScannerSuccess(requestID, payload: [
                    "pageCount": images.count,
                    "source": "Apple VisionKit Document Camera"
                ])
                return
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let page: [String: Any]? = autoreleasepool {
                    let optimized = self.optimizedScannerImage(images[index])
                    guard let data = optimized.jpegData(compressionQuality: 0.82) else { return nil }
                    return [
                        "index": index,
                        "imageDataUrl": "data:image/jpeg;base64,\(data.base64EncodedString())",
                        "width": Int(optimized.size.width * optimized.scale),
                        "height": Int(optimized.size.height * optimized.scale),
                        "mime": "image/jpeg"
                    ]
                }
                DispatchQueue.main.async {
                    guard let page else {
                        self.sendScannerFailure(requestID, message: "Scanned page \(index + 1) could not be prepared.")
                        return
                    }
                    self.deliverScannerPage(
                        page,
                        requestID: requestID,
                        index: index,
                        count: images.count
                    ) { [weak self] error in
                        guard let self else { return }
                        if let error {
                            self.sendScannerFailure(requestID, message: "FireVault could not receive scanned page \(index + 1). \(error.localizedDescription)")
                            return
                        }
                        self.prepareAndDeliverScannerPage(images, requestID: requestID, index: index + 1)
                    }
                }
            }
        }

        private func optimizedScannerImage(_ image: UIImage) -> UIImage {
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            let longestSide = max(pixelWidth, pixelHeight)
            let maximumSide: CGFloat = 2200
            guard longestSide > maximumSide else { return image }

            let ratio = maximumSide / longestSide
            let targetSize = CGSize(width: floor(pixelWidth * ratio), height: floor(pixelHeight * ratio))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                UIColor.white.setFill()
                UIRectFill(CGRect(origin: .zero, size: targetSize))
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }

        private func deliverScannerPage(
            _ page: [String: Any],
            requestID: String,
            index: Int,
            count: Int,
            completion: @escaping (Error?) -> Void
        ) {
            let response: [String: Any] = [
                "requestId": requestID,
                "index": index,
                "count": count,
                "page": page
            ]
            sendScannerJavaScript(
                function: "fireVaultNativeScannerPage",
                response: response,
                completion: completion
            )
        }

        private func sendScannerSuccess(_ requestID: String, payload: [String: Any]) {
            sendScannerJavaScript(function: "fireVaultNativeScannerResolve", response: [
                "requestId": requestID,
                "success": true,
                "payload": payload
            ])
        }

        private func sendScannerFailure(_ requestID: String, message: String, cancelled: Bool = false) {
            sendScannerJavaScript(function: "fireVaultNativeScannerResolve", response: [
                "requestId": requestID,
                "success": false,
                "cancelled": cancelled,
                "error": message
            ])
        }

        private func sendScannerJavaScript(
            function: String,
            response: [String: Any],
            completion: ((Error?) -> Void)? = nil
        ) {
            guard JSONSerialization.isValidJSONObject(response),
                  let data = try? JSONSerialization.data(withJSONObject: response),
                  var json = String(data: data, encoding: .utf8) else {
                completion?(NSError(domain: "FireVaultScanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid scanner response."]))
                return
            }
            json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            guard let webView else {
                completion?(NSError(domain: "FireVaultScanner", code: 2, userInfo: [NSLocalizedDescriptionKey: "FireVault web view is unavailable."]))
                return
            }
            let script = "if(typeof window.\(function)!=='function'){throw new Error('FireVault scanner receiver unavailable');}window.\(function)(\(json));"
            webView.evaluateJavaScript(script) { _, error in
                completion?(error)
            }
        }

        private func requestCurrentLocation(requestID: String) {
            guard CLLocationManager.locationServicesEnabled() else {
                sendFailure(requestID, message: "Location Services are turned off on this iPhone.")
                return
            }

            if let previous = pendingLocationRequestID, previous != requestID {
                sendFailure(previous, message: "A newer GPS request replaced this one.")
            }
            pendingLocationRequestID = requestID

            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.requestLocation()
            case .denied, .restricted:
                pendingLocationRequestID = nil
                sendFailure(requestID, message: "Allow FireVault location access in iPhone Settings to use GPS address assistance.")
            @unknown default:
                pendingLocationRequestID = nil
                sendFailure(requestID, message: "The iPhone location permission could not be determined.")
            }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            guard let requestID = pendingLocationRequestID else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                pendingLocationRequestID = nil
                sendFailure(requestID, message: "Location access was not allowed. You can enter the address manually or enable access in Settings.")
            default:
                break
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let requestID = pendingLocationRequestID,
                  let location = locations.last else { return }
            pendingLocationRequestID = nil
            sendSuccess(requestID, payload: [
                "lat": location.coordinate.latitude,
                "lng": location.coordinate.longitude,
                "accuracy": max(0, location.horizontalAccuracy),
                "capturedAt": ISO8601DateFormatter().string(from: location.timestamp),
                "source": "Apple Core Location"
            ])
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            guard let requestID = pendingLocationRequestID else { return }
            pendingLocationRequestID = nil
            sendFailure(requestID, message: "The iPhone could not determine your current location. \(error.localizedDescription)")
        }

        private func reverseGeocode(_ body: [String: Any], requestID: String) {
            guard let latitude = number(body["lat"]),
                  let longitude = number(body["lng"]),
                  CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)),
                  let request = MKReverseGeocodingRequest(
                    location: CLLocation(latitude: latitude, longitude: longitude)
                  ) else {
                sendFailure(requestID, message: "The GPS coordinates are invalid.")
                return
            }

            activeReverseRequests[requestID] = request
            request.getMapItems { [weak self] items, error in
                guard let self else { return }
                self.activeReverseRequests[requestID] = nil
                if let error {
                    self.sendFailure(requestID, message: "Apple Maps could not identify this address. \(error.localizedDescription)")
                    return
                }
                guard let item = items?.first else {
                    self.sendFailure(requestID, message: "Apple Maps did not return an address for this location.")
                    return
                }
                self.sendSuccess(requestID, payload: self.mapItemPayload(item, accuracy: self.number(body["accuracy"]) ?? 0))
            }
        }

        private func searchMap(_ body: [String: Any], requestID: String) {
            let query = (body["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard query.count >= 3 else {
                sendFailure(requestID, message: "Enter more of the address or business name before searching.")
                return
            }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            if let latitude = number(body["nearLat"]),
               let longitude = number(body["nearLng"]),
               CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) {
                request.region = MKCoordinateRegion(
                    center: .init(latitude: latitude, longitude: longitude),
                    latitudinalMeters: 160_000,
                    longitudinalMeters: 160_000
                )
            }

            let search = MKLocalSearch(request: request)
            activeSearches[requestID] = search
            search.start { [weak self] response, error in
                guard let self else { return }
                self.activeSearches[requestID] = nil
                if let error {
                    self.sendFailure(requestID, message: "Apple Maps search was unavailable. \(error.localizedDescription)")
                    return
                }
                let results = Array((response?.mapItems ?? []).prefix(5)).map { self.mapItemPayload($0) }
                self.sendSuccess(requestID, payload: ["results": results, "source": "Apple Maps"])
            }
        }

        private func openRoute(_ body: [String: Any], requestID: String) {
            guard let latitude = number(body["lat"]),
                  let longitude = number(body["lng"]),
                  CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else {
                sendFailure(requestID, message: "This location does not have valid GPS coordinates.")
                return
            }

            let destination = MKMapItem(
                location: CLLocation(latitude: latitude, longitude: longitude),
                address: nil
            )
            destination.name = (body["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let opened = destination.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
            if opened {
                sendSuccess(requestID, payload: ["opened": true, "source": "Apple Maps"])
            } else {
                sendFailure(requestID, message: "Apple Maps could not open this route.")
            }
        }

        private func createSnapshot(_ body: [String: Any], requestID: String) {
            guard let latitude = number(body["lat"]),
                  let longitude = number(body["lng"]),
                  CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else {
                sendFailure(requestID, message: "The map center is invalid.")
                return
            }

            let latitudeDelta = min(max(number(body["latDelta"]) ?? 0.012, 0.0005), 120)
            let longitudeDelta = min(max(number(body["lngDelta"]) ?? 0.012, 0.0005), 180)
            let width = min(max(number(body["width"]) ?? 420, 240), 700)
            let height = min(max(number(body["height"]) ?? 260, 140), 500)
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: .init(latitude: latitude, longitude: longitude),
                span: .init(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
            )
            options.size = CGSize(width: width, height: height)
            options.scale = min(UIScreen.main.scale, 2)
            options.mapType = .standard
            options.showsBuildings = true

            let snapshotter = MKMapSnapshotter(options: options)
            activeSnapshots[requestID] = snapshotter
            snapshotter.start { [weak self] snapshot, error in
                guard let self else { return }
                self.activeSnapshots[requestID] = nil
                if let error {
                    self.sendFailure(requestID, message: "Apple Maps could not draw this map. \(error.localizedDescription)")
                    return
                }
                guard let data = snapshot?.image.pngData() else {
                    self.sendFailure(requestID, message: "Apple Maps returned an empty map image.")
                    return
                }
                self.sendSuccess(requestID, payload: [
                    "imageDataUrl": "data:image/png;base64,\(data.base64EncodedString())",
                    "source": "Apple Maps"
                ])
            }
        }

        private func mapItemPayload(_ item: MKMapItem, accuracy: Double = 0) -> [String: Any] {
            let placemark = item.placemark
            let street = [placemark.subThoroughfare, placemark.thoroughfare]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let city = placemark.locality ?? placemark.subAdministrativeArea ?? ""
            let state = placemark.administrativeArea ?? ""
            let zip = placemark.postalCode ?? ""
            let fallbackAddress = [street, city, state, zip].filter { !$0.isEmpty }.joined(separator: ", ")
            let displayAddress = item.address?.fullAddress ?? fallbackAddress
            let rawName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalizedName = rawName.lowercased()
            let businessName = normalizedName == street.lowercased() || normalizedName == displayAddress.lowercased() ? "" : rawName

            return [
                "lat": item.location.coordinate.latitude,
                "lng": item.location.coordinate.longitude,
                "accuracy": accuracy,
                "capturedAt": ISO8601DateFormatter().string(from: Date()),
                "street": street,
                "city": city,
                "state": state,
                "zip": zip,
                "businessName": businessName,
                "displayAddress": displayAddress,
                "placeType": item.pointOfInterestCategory?.rawValue ?? "address",
                "source": "Apple Maps",
                "lookedUpAt": ISO8601DateFormatter().string(from: Date())
            ]
        }

        private func number(_ value: Any?) -> Double? {
            if let value = value as? Double { return value }
            if let value = value as? NSNumber { return value.doubleValue }
            if let value = value as? String { return Double(value) }
            return nil
        }

        private func sendSuccess(_ requestID: String, payload: [String: Any]) {
            sendToJavaScript(["requestId": requestID, "success": true, "payload": payload])
        }

        private func sendFailure(_ requestID: String, message: String) {
            sendToJavaScript(["requestId": requestID, "success": false, "error": message])
        }

        private func sendToJavaScript(_ response: [String: Any]) {
            guard JSONSerialization.isValidJSONObject(response),
                  let data = try? JSONSerialization.data(withJSONObject: response),
                  var json = String(data: data, encoding: .utf8) else { return }
            json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript("window.fireVaultNativeMapsResolve?.(\(json));")
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            presentDialog(
                on: webView,
                title: "FireVault",
                message: message,
                actions: [UIAlertAction(title: "OK", style: .default) { _ in completionHandler() }],
                fallback: completionHandler
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            presentDialog(
                on: webView,
                title: "FireVault",
                message: message,
                actions: [
                    UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) },
                    UIAlertAction(title: "Continue", style: .default) { _ in completionHandler(true) }
                ],
                fallback: { completionHandler(false) }
            )
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            guard let presenter = presentingViewController(for: webView) else {
                completionHandler(nil)
                return
            }

            let alert = UIAlertController(title: "FireVault", message: prompt, preferredStyle: .alert)
            alert.addTextField { field in field.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            presenter.present(alert, animated: true)
        }

        private func presentDialog(
            on webView: WKWebView,
            title: String,
            message: String,
            actions: [UIAlertAction],
            fallback: @escaping () -> Void
        ) {
            guard let presenter = presentingViewController(for: webView) else {
                fallback()
                return
            }

            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            actions.forEach(alert.addAction)
            presenter.present(alert, animated: true)
        }

        private func presentingViewController(for webView: WKWebView) -> UIViewController? {
            var presenter = webView.window?.rootViewController
            while let presented = presenter?.presentedViewController {
                presenter = presented
            }
            return presenter
        }

        private func showFailure(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            loadState = .failed("Check your internet connection, then try again. Your existing FireVault data has not been changed.")
        }
    }
}

private enum FireVaultLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

private enum FireVaultTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.075)
    static let surface = Color(red: 0.075, green: 0.105, blue: 0.135)
    static let secondaryText = Color(red: 0.58, green: 0.65, blue: 0.70)
    static let accent = Color(red: 0.20, green: 0.86, blue: 0.58)
    static let warning = Color(red: 0.96, green: 0.68, blue: 0.30)
}

private struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
