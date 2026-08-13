/**
 * What the cache breakpoint in composeAgentSystem can and cannot buy.
 *
 * The API caches on an exact byte prefix, and the render order is
 * tools -> system -> messages. The breakpoint sits on system[0], so the cached
 * prefix is `tools + system[0]` — NOT system[0] alone. Every phase of a run
 * sends a different tool, so no phase can read another phase's entry, however
 * identical their system blocks look.
 *
 * These tests capture the real arguments each phase produces and compare the
 * bytes that actually form the cache key.
 */
import { runIndependentPass } from "../company/independentPass";
import { runNegotiation } from "../company/negotiation";
import { AgentCaller } from "../company/router";
import { AgentId, AgentPosition, Conflict, FounderContext, TokenUsage } from "../company/types";

const founder: FounderContext = {
  profile: "Solo founder, one prior product.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire this quarter."],
  language: "en"
};
const rawRequest = "Should I add team seats or price single-player first?";
const realQuestion = "Which pricing bet do we make now?";
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

const position: AgentPosition = {
  stance: "proceed",
  position: "p",
  reasoning: "r",
  evidence_needed: [],
  risks_i_own: [],
  confidence: 3,
  cost_to_my_dept: "c",
  hard_blocker: null
};

/** The bytes the API hashes for the breakpoint on system[0]. */
const cacheKeyOf = (a: Parameters<AgentCaller>[0]) =>
  JSON.stringify({ tools: [a.tool], system0: a.system[0].text });

function capturing(sink: Parameters<AgentCaller>[0][]): AgentCaller {
  return async (a) => {
    sink.push(a);
    return {
      input: {
        stance: "proceed", position: "p", reasoning: "r", confidence: 3,
        cost_to_my_dept: "c", hard_blocker: null,
        // negotiation tool fields
        moved: false, concession: "", still_blocking: "", response_to: ""
      },
      usage: zeroUsage,
      stopReason: "tool_use"
    };
  };
}

describe("cache prefix across Virtual Company phases", () => {
  test("all departments in one phase share a byte-identical cache prefix", async () => {
    const seen: Parameters<AgentCaller>[0][] = [];
    await runIndependentPass({
      founder, rawRequest, realQuestion,
      agents: ["product", "finance", "engineering"],
      call: capturing(seen)
    });
    const keys = new Set(seen.map(cacheKeyOf));
    expect(seen.length).toBeGreaterThanOrEqual(3);
    expect(keys.size).toBe(1);
  });

  test("every one of them carries the breakpoint, so each is a WRITE", async () => {
    // They are dispatched concurrently and an entry is only readable once one
    // has finished writing it — so in this phase every copy pays the write rate
    // and none reads. That is the cost of keeping mutual blindness.
    const seen: Parameters<AgentCaller>[0][] = [];
    await runIndependentPass({
      founder, rawRequest, realQuestion,
      agents: ["product", "finance", "engineering"],
      call: capturing(seen)
    });
    for (const a of seen) {
      expect(a.system[0].cache_control).toEqual({ type: "ephemeral" });
    }
  });

  test("negotiation CANNOT read the positions phase entry — the tool differs", async () => {
    // The correction. The system blocks are identical between the two phases,
    // which is what makes this look like a cache hit on inspection. It is not:
    // tools render before system, so a different tool is a different prefix
    // from byte 0.
    const pass: Parameters<AgentCaller>[0][] = [];
    await runIndependentPass({
      founder, rawRequest, realQuestion,
      agents: ["product", "finance"],
      call: capturing(pass)
    });

    const conflicts: Conflict[] = [
      { a: "product" as AgentId, b: "finance" as AgentId, kind: "CONFLICT", reason: "x" } as Conflict
    ];
    const nego: Parameters<AgentCaller>[0][] = [];
    await runNegotiation({
      founder, rawRequest, realQuestion,
      positions: { product: position, finance: position },
      conflicts,
      call: capturing(nego)
    });

    expect(nego.length).toBeGreaterThan(0);

    // The system prefix really is identical — this is the part that misleads.
    expect(nego[0].system[0].text).toBe(pass[0].system[0].text);

    // But the cache key is not, because the tool in front of it changed.
    expect(cacheKeyOf(nego[0])).not.toBe(cacheKeyOf(pass[0]));
    expect((nego[0].tool as any).name).not.toBe((pass[0].tool as any).name);
  });
});
