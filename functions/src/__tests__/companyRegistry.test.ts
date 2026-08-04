import { AGENT_DEFS, composeAgentSystem } from "../company/registry";
import { ALL_AGENTS, FounderContext, DEPARTMENT_AGENTS } from "../company/types";
import { AGENT_MODEL, SYNTHESIS_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder, one prior product that plateaued at 200 users.",
  stage: "Pre-revenue, 4 months runway, 30 beta users, no pricing page.",
  constraints: ["Cannot hire this quarter.", "Must ship next month."],
  language: "en"
};
const rawRequest = "Should I add team seats or price the single-player product first?";

describe("AGENT_DEFS", () => {
  test("defines exactly the 4 MVP agents", () => {
    expect(Object.keys(AGENT_DEFS).sort()).toEqual([...ALL_AGENTS].sort());
  });

  test("every role prompt is substantial", () => {
    // Guards against a placeholder shipping by accident.
    for (const agent of ALL_AGENTS) {
      expect(AGENT_DEFS[agent].role.length).toBeGreaterThan(400);
    }
  });

  test("no role prompt contains an unreplaced placeholder marker", () => {
    for (const agent of ALL_AGENTS) {
      expect(AGENT_DEFS[agent].role).not.toContain("[...copy spec");
      expect(AGENT_DEFS[agent].role).not.toContain("TODO");
    }
  });

  test("department agents run on the mid tier, judgement roles on the top tier", () => {
    expect(AGENT_DEFS.product.model).toBe(AGENT_MODEL);
    expect(AGENT_DEFS.finance.model).toBe(AGENT_MODEL);
    expect(AGENT_DEFS.chief_of_staff.model).toBe(SYNTHESIS_MODEL);
    expect(AGENT_DEFS.devils_advocate.model).toBe(SYNTHESIS_MODEL);
  });

  test("each role prompt is distinct — no copy-paste between agents", () => {
    const roles = ALL_AGENTS.map((a) => AGENT_DEFS[a].role);
    expect(new Set(roles).size).toBe(roles.length);
  });

  test("department role prompts state what the agent owns", () => {
    expect(AGENT_DEFS.product.role).toContain("YOU OWN");
    expect(AGENT_DEFS.finance.role).toContain("YOU OWN");
  });

  test("department role prompts name their characteristic failure", () => {
    // Spec §3.3/§3.7: the self-awareness clause is what keeps each agent from
    // collapsing into the same voice with different vocabulary.
    expect(AGENT_DEFS.product.role).toContain("CHARACTERISTIC FAILURE");
    expect(AGENT_DEFS.finance.role).toContain("CHARACTERISTIC FAILURE");
  });

  test("the red team is told it is not a department", () => {
    expect(AGENT_DEFS.devils_advocate.role).toContain("You are not a department");
  });

  test("chief_of_staff carries the deployment roster so it cannot convene a missing agent", () => {
    const role = AGENT_DEFS.chief_of_staff.role;
    expect(role).toContain("ROSTER AVAILABLE TO YOU IN THIS DEPLOYMENT");
    expect(role).toContain("product");
    expect(role).toContain("finance");
  });
});

describe("composeAgentSystem", () => {
  test("returns exactly two blocks", () => {
    const blocks = composeAgentSystem({ agent: "product", founder, rawRequest });
    expect(blocks).toHaveLength(2);
  });

  test("only the first block carries the cache breakpoint", () => {
    const blocks = composeAgentSystem({ agent: "product", founder, rawRequest });
    expect(blocks[0].cache_control).toEqual({ type: "ephemeral" });
    expect(blocks[1].cache_control).toBeUndefined();
  });

  test("the cached prefix is byte-identical across agents in the same run", () => {
    const a = composeAgentSystem({ agent: "product", founder, rawRequest });
    const b = composeAgentSystem({ agent: "finance", founder, rawRequest });
    // This is the whole point: same prefix → one cache write, N cache reads.
    expect(a[0].text).toBe(b[0].text);
  });

  test("the prefix is identical for all four agents, not just the two departments", () => {
    const prefixes = ALL_AGENTS.map(
      (agent) => composeAgentSystem({ agent, founder, rawRequest })[0].text
    );
    expect(new Set(prefixes).size).toBe(1);
  });

  test("the role block differs per agent", () => {
    const a = composeAgentSystem({ agent: "product", founder, rawRequest });
    const b = composeAgentSystem({ agent: "finance", founder, rawRequest });
    expect(a[1].text).not.toBe(b[1].text);
    expect(a[1].text).toBe(AGENT_DEFS.product.role.trim());
  });

  test("the router is TOLD about every department it is allowed to convene", () => {
    // The bug this exists for: engineering, design, marketing, sales, support,
    // operations and legal were added to AgentId, to AGENT_DEFS, to
    // ROUTABLE_AGENTS and to the tool's enum — and the chief_of_staff prompt,
    // which is what the router actually reads to decide, still said "No other
    // departments exist yet" and named engineering as a discipline it did NOT
    // have. Every mechanism test passed. The router refused engineering on a
    // build-vs-buy question with "Not a department in this deployment", because
    // that is what we told it.
    //
    // Capability in the code is not capability in the model's belief.
    const role = AGENT_DEFS.chief_of_staff.role;
    for (const dept of DEPARTMENT_AGENTS) {
      expect(role).toMatch(new RegExp(`\\b${dept}\\b`));
    }
  });

  test("the router is never told a department is unavailable", () => {
    // A denial survives adding the department everywhere else, and it is the
    // model, not the code, that acts on it.
    const role = AGENT_DEFS.chief_of_staff.role.toLowerCase();
    for (const denial of [
      "no other departments",
      "do not have",
      "you do not have",
      "not available in this deployment",
      "does not exist"
    ]) {
      expect(role).not.toContain(denial);
    }
  });

  test("no role prompt tells an agent to push back on a department that does not exist", () => {
    // This replaces an MVP-era check that asserted the cut departments were
    // absent. The protection it gave is still worth having, inverted: every
    // department named in a "WHERE YOU PUSH BACK" line must be a real agent, or
    // the instruction addresses nobody. It caught "GTM" — written before
    // Marketing and Sales existed, and ambiguous between them once they did.
    const known = new Set([
      ...DEPARTMENT_AGENTS.map((a) => a.charAt(0).toUpperCase() + a.slice(1)),
      "everyone",
      "the founder",
      "yourself"
    ]);
    for (const agent of ALL_AGENTS) {
      for (const line of AGENT_DEFS[agent].role.split("\n")) {
        const m = /^- On (the founder|everyone|yourself|[A-Za-z]+)/.exec(line.trim());
        if (!m) continue;
        expect(known).toContain(m[1]);
      }
    }
  });
});
