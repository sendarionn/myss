@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum SearchIntent: Equatable, Sendable {
    case wordMeaning(headword: String)
    case wordMeaningWithContext(headword: String, context: String)
    case meaningToWord(query: String)

    var isWordLookup: Bool {
        if case .meaningToWord = self { return false }
        return true
    }
}

struct LexicalSource: Identifiable, Hashable, Sendable, Codable {
    let name: String
    let text: String
    let url: URL?
    let license: String?
    var id: String { "\(name):\(url?.absoluteString ?? text)" }
}

struct LexicalSense: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let headword: String
    let partOfSpeech: String?
    let summary: String
    let definitions: [String]
    let aliases: [String]
    let examples: [String]
    let sources: [LexicalSource]
    let relatedWords: [String]
    let score: Double
}

struct SearchResponse: Sendable, Codable {
    let intent: String
    let query: String
    let headword: String?
    let context: String?
    let senses: [LexicalSense]
    let phase: String

    var searchIntent: SearchIntent {
        switch (intent, headword, context) {
        case let ("wordMeaningWithContext", headword?, context?):
            .wordMeaningWithContext(headword: headword, context: context)
        case let ("wordMeaning", headword?, _):
            .wordMeaning(headword: headword)
        default:
            .meaningToWord(query: query)
        }
    }
}

struct BackendStatus: Sendable, Codable {
    let ready: Bool
    let model: String?
    let senseCount: Int?
    let message: String?
}

struct CapturedContext {
    let text: String
    let surroundingText: String
    let source: ContextSource
    let targetElement: AXUIElement?
    let sourceApplication: NSRunningApplication?
    static let empty = CapturedContext(text: "", surroundingText: "", source: .none, targetElement: nil, sourceApplication: nil)
}

enum ContextSource: String {
    case selection = "選択テキスト"
    case sentence = "カーソル周辺"
    case none = "手入力"
}

enum SemanticBackendError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message), let .server(message): message
        case .invalidResponse: "検索バックエンドから不正な応答を受信しました"
        }
    }
}

enum BackendLifecycleState: Equatable {
    case notConfigured
    case starting
    case ready
    case error(String)

    var label: String {
        switch self {
        case .notConfigured: "検索データ未準備"
        case .starting: "準備中"
        case .ready: "起動中"
        case .error: "エラー"
        }
    }
}
