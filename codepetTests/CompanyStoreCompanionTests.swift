// codepetTests/CompanyStoreCompanionTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreCompanionTests: XCTestCase {
    func testSetCompanionSetsAndPersists() async {
        var saved: (String, String)?
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             companionSaver: { c, id in saved = (c, id); return true })
        await s.hydrate(companyId: "u")
        await s.setCompanion(id: "nova")
        XCTAssertEqual(s.company.companionId, "nova")
        XCTAssertEqual(saved?.0, "u")
        XCTAssertEqual(saved?.1, "nova")
    }
    func testCompanionIdPayloadShape() {
        XCTAssertEqual(CompanyData.companionIdPayload("luna")["companionId"] as? String, "luna")
    }
}
