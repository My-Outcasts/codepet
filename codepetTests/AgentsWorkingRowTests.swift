import XCTest
@testable import codepet

final class AgentsWorkingRowTests: XCTestCase {
    private func makeRun(steps: [ExecStep],
                         status: AgentRunStatus = .working,
                         startedAt: Date = Date(timeIntervalSince1970: 0)) -> AgentRun {
        AgentRun(companionId: "byte", deptName: "Engineering",
                 taskTitle: "Build the API", steps: steps,
                 status: status, startedAt: startedAt)
    }

    func testStepCounterCountsDoneOverTotal() {
        let r = makeRun(steps: [ExecStep(label: "a", done: true),
                                ExecStep(label: "b", done: true),
                                ExecStep(label: "c", done: false)])
        XCTAssertEqual(r.stepCounter, "2/3")
    }

    func testStepCounterNoneDone() {
        let r = makeRun(steps: [ExecStep(label: "a", done: false),
                                ExecStep(label: "b", done: false)])
        XCTAssertEqual(r.stepCounter, "0/2")
    }

    func testCurrentStepIndexIsFirstNotDone() {
        let r = makeRun(steps: [ExecStep(label: "a", done: true),
                                ExecStep(label: "b", done: false),
                                ExecStep(label: "c", done: false)])
        XCTAssertEqual(r.currentStepIndex, 1)
    }

    func testCurrentStepIndexNilWhenAllDone() {
        let r = makeRun(steps: [ExecStep(label: "a", done: true)])
        XCTAssertNil(r.currentStepIndex)
    }

    func testElapsedStringFormatsMinutesSeconds() {
        let r = makeRun(steps: [])
        XCTAssertEqual(r.elapsedString(now: Date(timeIntervalSince1970: 134)), "2:14")
    }

    func testElapsedStringPadsSeconds() {
        let r = makeRun(steps: [])
        XCTAssertEqual(r.elapsedString(now: Date(timeIntervalSince1970: 8)), "0:08")
    }

    func testElapsedStringNeverNegative() {
        let r = makeRun(steps: [], startedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(r.elapsedString(now: Date(timeIntervalSince1970: 40)), "0:00")
    }

    func testStatusLabelExhaustiveEnglish() {
        XCTAssertEqual(AgentRunStatus.working.label(.en), "Working")
        XCTAssertEqual(AgentRunStatus.reviewing.label(.en), "Reviewing")
        XCTAssertEqual(AgentRunStatus.done.label(.en), "Done")
        XCTAssertEqual(AgentRunStatus.failed.label(.en), "Failed")
    }
}
