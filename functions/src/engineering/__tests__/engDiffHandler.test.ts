jest.mock("firebase-admin", () => {
  const store = new Map<string, Record<string, unknown>>();
  const doc = jest.fn((path: string) => ({
    path,
    get: jest.fn(async () => ({ exists: store.has(path), data: () => store.get(path) }))
  }));
  const firestore: unknown = jest.fn(() => ({ doc }));
  (firestore as { __store?: unknown }).__store = store;
  return { firestore };
});

jest.mock("../../auth", () => ({ verifyAuth: jest.fn() }));

jest.mock("../engRepo", () => {
  const actual = jest.requireActual("../engRepo");
  return { ...actual, loadGitHubToken: jest.fn() };
});

jest.mock("../engGitHub", () => {
  const actual = jest.requireActual("../engGitHub");
  return { ...actual, compare: jest.fn() };
});

jest.mock("firebase-functions/logger", () => ({
  error: jest.fn(),
  warn: jest.fn(),
  log: jest.fn()
}));

import { handleEngDiff, parseScope } from "../engDiff";
import * as admin from "firebase-admin";
import { verifyAuth } from "../../auth";
import { loadGitHubToken } from "../engRepo";
import { compare, GitHubError } from "../engGitHub";
import { spyOnLogs, callsContainMarker } from "./logLeakTestHelpers";

const UID = "uid_1";
const RUN_ID = "run_1";
const RUN_PATH = `companies/${UID}/engRuns/${RUN_ID}`;
const TOKEN = "github_pat_11SECRET";

type MockRes = { status: jest.Mock; json: jest.Mock };
function makeRes(): MockRes {
  const res: Partial<MockRes> = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res as MockRes;
}
function makeReq(query: Record<string, unknown> = { runId: RUN_ID }) {
  return { method: "GET", headers: { authorization: "Bearer t" }, query } as unknown as Parameters<
    typeof handleEngDiff
  >[0];
}
function body(res: MockRes): Record<string, unknown> {
  return res.json.mock.calls[0]?.[0] ?? {};
}
function store(): Map<string, Record<string, unknown>> {
  return (admin.firestore as unknown as { __store: Map<string, Record<string, unknown>> }).__store;
}
function seedRun(over: Record<string, unknown> = {}) {
  store().set(RUN_PATH, {
    repo: "https://github.com/o/r",
    branch: "codepet/run-run_1",
    baseBranch: "main",
    ...over
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  store().clear();
  process.env.CONNECTOR_ENC_KEY = "enc-key";
  (verifyAuth as jest.Mock).mockResolvedValue({ uid: UID });
  (loadGitHubToken as jest.Mock).mockResolvedValue(TOKEN);
  (compare as jest.Mock).mockResolvedValue({ files: [] });
});
afterEach(() => {
  delete process.env.CONNECTOR_ENC_KEY;
});

describe("parseScope", () => {
  it("defaults to the whole branch, the widest honest answer", () => {
    expect(parseScope(undefined)).toBe("branch");
    expect(parseScope("nonsense")).toBe("branch");
  });

  it("does not silently accept commit, which needs an id this endpoint is not given", () => {
    expect(parseScope("commit")).toBe("branch");
  });
});

describe("handleEngDiff", () => {
  it("401s without a valid token, before any lookup", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngDiff(makeReq(), res as never);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(loadGitHubToken).not.toHaveBeenCalled();
  });

  it("400s a runId that is not a safe path segment, before building a path", async () => {
    const res = makeRes();
    await handleEngDiff(makeReq({ runId: "../other" }), res as never);
    expect(res.status).toHaveBeenCalledWith(400);
  });

  it("404s a run that is not the caller's", async () => {
    store().set(`companies/other/engRuns/${RUN_ID}`, { repo: "x" });
    const res = makeRes();
    await handleEngDiff(makeReq(), res as never);
    expect(res.status).toHaveBeenCalledWith(404);
    expect(compare).not.toHaveBeenCalled();
  });

  it("compares the run's branch against its base", async () => {
    seedRun();
    await handleEngDiff(makeReq(), makeRes() as never);
    const [, owner, repo, base, head] = (compare as jest.Mock).mock.calls[0];
    expect([owner, repo, base, head]).toEqual(["o", "r", "main", "codepet/run-run_1"]);
  });

  it("falls back to the branch diff and SAYS SO when lastTurnBaseSha is absent", async () => {
    // Silently widening shows the founder earlier turns' changes as if they
    // were this turn's — a wrong answer wearing the right label.
    seedRun();
    const res = makeRes();
    await handleEngDiff(makeReq({ runId: RUN_ID, scope: "turn" }), res as never);
    expect(body(res).scopeFellBack).toBe(true);
    expect((compare as jest.Mock).mock.calls[0][3]).toBe("main");
  });

  it("uses lastTurnBaseSha when it exists, and does not claim a fallback", async () => {
    seedRun({ lastTurnBaseSha: "abc123" });
    const res = makeRes();
    await handleEngDiff(makeReq({ runId: RUN_ID, scope: "turn" }), res as never);
    expect((compare as jest.Mock).mock.calls[0][3]).toBe("abc123");
    expect(body(res).scopeFellBack).toBe(false);
  });

  it("never claims a fallback on a branch-scoped request", async () => {
    seedRun();
    const res = makeRes();
    await handleEngDiff(makeReq(), res as never);
    expect(body(res).scopeFellBack).toBe(false);
  });

  it("passes GitHub's payload through parseCompare", async () => {
    seedRun();
    (compare as jest.Mock).mockResolvedValueOnce({
      files: [{ filename: "a.ts", additions: 3, deletions: 1, status: "modified", patch: "@@" }]
    });
    const res = makeRes();
    await handleEngDiff(makeReq(), res as never);
    expect(body(res).additions).toBe(3);
    expect((body(res).files as unknown[])[0]).toMatchObject({ file: "a.ts", path: "a.ts" });
  });

  it("422s a run missing the fields engStartRun writes", async () => {
    seedRun({ branch: undefined });
    const res = makeRes();
    await handleEngDiff(makeReq(), res as never);
    expect(res.status).toHaveBeenCalledWith(422);
    expect(compare).not.toHaveBeenCalled();
  });

  it("409s when GitHub is not connected", async () => {
    seedRun();
    (loadGitHubToken as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngDiff(makeReq(), res as never);
    expect(res.status).toHaveBeenCalledWith(409);
  });

  it("503s without echoing anything from a GitHub failure", async () => {
    const spy = spyOnLogs();
    try {
      seedRun();
      (compare as jest.Mock).mockRejectedValueOnce(new GitHubError("compare", 403));
      const res = makeRes();
      await handleEngDiff(makeReq(), res as never);
      expect(res.status).toHaveBeenCalledWith(503);
      expect(callsContainMarker(spy.allCalls(), TOKEN)).toBe(false);
      expect(JSON.stringify(res.json.mock.calls)).not.toContain(TOKEN);
    } finally {
      spy.restore();
    }
  });
});
