import XCTest
@testable import codepet

/// CP-063. A brand-new founder finished onboarding with an EMPTY company: no roadmap, no
/// greeting, every department "LATER" — while step 8 said "I built your roadmap". Onboarding
/// never asked for the Claude grant, so "Analyze my project" ran enrichment + `generateRoadmap`
/// through a transport that answers `.blocked(.notGranted)`, fail-open returned nothing, and
/// the reveal fell back to its generic copy. Found 5 Oct on build 8 with a fresh account.
///
/// Founder's call: ask for the grant at "Analyze my project" — the moment the plan is first
/// spent, which is the rule `ProviderConsentFlow` already states.
final class OnboardingGrantGateTests: XCTestCase {

    func testAsksWhenClaudeIsInstalledButNotGranted() {
        XCTAssertTrue(OnboardingGrantGate.shouldAsk(installed: [.claudeCode], authorised: { _ in false }))
    }

    func testDoesNotAskWhenAlreadyGranted() {
        XCTAssertFalse(OnboardingGrantGate.shouldAsk(installed: [.claudeCode], authorised: { $0 == .claudeCode }))
    }

    /// A Codex grant is a grant: the analysis can run on it, so asking about Claude would be a
    /// question with no consequence.
    func testDoesNotAskWhenAnyInstalledProviderIsGranted() {
        XCTAssertFalse(OnboardingGrantGate.shouldAsk(installed: [.claudeCode, .codex], authorised: { $0 == .codex }))
    }

    /// Nothing installed is the provider step's job (it already gates "Start building"); a
    /// grant for a CLI that is not there would change nothing.
    func testDoesNotAskWhenNothingIsInstalled() {
        XCTAssertFalse(OnboardingGrantGate.shouldAsk(installed: [], authorised: { _ in false }))
    }

    /// Asks about the provider that will actually run — Claude first, the default transport.
    func testAsksAboutClaudeFirst() {
        XCTAssertEqual(OnboardingGrantGate.providerToAsk(installed: [.codex, .claudeCode]), .claudeCode)
        XCTAssertEqual(OnboardingGrantGate.providerToAsk(installed: [.codex]), .codex)
        XCTAssertNil(OnboardingGrantGate.providerToAsk(installed: []))
    }

    /// Not "Re-running here…": nothing has run yet (CP-066 found that wording on a first grant).
    func testTheAskSaysWhatItIsFor() {
        let en = ProviderConsentCopy.planMessage(.claudeCode, lang: .en)
        XCTAssertEqual(en, "Building your plan uses your Claude plan. Allow Codepet to spend it?")
        XCTAssertFalse(en.contains("Re-running"))
        XCTAssertFalse(ProviderConsentCopy.planMessage(.claudeCode, lang: .vi).isEmpty)
    }

    func testNotNowSaysWhyTheFounderIsStillHere() {
        XCTAssertEqual(OnboardingGrantGate.declinedLine(.claudeCode, lang: .en),
                       "Codepet needs your Claude plan to build your plan. You can skip onboarding and allow it later.")
    }
}

/// CP-067. The scaffold behind step 8 is two plan calls in a row — enrichment, then
/// `generateRoadmap` — each bounded at `LocalOneShotRunner.defaultTimeout` (180 s) on the
/// founder's own Claude plan. A 20 s fallback (sized for the old cloud path) showed the generic
/// step 8 at ~25 s on 5 Oct while the real roadmap took ~80 s, and "Start building" then
/// cancelled it, leaving the same empty company as CP-063.
final class OnboardingScaffoldTimingTests: XCTestCase {
    func testTheFallbackOutlastsBothPlanCalls() {
        XCTAssertGreaterThan(OnboardingScaffoldTiming.fallbackSeconds,
                             2 * LocalOneShotRunner.defaultTimeout)
    }

    func testStartBuildingDoesNotCancelARunningScaffold() {
        XCTAssertFalse(OnboardingScaffoldTiming.finishCancelsScaffold)
    }

    func testTheWaitLineSaysItCanTakeAMinute() {
        XCTAssertEqual(OnboardingScaffoldTiming.stillBuildingLine,
                       "Still building your company — this can take a minute or two.")
    }
}
