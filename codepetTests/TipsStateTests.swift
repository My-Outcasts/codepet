import XCTest
@testable import codepet

@MainActor
final class TipsStateTests: XCTestCase {

    private var state: TipsState!

    override func setUp() async throws {
        state = TipsState()
    }

    // MARK: - Skill Progress

    func testRecordPracticeIncrementsCount() {
        state.recordPractice(for: "nova", index: 0)
        let progress = state.progress(for: "nova", index: 0)
        XCTAssertEqual(progress.practiceCount, 1)
        XCTAssertFalse(progress.isMastered)
    }

    func testFivePracticesMarksMastered() {
        for _ in 0..<5 {
            state.recordPractice(for: "crash", index: 2)
        }
        let progress = state.progress(for: "crash", index: 2)
        XCTAssertEqual(progress.practiceCount, 5)
        XCTAssertTrue(progress.isMastered)
    }

    func testPracticeClampsAtFive() {
        for _ in 0..<8 {
            state.recordPractice(for: "byte", index: 1)
        }
        let progress = state.progress(for: "byte", index: 1)
        XCTAssertEqual(progress.practiceCount, 5)
    }

    func testMasteredCountPerPet() {
        // Master 2 of nova's 4 skills
        for _ in 0..<5 { state.recordPractice(for: "nova", index: 0) }
        for _ in 0..<5 { state.recordPractice(for: "nova", index: 3) }
        // Partially practice index 1
        state.recordPractice(for: "nova", index: 1)

        XCTAssertEqual(state.masteredCount(for: "nova"), 2)
    }

    func testMasteredCountIsolatedPerPet() {
        for _ in 0..<5 { state.recordPractice(for: "nova", index: 0) }
        for _ in 0..<5 { state.recordPractice(for: "crash", index: 0) }

        XCTAssertEqual(state.masteredCount(for: "nova"), 1)
        XCTAssertEqual(state.masteredCount(for: "crash"), 1)
    }

    func testProgressDefaultsToZero() {
        let progress = state.progress(for: "unknown_pet", index: 99)
        XCTAssertEqual(progress.practiceCount, 0)
        XCTAssertFalse(progress.isMastered)
    }

    // MARK: - Guidance

    func testGuidanceFreshnessToday() {
        let guidance = GuidanceResult(
            headline: "Test",
            project: nil,
            strength: "Strength",
            gap: nil,
            move: "Move",
            status: "new",
            mood: "thinking",
            generatedAt: Date()
        )
        state.currentGuidance = guidance
        XCTAssertTrue(guidance.isFresh)
        XCTAssertFalse(state.needsGuidanceFetch)
    }

    func testGuidanceStaleYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let guidance = GuidanceResult(
            headline: "Old",
            project: nil,
            strength: "Strength",
            gap: nil,
            move: "Move",
            status: "new",
            mood: "calm",
            generatedAt: yesterday
        )
        state.currentGuidance = guidance
        XCTAssertFalse(guidance.isFresh)
        XCTAssertTrue(state.needsGuidanceFetch)
    }

    func testNeedsGuidanceFetchWhenNil() {
        XCTAssertNil(state.currentGuidance)
        XCTAssertTrue(state.needsGuidanceFetch)
    }

    // MARK: - Dismiss

    func testDismissGuidance() {
        XCTAssertFalse(state.isGuidanceDismissed)
        state.dismissGuidance()
        XCTAssertTrue(state.isGuidanceDismissed)
    }

    // MARK: - Setup

    func testSetupCompletionTracking() {
        XCTAssertFalse(state.isSetupCompleted(petId: "luna", index: 2))
        state.markSetupCompleted(petId: "luna", index: 2)
        XCTAssertTrue(state.isSetupCompleted(petId: "luna", index: 2))
        // Other indices unaffected
        XCTAssertFalse(state.isSetupCompleted(petId: "luna", index: 0))
    }
}
