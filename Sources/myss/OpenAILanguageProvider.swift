import Foundation

/// OpenAI Responses APIを使う実装
struct OpenAILanguageProvider: LanguageAssistantProvider {
    static let model = "gpt-6-luna"
    static let maximumOutputTokens = 1200
    private static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!

    let apiKey: String
    var session: URLSession = .shared

    func request(_ request: LanguageRequest) async throws -> LanguageResponse {
        var urlRequest = try Self.urlRequest(apiKey: apiKey, body: Self.body(for: request))
        urlRequest.timeoutInterval = 60
        let (data, response) = try await session.data(for: urlRequest)
        try Self.checkStatus(response, data: data)
        return try Self.parse(data)
    }

    /// List models権限を要求しないよう、本番と同じ/v1/responsesへ最小の問い合わせを送る
    func verify() async throws {
        var urlRequest = try Self.urlRequest(apiKey: apiKey, body: Self.verificationBody)
        urlRequest.timeoutInterval = 20
        let (data, response) = try await session.data(for: urlRequest)
        try Self.checkStatus(response, data: data)
    }

    static func urlRequest(apiKey: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: responsesURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func body(for request: LanguageRequest) -> [String: Any] {
        [
            "model": model,
            "reasoning": ["effort": "none"],
            "instructions": LanguagePrompt.system,
            "input": LanguagePrompt.messages(for: request),
            "max_output_tokens": maximumOutputTokens,
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "language_response",
                    "strict": true,
                    "schema": LanguagePrompt.responseSchema
                ]
            ]
        ]
    }

    static var verificationBody: [String: Any] {
        [
            "model": model,
            "reasoning": ["effort": "none"],
            "input": "「OK」とだけ返してください",
            "max_output_tokens": 16,
            "store": false
        ]
    }

    static func parse(_ data: Data) throws -> LanguageResponse {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Content: Decodable {
                    let type: String
                    let text: String?
                    let refusal: String?
                }
                let type: String
                let content: [Content]?
            }
            struct IncompleteDetails: Decodable { let reason: String? }
            let status: String?
            let incomplete_details: IncompleteDetails?
            let output: [Item]?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw LanguageAssistantError.invalidResponse
        }
        let contents = (response.output ?? []).filter { $0.type == "message" }.flatMap { $0.content ?? [] }
        if contents.contains(where: { $0.type == "refusal" }) { throw LanguageAssistantError.refused }
        if response.status == "incomplete" {
            throw response.incomplete_details?.reason == "content_filter"
                ? LanguageAssistantError.refused
                : LanguageAssistantError.truncated
        }
        let text = contents.filter { $0.type == "output_text" }.compactMap(\.text).joined()
        guard !text.isEmpty,
              let decoded = try? JSONDecoder().decode(LanguageResponse.self, from: Data(text.utf8))
        else { throw LanguageAssistantError.invalidResponse }
        let target = decoded.targetExpression?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LanguageResponse(
            intent: decoded.intent,
            targetExpression: target?.isEmpty == false ? target : nil,
            summary: decoded.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            candidates: Array(deduplicated(decoded.candidates).prefix(10))
        )
    }

    static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw LanguageAssistantError.invalidResponse
        }
        struct ErrorBody: Decodable {
            struct Detail: Decodable {
                let message: String?
                let code: String?
            }
            let error: Detail
        }
        let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
        switch status {
        case 200..<300: return
        case 401: throw LanguageAssistantError.invalidAPIKey
        case 403: throw LanguageAssistantError.insufficientPermission
        case 429:
            throw detail?.code == "insufficient_quota" ? LanguageAssistantError.quotaExceeded : LanguageAssistantError.rateLimited
        case 500..<600: throw LanguageAssistantError.temporaryServerError
        default:
            throw LanguageAssistantError.server(detail?.message ?? "OpenAI APIでエラーが発生しました（HTTP \(status)）")
        }
    }

    private static func deduplicated(_ candidates: [LanguageCandidate]) -> [LanguageCandidate] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted else { return nil }
            return LanguageCandidate(
                text: text,
                explanation: candidate.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
