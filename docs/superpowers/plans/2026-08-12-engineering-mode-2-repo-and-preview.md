# Engineering Mode — Repo Onboarding and Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give an engineering run somewhere to build — a repo the founder connects or Codepet creates — and turn a finished run into something they can click: a preview URL, or an honest statement that there isn't one.

**Architecture:** Five Cloud Functions over the GitHub token the existing OAuth flow already stores. No Vercel API integration: Vercel publishes preview URLs as GitHub Deployment statuses, so the token we already hold reads them. The founder installs the Vercel GitHub app once, in their browser, and Codepet never holds a Vercel credential.

**Tech Stack:** Firebase Cloud Functions v2 (TypeScript, Node 22), GitHub REST API, Firestore. Native work is deferred to Plan 3's sheet.

## Two design decisions that shape everything below

**1. Read the preview URL from GitHub, not from Vercel.**

The obvious build is a Vercel OAuth integration: store a Vercel token, call
`/v13/deployments`, read the URL. Don't. When the Vercel GitHub app is
installed, Vercel creates a **GitHub Deployment** on each push with
`environment: "Preview"` and an `environment_url` — readable with the `repo`
scope we already have.

That removes an entire OAuth flow, a second credential to store, seal, rotate
and leak, and a second vendor on the critical path. The cost is real and worth
naming: we can only see previews Vercel chose to publish to GitHub, we cannot
trigger a redeploy, and a founder using Netlify or Cloudflare Pages gets
whatever *those* publish as deployment statuses — which, usefully, is the same
shape. The read is host-agnostic by accident, which is better than
Vercel-specific by design.

**2. Stop duplicating the GitHub token.**

`loadRepo` reads `sealed` off `companies/{uid}/engineering/repo`
(`engRepo.ts:56`), so the token exists in two documents: there and
`connectors/github`. Two copies is two things to rotate and two things to
leak, and the seed script written for Plan 1's runbook literally copies one
into the other.

`engineering/repo` should hold `{ url, defaultBranch }` and nothing secret.
`loadRepo` should take the token from `connectors/github`, the one place the
OAuth callback writes it. Task 1 does this, and it is first because every
later task writes that document.

## Global Constraints

- **Reuse the existing GitHub OAuth.** `GITHUB_SCOPES = ["read:user", "repo"]`
  (`githubOAuthCore.ts:21`) already covers listing, creating, pushing, PRs and
  reading deployments. Do not add a scope, and do not add a second flow.
- **One credential, one document.** After Task 1, the sealed GitHub token
  exists only at `companies/{uid}/connectors/github`.
- **`companies/{uid}/engineering/**` is denied to clients** for read and
  write; `engRuns` and `engBalance` are write-denied. Every write in this plan
  goes through a Cloud Function via the Admin SDK.
- **Never echo a GitHub response body** to a client or a log. A 4xx from the
  API can quote the request, and the request carries the token. Status only,
  via `safeErrorDetail`.
- **Fail closed on `defaultBranch`.** A missing or blank value resolves to "no
  repo linked", never a guessed `"main"` — a repo whose real default is
  `master` would mount a branch that does not exist and die inside a paid run.
- **Degrade honestly.** A repo with no deploy target shows *no preview chip*
  and says why. Never a dead chip, never a spinner that never resolves.
- Base URL: `https://us-central1-devpet-8f4b1.cloudfunctions.net`.
- Every handler follows the Plan 1 shape: `verifyAuth` → `isSafePathSegment`
  on anything reaching a Firestore path → work in try/catch → content-free
  diagnostics.

## File Structure

- `functions/src/engineering/engRepo.ts` — `loadRepo` reads the token from
  `connectors/github`; add `writeRepoLink`.
- `functions/src/engineering/engGitHub.ts` — **new.** Every GitHub REST call
  in one module: `listRepos`, `createRepo`, `getDefaultBranch`, `openPR`,
  `latestPreview`. One place that holds a token and one place to audit for
  leaks.
