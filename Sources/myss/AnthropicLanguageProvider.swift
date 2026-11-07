import Foundation

/// Anthropic Messages APIを使う実装
struct AnthropicLanguageProvider: LanguageAssistantProvider {
    static let model = "claude-opus-5-5"
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    private static let baseURL = URL(string: "https://api.anthropic.com/v1")!

    let apiKey: String
    var session: URLSession = .shared

    func request(_ request: LanguageRequest) async throws -> LanguageResponse {
        var urlRequest = makeURLRequest(path: "messages")
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        urlRequest.timeoutInterval = 60
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: Self.body(for: request))
        let (data, response) = try await session.data(for: urlRequest)
        try Self.checkStatus(response, data: data)
        return try Self.parse(data)
    }

    func verify() async throws {
        var urlRequest = makeURLRequest(path: "models")
        urlRequest.url = urlRequest.url?.appending(queryItems: [URLQueryItem(name: "limit", value: "1")])
        urlRequest.timeoutInterval = 15
        let (data, response) = try await session.data(for: urlRequest)
        try Self.checkStatus(response, data: data)
    }

    private func makeURLRequest(path: String) -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        return request
    }

    static func body(for request: LanguageRequest) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 4096,
            "system": LanguagePrompt.system,
            "messages": LanguagePrompt.messages(for: request),
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": LanguagePrompt.responseSchema]
            ],
            "fallbacks": "default"
        ]
    }

    static func parse(_ data: Data) throws -> LanguageResponse {
        struct Message: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
            let stop_reason: String?
        }
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else {
            throw LanguageAssistantError.invalidResponse
        }
        switch message.stop_reason {
        case "refusal": throw LanguageAssistantError.refused
        case "max_tokens": throw LanguageAssistantError.truncated
        default: break
        }
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard let response = try? JSONDecoder().decode(LanguageResponse.self, from: Data(text.utf8)) else {
            throw LanguageAssistantError.invalidResponse
        }
        return LanguageResponse(
            intent: response.intent,
            summary: response.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            candidates: deduplicated(response.candidates).prefix(10).map { $0 }
        )
    }

    static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw LanguageAssistantError.invalidResponse
        }
        switch status {
        case 200..<300: return
        case 401, 403: throw LanguageAssistantError.invalidAPIKey
        case 429: throw LanguageAssistantError.rateLimited
        case 529: throw LanguageAssistantError.overloaded
        default:
            struct ErrorBody: Decodable {
                struct Detail: Decodable { let message: String }
                let error: Detail
            }
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
            throw LanguageAssistantError.server(message ?? "AIサービスでエラーが発生しました（HTTP \(status)）")
        }
    }

    private static func deduplicated(_ candidates: [LanguageCandidate]) -> [LanguageCandidate] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted else { return nil }
            return LanguageCandidate(text: text, explanation: candidate.explanation)
        }
    }
}
