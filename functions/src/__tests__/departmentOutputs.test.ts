import {
  DEPARTMENT_FOUNDATIONS,
  DEPARTMENT_OUTPUTS,
  departmentOutputBlock,
  coerceKindForDepartment,
} from "../departments";
import {
  DELIVERABLE_KINDS,
  buildRunTaskPrompt,
  coerceDeliverable,
  RunTaskArgs,
} from "../runTaskCore";
import { ONE_SHOT_OPS } from "../local/oneShotOps";

/**
 * The department output contract.
 *
 * Before this, nothing constrained which department produced what: the generator said "Pick
 * whichever `kind` best fits what you produced from this exact list", and a department
 * contributed expertise (`DEPARTMENT_FOUNDATIONS`) and never an output shape. So Finance could
 * hand back `screens`, and nothing anywhere would notice.
 *
 * Each department now declares PRIMARY outputs, which steer the prompt, and ALLOWED ones,
 * reachable when the ask calls for them. Everything else is closed.
 */
describe("DEPARTMENT_OUTPUTS", () => {
  test("every department with expertise also declares outputs", () => {
    const missing = Object.keys(DEPARTMENT_FOUNDATIONS).filter((k) => !DEPARTMENT_OUTPUTS[k]);
    expect(missing).toEqual([]);
  });

  test("declares outputs for no department that does not exist", () => {
    const extra = Object.keys(DEPARTMENT_OUTPUTS).filter((k) => !DEPARTMENT_FOUNDATIONS[k]);
    expect(extra).toEqual([]);
  });

  test("every named kind is a real deliverable kind", () => {
    const bad: string[] = [];
    for (const [dept, o] of Object.entries(DEPARTMENT_OUTPUTS)) {
      for (const k of [...o.primary, ...o.allowed]) {
        if (!DELIVERABLE_KINDS.has(k)) bad.push(`${dept}: ${k}`);
      }
    }
    expect(bad).toEqual([]);
  });

  test("every department declares at least one primary output", () => {
    const empty = Object.entries(DEPARTMENT_OUTPUTS)
      .filter(([, o]) => o.primary.length === 0)
      .map(([k]) => k);
    expect(empty).toEqual([]);
  });

  /**
   * `text` and `other` are the untyped fallbacks. `other` exists so an unknown string fails open
   * on decode rather than throwing — it is a decode guard, not an output — and a department that
   * could choose either would be choosing to hand the founder prose with no shape at all.
   */
  test("no department can produce text or other", () => {
    const reachable: string[] = [];
    for (const [dept, o] of Object.entries(DEPARTMENT_OUTPUTS)) {
      for (const k of [...o.primary, ...o.allowed]) {
        if (k === "text" || k === "other") reachable.push(`${dept}: ${k}`);
      }
    }
    expect(reachable).toEqual([]);
  });

  test("a kind is never both primary and allowed for the same department", () => {
    const dupes: string[] = [];
    for (const [dept, o] of Object.entries(DEPARTMENT_OUTPUTS)) {
      for (const k of o.primary) if (o.allowed.includes(k)) dupes.push(`${dept}: ${k}`);
    }
    expect(dupes).toEqual([]);
  });

  /** The two the design turns on: Finance models money, Legal writes clauses. */
  test("finance leads with a model and legal with a clause document", () => {
    expect(DEPARTMENT_OUTPUTS.fin.primary).toContain("sheet");
    expect(DEPARTMENT_OUTPUTS.legal.primary).toContain("legal");
  });

  test("no department may produce another department's signature kind", () => {
    expect(DEPARTMENT_OUTPUTS.fin.primary).not.toContain("screens");
    expect(DEPARTMENT_OUTPUTS.fin.allowed).not.toContain("screens");
    expect(DEPARTMENT_OUTPUTS.legal.primary).not.toContain("site");
    expect(DEPARTMENT_OUTPUTS.legal.allowed).not.toContain("site");
  });
});

describe("departmentOutputBlock", () => {
  test("names the department's primary kinds so the prompt can steer", () => {
    const block = departmentOutputBlock("fin");
    expect(block).toContain("sheet");
    expect(block).toContain("doc");
  });

  test("does not offer a kind the department cannot produce", () => {
    const block = departmentOutputBlock("fin");
    expect(block).not.toContain("screens");
  });

  /** A dept-less (legacy) task must keep working, with no contract to render. */
  test("is empty for an unknown or absent department", () => {
    expect(departmentOutputBlock(undefined)).toBe("");
    expect(departmentOutputBlock("nonsense")).toBe("");
  });
});

/**
 * Steering the prompt is not enough on its own. `claude -p` cannot force a tool call, so the
 * local path asks for the schema in prose and parses the reply — which is exactly why every op
 * validates or coerces what it got rather than trusting it. The kind gets the same treatment.
 */
