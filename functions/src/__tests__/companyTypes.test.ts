import {
  ALL_AGENTS,
  DEPARTMENT_AGENTS,
  AGENT_DEPARTMENT_KEY,
  isAgentId
} from "../company/types";

describe("agent roster", () => {
  test("the roster is nine departments plus two agents that are not departments", () => {
    expect(ALL_AGENTS).toEqual([
      "chief_of_staff",
      "devils_advocate",
      "product",
      "finance",
      "engineering",
      "design",
      "marketing",
      "sales",
      "support",
      "operations",
      "legal"
    ]);
  });

  test("every department the client can render is a department that can hold a position", () => {
    // The nine keys here are DepartmentCatalog's on the client. A department the
    // UI can draw but the backend cannot convene would be a dead chip.
    expect(DEPARTMENT_AGENTS).toEqual([
      "product",
      "finance",
      "engineering",
      "design",
      "marketing",
      "sales",
      "support",
      "operations",
      "legal"
    ]);
    expect(DEPARTMENT_AGENTS).not.toContain("chief_of_staff");
    expect(DEPARTMENT_AGENTS).not.toContain("devils_advocate");
  });

  test("chief_of_staff and devils_advocate map to no department key", () => {
    // Not cosmetic: the client renders a null key with its own identity, and the
    // contract forbids giving the red team a department colour.
    expect(AGENT_DEPARTMENT_KEY.chief_of_staff).toBeNull();
    expect(AGENT_DEPARTMENT_KEY.devils_advocate).toBeNull();
    for (const dept of DEPARTMENT_AGENTS) {
      expect(AGENT_DEPARTMENT_KEY[dept]).toBeTruthy();
    }
  });

  test("department keys are the client's abbreviations, not the agent ids", () => {
    // These four differ, and a mismatch renders a column with no name or accent.
    expect(AGENT_DEPARTMENT_KEY.finance).toBe("fin");
    expect(AGENT_DEPARTMENT_KEY.engineering).toBe("eng");
    expect(AGENT_DEPARTMENT_KEY.marketing).toBe("mkt");
    expect(AGENT_DEPARTMENT_KEY.operations).toBe("ops");
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
