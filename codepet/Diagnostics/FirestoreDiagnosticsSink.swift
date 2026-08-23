// codepet/Diagnostics/FirestoreDiagnosticsSink.swift
import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

/// Writes diagnostics to `companies/{uid}/diagnostics/{autoId}`.
///
/// **Why under `companies/{uid}` and not a top-level collection.** `firestore.rules`
/// already ends the `companies/{companyId}` block with
///
///     match /{sub}/{document=**} {
///       allow read:  … && sub != 'connectors' && sub != 'engineering'
///       allow write: … && sub != 'connectors' && sub != 'connectorStatus'
///                       && sub != 'engineering' && sub != 'engRuns' && sub != 'engBalance'
///     }
///
/// `diagnostics` is not on either carve-out list, so the owner may already write AND
/// read it. That means this feature needs NO rules deploy — which matters more than it
/// sounds, because a missing rule is the exact way the `feedback` collection failed
/// silently, and a rules deploy is a step a human has to remember and can get wrong
/// (the header of `firestore.rules` records a revision that drifted from the live
/// ruleset once already). A top-level `diagnostics/` collection would have been
/// deny-by-default until someone deployed, i.e. a reporting system that reports nothing
/// while looking configured.
///
/// The read permission is the second reason. Under `companies/{uid}` the signed-in
/// founder can read their own diagnostics back, so a write can be VERIFIED by reading
/// it — see `-CODEPET_DIAG_SELFTEST YES`. The `feedback` rule denies clients `read`, so
/// nothing that writes there can ever confirm it landed.
///
/// The older game progress under `users/{uid}` was rejected: it is the pre-pivot iOS
/// game's tree, its rule is a blanket `allow read, write`, and diagnostics are about the
/// founder's company session, not their game save.
nonisolated final class FirestoreDiagnosticsSink: DiagnosticsSink {
    static let collection = "diagnostics"
    private static let log = DiagnosticsLog.sink

    func send(_ payload: [String: Any]) -> Bool {
        // `Auth.auth()` TRAPS rather than throwing when no default `FirebaseApp` is
        // configured — the crash `ServerLoggingGateTests` exists to prevent. The
        // reporter must never be the thing that takes the app down, so the guard comes
        // first and a missing app is simply "not reachable yet".
        // Each `return false` is logged with its reason. "Nothing is arriving" and
        // "nothing had anything to arrive about" are indistinguishable otherwise, and
        // the first question anyone will ask of this log is which one it is. Volume is
        // bounded by `DiagnosticsBudget` upstream — a sink that is never reachable sees
        // at most a few hundred lines in a session, not one per failure.
        guard FirebaseApp.app() != nil else {
            DiagnosticsLog.note(Self.log, "not reachable — no FirebaseApp configured")
            return false
        }
        guard !ServerLoggingGate.isOptedOut else {
            // Opted out is not "retry later" — it is "never". Return true so the
            // reporter drops it instead of buffering it forever.
            DiagnosticsLog.note(Self.log, "dropped — this account opted out of server logging")
            return true
        }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            DiagnosticsLog.note(Self.log, "not reachable yet — nobody signed in; buffering")
            return false
        }

        var data = payload
        // Added here rather than in `DiagnosticEvent.payload` so the payload builder
        // stays a pure dictionary a test can assert on, with no Firestore sentinel in it.
        data["timestamp"] = FieldValue.serverTimestamp()

        Firestore.firestore()
            .collection("companies").document(uid)
            .collection(Self.collection)
            .addDocument(data: data) { error in
                if let error {
                    // Reaching this line means diagnostics itself is not being
                    // delivered, and it is the one failure this system cannot report on
                    // its own behalf — the channel that would carry the report is the
                    // channel that just failed, and re-reporting would recurse. So the
                    // unified log is the ONLY record that exists, which is exactly why
                    // this must not be a `print`: a GUI app's stdout is discarded by
                    // `open` and empty under a redirect, so the previous version of this
                    // line recorded a rejected write precisely nowhere.
                    DiagnosticsLog.failure(Self.log,
                                            DiagnosticsLog.writeRejected(error))
                } else {
                    // The positive case matters too, and only here. This is the single
                    // point in the whole system that knows a document actually landed;
                    // everything upstream only knows it handed the write off. Without
                    // it, "diagnostics is silent" and "diagnostics is working and there
                    // was nothing to report" read identically in the log.
                    DiagnosticsLog.note(Self.log, "write accepted by Firestore")
                }
            }
        return true
    }
}
