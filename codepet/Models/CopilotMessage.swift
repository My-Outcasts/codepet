// codepet/Models/CopilotMessage.swift
import Foundation

/// Who authored a Copilot chat message.
enum CopilotRole { case me, companion }

/// One Copilot chat message (session-only; not persisted this phase). Named to
/// avoid the reflection `ChatMessage`.
struct CopilotMessage: Identifiable, Equatable {
    let id: String
    let role: CopilotRole
    let text: String
    var draft: Deliverable?
    var draftApproved: Bool

    init(id: String = UUID().uuidString, role: CopilotRole, text: String,
         draft: Deliverable? = nil, draftApproved: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.draft = draft
        self.draftApproved = draftApproved
    }
}
