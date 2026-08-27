// codepetTests/MockFlowTests.swift
import XCTest
@testable import codepet

/// The full-flow demo: `-CODEPET_MOCK_FLOW YES` must start at the cold open
/// and end in a populated company, with no network anywhere in between.
///
/// Worth testing rather than eyeballing, because both ends fail SILENTLY in
/// the same direction — a wrong `needsOnboarding` lands the founder straight
/// in the shell, and a wrong roadmap fixture leaves them in an empty one.
/// Either looks like "the demo doesn't work" with nothing saying why.
@MainActor
final class MockFlowTests: XCTestCase {

    private var previousChat: Any?
    private var previousFlow: Any?

    override func setUp() {
        super.setUp()
        previousChat = PrototypeMode.store.object(forKey: "CODEPET_MOCK_CHAT")
        previousFlow = PrototypeMode.store.object(forKey: "CODEPET_MOCK_FLOW")
        MockChat.flowOnboarded = false
        MockChat.flowBrief = nil
    }

    override func tearDown() {
        MockChat.flowBrief = nil
        restore("CODEPET_MOCK_CHAT", previousChat)
        restore("CODEPET_MOCK_FLOW", previousFlow)
        // Process-global. Left true, every later suite that reads it would see
        // a demo mid-walkthrough.
        MockChat.flowOnboarded = false
        super.tearDown()
    }

    private func restore(_ key: String, _ value: Any?) {
        if let value { PrototypeMode.store.set(value, forKey: key) }
        else { PrototypeMode.store.removeObject(forKey: key) }
    }

    // MARK: - the flag

    func testFlowImpliesMockSoOneArgumentRunsTheWholeThing() {
        // Two flags where one is meaningless without the other is a state you
        // can get half-right: mock off + flow on would run onboarding against
        // the real, dead backend.
        PrototypeMode.store.set(false, forKey: "CODEPET_MOCK_CHAT")
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        XCTAssertTrue(MockChat.enabled, "flow mode did not imply mock mode")
        XCTAssertTrue(MockChat.flowEnabled)
    }

    func testPlainMockModeDoesNotStartAtOnboarding() {
        // The existing behaviour, unchanged: `-CODEPET_MOCK_CHAT` alone boots
        // an already-onboarded company, which is what makes chat and
        // engineering reachable in one launch.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_CHAT")
        PrototypeMode.store.set(false, forKey: "CODEPET_MOCK_FLOW")
        XCTAssertTrue(MockChat.enabled)
        XCTAssertFalse(MockChat.flowEnabled)
    }

    // MARK: - the two ends of the walk

    func testTheDemoStartsBeforeOnboardingRatherThanAfterIt() {
        // `needsOnboarding` checks BOTH an absent stamp and a brief with no
        // signal. A blank brief carrying a stamp, or a stamped brief with
        // fields, would each land in the shell and skip the whole cold open.
        let fresh = MockChat.preOnboardingCompany()
        XCTAssertNil(fresh.onboardedAt)
        XCTAssertFalse(fresh.brief.hasAnySignal,
                       "the demo brief has signal, so onboarding would be skipped")
        XCTAssertTrue(fresh.tasks.isEmpty)
    }

    func testTheLoaderItselfIsWhatSendsTheDemoThroughOnboarding() async {
        // Calls `CompanyData.load` DIRECTLY rather than injecting a loader.
        //
        // Every other test here supplies its own closure, which means none of
        // them touch the branch that actually decides — deleting it left this
        // suite green. That is the same hole `EngineeringReachabilityTests`
        // exists for: correct pieces, unconnected wire. The mock path returns
        // before Firestore is touched, so this is safe to call in a test.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")

        MockChat.flowOnboarded = false
        let before = await CompanyData.load(companyId: "demo")
        XCTAssertNil(before.onboardedAt, "the demo boots past the cold open")
        XCTAssertTrue(before.tasks.isEmpty)

        MockChat.flowOnboarded = true
        let after = await CompanyData.load(companyId: "demo")
        XCTAssertNotNil(after.onboardedAt, "the demo loops back into onboarding")
        XCTAssertFalse(after.tasks.isEmpty, "the founder lands in an empty company")
    }

    func testTheRoadmapFetcherItselfAnswersFromTheFixture() async {
        // Same reasoning: `generateRoadmap` treats an empty result as "no
        // change", so a fetcher that fell through to the network would leave
        // the board empty and say nothing about why.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        var brief = CompanyBrief()
        brief.projectName = "Codepet"
        let tasks = await CompanyData.fetchRoadmap(brief: brief, language: .en)
        XCTAssertFalse(tasks.isEmpty, "the demo's board would be empty")
    }

    func testFinishingOnboardingLeavesTheDemoOnboarded() async {
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        let store = CompanyStore(loader: { _ in MockChat.preOnboardingCompany() },
                                 saver: { _, _ in true })
        await store.hydrate(companyId: "demo")
        XCTAssertTrue(store.isOnboarding, "the demo did not start at the cold open")

        var brief = CompanyBrief()
        brief.founderName = "Mona"
        brief.projectName = "Codepet"
        await store.finishOnboarding(brief: brief, token: store.onboardingToken)

        XCTAssertFalse(store.isOnboarding)
        // Without this, the next hydrate — an account switch, a sign-out —
        // drops the founder back at the cold open mid-walkthrough.
        XCTAssertTrue(MockChat.flowOnboarded)
    }

