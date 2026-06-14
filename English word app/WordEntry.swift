//
//  WordEntry.swift
//  English word app
//
//  Created by 岡田瑠聖 on 2026/03/23.
//

import Foundation
import SwiftData

struct WordSense: Codable, Equatable, Identifiable {
    let partOfSpeech: String
    let meaningJapanese: String
    let exampleSentence: String
    let exampleTranslation: String

    var id: String {
        [
            partOfSpeech,
            meaningJapanese,
            exampleSentence,
            exampleTranslation
        ].joined(separator: "::")
    }
}

func normalizeSensesForStorage(_ senses: [WordSense]) -> [WordSense] {
    var seen = Set<String>()

    return senses.compactMap { sense in
        let normalizedSense = WordSense(
            partOfSpeech: sense.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines),
            meaningJapanese: sense.meaningJapanese.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleSentence: sense.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleTranslation: sense.exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard normalizedSense.meaningJapanese.isEmpty == false else {
            return nil
        }

        let key = normalizedSense.id
        guard seen.insert(key).inserted else {
            return nil
        }

        return normalizedSense
    }
}

struct ContextualMeaning: Codable, Equatable, Identifiable {
    let sentence: String
    let sentenceTranslation: String
    let meaningJapanese: String
    let explanationJapanese: String

    var id: String {
        [sentence, sentenceTranslation, meaningJapanese, explanationJapanese].joined(separator: "::")
    }

    enum CodingKeys: String, CodingKey {
        case sentence
        case sentenceTranslation
        case meaningJapanese
        case explanationJapanese
    }

    init(
        sentence: String,
        sentenceTranslation: String = "",
        meaningJapanese: String,
        explanationJapanese: String
    ) {
        self.sentence = sentence
        self.sentenceTranslation = sentenceTranslation
        self.meaningJapanese = meaningJapanese
        self.explanationJapanese = explanationJapanese
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sentence = try container.decode(String.self, forKey: .sentence)
        sentenceTranslation = try container.decodeIfPresent(String.self, forKey: .sentenceTranslation) ?? ""
        meaningJapanese = try container.decode(String.self, forKey: .meaningJapanese)
        explanationJapanese = try container.decode(String.self, forKey: .explanationJapanese)
    }
}

@Model
final class WordEntry {
    var word: String
    var meaningJapanese: String
    var exampleSentence: String
    var exampleTranslation: String
    var sensesPayload: String
    var contextualMeaningsPayload: String
    var generatedBy: String
    var createdAt: Date

    init(
        word: String,
        meaningJapanese: String,
        exampleSentence: String,
        exampleTranslation: String,
        senses: [WordSense] = [],
        contextualMeanings: [ContextualMeaning] = [],
        generatedBy: String,
        createdAt: Date = .now
    ) {
        self.word = word
        self.meaningJapanese = meaningJapanese
        self.exampleSentence = exampleSentence
        self.exampleTranslation = exampleTranslation
        self.sensesPayload = WordEntry.encodeSenses(senses)
        self.contextualMeaningsPayload = WordEntry.encodeContextualMeanings(contextualMeanings)
        self.generatedBy = generatedBy
        self.createdAt = createdAt
    }

    var senses: [WordSense] {
        if let decoded = try? JSONDecoder().decode([WordSense].self, from: Data(sensesPayload.utf8)),
           decoded.isEmpty == false {
            return decoded
        }

        return [
            WordSense(
                partOfSpeech: "",
                meaningJapanese: meaningJapanese,
                exampleSentence: exampleSentence,
                exampleTranslation: exampleTranslation
            )
        ]
    }

    var contextualMeanings: [ContextualMeaning] {
        if let decoded = try? JSONDecoder().decode([ContextualMeaning].self, from: Data(contextualMeaningsPayload.utf8)) {
            return decoded
        }

        return []
    }

    private static func encodeSenses(_ senses: [WordSense]) -> String {
        guard
            senses.isEmpty == false,
            let data = try? JSONEncoder().encode(senses),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return string
    }

    private static func encodeContextualMeanings(_ contextualMeanings: [ContextualMeaning]) -> String {
        guard
            let data = try? JSONEncoder().encode(contextualMeanings),
            let string = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }

        return string
    }
}

struct WordEntryDraft: Equatable {
    let word: String
    let senses: [WordSense]
    let contextualMeanings: [ContextualMeaning]
    let generatedBy: String

    var primarySense: WordSense {
        senses.first ?? WordSense(
            partOfSpeech: "",
            meaningJapanese: "",
            exampleSentence: "",
            exampleTranslation: ""
        )
    }

    var meaningJapanese: String {
        primarySense.meaningJapanese
    }

    var exampleSentence: String {
        primarySense.exampleSentence
    }

    var exampleTranslation: String {
        primarySense.exampleTranslation
    }
}
