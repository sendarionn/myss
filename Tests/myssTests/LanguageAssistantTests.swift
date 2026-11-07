import XCTest
@testable import myss

final class ContextExtractionTests: XCTestCase {
    func testContextIncludesCurrentSentenceAndOneNeighborOnEachSide() {
        let text = "一文目です。二文目です。自分で判断して動く姿勢が必要だ。四文目です。五文目です。"
        let location = ("一文目です。二文目です。自分で判断して" as NSString).length
        let context = AccessibilityContextReader.contextAroundCursor(in: text, utf16Location: location)
        XCTAssertEqual(context.text, "二文目です。自分で判断して動く姿勢が必要だ。四文目です。")
        XCTAssertEqual(context.cursorOffset, ("二文目です。自分で判断して" as NSString).length)
    }

    func testContextAtEndOfTypedSentenceIncludesThatSentence() {
        let text = "前の文です。この対応は問題を一時的に抑えるだけなので、"
        let context = AccessibilityContextReader.contextAroundCursor(in: text, utf16Location: (text as NSString).length)
        XCTAssertEqual(context.text, text)
        XCTAssertEqual(context.cursorOffset, (text as NSString).length)
    }

    func testContextIsLimitedAroundCursor() {
        let text = String(repeating: "あ", count: 2000)
        let context = AccessibilityContextReader.contextAroundCursor(in: text, utf16Location: 1000, maximumLength: 100)
        XCTAssertEqual(context.text.count, 100)
        XCTAssertEqual(context.cursorOffset, 50)
    }
}

final class LanguagePromptTests: XCTestCase {
    private let release = LanguageResponse(intent: .explainExpression, summary: "公開すること", candidates: [])

    func testFirstMessageMarksCursorAndKeepsInputsSeparate() {
        let request = LanguageRequest(
            selectedText: "", surroundingContext: "抑えるだけなので、", cursorOffset: 9,
            history: [], manualInstruction: "熟語で"
        )
        let messages = LanguagePrompt.messages(for: request)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["content"], """
        <selected_text></selected_text>
        <context>抑えるだけなので、\(LanguagePrompt.cursorMarker)</context>
        <instruction>熟語で</instruction>
        """)
    }

    func testFollowUpInstructionsAreSentAfterPreviousAnswers() {
        let request = LanguageRequest(
            selectedText: "リリース", surroundingContext: "新製品のリリース時期を来月へ変更する。", cursorOffset: nil,
            history: [LanguageTurn(instruction: "", response: release)], manualInstruction: "もっと堅く"
        )
        let messages = LanguagePrompt.messages(for: request)
        XCTAssertEqual(messages.map { $0["role"] }, ["user", "assistant", "user"])
        XCTAssertTrue(messages[0]["content"]!.contains("<selected_text>リリース</selected_text>"))
        XCTAssertTrue(messages[0]["content"]!.contains("<instruction></instruction>"))
        XCTAssertTrue(messages[1]["content"]!.contains("公開すること"))
        XCTAssertEqual(messages[2]["content"], "<instruction>もっと堅く</instruction>")
    }

    func testRequestBodyUsesStructuredOutput() throws {
        let request = LanguageRequest(selectedText: "敷衍", surroundingContext: "", cursorOffset: nil, history: [], manualInstruction: "")
        let body = AnthropicLanguageProvider.body(for: request)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        let format = try XCTUnwrap(output["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
    }
}

final class AnthropicResponseTests: XCTestCase {
    private func message(text: String, stopReason: String = "end_turn") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]],
            "stop_reason": stopReason
        ])
    }

    func testParsesCandidatesAndDropsDuplicates() throws {
        let json = #"{"intent":"find_expression","summary":"表面だけに対応すること","candidates":[{"text":"対症療法","explanation":"原因ではなく症状に対応する"},{"text":" 対症療法 ","explanation":"重複"},{"text":"その場しのぎ","explanation":"否定的"}]}"#
        let response = try AnthropicLanguageProvider.parse(message(text: json))
        XCTAssertEqual(response.intent, .findExpression)
        XCTAssertEqual(response.candidates.map(\.text), ["対症療法", "その場しのぎ"])
    }

    func testUnknownIntentFallsBackToUnknown() throws {
        let json = #"{"intent":"something_new","summary":"","candidates":[]}"#
        XCTAssertEqual(try AnthropicLanguageProvider.parse(message(text: json)).intent, .unknown)
    }

    func testRefusalIsReported() throws {
        XCTAssertThrowsError(try AnthropicLanguageProvider.parse(message(text: "", stopReason: "refusal"))) {
            XCTAssertEqual($0 as? LanguageAssistantError, .refused)
        }
    }
}

