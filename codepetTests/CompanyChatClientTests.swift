// codepetTests/CompanyChatClientTests.swift
import XCTest
@testable import codepet

final class CompanyChatClientTests: XCTestCase {
    func testRequestEncodesSnakeCaseAndRoundTrips() throws {
        let req = CompanyChatRequest(companyId: "u1", language: "en", companionId: "byte",
                                     context: "ctx", history: [ChatTurnDTO(role: "me", text: "hi")],
                                     userMessage: "hello")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["company_id"] as? String, "u1")
        XCTAssertEqual(json?["companion_id"] as? String, "byte")
        XCTAssertEqual(json?["user_message"] as? String, "hello")
        let back = try JSONDecoder().decode(CompanyChatRequest.self, from: data)
        XCTAssertEqual(back.history, req.history)
    }
    func testResponseDecodesWithRunTaskId() throws {
        let data = "{\"reply\":\"On it\",\"run_task_id\":\"t1\"}".data(using: .utf8)!
        let r = try JSONDecoder().decode(CompanyChatResponse.self, from: data)
        XCTAssertEqual(r.reply, "On it")
        XCTAssertEqual(r.runTaskId, "t1")
    }
    func testResponseDecodesWithoutRunTaskId() throws {
        let data = "{\"reply\":\"hi\"}".data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(CompanyChatResponse.self, from: data).runTaskId)
    }
}
