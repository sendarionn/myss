import XCTest
@testable import myss

final class SemanticSearchEngineTests: XCTestCase {
    private let engine = SemanticSearchEngine()

    func testTemporaryTreatmentQueryRanksExpectedCandidate() {
        let results = engine.search(
            query: "問題の原因そのものには手を付けず、今起きている問題だけを一時的に抑える",
            direction: .meaningToWord
        )
        XCTAssertTrue(Set(results.prefix(3).map(\.entry.word)).contains("対症療法"))
    }

    func testInitiativeQueryReturnsRelevantWords() {
        let results = engine.search(query: "人に指示されなくても自分から考えて動く性質", direction: .meaningToWord)
        let topFive = Set(results.prefix(5).map(\.entry.word))
        XCTAssertTrue(topFive.contains("主体性"))
        XCTAssertTrue(topFive.contains("自主性"))
    }

    func testExactHeadwordSelectsWordToMeaning() {
        XCTAssertEqual(engine.direction(for: "敷衍"), .wordToMeaning)
        XCTAssertEqual(engine.search(query: "敷衍", direction: .wordToMeaning).first?.entry.word, "敷衍")
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
