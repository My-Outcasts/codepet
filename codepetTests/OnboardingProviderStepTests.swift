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

    // No `testOnboardingWritesNoGrant` here — see `OnboardingProviderStep.passes`'s doc
    // comment. `passes(installed:)` takes no store and reaches no global, so it cannot
    // write a grant BY CONSTRUCTION; a test built around a `FakeAuthStore` that
    // `passes` has no way to touch would pass no matter what the code does (verified:
    // deleting the `passes(...)` call itself and even the whole app-level path that
    // reaches `ProviderAuthorisation` still left the old assertions green). Real
    // guarantee needs no test that cannot fail.
}
