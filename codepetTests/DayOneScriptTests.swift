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
            case .recordFounderTask(let id): acted.append(id)
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

    /// Replaces a vacuous `testEveryIntentUsedHasAHandler`, which stringified each beat's intent
    /// name and checked it against a hardcoded set of handler names it never derived from
    /// `MockFlowPlayer` — a check against itself. `Intent` is an enum and the player's `switch`
    /// has no `default:`, so a genuinely unhandled case is a COMPILE error; that test could never
    /// fail.
    ///
    /// The real, silent version of that hazard is a typo'd task id. `.runTask` and
    /// `.recordFounderTask` both carry a raw `String` id looked up with `first(where:)` — a
    /// mistyped id (`"mur-stakc"` for `"mur-stack"`) fails that lookup and returns without doing
    /// anything or reporting anything. The beat's caption plays over a screen where nothing
    /// happened. This test is what would go red for that typo.
    func testEveryActedOnTaskIdResolvesToARealTask() {
        let boardIds = Set(DemoProject.murrorDayOne.tasks.map(\.id))
        for b in beats {
            switch b.intent {
            case .runTask(let id):
                XCTAssertTrue(boardIds.contains(id),
                              "`.runTask(\"\(id)\")` in chapter '\(b.chapter)' does not match any "
                              + "task on the day-one board — the beat would silently do nothing")
            case .recordFounderTask(let id):
                XCTAssertTrue(boardIds.contains(id),
                              "`.recordFounderTask(\"\(id)\")` in chapter '\(b.chapter)' does "
                              + "not match any task on the day-one board")
            default: break
            }
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

    /// Every department opens its own segment. Eight departments, and Marketing opens once
    /// even though it holds two links.
    func testEachDepartmentIsOpenedByItsOwnPet() {
        var asked: [String] = []
        for b in beats {
            if case let .petAsks(deptKey) = b.intent {
                asked.append(deptKey)
                XCTAssertNotNil(DepartmentCompanions.companionId(for: deptKey),
                                "\(deptKey) has no pet, so nobody can ask its question")
            }
        }
        XCTAssertEqual(asked.count, 8, "no department opens twice")
        XCTAssertEqual(Set(asked), Set(["mkt", "sales", "design", "eng", "fin", "support", "legal", "ops"]))
    }

    /// A pet asks BEFORE its link runs, never after.
    func testThePetAsksBeforeTheWorkItIntroduces() {
        var seenAsk = Set<String>()
        for b in beats {
            switch b.intent {
            case let .petAsks(deptKey): seenAsk.insert(deptKey)
            case let .runTask(id):
                let dept = DemoProject.murrorDayOne.tasks.first { $0.id == id }?.dept
                XCTAssertTrue(dept.map(seenAsk.contains) ?? false,
                              "\(id) runs before its department was introduced")
            default: break
            }
        }
    }

    /// Both languages, for every department that asks. An English question inside a chat
    /// bubble in a bilingual app is the finding that was raised about the credit line on 5 Sep.
    func testEveryQuestionExistsInBothLanguages() {
        for b in beats {
            guard case let .petAsks(deptKey) = b.intent else { continue }
            for lang in [AppLanguage.en, AppLanguage.vi] {
                let q = DayOneScript.question(for: deptKey, language: lang)
                XCTAssertNotNil(q, "\(deptKey) has no question in \(lang)")
                XCTAssertFalse(q?.isEmpty ?? true, "\(deptKey)'s \(lang) question is empty")
            }
        }
    }

    /// The two languages must not be the same string — a copy-paste that leaves English
    /// in the vi slot passes a non-empty check and ships English to a Vietnamese founder.
    func testTheTwoLanguagesActuallyDiffer() {
        for (deptKey, pair) in DayOneScript.questions {
            XCTAssertNotEqual(pair.en, pair.vi, "\(deptKey) has the same text in both languages")
        }
    }
}
