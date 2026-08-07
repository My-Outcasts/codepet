import { classifyPair, detectConflicts, needsNegotiation } from "../company/conflicts";
import { AgentPosition, Stance } from "../company/types";

function pos(stance: Stance, hardBlocker: string | null = null): AgentPosition {
  return {
    stance,
    position: "p",
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 3,
    cost_to_my_dept: "c",
    hard_blocker: hardBlocker
  };
}

describe("classifyPair", () => {
  test("opposed stances are a CONFLICT", () => {
    const c = classifyPair("product", pos("proceed"), "finance", pos("do_not_proceed"));
    expect(c.kind).toBe("CONFLICT");
    expect(c.reason).toMatch(/opposed/i);
  });

  test("proceed_with_conditions against do_not_proceed is still a CONFLICT", () => {
    const c = classifyPair(
      "product",
      pos("proceed_with_conditions"),
      "finance",
      pos("do_not_proceed")
    );
    expect(c.kind).toBe("CONFLICT");
  });

  test("a hard_blocker against a proceed stance is a BLOCKER", () => {
    const c = classifyPair(
      "product",
      pos("proceed"),
      "finance",
      pos("do_not_proceed", "CAC exceeds LTV; scaling loses money faster.")
    );
    expect(c.kind).toBe("BLOCKER");
    expect(c.reason).toContain("finance");
    expect(c.reason).toContain("CAC exceeds LTV");
  });

  test("BLOCKER outranks CONFLICT regardless of argument order", () => {
    const blocker = pos("do_not_proceed", "runway falls below 2 months");
    expect(classifyPair("product", pos("proceed"), "finance", blocker).kind).toBe("BLOCKER");
    expect(classifyPair("finance", blocker, "product", pos("proceed")).kind).toBe("BLOCKER");
  });

  test("same direction with different intensity is a TENSION", () => {
    const c = classifyPair("product", pos("proceed"), "finance", pos("proceed_with_conditions"));
    expect(c.kind).toBe("TENSION");
  });

  test("identical stances with no blockers are ALIGNED", () => {
    expect(classifyPair("product", pos("proceed"), "finance", pos("proceed")).kind).toBe("ALIGNED");
    expect(
      classifyPair("product", pos("do_not_proceed"), "finance", pos("do_not_proceed")).kind
    ).toBe("ALIGNED");
  });

  test("a hard_blocker on both sides of a shared stance stays ALIGNED", () => {
    // Both refuse for their own reasons — there is nothing to negotiate.
    const c = classifyPair(
      "product",
      pos("do_not_proceed", "displaces the only bet worth testing"),
      "finance",
      pos("do_not_proceed", "runway cannot absorb it")
    );
    expect(c.kind).toBe("ALIGNED");
  });

  test("a blocker attached to a proceed stance still bites the other proceeder", () => {
    // An agent can want to proceed AND hold a non-negotiable about how.
    const c = classifyPair(
      "product",
      pos("proceed", "not without instrumentation in place"),
      "finance",
      pos("proceed")
    );
    expect(c.kind).toBe("BLOCKER");
  });
});

describe("detectConflicts", () => {
  test("returns one entry per unique department pair", () => {
    const conflicts = detectConflicts({
      product: pos("proceed"),
      finance: pos("do_not_proceed")
    });
    expect(conflicts).toHaveLength(1);
    expect(conflicts[0].a).toBe("product");
    expect(conflicts[0].b).toBe("finance");
  });

  test("returns empty when fewer than two positions exist", () => {
    expect(detectConflicts({ product: pos("proceed") })).toEqual([]);
    expect(detectConflicts({})).toEqual([]);
  });

  test("ignores non-department agents", () => {
    const conflicts = detectConflicts({
      product: pos("proceed"),
      finance: pos("proceed"),
      chief_of_staff: pos("proceed")
    });
    expect(conflicts).toHaveLength(1);
    expect(
      conflicts.every((c) => c.a !== "chief_of_staff" && c.b !== "chief_of_staff")
    ).toBe(true);
  });

  test("is deterministic — pair order does not depend on key insertion order", () => {
    const a = detectConflicts({ finance: pos("proceed"), product: pos("do_not_proceed") });
    const b = detectConflicts({ product: pos("do_not_proceed"), finance: pos("proceed") });
    expect(a).toEqual(b);
  });

  test("returns synchronously — no LLM call, no promise", () => {
    // Spec §2.2 Phase 3 requires this phase to be pure code.
    const result = detectConflicts({ product: pos("proceed"), finance: pos("proceed") });
    expect(Array.isArray(result)).toBe(true);
  });
});

describe("needsNegotiation", () => {
  test("true when any pair is CONFLICT or BLOCKER", () => {
    expect(needsNegotiation([{ a: "product", b: "finance", kind: "CONFLICT", reason: "" }])).toBe(
      true
    );
    expect(needsNegotiation([{ a: "product", b: "finance", kind: "BLOCKER", reason: "" }])).toBe(
      true
    );
  });

  test("false when everything is ALIGNED or merely TENSION", () => {
    // Spec §2.2 Phase 3: never debate when there is nothing to debate.
    expect(needsNegotiation([{ a: "product", b: "finance", kind: "ALIGNED", reason: "" }])).toBe(
      false
    );
    expect(needsNegotiation([{ a: "product", b: "finance", kind: "TENSION", reason: "" }])).toBe(
      false
    );
    expect(needsNegotiation([])).toBe(false);
  });

  // Aug 7: four departments each answered `proceed_with_conditions` on "should we charge for the
  // beta", so every pair classified ALIGNED and the client flipped to its "WHERE THEY AGREE"
  // variant — over a synthesis that opened "the room split cleanly 2-2 on sequencing, and the
  // conflict detector calling this ALIGNED is wrong". The model was right.
  it("does not call two conditional yeses an agreement", () => {
    const c = classifyPair("product", pos("proceed_with_conditions"),
                           "finance", pos("proceed_with_conditions"));
    expect(c.kind).toBe("TENSION");
    expect(c.reason).toContain("conditions");
  });

  it("still calls two UNqualified yeses an agreement", () => {
    expect(classifyPair("product", pos("proceed"),
                        "finance", pos("proceed")).kind).toBe("ALIGNED");
  });

  it("still calls two refusals an agreement", () => {
    expect(classifyPair("product", pos("do_not_proceed"),
                        "finance", pos("do_not_proceed")).kind).toBe("ALIGNED");
  });

  // A blocker outranks the conditional rule — it says someone finds the outcome unacceptable,
  // which is a stronger signal than "we both attached conditions".
  it("a hard blocker still wins over two conditional yeses", () => {
    expect(classifyPair("sales", pos("proceed_with_conditions", "no public price list"),
                        "finance", pos("proceed_with_conditions")).kind).toBe("BLOCKER");
  });

});
