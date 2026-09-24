#!/usr/bin/env node
/**
 * Runs one NON-STREAMING Cloud Function on the founder's OWN CLI — Claude Code by default,
 * OpenAI's Codex when `CODEPET_CLI_PROVIDER=codex` — and prints the byte-for-byte body that
 * function's HTTP 200 would have carried, so the app's existing decoders read it unchanged.
 *
 * WHICH CLI is the only thing that differs between the two: the op's prompt, the prose
 * schema instruction, `extractJson` and the op's own coercion are one shared path, and
 * `CliAdapter` is the single seam holding the binary, its flags and its output handling.
 * Forking the prompt per provider would fork the cost model with it.
 *
 * Reads `{"op": "<name>", "body": {...}}` on stdin, where `body` is the exact JSON the
 * Cloud Function takes. Writes ONE JSON object on stdout: either that function's response
 * body, or `{"error": ..., "detail": ...}`.
 *
 * WHAT IT DOES NOT DO, and why that is the point:
 *   - No auth. There is nobody to authenticate to; the founder already owns this machine.
 *   - No rate limit. The ceiling is their Claude plan, not our Firestore counter.
 *   - No Anthropic client, and no API key anywhere in the process.
 *   - No tools, and no MCP. These ops read a prompt and answer; chat is the one that needs
 *     tools, and it has its own sidecar for exactly that reason.
 *
 * Prompts are NOT re-implemented here — see `oneShotOps.ts`. This file is process wiring
 * only, which is why the parsing and planning live next door where tests can reach them.
 */

import {
  ClaudeCliError, claudeAdapter, installSigtermHandler, runCli, type CliAdapter,
} from "./cliAdapter";
import { codexAdapter } from "./codexCli";
import {
  ONE_SHOT_OPS,
  OneShotBadRequest,
  OneShotUnusableAnswer,
  extractJson,
  schemaInstruction,
} from "./oneShotOps";

// Re-exported: this is the module whose contract the sidecar tests describe, and the flags
// are part of that contract even though the implementation is now shared with `vcSidecar`.
export { claudeArgs } from "./claudeCli";

/**
 * WHICH CLI runs the op.
 *
 * Read from the environment (`CODEPET_CLI_PROVIDER`) rather than from the request body, for
 * two reasons. The body is documented as "the exact JSON the Cloud Function takes" — one
 * wire shape shared with the HTTP path — and a provider is not part of any function's
 * contract; it is a property of the machine the sidecar was spawned on. And the two things
 * already chosen per spawn, the model and the effort, travel exactly this way
 * (`CODEPET_CHAT_MODEL`, `CODEPET_CHAT_EFFORT`), so the Swift side sets one more variable on
 * a process it already configures rather than learning a new key.
 *
 * **An unknown name FAILS.** Falling back to Claude would run the founder's work on a plan
 * she did not pick and report success, because both providers answer with the same JSON —
 * the same silent-degradation shape `--strict-config` exists to close on the Codex side.
 * Absent means Claude, which is what every shipped build does today.
 */
export function adapterFor(provider: string | undefined): CliAdapter {
  if (!provider || provider === "claude") return claudeAdapter;
  if (provider === "codex") return codexAdapter;
  throw new Error(`no local runner for provider '${provider}'`);
}

/**
 * What goes in `OneShotMeta.model` — and what goes there when NOTHING said what answered.
 *
 * Claude Code reports the models a run actually billed, so `resultFrom` reads the answering
 * one off `modelUsage` and it is reported as-is. Codex's default stdout is bare model text
 * with no envelope, and a `--json` run was checked too: none of its four line types carries
 * a model id. So on that provider nothing can answer the question.
 *
 * The requested model is then reported **marked as requested**, never as the answering one.
 * This field is written into the narrative card, the guidance body, the plan and the
 * overview — a founder reads it — so "we asked for this and the CLI never confirmed" has to
 * read differently from "this answered". A Claude id on a Codex run would be a lie in the
 * other direction and cannot happen: the label is built from the adapter's own binary name.
 */
export function reportedModel(
  answered: string | undefined,
  adapter: CliAdapter,
  requested: string | undefined,
): string {
  if (answered) return answered;
  return requested
    ? `${adapter.binary}-local (requested ${requested}, not confirmed)`
    : `${adapter.binary}-local (model not reported)`;
}

