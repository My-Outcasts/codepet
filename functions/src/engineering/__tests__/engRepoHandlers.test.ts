jest.mock("firebase-admin", () => {
  const get = jest.fn(async () => ({ data: () => ({ name: "Acme", brief: "we sell widgets" }) }));
  const doc = jest.fn(() => ({ get }));
  const firestore: unknown = jest.fn(() => ({ doc }));
  (firestore as { __get?: unknown }).__get = get;
  return { firestore };
});

jest.mock("../../auth", () => ({ verifyAuth: jest.fn() }));

jest.mock("../engRepo", () => {
  const actual = jest.requireActual("../engRepo");
  return { ...actual, loadGitHubToken: jest.fn(), writeRepoLink: jest.fn() };
});

jest.mock("../engGitHub", () => {
  const actual = jest.requireActual("../engGitHub");
  return { ...actual, listRepos: jest.fn(), getDefaultBranch: jest.fn(), createRepo: jest.fn() };
});

// The real module's exports are non-configurable getters (a bundling detail),
// so `jest.spyOn` cannot redefine them — the shared log spy needs plain
// `jest.fn()`s here, same as every other handler suite in this directory.
jest.mock("firebase-functions/logger", () => ({
  error: jest.fn(),
  warn: jest.fn(),
  log: jest.fn()
}));

import {
  parseFullName,
  repoSlug,
  vercelSetupUrl,
  handleEngListRepos,
  handleEngLinkRepo,
  handleEngCreateRepo
} from "../engRepoHandlers";
import { verifyAuth } from "../../auth";
import { loadGitHubToken, writeRepoLink } from "../engRepo";
import { listRepos, getDefaultBranch, createRepo, GitHubError } from "../engGitHub";
import { spyOnLogs, callsContainMarker } from "./logLeakTestHelpers";

type MockRes = { status: jest.Mock; json: jest.Mock };

function makeRes(): MockRes {
  const res: Partial<MockRes> = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res as MockRes;
}

function makeReq(body: unknown = {}, method = "POST") {
  return { method, headers: { authorization: "Bearer t" }, body } as unknown as Parameters<
    typeof handleEngLinkRepo
  >[0];
}

function body(res: MockRes): Record<string, unknown> {
  return res.json.mock.calls[0]?.[0] ?? {};
}

const TOKEN = "github_pat_11SECRET";

beforeEach(() => {
  jest.clearAllMocks();
  process.env.CONNECTOR_ENC_KEY = "enc-key";
  (verifyAuth as jest.Mock).mockResolvedValue({ uid: "uid_1" });
  (loadGitHubToken as jest.Mock).mockResolvedValue(TOKEN);
});

afterEach(() => {
  delete process.env.CONNECTOR_ENC_KEY;
});

describe("parseFullName", () => {
  it("accepts owner/repo", () => {
    expect(parseFullName("My-Outcasts/codepet")).toEqual({
      owner: "My-Outcasts",
      repo: "codepet"
    });
  });

  it("rejects a traversal attempt before it reaches a GitHub path", () => {
    // Both halves are interpolated into /repos/{owner}/{repo}.
    expect(parseFullName("../../evil")).toBeNull();
    expect(parseFullName("a/../b")).toBeNull();
    expect(parseFullName("owner/repo/extra")).toBeNull();
  });

  it("rejects an empty or non-string value", () => {
    expect(parseFullName("")).toBeNull();
    expect(parseFullName(undefined)).toBeNull();
    expect(parseFullName(42)).toBeNull();
  });

  it("rejects a name with whitespace, which would corrupt the URL", () => {
    expect(parseFullName("owner/ repo")).toBeNull();
    expect(parseFullName("own er/repo")).toBeNull();
  });
});

describe("handleEngListRepos", () => {
  it("401s without a valid token, before touching the connector", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngListRepos(makeReq({}, "GET"), res as never);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(loadGitHubToken).not.toHaveBeenCalled();
  });

  it("409s github_not_connected rather than showing an empty repo list", async () => {
    // An empty list reads as "you have no repos" — a dead end. The founder
    // needs to be sent to the connect flow instead.
    (loadGitHubToken as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngListRepos(makeReq({}, "GET"), res as never);
    expect(res.status).toHaveBeenCalledWith(409);
    expect(body(res).error).toBe("github_not_connected");
    expect(listRepos).not.toHaveBeenCalled();
  });

  it("returns the repos", async () => {
    (listRepos as jest.Mock).mockResolvedValueOnce([{ fullName: "o/r" }]);
    const res = makeRes();
    await handleEngListRepos(makeReq({}, "GET"), res as never);
    expect(res.status).toHaveBeenCalledWith(200);
    expect(body(res).repos).toEqual([{ fullName: "o/r" }]);
  });

  it("503s on a GitHub fault without echoing anything from it", async () => {
    const spy = spyOnLogs();
    try {
      (listRepos as jest.Mock).mockRejectedValueOnce(
        Object.assign(new Error(`forbidden for ${TOKEN}`), { status: 403 })
      );
      const res = makeRes();
      await handleEngListRepos(makeReq({}, "GET"), res as never);
      expect(res.status).toHaveBeenCalledWith(503);
      expect(callsContainMarker(spy.allCalls(), TOKEN)).toBe(false);
      expect(JSON.stringify(res.json.mock.calls)).not.toContain(TOKEN);
    } finally {
      spy.restore();
    }
  });
});

