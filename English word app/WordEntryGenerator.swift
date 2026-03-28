//
//  WordEntryGenerator.swift
//  English word app
//
//  Created by 岡田瑠聖 on 2026/03/23.
//

import Foundation

protocol WordEntryGenerating {
    func generateDraft(from input: String) async throws -> WordEntryDraft
}

enum WordGeneratorError: LocalizedError, Equatable {
    case emptyInput
    case backendURLMissing
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "英単語または熟語を入力してください。"
        case .backendURLMissing:
            return "単語生成サーバーのURLを設定すると、この機能を使えます。"
        case .generationFailed:
            return "単語情報を作成できませんでした。しばらくしてからもう一度お試しください。"
        }
    }
}

enum WordEntryGeneratorFactory {
    static func makeGenerator() -> any WordEntryGenerating {
        HybridWordEntryGenerator()
    }

    static var isAvailable: Bool {
        BackendWordEntryGenerator().isConfigured
    }

    static var availabilityMessage: String {
        if BackendWordEntryGenerator().isConfigured {
            return "日本語訳、例文、和訳を生成できます。"
        }

        return "WORD_ENTRY_API_BASE_URL を設定すると、この機能を使えます。"
    }
}

struct HybridWordEntryGenerator: WordEntryGenerating {
    private let backend = BackendWordEntryGenerator()

    func generateDraft(from input: String) async throws -> WordEntryDraft {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw WordGeneratorError.emptyInput
        }

        guard backend.isConfigured else {
            throw WordGeneratorError.backendURLMissing
        }

        do {
            return try await backend.generateDraft(from: normalized)
        } catch {
            throw WordGeneratorError.generationFailed
        }
    }
}
