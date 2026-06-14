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
    @Published private(set) var monthlyPriceDisplay = "月額 1080円"
    @Published private(set) var yearlyPriceDisplay = "年額 9800円"
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSimulationEnabled = false

#if canImport(StoreKit)
    private var premiumProductsByID: [String: Product] = [:]
    private var transactionUpdatesTask: Task<Void, Never>?
#endif
    
    private let monthlyProductID: String
    private let yearlyProductID: String
    private let simulationStore = SubscriptionSimulationStore()
    
    init(monthlyProductID: String? = nil, yearlyProductID: String? = nil) {
        let configuration = SubscriptionConfiguration.load()
        self.monthlyProductID = monthlyProductID ?? configuration.monthlyProductID
        self.yearlyProductID = yearlyProductID ?? configuration.yearlyProductID

#if canImport(StoreKit)
        self.transactionUpdatesTask = observeTransactionUpdates()
#endif
    }

    deinit {
#if canImport(StoreKit)
        transactionUpdatesTask?.cancel()
#endif
    }

    func prepare() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        isSimulationEnabled = simulationStore.isEnabled
        if isSimulationEnabled {
            hasPremiumAccess = simulationStore.hasPremiumAccess
            monthlyPriceDisplay = "月額 1080円"
            yearlyPriceDisplay = "年額 9800円"
            errorMessage = nil
            return
        }

#if canImport(StoreKit)
        await refreshEntitlements()

        do {
            let products = try await Product.products(for: [monthlyProductID, yearlyProductID])
            premiumProductsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            guard premiumProductsByID.isEmpty == false else {
                errorMessage = "サブスク商品が見つかりませんでした。App Store Connectの商品ID設定を確認してください。"
                return
            }
            if let monthlyProduct = premiumProductsByID[monthlyProductID] {
                premiumProductDisplayName = monthlyProduct.displayName
                monthlyPriceDisplay = monthlyProduct.displayPrice
            }
            if let yearlyProduct = premiumProductsByID[yearlyProductID] {
                yearlyPriceDisplay = yearlyProduct.displayPrice
            }
            errorMessage = nil
        } catch {
            errorMessage = "サブスク情報を読み込めませんでした。"
        }
#else
        monthlyPriceDisplay = "月額 1080円"
        yearlyPriceDisplay = "年額 9800円"
        errorMessage = nil
#endif
    }

    func purchasePremiumMonthly() async {
        await purchasePremium(productID: monthlyProductID)
    }

    func purchasePremiumYearly() async {
        await purchasePremium(productID: yearlyProductID)
    }

    func purchasePremium() async {
        await purchasePremiumMonthly()
    }

    private func purchasePremium(productID: String) async {
        guard isPurchasing == false else { return }

        if isSimulationEnabled {
            simulationStore.setPremiumAccess(true)
            hasPremiumAccess = true
            errorMessage = nil
            return
        }

#if canImport(StoreKit)
        if premiumProductsByID.isEmpty {
            await prepare()
        }

        guard let premiumProduct = premiumProductsByID[productID] else {
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
            ? "広告なし、AI自動テスト無制限、選んだ範囲から好きな問題数で出題できます。"
            : "無料版でもAI自動テストは何度でも使えます。Premiumでは広告なしで、選んだ範囲から好きな問題数で出題できます。"
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
                if [monthlyProductID, yearlyProductID].contains(transaction.productID) {
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

#if canImport(StoreKit)
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }

                do {
                    let transaction = try checkVerified(result)
                    await self.refreshEntitlements()
                    await transaction.finish()
                } catch {
                    continue
                }
            }
        }
    }
#endif
}

struct SubscriptionConfiguration {
    let monthlyProductID: String
    let yearlyProductID: String

    static func load(bundle: Bundle = .main) -> SubscriptionConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let monthlyProductID = environment["PREMIUM_MONTHLY_PRODUCT_ID"]
            ?? bundle.object(forInfoDictionaryKey: "PREMIUM_MONTHLY_PRODUCT_ID") as? String
            ?? "com.ryuseiokada.englishwordapp.premium.monthly1080"
        let yearlyProductID = environment["PREMIUM_YEARLY_PRODUCT_ID"]
            ?? bundle.object(forInfoDictionaryKey: "PREMIUM_YEARLY_PRODUCT_ID") as? String
            ?? "com.ryuseiokada.englishwordapp.premium.yearly9800"

        return SubscriptionConfiguration(
            monthlyProductID: monthlyProductID,
            yearlyProductID: yearlyProductID
        )
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
