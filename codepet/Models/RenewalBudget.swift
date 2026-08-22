// codepet/Models/RenewalBudget.swift
import Foundation
// NO `import Speech`. Whether renewing a recognition task is still worth doing is a
// decision over an Int and a String; the task, the request and the recognizer are the
// listener's business and none of them are needed to make it.

/// How many times `SpeechListener` may open a fresh recognition task that hears
/// nothing before it gives up and reports failure instead.
///
/// **Why this is a separate type.** It was three lines of inline state on
/// `SpeechListener` — the same shape as `stopRetryArmed` before it moved into
/// `SpeakingQueue`, and unreachable for the same reason: reaching it needs an
/// `SFSpeechRecognizer`, which no test may construct. Left inline it was the only
/// untested *decision* in that file, and it contained a defect a test would have
/// caught (see `sawTranscript`).
///
/// **What the bound is for.** `SFSpeechRecognitionTask` has a ~1 minute audio limit,
/// and hitting it means a minute of audio flowed — so renewing is right. A *fresh*
/// task that dies having delivered no transcript at all is not that: it is a
/// genuinely fatal condition (recognition authorisation revoked in System Settings,
/// the recognizer withdrawn, the network gone under vi-VN) that will kill every task
/// we open. Unbounded renewal there is a tight loop of failing tasks, silently,
/// forever, behind a live-looking orb. One renewal is spent finding out; the second
/// failure is reported.
///
/// The error is deliberately *not* the discriminator. The ~1 minute limit surfaces as
/// an `NSError` in `kAFAssistantErrorDomain` whose codes are undocumented and
/// version-dependent, and they cannot be measured here without an `SFSpeechRecognizer`.
/// Matching on a guessed code would either close the session on a renewable end or
/// renew forever on a fatal one.
struct RenewalBudget: Equatable {

    /// What the listener should do now that a task has ended.
    enum Decision: Equatable {
        /// Open a fresh request/task pair and keep listening.
        case renew
        /// Renewing is evidently futile: stop and tell the founder.
        case fail
    }

    /// Renewals allowed while nothing has been transcribed. One: enough to tell a
    /// task that ended for its own reasons from a recognizer that cannot work at all.
    static let allowance = 1

    private var spent = 0

    /// **Read-only, for the log line and nothing else.** `taskEnded()`'s answer alone
    /// cannot tell "this is the first end, renewing" from "this is the tenth, and
    /// something cleared the budget nine times" — the counter is the difference, and it
    /// was unreadable from outside. Deliberately not settable: the decision stays this
    /// type's, and a diagnostic that could move the number would be a diagnostic that can
    /// change the behaviour it is reporting on.
    var renewalsSpent: Int { spent }

    init() {}

    /// A recognition task delivered a transcript, so recognition demonstrably works
    /// and the budget is whole again.
    ///
    /// **Non-empty only, and that is the point of having this method.** The call site
    /// used to reset on `if let text`, where `text` is
    /// `result?.bestTranscription.formattedString` — so a result carrying `""`
    /// cleared the budget. An empty transcript is exactly what a task delivers while
    /// it is failing to hear anything, which is the one condition the budget exists
    /// to detect: it is the *absence* of evidence, not evidence.
    mutating func sawTranscript(_ text: String) {
        guard !text.isEmpty else { return }
        spent = 0
    }

    /// A recognition task ended — with an error, or having reported its final result.
    ///
    /// Note what is not consulted: which of those it was. See the type doc.
    mutating func taskEnded() -> Decision {
        guard spent < Self.allowance else { return .fail }
        spent += 1
        return .renew
    }
}
