// codepetTests/BriefReadTests.swift
import XCTest
@testable import codepet

/// The greeting named the founder's project and never said anything about it. This composes
/// the missing "here's what I understood" paragraph from what she actually typed.
///
/// **Why not the model's own summary alone.** `brief.summary` is written by onboarding's
/// enrich step, which runs on the founder's Claude — and she has not granted it yet, because
/// consent is asked at first use and onboarding comes first. `localOneShot` throws
/// `.blocked(.notGranted)` and `CompanyStore:807` fails open, so `summary` is nil on first
/// run for everyone. It IS filled later, for a founder who edits her brief after granting,
/// which is why it still wins when present.
final class BriefReadTests: XCTestCase {

    private func brief(oneLiner: String? = nil, summary: String? = nil,
                       audience: String? = nil, stage: String? = "Building",
                       goal: String? = nil) -> CompanyBrief {
        CompanyBrief(stage: stage, oneLiner: oneLiner, summary: summary,
                     audience: audience, goal: goal)
    }

    // MARK: - The anchor rule

    /// `stage` is the one field that is ALWAYS non-nil (`CompanyOnboardingModel` defaults it
    /// to "Building"). Composing off it alone would tell the founder what she picked from a
    /// slider and call it a read.
    func testStageAloneProducesNothing() {
        XCTAssertNil(BriefRead.compose(brief: brief(), language: .en))
    }

    func testAudienceWithoutAnAnchorProducesNothing() {
        XCTAssertNil(BriefRead.compose(brief: brief(audience: "solo founders"), language: .en))
    }

    func testOneLinerIsEnoughToRender() {
        let out = BriefRead.compose(brief: brief(oneLiner: "A macOS AI coding companion"),
                                    language: .en)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("A macOS AI coding companion"))
    }

    // MARK: - summary wins, and they never both render

    func testSummaryBeatsOneLiner() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "RAW ONE LINER", summary: "ENRICHED READ"),
            language: .en)!
        XCTAssertTrue(out.contains("ENRICHED READ"))
        XCTAssertFalse(out.contains("RAW ONE LINER"), "both anchors rendered")
    }

    // MARK: - MeaningfulText, not a bare ??

    /// A bare `??` would render "Here's what I understood: x".
    func testPlaceholderyAnchorIsTreatedAsAbsent() {
        XCTAssertNil(BriefRead.compose(brief: brief(oneLiner: "x"), language: .en))
        XCTAssertNil(BriefRead.compose(brief: brief(oneLiner: "12345"), language: .en))
        XCTAssertNil(BriefRead.compose(brief: brief(oneLiner: "me@example.com"), language: .en))
    }

    func testPlaceholderyAudienceIsDroppedButTheAnchorSurvives() {
        let out = BriefRead.compose(brief: brief(oneLiner: "A coding companion", audience: "x"),
                                    language: .en)!
        XCTAssertTrue(out.contains("A coding companion"))
        XCTAssertFalse(out.contains("It's for"), "placeholder audience rendered")
    }

    // MARK: - goal is off limits

    /// `brief.goal` is written only by the enrich-interview handler (`CompanyStore:694`) and
    /// the Murror fixture, and `startEnrichInterviewIfNeeded` has no caller in the app. A read
    /// built on it would be blank for every real founder and correct only in the demo.
    func testGoalIsNeverRead() {
        let withGoal = brief(oneLiner: "A coding companion", goal: "Launch in August")
        let without  = brief(oneLiner: "A coding companion")
        XCTAssertEqual(BriefRead.compose(brief: withGoal, language: .en),
                       BriefRead.compose(brief: without, language: .en),
                       "goal leaked into the read")
    }

    // MARK: - Trimmings

    func testAudienceAndStageAreAddedWhenPresent() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "A coding companion", audience: "solo founders",
                         stage: "Prototype"),
            language: .en)!
        XCTAssertTrue(out.contains("solo founders"))
        XCTAssertTrue(out.lowercased().contains("prototype"))
    }

    func testVietnameseIsADifferentSentence() {
        let b = brief(oneLiner: "Một trợ lý lập trình", audience: "nhà sáng lập")
        let vi = BriefRead.compose(brief: b, language: .vi)!
        let en = BriefRead.compose(brief: b, language: .en)!
        XCTAssertNotEqual(vi, en)
        XCTAssertTrue(vi.contains("Một trợ lý lập trình"))
    }

    /// The five stage values are English literals in `CompanyOnboardingModel.stages`, so the
    /// Vietnamese read must translate them rather than splicing an English word mid-sentence.
    func testKnownStagesAreTranslatedForVietnamese() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "Một trợ lý", stage: "Building"), language: .vi)!
        XCTAssertFalse(out.contains("Building"), "English stage label spliced into Vietnamese")
    }

    /// An unknown stage (an older brief, a hand-edited document) must pass through rather
    /// than vanish or crash. Case-insensitively: the English path lowercases the label so it
    /// reads as prose mid-sentence ("you're at the scaling stage"), which is the point — the
    /// assertion is that the word SURVIVES, not that its capitalisation does.
    func testUnknownStageFallsBackToItsRawValue() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "A coding companion", stage: "Scaling"), language: .en)!
        XCTAssertTrue(out.lowercased().contains("scaling"))
    }

    /// The founder's own full stop must not be doubled.
    func testAFounderTypedFullStopIsNotDoubled() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "A coding companion.", stage: nil), language: .en)!
        XCTAssertFalse(out.contains(".."), "doubled the founder's punctuation")
    }
}
