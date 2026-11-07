import XCTest
@testable import myss

final class SemanticSearchEngineTests: XCTestCase {
    func testResponseDecodesIntents() throws {
        func decode(_ json: String) throws -> SearchIntent {
            try JSONDecoder().decode(SearchResponse.self, from: Data(json.utf8)).searchIntent
        }
        XCTAssertEqual(
            try decode(#"{"intent":"wordMeaning","query":"敷衍","headword":"敷衍","senses":[],"phase":"embedding"}"#),
            .wordMeaning(headword: "敷衍")
        )
        XCTAssertEqual(
            try decode(#"{"intent":"wordMeaningWithContext","query":"リリース ビジネス","headword":"リリース","context":"ビジネス","senses":[],"phase":"embedding"}"#),
            .wordMeaningWithContext(headword: "リリース", context: "ビジネス")
        )
        XCTAssertEqual(
            try decode(#"{"intent":"meaningToWord","query":"自分で決める","senses":[],"phase":"embedding"}"#),
            .meaningToWord(query: "自分で決める")
        )
    }

    func testCapturedContextIsUsedOnlyWhileQueryStartsWithSelectedHeadword() {
        let sentence = "新製品のリリース時期を来月に変更する。"
        XCTAssertEqual(SearchViewModel.capturedContext(for: "リリース", selectedHeadword: "リリース", surroundingText: sentence), sentence)
        XCTAssertEqual(SearchViewModel.capturedContext(for: "リリース　営業資料", selectedHeadword: "リリース", surroundingText: sentence), sentence)
        XCTAssertNil(SearchViewModel.capturedContext(for: "リリースノート", selectedHeadword: "リリース", surroundingText: sentence))
        XCTAssertNil(SearchViewModel.capturedContext(for: "製品を公開すること", selectedHeadword: "リリース", surroundingText: sentence))
        XCTAssertNil(SearchViewModel.capturedContext(for: "リリース", selectedHeadword: "リリース", surroundingText: ""))
    }

    func testLexicalSenseDecodesSeparateSenses() throws {
        let data = Data("""
        {"intent":"wordMeaning","query":"橋","headword":"橋","senses":[
          {"id":"bridge-1","headword":"橋","partOfSpeech":"n","summary":"川を渡る構造物","definitions":["川を渡る構造物"],"aliases":[],"examples":[],"sources":[],"relatedWords":[],"score":0.9},
          {"id":"bridge-2","headword":"橋","partOfSpeech":"n","summary":"二者をつなぐもの","definitions":["二者をつなぐもの"],"aliases":[],"examples":[],"sources":[],"relatedWords":[],"score":0.8}
        ],"phase":"embedding"}
        """.utf8)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        XCTAssertEqual(response.senses.count, 2)
        XCTAssertNotEqual(response.senses[0].id, response.senses[1].id)
    }

    func testContextExtractionUsesCurrentSentenceOnly() {
        let text = "前の文です。自分で判断して動くような姿勢が必要だ。次の文です。"
        let location = ("前の文です。自分で判断して" as NSString).length
        XCTAssertEqual(
            AccessibilityContextReader.contextAroundCursor(in: text, utf16Location: location),
            "自分で判断して動くような姿勢が必要だ。"
        )
    }
}
