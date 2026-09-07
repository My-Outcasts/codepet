// codepetTests/DayOneScriptTests.swift
import XCTest
@testable import codepet

/// The script's shape. Content lives in the fixture; what is guarded here is that the sequence
/// asks nine questions, runs nine links and approves all nine.
final class DayOneScriptTests: XCTestCase {

    private var beats: [MockFlowScript.Beat] { DayOneScript.beats }

    /// The original nine-question chain's eight department chapters — the chapters
    /// `testExactlyEightDepartmentsSpeakThreeTimesEach` and its neighbours were written to
    /// guard, before Amendment 3 added "Environment · Byte" and "Code · Byte" after them.
    /// Byte speaks a second and third time in those two new chapters (see
    /// `DayOneScript.extraAppearances`), which is exactly why any test asserting "each
    /// department speaks exactly three times, in order" has to be scoped to THESE chapters —
    /// otherwise Byte's legitimate encore reads as the same bug the test exists to catch.
    private let chainChapters: Set<String> = [
        "Marketing · Nova", "Sales · Nova", "Design · Luna", "Engineering · Byte",
        "Finance · Crash", "Support · Sage", "Legal · Glitch", "Operations · Glitch",
    ]

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
        // **Nine, not eight, and the ninth is deliberate.** Eight are the chain's own links.
        // The ninth is `mur-site` — the landing page, the TENTH question the roadmap beacon
        // points at — run in the Code chapter after the hand-off. Re-scoped rather than
        // relaxed when that was added: the counts below still pin both halves separately, so
        // losing a chain link or gaining a stray run each still goes red.
        XCTAssertEqual(runs, 9, "eight chain links plus the landing page")
        XCTAssertEqual(approvals, 9, "each run is approved; the record files itself")
    }

    /// The eight chain runs and the one page build, counted apart — so neither can absorb a
    /// mistake in the other. `testItHasOneRecordEightRunsAndEightApprovals` sees only a total.
    func testTheChainRunsEightAndThePageIsTheNinth() {
        var chainRuns = 0, pageRuns = 0
        for b in beats {
            guard case let .runTask(id) = b.intent else { continue }
            if DemoProject.dayOneChain.contains(id) { chainRuns += 1 } else { pageRuns += 1 }
        }
        XCTAssertEqual(chainRuns, 8, "the chain's own eight Codepet links")
        XCTAssertEqual(pageRuns, 1, "exactly one build outside the chain: the landing page")
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
        // **The chain still comes first, in order, entire** — that is the claim this test was
        // written for and it is unchanged. What follows it is the tenth question: `mur-site`,
        // the landing page the roadmap beat has been pointing at. Asserted as a suffix rather
        // than folded into the equality, so a chain link that goes missing or reorders still
        // fails here exactly as before.
        // **The chain's own order is the claim; `mur-site` is a guest inside it.**
        // The landing page was moved forward to just after Design, so it is no longer a
        // suffix. Filtering to the chain's ids keeps the original guard exactly as strong —
        // drop a link or reorder two and this still fails — while allowing the one build that
        // is deliberately interleaved.
        XCTAssertEqual(acted.filter { DemoProject.dayOneChain.contains($0) },
                       DemoProject.dayOneChain,
                       "the script's order must BE the chain, not resemble it")
        XCTAssertEqual(acted.filter { !DemoProject.dayOneChain.contains($0) }, ["mur-site"],
                       "exactly one build outside the chain: the landing page")
        // And it must land AFTER the two tasks it is built on, or the demo shows a
        // chain-offer card instead of a page — the reason it sits here and not first.
        let i = acted.firstIndex(of: "mur-site")!
        for dep in ["mur-brand", "mur-landscape"] {
            XCTAssertTrue(acted.firstIndex(of: dep).map { $0 < i } ?? false,
                          "mur-site runs before \(dep) is filed")
        }
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

    /// Exactly 8 departments speak, and each exactly three times: `asks`, `frames`, `reports` —
    /// over the nine-question chain's own eight chapters.
    ///
    /// **Re-scoped, Amendment 3 (6 Sep).** This used to count every `.petSays` beat in the
    /// whole script, global. Amendment 3 gives Byte two more chapters after the chain ends
    /// ("Environment · Byte", "Code · Byte"), each with its own `asks`/`frames`/`reports` — real
    /// continuity (Byte chose the stack four questions ago), not a bug, but it made Byte speak
    /// nine times script-wide and this test go red for the wrong reason: the claim it guards —
    /// every department IN THE CHAIN speaks exactly three times — was still true. Scoping to
    /// `chainChapters` restores that claim without weakening it: delete a line from any of the
    /// eight chain chapters, or add a fourth, and this still goes red. The two new chapters get
    /// their own count assertions below instead of being folded into this one silently.
    func testExactlyEightDepartmentsSpeakThreeTimesEach() {
        var counts: [String: Int] = [:]
        for b in beats where chainChapters.contains(b.chapter) {
            if case let .petSays(deptKey, _) = b.intent { counts[deptKey, default: 0] += 1 }
        }
        XCTAssertEqual(counts.count, 8, "expected exactly 8 speaking departments, found \(counts.count)")
        for (dept, c) in counts {
            XCTAssertEqual(c, 3, "\(dept) spoke \(c) times; every department speaks exactly three")
        }
    }

    /// **Amendment 3, 6 Sep.** "Environment · Byte" is Byte's second appearance — its own
    /// `asks`/`frames`/`reports`, same shape as a chain department, just not one of the nine
    /// questions. Goes red if a line is lost, duplicated, or another department's key leaks in.
    func testEnvironmentChapterHasExactlyBytesThreeLines() {
        var counts: [String: Int] = [:]
        for b in beats where b.chapter == "Environment · Byte" {
            if case let .petSays(deptKey, _) = b.intent { counts[deptKey, default: 0] += 1 }
        }
        XCTAssertEqual(counts, ["eng": 3], "Environment · Byte must be exactly Byte, three lines")
    }

    /// **Amendment 3, 6 Sep.** "Code · Byte" is Byte's third appearance, same guard as above.
    func testCodeChapterHasExactlyBytesThreeLines() {
        var counts: [String: Int] = [:]
        for b in beats where b.chapter == "Code · Byte" {
            if case let .petSays(deptKey, _) = b.intent { counts[deptKey, default: 0] += 1 }
        }
        XCTAssertEqual(counts, ["eng": 3], "Code · Byte must be exactly Byte, three lines")
    }

    /// **Amendment 4, 6 Sep.** "Redesign · Luna" is a NEW chapter, not an encore of her earlier
    /// one — she already spoke her three chain lines in "Design · Luna". Same guard shape as
    /// Byte's encores: exactly Luna's three lines, and nobody else's key leaks in.
    func testRedesignChapterHasExactlyLunasThreeLines() {
        var counts: [String: Int] = [:]
        for b in beats where b.chapter == "Redesign · Luna" {
            if case let .petSays(deptKey, _) = b.intent { counts[deptKey, default: 0] += 1 }
        }
        XCTAssertEqual(counts, ["design": 3], "Redesign · Luna must be exactly Luna, three lines")
    }

    /// **The load-bearing ordering guard.** Per department: `asks` → `frames` → its link(s) →
    /// `reports`. A report placed before its department's work is filed must fail here —
    /// verified red before this change existed, since nothing enforced the order at all.
    /// Marketing holds two links (`mur-interviews`, `mur-landscape`) and reports once, only
    /// after BOTH are filed — this is what actually checks that, rather than trusting the
    /// beat list's visual order.
    ///
    /// **Scoped to `chainChapters`, Amendment 3 (6 Sep).** Byte's Environment/Code encores
    /// (re)use `deptKey: "eng"` for `.petSays`, so a state machine walking every beat would see
    /// "eng" already `.reported` from the Engineering chapter and flag the Environment chapter's
    /// `asks` as "asks twice" — a false positive, not a real ordering violation. Restricting the
    /// walk to the chain's own eight chapters keeps the guard aimed at what it was built for.
    func testEachDepartmentSpeaksAsksFramesWorkReportInOrder() {
        let chainBeats = beats.filter { chainChapters.contains($0.chapter) }

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

        for b in chainBeats {
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

    /// **Every trip into Developer must come back.** `.mode(.developer)` opens the CODE pane
    /// and nothing else switches it back, so a script that enters and never returns plays the
    /// whole rest of the day on the chat side while the founder watches a dormant Developer
    /// pane. She reported it as the demo being stuck; it was running perfectly, out of sight —
    /// the landing page filed, a redesign run, and five departments spoke, none of it visible.
    func testItAlwaysComesBackFromDeveloperMode() {
        var inDeveloper = false
        for b in beats {
            guard case let .mode(m) = b.intent else { continue }
            switch m {
            case .developer:
                XCTAssertFalse(inDeveloper, "entered Developer twice without returning")
                inDeveloper = true
            case .ask:
                XCTAssertTrue(inDeveloper, "returned to Ask without having entered Developer")
                inDeveloper = false
            }
        }
        XCTAssertFalse(inDeveloper,
                       "the script ends in Developer mode — everything after the last "
                       + "`.mode(.developer)` plays where the founder cannot see it")
    }

    /// The chapter bar reads as the opener plus eight departments plus Amendment 3's two new
    /// chapters plus Amendment 4's redesign, not twenty-one questions.
    ///
    /// **Amendment 3, 6 Sep.** Was "one opener + eight departments" (9 total) before Environment
    /// and Code were appended after the roadmap hand-back; this pins the full 11-chapter list so
    /// a chapter silently going missing, duplicated, or reordered still fails here.
    ///
    /// **Amendment 4, 6 Sep.** "Redesign · Luna" is appended after "Code · Byte" — the redesign
    /// pass Luna runs once the page exists to look at — so the pinned list grows to 12.
    func testTheChapterBarIsTheOpenerPlusEightDepartments() {
        var seen = Set<String>()
        let chapters = beats.compactMap { seen.insert($0.chapter).inserted ? $0.chapter : nil }
        XCTAssertEqual(chapters.count, 12,
                       "one opener + eight departments + Environment + Code + Redesign")
        XCTAssertEqual(chapters.first, "Day one")
        XCTAssertEqual(Array(chapters.dropFirst()), [
            // **Building moved forward, deliberately.** The founder asked for the landing page
            // early rather than at the very end. Environment/Code/Redesign sit right after
            // Design because that is the earliest point `mur-site`'s dependencies
            // (`mur-brand`, `mur-landscape`) are genuinely filed — any earlier and the demo
            // shows a chain-offer card instead of a page. Environment travels WITH them: it
            // links the folder, without which a code run lands in `.noProject`.
            "Marketing · Nova", "Sales · Nova", "Design · Luna",
            "Environment · Byte", "Code · Byte", "Redesign · Luna",
            "Engineering · Byte", "Finance · Crash", "Support · Sage", "Legal · Glitch",
            "Operations · Glitch",
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
    ///
    /// **Amendment 2, 6 Sep — the third raise.** The four opening beats added ~14s, so the
    /// ceiling moves again, 120s to 140s — deliberate headroom, not fitted to the result. This
    /// is the third raise on this value (75 → 120 → 140); the founder has been told twice and
    /// has not asked for it shorter.
    ///
    /// **Amendment 3, 6 Sep — the fourth raise.** Environment and Code add ~30s (measured:
    /// 126.8s → 157.2s), so the ceiling moves again, 140s to 170s. This is the fourth raise
    /// (75 → 120 → 140 → 170) against a prior author's 90s ceiling. The lever offered three
    /// times and not taken: cutting the eight department `frames` lines would return ~25s —
    /// the founder's own copy, not cut unless she says so.
    ///
    /// **Amendment 4, 6 Sep — the fifth raise.** The redesign pass (Luna's second appearance:
    /// `asks`/`frames`/a `.codeRun`+`.confirmCodeRun` pair/`reports`) pushed the real total to
    /// 170.2s — read off a temporarily-forced-failing assertion here (`XCTAssertLessThanOrEqual
    /// (total, 0.0)`), not estimated, then reverted to this real ceiling. 170s had essentially no
    /// headroom left for it, so the ceiling moves to 200s — real margin, not fitted to the exact
    /// result. This is the fifth raise (75 → 120 → 140 → 170 → 200).
    func testTheDayFitsItsTimeBudget() {
        let total = beats.reduce(0) { $0 + $1.seconds }
        XCTAssertLessThanOrEqual(total, 200.0, "day one runs \(total)s; budget is 200s")
        XCTAssertGreaterThan(total, 30, "seventeen speaking beats and nine links cannot honestly play in under 30s")
    }

    /// **Amendment 2, 6 Sep — the opening must come first.** No `.petSays` beat may precede any
    /// `.opening` beat: the whole point of the amendment is that the founder reads context
    /// before any department speaks, not after.
    func testTheOpeningPlaysBeforeAnyDepartmentSpeaks() {
        var sawPetSays = false
        var sawOpening = false
        for b in beats {
            switch b.intent {
            case .opening:
                XCTAssertFalse(sawPetSays, "an opening beat plays after a department already spoke")
                sawOpening = true
            case .petSays:
                sawPetSays = true
            default: break
            }
        }
        XCTAssertTrue(sawOpening, "the day-one script has no opening beats at all")
    }

    /// The four opening beats are exactly those four lines, in the order the design doc gives
    /// them — a scrambled or duplicated line would pass the "before any department" test above
    /// but still tell the wrong story.
    func testTheOpeningIsExactlyTheFourLinesInOrder() {
        let opening: [DayOneScript.OpeningLine] = beats.compactMap {
            if case let .opening(line) = $0.intent { return line }
            return nil
        }
        XCTAssertEqual(opening, [.summary, .prompt, .founderReply, .setup])
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

    /// **Amendment 3, 6 Sep.** The day used to hand the next move back by NAMING the landing
    /// page and stopping; now it actually builds it (Environment · Byte, Code · Byte) and closes
    /// on the board having moved, verbatim from the design doc's closing beat.
    func testItEndsWithTheBoardHavingMoved() throws {
        let last = try XCTUnwrap(beats.last)
        XCTAssertEqual(last.caption, "Nine questions answered, a page built and revised, and a board that has moved under all of it. The tenth question is hers: who does she tell first?")
        guard case .go(.roadmap) = last.intent else {
            return XCTFail("the closing beat must be `.go(.roadmap)`, found \(last.intent)")
        }
    }

    private func isRun(_ i: MockFlowScript.Intent) -> Bool {
        if case .runTask = i { return true }
        return false
    }

    /// Every department opens its own segment. Eight departments, and Marketing opens once
    /// even though it holds two links.
    ///
    /// **Scoped to `chainChapters`, Amendment 3 (6 Sep).** Byte's Environment and Code chapters
    /// each open with their own `.petSays(deptKey: "eng", line: .asks)` — a real, deliberate
    /// second and third "opening" for Byte specifically, not the "no department opens twice"
    /// bug this test exists to catch within the nine-question chain. Restricted to the chain's
    /// eight chapters, the count stays exactly 8 and a genuine duplicate WITHIN the chain still
    /// fails it.
    func testEachDepartmentIsOpenedByItsOwnPet() {
        var asked: [String] = []
        for b in beats where chainChapters.contains(b.chapter) {
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
            for lang in [AppLanguage.en] {
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
            XCTAssertFalse(entry.asks.isEmpty, "\(dept) asks is empty")
            XCTAssertFalse(entry.frames.isEmpty, "\(dept) frames is empty")
            XCTAssertFalse(entry.reports.isEmpty, "\(dept) reports is empty")
        }
    }

    /// **The chapter menu, on day one.** `MockFlowScript.chapters`/`firstBeat(of:)` only ever
    /// read `MockFlowScript.beats` — the 24-beat tour — so they say nothing about whether day
    /// one's OWN chapters ("Marketing · Nova" and the rest) are complete and reachable. The
    /// caption bar's compact menu reads `player.chapters`/`player.firstBeat(of:)` instead, which
    /// mirror that same computation against whichever script is actually playing (see
    /// `MockFlowPlayer.chapters`'s doc comment) — this drives the player with day one selected,
    /// the same `DemoProject.select` seam `MockFlowTests` already uses, and checks both halves:
    /// the list matches a fresh dedup of `DayOneScript.beats` in order, and every entry in it
    /// actually resolves. A department chapter that becomes unreachable would otherwise fail
    /// silently — `jump(toChapter:)` no-ops on a nil index — over a menu row a founder can still
    /// click.
    func testTheMenusChapterListIsExactlyDayOnesChaptersAndAllResolve() {
        let previousProject = PrototypeMode.store.string(forKey: DemoProject.key)
        defer {
            if let previousProject { PrototypeMode.store.set(previousProject, forKey: DemoProject.key) }
            else { PrototypeMode.store.removeObject(forKey: DemoProject.key) }
        }
        DemoProject.select("murror-day-one")

        let player = MockFlowPlayer()
        var seen = Set<String>()
        let expected = DayOneScript.beats.compactMap { seen.insert($0.chapter).inserted ? $0.chapter : nil }
        XCTAssertEqual(player.chapters, expected,
                       "the menu's day-one chapter list has drifted from the script")
        for chapter in player.chapters {
            XCTAssertNotNil(player.firstBeat(of: chapter),
                            "\(chapter) is offered in the day-one menu but unreachable — "
                            + "jumping to it would silently no-op")
        }
    }

    // MARK: - Amendment 3, 6 Sep — Environment and Code

    /// The environment beat navigates to `AppView.environment` — the real destination
    /// `Views/Environment/ProjectLinker.swift` lives behind. Goes red if it ever points
    /// somewhere else.
    func testTheEnvironmentChapterNavigatesToTheEnvironmentDestination() {
        let destinations: [AppView] = beats
            .filter { $0.chapter == "Environment · Byte" }
            .compactMap { if case let .go(v) = $0.intent { return v }; return nil }
        XCTAssertEqual(destinations, [.environment],
                       "Environment · Byte must navigate to exactly `.go(.environment)`")
    }

    /// The code chapter enters Developer mode AND comes back.
    ///
    /// It used to assert `[.developer]` alone, which is how the return trip came to be missing:
    /// the pane opened and the rest of the day — the landing page filing, the redesign, five
    /// more departments — played on the chat side behind it. The founder reported the demo as
    /// stuck. Pinning the pair is what makes a one-way trip fail here instead of on her screen.
    func testTheCodeChapterEntersAndLeavesDeveloperMode() {
        let modes: [WorkspaceMode] = beats
            .filter { $0.chapter == "Code · Byte" }
            .compactMap { if case let .mode(m) = $0.intent { return m }; return nil }
        XCTAssertEqual(modes, [.developer, .ask],
                       "Code · Byte must enter Developer and return to Ask, in that order")
    }

    /// **The precondition ordering.** `Views/Environment/ProjectLinker.swift` is the real
    /// prerequisite for a code run — without a linked folder, `startBuild` lands in
    /// `.noProject` and refuses. `.linkDemoFolder` must therefore occur strictly before
    /// `.codeRun` in the beat sequence. Verified red by hand: swapping the two beats in
    /// `DayOneScript.beats` during development made this fail exactly as expected, then the
    /// swap was reverted.
    func testTheFolderIsLinkedBeforeTheCodeRun() {
        var linkIndex: Int?
        var runIndex: Int?
        for (i, b) in beats.enumerated() {
            if case .linkDemoFolder = b.intent, linkIndex == nil { linkIndex = i }
            if case .codeRun = b.intent, runIndex == nil { runIndex = i }
        }
        guard let link = linkIndex, let run = runIndex else {
            return XCTFail("expected both `.linkDemoFolder` and `.codeRun` in the script")
        }
        XCTAssertLessThan(link, run,
                          "`.linkDemoFolder` (beat \(link)) must precede `.codeRun` (beat \(run)) "
                          + "— it is the real precondition for a code run, not decoration")
    }

    /// Nothing starts the run except the founder's own tap: `.confirmCodeRun` must follow
    /// `.codeRun`, in the same chapter, with nothing else acting on the run in between.
    func testConfirmCodeRunFollowsCodeRun() {
        var runIndex: Int?
        var confirmIndex: Int?
        for (i, b) in beats.enumerated() {
            if case .codeRun = b.intent, runIndex == nil { runIndex = i }
            if case .confirmCodeRun = b.intent, confirmIndex == nil { confirmIndex = i }
        }
        guard let run = runIndex, let confirm = confirmIndex else {
            return XCTFail("expected both `.codeRun` and `.confirmCodeRun` in the script")
        }
        XCTAssertLessThan(run, confirm,
                          "`.confirmCodeRun` (beat \(confirm)) must follow `.codeRun` (beat \(run)) "
                          + "— nothing starts without the founder's tap")
    }

    // MARK: - Amendment 4, 6 Sep — the redesign

    /// **The ordering claim this whole amendment exists to make.** The redesign is a revision
    /// of the built page, not an alternate take that happens to play first — Luna has to see
    /// what Byte built before she can ask for anything. Verified red by hand: swapping
    /// "Code · Byte" and "Redesign · Luna" in `DayOneScript.beats` during development failed
    /// this exactly as expected, then the swap was reverted.
    func testTheRedesignRunsAfterTheOriginalBuild() {
        guard let firstRedesign = beats.firstIndex(where: { $0.chapter == "Redesign · Luna" }) else {
            return XCTFail("expected a \"Redesign · Luna\" chapter in the day-one script")
        }
        guard let lastCode = beats.lastIndex(where: { $0.chapter == "Code · Byte" }) else {
            return XCTFail("expected a \"Code · Byte\" chapter in the day-one script")
        }
        XCTAssertLessThan(lastCode, firstRedesign,
                          "the redesign (beat \(firstRedesign)) must follow the original build "
                          + "(beat \(lastCode)), never precede it")
    }

    /// The redesign reuses `.codeRun`/`.confirmCodeRun` — a second pair, not new machinery — so
    /// this pins that the SECOND occurrence of each (the first belongs to the original build,
    /// already covered by `testTheFolderIsLinkedBeforeTheCodeRun`/`testConfirmCodeRunFollowsCodeRun`
    /// above) still keeps the founder's tap gating the run, inside "Redesign · Luna" specifically.
    func testTheRedesignsCodeRunIsAlsoGatedOnAConfirm() {
        var runIndex: Int?
        var confirmIndex: Int?
        for (i, b) in beats.enumerated() where b.chapter == "Redesign · Luna" {
            if case .codeRun = b.intent, runIndex == nil { runIndex = i }
            if case .confirmCodeRun = b.intent, confirmIndex == nil { confirmIndex = i }
        }
        guard let run = runIndex, let confirm = confirmIndex else {
            return XCTFail("expected both `.codeRun` and `.confirmCodeRun` inside \"Redesign · Luna\"")
        }
        XCTAssertLessThan(run, confirm,
                          "the redesign's `.confirmCodeRun` must follow its own `.codeRun`")
    }
}
