// codepetTests/BriefDocumentTests.swift
import XCTest
@testable import codepet

/// THE CALL's split: what stays on the card as a headline, and what moves into the reader.
///
/// The card rendered seven sections from eight `VCBrief` fields — ~550 words, nothing clamped, in a
/// 380pt column (founder, Aug 7). `BriefDocument` is the pure half of the fix, so the split is
/// testable without a view.
final class BriefDocumentTests: XCTestCase {

    private func brief(recommendation: String = "Do the thing. Then the other thing.",
                       confidence: Int = 3,
                       reason: String = "because",
                       real: String = "they disagreed",
                       tradeoff: String = "either A or B",
                       kill: [String] = ["it failed"],
                       action: String = "list the users",
                       owner: String = "mona",
                       unknown: String = "the cost",
                       unresolved: Bool = true) -> VCBrief {
        VCBrief(recommendation: recommendation, confidence: confidence, confidenceReason: reason,
                theRealDisagreement: real, tradeoffFounderMustOwn: tradeoff, killCriteria: kill,
                nextAction: VCNextAction(action: action, owner: owner),
                whatWeDontKnow: unknown, unresolved: unresolved)
    }

    // MARK: - headline

    /// The founder's own brief, verbatim: the first sentence IS the decision, and the em-dash
    /// clause belongs to it.
    func testTheHeadlineIsTheFirstSentenceAndKeepsItsEmDashClause() {
        let rec = "Don't build a pricing plan this week — run a price test this week. Sales' "
            + "sequencing wins on the merits because Finance never produced the one number."
        XCTAssertEqual(BriefDocument.headline(rec),
                       "Don't build a pricing plan this week — run a price test this week.")
    }

    /// A terminator must be followed by a space, or a decimal splits the call in half.
    func testADecimalDoesNotEndTheSentence() {
        XCTAssertEqual(BriefDocument.headline("Charge $9.99 a month from day one. Then revisit."),
                       "Charge $9.99 a month from day one.")
    }

    /// A two- or three-word opener is a throat-clear, not the call. Heading the card with "Two
    /// things." would say nothing, so the whole paragraph is better than a useless line.
    func testAThroatClearingOpenerFallsBackToTheWholeText() {
        let rec = "Two things. Run the price test, and pull the cost number tomorrow."
        XCTAssertEqual(BriefDocument.headline(rec), rec)
        XCTAssertEqual(BriefDocument.headline("Short answer. Do not build it yet."),
                       "Short answer. Do not build it yet.")
    }

    /// Measured in WORDS, not characters: this first sentence is 23 characters and a complete
    /// decision. A character threshold called it a fragment and swallowed the whole paragraph onto
    /// the card — the exact cramming this change exists to stop.
    func testAShortButCompleteFirstSentenceIsStillTheHeadline() {
        let rec = "Run the test this week. Here is why that beats building the plan."
        XCTAssertEqual(BriefDocument.headline(rec), "Run the test this week.")
    }

    func testASingleSentenceIsItsOwnHeadline() {
        let rec = "Run a real price test with five of your beta users this week."
        XCTAssertEqual(BriefDocument.headline(rec), rec)
    }

    func testEmptyRecommendationYieldsEmptyHeadline() {
        XCTAssertEqual(BriefDocument.headline("   "), "")
    }

    // MARK: - hasMore

    /// No reader button when the reader would be empty.
    func testAOneSentenceCallWithNothingElseOffersNoReader() {
        let b = brief(recommendation: "Run the price test this week.",
                      kill: [], action: "", unknown: "")
        XCTAssertFalse(BriefDocument.hasMore(b))
    }

    func testMoreRecommendationMeansThereIsSomethingToRead() {
        let b = brief(recommendation: "Run the test this week. Here is why that beats the plan.",
                      kill: [], action: "", unknown: "")
        XCTAssertTrue(BriefDocument.hasMore(b))
    }

    /// A one-sentence call still has a reader when the OTHER fields carry weight — the next action
    /// alone is worth a document.
    func testKillCriteriaOrNextActionAloneEarnTheReader() {
        XCTAssertTrue(BriefDocument.hasMore(
            brief(recommendation: "Run the price test this week.", kill: ["day 10 passes"],
                  action: "", unknown: "")))
        XCTAssertTrue(BriefDocument.hasMore(
            brief(recommendation: "Run the price test this week.", kill: [],
                  action: "email six users", unknown: "")))
    }

    // MARK: - document

    func testTheDocumentOrdersSectionsForReadingNotForFieldOrder() {
        let doc = BriefDocument.document(brief(), language: .en)
        XCTAssertEqual(doc.kind, .doc)
        XCTAssertEqual(doc.payload?.sections?.map(\.h),
                       ["Do this next · mona", "Stop if", "Still unknown"])
    }

    /// The lead block is the recommendation IN FULL — the card only ever showed its first
    /// sentence, so the reader is the one place the whole thing exists.
    func testTheDocumentCarriesTheWholeRecommendation() {
        let rec = "Do the thing. Then the other thing, for these reasons."
        let doc = BriefDocument.document(brief(recommendation: rec), language: .en)
        XCTAssertEqual(doc.payload?.call, rec)
        XCTAssertEqual(doc.body, rec)
    }

