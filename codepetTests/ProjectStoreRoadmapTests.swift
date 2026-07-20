// codepetTests/ProjectStoreRoadmapTests.swift
import XCTest
@testable import codepet

@MainActor
final class ProjectStoreRoadmapTests: XCTestCase {
    func testSetReadToggleTasksPersistInMemory() {
        let store = ProjectStore()
        let id = store.detectProject(cwd: "/tmp/rm")!.id
        let tasks = [RoadmapTask(id: "engineering-0", deptKey: .engineering, title: "Ship auth", detail: "d")]
        store.setRoadmapTasks(projectId: id, tasks: tasks)
        XCTAssertEqual(store.roadmapTasks(for: id).count, 1)
        XCTAssertFalse(store.roadmapTasks(for: id)[0].done)
        store.toggleRoadmapTask(projectId: id, taskId: "engineering-0")
        XCTAssertTrue(store.roadmapTasks(for: id)[0].done)
    }
}
