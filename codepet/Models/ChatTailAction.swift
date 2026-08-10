// codepet/Models/ChatTailAction.swift
import Foundation

/// What a chat turn owes its placeholder message once the companion stream is over.
///
/// A value type, in its own file, deliberately: three stream outcomes (threw, ended
/// with no `done`, ended clean) cross two text outcomes (empty, non-empty) and the
/// wrong answer either fires a second `chatSender` — running the same task twice —
/// or leaves the founder staring at an empty bubble.
///
/// The Virtual Company fan-out is deliberately NOT an input here. It used to be: the
/// room rewrote byte's own message, so every write in the tail had to re-ask "did the
/// room take this turn". The room now owns a separate appended message, so byte's
/// tail is exactly what it was before the feature existed.
enum ChatTailAction: Equatable {
    /// companyChat never delivered a well-formed reply (it threw, or it answered
    /// with no `done` frame — the shape a pre-deploy plain-JSON response collapses
    /// to). Call the non-streaming sender and fill the placeholder from it.
    case fallback
    /// A `done` arrived but byte sent zero chat text. Write a lead-in so the bubble is
    /// not left blank — the one this action's promise can actually keep.
    case leadIn(LeadIn)
    /// Leave the placeholder exactly as it stands.
    case none

    /// Which promise the lead-in is allowed to make. Only a run is "putting that
    /// together now": that one line used to be written for EVERY textless reply, so a
    /// reply whose only action was a nav chip announced work that was never going to
    /// happen — observed in the app, Aug 5, as "On it — putting that together now."
    /// above a "Go to Company" chip, twice, with nothing being put together either time.
    enum LeadIn: Equatable {
        /// A task is about to be produced in the chat.
        case run
        /// A place in the app is on offer; nothing is being made.
        case nav
        /// A toolkit item is on offer to turn on.
        case setup
        /// Nothing but facts to remember came back.
        case noted
        /// A roadmap change is on offer — mark a task done, or add one. Nothing is being made
        /// and nothing has changed: the founder presses the button in the card below.
        case roadmap
        /// A well-formed reply that said nothing and offered nothing.
        case nothing
    }

    static func decide(streamThrew: Bool,
                       receivedDone: Bool,
                       streamedText: String,
                       action: ChatDoneAction?) -> ChatTailAction {
        if streamThrew || !receivedDone { return .fallback }
        // Gated on "no `done`", NOT on empty text: byte can legitimately reply with
        // only a run-task decision, and falling back there would fire a second
        // chatSender call and run the same task twice.
        guard streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
        // A `done` carrying neither text nor any action is not a reply — it is a turn that
        // produced nothing, and the founder was being shown that as an answer ("I didn't have
        // an answer for that"). Measured in the app on Aug 5: `frame done — 63 bytes`, zero
        // delta frames, `chars=0`, while the Virtual Company room for the same turn came back
        // complete. So retry once on the non-streaming path — a second, independent generation
        // — instead of printing the dead end.
        //
        // Safe against the duplicate-run bug this file exists to prevent: the old defect was
        // falling back when a VALID `run_task` had already been dispatched, which ran it twice.
        // This falls back ONLY when nothing was dispatched at all, so there is no side effect
        // to repeat. A run-task-only reply still takes `.leadIn(.run)` and never lands here.
        if isEmpty(action) { return .fallback }
        return .leadIn(leadIn(for: action))
    }

    /// Nothing to show and nothing to do: no task, no destination, no toolkit item, no fact,
    /// no roadmap change.
    ///
    /// The two roadmap verbs were added on Aug 8 and this function was NOT updated, which broke
    /// them the first time the founder used one. Measured in the app, Aug 10: `response 200`,
    /// `frame done — 118 bytes`, `threw=false done=true chars=0`, `tail=fallback`. The model had
    /// replied with no prose and only a `complete_task` call — a perfectly good turn — and this
    /// check, seeing four nil fields it knew about, called it empty, fell back to a second
    /// generation, and printed "I can't reach my brain right now" over a working backend.
    ///
    /// EVERY new action field has to be added here and to `leadIn`. That is the third time this
    /// week an action was added without updating everything that reasons about actions (the
    /// non-streaming `ChatDoneAction` construction, then the mark-done grounding, now this).
    private static func isEmpty(_ action: ChatDoneAction?) -> Bool {
        guard let action else { return true }
        return action.runTaskId == nil && action.nav == nil && action.setup == nil
            && action.remember.isEmpty
            && action.completeTaskId == nil && action.addTask == nil
    }

    /// Precedence mirrors the CF's own: `run_task`/`navigate`/`setup_capability` are
    /// mutually exclusive there (it sets at most one), and `remember` is orthogonal and
    /// can ride along with any of them — so it only decides the line when it arrived alone.
    private static func leadIn(for action: ChatDoneAction?) -> LeadIn {
        guard let action else { return .nothing }
        if action.runTaskId != nil { return .run }
        if action.nav != nil { return .nav }
        if action.setup != nil { return .setup }
        if action.completeTaskId != nil || action.addTask != nil { return .roadmap }
        if !action.remember.isEmpty { return .noted }
        return .nothing
    }
}
