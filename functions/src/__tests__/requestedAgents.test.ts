import { applyRequestedAgents } from "../company/router";
import { runVirtualCompany, validateRunPayload } from "../company/orchestrate";
import { RoutingDecision } from "../company/types";

// 9 Oct: a founder who presses "Bring Finance + Sales in" must get that room. Without this the
// router could still answer single_agent and the escape hatch would discard the room — the
// button would do nothing visible.
const single: RoutingDecision = {
  decision: "single_agent", agents: ["finance"], real_question: "Is a discount worth it?",
  request_type: "DECISION", reason_per_agent: {}, excluded: {}, missing_info: [],
};

describe("applyRequestedAgents", () => {
  it("forces the founder's room over a single_agent routing, keeping the real question", () => {
    const r = applyRequestedAgents(single, ["finance", "sales"]);
    expect(r.decision).toBe("multi_agent");
    expect(r.agents).toEqual(["finance", "sales"]);
    expect(r.real_question).toBe("Is a discount worth it?");
  });
  it("keeps the red team when the router named it, outside the cap", () => {
    const r = applyRequestedAgents({ ...single, agents: ["finance", "devils_advocate"] },
      ["finance", "sales", "marketing", "legal", "support"]);
    expect(r.agents).toEqual(["finance", "sales", "marketing", "legal", "devils_advocate"]);
  });
  // Review, 9 Oct: the panel showed "✗ Sales — not a pricing question" under NOT IN THE ROOM
  // while Sales sat in the room, and gave Sales no ✓ line. A forced room must read as one.
  it("makes the routing panel agree with the forced room", () => {
    const r = applyRequestedAgents(
      { ...single, decision: "needs_clarification", excluded: { sales: "not a pricing question", legal: "no contract" },
        reason_per_agent: { finance: "owns price" }, missing_info: ["current conversion rate"] },
      ["finance", "sales"]);
    expect(r.excluded).toEqual({ legal: "no contract" });
    expect(r.reason_per_agent.finance).toBe("owns price");
    expect(r.reason_per_agent.sales).toMatch(/founder/i);
    expect(r.missing_info).toEqual([]);
  });
  it("leaves the routing alone with fewer than two routable departments", () => {
    expect(applyRequestedAgents(single, ["finance"])).toBe(single);
    expect(applyRequestedAgents(single, ["chief_of_staff", "devils_advocate", "product", "finance"])).toBe(single);
    expect(applyRequestedAgents(single, undefined)).toBe(single);
    expect(applyRequestedAgents(single, "finance")).toBe(single);
  });
});

describe("validateRunPayload agents", () => {
  const valid = { request: "q", language: "en", founder: { profile: "", stage: "", constraints: [] } };
  it("accepts a string array or nothing", () => {
    expect(validateRunPayload(valid)).toBeNull();
    expect(validateRunPayload({ ...valid, agents: ["finance"] })).toBeNull();
  });
  it("rejects anything else", () => {
    expect(validateRunPayload({ ...valid, agents: "finance" })).toMatch(/agents/);
    expect(validateRunPayload({ ...valid, agents: [1] })).toMatch(/agents/);
  });
});

describe("a founder-picked room never escapes", () => {
  async function run(agents?: string[]) {
    const events: Array<[string, any]> = [];
    let calls = 0;
    await runVirtualCompany({
      payload: { request: "Discount?", language: "en", founder: { profile: "", stage: "", constraints: [] }, ...(agents ? { agents } : {}) } as any,
      uid: "u", runId: "r",
      call: async () => {
        calls += 1;
        if (calls === 1) {
          return { input: { ...single, agents: ["finance"] }, usage: { input: 1, output: 1, cache_read: 0 } } as any;
        }
        throw new Error("stop after intake");
      },
      emit: (e, p) => events.push([e, p]),
      persist: async () => {},
      logError: () => {},
    });
    return events;
  }
  it("runs the requested departments even when the router says single_agent", async () => {
    const ev = await run(["finance", "sales"]);
    const routing = ev.find(([e]) => e === "routing")?.[1];
    expect(routing.decision).toBe("multi_agent");
    expect(ev.filter(([e]) => e === "agent_start").map(([, p]) => p.agent_id)).toEqual(["finance", "sales"]);
    expect(ev.some(([e, p]) => e === "done" && p.skipped === "single_agent")).toBe(false);
  });
  it("escapes as before without agents", async () => {
    const ev = await run();
    expect(ev.some(([e, p]) => e === "done" && p.skipped === "single_agent")).toBe(true);
  });
});
