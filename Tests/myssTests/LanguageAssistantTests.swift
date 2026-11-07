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
    private let release = LanguageResponse(intent: .explainExpression, targetExpression: "リリース", summary: "公開すること", candidates: [])

    func testPromptMarksCursorAndKeepsInputsSeparate() {
        let request = LanguageRequest(
            selectedText: "", surroundingContext: "抑えるだけなので、", cursorOffset: 9,
            history: [], manualInstruction: "熟語で"
        )
        XCTAssertEqual(LanguagePrompt.prompt(for: request), """
        <selected_text></selected_text>
        <context>抑えるだけなので、\(LanguagePrompt.cursorMarker)</context>
        <instruction>熟語で</instruction>
        """)
    }

    func testFollowUpPromptCarriesPreviousContextAndAnswer() {
        let request = LanguageRequest(
            selectedText: "residency", surroundingContext: "", cursorOffset: nil,
            history: [
                LanguageTurn(instruction: "", response: LanguageResponse(intent: .explainExpression, targetExpression: "residency", summary: "居住、滞在", candidates: [])),
                LanguageTurn(instruction: "APIでは", response: LanguageResponse(intent: .explainExpression, targetExpression: "residency", summary: "データの保存地域", candidates: []))
            ],
            manualInstruction: "クラウドでは"
        )
        let prompt = LanguagePrompt.prompt(for: request)
        XCTAssertTrue(prompt.contains("<selected_text>residency</selected_text>"))
        XCTAssertTrue(prompt.contains("<instruction>APIでは</instruction>"))
        XCTAssertTrue(prompt.contains("summary: データの保存地域"))
        XCTAssertTrue(prompt.hasSuffix("最新のinstructionを加えた現在の結果を1つ返してください"))
        XCTAssertTrue(prompt.contains("<instruction>クラウドでは</instruction>"))
    }

    func testDescribeIncludesTargetAndCandidates() {
        let response = LanguageResponse(intent: .findExpression, summary: "", candidates: [
            LanguageCandidate(text: "対症療法", explanation: ""), LanguageCandidate(text: "応急処置", explanation: "")
        ])
        XCTAssertEqual(LanguagePrompt.describe(response), "intent: find_expression / candidates: 対症療法、応急処置")
        XCTAssertTrue(LanguagePrompt.describe(release).contains("target_expression: リリース"))
    }

    func testPromptDoesNotDecideIntentFromSelectionAlone() {
        XCTAssertTrue(LanguagePrompt.system.contains("選択文字列の有無だけでintentを決めない"))
        XCTAssertFalse(LanguagePrompt.system.contains("追加指示がなければexplain_expression"))
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
    }

    actor Counter {
        var value = 0
        func increment() { value += 1 }
    }

    private let request = LanguageRequest(selectedText: "", surroundingContext: "一時的に抑える", cursorOffset: 7, history: [], manualInstruction: "")

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
        let cases: [(String, String, [LanguageTurn])] = [
            ("プレーンテキスト", "", []),
            ("", "プレーンテキスト プログラミングでは", []),
            ("", "プログラミングなどでの、シンプルなテキストファイルのこと", []),
            ("", "営業でいうリード", []),
            ("", "見込み客や将来顧客になる可能性のある相手", []),
            ("リリース", "もっと堅く", [])
        ]
        for (selected, instruction, history) in cases {
            let request = LanguageRequest(selectedText: selected, surroundingContext: "", cursorOffset: nil, history: history, manualInstruction: instruction)
            let clock = ContinuousClock()
            let start = clock.now
            let response = try await provider.request(request)
            print("[live] selected=\(selected) instruction=\(instruction) elapsed=\(clock.now - start)")
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
