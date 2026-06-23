import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

// Raised from 50 to 100_000 for demo / dev iteration — effectively no
// limit while still leaving a guard rail against true runaway loops.
// Re-lower when launching to public.
export const DAILY_LIMIT = 100_000;

export function todayKey(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);  // YYYY-MM-DD UTC
}

export function computeResetAt(now: Date = new Date()): Date {
  const next = new Date(now);
  next.setUTCHours(0, 0, 0, 0);
  next.setUTCDate(next.getUTCDate() + 1);
  return next;
}

export interface RateLimitResult {
  allowed: boolean;
  count: number;
  limit: number;
  resetAt: Date;
}

/**
 * Atomic increment-and-check. Reads current count, increments, returns whether
 * the call is allowed. Uses Firestore transaction to avoid race conditions.
 */
export async function checkAndIncrement(
  uid: string,
  now: Date = new Date()
): Promise<RateLimitResult> {
  const db = admin.firestore();
  const ref = db.collection("usage").doc(uid);
  const key = todayKey(now);
  const resetAt = computeResetAt(now);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = (snap.exists ? snap.data() : {}) as Record<string, number>;
    const count = data[key] ?? 0;

    if (count >= DAILY_LIMIT) {
      return { allowed: false, count, limit: DAILY_LIMIT, resetAt };
    }

    tx.set(ref, { [key]: FieldValue.increment(1) }, { merge: true });
    return { allowed: true, count: count + 1, limit: DAILY_LIMIT, resetAt };
  });
}
