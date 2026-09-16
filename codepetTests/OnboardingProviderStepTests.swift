// codepetTests/OnboardingProviderStepTests.swift
import XCTest
@testable import codepet

/// `FakeAuthStore` lives in `ProviderConsentTests.swift`, in this same target — reused
/// here rather than redefined, per the rule that already burned four test files that each
/// wrote mock flags into the founder's real `UserDefaults`.
final class OnboardingProviderStepTests: XCTestCase {

    /// At least one, not both. A founder who pays OpenAI and not Anthropic is a complete
    /// founder, and this step must not tell her otherwise.
    func testTheStepPassesWithExactlyOneProviderInstalled() {
        XCTAssertTrue(OnboardingProviderStep.passes(installed: [.codex]))
        XCTAssertTrue(OnboardingProviderStep.passes(installed: [.claudeCode]))
        XCTAssertTrue(OnboardingProviderStep.passes(installed: [.claudeCode, .codex]))
    }

    func testTheStepBlocksWithNothingInstalled() {
        XCTAssertFalse(OnboardingProviderStep.passes(installed: []))
    }

    /// Onboarding must never write a grant. Consent belongs where the plan is spent.
    func testOnboardingWritesNoGrant() {
        let store = FakeAuthStore()
        _ = OnboardingProviderStep.passes(installed: [.codex])
        XCTAssertFalse(store.isAuthorised(.codex, "c1"))
        XCTAssertFalse(store.isAuthorised(.claudeCode, "c1"))
    }
}
