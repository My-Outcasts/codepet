import XCTest
@testable import codepet

/// The enable-card had one state and two of its three cases were a lie: a pill that could not
/// fire (already-on, or unresolvable), and — the reported one — a pill that fired and said
/// nothing, so the founder read a working button as a broken one.
final class SetupCardStateTests: XCTestCase {

    private let webResearch = SetupAction(category: "skills", name: "Web research")

    /// Off and resolvable is the only state that may draw a button.
    func testAnOffItemIsAnOffer() {
        XCTAssertEqual(SetupCardState.of(webResearch, enabledTools: [], builtSkills: Toolkit.bundledBuiltSkills),
                       .offer(Toolkit.find(category: "skills", name: "Web research")!))
    }

    /// **The reported bug.** Same card, same offer, after the press — it must no longer look
    /// like an unpressed button. Before this type, both sides of this comparison rendered
    /// identically, which is exactly why the press read as a no-op.
    func testTheSameOfferChangesStateOnceItIsOn() {
        let before = SetupCardState.of(webResearch, enabledTools: [], builtSkills: Toolkit.bundledBuiltSkills)
        let after = SetupCardState.of(webResearch, enabledTools: ["web-research"], builtSkills: Toolkit.bundledBuiltSkills)
        XCTAssertEqual(after, .enabled(Toolkit.find(category: "skills", name: "Web research")!))
        XCTAssertNotEqual(before, after)
    }

    /// An item that ships on must acknowledge from the first render, never dangle a pill that
    /// `activateSetup`'s `!enabledTools.contains` guard would drop. `github` is `defaultOn`,
    /// and `CompanyStoreChatTests.testDoneWithSetupAppendsSuggestionAndActivateSetupIsGuarded`
    /// pins that the store really does refuse it.
    func testAnAlreadyOnItemAcknowledgesRatherThanOffering() {
        let github = SetupAction(category: "connectors", name: "GitHub")
        let state = SetupCardState.of(github, enabledTools: Toolkit.defaultEnabledIds, builtSkills: Toolkit.bundledBuiltSkills)
        XCTAssertEqual(state.item?.id, "github")
        guard case .enabled = state else {
            return XCTFail("a defaultOn item must not be offered: \(state)")
        }
    }

    /// No catalog item → no control, because no control could work. `item` is nil too, so the
    /// card falls back to the raw offered name for the transcript record.
    func testAnUnresolvableOfferDrawsNoControl() {
        let bogus = SetupAction(category: "skills", name: "Telepathy")
        XCTAssertEqual(SetupCardState.of(bogus, enabledTools: [], builtSkills: Toolkit.bundledBuiltSkills), .unresolved)
        XCTAssertNil(SetupCardState.of(bogus, enabledTools: [], builtSkills: Toolkit.bundledBuiltSkills).item)
    }

    /// A blank name cannot resolve — `Toolkit.find` guards it — and must not become an offer.
    func testABlankNameIsUnresolved() {
        XCTAssertEqual(SetupCardState.of(SetupAction(category: "skills", name: "   "),
                                         enabledTools: [],
                                         builtSkills: Toolkit.bundledBuiltSkills),
                       .unresolved)
    }

    /// `Toolkit.find` falls back to a name-only match, so a category the model got wrong still
    /// resolves. Traced: the category+name predicate fails, the name-only one matches
    /// `web-research`. Worth pinning — it is the difference between a working card and a dead
    /// one when the two sides disagree about which bucket a tool is in.
    func testACategoryMismatchStillResolvesByName() {
        let wrongCategory = SetupAction(category: "connectors", name: "Web research")
        XCTAssertEqual(SetupCardState.of(wrongCategory, enabledTools: [], builtSkills: Toolkit.bundledBuiltSkills).item?.id, "web-research")
    }

