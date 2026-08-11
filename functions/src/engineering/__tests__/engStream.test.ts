jest.mock("firebase-admin", () => {
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

import { dedupe, isTerminal, handleEngStream, writeFrame } from "../engStream";
import * as admin from "firebase-admin";
import { verifyAuth } from "../../auth";
import { getEngClient } from "../engClient";

describe("dedupe", () => {
  it("passes an event the first time and blocks it after", () => {
    const seen = new Set<string>();
    const e = { id: "sevt_1" };
    expect(dedupe(seen, e)).toBe(true);
    expect(dedupe(seen, e)).toBe(false);
  });

  it("passes an event with no id — an interrupt echo can arrive id-less", () => {
    expect(dedupe(new Set(), {})).toBe(true);
  });
});

describe("isTerminal", () => {
  it("ends on termination", () => {
    expect(isTerminal({ type: "session.status_terminated" })).toBe(true);
  });

  it("ends on a completed turn", () => {
    expect(isTerminal({ type: "session.status_idle", stop_reason: { type: "end_turn" } })).toBe(true);
  });

  it("ends when the budget is reached — only a budget change resumes it", () => {
    expect(isTerminal({ type: "session.status_idle", stop_reason: { type: "budget_reached" } })).toBe(true);
  });

  it("does NOT end while the agent is waiting on the founder", () => {
    // A tool approval sits here. Breaking would strand the run.
    expect(isTerminal({ type: "session.status_idle", stop_reason: { type: "requires_action" } })).toBe(false);
  });

  it("does not end on ordinary activity", () => {
    expect(isTerminal({ type: "agent.message" })).toBe(false);
    expect(isTerminal({ type: "session.status_running" })).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// handleEngStream
//
// Mocking a long-lived stream mostly just proves mocks return what we told
// them to. These two tests are the exceptions: each has an oracle that only
// a correct implementation of one of the file's ordering rules can satisfy —
// not something the mock setup hands us for free. Every test below wires its
// own auth/firestore/client fixtures from scratch, per the project rule that
// a guard added later must break these loudly rather than pass by accident.
// ---------------------------------------------------------------------------

type MockRes = {
  setHeader: jest.Mock;
  status: jest.Mock;
  write: jest.Mock;
  end: jest.Mock;
  json: jest.Mock;
  on: jest.Mock;
  writableEnded: boolean;
  destroyed: boolean;
};

// Plumbing only — `on`/`writableEnded`/`destroyed` exist so handleEngStream
// can call `res.on(...)` and check writability without crashing the mock.
// They default to "connected and writable" and are never the thing a given
// test is asserting on; a disconnect test overrides them explicitly (see
// below), per the project rule that a guard's own test can't lean on a
// shared default to pass.
function makeRes(): MockRes {
  const res: Partial<MockRes> = {};
  res.setHeader = jest.fn();
  res.status = jest.fn().mockReturnValue(res);
  res.write = jest.fn();
  res.end = jest.fn();
  res.json = jest.fn().mockReturnValue(res);
  res.on = jest.fn();
  res.writableEnded = false;
  res.destroyed = false;
  return res as MockRes;
}

function makeReq(runId = "run_1", authorization = "Bearer sometoken") {
  return {
    headers: { authorization },
    query: { runId }
  } as unknown as Parameters<typeof handleEngStream>[0];
}

function wireAuthAndRun(uid = "uid_1", sessionId = "sess_1") {
  (verifyAuth as jest.Mock).mockReset().mockResolvedValue({ uid });
  const admin_ = admin as unknown as { firestore: jest.Mock };
  const { doc } = admin_.firestore() as unknown as { doc: jest.Mock };
  doc.mockReset();
  doc.mockReturnValue({
    get: jest.fn().mockResolvedValue({ exists: true, data: () => ({ sessionId }) })
  });
}

function framesWritten(res: MockRes): string[] {
  return res.write.mock.calls.map((c) => c[0] as string);
}

describe("handleEngStream", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("opens the live stream before listing history, so nothing emitted in between is lost", async () => {
    wireAuthAndRun();

    async function* emptyHistory(): AsyncGenerator<Record<string, unknown>> {
      // yields nothing
    }
    async function* emptyLive(): AsyncGenerator<Record<string, unknown>> {
      // yields nothing — the loop just ends, no terminal frame either
    }

    const streamMock = jest.fn().mockImplementation(async () => emptyLive());
    const listMock = jest.fn().mockImplementation(() => emptyHistory());
    (getEngClient as jest.Mock).mockReturnValue({
      beta: { sessions: { events: { stream: streamMock, list: listMock } } }
    });

    await handleEngStream(makeReq(), makeRes() as unknown as Parameters<typeof handleEngStream>[1]);

    expect(streamMock).toHaveBeenCalledTimes(1);
    expect(listMock).toHaveBeenCalledTimes(1);
    // The real oracle: invocation ORDER, via jest's own global call-order
    // index, not anything the mock's return value tells us. A rewrite that
    // lists history before opening the stream — reintroducing the exact gap
    // this file's comments describe — makes this fail without touching the
    // mocked payloads at all.
    const streamCalledAt = streamMock.mock.invocationCallOrder[0];
    const listCalledAt = listMock.mock.invocationCallOrder[0];
    expect(streamCalledAt).toBeLessThan(listCalledAt);
  });

  it("still closes the stream on a terminal event already seen in history, instead of hanging on the next live event", async () => {
    wireAuthAndRun();

    // Terminal AND id-tagged, so it is "seen" once history has been read.
    const terminalEvent = { id: "sevt_terminal", type: "session.status_idle", stop_reason: { type: "end_turn" } };

    async function* history(): AsyncGenerator<Record<string, unknown>> {
      yield terminalEvent;
    }

    // The live tail replays the same event (a real overlap case), then would
    // block forever waiting on the next one. If the terminal check is ever
    // moved inside the dedupe gate, dedupe blocks this replayed event, the
    // loop calls next() again, and this test hangs until Jest's own timeout
    // fails it — a correct implementation never reaches that await at all.
    async function* live(): AsyncGenerator<Record<string, unknown>> {
      yield { ...terminalEvent };
      await new Promise(() => {
        // never resolves
      });
    }

    const streamMock = jest.fn().mockImplementation(async () => live());
    const listMock = jest.fn().mockImplementation(() => history());
    (getEngClient as jest.Mock).mockReturnValue({
      beta: { sessions: { events: { stream: streamMock, list: listMock } } }
    });

    const res = makeRes();
    await handleEngStream(makeReq(), res as unknown as Parameters<typeof handleEngStream>[1]);

    expect(res.end).toHaveBeenCalledTimes(1);
    const frames = framesWritten(res);
    expect(frames.some((f) => f.startsWith("event: done"))).toBe(true);
    // Never a second "step"/"message" frame for the replayed event — dedupe
    // still gated the relay, only not the terminal check.
    expect(frames.filter((f) => f.startsWith("event: step")).length).toBe(0);
  });

  it("stops pulling live events at its next iteration once the client disconnects mid-stream", async () => {
    wireAuthAndRun();

    // This test's own guard, built from scratch rather than borrowed from
    // makeRes()'s default: we capture whatever handler the implementation
    // registers for "close" and fire it ourselves, mid-stream, to simulate
    // the founder's app dropping the connection.
    let closeHandler: (() => void) | undefined;
    const res = makeRes();
    res.on = jest.fn((eventName: string, handler: () => void) => {
      if (eventName === "close") closeHandler = handler;
    });

    let disconnected = false;
    let pullsAfterDisconnect = 0;
    const TOTAL_EVENTS = 1000;

    async function* emptyHistory(): AsyncGenerator<Record<string, unknown>> {
      // yields nothing — the disconnect happens on the live tail
    }

    // A long-running live tail. At event index 2 we flip the connection to
    // "closed" — simulating the founder's app dropping mid-run — via the
    // exact close handler handleEngStream registered on res. The oracle:
    // the generator must not be pulled more than once more after that (the
    // one in-flight pull the for-await protocol can't avoid). A regression
    // that never checks the disconnect flag would instead drain all 1000.
    async function* live(): AsyncGenerator<Record<string, unknown>> {
      for (let i = 0; i < TOTAL_EVENTS; i++) {
        if (disconnected) pullsAfterDisconnect++;
        yield { id: `sevt_${i}`, type: "agent.tool_use", name: "bash", input: { command: `step ${i}` } };
        if (i === 2) {
          disconnected = true;
          closeHandler?.();
        }
      }
    }

    const streamMock = jest.fn().mockImplementation(async () => live());
    const listMock = jest.fn().mockImplementation(() => emptyHistory());
    (getEngClient as jest.Mock).mockReturnValue({
      beta: { sessions: { events: { stream: streamMock, list: listMock } } }
    });

    await handleEngStream(makeReq(), res as unknown as Parameters<typeof handleEngStream>[1]);

    // The loop noticed the disconnect at its very next iteration — not after
    // draining the remaining ~997 events waiting in the mock generator.
    expect(pullsAfterDisconnect).toBe(1);
    // None of those un-relayed events reached the client as "step" frames.
    const frames = framesWritten(res);
    expect(frames.filter((f) => f.startsWith("event: step")).length).toBeLessThanOrEqual(3);
    expect(res.end).toHaveBeenCalledTimes(1);
  });
});

describe("writeFrame", () => {
  // Each test builds its own bare response object — no shared "connected and
  // writable" default from makeRes() — so a future guard that changes what
  // "writable" means breaks these loudly instead of passing by accident.

  it("writes when the response is still writable", () => {
    const write = jest.fn();
    const res = { write, writableEnded: false, destroyed: false } as unknown as Parameters<typeof writeFrame>[0];

    writeFrame(res, "step", { id: "sevt_1", label: "ran a command", done: false });

    expect(write).toHaveBeenCalledTimes(1);
  });

  it("is a no-op once writableEnded is true", () => {
    const write = jest.fn();
    const res = { write, writableEnded: true, destroyed: false } as unknown as Parameters<typeof writeFrame>[0];

    writeFrame(res, "step", { id: "sevt_1", label: "ran a command", done: false });

    expect(write).not.toHaveBeenCalled();
  });

  it("is a no-op once the socket is destroyed", () => {
    const write = jest.fn();
    const res = { write, writableEnded: false, destroyed: true } as unknown as Parameters<typeof writeFrame>[0];

    writeFrame(res, "step", { id: "sevt_1", label: "ran a command", done: false });

    expect(write).not.toHaveBeenCalled();
  });

  it("swallows a synchronous write failure instead of throwing", () => {
    const write = jest.fn(() => {
      throw new Error("write after end");
    });
    const res = { write, writableEnded: false, destroyed: false } as unknown as Parameters<typeof writeFrame>[0];

    expect(() => writeFrame(res, "error", { error: "stream_failed" })).not.toThrow();
    expect(write).toHaveBeenCalledTimes(1);
  });
});
