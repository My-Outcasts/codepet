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
/// Whether a thumb may actually be WRITTEN — pure, so the rule is testable.
///
/// Split from `submit` for the same reason `MessageFeedbackPayload` is, and the split is what
/// was missing: `submit`'s own first condition returns early under XCTest, so no test could
/// ever reach the decision, and there was nowhere to assert it. That is exactly how the
/// prototype-mode hole survived — not a rule anyone disagreed with, a rule nothing checked.
enum MessageFeedbackGate {
    /// - `isRunningTests`: the suite must never write to the real project.
    /// - `isOptedOut`: `ServerLoggingGate` — an account that has opted out of server logging.
    /// - `allowsCloudWrites`: `PrototypeMode`'s safety gate. **This is the one that was
    ///   missing.** A thumb cast in prototype mode rated a FIXTURE reply: its `messageId` and
    ///   `threadId` name rows that live only in memory and are rebuilt from fixtures on every
    ///   load, so the document is unresolvable to any consumer — and `firestore.rules:42`
    ///   denies clients both `read` and `update`, so it can be neither corrected nor cleaned
    ///   up. The sidebar also promises, in those words, that nothing is written to the
    ///   founder's account while the mode is on. Found 7 Sep, by a stray thumb during an
    ///   automated on-screen verification writing a real document from a fixture company.
    ///
    ///   Note the gate stops the WRITE, not the vote: `CompanyStore.recordVote` only mutates
    ///   `chatMessages` in memory, so the thumb still fills in and the founder still sees her
    ///   rating. That is correct for a mode whose whole premise is fixtures end to end.
    static func allowsWrite(isRunningTests: Bool, isOptedOut: Bool, allowsCloudWrites: Bool) -> Bool {
        !isRunningTests && !isOptedOut && allowsCloudWrites
    }
}

@MainActor
enum MessageFeedbackService {
    static func submit(vote: MessageVote, message: CopilotMessage, threadId: String,
                       authManager: AuthManager, appState: AppState) {
        guard MessageFeedbackGate.allowsWrite(
            isRunningTests: AppEnvironment.isRunningTests,
            isOptedOut: ServerLoggingGate.isOptedOut,
            allowsCloudWrites: PrototypeMode.allowsCloudWrites
        ) else { return }
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
