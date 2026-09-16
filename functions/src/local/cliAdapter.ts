/**
 * One CLI call, and the single seam every provider-specific decision goes through.
 *
 * The one-shot path is shared end to end — the prose schema instruction, `extractJson`, each
 * op's coercion — and exactly three things are not: which binary is spawned, the flags it runs
 * under, and how its stdout is unwrapped. `CliAdapter` is those three things and nothing else,
 * so a second CLI is a new object here rather than a second copy of `runCli`.
 *
 * Everything below `runCli` — the per-call temp cwd, the login shell, the stripped credential
 * variables — is transport, identical whoever answers, and stays in one place for the same
 * reason the flags did: a second copy is how one of the two silently drifts.
 */

import { spawn } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";

export interface CliAdapter {
  /** The command name, resolved from the founder's own `PATH` by the login shell. */
  binary: string;
  /**
   * WHICH environment variable names the model for THIS provider — and it is per provider
   * on purpose, not a shared `CODEPET_CHAT_MODEL`.
   *
   * The Swift runner fills that shared variable from `ClaudeCodeModelPreference`, so a
   * founder who picked "Opus" in Settings has the bare alias `opus` in it. Handing that to
   * Codex sends `-m opus`, which findings Q7 measured as exit 1 on an unknown model — loud,
   * but loud on EVERY op she runs. A model id is not portable between providers, so the
   * variable it travels in must not be either: an unset one means "inherit that CLI's own
   * default", which is already the documented behaviour on both.
   */
  modelEnv: string;
  args(opts: { systemPrompt: string; model?: string; effort?: string }): string[];
  /** The model's text, plus whatever token counts this CLI reports (zeros if none). */
  resultFrom(stdout: string): {
    text: string;
    usage: { input: number; output: number; cache_read: number };
    /** What answered, when the CLI says. `undefined` when it does not — never a guess. */
    model?: string;
  };
}

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

/**
 * Which model to report, read out of `claude -p --output-format json`.
 *
 * `modelUsage` is keyed by model id and can hold more than one — a run also bills small
 * side calls (measured: a Haiku entry alongside the answering model). The one that produced
 * the answer is the one that emitted the most output tokens, so that is what is reported.
 * Reporting a guess would be worse than the honest fallback: the `model` field reaches the
 * client and is shown.
 *
 * It lives HERE, beside `usageFrom`, rather than in `oneShotOps` where it started: both read
 * the shape of CLAUDE's envelope, which is adapter knowledge, and `oneShotOps` is the part
 * of the path that is meant to be provider-blind. `oneShotOps` re-exports it so every
 * existing import still resolves.
 */
export function pickModel(envelope: any): string {
  const usage = envelope?.modelUsage;
  if (usage && typeof usage === "object") {
    let best: string | null = null;
    let bestTokens = -1;
    for (const [id, u] of Object.entries(usage as Record<string, any>)) {
      const tokens = typeof u?.outputTokens === "number" ? u.outputTokens : 0;
      if (tokens > bestTokens) {
        best = id;
        bestTokens = tokens;
      }
    }
    if (best) return best;
  }
  return "claude-code-local";
}

/** The founder's own Claude Code: the first implementation, and the one the app ships on. */
export const claudeAdapter: CliAdapter = {
  binary: "claude",
  // The variable every shipped build already sets, and the one chat uses. Unchanged.
  modelEnv: "CODEPET_CHAT_MODEL",
  args: claudeArgs,
  /**
   * The envelope's checks live here rather than in `runCli`, because "was this answer
   * usable" is the one failure question only the adapter can answer: `is_error` and a
   * missing `result` are Claude's shape, and Codex has no envelope to ask at all. Both
   * rejections are `ClaudeCliError`, so the sidecar still reports them as `upstream_failure`
   * exactly as it did when this check sat in the transport.
   */
  resultFrom(stdout: string) {
    let envelope: any;
    try {
      envelope = JSON.parse(stdout);
    } catch {
      throw new ClaudeCliError(`claude answered with no JSON envelope: ${stdout.slice(0, 200)}`);
    }
    if (envelope?.is_error || typeof envelope?.result !== "string") {
      throw new ClaudeCliError(String(envelope?.result ?? envelope?.error ?? "claude reported an error"));
    }
    return {
      text: envelope.result as string,
      usage: usageFrom(envelope),
      // Claude Code is the provider that SAYS what answered. Codex does not, and reports
      // `undefined` rather than echoing back what was asked for.
      model: pickModel(envelope),
    };
  },
};