final class RefinementSessionTests: XCTestCase {
    private func response(_ summary: String) -> LanguageResponse {
        LanguageResponse(intent: .rewrite, summary: summary, candidates: [])
    }

    func testEditingSameInstructionReplacesTurnAndNewInstructionCommitsIt() {
        var session = RefinementSession()
        let initial = session.history(for: "")
        XCTAssertEqual(initial, [])
        session.didAnswer(history: initial, instruction: "", response: response("R0"))

        let first = session.history(for: "もっと")
        XCTAssertEqual(first.map(\.instruction), [""])
        session.didAnswer(history: first, instruction: "もっと", response: response("R1"))

        XCTAssertEqual(session.history(for: "もっと堅く").map(\.instruction), [""])
        session.didAnswer(history: first, instruction: "もっと堅く", response: response("R2"))

        let second = session.history(for: "名詞で")
        XCTAssertEqual(second.map(\.instruction), ["", "もっと堅く"])
        XCTAssertEqual(second.last?.response.summary, "R2")
    }
}

final class ResponseCacheTests: XCTestCase {
    func testCachedResponseExpires() {
        var cache = ResponseCache()
        let request = LanguageRequest(selectedText: "敷衍", surroundingContext: "", cursorOffset: nil, history: [], manualInstruction: "")
        let response = LanguageResponse(intent: .explainExpression, summary: "", candidates: [])
        let now = Date()
        cache.insert(response, for: request, now: now)
        XCTAssertEqual(cache.value(for: request, now: now.addingTimeInterval(10)), response)
        XCTAssertNil(cache.value(for: request, now: now.addingTimeInterval(cache.lifetime + 1)))
    }
}

final class LanguageAssistantTests: XCTestCase {
    private struct CountingProvider: LanguageAssistantProvider {
        let counter: Counter
        func request(_ request: LanguageRequest) async throws -> LanguageResponse {
            await counter.increment()
            return LanguageResponse(intent: .findExpression, summary: "", candidates: [LanguageCandidate(text: "対症療法", explanation: "")])
        }
        func verify() async throws {}
    }

    actor Counter {
        var value = 0
        func increment() { value += 1 }
    }

    @MainActor
    func testSameRequestIsServedFromCache() async throws {
        let counter = Counter()
        let assistant = LanguageAssistant(apiKey: "test") { _ in CountingProvider(counter: counter) }
        let request = LanguageRequest(selectedText: "", surroundingContext: "一時的に抑える", cursorOffset: 7, history: [], manualInstruction: "")
        _ = try await assistant.respond(to: request)
        _ = try await assistant.respond(to: request)
        let count = await counter.value
        XCTAssertEqual(count, 1)
        XCTAssertNotNil(assistant.lastSentTranscript)
    }

    @MainActor
    func testMissingAPIKeyIsReported() async {
        let assistant = LanguageAssistant(apiKey: nil)
        do {
            _ = try await assistant.respond(to: LanguageRequest(selectedText: "a", surroundingContext: "", cursorOffset: nil, history: [], manualInstruction: ""))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? LanguageAssistantError, .missingAPIKey)
        }
    }
}