- `functions/src/engineering/engRepoHandlers.ts` — **new.** `engListRepos`,
  `engLinkRepo`, `engCreateRepo`.
- `functions/src/engineering/engShip.ts` — **new.** `engShip` (open the PR),
  `engPreview` (read the deployment status).
- `functions/src/index.ts` — five new exports.

---

### Task 1: One home for the GitHub token

**Files:**
- Modify: `functions/src/engineering/engRepo.ts:56-80`
- Modify: `functions/src/engineering/__tests__/engRepo.test.ts`
- Modify: `functions/scripts/seal-repo-doc.ts` (it exists to write the copy this task removes)

**Interfaces:**
- Consumes: `companies/{uid}/connectors/github` → `{ sealed }`, written by
  `githubOAuth.ts:116`.
- Produces: `loadRepo` unchanged in signature; `engineering/repo` now
  `{ url, defaultBranch }` only.

- [ ] **Step 1: Write the failing tests**

```typescript
it("takes the token from the connector, not from the repo document", async () => {
  seedDoc(`companies/u1/connectors/github`, { sealed: seal("tok_from_connector") });
  seedDoc(`companies/u1/engineering/repo`, { url: REPO_URL, defaultBranch: "main" });
  const repo = await loadRepo("u1", KEY);
  expect(repo?.token).toBe("tok_from_connector");
});

it("returns null when the repo is linked but GitHub is not connected", async () => {
  // Disconnecting GitHub must stop runs, not run them with a stale copy.
  seedDoc(`companies/u1/engineering/repo`, { url: REPO_URL, defaultBranch: "main" });
  expect(await loadRepo("u1", KEY)).toBeNull();
});

it("ignores a sealed token left on the repo document by the old shape", async () => {
  // Migration safety: a stale copy must not be preferred, or reconnecting
  // GitHub would silently keep using the revoked one.
  seedDoc(`companies/u1/connectors/github`, { sealed: seal("current") });
  seedDoc(`companies/u1/engineering/repo`, {
    url: REPO_URL, defaultBranch: "main", sealed: seal("stale")
  });
  expect((await loadRepo("u1", KEY))?.token).toBe("current");
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd functions && npx jest src/engineering/__tests__/engRepo.test.ts`
Expected: FAIL — `loadRepo` reads `data.sealed`.

- [ ] **Step 3: Implement**

Read `connectors/github` for the sealed blob; keep the silent-catch on decrypt
failure exactly as it is (a tampered blob resolves to "connect a repo", never
a decryption error shown to a founder).

- [ ] **Step 4: Verify green, and prove the guard**

Point the read back at `data.sealed`, watch the three tests go red, restore.

- [ ] **Step 5: Retire the duplication in the seed script**

`seal-repo-doc.ts` exists only to produce the copy this task removes. Make it
emit `{ url, defaultBranch }` and print a line saying the token now comes from
the connector.

- [ ] **Step 6: Commit**

---

### Task 2: `engGitHub` — every GitHub call in one module

**Files:**
- Create: `functions/src/engineering/engGitHub.ts`
- Test: `functions/src/engineering/__tests__/engGitHub.test.ts`

**Interfaces:**
- Produces:
  - `listRepos(token): Promise<RepoChoice[]>` — `{ fullName, url, defaultBranch, private, pushedAt }`, sorted by `pushedAt` descending, capped at 100.
  - `createRepo(token, name, description): Promise<RepoChoice>`
  - `getDefaultBranch(token, owner, repo): Promise<string | null>`
  - `openPR(token, owner, repo, head, base, title, body): Promise<{ number: number; url: string }>`
  - `latestPreview(token, owner, repo, ref): Promise<{ url: string; state: string } | null>`

One module because it is the only place a token is held in memory, which makes
"does this leak?" a question about one file.

- [ ] **Step 1: Write the failing tests** against a `fetch` stub. The ones
      that matter:

