jest.mock("firebase-admin", () => {
  // Base template only: every handler-level test below wires its own
  // doc()/get() fixture from scratch (per-test, not shared) so a guard added
  // earlier in the handler cannot silently keep a later test green for the
  // wrong reason.
  const doc = jest.fn();
  const firestoreFn: unknown = jest.fn(() => ({ doc }));
  return { firestore: firestoreFn };
});

jest.mock("../../auth", () => ({
  verifyAuth: jest.fn()
}));

jest.mock("../engClient", () => {
  const actual = jest.requireActual("../engClient");
  return { ...actual, getEngClient: jest.fn() };
});

import { buildTurnEvents, handleEngSendTurn } from "../engSendTurn";
import * as admin from "firebase-admin";
import { verifyAuth } from "../../auth";
import { getEngClient } from "../engClient";

describe("buildTurnEvents", () => {
  it("builds a plain follow-up message", () => {
    expect(buildTurnEvents({ text: "use a webhook instead" })).toEqual([
      { type: "user.message", content: [{ type: "text", text: "use a webhook instead" }] }
    ]);
  });

  it("builds a tool approval", () => {
    expect(buildTurnEvents({ approve: { toolUseId: "sevt_1", allow: true } })).toEqual([
      { type: "user.tool_confirmation", tool_use_id: "sevt_1", result: "allow" }
    ]);
  });

  it("carries a reason on a denial, so the agent can adjust", () => {
    expect(buildTurnEvents({ approve: { toolUseId: "sevt_1", allow: false, reason: "use pnpm" } })).toEqual([
      { type: "user.tool_confirmation", tool_use_id: "sevt_1", result: "deny", deny_message: "use pnpm" }
    ]);
  });

  it("builds an interrupt", () => {
    expect(buildTurnEvents({ interrupt: true })).toEqual([{ type: "user.interrupt" }]);
  });

  it("rejects an empty or unrecognised body", () => {
    expect(buildTurnEvents({})).toBeNull();
    expect(buildTurnEvents({ text: "   " })).toBeNull();
    expect(buildTurnEvents(null)).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// handleEngSendTurn
//
// Every test below sets up EVERY guard the handler checks before the code
// under test — method, auth, payload, the run lookup — from scratch. None of
// it lives in a shared beforeEach default, per the project rule that a guard
// added above a later path must make these tests fail loudly (wrong status
// code, mock never reached) rather than silently pass for the wrong reason.
// ---------------------------------------------------------------------------

type MockRes = { status: jest.Mock; json: jest.Mock };

function makeRes(): MockRes {
  const res: Partial<MockRes> = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res as MockRes;
}

function makeReq(body: unknown, method = "POST", authorization = "Bearer sometoken") {
  return {
    method,
    headers: { authorization },
    body
  } as unknown as Parameters<typeof handleEngSendTurn>[0];
}

function firestoreDoc(): jest.Mock {
  const admin_ = admin as unknown as { firestore: jest.Mock };
  const { doc } = admin_.firestore() as unknown as { doc: jest.Mock };
  doc.mockReset();
  return doc;
}

beforeEach(() => {
  jest.clearAllMocks();
});

/**
 * A leak assertion must not run bare `JSON.stringify` over a value that
 * could be an `Error` — `JSON.stringify(new Error("secret"))` is `"{}"`
 * because `message`/`stack` are non-enumerable, so the assertion would pass
 * while the secret still leaked. Walks call arguments (including nested
 * plain objects and `Error` instances) looking for the marker directly,
 * mirroring `callsContainMarker` in `engWebhook.test.ts`.
 */
function callsContainMarker(calls: unknown[][], marker: string): boolean {
  const seen = new Set<unknown>();
  const valueContains = (value: unknown): boolean => {
    if (value == null) return false;
    if (typeof value === "string") return value.includes(marker);
    if (value instanceof Error) {
      return value.message.includes(marker) || (value.stack ?? "").includes(marker);
    }
    if (typeof value === "object") {
      if (seen.has(value)) return false;
      seen.add(value);
      return Object.values(value as Record<string, unknown>).some(valueContains);
    }
    return false;
  };
  return calls.some((call) => call.some(valueContains));
}

describe("handleEngSendTurn", () => {
  it("rejects a non-POST request without checking auth, firestore, or the session client", async () => {
    const doc = firestoreDoc();

    await handleEngSendTurn(makeReq({}, "GET"), makeRes() as unknown as Parameters<typeof handleEngSendTurn>[1]);

    expect(verifyAuth).not.toHaveBeenCalled();
    expect(doc).not.toHaveBeenCalled();
  });

  it("rejects an unauthenticated request before touching firestore or the session client", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce(null);
    const doc = firestoreDoc();

    const res = makeRes();
    await handleEngSendTurn(
      makeReq({ runId: "run_1", text: "hi" }),
      res as unknown as Parameters<typeof handleEngSendTurn>[1]
    );

    expect(res.status).toHaveBeenCalledWith(401);
    expect(doc).not.toHaveBeenCalled();
  });

  it("rejects a payload with no runId or no recognised event before touching firestore", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
    const doc = firestoreDoc();

    const res = makeRes();
    await handleEngSendTurn(
      makeReq({ runId: "run_1" }), // no text/approve/interrupt
      res as unknown as Parameters<typeof handleEngSendTurn>[1]
    );

    expect(res.status).toHaveBeenCalledWith(400);
    expect(doc).not.toHaveBeenCalled();
  });

  it("responds 404 without calling the session client when the run does not exist", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
    const doc = firestoreDoc();
    doc.mockReturnValue({ get: jest.fn().mockResolvedValue({ exists: false, data: () => undefined }) });
    const send = jest.fn();
    (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { events: { send } } } });

    const res = makeRes();
    await handleEngSendTurn(
      makeReq({ runId: "run_1", text: "hi" }),
      res as unknown as Parameters<typeof handleEngSendTurn>[1]
    );

    expect(res.status).toHaveBeenCalledWith(404);
    expect(send).not.toHaveBeenCalled();
  });

  it("responds 404 without calling the session client when the run exists but has no sessionId yet", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
    const doc = firestoreDoc();
    doc.mockReturnValue({
      get: jest.fn().mockResolvedValue({ exists: true, data: () => ({ status: "starting" }) })
    });
    const send = jest.fn();
    (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { events: { send } } } });

    const res = makeRes();
    await handleEngSendTurn(
      makeReq({ runId: "run_1", text: "hi" }),
      res as unknown as Parameters<typeof handleEngSendTurn>[1]
    );

    expect(res.status).toHaveBeenCalledWith(404);
    expect(send).not.toHaveBeenCalled();
  });

  it(
    "addresses the run at the AUTHENTICATED founder's own path and its session, ignoring any uid the " +
      "request body itself claims — a founder cannot reach another founder's run by guessing a runId",
    async () => {
      (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
      const doc = firestoreDoc();
      // Two different documents exist at two different paths: the real
      // caller's own run, and a same-named run under a different founder
      // that the request body tries to point at via an extraneous `uid`
      // field. The handler must resolve the *first* path — built only from
      // `auth.uid` — never anything the body supplies.
      doc.mockImplementation((path: string) => ({
        get: jest.fn().mockResolvedValue(
          path === "companies/uid_1/engRuns/run_1"
            ? { exists: true, data: () => ({ sessionId: "sess_owned_by_uid_1" }) }
            : { exists: true, data: () => ({ sessionId: "sess_MUST_NOT_BE_USED" }) }
        )
      }));
      const send = jest.fn().mockResolvedValue(undefined);
      (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { events: { send } } } });

      const res = makeRes();
      await handleEngSendTurn(
        makeReq({ runId: "run_1", text: "hi", uid: "someone_else" }),
        res as unknown as Parameters<typeof handleEngSendTurn>[1]
      );

      // The oracle: which session actually got the message, not merely
      // that the handler returned 200. A version of the handler that ever
      // trusted a body-supplied uid would reach the other session instead.
      expect(send).toHaveBeenCalledWith("sess_owned_by_uid_1", expect.anything());
      expect(send).not.toHaveBeenCalledWith("sess_MUST_NOT_BE_USED", expect.anything());
      expect(doc).toHaveBeenCalledWith("companies/uid_1/engRuns/run_1");
      expect(doc).not.toHaveBeenCalledWith(expect.stringContaining("someone_else"));
      expect(res.status).toHaveBeenCalledWith(200);
    }
  );

  it(
    "maps a session paused at its budget to its own 409 status, not a generic upstream failure, " +
      "and never echoes the upstream error's content to the client",
    async () => {
      const SECRET_MARKER = "sk-ant-budget-secret-marker";
      (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
      const doc = firestoreDoc();
      doc.mockReturnValue({
        get: jest.fn().mockResolvedValue({ exists: true, data: () => ({ sessionId: "sess_1" }) })
      });
      const send = jest
        .fn()
        .mockRejectedValue(new Error(`session budget_reached (auth: Bearer ${SECRET_MARKER})`));
      (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { events: { send } } } });

      const res = makeRes();
      await handleEngSendTurn(
        makeReq({ runId: "run_1", text: "hi" }),
        res as unknown as Parameters<typeof handleEngSendTurn>[1]
      );

      expect(res.status).toHaveBeenCalledWith(409);
      expect(res.status).not.toHaveBeenCalledWith(502);
      const body = res.json.mock.calls[0][0];
      expect(JSON.stringify(body)).not.toContain(SECRET_MARKER);
      expect(body).not.toHaveProperty("detail");
    }
  );

  it("rejects a slash-bearing runId as a client error and never reaches firestore", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
    const doc = firestoreDoc();

    const res = makeRes();
    await handleEngSendTurn(
      makeReq({ runId: "run_1/../other", text: "hi" }),
      res as unknown as Parameters<typeof handleEngSendTurn>[1]
    );

    expect(res.status).toHaveBeenCalledWith(400);
    expect(doc).not.toHaveBeenCalled();
  });

  it("rejects a Firestore-reserved (__…__) runId as a client error and never reaches firestore", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
    const doc = firestoreDoc();

    const res = makeRes();
    await handleEngSendTurn(
      makeReq({ runId: "__reserved__", text: "hi" }),
      res as unknown as Parameters<typeof handleEngSendTurn>[1]
    );

    expect(res.status).toHaveBeenCalledWith(400);
    expect(doc).not.toHaveBeenCalled();
  });

  it(
    "maps a Firestore fault on the run lookup to a defined, retryable status — never a hang, never " +
      "404, and never a log or response containing the upstream error's content",
    async () => {
      const SECRET_MARKER = "sk-ant-lookup-fault-secret-marker";
      (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
      const doc = firestoreDoc();
      doc.mockReturnValue({
        get: jest.fn().mockRejectedValue(
          Object.assign(new Error(`firestore unavailable (auth: Bearer ${SECRET_MARKER})`), {
            code: 14,
            name: "FirestoreError"
          })
        )
      });
      const send = jest.fn();
      (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { events: { send } } } });

      const errorSpy = jest.spyOn(console, "error").mockImplementation(() => undefined);
      const warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
      const logSpy = jest.spyOn(console, "log").mockImplementation(() => undefined);
      try {
        const res = makeRes();
        await handleEngSendTurn(
          makeReq({ runId: "run_1", text: "hi" }),
          res as unknown as Parameters<typeof handleEngSendTurn>[1]
        );

        expect(send).not.toHaveBeenCalled();
        expect(res.status).not.toHaveBeenCalledWith(404);
        expect(res.status).toHaveBeenCalledWith(503);

        const body = res.json.mock.calls[0]?.[0];
        expect(callsContainMarker(res.json.mock.calls, SECRET_MARKER)).toBe(false);
        expect(body).not.toHaveProperty("detail");

        const allCalls = [...errorSpy.mock.calls, ...warnSpy.mock.calls, ...logSpy.mock.calls];
        expect(callsContainMarker(allCalls, SECRET_MARKER)).toBe(false);
      } finally {
        errorSpy.mockRestore();
        warnSpy.mockRestore();
        logSpy.mockRestore();
      }
    }
  );

  it("maps any other send failure to a generic 502, never echoing the upstream error's content", async () => {
    const SECRET_MARKER = "sk-ant-generic-failure-secret-marker";
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
    const doc = firestoreDoc();
    doc.mockReturnValue({
      get: jest.fn().mockResolvedValue({ exists: true, data: () => ({ sessionId: "sess_1" }) })
    });
    const send = jest.fn().mockRejectedValue(new Error(`upstream 500 (auth: Bearer ${SECRET_MARKER})`));
    (getEngClient as jest.Mock).mockReturnValue({ beta: { sessions: { events: { send } } } });

    const res = makeRes();
    await handleEngSendTurn(
      makeReq({ runId: "run_1", text: "hi" }),
      res as unknown as Parameters<typeof handleEngSendTurn>[1]
    );

    expect(res.status).toHaveBeenCalledWith(502);
    const body = res.json.mock.calls[0][0];
    expect(JSON.stringify(body)).not.toContain(SECRET_MARKER);
    expect(body).not.toHaveProperty("detail");
  });
});
