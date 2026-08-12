jest.mock("firebase-admin", () => {
  const doc = jest.fn();
  const firestoreFn: unknown = jest.fn(() => ({ doc }));
  (firestoreFn as { FieldValue?: unknown }).FieldValue = {
    increment: jest.fn((n: number) => ({ __increment: n }))
  };
  return { firestore: firestoreFn };
});

import * as admin from "firebase-admin";
import { BALANCE_PATH, readBalance, debit } from "../engBalance";

function mockDoc() {
  const admin_ = admin as unknown as { firestore: jest.Mock };
  return (admin_.firestore() as unknown as { doc: jest.Mock }).doc;
}

/** Make the next `doc(...).get()` resolve to `data`, or to a missing document. */
function whenBalanceIs(data: Record<string, unknown> | undefined) {
  mockDoc().mockReturnValue({
    get: jest.fn().mockResolvedValue({ data: () => data })
  });
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe("BALANCE_PATH", () => {
  it("is a subcollection document, not a field on the company doc", () => {
    // The whole point of this module: the number moved off
    // `companies/{uid}`, whose `allow update` the founder satisfies.
    expect(BALANCE_PATH("uid_1")).toBe("companies/uid_1/engBalance/current");
  });
});

describe("readBalance", () => {
  it("returns the stored credits", async () => {
    whenBalanceIs({ credits: 20 });
    await expect(readBalance("uid_1")).resolves.toBe(20);
  });

  it("reads from the balance path, not from the company document", async () => {
    whenBalanceIs({ credits: 20 });
    await readBalance("uid_1");
    expect(mockDoc()).toHaveBeenCalledWith("companies/uid_1/engBalance/current");
  });

  it("returns 0 when the document is missing, so a run cannot start on a guess", async () => {
    whenBalanceIs(undefined);
    await expect(readBalance("uid_1")).resolves.toBe(0);
  });

  it("returns 0 when credits is absent from an existing document", async () => {
    whenBalanceIs({ somethingElse: 1 });
    await expect(readBalance("uid_1")).resolves.toBe(0);
  });

  it("returns 0 for NaN rather than letting it through as a number", async () => {
    // `typeof NaN === "number"` is true and `NaN <= 0` is false, so a naive
    // check in the caller would treat this as a positive balance.
    whenBalanceIs({ credits: NaN });
    await expect(readBalance("uid_1")).resolves.toBe(0);
  });

  it("returns 0 for Infinity, which would otherwise mean an unbounded budget", async () => {
    whenBalanceIs({ credits: Infinity });
    await expect(readBalance("uid_1")).resolves.toBe(0);
  });

  it("returns 0 for a string, which is what a hand-edited console value looks like", async () => {
    whenBalanceIs({ credits: "20" });
    await expect(readBalance("uid_1")).resolves.toBe(0);
  });
});

describe("debit", () => {
  function makeTx() {
    return { set: jest.fn() } as unknown as FirebaseFirestore.Transaction & { set: jest.Mock };
  }

  it("decrements by the amount, inside the caller's transaction", () => {
    const ref = { id: "balance" };
    mockDoc().mockReturnValue(ref);
    const tx = makeTx();

    debit(tx, "uid_1", 6);

    expect(mockDoc()).toHaveBeenCalledWith("companies/uid_1/engBalance/current");
    expect(tx.set).toHaveBeenCalledWith(ref, { credits: { __increment: -6 } }, { merge: true });
  });

  it("uses increment rather than a computed value, so concurrent debits both land", () => {
    mockDoc().mockReturnValue({});
    const tx = makeTx();
    debit(tx, "uid_1", 3);
    const written = tx.set.mock.calls[0][1] as { credits: unknown };
    // A read-modify-write would put a plain number here, and two deliveries
    // committing at once would lose one of the decrements.
    expect(written.credits).toEqual({ __increment: -3 });
  });

  it("writes nothing for a zero debit", () => {
    mockDoc().mockReturnValue({});
    const tx = makeTx();
    debit(tx, "uid_1", 0);
    expect(tx.set).not.toHaveBeenCalled();
  });

  it("writes nothing for a negative debit, which would credit the founder back", () => {
    mockDoc().mockReturnValue({});
    const tx = makeTx();
    debit(tx, "uid_1", -5);
    expect(tx.set).not.toHaveBeenCalled();
  });

  it("writes nothing for NaN, which would corrupt the balance into an unreadable value", () => {
    // increment(-NaN) makes the stored credits NaN, which readBalance then
    // reports as 0 — silently locking the founder out of their own credits.
    mockDoc().mockReturnValue({});
    const tx = makeTx();
    debit(tx, "uid_1", NaN);
    expect(tx.set).not.toHaveBeenCalled();
  });

  it("writes nothing for Infinity", () => {
    mockDoc().mockReturnValue({});
    const tx = makeTx();
    debit(tx, "uid_1", Infinity);
    expect(tx.set).not.toHaveBeenCalled();
  });
});
