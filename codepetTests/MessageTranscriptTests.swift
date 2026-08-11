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

    /// `components(separatedBy:).count - 1` — how many times `needle` appears in `haystack`.
    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
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

    /// Real construction (`CompanyStore.proposeRun`) always sets `text` to the proposal's own
    /// sentence — never blank. The old test built this from `reply("")`, which never happens in
    /// production, and so passed whether or not the sentence was being duplicated.
    func testPlainOnARunProposalWithMatchingTextUsesTheSentenceOnce() {
        let proposal = RunProposal(taskId: "t1", title: "Pricing page",
                                   deptName: "Marketing", companionId: "nova")
        var m = reply(proposal.line(.en))
        m.runProposal = proposal
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertEqual(out, proposal.line(.en))
        XCTAssertEqual(occurrences(of: proposal.line(.en), in: out), 1)
    }

    /// Locks the fallback: a message the store built with no reply to carry the sentence
    /// still has to produce it.
    func testPlainOnARunProposalWithBlankTextFallsBackToTheSentence() {
        var m = reply("")
        m.runProposal = RunProposal(taskId: "t1", title: "Pricing page",
                                    deptName: "Marketing", companionId: "nova")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en),
                       "Let's do \"Pricing page\" in Marketing — ready when you are.")
    }

    /// Real construction (`handleRoadmapProposal`, attaching to a blank/generic reply) sets
    /// `text` to the proposal's own sentence.
    func testPlainOnARoadmapProposalWithMatchingTextUsesTheSentenceOnce() {
        let proposal = RoadmapProposal.complete(taskId: "t1", title: "Ship billing")
        var m = reply(proposal.line(.en))
        m.roadmapProposal = proposal
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertEqual(out, proposal.line(.en))
        XCTAssertEqual(occurrences(of: proposal.line(.en), in: out), 1)
    }

    func testPlainOnARoadmapProposalWithBlankTextFallsBackToTheSentence() {
        var m = reply("")
        m.roadmapProposal = .complete(taskId: "t1", title: "Ship billing")
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en),
                       "Want me to mark \"Ship billing\" done?")
    }

    /// When the model wrote its own prose (`handleRoadmapProposal`'s "existing text" branch),
    /// the on-screen card shows only that prose — the transcript must not inject the generic
    /// sentence on top of it.
    func testPlainOnARoadmapProposalWithDistinctProseKeepsTheProseOnly() {
        let proposal = RoadmapProposal.complete(taskId: "t1", title: "Ship billing")
        var m = reply("Nice work — marking billing as shipped.")
        m.roadmapProposal = proposal
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertTrue(out.contains("Nice work — marking billing as shipped."))
        XCTAssertFalse(out.contains(proposal.line(.en)))
    }

    /// Real construction (`askInterviewGap`) always sets `text` to the question itself.
    func testPlainOnAnInterviewWithMatchingTextUsesTheQuestionOnce() {
        let expected = EnrichInterview.question(for: .goal, language: .en).ask
        var m = reply(expected)
        m.interview = .goal
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertEqual(out, expected)
        XCTAssertEqual(occurrences(of: expected, in: out), 1)
    }

    func testPlainOnAnInterviewWithBlankTextFallsBackToTheQuestion() {
        var m = reply("")
        m.interview = .goal
        let expected = EnrichInterview.question(for: .goal, language: .en).ask
        XCTAssertEqual(MessageTranscript.plain(m, lang: .en), expected)
    }

    /// What a finished run really looks like (`CompanyStore.swift:1399-1402`): blank text,
    /// the exec log carried onto the draft, and the draft itself — all in the same message.
    func testPlainOnAFinishedRunCombinesExecStepsAndDraft() {
        var m = reply("")
        m.execSteps = [ExecStep(label: "Read the brief", done: true),
                       ExecStep(label: "Draft the copy", done: true)]
        m.draft = Deliverable(kind: .plan, title: "Launch plan", body: "Week 1: ship billing.")
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertTrue(out.contains("Launch plan"))
        XCTAssertTrue(out.contains("Week 1: ship billing."))
        XCTAssertTrue(out.contains("✓ Read the brief"))
        XCTAssertTrue(out.contains("✓ Draft the copy"))
    }

    // MARK: - drafts (companion-written messages, Finding 2)

    func testPlainOnADraftedMessageIncludesHeadingAndBody() {
        var m = reply("Here's what I'd send — copy it when you're happy with it.")
        m.drafts = [MessageDraftDTO(channel: "email", to: "founder@x.com",
                                    subject: "Pricing update", body: "Here's the new pricing.")]
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertTrue(out.contains("Pricing update"))
        XCTAssertTrue(out.contains("Here's the new pricing."))
    }

    /// Email drafts that have both a subject and a recipient must carry both — the subject
    /// in the heading and the recipient as its own line, matching where the view renders them
    /// (CopilotChatView:752-758), so nothing is lost to the clipboard.
    func testPlainOnAnEmailDraftIncludesSubjectAndRecipient() {
        var m = reply("Here's the draft.")
        m.drafts = [MessageDraftDTO(channel: "email", to: "founder@x.com",
                                    subject: "Pricing update", body: "Here's the new pricing.")]
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertTrue(out.contains("Pricing update"))
        XCTAssertTrue(out.contains("To: founder@x.com"))
        XCTAssertTrue(out.contains("Here's the new pricing."))
    }

    /// The recipient label must be localised to Vietnamese when requested.
    func testPlainOnAnEmailDraftUsesVietnameseLabelForRecipient() {
        var m = reply("Đây là bản nháp.")
        m.drafts = [MessageDraftDTO(channel: "email", to: "founder@x.com",
                                    subject: "Cập nhật giá", body: "Giá mới là...")]
        let out = MessageTranscript.plain(m, lang: .vi)
        XCTAssertTrue(out.contains("Cập nhật giá"))
        XCTAssertTrue(out.contains("Gửi tới: founder@x.com"))
        XCTAssertTrue(out.contains("Giá mới là..."))
    }

    /// An email draft with a subject but no recipient must not emit a stray "To: " label.
    func testPlainOnAnEmailDraftWithoutRecipientSkipsTheLabel() {
        var m = reply("Draft without a recipient.")
        m.drafts = [MessageDraftDTO(channel: "email", to: nil,
                                    subject: "Subject only", body: "Body text.")]
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertTrue(out.contains("Subject only"))
        XCTAssertTrue(out.contains("Body text."))
        XCTAssertFalse(out.contains("To: "))
    }

    /// A draft with neither a subject nor a recipient has an empty `heading` — the transcript
    /// must skip it rather than emit a blank block, matching the card's own behaviour.
    func testPlainOnADraftedMessageWithEmptyHeadingSkipsIt() {
        var m = reply("")
        m.drafts = [MessageDraftDTO(channel: "text", to: nil, subject: nil,
                                    body: "See you at 3.")]
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertEqual(out, "See you at 3.")
    }

    func testPlainOnMultipleDraftedMessagesIncludesBoth() {
        var m = reply("Two versions, pick one.")
        m.drafts = [
            MessageDraftDTO(channel: "email", to: "a@x.com", subject: "Follow-up",
                            body: "First draft body."),
            MessageDraftDTO(channel: "text", to: "b@x.com", subject: nil,
                            body: "Second draft body.")
        ]
        let out = MessageTranscript.plain(m, lang: .en)
        XCTAssertTrue(out.contains("Follow-up"))
        XCTAssertTrue(out.contains("First draft body."))
        XCTAssertTrue(out.contains("b@x.com"))
        XCTAssertTrue(out.contains("Second draft body."))
    }

    func testMarkdownOnADraftedMessageHeadsItWithH3() {
        var m = reply("Here's what I'd send — copy it when you're happy with it.")
        m.drafts = [MessageDraftDTO(channel: "email", to: "founder@x.com",
                                    subject: "Pricing update", body: "Here's the new pricing.")]
        let out = MessageTranscript.markdown(m, speaker: "Codepet", lang: .en)
        XCTAssertTrue(out.contains("### Pricing update"))
        XCTAssertTrue(out.contains("Here's the new pricing."))
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
