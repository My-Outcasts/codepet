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

    func testResetDuringHydrateWinsAndStaleResultIsDiscarded() async {
        // Loader suspends on a continuation the test controls, so we can
        // deterministically call reset() while hydrate() is still in flight.
        let staleCompany = CompanyState(brief: CompanyBrief(projectName: "Stale"),
                                         departments: [], library: [], stage: .building, companionId: "nova")
        var continuation: CheckedContinuation<CompanyState, Never>?
        let store = CompanyStore(loader: { _ in
            await withCheckedContinuation { cont in
                continuation = cont
            }
        })

        let hydrateTask = Task { await store.hydrate(companyId: "old-account") }

        // Wait until the loader has actually suspended and captured its continuation.
        while continuation == nil {
            await Task.yield()
        }

        store.reset()
        continuation?.resume(returning: staleCompany)
        await hydrateTask.value

        XCTAssertEqual(store.company, CompanyState.empty)
        XCTAssertEqual(store.view, .overview)
        XCTAssertFalse(store.isHydrating)
    }
}
