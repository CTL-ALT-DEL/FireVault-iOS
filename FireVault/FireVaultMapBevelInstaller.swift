//
//  FireVaultMapBevelInstaller.swift
//  FireVault
//
//  Applies the FireVault recessed 3D bezel to every Apple Map in the app.
//

import MapKit
import QuartzCore
import SwiftUI
import UIKit

struct FireVaultMapBevelInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        context.coordinator.hostView = view
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hostView = uiView
        context.coordinator.scanSoon()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        weak var hostView: UIView?
        private var timer: Timer?

        func start() {
            scanSoon()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
                self?.scan()
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        func scanSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.scan()
            }
        }

        private func scan() {
            guard let window = hostView?.window else { return }
            decorateMaps(in: window)
        }

        private func decorateMaps(in view: UIView) {
            if let mapView = view as? MKMapView {
                FireVaultMapBevel.apply(to: mapView)
            }

            for subview in view.subviews {
                decorateMaps(in: subview)
            }
        }
    }
}

private enum FireVaultMapBevel {
    private static let containerName = "FireVault.Map.RecessedBevel"
    private static let outerStrokeName = "FireVault.Map.OuterStroke"
    private static let innerShadowName = "FireVault.Map.InnerShadow"
    private static let topLeftShadeName = "FireVault.Map.TopLeftShade"
    private static let bottomRightHighlightName = "FireVault.Map.BottomRightHighlight"
    private static let cornerRadius: CGFloat = 24

    static func apply(to mapView: MKMapView) {
        guard mapView.bounds.width > 20, mapView.bounds.height > 20 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        mapView.layer.cornerRadius = cornerRadius
        mapView.layer.cornerCurve = .continuous
        mapView.layer.masksToBounds = true
        mapView.layer.borderWidth = 1.5
        mapView.layer.borderColor = UIColor.black.withAlphaComponent(0.82).cgColor

        let container = layer(named: containerName, in: mapView.layer) ?? {
            let layer = CALayer()
            layer.name = containerName
            layer.zPosition = 10_000
            layer.masksToBounds = true
            mapView.layer.addSublayer(layer)
            return layer
        }()

        container.frame = mapView.bounds
        container.cornerRadius = cornerRadius
        container.cornerCurve = .continuous

        let outerStroke = shapeLayer(named: outerStrokeName, in: container)
        outerStroke.frame = container.bounds
        outerStroke.path = roundedPath(in: container.bounds.insetBy(dx: 1.5, dy: 1.5), radius: cornerRadius - 1.5)
        outerStroke.fillColor = UIColor.clear.cgColor
        outerStroke.strokeColor = UIColor.black.withAlphaComponent(0.78).cgColor
        outerStroke.lineWidth = 3

        let innerShadow = shapeLayer(named: innerShadowName, in: container)
        innerShadow.frame = container.bounds
        innerShadow.path = roundedPath(in: container.bounds.insetBy(dx: 4, dy: 4), radius: cornerRadius - 4)
        innerShadow.fillColor = UIColor.clear.cgColor
        innerShadow.strokeColor = UIColor.black.withAlphaComponent(0.48).cgColor
        innerShadow.lineWidth = 5

        let topLeftShade = shapeLayer(named: topLeftShadeName, in: container)
        topLeftShade.frame = container.bounds
        topLeftShade.path = topLeftPath(in: container.bounds, radius: cornerRadius)
        topLeftShade.fillColor = UIColor.clear.cgColor
        topLeftShade.strokeColor = UIColor.black.withAlphaComponent(0.88).cgColor
        topLeftShade.lineWidth = 3.2
        topLeftShade.lineCap = .round
        topLeftShade.lineJoin = .round

        let bottomRightHighlight = shapeLayer(named: bottomRightHighlightName, in: container)
        bottomRightHighlight.frame = container.bounds
        bottomRightHighlight.path = bottomRightPath(in: container.bounds, radius: cornerRadius)
        bottomRightHighlight.fillColor = UIColor.clear.cgColor
        bottomRightHighlight.strokeColor = UIColor.white.withAlphaComponent(0.27).cgColor
        bottomRightHighlight.lineWidth = 1.4
        bottomRightHighlight.lineCap = .round
        bottomRightHighlight.lineJoin = .round

        CATransaction.commit()
    }

    private static func layer(named name: String, in parent: CALayer) -> CALayer? {
        parent.sublayers?.first(where: { $0.name == name })
    }

    private static func shapeLayer(named name: String, in parent: CALayer) -> CAShapeLayer {
        if let existing = layer(named: name, in: parent) as? CAShapeLayer {
            return existing
        }

        let layer = CAShapeLayer()
        layer.name = name
        parent.addSublayer(layer)
        return layer
    }

    private static func roundedPath(in rect: CGRect, radius: CGFloat) -> CGPath {
        UIBezierPath(
            roundedRect: rect,
            cornerRadius: max(0, radius)
        ).cgPath
    }

    private static func topLeftPath(in bounds: CGRect, radius: CGFloat) -> CGPath {
        let inset: CGFloat = 3
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            controlPoint: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        return path.cgPath
    }

    private static func bottomRightPath(in bounds: CGRect, radius: CGFloat) -> CGPath {
        let inset: CGFloat = 3
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - radius),
            controlPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        return path.cgPath
    }
}
