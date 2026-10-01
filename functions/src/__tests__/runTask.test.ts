import { buildRunTaskPrompt, coerceDeliverable, coercePayload, deliverableTool, DELIVERABLE_KINDS } from "../runTaskCore";

describe("buildRunTaskPrompt", () => {
  const base = {
    companionId: "luna",
    language: "en",
    context: "Project: Acme. Stage: build.",
    taskTitle: "Write the pricing page copy",
    taskDetail: "Three tiers, monthly billing.",
  };

  it("names the chosen companion", () => {
    expect(buildRunTaskPrompt(base)).toContain("Luna");
  });

  it("includes the founder's context, task title, and task detail", () => {
    const p = buildRunTaskPrompt(base);
    expect(p).toContain("Acme");
    expect(p).toContain("Write the pricing page copy");
    expect(p).toContain("Three tiers, monthly billing.");
  });

  it("bounds the deliverable length", () => {
    // `body` is the only unbounded field in RECORD_TOOL and it is the part the
    // founder reads. runTask also runs on a model that writes longer by
    // default, so without this the deliverable grows with no ceiling.
    expect(buildRunTaskPrompt(base)).toContain("LENGTH:");
  });

  it("falls back to byte for an unknown companion", () => {
    expect(buildRunTaskPrompt({ ...base, companionId: "zzz" })).toContain("Byte");
  });

  it("adds a Vietnamese instruction only for vi", () => {
    expect(buildRunTaskPrompt({ ...base, language: "vi" })).toMatch(/Vietnamese/i);
    expect(buildRunTaskPrompt(base)).not.toMatch(/Vietnamese/i);
  });

  it("falls back to a general note when context is empty", () => {
    expect(buildRunTaskPrompt({ ...base, context: "" })).toMatch(/hasn't filled in much/i);
  });

  it("appends a revise instruction with the current draft and the note when both are present", () => {
    const p = buildRunTaskPrompt({ ...base, reviseNote: "Make it punchier", current: "Draft body here." });
    expect(p).toMatch(/REVISING an existing deliverable/i);
    expect(p).toContain("Draft body here.");
    expect(p).toContain("Make it punchier");
    expect(p).toMatch(/full revised deliverable/i);
  });

  it("does not append a revise instruction when reviseNote or current is missing", () => {
    const withoutCurrent = buildRunTaskPrompt({ ...base, reviseNote: "Make it punchier" });
    expect(withoutCurrent).not.toMatch(/REVISING an existing deliverable/i);

    const withoutNote = buildRunTaskPrompt({ ...base, current: "Draft body here." });
    expect(withoutNote).not.toMatch(/REVISING an existing deliverable/i);
  });

  it("is identical to the non-revise prompt when reviseNote/current are absent (backward-compat)", () => {
    expect(buildRunTaskPrompt(base)).toBe(buildRunTaskPrompt({ ...base, reviseNote: undefined, current: undefined }));
    expect(buildRunTaskPrompt(base)).not.toMatch(/REVISING/i);
  });
});

describe("coerceDeliverable", () => {
  it("accepts a valid kind/title/body", () => {
    const d = coerceDeliverable({ kind: "post", title: "Launch post", body: "Hello world" }, "fallback title");
    expect(d).toEqual({ kind: "post", title: "Launch post", body: "Hello world" });
  });

  it("defaults an unknown kind to doc", () => {
    const d = coerceDeliverable({ kind: "not-a-kind", title: "t", body: "b" }, "fallback title");
    expect(d?.kind).toBe("doc");
  });

  it("requires a non-empty body — returns null when empty", () => {
    expect(coerceDeliverable({ kind: "doc", title: "t", body: "" }, "fallback title")).toBeNull();
    expect(coerceDeliverable({ kind: "doc", title: "t", body: "   " }, "fallback title")).toBeNull();
    expect(coerceDeliverable(null, "fallback title")).toBeNull();
  });

  it("falls back title -> taskTitle when title is missing", () => {
    const d = coerceDeliverable({ kind: "doc", body: "content" }, "fallback title");
    expect(d?.title).toBe("fallback title");
  });

  it("covers every allowed kind in DELIVERABLE_KINDS", () => {
    for (const kind of DELIVERABLE_KINDS) {
      const d = coerceDeliverable({ kind, title: "t", body: "b" }, "fallback");
      expect(d?.kind).toBe(kind);
    }
  });
});

describe("coerceDeliverable payload", () => {
  it("attaches a sanitized checklist payload and keeps body", () => {
    const out = coerceDeliverable({ kind: "checklist", title: "T", body: "md",
      payload: { items: [{ t: "Step 1", done: false }, { t: "", done: true }, { t: "Step 2", done: true }] } }, "task");
    expect(out!.kind).toBe("checklist");
    expect(out!.body).toBe("md");
    expect((out as any).payload.items).toEqual([{ t: "Step 1", done: false }, { t: "Step 2", done: true }]);
  });
  it("omits payload for a non-structured kind (backward-compat)", () => {
    const out = coerceDeliverable({ kind: "post", title: "T", body: "md", payload: { foo: 1 } }, "task");
    expect((out as any).payload).toBeUndefined();
    expect(out).toEqual({ kind: "post", title: "T", body: "md" });
  });
  it("omits payload when a structured kind's required fields are missing (fail-open to body)", () => {
    const out = coerceDeliverable({ kind: "doc", title: "T", body: "md", payload: { sections: [] } }, "task");
    expect((out as any).payload).toBeUndefined();
    expect(out!.body).toBe("md");
  });
});
describe("coercePayload", () => {
  it("plan requires goal+steps+changes", () => {
    expect(coercePayload("plan", { goal: "g", steps: ["a"], changes: [{ area: "x", edit: "y" }], verify: [], risks: "" }))
      .toEqual({ goal: "g", steps: ["a"], changes: [{ area: "x", edit: "y" }], verify: [], risks: "" });
    expect(coercePayload("plan", { goal: "g", steps: [], changes: [] })).toBeNull();
  });
  it("dms keeps up to 4 valid messages", () => {
    const p: any = coercePayload("dms", { messages: [{ name: "A", note: "n", msg: "m" }, { name: "", note: "", msg: "" }] });
    expect(p.messages).toHaveLength(1);
  });

  describe("calendar", () => {
    // CP-002 E1: weeks became phases. These are the legacy tests, rewritten for the lift — a
    // `weeks[]` payload now arrives as `phases[]`, with day → when and kind → format.
    const validWeek = { label: "Week 1", items: [{ day: "Mon", kind: "Thread", body: "Post about X" }] };
    it("a valid 2-week payload is lifted into two phases", () => {
      const p: any = coercePayload("calendar", { weeks: [validWeek, { label: "Week 2", items: [{ day: "Thu", kind: "Clip", body: "Demo" }] }] });
      expect(p.phases).toHaveLength(2);
      expect(p.phases[0]).toEqual({ label: "Week 1", from: "", to: "", items: [{ when: "Mon", format: "Thread", body: "Post about X" }] });
      expect(p).not.toHaveProperty("weeks");
    });
    it("drops malformed items and returns null when nothing valid remains", () => {
      expect(coercePayload("calendar", { weeks: [{ label: "Week 1", items: [{ day: "", kind: "x", body: "" }] }] })).toBeNull();
      expect(coercePayload("calendar", { weeks: [] })).toBeNull();
      expect(coercePayload("calendar", null)).toBeNull();
    });
    // Was "clips over-count to 2 weeks". The demo's launch runway has five, and lost three.
    it("no longer clips at two", () => {
      const p: any = coercePayload("calendar", { weeks: [validWeek, validWeek, validWeek, validWeek, validWeek] });
      expect(p.phases).toHaveLength(5);
    });
  });

  describe("sheet", () => {
    const okInput = { val: 12, min: 6, max: 20, step: 1 };
    it("a valid 4-input payload is lifted into the model shape (CP-002 D)", () => {
      const p: any = coercePayload("sheet", { price: okInput, waitlist: okInput, conversion: okInput, churn: okInput, summary: "It shows healthy growth." });
      expect(p.inputs.slice(0, 4).map((i: any) => [i.key, i.val, i.min, i.max, i.step]))
        .toEqual(["price", "waitlist", "conversion", "churn"].map((k) => [k, 12, 6, 20, 1]));
      expect(p.summary).toBe("It shows healthy growth.");
    });
    it("returns null when an input is missing or non-numeric", () => {
      expect(coercePayload("sheet", { price: okInput, waitlist: okInput, conversion: okInput, churn: { val: "x", min: 1, max: 2, step: 1 }, summary: "s" })).toBeNull();
      expect(coercePayload("sheet", { price: okInput, waitlist: okInput, conversion: okInput, summary: "s" })).toBeNull();
    });
    // Was "returns null when summary is missing". A model is still a model without its paragraph,
    // and the Failed rule (PR F) is about unusable payloads, not unfinished prose.
    it("summary is optional", () => {
      expect((coercePayload("sheet", { price: okInput, waitlist: okInput, conversion: okInput, churn: okInput }) as any).summary).toBe("");
    });
  });

  describe("site", () => {
    const base = {
      title: "Acme", brand: "Acme", kicker: "", headline: "Ship faster", headlineHi: "",
      sub: "The tool for builders.", ctaPrimary: "Get started", ctaSecondary: "",
      howEyebrow: "How it works", howTitle: "Three steps",
      steps: [{ h: "Connect", p: "Link your repo." }, { h: "Build", p: "Write code." }, { h: "Ship", p: "Deploy it." }],
      featEyebrow: "Why Acme", featTitle: "Built for speed",
      features: [{ h: "Fast", p: "Blazing." }, { h: "Simple", p: "No setup." }, { h: "Safe", p: "Tested." }],
      quote: "", quoteBy: "", finalTitle: "Start today", finalSub: "", finalCta: "Sign up",
      accent: "#6E8E68", footNote: "© 2026 Acme",
    };
    // CP-002 E2: the flat steps/features/quote are lifted into typed `blocks[]`, in the order
    // the page always drew them, so an old page renders the same (SiteLegacyParityTests).
    it("a legacy full payload lifts into blocks, in the old order", () => {
      const p: any = coercePayload("site", base);
      expect(p.blocks.map((b: any) => b.type)).toEqual(["steps", "features"]);
      expect(p.blocks[0]).toEqual({ type: "steps", eyebrow: "How it works", title: "Three steps", items: base.steps });
      for (const gone of ["steps", "features", "howEyebrow", "howTitle", "featEyebrow", "featTitle", "quote", "quoteBy"]) {
        expect(p).not.toHaveProperty(gone);
      }
      expect(p).toMatchObject({ headline: "Ship faster", finalCta: "Sign up", accent: "#6E8E68" });
    });
    it("a legacy quote becomes a quote block", () => {
      const p: any = coercePayload("site", { ...base, quote: "It works.", quoteBy: "a user" });
      expect(p.blocks[2]).toEqual({ type: "quote", eyebrow: "", title: "", text: "It works.", by: "a user" });
    });
    // Was "clips steps/features over-count to 3".
    it("no longer clips a list at three", () => {
      const p: any = coercePayload("site", { ...base, steps: [...base.steps, { h: "Extra", p: "Extra." }] });
      expect(p.blocks[0].items).toHaveLength(4);
    });
    it("returns null when a required field is missing, or there is nothing below the hero", () => {
      expect(coercePayload("site", { ...base, headline: "" })).toBeNull();
      expect(coercePayload("site", { ...base, steps: [], features: [] })).toBeNull();
      expect(coercePayload("site", {})).toBeNull();
    });
  });

  describe("screens", () => {
    const validScreen = { name: "Connect", time: "0:15", kick: "Step 1 of 3", title: "Link your account", sub: "", art: "connect", cta: "Continue", note: "" };
    it("accepts a valid 3-screen payload", () => {
      const p: any = coercePayload("screens", { screens: [validScreen, { ...validScreen, name: "Session", art: "session" }, { ...validScreen, name: "Recap", art: "recap" }] });
      expect(p.screens).toHaveLength(3);
      expect(p.screens[0]).toEqual(validScreen);
    });
    // CP-002 E3: `art` is a description of the illustration, not one of three enum values. It
    // used to be forced to "connect" — so a screen asking for a chart was drawn as a link icon.
    it("keeps any art as written, and no longer forces it to connect", () => {
      const p: any = coercePayload("screens", { screens: [{ ...validScreen, art: "a week of check-ins filling a grid, Thursday highlighted" }] });
      expect(p.screens[0].art).toBe("a week of check-ins filling a grid, Thursday highlighted");
    });
    it("a screen may have no art at all", () => {
      const p: any = coercePayload("screens", { screens: [{ ...validScreen, art: "" }] });
      expect(p.screens[0].art).toBe("");
    });
    it("drops screens missing name/title and returns null when none remain", () => {
      expect(coercePayload("screens", { screens: [{ ...validScreen, name: "", title: "" }] })).toBeNull();
      expect(coercePayload("screens", { screens: [] })).toBeNull();
    });
    // Was "clips over-count to 3 screens".
    it("keeps up to 8 screens", () => {
      const p: any = coercePayload("screens", { screens: Array.from({ length: 10 }, () => validScreen) });
      expect(p.screens).toHaveLength(8);
    });
    it("the prompt and schema no longer fix three screens or three illustrations", () => {
      const p = buildRunTaskPrompt({ companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "", deptKey: "design" } as any);
      const line = p.split("\n").find((l) => l.startsWith("- screens: ")) ?? "";
      expect(line).toContain("`art`");
      expect(line).not.toContain("exactly 3");
      expect(line).not.toMatch(/connect.*session.*recap/);
      const art = (deliverableTool("design").input_schema as any).properties.payload.properties.screens.items.properties.art;
      expect(art).not.toHaveProperty("enum");
    });
  });
});

describe("buildRunTaskPrompt structured guide", () => {
  it("mentions the per-kind payload guide", () => {
    const p = buildRunTaskPrompt({ companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "" });
    expect(p).toContain("ALSO fill `payload`");
    expect(p).toMatch(/checklist:.*items/);
    expect(p).toMatch(/dms:.*messages/);
    expect(p).toMatch(/calendar:.*phases/);
    expect(p).toMatch(/sheet:.*inputs.*outputs.*formula/);
    expect(p).toMatch(/site:.*steps/);
    expect(p).toMatch(/screens:.*`art`/);
  });
});

/**
 * `legal` fills `sections` (CP-002 A, spec Layer 2).
 *
 * Before this the schema documented `sections` as "doc/legal", the prompt never asked Legal to
 * fill it, `legal` was not a structured kind, and so even a model that filled it anyway had the
 * payload dropped on the way in. The prompt is the one that was wrong.
 */
describe("legal sections", () => {
  const clause = (h: string, p = "Clause text.") => ({ h, p });

  it("keeps ordered clauses and drops empty ones", () => {
    expect(coercePayload("legal", { sections: [clause("Definitions"), clause("", "orphan"), clause("Term")] }))
      .toEqual({ sections: [clause("Definitions"), clause("Term")] });
  });

  it("strips the model's own numbering, because the viewer numbers them", () => {
    const got: any = coercePayload("legal", { sections: [
      clause("1. Definitions"), clause("§2 Term"), clause("Section 3: Governing law"),
      clause("4) Notices"), clause("Clause 5 — Severability"), clause("2FA requirements"),
    ] });
    expect(got.sections.map((x: any) => x.h)).toEqual([
      "Definitions", "Term", "Governing law", "Notices", "Severability", "2FA requirements",
    ]);
  });

  it("does not cap a real policy at a doc's five blocks", () => {
    const many = Array.from({ length: 14 }, (_, i) => clause(`Clause ${String.fromCharCode(65 + i)}`));
    expect((coercePayload("legal", { sections: many }) as any).sections).toHaveLength(14);
  });

  it("is null without a clause, and carries no doc-only fields", () => {
    expect(coercePayload("legal", { sections: [] })).toBeNull();
    expect(coercePayload("legal", { call: "c", next: ["n"] })).toBeNull();
    expect(coercePayload("legal", { call: "c", sections: [clause("Term")] })).toEqual({ sections: [clause("Term")] });
  });

  it("reaches the stored deliverable instead of being dropped", () => {
    const out = coerceDeliverable({ kind: "legal", title: "NDA", body: "md", payload: { sections: [clause("Term")] } }, "task", "legal");
    expect(out).toEqual({ kind: "legal", title: "NDA", body: "md", payload: { sections: [clause("Term")] } });
  });

  it("a legal deliverable without sections still files on its body (legacy)", () => {
    expect(coerceDeliverable({ kind: "legal", title: "NDA", body: "md" }, "task", "legal"))
      .toEqual({ kind: "legal", title: "NDA", body: "md" });
  });

  it("the prompt asks Legal for sections, and does not ask Engineering", () => {
    const p = (deptKey: string) => buildRunTaskPrompt({
      companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "", deptKey,
    } as any);
    expect(p("legal")).toMatch(/- legal: .*`sections\[\]`/);
    expect(p("fin")).toMatch(/- legal: /);
    expect(p("eng")).not.toMatch(/- legal: /);
    expect(p("design")).not.toMatch(/- legal: /);
  });
});

/**
 * `dms` are addressed to an audience, not an invented person (CP-002 B, spec "dms invents
 * people"). The prompt used to ask for four messages whose `name` was a "persona placeholder",
 * so Sales handed the founder messages to people who do not exist, rendered like real prospects.
 */
describe("dms audience", () => {
  const sales = () => buildRunTaskPrompt({
    companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "", deptKey: "sales",
  } as any);
  const msgSchema = () => (deliverableTool("sales").input_schema as any).properties.payload.properties.messages;

  it("keeps an audience and never emits a name", () => {
    expect(coercePayload("dms", { messages: [{ audience: "lapsed journaler", note: "quit over streaks", msg: "Hi [name]" }] }))
      .toEqual({ messages: [{ audience: "lapsed journaler", note: "quit over streaks", msg: "Hi [name]" }] });
  });

  it("lifts a legacy `name` into `audience`", () => {
    const p: any = coercePayload("dms", { messages: [{ name: "privacy-first buyer", note: "n", msg: "m" }] });
    expect(p.messages).toEqual([{ audience: "privacy-first buyer", note: "n", msg: "m" }]);
    expect(p.messages[0]).not.toHaveProperty("name");
  });

  it("prefers `audience` when both arrive", () => {
    const p: any = coercePayload("dms", { messages: [{ name: "Sarah Chen", audience: "indie baker", note: "", msg: "m" }] });
    expect(p.messages[0].audience).toBe("indie baker");
  });

  it("the prompt asks for an audience and no longer asks for a persona", () => {
    expect(sales()).toMatch(/- dms: .*`audience`/);
    expect(sales()).not.toContain("persona placeholder");
    expect(sales()).not.toMatch(/\{name \(/);
  });

  it("the schema declares audience, not name", () => {
    expect(Object.keys(msgSchema().items.properties)).toEqual(["audience", "note", "msg"]);
    expect(msgSchema().items.required).toEqual(["audience", "note", "msg"]);
    expect(msgSchema().description).not.toContain("persona");
  });
});

/**
 * Additive fields (CP-002 C, spec Layer 2): checklist owner/due and no 5-7 cap, doc
 * `rules_out` + per-section `source`, post `platform`/`limit`, email `subject`/`to`. Every one is
 * optional on the way in, so each legacy shape must still coerce to exactly what it did.
 */
describe("additive fields", () => {
  const prompt = (deptKey?: string) => buildRunTaskPrompt({
    companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "", deptKey,
  } as any);
  const props = (d: string) => (deliverableTool(d).input_schema as any).properties.payload.properties;

  describe("checklist", () => {
    it("keeps owner and due when given, and omits them when not", () => {
      expect(coercePayload("checklist", { items: [
        { t: "Buy domain", done: true, owner: "you", due: "today" },
        { t: "Draft FAQ", done: false, owner: "", due: "" },
        { t: "Ship", done: false },
      ] })).toEqual({ items: [
        { t: "Buy domain", done: true, owner: "you", due: "today" },
        { t: "Draft FAQ", done: false },
        { t: "Ship", done: false },
      ] });
    });
    it("is no longer cut off at seven steps", () => {
      const items = Array.from({ length: 20 }, (_, i) => ({ t: `Step ${i + 1}`, done: false }));
      expect((coercePayload("checklist", { items }) as any).items).toHaveLength(20);
    });
    it("the prompt drops the 5-7 rule and asks for owner/due without inventing them", () => {
      expect(prompt("ops")).not.toContain("exactly 5-7");
      expect(prompt("ops")).toMatch(/- checklist: .*`owner`.*`due`/);
      expect(props("ops").items.description).not.toContain("5-7");
      expect(Object.keys(props("ops").items.items.properties)).toEqual(["t", "done", "owner", "due"]);
      expect(props("ops").items.items.required).toEqual(["t", "done"]);
    });
  });

  describe("doc", () => {
    const base = { call: "Charge $8", sections: [{ h: "Why", p: "Because." }], next: [] };
    it("a legacy doc coerces exactly as before", () => {
      expect(coercePayload("doc", base)).toEqual(base);
    });
    it("keeps rules_out and a section's source", () => {
      expect(coercePayload("doc", { ...base, rules_out: ["A free tier", ""], sections: [{ h: "Why", p: "Because.", source: "the pricing interviews" }] }))
        .toEqual({ ...base, rules_out: ["A free tier"], sections: [{ h: "Why", p: "Because.", source: "the pricing interviews" }] });
    });
    it("a legal clause never carries a source", () => {
      expect(coercePayload("legal", { sections: [{ h: "Term", p: "Two years.", source: "x" }] }))
        .toEqual({ sections: [{ h: "Term", p: "Two years." }] });
    });
    it("the prompt and schema offer rules_out to a doc department", () => {
      expect(prompt("eng")).toMatch(/- doc: .*`rules_out\[\]`/);
      expect(props("eng")).toHaveProperty("rules_out");
      expect(Object.keys(props("eng").sections.items.properties)).toEqual(["h", "p", "source"]);
    });
  });

  describe("post", () => {
    it("is a structured kind now: the platform and its limit reach the deliverable", () => {
      expect(coerceDeliverable({ kind: "post", title: "T", body: "hi", payload: { platform: "X", limit: 280 } }, "task", "mkt"))
        .toEqual({ kind: "post", title: "T", body: "hi", payload: { platform: "X", limit: 280 } });
    });
    it("a known platform's limit is the server's, not the model's", () => {
      expect(coercePayload("post", { platform: "Twitter", limit: 5000 })).toEqual({ platform: "X", limit: 280 });
      expect(coercePayload("post", { platform: "linkedin" })).toEqual({ platform: "LinkedIn", limit: 3000 });
      expect(coercePayload("post", { platform: "Bluesky", limit: 9 })).toEqual({ platform: "Bluesky", limit: 300 });
    });
    it("an unknown platform keeps a sane model limit, or none", () => {
      expect(coercePayload("post", { platform: "Farcaster", limit: 320 })).toEqual({ platform: "Farcaster", limit: 320 });
      expect(coercePayload("post", { platform: "Farcaster", limit: -1 })).toEqual({ platform: "Farcaster" });
      expect(coercePayload("post", { platform: "Farcaster", limit: "320" })).toEqual({ platform: "Farcaster" });
    });
    it("no platform, no payload: a legacy post files on its body", () => {
      expect(coercePayload("post", { limit: 280 })).toBeNull();
      expect(coerceDeliverable({ kind: "post", title: "T", body: "hi" }, "task", "mkt")).toEqual({ kind: "post", title: "T", body: "hi" });
    });
    it("only departments that may post are told how", () => {
      expect(prompt("mkt")).toMatch(/- post: .*`platform`/);
      expect(prompt("fin")).not.toMatch(/- post: /);
      expect(props("fin")).not.toHaveProperty("platform");
    });
  });

  describe("email", () => {
    it("keeps subject and to", () => {
      expect(coercePayload("email", { subject: "Your beta invite", to: "the two who asked to pay" }))
        .toEqual({ subject: "Your beta invite", to: "the two who asked to pay" });
    });
    it("to is optional, subject is not", () => {
      expect(coercePayload("email", { subject: "Hi" })).toEqual({ subject: "Hi" });
      expect(coercePayload("email", { to: "x" })).toBeNull();
    });
    it("an address is not a recipient description and is dropped", () => {
      expect(coercePayload("email", { subject: "Hi", to: "sarah@acme.com" })).toEqual({ subject: "Hi" });
    });
    it("the prompt forbids an invented recipient", () => {
      expect(prompt("sales")).toMatch(/- email: .*`subject`.*`to`.*never an invented name/);
      expect(prompt("design")).not.toMatch(/- email: /);
    });
  });
});

/**
 * `sheet` becomes any model (CP-002 D): free `inputs[]`, `outputs[]` written as formulas, and
 * the old fixed four lifted into that shape. Founder decisions (30 Sep): formulas always shown,
 * the hidden $2,500 of monthly costs becomes a fifth input, and at most 8 inputs and 8 outputs.
 */
describe("sheet model", () => {
  const inp = (key: string, val = 5, extra: object = {}) => ({ key, name: key.toUpperCase(), unit: "", val, min: 0, max: 100, step: 1, ...extra });
  const out = (key: string, formula: string, extra: object = {}) => ({ key, name: key.toUpperCase(), unit: "", formula, ...extra });
  const sheet = (r: unknown) => coercePayload("sheet", r) as any;

  it("keeps declared inputs and computes each output's value itself", () => {
    const got = sheet({ inputs: [inp("a", 3), inp("b", 4)], outputs: [out("total", "a * b", { value: 999 })], summary: "s" });
    expect(got.inputs.map((i: any) => i.key)).toEqual(["a", "b"]);
    expect(got.outputs).toEqual([{ key: "total", name: "TOTAL", unit: "", formula: "a * b", value: 12 }]);
    expect(got.summary).toBe("s");
  });

  it("a headline may be built from outputs listed after it", () => {
    const got = sheet({ inputs: [inp("a", 2)], outputs: [out("head", "x + 1"), out("x", "a * 10")] });
    expect(got.outputs.map((o: any) => [o.key, o.value])).toEqual([["head", 21], ["x", 20]]);
  });

  it("drops an output whose formula does not check out, and anything built on it", () => {
    const got = sheet({ inputs: [inp("a")], outputs: [
      out("ok", "a * 2"), out("bad", "sqrt(a)"), out("onbad", "bad + 1"), out("ghost", "nope"), out("loop", "loop + 1"),
    ] });
    expect(got.outputs.map((o: any) => o.key)).toEqual(["ok"]);
  });

  it("drops an output that is not finite at the defaults", () => {
    const got = sheet({ inputs: [inp("a", 0)], outputs: [out("ok", "a + 1"), out("div", "1 / a")] });
    expect(got.outputs.map((o: any) => o.key)).toEqual(["ok"]);
  });

  it("cleans inputs: bad keys, duplicates, broken ranges; clamps val into range", () => {
    const got = sheet({ inputs: [
      inp("Price"), inp("ok", 500), inp("ok"), inp("flip", 1, { min: 10, max: 2 }), inp("nostep", 1, { step: 0 }), inp("bad key"),
    ], outputs: [out("o", "ok")] });
    expect(got.inputs.map((i: any) => [i.key, i.val])).toEqual([["price", 5], ["ok", 100]]);
  });

  it("an output key may not shadow an input", () => {
    expect(sheet({ inputs: [inp("a")], outputs: [out("a", "a * 2"), out("b", "a")] }).outputs.map((o: any) => o.key)).toEqual(["b"]);
  });

  it("caps at 8 inputs and 8 outputs", () => {
    const got = sheet({
      inputs: Array.from({ length: 10 }, (_, i) => inp(`i${i}`)),
      outputs: Array.from({ length: 10 }, (_, i) => out(`o${i}`, `i0 + ${i}`)),
    });
    expect([got.inputs.length, got.outputs.length]).toEqual([8, 8]);
  });

  it("null without an input or without an output that survives", () => {
    expect(sheet({ inputs: [], outputs: [out("o", "1")] })).toBeNull();
    expect(sheet({ inputs: [inp("a")], outputs: [out("o", "zzz")] })).toBeNull();
  });

  describe("legacy lift", () => {
    const four = {
      price: { val: 6, min: 0, max: 20, step: 1 }, waitlist: { val: 400, min: 50, max: 5000, step: 50 },
      conversion: { val: 8, min: 1, max: 40, step: 1 }, churn: { val: 9, min: 1, max: 25, step: 1 }, summary: "s",
    };
    it("becomes five inputs, the fifth being the $2,500 that was hidden", () => {
      const got = sheet(four);
      expect(got.inputs.map((i: any) => i.key)).toEqual(["price", "waitlist", "conversion", "churn", "costs"]);
      expect(got.inputs[4]).toMatchObject({ name: "Monthly costs", unit: "$", val: 2500 });
      expect(got.legacy).toBe(true);
    });
    it("reproduces the six numbers the old fixed model computed", () => {
      // SheetModel.compute(6, 400, 8, 9): paid 32, mrr 192, arr 2304, ltv 67, life 11, breakeven 417.
      const v = Object.fromEntries(sheet(four).outputs.map((o: any) => [o.key, o.value]));
      expect(v).toEqual({ mrr: 192, paid: 32, arr: 2304, ltv: 67, life: 11, breakeven: 417 });
    });
    it("keeps the old floors: price at 1, churn at 1%", () => {
      const v = Object.fromEntries(sheet({ ...four, price: { val: 0, min: 0, max: 20, step: 1 }, churn: { val: 0, min: 0, max: 25, step: 1 } })
        .outputs.map((o: any) => [o.key, o.value]));
      expect(v).toMatchObject({ mrr: 32, ltv: 100, life: 100, breakeven: 2500 });
    });
    it("a payload with neither shape is not a sheet", () => {
      expect(sheet({ price: four.price, summary: "s" })).toBeNull();
    });
  });

  it("the prompt asks for inputs and formulas, and no longer fixes the four", () => {
    const p = buildRunTaskPrompt({ companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "", deptKey: "fin" } as any);
    expect(p).toMatch(/- sheet: .*`inputs\[\]`.*`outputs\[\]`.*`formula`/);
    expect(p).not.toContain("Never add a 5th input");
    expect(p).not.toContain("4 fixed inputs");
    const props = (deliverableTool("fin").input_schema as any).properties.payload.properties;
    expect(props).toHaveProperty("inputs");
    expect(props).toHaveProperty("outputs");
    for (const gone of ["price", "waitlist", "conversion", "churn"]) expect(props).not.toHaveProperty(gone);
  });
});

/** CP-002 E1: a calendar is a plan in phases (founder decisions, 30 Sep: items keep when/format). */
describe("calendar phases", () => {
  const item = (o: object = {}) => ({ when: "T-5", format: "verify", channel: "", owner: "", body: "Deletion deletes", ...o });
  const cal = (r: unknown) => coercePayload("calendar", r) as any;

  it("keeps phases with a span, and items with where and who", () => {
    expect(cal({ phases: [{ label: "Five days out", from: "T-5", to: "T-3", items: [item({ channel: "X", owner: "Marketing" })] }] }))
      .toEqual({ phases: [{ label: "Five days out", from: "T-5", to: "T-3", items: [
        { when: "T-5", format: "verify", channel: "X", owner: "Marketing", body: "Deletion deletes" }] }] });
  });
  it("omits empty channel and owner, so a legacy item reads as before", () => {
    expect(cal({ phases: [{ label: "P", from: "", to: "", items: [item()] }] }).phases[0].items[0])
      .toEqual({ when: "T-5", format: "verify", body: "Deletion deletes" });
  });
  it("an item needs text; a phase needs a label and an item", () => {
    expect(cal({ phases: [{ label: "", items: [item()] }, { label: "P", items: [item({ body: "" })] }] })).toBeNull();
  });
  it("caps at 8 phases of 8 items", () => {
    const got = cal({ phases: Array.from({ length: 10 }, (_, i) => ({ label: `P${i}`, items: Array.from({ length: 10 }, () => item()) })) });
    expect(got.phases).toHaveLength(8);
    expect(got.phases[0].items).toHaveLength(8);
  });
  it("the prompt asks for phases with relative spans, never dates, and drops the two-week rule", () => {
    const p = buildRunTaskPrompt({ companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "", deptKey: "mkt" } as any);
    expect(p).toMatch(/- calendar: .*`phases\[\]`.*`when`.*`format`.*`channel`.*`owner`/);
    expect(p).not.toContain("exactly 2");
    expect(p).toMatch(/never a calendar date/);
    const props = (deliverableTool("mkt").input_schema as any).properties.payload.properties;
    expect(props).toHaveProperty("phases");
    expect(props).not.toHaveProperty("weeks");
  });
});

/** CP-002 E2: a landing page is a hero, typed blocks in any order, and a closing CTA. */
describe("site blocks", () => {
  const hero = { title: "Murror", brand: "Murror", headline: "AI that brings people", ctaPrimary: "Start free", finalTitle: "Start", finalCta: "Go", accent: "#6E8E68" };
  const site = (blocks: unknown[]) => coercePayload("site", { ...hero, blocks }) as any;

  it("keeps all six types, in the model's order", () => {
    const got = site([
      { type: "faq", eyebrow: "Questions", title: "Before you ask", items: [{ h: "Is this therapy?", p: "No." }] },
      { type: "pricing", title: "Pricing", tiers: [
        { name: "Free", price: "$0", period: "", points: ["14 days of history"], cta: "Start free", highlight: false },
        { name: "Practice", price: "$6", period: "/ month", points: ["History forever"], cta: "Start", highlight: true }] },
      { type: "text", title: "Why", text: "Because." },
      { type: "quote", text: "It works.", by: "a user" },
      { type: "steps", title: "How", items: [{ h: "a", p: "b" }] },
      { type: "features", title: "What", items: [{ h: "c", p: "d" }] },
    ]);
    expect(got.blocks.map((b: any) => b.type)).toEqual(["faq", "pricing", "text", "quote", "steps", "features"]);
    expect(got.blocks[1].tiers[1]).toEqual({ name: "Practice", price: "$6", period: "/ month", points: ["History forever"], cta: "Start", highlight: true });
  });
  it("drops an unknown type, and a block with nothing in it", () => {
    const got = site([{ type: "carousel", title: "x", items: [{ h: "a", p: "b" }] }, { type: "faq", title: "empty", items: [] },
      { type: "pricing", tiers: [{ name: "", price: "" }] }, { type: "text", text: "kept" }]);
    expect(got.blocks.map((b: any) => b.type)).toEqual(["text"]);
  });
  it("never lets HTML through: text is text", () => {
    const got = site([{ type: "text", text: "<script>x</script>" }]);
    expect(got.blocks[0].text).toBe("<script>x</script>"); // stored as-is; SiteViewer escapes every string it writes
  });
  it("caps at 8 blocks, 8 items, 4 tiers, 6 points", () => {
    const items = Array.from({ length: 10 }, (_, i) => ({ h: `h${i}`, p: "p" }));
    const got = site([...Array.from({ length: 10 }, () => ({ type: "steps", title: "t", items })),]);
    expect(got.blocks).toHaveLength(8);
    expect(got.blocks[0].items).toHaveLength(8);
    const tiers = Array.from({ length: 6 }, (_, i) => ({ name: `T${i}`, price: "$1", points: Array.from({ length: 9 }, (_, j) => `p${j}`), cta: "c" }));
    const pr = site([{ type: "pricing", tiers }]).blocks[0];
    expect(pr.tiers).toHaveLength(4);
    expect(pr.tiers[0].points).toHaveLength(6);
  });
  it("the prompt offers the six types and drops the fixed three-and-three", () => {
    const p = buildRunTaskPrompt({ companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "", deptKey: "design" } as any);
    const line = p.split("\n").find((l) => l.startsWith("- site: ")) ?? "";
    expect(line).toContain("`blocks[]`");
    for (const t of ["`steps`", "`features`", "`faq`", "`quote`", "`text`", "`pricing`"]) expect(line).toContain(t);
    expect(p).not.toContain("exactly 3 `steps[]`");
    expect(p).not.toContain("exactly 3 `features[]`");
    const props = (deliverableTool("design").input_schema as any).properties.payload.properties;
    expect(props).toHaveProperty("blocks");
    for (const gone of ["features", "howEyebrow", "howTitle", "featEyebrow", "featTitle", "quote", "quoteBy"]) expect(props).not.toHaveProperty(gone);
  });
});

/**
 * The Failed rule (CP-002 F). A sheet, site, calendar or screens whose structure does not
 * survive coercion used to file as its markdown body: the founder was promised a model and got a
 * wall of text. Now it fails: nothing is filed, and the answer says which kind was not made.
 * Founder decision (1 Oct): only these four — a doc, post, email, legal draft, checklist, plan
 * or outreach still files its text, because its text IS the deliverable.
 */
describe("the Failed rule", () => {
  const raw = (kind: string, payload: unknown = {}) => ({ kind, title: "T", body: "some markdown", payload });

  it.each(["sheet", "site", "calendar", "screens"])("a %s without its structure fails instead of filing its body", (kind) => {
    expect(coerceDeliverable(raw(kind, { nonsense: true }), "task")).toEqual({ kind, title: "", body: "", failed: "missing_structure" });
    expect(coerceDeliverable({ kind, title: "T", body: "md" }, "task")).toEqual({ kind, title: "", body: "", failed: "missing_structure" });
  });

  it.each(["doc", "post", "email", "legal", "checklist", "plan", "dms"])("a %s without its structure still files its text", (kind) => {
    const out = coerceDeliverable(raw(kind, { nonsense: true }), "task", undefined);
    expect(out).toEqual({ kind, title: "T", body: "some markdown" });
  });

  it("a valid sheet is not a failure", () => {
    const out: any = coerceDeliverable(raw("sheet", { inputs: [{ key: "a", name: "A", unit: "", val: 1, min: 0, max: 2, step: 1 }], outputs: [{ key: "b", name: "B", unit: "", formula: "a" }] }), "task");
    expect(out.failed).toBeUndefined();
    expect(out.payload.outputs[0].value).toBe(1);
  });

  it("an out-of-contract kind still becomes a doc, not a failure", () => {
    // Finance may not produce `site`: the contract turns it into a doc with its text, which is
    // the deliberate fallback — the payload was built for the kind the contract closed.
    const out: any = coerceDeliverable(raw("site", {}), "task", "fin");
    expect(out).toEqual({ kind: "doc", title: "T", body: "some markdown" });
  });

  it("a revise pinned to a sheet fails rather than replacing the model with text", () => {
    expect(coerceDeliverable(raw("doc", { nonsense: true }), "task", "fin", "sheet"))
      .toEqual({ kind: "sheet", title: "", body: "", failed: "missing_structure" });
  });

  it("no body at all is still no answer (null), as before", () => {
    expect(coerceDeliverable({ kind: "sheet", title: "T", body: "" }, "task")).toBeNull();
  });
});
