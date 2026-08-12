# Engineering Mode — Credits Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the number that authorises real money spend server-authoritative, so a founder cannot grant themselves unlimited engineering runs by editing their own Firestore documents.

**Architecture:** Two client-writable documents currently feed the spend path. Move the authoritative balance into a read-allowed / write-denied subcollection (the pattern `connectorStatus` already uses in this same rules file), deny client writes to run documents, and move the debit's baseline into a server-only ledger so a future rules regression cannot silently reopen the hole. No new services; three Firestore paths and two handlers.

**Tech Stack:** Firebase Cloud Functions v2 (TypeScript, Node 22), Firestore security rules, `@firebase/rules-unit-testing` against the Firestore emulator, Jest.

## Why this exists

Found Aug 12 2026 while tracing why a completed run never debited. Both of
these are writable by the authenticated founder today:

| Path | Rule | Consequence |
|---|---|---|
| `companies/{uid}` | `allow update` guards only ownership (`firestore.rules:84`) | `credits` is directly editable. `engStartRun.ts:189` reads it and `creditsToBudget` turns it into the platform spend cap. |
| `companies/{uid}/engRuns/{runId}` | the carve-out excludes `connectors`, `connectorStatus`, `engineering` — **not `engRuns`** (`firestore.rules:126-133`) | `engWebhook.ts:283` reads `previousCreditsSpent` off this document and debits `Math.max(0, creditsSpent - previousCreditsSpent)`. Set the field high once and every later debit is zero. |

**Scope of the damage, stated honestly.** A single run cannot exceed $2.00
whatever `credits` says, because `creditsToBudget` clamps to
`DEFAULT_RUN_CREDITS * CREDIT_CENTS` (`engBudget.ts:45`). So this is not an
unbounded-single-run hole. It is unbounded *in aggregate*: an authenticated
founder can start $2.00 runs indefinitely and never be debited for any of
them. Nothing else limits the rate — none of the four engineering handlers
call `checkAndIncrement`, unlike the other fifteen AI handlers.

A second, narrower consequence of the same `engRuns` gap: `engSendTurn.ts:80`
and `engStream.ts:115` read `sessionId` from the run document to decide which
Managed Agents session to drive. A client that can write that document can
point it at any session id it knows, and inject turns into — or read the
event stream of — a session it does not own. Session ids are random and not
exposed across accounts, so this is not trivially exploitable, but the
server's authorization decision should not rest on a client-writable field
regardless.

**Why now, and why it is cheap now.** `credits` is consumed by nothing
outside `src/engineering/` (verified by grep across `functions/src`), and no
Swift client reads or writes `engRuns` yet — Plan 3 has not been built. Every
later week makes this more expensive.

**Not in scope:** rate limiting. It compounds with this and is listed under
Open Decisions, but it is the founder's call, not a defect to fix silently.

## Global Constraints

- **Every rule change ships with a test that goes red when the rule is
  removed.** The repo's working agreement: "If a test passes with and without
  the code it protects, it is not protecting anything." Rules have never been
  tested in this repo; Task 1 exists to make that possible.
- **Client read of run state must keep working.** The founder's app renders
  run status. Deny *write*, never read.
- **Client read of the balance must keep working.** The founder has to see
  their credits. `engineering/` is read-denied and is therefore the wrong home
  for a displayed value.
- **Server-only writes go through the Admin SDK,** which bypasses rules. No
  handler needs a rules change to keep working.
- Cents per credit is `CREDIT_CENTS = 5` and the per-run ceiling is
  `DEFAULT_RUN_CREDITS = 40`. Do not change either in this plan.
- The branch is `feat/engineering-mode-backend`, deployed to production and
  **not merged**. Deploys are scoped, human-run, and follow
  `docs/superpowers/RUNBOOK-engineering-backend.md`.

## File Structure

- `firestore.rules` — one new write carve-out; one new read-allowed /
  write-denied subcollection. Modify only the `match /{sub}/{document=**}`
  block and its comment.
- `functions/src/engineering/engBalance.ts` — **new.** The only module that
  reads or writes a founder's balance. One responsibility: `readBalance(uid)`
  and the transaction-safe `debit(tx, uid, credits)`. Exists so the balance
  path is one file to audit rather than two handlers to keep in sync.
- `functions/src/engineering/engStartRun.ts` — read the balance through
  `engBalance` instead of `company.credits`.
