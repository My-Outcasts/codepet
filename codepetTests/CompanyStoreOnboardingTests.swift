// codepetTests/CompanyStoreOnboardingTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreOnboardingTests: XCTestCase {
    private func store(loader: @escaping (String) async -> CompanyState,
                       saver: @escaping (String, CompanyBrief) async -> Bool = { _, _ in true }) -> CompanyStore {
        CompanyStore(loader: loader, saver: saver)
    }

    func testNeedsOnboardingWhenNoStampAndNoBriefSignal() async {
        let s = store(loader: { _ in .empty })
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.needsOnboarding)
        XCTAssertTrue(s.isOnboarding)
    }
    func testNotNeededWhenBriefHasSignal() async {
        let seeded = CompanyState(brief: CompanyBrief(projectName: "Codepet", oneLiner: "x"),
                                  departments: [], library: [], stage: .building, companionId: "byte", onboardedAt: nil)
        let s = store(loader: { _ in seeded })
        await s.hydrate(companyId: "u")
        XCTAssertFalse(s.isOnboarding)
    }
    func testFinishOnboardingSavesStampsAndClears() async {
        var savedBrief: CompanyBrief?
        let s = store(loader: { _ in .empty }, saver: { _, b in savedBrief = b; return true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: CompanyBrief(projectName: "Codepet"))
        XCTAssertEqual(savedBrief?.projectName, "Codepet")
        XCTAssertEqual(s.company.brief.projectName, "Codepet")
        XCTAssertNotNil(s.company.onboardedAt)
        XCTAssertFalse(s.isOnboarding)
    }
    func testFinishClearsEvenWhenSaveFails() async {
        let s = store(loader: { _ in .empty }, saver: { _, _ in false })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: CompanyBrief(projectName: "Codepet"))
        XCTAssertFalse(s.isOnboarding)                       // not trapped by a failed write
        XCTAssertEqual(s.company.brief.projectName, "Codepet") // in-memory brief kept
    }
    func testSkipStampsAndClears() async {
        let s = store(loader: { _ in .empty })
        await s.hydrate(companyId: "u")
        await s.skipOnboarding()
        XCTAssertFalse(s.isOnboarding)
        XCTAssertNotNil(s.company.onboardedAt)
    }
}
