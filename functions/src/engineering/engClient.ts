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

let client: Anthropic | null = null;

export function getEngClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}
