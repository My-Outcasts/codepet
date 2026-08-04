// codepet/Models/ChatTailAction.swift
import Foundation

/// What a chat turn owes its placeholder message once the companion stream is over.
///
/// A value type, in its own file, deliberately: the Virtual Company fan-out made
/// this the riskiest branch in `CompanyStore.sendMessage`, because four orderings of
/// "did the room take this turn" against "did companyChat answer" all land here, and
/// getting any one of them wrong either clobbers the room's handoff line or leaves
/// the founder staring at an empty bubble. `CompanyStore` itself cannot be unit
/// tested under Xcode 26.2 (the isolated-deinit teardown bug crashes the XCTest
/// host), so the decision lives where tests can reach it and the store only obeys it.
enum ChatTailAction: Equatable {
    /// companyChat never delivered a well-formed reply (it threw, or it answered
    /// with no `done` frame — the shape a pre-deploy plain-JSON response collapses
    /// to). Call the non-streaming sender and fill the placeholder from it.
    case fallback
    /// A `done` arrived but byte sent zero chat text — a run-task-only reply. Write
    /// the lead-in so the bubble is not left blank.
    case leadIn
    /// Leave the placeholder exactly as it stands.
    case none

    /// `roomTookOver` must be read fresh at the moment of the decision, never cached
    /// from before an `await`: a handoff can land while `chatSender` is in flight,
    /// and `CompanyStore` re-decides after that await for exactly this reason.
    static func decide(streamThrew: Bool,
                       receivedDone: Bool,
                       streamedText: String,
                       roomTookOver: Bool) -> ChatTailAction {
        // The room owns the turn. Both other actions write into the placeholder the
        // room has already claimed — the offline line would overwrite the handoff,
        // and the lead-in would too, because a handoff before the first delta means
        // every delta was dropped on purpose and `streamedText` is legitimately empty.
        if roomTookOver { return .none }
        if streamThrew || !receivedDone { return .fallback }
        // Gated on "no `done`", NOT on empty text: byte can legitimately reply with
        // only a run-task decision, and falling back there would fire a second
        // chatSender call and run the same task twice.
        if streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .leadIn }
        return .none
    }
}
