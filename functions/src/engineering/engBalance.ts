//
// The founder's spendable engineering credits. One module so there is a
// single place to audit the number that authorises real money.
//
import * as admin from "firebase-admin";

/**
 * Where a founder's spendable credits live.
 *
 * NOT `companies/{uid}.credits`. That document's `allow update` guards only
 * ownership, so the founder can edit any other field on it — and this number
 * becomes `budget.max_list_cost` on the Managed Agents session, so a client
 * that can write it is choosing its own spend cap.
 *
 * Not under `engineering/` either, even though that subcollection is already
 * denied to clients: it is denied for READ as well, and the founder has to be
 * able to see their own balance. `firestore.rules` gives `engBalance` the
 * shape `connectorStatus` already uses — read allowed, write denied.
 */
export const BALANCE_PATH = (uid: string): string => `companies/${uid}/engBalance/current`;

/**
 * The founder's credits. `0` for a missing document or a non-finite value.
 *
 * `Number.isFinite`, not `typeof === "number"`: `typeof NaN === "number"` is
 * true and `NaN <= 0` is false, so a corrupted balance would sail past a
 * caller's own `<= 0` check and start a run. Zero is the safe direction —
 * the founder is told they are out of credits, rather than a run beginning
 * against a balance nobody can reason about.
 */
export async function readBalance(uid: string): Promise<number> {
  const snap = await admin.firestore().doc(BALANCE_PATH(uid)).get();
  const credits = snap.data()?.credits;
  return Number.isFinite(credits) ? (credits as number) : 0;
}

/**
 * Decrement the balance inside the caller's transaction.
 *
 * Takes a transaction rather than writing on its own: the debit and the
 * dedupe marker that makes it at-most-once have to commit together, or a
 * crash between them either charges twice or not at all.
 *
 * `FieldValue.increment` rather than read-modify-write, so two deliveries
 * landing at once cannot lose one another's decrement.
 *
 * A non-positive or non-finite amount is a no-op, not a write: crediting a
 * founder back is not something this function is allowed to do by accident,
 * and `increment(-NaN)` would corrupt the balance into something
 * `readBalance` then reports as 0 — silently locking the founder out.
 */
export function debit(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  credits: number
): void {
  if (!Number.isFinite(credits) || credits <= 0) return;
  tx.set(
    admin.firestore().doc(BALANCE_PATH(uid)),
    { credits: admin.firestore.FieldValue.increment(-credits) },
    { merge: true }
  );
}
