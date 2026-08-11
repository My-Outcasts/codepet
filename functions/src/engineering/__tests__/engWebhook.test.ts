jest.mock("firebase-admin", () => {
  // Base template only: every test wires its own doc/collectionGroup mocks
  // from scratch (per-test, not shared) so a guard added earlier in the
  // handler cannot silently keep a later test green for the wrong reason.
  const doc = jest.fn();
  const collectionGroup = jest.fn();
  const firestoreFn: unknown = jest.fn(() => ({ doc, collectionGroup }));
  (firestoreFn as { FieldValue?: unknown }).FieldValue = {
    serverTimestamp: jest.fn(() => "SERVER_TIMESTAMP"),
    increment: jest.fn((n: number) => ({ __increment: n }))
  };
  return { firestore: firestoreFn };
});

jest.mock("../engClient", () => {
  const actual = jest.requireActual("../engClient");
  return { ...actual, getEngClient: jest.fn() };
});

import { statusFor, handleEngWebhook } from "../engWebhook";
import * as admin from "firebase-admin";
import { getEngClient } from "../engClient";

describe("statusFor", () => {
  it("maps a completed turn to reviewing — the diff is what comes next", () => {
    expect(statusFor("end_turn")).toBe("reviewing");
  });

  it("maps a budget pause to its own status, not to failed", () => {
    // The session is paused and resumable. Calling it failed would tell the
    // founder their work is gone when it is sitting there waiting.
    expect(statusFor("budget_reached")).toBe("budgetReached");
  });

  it("maps exhausted retries to failed", () => {
    expect(statusFor("retries_exhausted")).toBe("failed");
  });

  it("keeps a run that is waiting on the founder as running", () => {
    expect(statusFor("requires_action")).toBe("running");
  });

  it("treats an unknown stop reason as failed rather than silently reviewing", () => {
    expect(statusFor("something_new")).toBe("failed");
    expect(statusFor(undefined)).toBe("failed");
  });
});

// ---------------------------------------------------------------------------
// handleEngWebhook — the dedupe guard
//
// Deliveries retry, and the same event id can arrive more than once. A
// create-if-absent write on the event id (`webhookEvents/{event.id}`) is the
// only thing standing between a retried delivery and a second debit against
// the founder's credits. This cannot be exercised through a pure function —
// the guard IS the Firestore write failing — so it is reached here through
// `jest.mock("firebase-admin")`, the same technique `engRepo.test.ts` uses
// to drive `loadRepo`'s internal catch.
//
// Every fixture below is built fresh, per test, from scratch: doc(),
// collectionGroup(), and the Anthropic client are all wired inside the test
// body rather than in a shared beforeEach, so a guard added above this path
// later must break these loudly (call counts change) rather than pass
// silently for the wrong reason.
// ---------------------------------------------------------------------------

type MockRes = { status: jest.Mock; json: jest.Mock; send: jest.Mock };

function makeRes(): MockRes {
  const res: Partial<MockRes> = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  res.send = jest.fn().mockReturnValue(res);
  return res as MockRes;
}

function makeReq(rawBody: string, headers: Record<string, string> = { "webhook-signature": "sig" }) {
  return {
    method: "POST",
    headers,
    rawBody: Buffer.from(rawBody, "utf8")
  } as unknown as Parameters<typeof handleEngWebhook>[0];
}

/** A run doc ref (engRuns/{id}) whose `.parent.parent` is the company doc ref. */
function makeRunRef() {
  const companyRef = { set: jest.fn().mockResolvedValue(undefined) };
  const runRef = {
    set: jest.fn().mockResolvedValue(undefined),
    parent: { parent: companyRef }
  };
  return { runRef, companyRef };
}

/** Wires `db.collectionGroup("engRuns").where(...).limit(...).get()` to resolve to one match. */
function wireCollectionGroup(runRef: ReturnType<typeof makeRunRef>["runRef"]) {
  const admin_ = admin as unknown as { firestore: jest.Mock };
  const { collectionGroup } = admin_.firestore() as unknown as { collectionGroup: jest.Mock };
  collectionGroup.mockReset();
  collectionGroup.mockReturnValue({
    where: jest.fn().mockReturnValue({
      limit: jest.fn().mockReturnValue({
        get: jest.fn().mockResolvedValue({ empty: false, docs: [{ ref: runRef }] })
      })
    })
  });
}

