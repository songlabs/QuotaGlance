import Foundation
import Observation
import QuotaGlanceCore
import Security
import StoreKit

@Observable
@MainActor
final class PurchaseManager {
    static let trialProductID = "com.songlabs.QuotaGlance.pro.trial7d"
    static let lifetimeProductID = "com.songlabs.QuotaGlance.pro.lifetime"
    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    private(set) var accessLevel: AccessLevel = .free
    private(set) var trialProduct: Product?
    private(set) var lifetimeProduct: Product?
    private(set) var trialEndsAt: Date?
    private(set) var hasTrialTransaction = false
    private(set) var purchaseError: Error?
    private let trialStore: TrialKeychainStore
    private var updatesTask: Task<Void, Never>?
#if DEBUG
    private var screenshotLifetimePrice: String?
#endif

    init(trialStore: TrialKeychainStore = TrialKeychainStore()) {
        self.trialStore = trialStore
        updatesTask = observeTransactions()
    }

    isolated deinit { updatesTask?.cancel() }

    var hasProFeatures: Bool { accessLevel.hasProFeatures }
    var canStartTrial: Bool { !hasTrialTransaction && accessLevel != .pro }
    var lifetimeDisplayPrice: String? {
#if DEBUG
        screenshotLifetimePrice ?? lifetimeProduct?.displayPrice
#else
        lifetimeProduct?.displayPrice
#endif
    }
    var canPresentTrialPurchase: Bool {
#if DEBUG
        trialProduct != nil || screenshotLifetimePrice != nil
#else
        trialProduct != nil
#endif
    }
    var canPresentLifetimePurchase: Bool { lifetimeDisplayPrice != nil }
    var trialTimeRemaining: TimeInterval {
        guard let trialEndsAt else { return 0 }
        return max(0, trialEndsAt.timeIntervalSince(trialStore.effectiveNow(now: Date())))
    }

    func start() async {
        await loadProduct()
        await refreshEntitlements()
    }

    func refreshEntitlements(now: Date = Date()) async {
        var hasLifetimePurchase = false
        var trialPurchaseDate: Date?
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.lifetimeProductID:
                hasLifetimePurchase = true
            case Self.trialProductID:
                if trialPurchaseDate.map({ transaction.purchaseDate < $0 }) ?? true {
                    trialPurchaseDate = transaction.purchaseDate
                }
            default:
                continue
            }
        }
        hasTrialTransaction = trialPurchaseDate != nil
        trialEndsAt = trialPurchaseDate?.addingTimeInterval(Self.trialDuration)
        let effectiveNow = trialPurchaseDate == nil ? now : trialStore.record(now: now)
        accessLevel = .resolve(
            hasLifetimePurchase: hasLifetimePurchase,
            trialPurchaseDate: trialPurchaseDate,
            trialDuration: Self.trialDuration,
            now: effectiveNow
        )
    }

    func purchaseTrial() async -> Bool {
        await purchase(product: trialProduct, expectedProductID: Self.trialProductID, expectedAccess: .trial)
    }

    func purchaseLifetime() async -> Bool {
        await purchase(product: lifetimeProduct, expectedProductID: Self.lifetimeProductID, expectedAccess: .pro)
    }

    private func purchase(product: Product?, expectedProductID: String, expectedAccess: AccessLevel) async -> Bool {
        purchaseError = nil
        guard let product else { return false }
        do {
            switch try await product.purchase() {
            case let .success(.verified(transaction)):
                guard transaction.productID == expectedProductID else { return false }
                await transaction.finish()
                await refreshEntitlements()
                return accessLevel == expectedAccess || accessLevel == .pro
            case .success(.unverified):
                return false
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error
            return false
        }
    }

    func restorePurchases() async -> Bool {
        purchaseError = nil
        let result = await performRestore(
            sync: { try await AppStore.sync() },
            refreshEntitlements: { await self.refreshEntitlements() }
        )
        switch result {
        case .success:
            return true
        case let .failure(error):
            purchaseError = error
            return false
        }
    }

#if DEBUG
    func configureForScreenshot(
        accessLevel: AccessLevel,
        trialEndsAt: Date?,
        hasTrialTransaction: Bool,
        lifetimePrice: String
    ) {
        self.accessLevel = accessLevel
        self.trialEndsAt = trialEndsAt
        self.hasTrialTransaction = hasTrialTransaction
        screenshotLifetimePrice = lifetimePrice
    }
#endif

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.trialProductID, Self.lifetimeProductID])
            trialProduct = products.first { $0.id == Self.trialProductID }
            lifetimeProduct = products.first { $0.id == Self.lifetimeProductID }
        } catch {
            purchaseError = error
        }
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case let .verified(transaction) = result,
                   [Self.trialProductID, Self.lifetimeProductID].contains(transaction.productID) {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }
}

struct TrialRecord: Codable, Equatable {
    let lastSeenAt: Date
}

@MainActor
final class TrialKeychainStore {
    private let service = "com.songlabs.QuotaGlance.access"
    private let account = "proTrial.v1"

    func record(now: Date) -> Date {
        let existing = load()
        let effectiveNow = max(now, existing?.lastSeenAt ?? now)
        save(TrialRecord(lastSeenAt: effectiveNow))
        return effectiveNow
    }

    func effectiveNow(now: Date) -> Date {
        max(now, load()?.lastSeenAt ?? now)
    }

    private func load() -> TrialRecord? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TrialRecord.self, from: data)
    }

    private func save(_ record: TrialRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary) == errSecSuccess { return }
        var query = baseQuery
        attributes.forEach { query[$0.key] = $0.value }
        SecItemAdd(query as CFDictionary, nil)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
