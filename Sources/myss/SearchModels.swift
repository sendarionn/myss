@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum SearchDirection: String, CaseIterable, Identifiable, Sendable, Codable {
    case meaningToWord = "意味 → 語"
    case wordToMeaning = "語 → 意味"
    var id: Self { self }
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
    let senses: [LexicalSense]
    let phase: String
}

struct BackendStatus: Sendable, Codable {
    let ready: Bool
    let model: String?
    let senseCount: Int?
    let message: String?
}

struct CapturedContext {
    let text: String
    let source: ContextSource
    let targetElement: AXUIElement?
    let sourceApplication: NSRunningApplication?
    static let empty = CapturedContext(text: "", source: .none, targetElement: nil, sourceApplication: nil)
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
