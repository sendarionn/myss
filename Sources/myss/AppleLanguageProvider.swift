import Foundation
import FoundationModels

@Generable
enum GeneratedIntent {
    case findExpression
    case explainExpression
    case rewrite
    case compareExpressions
    case continueText
    case unknown

    var languageIntent: LanguageIntent {
        switch self {
        case .findExpression: .findExpression
        case .explainExpression: .explainExpression
        case .rewrite: .rewrite
        case .compareExpressions: .compareExpressions
        case .continueText: .continueText
        case .unknown: .unknown
        }
    }
}

@Generable
struct GeneratedCandidate {
    @Guide(description: "文章へそのまま入力する文字列　引用符、番号、説明を含めない")
    var text: String
    @Guide(description: "ニュアンスや使い分けを1文以内で")
    var explanation: String
}

/// 生成順にintent、説明対象、要約、候補を決めさせる
@Generable
struct GeneratedLanguageResponse {
    @Guide(description: "ユーザーが求めている言語操作")
    var intent: GeneratedIntent
    @Guide(description: "説明対象として認識した語句　説明対象がなければnull")
    var targetExpression: String?
    @Guide(description: "最大2文の日本語　explainExpressionでは指定された分野や文脈での意味")
    var summary: String
    @Guide(description: "候補　explainExpressionでは原則として空", .maximumCount(10))
    var candidates: [GeneratedCandidate]

    var languageResponse: LanguageResponse {
        LanguageResponse.normalized(
            intent: intent.languageIntent,
            targetExpression: targetExpression,
            summary: summary,
            candidates: candidates.map { LanguageCandidate(text: $0.text, explanation: $0.explanation) }
        )
    }
}

/// Apple IntelligenceのオンデバイスモデルSystemLanguageModel.defaultだけを使う
struct AppleLanguageProvider: LanguageAssistantProvider {
    static var availability: ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable: .unavailable
        }
    }

    /// ショートカット直後の初回応答を速くするため、モデル資源と指示を事前に読み込む
    static func prewarm() {
        guard availability.isAvailable else { return }
        makeSession().prewarm()
    }

    /// キャンセルされた古い生成が次の結果へ混入しないよう、問い合わせごとに新しいセッションを作る
    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: .default, instructions: LanguagePrompt.system)
    }

    func request(_ request: LanguageRequest) async throws -> LanguageResponse {
        let availability = Self.availability
        guard availability.isAvailable else { throw LanguageAssistantError.modelUnavailable(availability) }
        do {
            let response = try await Self.makeSession().respond(
                to: LanguagePrompt.prompt(for: request),
                generating: GeneratedLanguageResponse.self
            )
            return response.content.languageResponse
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }
    }

    static func map(_ error: Error) -> LanguageAssistantError {
        if #available(macOS 27.0, *) {
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded: return .contextTooLarge
                case .guardrailViolation, .refusal: return .refused
                case .unsupportedLanguageOrLocale: return .unsupportedLanguage
                case .rateLimited: return .busy
                default: return .generationFailed(error.localizedDescription)
                }
            }
            if error is GeneratedContent.ParsingError { return .invalidResponse }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .contextTooLarge
            case .guardrailViolation, .refusal: return .refused
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .rateLimited, .concurrentRequests: return .busy
            case .assetsUnavailable: return .modelUnavailable(.modelNotReady)
            case .decodingFailure: return .invalidResponse
            default: return .generationFailed(error.localizedDescription)
            }
        }
        return .generationFailed(error.localizedDescription)
    }
}
