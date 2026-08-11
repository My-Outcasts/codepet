// codepet/Models/MessageFeedbackService.swift
import Foundation
import FirebaseAuth
import FirebaseFirestore

/// The `feedback` document a thumb writes, built as pure data.
///
/// Split from the writer so it can be tested against `firestore.rules:37-43` without a
/// configured `FirebaseApp`. That rule — `rating is int` in 1...5, `feature is string` —
/// is the only thing between a thumb and a write that fails silently in production, and a
/// rejected write surfaces nothing to the founder. It permits extra fields, so the
/// message/thread identity rides along without a rule change.
enum MessageFeedbackPayload {
    static func build(vote: MessageVote, messageId: String, threadId: String,
                      companionId: String?, deptName: String?,
                      userId: String, authMethod: String, displayName: String,
                      pet: String, appVersion: String, build: String) -> [String: Any] {
        var data: [String: Any] = [
            "feature": FeedbackFeature.chatMessage.rawValue,
            // 5/1 rather than a Bool: the rule reads `rating is int`, and it cannot be
            // relaxed without a deploy.
            "rating": vote == .up ? 5 : 1,
            "messageId": messageId,
            "userId": userId,
            "authMethod": authMethod,
            "displayName": displayName,
            "pet": pet,
            "appVersion": appVersion,
            "build": build,
            "platform": "macos",
            "timestamp": FieldValue.serverTimestamp()
        ]
        // `companyStore.activeThreadId` stays nil until the first `flushActiveThread()`
        // (`CompanyStore.swift:614-617`), and `seedFirstRunGreeting` appends byte's first-run
        // greeting without flushing (`CompanyStore.swift:315-320`) — so a thumb on that very
        // first message can reach here with `threadId == ""`. The rule denies `update`
        // (`firestore.rules:42`), so a written `""` could never be corrected. Omit the key
        // instead: a missing field honestly means "unknown", where `""` looks like data.
        if !threadId.isEmpty { data["threadId"] = threadId }
        if let companionId, !companionId.isEmpty { data["companionId"] = companionId }
        if let deptName, !deptName.isEmpty { data["deptName"] = deptName }
        return data
    }
}

/// Writes one thumb to the `feedback` collection.
///
/// Separate from `FeatureFeedbackManager.submit` because that one is welded to the
/// once-ever toast — it takes the toast's state and ends in `dismiss()`. Same collection,
/// same identity fields, same opt-out gate.
///
/// The rule denies `update`, so correcting a misclicked thumb writes a SECOND document with
/// the same `messageId`. That is deliberate: `firestore.rules:42` denies clients `read` too,
/// so no reader IN THIS APP can resolve the duplicate — an external/admin consumer resolves
/// it by latest `timestamp`. Duplicate messageIds are not a bug.
@MainActor
enum MessageFeedbackService {
    static func submit(vote: MessageVote, message: CopilotMessage, threadId: String,
                       authManager: AuthManager, appState: AppState) {
        guard !AppEnvironment.isRunningTests, !ServerLoggingGate.isOptedOut else { return }
        let user = authManager.currentUser
        let data = MessageFeedbackPayload.build(
            vote: vote,
            messageId: message.id,
            threadId: threadId,
            companionId: message.companionId,
            deptName: message.deptName,
            userId: user?.uid ?? "anonymous",
            authMethod: authManager.authMethod ?? (authManager.isGuestMode ? "guest" : "none"),
            displayName: user?.displayName ?? appState.displayName,
            pet: appState.activeChar,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        )
        Firestore.firestore().collection("feedback").addDocument(data: data) { error in
            if let error {
                print("[MessageFeedback] submit error: \(error.localizedDescription)")
            }
        }
    }
}