```typescript
it("never includes the token in a thrown error", async () => {
  fetchReturns(403, `forbidden for token ${TOKEN}`);
  await expect(listRepos(TOKEN)).rejects.toThrow();
  const err = await listRepos(TOKEN).catch((e) => e);
  expect(String(err.message)).not.toContain(TOKEN);
});

it("returns null rather than throwing when a repo has no preview yet", async () => {
  // A run that finishes before the deploy does is normal, not an error.
  fetchReturns(200, JSON.stringify([]));
  expect(await latestPreview(TOKEN, "o", "r", "sha")).toBeNull();
});

it("picks the newest successful preview, not merely the newest", async () => {
  // A failed redeploy after a good one must not replace a working URL with a
  // dead link.
  fetchReturns(200, JSON.stringify([
    { environment: "Preview", created_at: "2026-08-12T10:00:00Z",
      statuses: [{ state: "failure", environment_url: "https://broken" }] },
    { environment: "Preview", created_at: "2026-08-12T09:00:00Z",
      statuses: [{ state: "success", environment_url: "https://works" }] }
  ]));
  expect((await latestPreview(TOKEN, "o", "r", "sha"))?.url).toBe("https://works");
});

it("ignores a Production deployment when asked for a preview", async () => {
  fetchReturns(200, JSON.stringify([
    { environment: "Production", statuses: [{ state: "success", environment_url: "https://live" }] }
  ]));
  expect(await latestPreview(TOKEN, "o", "r", "sha")).toBeNull();
});
```

- [ ] **Step 2–4: Verify failing, implement, verify green, commit**

---

### Task 3: `engListRepos` and `engLinkRepo`

**Files:**
- Create: `functions/src/engineering/engRepoHandlers.ts`
- Test: `functions/src/engineering/__tests__/engRepoHandlers.test.ts`
- Modify: `functions/src/index.ts`

**Interfaces:**
- `GET /engListRepos` → `{ repos: RepoChoice[] }`, or `409 github_not_connected`.
- `POST /engLinkRepo { fullName }` → `200 { url, defaultBranch }`.

`engLinkRepo` reads `default_branch` from the API at link time — the value the
founder's repo actually has, not one we assume. If GitHub does not report one,
respond `422` and write nothing: a half-written link is the failure `loadRepo`
cannot distinguish from no link at all.

- [ ] **Step 1: Write the failing tests**

```typescript
it("409s when GitHub is not connected, rather than showing an empty repo list", async () => {
  // An empty list reads as "you have no repos" — a dead end. The founder
  // needs to be sent to the connect flow.
  noConnector();
  await handleEngListRepos(req, res);
  expect(res.status).toHaveBeenCalledWith(409);
  expect(jsonBody(res).error).toBe("github_not_connected");
});

it("refuses to link a repo whose default branch GitHub does not report", async () => {
  githubDefaultBranch(null);
  await handleEngLinkRepo(makeReq({ fullName: "o/r" }), res);
  expect(res.status).toHaveBeenCalledWith(422);
  expect(writes()).toHaveLength(0);   // nothing half-written
});

it("rejects a fullName that is not owner/repo before it reaches a URL", async () => {
  await handleEngLinkRepo(makeReq({ fullName: "../../evil" }), res);
  expect(res.status).toHaveBeenCalledWith(400);
});
```

- [ ] **Step 2–4: Verify failing, implement, verify green, commit**

---

### Task 4: `engCreateRepo`

**Files:**
- Modify: `functions/src/engineering/engRepoHandlers.ts`
- Test: same suite

**Interfaces:**
- `POST /engCreateRepo { name? }` → `200 { url, defaultBranch, vercelSetupUrl }`.

Creates a **private** repo with an initial commit — `auto_init: true`, so it
has a default branch immediately. A repo with no commits has no default branch,
and `loadRepo` would fail closed on the link we just wrote.

