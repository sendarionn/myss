@preconcurrency import AppKit
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var direction: SearchDirection = .meaningToWord
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
    private var directionWasManuallyChanged = false

    var selectedSense: LexicalSense? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func begin(with context: CapturedContext) {
        searchTask?.cancel()
        self.context = context
        contextSource = context.source
        directionWasManuallyChanged = false
        query = context.text
        selectedIndex = 0
        statusMessage = nil
        direction = engine.direction(for: context.text)
        scheduleSearch()
    }

    func queryChanged() {
        if !directionWasManuallyChanged {
            direction = engine.direction(for: query)
        }
        scheduleSearch()
    }

    func setDirection(_ value: SearchDirection) {
        directionWasManuallyChanged = true
        direction = value
        scheduleSearch()
    }

    func moveSelection(_ offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    func primaryAction() {
        guard direction == .meaningToWord, let sense = selectedSense else { return }
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
        let currentDirection = direction
        searchTask?.cancel()
        guard !currentQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            statusMessage = nil
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self, engine] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            do {
                let response = try await engine.search(query: currentQuery, direction: currentDirection)
                guard !Task.isCancelled, let self, currentGeneration == self.generation else { return }
                results = response.senses
                selectedIndex = min(selectedIndex, max(results.count - 1, 0))
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
