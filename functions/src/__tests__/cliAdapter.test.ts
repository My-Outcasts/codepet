import * as fs from "fs";
import * as os from "os";
import * as path from "path";

import { ClaudeCliError, claudeAdapter, runCli, type CliAdapter } from "../local/cliAdapter";

/**
 * The adapter is the ONLY provider-specific thing in the one-shot path. Everything above it —
 * the prose schema instruction, `extractJson`, each op's coercion — is shared, and this test
 * exists to keep the boundary where it is.
 */
describe("the Claude adapter", () => {
  test("emits exactly the flags the CLI is run under", () => {
    expect(claudeAdapter.args({ systemPrompt: "SYS" })).toEqual([
      "-p",
      "--system-prompt", "SYS",
      "--strict-mcp-config",
      "--setting-sources", "",
      "--output-format", "json",
      "--tools", "",
    ]);
  });

  /** Passing no `--model` is the default on purpose: a founder who chose one in her own CLI
   *  already answered this, and overriding it would be Codepet deciding something she decided. */
  test("omits --model and --effort unless asked", () => {
    const a = claudeAdapter.args({ systemPrompt: "S" });
    expect(a).not.toContain("--model");
    expect(a).not.toContain("--effort");
    expect(claudeAdapter.args({ systemPrompt: "S", model: "claude-opus-5" }))
      .toEqual(expect.arrayContaining(["--model", "claude-opus-5"]));
  });

  test("pulls the answer out of the envelope", () => {
    expect(claudeAdapter.resultFrom('{"result":"hello"}').text).toBe("hello");
  });

  /** **Usage rides with the text, and this is why.** `usageFrom` is consumed by `vcSidecar`
   *  alone — the meeting's run ceiling, the only guard against a runaway loop on the founder's
   *  own plan. Returning bare text would strand it. Cache WRITES count as input: a real meeting
   *  reported `input_tokens: 2` for a prompt of thousands, because the prefix was cached and
   *  billed as `cache_creation_input_tokens`. */
  test("carries the token counts the meeting's ceiling depends on", () => {
    const r = claudeAdapter.resultFrom(
      '{"result":"hi","usage":{"input_tokens":2,"cache_creation_input_tokens":3000,"output_tokens":7}}');
    expect(r.usage).toEqual({ input: 3002, output: 7, cache_read: 0 });
  });

  test("is the claude binary", () => {
    expect(claudeAdapter.binary).toBe("claude");
  });

  /**
   * `model` is WHAT ANSWERED, and Claude Code is the provider that says. `modelUsage` can
   * hold more than one id — a run bills small side calls too — so the answering one is the
   * one that emitted the most output tokens. The field reaches the founder's screen, which
   * is why it is read rather than assumed from what was requested.
   */
  test("names what actually answered, off modelUsage", () => {
    const r = claudeAdapter.resultFrom(JSON.stringify({
      result: "hi",
      modelUsage: {
        "claude-haiku-4-5": { outputTokens: 12 },
        "claude-opus-5": { outputTokens: 900 },
      },
    }));
    expect(r.model).toBe("claude-opus-5");
  });
});

/**
 * The transport under both adapters. These spawn a real child through the real login shell,
 * because the property being tested is exactly the one a mock would assume away.
 */
describe("runCli", () => {
  function fakeCli(script: string): CliAdapter {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codepet-fakecli-"));
    const file = path.join(dir, "fake-cli");
    // `cat > /dev/null` first: the transport writes the prompt to stdin, and a child that
    // exits without draining it would break the pipe rather than the assertion.
    fs.writeFileSync(file, `#!/bin/sh\ncat > /dev/null\n${script}\n`, { mode: 0o755 });
    return {
      binary: file,
      // Named, not omitted: `modelEnv` is part of the interface, and a stub that skipped it
      // would stop this fixture noticing a provider that forgot to name its own variable.
      modelEnv: "CODEPET_FAKE_MODEL",
      args: () => [],
      resultFrom: (stdout: string) => ({
        text: stdout.trim(),
        usage: { input: 0, output: 0, cache_read: 0 },
      }),
    };
  }

  /**
   * THE guard. Measured on codex-cli 0.154.0: a fully successful run (exit 0, the answer on
   * stdout) still prints `ERROR codex_models_manager: failed to refresh available models` on
   * stderr. Any "failed if stderr said ERROR" check fails 100% of those runs. Branch on the
   * exit code — delete that and this goes red.
   */
  test("a run that shouts ERROR on stderr and exits 0 is a SUCCESS", async () => {
    const adapter = fakeCli(
      `printf 'bleu\\n'; echo '2026-09-16T00:34:09Z ERROR codex_models_manager: failed to refresh available models' >&2; exit 0`);
    const r = await runCli(adapter, { systemPrompt: "S", prompt: "P" });
    expect(r.text).toBe("bleu");
  }, 20000);

  /** The other half: a non-zero exit is the failure signal, and what the CLI said on stderr
   *  is the only place the real reason lives (findings Q7 — stdout is empty on both failure
   *  classes). */
  test("a non-zero exit fails, carrying what the CLI said", async () => {
    const adapter = fakeCli(`echo "error: unexpected argument '--nope' found" >&2; exit 2`);
    await expect(runCli(adapter, { systemPrompt: "S", prompt: "P" }))
      .rejects.toThrow(ClaudeCliError);
    await expect(runCli(adapter, { systemPrompt: "S", prompt: "P" }))
      .rejects.toThrow(/unexpected argument/);
  }, 20000);
});
