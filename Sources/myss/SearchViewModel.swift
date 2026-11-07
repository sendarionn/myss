@preconcurrency import AppKit
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var direction: SearchDirection = .meaningToWord
    @Published var results: [SearchResult] = []
    @Published var selectedIndex = 0
    @Published var contextSource: ContextSource = .none

    var onDismiss: (() -> Void)?
    private let engine = SemanticSearchEngine()
    private let inserter = TextInserter()
    private var context = CapturedContext.empty
    private var searchTask: Task<Void, Never>?
    private var generation = 0
    private var directionWasManuallyChanged = false

    func begin(with context: CapturedContext) {
        searchTask?.cancel()
        self.context = context
        contextSource = context.source
        directionWasManuallyChanged = false
        query = context.text
        direction = engine.direction(for: context.text)
        selectedIndex = 0
        scheduleSearch()
    }

    func queryChanged() {
        if !directionWasManuallyChanged { direction = engine.direction(for: query) }
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

    func insertSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        inserter.insert(results[selectedIndex].entry.word, into: context)
        onDismiss?()
    }

    func copySelection() {
        guard results.indices.contains(selectedIndex) else { return }
        inserter.copy(results[selectedIndex].entry.word)
        onDismiss?()
    }

    private func scheduleSearch() {
        generation += 1
        let currentGeneration = generation
        let currentQuery = query
        let currentDirection = direction
        searchTask?.cancel()
        searchTask = Task { [weak self, engine] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let newResults = await Task.detached {
                engine.search(query: currentQuery, direction: currentDirection)
            }.value
            guard !Task.isCancelled, let self, currentGeneration == self.generation else { return }
            self.results = newResults
            self.selectedIndex = min(self.selectedIndex, max(newResults.count - 1, 0))
        }
    }
}
