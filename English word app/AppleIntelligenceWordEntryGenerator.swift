//
//  AppleIntelligenceWordEntryGenerator.swift
//  English word app
//
//  Created by 岡田瑠聖 on 2026/03/23.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AppleIntelligenceWordEntryGenerator: WordEntryGenerating {
    enum AvailabilityState: Equatable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unknown
    }

    var availability: AvailabilityState {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            @unknown default:
                return .unknown
            }
        }
#endif
        return .unknown
    }

    var isPotentiallyAvailable: Bool {
#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
#endif
        return false
    }

    func generateDraft(from input: String) async throws -> WordEntryDraft {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw WordGeneratorError.emptyInput
        }

#if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(
                instructions: """
                You create English vocabulary notebook entries for Japanese learners.
                Return one structured entry with:
                - the original English word
                - multiple common meanings when the word is polysemous
                - one simple English example sentence for each meaning
                - a natural Japanese translation of each sentence
                Put the most common and representative learner meaning first.
                Keep the output suitable for middle school and high school learners.
                """
            )

            let response = try await session.respond(
                to: """
                Create a vocabulary notebook entry for this English word: \(normalized)
                Keep the word exactly as entered.
                Include up to 6 useful senses.
                Order the senses from the most representative meaning to less common ones.
                """,
                generating: AppleIntelligenceWordEntry.self
            )

            let content = response.content
            return WordEntryDraft(
                word: content.word.trimmingCharacters(in: .whitespacesAndNewlines),
                senses: normalizeSensesForStorage(content.senses.map {
                    WordSense(
                        partOfSpeech: $0.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines),
                        meaningJapanese: $0.meaningJapanese.trimmingCharacters(in: .whitespacesAndNewlines),
                        exampleSentence: $0.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        exampleTranslation: $0.exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }),
                contextualMeanings: [],
                generatedBy: "Apple Intelligence"
            )
        }
#endif

        throw WordGeneratorError.generationFailed
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleIntelligenceWordEntry {
    @Guide(description: "Repeat the original English word exactly as the user entered it.")
    let word: String

    @Guide(description: "The common meanings of the word. Include up to 6 useful senses without duplicates.")
    let senses: [AppleIntelligenceWordSense]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleIntelligenceWordSense {
    @Guide(description: "A short part of speech label such as noun, verb, adjective, adverb, or preposition.")
    let partOfSpeech: String

    @Guide(description: "A short, natural Japanese translation for this sense.")
    let meaningJapanese: String

    @Guide(description: "One simple English example sentence using the word naturally for this sense.")
    let exampleSentence: String

    @Guide(description: "A natural Japanese translation of the example sentence.")
    let exampleTranslation: String
}
#endif
