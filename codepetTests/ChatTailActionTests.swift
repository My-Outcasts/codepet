import XCTest
@testable import codepet

/// What a chat turn owes its placeholder once the companion stream is over.
///
/// The three "the room took this turn" cases this suite used to carry are gone with
/// the `roomTookOver` input itself: the room is an appended message now, so it can no
/// longer overwrite byte's bubble and the tail has nothing to defend against.
final class ChatTailActionTests: XCTestCase {

    func testAGoodStreamIsLeftUntouched() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "A full reply.", action: nil), .none)
    }

    func testFallsBackWhenTheStreamThrew() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: true, receivedDone: false,
                                             streamedText: "", action: nil), .fallback)
    }

    func testFallsBackWhenNoDoneFrameArrived() {
        // The pre-deploy shape: a plain-JSON body parses to zero SSE frames, so text
        // can even be present without a `done`.
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: false,
                                             streamedText: "partial", action: nil), .fallback)
    }

    func testWritesTheLeadInForARunTaskOnlyReply() {
        let run = ChatDoneAction(runTaskId: "t1")
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", action: run), .leadIn(.run))
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "  \n ", action: run), .leadIn(.run))
    }

    /// A textless reply whose only action is a nav chip is NOT work starting, and must not
    /// borrow the run's line. This is the exact pair seen in the app on Aug 5: "On it —
    /// putting that together now." above a "Go to Company" chip, nothing being made.
    func testANavOnlyReplyDoesNotPromiseWork() {
        let nav = ChatDoneAction(runTaskId: nil, nav: NavAction(destination: "company", target: nil))
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", action: nav), .leadIn(.nav))
    }

    func testASetupOnlyReplyOffersTheSwitch() {
        let setup = ChatDoneAction(runTaskId: nil, setup: SetupAction(category: "connectors", name: "GitHub"))
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", action: setup), .leadIn(.setup))
    }

    /// `remember` is orthogonal to the other three — it decides the line only when it
    /// arrived alone, and never overrides a run it rode along with.
    func testRememberDecidesTheLineOnlyWhenItArrivesAlone() {
        let notedOnly = ChatDoneAction(runTaskId: nil,
                                       remember: [RememberedFact(topic: "beta", statement: "31 freelancers invited")])
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", action: notedOnly), .leadIn(.noted))
        let withRun = ChatDoneAction(runTaskId: "t1",
                                     remember: [RememberedFact(topic: "beta", statement: "31 freelancers invited")])
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", action: withRun), .leadIn(.run))
    }

    /// A well-formed reply that said nothing and offered nothing is not an answer — it is a
    /// turn that produced nothing, so it earns a RETRY rather than an admission. Measured in
    /// the app on Aug 5: `frame done — 63 bytes`, zero deltas, `chars=0`, while the Virtual
    /// Company room for the same turn came back complete. Printing the dead end was the old
    /// behaviour; this asserts the recovery.
    func testAWordlessActionlessReplyRetriesInsteadOfGivingUp() {
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", action: ChatDoneAction(runTaskId: nil)),
                       .fallback)
        XCTAssertEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                             streamedText: "", action: nil), .fallback)
    }

    /// The retry must NOT extend to a wordless reply that DID something. That is the duplicate
    /// -run bug this file was written to prevent: falling back after a valid `run_task` was
    /// dispatched ran the task twice and appended two drafts.
    func testAWordlessReplyThatActedIsNeverRetried() {
        for action in [ChatDoneAction(runTaskId: "t1"),
                       ChatDoneAction(nav: NavAction(destination: "tasks", target: nil)),
                       ChatDoneAction(setup: SetupAction(category: "connectors", name: "GitHub")),
                       ChatDoneAction(remember: [RememberedFact(topic: "beta", statement: "31 invited")])] {
            XCTAssertNotEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                                    streamedText: "", action: action), .fallback)
        }
    }

    func testDoneWithTextNeverFallsBack() {
        // Guards the duplicate-run bug: falling back on empty text would fire a
        // second chatSender and run the same task twice.
        XCTAssertNotEqual(ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                                streamedText: "text", action: nil), .fallback)
    }
}

/// A turn that is ONLY a roadmap verb is a real turn, not an empty one.
///
/// Measured in the app on Aug 10, the first time the founder used `complete_task`:
/// `response 200`, `frame done — 118 bytes`, `threw=false done=true chars=0`, `tail=fallback`,
/// and she was shown "I can't reach my brain right now" over a completely healthy backend. The
/// model had replied with no prose and only the tool call — a perfectly good turn — and
/// `isEmpty`, checking four fields it knew about, called it nothing.
final class ChatTailActionRoadmapVerbTests: XCTestCase {

    private func decide(_ action: ChatDoneAction) -> ChatTailAction {
        ChatTailAction.decide(streamThrew: false, receivedDone: true, streamedText: "", action: action)
    }

    /// The exact shape that broke: no text, only a completion.
    func testATextFreeCompleteTaskIsNotAFallback() {
        XCTAssertEqual(decide(ChatDoneAction(completeTaskId: "t1")), .leadIn(.roadmap))
    }

