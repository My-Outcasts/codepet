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
    case preview
    case full
}

/// Reads the entitlement. The read is a closure so the rule is testable without Firestore —
/// `Firestore.firestore()` traps rather than throwing under an unconfigured `FirebaseApp`,
/// which kills the XCTest host and reads as an assertion failure.
struct PlanTierResolver {

    /// Mirrors the server's `PLAN_GATING_ENABLED`. That flag shipped `false`, so
    /// `resolvePlanTier` always answered `"full"` and the Firestore-reading branches below
    /// it never ran in production — they were dead code behind a disabled flag.
    ///
    /// **Turning this on is a product decision, not a refactor.** The `pro` / `pro_until`
    /// branches this gates were never exercised in production; flipping this default would
    /// start gating founders who have always had everything, not merely port existing
    /// behavior. Default stays `false` so the port is behavior-identical to what shipped.
    var gatingEnabled: Bool = false

    var read: (String) async -> [String: Any]? = { uid in
        try? await Firestore.firestore()
            .collection("entitlements").document(uid).getDocument().data()
    }

    func tier(uid: String) async -> PlanTier {
        guard gatingEnabled else { return .full }
        guard let doc = await read(uid), let pro = doc["pro"] as? Bool, pro else { return .preview }
        if let proUntil = doc["pro_until"] as? Timestamp, proUntil.dateValue() < Date() {
            return .preview
        }
        return .full
    }
}
