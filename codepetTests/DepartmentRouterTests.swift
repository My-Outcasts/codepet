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

    /// The floor. A 2-word task-title overlap with zero lexicon hits scores 2 — above zero,
    /// below the floor (3) — and must not route. This is deliberately NOT a fixture that
    /// scores 0 everywhere: a 0-everywhere fixture passes even with `floor` lowered to 0, so
    /// it proves nothing about the floor. This one does: with `floor` at 0, `best.total (2)
    /// - runnerUp (0) = 2 >= margin (2)` would clear BOTH gates and return a suggestion, so
    /// the test only stays green because `floor` is 3.
    func testASingleNonLexiconTokenYieldsNothing() {
        let s = DepartmentRouter.suggest(
            text: "can we rearrange the closet somehow",
            tasks: [task("Rearrange the storage closet shelving", dept: "ops")],
            lastActed: nil, language: .en)
        XCTAssertNil(s, "a 2-word task-title overlap is below the floor; got \(String(describing: s))")
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

    /// Guard 2 — whole words only, inherited from the tokenizer. Each fixture contains a REAL
    /// vocabulary term as a substring of a longer token, not as its own token: "apiary"
    /// contains "api" (eng), "brandish" contains "brand" (mkt), "screenshot" contains
    /// "screen" (design). A naive `raw.contains(term)` implementation would fire on all
    /// three and return a suggestion; `TextRelevance.tokenize`'s whole-word split does not,
    /// because `tokens.contains("api")` is false when the only token present is "apiary".
    func testSubstringsDoNotFire() {
        XCTAssertNil(DepartmentRouter.suggest(text: "she keeps bees in an apiary",
                                              tasks: [], lastActed: nil, language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "the salesman began to brandish his badge",
                                              tasks: [], lastActed: nil, language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "he sent me a screenshot of the issue",
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

    /// `testTasksBoostTheirDepartment`'s overlap of 3 is exactly `taskScoreCap` == `floor`,
    /// so it proves task overlap CAN clear the floor alone but says nothing about the
    /// weighted combination the 3-vs-1 weighting exists for. This test isolates that: a
    /// 2-word title overlap is below the floor by itself (taskScore = 2), and the SAME
    /// overlap plus a single lexicon hit (worth `lexiconWeight` = 3) clears it together
    /// (2 + 3 = 5 >= floor), which neither alone would.
    func testTaskOverlapPlusLexiconHitCombine() {
        let workTasks = [task("Tidy the archive folder", dept: "eng")]

        // Task-title overlap alone: {"tidy", "folder"} = 2. Below floor (3).
        XCTAssertNil(DepartmentRouter.suggest(text: "can we tidy the folder soon",
                                              tasks: workTasks, lastActed: nil, language: .en))

        // Same overlap, plus one eng lexicon hit ("backend"): 2 + (1 * lexiconWeight) = 5.
        let s = DepartmentRouter.suggest(text: "can we tidy the folder in the backend soon",
                                         tasks: workTasks, lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "eng")
        XCTAssertEqual(s?.tier, .topical)
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

    /// Vietnamese has no vocabulary yet, so tier 2 is silent rather than wrong. A Vietnamese
    /// FIXTURE proves nothing on its own — it also hits nothing in the English lexicon, so
    /// it would come back nil even if `terms(for:language:)` ignored `language` entirely.
    /// The pair below is the actual proof: the SAME English-vocabulary text scores under
    /// `.en` (finding "runway" and "burn" and routing to finance) but must score nothing
    /// once the only thing that changed is `language: .vi`, because
    /// `DepartmentTopics.map["fin"]!.vi` is empty.
    func testVietnameseYieldsNoTopicalSuggestion() {
        let text = "we need to talk about runway and burn"

        let en = DepartmentRouter.suggest(text: text, tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(en?.deptKey, "fin", "sanity check: this text must score under English")
        XCTAssertEqual(en?.tier, .topical)

        XCTAssertNil(DepartmentRouter.suggest(text: text, tasks: [], lastActed: nil, language: .vi),
                     "identical tokens must not score once language is .vi")
    }
}
