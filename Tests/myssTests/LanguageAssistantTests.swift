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
    func testPromptContainsOnlyQueryWhenNoContext() {
        XCTAssertEqual(LanguagePrompt.prompt(for: LanguageRequest(query: "residency OpenAI APIでは")), "<query>residency OpenAI APIでは</query>")
    }

    func testPromptAddsSurroundingContextAsAuxiliaryInformation() {
        let request = LanguageRequest(query: "リリース", surroundingContext: "新製品のリリース時期を来月へ変更する。")
        XCTAssertEqual(LanguagePrompt.prompt(for: request), """
        <query>リリース</query>
        <context>新製品のリリース時期を来月へ変更する。</context>
        """)
    }

    func testSurroundingContextIsDroppedOnceSelectionLeavesQuery() {
        let sentence = "新製品のリリース時期を来月へ変更する。"
        XCTAssertEqual(LanguageRequest.make(query: "リリース ビジネスでは", selectedText: "リリース", surroundingText: sentence).surroundingContext, sentence)
        XCTAssertEqual(LanguageRequest.make(query: "製品を公開すること", selectedText: "リリース", surroundingText: sentence).surroundingContext, "")
        XCTAssertEqual(LanguageRequest.make(query: "residency", selectedText: "", surroundingText: sentence).surroundingContext, "")
    }

    func testPromptDoesNotDistinguishSelectionFromTypedText() {
        XCTAssertFalse(LanguagePrompt.system.contains("selected_text"))
        XCTAssertFalse(LanguagePrompt.system.contains("instruction"))
        XCTAssertTrue(LanguagePrompt.system.contains("選択した文字列と、後から書き足した文字列は区別されない"))
    }
}

final class GeneratedResponseConversionTests: XCTestCase {
    func testConversionTrimsDeduplicatesAndLimitsCandidates() {
        let candidates = [GeneratedCandidate(text: "対症療法", explanation: " 原因ではなく症状に対応する "), GeneratedCandidate(text: " 対症療法 ", explanation: "重複")]
            + (1...12).map { GeneratedCandidate(text: "候補\($0)", explanation: "") }
        let generated = GeneratedLanguageResponse(intent: .findExpression, targetExpression: "  ", summary: " 表面だけに対応すること ", candidates: candidates)
        let response = generated.languageResponse
        XCTAssertEqual(response.intent, .findExpression)
        XCTAssertNil(response.targetExpression)
        XCTAssertEqual(response.summary, "表面だけに対応すること")
        XCTAssertEqual(response.candidates.count, 10)
        XCTAssertEqual(response.candidates.first, LanguageCandidate(text: "対症療法", explanation: "原因ではなく症状に対応する"))
        XCTAssertEqual(response.candidates.filter { $0.text == "対症療法" }.count, 1)
    }

    func testConversionKeepsTargetExpression() {
        let generated = GeneratedLanguageResponse(intent: .explainExpression, targetExpression: " プレーンテキスト ", summary: "書式を持たない文字データ", candidates: [])
        XCTAssertEqual(generated.languageResponse.targetExpression, "プレーンテキスト")
        XCTAssertEqual(generated.languageResponse.intent, .explainExpression)
    }

    func testEveryGeneratedIntentMapsToLanguageIntent() {
        let pairs: [(GeneratedIntent, LanguageIntent)] = [
            (.findExpression, .findExpression), (.explainExpression, .explainExpression), (.rewrite, .rewrite),
            (.compareExpressions, .compareExpressions), (.continueText, .continueText), (.unknown, .unknown)
        ]
        for (generated, expected) in pairs { XCTAssertEqual(generated.languageIntent, expected) }
    }

    func testUnavailableReasonsHaveMessages() {
        XCTAssertEqual(LanguageAssistantError.modelUnavailable(.appleIntelligenceNotEnabled).localizedDescription,
                       "Apple Intelligenceが無効です　システム設定で有効にしてください")
        XCTAssertEqual(LanguageAssistantError.modelUnavailable(.deviceNotEligible).localizedDescription,
                       "このMacはApple Intelligenceに対応していません")
    }
}

final class ResponseCacheTests: XCTestCase {
    func testCachedResponseExpires() {
        var cache = ResponseCache()
        let request = LanguageRequest(query: "敷衍")
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
    }

    actor Counter {
        var value = 0
        func increment() { value += 1 }
    }

    private let request = LanguageRequest(query: "一時的に抑えること")

    @MainActor
    func testSameRequestIsServedFromCache() async throws {
        let counter = Counter()
        let assistant = LanguageAssistant(provider: CountingProvider(counter: counter)) { .available }
        _ = try await assistant.respond(to: request)
        _ = try await assistant.respond(to: request)
        let count = await counter.value
        XCTAssertEqual(count, 1)
        XCTAssertNotNil(assistant.lastPrompt)
    }

    @MainActor
    func testUnavailableModelIsReportedWithoutCallingProvider() async {
        let counter = Counter()
        let assistant = LanguageAssistant(provider: CountingProvider(counter: counter)) { .appleIntelligenceNotEnabled }
        do {
            _ = try await assistant.respond(to: request)
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? LanguageAssistantError, .modelUnavailable(.appleIntelligenceNotEnabled))
        }
        let count = await counter.value
        XCTAssertEqual(count, 0)
    }
}