    /// And the match is case- and whitespace-insensitive, so a model that shouts or pads the
    /// name does not produce a dead pill.
    func testNameMatchingIgnoresCaseAndPadding() {
        let padded = SetupAction(category: "skills", name: "  WEB RESEARCH  ")
        XCTAssertEqual(SetupCardState.of(padded, enabledTools: [], builtSkills: Toolkit.bundledBuiltSkills).item?.id, "web-research")
        XCTAssertEqual(SetupCardState.of(padded, enabledTools: ["web-research"], builtSkills: Toolkit.bundledBuiltSkills),
                       .enabled(Toolkit.find(category: "skills", name: "Web research")!))
    }

    /// Enabling something ELSE must not flip this card — the state is about this item, not
    /// about the set having grown. A `!enabledTools.isEmpty` shortcut would pass every test
    /// above and fail this one.
    func testAnUnrelatedEnabledToolLeavesTheOfferAlone() {
        XCTAssertEqual(SetupCardState.of(webResearch, enabledTools: ["notion", "prd-writer"], builtSkills: Toolkit.bundledBuiltSkills),
                       .offer(Toolkit.find(category: "skills", name: "Web research")!))
    }

    /// A card for an unbuilt item must draw no pill. NOT reachable from stale
    /// transcript history — `chatMessages` is session-only and non-`Codable`, and
    /// `env_setup` only ever offers items that are both off and built, so a card
    /// can't be minted for an unbuilt item in the first place. The genuinely
    /// reachable path is mid-session: `refreshCapabilities()` narrows `builtSkills`
    /// after a card from earlier in the same session already exists. Without this
    /// case, the press would hit `toggleTool`'s guard and return silently, which is
    /// the 7 Sep bug all over again.
    func testAnUnbuiltItemDrawsNoControlEvenThoughItIsOff() {
        let codeReview = SetupAction(category: "skills", name: "Code review")
        let state = SetupCardState.of(codeReview,
                                      enabledTools: [],
                                      builtSkills: Toolkit.bundledBuiltSkills)
        XCTAssertEqual(state, .notBuilt(Toolkit.find(category: "skills", name: "Code review")!))
        // The name is still carried, so the transcript keeps the record of the offer.
        XCTAssertEqual(state.item?.id, "code-review")
    }

    func testAnAgentOfferIsNeverAnOffer() {
        let testWriter = SetupAction(category: "agents", name: "Test Writer")
        XCTAssertEqual(SetupCardState.of(testWriter,
                                         enabledTools: [],
                                         builtSkills: Set(Toolkit.catalog.map(\.id))),
                       .notBuilt(Toolkit.find(category: "agents", name: "Test Writer")!))
    }

    func testAManifestThatBuildsASkillRestoresItsOffer() {
        let codeReview = SetupAction(category: "skills", name: "Code review")
        XCTAssertEqual(SetupCardState.of(codeReview,
                                         enabledTools: [],
                                         builtSkills: ["code-review"]),
                       .offer(Toolkit.find(category: "skills", name: "Code review")!))
    }

    /// Pins the ordering in `of`: unbuilt is checked BEFORE already-on. A stored-on id for
    /// an unbuilt item (the mid-session-narrowing case `.notBuilt`'s doc comment describes)
    /// must render `.notBuilt`, never `.enabled` — it does nothing, and saying "Enabled" for
    /// something that does nothing is exactly the fiction this whole type exists to remove.
    /// Checked by inverting the order back locally and confirming this is the only test in
    /// the suite that goes red: every other `.enabled` fixture uses a built item.
    func testAStoredOnButUnbuiltItemIsNotBuiltNotEnabled() {
        let codeReview = SetupAction(category: "skills", name: "Code review")
        let state = SetupCardState.of(codeReview,
                                      enabledTools: ["code-review"],
                                      builtSkills: Toolkit.bundledBuiltSkills)
        XCTAssertEqual(state, .notBuilt(Toolkit.find(category: "skills", name: "Code review")!))
    }
}
