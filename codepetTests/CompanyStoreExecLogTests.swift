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
            "Reading your brief — mission, audience, your voice (+ 2 decisions)",
            "Pulling in the Marketing playbook",
            "Drafting Write landing copy",
            "Matching your tone and past decisions",
        ])
    }

    func testStepsWithoutSpecialistOrDecisions() {
        let steps = CompanyStore.execSteps(task: task(),
                                           specialist: nil,
                                           decisionCount: 0, language: .en).map(\.label)
        XCTAssertEqual(steps, [
            "Reading your brief — mission, audience, your voice",
            "Drafting Write landing copy",
            "Matching your tone and past decisions",
        ])
        // Every step starts not-done.
        let raw = CompanyStore.execSteps(task: task(), specialist: nil, decisionCount: 0, language: .en)
        XCTAssertTrue(raw.allSatisfy { !$0.done })
    }

    func testVietnameseLabels() {
        let steps = CompanyStore.execSteps(task: task(), specialist: ("nova", "Marketing"),
                                           decisionCount: 1, language: .vi).map(\.label)
        XCTAssertTrue(steps.first?.hasPrefix("Đọc brief") ?? false)
        XCTAssertEqual(steps.last, "Khớp giọng điệu và quyết định của bạn")
    }
}
