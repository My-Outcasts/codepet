import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller } from "./router";
import {
  AgentId,
  AgentPosition,
  Confidence,
  Conflict,
  DecisionBrief,
  DevilsAdvocateVerdict,
  FounderContext,
  NegotiationRound,
  TokenUsage
} from "./types";

export const BRIEF_TOOL = {
  name: "record_decision_brief",
  description:
    "Record the decision brief. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      recommendation: {
        type: "string",
        description:
          "One paragraph. Judged on one criterion: could the founder act tomorrow morning?"
      },
      confidence: { type: "integer", minimum: 1, maximum: 5 },
      confidence_reason: { type: "string", description: "Why that confidence and not higher." },
      the_real_disagreement: {
        type: "string",
        description:
          "Who opposed, on what grounds, quoted closely enough that the founder can judge for themselves. Never average opposing views into a middle position nobody argued for. If nobody disagreed, say so explicitly."
      },
      tradeoff_founder_must_own: {
        type: "string",
        description:
          "The choice no department can make for them, stated as a clean either/or. Never end on 'it depends on your priorities' without saying what those priorities trade against."
      },
      kill_criteria: {
        type: "array",
        items: { type: "string" },
        description:
          "Observable events that mean 'we were wrong, stop'. At least one. Always an array, even when there is only one criterion."
      },
      next_action: {
        type: "object",
        properties: {
          action: { type: "string", description: "Small enough to start today." },
          owner: { type: "string" }
        },
        required: ["action", "owner"],
        additionalProperties: false
      },
      what_we_dont_know: {
        type: "string",
        description: "The gap that most threatens this recommendation."
      },
      unresolved: {
        type: "boolean",
        description: "True if a trade-off could not be resolved. A valid, honest outcome."
      }
    },
    required: [
      "recommendation",
      "confidence",
      "the_real_disagreement",
      "tradeoff_founder_must_own",
      "kill_criteria",
      "next_action",
      "what_we_dont_know"
    ],
    additionalProperties: false
  }
};

function clampConfidence(value: unknown): Confidence {
  const n = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 3;
  return Math.min(5, Math.max(1, n)) as Confidence;
}

export function parseBriefToolInput(input: unknown): DecisionBrief | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "brief tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;
  const str = (key: string): string =>
    typeof raw[key] === "string" ? (raw[key] as string).trim() : "";

  for (const required of [
    "recommendation",
    "tradeoff_founder_must_own",
    "what_we_dont_know"
  ]) {
    if (str(required).length === 0) return { error: `${required} is required` };
  }

  // Opus collapses kill_criteria to a bare string whenever it settles on a single
  // criterion — measured deterministically, 3/3 real runs. Treating that as
  // "no kill criteria" threw away an otherwise usable brief at the most expensive
  // step in the run, so a lone string is read as a one-element list.
  const rawKillCriteria =
    typeof raw.kill_criteria === "string" ? [raw.kill_criteria] : raw.kill_criteria;
  const killCriteria = Array.isArray(rawKillCriteria)
    ? rawKillCriteria.filter((k): k is string => typeof k === "string" && k.trim().length > 0)
    : [];
  if (killCriteria.length === 0) {
    return { error: "kill_criteria requires at least one observable event" };
  }

  const action = raw.next_action;
  if (typeof action !== "object" || action === null) {
    return { error: "next_action is required" };
  }
  const actionText = (action as Record<string, unknown>).action;
  const owner = (action as Record<string, unknown>).owner;
  if (typeof actionText !== "string" || actionText.trim().length === 0) {
    return { error: "next_action.action is required" };
  }
  if (typeof owner !== "string" || owner.trim().length === 0) {
    return { error: "next_action.owner is required" };
  }

  return {
    recommendation: str("recommendation"),
    confidence: clampConfidence(raw.confidence),
    confidence_reason: str("confidence_reason"),
    the_real_disagreement: str("the_real_disagreement"),
    tradeoff_founder_must_own: str("tradeoff_founder_must_own"),
    kill_criteria: killCriteria.map((k) => k.trim()),
    next_action: { action: actionText.trim(), owner: owner.trim() },
    what_we_dont_know: str("what_we_dont_know"),
    unresolved: raw.unresolved === true
  };
}

/** Phrases that mean the brief smoothed the conflict away instead of showing it. */
const CONSENSUS_TELLS = [
  "everyone agreed",
  "all agreed",
  "no disagreement",
  "there was no disagreement",
  "the room agreed",
  "unanimous"
];

/**
 * Mechanical check for the failure mode the feature exists to prevent: a real
 * conflict existed and the brief did not report it. Spec §2.2 Phase 5 forbids
 * blurring the conflict and spec TASK 9 requires asserting dissent survives, so
 * this is enforced in code rather than trusted to the prompt.
 */
export function briefOmitsDissent(brief: DecisionBrief, conflicts: Conflict[]): boolean {
  const hadConflict = conflicts.some((c) => c.kind === "CONFLICT" || c.kind === "BLOCKER");
  if (!hadConflict) return false;

  const text = brief.the_real_disagreement.trim().toLowerCase();
  if (text.length === 0) return true;
  return CONSENSUS_TELLS.some((tell) => text.includes(tell));
}

const SYNTHESIS_INSTRUCTION = `Perform your SYNTHESIS duties.

THE REAL QUESTION AT STAKE:
<real_question>

WHAT EACH DEPARTMENT SAID, VERBATIM:
<positions>

CONFLICT DETECTION FOUND:
<conflicts>

<negotiation><red_team>Your synthesis is judged on one criterion: could the founder act tomorrow
morning? Produce all six components.

Never average opposing views into a middle position that nobody argued for.
Quote the disagreement closely enough that the founder can judge it themselves.
Do not bury dissent in a footnote.

Call record_decision_brief.`;

