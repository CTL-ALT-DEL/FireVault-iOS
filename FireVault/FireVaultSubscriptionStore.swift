//
//  FireVaultSubscriptionStore.swift
//  FireVault
//
//  Central StoreKit 2 product loading, purchasing, and entitlement state.
//

import Foundation
import Combine
import StoreKit
import Supabase

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

    /// Account records and on-device field tools remain available on the free
    /// tier. Paid network services use `grantsFullAccess` instead.
    var grantsLocalAccess: Bool { true }

    var isResolvedWithoutPaidAccess: Bool {
        switch self {
        case .checking, .trial, .active, .billingGracePeriod, .offlineGracePeriod:
            false
        case .billingRetry, .expired, .notSubscribed, .unavailable:
            true
        }
    }

    func planCardDetail(now: Date = Date()) -> String? {
        switch self {
        case .trial(_, let expiration):
            guard let expiration else { return "Free trial active" }
            let remaining = max(0, Int(ceil(expiration.timeIntervalSince(now) / 86_400)))
            if remaining == 0 { return "Free trial ends today" }
            return "\(remaining) free-trial day\(remaining == 1 ? "" : "s") remaining"
        case .active(_, let expiration):
            return expiration.map { "Renews \($0.formatted(date: .abbreviated, time: .omitted))" }
        case .billingGracePeriod(_, let expiration):
            return expiration.map { "Access through \($0.formatted(date: .abbreviated, time: .omitted))" }
        case .offlineGracePeriod(_, let expiration):
            return "Reconnect by \(expiration.formatted(date: .abbreviated, time: .omitted))"
        case .checking, .billingRetry, .expired, .notSubscribed, .unavailable:
            return nil
        }
    }
}

enum FireVaultPaidFeature: String, CaseIterable {
    case cloudStorage
    case aiGeneration
    case tripReportEmail

    var title: String {
        switch self {
        case .cloudStorage: "Cloud storage"
        case .aiGeneration: "AI generation"
        case .tripReportEmail: "Trip Report email"
        }
    }
}

enum FireVaultPaidFeatureError: LocalizedError, Equatable {
    case subscriptionRequired(FireVaultPaidFeature)

    var errorDescription: String? {
        switch self {
        case .subscriptionRequired(let feature):
            "Subscription Required: \(feature.title) is included with a FireVault Technician plan."
        }
    }
}

enum FireVaultPaidFeatureAccess {
    static func isAllowed(_ access: FireVaultSubscriptionAccess) -> Bool {
        access.grantsFullAccess
    }

    static func require(
        _ feature: FireVaultPaidFeature,
        access: FireVaultSubscriptionAccess
    ) throws {
        guard isAllowed(access) else {
            throw FireVaultPaidFeatureError.subscriptionRequired(feature)
        }
    }

    static func requireCached(
        _ feature: FireVaultPaidFeature,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws {
        guard FireVaultSubscriptionStore.cachedRecordChangesAreAllowed(defaults: defaults, now: now) else {
            throw FireVaultPaidFeatureError.subscriptionRequired(feature)
        }
    }
}

enum FireVaultPurchaseOutcome: Equatable {
    case purchased
    case pending
    case cancelled
}

enum FireVaultRestoreOutcome: Equatable {
    case restored
    case noActiveSubscription

    var message: String {
        switch self {
        case .restored:
            "Your FireVault Technician subscription was restored."
        case .noActiveSubscription:
            "No active FireVault Technician subscription was found for this Apple Account."
        }
    }
}

struct FireVaultCurrentEntitlementSnapshot: Equatable {
    let productID: String
    let expirationDate: Date?
    let isTrial: Bool
    let isRevoked: Bool
    let isUpgraded: Bool
    let signedTransaction: String
}

enum FireVaultCurrentEntitlementResolver {
    static func bestCandidate(
        from snapshots: [FireVaultCurrentEntitlementSnapshot],
        now: Date = Date()
    ) -> FireVaultCurrentEntitlementSnapshot? {
        snapshots
            .filter {
                FireVaultSubscriptionCatalog.productIDs.contains($0.productID)
                    && !$0.isRevoked
                    && !$0.isUpgraded
                    && ($0.expirationDate.map { $0 >= now } ?? true)
            }
            .max { lhs, rhs in
                let lhsExpiration = lhs.expirationDate ?? .distantFuture
                let rhsExpiration = rhs.expirationDate ?? .distantFuture
                return lhsExpiration < rhsExpiration
            }
    }

    static func access(
        for snapshot: FireVaultCurrentEntitlementSnapshot
    ) -> FireVaultSubscriptionAccess {
        snapshot.isTrial
            ? .trial(productID: snapshot.productID, expiresAt: snapshot.expirationDate)
            : .active(productID: snapshot.productID, expiresAt: snapshot.expirationDate)
    }
}

struct FireVaultServerSubscriptionResponse: Decodable, Equatable {
    let ok: Bool
    let updated: Bool
    let status: String
    let productID: String
    let expiresAt: String?
    let environment: String
}

enum FireVaultSubscriptionServer {
    private struct SyncRequest: Encodable {
        let signedTransaction: String
        let signedRenewalInfo: String?
    }

    static func appAccountToken() async throws -> UUID {
        try await SupabaseManager.client.auth.session.user.id
    }

    static func synchronize(
        signedTransaction: String,
        signedRenewalInfo: String? = nil
    ) async throws -> FireVaultServerSubscriptionResponse {
        try await SupabaseManager.client.functions.invoke(
            "app-store-entitlement-sync",
            options: FunctionInvokeOptions(
                body: SyncRequest(
                    signedTransaction: signedTransaction,
                    signedRenewalInfo: signedRenewalInfo
                )
            )
        )
    }
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
        _ = await refreshState()
    }