- `functions/src/engineering/engWebhook.ts` — debit through `engBalance`, and
  take the delta baseline from the server-only ledger rather than the run doc.
- `functions/scripts/migrate-eng-balance.ts` — **new.** One-shot, idempotent:
  copy `companies/{uid}.credits` into the new location for every existing
  company.
- `functions/src/engineering/__tests__/engBalance.test.ts` — **new.**
- `functions/src/engineering/__tests__/rules.test.ts` — **new.** The rules
  harness.

---

### Task 1: A rules test harness that can fail

**Files:**
- Create: `functions/src/engineering/__tests__/rules.test.ts`
- Modify: `functions/package.json` (add `test:rules`)

**Interfaces:**
- Consumes: `firestore.rules` at the repo root.
- Produces: `npm run test:rules`, which later tasks extend with one case per
  rule they change.

`@firebase/rules-unit-testing` drives the Firestore emulator, and the
emulator needs a JRE. There is none on this machine — that is why the
`engineering` carve-out shipped hand-checked. Installing one is a
prerequisite, not an optional extra: without it every rule in this plan is
asserted rather than tested.

- [ ] **Step 1: Install a JRE and confirm the emulator starts**

```bash
brew install --cask temurin
java -version
cd ~/Developer/codepet-eng-backend
firebase emulators:exec --only firestore "echo emulator-ok"
```

Expected: `java -version` prints a version, and the `firebase` command exits 0
having printed `emulator-ok`. If `brew` is unavailable, stop and escalate —
do not proceed by hand-checking rules.

- [ ] **Step 2: Add the dependency and the script**

```bash
cd ~/Developer/codepet-eng-backend/functions
npm install --save-dev @firebase/rules-unit-testing
```

Add to `functions/package.json` scripts:

```json
"test:rules": "firebase emulators:exec --only firestore --project devpet-8f4b1 \"npx jest src/engineering/__tests__/rules.test.ts\""
```

- [ ] **Step 3: Write a failing test for a rule that is already correct**

Start with the `engineering` carve-out, because it is already in place — this
proves the harness reports the truth before any new rule depends on it.

```typescript
import { readFileSync } from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  type RulesTestEnvironment
} from "@firebase/rules-unit-testing";
import { setDoc, doc, getDoc } from "firebase/firestore";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "devpet-8f4b1",
    firestore: {
      rules: readFileSync(path.resolve(__dirname, "../../../../firestore.rules"), "utf8")
    }
  });
});

afterAll(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const UID = "founder_1";

/** A founder signed in as themselves, which is the only threat model here. */
function asFounder() {
  return env.authenticatedContext(UID).firestore();
}

describe("companies/{uid}/engineering", () => {
  it("denies the founder reading their own sealed repo token", async () => {
    const db = asFounder();
    await assertFails(getDoc(doc(db, `companies/${UID}/engineering/repo`)));
  });

  it("denies the founder writing their own sealed repo token", async () => {
    const db = asFounder();
    await assertFails(
      setDoc(doc(db, `companies/${UID}/engineering/repo`), { url: "https://github.com/x/y" })
    );
  });
});
```

- [ ] **Step 4: Run it**

Run: `cd functions && npm run test:rules`
Expected: PASS, 2 tests.

- [ ] **Step 5: Prove the harness is load-bearing**

Temporarily delete `&& sub != 'engineering'` from the `allow read` line in
`firestore.rules`, re-run, and confirm the read test FAILS. Restore the line
and confirm it passes again. A harness that cannot go red is worth nothing.

Run: `cd functions && npm run test:rules`
Expected: 1 failed with the guard removed; 2 passed once restored.

- [ ] **Step 6: Commit**

```bash
git add functions/package.json functions/package-lock.json functions/src/engineering/__tests__/rules.test.ts
git commit -F - <<'EOF'
test(rules): a harness for firestore.rules, proven able to fail

firestore.rules has never had a test in this repo — the engineering carve-out
shipped hand-checked because the emulator needs a JRE that was not installed.
Every rule change in the credits-integrity plan depends on this existing.

Proof it is load-bearing: removing `&& sub != 'engineering'` from the read
allow turns the read test red, and restoring it turns it green.
EOF
```

---

### Task 2: Deny client writes to run documents

