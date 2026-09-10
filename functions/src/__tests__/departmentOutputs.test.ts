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
  deliverableTool,
  DELIVERABLE_TOOL,
  PAYLOAD_FIELD_KINDS,
  RunTaskArgs,
} from "../runTaskCore";
import { ONE_SHOT_OPS, schemaInstruction } from "../local/oneShotOps";
import { DEPT_KEYS } from "../generateRoadmapCore";
import { TASK_DEPTS } from "../companyChatCore";

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

  /**
   * An out-of-contract kind becomes `doc`, NOT the department's first primary.
   *
   * The payload was built for the kind the model chose, so `coercePayload` rejects it under the
   * new kind and it is dropped: all that survives is the markdown `body`. `doc` is the only kind
   * whose contract IS "prose in the body", and it is primary for all eight departments, so it
   * both satisfies the contract and describes what is actually being handed over. Relabelling
   * screens copy as `sheet` would put it in the Library as a "live model" and lie to the founder.
   */
  test("falls back to doc for a kind the department cannot produce", () => {
    expect(coerceKindForDepartment("fin", "screens")).toBe("doc");
    expect(coerceKindForDepartment("design", "sheet")).toBe("doc");
  });

  test("rescues the untyped fallbacks, which no department may emit", () => {
    expect(coerceKindForDepartment("legal", "text")).toBe("doc");
    expect(coerceKindForDepartment("legal", "other")).toBe("doc");
  });

  /** Every department has `doc` primary, so the fallback always satisfies the contract. */
  test("every department can produce the fallback it would be given", () => {
    for (const [k, o] of Object.entries(DEPARTMENT_OUTPUTS)) {
      expect([...o.primary, ...o.allowed]).toContain(coerceKindForDepartment(k, "screens"));
    }
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
    expect(coerceKindForDepartment("ops", "spreadsheet")).toBe("doc");
  });

  /** An absent kind is not evidence of anything. It must not become a signature kind. */
  test("gives doc for an empty kind rather than the department's speciality", () => {
    expect(coerceKindForDepartment("fin", "")).toBe("doc");
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
    expect(coerceDeliverable(raw, "T", "fin")?.kind).toBe("doc");
  });

  test("leaves a kind the department may produce", () => {
    expect(coerceDeliverable({ ...raw, kind: "legal" }, "T", "fin")?.kind).toBe("legal");
  });

  test("leaves a dept-less task's kind alone", () => {
    expect(coerceDeliverable(raw, "T", undefined)?.kind).toBe("screens");
  });

  /**
   * A garbage kind becomes `doc`, like any other out-of-contract kind. It was briefly the
   * department's speciality (`ops` → `checklist`), which read well until you notice the payload
   * has been dropped and the body is whatever the model wrote — prose, i.e. a doc.
   */
  test("gives doc for an unreadable kind rather than the department's speciality", () => {
    expect(coerceDeliverable({ ...raw, kind: "spreadsheet" }, "T", "ops")?.kind).toBe("doc");
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
    expect(d.kind).toBe("doc");
  });

  test("narrows dept_key the same way the prompt side does", () => {
    const p = ONE_SHOT_OPS.runTask.plan(body).prompt;
    expect(p).toContain("This function produces sheet, doc.");
    expect(p).not.toContain("screens");
  });
});

/**
 * What happens to the payload when the kind is rewritten under it.
 *
 * The model built `payload` for the kind IT chose. Once the contract renames the kind, that
 * payload no longer matches, `coercePayload` rejects it, and only the markdown body survives.
 * That is the right outcome — a screens payload under `kind: "sheet"` would break the sheet
 * viewer — but it means the kind must describe prose, which is why the fallback is `doc`.
 */
describe("a rewritten kind and its payload", () => {
  const screensPayload = {
    screens: [
      { name: "Connect", time: "1m", kick: "k", title: "t", sub: "s", art: "connect", cta: "c", note: "n" },
      { name: "Session", time: "1m", kick: "k", title: "t", sub: "s", art: "session", cta: "c", note: "n" },
      { name: "Recap", time: "1m", kick: "k", title: "t", sub: "s", art: "recap", cta: "c", note: "n" },
    ],
  };
  const raw = { kind: "screens", title: "Onboarding", body: "# Screens", payload: screensPayload };

  test("drops the payload it can no longer honour, and says doc rather than sheet", () => {
    const d = coerceDeliverable(raw, "T", "fin");
    expect(d?.kind).toBe("doc");
    expect(d?.payload).toBeUndefined();
    expect(d?.body).toBe("# Screens");
  });

  /** The in-contract path must be untouched: Design may produce screens, payload and all. */
  test("keeps the payload when the department may produce that kind", () => {
    const d = coerceDeliverable(raw, "T", "design");
    expect(d?.kind).toBe("screens");
    expect(d?.payload).toEqual(screensPayload);
  });

  test("a reply with no kind at all becomes doc, not the department's speciality", () => {
    expect(coerceDeliverable({ body: "b" }, "T", "fin")?.kind).toBe("doc");
  });
});

