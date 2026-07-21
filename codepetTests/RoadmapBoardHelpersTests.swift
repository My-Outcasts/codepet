// codepetTests/RoadmapBoardHelpersTests.swift
import XCTest
@testable import codepet

final class RoadmapBoardHelpersTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does)
    }

    func testOrderedColumnsAllFivePhasesInOrder() {
        let tasks = [t("a", .build), t("b", .find), t("c", .build)]
        let cols = RoadmapEngine.orderedColumns(tasks)
        XCTAssertEqual(cols.map(\.phase), RoadmapPhase.allCases)   // Find..Launch, all 5
        XCTAssertEqual(cols.map(\.phase.order), [0, 1, 2, 3, 4])
        XCTAssertEqual(cols[0].tasks.map(\.id), ["b"])            // find
        XCTAssertEqual(cols[2].tasks.map(\.id), ["a", "c"])       // build, input order preserved
        XCTAssertTrue(cols[3].tasks.isEmpty)                      // ship — empty phase present
        XCTAssertTrue(cols[4].tasks.isEmpty)                     // launch — empty phase present
    }
    func testOrderedColumnsEmptyInputStillFivePhases() {
        XCTAssertEqual(RoadmapEngine.orderedColumns([]).map(\.phase), RoadmapPhase.allCases)
        XCTAssertTrue(RoadmapEngine.orderedColumns([]).allSatisfy { $0.tasks.isEmpty })
    }
    func testStatusLabelsDistinctNonEmptyBothLanguages() {
        let statuses: [TaskStatus] = [.done, .codepetCanDo, .needsApproval, .needsYou, .blocked]
        for lang in [AppLanguage.en, .vi] {
            let labels = statuses.map { $0.label(lang) }
            XCTAssertEqual(Set(labels).count, 5)                  // all distinct
            XCTAssertFalse(labels.contains(where: \.isEmpty))
        }
    }
    func testWhoLabelsDistinctNonEmptyBothLanguages() {
        let whos: [TaskWho] = [.does, .draft, .you]
        for lang in [AppLanguage.en, .vi] {
            let labels = whos.map { $0.label(lang) }
            XCTAssertEqual(Set(labels).count, 3)
            XCTAssertFalse(labels.contains(where: \.isEmpty))
        }
    }
}
