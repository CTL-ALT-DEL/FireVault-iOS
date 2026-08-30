//
//  FireVaultTechnicianStorefrontView.swift
//  FireVault
//

import SwiftUI
import StoreKit
import UIKit

struct FireVaultTechnicianStorefrontView: View {
    @EnvironmentObject private var subscriptions: FireVaultSubscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedProductID = FireVaultSubscriptionCatalog.annualProductID
    @State private var isPurchasing = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 11) {
                hero
                statusCard
                benefitsCard
                planChoices
                purchaseButton
                accountActions
                renewalDisclosure
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 126)
        }
        .background(NativeShellPalette.background.ignoresSafeArea())
        .navigationTitle("FireVault Plan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if subscriptions.products.isEmpty {
                await subscriptions.refresh()
            }
        }
        .alert("FireVault Plan", isPresented: messageIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var hero: some View {
        HStack(spacing: 12) {
            FireVaultProIconBadge(size: 42, cornerRadius: 11)

            VStack(alignment: .leading, spacing: 4) {
                FireVaultProWordmark(
                    vaultColor: colorScheme == .light ? .black : .white,
                    proColor: colorScheme == .light ? .black : .white,
                    fontSize: 14,
                    proFontSize: 6,
                    tracking: 1.2,
                    hasBackground: false
                )

                Text("TECHNICIAN • INDIVIDUAL PLAN")
                    .font(.caption.bold())
                    .tracking(0.65)
                    .foregroundStyle(NativeShellPalette.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(NativeShellPalette.hairline, lineWidth: 1)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: statusPresentation.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(statusPresentation.color)
                .frame(width: 34, height: 34)
                .background(statusPresentation.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Current access")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusPresentation.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail = statusPresentation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(10)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(statusPresentation.color.opacity(0.24), lineWidth: 1)
        }
    }

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EVERY FIELD TOOL")
                .font(.headline)
                .tracking(0.6)
                .lineLimit(1)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 5
            ) {
                benefit("Nearby & CarPlay", symbol: "location.fill")
                benefit("Trip logs & reports", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                benefit("Notes & equipment", symbol: "folder.fill")
                benefit("Photos, video & scans", symbol: "camera.fill")
                benefit("Sync & backup", symbol: "arrow.triangle.2.circlepath.icloud.fill")
                benefit("Web portal", symbol: "globe")
            }
        }
        .padding(12)
        .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var planChoices: some View {
        if subscriptions.isLoading && subscriptions.products.isEmpty {
            ProgressView("Loading plans…")
                .frame(maxWidth: .infinity)
                .padding(28)
        } else if subscriptions.products.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Plans are temporarily unavailable")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Button("Try Again") {
                    Task { await subscriptions.refresh() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(NativeShellPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            VStack(spacing: 10) {
                ForEach(subscriptions.products, id: \.id) { product in
                    planButton(product)
                }
            }
        }
    }

    private func planButton(_ product: Product) -> some View {
        let isAnnual = product.id == FireVaultSubscriptionCatalog.annualProductID
        let isSelected = selectedProductID == product.id

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 13) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? NativeShellPalette.blue : .secondary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(isAnnual ? "Annual" : "Monthly")
                            .font(.headline)
                            .lineLimit(1)
                        if isAnnual {
                            Text("2 MONTHS FREE")
                                .font(.caption2.bold())
                                .tracking(0.25)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(NativeShellPalette.red, in: Capsule())
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                    Text(isAnnual ? "Best annual value" : "Cancel any time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.headline.monospacedDigit())
                        .lineLimit(1)
                    Text(isAnnual ? "per year" : "per month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                isSelected ? NativeShellPalette.blue.opacity(0.10) : NativeShellPalette.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? NativeShellPalette.blue : NativeShellPalette.hairline, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isAnnual ? "Annual" : "Monthly"), \(product.displayPrice)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var purchaseButton: some View {
        Button {
            purchaseSelection()
        } label: {
            HStack {
                Spacer()
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(purchaseButtonTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Spacer()
            }
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(NativeShellPalette.red, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .disabled(selectedProduct == nil || isPurchasing)
        .opacity(selectedProduct == nil || isPurchasing ? 0.58 : 1)
    }

    private var accountActions: some View {
        HStack(spacing: 10) {
            Button {
                restorePurchases()
            } label: {
                Label("Restore", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            Button {
                manageSubscription()
            } label: {
                Label("Manage", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
        .foregroundStyle(NativeShellPalette.blue)
    }

    private var renewalDisclosure: some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                ForEach(renewalDisclosureLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                Link("Privacy Policy", destination: FireVaultPublisherInfo.privacyPolicyURL)
                Link("Terms of Use", destination: FireVaultPublisherInfo.termsOfUseURL)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(NativeShellPalette.blue)
            .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 18)
    }

    private func benefit(_ title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(NativeShellPalette.blue)
                .frame(width: 20)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 22)
    }

    private var selectedProduct: Product? {
        subscriptions.products.first { $0.id == selectedProductID }
            ?? subscriptions.products.first
    }

    private var selectedProductIsEligibleForTrial: Bool {
        guard let selectedProduct else { return false }
        return subscriptions.introOfferEligibleProductIDs.contains(selectedProduct.id)
    }

    private var purchaseButtonTitle: String {
        if subscriptions.access.grantsFullAccess { return "Change Plan" }
        return selectedProductIsEligibleForTrial ? "Start 14-Day Free Trial" : "Subscribe"
    }

    private var renewalDisclosureLines: [String] {
        let opening = selectedProductIsEligibleForTrial
            ? "Apple charges your selected plan after the 14-day trial."
            : "Apple charges your selected plan when you confirm."
        return [
            opening,
            "Renews automatically unless canceled 24 hours before renewal.",
            "Manage or cancel anytime in App Store settings."
        ]
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )
    }

    private func purchaseSelection() {
        guard let selectedProduct else { return }
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                switch try await subscriptions.purchase(selectedProduct) {
                case .purchased:
                    message = "Your FireVault Technician access is active."
                case .pending:
                    message = "Apple is still processing this purchase. Access will update automatically after approval."
                case .cancelled:
                    break
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func restorePurchases() {
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                try await subscriptions.restorePurchases()
                message = subscriptions.access.grantsFullAccess
                    ? "Your FireVault Technician subscription was restored."
                    : "No active FireVault Technician subscription was found for this Apple Account."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func manageSubscription() {
        Task {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else {
                message = "Subscription settings are not available right now."
                return
            }
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                await subscriptions.refresh()
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private var statusPresentation: (title: String, detail: String?, symbol: String, color: Color) {
        switch subscriptions.access {
        case .checking:
            ("Checking subscription…", nil, "hourglass", .secondary)
        case .trial(_, let expiration):
            ("Free trial active", dateDetail("Trial ends", expiration), "sparkles", NativeShellPalette.green)
        case .active(_, let expiration):
            ("Technician plan active", dateDetail("Renews", expiration), "checkmark.seal.fill", NativeShellPalette.green)
        case .billingGracePeriod(_, let expiration):
            ("Billing grace period", dateDetail("Access through", expiration), "clock.badge.checkmark", .orange)
        case .offlineGracePeriod(_, let expiration):
            ("Temporary offline access", dateDetail("Reconnect by", expiration), "wifi.slash", .orange)
        case .billingRetry:
            ("Payment needs attention", "Existing records remain available.", "creditcard.trianglebadge.exclamationmark", .orange)
        case .expired:
            ("Subscription expired", "Existing records remain available.", "calendar.badge.exclamationmark", .secondary)
        case .notSubscribed:
            (
                "No active plan",
                selectedProductIsEligibleForTrial ? "Start with 14 days free." : "Choose a monthly or annual plan.",
                "person.crop.circle.badge.plus",
                NativeShellPalette.blue
            )
        case .unavailable:
            ("Plans unavailable", "Try again when connected.", "wifi.exclamationmark", .secondary)
        }
    }

    private func dateDetail(_ prefix: String, _ date: Date?) -> String? {
        guard let date else { return nil }
        return "\(prefix) \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
