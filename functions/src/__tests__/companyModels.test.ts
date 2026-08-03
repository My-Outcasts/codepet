import { ROUTER_MODEL, AGENT_MODEL, SYNTHESIS_MODEL, MODEL_PRICING } from "../anthropic";

describe("virtual company model tiering", () => {
  test("router uses the cheapest tier", () => {
    expect(ROUTER_MODEL).toBe("claude-haiku-4-5");
  });

  test("department agents use sonnet 5", () => {
    expect(AGENT_MODEL).toBe("claude-sonnet-5");
  });

  test("synthesis and red team use opus 5", () => {
    expect(SYNTHESIS_MODEL).toBe("claude-opus-5");
  });

  test("model ids carry no date suffix", () => {
    for (const id of [ROUTER_MODEL, AGENT_MODEL, SYNTHESIS_MODEL]) {
      expect(id).not.toMatch(/-\d{8}$/);
    }
  });

  test("pricing is defined for every tier used", () => {
    for (const id of [ROUTER_MODEL, AGENT_MODEL, SYNTHESIS_MODEL]) {
      expect(MODEL_PRICING[id]).toBeDefined();
      expect(MODEL_PRICING[id].inputPerMTok).toBeGreaterThan(0);
      expect(MODEL_PRICING[id].outputPerMTok).toBeGreaterThan(0);
    }
  });

  test("every tier declares its minimum cacheable prefix", () => {
    // Below this floor, cache_control silently no-ops — no error, just full price.
    for (const id of [ROUTER_MODEL, AGENT_MODEL, SYNTHESIS_MODEL]) {
      expect(MODEL_PRICING[id].cacheMinTokens).toBeGreaterThan(0);
    }
  });
});
