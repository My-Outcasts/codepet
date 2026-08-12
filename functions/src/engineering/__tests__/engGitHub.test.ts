import {
  listRepos,
  createRepo,
  getDefaultBranch,
  openPR,
  latestPreview,
  hasDeployTarget,
  GitHubError
} from "../engGitHub";

const TOKEN = "github_pat_11SECRETSECRET";

type Reply = { status: number; body: unknown };

/**
 * Queues replies in call order and records every request.
 *
 * A queue rather than a URL→reply map on purpose: `latestPreview` makes two
 * different calls and the ORDER matters, so a map would let a wrong-order
 * implementation pass.
 */
function stubFetch(replies: Reply[]) {
  const calls: { url: string; init: RequestInit }[] = [];
  const queue = [...replies];
  (globalThis as { fetch: unknown }).fetch = jest.fn(async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    const reply = queue.shift() ?? { status: 404, body: {} };
    return {
      ok: reply.status >= 200 && reply.status < 300,
      status: reply.status,
      json: async () => reply.body,
      text: async () => JSON.stringify(reply.body)
    };
  });
  return calls;
}

const realFetch = globalThis.fetch;
afterEach(() => {
  (globalThis as { fetch: unknown }).fetch = realFetch;
});

function repoPayload(over: Record<string, unknown> = {}) {
  return {
    full_name: "owner/repo",
    html_url: "https://github.com/owner/repo",
    default_branch: "main",
    private: true,
    pushed_at: "2026-08-12T00:00:00Z",
    ...over
  };
}

describe("the token never escapes", () => {
  it("is not in the thrown error when GitHub rejects the call", async () => {
    // GitHub's 403 body quotes the request that produced it, and the request
    // carries the token in its Authorization header.
    stubFetch([{ status: 403, body: { message: `forbidden for token ${TOKEN}` } }]);
    const err = await listRepos(TOKEN).catch((e) => e);
    expect(err).toBeInstanceOf(GitHubError);
    expect(JSON.stringify({ m: err.message, s: err.stack })).not.toContain(TOKEN);
  });

  it("is sent as a header, never in the URL where it would land in logs", async () => {
    const calls = stubFetch([{ status: 200, body: [] }]);
    await listRepos(TOKEN);
    expect(calls[0].url).not.toContain(TOKEN);
    expect((calls[0].init.headers as Record<string, string>).Authorization).toContain(TOKEN);
  });
});

describe("listRepos", () => {
  it("returns the repos GitHub reports", async () => {
    stubFetch([{ status: 200, body: [repoPayload()] }]);
    const repos = await listRepos(TOKEN);
    expect(repos).toEqual([
      {
        fullName: "owner/repo",
        url: "https://github.com/owner/repo",
        defaultBranch: "main",
        isPrivate: true,
        pushedAt: "2026-08-12T00:00:00Z"
      }
    ]);
  });

  it("asks for push-capable repos, newest first", async () => {
    // A read-only repo would produce a run that does all the work and fails at
    // the push — the most expensive possible way to find out.
    const calls = stubFetch([{ status: 200, body: [] }]);
    await listRepos(TOKEN);
    expect(calls[0].url).toContain("affiliation=owner,collaborator,organization_member");
    expect(calls[0].url).toContain("sort=pushed");
  });

  it("drops a repo with no default branch rather than offering an unusable choice", async () => {
    // loadRepo fails closed without one, so linking it would produce
    // "connect a repo" the moment it was written.
    stubFetch([{ status: 200, body: [repoPayload(), repoPayload({ default_branch: "" })] }]);
    expect(await listRepos(TOKEN)).toHaveLength(1);
  });

  it("returns an empty list, not a crash, when GitHub sends something unexpected", async () => {
    stubFetch([{ status: 200, body: { not: "an array" } }]);
    expect(await listRepos(TOKEN)).toEqual([]);
  });
});

describe("createRepo", () => {
  it("creates a private repo with an initial commit", async () => {
    // auto_init is load-bearing: a repo with no commits has no default branch.
    const calls = stubFetch([{ status: 201, body: repoPayload() }]);
    await createRepo(TOKEN, "acme", "built by Codepet");
    const body = JSON.parse(calls[0].init.body as string);
    expect(body.private).toBe(true);
    expect(body.auto_init).toBe(true);
  });

  it("throws rather than returning a repo with no default branch", async () => {
    stubFetch([{ status: 201, body: repoPayload({ default_branch: "" }) }]);
    await expect(createRepo(TOKEN, "acme", "")).rejects.toBeInstanceOf(GitHubError);
  });
});

