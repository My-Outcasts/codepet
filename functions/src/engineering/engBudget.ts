//
// Credits ↔ the session budget Managed Agents enforces.
//
// This is the whole of our spend enforcement for engineering runs. The
// platform refuses to start a model request once a session's list cost
// reaches the cap, so a bug here is not "we mis-report usage" — it is
// "a founder's run can outspend their balance". Hence: round the grant
// DOWN and the charge UP, and cap every run regardless of balance.

/** One credit, in cents. Matches the $0.05/credit overage rate. */
export const CREDIT_CENTS = 5;

/**
 * Per-run ceiling, in credits. A run that needs more than this is a run
 * that has gone wrong; the session pauses at `budget_reached` and the
 * founder decides whether to raise it. Proposed in spec §6, pending
 * closed-beta calibration.
 */
export const DEFAULT_RUN_CREDITS = 40;

export interface SessionBudget {
  type: "limit";
  max_list_cost: { amount: string; currency: "USD" };
}

/**
 * The budget to attach to a session, given the founder's remaining credits.
 *
 * Two deliberate asymmetries: the balance is floored (never grant a fraction
 * of a credit the founder doesn't have) and the result is capped at
 * DEFAULT_RUN_CREDITS (a rich balance is not permission for one runaway run).
 * The one-cent floor exists because the API rejects a zero or negative amount
 * outright — a founder at zero credits should be stopped by our own balance
 * check with a clear message, not by a 400 from Anthropic.
 */
export function creditsToBudget(credits: number): SessionBudget {
  // Reject non-finite input (NaN or Infinity) by emitting minimum budget: granting a
  // large cap on a corrupted balance is the expensive mistake, so we deny the run.
  if (!Number.isFinite(credits)) {
    return { type: "limit", max_list_cost: { amount: "1", currency: "USD" } };
  }

  const grantable = Math.min(Math.floor(credits * CREDIT_CENTS), DEFAULT_RUN_CREDITS * CREDIT_CENTS);
  const amount = Math.max(1, grantable);
  return { type: "limit", max_list_cost: { amount: String(amount), currency: "USD" } };
}

/** What to debit once a session reports its final list cost, in cents. */
export function listCostToCredits(cents: number): number {
  // Reject non-finite input (NaN or Infinity) by charging zero: corrupting the ledger
  // is worse than under-charging one run, and a zero charge leaves the anomaly visible
  // for human review rather than silently destroying the balance.
  if (!Number.isFinite(cents) || cents <= 0) return 0;
  return Math.ceil(cents / CREDIT_CENTS);
}
