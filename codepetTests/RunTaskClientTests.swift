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
    /// `reviseNote`/`current` default to nil and are OMITTED from the encoded wire
    /// payload when unset — a first run / blind redo's request shape is byte-for-byte
    /// unchanged from before these fields existed.
    func testRequestOmitsReviseFieldsWhenNil() throws {
        let req = RunTaskRequest(companyId: "u1", language: "en", companionId: "byte",
                                 context: "ctx", taskId: "t1", taskTitle: "Survey", taskDetail: "wtp")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(json?["revise_note"])
        XCTAssertNil(json?["current"])
    }
    /// A revise chip re-run encodes `revise_note` (snake_case, matching every other
    /// multi-word field on this request) + `current` (the draft's present body).
    func testRequestEncodesReviseNoteAndCurrent() throws {
        let req = RunTaskRequest(companyId: "u1", language: "en", companionId: "byte",
                                 context: "ctx", taskId: "t1", taskTitle: "Survey", taskDetail: "wtp",
                                 reviseNote: "Make it shorter", current: "# Q1\nBody")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["revise_note"] as? String, "Make it shorter")
        XCTAssertEqual(json?["current"] as? String, "# Q1\nBody")
        let back = try JSONDecoder().decode(RunTaskRequest.self, from: data)
        XCTAssertEqual(back.reviseNote, "Make it shorter")
        XCTAssertEqual(back.current, "# Q1\nBody")
    }
    func testResponseDecodes() throws {
        let data = "{\"kind\":\"doc\",\"title\":\"Scope\",\"body\":\"# Hi\"}".data(using: .utf8)!
        let r = try JSONDecoder().decode(RunTaskResponse.self, from: data)
        XCTAssertEqual(r.kind, "doc")
        XCTAssertEqual(r.title, "Scope")
        XCTAssertEqual(r.body, "# Hi")
    }
}
