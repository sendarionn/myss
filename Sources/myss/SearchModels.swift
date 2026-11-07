@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum SearchDirection: String, CaseIterable, Identifiable, Sendable {
    case meaningToWord = "意味 → 語"
    case wordToMeaning = "語 → 意味"

    var id: Self { self }
}

struct LexicalEntry: Identifiable, Hashable, Sendable {
    let word: String
    let summary: String
    let aliases: [String]
    let cues: [String]

    var id: String { word }
}

struct SearchResult: Identifiable, Hashable, Sendable {
    let entry: LexicalEntry
    let score: Double

    var id: String { entry.id }
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
