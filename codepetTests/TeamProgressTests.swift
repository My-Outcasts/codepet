// codepetTests/TeamProgressTests.swift
import XCTest
@testable import codepet

/// CP-033: while a Team Build runs, the card shows a progress strip and one live line instead of
/// every step's full row. `TeamProgress` is what the card reads, pure so the rules are pinned.
final class TeamProgressTests: XCTestCase {
    private let plan = WorkPlan(
        title: "Beta FAQ page", slug: "faq", summary: "An FAQ for beta testers.", projectType: "static landing page",
        steps: [
            WorkStep(id: "s1", dept: "support", title: "Collect recurring questions", instruction: "i", kind: "doc", dependsOn: []),
            WorkStep(id: "s2", dept: "support", title: "Write the FAQ answers", instruction: "i", kind: "doc", dependsOn: ["s1"]),
            WorkStep(id: "s3", dept: "legal", title: "Check claims and privacy wording", instruction: "i", kind: "doc", dependsOn: ["s2"]),
            WorkStep(id: "build", dept: "eng", title: "Build the project", instruction: "i", kind: "other", dependsOn: ["s1", "s2", "s3"]),
        ])

    private func run(_ statuses: [String: TeamStepStatus], phase: TeamRunPhase = .running) -> TeamRun {
        var r = TeamRun(request: "an FAQ", createdAt: Date(), brief: nil, plan: plan)
        r.phase = phase
        for (id, s) in statuses {
            if let i = r.steps.firstIndex(where: { $0.stepId == id }) { r.steps[i].status = s }
        }
        return r
    }

    func testTheStripHasOneSegmentPerStepInPlanOrder() {
        let p = TeamProgress(run(["s1": .done, "s2": .running]))
        XCTAssertEqual(p.segments, [.done, .running, .waiting, .waiting])
        XCTAssertEqual(p.doneCount, 1)
        XCTAssertEqual(p.total, 4)
    }

    func testTheLiveLineNamesTheRunningStepAndWhatIsNext() {
        let p = TeamProgress(run(["s1": .done, "s2": .running]))
        XCTAssertEqual(p.current.map(\.id), ["s2"])
        XCTAssertEqual(p.next?.id, "s3", "the first waiting step, in plan order")
        XCTAssertEqual(TeamBuildCopy.liveLine(p, lang: .en), "Support: Write the FAQ answers")
        XCTAssertEqual(TeamBuildCopy.nextLine(p, lang: .en), "Next: Legal, Check claims and privacy wording")
        XCTAssertEqual(TeamBuildCopy.nextLine(p, lang: .vi), "Tiếp theo: Legal, Check claims and privacy wording")
    }

    /// Up to three steps run at once. The line names the count and the departments, not one title.
    func testSeveralRunningStepsAreCountedNotListed() {
        let p = TeamProgress(run(["s1": .running, "s3": .running]))
        XCTAssertEqual(p.current.count, 2)
        XCTAssertEqual(TeamBuildCopy.liveLine(p, lang: .en), "2 departments working: Support, Legal")
        XCTAssertEqual(TeamBuildCopy.liveLine(p, lang: .vi), "2 phòng ban đang làm: Support, Legal")
    }

    func testWithNothingRunningAndNothingLeftThereIsNoLiveOrNextLine() {
        let p = TeamProgress(run(["s1": .done, "s2": .done, "s3": .done, "build": .done], phase: .ready))
        XCTAssertTrue(p.current.isEmpty)
        XCTAssertNil(p.next)
        XCTAssertNil(TeamBuildCopy.liveLine(p, lang: .en))
        XCTAssertNil(TeamBuildCopy.nextLine(p, lang: .en))
    }

    /// The plan the founder approves must list every step; a failed run must show which step
    /// failed and its retry. Only running, assembling, ready and filed compact.
    func testWhichPhasesCompact() {
        XCTAssertFalse(TeamProgress.compacts(.planned))
        XCTAssertFalse(TeamProgress.compacts(.failed))
        XCTAssertFalse(TeamProgress.compacts(.cancelled))
        XCTAssertTrue(TeamProgress.compacts(.running))
        XCTAssertTrue(TeamProgress.compacts(.assembling))
        XCTAssertTrue(TeamProgress.compacts(.ready))
        XCTAssertTrue(TeamProgress.compacts(.filed))
    }

    func testTheDisclosureNamesTheStepCount() {
        XCTAssertEqual(TeamBuildCopy.allSteps(4, expanded: false, lang: .en), "See all 4 steps")
        XCTAssertEqual(TeamBuildCopy.allSteps(4, expanded: true, lang: .en), "Hide steps")
        XCTAssertEqual(TeamBuildCopy.allSteps(4, expanded: false, lang: .vi), "Xem cả 4 bước")
    }
}
