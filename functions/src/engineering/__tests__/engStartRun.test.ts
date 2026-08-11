import { buildSessionParams } from "../engStartRun";

const repo = {
  url: "https://github.com/acme/widget",
  owner: "acme",
  repo: "widget",
  defaultBranch: "main",
  token: "github_pat_secret"
};

describe("buildSessionParams", () => {
  it("mounts the repo at the shared mount path", () => {
    const p = buildSessionParams({ agentId: "agent_1", agentVersion: 3, environmentId: "env_1", repo, credits: 40, ask: "add checkout", brief: "" });
    expect(p.resources).toEqual([
      {
        type: "github_repository",
        url: "https://github.com/acme/widget",
        authorization_token: "github_pat_secret",
        mount_path: "/workspace/repo",
        checkout: { type: "branch", name: "main" }
      }
    ]);
  });

  it("pins the agent version, so a mid-run agent update cannot change behaviour", () => {
    const p = buildSessionParams({ agentId: "agent_1", agentVersion: 3, environmentId: "env_1", repo, credits: 40, ask: "x", brief: "" });
    expect(p.agent).toMatchObject({ type: "agent_with_overrides", id: "agent_1", version: 3 });
  });

  it("attaches a budget derived from the founder's credits", () => {
    const p = buildSessionParams({ agentId: "a", agentVersion: 1, environmentId: "e", repo, credits: 10, ask: "x", brief: "" });
    expect(p.budget).toEqual({ type: "limit", max_list_cost: { amount: "50", currency: "USD" } });
  });

  it("puts the company brief in the system override, never in the user message", () => {
    const p = buildSessionParams({ agentId: "a", agentVersion: 1, environmentId: "e", repo, credits: 5, ask: "add checkout", brief: "Acme sells widgets." });
    expect(p.agent.system).toContain("Acme sells widgets.");
    const firstEvent = p.initial_events[0] as { content: Array<{ text: string }> };
    expect(firstEvent.content[0].text).toBe("add checkout");
    expect(firstEvent.content[0].text).not.toContain("Acme sells widgets.");
  });

  it("never puts the token anywhere but the repo resource", () => {
    const p = buildSessionParams({ agentId: "a", agentVersion: 1, environmentId: "e", repo, credits: 5, ask: "x", brief: "y" });
    const withoutResources = JSON.stringify({ ...p, resources: [] });
    expect(withoutResources).not.toContain("github_pat_secret");
  });

  it("starts the run in the same call, so the session never sits idle", () => {
    const p = buildSessionParams({ agentId: "a", agentVersion: 1, environmentId: "e", repo, credits: 5, ask: "add checkout", brief: "" });
    expect(p.initial_events).toHaveLength(1);
    expect(p.initial_events[0].type).toBe("user.message");
  });
});
