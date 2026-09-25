// codepetTests/CompanyOwnershipPayloadTests.swift
import XCTest
@testable import codepet

/// Every company write must carry the fields `firestore.rules` demands on create. Without them a
/// natively-onboarded founder's writes were all denied and the company vanished on relaunch
/// (rules side: `functions/src/engineering/__tests__/rules.test.ts`, "the native app's merge writes").
@MainActor
final class CompanyOwnershipPayloadTests: XCTestCase {
    func testOwnedAddsOwnerAndMembersAndKeepsThePayload() async {
        let p = CompanyData.owned(CompanyData.deliverablesPayload([]), companyId: "uid1")
        XCTAssertEqual(p["ownerId"] as? String, "uid1")
        XCTAssertNotNil(p["memberIds"], "memberIds must be present — the create rule requires the list")
        XCTAssertNotNil(p["library"])
        XCTAssertEqual(Set(CompanyData.ownershipFieldNames), ["ownerId", "memberIds"])
    }
}