/**
 * The forced tool's schema is the other half of the steer, and on the local transport it is
 * appended AFTER the prompt: `renderPrompt` emits `prompt + schemaInstruction(schema)`. An
 * unnarrowed schema therefore spells out the `screens` and `site` fields immediately after the
 * prompt has said "Do not use any other kind" — measured at 2,813 prompt chars followed by
 * 14,768 with the schema. Narrowing the schema is what closes that.
 */
describe("the tool schema carries the contract", () => {
  const kindEnum = (k?: string) =>
    (deliverableTool(k).input_schema as any).properties.kind.enum;
  const payloadKeys = (k?: string) =>
    Object.keys((deliverableTool(k).input_schema as any).properties.payload.properties ?? {});

  test("offers a department only its own kinds", () => {
    expect(kindEnum("fin")).toEqual(["sheet", "doc", "legal"]);
  });

  test("drops the payload fields of kinds the department cannot produce", () => {
    expect(payloadKeys("fin")).not.toContain("screens");
    expect(payloadKeys("fin")).not.toContain("ctaPrimary");
  });

  test("keeps the payload fields of kinds it can", () => {
    expect(payloadKeys("design")).toContain("screens");
  });

  /** A dept-less task keeps the exact schema it had — no enum, every kind's fields. */
  test("leaves a dept-less task's schema alone", () => {
    expect(deliverableTool(undefined)).toBe(DELIVERABLE_TOOL);
    expect((DELIVERABLE_TOOL.input_schema as any).properties.kind.enum).toBeUndefined();
  });

  /** End to end on the transport that actually appends it. */
  test("the local transport no longer re-offers a closed kind", () => {
    const plan = ONE_SHOT_OPS.runTask.plan({ task_title: "Cost of inference", dept_key: "fin" });
    const sent = `${plan.prompt}\n\n${schemaInstruction(plan.schema)}`;
    expect(sent).not.toContain("screens");
    expect(sent).toContain("This function produces sheet, doc.");
  });
});

/**
 * The three hand-written eight-key lists that must agree.
 *
 * `DEPT_KEYS` gates what the roadmap may tag a task with, `TASK_DEPTS` what chat may, and
 * `DEPARTMENT_OUTPUTS` which of those have a contract. Add Product to the first two and forget
 * the third and every Product task runs with the full kind list and no contract, silently, with
 * this suite green. The spec's build order puts Product behind `bizplan`, so today they agree —
 * this is the tripwire for the day someone changes that.
 */
describe("the department key lists agree", () => {
  test("roadmap, chat and the contract name the same departments", () => {
    expect([...DEPT_KEYS].sort()).toEqual(Object.keys(DEPARTMENT_OUTPUTS).sort());
    expect([...TASK_DEPTS].sort()).toEqual(Object.keys(DEPARTMENT_OUTPUTS).sort());
  });
});

/**
 * The legacy prompt, pinned.
 *
 * Byte-parity for a dept-less task is the strongest backward-compatibility property in this
 * change and it was verified by hand against the previous commit. Without a test, a later edit
 * to `payloadBlock` or `orList` could shift every legacy prompt with the suite still green.
 */
describe("a dept-less task's prompt is unchanged", () => {
  const p = () =>
    buildRunTaskPrompt({
      companionId: "byte", language: "en", context: "Acme",
      taskTitle: "T", taskDetail: "", deptKey: undefined,
    } as unknown as RunTaskArgs);

  test("still offers every kind, and no contract sentence", () => {
    for (const k of DELIVERABLE_KINDS) expect(p()).toContain(k);
    expect(p()).not.toContain("This function produces");
  });

  test("still names all eight kinds in the payload guide preamble", () => {
    expect(p()).toContain("checklist, doc, plan, dms, calendar, sheet, site, or screens");
  });
});

