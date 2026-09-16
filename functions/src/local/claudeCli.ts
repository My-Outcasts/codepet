/**
 * One `claude -p` call, and the flags every local non-streaming run makes it under.
 *
 * Shared by `oneShotSidecar` (one prompt, one JSON body) and `vcSidecar` (one prompt per
 * agent, many times in one run). Both need the identical isolation, and a second copy of
 * these flags is how one of the two silently starts reading the founder's hooks.
 *
 * The implementation moved down to `cliAdapter.ts`, where the three provider-specific
 * decisions — binary, flags, envelope unwrap — became `claudeAdapter` and everything else
 * became `runCli`. This module stays as the CLAUDE-shaped face of it: the names its callers
 * and tests already import, unchanged.
 */

export {
  ClaudeCliError,
  claudeAdapter,
  claudeArgs,
  quote,
  usageFrom,
  type CliAdapter,
} from "./cliAdapter";

import { claudeAdapter, runCliEnvelope } from "./cliAdapter";

/**
 * Run one prompt and return the parsed `--output-format json` envelope.
 *
 * Still the envelope, not `runCli`'s `{ text, usage }`, and deliberately: both callers read a
 * field off it that the adapter interface does not promise — `oneShotSidecar` takes
 * `modelUsage` through `pickModel`, `vcSidecar` takes `stop_reason` to tell a truncated
 * object from a model that ignored the schema. Moving them onto `runCli` would drop those
 * silently, which is a behaviour change this refactor is not allowed to make. The spawn
 * itself is shared, so there is still exactly one copy of it.
 */
export async function runClaudeJson(opts: {
  systemPrompt: string;
  prompt: string;
  model?: string;
  effort?: string;
}): Promise<any> {
  const { envelope } = await runCliEnvelope(claudeAdapter, opts);
  return envelope;
}