`vercelSetupUrl` is `https://vercel.com/new/git/github/<owner>/<repo>`. We
return the link; the founder installs the app. Codepet never holds a Vercel
credential.

**What to scaffold is an open question in the spec (§11)** — empty repo with a
README, or a stack inferred from the brief. This plan implements the README,
deliberately: it cannot be wrong, it ships inside the freeze, and the agent's
first run can scaffold whatever stack the founder actually wants. Revisit after
beta.

- [ ] **Step 1: Write the failing tests**

```typescript
it("creates the repo with an initial commit, so it has a default branch", async () => {
  await handleEngCreateRepo(makeReq({}), res);
  expect(createRepoArgs().auto_init).toBe(true);
});

it("creates a private repo", async () => {
  // The founder's product source. Public is not a default anyone chose.
  await handleEngCreateRepo(makeReq({}), res);
  expect(createRepoArgs().private).toBe(true);
});

it("does not link the repo when creation succeeds but the link write fails", async () => {
  // The repo now exists on GitHub and is not linked here. Report it, with the
  // URL, so the founder can link it rather than creating a second one.
  firestoreWriteFails();
  await handleEngCreateRepo(makeReq({}), res);
  expect(res.status).toHaveBeenCalledWith(503);
  expect(jsonBody(res).createdRepoUrl).toBeTruthy();
});

it("derives a slug from the company name and never sends an invalid one", async () => {
  seedCompany({ name: "Mona's Café ☕" });
  await handleEngCreateRepo(makeReq({}), res);
  expect(createRepoArgs().name).toMatch(/^[A-Za-z0-9._-]+$/);
});
```

- [ ] **Step 2–4: Verify failing, implement, verify green, commit**

---

### Task 5: `engShip` and `engPreview`

**Files:**
- Create: `functions/src/engineering/engShip.ts`
- Test: `functions/src/engineering/__tests__/engShip.test.ts`
- Modify: `functions/src/index.ts`

**Interfaces:**
- `POST /engShip { runId }` → `200 { prNumber, prUrl }`.
- `GET /engPreview?runId=` → `200 { url, state } | { url: null, reason }`.

**`engShip` opens a PR. It does not merge.** The spec's button says "Ship
this", and the honest meaning of that at this stage is "put this up for
deploy" — merging someone's default branch from a button, on a run they may
have skim-read, is not a thing to build before there is a review pane people
trust. The wording stays; the action is a PR.

`engPreview`'s `reason` is what makes the no-preview case honest, and it is a
closed set: `no_deploy_target` (no Deployments at all — the Vercel app is not
installed), `pending` (Deployment exists, no successful status yet),
`failed` (latest status is a failure).

- [ ] **Step 1: Write the failing tests**

```typescript
it("reports no_deploy_target rather than pending when nothing is watching the repo", async () => {
  // These are different states and the founder should be told different
  // things: one is "install Vercel", the other is "wait".
  githubDeployments([]);
  expect(jsonBody(await getPreview()).reason).toBe("no_deploy_target");
});

it("reports pending while the deployment exists but has not succeeded", async () => {
  githubDeployments([{ environment: "Preview", statuses: [{ state: "in_progress" }] }]);
  expect(jsonBody(await getPreview()).reason).toBe("pending");
});

it("404s engShip for a run that is not the caller's", async () => {
  // The run document is addressed under the caller's own uid; a runId from
  // another founder simply does not resolve.
  seedRunUnder("other_uid", "run_1");
  await handleEngShip(makeReq({ runId: "run_1" }), res);
  expect(res.status).toHaveBeenCalledWith(404);
});

it("does not open a second PR for a run that already has one", async () => {
  seedRun({ runId: "run_1", prNumber: 7 });
  await handleEngShip(makeReq({ runId: "run_1" }), res);
  expect(openPR).not.toHaveBeenCalled();
  expect(jsonBody(res).prNumber).toBe(7);
});
```

- [ ] **Step 2–4: Verify failing, implement, verify green, commit**

