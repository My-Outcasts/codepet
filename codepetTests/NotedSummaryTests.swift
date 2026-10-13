// codepetTests/NotedSummaryTests.swift
import XCTest
@testable import codepet

/// Remembered facts fold into one line instead of one pill each (12 Oct, founder screenshot of
/// three "📌 Noted" pills under a Finance reply).
final class NotedSummaryTests: XCTestCase {

    private let burn = RememberedFact(topic: "burn", statement: "Tiffin burns $6k a month.")
    private let cash = RememberedFact(topic: "cash", statement: "Tiffin has $48k in the bank.")
    private let runway = RememberedFact(topic: "runway", statement: "Tiffin's runway is 8 months.")

    func testSeveralFactsFoldToACountAndTheirTopics() {
        XCTAssertEqual(NotedSummary.line([burn, cash, runway], lang: .en), "Noted 3 facts · burn, cash, runway")
        XCTAssertTrue(NotedSummary.folds([burn, cash]))
    }

    func testOneFactStaysInlineWithItsSentence() {
        XCTAssertEqual(NotedSummary.line([burn], lang: .en), "Noted · burn — Tiffin burns $6k a month.")
        XCTAssertFalse(NotedSummary.folds([burn]))
    }

    func testVietnamese() {
        XCTAssertEqual(NotedSummary.line([burn, cash], lang: .vi), "Đã ghi nhớ 2 điều · burn, cash")
    }

    func testNothingToAcknowledge() {
        XCTAssertNil(NotedSummary.line([], lang: .en))
    }

    /// The decorative pin and the per-fact pill are gone from the chat view's noted row.
    func testChatViewNoLongerPinsEachFact() throws {
        let src = try String(contentsOfFile: #filePath
            .replacingOccurrences(of: "codepetTests/NotedSummaryTests.swift",
                                  with: "codepet/Views/Copilot/CopilotChatView.swift"), encoding: .utf8)
        XCTAssertFalse(src.contains("Text(\"📌 \""))
        XCTAssertTrue(src.contains("NotedSummary.line("))
    }
}