/**
 * WHICH model this provider was asked for — read from THAT provider's own variable.
 *
 * It was `process.env.CODEPET_CHAT_MODEL` for both, and that was a real bug rather than a
 * tidiness point. `LocalOneShotRunner` fills that variable from `ClaudeCodeModelPreference`,
 * so a founder who picked "Opus" in Settings has the bare alias `opus` in it — and the Codex
 * adapter would turn that into `-m opus`. Findings Q7 measured Codex's response to an unknown
 * model: exit 1 with an `invalid_request_error`. Loud, which is the good half; the bad half is
 * that it is EVERY op, for as long as that preference is set.
 *
 * A model id is not portable between providers, so neither is the variable carrying it. Each
 * adapter names its own (`CliAdapter.modelEnv`), and an unset one means what it already means
 * on both CLIs: pass no model flag and inherit that CLI's own default (findings Q6).
 *
 * EFFORT is deliberately NOT scoped this way, and that was verified rather than assumed: every
 * value `ClaudeCodeEffort.flag` can emit — `low`, `medium`, `high`, `xhigh`, `max` — was run
 * through `codex exec --strict-config -c model_reasoning_effort=<v>` on this machine and all
 * five exited 0, with the banner echoing the value back. The ladder is shared; the model ids
 * are not.
 */
export function requestedModel(
  adapter: CliAdapter,
  env: NodeJS.ProcessEnv,
): string | undefined {
  return env[adapter.modelEnv];
}

/**
 * The prompt as the model receives it: the shared builder's text, then the shape asked for.
 *
 * A free-text op gets the builder's text ALONE. Appending "reply with only a JSON object" to a
 * chat turn would change the answer, not just its shape.
 */
export function renderPrompt(prompt: string, schema: unknown, freeText = false): string {
  return freeText ? prompt : `${prompt}\n\n${schemaInstruction(schema)}`;
}

function emit(payload: unknown): void {
  process.stdout.write(JSON.stringify(payload));
}

/* istanbul ignore next -- process wiring; the pure parts carry the tests */
async function main(): Promise<void> {
  const raw = await new Promise<string>((resolve) => {
    let s = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c: string) => (s += c));
    process.stdin.on("end", () => resolve(s));
  });

  let request: { op?: string; body?: unknown };
  try {
    request = JSON.parse(raw);
  } catch (err) {
    emit({ error: "invalid_payload", detail: String(err) });
    process.exitCode = 1;
    return;
  }

  const op = request.op ? ONE_SHOT_OPS[request.op] : undefined;
  if (!op) {
    // Named rather than generic: an op the app asks for and this build does not have means
    // the bundle is older than the app, which is a fixable thing to be told.
    emit({ error: "unknown_op", detail: `no local runner for op '${request.op}'` });
    process.exitCode = 1;
    return;
  }

  const body = request.body ?? {};
  let plan;
  try {
    plan = op.plan(body);
  } catch (err) {
    const bad = err instanceof OneShotBadRequest;
    emit({ error: bad ? "invalid_payload" : "op_failure", detail: String((err as Error).message) });
    process.exitCode = 1;
    return;
  }

  // Nothing to ask. The Cloud Function would have answered without spending anything, so
  // neither does the founder's plan.
  if (plan.answer !== undefined) {
    emit(plan.answer);
    return;
  }

  let adapter: CliAdapter;
  try {
    adapter = adapterFor(process.env.CODEPET_CLI_PROVIDER);
  } catch (err) {
    emit({ error: "sidecar_failure", detail: String((err as Error).message) });
    process.exitCode = 1;
    return;
  }
  // AFTER the adapter is known, because which variable holds the model depends on which
  // provider is answering. Reading it first is what let a Claude alias reach Codex.
  const requested = requestedModel(adapter, process.env);

  let answer: { text: string; model?: string };
  try {
    answer = await runCli(adapter, {
      systemPrompt: plan.system ?? "",
      prompt: renderPrompt(plan.prompt ?? "", plan.schema, plan.freeText === true),
      model: requested,
      effort: process.env.CODEPET_CHAT_EFFORT,
    });
  } catch (err) {
    emit({
      error: err instanceof ClaudeCliError ? "upstream_failure" : "sidecar_failure",
      detail: String((err as Error).message),
    });
    process.exitCode = 1;
    return;
  }

  try {
    // A free-text op is handed the reply itself; everything else gets the object out of it.
    const parsed = plan.freeText === true ? answer.text : extractJson(answer.text);
    emit(op.respond(body, parsed, {
      model: reportedModel(answer.model, adapter, requested),
      nowISO: new Date().toISOString(),
    }));
  } catch (err) {
    const unusable = err instanceof OneShotUnusableAnswer;
    emit({
      error: unusable ? "unusable_answer" : "op_failure",
      detail: String((err as Error).message),
    });
    process.exitCode = 1;
  }
}

if (require.main === module) {
  // Stop and the 180 s timeout SIGTERM this process; end the CLI child with it.
  installSigtermHandler();
  main().catch((err) => {
    emit({ error: "sidecar_failure", detail: String(err) });
    process.exitCode = 1;
  });
}
