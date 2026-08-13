import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller, POSITION_EFFORT } from "./router";
import {
  AgentId,
  AgentPosition,
  Conflict,
  FounderContext,
  NegotiationRound,
  NegotiationTurn,
  TokenUsage
} from "./types";

/**
 * Hard cap, not a request parameter (spec §2.2 Phase 4). Unbounded debate is
 * where cost explodes and where agents drift toward false consensus.
 */
export const MAX_NEGOTIATION_ROUNDS = 2;

export const NEGOTIATION_TOOL = {
  name: "submit_negotiation_turn",
  description:
    "Respond to the opposing department's position. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      precise_disagreement: {
        type: "string",
        description:
          "The exact point of disagreement. Do not drift to a different objection than the one on the table."
      },
      what_would_change_my_mind: {
        type: "string",
        description:
          "A falsifiable condition. Name the observation that would move you, not a sentiment. 'More data' is not a falsification condition; 'month-2 retention below 35%' is."
      },
      proposal: {
        type: "string",
        description:
          "An option that preserves both sides' hard blockers. If none exists, say plainly that this is an unresolvable trade-off the founder must choose."
      },
      resolved: {
        type: "boolean",
        description:
          "True only if you genuinely believe the trade-off is now resolvable. Conceding to keep the peace is forbidden."
      }
    },
    required: [
      "precise_disagreement",
      "what_would_change_my_mind",
      "proposal",
      "resolved"
    ],
    additionalProperties: false
  }
};

export function parseNegotiationToolInput(
  input: unknown
): Omit<NegotiationTurn, "agent"> | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "negotiation tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;

  const disagreement =
    typeof raw.precise_disagreement === "string" ? raw.precise_disagreement.trim() : "";
  if (disagreement.length === 0) {
    return { error: "precise_disagreement is required" };
  }

  const falsifier =
    typeof raw.what_would_change_my_mind === "string"
      ? raw.what_would_change_my_mind.trim()
      : "";
  if (falsifier.length === 0) {
    // Without a falsifier there is no way for evidence to settle this, which
    // makes the turn noise rather than negotiation.
    return { error: "what_would_change_my_mind is required" };
  }

  return {
    precise_disagreement: disagreement,
    what_would_change_my_mind: falsifier,
    proposal: typeof raw.proposal === "string" ? raw.proposal.trim() : "",
    // Anything that is not literally true counts as unresolved.
    resolved: raw.resolved === true
  };
}

export function conflictingAgents(conflicts: Conflict[]): AgentId[] {
  const out: AgentId[] = [];
  for (const c of conflicts) {
    if (c.kind !== "CONFLICT" && c.kind !== "BLOCKER") continue;
    for (const agent of [c.a, c.b]) {
      if (!out.includes(agent)) out.push(agent);
    }
  }
  return out;
}

/**
 * Resolution requires unanimity in the final round. One side conceding while the
 * other holds is not resolution — it is the capitulation the spec forbids.
 */
export function isResolved(rounds: NegotiationRound[]): boolean {
  const last = rounds[rounds.length - 1];
  if (!last || last.turns.length === 0) return false;
  return last.turns.every((t) => t.resolved);
}

function renderOpposing(
  self: AgentId,
  participants: AgentId[],
  positions: Partial<Record<AgentId, AgentPosition>>
): string {
  return participants
    .filter((a) => a !== self)
    .map((a) => {
      const p = positions[a];
      if (!p) return `${a}: (no position on record)`;
      const blocker = p.hard_blocker
        ? `\n   HARD BLOCKER: ${p.hard_blocker}`
        : "\n   No hard blocker.";
      return `${a} (stance: ${p.stance}, confidence ${p.confidence}/5):\n   ${p.position}\n   Reasoning: ${p.reasoning}${blocker}`;
    })
    .join("\n\n");
}

