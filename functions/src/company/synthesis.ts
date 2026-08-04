import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller, BRIEF_MAX_TOKENS, PATCH_MAX_TOKENS } from "./router";
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
    // Field ORDER is load-bearing, not cosmetic. Measured on the Vietnamese
    // path: the model emits properties roughly in schema order and drops the
    // last ones once the brief runs long, so what_we_dont_know and next_action
    // — short fields the parser hard-requires — were the casualties while
    // paragraphs of prose came through fine. The short required fields now come
    // first and the long prose sits behind them; only confidence_reason and
    // unresolved, the two the parser tolerates missing, are last.
    properties: {
      recommendation: {
        type: "string",
        description:
          "One paragraph. Judged on one criterion: could the founder act tomorrow morning?"
      },
      confidence: { type: "integer", minimum: 1, maximum: 5 },
      next_action: {
        type: "object",
        properties: {
          action: { type: "string", description: "Small enough to start today." },
          owner: { type: "string" }
        },
        required: ["action", "owner"],
        additionalProperties: false
      },
      kill_criteria: {
        type: "array",
        items: { type: "string" },
        description:
          "Observable events that mean 'we were wrong, stop'. At least one. Always an array, even when there is only one criterion."
      },
      what_we_dont_know: {
        type: "string",
        description: "The gap that most threatens this recommendation."
      },
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
      confidence_reason: { type: "string", description: "Why that confidence and not higher." },
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

/**
 * Who owns the next action when the model does not say. The founder is the only
 * party in this deployment who can act — the departments advise.
 */
export const DEFAULT_ACTION_OWNER = "founder";

/**
 * How many times to ask for missing brief fields before giving up. Two: the
 * first patch fixes most gaps, a second catches the rest, and a third has never
 * been observed to help.
 */
export const MAX_PATCH_ATTEMPTS = 2;

function clampConfidence(value: unknown): Confidence {
  const n = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 3;
  return Math.min(5, Math.max(1, n)) as Confidence;
}

/**
 * Which required fields are missing or empty, by name. The parser reports only
 * the first problem it hits, which is enough for a log line but not enough to
 * tell the model what to fix — measured on the Vietnamese path, a retry that
 * says "every required field must be present" fails about as often as the first
 * attempt, while naming the specific fields gives it something to act on.
 */
export function missingBriefFields(input: unknown): string[] {
  if (typeof input !== "object" || input === null) return Object.keys(BRIEF_PROPERTIES);
  const raw = input as Record<string, unknown>;
  const missing: string[] = [];

  for (const key of ["recommendation", "tradeoff_founder_must_own", "what_we_dont_know"]) {
    const v = raw[key];
    if (typeof v !== "string" || v.trim().length === 0) missing.push(key);
  }

  const kc = typeof raw.kill_criteria === "string" ? [raw.kill_criteria] : raw.kill_criteria;
  const usableKc =
    Array.isArray(kc) && kc.some((k) => typeof k === "string" && k.trim().length > 0);
  if (!usableKc) missing.push("kill_criteria");

  // Mirrors the parser: a bare string is usable and a missing owner is filled
  // in, so only an absent or empty ACTION counts as a hole worth another call.
  const na = raw.next_action;
  const actionText =
    typeof na === "string"
      ? na
      : typeof na === "object" && na !== null
        ? (na as Record<string, unknown>).action
        : undefined;
  if (typeof actionText !== "string" || actionText.trim().length === 0) {
    missing.push("next_action");
  }

  return missing;
}

/** Property schemas for the brief, reused when asking for a subset of them. */
const BRIEF_PROPERTIES = BRIEF_TOOL.input_schema.properties as Record<string, unknown>;

/**
 * A tool that asks for ONLY the fields the brief left out.
 *
 * Regenerating the whole brief did not work: measured on the Vietnamese path, a
 * full retry dropped a required field about as often as the first attempt, since
 * the failure mode is the model running long and leaving fields off — asking it
 * to write the same long thing again reproduces the same conditions. A patch
 * call has a few hundred tokens of output to produce, and the good prose from
 * the first attempt is kept rather than re-rolled.
 */
export function briefPatchTool(missing: string[]): {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
} {
  const properties: Record<string, unknown> = {};
  for (const key of missing) {
    if (BRIEF_PROPERTIES[key]) properties[key] = BRIEF_PROPERTIES[key];
  }
  return {
    name: "complete_brief",
    description:
      "Supply ONLY the fields listed here. They were left out of the brief you just " +
      "submitted. Do not restate any other part of the brief.",
    input_schema: {
      type: "object" as const,
      properties,
      required: Object.keys(properties),
      additionalProperties: false
    }
  };
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

  // next_action comes back three ways in practice: the declared object, a bare
  // string holding just the action, or an object with the action but no owner.
  // The last two used to sink the run. Nobody in this deployment can carry out a
  // next action except the founder — product and finance advise, chief_of_staff
  // synthesises — so an absent owner is filled in rather than treated as a gap.
  // An absent ACTION is still fatal: that is the content, and inventing it would
  // put words in the room's mouth.
  const rawAction = typeof raw.next_action === "string"
    ? { action: raw.next_action, owner: DEFAULT_ACTION_OWNER }
    : raw.next_action;
  if (typeof rawAction !== "object" || rawAction === null) {
    return { error: "next_action is required" };
  }
  const actionText = (rawAction as Record<string, unknown>).action;
  const rawOwner = (rawAction as Record<string, unknown>).owner;
  if (typeof actionText !== "string" || actionText.trim().length === 0) {
    return { error: "next_action.action is required" };
  }
  const owner =
    typeof rawOwner === "string" && rawOwner.trim().length > 0
      ? rawOwner
      : DEFAULT_ACTION_OWNER;

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
      toolName: BRIEF_TOOL.name,
      maxTokens: BRIEF_MAX_TOKENS
    });

  // Phase 5 is the last and most expensive call in the run, so a rejected brief
  // used to throw away everything already paid for. Observed in production on a
  // real run: the model omitted what_we_dont_know and an otherwise complete brief
  // was discarded. Same failure mode as the positions in phase 2 — a required
  // field simply missing — so it gets the same remedy: one more attempt with the
  // reason quoted back. Both calls are billed, so both are counted.
  const first = await ask(baseMessage);
  let input = first.input;
  let usage = { ...first.usage };
  let truncated = first.stopReason === "max_tokens";
  let parsed = parseBriefToolInput(input);
  let dissentBuried = "error" in parsed ? false : briefOmitsDissent(parsed, args.conflicts);

  const account = (u: TokenUsage, stopReason?: string | null) => {
    usage = {
      input: usage.input + u.input,
      output: usage.output + u.output,
      cache_read: usage.cache_read + u.cache_read
    };
    truncated = stopReason === "max_tokens";
  };

  // A gap gets patched, not re-rolled: two patch attempts at a few hundred output
  // tokens each, measured to carry the pass rate from roughly 6 in 10 to 7 or
  // better out of 8 on the Vietnamese path. Regenerating the whole brief instead
  // reproduced the failure as often as it fixed it — writing the long thing again
  // recreates the conditions that dropped the field.
  for (let attempt = 0; attempt < MAX_PATCH_ATTEMPTS && "error" in parsed; attempt++) {
    const missing = missingBriefFields(input);
    if (missing.length === 0) break;
    const patch = briefPatchTool(missing);
    const filled = await args.call({
      agent: "chief_of_staff",
      model,
      system,
      userMessage:
        `${baseMessage}\n\nYou already submitted a brief, but it left out these required ` +
        `fields: ${missing.join(", ")}. Call complete_brief with those fields only, in the ` +
        `same language as the brief. Everything else you wrote is kept.`,
      tool: patch,
      toolName: patch.name,
      maxTokens: PATCH_MAX_TOKENS
    });
    account(filled.usage, filled.stopReason);
    input = { ...(input as Record<string, unknown>), ...(filled.input as Record<string, unknown>) };
    parsed = parseBriefToolInput(input);
    dissentBuried = "error" in parsed ? false : briefOmitsDissent(parsed, args.conflicts);
  }

  if (dissentBuried) {
    // Not a gap — the brief had the field and used it to smooth the conflict
    // away. That is a content failure, so the whole brief is asked for again.
    const redo = await ask(
      `${baseMessage}\n\nYour previous submit_brief call was rejected: the conflict between ` +
        `the departments was real, but the_real_disagreement did not report it. Name both ` +
        `sides and what each of them actually said.`
    );
    account(redo.usage, redo.stopReason);
    input = redo.input;
    parsed = parseBriefToolInput(input);
    dissentBuried = "error" in parsed ? false : briefOmitsDissent(parsed, args.conflicts);
  }

  if ("error" in parsed) {
    // Truncation and schema-ignoring look identical at the parse site — both
    // present as a missing field. Saying which one it was is the difference
    // between raising the cap and rewriting a prompt.
    if (truncated) {
      throw new Error(
        `decision brief was cut off at the ${BRIEF_MAX_TOKENS}-token output cap ` +
          `(stop_reason=max_tokens), so "${parsed.error}" is a truncation, not the ` +
          `model ignoring the schema. Raise BRIEF_MAX_TOKENS.`
      );
    }
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
