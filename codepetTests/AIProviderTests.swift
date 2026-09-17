import XCTest
@testable import codepet

/// Which of the founder's plans paid for a run.
///
/// `AIProvider` is a NAME, not a switch: nothing in this phase selects one (per-provider
/// consent is a later task). What it has to get right is the two things a name is read for —
/// the founder-facing label a run is credited with, and the raw value a stored or wire-encoded
/// choice round-trips through.
final class AIProviderTests: XCTestCase {

    /// The founder never sees `claudeCode`. She sees the product's own name, spelled the way
    /// its makers spell it — this string is what a run's credit line is built from.
    func testDisplayNamesAreTheFounderFacingProductNames() {
        XCTAssertEqual(AIProvider.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(AIProvider.codex.displayName, "Codex")
    }

    /// A provider added without a `displayName` arm cannot compile, but one added with an
    /// EMPTY or duplicated arm can — and either way the founder is told nothing useful about
    /// which plan she just spent. Driven off `allCases` so a third provider has to satisfy it.
    func testEveryProviderHasItsOwnNonEmptyDisplayName() {
        let names = AIProvider.allCases.map(\.displayName)
        for name in names {
            XCTAssertFalse(name.trimmingCharacters(in: .whitespaces).isEmpty,
                           "a provider with no label credits a run to nothing")
        }
        XCTAssertEqual(Set(names).count, names.count,
                       "two providers sharing a label makes the credit line ambiguous")
    }

    /// Both providers are enumerable, in declaration order. `CaseIterable` is what a later
    /// task's chooser iterates; a provider that exists but is not listed is unreachable there.
    func testBothProvidersAreEnumerated() {
        XCTAssertEqual(AIProvider.allCases, [.claudeCode, .codex])
    }

    /// The raw values are the STORED form. They are pinned as literals because a rename that
    /// only looks like a Swift refactor silently invalidates every persisted value — the
    /// founder's recorded provider reads back as nil and the run is credited to nobody.
    func testRawValuesArePinnedBecauseTheyArePersisted() {
        XCTAssertEqual(AIProvider.claudeCode.rawValue, "claudeCode")
        XCTAssertEqual(AIProvider.codex.rawValue, "codex")
        XCTAssertEqual(AIProvider(rawValue: "claudeCode"), .claudeCode)
        XCTAssertEqual(AIProvider(rawValue: "codex"), .codex)
        XCTAssertNil(AIProvider(rawValue: "Claude Code"),
                     "the display name is not the stored form; they must not be interchangeable")
    }
}
