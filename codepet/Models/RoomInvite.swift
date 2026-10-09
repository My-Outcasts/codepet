// codepet/Models/RoomInvite.swift
import Foundation

/// "Bring Finance + Sales in" (9 Oct): a department's offer to convene the room on a question.
/// The offer arrives in chat's native department keys; the room speaks agent ids.
enum RoomInvite {
    /// Mirrors `ROOM_AGENT_FOR` in functions/src/companyChatCore.ts — `RoomOfferTests` pins
    /// every key, so the two cannot drift silently. nil for anything that is not a chat
    /// department (product is kept off the roster).
    static func roomAgentId(for key: String) -> String? {
        ["eng": "engineering", "design": "design", "mkt": "marketing", "sales": "sales",
         "support": "support", "fin": "finance", "ops": "operations", "legal": "legal"][key]
    }

    /// "Finance + Sales" — the departments as the founder reads them on the button.
    static func names(_ offer: RoomOfferDTO) -> String {
        offer.departments.compactMap { DepartmentCatalog.find($0)?.name }.joined(separator: " + ")
    }
}
