@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation

struct CapturedContext {
    let selectedText: String
    let surroundingText: String
    /// surroundingText内のカーソル位置（UTF-16）　選択がある場合はnil
    let cursorOffset: Int?
    let source: ContextSource
    let targetElement: AXUIElement?
    let sourceApplication: NSRunningApplication?

    static let empty = CapturedContext(
        selectedText: "", surroundingText: "", cursorOffset: nil,
        source: .none, targetElement: nil, sourceApplication: nil
    )

    var isEmpty: Bool { selectedText.isEmpty && surroundingText.isEmpty }
}

enum ContextSource: String {
    case selection = "選択テキスト"
    case sentence = "カーソル周辺"
    case none = "手入力"
}

enum LanguageIntent: String, Codable, Hashable, Sendable, CaseIterable {
    case findExpression = "find_expression"
    case explainExpression = "explain_expression"
    case rewrite
    case compareExpressions = "compare_expressions"
    case continueText = "continue_text"
    case unknown
}

struct LanguageCandidate: Codable, Hashable, Sendable, Identifiable {
    let text: String
    let explanation: String
    var id: String { text }
}

struct LanguageResponse: Codable, Hashable, Sendable {
    let intent: LanguageIntent
    /// AIが説明対象として認識した語句　なければnil
    let targetExpression: String?
    let summary: String
    let candidates: [LanguageCandidate]

    init(intent: LanguageIntent, targetExpression: String? = nil, summary: String, candidates: [LanguageCandidate]) {
        self.intent = intent
        self.targetExpression = targetExpression
        self.summary = summary
        self.candidates = candidates
    }

    /// 生成結果を表示用に整える　空白除去、空の対象語のnil化、候補の重複除去、最大10件
    static func normalized(
        intent: LanguageIntent, targetExpression: String?, summary: String, candidates: [LanguageCandidate]
    ) -> LanguageResponse {
        let target = targetExpression?.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        let unique = candidates.compactMap { candidate -> LanguageCandidate? in
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text).inserted else { return nil }
            return LanguageCandidate(text: text, explanation: candidate.explanation.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return LanguageResponse(
            intent: intent,
            targetExpression: target?.isEmpty == false ? target : nil,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            candidates: Array(unique.prefix(10))
        )
    }
}

/// 現在の入力欄の文字列だけで毎回意図を推定させる　過去の回答は会話として積まない
struct LanguageRequest: Hashable, Sendable {
    var query: String
    /// 選択元の周辺文章　入力欄に選択文字列が残っている間だけ補助情報として渡す
    var surroundingContext: String = ""

    /// 選択文字列が入力欄から消えたら、周辺文章は現在の入力と無関係とみなして渡さない
    static func make(query: String, selectedText: String, surroundingText: String) -> LanguageRequest {
        let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepsSelection = !selected.isEmpty && query.contains(selected)
        return LanguageRequest(query: query, surroundingContext: keepsSelection ? surroundingText : "")
    }
}

protocol LanguageAssistantProvider: Sendable {
    func request(_ request: LanguageRequest) async throws -> LanguageResponse
}

/// オンデバイスモデルの利用可否
enum ModelAvailability: Equatable, Sendable {
    case available
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case unavailable

    var isAvailable: Bool { self == .available }

    var label: String {
        switch self {
        case .available: "利用可能"
        case .appleIntelligenceNotEnabled: "Apple Intelligenceが無効です　システム設定で有効にしてください"
        case .deviceNotEligible: "このMacはApple Intelligenceに対応していません"
        case .modelNotReady: "オンデバイスモデルを準備中です"
        case .unavailable: "このMacではオンデバイスAIを利用できません"
        }
    }
}

enum LanguageAssistantError: LocalizedError, Equatable {
    case modelUnavailable(ModelAvailability)
    case contextTooLarge
    case refused
    case unsupportedLanguage
    case busy
    case invalidResponse
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .modelUnavailable(availability): availability.label
        case .contextTooLarge: "文章が長すぎるため処理できませんでした"
        case .refused: "この内容には回答できませんでした"
        case .unsupportedLanguage: "この言語はオンデバイスAIで処理できません"
        case .busy: "オンデバイスAIが処理中です　少し待ってから再試行してください"
        case .invalidResponse: "オンデバイスAIから結果を取得できませんでした"
        case let .generationFailed(message): message
        }
    }
}
