import XCTest
@testable import codepet

/// Tier order is the safety model. Tier 1 is today's behaviour, called unchanged and placed
/// above everything new — so every message that routes today routes the same way, and the new
/// tiers can only add answers where there were none.
final class DepartmentRouterTests: XCTestCase {

    func testAddressedWins() {
        let s = DepartmentRouter.suggest(text: "ask marketing about the launch",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "mkt")
        XCTAssertEqual(s?.tier, .addressed)
    }

    func testNothingToGoOnYieldsNoSuggestion() {
        XCTAssertNil(DepartmentRouter.suggest(text: "hello",
                                              tasks: [], lastActed: nil, language: .en))
    }

    func testEmptyDraftIsNeverPreArmed() {
        XCTAssertNil(DepartmentRouter.suggest(text: "",
                                              tasks: [], lastActed: nil, language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "   \n  ",
                                              tasks: [], lastActed: nil, language: .en))
    }

    // MARK: - Tier 2: topical

    private func task(_ title: String, dept: String) -> RoadmapTask {
        // `TaskWho` is `does | draft | you` — there is no `.founder`.
        RoadmapTask(id: UUID().uuidString, title: title, detail: "",
                    phase: .build, who: .you, dept: dept)
    }

    func testTopicalRoutesWithoutNamingTheDepartment() {
        let s = DepartmentRouter.suggest(text: "how should I price the pro tier?",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertEqual(s?.tier, .topical)
        XCTAssertEqual(s?.matched, "price")
    }

    /// The floor. One weak token must not route a turn.
    func testASingleNonLexiconTokenYieldsNothing() {
        XCTAssertNil(DepartmentRouter.suggest(text: "can you look at this thing tomorrow",
                                              tasks: [], lastActed: nil, language: .en))
    }

    /// The margin, and the "near-ties stay with byte" decision. This sentence is genuinely
    /// two departments and byte is the honest answer.
    func testTwoDepartmentsWithinTheMarginYieldNothing() {
        let s = DepartmentRouter.suggest(
            text: "the landing page copy feels off and I'm not sure the price is right",
            tasks: [], lastActed: nil, language: .en)
        XCTAssertNil(s, "mkt and fin are within the margin; got \(String(describing: s))")
    }

    /// Guard 1 — the Aug 7 shape. A founder pasting a customer's words must not change who
    /// answers. DIRECT REGRESSION TEST.
    func testQuotedSpansDoNotVote() {
        let s = DepartmentRouter.suggest(
            text: "She said \"it emails me when something's off instead of a refund ticket\"",
            tasks: [], lastActed: nil, language: .en)
        XCTAssertNil(s, "words inside a quote are someone else's; got \(String(describing: s))")
    }

    func testBlockquotedLinesDoNotVote() {
        let s = DepartmentRouter.suggest(text: "what do you make of this\n> refund ticket faq",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertNil(s)
    }

    /// Guard 2 — whole words only, inherited from the tokenizer.
    func testSubstringsDoNotFire() {
        XCTAssertNil(DepartmentRouter.suggest(text: "the app is well designed",
                                              tasks: [], lastActed: nil, language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "our operational costs are high",
                                              tasks: [], lastActed: nil, language: .en))
    }

    /// Multi-word entries match against raw text, since tokenize() cannot see a phrase.
    func testPhrasesMatch() {
        let s = DepartmentRouter.suggest(text: "the landing page needs work",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "mkt")
        XCTAssertEqual(s?.matched, "landing page")
    }

    /// The founder's own roadmap is signal. Same sentence, different company, different answer.
    func testTasksBoostTheirDepartment() {
        let text = "can we make the checkout smoother"
        XCTAssertNil(DepartmentRouter.suggest(text: text, tasks: [],
                                              lastActed: nil, language: .en))
        let withWork = DepartmentRouter.suggest(
            text: text,
            // NOTE: deviates from the brief's literal titles ("Redesign the checkout screen",
            // "Checkout empty state"), which only share ONE content word ("checkout") with the
            // query. taskScore = min(overlap, taskScoreCap) * taskWeight = 1 * 1 = 1, which
            // cannot cross floor = 3 under the brief's own fixed constants — confirmed by
            // running the tokenizer on both strings by hand. Vocabulary tuning (the brief's
            // sanctioned escape hatch) cannot fix this: any lexicon term matching "checkout",
            // "make", "can", or "smoother" would also fire on the bare query with `tasks: []`,
            // which the test's first assertion requires to stay nil. So the fixture itself is
            // adjusted to share three content words ("make", "checkout", "smoother") with the
            // query, reaching taskScore = 3 = floor, same scenario intent. See task-4-report.md.
            tasks: [task("Make the checkout flow smoother", dept: "design"),
                    task("Redesign checkout screen", dept: "design")],
            lastActed: nil, language: .en)
        XCTAssertEqual(withWork?.deptKey, "design")
        XCTAssertEqual(withWork?.tier, .topical)
    }

    /// Spec §4.4's third example — an approved behaviour CHANGE. Tier 1 still refuses to hand
    /// this to Support off the bare word "support"; tier 2 gives it to Finance, which is who
    /// should hold a sentence about investors.
    func testInvestorsSentenceGoesToFinanceNotSupport() {
        let s = DepartmentRouter.suggest(text: "we have support from two angel investors",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "we have support from two angel investors"),
                     "tier 1 must still refuse this — the Aug 10 regression")
    }

    /// Vietnamese has no vocabulary yet, so tier 2 is silent rather than wrong.
    func testVietnameseYieldsNoTopicalSuggestion() {
        XCTAssertNil(DepartmentRouter.suggest(text: "định giá cho pro tier thế nào?",
                                              tasks: [], lastActed: nil, language: .vi))
    }
}
