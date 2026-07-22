// codepetTests/CompanyDataTasksTests.swift
import XCTest
@testable import codepet

final class CompanyDataTasksTests: XCTestCase {
    func testStateMapsTasks() {
        let task = RoadmapTask(id: "t1", title: "Ship", detail: "d", phase: .build, who: .does)
        let s = CompanyData.state(from: CompanyDoc(brief: CompanyBrief(), stage: nil,
                                                   companionId: nil, onboardedAt: nil, tasks: [task]))
        XCTAssertEqual(s.tasks.map(\.id), ["t1"])
        XCTAssertEqual(CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil, onboardedAt: nil, tasks: nil)).tasks, [])
    }
    func testTasksPayloadShape() {
        let payload = CompanyData.tasksPayload([RoadmapTask(id: "t1", title: "Ship", detail: "d", phase: .build, who: .does)])
        let arr = payload["tasks"] as? [[String: Any]]
        XCTAssertEqual(arr?.count, 1)
        XCTAssertEqual(arr?.first?["id"] as? String, "t1")
        XCTAssertEqual(arr?.first?["phase"] as? String, "build")
    }
    // Note: `fetchRoadmap` is now a real network call to the generateRoadmap CF (it was a
    // `return []` stub). Its fail-open-to-[] behavior is verified in the live E2E, not here —
    // a unit test would hit the network / an unconfigured Auth. The pure mapping + payload
    // logic above remains covered.
}
