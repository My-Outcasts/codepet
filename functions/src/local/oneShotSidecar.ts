#!/usr/bin/env node
/**
 * Runs one NON-STREAMING Cloud Function on the founder's OWN Claude Code, and prints the
 * byte-for-byte body that function's HTTP 200 would have carried — so the app's existing
 * decoders read it unchanged.
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

import { ClaudeCliError, runClaudeJson } from "./claudeCli";
import {
  ONE_SHOT_OPS,
  OneShotBadRequest,
  OneShotUnusableAnswer,
  extractJson,
  pickModel,
  schemaInstruction,
} from "./oneShotOps";

// Re-exported: this is the module whose contract the sidecar tests describe, and the flags
// are part of that contract even though the implementation is now shared with `vcSidecar`.
export { claudeArgs } from "./claudeCli";

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

  let envelope: any;
  try {
    envelope = await runClaudeJson({
      systemPrompt: plan.system ?? "",
      prompt: renderPrompt(plan.prompt ?? "", plan.schema, plan.freeText === true),
      model: process.env.CODEPET_CHAT_MODEL,
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
    const parsed = plan.freeText === true ? envelope.result : extractJson(envelope.result);
    emit(op.respond(body, parsed, {
      model: pickModel(envelope),
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
  main().catch((err) => {
    emit({ error: "sidecar_failure", detail: String(err) });
    process.exitCode = 1;
  });
}
