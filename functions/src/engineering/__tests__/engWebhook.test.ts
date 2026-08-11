jest.mock("firebase-admin", () => {
  // Base template only: every test wires its own doc()/runTransaction()
  // fixtures from scratch (per-test, not shared) so a guard added earlier in
  // the handler cannot silently keep a later test green for the wrong
  // reason. `collectionGroup` stays on the mock purely so a test can assert
  // it is never called — the handler itself must never invoke it (Finding 3:
  // no collectionGroup scan).
  const doc = jest.fn();
  const collectionGroup = jest.fn();
  const runTransaction = jest.fn();
  const firestoreFn: unknown = jest.fn(() => ({ doc, collectionGroup, runTransaction }));
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
// handleEngWebhook
//
// Deliveries retry, and the same event id can arrive more than once. The
// dedupe check, the run write, and the credit debit all happen inside one
// Firestore transaction (`db.runTransaction`) so a mid-flight failure can
// never leave the marker recorded without the debit, or the debit applied
// without the marker (Finding 1). Duplicate detection is a plain read of the
// marker *inside* that transaction, not a caught error (Finding 2) — so a
// transaction that throws for any other reason must never be mistaken for a
// duplicate. The run is addressed directly at
// `companies/{uid}/engRuns/{runId}` using the `runId`/`uid` the session
// carries in its own metadata (Finding 3) — no collectionGroup scan.
//
// This cannot be exercised through a pure function — the guard IS the
// Firestore transaction succeeding, failing, or finding a duplicate — so it
// is reached here through `jest.mock("firebase-admin")`, the same technique
// `engRepo.test.ts` uses to drive `loadRepo`'s internal catch.
//
// Every fixture below is built fresh, per test, from scratch via
// `makeFirestoreDouble` (never a shared beforeEach), so a guard added above
// this path later must break these loudly (call counts, committed state)
// rather than pass silently for the wrong reason.
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

const UID = "uid_1";
const RUN_ID = "run_1";
const RUN_PATH = `companies/${UID}/engRuns/${RUN_ID}`;
const COMPANY_PATH = `companies/${UID}`;

function seenPath(eventId: string) {
  return `webhookEvents/${eventId}`;
}

type SetCall = { path: string; data: unknown; options?: unknown };

/**
 * A minimal in-memory Firestore double, not a per-call script. `store`
 * tracks which paths "exist"; a transaction's writes only land in `store`
 * and `setCalls` if its callback runs to completion — a rejected callback
 * commits nothing, matching real Firestore atomicity. This is what makes
 * the exactly-once tests below actually load-bearing: whether a retry sees
 * the marker depends on what the *previous attempt actually committed*, not
 * on a hardcoded "this is delivery 2, say true" fixture.
 *
 * `doc()` refs also expose bare `get`/`create`, unused by the fixed
 * handler (which only reads/writes through `tx`), kept only so the
 * Finding-1 load-bearing proof can temporarily reintroduce a
 * non-transactional marker write — the pre-fix shape — without touching
 * this file at all.
 */
/**
 * `initialData` seeds what `.data()` returns for a path that "exists" — used
 * by the Finding-3-delta tests to plant a run doc's previously-recorded
 * `creditsSpent` before a delivery runs. Kept as a SEPARATE map from `store`,
 * not merged into it, because `store`'s boolean values are asserted directly
 * by existing tests (e.g. `expect(store.get(seenPath(...))).toBeFalsy()`) —
 * widening those to `{ exists, data }` objects would make every one of those
 * assertions vacuously truthy (an object is always truthy) and silently stop
 * protecting anything.
 */
function makeFirestoreDouble(
  initialExists: Record<string, boolean> = {},
  initialData: Record<string, Record<string, unknown>> = {}
) {
  const admin_ = admin as unknown as { firestore: jest.Mock };
  const { doc, collectionGroup, runTransaction } = admin_.firestore() as unknown as {
    doc: jest.Mock;
    collectionGroup: jest.Mock;
    runTransaction: jest.Mock;
  };
  doc.mockReset();
  collectionGroup.mockReset();
  runTransaction.mockReset();

  const store = new Map<string, boolean>(Object.entries(initialExists));
  const dataStore = new Map<string, Record<string, unknown>>(Object.entries(initialData));
  const setCalls: SetCall[] = [];

  doc.mockImplementation((path: string) => ({
    path,
    get: jest.fn(async () => ({ exists: Boolean(store.get(path)), data: () => dataStore.get(path) })),
    create: jest.fn(async () => {
      if (store.get(path)) {
        throw Object.assign(new Error("ALREADY_EXISTS"), { code: 6 });
      }
      store.set(path, true);
    })
  }));

  runTransaction.mockImplementation(async (fn: (tx: unknown) => Promise<unknown>) => {
    const pending: SetCall[] = [];
    const tx = {
      get: jest.fn(async (ref: { path: string }) => ({
        exists: Boolean(store.get(ref.path)),
        data: () => dataStore.get(ref.path)
      })),
      set: jest.fn((ref: { path: string }, data: unknown, options?: unknown) => {
        pending.push({ path: ref.path, data, options });
      })
    };
    const result = await fn(tx);
    // Only reached if `fn` resolved without throwing — commit.
    for (const w of pending) {
      store.set(w.path, true);
      // Merge plain fields into dataStore so the NEXT transaction's tx.get(...).data()
      // sees what this one committed — this is what makes the three-delivery
      // delta test load-bearing across calls, not a fixed per-test fixture.
      // FieldValue sentinels (e.g. `{ __increment: n }` from `admin.firestore.FieldValue.increment`)
      // are opaque wrapper objects in this double; nothing under test reads a
      // company doc's `credits` back via `.data()`, only the run doc's plain
      // `creditsSpent` number, so no sentinel-resolution logic is needed here.
      const existing = dataStore.get(w.path) ?? {};
      dataStore.set(w.path, { ...existing, ...(w.data as Record<string, unknown>) });
      setCalls.push(w);
    }
    return result;
  });

  return { doc, collectionGroup, runTransaction, store, dataStore, setCalls };
}

/**
 * Forces the *next* `db.runTransaction` call to reject before its callback
 * ever runs — an infra fault mid-flight. Nothing it would have written
 * commits, because `makeFirestoreDouble`'s `runTransaction` only applies
 * pending writes after the callback resolves.
 */
function failNextTransaction(runTransaction: jest.Mock, err: unknown) {
  runTransaction.mockImplementationOnce(() => Promise.reject(err));
}

function makeEngClient(overrides?: {
  eventId?: string;
  eventType?: "session.status_idled" | "session.status_terminated";
  sessionId?: string;
  amountCents?: string;
  stopReasonType?: string;
  uid?: string | null;
  runId?: string | null;
  metadata?: Record<string, unknown> | null;
  // Stashed on the mocked session under a field nothing in the handler is
  // supposed to log wholesale (`session._debugRequest`). Planting a secret
  // here — rather than in `runId`/`uid`/`sessionId` themselves, which the
  // handler legitimately logs — proves the leak-safety tests below are
  // actually exercising "only the safe fields are logged", not "nothing at
  // this call site happens to contain the marker".
  secretMarker?: string;
}) {
  const eventId = overrides?.eventId ?? "evt_1";
  const eventType = overrides?.eventType ?? "session.status_idled";
  const sessionId = overrides?.sessionId ?? "sess_1";
  const amountCents = overrides?.amountCents ?? "25";
  const stopReasonType = overrides?.stopReasonType ?? "end_turn";
  const metadata =
    overrides?.metadata !== undefined
      ? overrides.metadata
      : { runId: overrides?.runId ?? RUN_ID, uid: overrides?.uid ?? UID };

  return {
    beta: {
      webhooks: {
        unwrap: jest.fn().mockResolvedValue({
          id: eventId,
          data: { type: eventType, id: sessionId }
        })
      },
      sessions: {
        retrieve: jest.fn().mockResolvedValue({
          usage: { list_cost: { amount: amountCents } },
          metadata,
          ...(overrides?.secretMarker
            ? { _debugRequest: { authorization: `Bearer ${overrides.secretMarker}` } }
            : {})
        }),
        events: {
          list: jest.fn().mockResolvedValue({
            data: [{ type: "session.status_idle", stop_reason: { type: stopReasonType } }]
          })
        }
      }
    }
  };
}

/** Spies on all three console sinks and hands back a combined-calls getter. */
function spyOnConsole() {
  const errorSpy = jest.spyOn(console, "error").mockImplementation(() => undefined);
  const warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
  const logSpy = jest.spyOn(console, "log").mockImplementation(() => undefined);
  return {
    allCalls: () => [...errorSpy.mock.calls, ...warnSpy.mock.calls, ...logSpy.mock.calls],
    restore: () => {
      errorSpy.mockRestore();
      warnSpy.mockRestore();
      logSpy.mockRestore();
    }
  };
}

/**
 * Whether `marker` shows up anywhere in a logged console call — including
 * inside an `Error`'s `message`/`stack`. `JSON.stringify` alone is not
 * enough here: `message` and `stack` are non-enumerable on `Error`, so
 * `JSON.stringify(new Error("secret"))` is `"{}"` and would hide a leaked
 * secret carried on a raw error object, which is exactly the regression
 * shape Finding 2 is guarding against (passing raw `err` to console instead
 * of a picked-field object). Real `console.error(err)` prints the message
 * and stack via `util.inspect`, so this check has to look there too or the
 * assertion is not load-bearing against that regression.
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

describe("handleEngWebhook — replayed delivery (dedupe)", () => {
  it(
    "debits credits exactly once and writes the run outcome exactly once " +
      "across two deliveries of the same event",
    async () => {
      const client = makeEngClient();
      (getEngClient as jest.Mock).mockReturnValue(client);
      const { runTransaction, setCalls } = makeFirestoreDouble({ [RUN_PATH]: true });

      const res1 = makeRes();
      await handleEngWebhook(makeReq('{"event":"one"}'), res1 as unknown as Parameters<typeof handleEngWebhook>[1]);

      const res2 = makeRes();
      await handleEngWebhook(makeReq('{"event":"one"}'), res2 as unknown as Parameters<typeof handleEngWebhook>[1]);

      // The oracle: the transaction (marker + run write + debit) ran to
      // completion exactly once, not that the second call merely "did
      // something else". A version of the handler that dedupes outside the
      // transaction, or with the marker written before the work, reaches
      // this code twice and this assertion fails.
      expect(runTransaction).toHaveBeenCalledTimes(2);
      expect(setCalls.filter((c) => c.path === RUN_PATH)).toHaveLength(1);
      expect(setCalls.filter((c) => c.path === COMPANY_PATH)).toHaveLength(1);
      expect(setCalls.filter((c) => c.path === COMPANY_PATH)[0].data).toEqual({
        credits: { __increment: -5 }
      });
      expect(setCalls.filter((c) => c.path === seenPath("evt_1"))).toHaveLength(1);

      // The reads that feed the write are idempotent and safe to repeat on
      // every delivery — only the transactional writes are guarded.
      expect(client.beta.sessions.retrieve).toHaveBeenCalledTimes(2);

      // Both deliveries still get acknowledged so Anthropic does not keep
      // retrying a delivery we have already (or intentionally haven't) acted on.
      expect(res1.status).toHaveBeenCalledWith(204);
      expect(res2.status).toHaveBeenCalledWith(204);
    }
  );

  it(
    "recovers from a mid-flight failure: a delivery that fails during the " +
      "transactional write is retried and completes exactly once, never twice " +
      "— the run doc ends in the correct final state",
    async () => {
      const client = makeEngClient();
      (getEngClient as jest.Mock).mockReturnValue(client);
      const { runTransaction, setCalls, store } = makeFirestoreDouble({ [RUN_PATH]: true });

      // The reads (session retrieve, events list) always succeed — they're
      // idempotent — but the transaction itself fails partway through the
      // write/debit. Because it is one atomic transaction, NOTHING commits:
      // not the marker, not the run write, not the debit.
      failNextTransaction(runTransaction, Object.assign(new Error("boom"), { code: 13 }));

      const res1 = makeRes();
      await handleEngWebhook(makeReq('{"event":"one"}'), res1 as unknown as Parameters<typeof handleEngWebhook>[1]);
      expect(res1.status).toHaveBeenCalledWith(503); // retryable, not swallowed as 204
      expect(store.get(seenPath("evt_1"))).toBeFalsy();

      // Retry: the marker is still absent (the failed attempt committed
      // nothing), the run still exists, so this attempt does the full work.
      const res2 = makeRes();
      await handleEngWebhook(makeReq('{"event":"one"}'), res2 as unknown as Parameters<typeof handleEngWebhook>[1]);
      expect(res2.status).toHaveBeenCalledWith(204);

      // The debit landed exactly once overall, not zero (lost) and not
      // twice (double-charged).
      const companySets = setCalls.filter((c) => c.path === COMPANY_PATH);
      expect(companySets).toHaveLength(1);
      expect(companySets[0].data).toEqual({ credits: { __increment: -5 } });

      // The run document's final recorded state is the real outcome
      // (reviewing, from end_turn), not left stuck at whatever it was
      // before the retry succeeded.
      const runSets = setCalls.filter((c) => c.path === RUN_PATH);
      expect(runSets).toHaveLength(1);
      expect(runSets[0].data).toEqual(expect.objectContaining({ status: "reviewing", creditsSpent: 5 }));
    }
  );

  it(
    "does not acknowledge (204) an infrastructure fault on the marker/transaction — it is not a " +
      "duplicate — and never logs the raw error (Finding 2: `{ code, name }`, not `err`, at this site)",
    async () => {
      const SECRET_MARKER = "sk-ant-txn-fault-secret-marker";
      const client = makeEngClient();
      (getEngClient as jest.Mock).mockReturnValue(client);
      const { runTransaction, setCalls } = makeFirestoreDouble({ [RUN_PATH]: true });
      // A generic failure, unrelated to the marker already existing. Nothing
      // in this fixture says "duplicate" — the transaction just throws. The
      // message carries a secret marker, standing in for the credential an
      // SDK/Firestore error's `err` object can carry on its `request` — this
      // is what a future edit swapping `{ code, name }` for raw `err` would
      // leak, and the only reason this test can catch that regression.
      failNextTransaction(
        runTransaction,
        Object.assign(new Error(`firestore unavailable (auth: Bearer ${SECRET_MARKER})`), {
          code: 13,
          name: "FirestoreError"
        })
      );

      const consoleSpy = spyOnConsole();
      try {
        const res = makeRes();
        await handleEngWebhook(makeReq('{"event":"one"}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

        expect(res.status).not.toHaveBeenCalledWith(204);
        expect(res.status).toHaveBeenCalledWith(503);
        expect(setCalls).toHaveLength(0);

        expect(callsContainMarker(consoleSpy.allCalls(), SECRET_MARKER)).toBe(false);
      } finally {
        consoleSpy.restore();
      }
    }
  );
});

describe("handleEngWebhook — direct addressing (no collectionGroup scan)", () => {
  it("reads the run via the session's own metadata and never issues a collectionGroup query", async () => {
    const client = makeEngClient({ uid: "founder_42", runId: "run_99" });
    (getEngClient as jest.Mock).mockReturnValue(client);
    const { collectionGroup, setCalls } = makeFirestoreDouble({
      "companies/founder_42/engRuns/run_99": true
    });

    const res = makeRes();
    await handleEngWebhook(makeReq('{"event":"one"}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

    expect(collectionGroup).not.toHaveBeenCalled();
    expect(setCalls.some((c) => c.path === "companies/founder_42/engRuns/run_99")).toBe(true);
    expect(setCalls.some((c) => c.path === "companies/founder_42")).toBe(true);
    expect(res.status).toHaveBeenCalledWith(204);
  });
});

describe("handleEngWebhook — other behaviour", () => {
  it("rejects a non-POST request without touching Firestore or the client", async () => {
    const client = makeEngClient();
    (getEngClient as jest.Mock).mockReturnValue(client);
    makeFirestoreDouble();

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
    const { setCalls } = makeFirestoreDouble({ [RUN_PATH]: true });

    // Deliberately not valid JSON — proves the exact raw bytes are what get
    // handed to unwrap, not something reconstructed from a parsed body.
    const rawBody = '{"event":  "one", "padding": "xx"}';
    const res = makeRes();

    await handleEngWebhook(makeReq(rawBody), res as unknown as Parameters<typeof handleEngWebhook>[1]);

    expect(client.beta.webhooks.unwrap).toHaveBeenCalledWith(
      rawBody,
      expect.objectContaining({ headers: expect.anything() })
    );
    expect(setCalls.filter((c) => c.path === COMPANY_PATH)).toHaveLength(1);
  });

  it("responds 400 without echoing the upstream error when signature verification fails", async () => {
    const SECRET_MARKER = "sk-ant-super-secret-should-never-leak";
    const client = makeEngClient();
    client.beta.webhooks.unwrap = jest
      .fn()
      .mockRejectedValue(new Error(`invalid signature for key ${SECRET_MARKER}`));
    (getEngClient as jest.Mock).mockReturnValue(client);
    makeFirestoreDouble();

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
    makeFirestoreDouble();

    const res = makeRes();
    await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

    expect(res.status).toHaveBeenCalledWith(204);
    expect(client.beta.sessions.retrieve).not.toHaveBeenCalled();
  });

  it(
    "acknowledges (204) without debiting when the session's metadata points at a run that does not " +
      "exist, and never logs more than runId/uid (Finding 2: `{ runId, uid }`, not the raw session)",
    async () => {
      const SECRET_MARKER = "sk-ant-unmatched-run-secret-marker";
      const client = makeEngClient({ secretMarker: SECRET_MARKER });
      (getEngClient as jest.Mock).mockReturnValue(client);
      // The run doc itself is missing — deleted, or metadata pointing nowhere
      // real. Reads still happen (Finding 1: reads are unconditional), but no
      // scan is issued to try to find it another way (Finding 3).
      const { setCalls } = makeFirestoreDouble({});

      const consoleSpy = spyOnConsole();
      try {
        const res = makeRes();
        await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

        expect(res.status).toHaveBeenCalledWith(204);
        expect(setCalls.filter((c) => c.path === COMPANY_PATH)).toHaveLength(0);
        expect(setCalls.filter((c) => c.path === RUN_PATH)).toHaveLength(0);

        expect(callsContainMarker(consoleSpy.allCalls(), SECRET_MARKER)).toBe(false);
      } finally {
        consoleSpy.restore();
      }
    }
  );

  it(
    "does not fall back to a scan and retries instead when the session has no runId/uid metadata, " +
      "and never logs more than the session id (Finding 2: `{ sessionId }`, not the raw session)",
    async () => {
      const SECRET_MARKER = "sk-ant-missing-metadata-secret-marker";
      const client = makeEngClient({ metadata: null, secretMarker: SECRET_MARKER });
      (getEngClient as jest.Mock).mockReturnValue(client);
      const { runTransaction, collectionGroup, setCalls } = makeFirestoreDouble();

      const consoleSpy = spyOnConsole();
      try {
        const res = makeRes();
        await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

        // Pinned to the exact value (Finding 3) — a regression that returned
        // 200 here would silently swallow a fault that must force a retry,
        // and asserting only "not 204" would let it through.
        expect(res.status).toHaveBeenCalledWith(500);
        expect(collectionGroup).not.toHaveBeenCalled();
        expect(runTransaction).not.toHaveBeenCalled();
        expect(setCalls).toHaveLength(0);

        expect(callsContainMarker(consoleSpy.allCalls(), SECRET_MARKER)).toBe(false);
      } finally {
        consoleSpy.restore();
      }
    }
  );

  it.each([
    ["a slash-bearing uid", { uid: "founder/../other" }],
    ["a slash-bearing runId", { runId: "run/../other" }],
    ["a reserved-form uid", { uid: "__reserved__" }],
    ["a reserved-form runId", { runId: "__reserved__" }]
  ])(
    "rejects %s before it is ever used to build a Firestore path — retryable status, no write of any kind",
    async (_label, override) => {
      const client = makeEngClient(override);
      (getEngClient as jest.Mock).mockReturnValue(client);
      const { runTransaction, collectionGroup, setCalls } = makeFirestoreDouble({ [RUN_PATH]: true });

      const res = makeRes();
      await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

      // Same status as any other malformed-metadata rejection (Finding 3:
      // pinned, not "not 204") — retryable, but never a construction throw
      // escaping unhandled and never a silent redirect to some other path.
      expect(res.status).toHaveBeenCalledWith(500);
      expect(collectionGroup).not.toHaveBeenCalled();
      expect(runTransaction).not.toHaveBeenCalled();
      expect(setCalls).toHaveLength(0);
    }
  );

  it("writes budgetReached, not failed, when the session paused on its budget", async () => {
    const client = makeEngClient({ stopReasonType: "budget_reached" });
    (getEngClient as jest.Mock).mockReturnValue(client);
    const { setCalls } = makeFirestoreDouble({ [RUN_PATH]: true });

    const res = makeRes();
    await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

    const runSets = setCalls.filter((c) => c.path === RUN_PATH);
    expect(runSets).toHaveLength(1);
    expect(runSets[0].data).toEqual(expect.objectContaining({ status: "budgetReached" }));
  });
});

// ---------------------------------------------------------------------------
// Fix 2: the terminal idle event must be found even when it is not on the
// first page. `events.list(sessionId)` with no params returns ONE page,
// chronological order — the old code searched only that page for the last
// `session.status_idle`. A run producing more than one page of events found
// no idle at all and was recorded `failed` even though it finished cleanly.
// ---------------------------------------------------------------------------

describe("handleEngWebhook — terminal event addressed directly, not by scanning one page (Fix 2)", () => {
  it(
    "still finds the terminal idle event and records the correct status when it is not on the first, " +
      "unfiltered page a plain `events.list(sessionId)` call would see",
    async () => {
      const client = makeEngClient({ stopReasonType: "end_turn" });
      // Replaces the generic fixture's `events.list` with one that only
      // "sees" the terminal idle event when queried directly (desc order,
      // filtered to the idle type, limited to 1) — exactly the shape Fix 2
      // asks for. Any other call shape — including the old bug's bare
      // `events.list(sessionId)` — gets back a page that does NOT contain the
      // idle event, standing in for "it's on a later page this call never
      // reaches."
      client.beta.sessions.events.list = jest.fn((_sessionId: string, params?: Record<string, unknown>) => {
        const isDirectIdleQuery =
          params?.order === "desc" &&
          Array.isArray(params?.types) &&
          (params.types as unknown[]).includes("session.status_idle") &&
          params?.limit === 1;
        if (isDirectIdleQuery) {
          return Promise.resolve({
            data: [{ type: "session.status_idle", stop_reason: { type: "end_turn" } }]
          });
        }
        return Promise.resolve({ data: [{ type: "session.status_running" }] });
      });
      (getEngClient as jest.Mock).mockReturnValue(client);
      const { setCalls } = makeFirestoreDouble({ [RUN_PATH]: true });

      const res = makeRes();
      await handleEngWebhook(makeReq('{"x":1}'), res as unknown as Parameters<typeof handleEngWebhook>[1]);

      expect(res.status).toHaveBeenCalledWith(204);
      const runSets = setCalls.filter((c) => c.path === RUN_PATH);
      expect(runSets).toHaveLength(1);
      // The load-bearing assertion: a version that reads only the first,
      // unfiltered page finds no idle event and falls through to the
      // `failed` default — telling the founder a successful run failed.
      expect(runSets[0].data).toEqual(expect.objectContaining({ status: "reviewing" }));
    }
  );
});

// ---------------------------------------------------------------------------
// Fix 3: `creditsSpent` is cumulative for the whole session, but the dedupe
// marker only protects against a RETRY of the same event id. Every distinct
// terminal delivery (e.g. one per approval pause) re-reads the session's
// running total and, pre-fix, re-debited that ENTIRE total — so a run with
// two approvals billed roughly three times. The fix debits the delta between
// this delivery's cumulative cost and the cumulative cost the previous
// delivery persisted on the run doc.
// ---------------------------------------------------------------------------

/** One delivery's client fixture: a distinct event id, a fixed cumulative usage reading. */
function clientForDelivery(opts: { eventId: string; amountCents: string; stopReasonType: string }) {
  return {
    beta: {
      webhooks: {
        unwrap: jest.fn().mockResolvedValue({
          id: opts.eventId,
          data: { type: "session.status_idled", id: "sess_delta_1" }
        })
      },
      sessions: {
        retrieve: jest.fn().mockResolvedValue({
          usage: { list_cost: { amount: opts.amountCents } },
          metadata: { runId: RUN_ID, uid: UID }
        }),
        events: {
          list: jest.fn().mockResolvedValue({
            data: [{ type: "session.status_idle", stop_reason: { type: opts.stopReasonType } }]
          })
        }
      }
    }
  };
}

describe("handleEngWebhook — delta debit across multiple deliveries (Fix 3)", () => {
  it(
    "debits the DELTA per delivery, so the total charged across three deliveries of one session " +
      "equals the FINAL cumulative cost, not the sum of the three cumulative readings",
    async () => {
      const { setCalls } = makeFirestoreDouble({ [RUN_PATH]: true });

      // Delivery 1: cumulative cost 25c -> 5 credits. Delta from a fresh run
      // (creditsSpent starts at 0, per engStartRun.ts) is 5.
      (getEngClient as jest.Mock).mockReturnValue(
        clientForDelivery({ eventId: "evt_delta_a", amountCents: "25", stopReasonType: "requires_action" })
      );
      await handleEngWebhook(
        makeReq('{"e":"a"}'),
        makeRes() as unknown as Parameters<typeof handleEngWebhook>[1]
      );

      // Delivery 2: cumulative cost 60c -> 12 credits. Delta from 5 is 7.
      (getEngClient as jest.Mock).mockReturnValue(
        clientForDelivery({ eventId: "evt_delta_b", amountCents: "60", stopReasonType: "requires_action" })
      );
      await handleEngWebhook(
        makeReq('{"e":"b"}'),
        makeRes() as unknown as Parameters<typeof handleEngWebhook>[1]
      );

      // Delivery 3: cumulative cost 95c -> 19 credits. Delta from 12 is 7.
      (getEngClient as jest.Mock).mockReturnValue(
        clientForDelivery({ eventId: "evt_delta_c", amountCents: "95", stopReasonType: "end_turn" })
      );
      await handleEngWebhook(
        makeReq('{"e":"c"}'),
        makeRes() as unknown as Parameters<typeof handleEngWebhook>[1]
      );

      const companySets = setCalls.filter((c) => c.path === COMPANY_PATH);
      expect(companySets).toHaveLength(3);
      const totalDebited = companySets.reduce(
        (sum, c) => sum + -(c.data as { credits: { __increment: number } }).credits.__increment,
        0
      );
      // The oracle: total debited is the FINAL cumulative cost (5+7+7=19),
      // not the sum of the three raw cumulative readings a re-debit-the-total
      // bug would produce (5+12+19=36).
      expect(totalDebited).toBe(19);

      const runSets = setCalls.filter((c) => c.path === RUN_PATH);
      expect(runSets).toHaveLength(3);
      expect(runSets[runSets.length - 1].data).toEqual(
        expect.objectContaining({ status: "reviewing", creditsSpent: 19 })
      );
    }
  );
});