/**
 * Wires `db.doc("webhookEvents/{id}").create(...)` — the dedupe write
 * itself. `outcomes` is consumed in order across successive calls to
 * `handleEngWebhook`, one outcome per delivery.
 */
function wireDedupeDoc(outcomes: Array<"created" | "already-exists">) {
  const admin_ = admin as unknown as { firestore: jest.Mock };
  const { doc } = admin_.firestore() as unknown as { doc: jest.Mock };
  doc.mockReset();
  const create = jest.fn();
  for (const outcome of outcomes) {
    if (outcome === "created") {
      create.mockImplementationOnce(() => Promise.resolve(undefined));
    } else {
      create.mockImplementationOnce(() => Promise.reject(new Error("ALREADY_EXISTS")));
    }
  }
  doc.mockReturnValue({ create });
  return create;
}

function makeEngClient(overrides?: {
  eventId?: string;
  eventType?: "session.status_idled" | "session.status_terminated";
  sessionId?: string;
  amountCents?: string;
  stopReasonType?: string;
}) {
  const eventId = overrides?.eventId ?? "evt_1";
  const eventType = overrides?.eventType ?? "session.status_idled";
  const sessionId = overrides?.sessionId ?? "sess_1";
  const amountCents = overrides?.amountCents ?? "25";
  const stopReasonType = overrides?.stopReasonType ?? "end_turn";

  return {
    beta: {
      webhooks: {
        unwrap: jest.fn().mockResolvedValue({
          id: eventId,
          data: { type: eventType, id: sessionId }
        })
      },
      sessions: {
        retrieve: jest.fn().mockResolvedValue({ usage: { list_cost: { amount: amountCents } } }),
        events: {
          list: jest.fn().mockResolvedValue({
            data: [{ type: "session.status_idle", stop_reason: { type: stopReasonType } }]
          })
        }
      }
    }
  };
}

describe("handleEngWebhook — replayed delivery (dedupe)", () => {
  it(
    "debits credits exactly once and writes the run outcome exactly once " +
      "across two deliveries of the same event",
    async () => {
      const client = makeEngClient();
      (getEngClient as jest.Mock).mockReturnValue(client);

      const { runRef, companyRef } = makeRunRef();
      wireCollectionGroup(runRef);
      // First delivery's create-if-absent write lands; the replay's loses
      // the race against the doc the first delivery just created.
      wireDedupeDoc(["created", "already-exists"]);

      const res1 = makeRes();
      await handleEngWebhook(makeReq('{"event":"one"}'), res1 as unknown as Parameters<typeof handleEngWebhook>[1]);

      const res2 = makeRes();
      await handleEngWebhook(makeReq('{"event":"one"}'), res2 as unknown as Parameters<typeof handleEngWebhook>[1]);

      // The oracle: proves the guarded code (session fetch, run write, credit
      // debit) ran exactly once, not that the second call merely "did
      // something else". A version of the handler with the dedupe write
      // deleted reaches this code twice and this assertion fails.
      expect(client.beta.sessions.retrieve).toHaveBeenCalledTimes(1);
      expect(runRef.set).toHaveBeenCalledTimes(1);
      expect(companyRef.set).toHaveBeenCalledTimes(1);
      expect(companyRef.set).toHaveBeenCalledWith(
        { credits: { __increment: -5 } },
        { merge: true }
      );

      // Both deliveries still get acknowledged so Anthropic does not keep
      // retrying a delivery we have already (or intentionally haven't) acted on.
      expect(res1.status).toHaveBeenCalledWith(204);
      expect(res2.status).toHaveBeenCalledWith(204);
    }
  );
});

