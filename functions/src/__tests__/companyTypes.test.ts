import {
  ALL_AGENTS,
  DEPARTMENT_AGENTS,
  AGENT_DEPARTMENT_KEY,
  isAgentId
} from "../company/types";

describe("agent roster", () => {
  test("MVP roster is exactly 4 agents", () => {
    expect(ALL_AGENTS).toEqual([
      "chief_of_staff",
      "devils_advocate",
      "product",
      "finance"
    ]);
  });

  test("only product and finance produce positions", () => {
    expect(DEPARTMENT_AGENTS).toEqual(["product", "finance"]);
  });

  test("cut agents are not in the roster", () => {
    for (const cut of ["engineering", "design", "gtm", "legal", "security"]) {
      expect(ALL_AGENTS).not.toContain(cut);
    }
  });

  test("isAgentId accepts roster members and rejects everything else", () => {
    expect(isAgentId("product")).toBe(true);
    expect(isAgentId("finance")).toBe(true);
    expect(isAgentId("gtm")).toBe(false);
    expect(isAgentId("")).toBe(false);
    expect(isAgentId("PRODUCT")).toBe(false);
    expect(isAgentId(null)).toBe(false);
    expect(isAgentId(42)).toBe(false);
  });

  test("department agents map to client-side department keys", () => {
    // finance maps onto the existing Department.all entry `fin`.
    expect(AGENT_DEPARTMENT_KEY.finance).toBe("fin");
    // product has no entry in Department.all yet — the UI engineer adds it.
    expect(AGENT_DEPARTMENT_KEY.product).toBe("product");
    // The red team is explicitly not a department (spec §3.8).
    expect(AGENT_DEPARTMENT_KEY.devils_advocate).toBeNull();
    // Chief of staff is rendered as the founder's companion pet.
    expect(AGENT_DEPARTMENT_KEY.chief_of_staff).toBeNull();
  });

  test("every agent has a department-key entry", () => {
    for (const agent of ALL_AGENTS) {
      expect(AGENT_DEPARTMENT_KEY).toHaveProperty(agent);
    }
  });
});
