/**
 * One `claude -p` call, and the flags every local non-streaming run makes it under.
 *
 * Shared by `oneShotSidecar` (one prompt, one JSON body) and `vcSidecar` (one prompt per
 * agent, many times in one run). Both need the identical isolation, and a second copy of
 * these flags is how one of the two silently starts reading the founder's hooks.
 */

import { spawn } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

/**
 * The flags one call runs under. Each is load-bearing, and each is the same decision
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
 *   or arguing a decision has no business holding Bash, Edit or Write.
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

/** Shell-quote one argument for the login shell the child runs under. */
export function quote(arg: string): string {
  return `'${arg.replace(/'/g, "'\\''")}'`;
}

/** A `claude` run that produced no usable envelope. Carries what it did say. */
export class ClaudeCliError extends Error {}

/**
 * Run one prompt and return the parsed `--output-format json` envelope.
 *
 * Every call gets its OWN temp cwd, deliberately: discovery of `CLAUDE.md` walks UP from
 * cwd, so a temp dir keeps the founder's repo instructions out of Codepet's turn — and a
 * per-call directory means the parallel calls a virtual-company run makes cannot race each
 * other's cleanup.
 */
export async function runClaudeJson(opts: {
  systemPrompt: string;
  prompt: string;
  model?: string;
  effort?: string;
}): Promise<any> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codepet-claude-"));
  const args = claudeArgs(opts);

  // A login shell so the founder's PATH resolves `claude`, and the two credential variables
  // stripped: precedence puts them ABOVE the subscription, and under -p a present key is
  // always used — so an exported key would bill their API account for work this whole
  // design exists to put on the plan they already pay for.
  const env = { ...process.env };
  delete env.ANTHROPIC_API_KEY;
  delete env.ANTHROPIC_AUTH_TOKEN;

  return new Promise((resolve, reject) => {
    const child = spawn("/bin/zsh", ["-lc", `claude ${args.map(quote).join(" ")}`], {
      cwd: dir,
      env,
    });
    child.stdin.write(opts.prompt);
    child.stdin.end();

    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (c: string) => (stdout += c));
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (c: string) => (stderr += c));

    child.on("close", (code) => {
      try { fs.rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }

      let envelope: any;
      try {
        envelope = JSON.parse(stdout);
      } catch {
        // No envelope at all: the CLI never got as far as answering. Its stderr carries the
        // real reason (a missing login, a bad flag), so that is what travels.
        reject(new ClaudeCliError(stderr.trim() || `claude exited ${code} with no output`));
        return;
      }
      if (envelope?.is_error || typeof envelope?.result !== "string") {
        reject(new ClaudeCliError(String(
          envelope?.result ?? envelope?.error ?? stderr.trim() ?? `claude exited ${code}`)));
        return;
      }
      resolve(envelope);
    });

    child.on("error", (err) => reject(new ClaudeCliError(String(err))));
  });
}

/**
 * Token usage as the CLI reports it, in the shape the blackboard records.
 *
 * Real numbers rather than zeroes, because the per-run ceilings are computed from them and
 * they are not relaxed for the local path: a runaway loop on the founder's own plan is still
 * a runaway loop. Cache reads are reported when present — the orchestrator excludes them
 * from the ceiling on purpose, so passing them through changes nothing but the telemetry the
 * founder can see.
 */
export function usageFrom(envelope: any): { input: number; output: number; cache_read: number } {
  const u = envelope?.usage ?? {};
  const num = (v: unknown) => (typeof v === "number" ? v : 0);
  return {
    // Cache WRITES count as input, and this was measured rather than assumed: a real meeting
    // reported `input_tokens: 2` for a department whose prompt was thousands of tokens,
    // because Claude Code cached the prefix and billed it as `cache_creation_input_tokens`.
    // Counting only `input_tokens` would have made the run ceiling — the one guard against a
    // runaway loop on the founder's own plan — see almost no input at all.
    input: num(u.input_tokens) + num(u.cache_creation_input_tokens),
    output: num(u.output_tokens),
    cache_read: num(u.cache_read_input_tokens),
  };
}
