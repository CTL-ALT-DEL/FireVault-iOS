//
//  FireVaultSubscriptionStore.swift
//  FireVault
//
//  Central StoreKit 2 product loading, purchasing, and entitlement state.
//

import Foundation
import Combine
import StoreKit

enum FireVaultSubscriptionCatalog {
    static let groupReferenceName = "FireVault Technician"
    static let monthlyProductID = "us.bannerman.firevault.technician.monthly"
    static let annualProductID = "us.bannerman.firevault.technician.annual"
    static let productIDs: Set<String> = [monthlyProductID, annualProductID]

    static func sortProducts(_ products: [Product]) -> [Product] {
        products.sorted { lhs, rhs in
            if lhs.id == annualProductID { return true }
            if rhs.id == annualProductID { return false }
            return lhs.price < rhs.price
        }
    }
}

enum FireVaultSubscriptionAccess: Equatable {
    case checking
    case trial(productID: String, expiresAt: Date?)
    case active(productID: String, expiresAt: Date?)
    case billingGracePeriod(productID: String, expiresAt: Date?)
    case offlineGracePeriod(productID: String, expiresAt: Date)
    case billingRetry
    case expired
    case notSubscribed
    case unavailable

    var grantsFullAccess: Bool {
        switch self {
        case .trial, .active, .billingGracePeriod, .offlineGracePeriod:
            true
        case .checking, .billingRetry, .expired, .notSubscribed, .unavailable:
            false
        }
    }

    var preservesReadOnlyAccess: Bool {
        switch self {
        case .billingRetry, .expired, .notSubscribed, .unavailable:
            true
        case .checking, .trial, .active, .billingGracePeriod, .offlineGracePeriod:
            false
        }
    }
}

enum FireVaultPurchaseOutcome: Equatable {
    case purchased
    case pending
    case cancelled
}

enum FireVaultSubscriptionError: LocalizedError {
    case failedVerification
    case productsUnavailable
    case unknownPurchaseResult

    var errorDescription: String? {
        switch self {
        case .failedVerification:
            "Apple could not verify this purchase. No subscription access was changed."
        case .productsUnavailable:
            "Apple returned no FireVault subscription products. Check your connection and try again. If this continues in TestFlight, the Paid Apps Agreement or subscription setup in App Store Connect still needs attention."
        case .unknownPurchaseResult:
            "The App Store returned an unfamiliar purchase result. Please try again."
        }
    }
}

