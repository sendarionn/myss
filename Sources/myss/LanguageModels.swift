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

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = LanguageIntent(rawValue: value) ?? .unknown
    }
}

struct LanguageCandidate: Codable, Hashable, Sendable, Identifiable {
    let text: String
    let explanation: String
    var id: String { text }
}

struct LanguageResponse: Codable, Hashable, Sendable {
    let intent: LanguageIntent
    let summary: String
    let candidates: [LanguageCandidate]
}

struct LanguageTurn: Hashable, Sendable {
    let instruction: String
    let response: LanguageResponse
}

struct LanguageRequest: Hashable, Sendable {
    var selectedText: String
    var surroundingContext: String
    var cursorOffset: Int?
    /// 同じパネル内で完了した過去の指示と回答
    var history: [LanguageTurn]
    var manualInstruction: String
}

protocol LanguageAssistantProvider: Sendable {
    func request(_ request: LanguageRequest) async throws -> LanguageResponse
    func verify() async throws
}

enum LanguageAssistantError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case overloaded
    case refused
    case truncated
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "APIキーが未設定です"
        case .invalidAPIKey: "APIキーが無効です"
        case .rateLimited: "リクエストが多すぎます　少し待ってから再試行してください"
        case .overloaded: "AIサービスが混雑しています　少し待ってから再試行してください"
        case .refused: "この内容には回答できませんでした"
        case .truncated: "回答が途中で終了しました"
        case .invalidResponse: "AIサービスから不正な応答を受信しました"
        case let .server(message): message
        }
    }
}