    func testATextFreeAddTaskIsNotAFallback() {
        let add = AddTaskDTO(title: "Call the bakeries", detail: nil, dept: nil, owner: "founder")
        XCTAssertEqual(decide(ChatDoneAction(addTask: add)), .leadIn(.roadmap))
    }

    /// A genuinely empty turn must STILL fall back — the guard this file exists for.
    func testATrulyEmptyTurnStillFallsBack() {
        XCTAssertEqual(decide(ChatDoneAction()), .fallback)
    }

    /// Precedence: producing a deliverable outranks offering a roadmap change, because the run is
    /// the thing that takes time and the founder needs to know it started.
    func testARunStillWinsTheLeadIn() {
        XCTAssertEqual(decide(ChatDoneAction(runTaskId: "t1", completeTaskId: "t2")), .leadIn(.run))
    }

    /// `remember` rides along with anything, so a completion that also recorded a fact still reads
    /// as a roadmap turn rather than a bare "Noted."
    func testARoadmapVerbOutranksARememberThatRodeAlong() {
        let fact = RememberedFact(topic: "traction", statement: "9 bakeries in beta")
        XCTAssertEqual(decide(ChatDoneAction(remember: [fact], completeTaskId: "t1")),
                       .leadIn(.roadmap))
    }

    /// Text present → no lead-in is needed at all; the reply speaks for itself.
    func testATurnWithProseNeedsNoLeadIn() {
        XCTAssertEqual(
            ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                  streamedText: "Marking that off now.",
                                  action: ChatDoneAction(completeTaskId: "t1")),
            .none)
    }
}

/// A turn that is ONLY drafted messages is a real turn — the loudest possible version of the
/// `isEmpty` bug above.
///
/// `draft_message` (Aug 10) exists so the companion STOPS typing messages into its reply and
/// emits them instead. A turn carrying nothing but drafts is therefore the tool working exactly
/// as designed — and had `isEmpty` not learned about it, the fix for "messages look like prose"
/// would have shipped as "I can't reach my brain right now". That is the fourth time in a week
/// an action was added without updating everything that reasons about actions, so this suite
/// asserts the whole list rather than only the new field.
final class ChatTailActionDraftedMessageTests: XCTestCase {

    private func decide(_ action: ChatDoneAction) -> ChatTailAction {
        ChatTailAction.decide(streamThrew: false, receivedDone: true, streamedText: "", action: action)
    }

    private func draft(_ body: String = "Hey [name] — worth fifteen minutes?") -> MessageDraftDTO {
        MessageDraftDTO(channel: "dm", to: "the two who asked", subject: nil, body: body)
    }

    /// The shape the feature produces on a good day: no prose, one card.
    func testATextFreeDraftIsNotAFallback() {
        XCTAssertEqual(decide(ChatDoneAction(drafts: [draft()])), .leadIn(.drafted))
    }

    /// The founder's reported turn carried TWO drafts.
    func testSeveralDraftsInOneTurnAreOneTurn() {
        XCTAssertEqual(decide(ChatDoneAction(drafts: [draft(), draft("Quick heads up — [date].")])),
                       .leadIn(.drafted))
    }

    /// The lead-in must not promise work. Nothing is being produced and nothing is being sent —
    /// the founder copies the card. `.run`'s "putting that together now" would be a lie here.
    func testTheLeadInDoesNotPromiseWork() {
        guard case .leadIn(let kind) = decide(ChatDoneAction(drafts: [draft()])) else {
            return XCTFail("expected a lead-in")
        }
        XCTAssertNotEqual(kind, .run)
        XCTAssertNotEqual(kind, .nothing)
    }

    /// A roadmap change needs a button pressed; a draft needs nothing. So when both arrive,
    /// the line names the one with a pending decision — the cards still render underneath.
    func testAPendingConfirmationOutranksADraft() {
        XCTAssertEqual(decide(ChatDoneAction(completeTaskId: "t1", drafts: [draft()])),
                       .leadIn(.roadmap))
    }

    /// A run outranks it for the same reason it outranks everything: it takes time and the
    /// founder needs to know it started.
    func testARunStillWinsOverADraft() {
        XCTAssertEqual(decide(ChatDoneAction(runTaskId: "t1", drafts: [draft()])), .leadIn(.run))
    }

    /// `remember` only ever decides the line when it arrives alone.
    func testADraftOutranksARememberThatRodeAlong() {
        let fact = RememberedFact(topic: "pricing", statement: "$39/month")
        XCTAssertEqual(decide(ChatDoneAction(remember: [fact], drafts: [draft()])),
                       .leadIn(.drafted))
    }

    /// An empty drafts array is not a draft — it must not rescue a turn that produced nothing.
    func testAnEmptyDraftsArrayStillFallsBack() {
        XCTAssertEqual(decide(ChatDoneAction(drafts: [])), .fallback)
    }

    /// With prose, the framing the companion wrote IS the reply and no lead-in is needed.
    func testProseWithDraftsNeedsNoLeadIn() {
        XCTAssertEqual(
            ChatTailAction.decide(streamThrew: false, receivedDone: true,
                                  streamedText: "Here's two versions — one for each group.",
                                  action: ChatDoneAction(drafts: [draft()])),
            .none)
    }
}
