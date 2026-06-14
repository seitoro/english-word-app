import Foundation

protocol AITestGenerating {
    func generateOriginalInputQuestions(from items: [AITestPromptInput]) async throws -> [AITestPromptOutput]
}

enum AITestGenerationError: LocalizedError, Equatable {
    case backendURLMissing
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .backendURLMissing:
            return "AIテスト生成サーバーのURLを設定すると、この機能を使えます。"
        case .generationFailed:
            return "テスト問題を作成できませんでした。しばらくしてからもう一度お試しください。"
        }
    }
}

struct AITestPromptInput: Encodable, Equatable {
    let word: String
    let meaningJapanese: String
    let partOfSpeech: String
}

struct AITestPromptOutput: Decodable, Equatable {
    let word: String
    let meaningJapanese: String
    let exampleSentence: String
    let exampleTranslation: String
}

struct BackendAITestGenerator: AITestGenerating {
    private let session: URLSession
    private let configuration: BackendConfiguration?

    init(
        session: URLSession = .shared,
        configuration: BackendConfiguration? = .load()
    ) {
        self.session = session
        self.configuration = configuration
    }

    func generateOriginalInputQuestions(from items: [AITestPromptInput]) async throws -> [AITestPromptOutput] {
        guard let configuration else {
            throw AITestGenerationError.backendURLMissing
        }

        guard items.isEmpty == false else {
            return []
        }

        var request = URLRequest(url: configuration.baseURL.appending(path: "v1/ai-test-prompts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AITestPromptRequest(items: items))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
            throw AITestGenerationError.generationFailed
        }

        let payload = try JSONDecoder().decode(AITestPromptResponse.self, from: data)
        return payload.items
    }
}

private struct AITestPromptRequest: Encodable {
    let items: [AITestPromptInput]
}

private struct AITestPromptResponse: Decodable {
    let items: [AITestPromptOutput]
}
