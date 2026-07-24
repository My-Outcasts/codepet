// codepetTests/CompanyStoreOnboardingTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreOnboardingTests: XCTestCase {
    private func store(loader: @escaping (String) async -> CompanyState,
                       saver: @escaping (String, CompanyBrief) async -> Bool = { _, _ in true },
                       roadmapFetcher: @escaping (CompanyBrief, AppLanguage) async -> [RoadmapTask] = { _, _ in [] },
                       enricher: @escaping (CompanyBrief) async throws -> CompanyBrief = { $0 }) -> CompanyStore {
        CompanyStore(loader: loader, saver: saver, roadmapFetcher: roadmapFetcher, enricher: enricher)
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
    /// Regression: a legacy/partial brief with only `role` (no product text) and no
    /// stamp counts as onboarded on web; native must not re-onboard it.
    func testNotNeededWhenBriefHasOnlyRole() async {
        let seeded = CompanyState(brief: CompanyBrief(role: "Founder"),
                                  departments: [], library: [], stage: .building,
                                  companionId: "byte", onboardedAt: nil)
        let s = store(loader: { _ in seeded })
        await s.hydrate(companyId: "u")
        XCTAssertFalse(s.isOnboarding)
    }
    func testFinishOnboardingSavesStampsAndClears() async {
        var savedBrief: CompanyBrief?
        let s = store(loader: { _ in .empty }, saver: { _, b in savedBrief = b; return true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: CompanyBrief(projectName: "Codepet"), token: s.onboardingToken)
        XCTAssertEqual(savedBrief?.projectName, "Codepet")
        XCTAssertEqual(s.company.brief.projectName, "Codepet")
        XCTAssertNotNil(s.company.onboardedAt)
        XCTAssertFalse(s.isOnboarding)
    }
    func testFinishClearsEvenWhenSaveFails() async {
        let s = store(loader: { _ in .empty }, saver: { _, _ in false })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: CompanyBrief(projectName: "Codepet"), token: s.onboardingToken)
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

    /// A stale finish from account A (token captured before an account switch) must
    /// NOT write into account B's doc or clobber B's freshly-hydrated state.
    func testStaleFinishAfterAccountSwitchDoesNotClobber() async {
        var savedTo: [String] = []
        let bState = CompanyState(brief: CompanyBrief(projectName: "B-Co"),
                                  departments: [], library: [], stage: .growth,
                                  companionId: "byte", onboardedAt: Date())
        let s = CompanyStore(loader: { id in id == "B" ? bState : .empty },
                             saver: { cid, _ in savedTo.append(cid); return true })
        // Account A hydrates → onboarding; capture A's token like the model does.
        await s.hydrate(companyId: "A")
        let aToken = s.onboardingToken
        XCTAssertTrue(s.isOnboarding)
        // Account switch: reset + hydrate B (already onboarded).
        s.reset()
        await s.hydrate(companyId: "B")
        XCTAssertFalse(s.isOnboarding)
        // A's stale finish arrives with the old token → must be discarded.
        await s.finishOnboarding(brief: CompanyBrief(projectName: "A-Co"), token: aToken)
        XCTAssertEqual(s.company.brief.projectName, "B-Co")  // B not clobbered
        XCTAssertFalse(savedTo.contains("B"))                // A's brief not written to B
    }

    func testScaffoldPersistsEnrichedBriefBeforeRoadmap() async {
        var savedBrief: CompanyBrief?
        var roadmapSawSummary: String?
        let s = CompanyStore(
            loader: { _ in .empty },
            saver: { _, b in savedBrief = b; return true },
            roadmapFetcher: { brief, _ in roadmapSawSummary = brief.summary; return [] },
            enricher: { raw in var e = raw; e.summary = "ENRICHED"; return e }
        )
        await s.hydrate(companyId: "u")
        _ = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "Codepet"),
                                           token: s.onboardingToken)
        XCTAssertEqual(savedBrief?.summary, "ENRICHED")       // enriched brief persisted
        XCTAssertEqual(s.company.brief.summary, "ENRICHED")   // enriched brief in state
        XCTAssertEqual(roadmapSawSummary, "ENRICHED")         // roadmap generated from enriched
    }

    func testScaffoldFailsOpenWhenEnrichThrows() async {
        struct E: Error {}
        var savedBrief: CompanyBrief?
        let s = CompanyStore(
            loader: { _ in .empty },
            saver: { _, b in savedBrief = b; return true },
            roadmapFetcher: { _, _ in [] },
            enricher: { _ in throw E() }
        )
        await s.hydrate(companyId: "u")
        _ = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "Raw"),
                                           token: s.onboardingToken)
        XCTAssertEqual(savedBrief?.projectName, "Raw")        // raw brief used, not blocked
        XCTAssertNil(savedBrief?.summary)                     // no enrichment applied
    }
}
