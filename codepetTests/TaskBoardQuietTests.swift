// codepetTests/TaskBoardQuietTests.swift
import XCTest
@testable import codepet

/// The Tasks board, same four lanes, refined (6 Oct design pass, mock approved): a blocked card
/// says what it waits for instead of a "Needs earlier steps" pill, long lanes stop at a few cards
/// plus "N more", and empty lanes say what goes there.
final class TaskBoardQuietTests: XCTestCase {
    private func t(_ id: String, _ title: String, who: TaskWho = .does, done: Bool = false, deps: [String] = []) -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: "", phase: .find, who: who, dependsOn: deps, done: done)
    }

    /// The first unfinished dependency, by title, in `dependsOn` order; finished ones are skipped.
    func testTheWaitingLineNamesTheFirstUnfinishedStep() {
        let all = [t("a", "Interview tenants", who: .you, done: true), t("b", "Decide who pays", who: .you),
                   t("c", "Scope the MVP", deps: ["a", "b"])]
        XCTAssertEqual(TaskBoard.waitingLine(all[2], in: all, lang: .en), "After \u{201C}Decide who pays\u{201D}")
    }

    func testSeveralUnfinishedStepsAreCounted() {
        let all = [t("a", "Interview tenants", who: .you), t("b", "Decide who pays", who: .you),
                   t("c", "Map couriers", who: .you), t("d", "Scope", deps: ["a", "b", "c"])]
        XCTAssertEqual(TaskBoard.waitingLine(all[3], in: all, lang: .en), "After \u{201C}Interview tenants\u{201D} and 2 more")
        XCTAssertEqual(TaskBoard.waitingLine(all[3], in: all, lang: .vi), "Sau \u{201C}Interview tenants\u{201D} và 2 bước khác")
    }

    /// A task with nothing left to wait for has no line — never an empty "After".
    func testNoLineWithoutAnUnfinishedDependency() {
        let all = [t("a", "A", done: true), t("b", "B", deps: ["a", "gone"])]
        XCTAssertNil(TaskBoard.waitingLine(all[1], in: all, lang: .en), "a missing id is not a step to wait for")
        XCTAssertNil(TaskBoard.waitingLine(t("x", "X"), in: [], lang: .en))
    }

    func testLongLanesShowSixThenCountTheRest() {
        XCTAssertEqual(TaskBoard.visible(count: 4, expanded: false), 4)
        XCTAssertEqual(TaskBoard.visible(count: 19, expanded: false), 6)
        XCTAssertEqual(TaskBoard.visible(count: 19, expanded: true), 19)
        XCTAssertEqual(TaskBoard.moreLabel(hidden: 13, lang: .en), "13 more")
    }

    func testTheApprovalLaneIsShortAndEveryEmptyLaneSaysWhatGoesThere() {
        XCTAssertEqual(TaskColumn.awaiting.label(.en), "To approve")
        for col in TaskColumn.allCases {
            XCTAssertFalse(TaskBoard.emptyText(col, lang: .en).isEmpty)
            XCTAssertNotEqual(TaskBoard.emptyText(col, lang: .en), "Nothing here")
        }
    }
}
