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
    func testResponseDecodes() throws {
        let data = "{\"reply\":\"hi there\"}".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(CompanyChatResponse.self, from: data).reply, "hi there")
    }
}
