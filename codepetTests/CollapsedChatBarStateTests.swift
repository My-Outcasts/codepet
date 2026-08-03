// codepetTests/CollapsedChatBarStateTests.swift
import XCTest
@testable import codepet

/// The collapsed copilot bar replaced a full-height reopen rail with a real input,
/// so its send gate and unread rule are now load-bearing: a wrong gate either drops
/// a founder's message or fires a second turn mid-stream.
final class CollapsedChatBarStateTests: XCTestCase {

    // MARK: - canSend

    func testWontSendEmptyOrWhitespaceOnly() {
        XCTAssertFalse(CollapsedChatBarState.canSend(draft: "", busy: false))
        XCTAssertFalse(CollapsedChatBarState.canSend(draft: "   ", busy: false))
        XCTAssertFalse(CollapsedChatBarState.canSend(draft: "\n\t ", busy: false))
    }

    func testSendsRealText() {
        XCTAssertTrue(CollapsedChatBarState.canSend(draft: "ship the waitlist", busy: false))
        // Padding around real text is still real text.
        XCTAssertTrue(CollapsedChatBarState.canSend(draft: "  hello  ", busy: false))
    }

    /// The bar stays visible while a turn streams, so without this a second Return
    /// would fire a concurrent turn into the same thread.
    func testWontSendWhileATurnIsInFlight() {
        XCTAssertFalse(CollapsedChatBarState.canSend(draft: "ship the waitlist", busy: true))
    }

    // MARK: - unread dot

    func testNoDotWhenNothingArrivedSinceTheDockWasOpen() {
        XCTAssertFalse(CollapsedChatBarState.showsUnreadDot(messageCount: 4, seen: 4))
        XCTAssertFalse(CollapsedChatBarState.showsUnreadDot(messageCount: 0, seen: 0))
    }

    func testDotWhenMessagesArrivedWhileClosed() {
        XCTAssertTrue(CollapsedChatBarState.showsUnreadDot(messageCount: 5, seen: 4))
    }

    /// A thread switch or "New chat" can leave fewer messages than were seen; that
    /// is not unread, and must not read as a negative-delta dot.
    func testShrinkingTranscriptIsNotUnread() {
        XCTAssertFalse(CollapsedChatBarState.showsUnreadDot(messageCount: 2, seen: 9))
    }

    // MARK: - needs-you count agrees with the nav badge

    /// The bar's count and the Tasks nav badge must never disagree about the same
    /// state, so the bar derives from the same `TopbarCounts.tasks` rule.
    func testNeedsYouMatchesTheTasksNavBadge() {
        let tasks = [
            task("a", who: .you),                 // counts — hers to do
            task("b", who: .draft),               // counts — draft awaiting approval
            task("c", who: .you, done: true),     // done → excluded
            task("d", who: .does),                // Codepet's move → excluded
        ]
        XCTAssertEqual(CollapsedChatBarState.needsYouCount(tasks: tasks), 2)
        // Pinned to the nav badge's own rule, so the two can't drift apart.
        XCTAssertEqual(CollapsedChatBarState.needsYouCount(tasks: tasks),
                       TopbarCounts.tasks(tasks))
    }

    func testNeedsYouIsZeroWithNoTasks() {
        XCTAssertEqual(CollapsedChatBarState.needsYouCount(tasks: []), 0)
    }

    private func task(_ id: String, who: TaskWho, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: .build, who: who, done: done)
    }
}