---

### Task 6: The connect-or-create sheet

**Files:**
- Create: `codepet/Views/Engineering/ConnectRepoSheet.swift`
- Create: `codepet/Services/EngineeringRepoClient.swift`
- Test: `codepetTests/ConnectRepoSheetTests.swift`

The spec's §5.4, once, on the first Engineering send:

> **Where should Codepet build?**
> `[ Connect a GitHub repo ]` — pick from your repos
> `[ Create one for me ]` — Codepet scaffolds `<company-slug>` and wires up preview deploys

Three states this must handle, because all three are reachable on a first run:
GitHub not connected (send to the existing OAuth flow first), connected with
repos (the list), connected with none (only create).

- [ ] **Step 1: Write the failing tests** — one per state, plus: the sheet
      appears **once**, and dismissing without choosing does not start a run
      and does not spend credits.

- [ ] **Step 2–4: Implement, verify green, commit**

- [ ] **Step 5: HAND OFF** — Screen Recording is denied, so whether this reads
      well is Mona's call. One question: "does 'Create one for me' read as
      safe, or as something that might touch your existing repos?"

---

### Task 7: Ship and preview in the Review pane

**Files:**
- Modify: `codepet/Views/Engineering/ReviewPane.swift` (Plan 3, Task 11)
- Test: `codepetTests/ReviewPaneShipTests.swift`

**Depends on Plan 3.** Sequence it after.

- [ ] **Step 1: Write the failing tests**

```swift
func testNoPreviewChipWhenThereIsNoDeployTarget() {
    // A dead chip is worse than no chip. The spec's own words: repos with no
    // deploy target "degrade honestly to diff+PR".
    pane.preview = .unavailable(reason: .noDeployTarget)
    XCTAssertFalse(pane.showsPreviewChip)
    XCTAssertTrue(pane.explainsWhyNoPreview)
}

func testShipDisablesWhileInFlightSoTwoTapsCannotOpenTwoPRs() { ... }

func testShipSaysOpenPRNotMerge() {
    // "Ship this" is the label; the action is a PR. The button must not imply
    // it merged anything.
    XCTAssertFalse(pane.shipConfirmationText.localizedCaseInsensitiveContains("merged"))
}
```

- [ ] **Step 2–4: Implement, verify green, commit**

---

### Task 8: Deploy and verify

- [ ] **Step 1:** `npm run build && npx jest && npm run test:rules`
- [ ] **Step 2:** Scoped deploy of the five new functions. Check
      `firebase functions:list` first and confirm the export set is a superset.
- [ ] **Step 3:** Live: create a repo, install the Vercel app from the returned
      link, run an engineering task, ship it, watch the preview URL appear.
      **Needs Anthropic credits** — blocked until the account is topped up.

---

## Self-review notes

**Spec coverage.** §5.4 → Task 6. "Ship this" / preview (§5.3) → Tasks 5, 7.
Decision 5 (preview via the Vercel GitHub app) → Tasks 2, 4, 5.

**Three deliberate divergences, each flagged rather than absorbed:**

1. **No Vercel API integration.** Preview URLs come from GitHub Deployment
   statuses. Removes an OAuth flow and a stored credential; costs the ability
   to trigger a redeploy.
2. **`engShip` opens a PR, it does not merge.** The label stays "Ship this".
3. **A created repo gets a README, not a scaffolded stack.** The spec leaves
   this open (§11); the README cannot be wrong and the agent's first run can
   build whatever the founder actually wants.

**One correction folded in:** Task 1 removes the duplicated GitHub token. Plan
1 shipped `loadRepo` reading a second sealed copy from `engineering/repo`, and
the runbook's seed script exists solely to write that copy. Two copies of a
credential is two things to rotate, and a disconnected GitHub account would
otherwise keep working from the stale one.

**Open question for Mona:** confirm "Ship this" opening a PR rather than
merging matches what you meant by the word.