/// MYSS_LIVE_MODEL=1のときだけ実際のオンデバイスモデルで代表例を実行する　出力文は固定しない
final class LiveOnDeviceModelTests: XCTestCase {
    func testRepresentativeCases() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MYSS_LIVE_MODEL"] == "1", "実機確認時だけ実行")
        let provider = AppleLanguageProvider()
        let queries = [
            "プレーンテキスト",
            "プレーンテキスト プログラミングでは",
            "プログラミングなどでの、シンプルなテキストファイルのこと",
            "営業でいうリード",
            "見込み客や将来顧客になる可能性のある相手",
            "リリース もっと堅く"
        ]
        for query in queries {
            let request = LanguageRequest(query: query)
            let clock = ContinuousClock()
            let start = clock.now
            let response = try await provider.request(request)
            print("[live] query=\(query) elapsed=\(clock.now - start)")
            print("[live]   intent=\(response.intent.rawValue) target=\(response.targetExpression ?? "nil")")
            print("[live]   summary=\(response.summary)")
            print("[live]   candidates=\(response.candidates.map(\.text))")
        }
    }
}

final class SelectionExtractionTests: XCTestCase {
    func testRangeIsCutFromValue() {
        XCTAssertEqual(AccessibilityContextReader.substring(of: "abcdef", range: CFRange(location: 2, length: 3)), "cde")
    }

    func testRangeUsesUTF16WithJapaneseAndEmoji() {
        let value = "新製品😀のリリース時期"
        let location = ("新製品😀の" as NSString).length
        XCTAssertEqual(AccessibilityContextReader.substring(of: value, range: CFRange(location: location, length: 4)), "リリース")
        XCTAssertEqual(AccessibilityContextReader.substring(of: value, range: CFRange(location: 3, length: 2)), "😀")
    }

    func testInvalidRangeDoesNotCrash() {
        let value = "abcdef"
        XCTAssertNil(AccessibilityContextReader.substring(of: value, range: CFRange(location: 7, length: 1)))
        XCTAssertNil(AccessibilityContextReader.substring(of: value, range: CFRange(location: 4, length: 5)))
        XCTAssertNil(AccessibilityContextReader.substring(of: value, range: CFRange(location: -1, length: 2)))
        XCTAssertNil(AccessibilityContextReader.substring(of: value, range: CFRange(location: 2, length: Int.max)))
    }

    func testEmptyRangeIsNotSelection() {
        XCTAssertNil(AccessibilityContextReader.substring(of: "abcdef", range: CFRange(location: 3, length: 0)))
        XCTAssertNil(AccessibilityContextReader.limitedSelection(" \n"))
    }

    func testSelectionKeepsMaximumLength() {
        let long = String(repeating: "あ", count: 700)
        XCTAssertEqual(AccessibilityContextReader.limitedSelection(long)?.count, AccessibilityContextReader.maximumSelectionLength)
    }
}

final class PasteboardSnapshotTests: XCTestCase {
    @MainActor
    func testSnapshotRestoresAllItemsAndTypes() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("myss-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("plain", forType: .string)
        first.setData(Data("<b>rich</b>".utf8), forType: .html)
        let second = NSPasteboardItem()
        second.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.custom"))
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("copied selection", forType: .string)
        snapshot.restore(to: pasteboard)

        let items = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.string(forType: .string), "plain")
        XCTAssertEqual(items.first?.data(forType: .html), Data("<b>rich</b>".utf8))
        XCTAssertEqual(items.last?.data(forType: NSPasteboard.PasteboardType("com.example.custom")), Data([1, 2, 3]))
    }
}

final class ClipboardFallbackConditionTests: XCTestCase {
    func testFallbackRunsEvenWhenRangeIsZeroLength() {
        // AXSelectedTextが失敗し、範囲が長さ0でもAX側の選択結果がなければ⌘Cを試す
        let zeroRange = CFRange(location: 120, length: 0)
        XCTAssertNil(AccessibilityContextReader.substring(of: String(repeating: "a", count: 200), range: zeroRange))
        XCTAssertTrue(AccessibilityContextReader.needsClipboardFallback(selection: nil))
    }

    func testFallbackDoesNotRunWhenAccessibilityFoundSelection() {
        let selection = SelectionResult(text: "リリース", range: CFRange(location: 3, length: 4), method: .selectedTextAttribute)
        XCTAssertFalse(AccessibilityContextReader.needsClipboardFallback(selection: selection))
    }

    func testDiagnosticsDoNotContainSelectedText() {
        var diagnostics = SelectionDiagnostics(sourceApp: "Google Chrome")
        diagnostics.selectionMethod = SelectionAcquisitionMethod.clipboard.rawValue
        diagnostics.selectedLength = 14
        let rendered = diagnostics.lines.map { "\($0.label)=\($0.value)" }.joined(separator: "\n")
        XCTAssertTrue(rendered.contains("Selection method=clipboard"))
        XCTAssertTrue(rendered.contains("Selected length=14"))
    }
}

