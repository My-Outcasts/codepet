import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller } from "./router";
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

  // allSettled, not all: one department failing must not take down the room
  // (spec §5.5 graceful degradation).
  const settled = await Promise.allSettled(
    args.agents.map(async (agent): Promise<PassResult> => {
      const model = AGENT_DEFS[agent].model;
      const { input, usage } = await args.call({
        agent,
        model,
        system: composeAgentSystem({
          agent,
          founder: args.founder,
          rawRequest: args.rawRequest
        }),
        userMessage,
        tool: POSITION_TOOL,
        toolName: POSITION_TOOL.name
      });

      const parsed = parsePositionToolInput(input);
      if ("error" in parsed) {
        // The call was still billed, so usage is reported either way.
        return { agent, error: parsed.error, usage, model };
      }
      return { agent, position: parsed, usage, model };
    })
  );

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
