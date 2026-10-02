import { BRIEF_TOOL, SYNTHESIS_INSTRUCTION } from "../company/synthesis";

/**
 * CP-048, from Dominich's build 6 report (1 Oct): "The real disagreement" rendered as a
 * ~15-line paragraph in both the Plan room and the Team Build room. Not a CP-030 regression —
 * CP-030 shortened the pairwise conflict list and left this field alone on purpose. The UI must
 * show it verbatim and never behind a disclosure (SSE contract rule 3), so the only place a
 * length can be set is where the model writes it. Nothing bounded it: the field asked for the
 * opposition "quoted closely enough that the founder can judge", and with three or four seats
 * quoting each side closely is a paragraph.
 */
const field = (BRIEF_TOOL.input_schema.properties as unknown as Record<string, { description: string }>)
  .the_real_disagreement.description;

describe("the_real_disagreement is bounded where it is written", () => {
  it("the tool field asks for at most two sentences and about 50 words", () => {
    expect(field).toMatch(/at most two sentences/i);
    expect(field).toMatch(/50 words/);
  });

  it("the synthesis instruction says the same, so the two cannot disagree", () => {
    expect(SYNTHESIS_INSTRUCTION).toMatch(/at most two sentences/i);
    expect(SYNTHESIS_INSTRUCTION).toMatch(/50 words/);
  });

  it("keeps the rules the length must not cost: no averaging, name who is on each side", () => {
    expect(field).toMatch(/Never average opposing views/);
    expect(field).toMatch(/who is on each side/i);
    expect(SYNTHESIS_INSTRUCTION).toMatch(/Never average opposing views/);
  });

  it("drops the instruction that produced the paragraph", () => {
    expect(field).not.toMatch(/quoted closely enough/);
    expect(SYNTHESIS_INSTRUCTION).not.toMatch(/Quote the disagreement closely enough/);
  });
});
