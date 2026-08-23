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
final class FirestoreDiagnosticsSink: DiagnosticsSink {
    static let collection = "diagnostics"

    func send(_ payload: [String: Any]) -> Bool {
        // `Auth.auth()` TRAPS rather than throwing when no default `FirebaseApp` is
        // configured — the crash `ServerLoggingGateTests` exists to prevent. The
        // reporter must never be the thing that takes the app down, so the guard comes
        // first and a missing app is simply "not reachable yet".
        guard FirebaseApp.app() != nil else { return false }
        guard !ServerLoggingGate.isOptedOut else {
            // Opted out is not "retry later" — it is "never". Return true so the
            // reporter drops it instead of buffering it forever.
            return true
        }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return false }

        var data = payload
        // Added here rather than in `DiagnosticEvent.payload` so the payload builder
        // stays a pure dictionary a test can assert on, with no Firestore sentinel in it.
        data["timestamp"] = FieldValue.serverTimestamp()

        Firestore.firestore()
            .collection("companies").document(uid)
            .collection(Self.collection)
            .addDocument(data: data) { error in
                if let error {
                    // The console is the only place left. Reaching this line means
                    // diagnostics itself is not being delivered, which is the one
                    // failure this system cannot report on its own behalf.
                    print("[Diagnostics] write failed: \(error.localizedDescription)")
                }
            }
        return true
    }
}
