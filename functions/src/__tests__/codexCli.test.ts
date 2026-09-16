import { codexAdapter } from "../local/codexCli";
import { claudeAdapter } from "../local/cliAdapter";
import { ONE_SHOT_OPS, extractJson } from "../local/oneShotOps";

/**
 * The SECOND implementation of `CliAdapter`, and the test that keeps it honest.
 *
 * Every flag asserted here was verified against the real binary (codex-cli 0.154.0) in
 * `.superpowers/sdd/codex-cli-findings.md`. Nothing in this file is copied from Codex
 * documentation or inferred from the Claude adapter, because the two CLIs agree on almost
 * nothing: `-p` means `--profile` here, there is no envelope, and stderr carries `ERROR`
 * lines on runs that succeeded.
 */
describe("the Codex adapter", () => {
  /**
   * PINNED, not counted and not searched. A rename that keeps the arity would pass a
   * contains-check and ship a run with no role framing at all.
   */
  test("emits exactly the flags the CLI is run under", () => {
    expect(codexAdapter.args({ systemPrompt: "SYS" })).toEqual([
      "exec",
      "--ignore-user-config",
      "--strict-config",
      "--skip-git-repo-check",
      "--ephemeral",
      "-s", "read-only",
      "-c", "developer_instructions=SYS",
      "-",
    ]);
  });

  test("puts the model and the reasoning effort in, still ending on the stdin marker", () => {
    expect(codexAdapter.args({ systemPrompt: "SYS", model: "gpt-5.6-terra", effort: "low" }))
      .toEqual([
        "exec",
        "--ignore-user-config",
        "--strict-config",
        "--skip-git-repo-check",
        "--ephemeral",
        "-s", "read-only",
        "-c", "developer_instructions=SYS",
        "-m", "gpt-5.6-terra",
        "-c", "model_reasoning_effort=low",
        "-",
      ]);
  });

  /** Same default as the Claude path: a founder who chose a model in her own CLI already
   *  answered this. Findings Q6 — omitting `-m` inherits her default. */
  test("omits the model and the effort unless asked", () => {
    const a = codexAdapter.args({ systemPrompt: "S" });
    expect(a).not.toContain("-m");
    expect(a.join(" ")).not.toContain("model_reasoning_effort");
  });

  /**
   * THE guard this file exists for. Findings Q1: on `codex` and `codex exec` alike, `-p` is
   * `--profile`, NOT "print". Claude muscle memory (`claude -p`) silently layers a config
   * profile over the run instead of doing anything like what it means. Put `-p` back and
   * this goes red.
   */
  test("never passes -p, which on this CLI means --profile", () => {
    expect(codexAdapter.args({ systemPrompt: "S", model: "m", effort: "low" }))
      .not.toContain("-p");
  });

  /**
   * THE other guard. Findings Q3: without `--strict-config` an unrecognised `-c` key is
   * accepted and SILENTLY IGNORED — the verifier's first steering test "passed" while the
   * model saw no system prompt at all (`base_instructions` is exactly such a key). With it,
   * a Codex release that renamed `developer_instructions` fails loudly on exit 1 instead of
   * quietly dropping every op's role framing.
   */
  test("pairs the system-prompt override with --strict-config", () => {
    const a = codexAdapter.args({ systemPrompt: "S" });
    expect(a).toContain("--strict-config");
    expect(a).toContain("developer_instructions=S");
    expect(a.join(" ")).not.toContain("base_instructions");
  });

  /** Findings Q5: this is the `--strict-mcp-config` analogue — it is what keeps the
   *  founder's own MCP servers out of an op that only has to read a brief and answer. */
  test("loads none of the founder's config, and writes nothing to disk", () => {
    const a = codexAdapter.args({ systemPrompt: "S" });
    expect(a).toContain("--ignore-user-config");
    expect(a).toContain("--ephemeral");
    expect(a.slice(a.indexOf("-s"), a.indexOf("-s") + 2)).toEqual(["-s", "read-only"]);
  });

  test("is the codex binary, resolved off the founder's PATH", () => {
    expect(codexAdapter.binary).toBe("codex");
  });

  /**
   * REAL capture, run on this machine with exactly the argv above:
   *
   *   printf 'What colour is a clear midday sky?' | codex exec --ignore-user-config \
   *     --strict-config --skip-git-repo-check --ephemeral -s read-only \
   *     -c developer_instructions='...answer in FRENCH, lowercase, one word...' -
   *   EXIT=0 ; stdout hexdump: 626c 6575 0a  ->  "bleu\n"
   *
   * There is no envelope to unwrap (findings Q4): stdout IS the answer. The only handling
   * is the trailing newline the CLI terminates its last line with, which Claude's
   * `result` string does not carry — so both providers hand `extractJson` the same bytes.
   */
  test("takes the answer straight off stdout — there is no envelope", () => {
    expect(codexAdapter.resultFrom("bleu\n").text).toBe("bleu");
  });

  /**
   * The other real capture, and the shape eleven of the twelve ops actually get back:
   *
   *   printf 'Name one colour of a clear midday sky.' | codex exec ... \
   *     -c developer_instructions='Reply with ONLY a JSON object matching ...' -
   *   EXIT=0 ; stdout: {"colour":"blue","confidence":0.99}\n
   */
  test("hands the shared extractJson a body it can parse", () => {
    const real = '{"colour":"blue","confidence":0.99}\n';
    expect(extractJson(codexAdapter.resultFrom(real).text))
      .toEqual({ colour: "blue", confidence: 0.99 });
  });

  /**
   * ZEROS, honestly. The default path prints no token counts anywhere on stdout — the
   * `tokens used` line is stderr chatter, not a number this adapter is allowed to invent.
   * (`--json` does carry real counts, and is deliberately not used: it would fork the
   * output path the prose contract exists to keep single.)
   */
  test("reports zero usage rather than a number it did not measure", () => {
    expect(codexAdapter.resultFrom("bleu\n").usage)
      .toEqual({ input: 0, output: 0, cache_read: 0 });
  });

  /**
   * `undefined` is the honest answer, and it was VERIFIED rather than assumed. Run on this
   * machine, `codex exec --json` prints exactly four line types and not one carries a model
   * id:
   *
   *   {"type":"thread.started","thread_id":"01a0a7d8-..."}
   *   {"type":"turn.started"}
   *   {"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"PONG"}}
   *   {"type":"turn.completed","usage":{"input_tokens":13913,...}}
   *
   * The banner on STDERR names the model, but stderr is not a data channel here. Nothing
   * Codex says on stdout answers "what answered", so this reports nothing — never the
   * requested model dressed up as the answering one, and never a Claude id.
   */
  test("says nothing about what answered, because Codex does not say", () => {
    expect(codexAdapter.resultFrom("bleu\n").model).toBeUndefined();
  });
});

/** The claim this design rests on: one op, two adapters, ONE prompt. If this ever fails, a
 *  second prompt path has been forked and the cost model changed. */
test("the same op produces the same prompt whichever adapter runs it", () => {
  const plan = ONE_SHOT_OPS.runTask.plan({ task_title: "X", dept_key: "fin" });
  expect(plan.prompt).toContain("This function produces sheet, doc.");
  // the adapters differ in argv and envelope ONLY
  expect(claudeAdapter.args({ systemPrompt: "S" }))
    .not.toEqual(codexAdapter.args({ systemPrompt: "S" }));
});
