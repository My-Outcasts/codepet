// codepetTests/CompanyDataDeliverablesTests.swift
import XCTest
@testable import codepet

final class CompanyDataDeliverablesTests: XCTestCase {
    func testDeliverablesPayloadShape() {
        let d = Deliverable(id: "d1", kind: .plan, title: "Plan", body: "# x",
                            createdAt: "2026-07-21T00:00:00Z", sourceTaskId: "t1")
        let payload = CompanyData.deliverablesPayload([d])
        let arr = payload["library"] as? [[String: Any]]
        XCTAssertEqual(arr?.count, 1)
        XCTAssertEqual(arr?.first?["id"] as? String, "d1")
        XCTAssertEqual(arr?.first?["kind"] as? String, "plan")
        XCTAssertEqual(arr?.first?["title"] as? String, "Plan")
        XCTAssertEqual(arr?.first?["source_task_id"] as? String ?? arr?.first?["sourceTaskId"] as? String, "t1")
    }
    func testEmptyLibraryPayload() {
        let payload = CompanyData.deliverablesPayload([])
        XCTAssertEqual((payload["library"] as? [[String: Any]])?.count, 0)
    }
}
