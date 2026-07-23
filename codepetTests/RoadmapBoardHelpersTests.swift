// codepetTests/RoadmapBoardHelpersTests.swift
import XCTest
@testable import codepet

final class RoadmapBoardHelpersTests: XCTestCase {
    private func t(_ id: String, _ phase: RoadmapPhase) -> RoadmapTask {
        RoadmapTask(id: id, title: id, detail: "", phase: phase, who: .does)
    }

    func testOrderedColumnsAllPhasesInOrder() {
        let tasks = [t("a", .build), t("b", .find), t("c", .build)]
        let cols = RoadmapEngine.orderedColumns(tasks)
        XCTAssertEqual(cols.map(\.phase), RoadmapPhase.allCases)   // every phase, in declared order
        XCTAssertEqual(cols.map(\.phase.order), Array(0..<RoadmapPhase.allCases.count))
        XCTAssertEqual(cols[RoadmapPhase.find.order].tasks.map(\.id), ["b"])
        XCTAssertEqual(cols[RoadmapPhase.build.order].tasks.map(\.id), ["a", "c"]) // input order preserved
        XCTAssertTrue(cols[RoadmapPhase.ship.order].tasks.isEmpty)   // empty phase still present
        XCTAssertTrue(cols[RoadmapPhase.launch.order].tasks.isEmpty)
    }
    func testOrderedColumnsEmptyInputStillAllPhases() {
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
