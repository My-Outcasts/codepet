// codepetTests/DraftNextStepTests.swift
import XCTest
@testable import codepet

/// A filed draft says what happens next. Before this the card ended on "Added to Library" and
/// the founder did not know whether to wait, type, or go somewhere.
@MainActor
final class DraftNextStepTests: XCTestCase {
    private func task(_ id: String, who: TaskWho = .does, done: Bool = false, drafted: Bool = false,
                      deps: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: "Task \(id)", detail: "", phase: .find, who: who,
                    dependsOn: deps, done: done, drafted: drafted, dept: "design")
    }

    func testNextRunnableTaskIsOfferedToRun() async {
        let tasks = [task("a", done: true), task("b", deps: ["a"])]
        XCTAssertEqual(DraftCardCopy.nextStep(in: tasks), .run(tasks[1]))
    }

    func testAFounderTaskIsTheirs() async {
        let tasks = [task("a", done: true), task("b", who: .you)]
        XCTAssertEqual(DraftCardCopy.nextStep(in: tasks), .yours(tasks[1]))
    }

    func testAWaitingDraftAsksForReview() async {
        let tasks = [task("a", drafted: true)]
        XCTAssertEqual(DraftCardCopy.nextStep(in: tasks), .review(tasks[0]))
    }

    func testAllDoneSaysSoRatherThanNothing() async {
        let step = DraftCardCopy.nextStep(in: [task("a", done: true)])
        XCTAssertEqual(step, .none)
        XCTAssertFalse(DraftCardCopy.nextLine(step, deptName: { _ in nil }, .en).isEmpty)
    }

    func testOnlyTheLatestFiledDraftCarriesIt() async {
        let d = Deliverable(kind: .doc, title: "x", body: "y")
        var older = CopilotMessage(role: .companion, text: "", draft: d); older.draftApproved = true
        var newer = CopilotMessage(role: .companion, text: "", draft: d); newer.draftApproved = true
        let pending = CopilotMessage(role: .companion, text: "", draft: d)
        let msgs = [older, newer, pending]
        XCTAssertFalse(DraftCardCopy.isLatestFiled(older.id, in: msgs))
        XCTAssertTrue(DraftCardCopy.isLatestFiled(newer.id, in: msgs), "an unapproved draft after it does not take it")
    }
}