**Files:**
- Modify: `firestore.rules` (the `match /{sub}/{document=**}` block and its comment)
- Modify: `functions/src/engineering/__tests__/rules.test.ts`

**Interfaces:**
- Consumes: the harness from Task 1.
- Produces: `engRuns` documents that only the Admin SDK can write. Read is
  unchanged, so the client keeps rendering run state.

- [ ] **Step 1: Write the failing tests**

Add to `rules.test.ts`:

```typescript
describe("companies/{uid}/engRuns", () => {
  it("lets the founder read their own run, which the app needs to render it", async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), `companies/${UID}/engRuns/run_1`), {
        status: "running",
        creditsSpent: 3
      });
    });
    const db = asFounder();
    await assertSucceeds(getDoc(doc(db, `companies/${UID}/engRuns/run_1`)));
  });

  it("denies the founder writing creditsSpent, which is the debit baseline", async () => {
    // engWebhook debits max(0, creditsSpent - previousCreditsSpent) and reads
    // the baseline from this document. A founder who can set it high once is
    // never debited again.
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), `companies/${UID}/engRuns/run_1`), {
        status: "running",
        creditsSpent: 0
      });
    });
    const db = asFounder();
    await assertFails(
      setDoc(doc(db, `companies/${UID}/engRuns/run_1`), { status: "running", creditsSpent: 999999 })
    );
  });

  it("denies the founder creating a run that points at someone else's session", async () => {
    // engSendTurn and engStream both take sessionId from this document.
    const db = asFounder();
    await assertFails(
      setDoc(doc(db, `companies/${UID}/engRuns/forged`), { sessionId: "sesn_not_mine" })
    );
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd functions && npm run test:rules`
Expected: the read test passes; both write tests FAIL, because `engRuns` is
currently writable.

- [ ] **Step 3: Add the carve-out**

In `firestore.rules`, in the `allow write` condition only, add:

```
          && sub != 'engRuns';
```

and extend the comment block above the match with:

```
      //   engRuns/         one document per engineering run: status, sessionId,
      //                    creditsSpent. READ is allowed — the app renders run state
      //                    from it. WRITE is denied, for two reasons that are both
      //                    money or authorization. engWebhook debits
      //                    max(0, creditsSpent - previousCreditsSpent) and takes the
      //                    baseline from this document, so a client that could raise
      //                    `creditsSpent` would never be debited again. And engSendTurn
      //                    and engStream both read `sessionId` here to decide which
      //                    Managed Agents session to drive, so a forged document points
      //                    those handlers at a session the caller does not own.
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd functions && npm run test:rules`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules functions/src/engineering/__tests__/rules.test.ts
git commit -F - <<'EOF'
fix(rules): deny client writes to engRuns — it holds the debit baseline

The subcollection carve-out covered connectors, connectorStatus and
engineering but not engRuns, which is where engWebhook reads
previousCreditsSpent from. A founder could set creditsSpent high once and
every subsequent debit computes to max(0, actual - huge) = 0.

The same document holds sessionId, which engSendTurn and engStream read to
decide which session to drive, so a forged run document also points those
handlers at a session the caller does not own.

Read stays allowed: the app renders run state from these documents.
EOF
```

---

### Task 3: A server-authoritative balance

**Files:**
- Create: `functions/src/engineering/engBalance.ts`
- Create: `functions/src/engineering/__tests__/engBalance.test.ts`
- Modify: `firestore.rules`, `functions/src/engineering/__tests__/rules.test.ts`
- Modify: `functions/src/engineering/engStartRun.ts:185-192`

**Interfaces:**
- Consumes: nothing from earlier tasks except the rules harness.
- Produces:
  - `readBalance(uid: string): Promise<number>` — the founder's credits, `0`
    when absent or non-finite.
  - `debit(tx: FirebaseFirestore.Transaction, uid: string, credits: number): void`
    — decrement inside a caller's transaction.
  - Storage at `companies/{uid}/engBalance/current`, field `credits: number`.

`engineering/` is read-denied, so it cannot hold a value the founder must
see. `connectorStatus` already establishes the right pattern in this file:
read allowed, write denied. `engBalance` follows it.

- [ ] **Step 1: Write the failing rules tests**

```typescript
describe("companies/{uid}/engBalance", () => {
  it("lets the founder read their own balance, which the app displays", async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), `companies/${UID}/engBalance/current`), { credits: 20 });
    });
    await assertSucceeds(getDoc(doc(asFounder(), `companies/${UID}/engBalance/current`)));
  });

  it("denies the founder topping up their own balance", async () => {
    await assertFails(
      setDoc(doc(asFounder(), `companies/${UID}/engBalance/current`), { credits: 999999 })
    );
  });
});
```

- [ ] **Step 2: Run to verify the write test fails**

Run: `cd functions && npm run test:rules`
Expected: the read test passes (no rule denies it yet), the write test FAILS.

- [ ] **Step 3: Add the rule**

In `firestore.rules`, add to the `allow write` condition only:

```
          && sub != 'engBalance';
