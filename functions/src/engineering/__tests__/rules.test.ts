/**
 * Tests for `firestore.rules`.
 *
 * NOT part of `npm test` — these need the Firestore emulator, which needs a
 * JRE, so `jest.config.js` ignores this file and `npm run test:rules` runs it
 * under `firebase emulators:exec` with `jest.rules.config.js`. Keeping it out
 * of the default suite means a machine without Java still gets a green
 * `npm test` rather than a failure that looks like a broken rule.
 *
 * The threat model throughout is a founder signed in as THEMSELVES. Not a
 * stranger, not an unauthenticated caller — deny-by-default already handles
 * those, and they are not what these rules are for. Every document below is
 * one the founder legitimately owns; the question each test asks is whether
 * owning it should also mean being able to write it.
 */
import { readFileSync } from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  type RulesTestEnvironment
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";

let env: RulesTestEnvironment;

const UID = "founder_1";

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "devpet-8f4b1",
    firestore: {
      // functions/src/engineering/__tests__ -> repo root
      rules: readFileSync(path.resolve(__dirname, "../../../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080
    }
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
});

/** The founder, signed in as themselves and owning `companies/{UID}`. */
function asFounder() {
  return env.authenticatedContext(UID).firestore();
}

/** Seed a document the way a Cloud Function would — Admin SDK, rules bypassed. */
async function seed(docPath: string, data: Record<string, unknown>): Promise<void> {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), docPath), data);
  });
}

describe("companies/{uid} itself", () => {
  it("lets the founder read their own company", async () => {
    await seed(`companies/${UID}`, { ownerId: UID, memberIds: [UID], brief: "x" });
    await assertSucceeds(getDoc(doc(asFounder(), `companies/${UID}`)));
  });
});

describe("companies/{uid}/engineering", () => {
  // Holds the sealed GitHub token. The carve-out for it already exists; these
  // two tests are here to prove this harness reports the truth before any new
  // rule is written against it.
  it("denies the founder reading their own sealed repo token", async () => {
    await seed(`companies/${UID}/engineering/repo`, {
      url: "https://github.com/o/r",
      defaultBranch: "main",
      sealed: { iv: "a", tag: "b", ciphertext: "c" }
    });
    await assertFails(getDoc(doc(asFounder(), `companies/${UID}/engineering/repo`)));
  });

  it("denies the founder writing their own sealed repo token", async () => {
    // Write matters more than read: overwriting `url` or `sealed` would point
    // a paid run at a repo of the caller's choosing, or swap in a token the
    // caller can decrypt.
    await assertFails(
      setDoc(doc(asFounder(), `companies/${UID}/engineering/repo`), {
        url: "https://github.com/attacker/repo"
      })
    );
  });
});

describe("companies/{uid}/engRuns", () => {
  it("lets the founder read their own run, which the app needs to render it", async () => {
    await seed(`companies/${UID}/engRuns/run_1`, { status: "running", creditsSpent: 3 });
    await assertSucceeds(getDoc(doc(asFounder(), `companies/${UID}/engRuns/run_1`)));
  });

  it("denies the founder raising creditsSpent, which is the debit baseline", async () => {
    // engWebhook charges max(0, creditsSpent - previousCreditsSpent) and reads
    // the baseline from this document. A founder who can set it high once
    // computes every later delta to 0 and is never charged again.
    await seed(`companies/${UID}/engRuns/run_1`, { status: "running", creditsSpent: 0 });
    await assertFails(
      setDoc(doc(asFounder(), `companies/${UID}/engRuns/run_1`), {
        status: "running",
        creditsSpent: 999999
      })
    );
  });

  it("denies the founder creating a run that points at someone else's session", async () => {
    // engSendTurn and engStream both take `sessionId` from this document to
    // decide which Managed Agents session to drive. A forged run document
    // aims those handlers at a session the caller does not own.
    await assertFails(
      setDoc(doc(asFounder(), `companies/${UID}/engRuns/forged`), {
        sessionId: "sesn_belongs_to_someone_else",
        status: "running"
      })
    );
  });
});
