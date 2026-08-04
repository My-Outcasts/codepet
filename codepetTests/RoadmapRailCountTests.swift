// codepetTests/RoadmapRailCountTests.swift
import XCTest
@testable import codepet

/// A collapsed rail's count slot. An unplanned phase used to print nothing at all,
/// leaving a rail that looked identical to one whose number had failed to render —
/// with the only explanation in a hover tooltip. The slot is now always occupied.
final class RoadmapRailCountTests: XCTestCase {

    func testPlannedPhaseShowsDoneOverTotal() {
        XCTAssertEqual(RoadmapBoardCopy.railCount(done: 2, total: 3), "2/3")
        XCTAssertEqual(RoadmapBoardCopy.railCount(done: 0, total: 3), "0/3")
        XCTAssertEqual(RoadmapBoardCopy.railCount(done: 3, total: 3), "3/3")
    }

    /// The case that was blank on screen: LAUNCH and RUN & GROW with no tasks.
    func testUnplannedPhaseShowsAnEmDashNotAnEmptyString() {
        XCTAssertEqual(RoadmapBoardCopy.railCount(done: 0, total: 0), "—")
    }

    /// Whatever the inputs, the slot is never blank — that blankness was the defect.
    func testSlotIsNeverEmpty() {
        for total in 0...4 {
            for done in 0...total {
                XCTAssertFalse(RoadmapBoardCopy.railCount(done: done, total: total).isEmpty,
                               "rail count was blank for \(done)/\(total)")
            }
        }
    }

    /// An unplanned phase must not read as "nothing done out of nothing", which is
    /// what a bare 0/0 looks like — indistinguishable from a bug.
    func testUnplannedIsNotRenderedAsZeroOverZero() {
        XCTAssertNotEqual(RoadmapBoardCopy.railCount(done: 0, total: 0), "0/0")
    }
}
