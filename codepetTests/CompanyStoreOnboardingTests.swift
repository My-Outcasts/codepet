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

    /// Regression (finding I1): the wizard's final "Start building" step must finish
    /// onboarding with the store's already-enriched `company.brief` — NOT a freshly
    /// reconstructed raw draft — or the enriched summary/audience/categories get
    /// clobbered by finishOnboarding's persist+assign. Simulates the real call site
    /// (OnboardingView.finishWithCompanion): scaffold enriches, then finish is called
    /// with `s.company.brief` (the fix), and the enrichment must survive in both the
    /// saved brief and in-memory state.
    func testEnrichedBriefSurvivesScaffoldThenFinish() async {
        var savedBrief: CompanyBrief?
        let s = CompanyStore(
            loader: { _ in .empty },
            saver: { _, b in savedBrief = b; return true },
            roadmapFetcher: { _, _ in [] },
            enricher: { raw in var e = raw; e.summary = "ENRICHED"; return e }
        )
        await s.hydrate(companyId: "u")
        let token = s.onboardingToken
        _ = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "Codepet"), token: token)
        XCTAssertEqual(s.company.brief.summary, "ENRICHED")   // sanity: scaffold enriched it

        // Finish using the store's current (enriched) brief, as the fixed call site does.
        await s.finishOnboarding(brief: s.company.brief, token: token)

        XCTAssertEqual(savedBrief?.summary, "ENRICHED")       // persisted brief still enriched
        XCTAssertEqual(s.company.brief.summary, "ENRICHED")   // in-memory brief still enriched
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

    /// Regression (finding I2): if "Start building" is reached while the step-6
    /// scaffold Task is still in-flight, `finishWithCompanion`'s `scaffoldTask?.cancel()`
    /// can trip a cancellation guard inside `scaffoldFromOnboarding` BEFORE it ever
    /// assigns `company.brief = enriched` — leaving `company.brief` at its empty
    /// default. The view-level fix (OnboardingView.finishWithCompanion) guards against
    /// persisting that empty brief by choosing:
    ///   `company.brief.hasAnySignal ? company.brief : brief()` (the raw step 1-5 draft)
    /// `finishWithCompanion` is a private SwiftUI View func and not directly unit-
    /// testable, so this test pins the discriminator at the store/model boundary that
    /// the fix relies on: an empty `CompanyBrief` must read `hasAnySignal == false`
    /// (triggering the raw-draft fallback), while a populated/enriched brief — the
    /// happy path and the fail-open path — must read `hasAnySignal == true` (using the
    /// store's brief, preserving enrichment). If either flips, the view's fallback
    /// branch stops firing when it should (or fires when it shouldn't).
    func testFinishWithEmptyBriefFallbackContract() {
        // Race outcome: scaffold cancelled before `company.brief = enriched` ran.
        let racedEmpty = CompanyBrief()
        XCTAssertFalse(racedEmpty.hasAnySignal)                // must fall back to brief()

        // Happy path: scaffold completed and enriched the brief.
        var enriched = CompanyBrief(projectName: "Codepet", oneLiner: "x")
        enriched.summary = "ENRICHED"
        XCTAssertTrue(enriched.hasAnySignal)                   // must use company.brief as-is

        // Fail-open path: enrichment threw, company.brief == the raw brief (still signal).
        let failOpenRaw = CompanyBrief(projectName: "Codepet", oneLiner: "x")
        XCTAssertTrue(failOpenRaw.hasAnySignal)                // must use company.brief as-is
    }
}
