import XCTest
@testable import codepet

/// The demo's starting library.
///
/// `MockChat.company()` handed back `library: []`, so prototype mode opened with `done`
/// prerequisites and nothing filed behind them — a state the real product cannot reach, since
/// approving is what marks a task done AND files its deliverable. The consequence was that the
/// collaboration feature was invisible in the only place it can be demonstrated: with an empty
/// library `UpstreamWork.assemble` returns nothing, so no run inherits anything and no credit
/// renders. Measured on the autoplay walkthrough: zero credit lines across 24 chapters.
final class DemoProjectFiledTests: XCTestCase {

    func testMurrorFilesItsTwoPrerequisites() {
        let library = DemoProject.murror.library()
        XCTAssertEqual(library.map(\.sourceTaskId),
                       ["mur-interviews", "mur-landscape", "mur-brand"])
        for item in library {
            XCTAssertFalse(item.body.isEmpty, "a filed deliverable with no body renders blank")
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.body.contains("{{"), "an unsubstituted token reached the library")
        }
    }

    /// The default demo must open exactly as it did — every pre-existing suite depends on it.
    func testCodepetFilesNothing() {
        XCTAssertTrue(DemoProject.codepet.filed.isEmpty)
        XCTAssertTrue(DemoProject.codepet.library().isEmpty)
    }

    /// THE point of the change: with these filed, a downstream run actually inherits them.
    func testADownstreamRunNowInheritsTheFiledWork() {
        let tasks = DemoProject.murror.tasks
        let site = tasks.first { $0.id == "mur-site" }!
        let up = UpstreamWork.assemble(for: site, in: tasks,
                                       library: DemoProject.murror.library())
        XCTAssertEqual(up.count, 2, "mur-site dependsOn brand + landscape, both now filed")
        XCTAssertEqual(up.map(\.deptName), ["Design", "Marketing"])
        XCTAssertFalse(up.contains { $0.unapproved }, "filed work IS approved work")
        XCTAssertNotNil(UpstreamCredit.line(up))
    }

    /// And the corollary: the chain offer should now be RARE in the demo rather than universal.
    /// It fired on 8 of 8 runnable Murror tasks before this, which made a two-button question
    /// the first screen of every department ask.
    func testTheOfferNoLongerFiresOnEveryMurrorTask() {
        let tasks = DemoProject.murror.tasks
        let library = DemoProject.murror.library()
        let runnable = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .codepetCanDo }
        XCTAssertEqual(runnable.count, 8, "the roster claim: one runnable task per department")
        let offering = runnable.filter {
            UpstreamWork.firstUnfiled(dependencyOf: $0, in: tasks, library: library) != nil
        }
        XCTAssertTrue(offering.isEmpty,
                      "still offers on: \(offering.map(\.id)) — every dependency should be filed")
    }

    /// **The near-miss this test exists for.** `deliverable(for:)` falls back to the LAST
    /// entry when no keyword matches, so filing a task whose title matches nothing silently
    /// files the generic catch-all instead. The first version of this change did exactly that
    /// for both prerequisites: the credit line rendered correctly and the body fed forward was
    /// filler, which is a card telling the truth about a lie. Nothing about it looked wrong.
    func testTheFiledWorkIsRealAndNotTheCatchAll() throws {
        let catchAll = try XCTUnwrap(DemoProject.murror.deliverables.last)
        XCTAssertTrue(catchAll.keywords.isEmpty, "the last entry must be the catch-all")
        for item in DemoProject.murror.library() {
            XCTAssertFalse(item.body.contains("a starting point, not the final word"),
                           "\(item.sourceTaskId ?? "?") fell through to the catch-all")
        }
        // And each one is actually about its own subject.
        let byTask = Dictionary(uniqueKeysWithValues:
            DemoProject.murror.library().map { ($0.sourceTaskId ?? "", $0.body) })
        XCTAssertTrue(byTask["mur-brand"]?.contains("amber") ?? false)
        XCTAssertTrue(byTask["mur-landscape"]?.contains("day three") ?? false)
        XCTAssertTrue(byTask["mur-interviews"]?.contains("Twelve conversations") ?? false)
    }

    /// Codepet must never offer to run the founder's own task. `mur-interviews` is
    /// `who: .you` — twelve conversations that happened off the screen — and
    /// `handleRunTaskId` refuses a `.you` task everywhere else, so an offer whose "Run both"
    /// reached one would promise work the product declines to do.
    func testAFounderOwnedDependencyIsNeverOfferedAsARun() {
        let tasks = DemoProject.murror.tasks
        let faq = tasks.first { $0.dependsOn == ["mur-interviews"] }!
        XCTAssertEqual(tasks.first { $0.id == "mur-interviews" }?.who, .you,
                       "fixture moved; this test's premise is gone")
        XCTAssertNil(UpstreamWork.firstUnfiled(dependencyOf: faq, in: tasks, library: []),
                     "a `.you` dependency must feed nothing forward rather than be offered")
    }

    /// Ids are derived so a relaunch does not reshuffle the Library.
    func testIdsAreStableAcrossCalls() {
        XCTAssertEqual(DemoProject.murror.library().map(\.id),
                       DemoProject.murror.library().map(\.id))
    }
}
