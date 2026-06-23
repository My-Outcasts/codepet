import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// MARK: - RevenueCat webhook
//
// Receives RevenueCat subscription events and mirrors entitlement state into
// Firestore at entitlements/{uid}, which `resolvePlanTier` reads to gate plans.
//
// Setup (when wiring monetization):
//   1. In the RevenueCat dashboard, set this function's URL as the webhook.
//   2. Set the webhook "Authorization header value" to a shared secret and put
//      the same value in this function's REVENUECAT_WEBHOOK_TOKEN env var.
//   3. Configure RevenueCat so app_user_id == the Firebase uid.
//
// Until REVENUECAT_WEBHOOK_TOKEN is set, the function rejects everything (401),
// so it's safe to deploy inert before RevenueCat is connected.

interface RevenueCatEvent {
  type?: string;
  app_user_id?: string;
  expiration_at_ms?: number | null;
}

/** Event types that, when received, mean the user currently has access. */
const GRANTING_TYPES = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_EXTENDED",
]);

function tokenMatches(header: string | undefined): boolean {
  const expected = process.env.REVENUECAT_WEBHOOK_TOKEN;
  if (!expected) return false;            // not configured → reject (inert)
  if (!header) return false;
  // RevenueCat sends exactly the configured header value; accept raw or Bearer.
  return header === expected || header === `Bearer ${expected}`;
}

export async function handleRevenueCatWebhook(
  req: Request,
  res: Response
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  if (!tokenMatches(req.headers.authorization)) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const event = (req.body?.event ?? {}) as RevenueCatEvent;
  const uid = event.app_user_id;
  if (!uid || typeof uid !== "string") {
    res.status(400).json({ error: "missing_app_user_id" });
    return;
  }

  // Derive current access. Expiry (subscriptions) wins; non-expiring grants
  // stay true; EXPIRATION/refund-style events revoke.
  const expirationMs = typeof event.expiration_at_ms === "number" ? event.expiration_at_ms : null;
  let pro: boolean;
  if (event.type === "EXPIRATION") {
    pro = false;
  } else if (expirationMs != null) {
    pro = expirationMs > Date.now();
  } else {
    pro = GRANTING_TYPES.has(event.type ?? "");
  }

  try {
    await admin.firestore().collection("entitlements").doc(uid).set(
      {
        pro,
        pro_until: expirationMs != null ? admin.firestore.Timestamp.fromMillis(expirationMs) : null,
        last_event: event.type ?? "unknown",
        updated_at: admin.firestore.Timestamp.now(),
      },
      { merge: true }
    );
    logger.info("revenuecat entitlement updated", { uid, type: event.type, pro });
    res.status(200).json({ ok: true });
  } catch (err) {
    logger.error("revenuecat webhook write failed", { uid, err: String(err) });
    res.status(500).json({ error: "write_failed" });
  }
}
