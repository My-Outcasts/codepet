// codepet/Models/ContextPin.swift
import Foundation

/// What the founder pinned for the NEXT turn — spec §6.
///
/// **PROTOTYPE STATE (21 Aug).** The control, the pills, and the caps are real and
/// live in the app. What is NOT wired yet is the last hop: `ChatContext.compose`
/// does not take a `pinned:` parameter, so a pin is *visible* but does not yet
/// reach the model. That hop is Tasks 2-3 of the plan and touches grounding, which
/// this prototype deliberately does not.
///
/// **Why this exists at all.** Relevant prior work already reaches the model on
/// every turn: `ChatContext.selectPriorWork` ranks up to three Library deliverables
/// by token overlap against the founder's message. A pin does not add grounding, it
/// replaces the ranker's guess with the founder's choice. Describing it as
/// "attaching a document" would oversell it.
///
/// **Consumed by the send, like the department chip.** A pin is context for the next
/// message, not a session setting. `CopilotChatView.send` clears it, for the reason
/// written on `selectedDept` there: a selection that survives its send goes stale
/// out of the founder's eyeline, and she pays for the stale grounding every turn.
enum ContextPin: Identifiable, Equatable {
    /// A Library deliverable, by `Deliverable.id`.
    case deliverable(id: String, title: String)
    /// A roadmap task, by `RoadmapTask.id`.
    case task(id: String, title: String)

    /// **Namespaced by case, not the bare id.** Deliverable ids and task ids come
    /// from two different collections and nothing guarantees they don't collide; an
    /// un-namespaced id would let one pin silently replace the other.
    var id: String {
        switch self {
        case .deliverable(let id, _): return "deliverable:\(id)"
        case .task(let id, _):        return "task:\(id)"
        }
    }

    var title: String {
        switch self {
        case .deliverable(_, let title), .task(_, let title): return title
        }
    }

    var icon: String {
        switch self {
        case .deliverable: return "books.vertical"
        case .task:        return "map"
        }
    }

    /// A two-or-three-letter gloss on the pill, so a Library doc and a roadmap task
    /// are distinguishable at 11pt without reading the title.
    var gloss: String {
        switch self {
        case .deliverable: return "DOC"
        case .task:        return "TASK"
        }
    }

    /// The `Deliverable.id` when this pin is one. `ChatContext.compose` will build its
    /// exclusion set from this once pinning is wired, so a task must return nil here —
    /// a task id leaking into that set would drop an unrelated Library entry from the
    /// automatic prior-work block.
    var deliverableId: String? {
        if case .deliverable(let id, _) = self { return id }
        return nil
    }

    /// Matches `ChatAttachment.max`, and `selectPriorWork`'s own `max: 3`. Both are
    /// "things riding the next message", and the pill row shares one ceiling because
    /// two different ones would be arbitrary to the founder looking at it.
    static let max = 3

    /// Add, de-duped by `id` and capped at `max`.
    ///
    /// At the cap the NEW pin is dropped rather than the oldest evicted: silently
    /// removing a choice the founder already made and can see on screen is worse
    /// than declining one she has not made yet. The menu row disables at the cap, so
    /// this path is the backstop, not the UI.
    static func adding(_ pin: ContextPin, to pins: [ContextPin]) -> [ContextPin] {
        guard !pins.contains(where: { $0.id == pin.id }) else { return pins }
        guard pins.count < max else { return pins }
        return pins + [pin]
    }

    static func removing(_ pin: ContextPin, from pins: [ContextPin]) -> [ContextPin] {
        pins.filter { $0.id != pin.id }
    }

    /// The grounding block's heading, for when Task 2 wires this up. **English only,
    /// and not a function of `AppLanguage`:** this is prompt text the model reads,
    /// not chrome the founder reads, and the rest of `ChatContext` composes in
    /// English regardless of `uiLanguage`.
    static let groundingHeading =
        "The founder pinned this for this question — use it directly:"
}
