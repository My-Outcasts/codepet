jest.mock("firebase-admin", () => {
  const store = new Map<string, Record<string, unknown>>();
  const set = jest.fn(async () => undefined);
  const get = jest.fn();
  const doc = jest.fn((path: string) => ({
    path,
    set,
    get: jest.fn(async () => ({ exists: store.has(path), data: () => store.get(path) }))
  }));
  const firestore: unknown = jest.fn(() => ({ doc }));
  (firestore as { __store?: unknown; __set?: unknown; __get?: unknown }).__store = store;
  (firestore as { __set?: unknown }).__set = set;
  (firestore as { __get?: unknown }).__get = get;
  return { firestore };
});

jest.mock("../../auth", () => ({ verifyAuth: jest.fn() }));

jest.mock("../engRepo", () => {
  const actual = jest.requireActual("../engRepo");
  return { ...actual, loadGitHubToken: jest.fn() };
});

jest.mock("../engGitHub", () => {
  const actual = jest.requireActual("../engGitHub");
  return { ...actual, openPR: jest.fn(), latestPreview: jest.fn(), hasDeployTarget: jest.fn() };
});

jest.mock("firebase-functions/logger", () => ({
  error: jest.fn(),
  warn: jest.fn(),
  log: jest.fn()
}));

import { handleEngShip, handleEngPreview } from "../engShip";
import * as admin from "firebase-admin";
import { verifyAuth } from "../../auth";
import { loadGitHubToken } from "../engRepo";
import { openPR, latestPreview, hasDeployTarget, GitHubError } from "../engGitHub";
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

function makeReq(body: unknown = { runId: RUN_ID }, method = "POST") {
  return {
    method,
    headers: { authorization: "Bearer t" },
    body,
    query: body
  } as unknown as Parameters<typeof handleEngShip>[0];
}

function body(res: MockRes): Record<string, unknown> {
  return res.json.mock.calls[0]?.[0] ?? {};
}

function store(): Map<string, Record<string, unknown>> {
  return (admin.firestore as unknown as { __store: Map<string, Record<string, unknown>> }).__store;
}

function setSpy(): jest.Mock {
  return (admin.firestore as unknown as { __set: jest.Mock }).__set;
}

function seedRun(over: Record<string, unknown> = {}, path = RUN_PATH): void {
  store().set(path, {
    repo: "https://github.com/o/r",
    branch: "codepet/run-run_1",
    baseBranch: "main",
    ask: "add stripe checkout",
    ...over
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  store().clear();
  process.env.CONNECTOR_ENC_KEY = "enc-key";
  (verifyAuth as jest.Mock).mockResolvedValue({ uid: UID });
  (loadGitHubToken as jest.Mock).mockResolvedValue(TOKEN);
});

afterEach(() => {
  delete process.env.CONNECTOR_ENC_KEY;
});

describe("handleEngShip", () => {
  it("405s a non-POST", async () => {
    const res = makeRes();
    await handleEngShip(makeReq({ runId: RUN_ID }, "GET"), res as never);
    expect(res.status).toHaveBeenCalledWith(405);
  });

  it("401s without a valid token, before reading anything", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngShip(makeReq(), res as never);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(loadGitHubToken).not.toHaveBeenCalled();
  });

  it("400s a runId that is not a safe path segment, before building a path", async () => {
    const res = makeRes();
    await handleEngShip(makeReq({ runId: "../other" }), res as never);
    expect(res.status).toHaveBeenCalledWith(400);
  });

  it("404s a run that is not the caller's", async () => {
    // The document is addressed under the caller's own uid, so another
    // founder's runId simply does not resolve — there is no ownership check
    // to forget, because the path cannot name someone else's run.
    seedRun({}, `companies/other_uid/engRuns/${RUN_ID}`);
    const res = makeRes();
    await handleEngShip(makeReq(), res as never);
    expect(res.status).toHaveBeenCalledWith(404);
    expect(openPR).not.toHaveBeenCalled();
  });

  it("opens a PR from the run's branch onto its base", async () => {
    seedRun();
    (openPR as jest.Mock).mockResolvedValueOnce({ number: 7, url: "https://github.com/o/r/pull/7" });
    const res = makeRes();
    await handleEngShip(makeReq(), res as never);
    const [, owner, repo, head, base] = (openPR as jest.Mock).mock.calls[0];
    expect([owner, repo, head, base]).toEqual(["o", "r", "codepet/run-run_1", "main"]);
    expect(body(res)).toEqual({ prNumber: 7, prUrl: "https://github.com/o/r/pull/7" });
  });

  it("does not merge — it only ever opens a pull request", async () => {
    // "Ship this" is the label; the action is a PR. Merging a founder's
    // default branch from a button, on a diff they may have skim-read, is not
    // something to build before there is a review pane people trust.
    //
    // Asserted at the capability level, not by grepping the write for
    // "merge": the first version of this test did that and matched
    // Firestore's own `{ merge: true }` set option, which has nothing to do
    // with git. The real guarantee is that nothing reachable from here CAN
    // merge — engGitHub exposes no such call, so no future edit to this
    // handler can quietly start merging without adding one.
    const gh = jest.requireActual("../engGitHub") as Record<string, unknown>;
    const merging = Object.keys(gh).filter((k) => /merge/i.test(k));
    expect(merging).toEqual([]);

    seedRun();
    (openPR as jest.Mock).mockResolvedValueOnce({ number: 7, url: "u" });
    const res = makeRes();
    await handleEngShip(makeReq(), res as never);

    // And what the founder is told is a PR, not a completed deploy.
    expect(Object.keys(body(res)).sort()).toEqual(["prNumber", "prUrl"]);
  });

  it("does not open a second PR for a run that already has one", async () => {
    // GitHub would reject the duplicate with a 422 the founder cannot act on,
    // and a second tap on a slow button must not read as a failure.
    seedRun({ prNumber: 7, prUrl: "https://github.com/o/r/pull/7" });
    const res = makeRes();
    await handleEngShip(makeReq(), res as never);
    expect(openPR).not.toHaveBeenCalled();
    expect(body(res)).toEqual({ prNumber: 7, prUrl: "https://github.com/o/r/pull/7" });
  });

  it("hands back the PR when it was opened but recording it failed", async () => {
    // The PR exists. A bare 503 hides a pull request the founder already has,
    // and the next Ship would try to open it again.
    seedRun();
    (openPR as jest.Mock).mockResolvedValueOnce({ number: 9, url: "https://github.com/o/r/pull/9" });
    setSpy().mockRejectedValueOnce(new Error("firestore down"));
    const res = makeRes();
    await handleEngShip(makeReq(), res as never);
    expect(res.status).toHaveBeenCalledWith(503);
    expect(body(res).prNumber).toBe(9);
  });

  it("422s a run missing the fields engStartRun writes, without calling GitHub", async () => {
    seedRun({ branch: undefined });
    const res = makeRes();
    await handleEngShip(makeReq(), res as never);
    expect(res.status).toHaveBeenCalledWith(422);
    expect(openPR).not.toHaveBeenCalled();
  });

  it("never echoes a GitHub error", async () => {
    const spy = spyOnLogs();
    try {
      seedRun();
      (openPR as jest.Mock).mockRejectedValueOnce(new GitHubError("openPR", 403));
      const res = makeRes();
      await handleEngShip(makeReq(), res as never);
      expect(res.status).toHaveBeenCalledWith(503);
      expect(callsContainMarker(spy.allCalls(), TOKEN)).toBe(false);
    } finally {
      spy.restore();
    }
  });
});

