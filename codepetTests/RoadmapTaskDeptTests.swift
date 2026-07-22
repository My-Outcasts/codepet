import XCTest
@testable import codepet

final class RoadmapTaskDeptTests: XCTestCase {
    // Existing saved tasks have NO `dept` key — decode must still succeed (dept == nil).
    func testDecodesWithoutDept() throws {
        let json = """
        {"id":"t1","title":"Ship","detail":"d","phase":"build","who":"does","dependsOn":[],"done":false,"drafted":false}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(RoadmapTask.self, from: json)
        XCTAssertNil(task.dept)
        XCTAssertEqual(task.id, "t1")
    }
    func testDecodesWithDept() throws {
        let json = """
        {"id":"t1","title":"Ship","detail":"d","phase":"build","who":"does","dependsOn":[],"done":false,"drafted":false,"dept":"eng"}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(RoadmapTask.self, from: json)
        XCTAssertEqual(task.dept, "eng")
    }
    func testInitDefaultsDeptNil() {
        let t = RoadmapTask(id: "x", title: "T", detail: "", phase: .find, who: .you)
        XCTAssertNil(t.dept)
    }
}
