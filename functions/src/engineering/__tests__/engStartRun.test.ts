jest.mock("firebase-admin", () => {
  const doc = jest.fn();
  const collection = jest.fn();
  const firestoreFn: unknown = jest.fn(() => ({ doc, collection }));
  (firestoreFn as { FieldValue?: unknown }).FieldValue = {
    serverTimestamp: jest.fn(() => "SERVER_TIMESTAMP")
  };
  return { firestore: firestoreFn };
});

jest.mock("../../auth", () => ({
  verifyAuth: jest.fn()
}));

jest.mock("../engRepo", () => {
  const actual = jest.requireActual("../engRepo");
  return { ...actual, loadRepo: jest.fn() };
});

jest.mock("../engClient", () => {
  const actual = jest.requireActual("../engClient");
  return { ...actual, getEngClient: jest.fn() };
});

// The real module's exports are non-configurable getters (a rolldown/esbuild
// `__export` bundling detail) — `jest.spyOn` cannot redefine those, so this
// handler's tests need the module replaced with plain, spy-able `jest.fn()`s,
// same as `engStream.test.ts` already does.
jest.mock("firebase-functions/logger", () => ({
  error: jest.fn(),
  warn: jest.fn(),
  log: jest.fn()
}));

import { buildSessionParams, handleEngStartRun } from "../engStartRun";
import * as admin from "firebase-admin";
import { verifyAuth } from "../../auth";
import { loadRepo } from "../engRepo";
import { getEngClient } from "../engClient";
import { spyOnLogs } from "./logLeakTestHelpers";

const repo = {
  url: "https://github.com/acme/widget",
  owner: "acme",
  repo: "widget",
  defaultBranch: "main",
  token: "github_pat_secret"
};

describe("buildSessionParams", () => {
  it("mounts the repo at the shared mount path", () => {
    const p = buildSessionParams({
      agentId: "agent_1",
      agentVersion: 3,
      environmentId: "env_1",
      repo,
      credits: 40,
      ask: "add checkout",
      brief: "",
      metadata: { runId: "run_1", uid: "uid_1" }
    });
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
    const p = buildSessionParams({
      agentId: "agent_1",
      agentVersion: 3,
      environmentId: "env_1",
      repo,
      credits: 40,
      ask: "x",
      brief: "",
      metadata: { runId: "run_1", uid: "uid_1" }
    });
    expect(p.agent).toMatchObject({ type: "agent_with_overrides", id: "agent_1", version: 3 });
  });

  it("attaches a budget derived from the founder's credits", () => {
    const p = buildSessionParams({
      agentId: "a",
      agentVersion: 1,
      environmentId: "e",
      repo,
      credits: 10,
      ask: "x",
      brief: "",
      metadata: { runId: "run_1", uid: "uid_1" }
    });
    expect(p.budget).toEqual({ type: "limit", max_list_cost: { amount: "50", currency: "USD" } });
  });

  it("puts the company brief in the system override, never in the user message", () => {
    const p = buildSessionParams({
      agentId: "a",
      agentVersion: 1,
      environmentId: "e",
      repo,
      credits: 5,
      ask: "add checkout",
      brief: "Acme sells widgets.",
      metadata: { runId: "run_1", uid: "uid_1" }
    });
    expect(p.agent.system).toContain("Acme sells widgets.");
    const firstEvent = p.initial_events[0] as { content: Array<{ text: string }> };
    expect(firstEvent.content[0].text).toBe("add checkout");
    expect(firstEvent.content[0].text).not.toContain("Acme sells widgets.");
  });

  it("never puts the token anywhere but the repo resource", () => {
    const p = buildSessionParams({
      agentId: "a",
      agentVersion: 1,
      environmentId: "e",
      repo,
      credits: 5,
      ask: "x",
      brief: "y",
      metadata: { runId: "run_1", uid: "uid_1" }
    });
    const withoutResources = JSON.stringify({ ...p, resources: [] });
    expect(withoutResources).not.toContain("github_pat_secret");
  });

  it("starts the run in the same call, so the session never sits idle", () => {
    const p = buildSessionParams({
      agentId: "a",
      agentVersion: 1,
      environmentId: "e",
      repo,
      credits: 5,
      ask: "add checkout",
      brief: "",
      metadata: { runId: "run_1", uid: "uid_1" }
    });
    expect(p.initial_events).toHaveLength(1);
    expect(p.initial_events[0].type).toBe("user.message");
  });

  it("carries the run id and uid as session metadata, so the run is recoverable from the session alone", () => {
    const p = buildSessionParams({
      agentId: "a",
      agentVersion: 1,
      environmentId: "e",
      repo,
      credits: 5,
      ask: "add checkout",
      brief: "",
      metadata: { runId: "run_42", uid: "uid_99" }
    });
    expect(p.metadata).toEqual({ runId: "run_42", uid: "uid_99" });
  });
});

