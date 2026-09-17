import { spawn } from "child_process";
import { codexAdapter } from "../local/codexCli";
import { claudeAdapter, runCli, type CliAdapter } from "../local/cliAdapter";
import { ONE_SHOT_OPS, extractJson } from "../local/oneShotOps";
import { renderPrompt, requestedModel } from "../local/oneShotSidecar";

jest.mock("child_process", () => ({ spawn: jest.fn() }));

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

  /**
   * The effort key is pinned here because FINDINGS Q8 verified it against the binary — not
   * the other way round. It was the reverse for one commit: the flag's only record was a task
   * report, and this literal was what made it look confirmed. Q8 now carries the control (an
   * invented key rejected under `--strict-config`) and the behaviour measurement (0 reasoning
   * tokens at `low`, 21 at `high`, same prompt).
   */
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

/**
 * A Claude model preference must never reach Codex.
 *
 * `LocalOneShotRunner` fills `CODEPET_CHAT_MODEL` from `ClaudeCodeModelPreference`, so a
 * founder who picked "Opus" in Settings has `opus` in that variable. Passing it to Codex
 * sends `-m opus`, and findings Q7 says an unknown model exits 1 — loudly, but on EVERY op
 * that founder runs. The model variable is therefore provider-scoped: Codex reads its own.
 *
 * PINNED argv, not a contains-check, and deliberately not `not.toMatch(/claude/i)` — the
 * aliases the preference actually emits are bare words like `opus` and `sonnet`, which that
 * regex would wave straight through.
 */
describe("a Claude model preference and the Codex adapter", () => {
  /** Exactly what `ClaudeCodeModel.flag` can produce, plus the full ids they alias to. */
  const CLAUDE_MODELS = [
    "opus", "sonnet", "haiku",
    "claude-opus-5", "claude-sonnet-4-5", "claude-3-5-haiku-latest",
  ];

  it.each(CLAUDE_MODELS)("never puts %s in Codex's argv", (model) => {
    const env = { CODEPET_CHAT_MODEL: model, CODEPET_CHAT_EFFORT: "low" };
    expect(requestedModel(codexAdapter, env)).toBeUndefined();
    expect(codexAdapter.args({
      systemPrompt: "SYS",
      model: requestedModel(codexAdapter, env),
      effort: env.CODEPET_CHAT_EFFORT,
    })).toEqual([
      "exec",
      "--ignore-user-config",
      "--strict-config",
      "--skip-git-repo-check",
      "--ephemeral",
      "-s", "read-only",
      "-c", "developer_instructions=SYS",
      "-c", "model_reasoning_effort=low",
      "-",
    ]);
  });

  /** The founder's Claude choice still reaches Claude — the fix scopes it, not drops it. */
  it("still hands the Claude adapter the founder's Claude choice", () => {
    expect(requestedModel(claudeAdapter, { CODEPET_CHAT_MODEL: "opus" })).toBe("opus");
    expect(requestedModel(claudeAdapter, {})).toBeUndefined();
  });

  /** And Codex gets a model when one was chosen FOR CODEX, whatever Claude's says. */
  it("reads Codex's own variable, even with a Claude preference set beside it", () => {
    expect(requestedModel(codexAdapter, {
      CODEPET_CODEX_MODEL: "gpt-5.6-terra",
      CODEPET_CHAT_MODEL: "opus",
    })).toBe("gpt-5.6-terra");
  });
});

/**
 * THE claim this whole design rests on: one op, two adapters, ONE prompt — byte for byte.
 *
 * The previous version of this test asserted a substring of one prompt and that the two
 * argv arrays differ. Both are true of a design that forked the prompt per provider
 * tomorrow, so it proved nothing it claimed. This drives the REAL send path instead:
 * `runCli` for each adapter over a stubbed `spawn`, capturing the exact bytes written to
 * the child's stdin. If a provider-specific prompt fork ever appears — in `plan`, in
 * `renderPrompt`, in an adapter, or in the transport — these bytes diverge and this fails.
 */
describe("one op, two adapters, one prompt", () => {
  /** What the stubbed child said back; both adapters can read this shape. */
  const STDOUT = '{"result":"ok"}';

  function stubChild() {
    const written: Buffer[] = [];
    const child: any = {
      stdin: {
        write: (chunk: string) => { written.push(Buffer.from(chunk, "utf8")); },
        end: () => undefined,
      },
      stdout: {
        setEncoding: () => undefined,
        on: (ev: string, cb: (c: string) => void) => { if (ev === "data") cb(STDOUT); },
      },
      stderr: { setEncoding: () => undefined, on: () => undefined },
      on: (ev: string, cb: (code: number) => void) => {
        if (ev === "close") setImmediate(() => cb(0));
      },
    };
    return { child, written };
  }

  /** Run one prompt through one adapter and report exactly what went down the pipe. */
  async function sent(adapter: CliAdapter, opts: { systemPrompt: string; prompt: string }) {
    const { child, written } = stubChild();
    (spawn as unknown as jest.Mock).mockReturnValueOnce(child);
    await runCli(adapter, opts);
    const call = (spawn as unknown as jest.Mock).mock.calls.at(-1)!;
    return { stdin: Buffer.concat(written), commandLine: call[1][1] as string };
  }

  beforeEach(() => (spawn as unknown as jest.Mock).mockReset());

  /** Three structurally different ops: a schema'd sheet, an array-of-tasks, and the one
   *  free-text op — whose prompt must NOT carry the schema instruction on either provider. */
  const CASES: Array<[string, Record<string, unknown>]> = [
    ["runTask", {
      language: "en", companion_id: "nova", context: "ACME sells widgets.",
      task_title: "Write the launch email", task_detail: "Announce the beta", dept_key: "mkt",
    }],
    ["generateRoadmap", {
      language: "en", brief: { projectName: "Codepet", oneLiner: "an app for founders" },
    }],
    ["chatSession", {
      session_id: "s1", language: "en", user_message: "why did that work?",
      history: [{ role: "user", text: "hello" }],
      session_context: { turns: [{ prompt: "add a login screen", events: [] }], summary: "s", lesson: "l" },
    }],
  ];

  it.each(CASES)("sends %s byte-identically to both binaries", async (op, body) => {
    const plan = ONE_SHOT_OPS[op].plan(body);
    // Rendered ONCE, by the provider-blind builder, exactly as the sidecar renders it.
    const prompt = renderPrompt(plan.prompt ?? "", plan.schema, plan.freeText === true);
    const systemPrompt = plan.system ?? "";

    const viaClaude = await sent(claudeAdapter, { systemPrompt, prompt });
    const viaCodex = await sent(codexAdapter, { systemPrompt, prompt });

    // THE assertion: the same bytes, not the same substring.
    expect(Buffer.compare(viaCodex.stdin, viaClaude.stdin)).toBe(0);
    expect(Buffer.compare(viaCodex.stdin, Buffer.from(prompt, "utf8"))).toBe(0);

    // ...and the ONLY thing that differs is the command line, which is the seam's whole job.
    expect(viaCodex.commandLine).not.toBe(viaClaude.commandLine);
    expect(viaCodex.commandLine.startsWith("codex 'exec' ")).toBe(true);
    expect(viaClaude.commandLine.startsWith("claude '-p' ")).toBe(true);
    // The prompt travels on STDIN on both, never in argv where a flag could swallow it.
    expect(viaCodex.commandLine).not.toContain(prompt);
    expect(viaClaude.commandLine).not.toContain(prompt);
  });
});
