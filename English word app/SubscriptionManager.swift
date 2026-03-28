//
//  SubscriptionManager.swift
//  English word app
//
//  Created by Codex on 2026/03/24.
//

import Foundation
import Combine

#if canImport(StoreKit)
import StoreKit
#endif

@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var hasPremiumAccess = false
    @Published private(set) var premiumProductDisplayName = "プレミアム"
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSimulationEnabled = false

#if canImport(StoreKit)
    private var premiumProduct: Product?
#endif

    private let productID: String
    private let simulationStore = SubscriptionSimulationStore()

    init(productID: String? = nil) {
        let resolvedProductID = productID ?? SubscriptionConfiguration.load().premiumProductID
        self.productID = resolvedProductID
    }

    func prepare() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        isSimulationEnabled = simulationStore.isEnabled
        if isSimulationEnabled {
            hasPremiumAccess = simulationStore.hasPremiumAccess
            errorMessage = nil
            return
        }

#if canImport(StoreKit)
        await refreshEntitlements()

        do {
            let products = try await Product.products(for: [productID])
            premiumProduct = products.first
            if let premiumProduct {
                premiumProductDisplayName = premiumProduct.displayName
            }
            errorMessage = nil
        } catch {
            errorMessage = "サブスク情報を読み込めませんでした。"
        }
#else
        errorMessage = nil
#endif
    }

    func purchasePremium() async {
        guard isPurchasing == false else { return }

        if isSimulationEnabled {
            simulationStore.setPremiumAccess(true)
            hasPremiumAccess = true
            errorMessage = nil
            return
        }

#if canImport(StoreKit)
        if premiumProduct == nil {
            await prepare()
        }

        guard let premiumProduct else {
            errorMessage = "サブスク商品が見つかりませんでした。"
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await premiumProduct.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                hasPremiumAccess = true
                errorMessage = nil
                await transaction.finish()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "サブスクを購入できませんでした。"
        }
#else
        errorMessage = "この環境では購入機能を利用できません。"
#endif
    }

    func restorePurchases() async {
        guard isRestoring == false else { return }

        if isSimulationEnabled {
            errorMessage = nil
            return
        }

#if canImport(StoreKit)
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            errorMessage = nil
        } catch {
            errorMessage = "購入情報を復元できませんでした。"
        }
#else
        errorMessage = "この環境では復元機能を利用できません。"
#endif
    }

    var upgradeMessage: String {
        if isSimulationEnabled {
            return hasPremiumAccess
                ? "シミュレーション中: プレミアム状態で全機能を確認できます。"
                : "シミュレーション中: 購入ボタンでプレミアム状態を擬似的に有効化できます。"
        }

        return hasPremiumAccess
            ? "広告なし、作成無制限、音声、AI自動テストが使えます。"
            : "初回5回まで無料。以降は広告視聴で3回ずつ追加できます。プレミアムは月額1,280円です。"
    }

    func disablePremiumSimulation() {
        guard isSimulationEnabled else { return }
        simulationStore.setPremiumAccess(false)
        hasPremiumAccess = false
        errorMessage = nil
    }

    private func refreshEntitlements() async {
#if canImport(StoreKit)
        do {
            for await result in Transaction.currentEntitlements {
                let transaction = try checkVerified(result)
                if transaction.productID == productID {
                    hasPremiumAccess = true
                    errorMessage = nil
                    return
                }
            }
            hasPremiumAccess = false
        } catch {
            hasPremiumAccess = false
        }
#endif
    }
}

struct SubscriptionConfiguration {
    let premiumProductID: String

    static func load(bundle: Bundle = .main) -> SubscriptionConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let premiumProductID = environment["PREMIUM_PRODUCT_ID"]
            ?? bundle.object(forInfoDictionaryKey: "PREMIUM_PRODUCT_ID") as? String
            ?? "com.ryuseiokada.englishwordapp.multisense"

        return SubscriptionConfiguration(premiumProductID: premiumProductID)
    }
}

private struct SubscriptionSimulationStore {
    private let enabledKey = "ENABLE_SUBSCRIPTION_SIMULATION"
    private let accessKey = "debug.subscription.hasPremiumAccess"

    var isEnabled: Bool {
        let environmentValue = ProcessInfo.processInfo.environment[enabledKey]?.lowercased()
        guard let environmentValue else {
            return false
        }

        return ["1", "true", "yes", "on"].contains(environmentValue)
    }

    var hasPremiumAccess: Bool {
        UserDefaults.standard.bool(forKey: accessKey)
    }

    func setPremiumAccess(_ hasPremiumAccess: Bool) {
        UserDefaults.standard.set(hasPremiumAccess, forKey: accessKey)
    }
}

#if canImport(StoreKit)
private func checkVerified<T>(_ verificationResult: VerificationResult<T>) throws -> T {
    switch verificationResult {
    case .verified(let signedType):
        return signedType
    case .unverified:
        throw SubscriptionError.verificationFailed
    }
}

private enum SubscriptionError: Error {
    case verificationFailed
}
#endif