    func testSkippingCountsAsFinishing() async {
        // Otherwise Skip appears not to have worked: it leaves onboarding, and
        // the next hydrate puts them straight back into it.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        let store = CompanyStore(loader: { _ in MockChat.preOnboardingCompany() },
                                 saver: { _, _ in true })
        await store.hydrate(companyId: "demo")

        await store.skipOnboarding()

        XCTAssertFalse(store.isOnboarding)
        XCTAssertTrue(MockChat.flowOnboarded)
    }

    // MARK: - what the founder lands in

    func testTheFakeCompanyHasWorkCodepetCanActuallyRun() {
        // The roadmap fixture is the whole point of landing in a company: an
        // empty board makes every downstream surface — chat's runnable list,
        // the fan-out, the Tasks page — demo as if broken.
        let tasks = MockChat.roadmap()
        XCTAssertFalse(tasks.isEmpty)
        let depts = Set(tasks.filter { $0.who == .draft && $0.phase == .find }.map { $0.dept })
        XCTAssertGreaterThanOrEqual(depts.count, 3,
            "fewer than three departments have runnable work, so the fan-out demos as one agent")
    }

    // MARK: - whose project is this

    func testTheDemoKeepsTheProjectTheFounderTyped() async {
        // The bug this closes: `CompanyData.load` answers every hydrate after
        // onboarding with `company()`, whose brief was hardcoded — so a
        // founder who onboarded something else watched their project silently
        // become Codepet on the next account switch.
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_FLOW")
        let store = CompanyStore(loader: { _ in MockChat.preOnboardingCompany() },
                                 saver: { _, _ in true })
        await store.hydrate(companyId: "demo")

        var brief = CompanyBrief()
        brief.founderName = "Mona"
        brief.projectName = "Murror"
        await store.finishOnboarding(brief: brief, token: store.onboardingToken)

        let reloaded = await CompanyData.load(companyId: "demo")
        XCTAssertEqual(reloaded.brief.projectName, "Murror",
                       "the demo replaced the founder's project with the fixture's")
    }

    func testCannedCopyNamesTheFoundersProductNotOurs() {
        // Thirteen hardcoded mentions used to say "Codepet" no matter what was
        // onboarded, which reads as the fixture having ignored what they typed.
        var brief = CompanyBrief()
        brief.projectName = "Murror"
        MockChat.flowBrief = brief

        let filled = MockChat.fill("Here's where {{product}} stands.")
        XCTAssertEqual(filled, "Here's where Murror stands.")
        XCTAssertFalse(filled.contains("{{"), "a token leaked into copy the founder reads")
    }

    func testWithNoFlowBriefTheCopyStillNamesSomething() {
        // Plain `-CODEPET_MOCK_CHAT` never captures a brief. The token must
        // still resolve — a raw `{{product}}` on screen is worse than a name
        // that happens to be ours.
        MockChat.flowBrief = nil
        XCTAssertEqual(MockChat.fill("{{product}} ships."), "Codepet ships.")
    }

    func testABlankProjectNameDoesNotProduceAnEmptySentence() {
        var brief = CompanyBrief()
        brief.projectName = "   "
        MockChat.flowBrief = brief
        XCTAssertEqual(MockChat.fill("{{product}} ships."), "Codepet ships.")
    }

    // MARK: - enrichment

    func testEnrichmentFillsTheBlanksAndKeepsWhatWasTyped() {
        // A mock that overwrote the founder's own words would show them
        // someone else's project at the reveal — the moment the whole
        // onboarding gets judged on.
        var brief = CompanyBrief()
        brief.projectName = "Codepet"
        brief.oneLiner = "My own sentence."
        let enriched = MockChat.enrich(brief)

        XCTAssertEqual(enriched.oneLiner, "My own sentence.")
        XCTAssertFalse((enriched.audience ?? "").isEmpty, "a blank field was left blank")
        XCTAssertFalse((enriched.goal ?? "").isEmpty)
    }

    func testEnrichmentTreatsWhitespaceAsEmpty() {
        // A founder who tabbed through and one who typed spaces both left it
        // empty; the real enricher fills both.
        var brief = CompanyBrief()
        brief.projectName = "Codepet"
        brief.oneLiner = "   "
        let enriched = MockChat.enrich(brief)
        XCTAssertTrue((enriched.oneLiner ?? "").contains("Codepet"),
                      "a whitespace-only sentence was treated as written")
    }

    func testEnrichmentNamesTheProjectTheFounderTyped() {
        var brief = CompanyBrief()
        brief.projectName = "Murror"
        let enriched = MockChat.enrich(brief)
        XCTAssertTrue((enriched.oneLiner ?? "").contains("Murror"),
                      "the reveal would show a project the founder never named")
    }
}