    /// The contract pins three things to the CARD. If they leaked into the document they would be
    /// said twice, which is the duplication this whole change removes.
    func testTheDocumentDoesNotRepeatWhatTheContractPinsToTheCard() {
        let doc = BriefDocument.document(
            brief(real: "REAL_DISAGREEMENT_MARKER", tradeoff: "TRADEOFF_MARKER"), language: .en)
        let all = ((doc.payload?.sections ?? []).map { $0.h + $0.p }
                    + [doc.payload?.call ?? "", doc.body]).joined()
        XCTAssertFalse(all.contains("TRADEOFF_MARKER"), "rule 5 keeps the either/or on the card")
        XCTAssertFalse(all.contains("REAL_DISAGREEMENT_MARKER"), "rule 3's text is its own card")
    }

    func testEmptySectionsAreOmittedRatherThanRenderedAsEmptyHeadings() {
        let doc = BriefDocument.document(brief(kill: [], action: "  ", unknown: ""), language: .en)
        XCTAssertEqual(doc.payload?.sections?.count, 0)
    }

    func testAnOwnerlessNextActionStillGetsItsSection() {
        let doc = BriefDocument.document(brief(owner: "  "), language: .en)
        XCTAssertEqual(doc.payload?.sections?.first?.h, "Do this next")
    }

    func testVietnameseHeadingsAndTitle() {
        let doc = BriefDocument.document(brief(), language: .vi)
        XCTAssertEqual(doc.title, "Quyết định")
        XCTAssertEqual(doc.payload?.sections?.first?.h, "Việc tiếp theo · mona")
    }
}

/// Tool-call markup that leaked out of the model must never reach the founder.
///
/// Seen in the reader on Aug 7: "Do this next" opened with
/// `<parameter name="action">Write the one-sentence value prop…`. The model emitted a fragment of
/// its own tool syntax inside `next_action.action` and it was stored and rendered verbatim. The
/// real fix is upstream — the Cloud Function should not persist a field still containing tool
/// syntax — but the client is where it is seen.
final class ModelTextTests: XCTestCase {

    /// The exact leak, from the screenshot.
    func testTheReportedParameterTagIsStripped() {
        let leaked = "<parameter name=\"action\">Write the one-sentence value prop, then ship a "
            + "static waitlist page."
        XCTAssertEqual(ModelText.stripToolMarkup(leaked),
                       "Write the one-sentence value prop, then ship a static waitlist page.")
    }

    func testClosingAndNamespacedTagsGoToo() {
        XCTAssertEqual(ModelText.stripToolMarkup("<invoke name=\"x\">do it</invoke>"), "do it")
        XCTAssertEqual(ModelText.stripToolMarkup("<parameter name=\"a\">do it"), "do it")
        XCTAssertEqual(ModelText.stripToolMarkup("<function_calls>do it</function_calls>"), "do it")
    }

    /// The conservative half, and the one that matters more: an engineering deliverable is full of
    /// angle brackets, and eating them would be a worse failure than leaving a stray tag.
    func testRealAngleBracketsInProseSurvive() {
        XCTAssertEqual(ModelText.stripToolMarkup("Ship it if x < y and y > z."),
                       "Ship it if x < y and y > z.")
        XCTAssertEqual(ModelText.stripToolMarkup("Wrap the copy in <html> and <p> tags."),
                       "Wrap the copy in <html> and <p> tags.")
    }

    /// The match is anchored to the whole tag name — a tag that merely starts with the same letters
    /// is someone else's content.
    func testATagThatOnlyStartsWithAToolNameIsLeftAlone() {
        XCTAssertEqual(ModelText.stripToolMarkup("Use <parameters> in the schema."),
                       "Use <parameters> in the schema.")
    }

    /// Paragraph breaks carry the document's structure and must survive the sweep.
    func testParagraphBreaksSurvive() {
        XCTAssertEqual(ModelText.stripToolMarkup("First line.\n\nSecond line."),
                       "First line.\n\nSecond line.")
    }

    func testCleanTextIsUnchanged() {
        let prose = "Ship the waitlist tomorrow as a single static page."
        XCTAssertEqual(ModelText.stripToolMarkup(prose), prose)
    }

    /// End to end: the leak must not survive into the document the reader draws.
    func testTheDocumentIsSweptNotJustTheRawField() {
        let b = VCBrief(recommendation: "Ship it. Then measure.", confidence: 3,
                        confidenceReason: "", theRealDisagreement: "", tradeoffFounderMustOwn: "",
                        killCriteria: ["<parameter name=\"k\">it exceeds a day"],
                        nextAction: VCNextAction(action: "<parameter name=\"action\">Do the thing",
                                                 owner: "mona"),
                        whatWeDontKnow: "", unresolved: false)
        let doc = BriefDocument.document(b, language: .en)
        let all = (doc.payload?.sections ?? []).map { $0.h + $0.p }.joined()
        XCTAssertFalse(all.contains("<parameter"))
        XCTAssertTrue(all.contains("Do the thing"))
        XCTAssertTrue(all.contains("it exceeds a day"))
    }
}
