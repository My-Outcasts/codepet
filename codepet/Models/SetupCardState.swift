import Foundation

/// What an enable-card should DRAW, given the offer and what is already on.
///
/// **This exists because the card had exactly one state and two of the three cases were a
/// lie.** `setupInline` rendered a name, an optional why-line and an Enable pill, none of
/// which read `enabledTools` — so pressing Enable changed nothing on screen. It worked:
/// `activateSetup` resolved the item, flipped it on and persisted it. The founder pressed
/// "Web research", got no acknowledgement of any kind, and reported that she could not press
/// the button (7 Sep). Proven after the fact from the local Firestore cache, which held one
/// record of `enabledTools` without `web-research` and a later one with it.
///
/// The other two cases were genuinely dead pills, and both are `guard`s in `activateSetup`
/// that return silently:
///   - the item is ALREADY on — `!enabledTools.contains(item.id)` fails. Reachable: a second
///     press of the same card, and `CompanyStoreChatTests`
///     `testDoneWithSetupAppendsSuggestionAndActivateSetupIsGuarded` pins the behaviour.
///   - the {category,name} resolves to no catalog item at all — nothing to toggle. The live
///     path validates the model's choice against the client's own list, so this should be
///     unreachable there; it stays a case rather than a `precondition` because the card is
///     built from a decoded payload, and a card that cannot act must not show a pill that
///     pretends it can.
///
/// Pure, so the three cases are testable without a store or a view — same shape as
/// `DepartmentChipState.of` and `MessageActionRules.canRetry`.
enum SetupCardState: Equatable {
    /// Resolvable and currently off: draw the Enable button. It is the only state that can act.
    case offer(ToolItem)
    /// Resolvable and already on: acknowledge it, and draw NO button. Retired rather than
    /// removed, the same rule `runProposalCard` follows — a vanished affordance loses the
    /// fact that the thing is on.
    case enabled(ToolItem)
    /// Resolves to nothing in the catalog: keep the transcript record of what was offered,
    /// but draw no control, because no control could work.
    case unresolved
    /// Resolvable, off, and does nothing yet: title it, and draw NO button.
    ///
    /// Distinct from `unresolved` on purpose — the item is real and nameable, it
    /// simply has no implementation — and distinct from `offer` because the rule
    /// this whole type exists to enforce is that a card which cannot act must not
    /// show a pill that pretends it can. Without this case, `toggleTool`'s guard
    /// would turn the press into a silent no-op: the 7 Sep bug exactly.
    case notBuilt(ToolItem)

    /// `builtSkills` is required rather than defaulted: a defaulted gate is how
    /// `sendChat`'s `convenesRoom:` left eight tests red for a day, and this one
    /// decides whether a control appears at all.
    static func of(_ setup: SetupAction,
                   enabledTools: Set<String>,
                   builtSkills: Set<String>) -> SetupCardState {
        guard let item = Toolkit.find(category: setup.category, name: setup.name) else {
            return .unresolved
        }
        // Already-on is checked FIRST, so a stored id for something since un-built
        // still acknowledges rather than reading as unavailable.
        if enabledTools.contains(item.id) { return .enabled(item) }
        return item.isBuilt(builtSkills: builtSkills) ? .offer(item) : .notBuilt(item)
    }

    /// The item behind the offer, when there is one — what the card titles itself with.
    var item: ToolItem? {
        switch self {
        case .offer(let i), .enabled(let i), .notBuilt(let i): return i
        case .unresolved: return nil
        }
    }
}
