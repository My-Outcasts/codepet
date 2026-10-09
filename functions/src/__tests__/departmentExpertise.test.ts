import { buildSystemPrompt } from "../companyChatCore";
import { buildRunTaskPrompt } from "../runTaskCore";
import { DEPARTMENT_FOUNDATIONS, DEPARTMENT_NAMES } from "../departments";
import { AGENT_DEFS } from "../company/registry";

// DEPARTMENT_FOUNDATIONS has existed since Jul 15 and, until this change, exactly one caller
// read it — the roadmap generator. Chat and run-task, the two places a founder actually
// receives departmental work, never saw it: they got a companion voice and generic company
// context, so "Nova · Marketing" was a marketing NAME on a generalist's answer.
//
// These tests hold that wiring in place from both ends: the expertise is present when a
// department is in play, and absent (byte-identical to before) when one is not.
describe("department expertise reaches the prompts", () => {
  const marketingMandate = DEPARTMENT_FOUNDATIONS.mkt.mandate;

  describe("chat system prompt", () => {
    it("carries the department's mandate and skills when a department is in focus", () => {
      const p = buildSystemPrompt({ companionId: "nova", language: "en", deptKey: "mkt" });
      expect(p).toContain(marketingMandate);
      expect(p).toContain("Marketing function");
    });

    it("says nothing about departments on an ordinary turn", () => {
      const p = buildSystemPrompt({ companionId: "byte", language: "en" });
      expect(p).not.toContain(marketingMandate);
      expect(p).not.toContain("function of the founder's company");
    });

    // The static block is the CACHED prefix. Two founders asking Marketing must produce a
    // byte-identical prefix or the cache stops paying for itself — the whole reason this
    // block is separate from the per-request context.
    it("is identical for two founders in the same department and language", () => {
      const a = buildSystemPrompt({ companionId: "nova", language: "en", deptKey: "mkt" });
      const b = buildSystemPrompt({ companionId: "nova", language: "en", deptKey: "mkt" });
      expect(a).toBe(b);
    });

    // Fail open, always: dept_key arrives from a client and must never be able to break a
    // turn. An unknown key degrades to an ordinary prompt rather than an empty section or a
    // half-written sentence.
    it("degrades to an ordinary prompt on an unknown or empty department key", () => {
      const plain = buildSystemPrompt({ companionId: "byte", language: "en" });
      expect(buildSystemPrompt({ companionId: "byte", language: "en", deptKey: "nope" })).toBe(plain);
      expect(buildSystemPrompt({ companionId: "byte", language: "en", deptKey: "" })).toBe(plain);
      expect(buildSystemPrompt({ companionId: "byte", language: "en", deptKey: null })).toBe(plain);
    });
  });

  // 9 Oct: the foundations are a mandate and a skill list — enough to name the topic, not
  // enough to think like the department. The room's role prompts (registry.ts) carry the lens,
  // the metrics and the characteristic failure, and until now only the room read them, so the
  // same Finance answered a Plan question with runway arithmetic and an Ask question without.
  describe("chat speaks with the room's head of department", () => {
    it("carries the room's role prompt for every chat department", () => {
      for (const key of Object.keys(DEPARTMENT_NAMES)) {
        const p = buildSystemPrompt({ companionId: "byte", language: "en", deptKey: key });
        const roomKey = ROOM_KEY_FOR_TEST[key];
        expect(p).toContain(AGENT_DEFS[roomKey].role);
      }
    });

    it("keeps an ordinary turn free of any role prompt", () => {
      const p = buildSystemPrompt({ companionId: "byte", language: "en" });
      expect(p).not.toContain("ROLE: Head of");
    });

    // A department that answers from expertise will fill a gap with a plausible number. The
    // founder asked Finance because they want THEIR number, so a missing one is named, not made up.
    it("tells the department to name what is not on record instead of inventing it", () => {
      const p = buildSystemPrompt({ companionId: "byte", language: "en", deptKey: "fin" });
      expect(p).toMatch(/not on record/i);
      expect(buildSystemPrompt({ companionId: "byte", language: "en" })).not.toMatch(/not on record/i);
    });
  });

  describe("run-task prompt", () => {
    const base = {
      companionId: "nova",
      language: "en",
      context: "A bakery SaaS.",
      taskTitle: "Draft the launch email",
      taskDetail: "",
    };

    it("carries the department's expertise into the deliverable prompt", () => {
      const p = buildRunTaskPrompt({ ...base, deptKey: "mkt" });
      expect(p).toContain(marketingMandate);
      expect(p).toContain("Marketing function");
    });

    it("is unchanged for a legacy task with no department", () => {
      const withNone = buildRunTaskPrompt(base);
      expect(withNone).not.toContain(marketingMandate);
      expect(buildRunTaskPrompt({ ...base, deptKey: "nope" })).toBe(withNone);
    });

    // The department block must not displace the deliverable instructions that follow it —
    // the prompt's whole job is still to produce the artifact.
    it("keeps the deliverable instruction after the department block", () => {
      const p = buildRunTaskPrompt({ ...base, deptKey: "mkt" });
      expect(p.indexOf("Marketing function")).toBeLessThan(p.indexOf("Produce the REAL deliverable"));
      expect(p).toContain("The founder's company:");
    });
  });
});

// Spelled out here rather than imported: if the production map drops or misroutes a key, this
// table is what disagrees with it.
const ROOM_KEY_FOR_TEST: Record<string, keyof typeof AGENT_DEFS> = {
  eng: "engineering", design: "design", mkt: "marketing", sales: "sales",
  support: "support", fin: "finance", ops: "operations", legal: "legal",
};