const NEGOTIATION_INSTRUCTION = `You are now in a bounded negotiation. Round <round> of ${MAX_NEGOTIATION_ROUNDS}.

THE REAL QUESTION AT STAKE:
<real_question>

THE OPPOSING POSITION:
<opposing>

<prior>Do all four of these:
1. State the precise point of disagreement. Do not drift to a different objection.
2. State what would change your mind, as a falsifiable condition.
3. Propose an option that preserves both hard blockers.
4. If no such option exists, say plainly that this is an unresolvable trade-off
   and the founder must choose.

Conceding to keep the peace is forbidden. If you concede, the concession must
carry a stated reason. Returning "unresolved" is a valid and useful outcome.

Call submit_negotiation_turn.`;

export async function runNegotiation(args: {
  founder: FounderContext;
  rawRequest: string;
  realQuestion: string;
  positions: Partial<Record<AgentId, AgentPosition>>;
  conflicts: Conflict[];
  call: AgentCaller;
}): Promise<{
  rounds: NegotiationRound[];
  unresolved: boolean;
  usages: Array<{ agent: AgentId; model: string; usage: TokenUsage }>;
}> {
  const participants = conflictingAgents(args.conflicts);
  // Spec §2.2 Phase 3: never debate when there is nothing to debate.
  if (participants.length < 2) {
    return { rounds: [], unresolved: false, usages: [] };
  }

  const rounds: NegotiationRound[] = [];
  const usages: Array<{ agent: AgentId; model: string; usage: TokenUsage }> = [];

  for (let round = 1; round <= MAX_NEGOTIATION_ROUNDS; round++) {
    const prior =
      rounds.length === 0
        ? ""
        : `WHAT WAS SAID IN THE PREVIOUS ROUND:\n${rounds[rounds.length - 1].turns
            .map(
              (t) =>
                `${t.agent}: ${t.precise_disagreement} — would change their mind if: ${t.what_would_change_my_mind}. Proposal: ${t.proposal}`
            )
            .join("\n")}\n\n`;

    const settled = await Promise.allSettled(
      participants.map(async (agent): Promise<NegotiationTurn> => {
        const model = AGENT_DEFS[agent].model;
        const { input, usage } = await args.call({
          agent,
          model,
          system: composeAgentSystem({
            agent,
            founder: args.founder,
            rawRequest: args.rawRequest,
            // This phase has no retry path, and it cannot read the positions
            // phase's entry because it sends a different tool. Every copy would
            // be a write nobody reads — a flat 25% surcharge on the prefix.
            cache: false
          }),
          userMessage: NEGOTIATION_INSTRUCTION.replace("<round>", String(round))
            .replace("<real_question>", args.realQuestion.trim())
            .replace("<opposing>", renderOpposing(agent, participants, args.positions))
            .replace("<prior>", prior),
          tool: NEGOTIATION_TOOL,
          toolName: NEGOTIATION_TOOL.name,
          effort: POSITION_EFFORT
        });
        usages.push({ agent, model, usage });

        const parsed = parseNegotiationToolInput(input);
        if ("error" in parsed) {
          // An unparseable turn cannot count as resolution — otherwise a
          // malformed response could silently close a live disagreement.
          return {
            agent,
            precise_disagreement: `(unusable turn: ${parsed.error})`,
            what_would_change_my_mind: "",
            proposal: "",
            resolved: false
          };
        }
        return { agent, ...parsed };
      })
    );

    const turns: NegotiationTurn[] = settled.map((outcome, i) =>
      outcome.status === "fulfilled"
        ? outcome.value
        : {
            agent: participants[i],
            precise_disagreement: `(turn failed: ${String(outcome.reason)})`,
            what_would_change_my_mind: "",
            proposal: "",
            resolved: false
          }
    );

    rounds.push({ round: round as 1 | 2, turns });
    if (isResolved(rounds)) break;
  }

  return { rounds, unresolved: !isResolved(rounds), usages };
}
