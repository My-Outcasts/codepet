import XCTest
@testable import codepet

final class TurnTests: XCTestCase {
    func testTurnIDIsDeterministic() {
        let id = Turn.makeID(sessionId: "abc123", promptISO: "2026-05-05T09:15:23Z")
        XCTAssertEqual(id, "abc123:2026-05-05T09:15:23Z")
    }

    func testNarrativeRoundTripJSON() throws {
        let n = Narrative(
            title: "Test",
            whatYouWanted: "want",
            whatHappened: "did",
            lesson: "learned",
            nextSteps: "try X next",
            model: "claude-haiku-4-5-20251001",
            generatedAt: Date(timeIntervalSince1970: 0),
            schemaVersion: 1
        )
        let data = try JSONEncoder().encode(n)
        let decoded = try JSONDecoder().decode(Narrative.self, from: data)
        XCTAssertEqual(decoded.title, "Test")
        XCTAssertEqual(decoded.lesson, "learned")
    }

    func testTurnStateEquatable() {
        XCTAssertEqual(TurnState.pending, .pending)
        XCTAssertNotEqual(TurnState.failed(reason: .auth), .failed(reason: .quota))
    }
}