describe("getDefaultBranch", () => {
  it("returns the branch GitHub reports", async () => {
    stubFetch([{ status: 200, body: { default_branch: "master" } }]);
    expect(await getDefaultBranch(TOKEN, "o", "r")).toBe("master");
  });

  it("returns null rather than guessing main", async () => {
    // Guessing is what mounts a branch that does not exist and dies inside a
    // paid run with an obscure git error.
    stubFetch([{ status: 200, body: {} }]);
    expect(await getDefaultBranch(TOKEN, "o", "r")).toBeNull();
  });
});

describe("openPR", () => {
  it("returns the number and URL", async () => {
    stubFetch([{ status: 201, body: { number: 7, html_url: "https://github.com/o/r/pull/7" } }]);
    expect(await openPR(TOKEN, "o", "r", "head", "main", "t", "b")).toEqual({
      number: 7,
      url: "https://github.com/o/r/pull/7"
    });
  });

  it("throws when the response carries no PR number", async () => {
    stubFetch([{ status: 201, body: {} }]);
    await expect(openPR(TOKEN, "o", "r", "h", "m", "t", "b")).rejects.toBeInstanceOf(GitHubError);
  });
});

describe("latestPreview", () => {
  it("returns null when the repo has no Preview deployments at all", async () => {
    stubFetch([{ status: 200, body: [] }]);
    expect(await latestPreview(TOKEN, "o", "r", "sha")).toBeNull();
  });

  it("reads statuses as a second call, which is what the API actually requires", async () => {
    // Deployments and their statuses are separate resources — a status is not
    // nested in the deployment object.
    const calls = stubFetch([
      { status: 200, body: [{ id: 1 }] },
      { status: 200, body: [{ state: "success", environment_url: "https://p.vercel.app" }] }
    ]);
    expect(await latestPreview(TOKEN, "o", "r", "sha")).toEqual({
      url: "https://p.vercel.app",
      state: "success"
    });
    expect(calls).toHaveLength(2);
    expect(calls[0].url).toContain("/deployments?sha=sha");
    expect(calls[1].url).toContain("/deployments/1/statuses");
  });

  it("asks only for Preview deployments, so Production is never returned", async () => {
    const calls = stubFetch([{ status: 200, body: [] }]);
    await latestPreview(TOKEN, "o", "r", "sha");
    expect(calls[0].url).toContain("environment=Preview");
  });

  it("skips a failed deployment and returns the older successful one", async () => {
    // A failed redeploy after a good one must not replace a working link with
    // a dead one.
    stubFetch([
      { status: 200, body: [{ id: 2 }, { id: 1 }] },
      { status: 200, body: [{ state: "failure", environment_url: "https://broken" }] },
      { status: 200, body: [{ state: "success", environment_url: "https://works" }] }
    ]);
    expect((await latestPreview(TOKEN, "o", "r", "sha"))?.url).toBe("https://works");
  });

  it("ignores a success with no environment_url", async () => {
    stubFetch([
      { status: 200, body: [{ id: 1 }] },
      { status: 200, body: [{ state: "success" }] }
    ]);
    expect(await latestPreview(TOKEN, "o", "r", "sha")).toBeNull();
  });

  it("returns null while every deployment is still in progress", async () => {
    stubFetch([
      { status: 200, body: [{ id: 1 }] },
      { status: 200, body: [{ state: "in_progress", environment_url: "https://not-ready" }] }
    ]);
    expect(await latestPreview(TOKEN, "o", "r", "sha")).toBeNull();
  });
});

describe("hasDeployTarget", () => {
  it("is false when nothing has ever deployed this ref", async () => {
    // This is what separates "install Vercel" from "wait a moment".
    stubFetch([{ status: 200, body: [] }]);
    expect(await hasDeployTarget(TOKEN, "o", "r", "sha")).toBe(false);
  });

  it("is true for a deployment in any state, including a failed one", async () => {
    stubFetch([{ status: 200, body: [{ id: 1 }] }]);
    expect(await hasDeployTarget(TOKEN, "o", "r", "sha")).toBe(true);
  });

  it("does not filter by environment, so a Production-only setup still counts", async () => {
    const calls = stubFetch([{ status: 200, body: [] }]);
    await hasDeployTarget(TOKEN, "o", "r", "sha");
    expect(calls[0].url).not.toContain("environment=");
  });
});
