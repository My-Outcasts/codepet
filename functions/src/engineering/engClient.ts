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
