import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller } from "./router";
import {
  AgentId,
  AgentPosition,
  Conflict,
  DevilsAdvocateVerdict,
  FounderContext,
  TokenUsage
} from "./types";

const HIGH_CONFIDENCE = 4;

export const DEVILS_ADVOCATE_TOOL = {
  name: "submit_red_team",
  description:
    "Submit your red-team analysis. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      load_bearing_assumption: {
        type: "string",
        description: "The one belief that, if false, collapses everything."
      },
      how_it_could_be_false: { type: "string" },
      cheapest_test: {
        type: "string",
        description:
          "The cheapest way to find out quickly. Every objection must be actionable."
      },
      failure_post_mortem: {
        type: "string",
        description:
          "It is twelve months from now and this was a clear mistake. Two sentences on why — the actual mechanism, not 'the market changed'."
      },
      who_is_not_in_the_room: {
        type: "string",
        description:
          "Whose interest has no representative here. Usually the user who churns silently, the engineer who inherits this, or the founder's own time."
      },
      objections: {
        type: "array",
        items: { type: "string" },
        description: "Ranked. Lead with the one that would change the decision."
      },
      plan_is_sound: {
        type: "boolean",
        description:
          "True if the plan is genuinely sound. A red team that always finds fatal flaws is noise."
      }
    },
    required: [
      "load_bearing_assumption",
      "how_it_could_be_false",
      "cheapest_test",
      "failure_post_mortem",
      "who_is_not_in_the_room",
      "plan_is_sound"
    ],
    additionalProperties: false
  }
};

export function parseDevilsAdvocateInput(
  input: unknown
): DevilsAdvocateVerdict | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "red team tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;
  const str = (key: string): string =>
    typeof raw[key] === "string" ? (raw[key] as string).trim() : "";

  for (const required of [
    "load_bearing_assumption",
    "cheapest_test",
    "failure_post_mortem"
  ]) {
    if (str(required).length === 0) {
      return { error: `${required} is required` };
    }
  }

  return {
    load_bearing_assumption: str("load_bearing_assumption"),
    how_it_could_be_false: str("how_it_could_be_false"),
    cheapest_test: str("cheapest_test"),
    failure_post_mortem: str("failure_post_mortem"),
    who_is_not_in_the_room: str("who_is_not_in_the_room"),
    objections: Array.isArray(raw.objections)
      ? raw.objections.filter((o): o is string => typeof o === "string")
      : [],
    plan_is_sound: raw.plan_is_sound === true
  };
}

/**
 * The false-consensus countermeasure (spec §3.8). Pure so it can be reasoned
 * about and tested without a model call.
 *
 * The spec's primary trigger is "three or more departments align quickly", which
 * cannot occur with a 2-department MVP roster. The equivalent signal here is:
 * the room agrees, confidence is high, and at least one agent could not name the
 * evidence its confidence rests on. That combination is exactly when nobody is
 * checking the premise.
 *
 * The evidence check is `some`, not `every`, on purpose. One department naming
 * its falsifiers does not make an over-confident room well-evidenced, and firing
 * the red team is cheap next to an expensive wrong decision — it is instructed
 * to answer "plan is sound" when the plan is sound, so a false positive costs
 * one call rather than a bad brief.
 */
export function shouldInvokeDevilsAdvocate(args: {
  positions: Partial<Record<AgentId, AgentPosition>>;
  conflicts: Conflict[];
  founderRequested?: boolean;
}): boolean {
  if (args.founderRequested === true) return true;

  const present = Object.values(args.positions).filter(
    (p): p is AgentPosition => p !== undefined
  );
  if (present.length < 2) return false;

  const hasLiveDisagreement = args.conflicts.some(
    (c) => c.kind === "CONFLICT" || c.kind === "BLOCKER"
  );
  // A live conflict already gives the founder the tension the red team exists
  // to manufacture. Spending a top-tier call on it adds noise, not signal.
  if (hasLiveDisagreement) return false;

  const allConfident = present.every((p) => p.confidence >= HIGH_CONFIDENCE);
  const evidenceIsThin = present.some((p) => p.evidence_needed.length === 0);
  return allConfident && evidenceIsThin;
}

const RED_TEAM_INSTRUCTION = `The room has reached a view. Stress-test it.

THE REAL QUESTION AT STAKE:
<real_question>

WHAT EACH DEPARTMENT SAID:
<positions>

Work through all four parts of your method: find the load-bearing assumption,
write the failure post-mortem, attack the strongest version of the
recommendation rather than the weakest, and name who is not in the room.

If the plan is genuinely sound, say so plainly and name the one thing you would
still monitor. Do not be contrarian for its own sake.

Call submit_red_team.`;

function renderPositions(positions: Partial<Record<AgentId, AgentPosition>>): string {
  return Object.entries(positions)
    .filter(([, p]) => p !== undefined)
    .map(([agent, p]) => {
      const position = p as AgentPosition;
      const blocker = position.hard_blocker
        ? `\n   HARD BLOCKER: ${position.hard_blocker}`
        : "";
      return `${agent} (stance: ${position.stance}, confidence ${position.confidence}/5):\n   ${position.position}\n   Reasoning: ${position.reasoning}\n   Cost to their own department: ${position.cost_to_my_dept}${blocker}`;
    })
    .join("\n\n");
}

export async function runDevilsAdvocate(args: {
  founder: FounderContext;
  rawRequest: string;
  realQuestion: string;
  positions: Partial<Record<AgentId, AgentPosition>>;
  call: AgentCaller;
}): Promise<{ verdict: DevilsAdvocateVerdict; model: string; usage: TokenUsage }> {
  const model = AGENT_DEFS.devils_advocate.model;
  const { input, usage } = await args.call({
    agent: "devils_advocate",
    model,
    system: composeAgentSystem({
      agent: "devils_advocate",
      founder: args.founder,
      rawRequest: args.rawRequest,
      // One call, no retry, and its tool is unique to this phase — nothing will
      // ever read what a breakpoint here would write.
      cache: false
    }),
    userMessage: RED_TEAM_INSTRUCTION.replace(
      "<real_question>",
      args.realQuestion.trim()
    ).replace("<positions>", renderPositions(args.positions)),
    tool: DEVILS_ADVOCATE_TOOL,
    toolName: DEVILS_ADVOCATE_TOOL.name
  });

  const parsed = parseDevilsAdvocateInput(input);
  if ("error" in parsed) {
    throw new Error(`unusable verdict from devils_advocate: ${parsed.error}`);
  }
  return { verdict: parsed, model, usage };
}
