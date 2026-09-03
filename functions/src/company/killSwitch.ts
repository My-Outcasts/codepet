/**
 * The server-side kill switch for the virtual company.
 *
 * Split from `budget.ts` so the ceilings stay importable without `firebase-admin` — the
 * local path enforces the SAME ceilings (they exist to stop a runaway loop, and a runaway
 * loop on the founder's own plan is still a runaway loop) while having no Firestore to read
 * a flag from. A local run therefore cannot be switched off remotely, which is a real
 * difference: the founder's machine answers to the founder.
 */

import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

/** Config doc read at request time so the feature can be disabled without a deploy. */
export const KILL_SWITCH_DOC = "config/virtual_company";

/**
 * Reads the kill switch. Defaults to enabled when the doc or field is missing —
 * a config document that was never created must not take the feature down. A
 * read error also defaults to enabled and is logged, so a Firestore blip does
 * not look like an intentional shutdown.
 */
export async function isFeatureEnabled(): Promise<boolean> {
  try {
    const [collection, doc] = KILL_SWITCH_DOC.split("/");
    const snap = await admin.firestore().collection(collection).doc(doc).get();
    if (!snap.exists) return true;
    const enabled = (snap.data() as Record<string, unknown>).enabled;
    return enabled !== false;
  } catch (err) {
    logger.warn("virtual company kill switch unreadable; defaulting to enabled", {
      err: String(err)
    });
    return true;
  }
}