/**
 * `PAYLOAD_FIELD_KINDS` is the map the schema narrowing consults, and it is hand-written beside
 * a 37-field schema. A field missing from it is silently dropped from EVERY department's schema
 * — the model would never be asked for it again — so the map has to be exhaustive by test, not
 * by care.
 */
describe("every payload field is classified", () => {
  const declared = Object.keys(
    (DELIVERABLE_TOOL.input_schema as any).properties.payload.properties
  );

  test("no schema field is left unclassified", () => {
    // A classified field survives for at least one department; an unclassified one survives for
    // none. Design + Finance + Operations + Legal between them cover every kind that has fields.
    const covered = new Set(
      ["design", "fin", "ops", "legal", "mkt", "sales", "eng", "support"].flatMap((d) =>
        Object.keys((deliverableTool(d).input_schema as any).properties.payload.properties)
      )
    );
    expect(declared.filter((f) => !covered.has(f))).toEqual([]);
  });

  test("the schema still declares the fields this map was written against", () => {
    expect(declared.length).toBe(37);
  });
});

/**
 * The map, cross-checked against the schema's own field descriptions.
 *
 * The coverage and count tests above catch a field left OUT of the map, and one classified to a
 * kind no department has. Neither catches a field classified to the WRONG live kind, which is
 * the failure that matters: put `price` under `doc` and the four sheet inputs get offered to all
 * eight departments; put `screens` under `site` and Marketing is offered a kind it cannot
 * produce — the exact defect the narrowing exists to prevent. Both mutations pass every other
 * test in this file.
 *
 * Every description begins with the kinds that field belongs to ("checklist: …", "doc/legal: …",
 * "plan: … site: …"). That prose is not the source of truth for what gets sent — the map is —
 * but the two must agree, and this is what says so.
 */
describe("the payload field map agrees with the schema's own descriptions", () => {
  const props = (DELIVERABLE_TOOL.input_schema as any).properties.payload.properties as
    Record<string, { description?: string }>;

  /** Kinds named by a description: at its start, or after a sentence break, `a:` or `a/b:`. */
  const kindsInDescription = (d: string): string[] => {
    const out = new Set<string>();
    for (const m of d.matchAll(/(?:^|\.\s+)([a-z]+(?:\/[a-z]+)*):/g)) {
      for (const k of (m[1] as string).split("/")) out.add(k);
    }
    return [...out].sort();
  };

  test("each field is classified under exactly the kinds its description names", () => {
    const mismatched = Object.entries(props)
      .map(([field, spec]) => ({
        field,
        fromMap: [...(PAYLOAD_FIELD_KINDS[field] ?? [])].sort(),
        fromDescription: kindsInDescription(spec.description ?? ""),
      }))
      .filter((r) => r.fromMap.join(",") !== r.fromDescription.join(","));
    expect(mismatched).toEqual([]);
  });

  /** The descriptions must actually name kinds, or the check above passes on empty sets. */
  test("every description names at least one real kind", () => {
    for (const [field, spec] of Object.entries(props)) {
      const named = kindsInDescription(spec.description ?? "");
      expect(named.length).toBeGreaterThan(0);
      for (const k of named) expect([...DELIVERABLE_KINDS]).toContain(k);
      expect(field).toBeTruthy();
    }
  });
});

/**
 * Two shapes no live department has, which the contract's own docstrings contemplate.
 * Injected into `DEPARTMENT_OUTPUTS` for the length of one test, because the eight real
 * departments cannot exercise either branch.
 */
describe("contract shapes the eight live departments cannot reach", () => {
  const withDept = (key: string, o: { primary: string[]; allowed: string[] }, run: () => void) => {
    (DEPARTMENT_OUTPUTS as Record<string, { primary: string[]; allowed: string[] }>)[key] = o;
    try {
      run();
    } finally {
      delete (DEPARTMENT_OUTPUTS as Record<string, unknown>)[key];
    }
  };

  /** `doc` reachable only via `allowed` still has to be the fallback — else Finding 1 returns. */
  test("falls back to doc when doc is allowed rather than primary", () => {
    withDept("__docAllowed", { primary: ["site"], allowed: ["doc"] }, () => {
      expect(coerceKindForDepartment("__docAllowed", "screens")).toBe("doc");
    });
  });

  /** An empty contract must not emit `enum: []`, which no value can satisfy. */
  test("omits the kind enum entirely for a department that declares nothing", () => {
    withDept("__empty", { primary: [], allowed: [] }, () => {
      const kind = (deliverableTool("__empty").input_schema as any).properties.kind;
      expect(kind.enum).toBeUndefined();
    });
  });
});
