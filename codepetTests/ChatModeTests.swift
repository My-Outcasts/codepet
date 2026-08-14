import XCTest
@testable import codepet

final class ChatModeTests: XCTestCase {
    func testAskReturnsTextUnchanged() {
        XCTAssertEqual(ChatMode.ask.shape("what's next?", language: .en), "what's next?")
        XCTAssertEqual(ChatMode.ask.shape("việc gì tiếp?", language: .vi), "việc gì tiếp?")
    }

    func testPlanWrapsAndPreservesText() {
        let out = ChatMode.plan.shape("pricing page", language: .en)
        XCTAssertTrue(out.contains("pricing page"))
        XCTAssertNotEqual(out, "pricing page")
        XCTAssertTrue(out.lowercased().contains("plan"))
    }

    func testBuildNoLongerWrapsItsText() {
        // Inverted on 14 Aug, when Build absorbed Developer.
        //
        // Build's wrapper ("Let's build this together…") was never reaching
        // anyone: `send()` routes `.build` straight to a runner and has never
        // called `shape` for it. This test pinned the string, not the
        // behaviour — which is why the copy survived being unreachable, and
        // why I called it dead in the commit while a green test still asserted
        // it existed. It was dead in the app and alive here.
        //
        // Now it must be identity for a reason that DOES reach the founder:
        // the text becomes `engStartRun`'s `ask` — the agent's instruction and
        // the session title — so framing copy would land inside both.
        let ask = "landing page"
        XCTAssertEqual(ChatMode.build.shape(ask, language: .en), ask)
        XCTAssertEqual(ChatMode.build.shape(ask, language: .vi), ask)
    }

    func testPlanIsLocalized() {
        XCTAssertNotEqual(ChatMode.plan.shape("x", language: .en),
                          ChatMode.plan.shape("x", language: .vi))
    }

    func testAllCasesHaveNonEmptyLabels() {
        for m in ChatMode.allCases {
            XCTAssertFalse(m.label(.en).isEmpty)
            XCTAssertFalse(m.label(.vi).isEmpty)
        }
    }
}
