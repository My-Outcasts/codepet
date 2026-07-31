import XCTest
@testable import codepet

final class RoadmapBoardCopyTests: XCTestCase {
    // Web VERB map: only actionable states earn a verb chip.
    func testVerbsMatchWeb() {
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .codepetCanDo, .en), "Start")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsApproval, .en), "Review")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsYou, .en), "Add your input")
        XCTAssertNil(RoadmapBoardCopy.verb(for: .done, .en))
        XCTAssertNil(RoadmapBoardCopy.verb(for: .blocked, .en))
    }

    func testVerbsLocalised() {
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .codepetCanDo, .vi), "Bắt đầu")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsApproval, .vi), "Duyệt")
        XCTAssertEqual(RoadmapBoardCopy.verb(for: .needsYou, .vi), "Cần bạn")
    }

    // done / blocked render as PLAIN TEXT on web, never a pill — so they get a quiet label
    // and no verb. Everything else is nil here (it has a chip instead).
    func testQuietLabelsOnlyForDoneAndBlocked() {
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .done, lang: .en), "Done")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .blocked, lang: .en), "Needs earlier steps")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .done, lang: .vi), "Xong")
        XCTAssertEqual(RoadmapBoardCopy.quietLabel(for: .blocked, lang: .vi), "Cần bước trước")
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .codepetCanDo, lang: .en))
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .needsYou, lang: .en))
        XCTAssertNil(RoadmapBoardCopy.quietLabel(for: .needsApproval, lang: .en))
    }

    // Web shows the small deliverable/tray marker ONLY on locked cards.
    func testTrayMarkerOnlyOnBlocked() {
        XCTAssertTrue(RoadmapBoardCopy.showsTrayMarker(.blocked))
        for s in [TaskStatus.done, .codepetCanDo, .needsYou, .needsApproval] {
            XCTAssertFalse(RoadmapBoardCopy.showsTrayMarker(s))
        }
    }

    // The beacon names the FOUNDER (never the companion), and falls back to second person —
    // composed so it reads "You are here", never "You is here".
    func testHerePhrase() {
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "Mona", lang: .en), "Mona is here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: nil, lang: .en), "You are here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "  ", lang: .en), "You are here")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "Mona", lang: .vi), "Mona đang ở đây")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: nil, lang: .vi), "Bạn đang ở đây")
    }

    // The nil branches must hold in BOTH languages: a state that renders a verb chip must never
    // also produce a quiet status line. Asserting only in English left a Vietnamese-only
    // regression invisible.
    func testQuietLabelsAreNilInVietnameseToo() {
        for status in [TaskStatus.codepetCanDo, .needsYou, .needsApproval] {
            XCTAssertNil(RoadmapBoardCopy.quietLabel(for: status, lang: .vi))
        }
    }

    // The whitespace-trim fallback is language-independent; pin it in Vietnamese so it stays that way.
    func testHerePhraseWhitespaceFallbackInVietnamese() {
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "   ", lang: .vi), "Bạn đang ở đây")
        XCTAssertEqual(RoadmapBoardCopy.herePhrase(founderName: "\n", lang: .vi), "Bạn đang ở đây")
    }
}
