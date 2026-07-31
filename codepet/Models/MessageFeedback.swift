import Foundation

/// A per-message reaction (thumb up/down) recorded to the `feedback` collection.
/// Pure — the writer (`CompanyStore.reactToMessage`) adds the server timestamp.
/// `kind: "chat_message"` distinguishes these from FeatureFeedbackManager's
/// feature-rating docs.
struct MessageFeedback: Equatable {
    let messageId: String
    let helpful: Bool
    let companyId: String
    let userId: String
    let companionId: String

    func firestoreData() -> [String: Any] {
        [
            "kind": "chat_message",
            "messageId": messageId,
            "helpful": helpful,
            "companyId": companyId,
            "userId": userId,
            "companionId": companionId,
            "platform": "macos",
        ]
    }
}