describe("handleEngLinkRepo", () => {
  it("405s a non-POST", async () => {
    const res = makeRes();
    await handleEngLinkRepo(makeReq({}, "GET"), res as never);
    expect(res.status).toHaveBeenCalledWith(405);
  });

  it("400s a fullName that is not owner/repo, before any GitHub call", async () => {
    const res = makeRes();
    await handleEngLinkRepo(makeReq({ fullName: "../../evil" }), res as never);
    expect(res.status).toHaveBeenCalledWith(400);
    expect(getDefaultBranch).not.toHaveBeenCalled();
  });

  it("refuses to link a repo whose default branch GitHub does not report", async () => {
    // loadRepo fails closed on a blank branch, so a half-written link is
    // indistinguishable from no link: the founder would be told to connect a
    // repo having just connected one.
    (getDefaultBranch as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngLinkRepo(makeReq({ fullName: "o/r" }), res as never);
    expect(res.status).toHaveBeenCalledWith(422);
    expect(writeRepoLink).not.toHaveBeenCalled();
  });

  it("writes the link with the branch GitHub actually reported, not a guess", async () => {
    // A repo whose real default is `master` would, under a guessed `main`,
    // mount a branch that does not exist and die inside a paid run.
    (getDefaultBranch as jest.Mock).mockResolvedValueOnce("master");
    const res = makeRes();
    await handleEngLinkRepo(makeReq({ fullName: "o/r" }), res as never);
    expect(writeRepoLink).toHaveBeenCalledWith("uid_1", "https://github.com/o/r", "master");
    expect(body(res)).toEqual({ url: "https://github.com/o/r", defaultBranch: "master" });
  });

  it("503s and does not claim success when the link write fails", async () => {
    (getDefaultBranch as jest.Mock).mockResolvedValueOnce("main");
    (writeRepoLink as jest.Mock).mockRejectedValueOnce(new Error("firestore down"));
    const res = makeRes();
    await handleEngLinkRepo(makeReq({ fullName: "o/r" }), res as never);
    expect(res.status).toHaveBeenCalledWith(503);
    expect(res.status).not.toHaveBeenCalledWith(200);
  });

  it("409s when GitHub is not connected, before asking GitHub anything", async () => {
    (loadGitHubToken as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngLinkRepo(makeReq({ fullName: "o/r" }), res as never);
    expect(res.status).toHaveBeenCalledWith(409);
    expect(getDefaultBranch).not.toHaveBeenCalled();
  });

  it("500s misconfigured when the encryption key is absent, and says which", async () => {
    delete process.env.CONNECTOR_ENC_KEY;
    const res = makeRes();
    await handleEngLinkRepo(makeReq({ fullName: "o/r" }), res as never);
    expect(res.status).toHaveBeenCalledWith(500);
    expect(body(res).detail).toContain("CONNECTOR_ENC_KEY");
  });

  it("never echoes a GitHub error body", async () => {
    const spy = spyOnLogs();
    try {
      (getDefaultBranch as jest.Mock).mockRejectedValueOnce(new GitHubError("getDefaultBranch", 403));
      const res = makeRes();
      await handleEngLinkRepo(makeReq({ fullName: "o/r" }), res as never);
      expect(res.status).toHaveBeenCalledWith(503);
      expect(callsContainMarker(spy.allCalls(), TOKEN)).toBe(false);
    } finally {
      spy.restore();
    }
  });
});

describe("repoSlug", () => {
  it("turns a company name into something GitHub accepts", () => {
    expect(repoSlug("Acme Widgets")).toBe("acme-widgets");
  });

  it("keeps an accented name readable rather than deleting the letter", () => {
    // "Café" must not become "caf".
    expect(repoSlug("Mona's Café")).toBe("mona-s-cafe");
  });

  it("never emits a character GitHub rejects", () => {
    for (const name of ["Mona's Café ☕", "a/b", "  spaced  ", "emoji 🚀 co", "sym#bol$"]) {
      expect(repoSlug(name)).toMatch(/^[A-Za-z0-9._-]+$/);
    }
  });

  it("never starts or ends with a dash or dot", () => {
    // A leading dot is how a repo ends up looking hidden.
    expect(repoSlug("  -weird-  ")).toBe("weird");
    expect(repoSlug(".hidden.")).toBe("hidden");
  });

  it("falls back to a usable name when nothing survives", () => {
    // An all-emoji company name is a real thing, and POSTing "" 422s with
    // nothing the founder can act on.
    expect(repoSlug("🚀🚀🚀")).toBe("codepet-project");
    expect(repoSlug("")).toBe("codepet-project");
    expect(repoSlug(undefined)).toBe("codepet-project");
  });

  it("bounds the length", () => {
    expect(repoSlug("x".repeat(300)).length).toBeLessThanOrEqual(90);
  });
});

describe("vercelSetupUrl", () => {
  it("points at the import flow for that specific repo", () => {
    expect(vercelSetupUrl("o", "r")).toBe("https://vercel.com/new/git/github/o/r");
  });
});

describe("handleEngCreateRepo", () => {
  const createdRepo = {
    fullName: "o/acme",
    url: "https://github.com/o/acme",
    defaultBranch: "main",
    isPrivate: true,
    pushedAt: "2026-08-12T00:00:00Z"
  };

  it("creates a private repo with an initial commit", async () => {
    // auto_init is load-bearing, not tidiness: a repo with no commits has no
    // default branch, and loadRepo fails closed on a blank one — so the link
    // we write next would resolve to "connect a repo" immediately.
    (createRepo as jest.Mock).mockResolvedValueOnce(createdRepo);
    await handleEngCreateRepo(makeReq({}), makeRes() as never);
    // The private/auto_init flags live in engGitHub.createRepo, which has its
    // own tests; what this asserts is that this handler goes through it.
    expect(createRepo).toHaveBeenCalledTimes(1);
  });

  it("derives the repo name from the company and never sends an invalid one", async () => {
    (createRepo as jest.Mock).mockResolvedValueOnce(createdRepo);
    await handleEngCreateRepo(makeReq({}), makeRes() as never);
    const [, name] = (createRepo as jest.Mock).mock.calls[0];
    expect(name).toMatch(/^[A-Za-z0-9._-]+$/);
    expect(name).toBe("acme");
  });

  it("links the new repo and returns the Vercel setup link", async () => {
    (createRepo as jest.Mock).mockResolvedValueOnce(createdRepo);
    const res = makeRes();
    await handleEngCreateRepo(makeReq({}), res as never);
    expect(writeRepoLink).toHaveBeenCalledWith("uid_1", createdRepo.url, "main");
    expect(body(res).vercelSetupUrl).toBe("https://vercel.com/new/git/github/o/acme");
  });

  it("hands back the repo URL when creation succeeded but the link write failed", async () => {
    // The repo EXISTS on GitHub now. A bare 503 leaves the founder to press
    // "Create one for me" again and end up with a second empty repo.
    (createRepo as jest.Mock).mockResolvedValueOnce(createdRepo);
    (writeRepoLink as jest.Mock).mockRejectedValueOnce(new Error("firestore down"));
    const res = makeRes();
    await handleEngCreateRepo(makeReq({}), res as never);
    expect(res.status).toHaveBeenCalledWith(503);
    expect(body(res).createdRepoUrl).toBe(createdRepo.url);
  });

  it("still creates a repo when the company document cannot be read", async () => {
    // Losing the founder's company name is worth far less than losing the run.
    const admin = require("firebase-admin");
    (admin.firestore as unknown as { __get: jest.Mock }).__get.mockRejectedValueOnce(
      new Error("firestore down")
    );
    (createRepo as jest.Mock).mockResolvedValueOnce(createdRepo);
    const res = makeRes();
    await handleEngCreateRepo(makeReq({}), res as never);
    expect(res.status).toHaveBeenCalledWith(200);
    expect((createRepo as jest.Mock).mock.calls[0][1]).toBe("codepet-project");
  });

  it("409s when GitHub is not connected, before creating anything", async () => {
    (loadGitHubToken as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngCreateRepo(makeReq({}), res as never);
    expect(res.status).toHaveBeenCalledWith(409);
    expect(createRepo).not.toHaveBeenCalled();
  });

  it("405s a non-POST", async () => {
    const res = makeRes();
    await handleEngCreateRepo(makeReq({}, "GET"), res as never);
    expect(res.status).toHaveBeenCalledWith(405);
  });
});
