import * as admin from "firebase-admin";

// MARK: - Plan gating master switch
//
// While FALSE, every user gets the full plan — plans ship free so we can
// validate whether people actually open and act on them (spec build-order
// steps 1–3). Flip to TRUE only once a purchase flow + RevenueCat are wired
// and there is actually something to buy; otherwise users get preview-only
// plans with no way to unlock.
export const PLAN_GATING_ENABLED = false;

export type PlanTier = "preview" | "full";

/** Firestore shape at entitlements/{uid}, written by the RevenueCat webhook. */
interface EntitlementDoc {
  pro?: boolean;
  pro_until?: admin.firestore.Timestamp | null;
  last_event?: string;
  updated_at?: admin.firestore.Timestamp;
}

/**
 * Resolve a user's plan tier. With gating off, always "full". With gating on,
 * reads entitlements/{uid}: "full" when `pro` is true and not past `pro_until`,
 * otherwise "preview".
 */
export async function resolvePlanTier(uid: string): Promise<PlanTier> {
  if (!PLAN_GATING_ENABLED) return "full";

  try {
    const snap = await admin.firestore().collection("entitlements").doc(uid).get();
    if (!snap.exists) return "preview";

    const data = snap.data() as EntitlementDoc;
    if (data.pro !== true) return "preview";

    // Respect expiry when present (subscriptions); non-expiring grants pass.
    if (data.pro_until && data.pro_until.toMillis() < Date.now()) return "preview";
    return "full";
  } catch {
    // On any lookup failure, fail closed to the free tier.
    return "preview";
  }
}
