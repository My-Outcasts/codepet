// codepetTests/RoomHandoffLineTests.swift
import XCTest
@testable import codepet

/// byte's handoff line names the departments actually in the room.
///
/// It was a constant — "Let me bring in product and finance" — on every room. On 1 Oct (build 6,
/// real account) one room seated Finance, Marketing and Sales and the next Marketing and Design,
/// while the line said product and finance both times. Product is not even on the roster.
final class RoomHandoffLineTests: XCTestCase {
    private func routing(_ meta: [(String, String?)]) throws -> VCRouting {
        let items = meta.map { id, key in
            "{\"agent_id\":\"\(id)\",\"department_key\":\(key.map { "\"\($0)\"" } ?? "null")}"
        }.joined(separator: ",")
        let json = "{\"decision\":\"multi_agent\",\"agents\":[\(meta.map { "\"\($0.0)\"" }.joined(separator: ","))],\"agent_meta\":[\(items)]}"
        return try JSONDecoder().decode(VCRouting.self, from: Data(json.utf8))
    }

    func testNamesTheSeatedDepartmentsInOrder() throws {
        let line = RoomHandoff.line(.en, routing: try routing([("finance", "fin"), ("marketing", "mkt"), ("sales", "sales")]))
        XCTAssertEqual(line, "Actually — this one needs the whole room. Let me bring in Finance, Marketing and Sales.")
    }

    func testTwoDepartmentsUseAnd() throws {
        let line = RoomHandoff.line(.en, routing: try routing([("marketing", "mkt"), ("design", "design")]))
        XCTAssertTrue(line.hasSuffix("Let me bring in Marketing and Design."), line)
    }

    /// The challenger takes no seat in the cap and is not a department; it must not be named.
    func testTheChallengerAndChiefOfStaffAreNotNamed() throws {
        let line = RoomHandoff.line(.en, routing: try routing([("devils_advocate", nil), ("finance", "fin"), ("chief_of_staff", nil), ("legal", "legal")]))
        XCTAssertTrue(line.hasSuffix("Let me bring in Finance and Legal."), line)
        XCTAssertFalse(line.lowercased().contains("challenger"))
    }

    func testNeverTheOldConstant() throws {
        let line = RoomHandoff.line(.en, routing: try routing([("sales", "sales")]))
        XCTAssertFalse(line.contains("product and finance"))
        XCTAssertTrue(line.hasSuffix("Let me bring in Sales."), line)
    }

    /// Team build: the founder asked for the room, so byte does not have a second thought about it.
    func testARequestedRoomOnlySaysWhoIsComingIn() throws {
        let r = try routing([("finance", "fin"), ("marketing", "mkt")])
        XCTAssertEqual(RoomHandoff.line(.en, routing: r, requested: true), "Bringing in Finance and Marketing.")
        XCTAssertEqual(RoomHandoff.line(.en, routing: nil, requested: true), "Bringing the team in.")
        XCTAssertFalse(RoomHandoff.line(.vi, routing: r, requested: true).contains("Thật ra"))
    }

    /// No routing to read (should not happen behind `handsOffToRoom`) still says something true.
    func testWithNoSeatsItNamesNoOne() {
        XCTAssertEqual(RoomHandoff.line(.en, routing: nil), "Actually — this one needs the whole room. Let me bring the team in.")
    }

    /// A frame with no `agent_meta` still names its seats from the bare ids.
    func testFallsBackToTheAgentIdsWithoutMeta() throws {
        let json = #"{"decision":"multi_agent","agents":["devils_advocate","operations","sales"]}"#
        let r = try JSONDecoder().decode(VCRouting.self, from: Data(json.utf8))
        XCTAssertTrue(RoomHandoff.line(.en, routing: r).hasSuffix("Let me bring in Operations and Sales."))
    }

    func testVietnamese() throws {
        let line = RoomHandoff.line(.vi, routing: try routing([("finance", "fin"), ("sales", "sales")]))
        XCTAssertEqual(line, "Thật ra cái này cần cả phòng — để mình gọi Finance và Sales vào.")
    }
}
