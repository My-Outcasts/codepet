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

import { spawn } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import {
  ONE_SHOT_OPS,
  OneShotBadRequest,
  OneShotUnusableAnswer,
  extractJson,
  pickModel,
  schemaInstruction,
} from "./oneShotOps";

/**
 * The flags one op runs under. Each is load-bearing, and each is the same decision
 * `chatSidecar.claudeArgs` records — read that first if changing one:
 *
 * - `--system-prompt` REPLACES Claude Code's own. These prompts are complete on their own,
 *   and a coding assistant's persona fights them for voice and format.
 * - `--setting-sources ""` keeps the founder's settings out, and therefore their HOOKS. A
 *   `SessionStart` hook injecting its own content into a JSON-only turn is how you get
 *   prose wrapped around the object.
 * - `--strict-mcp-config` with NO `--mcp-config`: strict alone excludes every server, which
 *   here is exactly what is wanted. Chat has to pass both because it ships a server.
 * - `--tools ""` grants nothing. A SAFETY property, not tidiness: reading a founder's brief
 *   has no business holding Bash, Edit or Write.
 * - `--output-format json` gives one envelope with the final text in `result`, so there is
 *   no stream to reassemble. The streaming form buys nothing when the caller waits for the
 *   whole object anyway.
 * - Prompt on stdin, never as an argument, so no flag above can swallow it.
 */
export function claudeArgs(opts: {
  systemPrompt: string;
  model?: string;
  effort?: string;
}): string[] {
  return [
    "-p",
    "--system-prompt", opts.systemPrompt,
    "--strict-mcp-config",
    "--setting-sources", "",
    "--output-format", "json",
    "--tools", "",
    ...(opts.model ? ["--model", opts.model] : []),
    ...(opts.effort ? ["--effort", opts.effort] : []),
  ];
}

/** The prompt as the model receives it: the shared builder's text, then the shape asked for. */
export function renderPrompt(prompt: string, schema: unknown): string {
  return `${prompt}\n\n${schemaInstruction(schema)}`;
}

function emit(payload: unknown): void {
  process.stdout.write(JSON.stringify(payload));
}

/** Shell-quote one argument for the login shell the child runs under. */
function quote(arg: string): string {
  return `'${arg.replace(/'/g, "'\\''")}'`;
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

  // A run directory the founder's CLAUDE.md cannot be discovered from: discovery walks UP
  // from cwd, so a temp dir keeps their repo instructions out of Codepet's turn.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codepet-oneshot-"));
  const cleanup = () => {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  };

  const args = claudeArgs({
    systemPrompt: plan.system ?? "",
    model: process.env.CODEPET_CHAT_MODEL,
    effort: process.env.CODEPET_CHAT_EFFORT,
  });

  // A login shell so the founder's PATH resolves `claude`, and the two credential variables
  // stripped: precedence puts them ABOVE the subscription, and under -p a present key is
  // always used — so an exported key would bill their API account for work this whole
  // design exists to put on the plan they already pay for.
  const env = { ...process.env };
  delete env.ANTHROPIC_API_KEY;
  delete env.ANTHROPIC_AUTH_TOKEN;

  const child = spawn("/bin/zsh", ["-lc", `claude ${args.map(quote).join(" ")}`], { cwd: dir, env });
  child.stdin.write(renderPrompt(plan.prompt ?? "", plan.schema));
  child.stdin.end();

  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (c: string) => (stdout += c));
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (c: string) => (stderr += c));

  child.on("close", (code) => {
    cleanup();

    let envelope: any;
    try {
      envelope = JSON.parse(stdout);
    } catch {
      // No envelope at all: the CLI never got as far as answering. Its stderr is the real
      // reason (a missing login, a bad flag), so that is what travels, not a guess.
      emit({
        error: "upstream_failure",
        detail: stderr.trim() || `claude exited ${code} with no output`,
      });
      process.exitCode = 1;
      return;
    }

    if (envelope?.is_error || typeof envelope?.result !== "string") {
      emit({
        error: "upstream_failure",
        detail: String(envelope?.result ?? envelope?.error ?? stderr.trim() ?? `claude exited ${code}`),
      });
      process.exitCode = 1;
      return;
    }

    try {
      const parsed = extractJson(envelope.result);
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
  });
}

if (require.main === module) {
  main().catch((err) => {
    emit({ error: "sidecar_failure", detail: String(err) });
    process.exitCode = 1;
  });
}