// ---------------------------------------------------------------------------
// handleEngStartRun
//
// Each test below sets up EVERY guard the handler checks before the code
// under test — auth, payload, config env vars, repo, credits — from scratch.
// None of it lives in a shared beforeEach default. A guard added above these
// paths later must make these tests fail loudly (wrong status code, mock
// never reached) rather than silently pass for the wrong reason.
// ---------------------------------------------------------------------------

type MockRes = { status: jest.Mock; json: jest.Mock };

function makeRes(): MockRes {
  const res: Partial<MockRes> = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res as MockRes;
}

function makeReq(body: unknown, authorization = "Bearer sometoken") {
  return {
    method: "POST",
    headers: { authorization },
    body
  } as unknown as Parameters<typeof handleEngStartRun>[0];
}

const GITHUB_TOKEN = "gh_super_secret_TOKEN_should_never_leak_xyz789";

function repoFixture() {
  return {
    url: "https://github.com/acme/widget",
    owner: "acme",
    repo: "widget",
    defaultBranch: "main",
    token: GITHUB_TOKEN
  };
}

function setConfigEnv() {
  process.env.CONNECTOR_ENC_KEY = "enc-key";
  process.env.ENG_AGENT_ID = "agent_1";
  process.env.ENG_AGENT_VERSION = "3";
  process.env.ENG_ENVIRONMENT_ID = "env_1";
}

function clearConfigEnv() {
  delete process.env.CONNECTOR_ENC_KEY;
  delete process.env.ENG_AGENT_ID;
  delete process.env.ENG_AGENT_VERSION;
  delete process.env.ENG_ENVIRONMENT_ID;
}

function makeRunRef(id = "run_generated_1") {
  return {
    id,
    set: jest.fn().mockResolvedValue(undefined),
    update: jest.fn().mockResolvedValue(undefined)
  };
}

function wireFirestore(runRef: ReturnType<typeof makeRunRef>, credits = 40) {
  const admin_ = admin as unknown as {
    firestore: jest.Mock & { FieldValue: { serverTimestamp: jest.Mock } };
  };
  const { doc, collection } = admin_.firestore() as unknown as { doc: jest.Mock; collection: jest.Mock };
  doc.mockReset();
  collection.mockReset();
  doc.mockReturnValue({ get: jest.fn().mockResolvedValue({ data: () => ({ credits }) }) });
  collection.mockReturnValue({ doc: jest.fn(() => runRef) });
}

beforeEach(() => {
  jest.clearAllMocks();
  clearConfigEnv();
});

afterEach(() => {
  clearConfigEnv();
});

