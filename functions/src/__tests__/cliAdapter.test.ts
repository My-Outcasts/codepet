import { claudeAdapter } from "../local/cliAdapter";

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
});
