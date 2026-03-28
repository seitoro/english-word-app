//
//  UsageQuotaManager.swift
//  English word app
//
//  Created by Codex on 2026/03/25.
//

import Foundation
import Combine

@MainActor
final class UsageQuotaManager: ObservableObject {
    @Published private(set) var remainingCreations = 0

    private let store = UsageQuotaStore()

    func refresh() {
        remainingCreations = store.snapshot().remainingCreations
    }

    func consumeCreation() {
        remainingCreations = store.consumeCreation().remainingCreations
    }

    func addRewardedCreations() {
        remainingCreations = store.addRewardedCreations().remainingCreations
    }

    func setPreviewRemainingCreations(_ remaining: Int) {
        remainingCreations = store.setRemainingCreations(remaining).remainingCreations
    }
}

private struct UsageQuotaSnapshot {
    let remainingCreations: Int
}

private struct UsageQuotaStore {
    private let baseFreeCreations = 5
    private let rewardCreations = 3
    private let remainingKey = "usage.quota.remaining"

    func snapshot() -> UsageQuotaSnapshot {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: remainingKey) == nil {
            defaults.set(baseFreeCreations, forKey: remainingKey)
            return UsageQuotaSnapshot(remainingCreations: baseFreeCreations)
        }

        let remaining = defaults.object(forKey: remainingKey) as? Int ?? baseFreeCreations
        return UsageQuotaSnapshot(remainingCreations: max(remaining, 0))
    }

    func consumeCreation() -> UsageQuotaSnapshot {
        let current = snapshot()
        let nextValue = max(current.remainingCreations - 1, 0)
        UserDefaults.standard.set(nextValue, forKey: remainingKey)
        return UsageQuotaSnapshot(remainingCreations: nextValue)
    }

    func addRewardedCreations() -> UsageQuotaSnapshot {
        let current = snapshot()
        let nextValue = current.remainingCreations + rewardCreations
        UserDefaults.standard.set(nextValue, forKey: remainingKey)
        return UsageQuotaSnapshot(remainingCreations: nextValue)
    }

    func setRemainingCreations(_ remaining: Int) -> UsageQuotaSnapshot {
        let nextValue = max(remaining, 0)
        UserDefaults.standard.set(nextValue, forKey: remainingKey)
        return UsageQuotaSnapshot(remainingCreations: nextValue)
    }
}
