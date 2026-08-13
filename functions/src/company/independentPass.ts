import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller, POSITION_EFFORT } from "./router";
import {
  AgentId,
  AgentPosition,
  Confidence,
  FounderContext,
  Stance,
  TokenUsage
} from "./types";

const STANCES: Stance[] = ["proceed", "proceed_with_conditions", "do_not_proceed"];

export const POSITION_TOOL = {
  name: "submit_position",
  description:
    "Submit your department's independent position on this decision. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      stance: {
        type: "string",
        enum: STANCES,
        description:
          "Machine-readable summary of your view. do_not_proceed only if you genuinely believe the founder should not do this; reservations are proceed_with_conditions."
      },
      position: { type: "string", description: "Your stance in 1-2 sentences." },
      reasoning: { type: "string", description: "Why, through your department's lens only." },
      evidence_needed: {
        type: "array",
        items: { type: "string" },
        description: "What would raise your confidence, named concretely enough to go and collect."
      },
      risks_i_own: {
        type: "array",
        items: { type: "string" },
        description: "Risks inside your remit, not someone else's."
      },
      confidence: {
        type: "integer",
        minimum: 1,
        maximum: 5,
        description: "At most 2 if you cannot name falsifying evidence."
      },
      cost_to_my_dept: {
        type: "string",
        description: "What your own recommendation costs YOUR department."
      },
      hard_blocker: {
        type: ["string", "null"],
        description:
          "Your single non-negotiable, or null. Use sparingly: this means 'I cannot accept this outcome under any framing', not 'I would prefer otherwise'."
      }
    },
    required: [
      "stance",
      "position",
      "reasoning",
      "confidence",
      "cost_to_my_dept",
      "hard_blocker"
    ],
    additionalProperties: false
  }
};

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];
}

function clampConfidence(value: unknown): Confidence {
  const n = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 3;
  return Math.min(5, Math.max(1, n)) as Confidence;
}

export function parsePositionToolInput(input: unknown): AgentPosition | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "position tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;

  const stance = raw.stance;
  if (typeof stance !== "string" || !(STANCES as string[]).includes(stance)) {
    return { error: `unknown stance: ${String(stance)}` };
  }
  if (typeof raw.position !== "string" || raw.position.trim().length === 0) {
    return { error: "position is required" };
  }

  // Models sometimes emit "" or "  " instead of null. An empty string must not
  // read as a hard blocker — that would fabricate a BLOCKER in phase 3.
  const blockerRaw = typeof raw.hard_blocker === "string" ? raw.hard_blocker.trim() : "";
  const hardBlocker = blockerRaw.length > 0 ? blockerRaw : null;

  return {
    stance: stance as Stance,
    position: raw.position.trim(),
    reasoning: typeof raw.reasoning === "string" ? raw.reasoning.trim() : "",
    evidence_needed: stringList(raw.evidence_needed),
    risks_i_own: stringList(raw.risks_i_own),
    confidence: clampConfidence(raw.confidence),
    cost_to_my_dept:
      typeof raw.cost_to_my_dept === "string" ? raw.cost_to_my_dept.trim() : "",
    hard_blocker: hardBlocker
  };
}

/**
 * The user message for Phase 2. Contains the request and the real question and
 * NOTHING derived from another agent — not their output, and not even their
 * names. That omission is the entire point of this phase (spec §2.2 Phase 2):
 * an agent that knows who else is in the room starts writing for them.
 */
const POSITION_INSTRUCTION = `Give your independent position on this decision.

You are answering at the same moment as the other departments and you cannot
see what any of them said. Do not speculate about their views or pre-emptively
concede to them. Answer only from your own department's lens.

THE REAL QUESTION AT STAKE:
<real_question>

Call submit_position.`;

export interface PassResult {
  agent: AgentId;
  position?: AgentPosition;
  error?: string;
  usage: TokenUsage;
  model: string;
}

function addUsage(a: TokenUsage, b: TokenUsage): TokenUsage {
  return {
    input: a.input + b.input,
    output: a.output + b.output,
    cache_read: a.cache_read + b.cache_read
  };
}

export async function runIndependentPass(args: {
  founder: FounderContext;
  rawRequest: string;
  realQuestion: string;
  agents: AgentId[];
  call: AgentCaller;
}): Promise<{ results: PassResult[] }> {
  const userMessage = POSITION_INSTRUCTION.replace(
    "<real_question>",
    args.realQuestion.trim()
  );

  const runOne = async (agent: AgentId): Promise<PassResult> => {
    const model = AGENT_DEFS[agent].model;
    const system = composeAgentSystem({
      agent,
      founder: args.founder,
      rawRequest: args.rawRequest
    });
    const ask = (message: string) =>
      args.call({
        agent,
        model,
        system,
        userMessage: message,
        tool: POSITION_TOOL,
        toolName: POSITION_TOOL.name,
        effort: POSITION_EFFORT
      });

    const first = await ask(userMessage);
    const parsed = parsePositionToolInput(first.input);
    if (!("error" in parsed)) {
      return { agent, position: parsed, usage: first.usage, model };
    }

    // Measured on real runs: the model drops a required field (usually stance)
    // in roughly 1 call in 3, with stop_reason=tool_use — the schema is a hint,
    // not a constraint. Losing a department to that silently degrades the run to
    // a single opinion, which is the one outcome this feature exists to prevent,
    // so a rejected position is asked again once with the reason quoted back.
    const retry = await ask(
      `${userMessage}\n\nYour previous submit_position call was rejected: ${parsed.error}. ` +
        `Every required field must be present, including stance. Call submit_position again ` +
        `with all of them.`
    );
    // Both calls were billed, so both are reported whichever way this ends.
    const usage = addUsage(first.usage, retry.usage);
    const reparsed = parsePositionToolInput(retry.input);
    if ("error" in reparsed) {
      return { agent, error: reparsed.error, usage, model };
    }
    return { agent, position: reparsed, usage, model };
  };

  // Concurrent dispatch is load-bearing, not incidental: it is the second line
  // of defence for mutual blindness (spec §2.2 Phase 2), because a sequential
  // loop is what would let a later refactor thread an earlier position into a
  // later prompt. See the concurrency test in companyIndependentPass.test.ts.
  //
  // It does cost money. Every agent here sends a byte-identical cached prefix,
  // and a cache entry is only readable once some request has finished writing
  // it — so N concurrent agents each WRITE the prefix at 1.25x and none reads.
  // Round 2 (negotiation) does read those entries, which is what keeps the
  // breakpoint net-positive overall (1.35x per copy across both rounds, against
  // 2.0x with no caching at all). Running one department to completion first
  // would take the two rounds to ~0.2x per copy, at the price of one call's
  // latency and of weakening the guarantee above. That trade is deliberately
  // not taken here.
  //
  // allSettled, not all: one department failing must not take down the room
  // (spec §5.5 graceful degradation).
  const settled = await Promise.allSettled(args.agents.map(runOne));

  const zero: TokenUsage = { input: 0, output: 0, cache_read: 0 };
  const results: PassResult[] = settled.map((outcome, i) => {
    if (outcome.status === "fulfilled") return outcome.value;
    return {
      agent: args.agents[i],
      error: String(outcome.reason),
      usage: zero,
      model: AGENT_DEFS[args.agents[i]].model
    };
  });

  return { results };
}