```

with a comment matching the `connectorStatus` entry's shape, saying that read
is allowed because the founder must see their balance and write is denied
because it authorises spend.

- [ ] **Step 4: Run to verify**

Run: `cd functions && npm run test:rules`
Expected: PASS, 7 tests.

- [ ] **Step 5: Write the failing unit tests for `engBalance`**

```typescript
import { readBalance, BALANCE_PATH } from "../engBalance";

describe("readBalance", () => {
  it("returns the stored credits", async () => {
    // ... mock admin.firestore().doc(BALANCE_PATH("u1")).get() -> { credits: 20 }
    await expect(readBalance("u1")).resolves.toBe(20);
  });

  it("returns 0 when the document is missing, so a run cannot start on a guess", async () => {
    await expect(readBalance("u1")).resolves.toBe(0);
  });

  it("returns 0 for a NaN balance rather than letting it through", async () => {
    // typeof NaN === "number" and NaN <= 0 is false, so a naive check starts a run.
    await expect(readBalance("u1")).resolves.toBe(0);
  });
});
```

- [ ] **Step 6: Run to verify they fail**

Run: `cd functions && npx jest src/engineering/__tests__/engBalance.test.ts`
Expected: FAIL — `Cannot find module '../engBalance'`.

- [ ] **Step 7: Implement `engBalance.ts`**

```typescript
import * as admin from "firebase-admin";

/**
 * Where a founder's spendable credits live.
 *
 * NOT `companies/{uid}.credits`, and not anything else the founder can write:
 * this number becomes the platform-enforced spend cap on a Managed Agents
 * session, so a client that can edit it sets its own budget. Read is allowed
 * by `firestore.rules` — the app displays the balance — and write is denied,
 * the same shape `connectorStatus` uses.
 */
export const BALANCE_PATH = (uid: string): string => `companies/${uid}/engBalance/current`;

/** The founder's credits. 0 for a missing document or a non-finite value. */
export async function readBalance(uid: string): Promise<number> {
  const snap = await admin.firestore().doc(BALANCE_PATH(uid)).get();
  const credits = snap.data()?.credits;
  // `Number.isFinite`, not `typeof === "number"`: `typeof NaN === "number"` is
  // true and `NaN <= 0` is false, so a corrupted balance would sail past the
  // caller's own <= 0 check and start a run.
  return Number.isFinite(credits) ? (credits as number) : 0;
}

/** Decrement inside the caller's transaction. Never call outside one. */
export function debit(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  credits: number
): void {
  if (!Number.isFinite(credits) || credits <= 0) return;
  tx.set(
    admin.firestore().doc(BALANCE_PATH(uid)),
    { credits: admin.firestore.FieldValue.increment(-credits) },
    { merge: true }
  );
}
```

- [ ] **Step 8: Run to verify they pass**

Run: `cd functions && npx jest src/engineering/__tests__/engBalance.test.ts`
Expected: PASS, 3 tests.

- [ ] **Step 9: Switch `engStartRun` onto it**

Replace the company-document read at `engStartRun.ts:185-192`. The `brief`
still comes from the company document, so that read stays; only the credits
line moves:

```typescript
  const credits = await readBalance(auth.uid);
  if (credits <= 0) {
    res.status(402).json({ error: "no_credits" });
    return;
  }
```

Keep the existing `try`/`catch` around the Firestore access and its 503, and
keep `readBalance` inside it — a balance read that throws must not escape as
an unhandled rejection.

- [ ] **Step 10: Run the engStartRun suite**

Run: `cd functions && npx jest src/engineering/__tests__/engStartRun.test.ts`
Expected: PASS. Update the fixtures that seeded `companies/{uid}.credits` to
seed the balance document instead.

- [ ] **Step 11: Commit**

```bash
git add functions/src/engineering/engBalance.ts functions/src/engineering/__tests__/engBalance.test.ts functions/src/engineering/engStartRun.ts functions/src/engineering/__tests__/engStartRun.test.ts firestore.rules functions/src/engineering/__tests__/rules.test.ts
git commit -F - <<'EOF'
fix(eng): move the spendable balance out of a client-writable document

