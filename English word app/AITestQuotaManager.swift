//
//  AITestQuotaManager.swift
//  English word app
//
//  Created by Codex on 2026/03/30.
//

import Foundation
import Combine

@MainActor
final class AITestQuotaManager: ObservableObject {
    @Published private(set) var remainingTests = 0

    private let store = AITestQuotaStore()

    func refresh() {
        remainingTests = store.snapshot().remainingTests
    }

    func consumeTest() {
        remainingTests = store.consumeTest().remainingTests
    }

    func addRewardedTest() {
        remainingTests = store.addRewardedTest().remainingTests
    }

    func setPreviewRemainingTests(_ remaining: Int) {
        remainingTests = store.setRemainingTests(remaining).remainingTests
    }
}

private struct AITestQuotaSnapshot {
    let remainingTests: Int
}

private struct AITestQuotaStore {
    private let baseFreeTests = 3
    private let rewardTests = 2
    private let remainingKey = "ai.test.quota.remaining"

    func snapshot() -> AITestQuotaSnapshot {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: remainingKey) == nil {
            defaults.set(baseFreeTests, forKey: remainingKey)
            return AITestQuotaSnapshot(remainingTests: baseFreeTests)
        }

        let remaining = defaults.object(forKey: remainingKey) as? Int ?? baseFreeTests
        return AITestQuotaSnapshot(remainingTests: max(remaining, 0))
    }

    func consumeTest() -> AITestQuotaSnapshot {
        let current = snapshot()
        let nextValue = max(current.remainingTests - 1, 0)
        UserDefaults.standard.set(nextValue, forKey: remainingKey)
        return AITestQuotaSnapshot(remainingTests: nextValue)
    }

    func addRewardedTest() -> AITestQuotaSnapshot {
        let current = snapshot()
        let nextValue = current.remainingTests + rewardTests
        UserDefaults.standard.set(nextValue, forKey: remainingKey)
        return AITestQuotaSnapshot(remainingTests: nextValue)
    }

    func setRemainingTests(_ remaining: Int) -> AITestQuotaSnapshot {
        let nextValue = max(remaining, 0)
        UserDefaults.standard.set(nextValue, forKey: remainingKey)
        return AITestQuotaSnapshot(remainingTests: nextValue)
    }
}
