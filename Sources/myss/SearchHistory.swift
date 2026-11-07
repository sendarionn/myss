import Foundation

struct SearchHistoryItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let query: String
    let response: LanguageResponse
    let createdAt: Date

    init(id: UUID = UUID(), query: String, response: LanguageResponse, createdAt: Date = Date()) {
        self.id = id
        self.query = query
        self.response = response
        self.createdAt = createdAt
    }
}

/// 検索文字列と最終結果をローカルのJSONファイルへ保存する　新しい順に最大件数まで保持する
@MainActor
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()
    static let defaultLimit = 100

    @Published private(set) var items: [SearchHistoryItem] = []

    let fileURL: URL
    let limit: Int

    init(fileURL: URL = SearchHistoryStore.defaultFileURL, limit: Int = SearchHistoryStore.defaultLimit) {
        self.fileURL = fileURL
        self.limit = limit
        load()
    }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "myss", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            items = []
            return
        }
        let decoder = JSONDecoder()
        items = (try? decoder.decode([SearchHistoryItem].self, from: data)) ?? []
    }

    /// 直前の履歴と同じ内容は保存しない
    @discardableResult
    func record(query: String, response: LanguageResponse, now: Date = Date()) -> SearchHistoryItem? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        if let latest = items.first, latest.query == query, latest.response == response { return nil }
        let item = SearchHistoryItem(query: query, response: response, createdAt: now)
        items = Array(([item] + items).prefix(limit))
        save()
        return item
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[myss][history] save failed: \(error.localizedDescription)")
            #endif
        }
    }
}
