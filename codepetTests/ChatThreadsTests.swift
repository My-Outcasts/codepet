// codepetTests/ChatThreadsTests.swift
import XCTest
@testable import codepet

/// Struct-only tests for the pure `ChatThreads.swift` helpers — no `CompanyStore`,
/// no `@MainActor`, no DI stub. Mirrors the web's `lib/chat/threads.test.ts`.
final class ChatThreadsTests: XCTestCase {

    // MARK: - deriveThreadTitle

    private func me(_ text: String) -> CopilotMessage { CopilotMessage(role: .me, text: text) }
    private func companion(_ text: String) -> CopilotMessage { CopilotMessage(role: .companion, text: text) }

    func testDeriveThreadTitleUsesFirstMeMessageCollapsingWhitespace() {
        let messages = [me("  Help me   draft copy ")]
        XCTAssertEqual(deriveThreadTitle(messages), "Help me draft copy")
    }

    func testDeriveThreadTitleSkipsLeadingCompanionMessages() {
        let messages = [companion("greeting"), companion("another"), me("  Actual first ask ")]
        XCTAssertEqual(deriveThreadTitle(messages), "Actual first ask")
    }

    func testDeriveThreadTitleTruncatesTo40CharsWithEllipsis() {
        let long = "Draft the landing page hero copy for the new pricing tiers"
        XCTAssertEqual(deriveThreadTitle([me(long)]), "Draft the landing page hero copy for the\u{2026}")
    }

    func testDeriveThreadTitleKeeps40CharsUnchangedButTruncates41() {
        XCTAssertEqual(deriveThreadTitle([me(String(repeating: "a", count: 40))]),
                       String(repeating: "a", count: 40))
        XCTAssertEqual(deriveThreadTitle([me(String(repeating: "a", count: 41))]),
                       String(repeating: "a", count: 40) + "\u{2026}")
    }

    func testDeriveThreadTitleNilWhenEmpty() {
        XCTAssertNil(deriveThreadTitle([]))
    }

    /// A thread with only byte's seeded question/greeting (no founder message yet)
    /// now falls back to that message so it gets a distinguishable name, not "New chat".
    func testDeriveThreadTitleFallsBackToCompanionWhenNoMe() {
        XCTAssertEqual(deriveThreadTitle([companion("hi there")]), "hi there")
    }

    /// The founder's first message still wins over an earlier companion message.
    func testDeriveThreadTitlePrefersMeOverCompanion() {
        XCTAssertEqual(deriveThreadTitle([companion("byte's question"), me("my real topic")]),
                       "my real topic")
    }

    func testDeriveThreadTitleNilWhenFirstMeMessageIsBlank() {
        XCTAssertNil(deriveThreadTitle([me("   ")]))
    }

    // MARK: - sortThreadsByRecent

    private func thread(_ id: String, _ updatedAt: Date) -> ChatThread {
        ChatThread(id: id, title: id, messages: [], createdAt: updatedAt, updatedAt: updatedAt)
    }

    func testSortThreadsByRecentOrdersDescendingWithoutMutatingInput() {
        let base = Date()
        let input = [thread("a", base.addingTimeInterval(1)),
                     thread("b", base.addingTimeInterval(3)),
                     thread("c", base.addingTimeInterval(2))]
        XCTAssertEqual(sortThreadsByRecent(input).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(input.map(\.id), ["a", "b", "c"])   // input unchanged
    }

    // MARK: - pickFallbackThreadId

    func testPickFallbackThreadIdReturnsMostRecentRemaining() {
        let base = Date()
        let threads = [thread("a", base.addingTimeInterval(1)),
                       thread("b", base.addingTimeInterval(3)),
                       thread("c", base.addingTimeInterval(2))]
        XCTAssertEqual(pickFallbackThreadId(after: "b", in: threads), "c")
    }

    func testPickFallbackThreadIdNilWhenNothingRemains() {
        let threads = [thread("a", Date())]
        XCTAssertNil(pickFallbackThreadId(after: "a", in: threads))
    }

    // MARK: - pickResumeThreadId

    private func thread(_ id: String, _ updatedAt: Date, messages: [CopilotMessage]) -> ChatThread {
        ChatThread(id: id, title: id, messages: messages, createdAt: updatedAt, updatedAt: updatedAt)
    }

    func testPickResumeThreadIdReturnsMostRecentInsideTheWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let threads = [thread("a", now.addingTimeInterval(-3600), messages: [me("older")]),
                       thread("b", now.addingTimeInterval(-600), messages: [me("newest")]),
                       thread("c", now.addingTimeInterval(-1800), messages: [me("middle")])]
        XCTAssertEqual(pickResumeThreadId(in: threads, now: now), "b")
    }

    func testPickResumeThreadIdNilWhenTheLastThreadIsStale() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Quit last evening, reopening the next morning → land on the hero, not
        // yesterday's transcript.
        let threads = [thread("a", now.addingTimeInterval(-15 * 3600), messages: [me("yesterday")])]
        XCTAssertNil(pickResumeThreadId(in: threads, now: now))
    }

    func testPickResumeThreadIdWindowBoundaryIsInclusive() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let atEdge = [thread("a", now.addingTimeInterval(-threadResumeWindow), messages: [me("hi")])]
        XCTAssertEqual(pickResumeThreadId(in: atEdge, now: now), "a")
        let pastEdge = [thread("a", now.addingTimeInterval(-threadResumeWindow - 1), messages: [me("hi")])]
        XCTAssertNil(pickResumeThreadId(in: pastEdge, now: now))
    }

    func testPickResumeThreadIdNilWhenNoThreads() {
        XCTAssertNil(pickResumeThreadId(in: [], now: Date()))
    }

    /// A decoded doc with no messages left (nothing but stripped run state) is not
    /// something to resume INTO — fall through to the newest thread that has
    /// content, so launch never opens a blank transcript with no hero either.
    func testPickResumeThreadIdSkipsMessagelessThreads() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let threads = [thread("empty", now.addingTimeInterval(-60), messages: []),
                       thread("real", now.addingTimeInterval(-300), messages: [me("hi")])]
        XCTAssertEqual(pickResumeThreadId(in: threads, now: now), "real")
    }

    /// Clock skew (a thread stamped slightly in the future by another device)
    /// must not read as "stale" and drop the founder onto the hero.
    func testPickResumeThreadIdToleratesFutureTimestamps() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let threads = [thread("a", now.addingTimeInterval(120), messages: [me("hi")])]
        XCTAssertEqual(pickResumeThreadId(in: threads, now: now), "a")
    }

    // MARK: - relativeTime

    func testRelativeTimeFormatsRecentTimes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(relativeTime(now, now: now), "just now")
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-5 * 60), now: now), "5m ago")
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-3 * 3600), now: now), "3h ago")
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-2 * 86400), now: now), "2d ago")
    }

    func testRelativeTimeHandlesTierBoundariesExactly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-59), now: now), "just now")
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-60), now: now), "1m ago")
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-59 * 60), now: now), "59m ago")
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-60 * 60), now: now), "1h ago")
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-23 * 3600), now: now), "23h ago")
        XCTAssertEqual(relativeTime(now.addingTimeInterval(-24 * 3600), now: now), "1d ago")
    }
}
