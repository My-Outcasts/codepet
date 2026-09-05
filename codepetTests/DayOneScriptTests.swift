// codepetTests/DayOneScriptTests.swift
import XCTest
@testable import codepet

/// The script's shape. Content lives in the fixture; what is guarded here is that the sequence
/// asks nine questions, runs nine links and approves all nine.
final class DayOneScriptTests: XCTestCase {

    private var beats: [MockFlowScript.Beat] { DayOneScript.beats }

    /// Link 1 is founder-only, so it is RECORDED, not run. The other eight are run and approved.
    func testItHasOneRecordEightRunsAndEightApprovals() {
        var record = 0, runs = 0, approvals = 0
        for b in beats {
            switch b.intent {
            case .recordFounderTask: record += 1
            case .runTask: runs += 1
            case .approveNewestDraft: approvals += 1
            default: break
            }
        }
        XCTAssertEqual(record, 1, "only `mur-interviews` is the founder's own work")
        XCTAssertEqual(runs, 8, "the other eight links are Codepet runs")
        XCTAssertEqual(approvals, 8, "each run is approved; the record files itself")
    }

    /// **The guard that replaces an assumption.** An earlier draft used `.runBeacon` and trusted
    /// `RoadmapEngine.nextStep` to follow the dependency chain. It does not — it sorts every
    /// dependency-satisfied open task by (phase order, array position), and simulated against
    /// the real fixture it drifted to `mur-pricing` at step 3. The script now names its ids, and
    /// this pins them to the chain so the two cannot diverge.
    func testTheScriptRunsExactlyTheDayOneChain() {
        var acted: [String] = []
        for b in beats {
            switch b.intent {
            case .recordFounderTask(let id, _): acted.append(id)
            case .runTask(let id): acted.append(id)
            default: break
            }
        }
        XCTAssertEqual(acted, DemoProject.dayOneChain,
                       "the script's order must BE the chain, not resemble it")
    }

    /// Every run beat must be followed by its approval before the next link runs — otherwise the
    /// next department reads an unfiled predecessor and its credit line comes back empty.
    func testEveryRunIsApprovedBeforeTheNextRun() {
        var awaitingApproval = false
        for b in beats {
            switch b.intent {
            case .runTask(let id):
                XCTAssertFalse(awaitingApproval, "a run started before \(id)'s predecessor was approved")
                awaitingApproval = true
            case .approveNewestDraft:
                awaitingApproval = false
            default: break
            }
        }
        XCTAssertFalse(awaitingApproval, "the last run is never approved")
    }

    /// A beat whose intent has no handler is a silent no-op — it plays as a caption over a
    /// screen where nothing happens, and nothing fails.
    func testEveryIntentUsedHasAHandler() {
        let handled: Set<String> = ["hold", "mode", "go", "newChat", "say", "runBeacon",
                                    "approveNewestDraft", "convene", "linkDemoFolder",
                                    "codeRun", "confirmCodeRun", "approveCodeRun",
                                    "walkthroughFounderTask", "recordFounderTask", "runTask"]
        for b in beats {
            let name = String(describing: b.intent).prefix(while: { $0 != "(" })
            XCTAssertTrue(handled.contains(String(name)),
                          "`\(name)` has no case in MockFlowPlayer")
        }
    }

    /// Each link needs long enough to read a question and watch a run. Measured: a run is
    /// ~6 exec steps at 420ms plus a 260ms settle.
    func testEveryRunBeatIsLongEnoughToWatch() {
        for b in beats where isRun(b.intent) {
            XCTAssertGreaterThanOrEqual(b.seconds, 2.6,
                                        "a run beat shorter than the run itself cuts it off")
        }
    }

    /// It must stay watchable. The 24-beat tour holds a 100s ceiling for the same reason.
    func testTheWholeSequenceStaysUnderNinetySeconds() {
        let total = beats.reduce(0) { $0 + $1.seconds }
        XCTAssertLessThan(total, 90, "a \(Int(total))s simulation is one nobody watches twice")
        XCTAssertGreaterThan(total, 30, "nine links cannot honestly play in under 30s")
    }

    /// The opening must be the founder's own words, not a feature tour.
    func testItOpensOnNotKnowingWhereToStart() throws {
        let first = try XCTUnwrap(beats.first)
        XCTAssertTrue(first.caption.lowercased().contains("where to start"),
                      "the opening states the problem this simulation exists for: \(first.caption)")
    }

    /// The ending hands the next move back rather than taking it.
    func testItEndsPointingAtTheLandingPage() throws {
        let last = try XCTUnwrap(beats.last)
        XCTAssertTrue(last.caption.lowercased().contains("landing page"),
                      "the bridge to the tour must be named: \(last.caption)")
    }

    private func isRun(_ i: MockFlowScript.Intent) -> Bool {
        if case .runTask = i { return true }
        return false
    }
}