    @discardableResult
    private func refreshState(now: Date = Date()) async -> Bool {
        guard !isLoading else { return access.grantsFullAccess }
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
            let hasVerifiedPaidAccess = try await refreshVerifiedAccess()
            if !hasVerifiedPaidAccess,
               await refreshFromCurrentEntitlements(now: now) {
                lastErrorMessage = nil
                return true
            }
            lastErrorMessage = nil
            return hasVerifiedPaidAccess
        } catch {
            lastErrorMessage = error.localizedDescription
            if await refreshFromCurrentEntitlements(now: now) {
                return true
            }
            restoreCachedAccessIfNeeded()
            return false
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

        let appAccountToken = try await FireVaultSubscriptionServer.appAccountToken()
        let result = try await product.purchase(
            options: [.appAccountToken(appAccountToken)]
        )
        switch result {
        case .success(let verification):
            let transaction = try verified(verification)
            guard FireVaultSubscriptionCatalog.productIDs.contains(transaction.productID) else {
                throw FireVaultSubscriptionError.failedVerification
            }
            await synchronizeServerEntitlement(verification.jwsRepresentation)
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

    func restorePurchases() async throws -> FireVaultRestoreOutcome {
        try await AppStore.sync()

        // AppStore.sync() can cause Transaction.updates to start a refresh.
        // Let that refresh finish before performing the explicit restore check,
        // so this result never reflects state from before Apple's sync completed.
        while isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }

        return await refreshState() ? .restored : .noActiveSubscription
    }

    @discardableResult
    private func refreshVerifiedAccess() async throws -> Bool {
        guard let subscription = products.compactMap(\.subscription).first else {
            access = .unavailable
            return false
        }

        let statuses = try await subscription.status
        var bestCandidate: (
            priority: Int,
            access: FireVaultSubscriptionAccess,
            cache: CachedEntitlement?,
            signedTransaction: String
        )?

        for status in statuses {
            guard case .verified(let transaction) = status.transaction,
                  FireVaultSubscriptionCatalog.productIDs.contains(transaction.productID),
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

            let candidate: (Int, FireVaultSubscriptionAccess, CachedEntitlement?, String)
            if transaction.revocationDate != nil {
                // Keep a revoked transaction available for server reconciliation,
                // but never let an older revocation outrank another active renewal.
                candidate = (2, .expired, nil, status.transaction.jwsRepresentation)
            } else {
                switch status.state {
            case .subscribed:
                candidate = (
                    5,
                    isTrial
                        ? .trial(productID: transaction.productID, expiresAt: expirationDate)
                        : .active(productID: transaction.productID, expiresAt: expirationDate),
                    transaction.revocationDate == nil ? cache : nil,
                    status.transaction.jwsRepresentation
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
                    transaction.revocationDate == nil ? cache : nil,
                    status.transaction.jwsRepresentation
                )
            case .inBillingRetryPeriod:
                candidate = (3, .billingRetry, nil, status.transaction.jwsRepresentation)
            case .expired, .revoked:
                candidate = (2, .expired, nil, status.transaction.jwsRepresentation)
            default:
                continue
                }
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
            await synchronizeServerEntitlement(
                bestCandidate.signedTransaction,
                signedRenewalInfo: statuses
                    .first(where: { $0.transaction.jwsRepresentation == bestCandidate.signedTransaction })?
                    .renewalInfo.jwsRepresentation
            )
            return bestCandidate.access.grantsFullAccess
        } else {
            access = .notSubscribed
            clearCache()
            return false
        }
    }

    /// `Product.products(for:)` can temporarily return an empty catalog when
    /// App Store metadata or agreements are propagating. Verified current
    /// entitlements remain independently available and must still restore a
    /// subscriber's access in that state.
    private func refreshFromCurrentEntitlements(now: Date) async -> Bool {
        var snapshots: [FireVaultCurrentEntitlementSnapshot] = []

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  FireVaultSubscriptionCatalog.productIDs.contains(transaction.productID) else {
                continue
            }

            snapshots.append(
                FireVaultCurrentEntitlementSnapshot(
                    productID: transaction.productID,
                    expirationDate: transaction.expirationDate,
                    isTrial: transaction.offer?.type == .introductory
                        && transaction.offer?.paymentMode == .freeTrial,
                    isRevoked: transaction.revocationDate != nil,
                    isUpgraded: transaction.isUpgraded,
                    signedTransaction: verification.jwsRepresentation
                )
            )
        }

        guard let candidate = FireVaultCurrentEntitlementResolver.bestCandidate(
            from: snapshots,
            now: now
        ) else {
            return false
        }

        let resolvedAccess = FireVaultCurrentEntitlementResolver.access(for: candidate)
        access = resolvedAccess
        persist(
            CachedEntitlement(
                productID: candidate.productID,
                expirationDate: candidate.expirationDate,
                isTrial: candidate.isTrial,
                verifiedAt: now
            )
        )
        await synchronizeServerEntitlement(candidate.signedTransaction)
        return true
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result {
                    await self?.synchronizeServerEntitlement(result.jwsRepresentation)
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

    private func synchronizeServerEntitlement(
        _ signedTransaction: String,
        signedRenewalInfo: String? = nil
    ) async {
        do {
            _ = try await FireVaultSubscriptionServer.synchronize(
                signedTransaction: signedTransaction,
                signedRenewalInfo: signedRenewalInfo
            )
        } catch {
            // StoreKit remains the on-device source of truth. A later refresh,
            // restore, or transaction update safely retries server linking.
        }
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
