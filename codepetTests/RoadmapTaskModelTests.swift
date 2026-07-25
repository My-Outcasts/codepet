// codepetTests/RoadmapTaskModelTests.swift
import XCTest
@testable import codepet

final class RoadmapTaskModelTests: XCTestCase {
    func testPhaseOrderAndLabels() {
        XCTAssertEqual(RoadmapPhase.allCases.map(\.rawValue),
                       ["find", "foundation", "build", "ship", "launch", "grow"])
        XCTAssertEqual(RoadmapPhase.find.order, 0)
        XCTAssertEqual(RoadmapPhase.launch.order, 4)
        XCTAssertEqual(RoadmapPhase.grow.order, 5)
        for p in RoadmapPhase.allCases {
            XCTAssertFalse(p.label(.en).isEmpty); XCTAssertFalse(p.label(.vi).isEmpty)
        }
    }
    func testTaskRoundTripsCodableWithDefaults() throws {
        let t = RoadmapTask(id: "t1", title: "Ship auth", detail: "wire sign-in", phase: .build, who: .does)
        XCTAssertEqual(t.dependsOn, []); XCTAssertFalse(t.done); XCTAssertFalse(t.drafted)
        let back = try JSONDecoder().decode(RoadmapTask.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
    }
    func testDraftRoundTripsThroughCodable() throws {
        let d = Deliverable(kind: .doc, title: "Draft", body: "body", sourceTaskId: "t1")
        let t = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .draft, drafted: true, draft: d)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(RoadmapTask.self, from: data)
        XCTAssertEqual(back.draft?.title, "Draft")
        XCTAssertEqual(back.draft?.sourceTaskId, "t1")
        XCTAssertTrue(back.drafted)
    }
    func testDraftDefaultsNilAndDecodesFromLegacyTaskWithoutField() throws {
        XCTAssertNil(RoadmapTask(id: "x", title: "T", detail: "", phase: .find, who: .does).draft)
        // legacy stored task (no `draft` key) still decodes (optional field)
        let legacy = #"{"id":"x","title":"T","detail":"","phase":"find","who":"does","dependsOn":[],"done":false,"drafted":false}"#
        let back = try JSONDecoder().decode(RoadmapTask.self, from: Data(legacy.utf8))
        XCTAssertNil(back.draft)
    }
}
