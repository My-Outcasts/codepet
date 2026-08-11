// codepetTests/VirtualCompanyInterviewTests.swift
import XCTest
@testable import codepet

/// The gate itself is pure, so most of this suite needs no store. The last section
/// drives the trigger through `CompanyStore`'s injected seams (same harness as
/// `CompanyStoreVirtualCompanyTests`), because "asked at most once, and never after
/// a run that produced nothing" is a store behaviour, not a pure one.
@MainActor
final class VirtualCompanyInterviewTests: XCTestCase {

    private func finishedRun() -> VirtualCompanyRunState {
        var s = VirtualCompanyRunState()
        let json: [String: Any] = ["decision": "multi_agent", "agents": ["product", "finance"],
                                   "real_question": "q", "request_type": "DECISION"]
        s.apply(.routing(try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))))
        s.apply(.brief(VCBrief(recommendation: "r", confidence: 3, confidenceReason: "c",
                               theRealDisagreement: "d", tradeoffFounderMustOwn: "t", killCriteria: ["k"],
                               nextAction: VCNextAction(action: "a", owner: "Founder"),
                               whatWeDontKnow: "u", unresolved: false)))
        s.apply(.done(runId: "r1", unresolved: false, skipped: nil))
        return s
    }

    func testAsksOnceAfterTheFirstBriefWithNoConstraints() {
        XCTAssertTrue(VirtualCompanyInterview.shouldAsk(
            state: finishedRun(), brief: CompanyBrief(), alreadyAsked: false))
    }

    func testNeverAsksTwice() {
        XCTAssertFalse(VirtualCompanyInterview.shouldAsk(
            state: finishedRun(), brief: CompanyBrief(), alreadyAsked: true))
    }

    func testDoesNotAskWhenConstraintsAreAlreadyOnRecord() {
        var brief = CompanyBrief()
        brief.constraints = "Không thuê người quý này."
        XCTAssertFalse(VirtualCompanyInterview.shouldAsk(
            state: finishedRun(), brief: brief, alreadyAsked: false))
    }

    func testDoesNotAskUntilABriefActuallyArrived() {
        // Asking after a failed or escape-hatch run would interrogate the founder
        // for nothing.
        var s = VirtualCompanyRunState()
        s.apply(.error("upstream_failure", nil))
        XCTAssertFalse(VirtualCompanyInterview.shouldAsk(
            state: s, brief: CompanyBrief(), alreadyAsked: false))
    }

    func testAsksRunwayThenConstraints() {
        XCTAssertEqual(VirtualCompanyInterview.gaps, [.runway, .constraints])
    }

    func testBothNewGapsHaveCopyInBothLanguages() {
        for gap in VirtualCompanyInterview.gaps {
            for lang in [AppLanguage.vi, AppLanguage.en] {
                let q = EnrichInterview.question(for: gap, language: lang)
                XCTAssertFalse(q.ask.isEmpty, "\(gap) has no ask in \(lang)")
                XCTAssertFalse(q.why.isEmpty, "\(gap) has no why in \(lang)")
            }
        }
    }

    func testOnboardingInterviewIsUnchanged() {
        // The first-run interview filters gapOrder, so the two new cases must not
        // appear there — onboarding is owned by someone else.
        XCTAssertEqual(EnrichInterview.gapOrder, [.goal, .traction, .problem])
        XCTAssertFalse(EnrichInterview.detectGaps(nil).contains(.runway))
        XCTAssertFalse(EnrichInterview.detectGaps(nil).contains(.constraints))
    }

    /// The store's seam is `(companyId) -> Bool`, so the injected stub cannot see the
    /// key at all — which means a device-global key would slip past every store test
    /// below. This is the only place that catches it.
    func testTheFlagKeyIsPerCompanyAndProjectPrefixed() {
        XCTAssertNotEqual(VirtualCompanyInterviewFlag.key("founderA"),
                          VirtualCompanyInterviewFlag.key("founderB"),
                          "a device-global key would never ask a second founder")
        XCTAssertTrue(VirtualCompanyInterviewFlag.key("u").hasPrefix("cp_"),
                      "account-scoped keys must be cp_-prefixed so AccountDataStore vaults them")
        XCTAssertTrue(VirtualCompanyInterviewFlag.key("u").contains("u"))
    }

    // MARK: - The trigger, through the store

    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private static func routing(_ decision: String) -> VCRouting {
        let json: [String: Any] = ["decision": decision, "agents": ["product", "finance"],
                                   "real_question": "q", "request_type": "DECISION"]
        return try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))
    }

    private static let aBrief = VCBrief(
        recommendation: "r", confidence: 3, confidenceReason: "c", theRealDisagreement: "d",
        tradeoffFounderMustOwn: "t", killCriteria: ["k"],
        nextAction: VCNextAction(action: "a", owner: "Founder"),
        whatWeDontKnow: "u", unresolved: false)

    /// Records every brief the store persisted, so "the answers are durable" is a
    /// claim about the saver and not just about the in-memory struct.
    private final class SaveProbe { var briefs: [CompanyBrief] = [] }

    /// Stands in for `UserDefaults` so no case touches the real defaults domain — and,
    /// more importantly, so asked-ness cannot leak between cases (they all use cid "u").
    /// Shared deliberately across two stores in the relaunch/switch tests: that shared
    /// box IS the disk.
    private final class FlagDisk {
        var asked: Set<String> = []
        var flag: VirtualCompanyInterviewFlag {
            VirtualCompanyInterviewFlag(wasAsked: { [self] in asked.contains($0) },
                                        markAsked: { [self] in asked.insert($0) })
        }
    }

    private func store(_ probe: SaveProbe,
                       disk: FlagDisk = FlagDisk(),
                       loader: @escaping (String) async -> CompanyState = { _ in .empty },
                       vcRunner: @escaping (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error>)
    -> CompanyStore {
        CompanyStore(loader: loader,
                     saver: { _, brief in probe.briefs.append(brief); return true },
                     chatSender: { _ in
                         try? await Task.sleep(nanoseconds: 30_000_000)
                         return CompanyChatReply(text: "byte's answer", runTaskId: nil)
                     },
                     chatStreamer: Self.failingStreamer,
                     vcRunner: vcRunner,
                     vcInterviewFlag: disk.flag)
    }

    private func runnerYielding(_ events: [VirtualCompanyEvent])
    -> (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        { _ in
            AsyncThrowingStream { cont in
                for e in events { cont.yield(e) }
                cont.finish()
            }
        }
    }

    private func briefedRunEvents() -> [VirtualCompanyEvent] {
        [.runStarted(runId: "r1"), .routing(Self.routing("multi_agent")),
         .brief(Self.aBrief), .done(runId: "r1", unresolved: false, skipped: nil)]
    }

    /// The Aug 7 rule itself, pinned — because its absence is what made this whole suite red.
    ///
    /// `b42bc10` gated convening behind Plan mode: every typed message used to fan out to
    /// `virtualCompanyRun`, and a convened decision costs ~$0.20 against ~$0.005 for an ordinary
    /// turn, so a casual Ask could cost forty times what it looked like. Every test here was
    /// written before that and called `sendChat` without `convenesRoom`, so no room convened, no
    /// brief arrived, and eight tests failed for asserting a rule the product had deliberately
    /// changed. They were skipped in CI for a day on the strength of that.
    ///
    /// This test is the one that would have said so out loud: it asserts the DEFAULT is not to
    /// convene. If the gate is ever removed, this goes red and names the cost.
    func testAskDoesNotConveneTheRoomAtAll() async {
        let probe = SaveProbe()
        var runnerCalled = false
        let s = store(probe, vcRunner: { req in
            runnerCalled = true
            return self.runnerYielding(self.briefedRunEvents())(req)
        })
        await s.hydrate(companyId: "u")
        // No `convenesRoom:` — exactly how Ask mode calls it.
        await s.sendChat("free with ads or $9.99 once?", language: .en)
        XCTAssertFalse(runnerCalled, "an Ask turn must not convene the room \u{2014} that is the Aug 7 cost gate")
        XCTAssertNil(s.chatMessages.last?.interview, "and with no brief there is nothing to interview about")
        XCTAssertFalse(s.vcInterviewAsked)
    }

    func testStoreAsksRunwayRightAfterTheRoomDelivers() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en, convenesRoom: true)

        XCTAssertEqual(s.chatMessages.last?.interview, .runway)
        XCTAssertEqual(s.chatMessages.last?.text,
                       EnrichInterview.question(for: .runway, language: .en).ask)
        XCTAssertTrue(s.vcInterviewAsked)
    }

    /// The trap this wiring exists to avoid: the queue emptying must NOT welcome the
    /// founder like a new user mid-session.
    func testAnsweringBothQuestionsSavesThemAndSeedsNoGreeting() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en, convenesRoom: true)

        let runwayId = s.chatMessages.last!.id
        await s.answerInterview(messageId: runwayId, gap: .runway, answer: "6 months", language: .en)
        XCTAssertEqual(s.chatMessages.last?.interview, .constraints)

        let constraintsId = s.chatMessages.last!.id
        await s.answerInterview(messageId: constraintsId, gap: .constraints,
                                answer: "No hiring this quarter", language: .en)

        XCTAssertEqual(s.company.brief.runway, "6 months")
        XCTAssertEqual(s.company.brief.constraints, "No hiring this quarter")
        XCTAssertEqual(probe.briefs.last?.constraints, "No hiring this quarter")
        // Asserted by identity, not by role or by a message count: both moved under
        // this test once the room started appending its own message, and again once
        // the interview earned a closing line. What must stay true is narrower than
        // "no companion message follows" — it is that THIS particular message, the
        // first-run welcome, is not among them.
        let greeting = FirstRunGreetingBuilder.build(brief: s.company.brief,
                                                     nextStep: RoadmapEngine.nextStep(s.company.tasks),
                                                     language: .en)
        XCTAssertFalse(s.chatMessages.contains { $0.text == greeting.text },
                       "the queue emptying must not welcome the founder like a new user")
    }

    func testTheInterviewClosesByQuotingTheAnswersBackAndNamingTheirEffect() async {
        // The founder answered two questions and the conversation simply stopped —
        // nothing said, nothing visibly changed. Neither answer appears anywhere in
        // the UI, so this closing line is the only evidence they landed.
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en, convenesRoom: true)

        await s.answerInterview(messageId: s.chatMessages.last!.id, gap: .runway,
                                answer: "6 months", language: .en)
        await s.answerInterview(messageId: s.chatMessages.last!.id, gap: .constraints,
                                answer: "No hiring this quarter", language: .en)

        let close = try? XCTUnwrap(s.chatMessages.last)
        XCTAssertEqual(close?.role, .companion)
        // Quotes both answers back, so the founder sees the specifics were heard.
        XCTAssertTrue(close?.text.contains("6 months") == true)
        XCTAssertTrue(close?.text.contains("No hiring this quarter") == true)
        // And names what they change — runway is what makes a three-week proposal
        // unacceptable, and a founder has no way to infer that.
        XCTAssertTrue(close?.text.contains("recommend") == true,
                      "the close must say what the answers change, not just thank them")
    }

    func testSkippingBothQuestionsSaysSoRatherThanClaimingAnEffect() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en, convenesRoom: true)

        await s.answerInterview(messageId: s.chatMessages.last!.id, gap: .runway,
                                answer: nil, language: .en)
        await s.answerInterview(messageId: s.chatMessages.last!.id, gap: .constraints,
                                answer: nil, language: .en)

        let close = s.chatMessages.last
        XCTAssertEqual(close?.role, .companion)
        XCTAssertTrue(close?.text.contains("more general") == true,
                      "a skipped interview must not claim an effect it did not get")
        XCTAssertNil(s.company.brief.runway)
        XCTAssertNil(s.company.brief.constraints)
    }

    func testStoreAsksAtMostOnceAcrossTwoRuns() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("first trade-off", language: .en, convenesRoom: true)
        let runwayId = s.chatMessages.last!.id
        await s.answerInterview(messageId: runwayId, gap: .runway, answer: "6 months", language: .en)
        await s.answerInterview(messageId: s.chatMessages.last!.id, gap: .constraints,
                                answer: "No hiring", language: .en)
        let countAfterFirst = s.chatMessages.count

        await s.sendChat("second trade-off", language: .en, convenesRoom: true)
        XCTAssertNil(s.chatMessages.last?.interview)
        XCTAssertNotNil(s.chatMessages.last?.vcRun, "the second run still convenes")
        // me + byte's own answer + the room's message. No third question.
        XCTAssertEqual(s.chatMessages.count, countAfterFirst + 3)
    }

    /// A failed run must never damage the chat — and must never interrogate the
    /// founder for an answer it did not produce.
    func testAFailedRunAsksNothing() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(
            [.routing(Self.routing("multi_agent")), .error("upstream_failure", nil)]))
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en, convenesRoom: true)
        XCTAssertNil(s.chatMessages.last?.interview)
        XCTAssertFalse(s.vcInterviewAsked)
    }

    // MARK: - Asked-ness is remembered per founder, not per session or per device

    /// Skip is a no-write path and its semantics belong to the onboarding interview,
    /// so nothing lands in the brief. A session-only flag would therefore re-ask on
    /// the first brief of every launch, forever.
    func testTheAskSurvivesARelaunchEvenWhenTheFounderSkippedBoth() async {
        let disk = FlagDisk()
        let probe = SaveProbe()
        let first = store(probe, disk: disk, vcRunner: runnerYielding(briefedRunEvents()))
        await first.hydrate(companyId: "u")
        await first.sendChat("first trade-off", language: .en, convenesRoom: true)
        // Skip both: nil answer → no brief write, so `constraints` stays nil and only
        // the persisted flag can stop the re-ask.
        await first.answerInterview(messageId: first.chatMessages.last!.id, gap: .runway,
                                    answer: nil, language: .en)
        await first.answerInterview(messageId: first.chatMessages.last!.id, gap: .constraints,
                                   answer: nil, language: .en)
        XCTAssertNil(first.company.brief.constraints, "skip must stay a no-write path")
        XCTAssertEqual(disk.asked, ["u"])

        // A fresh store over the same disk is the relaunch.
        let relaunched = store(SaveProbe(), disk: disk, vcRunner: runnerYielding(briefedRunEvents()))
        await relaunched.hydrate(companyId: "u")
        XCTAssertTrue(relaunched.vcInterviewAsked, "hydrate must re-derive it from this company's flag")
        await relaunched.sendChat("second trade-off", language: .en, convenesRoom: true)
        XCTAssertNil(relaunched.chatMessages.last?.interview)
    }

    /// The cross-account bug: `reset()` used to leave the flag true, so founder B —
    /// empty brief, nothing on record — was never asked at all.
    func testAnotherFounderIsStillAskedAfterASignOut() async {
        let disk = FlagDisk()
        let s = store(SaveProbe(), disk: disk, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("first trade-off", language: .en, convenesRoom: true)
        XCTAssertEqual(s.chatMessages.last?.interview, .runway)

        s.reset()
        XCTAssertFalse(s.vcInterviewAsked, "reset() must not carry one founder's asked-ness over")

        await s.hydrate(companyId: "v")
        await s.sendChat("B's first trade-off", language: .en, convenesRoom: true)
        XCTAssertEqual(s.chatMessages.last?.interview, .runway, "founder B was never asked")
        XCTAssertEqual(disk.asked, ["u", "v"], "each founder gets their own key")
    }

    /// A founder who already has constraints on record is not asked, and the flag is
    /// not spent on them either — `shouldAsk`'s brief check is the first line of defence
    /// and the persisted flag is the second, independent one.
    func testAFounderWithConstraintsOnRecordIsNeverAskedAndSpendsNoFlag() async {
        let disk = FlagDisk()
        var brief = CompanyBrief()
        brief.constraints = "Không thuê người quý này."
        let seeded = CompanyState(brief: brief, departments: [], library: [], stage: .idea,
                                 companionId: "byte", onboardedAt: Date(), tasks: [])
        let s = store(SaveProbe(), disk: disk, loader: { _ in seeded },
                      vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("a trade-off", language: .en, convenesRoom: true)
        XCTAssertNil(s.chatMessages.last?.interview)
        XCTAssertTrue(disk.asked.isEmpty)
    }

    // MARK: - The guard that protects the other engineer's flow

    /// The ONLY thing standing between a briefed run and byte's first-run greeting.
    /// Without `guard interviewState == nil`, a run landing while the first-run
    /// interview is mid-queue would overwrite that queue — losing its remaining gaps
    /// and flipping its tail to `seedGreetingWhenDone: false`, so the founder would
    /// silently never be greeted. The composer is gated only on chat being busy, never
    /// on a pending interview, so this ordering is reachable.
    func testABriefedRunNeverJumpsAPendingFirstRunInterview() async {
        let disk = FlagDisk()
        let s = store(SaveProbe(), disk: disk, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.startEnrichInterviewIfNeeded(language: .en))
        XCTAssertEqual(s.chatMessages.last?.interview, .goal)

        await s.sendChat("free with ads or $9.99 once?", language: .en, convenesRoom: true)

        // The run really happened — otherwise this test would pass against a fan-out
        // that never ran.
        XCTAssertNotNil(s.chatMessages.first(where: { $0.vcRun?.brief != nil }),
                        "the room never delivered a brief, so nothing was guarded")
        XCTAssertFalse(s.chatMessages.contains { $0.interview == .runway },
                       "the VC interview jumped a pending first-run interview")
        XCTAssertEqual(s.chatMessages.last(where: { $0.interview != nil })?.interview, .goal,
                       "the first-run queue must still be waiting on its own question")
        XCTAssertFalse(s.vcInterviewAsked, "merely deferred — it may still ask on a later run")
        XCTAssertTrue(disk.asked.isEmpty, "and it must not have spent the founder's flag")

        // And the first-run queue still drains into byte's greeting.
        for gap in [InterviewGap.goal, .traction, .problem] {
            guard let pending = s.chatMessages.last(where: {
                $0.interview == gap && !$0.interviewAnswered
            }) else { return XCTFail("first-run interview lost its \(gap) question") }
            await s.answerInterview(messageId: pending.id, gap: gap, answer: "a", language: .en)
        }
        let greeting = FirstRunGreetingBuilder.build(
            brief: s.company.brief, nextStep: RoadmapEngine.nextStep(s.company.tasks), language: .en)
        XCTAssertFalse(greeting.text.isEmpty)
        XCTAssertEqual(s.chatMessages.last?.text, greeting.text,
                       "byte's first-run greeting was lost")
    }

    /// The escape hatch discards the run entirely, so nothing downstream of it —
    /// including this interview — may fire.
    func testAnEscapeHatchRunAsksNothing() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(
            [.routing(Self.routing("single_agent")), .brief(Self.aBrief),
             .done(runId: "r1", unresolved: false, skipped: nil)]))
        await s.hydrate(companyId: "u")
        await s.sendChat("name the 4th tab Insights or Progress?", language: .en, convenesRoom: true)
        XCTAssertNil(s.chatMessages.last?.interview)
        XCTAssertFalse(s.vcInterviewAsked)
    }
}
