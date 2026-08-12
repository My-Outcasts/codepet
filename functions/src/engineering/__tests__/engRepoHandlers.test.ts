jest.mock("../../auth", () => ({ verifyAuth: jest.fn() }));

jest.mock("../engRepo", () => {
  const actual = jest.requireActual("../engRepo");
  return { ...actual, loadGitHubToken: jest.fn(), writeRepoLink: jest.fn() };
});

jest.mock("../engGitHub", () => {
  const actual = jest.requireActual("../engGitHub");
  return { ...actual, listRepos: jest.fn(), getDefaultBranch: jest.fn() };
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
  handleEngListRepos,
  handleEngLinkRepo
} from "../engRepoHandlers";
import { verifyAuth } from "../../auth";
import { loadGitHubToken, writeRepoLink } from "../engRepo";
import { listRepos, getDefaultBranch, GitHubError } from "../engGitHub";
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
