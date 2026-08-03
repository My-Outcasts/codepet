import { buildRoadmapPrompt, coerceRoadmap, slug, ROADMAP_PHASES } from "../generateRoadmapCore";

describe("buildRoadmapPrompt", () => {
  const brief = { projectName: "Codepet", oneLiner: "a recap tool", stage: "idea" };

  it("mentions the project and all five phases", () => {
    const p = buildRoadmapPrompt({ language: "en", brief });
    expect(p).toContain("Codepet");
    for (const phase of ROADMAP_PHASES) {
      expect(p).toContain(phase);
    }
  });

  it("adds a Vietnamese instruction only for vi", () => {
    expect(buildRoadmapPrompt({ language: "vi", brief })).toMatch(/Vietnamese/i);
    expect(buildRoadmapPrompt({ language: "en", brief })).not.toMatch(/Vietnamese/i);
  });

  it("does not invent facts — instructs grounding", () => {
    expect(buildRoadmapPrompt({ language: "en", brief })).toMatch(/do not invent/i);
  });

  it("injects department grounding with the stage focus", () => {
    const p = buildRoadmapPrompt({ language: "en", brief: { projectName: "Codepet", stage: "Prototype" } });
    expect(p).toContain("Engineering");                 // department name label
    expect(p).toContain("Mandate:");                    // grounding block present
    expect(p).toContain('Focus at the "Prototype" stage'); // stage-specific focus line
  });
  it("still builds (no throw) when stage is unknown/missing", () => {
    const p = buildRoadmapPrompt({ language: "en", brief: { projectName: "Codepet" } });
    expect(p).toContain("Mandate:");                    // grounding still present
    expect(p).not.toContain("Focus at the");            // no stage focus without a stage
  });
});

describe("slug", () => {
  it("lowercases, replaces non-alphanumerics, and trims dashes", () => {
    expect(slug("Ship Auth!!")).toBe("ship-auth");
    expect(slug("  Validate the idea  ")).toBe("validate-the-idea");
  });
});

describe("coerceRoadmap", () => {
  it("assigns unique ids and keeps only valid phases", () => {
    const out = coerceRoadmap({
      tasks: [
        { phase: "find", title: "Talk to 5 users", detail: "d", who: "you", deps: [] },
        { phase: "bogus-phase", title: "Should be dropped", detail: "d", who: "does", deps: [] },
        { phase: "build", title: "", detail: "d", who: "does", deps: [] }, // empty title dropped
      ],
    });
    expect(out.tasks).toHaveLength(1);
    expect(out.tasks[0].phase).toBe("find");
    expect(out.tasks[0].id).toBe("talk-to-5-users-0");
  });

  it("caps tasks at 4 per phase", () => {
    const tasks = Array.from({ length: 6 }, (_, i) => ({
      phase: "build", title: `Task ${i}`, detail: "d", who: "does", deps: [],
    }));
    const out = coerceRoadmap({ tasks });
    expect(out.tasks).toHaveLength(4);
  });

  it("resolves deps titles to ids and drops unknown/self references", () => {
    const out = coerceRoadmap({
      tasks: [
        { phase: "find", title: "Validate the idea", detail: "d", who: "you", deps: [] },
        {
          phase: "foundation",
          title: "Register the company",
          detail: "d",
          who: "does",
          deps: ["Validate the idea", "Some task that does not exist", "Register the company"],
        },
      ],
    });
    const validate = out.tasks.find((t) => t.title === "Validate the idea")!;
    const register = out.tasks.find((t) => t.title === "Register the company")!;
    expect(register.dependsOn).toEqual([validate.id]); // unknown + self dep dropped
  });

  it("backstops a later-phase orphan task to the previous phase (phase-gating)", () => {
    const out = coerceRoadmap({ tasks: [
      { phase: "find", title: "Validate", who: "you", deps: [] },
      { phase: "foundation", title: "Register", who: "does", deps: [] },  // orphan
    ]}, { language: "en" });
    const validate = out.tasks.find((t) => t.title === "Validate")!;
    const register = out.tasks.find((t) => t.title === "Register")!;
    expect(validate.dependsOn).toEqual([]);              // find entry stays depless
    expect(register.dependsOn).toEqual([validate.id]);   // foundation orphan chained back
  });

  it("keeps a valid dept and leaves an invalid/missing one unassigned", () => {
    const out = coerceRoadmap({ tasks: [
      { phase: "build", title: "A", who: "does", deps: [], dept: "eng" },
      { phase: "find",  title: "B", who: "you",  deps: [], dept: "zzz" },
      { phase: "ship",  title: "C", who: "draft", deps: [] },
    ]}, { language: "en" });
    expect(out.tasks.find((t) => t.title === "A")!.dept).toBe("eng");
    expect(out.tasks.find((t) => t.title === "B")!.dept).toBe(""); // invalid → unassigned
    expect(out.tasks.find((t) => t.title === "C")!.dept).toBe(""); // missing → unassigned
  });

  it("drops later duplicate-title tasks so dep resolution stays unambiguous", () => {
    // Two tasks titled "Ship it"; the second self-references by title. Without the
    // unique-title guard, that self-ref would resolve to the FIRST task's id and
    // fabricate a dependency edge. The later duplicate must be dropped entirely.
    const out = coerceRoadmap({
      tasks: [
        { phase: "build", title: "Ship it", detail: "d", who: "does", deps: [] },
        { phase: "launch", title: "Ship it", detail: "d", who: "draft", deps: ["Ship it"] },
      ],
    });
    expect(out.tasks).toHaveLength(1);
    expect(out.tasks[0].phase).toBe("build");
    expect(out.tasks[0].dependsOn).toEqual([]); // no fabricated edge
  });

  it("defaults who, detail, done, and drafted", () => {
    const out = coerceRoadmap({
      tasks: [{ phase: "ship", title: "Ship it" }],
    });
    expect(out.tasks[0].who).toBe("draft");
    expect(out.tasks[0].detail).toBe("");
    expect(out.tasks[0].done).toBe(false);
    expect(out.tasks[0].drafted).toBe(false);
  });

  it("returns {tasks: []} on junk input", () => {
    expect(coerceRoadmap(null).tasks).toEqual([]);
    expect(coerceRoadmap(undefined).tasks).toEqual([]);
    expect(coerceRoadmap({}).tasks).toEqual([]);
    expect(coerceRoadmap({ tasks: "nope" }).tasks).toEqual([]);
    expect(coerceRoadmap("garbage").tasks).toEqual([]);
  });
});
