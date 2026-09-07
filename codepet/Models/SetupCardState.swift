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

    static func of(_ setup: SetupAction, enabledTools: Set<String>) -> SetupCardState {
        guard let item = Toolkit.find(category: setup.category, name: setup.name) else {
            return .unresolved
        }
        return enabledTools.contains(item.id) ? .enabled(item) : .offer(item)
    }

    /// The item behind the offer, when there is one — what the card titles itself with.
    var item: ToolItem? {
        switch self {
        case .offer(let i), .enabled(let i): return i
        case .unresolved: return nil
        }
    }
}
