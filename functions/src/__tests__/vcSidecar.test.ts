import { agentPrompt } from "../local/vcSidecar";
import { usageFrom } from "../local/claudeCli";
import { runVirtualCompany, RunPayload } from "../company/orchestrate";
import { AgentCaller } from "../company/router";

/**
 * The local virtual-company path: a meeting running on the founder's own Claude Code.
 *
 * Two things are worth guarding here, and neither is about a prompt's wording:
 *  - the SSE FRAME ORDER, because that order IS the client contract
 *    (`docs/superpowers/specs/virtual-company-sse-contract.md`), and it is now produced by
 *    one shared orchestrator that two transports call;
 *  - what the local `AgentCaller` reports back, since the run ceilings are computed from it.
 */

describe("agentPrompt", () => {
  const tool = {
    name: "record_position",
    input_schema: { type: "object", properties: { stance: { type: "string" } } },
  };

  it("keeps the phase's own user message first, verbatim", () => {
    expect(agentPrompt({ userMessage: "What is the price?", tool }).startsWith("What is the price?"))
      .toBe(true);
  });

  /**
   * The API forces the agent's tool; `claude -p` cannot. So the same `input_schema` is asked
   * for in prose — a paraphrase would be a second source of truth and would drift the first
   * time a field was added to a position.
   */
  it("asks for the agent tool's own schema", () => {
    expect(agentPrompt({ userMessage: "q", tool })).toContain('"stance"');
  });

  it("survives a tool with no schema rather than throwing mid-meeting", () => {
    expect(() => agentPrompt({ userMessage: "q", tool: null })).not.toThrow();
  });
});

describe("usageFrom", () => {
  /**
   * MEASURED, not assumed: a real local meeting reported `input_tokens: 2` for a department
   * whose prompt was thousands of tokens, because Claude Code cached the prefix and billed it
   * as `cache_creation_input_tokens`. Counting only `input_tokens` would leave the run
   * ceiling — the one guard against a runaway loop on the founder's own plan — seeing almost
   * no input at all.
   */
  it("counts a cache write as input, because that is what it is", () => {
    expect(usageFrom({ usage: { input_tokens: 2, cache_creation_input_tokens: 4000, output_tokens: 800 } }))
      .toEqual({ input: 4002, output: 800, cache_read: 0 });
  });

  it("reports zeroes rather than NaN when the envelope carries no usage", () => {
    expect(usageFrom({})).toEqual({ input: 0, output: 0, cache_read: 0 });
  });

  it("passes cache reads through for the telemetry the founder can see", () => {
    expect(usageFrom({ usage: { cache_read_input_tokens: 900 } }).cache_read).toBe(900);
  });
});

/**
 * The frame order, driven through the SHARED orchestrator with a stubbed caller — so it
 * covers the cloud path and the local path at once. That is the point of the extraction:
 * before it, this order existed only inside an HTTP handler and nothing tested it.
 */
describe("runVirtualCompany frame order", () => {
  const payload: RunPayload = {
    request: "Should we charge $19 or $49 a month?",
    language: "en",
    founder: { profile: "solo founder", stage: "Private beta", constraints: ["6 months runway"] },
  };

  /** Answers every phase with the minimum its parser accepts. */
  const stubCaller = (routed: string[]): AgentCaller => async (args) => {
    const usage = { input: 10, output: 10, cache_read: 0 };
    if (args.toolName === "record_routing") {
      return {
        input: {
          decision: "multi_agent",
          request_type: "DECISION",
          real_question: "Which price survives the runway?",
          agents: routed,
          why_these_agents: "money and customers",
        },
        usage,
        stopReason: "end_turn",
      };
    }
    if (args.toolName === "submit_position") {
      return {
        input: {
          stance: "proceed_with_conditions",
          position: "Charge $49.",
          reasoning: "The conversion maths at $19 needs the whole waitlist.",
          confidence: 3,
          what_would_change_my_mind: "30 waitlist calls saying no at $49.",
          hard_blocker: null,
        },
        usage,
        stopReason: "end_turn",
      };
    }
    return {
      input: {
        recommendation: "Charge $49 and test it.",
        the_real_disagreement: "Whether price or volume protects the runway.",
        tradeoff_founder_must_own: "Either test at $49 for two weeks, or launch at $19 now.",
        confidence: 3,
        confidence_reason: "The maths is clear; the demand is not.",
        what_we_dont_know: "What the waitlist will actually pay.",
        next_action: "Call 30 people on the waitlist.",
        kill_criteria: "Fewer than 5 of 30 accept $49.",
        unresolved: false,
      },
      usage,
      stopReason: "end_turn",
    };
  };

  const collect = async (routed: string[]) => {
    const events: string[] = [];
    await runVirtualCompany({
      payload,
      uid: "u1",
      runId: "run_test",
      call: stubCaller(routed),
      emit: (event, data) => events.push(event === 'error' ? `error:${JSON.stringify(data)}` : event),
      persist: async () => {},
    });
    return events;
  };

  it("opens every column before any position arrives, and ends on the brief", async () => {
    const events = await collect(["finance", "sales"]);
    expect(events).toEqual([
      "run_started",
      "routing",
      // Both starts before both positions: that simultaneity is what reads as a room
      // thinking, and a client that opened columns one at a time would lose it.
      "agent_start",
      "agent_start",
      "agent_position",
      "agent_position",
      "conflicts",
      "brief",
      "telemetry",
      "done",
    ]);
  });

  /**
   * The router's escape hatch. A request that needs no room must not convene one — that is
   * the difference between a ~$0.20 decision and a ~$0.005 one on the cloud path, and
   * between a 90-second wait and an instant answer on the local one.
   */
  it("stops after routing when the router declines to convene", async () => {
    const events: string[] = [];
    await runVirtualCompany({
      payload,
      uid: "u1",
      runId: "run_test",
      call: async () => ({
        input: {
          decision: "single_agent",
          request_type: "DECISION",
          real_question: "q",
          agents: ["finance"],
          why_these_agents: "one is enough",
        },
        usage: { input: 1, output: 1, cache_read: 0 },
        stopReason: "end_turn",
      }),
      emit: (event) => events.push(event),
      persist: async () => {},
    });
    expect(events).toEqual(["run_started", "routing", "telemetry", "done"]);
  });

  /**
   * A failure is reported as a frame and the run is still persisted best-effort — the client
   * must never be left with a stream that simply stops.
   */
  it("emits an error frame rather than throwing out of the run", async () => {
    const events: string[] = [];
    let persisted = false;
    await runVirtualCompany({
      payload,
      uid: "u1",
      runId: "run_test",
      call: async () => { throw new Error("claude not logged in"); },
      emit: (event) => events.push(event),
      persist: async () => { persisted = true; },
    });
    expect(events).toEqual(["run_started", "error"]);
    expect(persisted).toBe(true);
  });
});
