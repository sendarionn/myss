@preconcurrency import AppKit
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var intent: SearchIntent?
    @Published var results: [LexicalSense] = []
    @Published var selectedIndex = 0
    @Published var contextSource: ContextSource = .none
    @Published var statusMessage: String?
    @Published var isSearching = false

    var onDismiss: (() -> Void)?
    private let engine = SemanticSearchEngine.shared
    private let inserter = TextInserter()
    private var context = CapturedContext.empty
    private var searchTask: Task<Void, Never>?
    private var generation = 0

    var selectedSense: LexicalSense? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func begin(with context: CapturedContext) {
        searchTask?.cancel()
        self.context = context
        contextSource = context.source
        query = context.text
        selectedIndex = 0
        statusMessage = nil
        intent = nil
        results = []
        scheduleSearch()
    }

    func queryChanged() {
        scheduleSearch()
    }

    /// 選択語から始まる入力の間だけ、選択時に取得した周辺文脈を検索へ渡す
    nonisolated static func capturedContext(for query: String, selectedHeadword: String, surroundingText: String) -> String? {
        let normalize = { (text: String) in text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let query = normalize(query)
        let headword = normalize(selectedHeadword)
        let surrounding = surroundingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headword.isEmpty, !surrounding.isEmpty,
              query == headword || query.hasPrefix(headword + " ")
        else { return nil }
        return surrounding
    }

    func moveSelection(_ offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    func primaryAction() {
        guard intent?.isWordLookup == false, let sense = selectedSense else { return }
        inserter.insert(sense.headword, into: context)
        onDismiss?()
    }

    func copySelection() {
        guard let sense = selectedSense else { return }
        inserter.copy(sense.headword)
        onDismiss?()
    }

    private func scheduleSearch() {
        generation += 1
        let currentGeneration = generation
        let currentQuery = query
        let currentContext = context.source == .selection
            ? Self.capturedContext(for: currentQuery, selectedHeadword: context.text, surroundingText: context.surroundingText)
            : nil
        searchTask?.cancel()
        guard !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            intent = nil
            statusMessage = nil
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self, engine] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            do {
                let response = try await engine.search(query: currentQuery, capturedContext: currentContext)
                guard !Task.isCancelled, let self, currentGeneration == self.generation else { return }
                let newIntent = response.searchIntent
                #if DEBUG
                print("myss intent:", newIntent)
                #endif
                intent = newIntent
                results = response.senses
                selectedIndex = 0
                statusMessage = results.isEmpty ? "該当する語義がありません" : nil
                isSearching = false
            } catch {
                guard !Task.isCancelled, let self, currentGeneration == self.generation else { return }
                results = []
                statusMessage = error.localizedDescription
                isSearching = false
            }
        }
    }
}