describe("handleEngWebhook — other behaviour", () => {
  it("rejects a non-POST request without touching Firestore or the client", async () => {
    const client = makeEngClient();
    (getEngClient as jest.Mock).mockReturnValue(client);
    const { runRef } = makeRunRef();
    wireCollectionGroup(runRef);
    wireDedupeDoc(["created"]);

    const req = { method: "GET", headers: {}, rawBody: Buffer.from("") } as unknown as Parameters<
      typeof handleEngWebhook
    >[0];
    const res = makeRes();

    await handleEngWebhook(req, res as unknown as Parameters<typeof handleEngWebhook>[1]);

    expect(res.status).toHaveBeenCalledWith(405);
    expect(client.beta.webhooks.unwrap).not.toHaveBeenCalled();
  });

  it("verifies against req.rawBody, not a re-serialised body", async () => {
    const client = makeEngClient();
    (getEngClient as jest.Mock).mockReturnValue(client);
    const { runRef, companyRef } = makeRunRef();
    wireCollectionGroup(runRef);
    wireDedupeDoc(["created"]);

    // Deliberately not valid JSON — proves the exact raw bytes are what get
    // handed to unwrap, not something reconstructed from a parsed body.
    const rawBody = '{"event":  "one", "padding": "xx"}';
    const res = makeRes();

    await handleEngWebhook(makeReq(rawBody), res as unknown as Parameters<typeof handleEngWebhook>[1]);

    expect(client.beta.webhooks.unwrap).toHaveBeenCalledWith(
      rawBody,
      expect.objectContaining({ headers: expect.anything() })
    );
    expect(companyRef.set).toHaveBeenCalledTimes(1);
  });

  it("responds 400 without echoing the upstream error when signature verification fails", async () => {
    const SECRET_MARKER = "sk-ant-super-secret-should-never-leak";
    const client = makeEngClient();
    client.beta.webhooks.unwrap = jest
      .fn()
      .mockRejectedValue(new Error(`invalid signature for key ${SECRET_MARKER}`));
    (getEngClient as jest.Mock).mockReturnValue(client);

    const errorSpy = jest.spyOn(console, "error").mockImplementation(() => undefined);
    const warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
    const logSpy = jest.spyOn(console, "log").mockImplementation(() => undefined);

    try {
      const res = makeRes();
      await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

      expect(res.status).toHaveBeenCalledWith(400);
      const sendBody = res.send.mock.calls[0]?.[0];
      expect(JSON.stringify(sendBody)).not.toContain(SECRET_MARKER);

      const allConsoleCalls = [...errorSpy.mock.calls, ...warnSpy.mock.calls, ...logSpy.mock.calls];
      for (const call of allConsoleCalls) {
        expect(JSON.stringify(call)).not.toContain(SECRET_MARKER);
      }
    } finally {
      errorSpy.mockRestore();
      warnSpy.mockRestore();
      logSpy.mockRestore();
    }
  });

  it("acknowledges (204) and does not look up a session for an event type it does not act on", async () => {
    const client = makeEngClient({ eventType: "session.status_idled" });
    client.beta.webhooks.unwrap = jest.fn().mockResolvedValue({
      id: "evt_other",
      data: { type: "session.created", id: "sess_1" }
    });
    (getEngClient as jest.Mock).mockReturnValue(client);
    wireDedupeDoc(["created"]);

    const res = makeRes();
    await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

    expect(res.status).toHaveBeenCalledWith(204);
    expect(client.beta.sessions.retrieve).not.toHaveBeenCalled();
  });

  it("acknowledges (204) without debiting when no run matches the session id", async () => {
    const client = makeEngClient();
    (getEngClient as jest.Mock).mockReturnValue(client);
    wireDedupeDoc(["created"]);
    const admin_ = admin as unknown as { firestore: jest.Mock };
    const { collectionGroup } = admin_.firestore() as unknown as { collectionGroup: jest.Mock };
    collectionGroup.mockReset();
    collectionGroup.mockReturnValue({
      where: jest.fn().mockReturnValue({
        limit: jest.fn().mockReturnValue({ get: jest.fn().mockResolvedValue({ empty: true, docs: [] }) })
      })
    });

    const res = makeRes();
    await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

    expect(res.status).toHaveBeenCalledWith(204);
    expect(client.beta.sessions.retrieve).not.toHaveBeenCalled();
  });

  it("writes budgetReached, not failed, when the session paused on its budget", async () => {
    const client = makeEngClient({ stopReasonType: "budget_reached" });
    (getEngClient as jest.Mock).mockReturnValue(client);
    const { runRef } = makeRunRef();
    wireCollectionGroup(runRef);
    wireDedupeDoc(["created"]);

    const res = makeRes();
    await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

    expect(runRef.set).toHaveBeenCalledWith(
      expect.objectContaining({ status: "budgetReached" }),
      { merge: true }
    );
  });
});
