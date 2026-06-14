//
//  RewardedAdManager.swift
//  English word app
//
//  Created by Codex on 2026/03/25.
//

import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

@MainActor
final class RewardedAdManager: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var isShowingSimulationAd = false

    private let configuration: RewardedAdConfiguration

#if canImport(GoogleMobileAds)
    private var rewardedAd: RewardedAd?
    private var rewardContinuation: CheckedContinuation<Bool, Never>?
#endif
    private var simulationContinuation: CheckedContinuation<Bool, Never>?

    init(configuration: RewardedAdConfiguration = .load()) {
        self.configuration = configuration
    }

    func prepare() {
        errorMessage = nil

        if configuration.isSimulationEnabled {
            return
        }

#if canImport(GoogleMobileAds)
        guard configuration.isConfigured else {
            errorMessage = "広告設定がまだありません。"
            return
        }

        MobileAds.shared.start(completionHandler: nil)
        Task {
            await loadRewardedAd()
        }
#else
        errorMessage = "広告SDKが未設定です。"
#endif
    }

    func showRewardedAd() async -> Bool {
        errorMessage = nil

        if configuration.isSimulationEnabled {
            return await withCheckedContinuation { continuation in
                simulationContinuation = continuation
                isShowingSimulationAd = true
            }
        }

#if canImport(GoogleMobileAds)
        guard configuration.isConfigured else {
            errorMessage = "広告設定がまだありません。"
            return false
        }

        if rewardedAd == nil {
            await loadRewardedAd()
        }

        guard let rewardedAd else {
            errorMessage = errorMessage ?? "広告を読み込めませんでした。"
            return false
        }

        guard let rootViewController = Self.rootViewController() else {
            errorMessage = "広告を表示できませんでした。"
            return false
        }

        rewardedAd.fullScreenContentDelegate = self

        return await withCheckedContinuation { continuation in
            rewardContinuation = continuation
            rewardedAd.present(from: rootViewController) {
                continuation.resume(returning: true)
                self.rewardContinuation = nil
            }
        }
#else
        errorMessage = "広告SDKが未設定です。"
        return false
#endif
    }

    func completeSimulationAd() {
        isShowingSimulationAd = false
        simulationContinuation?.resume(returning: true)
        simulationContinuation = nil
    }

    func dismissSimulationAd() {
        isShowingSimulationAd = false
        simulationContinuation?.resume(returning: false)
        simulationContinuation = nil
    }

#if canImport(GoogleMobileAds)
    private func loadRewardedAd() async {
        guard isLoading == false else { return }
        guard let rewardedAdUnitID = configuration.rewardedAdUnitID, rewardedAdUnitID.isEmpty == false else {
            rewardedAd = nil
            errorMessage = "広告設定がまだありません。"
            return
        }

        isLoading = true
        defer { isLoading = false }

        let loadedAd = await withCheckedContinuation { continuation in
            RewardedAd.load(with: rewardedAdUnitID, request: Request()) { rewardedAd, _ in
                continuation.resume(returning: rewardedAd)
            }
        }

        rewardedAd = loadedAd
        rewardedAd?.fullScreenContentDelegate = self
        errorMessage = loadedAd == nil ? "広告を読み込めませんでした。" : nil
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
#endif
}

struct RewardedAdConfiguration {
    let appID: String?
    let rewardedAdUnitID: String?
    let isSimulationEnabled: Bool

    private static let debugTestAppID = "ca-app-pub-3940256099942544~1458002511"
    private static let debugTestRewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    var isConfigured: Bool {
        guard let appID, let rewardedAdUnitID else { return false }
        return appID.isEmpty == false && rewardedAdUnitID.isEmpty == false
    }

    nonisolated static func load(bundle: Bundle = .main) -> RewardedAdConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let simulationEnabledFromEnv = ["1", "true", "yes", "on"].contains(
            (environment["ENABLE_AD_SIMULATION"] ?? "").lowercased()
        )
        #if targetEnvironment(simulator)
        let simulationEnabled = true
        #elseif canImport(GoogleMobileAds)
        let simulationEnabled = simulationEnabledFromEnv
        #else
        let simulationEnabled = true
        #endif

        #if DEBUG
        let appID = debugTestAppID
        let rewardedAdUnitID = debugTestRewardedAdUnitID
        #else
        let appID = environment["ADMOB_APP_ID"]
            ?? bundle.object(forInfoDictionaryKey: "ADMOB_APP_ID") as? String
            ?? bundle.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
        let rewardedAdUnitID = environment["ADMOB_REWARDED_AD_UNIT_ID"]
            ?? bundle.object(forInfoDictionaryKey: "ADMOB_REWARDED_AD_UNIT_ID") as? String
        #endif

        return RewardedAdConfiguration(
            appID: appID,
            rewardedAdUnitID: rewardedAdUnitID,
            isSimulationEnabled: simulationEnabled
        )
    }
}

#if canImport(GoogleMobileAds)
extension RewardedAdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        rewardedAd = nil
        Task {
            await loadRewardedAd()
        }
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        errorMessage = "広告を表示できませんでした。"
        rewardContinuation?.resume(returning: false)
        rewardContinuation = nil
        rewardedAd = nil
    }
}
#endif
