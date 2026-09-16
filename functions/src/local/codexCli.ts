/**
 * The SECOND `CliAdapter`: OpenAI's Codex CLI, running on the founder's own ChatGPT plan.
 *
 * Everything above this file is shared with the Claude path — the op's prompt builder, the
 * prose schema instruction, `extractJson`, the op's own coercion. What is Codex-specific is
 * exactly what `CliAdapter` names: the binary, its flags, and how its stdout is read. That
 * is the whole point of the seam; a second prompt path would fork the cost model as well as
 * the maintenance.
 *
 * **Every flag here was verified against the real binary** (codex-cli 0.154.0, brew cask at
 * `/opt/homebrew/bin/codex`, ChatGPT-authenticated) and is recorded with its measurement in
 * `.superpowers/sdd/codex-cli-findings.md`. None of it is copied from the Claude adapter,
 * because the two CLIs agree on almost nothing — including the meaning of `-p`.
 */

import type { CliAdapter } from "./cliAdapter";

/**
 * The flags one Codex call runs under. Each one, and what it is protecting:
 *
 * - `exec` is the non-interactive mode — the `claude -p` equivalent. **`-p` MUST NEVER
 *   appear**: on this CLI it is `--profile`, and Claude muscle memory would silently layer a
 *   config profile over the run instead of doing anything like "print".
 * - `--ignore-user-config` skips `$CODEX_HOME/config.toml`, and therefore the founder's MCP
 *   servers. This is the `--strict-mcp-config` analogue: reading a brief and answering has no
 *   business holding whatever servers she wired into her own editor. Auth still resolves.
 *   The cost is recorded honestly below.
 * - `--strict-config` is **mandatory, not tidiness.** Without it an unrecognised `-c` key is
 *   accepted and SILENTLY IGNORED — `base_instructions` is exactly such a key, and the
 *   verification spike nearly recorded a false positive on it. A Codex release that renames
 *   `developer_instructions` must fail loudly rather than run every op with no role framing.
 * - `--skip-git-repo-check` because the transport runs each call in a fresh temp cwd, which
 *   is not a git repo and is not meant to be.
 * - `--ephemeral` writes no session file for work that is one prompt long.
 * - `-s read-only` is the sandbox. It is NOT the equivalent of Claude's `--tools ""`: Codex
 *   has no way to grant nothing, so its shell tooling stays reachable regardless of what the
 *   schema instruction tells the model to do. The instruction itself was reworded from a
 *   factual claim ("there are no tools available") to a directive ("do not use any tools"),
 *   because the old wording was true under Claude — which really does run with `--tools ""`
 *   — but false here, where the tools exist and are merely told not to be used. Both real op
 *   runs in the spike made zero tool calls, so compliance held — but it rests on the model
 *   rather than a capability gate, and `read-only` is what bounds the blast radius meanwhile.
 * - `-c developer_instructions=` is the system prompt. There is no `--system-prompt` flag;
 *   this is a config override, and the system prompt therefore travels in ARGV rather than on
 *   stdin. Op systems are short and op-authored (the `runTask` one is 118 bytes), so this is
 *   within argv's ~1 MB ceiling — FOUNDER text must stay on stdin, where it already is.
 * - `-` reads the prompt from stdin, and is last. Passing a prompt argument AND piping stdin
 *   makes stdin a `<stdin>` block appended to it rather than the prompt, so the adapter does
 *   one or the other, never both.
 *
 * **The tension this settles deliberately** (findings Q6): `--ignore-user-config` also
 * discards any `model=` the founder set for herself. Excluding her MCP servers wins, because
 * that is a safety property and the model is a preference — and because Codepet can pass
 * `-m` when it has an opinion, whereas there is no flag that re-excludes a server.
 */
export function codexArgs(opts: {
  systemPrompt: string;
  model?: string;
  effort?: string;
}): string[] {
  return [
    "exec",
    "--ignore-user-config",
    "--strict-config",
    "--skip-git-repo-check",
    "--ephemeral",
    "-s", "read-only",
    "-c", `developer_instructions=${opts.systemPrompt}`,
    ...(opts.model ? ["-m", opts.model] : []),
    // Codex has no `--effort`; reasoning effort is a config key, and it is a REAL one —
    // verified under `--strict-config` (an invented key next to it was rejected) and
    // observed taking effect in the run banner as `reasoning effort: low`.
    ...(opts.effort ? ["-c", `model_reasoning_effort=${opts.effort}`] : []),
    "-",
  ];
}

/** The founder's own Codex CLI: the second implementation, and the proof the seam is real. */
export const codexAdapter: CliAdapter = {
  binary: "codex",
  args: codexArgs,

  /**
   * Near-identity, and that is the finding rather than a shortcut.
   *
   * **There is no envelope.** `codex exec` prints the model's text on stdout and nothing
   * else; every banner, progress line and telemetry number goes to stderr. There is no
   * Codex analogue of Claude's `.result` because there is no wrapper to take it out of.
   * The one piece of handling is the trailing newline the CLI terminates its last line with,
   * which Claude's `result` string does not carry — trimming it means both providers hand
   * `extractJson` the same bytes.
   *
   * **Usage is zeros, honestly.** Nothing on stdout carries a token count. `--json` does
   * (verified: `turn.completed` reports real input/output/cached numbers), and is
   * deliberately not used — it would fork the output path this design keeps single, and the
   * one consumer of these counts is the meeting's run ceiling, which is Claude-only. A
   * fabricated number would be worse than a zero, because the ceiling is computed from it.
   *
   * **`model` is left undefined, and that was verified rather than assumed.** A `--json` run
   * on this machine printed four line types — `thread.started`, `turn.started`,
   * `item.completed`, `turn.completed` — and not one carries a model id. The stderr banner
   * names it, but stderr is not a data channel here (it also says `ERROR` on runs that
   * succeed). Nothing Codex says on stdout answers "what answered", so this says nothing.
   */
  resultFrom(stdout: string) {
    return {
      text: stdout.trim(),
      usage: { input: 0, output: 0, cache_read: 0 },
      model: undefined,
    };
  },
};
