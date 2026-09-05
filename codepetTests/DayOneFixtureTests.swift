// codepetTests/DayOneFixtureTests.swift
import XCTest
@testable import codepet

/// Day one is mid-flight with two fields changed. Asserting that here is what stops the two
/// drifting into different stories — the bridge claim is only true while they share a board.
final class DayOneFixtureTests: XCTestCase {

    private var dayOne: DemoProject { .murrorDayOne }
    private var midFlight: DemoProject { .murror }

    /// The ordered nine, and the shape of the run.
    func testTheChainIsNineTasksCoveringAllEightDepartments() {
        XCTAssertEqual(DemoProject.dayOneChain,
                       ["mur-interviews", "mur-landscape", "mur-notfor", "mur-brand",
                        "mur-stack", "mur-unitcost", "mur-crisis", "mur-deletion", "mur-rhythm"])
        let byId = Dictionary(uniqueKeysWithValues: midFlight.tasks.map { ($0.id, $0) })
        let depts = Set(DemoProject.dayOneChain.compactMap { byId[$0]?.dept })
        XCTAssertEqual(depts, Set(DepartmentCatalog.roster.map(\.key)),
                       "nine tasks must cover all eight departments")
    }

    /// **The bridge's precondition.** The nine the simulation runs are exactly the nine
    /// mid-flight has filed, or running them cannot land on mid-flight.
    func testTheChainIsExactlyMidFlightsFiledSet() {
        XCTAssertEqual(Set(DemoProject.dayOneChain), Set(midFlight.filed))
    }

    func testDayOneStartsFromNothing() {
        XCTAssertTrue(dayOne.filed.isEmpty, "day one has no filed work")
        XCTAssertTrue(dayOne.library().isEmpty, "and therefore an empty Library")
        for id in DemoProject.dayOneChain {
            let t = dayOne.tasks.first { $0.id == id }
            XCTAssertEqual(t?.done, false, "\(id) must be open on day one")
        }
    }

    /// One source, two states: same ids, same titles, same order, same departments.
    func testTheTwoBoardsDifferOnlyInDoneAndFiled() {
        XCTAssertEqual(dayOne.tasks.map(\.id), midFlight.tasks.map(\.id))
        XCTAssertEqual(dayOne.tasks.map(\.title), midFlight.tasks.map(\.title))
        XCTAssertEqual(dayOne.tasks.map(\.dept), midFlight.tasks.map(\.dept))
        XCTAssertEqual(dayOne.tasks.map(\.dependsOn), midFlight.tasks.map(\.dependsOn),
                       "the chain edges live in the SHARED list, not in one state")
        XCTAssertEqual(dayOne.brief.projectName, midFlight.brief.projectName)
    }

    /// The chain must actually be a line, or `nextStep` will not walk it in order.
    func testEachLinkDependsOnItsPredecessor() {
        let byId = Dictionary(uniqueKeysWithValues: dayOne.tasks.map { ($0.id, $0) })
        for (i, id) in DemoProject.dayOneChain.enumerated() where i > 0 {
            let prev = DemoProject.dayOneChain[i - 1]
            XCTAssertTrue(byId[id]?.dependsOn.contains(prev) == true,
                          "\(id) must depend on \(prev) or the beacon will skip it")
        }
    }

    /// On day one exactly ONE task in the chain is startable, and it is link 1.
    ///
    /// `mur-clinician` also shows up here: it is a pre-existing founder-only task with no
    /// `dependsOn`, open in `.murror` already (the "ONLY one on this board" per that fixture's
    /// own comment) and untouched by `murrorDayOne` because it is not one of the nine chain
    /// ids. It stays `.needsYou` on both boards — that is unrelated to this task's edges, so it
    /// is asserted here rather than filtered out.
    func testOnlyTheFirstLinkIsOpenOnDayOne() {
        let startable = dayOne.tasks.filter {
            let s = RoadmapEngine.status(for: $0, in: dayOne.tasks)
            return s == .codepetCanDo || s == .needsYou
        }
        XCTAssertEqual(startable.map(\.id), ["mur-interviews", "mur-clinician"])
        let chainStartable = startable.filter { DemoProject.dayOneChain.contains($0.id) }
        XCTAssertEqual(chainStartable.map(\.id), ["mur-interviews"],
                       "of the nine-question chain, only link 1 must be open")
    }

    /// **The 17 suites' premise.** New edges among tasks that are all `done` must change
    /// nothing about mid-flight: `status` returns `.done` before it consults `depsSatisfied`.
    func testMidFlightIsUnchangedByTheNewEdges() {
        let runnable = midFlight.tasks.filter {
            RoadmapEngine.status(for: $0, in: midFlight.tasks) == .codepetCanDo
        }
        XCTAssertEqual(runnable.count, 8)
        XCTAssertEqual(Set(runnable.compactMap(\.dept)), Set(DepartmentCatalog.roster.map(\.key)))
        XCTAssertEqual(RoadmapEngine.nextStep(midFlight.tasks)?.id, "mur-site",
                       "the tour's beacon must still point at the landing page")
        XCTAssertEqual(midFlight.library().count, 9)
    }

    func testDayOneIsSelectable() {
        XCTAssertTrue(DemoProject.all.contains { $0.id == "murror-day-one" })
    }
}
