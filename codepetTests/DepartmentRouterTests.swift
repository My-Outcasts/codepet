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

    /// Spec §8 asks for a tier-order test proving tier 1 wins **even when tier 2 would pick a
    /// DIFFERENT department**. `testAddressedWins` cannot: "ask marketing about the launch"
    /// has tier 1 and tier 2 both landing on `mkt` ("launch" is in mkt's lexicon), so it stays
    /// green with the tiers swapped. This fixture genuinely splits them.
    ///
    /// Arithmetic for "ask design about the pricing page". Tier 1: `mentionedDeptKey` finds the
    /// addressed name "design". Tier 2, had it run: tokens are {ask, design, pricing, page}
    /// ("about"/"the" are stopwords). "design" is a department NAME and so is absent from every
    /// lexicon by construction (`testNoEntryIsADepartmentName`); "pricing" is fin's, scoring
    /// `lexiconWeight` = 3. "page" is not a term — mkt's entry is the PHRASE "landing page",
    /// which is not present. So fin 3, every other department 0, clearing floor (3) and margin
    /// (3 - 0 >= 2): tier 2 alone returns **fin**, asserted below rather than asserted about.
    ///
    /// Reorder `suggest` to score before it checks the name and the first assertion goes red
    /// with `fin`/`.topical` — which is the entire claim.
    func testAddressedWinsOverADifferentTopicalWinner() {
        let s = DepartmentRouter.suggest(text: "ask design about the pricing page",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "design")
        XCTAssertEqual(s?.tier, .addressed)

        // The other half of the proof: the same words, minus the address, really do go
        // somewhere else. Without this the test would pass on a fixture nobody checked.
        let topicalOnly = DepartmentRouter.suggest(text: "what about the pricing page",
                                                   tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(topicalOnly?.deptKey, "fin",
                       "fixture is void unless tier 2 picks a DIFFERENT department")
        XCTAssertEqual(topicalOnly?.tier, .topical)
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
    func testBelowFloorTotalYieldsNothing() {
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

    /// `testTasksBoostTheirDepartment`'s overlap of 3 is exactly `taskScoreCap` == `floor`, so
    /// it proves task overlap CAN clear the floor alone but says nothing about the weighted
    /// combination the 3-vs-1 weighting exists for. A fixture that only clears the FLOOR can't
    /// prove that either: one lexicon hit already scores `lexiconWeight` = 3 = floor, so a
    /// department never needs task overlap on top of a lexicon hit just to reach the floor —
    /// only to beat a rival that also reached it. This test forces that: the message has one
    /// eng lexicon hit ("bug") and one design lexicon hit ("icon"), tying both at 3 — which
    /// fails the margin (needs a 2-point lead) and returns nil. Tagging a task to eng whose
    /// title shares two OTHER words with the message ("need", "new") adds
    /// `taskWeight` * 2 = 2, taking eng to 5 against design's unchanged 3 — a 2-point lead,
    /// exactly `margin`. Only the task overlap wins this; the tied lexicon hit alone could
    /// not (proof: set `taskWeight = 0` and this test goes red — see task-4-report.md).
    func testTaskOverlapPlusLexiconHitCombine() {
        let tiedMessage = "there's a bug and we need a new icon soon"

        // eng ("bug") and design ("icon") each score exactly one lexicon hit: 3 vs 3. Tied,
        // so the margin gate refuses both.
        XCTAssertNil(DepartmentRouter.suggest(text: tiedMessage, tasks: [],
                                              lastActed: nil, language: .en))

        // eng gets a task overlapping the message on "need" and "new": taskScore =
        // min(2, taskScoreCap) = 2. eng total = 3 + 2 = 5; design stays at 3. 5 - 3 = 2 =
        // margin, so eng now wins the tie it could not win on the lexicon hit alone.
        let workTasks = [task("We need new server backups", dept: "eng")]
        let s = DepartmentRouter.suggest(text: tiedMessage, tasks: workTasks,
                                         lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "eng")
        XCTAssertEqual(s?.tier, .topical)
    }

    /// The word-boundary check in `contains(phrase:in:)` must reject an adjacent DIGIT, not
    /// just an adjacent letter — otherwise "page2" reads as a match for the phrase "landing
    /// page". Revert `isWordChar` to `ch.isLetter` alone and this goes red: the phrase is
    /// accepted, mkt scores `lexiconWeight` = 3 >= floor with no rival, and a suggestion comes
    /// back where there must be none.
    func testDigitImmediatelyAfterPhraseDoesNotCountAsAWordBoundary() {
        let s = DepartmentRouter.suggest(text: "the landing page2 mock",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertNil(s, "\"landing page2\" must not match the phrase \"landing page\"; got \(String(describing: s))")
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

    /// Nested vocabulary entries are ONE concept and must score once — spec §4.1 defines the
    /// lexicon score as a set intersection, and three pairs nest: "burn"/"burn rate",
    /// "terms"/"terms of service", "privacy"/"privacy policy".
    ///
    /// Each fixture below sets a nested phrase against a rival department holding exactly ONE
    /// ordinary lexicon hit, so it asserts the score through the only observable the router
    /// has: the margin.
    ///   • "our burn rate versus the layout" — fin {burn rate} = 3, design {layout} = 3. Tied,
    ///     so the margin (2) refuses both. Counted per term, fin is {burn, burn rate} = 6
    ///     against design's 3, a 3-point lead that clears the margin and routes to fin.
    ///   • "do the terms of service need a pricing clause" — legal {terms of service} = 3 vs
    ///     fin {pricing} = 3. Per term, legal is {terms, terms of service} = 6 and wins by 3.
    ///     This is the sentence the review named: a genuine two-department question that a
    ///     double count turned into a confident wrong answer.
    ///   • "does the privacy policy mention pricing" — legal {privacy policy} = 3 vs fin
    ///     {pricing} = 3. Per term, legal = 6.
    ///
    /// LOAD-BEARING: delete the `fired.contains(where:)` skip in `score` and all three go red,
    /// each returning the nesting department where there must be no suggestion. Verified by
    /// reverting the dedupe and running the suite, not by reasoning about it.
    func testNestedVocabularyEntriesScoreAsOneConcept() {
        XCTAssertNil(
            DepartmentRouter.suggest(text: "our burn rate versus the layout",
                                     tasks: [], lastActed: nil, language: .en),
            "\"burn\" + \"burn rate\" is one concept; fin must tie design, not beat it")
        XCTAssertNil(
            DepartmentRouter.suggest(text: "do the terms of service need a pricing clause",
                                     tasks: [], lastActed: nil, language: .en),
            "\"terms\" + \"terms of service\" is one concept; legal must tie fin, not beat it")
        XCTAssertNil(
            DepartmentRouter.suggest(text: "does the privacy policy mention pricing",
                                     tasks: [], lastActed: nil, language: .en),
            "\"privacy\" + \"privacy policy\" is one concept; legal must tie fin, not beat it")
    }

    /// The dedupe must not silence the phrase — it still fires, once, and it is the LONGER
    /// term that gets reported. `matched` is founder-facing ("you mentioned …"), so naming
    /// "burn rate" rather than the bare "burn" the table happens to list first is the point of
    /// walking longest-first rather than merely counting a set.
    func testANestedPhraseStillFiresAndReportsTheSpecificTerm() {
        let s = DepartmentRouter.suggest(text: "our burn rate is high",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertEqual(s?.tier, .topical)
        XCTAssertEqual(s?.matched, "burn rate",
                       "the hover must name the specific phrase, not the substring")
    }

    // MARK: - Tier 3: carry-over

    func testKeywordFreeFollowUpStaysWithTheLastDepartment() {
        let s = DepartmentRouter.suggest(text: "make it shorter",
                                         tasks: [], lastActed: "fin", language: .en)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertEqual(s?.tier, .carryOver)
        XCTAssertNil(s?.matched, "carry-over matched no word — the view says 'continuing with'")
    }

    func testAClearWinnerDisplacesCarryOver() {
        let s = DepartmentRouter.suggest(text: "the landing page needs work",
                                         tasks: [], lastActed: "fin", language: .en)
        XCTAssertEqual(s?.deptKey, "mkt")
        XCTAssertEqual(s?.tier, .topical)
    }

    func testAddressingDisplacesCarryOver() {
        let s = DepartmentRouter.suggest(text: "ask design about this",
                                         tasks: [], lastActed: "fin", language: .en)
        XCTAssertEqual(s?.deptKey, "design")
        XCTAssertEqual(s?.tier, .addressed)
    }

    func testNoLastActedMeansNoCarryOver() {
        XCTAssertNil(DepartmentRouter.suggest(text: "make it shorter",
                                              tasks: [], lastActed: nil, language: .en))
    }

    /// A department that lost its pet — or a stale key — must not be carried forward.
    func testCarryOverIgnoresAnUnroutableKey() {
        XCTAssertNil(DepartmentRouter.suggest(text: "make it shorter",
                                              tasks: [], lastActed: "product", language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "make it shorter",
                                              tasks: [], lastActed: "nonsense", language: .en))
    }

    /// Carry-over is language-agnostic: it is memory, not vocabulary.
    func testCarryOverWorksInVietnamese() {
        let s = DepartmentRouter.suggest(text: "ngắn hơn được không",
                                         tasks: [], lastActed: "fin", language: .vi)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertEqual(s?.tier, .carryOver)
    }
}