describe("handleEngPreview", () => {
  it("returns the URL when a successful preview exists", async () => {
    seedRun();
    (latestPreview as jest.Mock).mockResolvedValueOnce({
      url: "https://p.vercel.app",
      state: "success"
    });
    const res = makeRes();
    await handleEngPreview(makeReq({ runId: RUN_ID }, "GET"), res as never);
    expect(body(res)).toEqual({ url: "https://p.vercel.app", state: "success" });
    // No need to ask whether a deploy target exists — we just saw one work.
    expect(hasDeployTarget).not.toHaveBeenCalled();
  });

  it("reports no_deploy_target when nothing has ever deployed this branch", async () => {
    // "Install Vercel" and "wait a moment" are different things to tell a
    // founder, and a single null cannot tell them apart.
    seedRun();
    (latestPreview as jest.Mock).mockResolvedValueOnce(null);
    (hasDeployTarget as jest.Mock).mockResolvedValueOnce(false);
    const res = makeRes();
    await handleEngPreview(makeReq({ runId: RUN_ID }, "GET"), res as never);
    expect(body(res)).toEqual({ url: null, reason: "no_deploy_target" });
  });

  it("reports pending when a deployment exists but has not succeeded", async () => {
    seedRun();
    (latestPreview as jest.Mock).mockResolvedValueOnce(null);
    (hasDeployTarget as jest.Mock).mockResolvedValueOnce(true);
    const res = makeRes();
    await handleEngPreview(makeReq({ runId: RUN_ID }, "GET"), res as never);
    expect(body(res)).toEqual({ url: null, reason: "pending" });
  });

  it("never returns a URL it did not get from a successful deployment", async () => {
    seedRun();
    (latestPreview as jest.Mock).mockResolvedValueOnce(null);
    (hasDeployTarget as jest.Mock).mockResolvedValueOnce(true);
    const res = makeRes();
    await handleEngPreview(makeReq({ runId: RUN_ID }, "GET"), res as never);
    expect(body(res).url).toBeNull();
  });

  it("503s on a GitHub fault rather than reporting no preview", async () => {
    // Reporting "no preview" for an API outage would tell the founder to go
    // install something they have already installed.
    seedRun();
    (latestPreview as jest.Mock).mockRejectedValueOnce(new GitHubError("listDeployments", 500));
    const res = makeRes();
    await handleEngPreview(makeReq({ runId: RUN_ID }, "GET"), res as never);
    expect(res.status).toHaveBeenCalledWith(503);
  });
});