/**
 * Spawn the CLI the adapter names and collect everything it said.
 *
 * Every call gets its OWN temp cwd, deliberately: discovery of `CLAUDE.md` walks UP from
 * cwd, so a temp dir keeps the founder's repo instructions out of Codepet's turn — and a
 * per-call directory means the parallel calls a virtual-company run makes cannot race each
 * other's cleanup. Codex is run from the same temp dir, which is why its flag set carries
 * `--skip-git-repo-check`.
 *
 * It resolves whatever the child produced, **including a non-zero exit**, and judges none of
 * it. Judging is the caller's, and the two callers judge differently on purpose: `runCli`
 * branches on the exit code alone (Codex prints `ERROR` lines on successful runs), while
 * `runCliEnvelope` keeps Claude's envelope checks, which is what the meeting still reads.
 */
function spawnCli(adapter: CliAdapter, opts: {
  systemPrompt: string;
  prompt: string;
  model?: string;
  effort?: string;
}): Promise<{ stdout: string; stderr: string; code: number | null }> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codepet-cli-"));
  const args = adapter.args(opts);

  // A login shell so the founder's PATH resolves the CLI — `claude` and the brew cask's
  // `/opt/homebrew/bin/codex` alike — and the two credential variables stripped: precedence
  // puts them ABOVE the subscription, and under -p a present key is always used, so an
  // exported key would bill their API account for work this whole design exists to put on
  // the plan they already pay for.
  const env = { ...process.env };
  delete env.ANTHROPIC_API_KEY;
  delete env.ANTHROPIC_AUTH_TOKEN;

  return new Promise((resolve, reject) => {
    const child = spawn("/bin/zsh", ["-lc", `${adapter.binary} ${args.map(quote).join(" ")}`], {
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
      resolve({ stdout, stderr, code });
    });

    child.on("error", (err) => reject(new ClaudeCliError(String(err))));
  });
}

/**
 * Run one prompt and return the parsed `--output-format json` envelope.
 *
 * CLAUDE-SHAPED, and the only remaining caller is the meeting: `vcSidecar` reads
 * `stop_reason` off the envelope to tell a truncated object from a model that ignored the
 * schema, which is not something `CliAdapter` promises and not something Codex could answer.
 * Meetings stay Claude-only, so this stays as it was — same checks, same messages, same
 * order — over the shared spawn.
 */
export async function runCliEnvelope(adapter: CliAdapter, opts: {
  systemPrompt: string;
  prompt: string;
  model?: string;
  effort?: string;
}): Promise<{ envelope: any; stdout: string }> {
  const { stdout, stderr, code } = await spawnCli(adapter, opts);

  let envelope: any;
  try {
    envelope = JSON.parse(stdout);
  } catch {
    // No envelope at all: the CLI never got as far as answering. Its stderr carries the
    // real reason (a missing login, a bad flag), so that is what travels.
    throw new ClaudeCliError(
      stderr.trim() || `${adapter.binary} exited ${code} with no output`);
  }
  if (envelope?.is_error || typeof envelope?.result !== "string") {
    throw new ClaudeCliError(String(
      envelope?.result ?? envelope?.error ?? stderr.trim() ?? `${adapter.binary} exited ${code}`));
  }
  return { envelope, stdout };
}

/**
 * Run one prompt on whichever CLI the adapter names, and take back the three things this
 * path needs: the model's text, the token counts a run ceiling is computed from, and what
 * answered — when the CLI says so.
 *
 * **It branches on the EXIT CODE, and on nothing else.** That is not a simplification, it is
 * a measured requirement: a fully successful `codex exec` run (exit 0, answer on stdout)
 * prints `ERROR codex_models_manager: failed to refresh available models` on stderr, so any
 * "failed if stderr mentioned an error" check would fail every Codex run there is. stderr is
 * read for one purpose only — it is where a CLI that produced nothing says why.
 *
 * Unwrapping is the adapter's, including deciding that what came back is unusable: Claude's
 * `is_error`/missing-`result` envelope and Codex's bare text have no shared shape to check
 * here, and a check in both places is how the two silently drift.
 */
export async function runCli(adapter: CliAdapter, opts: {
  systemPrompt: string;
  prompt: string;
  model?: string;
  effort?: string;
}): Promise<{
  text: string;
  usage: { input: number; output: number; cache_read: number };
  model?: string;
}> {
  const { stdout, stderr, code } = await spawnCli(adapter, opts);
  if (code !== 0 || !stdout.trim()) {
    // The CLI never got as far as answering. Its stderr carries the real reason (a missing
    // login, a bad flag, a config key this version does not know), so that is what travels.
    throw new ClaudeCliError(
      stderr.trim() || `${adapter.binary} exited ${code} with no output`);
  }
  return adapter.resultFrom(stdout);
}
