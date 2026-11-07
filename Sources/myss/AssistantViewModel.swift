@preconcurrency import AppKit
import Foundation

/// 追加指示の連続修正を管理する
/// 直前の回答の指示を書き足し・削っている間は同じ段階の修正として扱い、別の指示に変わったら直前の回答を履歴へ確定する
struct RefinementSession: Equatable {
    private(set) var history: [LanguageTurn] = []
    private(set) var answered: (history: [LanguageTurn], turn: LanguageTurn)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.history == rhs.history && lhs.answered?.history == rhs.answered?.history && lhs.answered?.turn == rhs.answered?.turn
    }

    /// 指示に対して送る履歴を返す
    mutating func history(for instruction: String) -> [LanguageTurn] {
        guard let answered else { return history }
        if !answered.turn.instruction.isEmpty, Self.isSameTurn(answered.turn.instruction, instruction) {
            return answered.history
        }
        history = answered.history + [answered.turn]
        self.answered = nil
        return history
    }

    mutating func didAnswer(history: [LanguageTurn], instruction: String, response: LanguageResponse) {
        answered = (history, LanguageTurn(instruction: instruction, response: response))
        self.history = history
    }

    static func isSameTurn(_ previous: String, _ next: String) -> Bool {
        previous.hasPrefix(next) || next.hasPrefix(previous)
    }
}

@MainActor
final class AssistantViewModel: ObservableObject {
    static let instructionDebounce: Duration = .milliseconds(400)

    @Published var instruction = ""
    @Published private(set) var response: LanguageResponse?
    @Published var selectedIndex = 0
    @Published private(set) var isLoading = false
    @Published private(set) var error: LanguageAssistantError?
    @Published private(set) var errorMessage: String?
    @Published private(set) var context = CapturedContext.empty
    @Published private(set) var accessibilityTrusted = true

    var onDismiss: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private let assistant: LanguageAssistant
    private let inserter = TextInserter()
    private var session = RefinementSession()
    private var requestTask: Task<Void, Never>?
    private var generation = 0
    private var scheduledInstruction: String?

    init(assistant: LanguageAssistant = .shared) {
        self.assistant = assistant
    }

    var candidates: [LanguageCandidate] { response?.candidates ?? [] }

    var selectedCandidate: LanguageCandidate? {
        candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : nil
    }

    /// パネル上部に表示する対象
    var subject: String {
        let text = context.selectedText.isEmpty ? context.surroundingText : context.selectedText
        return text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    func begin(with context: CapturedContext, accessibilityTrusted: Bool = true) {
        requestTask?.cancel()
        self.context = context
        self.accessibilityTrusted = accessibilityTrusted
        session = RefinementSession()
        instruction = ""
        response = nil
        selectedIndex = 0
        clearError()
        if context.isEmpty {
            scheduledInstruction = ""
            isLoading = false
        } else {
            schedule(instruction: "", delay: nil)
        }
    }

    func instructionChanged() {
        let value = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value != scheduledInstruction else { return }
        if value.isEmpty, response != nil || context.isEmpty {
            requestTask?.cancel()
            scheduledInstruction = value
            isLoading = false
            return
        }
        schedule(instruction: value, delay: Self.instructionDebounce)
    }

    func retry() {
        schedule(instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines), delay: nil)
    }

    func moveSelection(_ offset: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), candidates.count - 1)
    }

    /// 候補がある場合だけ元の位置へ入力する
    func primaryAction() {
        guard let candidate = selectedCandidate else { return }
        inserter.insert(candidate.text, into: context)
        onDismiss?()
    }

    func copySelection() {
        let text = selectedCandidate?.text ?? response?.summary ?? ""
        guard !text.isEmpty else { return }
        inserter.copy(text)
        onDismiss?()
    }

    func insert(_ candidate: LanguageCandidate) {
        inserter.insert(candidate.text, into: context)
        onDismiss?()
    }

    func copy(_ candidate: LanguageCandidate) {
        inserter.copy(candidate.text)
        onDismiss?()
    }

    private func schedule(instruction value: String, delay: Duration?) {
        generation += 1
        let currentGeneration = generation
        scheduledInstruction = value
        requestTask?.cancel()
        let history = session.history(for: value)
        let request = LanguageRequest(
            selectedText: context.selectedText,
            surroundingContext: context.surroundingText,
            cursorOffset: context.cursorOffset,
            history: history,
            manualInstruction: value
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
                session.didAnswer(history: history, instruction: value, response: response)
                self.response = response
                selectedIndex = 0
                isLoading = false
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
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
