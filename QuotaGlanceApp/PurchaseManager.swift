import Foundation
import Observation
import QuotaGlanceCore
import Security
import StoreKit

@Observable
@MainActor
final class PurchaseManager {
    static let productID = "com.songlabs.QuotaGlance.pro.lifetime"
    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    private(set) var accessLevel: AccessLevel = .trial
    private(set) var product: Product?
    private(set) var trialEndsAt: Date
    private(set) var purchaseError: Error?
    private let trialStore: TrialKeychainStore
    private var updatesTask: Task<Void, Never>?

    init(trialStore: TrialKeychainStore = TrialKeychainStore(), now: Date = Date()) {
        self.trialStore = trialStore
        let record = trialStore.loadOrCreate(now: now)
        trialEndsAt = record.startedAt.addingTimeInterval(Self.trialDuration)
        accessLevel = .resolve(isPurchased: false, trialEndsAt: trialEndsAt, now: record.effectiveNow)
        updatesTask = observeTransactions()
    }

    deinit { updatesTask?.cancel() }

    var hasProFeatures: Bool { accessLevel.hasProFeatures }
    var trialTimeRemaining: TimeInterval { max(0, trialEndsAt.timeIntervalSinceNow) }

    func start() async {
        await loadProduct()
        await refreshEntitlements()
    }

    func refreshEntitlements(now: Date = Date()) async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil else { continue }
            purchased = true
        }
        let record = trialStore.loadOrCreate(now: now)
        trialEndsAt = record.startedAt.addingTimeInterval(Self.trialDuration)
        accessLevel = .resolve(isPurchased: purchased, trialEndsAt: trialEndsAt, now: record.effectiveNow)
    }

    func purchase() async -> Bool {
        purchaseError = nil
        guard let product else { return false }
        do {
            switch try await product.purchase() {
            case let .success(.verified(transaction)):
                await transaction.finish()
                await refreshEntitlements()
                return accessLevel == .pro
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

    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = error
        }
    }

    private func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            purchaseError = error
        }
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                if case let .verified(transaction) = result, transaction.productID == Self.productID {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }
}

struct TrialRecord: Codable, Equatable {
    let startedAt: Date
    let lastSeenAt: Date

    var effectiveNow: Date { max(startedAt, lastSeenAt) }
}

@MainActor
final class TrialKeychainStore {
    private let service = "com.songlabs.QuotaGlance.access"
    private let account = "proTrial.v1"

    func loadOrCreate(now: Date) -> TrialRecord {
        let existing = load()
        let startedAt = existing?.startedAt ?? now
        let effectiveNow = max(now, existing?.lastSeenAt ?? now)
        let record = TrialRecord(startedAt: startedAt, lastSeenAt: effectiveNow)
        save(record)
        return record
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
