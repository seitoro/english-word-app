//
//  English_word_appTests.swift
//  English word appTests
//
//  Created by 岡田瑠聖 on 2026/03/23.
//

import Foundation
import Testing
@testable import English_word_app

struct English_word_appTests {

    @Test func previewGeneratorReturnsDraftForInput() async throws {
        let generator = TestWordEntryGenerator()

        let draft = try await generator.generateDraft(from: "challenge")

        #expect(draft.word == "challenge")
        #expect(draft.senses.count == 2)
        #expect(draft.contextualMeanings.count == 1)
        #expect(draft.meaningJapanese == "テスト用の日本語訳 1")
        #expect(draft.exampleSentence.contains("challenge"))
        #expect(draft.generatedBy == "Test Generator")
    }

    @Test func generatorRejectsEmptyInput() async throws {
        let generator = TestWordEntryGenerator()

        await #expect(throws: WordGeneratorError.emptyInput) {
            try await generator.generateDraft(from: "   ")
        }
    }

    @Test func entryKindTreatsSingleTokenAsWord() {
        let senses = [
            WordSense(
                partOfSpeech: "noun",
                meaningJapanese: "挑戦",
                exampleSentence: "This is a challenge.",
                exampleTranslation: "これは挑戦です。"
            )
        ]

        #expect(entryKind(for: "challenge", senses: senses) == .word)
    }

    @Test func entryKindTreatsWhitespaceInputAsPhrase() {
        #expect(entryKind(for: "look after", senses: []) == .phrase)
    }

    @Test func entryKindTreatsCollapsedWhitespaceInputAsPhrase() {
        #expect(entryKind(for: "get   away", senses: []) == .phrase)
    }

    @Test func entryKindTreatsPhrasePartOfSpeechAsPhrase() {
        let senses = [
            WordSense(
                partOfSpeech: "phrasal verb",
                meaningJapanese: "世話をする",
                exampleSentence: "She looks after her brother.",
                exampleTranslation: "彼女は弟の世話をします。"
            )
        ]

        #expect(entryKind(for: "look", senses: senses) == .phrase)
    }

    @Test func entryKindTreatsCompositePhrasePartOfSpeechAsPhrase() {
        let senses = [
            WordSense(
                partOfSpeech: "common phrasal verb",
                meaningJapanese: "逃げる",
                exampleSentence: "The thief got away.",
                exampleTranslation: "泥棒は逃げました。"
            )
        ]

        #expect(entryKind(for: "get", senses: senses) == .phrase)
    }

    @Test func normalizeSensesForStorageKeepsFirstSenseAndRemovesDuplicates() {
        let senses = [
            WordSense(
                partOfSpeech: "verb",
                meaningJapanese: "走る",
                exampleSentence: "She runs every morning.",
                exampleTranslation: "彼女は毎朝走ります。"
            ),
            WordSense(
                partOfSpeech: "verb",
                meaningJapanese: "走る",
                exampleSentence: "She runs every morning.",
                exampleTranslation: "彼女は毎朝走ります。"
            ),
            WordSense(
                partOfSpeech: "noun",
                meaningJapanese: "経営",
                exampleSentence: "He manages the daily run of the store.",
                exampleTranslation: "彼は店の日々の運営を担当しています。"
            )
        ]

        let normalized = normalizeSensesForStorage(senses)

        #expect(normalized.count == 2)
        #expect(normalized.first?.meaningJapanese == "走る")
        #expect(normalized.last?.meaningJapanese == "経営")
    }

}

private struct TestWordEntryGenerator: WordEntryGenerating {
    func generateDraft(from input: String) async throws -> WordEntryDraft {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw WordGeneratorError.emptyInput
        }

        return WordEntryDraft(
            word: normalized,
            senses: [
                WordSense(
                    partOfSpeech: "noun",
                    meaningJapanese: "テスト用の日本語訳 1",
                    exampleSentence: "This is a test sentence with \(normalized).",
                    exampleTranslation: "\(normalized) を使ったテスト用の例文です。"
                ),
                WordSense(
                    partOfSpeech: "verb",
                    meaningJapanese: "テスト用の日本語訳 2",
                    exampleSentence: "They test how to use \(normalized) in context.",
                    exampleTranslation: "彼らは文脈の中で \(normalized) の使い方をテストします。"
                )
            ],
            contextualMeanings: [
                ContextualMeaning(
                    sentence: "They used \(normalized) in a different context.",
                    meaningJapanese: "文脈に応じた意味",
                    explanationJapanese: "文の内容によって意味の取り方が少し変わります。"
                )
            ],
            generatedBy: "Test Generator"
        )
    }
}
