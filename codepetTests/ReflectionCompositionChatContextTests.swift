import XCTest
@testable import codepet

final class ReflectionCompositionChatContextTests: XCTestCase {

    func testMakeChatContextFlattensSessionFields() {
        // CapturedEvent.text drives the tool/path extraction:
        // "Edit ReflectionTab.swift" → tool="Edit", path="ReflectionTab.swift"
        // "Bash: swift test"         → tool="Bash", path="swift test"
        let rawEvents: [CapturedEvent] = [
            CapturedEvent(time: "09:00", source: .claudeCode, text: "Edit ReflectionTab.swift"),
            CapturedEvent(time: "09:05", source: .claudeCode, text: "Bash: swift test")
        ]

        let narrative = Narrative(
            title: "T",
            whatYouWanted: "you wanted clean rows",
            whatHappened: "we tried twice",
            lesson: "isolate the layout first",
            nextSteps: "",
            model: "test-model",
            generatedAt: Date(),
            schemaVersion: 1
        )

        let turn = Turn.makeForTesting(
            prompt: "fix the layout",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),  // +10 min
            narrative: narrative,
            rawEvents: rawEvents
        )

        let summary = SessionSummary.makeForTesting(
            sessionId: "s1",
            summary: "We worked through the layout together.",
            lesson: "Isolation first.",
            createdAt: Date()
        )

        let session = Session.makeForTesting(
            id: "s1",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            turns: [turn],
            summary: summary
        )

        let context = ReflectionComposition.makeChatContext(
            for: session,
            userBrief: "shipping a journaling app"
        )

        XCTAssertEqual(context.userBrief, "shipping a journaling app")
        XCTAssertEqual(context.summary?.summary, "We worked through the layout together.")
        XCTAssertEqual(context.summary?.lesson, "Isolation first.")
        XCTAssertEqual(context.turns.count, 1)
        let dto = context.turns.first!
        XCTAssertEqual(dto.prompt, "fix the layout")
        XCTAssertEqual(dto.whatYouWanted, "you wanted clean rows")
        XCTAssertEqual(dto.whatHappened, "we tried twice")
        XCTAssertEqual(dto.lesson, "isolate the layout first")
        XCTAssertEqual(dto.durationMinutes, 10)
        XCTAssertEqual(dto.events.count, 2)
        XCTAssertEqual(dto.events.first?.tool, "Edit")
    }

    func testMakeChatContextOmitsMissingFields() {
        let turn = Turn.makeForTesting(
            prompt: "x",
            startedAt: Date(),
            endedAt: nil,
            narrative: nil,
            rawEvents: []
        )
        let session = Session.makeForTesting(
            id: "s1",
            startedAt: Date(),
            endedAt: nil,
            turns: [turn],
            summary: nil
        )

        let context = ReflectionComposition.makeChatContext(for: session, userBrief: nil)
        XCTAssertNil(context.userBrief)
        XCTAssertNil(context.summary)
        XCTAssertNil(context.turns.first?.whatYouWanted)
        XCTAssertNil(context.turns.first?.durationMinutes)
    }
}
