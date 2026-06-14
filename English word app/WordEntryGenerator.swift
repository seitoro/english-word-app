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
    case entryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "英単語または英熟語を入力してください。"
        case .backendURLMissing:
            return "英単語生成サーバーのURLを設定すると、この機能を使えます。"
        case .generationFailed:
            return "英単語情報を作成できませんでした。しばらくしてからもう一度お試しください。"
        case .entryNotFound(let note):
            return note.isEmpty ? "存在しない英単語または英熟語の可能性があります。" : note
        }
    }
}

enum WordEntryGeneratorFactory {
    static func makeGenerator() -> any WordEntryGenerating {
        HybridWordEntryGenerator()
    }

    static var isAvailable: Bool {
        BackendWordEntryGenerator().isConfigured || AppleIntelligenceWordEntryGenerator().isPotentiallyAvailable
    }

    static var availabilityMessage: String {
        if BackendWordEntryGenerator().isConfigured {
            return "日本語訳、例文、和訳を生成できます。"
        }

        if AppleIntelligenceWordEntryGenerator().isPotentiallyAvailable {
            return "日本語訳、例文、和訳を生成できます。"
        }

        return "この端末では作成機能を利用できません。"
    }
}

struct HybridWordEntryGenerator: WordEntryGenerating {
    private let backend = BackendWordEntryGenerator()
    private let appleIntelligence = AppleIntelligenceWordEntryGenerator()

    func generateDraft(from input: String) async throws -> WordEntryDraft {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw WordGeneratorError.emptyInput
        }

        if backend.isConfigured {
            do {
                return try await backend.generateDraft(from: normalized)
            } catch {
                if appleIntelligence.isPotentiallyAvailable {
                    return try await appleIntelligence.generateDraft(from: normalized)
                }

                throw WordGeneratorError.generationFailed
            }
        }

        if appleIntelligence.isPotentiallyAvailable {
            return try await appleIntelligence.generateDraft(from: normalized)
        }

        throw WordGeneratorError.backendURLMissing
    }
}
