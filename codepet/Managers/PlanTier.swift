// codepet/Managers/PlanTier.swift
import Foundation
import FirebaseFirestore

/// What the founder has paid for.
///
/// This used to be answered by `generatePlan` on the server, reading `entitlements/{uid}`.
/// That function is gone with the rest of the hosted AI path, and the work it gated now runs
/// on the founder's own machine — so the check comes to the client.
///
/// **Spoofable, and accepted.** A founder willing to edit her own Firestore document can lift
/// her own tier. What is protected is a feature tier, not somebody else's compute, and the
/// previous arrangement was not stronger: on the local path `generatePlan` already answered
/// `tier: "full"` because there was no entitlement to read.
enum PlanTier: String, Equatable {
    case free
    case full
}

/// Reads the entitlement. The read is a closure so the rule is testable without Firestore —
/// `Firestore.firestore()` traps rather than throwing under an unconfigured `FirebaseApp`,
/// which kills the XCTest host and reads as an assertion failure.
struct PlanTierResolver {

    var read: (String) async -> [String: Any]? = { uid in
        try? await Firestore.firestore()
            .collection("entitlements").document(uid).getDocument().data()
    }

    func tier(uid: String) async -> PlanTier {
        guard let doc = await read(uid), let pro = doc["pro"] as? Bool else { return .free }
        return pro ? .full : .free
    }
}
