import Foundation

struct ChatMessage: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let role: Role
    let text: String
    let createdAt: Date

    enum Role: String, Codable {
        case user
        case pet
    }
}

struct SessionChatThread: Codable, Equatable {
    let sessionId: String
    var messages: [ChatMessage]
    var updatedAt: Date
}
