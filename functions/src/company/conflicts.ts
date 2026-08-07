import {
  AgentId,
  AgentPosition,
  Conflict,
  ConflictKind,
  DEPARTMENT_AGENTS,
  Stance
} from "./types";

/** True for any stance that means "go ahead", at any intensity. */
function isProceed(stance: Stance): boolean {
  return stance === "proceed" || stance === "proceed_with_conditions";
}

function opposed(a: Stance, b: Stance): boolean {
  return isProceed(a) !== isProceed(b);
}

/**
 * Classifies one pair of positions. Pure and deterministic — spec §2.2 Phase 3
 * requires this phase to make no LLM call, so the comparison runs on the
 * `stance` enum and `hard_blocker` presence rather than on prose.
 *
 * Priority order matters: a blocker is a stronger signal than opposed stances,
 * because it tells the founder someone considers the outcome unacceptable rather
 * than merely unwise.
 */
export function classifyPair(
  a: AgentId,
  pa: AgentPosition,
  b: AgentId,
  pb: AgentPosition
): Conflict {
  const mk = (kind: ConflictKind, reason: string): Conflict => ({ a, b, kind, reason });

  // A blocker only bites when the other side actually wants to proceed. Two
  // agents refusing for different reasons have nothing to negotiate.
  const aBlocks = pa.hard_blocker !== null && isProceed(pb.stance);
  const bBlocks = pb.hard_blocker !== null && isProceed(pa.stance);
  if (aBlocks || bBlocks) {
    const blocker = aBlocks ? a : b;
    const blockerText = (aBlocks ? pa.hard_blocker : pb.hard_blocker) ?? "";
    return mk("BLOCKER", `${blocker} raised a hard blocker: ${blockerText}`);
  }

  if (opposed(pa.stance, pb.stance)) {
    return mk("CONFLICT", `Directly opposed: ${a} is ${pa.stance}, ${b} is ${pb.stance}.`);
  }

  if (pa.stance !== pb.stance) {
    return mk(
      "TENSION",
      `Same direction, different priority: ${a} is ${pa.stance}, ${b} is ${pb.stance}.`
    );
  }

  // Two conditional yeses are NOT an agreement.
  //
  // `proceed_with_conditions` means "yes, but" — and the "but" is where the disagreement lives.
  // This phase is deliberately LLM-free (spec §2.2 Phase 3), so it compares the stance enum and
  // cannot read the conditions; treating two identical conditional stances as agreement asserts
  // something it has no way to check.
  //
  // Observed Aug 7. Four departments each answered `proceed_with_conditions` on "should we charge
  // for the beta", so all six pairs classified ALIGNED and the client flipped to its
  // "WHERE THEY AGREE" variant — over a synthesis whose own first sentence read: "the room split
  // cleanly 2-2 on sequencing, and the conflict detector calling this ALIGNED is wrong — it read
  // stance labels, not content." The model was right and this function was wrong.
  //
  // TENSION rather than a new kind: it already means "same direction, unsettled", which is exactly
  // what two sets of unread conditions are, and it needs no client change. ALIGNED is now reserved
  // for stances that carry no conditions — an unqualified yes twice, or an unqualified no twice —
  // where sameness really is agreement.
  if (pa.stance === "proceed_with_conditions" && pb.stance === "proceed_with_conditions") {
    return mk(
      "TENSION",
      `${a} and ${b} both proceed only with conditions — this phase compares stances, not the ` +
        `conditions themselves, so treat it as unsettled rather than agreed.`
    );
  }

  return mk("ALIGNED", `Both ${a} and ${b} are ${pa.stance} with no hard blocker in play.`);
}

/**
 * Classifies every unique pair of department positions. Iterates
 * DEPARTMENT_AGENTS rather than Object.keys(positions) so the output order is
 * stable regardless of how the positions object was built, and so a
 * non-department agent that somehow carries a position is ignored.
 */
export function detectConflicts(
  positions: Partial<Record<AgentId, AgentPosition>>
): Conflict[] {
  const present = DEPARTMENT_AGENTS.filter((id) => positions[id] !== undefined);
  const out: Conflict[] = [];
  for (let i = 0; i < present.length; i++) {
    for (let j = i + 1; j < present.length; j++) {
      const a = present[i];
      const b = present[j];
      out.push(classifyPair(a, positions[a]!, b, positions[b]!));
    }
  }
  return out;
}

/** Spec §2.2: if everything is ALIGNED, skip Phase 4 entirely. */
export function needsNegotiation(conflicts: Conflict[]): boolean {
  return conflicts.some((c) => c.kind === "CONFLICT" || c.kind === "BLOCKER");
}
