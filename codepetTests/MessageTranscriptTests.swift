// codepetTests/MessageTranscriptTests.swift
import XCTest
@testable import codepet

/// Struct-only tests for the pure `MessageTranscript` serializer — no `CompanyStore`,
/// no `@MainActor`, no Firebase. The blank-text draft case is the bug this type exists
/// to prevent: `message.text` is empty on a draft-card reply, so copying it handed the
/// founder an empty clipboard.
final class MessageTranscriptTests: XCTestCase {

    private func reply(_ text: String) -> CopilotMessage {
        CopilotMessage(role: .companion, text: text)
    }

    // MARK: - plain

    func testPlainReturnsProseForAnOrdinaryReply() {
        let m = reply("Here is the pricing page copy.")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en), "Here is the pricing page copy.")
    }

    func testPlainTrimsSurroundingWhitespace() {
        let m = reply("  Ready when you are.\n\n")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en), "Ready when you are.")
    }

    /// The bug. A draft-card reply carries a blank `text`, so the old copy path
    /// produced "". The title and body must both survive.
    func testPlainOnADraftWithBlankTextIsNotEmpty() {
        var m = reply("")
        m.draft = Deliverable(kind: .plan, title: "Launch plan", body: "Week 1: ship billing.")
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertFalse(out.isEmpty)
        XCTAssertTrue(out.contains("Launch plan"))
        XCTAssertTrue(out.contains("Week 1: ship billing."))
    }

    func testPlainOnADraftKeepsProseAboveTheDraft() {
        var m = reply("I drafted this for you.")
        m.draft = Deliverable(kind: .plan, title: "Launch plan", body: "Week 1: ship billing.")
        let out = MessageTranscript.plain(m, lang: .en)
        let prose = out.range(of: "I drafted this for you.")
        let title = out.range(of: "Launch plan")
        XCTAssertNotNil(prose)
        XCTAssertNotNil(title)
        XCTAssertTrue(prose!.lowerBound < title!.lowerBound, "prose must come before the draft")
    }

    func testPlainOnARoomKeepsTheHandoffLineThenTheRecommendation() {
        var m = reply("This one needs the whole room.")
        var run = VirtualCompanyRunState()
        run.brief = VCBrief(recommendation: "Charge for the beta.",
                            confidence: 70, confidenceReason: "r",
                            theRealDisagreement: "d", tradeoffFounderMustOwn: "t",
                            killCriteria: [], nextAction: VCNextAction(action: "a", owner: "o"),
                            whatWeDontKnow: "u", unresolved: false)
        m.vcRun = run
        let out = MessageTranscript.plain(m, lang: .en)
        let handoff = out.range(of: "This one needs the whole room.")
        let rec = out.range(of: "Charge for the beta.")
        XCTAssertNotNil(handoff)
        XCTAssertNotNil(rec)
        XCTAssertTrue(handoff!.lowerBound < rec!.lowerBound)
    }

    func testPlainOnExecStepsListsThemWithDoneMarkers() {
        var m = reply("")
        m.execSteps = [ExecStep(label: "Read the brief", done: true),
                       ExecStep(label: "Draft the copy", done: false)]
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertTrue(out.contains("✓ Read the brief"))
        XCTAssertTrue(out.contains("• Draft the copy"))
    }

    func testPlainOnARunProposalUsesTheProposalSentence() {
        var m = reply("")
        m.runProposal = RunProposal(taskId: "t1", title: "Pricing page",
                                    deptName: "Marketing", companionId: "nova")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en),
                       "Let's do \"Pricing page\" in Marketing — ready when you are.")
    }

    func testPlainOnARoadmapProposalUsesTheProposalSentence() {
        var m = reply("")
        m.roadmapProposal = .complete(taskId: "t1", title: "Ship billing")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en),
                       "Want me to mark \"Ship billing\" done?")
    }

    func testPlainOnAnInterviewUsesTheQuestion() {
        var m = reply("")
        m.interview = .goal
        let expected = EnrichInterview.question(for: .goal, language: .en).ask
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en), expected)
    }

    func testPlainHonoursVietnamese() {
        var m = reply("")
        m.roadmapProposal = .complete(taskId: "t1", title: "Ship billing")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .vi),
                       "Mình đánh dấu \"Ship billing\" là xong nhé?")
    }

    // MARK: - markdown

    func testMarkdownLeadsWithTheSpeaker() {
        let m = reply("Here is the copy.")
        let out = MessageTranscript.markdown(m, speaker: "Glitch · Engineering", lang: .en)
        XCTAssertTrue(out.hasPrefix("**Glitch · Engineering**"))
        XCTAssertTrue(out.contains("Here is the copy."))
    }

    func testMarkdownHeadsADraftWithItsTitle() {
        var m = reply("")
        m.draft = Deliverable(kind: .plan, title: "Launch plan", body: "Week 1: ship billing.")
        let out = MessageTranscript.markdown(m, speaker: "Codepet", lang: .en)
        XCTAssertTrue(out.contains("## Launch plan"))
        XCTAssertTrue(out.contains("Week 1: ship billing."))
    }

    func testMarkdownRendersExecStepsAsATaskList() {
        var m = reply("")
        m.execSteps = [ExecStep(label: "Read the brief", done: true),
                       ExecStep(label: "Draft the copy", done: false)]
        let out = MessageTranscript.markdown(m, speaker: "Codepet", lang: .en)
        XCTAssertTrue(out.contains("- [x] Read the brief"))
        XCTAssertTrue(out.contains("- [ ] Draft the copy"))
    }

    func testMarkdownOnARoomListsEachSeatsPosition() {
        var m = reply("")
        var run = VirtualCompanyRunState()
        run.brief = VCBrief(recommendation: "Charge for the beta.",
                            confidence: 70, confidenceReason: "r",
                            theRealDisagreement: "d", tradeoffFounderMustOwn: "t",
                            killCriteria: [], nextAction: VCNextAction(action: "a", owner: "o"),
                            whatWeDontKnow: "u", unresolved: false)
        run.agents = [VCAgentMeta(agentId: "a1", departmentKey: "finance")]
        run.positions = ["a1": VCPosition(stance: "proceed", position: "Price it at $20.",
                                          reasoning: "r", evidenceNeeded: [], risksIOwn: [],
                                          confidence: 60, costToMyDept: "c", hardBlocker: nil)]
        m.vcRun = run
        let out = MessageTranscript.markdown(m, speaker: "Codepet", lang: .en)
        XCTAssertTrue(out.contains("Charge for the beta."))
        XCTAssertTrue(out.contains("**finance** — Price it at $20."))
    }

    func testMarkdownOnAnEmptyMessageIsJustTheSpeaker() {
        let out = MessageTranscript.markdown(reply(""), speaker: "Codepet", lang: .en)
        XCTAssertEqual(out, "**Codepet**")
    }
}
