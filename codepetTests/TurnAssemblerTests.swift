import XCTest
@testable import codepet

final class TurnAssemblerTests: XCTestCase {
    private let session = "session-A"

    private func makeEvent(
        time: String,
        text: String,
        sessionId: String? = nil,
        source: EventSource = .claudeCode
    ) -> CapturedEvent {
        CapturedEvent(
            time: time,
            source: source,
            text: text,
            sessionId: sessionId ?? session
        )
    }

    func testSingleTurnHappyPath() {
        // prompt + 2 tools + summary -> 1 ready-shape turn
        let prompt = AssemblerInput(
            kind: .prompt(text: "fix the bug"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let tool1 = AssemblerInput(
            kind: .tool(text: "Edit"),
            isoTime: "2026-05-05T09:00:30Z",
            sessionId: session
        )
        let tool2 = AssemblerInput(
            kind: .tool(text: "Bash"),
            isoTime: "2026-05-05T09:01:00Z",
            sessionId: session
        )
        let summary = AssemblerInput(
            kind: .summary(text: "Edit foo.swift · Bash: git commit"),
            isoTime: "2026-05-05T09:02:00Z",
            sessionId: session
        )

        let turns = TurnAssembler.assemble(
            inputs: [prompt, tool1, tool2, summary],
            now: Date(),
            narratives: [:]
        )

        XCTAssertEqual(turns.count, 1)
        let t = turns[0]
        XCTAssertEqual(t.sessionId, session)
        XCTAssertEqual(t.prompt, "fix the bug")
        XCTAssertEqual(t.rawEvents.count, 2)
        XCTAssertEqual(t.state, .summarizing)  // closed but no narrative
        XCTAssertNotNil(t.endedAt)
    }

    func testTwoPromptsBackToBackFirstIsOrphan() {
        let p1 = AssemblerInput(
            kind: .prompt(text: "first"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let p2 = AssemblerInput(
            kind: .prompt(text: "second"),
            isoTime: "2026-05-05T09:01:00Z",
            sessionId: session
        )
        let s2 = AssemblerInput(
            kind: .summary(text: "did stuff"),
            isoTime: "2026-05-05T09:02:00Z",
            sessionId: session
        )

        let turns = TurnAssembler.assemble(
            inputs: [p1, p2, s2],
            now: Date(),
            narratives: [:]
        )

        XCTAssertEqual(turns.count, 2)
        // Sorted by startedAt descending => second prompt first
        XCTAssertEqual(turns[0].prompt, "second")
        XCTAssertEqual(turns[1].prompt, "first")
        XCTAssertEqual(turns[1].state, .pendingOrphan)
    }

    func testPromptWithNoSummaryWithin30MinutesIsOrphan() {
        let p = AssemblerInput(
            kind: .prompt(text: "abandoned"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let now = ISO8601DateFormatter().date(from: "2026-05-05T09:35:00Z")!

        let turns = TurnAssembler.assemble(
            inputs: [p],
            now: now,
            narratives: [:]
        )

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].state, .pendingOrphan)
    }

    func testPromptWithNoSummaryWithin30MinutesIsPending() {
        let p = AssemblerInput(
            kind: .prompt(text: "still going"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let now = ISO8601DateFormatter().date(from: "2026-05-05T09:10:00Z")!

        let turns = TurnAssembler.assemble(
            inputs: [p],
            now: now,
            narratives: [:]
        )

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].state, .pending)
    }

    func testSummaryBeforePromptIsIgnored() {
        let s = AssemblerInput(
            kind: .summary(text: "lost"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let p = AssemblerInput(
            kind: .prompt(text: "first prompt"),
            isoTime: "2026-05-05T09:01:00Z",
            sessionId: session
        )
        let now = ISO8601DateFormatter().date(from: "2026-05-05T09:05:00Z")!

        let turns = TurnAssembler.assemble(
            inputs: [s, p],
            now: now,
            narratives: [:]
        )

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].prompt, "first prompt")
        XCTAssertEqual(turns[0].state, .pending)
    }

    func testNarrativeMergedWhenAvailable() {
        let p = AssemblerInput(
            kind: .prompt(text: "summarize me"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let s = AssemblerInput(
            kind: .summary(text: "raw"),
            isoTime: "2026-05-05T09:01:00Z",
            sessionId: session
        )
        let id = Turn.makeID(sessionId: session, promptISO: "2026-05-05T09:00:00Z")
        let n = Narrative(
            title: "T",
            whatYouWanted: "w",
            whatHappened: "h",
            lesson: "l",
            nextSteps: "",
            model: "m",
            generatedAt: Date(),
            schemaVersion: 1
        )

        let turns = TurnAssembler.assemble(
            inputs: [p, s],
            now: Date(),
            narratives: [id: n]
        )

        XCTAssertEqual(turns.count, 1)
        XCTAssertNotNil(turns[0].narrative)
        XCTAssertEqual(turns[0].state, .ready)
    }

    func testRawEventIDsAreDeterministicAcrossCalls() {
        let p = AssemblerInput(
            kind: .prompt(text: "p"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let t = AssemblerInput(
            kind: .tool(text: "Edit"),
            isoTime: "2026-05-05T09:00:30Z",
            sessionId: session
        )
        let s = AssemblerInput(
            kind: .summary(text: "done"),
            isoTime: "2026-05-05T09:01:00Z",
            sessionId: session
        )

        let first = TurnAssembler.assemble(inputs: [p, t, s], now: Date(), narratives: [:])
        let second = TurnAssembler.assemble(inputs: [p, t, s], now: Date(), narratives: [:])

        XCTAssertEqual(first[0].rawEvents[0].id, second[0].rawEvents[0].id,
                       "Same logical event must get same UUID across calls")
    }

    func testPromptAtExactly30MinutesIsPending() {
        let p = AssemblerInput(
            kind: .prompt(text: "boundary"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let now = ISO8601DateFormatter().date(from: "2026-05-05T09:30:00Z")!

        let turns = TurnAssembler.assemble(inputs: [p], now: now, narratives: [:])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].state, .pending,
                       "At exactly 30:00 the prompt is still pending — orphan threshold is strict >30min")
    }

    func testPromptAtJustOver30MinutesIsOrphan() {
        let p = AssemblerInput(
            kind: .prompt(text: "boundary"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: session
        )
        let now = ISO8601DateFormatter().date(from: "2026-05-05T09:30:01Z")!

        let turns = TurnAssembler.assemble(inputs: [p], now: now, narratives: [:])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].state, .pendingOrphan)
    }

    // MARK: - Session assembler tests

    func testAssembleSessionsGroupsTurnsBySessionId() {
        let pA = AssemblerInput(kind: .prompt(text: "A1"), isoTime: "2026-05-05T09:00:00Z", sessionId: "A")
        let sA = AssemblerInput(kind: .summary(text: "A done"), isoTime: "2026-05-05T09:05:00Z", sessionId: "A")
        let pB1 = AssemblerInput(kind: .prompt(text: "B1"), isoTime: "2026-05-05T09:01:00Z", sessionId: "B")
        let sB1 = AssemblerInput(kind: .summary(text: "B1 done"), isoTime: "2026-05-05T09:06:00Z", sessionId: "B")
        let pB2 = AssemblerInput(kind: .prompt(text: "B2"), isoTime: "2026-05-05T09:10:00Z", sessionId: "B")
        let sB2 = AssemblerInput(kind: .summary(text: "B2 done"), isoTime: "2026-05-05T09:15:00Z", sessionId: "B")

        let turns = TurnAssembler.assemble(
            inputs: [pA, sA, pB1, sB1, pB2, sB2],
            now: Date(),
            narratives: [:]
        )
        let sessions = TurnAssembler.assembleSessions(turns: turns, summaries: [:])

        XCTAssertEqual(sessions.count, 2, "Should produce exactly 2 sessions")

        let sessionIds = Set(sessions.map { $0.id })
        XCTAssertEqual(sessionIds, ["A", "B"])

        let sessionB = sessions.first(where: { $0.id == "B" })!
        XCTAssertEqual(sessionB.turns.count, 2, "Session B should have 2 turns")

        // Turns within session B should be sorted oldest-first
        XCTAssertLessThan(sessionB.turns[0].startedAt, sessionB.turns[1].startedAt,
                          "Turns inside session should be sorted oldest-first")

        // Sessions sorted newest-first by their last turn's startedAt
        // Session B's newest turn is at 09:10 vs Session A's only turn at 09:00
        XCTAssertEqual(sessions[0].id, "B", "Session with more recent activity should sort first")
    }

    func testLongIdleGapSplitsSessionIntoSegments() {
        // One CLI session id "S" with two bursts of work separated by a 55-min
        // idle gap (turn 1 ends 09:05, turn 2 starts 10:00). Should split into
        // two CodePet sessions.
        let p1 = AssemblerInput(kind: .prompt(text: "morning"), isoTime: "2026-05-05T09:00:00Z", sessionId: "S")
        let s1 = AssemblerInput(kind: .summary(text: "morning done"), isoTime: "2026-05-05T09:05:00Z", sessionId: "S")
        let p2 = AssemblerInput(kind: .prompt(text: "afternoon"), isoTime: "2026-05-05T10:00:00Z", sessionId: "S")
        let s2 = AssemblerInput(kind: .summary(text: "afternoon done"), isoTime: "2026-05-05T10:05:00Z", sessionId: "S")

        let turns = TurnAssembler.assemble(inputs: [p1, s1, p2, s2], now: Date(), narratives: [:])
        let sessions = TurnAssembler.assembleSessions(turns: turns, summaries: [:])

        XCTAssertEqual(sessions.count, 2, "A 55-min idle gap should split one CLI session into two")
        // First segment keeps the raw id; later segment is suffixed.
        XCTAssertEqual(Set(sessions.map { $0.id }), ["S", "S#2"])
        let first = sessions.first(where: { $0.id == "S" })!
        let second = sessions.first(where: { $0.id == "S#2" })!
        XCTAssertEqual(first.turns.count, 1, "Morning burst is its own session")
        XCTAssertEqual(second.turns.count, 1, "Afternoon burst is its own session")
    }

    func testShortGapDoesNotSplitSession() {
        // 09:05 end -> 09:49 start is a 44-min gap, just under the 45-min cut.
        let p1 = AssemblerInput(kind: .prompt(text: "first"), isoTime: "2026-05-05T09:00:00Z", sessionId: "S")
        let s1 = AssemblerInput(kind: .summary(text: "first done"), isoTime: "2026-05-05T09:05:00Z", sessionId: "S")
        let p2 = AssemblerInput(kind: .prompt(text: "second"), isoTime: "2026-05-05T09:49:00Z", sessionId: "S")
        let s2 = AssemblerInput(kind: .summary(text: "second done"), isoTime: "2026-05-05T09:54:00Z", sessionId: "S")

        let turns = TurnAssembler.assemble(inputs: [p1, s1, p2, s2], now: Date(), narratives: [:])
        let sessions = TurnAssembler.assembleSessions(turns: turns, summaries: [:])

        XCTAssertEqual(sessions.count, 1, "A sub-45-min gap should stay one session")
        XCTAssertEqual(sessions[0].id, "S")
        XCTAssertEqual(sessions[0].turns.count, 2)
    }

    func testSplitSegmentsResolveTheirOwnSummaries() {
        // After a split, each segment looks up its own summary by its derived id.
        let p1 = AssemblerInput(kind: .prompt(text: "morning"), isoTime: "2026-05-05T09:00:00Z", sessionId: "S")
        let s1 = AssemblerInput(kind: .summary(text: "morning done"), isoTime: "2026-05-05T09:05:00Z", sessionId: "S")
        let p2 = AssemblerInput(kind: .prompt(text: "evening"), isoTime: "2026-05-05T17:00:00Z", sessionId: "S")
        let s2 = AssemblerInput(kind: .summary(text: "evening done"), isoTime: "2026-05-05T17:05:00Z", sessionId: "S")

        let turns = TurnAssembler.assemble(inputs: [p1, s1, p2, s2], now: Date(), narratives: [:])
        let summaries = [
            "S": SessionSummary(sessionId: "S", summary: "morning recap", lesson: "L1",
                                generatedAt: Date(), model: "m", schemaVersion: 1),
            "S#2": SessionSummary(sessionId: "S#2", summary: "evening recap", lesson: "L2",
                                  generatedAt: Date(), model: "m", schemaVersion: 1),
        ]
        let sessions = TurnAssembler.assembleSessions(turns: turns, summaries: summaries)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first(where: { $0.id == "S" })?.summary?.summary, "morning recap")
        XCTAssertEqual(sessions.first(where: { $0.id == "S#2" })?.summary?.summary, "evening recap")
    }

    func testAssembleSessionsAttachesSummary() {
        let p = AssemblerInput(kind: .prompt(text: "do stuff"), isoTime: "2026-05-05T09:00:00Z", sessionId: "S1")
        let s = AssemblerInput(kind: .summary(text: "done"), isoTime: "2026-05-05T09:05:00Z", sessionId: "S1")

        let turns = TurnAssembler.assemble(inputs: [p, s], now: Date(), narratives: [:])

        let mockSummary = SessionSummary(
            sessionId: "S1",
            summary: "Session S1 summary",
            lesson: "Key lesson",
            generatedAt: Date(),
            model: "claude-haiku",
            schemaVersion: 1
        )
        let sessions = TurnAssembler.assembleSessions(turns: turns, summaries: ["S1": mockSummary])

        XCTAssertEqual(sessions.count, 1)
        XCTAssertNotNil(sessions[0].summary, "Summary should be attached to session")
        XCTAssertEqual(sessions[0].summary?.summary, "Session S1 summary")
        XCTAssertEqual(sessions[0].summary?.lesson, "Key lesson")

        // Session without summary should have nil
        let sessionsNoSummary = TurnAssembler.assembleSessions(turns: turns, summaries: [:])
        XCTAssertNil(sessionsNoSummary[0].summary, "Session without matching summary should have nil")
    }

    func testInterleavedSessionsKeptSeparate() {
        let pA = AssemblerInput(
            kind: .prompt(text: "A1"),
            isoTime: "2026-05-05T09:00:00Z",
            sessionId: "A"
        )
        let pB = AssemblerInput(
            kind: .prompt(text: "B1"),
            isoTime: "2026-05-05T09:00:30Z",
            sessionId: "B"
        )
        let sA = AssemblerInput(
            kind: .summary(text: "A done"),
            isoTime: "2026-05-05T09:01:00Z",
            sessionId: "A"
        )
        let sB = AssemblerInput(
            kind: .summary(text: "B done"),
            isoTime: "2026-05-05T09:01:30Z",
            sessionId: "B"
        )

        let turns = TurnAssembler.assemble(
            inputs: [pA, pB, sA, sB],
            now: Date(),
            narratives: [:]
        )

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(Set(turns.map { $0.sessionId }), ["A", "B"])
        // Both turns are closed by a summary but have no write tools, so they
        // resolve straight to .ready (read-only turns skip summarization).
        XCTAssertTrue(turns.allSatisfy { $0.state == .ready })
    }
}
