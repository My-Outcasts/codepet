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

    private func store(_ probe: SaveProbe,
                       vcRunner: @escaping (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error>)
    -> CompanyStore {
        CompanyStore(loader: { _ in .empty },
                     saver: { _, brief in probe.briefs.append(brief); return true },
                     chatSender: { _ in
                         try? await Task.sleep(nanoseconds: 30_000_000)
                         return CompanyChatReply(text: "byte's answer", runTaskId: nil)
                     },
                     chatStreamer: Self.failingStreamer,
                     vcRunner: vcRunner)
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

    func testStoreAsksRunwayRightAfterTheRoomDelivers() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en)

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
        await s.sendChat("free with ads or $9.99 once?", language: .en)

        let runwayId = s.chatMessages.last!.id
        await s.answerInterview(messageId: runwayId, gap: .runway, answer: "6 months", language: .en)
        XCTAssertEqual(s.chatMessages.last?.interview, .constraints)

        let constraintsId = s.chatMessages.last!.id
        await s.answerInterview(messageId: constraintsId, gap: .constraints,
                                answer: "No hiring this quarter", language: .en)

        XCTAssertEqual(s.company.brief.runway, "6 months")
        XCTAssertEqual(s.company.brief.constraints, "No hiring this quarter")
        XCTAssertEqual(probe.briefs.last?.constraints, "No hiring this quarter")
        // [me, run, runway Q, me, constraints Q, me] — a 7th companion message here
        // would be byte's first-run greeting.
        XCTAssertEqual(s.chatMessages.count, 6)
        XCTAssertEqual(s.chatMessages.last?.role, .me)
    }

    func testStoreAsksAtMostOnceAcrossTwoRuns() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(briefedRunEvents()))
        await s.hydrate(companyId: "u")
        await s.sendChat("first trade-off", language: .en)
        let runwayId = s.chatMessages.last!.id
        await s.answerInterview(messageId: runwayId, gap: .runway, answer: "6 months", language: .en)
        await s.answerInterview(messageId: s.chatMessages.last!.id, gap: .constraints,
                                answer: "No hiring", language: .en)
        let countAfterFirst = s.chatMessages.count

        await s.sendChat("second trade-off", language: .en)
        XCTAssertNil(s.chatMessages.last?.interview)
        // me + the room's message only.
        XCTAssertEqual(s.chatMessages.count, countAfterFirst + 2)
    }

    /// A failed run must never damage the chat — and must never interrogate the
    /// founder for an answer it did not produce.
    func testAFailedRunAsksNothing() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(
            [.routing(Self.routing("multi_agent")), .error("upstream_failure", nil)]))
        await s.hydrate(companyId: "u")
        await s.sendChat("free with ads or $9.99 once?", language: .en)
        XCTAssertNil(s.chatMessages.last?.interview)
        XCTAssertFalse(s.vcInterviewAsked)
    }

    /// The escape hatch discards the run entirely, so nothing downstream of it —
    /// including this interview — may fire.
    func testAnEscapeHatchRunAsksNothing() async {
        let probe = SaveProbe()
        let s = store(probe, vcRunner: runnerYielding(
            [.routing(Self.routing("single_agent")), .brief(Self.aBrief),
             .done(runId: "r1", unresolved: false, skipped: nil)]))
        await s.hydrate(companyId: "u")
        await s.sendChat("name the 4th tab Insights or Progress?", language: .en)
        XCTAssertNil(s.chatMessages.last?.interview)
        XCTAssertFalse(s.vcInterviewAsked)
    }
}
