//
// One Anthropic client for every engineering handler, built lazily so the
// module can be imported by tests that never touch the network.
import Anthropic from "@anthropic-ai/sdk";

/**
 * The model engineering runs use. Spec §11 leaves Opus 5 vs. Sonnet 5 open
 * as a margin decision — this constant is the single place that changes.
 */
export const ENG_MODEL = "claude-opus-5";

/** Set at deploy from the agent created by `scripts/provision-eng-agent.ts`. */
export const ENG_AGENT_ID_ENV = "ENG_AGENT_ID";
export const ENG_AGENT_VERSION_ENV = "ENG_AGENT_VERSION";
export const ENG_ENVIRONMENT_ID_ENV = "ENG_ENVIRONMENT_ID";

/**
 * Every value any engineering handler writes to an `engRuns/{id}.status`
 * field, in one place. `engStartRun` writes `starting`/`running`/`failed`;
 * `engWebhook` (durable-outcome handler) additionally writes
 * `reviewing`/`budgetReached`. Both handlers import this rather than each
 * declaring their own string literals, so the two vocabularies cannot drift
 * apart the way they would if each handler typed its own union.
 */
export type RunStatus = "starting" | "running" | "reviewing" | "budgetReached" | "failed";

let client: Anthropic | null = null;

export function getEngClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}

/**
 * A path segment is safe to interpolate into a Firestore document path only
 * when it cannot contain a "/" — which either makes `db.doc(...)` throw
 * synchronously (an odd resulting segment count) or silently redirects the
 * operation to a different, caller-influenced document within the same
 * project (an even segment count, no throw at all) — and is not Firestore's
 * own reserved `__…__` document-id form, which addresses metadata Firestore
 * treats specially, never an ordinary application document.
 *
 * Lives here, rather than being exported from whichever engineering handler
 * defined it first, because this module is the one every handler already
 * imports (`getEngClient`) — so no handler needs to import a sibling
 * handler just to reuse this rule.
 */
export function isSafePathSegment(value: string): boolean {
  return value.length > 0 && !value.includes("/") && !/^__.*__$/.test(value);
}
