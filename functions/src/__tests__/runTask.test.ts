import { buildRunTaskPrompt, coerceDeliverable, coercePayload, DELIVERABLE_KINDS } from "../runTaskCore";

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
    const validWeek = { label: "Week 1", items: [{ day: "Mon", kind: "Thread", body: "Post about X" }] };
    it("accepts a valid 2-week payload", () => {
      const p: any = coercePayload("calendar", { weeks: [validWeek, { label: "Week 2", items: [{ day: "Thu", kind: "Clip", body: "Demo" }] }] });
      expect(p.weeks).toHaveLength(2);
      expect(p.weeks[0]).toEqual({ label: "Week 1", items: [{ day: "Mon", kind: "Thread", body: "Post about X" }] });
    });
    it("drops malformed items and returns null when nothing valid remains", () => {
      expect(coercePayload("calendar", { weeks: [{ label: "Week 1", items: [{ day: "", kind: "x", body: "" }] }] })).toBeNull();
      expect(coercePayload("calendar", { weeks: [] })).toBeNull();
      expect(coercePayload("calendar", null)).toBeNull();
    });
    it("clips over-count to 2 weeks", () => {
      const p: any = coercePayload("calendar", { weeks: [validWeek, validWeek, validWeek] });
      expect(p.weeks).toHaveLength(2);
    });
  });

  describe("sheet", () => {
    const okInput = { val: 12, min: 6, max: 20, step: 1 };
    it("accepts a valid 4-input payload", () => {
      const p = coercePayload("sheet", { price: okInput, waitlist: okInput, conversion: okInput, churn: okInput, summary: "It shows healthy growth." });
      expect(p).toEqual({ price: okInput, waitlist: okInput, conversion: okInput, churn: okInput, summary: "It shows healthy growth." });
    });
    it("returns null when an input is missing or non-numeric", () => {
      expect(coercePayload("sheet", { price: okInput, waitlist: okInput, conversion: okInput, churn: { val: "x", min: 1, max: 2, step: 1 }, summary: "s" })).toBeNull();
      expect(coercePayload("sheet", { price: okInput, waitlist: okInput, conversion: okInput, summary: "s" })).toBeNull();
    });
    it("returns null when summary is missing", () => {
      expect(coercePayload("sheet", { price: okInput, waitlist: okInput, conversion: okInput, churn: okInput })).toBeNull();
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
    it("accepts a valid full payload", () => {
      const p = coercePayload("site", base);
      expect(p).toEqual(base);
    });
    it("clips steps/features over-count to 3", () => {
      const p: any = coercePayload("site", { ...base, steps: [...base.steps, { h: "Extra", p: "Extra." }] });
      expect(p.steps).toHaveLength(3);
    });
    it("returns null when a required field is missing", () => {
      expect(coercePayload("site", { ...base, headline: "" })).toBeNull();
      expect(coercePayload("site", { ...base, steps: [] })).toBeNull();
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
    it("falls back to a valid enum value when art is invalid", () => {
      const p: any = coercePayload("screens", { screens: [{ ...validScreen, art: "not-a-real-art" }] });
      expect(p.screens[0].art).toBe("connect");
    });
    it("drops screens missing name/title and returns null when none remain", () => {
      expect(coercePayload("screens", { screens: [{ ...validScreen, name: "", title: "" }] })).toBeNull();
      expect(coercePayload("screens", { screens: [] })).toBeNull();
    });
    it("clips over-count to 3 screens", () => {
      const p: any = coercePayload("screens", { screens: [validScreen, validScreen, validScreen, validScreen] });
      expect(p.screens).toHaveLength(3);
    });
  });
});

describe("buildRunTaskPrompt structured guide", () => {
  it("mentions the per-kind payload guide", () => {
    const p = buildRunTaskPrompt({ companionId: "byte", language: "en", context: "", taskTitle: "T", taskDetail: "" });
    expect(p).toContain("ALSO fill `payload`");
    expect(p).toMatch(/checklist:.*items/);
    expect(p).toMatch(/dms:.*messages/);
    expect(p).toMatch(/calendar:.*weeks/);
    expect(p).toMatch(/sheet:.*price.*waitlist.*conversion.*churn/);
    expect(p).toMatch(/site:.*steps/);
    expect(p).toMatch(/screens:.*connect.*session.*recap/);
  });
});
