// codepetTests/CompanyStoreTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreTests: XCTestCase {
    func testSelectUpdatesView() {
        let store = CompanyStore()
        store.select(.roadmap)
        XCTAssertEqual(store.view, .roadmap)
    }
    func testHydrateLoadsCompanyAndClearsFlag() async {
        let seeded = CompanyState(brief: CompanyBrief(projectName: "Codepet"),
                                  departments: [], library: [], stage: .building, companionId: "nova")
        let store = CompanyStore(loader: { _ in seeded })
        await store.hydrate(companyId: "uid1")
        XCTAssertEqual(store.company.brief.projectName, "Codepet")
        XCTAssertEqual(store.company.stage, .building)
        XCTAssertFalse(store.isHydrating)
    }
    func testResetClearsToEmptyOverview() {
        let store = CompanyStore(loader: { _ in CompanyState(brief: CompanyBrief(projectName: "X"), departments: [], library: [], stage: .growth, companionId: "luna") })
        store.select(.tasks)
        store.reset()
        XCTAssertEqual(store.view, .overview)
        XCTAssertEqual(store.company, CompanyState.empty)
    }
}
