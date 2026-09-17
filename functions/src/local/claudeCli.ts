/**
 * One `claude -p` call, and the flags every local non-streaming run makes it under.
 *
 * `vcSidecar` (one prompt per agent, many times in one run) is what still runs through here:
 * meetings are Claude-only, because the frame order they stream is read off the envelope's
 * `stop_reason`, which is Claude's shape and not something `CliAdapter` promises.
 * `oneShotSidecar` now goes through `runCli` and can run on either CLI.
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
 * Still the envelope, not `runCli`'s `{ text, usage, model }`, and deliberately: `vcSidecar`
 * reads `stop_reason` off it to tell a truncated object from a model that ignored the schema,
 * which the adapter interface does not promise and Codex could not answer. Moving the meeting
 * onto `runCli` would drop it silently, and meetings stay Claude-only either way. The spawn
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
