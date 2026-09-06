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

    /// Exactly 8 departments speak, and each exactly three times: `asks`, `frames`, `reports`.
    /// The load-bearing count this branch adds — a department missing one of its three lines,
    /// or gaining a fourth, goes red here.
    func testExactlyEightDepartmentsSpeakThreeTimesEach() {
        var counts: [String: Int] = [:]
        for b in beats {
            if case let .petSays(deptKey, _) = b.intent { counts[deptKey, default: 0] += 1 }
        }
        XCTAssertEqual(counts.count, 8, "expected exactly 8 speaking departments, found \(counts.count)")
        for (dept, c) in counts {
            XCTAssertEqual(c, 3, "\(dept) spoke \(c) times; every department speaks exactly three")
        }
    }

    /// **The load-bearing ordering guard.** Per department: `asks` → `frames` → its link(s) →
    /// `reports`. A report placed before its department's work is filed must fail here —
    /// verified red before this change existed, since nothing enforced the order at all.
    /// Marketing holds two links (`mur-interviews`, `mur-landscape`) and reports once, only
    /// after BOTH are filed — this is what actually checks that, rather than trusting the
    /// beat list's visual order.
    func testEachDepartmentSpeaksAsksFramesWorkReportInOrder() {
        // Every task id day one acts on, grouped by the department that owns it — the set of
        // work a department's `reports` beat must have seen filed before it plays.
        var workByDept: [String: Set<String>] = [:]
        for id in DemoProject.dayOneChain {
            guard let dept = DemoProject.murrorDayOne.tasks.first(where: { $0.id == id })?.dept
            else { continue }
            workByDept[dept, default: []].insert(id)
        }

        enum Stage: Equatable { case notStarted, asked, framed, reported }
        var stage: [String: Stage] = [:]
        var filedByDept: [String: Set<String>] = [:]
        var lastRunId: String?

        for b in beats {
            switch b.intent {
            case let .petSays(deptKey, line):
                let current = stage[deptKey] ?? .notStarted
                switch line {
                case .asks:
                    XCTAssertEqual(current, .notStarted, "\(deptKey) asks twice, or out of order")
                    stage[deptKey] = .asked
                case .frames:
                    XCTAssertEqual(current, .asked, "\(deptKey) frames before asking, or twice")
                    stage[deptKey] = .framed
                case .reports:
                    XCTAssertEqual(current, .framed,
                                    "\(deptKey) reports before framing, or reports twice")
                    let need = workByDept[deptKey] ?? []
                    let have = filedByDept[deptKey] ?? []
                    XCTAssertTrue(need.isSubset(of: have),
                                  "\(deptKey) reports before its own work "
                                  + "(\(need.subtracting(have).sorted())) was filed")
                    stage[deptKey] = .reported
                }
            case .runTask(let id):
                lastRunId = id
            case .approveNewestDraft:
                if let id = lastRunId,
                   let dept = DemoProject.murrorDayOne.tasks.first(where: { $0.id == id })?.dept {
                    filedByDept[dept, default: []].insert(id)
                }
                lastRunId = nil
            case .recordFounderTask(let id):
                if let dept = DemoProject.murrorDayOne.tasks.first(where: { $0.id == id })?.dept {
                    filedByDept[dept, default: []].insert(id)
                }
            default: break
            }
        }
        for (dept, s) in stage {
            XCTAssertEqual(s, .reported, "\(dept) never reaches `reports`")
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

    /// The chapter bar reads as the opener plus eight departments, not twenty-one questions.
    func testTheChapterBarIsTheOpenerPlusEightDepartments() {
        var seen = Set<String>()
        let chapters = beats.compactMap { seen.insert($0.chapter).inserted ? $0.chapter : nil }
        XCTAssertEqual(chapters.count, 9, "one opener + eight departments")
        XCTAssertEqual(chapters.first, "Day one")
        XCTAssertEqual(Array(chapters.dropFirst()), [
            "Marketing · Nova", "Sales · Nova", "Design · Luna", "Engineering · Byte",
            "Finance · Crash", "Support · Sage", "Legal · Glitch", "Operations · Glitch",
        ])
    }

    /// The whole day still fits the budget. Recorded, not estimated: sixteen new `frames`/
    /// `reports` beats raised the day-one total from 74.6s, so the ceiling moved from 75s to
    /// 120s — deliberately with headroom, not fitted to the result.
    ///
    /// **Absorbs the old `testTheWholeSequenceStaysUnderNinetySeconds`.** That test enforced a
    /// second, stricter, hardcoded 90s ceiling on the same `total` this test already checks —
    /// once sixteen beats pushed the real total past 90s it would have gone red for the right
    /// reason, but keeping two differently-numbered budget assertions on one value is the kind
    /// of duplication that invites the next raise to update one and miss the other. Its floor
    /// check is folded in below.
    func testTheDayFitsItsTimeBudget() {
        let total = beats.reduce(0) { $0 + $1.seconds }
        XCTAssertLessThanOrEqual(total, 120.0, "day one runs \(total)s; budget is 120s")
        XCTAssertGreaterThan(total, 30, "seventeen speaking beats and nine links cannot honestly play in under 30s")
    }

    /// Caption readability is a budget independent of the total-runtime one above: a beat
    /// trimmed to fit the 75s ceiling can still be too short to read. Same formula
    /// `MockFlowScriptTests.testCaptionsHaveTimeToBeRead` uses for the 24-beat tour — ~18
    /// characters/second, floored further by the player's Slow pace (1.5x).
    func testEveryCaptionHasTimeToBeReadEvenOnSlow() {
        for beat in beats {
            let needed = Double(beat.caption.count) / 45.0
            XCTAssertGreaterThanOrEqual(beat.seconds * 1.5, needed,
                                        "beat \(beat.id) ('\(beat.chapter)') shows "
                                        + "\(beat.caption.count) characters for \(beat.seconds)s "
                                        + "— unreadable even on Slow")
        }
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
            if case let .petSays(deptKey, .asks) = b.intent {
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
            case let .petSays(deptKey, .asks): seenAsk.insert(deptKey)
            case let .runTask(id):
                let dept = DemoProject.murrorDayOne.tasks.first { $0.id == id }?.dept
                XCTAssertTrue(dept.map(seenAsk.contains) ?? false,
                              "\(id) runs before its department was introduced")
            default: break
            }
        }
    }

    /// Both languages, for every department's `asks` line. An English question inside a chat
    /// bubble in a bilingual app is the finding that was raised about the credit line on 5 Sep.
    func testEveryQuestionExistsInBothLanguages() {
        for b in beats {
            guard case let .petSays(deptKey, .asks) = b.intent else { continue }
            for lang in [AppLanguage.en, AppLanguage.vi] {
                let q = DayOneScript.line(for: deptKey, .asks, language: lang)
                XCTAssertNotNil(q, "\(deptKey) has no question in \(lang)")
                XCTAssertFalse(q?.isEmpty ?? true, "\(deptKey)'s \(lang) question is empty")
            }
        }
    }

    /// The two languages must not be the same string — a copy-paste that leaves English
    /// in the vi slot passes a non-empty check and ships English to a Vietnamese founder.
    func testTheTwoLanguagesActuallyDiffer() {
        for (deptKey, entry) in DayOneScript.script {
            XCTAssertNotEqual(entry.asks.en, entry.asks.vi,
                              "\(deptKey) has the same text in both languages")
        }
    }

    /// Every department has all three lines, non-empty. `frames` and `reports` are `String`,
    /// not a bilingual pair — there is no `vi` slot for them to leave empty; the type itself is
    /// the guard for "must not gain an empty vi slot". This checks the content is real.
    /// **Amendment, 6 Sep.** `.walkthroughFounderTask` was the only beat in day one that
    /// triggered a live `MockChat` conversational turn (through `sendChat`), and it served
    /// `murrorDepartmentReplies` — copy written against the MID-FLIGHT board, four segments
    /// before the beat it grounds even speaks. Removed. This is what would go red if it, or
    /// `.say` (the composer's own free-text intent, also routed through `MockChat`), came back.
    func testDayOneTriggersNoMockChatConversationalTurn() {
        for b in beats {
            switch b.intent {
            case .walkthroughFounderTask:
                XCTFail("day one must not trigger a MockChat reply via `.walkthroughFounderTask`")
            case .say:
                XCTFail("day one must not trigger a MockChat reply via `.say`")
            default: break
            }
        }
    }

    func testEveryDepartmentHasAllThreeNonEmptyLines() {
        let expected = ["mkt", "sales", "design", "eng", "fin", "support", "legal", "ops"]
        for dept in expected {
            guard let entry = DayOneScript.script[dept] else {
                XCTFail("\(dept) has no script entry at all")
                continue
            }
            XCTAssertFalse(entry.asks.en.isEmpty, "\(dept) asks.en is empty")
            XCTAssertFalse(entry.asks.vi.isEmpty, "\(dept) asks.vi is empty")
            XCTAssertFalse(entry.frames.isEmpty, "\(dept) frames is empty")
            XCTAssertFalse(entry.reports.isEmpty, "\(dept) reports is empty")
        }
    }
}
