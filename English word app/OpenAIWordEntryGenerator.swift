//
//  OpenAIWordEntryGenerator.swift
//  English word app
//
//  Created by 岡田瑠聖 on 2026/03/23.
//

import Foundation

struct BackendWordEntryGenerator: WordEntryGenerating {
    private let session: URLSession
    private let configuration: BackendConfiguration?

    init(
        session: URLSession = .shared,
        configuration: BackendConfiguration? = .load()
    ) {
        self.session = session
        self.configuration = configuration
    }

    var isConfigured: Bool {
        configuration != nil
    }

    func generateDraft(from input: String) async throws -> WordEntryDraft {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw WordGeneratorError.emptyInput
        }
        guard let configuration else {
            throw WordGeneratorError.backendURLMissing
        }

        var request = URLRequest(url: configuration.baseURL.appending(path: "v1/word-entry"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = WordEntryRequest(word: normalized)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WordGeneratorError.generationFailed
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if
                let backendError = try? JSONDecoder().decode(BackendErrorResponse.self, from: data),
                backendError.error == "OpenAI quota is not available"
            {
                throw WordGeneratorError.generationFailed
            }
            throw WordGeneratorError.generationFailed
        }

        let payload = try JSONDecoder().decode(WordEntryResponse.self, from: data)
        return WordEntryDraft(
            word: payload.word.trimmingCharacters(in: .whitespacesAndNewlines),
            senses: payload.senses.map {
                WordSense(
                    partOfSpeech: $0.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines),
                    meaningJapanese: $0.meaningJapanese.trimmingCharacters(in: .whitespacesAndNewlines),
                    exampleSentence: $0.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    exampleTranslation: $0.exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            },
            contextualMeanings: (payload.contextualMeanings ?? []).map {
                ContextualMeaning(
                    sentence: $0.sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    sentenceTranslation: $0.sentenceTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
                    meaningJapanese: $0.meaningJapanese.trimmingCharacters(in: .whitespacesAndNewlines),
                    explanationJapanese: $0.explanationJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            },
            generatedBy: payload.generatedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct BackendConfiguration {
    let baseURL: URL

    static func load(bundle: Bundle = .main) -> BackendConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        let baseURLString = environment["WORD_ENTRY_API_BASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "WORD_ENTRY_API_BASE_URL") as? String
            ?? "http://localhost:3000"

        guard
            baseURLString.isEmpty == false,
            let baseURL = URL(string: baseURLString)
        else {
            return nil
        }

        return BackendConfiguration(baseURL: baseURL)
    }
}

private struct WordEntryRequest: Encodable {
    let word: String
}

private struct WordEntryResponse: Decodable {
    let word: String
    let senses: [WordSenseResponse]
    let contextualMeanings: [ContextualMeaningResponse]?
    let generatedBy: String
}

private struct BackendErrorResponse: Decodable {
    let error: String
    let details: String?
}

private struct WordSenseResponse: Decodable {
    let partOfSpeech: String
    let meaningJapanese: String
    let exampleSentence: String
    let exampleTranslation: String
}

private struct ContextualMeaningResponse: Decodable {
    let sentence: String
    let sentenceTranslation: String
    let meaningJapanese: String
    let explanationJapanese: String
}