final class AccessibilityDiagnosticsTests: XCTestCase {
    func testDiagnosticsShowAccessibilityTrustedState() {
        var diagnostics = SelectionDiagnostics(sourceApp: "TextEdit")
        diagnostics.accessibilityTrusted = false
        XCTAssertTrue(diagnostics.lines.contains { $0.label == "Accessibility trusted" && $0.value == "no" })
    }
}

final class SearchHistoryStoreTests: XCTestCase {
    @MainActor
    private func makeStore(limit: Int = 100) -> SearchHistoryStore {
        let url = FileManager.default.temporaryDirectory.appending(path: "myss-history-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return SearchHistoryStore(fileURL: url, limit: limit)
    }

    private let response = LanguageResponse(intent: .explainExpression, targetExpression: "residency", summary: "居住、滞在", candidates: [])

    @MainActor
    func testRecordPersistsNewestFirstAndSkipsDuplicateOfLatest() {
        let store = makeStore()
        store.record(query: "residency", response: response)
        XCTAssertNil(store.record(query: "residency", response: response))
        store.record(query: "residency APIでは", response: response)
        XCTAssertEqual(store.items.map(\.query), ["residency APIでは", "residency"])

        let reloaded = SearchHistoryStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.items, store.items)
    }

    @MainActor
    func testOldestItemsAreDroppedOverLimit() {
        let store = makeStore(limit: 3)
        for index in 1...5 { store.record(query: "q\(index)", response: response) }
        XCTAssertEqual(store.items.map(\.query), ["q5", "q4", "q3"])
    }
}

final class AssistantHistoryFlowTests: XCTestCase {
    private struct EchoProvider: LanguageAssistantProvider {
        func request(_ request: LanguageRequest) async throws -> LanguageResponse {
            LanguageResponse(intent: .explainExpression, targetExpression: nil, summary: "意味: \(request.query)", candidates: [])
        }
    }

    @MainActor
    private func makeModel() -> AssistantViewModel {
        let url = FileManager.default.temporaryDirectory.appending(path: "myss-history-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let assistant = LanguageAssistant(provider: EchoProvider()) { .available }
        return AssistantViewModel(assistant: assistant, historyStore: SearchHistoryStore(fileURL: url), debounce: .milliseconds(1))
    }

    private func selection(_ text: String) -> CapturedContext {
        CapturedContext(selectedText: text, surroundingText: "", cursorOffset: nil, source: .selection, targetElement: nil, sourceApplication: nil)
    }

    @MainActor
    private func waitForResponse(_ model: AssistantViewModel, query: String) async throws {
        for _ in 0..<200 {
            if model.response?.summary == "意味: \(query)", !model.isLoading { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("response for \(query) did not arrive")
    }

    @MainActor
    private func type(_ text: String, into model: AssistantViewModel) {
        model.queryText = text
        model.queryChanged()
    }

    @MainActor
    func testSelectionFillsQueryAndOnlyFinalResultIsSaved() async throws {
        let model = makeModel()
        model.begin(with: selection("residency"))
        XCTAssertEqual(model.queryText, "residency")
        XCTAssertFalse(model.isShowingHistory)
        try await waitForResponse(model, query: "residency")

        type("residency API", into: model)
        type("residency APIでは", into: model)
        try await waitForResponse(model, query: "residency APIでは")
        model.dismiss()

        XCTAssertEqual(model.historyItems.map(\.query), ["residency APIでは"])
    }

    @MainActor
    func testEmptyLaunchAndClearingShowHistory() async throws {
        let model = makeModel()
        model.begin(with: .empty)
        XCTAssertTrue(model.isShowingHistory)

        type("プレーンテキスト", into: model)
        try await waitForResponse(model, query: "プレーンテキスト")
        type("", into: model)
        XCTAssertTrue(model.isShowingHistory)
        XCTAssertNil(model.response)
        XCTAssertEqual(model.historyItems.map(\.query), ["プレーンテキスト"])
    }

    @MainActor
    func testOpeningHistoryRestoresWithoutDuplicatingAndEditsBecomeNewItem() async throws {
        let model = makeModel()
        model.begin(with: selection("residency APIでは"))
        try await waitForResponse(model, query: "residency APIでは")
        model.dismiss()

        model.begin(with: .empty)
        let original = try XCTUnwrap(model.historyItems.first)
        model.openHistory(original)
        XCTAssertEqual(model.queryText, "residency APIでは")
        XCTAssertEqual(model.response, original.response)
        model.dismiss()
        XCTAssertEqual(model.historyItems.count, 1)

        model.begin(with: .empty)
        model.openHistory(original)
        type("residency OpenAI APIでは", into: model)
        try await waitForResponse(model, query: "residency OpenAI APIでは")
        model.dismiss()

        XCTAssertEqual(model.historyItems.map(\.query), ["residency OpenAI APIでは", "residency APIでは"])
        XCTAssertEqual(model.historyItems.last, original)
    }
}
