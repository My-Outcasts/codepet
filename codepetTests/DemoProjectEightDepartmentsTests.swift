// codepetTests/DemoProjectEightDepartmentsTests.swift
import XCTest
@testable import codepet

/// Guards that the demo shows finished work from ALL EIGHT departments.
///
/// Measured 5 Sep: the 24-chapter walkthrough contained one `runBeacon`, one
/// `approveNewestDraft` and one `convene`, so ONE department produced work on camera — while
/// the board carried eight runnable tasks with eight real deliverables. Chapter 2 narrates
/// "eight departments, each speaking with its own pet" and the tour demonstrated one.
///
/// `LibraryView` already groups by department; it showed two groups because the fixture filed
/// three artifacts belonging to two departments, all of kind `doc`.
final class DemoProjectEightDepartmentsTests: XCTestCase {

    private var murror: DemoProject { .murror }

    // MARK: - Task 1: the six artifacts

    /// The six new titles must each resolve to their OWN entry, not to the catch-all and not to
    /// an existing entry's keywords.
    func testTheSixNewTitlesResolveToTheirOwnDeliverables() {
        let expected: [(title: String, kind: String, marker: String)] = [
            ("Choose what the app is built on", "doc", "on-device"),
            ("Work out what a month of inference costs", "sheet", "per active user"),
            ("Write down who this is not for", "doc", "not for"),
            ("Decide what happens on a bad night", "doc", "crisis"),
            ("Set up the weekly release rhythm", "checklist", "Thursday"),
            ("Write the data-deletion promise", "legal", "one tap"),
        ]
        for e in expected {
            let d = murror.deliverable(for: e.title)
            XCTAssertFalse(d.keywords.isEmpty, "\"\(e.title)\" fell through to the catch-all")
            XCTAssertEqual(d.kind, e.kind, e.title)
            // Case-insensitive: the marker is a content check, not a capitalisation check.
            // "On-device" and "One tap" both open sentences, so a case-sensitive `contains`
            // fails on correct content — which it did, on the first run.
            XCTAssertTrue(d.body.lowercased().contains(e.marker.lowercased()),
                          "\"\(e.title)\" resolved to the wrong entry: \(d.body.prefix(60))")
        }
    }

    /// **The shadowing guard.** `deliverable(for:)` returns the first entry whose keyword appears
    /// in the lowercased title, so a broad new keyword placed early silently steals another
    /// department's deliverable — no error, just Sales showing Engineering's work.
    func testTheNewKeywordsShadowNoExistingTitle() {
        let existing = [
            "Build the Murror landing page": "site",
            "Design the first-run flow": "screens",
            "Decide what free and paid mean": "sheet",
            "Ship an email capture": "checklist",
            "Find the first 20 users": "dms",
            "Answer the first questions": "doc",
            "Write the launch checklist": "plan",
            "Draft the privacy policy": "legal",
        ]
        for (title, kind) in existing {
            XCTAssertEqual(murror.deliverable(for: title).kind, kind,
                           "\"\(title)\" now resolves to the wrong entry")
        }
    }

    /// No filled body may leak an unsubstituted token to a founder's screen.
    ///
    /// Tokens are legitimate in the SOURCE — `{{product}}` is how the fixture stays project-
    /// agnostic — so this asserts on the FILLED output, which is what reaches a card.
    func testNoFilledBodyLeaksAToken() {
        for entry in murror.deliverables where !entry.keywords.isEmpty {
            let filled = MockChat.fill(entry.body, title: "T")
            XCTAssertFalse(filled.contains("{{"),
                           "unsubstituted token survives filling in \(entry.keywords)")
        }
    }

    // MARK: - Task 2: the board carries both halves

    /// **The claim this whole change exists to make.** Every roster department has finished work
    /// a founder can open, not just a task it could run.
    func testEveryRosterDepartmentHasFiledWork() {
        let library = murror.library()
        let byDept = Dictionary(grouping: library) { d -> String in
            murror.tasks.first { $0.id == d.sourceTaskId }?.dept ?? "?"
        }
        for dept in DepartmentCatalog.roster.map(\.key) {
            XCTAssertNotNil(byDept[dept], "\(dept) has no filed deliverable — the Library will "
                            + "show seven groups, not eight")
        }
    }

    /// And the existing headline claim survives. These two pull against each other — a task
    /// cannot be both `done` with work behind it and open for Codepet to run — so they are
    /// asserted together, because a future edit will be tempted to trade one for the other.
    func testTheEightAreStillRunnable() {
        let tasks = murror.tasks
        let runnable = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .codepetCanDo }
        XCTAssertEqual(runnable.count, 8)
        XCTAssertEqual(Set(runnable.compactMap(\.dept)),
                       Set(DepartmentCatalog.roster.map(\.key)))
    }

    func testTheNewTasksAreDoneAndNotRunnable() {
        for id in ["mur-stack", "mur-unitcost", "mur-notfor",
                   "mur-crisis", "mur-rhythm", "mur-deletion"] {
            guard let t = murror.tasks.first(where: { $0.id == id }) else {
                XCTFail("\(id) missing from the board"); continue
            }
            XCTAssertTrue(t.done, "\(id) must be done")
            XCTAssertEqual(RoadmapEngine.status(for: t, in: murror.tasks), .done)
        }
    }

    /// Every filed deliverable traces to a done task on the roadmap. That provenance IS the
    /// "your company did this" claim; filed work with no source task quietly weakens it.
    func testEveryFiledDeliverableTracesToADoneTask() {
        for d in murror.library() {
            guard let id = d.sourceTaskId else {
                XCTFail("\(d.title) has no source task"); continue
            }
            guard let t = murror.tasks.first(where: { $0.id == id }) else {
                XCTFail("\(d.title) points at \(id), not on the board"); continue
            }
            XCTAssertTrue(t.done, "\(d.title) is filed but its task is not done")
        }
    }


    // MARK: - Task 3: the walkthrough points at it

    /// Exactly one Library beat. The walkthrough already had one, so this change re-captions it
    /// rather than adding a second — which would be the duplication the spec warns about.
    func testThereIsExactlyOneLibraryBeat() {
        let n = MockFlowScript.beats.filter { $0.intent == .go(.library) }.count
        XCTAssertEqual(n, 1, "one Library beat, not two")
    }

    /// It must claim the breadth that is now actually on screen. The old caption spoke only of
    /// the single deliverable just approved, which with nine artifacts across eight departments
    /// understates it badly.
    func testTheLibraryBeatNamesTheBreadth() throws {
        let beat = try XCTUnwrap(MockFlowScript.beats.first { $0.intent == .go(.library) })
        XCTAssertTrue(beat.caption.lowercased().contains("eight"),
                      "the caption should name the eight departments: \(beat.caption)")
        XCTAssertGreaterThanOrEqual(beat.seconds, 4.0,
                                    "2.6s is not long enough to read eight groups")
    }

}