companies/{uid}.credits is editable by the founder — the company doc's
`allow update` guards ownership and nothing else — and engStartRun turns that
number into the platform spend cap via creditsToBudget. A single run is still
clamped to $2.00 by DEFAULT_RUN_CREDITS, so this was never an unbounded single
run; it was unbounded in aggregate.

The balance now lives at companies/{uid}/engBalance/current: read allowed
because the founder must see it, write denied because it authorises spend.
Same shape connectorStatus already uses in this rules file.

Cheap to do now and not later: credits has no consumer outside
src/engineering, and no Swift client reads it yet.
EOF
```

---

### Task 4: Take the debit baseline off the run document

**Files:**
- Modify: `functions/src/engineering/engWebhook.ts:254-290`
- Modify: `functions/src/engineering/__tests__/engWebhook.test.ts`

**Interfaces:**
- Consumes: `debit` from Task 3.
- Produces: the running total of what a run has already been charged, stored
  at `companies/{uid}/engineering/debits/{runId}`, field `creditsSpent`.

Task 2 denies clients writing `engRuns`, which closes this. This task is
defence in depth, and the argument for it is narrow but real: rules are one
careless deploy from regressing, and what regresses here is money. Under
`engineering/` the value is unreachable by any client even if the `engRuns`
carve-out is ever lost.

`engRuns/{runId}.creditsSpent` stays written — the app displays it. It stops
being the thing arithmetic is done against.

- [ ] **Step 1: Write the failing test**

```typescript
it("debits the delta against the server-only ledger, not the run document", async () => {
  // The run document claims a large prior spend. If the handler still trusts
  // it, the delta computes to 0 and the founder is never charged.
  seedRun({ runId: "run_1", creditsSpent: 999999, status: "running" });
  seedLedger({ runId: "run_1", creditsSpent: 4 });
  seedSessionCost(30); // 30 cents -> 6 credits cumulative

  await handleEngWebhook(req, res);

  expect(debitedCredits()).toBe(2); // 6 - 4, not max(0, 6 - 999999) = 0
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd functions && npx jest src/engineering/__tests__/engWebhook.test.ts -t "server-only ledger"`
Expected: FAIL, `expect(0).toBe(2)`.

- [ ] **Step 3: Read the baseline from the ledger**

In the transaction, replace the `previousCreditsSpent` read:

```typescript
      const ledgerRef = db.doc(`companies/${uid}/engineering/debits/${runId}`);
      const ledgerSnap = await tx.get(ledgerRef);
      const previousCreditsSpent = Number.isFinite(ledgerSnap.data()?.creditsSpent)
        ? (ledgerSnap.data()!.creditsSpent as number)
        : 0;
      const delta = Math.max(0, creditsSpent - previousCreditsSpent);
```

and write the new total to the ledger alongside the existing run-document
write, inside the same transaction:

```typescript
      tx.set(ledgerRef, { creditsSpent }, { merge: true });
```

Every `tx.get` must still precede every `tx.set` — Firestore rejects a
transaction that reads after writing.

- [ ] **Step 4: Run to verify it passes**

Run: `cd functions && npx jest src/engineering/__tests__/engWebhook.test.ts`
Expected: PASS, whole suite.

- [ ] **Step 5: Prove the guard is load-bearing**

Point `previousCreditsSpent` back at `runSnap.data()?.creditsSpent`, re-run,
and confirm the new test goes red. Restore it.

- [ ] **Step 6: Commit**

```bash
git add functions/src/engineering/engWebhook.ts functions/src/engineering/__tests__/engWebhook.test.ts
git commit -F - <<'EOF'
fix(eng): debit against a server-only ledger, not the run document

Task 2's rules change already denies clients writing engRuns, so this is
defence in depth — but what regresses if that rule is ever lost is money, and
the failure is silent: the delta simply computes to 0 and nobody is charged.

The baseline now lives under companies/{uid}/engineering/, which no client can
read or write. engRuns/{runId}.creditsSpent is still written for display; it
is no longer what arithmetic is done against.
EOF
```

---

### Task 5: Migrate existing balances

**Files:**
- Create: `functions/scripts/migrate-eng-balance.ts`
- Modify: `functions/package.json` (add `migrate:balance`)

**Interfaces:**
- Consumes: `BALANCE_PATH` from Task 3.
- Produces: an `engBalance/current` document for every company that has a
  `credits` field.

- [ ] **Step 1: Write the script**

```typescript
/**
 * One-shot, idempotent: copy companies/{uid}.credits into the write-denied
 * balance document introduced by the credits-integrity plan.
 *
 * Idempotent by SKIPPING any company that already has a balance document —
 * not by overwriting. Re-running after a founder has spent credits must not
 * restore them to the pre-migration figure.
 *
 *   cd functions
 *   GOOGLE_APPLICATION_CREDENTIALS=... npx ts-node --compilerOptions '{"module":"commonjs"}' scripts/migrate-eng-balance.ts
 */
import * as admin from "firebase-admin";
import { BALANCE_PATH } from "../src/engineering/engBalance";

async function main(): Promise<void> {
  admin.initializeApp();
  const db = admin.firestore();
  const companies = await db.collection("companies").get();
  let migrated = 0;
  let skipped = 0;
  for (const company of companies.docs) {
    const credits = company.data().credits;
    if (!Number.isFinite(credits)) { skipped++; continue; }
    const ref = db.doc(BALANCE_PATH(company.id));
    if ((await ref.get()).exists) { skipped++; continue; }
    await ref.set({ credits });
    migrated++;
  }
  console.log(`migrated ${migrated}, skipped ${skipped}`);
}

main().catch((err) => { console.error(err); process.exit(1); });
```

- [ ] **Step 2: Dry-run against the test founder**

Confirm `companies/q7V492ASkMNblUz9bw6AGAzsxHa2` gains
`engBalance/current` with `credits: 20`, and that a second run reports it
skipped rather than rewriting it.

- [ ] **Step 3: Commit**

```bash
git add functions/scripts/migrate-eng-balance.ts functions/package.json
git commit -m "chore(eng): one-shot migration of credits into the write-denied balance doc"
```

---

### Task 6: Deploy and verify

**Files:** none — this is the human-gated half.

- [ ] **Step 1: Full suite and build**

Run: `cd functions && npm run build && npx jest && npm run test:rules`
Expected: tsc clean, every suite green.

- [ ] **Step 2: Deploy rules and the two handlers, scoped**

```bash
cd ~/Developer/codepet-eng-backend
firebase functions:list
firebase deploy --only firestore:rules,functions:engStartRun,functions:engWebhook
```

**Rules deploy is global and immediate.** Unlike the scoped function deploy,
it replaces the rules for the whole project the moment it lands. Read the
diff before running it.

- [ ] **Step 3: Run the migration**

- [ ] **Step 4: Prove the hole is closed against production**

From the client, as the test founder, attempt to write
`companies/{uid}/engRuns/{runId}` and `companies/{uid}/engBalance/current`.
Both must be rejected. Then run `npm run verify:eng` with `AUTO_APPROVE=1`
and confirm the balance falls by the run's actual cost.

---

## Open decisions for the founder

1. **Rate limiting.** None of the four engineering handlers call
   `checkAndIncrement`; all fifteen other AI handlers do. This plan closes the
   free-runs hole, but nothing then limits how many *paid* runs a founder
   starts concurrently. An engineering run costs orders of magnitude more than
   a chat turn, so sharing the existing 100,000/day bucket may be the wrong
   shape. Options: share the bucket, give engineering its own much smaller
   one, or cap concurrent in-flight runs per founder instead of daily count.

2. **Whether `companies/{uid}.credits` should be deleted after migration.**
   Leaving it is a second number that looks authoritative and is not — the
   exact confusion that makes bugs. Removing it means anything that displays
   it must move to `engBalance` first. Recommend removing it in the same
   change that updates the client, not before.

3. **Whether the webhook problem changes any of this.** As of writing,
   Anthropic is not delivering `session.status_idled` despite a correctly
   signed endpoint returning 204 to a manual probe. If deliveries never work,
   `engWebhook` never debits at all and Tasks 3–5 protect a path that does not
   run. They are still right, but the priority ordering changes.