describe("handleEngStartRun", () => {
  it(
    "never lets a session-create error reach the client or the logs, even when the SDK error " +
      "stringifies the request (and its embedded GitHub token)",
    async () => {
      (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
      (loadRepo as jest.Mock).mockResolvedValueOnce(repoFixture());
      setConfigEnv();
      const runRef = makeRunRef();
      wireFirestore(runRef, 40);

      // Mimics an Anthropic SDK HTTP-client error: many such errors carry the
      // request configuration in their message/toString, and the request we
      // just made embeds the repo resource (which carries the GitHub token).
      const leakyError = new Error(
        `Request failed: {"resources":[{"authorization_token":"${GITHUB_TOKEN}"}]}`
      );
      const sessionsCreate = jest.fn().mockRejectedValueOnce(leakyError);
      (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { create: sessionsCreate } } });

      // Covers BOTH log channels this codebase uses (console AND
      // firebase-functions/logger) — Finding 5 gives this handler its first
      // logger calls, and a leak assertion that only spied on console would
      // go blind to them the moment they exist. `containsMarker` also looks
      // inside an Error's message/stack, not just enumerable fields — plain
      // `JSON.stringify(call)` would miss a marker carried there.
      const logs = spyOnLogs();

      try {
        const req = makeReq({ ask: "add checkout" });
        const res = makeRes();

        await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

        expect(res.status).toHaveBeenCalledWith(502);
        const body = res.json.mock.calls[0][0];
        expect(JSON.stringify(body)).not.toContain(GITHUB_TOKEN);

        expect(logs.containsMarker(GITHUB_TOKEN)).toBe(false);
      } finally {
        logs.restore();
      }
    }
  );

  it(
    "marks the run document failed, responds 502, and logs a content-free diagnostic " +
      "(Finding 5) when session-create fails",
    async () => {
      (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_2" });
      (loadRepo as jest.Mock).mockResolvedValueOnce(repoFixture());
      setConfigEnv();
      const runRef = makeRunRef("run_fail_1");
      wireFirestore(runRef, 40);

      const upstreamError = Object.assign(new Error("upstream exploded"), { name: "APIError", status: 502 });
      const sessionsCreate = jest.fn().mockRejectedValueOnce(upstreamError);
      (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { create: sessionsCreate } } });

      const logs = spyOnLogs();
      try {
        const req = makeReq({ ask: "add checkout" });
        const res = makeRes();

        await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

        expect(res.status).toHaveBeenCalledWith(502);
        expect(res.json).toHaveBeenCalledWith({ error: "session_create_failed" });
        expect(runRef.update).toHaveBeenCalledWith(expect.objectContaining({ status: "failed" }));

        // Before this fix, this handler had zero diagnostic signal on any of
        // its six failure exits — a deploy misconfiguration surfacing here
        // left nothing anywhere to explain the 502. Now it logs a fixed
        // message plus the two content-free fields `safeErrorDetail` allows.
        const messages = logs.allCalls().map((call) => call[0]);
        expect(messages.some((m) => typeof m === "string" && /session.create failed/i.test(m))).toBe(
          true
        );
        expect(logs.containsMarker("upstream exploded")).toBe(false);
      } finally {
        logs.restore();
      }
    }
  );

  it("creates the run document (status starting, no sessionId) before calling session-create", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_3" });
    (loadRepo as jest.Mock).mockResolvedValueOnce(repoFixture());
    setConfigEnv();
    const runRef = makeRunRef("run_order_1");
    wireFirestore(runRef, 40);

    // Captured here, asserted AFTER the handler returns (outside the mock).
    // If the ordering regresses, the mock itself must stay a plain success
    // so the handler's own try/catch never sees a thrown assertion — a
    // regression must surface as a failed assertion below, not a misleading
    // "expected 200, got 502" from the handler swallowing an exception that
    // originated inside its own mocked dependency.
    let setCallsAtCreateTime = -1;
    let writtenAtCreateTime: { status?: string; sessionId?: string } | undefined;
    const sessionsCreate = jest.fn().mockImplementation(() => {
      setCallsAtCreateTime = runRef.set.mock.calls.length;
      writtenAtCreateTime = runRef.set.mock.calls[0]?.[0];
      return Promise.resolve({ id: "sess_order_1" });
    });
    (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { create: sessionsCreate } } });

    const req = makeReq({ ask: "add checkout" });
    const res = makeRes();

    await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

    expect(sessionsCreate).toHaveBeenCalledTimes(1);
    expect(res.status).toHaveBeenCalledWith(200);

    // The oracle, asserted outside the mock: by the time session-create was
    // invoked, the run doc write had already happened, with the
    // pre-billing shape.
    expect(setCallsAtCreateTime).toBe(1);
    expect(writtenAtCreateTime?.status).toBe("starting");
    expect(writtenAtCreateTime?.sessionId).toBeUndefined();
  });

  it("still returns 200 with a runId (and does not hang) when the post-create Firestore update fails", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_4" });
    (loadRepo as jest.Mock).mockResolvedValueOnce(repoFixture());
    setConfigEnv();
    const runRef = makeRunRef("run_update_fail_1");
    wireFirestore(runRef, 40);
    // First update call (sessionId/status: running) fails; any follow-up
    // reconciliation write succeeds.
    runRef.update.mockReset();
    runRef.update.mockRejectedValueOnce(new Error("firestore unavailable")).mockResolvedValue(undefined);

    const sessionsCreate = jest.fn().mockResolvedValueOnce({ id: "sess_update_fail_1" });
    (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { create: sessionsCreate } } });

    const req = makeReq({ ask: "add checkout" });
    const res = makeRes();

    await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

    expect(res.status).toHaveBeenCalledWith(200);
    const body = res.json.mock.calls[0][0];
    expect(body.runId).toBe("run_update_fail_1");
    // A later reconciler needs a field on the document, not a log line.
    expect(runRef.update).toHaveBeenCalledTimes(2);
    const secondCall = runRef.update.mock.calls[1][0];
    expect(JSON.stringify(secondCall)).toMatch(/reconcile/i);
  });

  // -------------------------------------------------------------------------
  // Every I/O call in this handler must fail into a defined HTTP response,
  // never an unhandled rejection (that is exactly the hang this file's own
  // comments describe as the thing to avoid). These three cover the reads
  // and the initial write that ran unguarded before this fix.
  // -------------------------------------------------------------------------

  it("responds with a defined status (never a hang), distinct from 409/402, and logs a content-free diagnostic when loadRepo throws", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_repo_fail" });
    (loadRepo as jest.Mock).mockRejectedValueOnce(new Error("firestore outage MARKER_REPO_LOOKUP"));
    setConfigEnv();
    const runRef = makeRunRef("run_repo_fail_1");
    wireFirestore(runRef, 40);

    const logs = spyOnLogs();
    try {
      const req = makeReq({ ask: "add checkout" });
      const res = makeRes();

      await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

      expect(res.status).toHaveBeenCalled();
      expect(res.status).not.toHaveBeenCalledWith(409);
      expect(res.status).not.toHaveBeenCalledWith(402);
      const statusCode = res.status.mock.calls[0][0];
      expect(statusCode).toBeGreaterThanOrEqual(500);
      const body = res.json.mock.calls[0][0];
      expect(JSON.stringify(body)).not.toContain("MARKER_REPO_LOOKUP");
      // Nothing has been billed or recorded — the run doc must not exist.
      expect(runRef.set).not.toHaveBeenCalled();

      const messages = logs.allCalls().map((call) => call[0]);
      expect(messages.some((m) => typeof m === "string" && /repo lookup failed/i.test(m))).toBe(true);
      expect(logs.containsMarker("MARKER_REPO_LOOKUP")).toBe(false);
    } finally {
      logs.restore();
    }
  });

  it("responds with a defined status (never a hang), distinct from 409/402, and logs a content-free diagnostic when the company lookup throws", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_company_fail" });
    (loadRepo as jest.Mock).mockResolvedValueOnce(repoFixture());
    setConfigEnv();
    const runRef = makeRunRef("run_company_fail_1");
    wireFirestore(runRef, 40);
    const admin_ = admin as unknown as { firestore: jest.Mock };
    const { doc } = admin_.firestore() as unknown as { doc: jest.Mock };
    doc.mockReturnValue({
      get: jest.fn().mockRejectedValue(new Error("firestore outage MARKER_COMPANY_LOOKUP"))
    });

    const logs = spyOnLogs();
    try {
      const req = makeReq({ ask: "add checkout" });
      const res = makeRes();

      await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

      expect(res.status).toHaveBeenCalled();
      expect(res.status).not.toHaveBeenCalledWith(409);
      expect(res.status).not.toHaveBeenCalledWith(402);
      const statusCode = res.status.mock.calls[0][0];
      expect(statusCode).toBeGreaterThanOrEqual(500);
      const body = res.json.mock.calls[0][0];
      expect(JSON.stringify(body)).not.toContain("MARKER_COMPANY_LOOKUP");
      expect(runRef.set).not.toHaveBeenCalled();

      const messages = logs.allCalls().map((call) => call[0]);
      expect(messages.some((m) => typeof m === "string" && /company lookup failed/i.test(m))).toBe(true);
      expect(logs.containsMarker("MARKER_COMPANY_LOOKUP")).toBe(false);
    } finally {
      logs.restore();
    }
  });

  it("responds with a defined status (never a hang) and logs a content-free diagnostic when the initial run-document write throws", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_write_fail" });
    (loadRepo as jest.Mock).mockResolvedValueOnce(repoFixture());
    setConfigEnv();
    const runRef = makeRunRef("run_write_fail_1");
    wireFirestore(runRef, 40);
    runRef.set.mockRejectedValueOnce(new Error("firestore outage MARKER_INITIAL_WRITE"));

    const sessionsCreate = jest.fn();
    (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { create: sessionsCreate } } });

    const logs = spyOnLogs();
    try {
      const req = makeReq({ ask: "add checkout" });
      const res = makeRes();

      await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

      expect(res.status).toHaveBeenCalled();
      expect(res.status).not.toHaveBeenCalledWith(409);
      expect(res.status).not.toHaveBeenCalledWith(402);
      const statusCode = res.status.mock.calls[0][0];
      expect(statusCode).toBeGreaterThanOrEqual(500);
      const body = res.json.mock.calls[0][0];
      expect(JSON.stringify(body)).not.toContain("MARKER_INITIAL_WRITE");
      // A run that failed to record itself must never bill a session.
      expect(sessionsCreate).not.toHaveBeenCalled();

      const messages = logs.allCalls().map((call) => call[0]);
      expect(messages.some((m) => typeof m === "string" && /run create failed/i.test(m))).toBe(true);
      expect(logs.containsMarker("MARKER_INITIAL_WRITE")).toBe(false);
    } finally {
      logs.restore();
    }
  });

  // -------------------------------------------------------------------------
  // Finding 5: the two config-guard exits also had zero diagnostic signal.
  // Neither carries an upstream `err` — there is nothing to leak — so these
  // just confirm a fixed, named message is logged for whichever variable is
  // absent, which is what turns "502 with nothing anywhere to explain it"
  // into an actionable deploy-misconfiguration signal.
  // -------------------------------------------------------------------------

  it("logs a content-free diagnostic when CONNECTOR_ENC_KEY is absent", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_no_enc_key" });
    clearConfigEnv();

    const logs = spyOnLogs();
    try {
      const req = makeReq({ ask: "add checkout" });
      const res = makeRes();

      await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

      expect(res.status).toHaveBeenCalledWith(500);
      const messages = logs.allCalls().map((call) => call[0]);
      expect(messages.some((m) => typeof m === "string" && /CONNECTOR_ENC_KEY/.test(m))).toBe(true);
    } finally {
      logs.restore();
    }
  });

  it("logs a content-free diagnostic when the engineering agent is not provisioned", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_no_agent" });
    (loadRepo as jest.Mock).mockResolvedValueOnce(repoFixture());
    const runRef = makeRunRef("run_no_agent_1");
    wireFirestore(runRef, 40);
    process.env.CONNECTOR_ENC_KEY = "enc-key";
    // Deliberately leave ENG_AGENT_ID/ENG_AGENT_VERSION/ENG_ENVIRONMENT_ID unset.

    const logs = spyOnLogs();
    try {
      const req = makeReq({ ask: "add checkout" });
      const res = makeRes();

      await handleEngStartRun(req, res as unknown as Parameters<typeof handleEngStartRun>[1]);

      expect(res.status).toHaveBeenCalledWith(500);
      const messages = logs.allCalls().map((call) => call[0]);
      expect(messages.some((m) => typeof m === "string" && /agent not provisioned/i.test(m))).toBe(true);
    } finally {
      logs.restore();
    }
  });
});