@MainActor
final class FireVaultSubscriptionStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var introOfferEligibleProductIDs: Set<String> = []
    @Published private(set) var access: FireVaultSubscriptionAccess
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?

    private struct CachedEntitlement: Codable {
        let productID: String
        let expirationDate: Date?
        let isTrial: Bool
        let verifiedAt: Date
    }

    private enum CacheKey {
        static let entitlement = "firevault.subscription.verified-entitlement.v1"
    }

    private static let offlineGraceInterval: TimeInterval = 72 * 60 * 60
    private static let productRetryDelays: [TimeInterval] = [0, 1, 2]

    private let defaults: UserDefaults
    private var transactionUpdatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        access = Self.restoredAccess(defaults: defaults, now: now)
        transactionUpdatesTask = observeTransactionUpdates()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func start() async {
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedProducts = try await loadProductsWithRetry()
            products = FireVaultSubscriptionCatalog.sortProducts(loadedProducts)
            var eligibleProductIDs: Set<String> = []
            for product in loadedProducts {
                if let subscription = product.subscription,
                   await subscription.isEligibleForIntroOffer {
                    eligibleProductIDs.insert(product.id)
                }
            }
            introOfferEligibleProductIDs = eligibleProductIDs
            try await refreshVerifiedAccess()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            restoreCachedAccessIfNeeded()
        }
    }

    private func loadProductsWithRetry() async throws -> [Product] {
        var lastError: Error?

        for delay in Self.productRetryDelays {
            if delay > 0 {
                try await Task.sleep(for: .seconds(delay))
            }

            do {
                let loadedProducts = try await Product.products(
                    for: FireVaultSubscriptionCatalog.productIDs
                )
                if !loadedProducts.isEmpty {
                    return loadedProducts
                }
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw FireVaultSubscriptionError.productsUnavailable
    }

    func purchase(_ product: Product) async throws -> FireVaultPurchaseOutcome {
        guard FireVaultSubscriptionCatalog.productIDs.contains(product.id) else {
            throw FireVaultSubscriptionError.failedVerification
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verified(verification)
            guard FireVaultSubscriptionCatalog.productIDs.contains(transaction.productID) else {
                throw FireVaultSubscriptionError.failedVerification
            }
            await transaction.finish()
            await refresh()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw FireVaultSubscriptionError.unknownPurchaseResult
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refresh()
    }

    private func refreshVerifiedAccess() async throws {
        guard let subscription = products.compactMap(\.subscription).first else {
            access = .unavailable
            return
        }

        let statuses = try await subscription.status
        var bestCandidate: (priority: Int, access: FireVaultSubscriptionAccess, cache: CachedEntitlement?)?

        for status in statuses {
            guard case .verified(let transaction) = status.transaction,
                  FireVaultSubscriptionCatalog.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded else { continue }

            let expirationDate = transaction.expirationDate
            let isTrial = transaction.offer?.type == .introductory
                && transaction.offer?.paymentMode == .freeTrial
            let cache = CachedEntitlement(
                productID: transaction.productID,
                expirationDate: expirationDate,
                isTrial: isTrial,
                verifiedAt: Date()
            )

            let candidate: (Int, FireVaultSubscriptionAccess, CachedEntitlement?)
            switch status.state {
            case .subscribed:
                candidate = (
                    5,
                    isTrial
                        ? .trial(productID: transaction.productID, expiresAt: expirationDate)
                        : .active(productID: transaction.productID, expiresAt: expirationDate),
                    cache
                )
            case .inGracePeriod:
                let graceExpiration: Date?
                if case .verified(let renewalInfo) = status.renewalInfo {
                    graceExpiration = renewalInfo.gracePeriodExpirationDate ?? expirationDate
                } else {
                    graceExpiration = expirationDate
                }
                candidate = (
                    4,
                    .billingGracePeriod(
                        productID: transaction.productID,
                        expiresAt: graceExpiration
                    ),
                    cache
                )
            case .inBillingRetryPeriod:
                candidate = (3, .billingRetry, nil)
            case .expired, .revoked:
                candidate = (2, .expired, nil)
            default:
                continue
            }

            if bestCandidate == nil || candidate.0 > bestCandidate!.priority {
                bestCandidate = candidate
            }
        }

        if let bestCandidate {
            access = bestCandidate.access
            if let cache = bestCandidate.cache {
                persist(cache)
            } else if !bestCandidate.access.grantsFullAccess {
                clearCache()
            }
        } else {
            access = .notSubscribed
            clearCache()
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            value
        case .unverified:
            throw FireVaultSubscriptionError.failedVerification
        }
    }

    private func persist(_ entitlement: CachedEntitlement) {
        guard let data = try? JSONEncoder().encode(entitlement) else { return }
        defaults.set(data, forKey: CacheKey.entitlement)
    }

    private func clearCache() {
        defaults.removeObject(forKey: CacheKey.entitlement)
    }

    private func restoreCachedAccessIfNeeded(now: Date = Date()) {
        guard !access.grantsFullAccess else { return }
        let restored = Self.restoredAccess(defaults: defaults, now: now)
        access = restored == .checking ? .unavailable : restored
    }

    private static func restoredAccess(defaults: UserDefaults, now: Date) -> FireVaultSubscriptionAccess {
        guard let data = defaults.data(forKey: CacheKey.entitlement),
              let cached = try? JSONDecoder().decode(CachedEntitlement.self, from: data) else {
            return .checking
        }

        if let expirationDate = cached.expirationDate {
            if expirationDate >= now {
                return cached.isTrial
                    ? .trial(productID: cached.productID, expiresAt: expirationDate)
                    : .active(productID: cached.productID, expiresAt: expirationDate)
            }

            let offlineGraceExpiration = expirationDate.addingTimeInterval(offlineGraceInterval)
            if offlineGraceExpiration >= now {
                return .offlineGracePeriod(
                    productID: cached.productID,
                    expiresAt: offlineGraceExpiration
                )
            }
            return .expired
        }

        let cacheAge = now.timeIntervalSince(cached.verifiedAt)
        guard cacheAge >= 0, cacheAge <= offlineGraceInterval else { return .expired }
        return cached.isTrial
            ? .trial(productID: cached.productID, expiresAt: nil)
            : .active(productID: cached.productID, expiresAt: nil)
    }

    static func cachedRecordChangesAreAllowed(
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> Bool {
        restoredAccess(defaults: defaults, now: now).grantsFullAccess
    }
}
