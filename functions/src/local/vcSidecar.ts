#!/usr/bin/env node
/**
 * Runs one VIRTUAL COMPANY meeting on the founder's OWN Claude Code, and emits the same SSE
 * frames the Cloud Function does — so the app's existing `SSEParser` and event decoder read
 * it unchanged.
 *
 * Reads the request body (the same JSON the CF takes) on stdin, writes `event: <name>` /
 * `data: <json>` frames on stdout, in the order
 * `docs/superpowers/specs/virtual-company-sse-contract.md` fixes.
 *
 * **The orchestration is NOT re-implemented.** `runVirtualCompany` is the single
 * implementation both this and the HTTP handler call, which matters more here than anywhere
 * else in this feature: the frame ORDER is the contract, and two copies of an order is how a
 * client that renders the room correctly on one transport renders it wrong on the other.
 * What this file provides is the four things the orchestrator does not decide — who answers
 * (an `AgentCaller` built on `claude -p`), where the frames go, whether anything is
 * persisted, and where an error is recorded.
 *
 * WHAT IT DOES NOT DO, and why that is the point:
 *   - No auth. There is nobody to authenticate to; the founder already owns this machine.
 *   - No rate limit. The ceiling is their Claude plan, not our Firestore counter.
 *   - No kill switch. `isFeatureEnabled` reads a Firestore config doc; a local run answers
 *     to the founder, not to a flag we can flip. The per-run CEILINGS still apply — they
 *     stop a runaway loop, which is still a runaway loop on someone's own plan.
 *   - No blackboard write. There is no `company_runs` collection to write to from here, so
 *     a local run leaves no server-side record. The client keeps what it rendered.
 *   - No prompt caching. `claude -p` has no cache-control, so the cached-prefix saving the
 *     cloud path gets does not exist here. It costs turns of the founder's plan, not money,
 *     which is the trade this whole transport is.
 *   - No Anthropic client, and no API key anywhere in the process.
 */

import { AgentCaller } from "../company/router";
import { RunPayload, runVirtualCompany, validateRunPayload } from "../company/orchestrate";
import { ClaudeCliError, runClaudeJson, usageFrom } from "./claudeCli";
import { extractJson, schemaInstruction } from "./oneShotOps";

function frame(event: string, payload: unknown): void {
  process.stdout.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}

/**
 * The prompt one agent receives.
 *
 * The system blocks are JOINED rather than sent as blocks: they exist as an array so the
 * cloud path can mark a cache breakpoint, and `claude -p` has no cache control at all. The
 * TEXT is identical, which is what keeps the two paths comparable.
 *
 * The schema instruction is what replaces `tool_choice`. The API forces the agent's tool;
 * here the same `input_schema` is asked for in prose and the answer parsed — so a department
 * that answers in paragraphs fails its own column rather than corrupting the run.
 */
export function agentPrompt(args: { userMessage: string; tool: unknown }): string {
  const schema = (args.tool as { input_schema?: unknown } | null)?.input_schema;
  return `${args.userMessage}\n\n${schemaInstruction(schema)}`;
}

/**
 * The founder's own Claude Code as an `AgentCaller`.
 *
 * `model` and `effort` are passed THROUGH from the phase that asked, not overridden by the
 * founder's chat preference. The room's tiering is deliberate — routing runs on the cheapest
 * tier, synthesis on the top one — and flattening it to one model would change what the
 * room is, not just what it costs. A tier the founder's plan cannot reach fails that call,
 * and the run degrades the way the orchestrator already handles: that column errors, the
 * meeting continues.
 */
export const localAgentCaller: AgentCaller = async (args) => {
  const envelope = await runClaudeJson({
    systemPrompt: args.system.map((b) => (b as { text?: string }).text ?? "").join("\n\n"),
    prompt: agentPrompt({ userMessage: args.userMessage, tool: args.tool }),
    model: args.model,
    effort: args.effort,
  });
  return {
    input: extractJson(envelope.result),
    usage: usageFrom(envelope),
    // `claude -p` reports why it stopped in the envelope. It travels because the parse sites
    // use it to tell a truncated object from a model that ignored the schema.
    stopReason: typeof envelope.stop_reason === "string" ? envelope.stop_reason : "end_turn",
  };
};

/* istanbul ignore next -- process wiring; the pure parts above carry the tests */
async function main(): Promise<void> {
  const raw = await new Promise<string>((resolve) => {
    let s = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c: string) => (s += c));
    process.stdin.on("end", () => resolve(s));
  });

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch (err) {
    frame("error", { error: "invalid_payload", detail: String(err) });
    process.exitCode = 1;
    return;
  }

  const invalid = validateRunPayload(body);
  if (invalid) {
    frame("error", { error: "invalid_payload", detail: invalid });
    process.exitCode = 1;
    return;
  }

  const payload = body as RunPayload;
  await runVirtualCompany({
    payload,
    // The company id, passed in by the client. It only reaches the blackboard, which is
    // never written here — but a run that recorded the wrong owner would be worse than one
    // that records nothing.
    uid: process.env.CODEPET_COMPANY_ID ?? "local",
    // Not `Date.now()`-free like a workflow script: this IS a process, and the run id has to
    // be unique per meeting for the client to key its cards on.
    runId: `run_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`,
    call: localAgentCaller,
    emit: frame,
    // Nothing to persist to. Stated as a no-op rather than left out so the orchestrator's
    // "persist a failed run, best effort" path stays reachable and cannot throw here.
    persist: async () => {},
    logError: (err, runId) => {
      // stderr, never stdout: stdout is the frame stream, and a log line in it would reach
      // the client's parser as a malformed frame.
      const reason = err instanceof ClaudeCliError ? err.message : String(err);
      process.stderr.write(`virtual company run ${runId} failed: ${reason}\n`);
    },
  });
}

if (require.main === module) {
  main().catch((err) => {
    frame("error", { error: "sidecar_failure", detail: String(err) });
    process.exitCode = 1;
  });
}
