import XCTest
@testable import codepet

final class DecisionsTests: XCTestCase {
    func testMergeSupersedesSameTopicCaseInsensitiveAndStamps() {
        let existing = [DecisionEntry(topic: "Pricing", statement: "old", source: nil, updatedAt: 1)]
        let out = Decisions.mergeDecisions(existing: existing,
            extracted: [ExtractedDecision(topic: "pricing", statement: "Plus is $4/mo", source: "Pricing page")],
            now: 1000)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].statement, "Plus is $4/mo")
        XCTAssertEqual(out[0].updatedAt, 1000)
        XCTAssertEqual(out[0].source, "Pricing page")
    }
    func testMergePreservesUntouchedAndAppendsNew() {
        let existing = [DecisionEntry(topic: "naming", statement: "Codepet", source: nil, updatedAt: 1)]
        let out = Decisions.mergeDecisions(existing: existing,
            extracted: [ExtractedDecision(topic: "tech", statement: "SwiftUI", source: nil)], now: 2)
        XCTAssertEqual(out.map { $0.topic }, ["naming", "tech"])
    }
    func testMergeDropsEmptyAndCapsKeepingRecent() {
        let existing = (0..<30).map { DecisionEntry(topic: "t\($0)", statement: "s", source: nil, updatedAt: Double($0)) }
        let out = Decisions.mergeDecisions(existing: existing,
            extracted: [ExtractedDecision(topic: "", statement: "x", source: nil),
                        ExtractedDecision(topic: "new", statement: "recent", source: nil)], now: 999)
        XCTAssertEqual(out.count, 30)
        XCTAssertTrue(out.contains { $0.topic == "new" })   // newest kept
        XCTAssertFalse(out.contains { $0.topic == "t0" })   // oldest evicted
    }
    func testNormalizeDropsEmptyTrimsCaps() {
        let raw = [DecisionEntry(topic: " a ", statement: " b ", source: " ", updatedAt: nil),
                   DecisionEntry(topic: "", statement: "x", source: nil, updatedAt: nil)]
        let out = Decisions.normalizeDecisions(raw)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].topic, "a"); XCTAssertEqual(out[0].statement, "b"); XCTAssertNil(out[0].source)
    }
    func testComposeEmptyAndNonEmpty() {
        XCTAssertEqual(Decisions.composeDecisions([]), "")
        let s = Decisions.composeDecisions([DecisionEntry(topic: "pricing", statement: "$4/mo", source: nil, updatedAt: nil)])
        XCTAssertTrue(s.contains("honor these"))
        XCTAssertTrue(s.contains("- pricing: $4/mo"))
    }
}
