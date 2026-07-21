// codepetTests/RunTaskClientTests.swift
import XCTest
@testable import codepet

final class RunTaskClientTests: XCTestCase {
    func testRequestEncodesSnakeCaseAndRoundTrips() throws {
        let req = RunTaskRequest(companyId: "u1", language: "en", companionId: "byte",
                                 context: "ctx", taskId: "t1", taskTitle: "Survey", taskDetail: "willingness to pay")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["company_id"] as? String, "u1")
        XCTAssertEqual(json?["companion_id"] as? String, "byte")
        XCTAssertEqual(json?["task_id"] as? String, "t1")
        XCTAssertEqual(json?["task_title"] as? String, "Survey")
        XCTAssertEqual(json?["task_detail"] as? String, "willingness to pay")
        let back = try JSONDecoder().decode(RunTaskRequest.self, from: data)
        XCTAssertEqual(back.taskId, "t1")
    }
    func testResponseDecodes() throws {
        let data = "{\"kind\":\"doc\",\"title\":\"Scope\",\"body\":\"# Hi\"}".data(using: .utf8)!
        let r = try JSONDecoder().decode(RunTaskResponse.self, from: data)
        XCTAssertEqual(r.kind, "doc")
        XCTAssertEqual(r.title, "Scope")
        XCTAssertEqual(r.body, "# Hi")
    }
}
