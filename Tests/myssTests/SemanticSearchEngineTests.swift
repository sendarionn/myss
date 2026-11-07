import XCTest
@testable import myss

final class SemanticSearchEngineTests: XCTestCase {
    @MainActor
    func testSearchDirectionUsesShortTextAsHeadword() {
        let direction = SemanticSearchEngine().direction(for: "敷衍")
        XCTAssertEqual(direction, .wordToMeaning)
    }

    @MainActor
    func testSearchDirectionUsesSentenceAsMeaning() {
        let direction = SemanticSearchEngine().direction(for: "人に指示されなくても自分から考えて動く性質")
        XCTAssertEqual(direction, .meaningToWord)
    }

    func testLexicalSenseDecodesSeparateSenses() throws {
        let data = Data("""
        {"senses":[
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
