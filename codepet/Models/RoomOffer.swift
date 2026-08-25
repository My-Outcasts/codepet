// codepet/Models/RoomOffer.swift
import Foundation

/// Convening the Virtual Company, as a priced act.
///
/// **The gap this closes.** `CopilotChatView` passes `convenesRoom: mode.convenesRoom`
/// and `ChatMode.convenesRoom` is true only for `.plan` — the mode whose composer pill
/// the two-mode shell removed. So the room, which `CLAUDE.md` calls the headline
/// feature, could not be convened in this shell at all: reachable in the dock,
/// unreachable in the pane.
///
/// **Why this is a control and not a suggestion.** The spec's shape is "the companion
/// offers it, the founder taps". A companion that DETECTS a decision needs a signal
/// from the router — and `sendMessage`'s own comment is explicit that "the room is
/// convened by the router's escape hatch, not by a client-side heuristic". Guessing
/// here would contradict that and put a spend prompt in front of questions that never
/// warranted one. So this restores the founder's own way in, priced, and the
/// companion's offer stays a backend field that does not exist yet.
///
/// **Credits, never dollars.** ~10 credits, from the spec: 0.25 × the measured ~40×
/// an ordinary turn. Publishing the ~$0.20 figure would leak cost of goods.
enum RoomOffer {

    /// The stated price. A price, not a balance — there is no live ledger (`Plan` is
    /// static copy), so this is what the act costs and not what remains.
    static let credits = 10

    /// Four departments, the cap `parseRoutingToolInput` enforces server-side.
    static let seats = 4

    /// A room needs a question to argue. Convening on an empty composer would spend
    /// on nothing, so the control is dead until something is typed.
    static func canConvene(draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The menu item. Carries the price in the label, because a founder should never
    /// have to tap to find out what something costs.
    static func label(_ language: AppLanguage) -> String {
        language == .vi
            ? "Triệu tập phòng họp · ~\(credits) tín dụng"
            : "Convene the room · ~\(credits) credits"
    }

    /// What it does, for the menu's own subtitle and the help tag.
    static func detail(_ language: AppLanguage) -> String {
        language == .vi
            ? "\(seats) phòng ban tranh luận câu hỏi này rồi đưa ra khuyến nghị."
            : "\(seats) departments argue this question and hand you a recommendation."
    }
}
