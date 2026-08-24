import XCTest
@testable import codepet

/// The tokenizer moved out of `ChatContext` so `DepartmentRouter` could use it without a
/// second copy of the stopword list. A duplicated stopword list is a live trap: fixing one
/// copy leaves the other wrong, silently, in a grounding path.
final class TextRelevanceTests: XCTestCase {
    func testTokenizeLowercasesDedupesAndDropsShortWords() {
        let tokens = TextRelevance.tokenize("Pricing pricing PRICING at $19 ok")
        XCTAssertTrue(tokens.contains("pricing"))
        XCTAssertEqual(tokens.filter { $0 == "pricing" }.count, 1)
        // Under three characters never survives — this is why the lexicon has no "ux"/"ui".
        XCTAssertFalse(tokens.contains("at"))
        XCTAssertFalse(tokens.contains("19"))
    }

    func testTokenizeDropsStopwords() {
        let tokens = TextRelevance.tokenize("the and for our your their")
        XCTAssertTrue(tokens.isEmpty, "stopwords carry no signal; got \(tokens)")
    }

    func testTokenizeSplitsOnPunctuationSoWholeWordsOnly() {
        // "designed" must never match "design" — the Aug 7 substring defect.
        let tokens = TextRelevance.tokenize("well-designed, fast/cheap")
        XCTAssertTrue(tokens.contains("designed"))
        XCTAssertFalse(tokens.contains("design"))
        XCTAssertTrue(tokens.contains("fast"))
        XCTAssertTrue(tokens.contains("cheap"))
    }

    func testOverlapCountsSharedTokens() {
        let a = TextRelevance.tokenize("pricing runway investors")
        let b = TextRelevance.tokenize("runway investors margin")
        XCTAssertEqual(TextRelevance.overlap(a, b), 2)
    }
}