function renderPositions(positions: Partial<Record<AgentId, AgentPosition>>): string {
  return Object.entries(positions)
    .filter(([, p]) => p !== undefined)
    .map(([agent, p]) => {
      const position = p as AgentPosition;
      const blocker = position.hard_blocker
        ? `\n   HARD BLOCKER: ${position.hard_blocker}`
        : "";
      return `${agent} (stance: ${position.stance}, confidence ${position.confidence}/5):\n   Position: ${position.position}\n   Reasoning: ${position.reasoning}\n   Cost to their own department: ${position.cost_to_my_dept}\n   Evidence they want: ${
        position.evidence_needed.join("; ") || "none named"
      }${blocker}`;
    })
    .join("\n\n");
}

export async function runSynthesis(args: {
  founder: FounderContext;
  rawRequest: string;
  realQuestion: string;
  positions: Partial<Record<AgentId, AgentPosition>>;
  conflicts: Conflict[];
  negotiation: NegotiationRound[];
  devilsAdvocate: DevilsAdvocateVerdict | null;
  unresolved: boolean;
  call: AgentCaller;
}): Promise<{ brief: DecisionBrief; model: string; usage: TokenUsage }> {
  const negotiationBlock =
    args.negotiation.length === 0
      ? ""
      : `THE NEGOTIATION (${
          args.unresolved ? "ended UNRESOLVED" : "reached resolution"
        }):\n` +
        args.negotiation
          .map(
            (r) =>
              `Round ${r.round}:\n` +
              r.turns
                .map(
                  (t) =>
                    `  ${t.agent}: ${t.precise_disagreement}\n    Would change their mind if: ${t.what_would_change_my_mind}\n    Proposal: ${t.proposal}\n    Considers it resolved: ${t.resolved}`
                )
                .join("\n")
          )
          .join("\n\n") +
        "\n\n";

  const redTeamBlock =
    args.devilsAdvocate === null
      ? ""
      : `THE RED TEAM SAID:\n  Load-bearing assumption: ${args.devilsAdvocate.load_bearing_assumption}\n  How it could be false: ${args.devilsAdvocate.how_it_could_be_false}\n  Cheapest test: ${args.devilsAdvocate.cheapest_test}\n  Failure post-mortem: ${args.devilsAdvocate.failure_post_mortem}\n  Not in the room: ${args.devilsAdvocate.who_is_not_in_the_room}\n  Plan judged sound: ${args.devilsAdvocate.plan_is_sound}\n\n`;

  const conflictBlock =
    args.conflicts.length === 0
      ? "No pairs to compare."
      : args.conflicts.map((c) => `${c.a} vs ${c.b}: ${c.kind} — ${c.reason}`).join("\n");

  const model = AGENT_DEFS.chief_of_staff.model;
  const system = composeAgentSystem({
    agent: "chief_of_staff",
    founder: args.founder,
    rawRequest: args.rawRequest
  });
  const baseMessage = SYNTHESIS_INSTRUCTION.replace("<real_question>", args.realQuestion.trim())
    .replace("<positions>", renderPositions(args.positions))
    .replace("<conflicts>", conflictBlock)
    .replace("<negotiation>", negotiationBlock)
    .replace("<red_team>", redTeamBlock);
  const ask = (message: string) =>
    args.call({
      agent: "chief_of_staff",
      model,
      system,
      userMessage: message,
      tool: BRIEF_TOOL,
      toolName: BRIEF_TOOL.name
    });

  // Phase 5 is the last and most expensive call in the run, so a rejected brief
  // used to throw away everything already paid for. Observed in production on a
  // real run: the model omitted what_we_dont_know and an otherwise complete brief
  // was discarded. Same failure mode as the positions in phase 2 — a required
  // field simply missing — so it gets the same remedy: one more attempt with the
  // reason quoted back. Both calls are billed, so both are counted.
  const first = await ask(baseMessage);
  let input = first.input;
  let usage = first.usage;
  let parsed = parseBriefToolInput(input);
  let dissentBuried = "error" in parsed ? false : briefOmitsDissent(parsed, args.conflicts);

  if ("error" in parsed || dissentBuried) {
    const reason = "error" in parsed
      ? parsed.error
      : "the_real_disagreement does not report the conflict that actually existed";
    const retry = await ask(
      `${baseMessage}\n\nYour previous submit_brief call was rejected: ${reason}. ` +
        `Every required field must be present and non-empty. Call the tool again with all of them.`
    );
    input = retry.input;
    usage = {
      input: first.usage.input + retry.usage.input,
      output: first.usage.output + retry.usage.output,
      cache_read: first.usage.cache_read + retry.usage.cache_read
    };
    parsed = parseBriefToolInput(input);
    dissentBuried = "error" in parsed ? false : briefOmitsDissent(parsed, args.conflicts);
  }

  if ("error" in parsed) {
    throw new Error(`unusable decision brief from chief_of_staff: ${parsed.error}`);
  }
  if (dissentBuried) {
    throw new Error(
      "decision brief buried dissent: a CONFLICT or BLOCKER existed but the_real_disagreement does not report it"
    );
  }

  // The negotiation outcome is authoritative — the synthesiser can escalate to
  // unresolved but cannot downgrade an unresolved trade-off into a resolved one.
  return {
    brief: { ...parsed, unresolved: parsed.unresolved || args.unresolved },
    model,
    usage
  };
}
