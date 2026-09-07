import XCTest
@testable import codepet

/// The enable-card had one state and two of its three cases were a lie: a pill that could not
/// fire (already-on, or unresolvable), and — the reported one — a pill that fired and said
/// nothing, so the founder read a working button as a broken one.
final class SetupCardStateTests: XCTestCase {

    private let webResearch = SetupAction(category: "skills", name: "Web research")

    /// Off and resolvable is the only state that may draw a button.
    func testAnOffItemIsAnOffer() {
        XCTAssertEqual(SetupCardState.of(webResearch, enabledTools: []),
                       .offer(Toolkit.find(category: "skills", name: "Web research")!))
    }

    /// **The reported bug.** Same card, same offer, after the press — it must no longer look
    /// like an unpressed button. Before this type, both sides of this comparison rendered
    /// identically, which is exactly why the press read as a no-op.
    func testTheSameOfferChangesStateOnceItIsOn() {
        let before = SetupCardState.of(webResearch, enabledTools: [])
        let after = SetupCardState.of(webResearch, enabledTools: ["web-research"])
        XCTAssertEqual(after, .enabled(Toolkit.find(category: "skills", name: "Web research")!))
        XCTAssertNotEqual(before, after)
    }

    /// An item that ships on must acknowledge from the first render, never dangle a pill that
    /// `activateSetup`'s `!enabledTools.contains` guard would drop. `github` is `defaultOn`,
    /// and `CompanyStoreChatTests.testDoneWithSetupAppendsSuggestionAndActivateSetupIsGuarded`
    /// pins that the store really does refuse it.
    func testAnAlreadyOnItemAcknowledgesRatherThanOffering() {
        let github = SetupAction(category: "connectors", name: "GitHub")
        let state = SetupCardState.of(github, enabledTools: Toolkit.defaultEnabledIds)
        XCTAssertEqual(state.item?.id, "github")
        guard case .enabled = state else {
            return XCTFail("a defaultOn item must not be offered: \(state)")
        }
    }

    /// No catalog item → no control, because no control could work. `item` is nil too, so the
    /// card falls back to the raw offered name for the transcript record.
    func testAnUnresolvableOfferDrawsNoControl() {
        let bogus = SetupAction(category: "skills", name: "Telepathy")
        XCTAssertEqual(SetupCardState.of(bogus, enabledTools: []), .unresolved)
        XCTAssertNil(SetupCardState.of(bogus, enabledTools: []).item)
    }

    /// A blank name cannot resolve — `Toolkit.find` guards it — and must not become an offer.
    func testABlankNameIsUnresolved() {
        XCTAssertEqual(SetupCardState.of(SetupAction(category: "skills", name: "   "),
                                         enabledTools: []),
                       .unresolved)
    }

    /// `Toolkit.find` falls back to a name-only match, so a category the model got wrong still
    /// resolves. Traced: the category+name predicate fails, the name-only one matches
    /// `web-research`. Worth pinning — it is the difference between a working card and a dead
    /// one when the two sides disagree about which bucket a tool is in.
    func testACategoryMismatchStillResolvesByName() {
        let wrongCategory = SetupAction(category: "connectors", name: "Web research")
        XCTAssertEqual(SetupCardState.of(wrongCategory, enabledTools: []).item?.id, "web-research")
    }

    /// And the match is case- and whitespace-insensitive, so a model that shouts or pads the
    /// name does not produce a dead pill.
    func testNameMatchingIgnoresCaseAndPadding() {
        let padded = SetupAction(category: "skills", name: "  WEB RESEARCH  ")
        XCTAssertEqual(SetupCardState.of(padded, enabledTools: []).item?.id, "web-research")
        XCTAssertEqual(SetupCardState.of(padded, enabledTools: ["web-research"]),
                       .enabled(Toolkit.find(category: "skills", name: "Web research")!))
    }

    /// Enabling something ELSE must not flip this card — the state is about this item, not
    /// about the set having grown. A `!enabledTools.isEmpty` shortcut would pass every test
    /// above and fail this one.
    func testAnUnrelatedEnabledToolLeavesTheOfferAlone() {
        XCTAssertEqual(SetupCardState.of(webResearch, enabledTools: ["notion", "prd-writer"]),
                       .offer(Toolkit.find(category: "skills", name: "Web research")!))
    }
}