describe("coerceKindForDepartment", () => {
  test("passes a primary kind through untouched", () => {
    expect(coerceKindForDepartment("fin", "sheet")).toBe("sheet");
  });

  test("passes an allowed kind through untouched", () => {
    const allowed = DEPARTMENT_OUTPUTS.fin.allowed[0];
    expect(coerceKindForDepartment("fin", allowed)).toBe(allowed);
  });

  test("falls back to the department's first primary for a kind it cannot produce", () => {
    expect(coerceKindForDepartment("fin", "screens")).toBe(DEPARTMENT_OUTPUTS.fin.primary[0]);
  });

  test("rescues the untyped fallbacks, which no department may emit", () => {
    expect(coerceKindForDepartment("legal", "text")).toBe(DEPARTMENT_OUTPUTS.legal.primary[0]);
    expect(coerceKindForDepartment("legal", "other")).toBe(DEPARTMENT_OUTPUTS.legal.primary[0]);
  });

  /**
   * A task with no department has no contract to judge against, and inventing one would change
   * what legacy tasks produce. Whatever the model chose stands.
   */
  test("leaves a dept-less task's kind alone", () => {
    expect(coerceKindForDepartment(undefined, "screens")).toBe("screens");
    expect(coerceKindForDepartment(null, "text")).toBe("text");
  });

  test("leaves an unknown department's kind alone rather than inventing a contract", () => {
    expect(coerceKindForDepartment("nonsense", "screens")).toBe("screens");
  });

  /** An unknown kind string is still coerced — it would otherwise decode to `other`. */
  test("coerces a kind that is not a deliverable kind at all", () => {
    expect(coerceKindForDepartment("ops", "spreadsheet")).toBe(DEPARTMENT_OUTPUTS.ops.primary[0]);
  });
});

/**
 * The contract has to reach the prompt and the parse, or it is a table nobody consults.
 */
describe("the run prompt carries the contract", () => {
  const base = {
    taskTitle: "Work out what a month of inference costs",
    taskDetail: "",
    language: "en",
  } as unknown as RunTaskArgs;

  test("names the department's kinds instead of the whole list", () => {
    const p = buildRunTaskPrompt({ ...base, deptKey: "fin" });
    expect(p).toContain("This function produces sheet, doc.");
  });

  test("does not offer the full kind list once a department is known", () => {
    const p = buildRunTaskPrompt({ ...base, deptKey: "fin" });
    expect(p).not.toContain("screens");
  });

  /** A dept-less task keeps the behaviour it had: the whole list, no contract. */
  test("still offers every kind when the task has no department", () => {
    const p = buildRunTaskPrompt({ ...base, deptKey: undefined });
    expect(p).toContain("screens");
    expect(p).not.toContain("This function produces");
  });
});

/**
 * Steering the prompt is not enforcement. `claude -p` cannot be forced to a tool call, so the
 * local path asks for the schema in prose and parses the reply; the API path can be forced to
 * the tool but not to a particular `kind` inside it. Either way an out-of-contract kind can
 * arrive, and the parse is the last place to catch it before the founder's library.
 */
describe("the parse holds the contract", () => {
  const raw = { kind: "screens", title: "Onboarding", body: "# Screens" };

  test("rewrites a kind the department cannot produce", () => {
    expect(coerceDeliverable(raw, "T", "fin")?.kind).toBe("sheet");
  });

  test("leaves a kind the department may produce", () => {
    expect(coerceDeliverable({ ...raw, kind: "legal" }, "T", "fin")?.kind).toBe("legal");
  });

  test("leaves a dept-less task's kind alone", () => {
    expect(coerceDeliverable(raw, "T", undefined)?.kind).toBe("screens");
  });

  /** A garbage kind becomes the department's usual output, not a generic doc. */
  test("gives a department its first primary for an unreadable kind", () => {
    expect(coerceDeliverable({ ...raw, kind: "spreadsheet" }, "T", "ops")?.kind).toBe("checklist");
  });

  /** Legacy: with no department there is no contract, so the old `doc` floor still applies. */
  test("still floors an unreadable kind to doc with no department", () => {
    expect(coerceDeliverable({ ...raw, kind: "spreadsheet" }, "T")?.kind).toBe("doc");
  });
});

/**
 * The third place. `handleRunTask` and the `runTask` entry in `ONE_SHOT_OPS` narrow the same
 * wire body separately, and the local path is the DEFAULT for a founder running on their own
 * Claude plan — the transport nobody curls. Miss it there and the contract holds only for the
 * traffic that never reaches most founders.
 */
describe("the local transport holds the contract too", () => {
  const body = { task_title: "Work out what a month of inference costs", dept_key: "fin" };

  test("coerces an out-of-contract kind on the way back through the sidecar", () => {
    const d = ONE_SHOT_OPS.runTask.respond(
      body,
      { kind: "screens", title: "Onboarding", body: "# Screens" },
      { model: "m", nowISO: "t" }
    ) as { kind: string };
    expect(d.kind).toBe("sheet");
  });

  test("narrows dept_key the same way the prompt side does", () => {
    const p = ONE_SHOT_OPS.runTask.plan(body).prompt;
    expect(p).toContain("This function produces sheet, doc.");
    expect(p).not.toContain("screens");
  });
});
