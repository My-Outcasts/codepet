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
