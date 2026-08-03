import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { Blackboard } from "./types";

/**
 * Per-run ceilings. A 4-agent run with a cached prefix should land far below
 * these — they exist to stop a runaway loop, not to shape a normal run.
 */
export const MAX_RUN_TOKENS = 200_000;
export const MAX_RUN_COST_USD = 1.5;

/** Config doc read at request time so the feature can be disabled without a deploy. */
export const KILL_SWITCH_DOC = "config/virtual_company";

/**
 * Billable generation and fresh input. Cache reads are excluded deliberately:
 * they cost a tenth of input and are the behaviour we want, so charging them
 * against the ceiling would punish a well-cached run.
 */
export function totalTokens(bb: Blackboard): number {
  return Object.values(bb.telemetry.tokens_per_agent).reduce(
    (sum, usage) => sum + (usage?.input ?? 0) + (usage?.output ?? 0),
    0
  );
}

export function budgetState(bb: Blackboard): {
  withinBudget: boolean;
  reason: string | null;
} {
  const tokens = totalTokens(bb);
  if (tokens >= MAX_RUN_TOKENS) {
    return {
      withinBudget: false,
      reason: `Run stopped: token ceiling reached (${tokens} of ${MAX_RUN_TOKENS} allowed for one run).`
    };
  }
  const cost = bb.telemetry.cost_estimate_usd;
  if (cost >= MAX_RUN_COST_USD) {
    return {
      withinBudget: false,
      reason: `Run stopped: cost ceiling reached (estimated $${cost.toFixed(
        2
      )} of $${MAX_RUN_COST_USD.toFixed(2)} allowed for one run).`
    };
  }
  return { withinBudget: true, reason: null };
}

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
