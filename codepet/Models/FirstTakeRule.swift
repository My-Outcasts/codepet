// codepet/Models/FirstTakeRule.swift
import Foundation

/// What happens to Codepet's first reply once a department room answers the same question
/// (CP-029).
///
/// The store marks that reply `supersededByRoom` the moment the room's card lands, and the view
/// already folded its TEXT to one "Codepet's first take" row. Its OFFER was drawn by an earlier
/// branch of the message chain, though — `roadmapProposal`, `runProposal`, `chainOffer`, the
/// first-run action and the grant button all come before the fold — so "Yes, make a new
/// version" stayed purple above the room's "Lock this decision in". Two primary buttons on one
/// answer, and nothing told the founder which one counted.
///
/// A rule rather than an inline condition so a test goes red when someone reorders the chain.
enum FirstTakeRule {
    /// The reply is the room's first take and draws only its one-line fold.
    static func isFolded(_ message: CopilotMessage) -> Bool {
        message.role != .me && message.supersededByRoom
    }

    /// Whether the reply may draw its own offer. False for a folded first take: the room's
    /// card carries the answer and its single action from then on.
    static func drawsOwnOffer(_ message: CopilotMessage) -> Bool {
        !isFolded(message)
    }
}
