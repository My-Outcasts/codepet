import {
  cacheableSystemBlock,
  estimatePromptTokens,
  MODEL,
  MODEL_PRICING,
  NARRATIVE_TOOL,
  priceFor,
  SESSION_SUMMARY_TOOL,
  SESSION_SYSTEM_PROMPT,
  SYSTEM_PROMPT
} from "../anthropic";

/** A prefix long enough to clear any floor in MODEL_PRICING. */
const LONG = "x".repeat(4096 * 4);

describe("priceFor", () => {
  test("resolves a dated snapshot id to its alias entry", () => {
    // MODEL is claude-haiku-4-5-20251001; the table is keyed on the alias. A
    // lookup that missed here would silently return undefined, and
    // cacheableSystemBlock would then keep every marker it should drop.
    expect(MODEL).not.toBe("claude-haiku-4-5");
    expect(priceFor(MODEL)).toBe(MODEL_PRICING["claude-haiku-4-5"]);
  });

  test("returns undefined for a model that is not in the table", () => {
    expect(priceFor("claude-something-unreleased")).toBeUndefined();
  });
});

describe("cacheableSystemBlock", () => {
  test("drops the breakpoint below the model's minimum cacheable prefix", () => {
    const block = cacheableSystemBlock({ model: "claude-haiku-4-5", text: "short" });
    expect(block.cache_control).toBeUndefined();
    expect(block.text).toBe("short");
  });

  test("keeps the breakpoint once the prefix clears the minimum", () => {
    const block = cacheableSystemBlock({ model: "claude-haiku-4-5", text: LONG });
    expect(block.cache_control).toEqual({ type: "ephemeral" });
  });

  test("counts the tool schema, which renders before system", () => {
    // A prefix that is under the floor on its own but over it once the tools
    // that precede it are counted must keep the marker. Without this the guard
    // would drop breakpoints that would have fired.
    const floor = MODEL_PRICING["claude-haiku-4-5"].cacheMinTokens;
    const toolTokens = estimatePromptTokens(JSON.stringify(NARRATIVE_TOOL));
    expect(toolTokens).toBeLessThan(floor);
    const text = "y".repeat(Math.round((floor - toolTokens + 20) * 3.5));
    expect(estimatePromptTokens(text)).toBeLessThan(floor);

    expect(cacheableSystemBlock({ model: "claude-haiku-4-5", text }).cache_control)
      .toBeUndefined();
    expect(
      cacheableSystemBlock({ model: "claude-haiku-4-5", text, tools: NARRATIVE_TOOL })
        .cache_control
    ).toEqual({ type: "ephemeral" });
  });

  test("keeps the breakpoint for a model with no known floor", () => {
    // Unknown model: a dead marker is free, a missing one is not.
    expect(
      cacheableSystemBlock({ model: "claude-something-unreleased", text: "short" })
        .cache_control
    ).toEqual({ type: "ephemeral" });
  });

  test("the two Haiku narrative prefixes are below Haiku's floor, markers dropped", () => {
    // The reason this guard exists. Both of these carried a cache_control that
    // the API silently ignored, which made cache_hit read as a permanent miss
    // rather than as a cache that was never possible. If either prefix later
    // grows past 4096 this test goes red and the marker should come back —
    // that is a real change in behaviour and should not pass unnoticed.
    const floor = MODEL_PRICING["claude-haiku-4-5"].cacheMinTokens;

    const turn = estimatePromptTokens(SYSTEM_PROMPT) +
      estimatePromptTokens(JSON.stringify(NARRATIVE_TOOL));
    const session = estimatePromptTokens(SESSION_SYSTEM_PROMPT) +
      estimatePromptTokens(JSON.stringify(SESSION_SUMMARY_TOOL));

    expect(turn).toBeLessThan(floor);
    expect(session).toBeLessThan(floor);

    expect(
      cacheableSystemBlock({ model: MODEL, text: SYSTEM_PROMPT, tools: NARRATIVE_TOOL })
        .cache_control
    ).toBeUndefined();
    expect(
      cacheableSystemBlock({
        model: MODEL,
        text: SESSION_SYSTEM_PROMPT,
        tools: SESSION_SUMMARY_TOOL
      }).cache_control
    ).toBeUndefined();
  });
});
