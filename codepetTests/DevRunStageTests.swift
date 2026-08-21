// codepetTests/DevRunStageTests.swift
import XCTest
@testable import codepet

/// Guards on Developer's phase router.
///
/// These exist because of a specific bug: the work pane drew three of the eight
/// phases and nothing in Developer ever called `execute()`, so a proposed run
/// reached `.previewing` and stayed there — header reading `PREPARING`, no steps,
/// no diff, no error. It looked like a slow run. It was a dead end, and the only
/// reason it surfaced is that a human watched the walkthrough and said the demo did
/// not work.
final class DevRunStageTests: XCTestCase {

    /// **Every phase draws something.** A phase with no body is a screen that stops
    /// responding, and there is no signal when one is added — this is the assertion
    /// that turns "nobody wired the new phase" into a red test.
    func testEveryPhaseHasAStage() {
        let phases: [EditCodePhase] = [
            .noProject, .previewing, .readyToRun, .running,
            .reviewing, .committed, .discarded, .failed("nope"),
        ]
        var stages: [DevRunStage] = []
        for phase in phases {
            let stage = DevRunStage.stage(for: phase)
            XCTAssertNotEqual(stage, .idle,
                              "\(phase) falls through to the no-run body — it would draw nothing")
            stages.append(stage)
        }
        // `.readyToRun` and `.running` share a body deliberately (both are "it is
        // working"); nothing else may collapse, or a phase is being drawn as another.
        XCTAssertEqual(Set(stages).count, phases.count - 1)
    }

    func testNoRunIsIdle() {
        XCTAssertEqual(DevRunStage.stage(for: nil), .idle)
    }

    /// **The distinction the whole plan-preview exists for.** `.readyToRun` means the
    /// planner judged the change small enough that the diff review IS the gate.
    /// `.previewing` is the opposite judgement — multi-file, or it needs a shell — and
    /// starting it unasked would execute a plan the founder was shown but never
    /// agreed to. One character apart in a view; a deleted guard here goes red.
    func testOnlyReadyToRunStartsItself() {
        XCTAssertTrue(DevRunStage.startsItself(.readyToRun))
        for phase: EditCodePhase in [.previewing, .running, .reviewing, .committed,
                                     .discarded, .noProject, .failed("x")] {
            XCTAssertFalse(DevRunStage.startsItself(phase),
                           "\(phase) would start a run nobody asked to start")
        }
        XCTAssertFalse(DevRunStage.startsItself(nil))
    }

    /// The failure reason has to reach the body, not be flattened to "it failed" —
    /// the run card's whole job in that state is to say what went wrong.
    func testAFailureCarriesItsReason() {
        XCTAssertEqual(DevRunStage.stage(for: .failed("claude is not installed")),
                       .failed("claude is not installed"))
    }

    /// The gate is reachable only from `.reviewing`. If any other phase mapped to
    /// `.gate`, Approve would be offered over a run with no diffs behind it.
    func testOnlyReviewingOpensTheGate() {
        let gated: [EditCodePhase] = [.noProject, .previewing, .readyToRun, .running,
                                      .committed, .discarded, .failed("x")]
        for phase in gated {
            XCTAssertNotEqual(DevRunStage.stage(for: phase), .gate)
        }
        XCTAssertEqual(DevRunStage.stage(for: .reviewing), .gate)
    }
}
