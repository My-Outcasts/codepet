// codepetTests/CompanyStoreExecLogTests.swift
import XCTest
@testable import codepet

/// #2 — the run execute-log: the steps describe the real pipeline (context →
/// [specialist] → draft → review) and are grounded in the actual request inputs.
@MainActor
final class CompanyStoreExecLogTests: XCTestCase {
    private func task() -> RoadmapTask {
        RoadmapTask(id: "t1", title: "Write landing copy", detail: "hero", phase: .build, who: .draft, dept: "mkt")
    }

    func testStepsWithSpecialistAndDecisions() {
        let steps = CompanyStore.execSteps(task: task(),
                                           specialist: ("nova", "Marketing"),
                                           decisionCount: 2, language: .en).map(\.label)
        XCTAssertEqual(steps, [
            "Reading your brief and 2 decisions",
            "Applying Marketing expertise",
            "Drafting Write landing copy",
            "Reviewing the draft",
        ])
    }

    func testStepsWithoutSpecialistOrDecisions() {
        let steps = CompanyStore.execSteps(task: task(),
                                           specialist: nil,
                                           decisionCount: 0, language: .en).map(\.label)
        XCTAssertEqual(steps, [
            "Reading your brief",
            "Drafting Write landing copy",
            "Reviewing the draft",
        ])
        // Every step starts not-done.
        let raw = CompanyStore.execSteps(task: task(), specialist: nil, decisionCount: 0, language: .en)
        XCTAssertTrue(raw.allSatisfy { !$0.done })
    }

    func testVietnameseLabels() {
        let steps = CompanyStore.execSteps(task: task(), specialist: ("nova", "Marketing"),
                                           decisionCount: 1, language: .vi).map(\.label)
        XCTAssertEqual(steps.first, "Đọc brief và 1 quyết định của bạn")
        XCTAssertEqual(steps.last, "Rà soát bản nháp")
    }
}
