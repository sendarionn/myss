@preconcurrency import AppKit
import Foundation

@MainActor
final class AssistantViewModel: ObservableObject {
    static let queryDebounce: Duration = .milliseconds(400)

    /// 選択文字列と後から入力した文字列を区別しない、ただ1つの入力欄
    @Published var queryText = ""
    @Published private(set) var response: LanguageResponse?
    @Published var selectedIndex = 0
    @Published private(set) var isLoading = false
    @Published private(set) var error: LanguageAssistantError?
    @Published private(set) var errorMessage: String?
    @Published private(set) var accessibilityTrusted = true

    var onDismiss: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    let historyStore: SearchHistoryStore
    private let assistant: LanguageAssistant
    private let debounce: Duration
    private let inserter = TextInserter()
    /// 元アプリへの挿入先　UIには出さない
    private var insertionContext = CapturedContext.empty
    private var requestTask: Task<Void, Never>?
    private var generation = 0
    private var scheduledQuery: String?
    /// 履歴へ保存する候補となる、最新の成功結果
    private var lastSuccess: (query: String, response: LanguageResponse)?
    /// 開いている、または保存済みの履歴　同じ内容を再保存しないために使う
    private var savedItem: (query: String, response: LanguageResponse)?

    init(
        assistant: LanguageAssistant = .shared,
        historyStore: SearchHistoryStore = .shared,
        debounce: Duration = AssistantViewModel.queryDebounce
    ) {
        self.assistant = assistant
        self.historyStore = historyStore
        self.debounce = debounce
    }

    var isShowingHistory: Bool { trimmedQuery.isEmpty }
    var historyItems: [SearchHistoryItem] { historyStore.items }
    var candidates: [LanguageCandidate] { response?.candidates ?? [] }

    var selectedCandidate: LanguageCandidate? {
        candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil
    }

    private var trimmedQuery: String { queryText.trimmingCharacters(in: .whitespacesAndNewlines) }

    func begin(with context: CapturedContext, accessibilityTrusted: Bool = true) {
        commitCurrentResult()
        requestTask?.cancel()
        insertionContext = context
        self.accessibilityTrusted = accessibilityTrusted
        resetResult()
        let query = context.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        scheduledQuery = query
        queryText = query
        if !query.isEmpty { schedule(query: query, delay: nil) }
    }

    func queryChanged() {
        let value = trimmedQuery
        guard value != scheduledQuery else { return }
        scheduledQuery = value
        guard !value.isEmpty else {
            // 全削除したら現在の結果を確定し、履歴へ戻る
            commitCurrentResult()
            requestTask?.cancel()
            resetResult()
            return
        }
        schedule(query: value, delay: debounce)
    }

    func retry() {
        guard !trimmedQuery.isEmpty else { return }
        schedule(query: trimmedQuery, delay: nil)
    }

    /// 保存済みの結果を再生成せずに表示する
    func openHistory(_ item: SearchHistoryItem) {
        commitCurrentResult()
        requestTask?.cancel()
        resetResult()
        scheduledQuery = item.query
        queryText = item.query
        response = item.response
        lastSuccess = (item.query, item.response)
        savedItem = (item.query, item.response)
    }

    func moveSelection(_ offset: Int) {
        let count = isShowingHistory ? historyItems.count : candidates.count
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), count - 1)
    }

    /// 空欄では選択中の履歴を開き、候補がある場合は元の位置へ入力する
    func primaryAction() {
        if isShowingHistory {
            guard historyItems.indices.contains(selectedIndex) else { return }
            openHistory(historyItems[selectedIndex])
            return
        }
        guard let candidate = selectedCandidate else { return }
        insert(candidate)
    }

    func copySelection() {
        let text = selectedCandidate?.text ?? response?.summary ?? ""
        guard !text.isEmpty else { return }
        commitCurrentResult()
        inserter.copy(text)
        onDismiss?()
    }

    func insert(_ candidate: LanguageCandidate) {
        commitCurrentResult()
        inserter.insert(candidate.text, into: insertionContext)
        onDismiss?()
    }

    func copy(_ candidate: LanguageCandidate) {
        commitCurrentResult()
        inserter.copy(candidate.text)
        onDismiss?()
    }

    func dismiss() {
        commitCurrentResult()
        requestTask?.cancel()
        onDismiss?()
    }

    /// 入力途中ではなく、確定時点の最新の成功結果だけを履歴へ保存する
    func commitCurrentResult() {
        guard let lastSuccess else { return }
        if let savedItem, savedItem.query == lastSuccess.query, savedItem.response == lastSuccess.response { return }
        historyStore.record(query: lastSuccess.query, response: lastSuccess.response)
        savedItem = lastSuccess
    }

    private func resetResult() {
        response = nil
        lastSuccess = nil
        savedItem = nil
        selectedIndex = 0
        isLoading = false
        clearError()
    }

    private func schedule(query: String, delay: Duration?) {
        generation += 1
        let currentGeneration = generation
        requestTask?.cancel()
        let request = LanguageRequest.make(
            query: query,
            selectedText: insertionContext.selectedText,
            surroundingText: insertionContext.surroundingText
        )
        isLoading = true
        clearError()
        requestTask = Task { [weak self, assistant] in
            if let delay {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            do {
                let response = try await assistant.respond(to: request)
                guard !Task.isCancelled, let self, currentGeneration == self.generation else { return }
                self.response = response
                lastSuccess = (query, response)
                selectedIndex = 0
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, currentGeneration == self.generation else { return }
                self.error = error as? LanguageAssistantError
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func clearError() {
        error = nil
        errorMessage = nil
    }
}
