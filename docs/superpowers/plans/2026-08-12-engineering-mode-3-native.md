# Engineering Mode — Native Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Engineering mode visible and usable in the macOS app — a founder types an ask, watches the agent work, answers its permission questions, and reads the resulting diff.

**Architecture:** A fourth `ChatMode` in the existing dock, backed by an `EngineeringRunStore` that consumes the SSE relay `engStream` already serves. Review swaps `AppShellView`'s content area into a two-pane workspace. One new Cloud Function (`engDiff`) because the Review pane has no data source today.

**Tech Stack:** SwiftUI (macOS 26.2), Swift 5 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `URLSession.bytes` + the existing `SSEParser`, XCTest. Backend: Firebase Cloud Functions v2, TypeScript.

## Scope decision, stated up front

**The Review pane has no backend.** `engDiff.ts`'s `parseCompare` is fully
written and tested, and **nothing calls it** — verified by grep across
`functions/src`. Plan 1 built the parser and never wired an endpoint. So the
centrepiece of the spec's §5.3 has no data source, and Task 1 here is that
endpoint. It is small (one handler over an already-tested pure function) and
including it keeps this plan a single coherent deliverable rather than a UI
that cannot show anything.

**"Ship this" and the preview URL are OUT of scope**, and that is a real
subtraction from the spec's §5.3 mockup. Both depend on Plan 2 (repo
onboarding + the Vercel GitHub app), which does not exist. The spec already
describes the honest degradation — "Imported repos with no deploy target
degrade honestly to diff+PR" — and this plan implements exactly that: the
Review pane ends at the diff, with no dead chip and no button that does
nothing.

**What ships here:** `.engineering` mode, the collapsed result bar, live
streaming with the exec log, inline approval cards, follow-up turns, the
expanded two-pane workspace, the Review pane with the scope selector and
per-line hit targets.

## Global Constraints

- **Deployment target macOS 26.2.** Not 13.
- **Engineering's accent is `CodepetTheme.accentBlue`** — the Department
  catalog's colour for `key: "eng"` (`Models/Department.swift:48`). Do not
  invent a palette; do not reuse the purple copilot chrome.
- **No decorative icons.** Functional only. Minimalist, space-forward.
- **No Undo button.** The branch is the undo. A dead Undo was already removed
  once in `6982df0` — do not reintroduce it.
- **Approval renders inline in the transcript, never as a modal.** Modal
  dialogs are a known hazard in this codebase and an `npm install` does not
  warrant blocking the app.
- **The diff renderer owns per-line hit targets from day one**, even though
  nothing is wired to them at freeze. Inline line comments are the first thing
  after freeze (spec §10) and must drop in without a rewrite.
- **New `.swift` files need no project-file edit** —
  `PBXFileSystemSynchronizedRootGroup`; target membership follows the folder.
- **The XCTest host crashes on Xcode 26.2** when a `@MainActor
  ObservableObject` deallocates: ~27 of ~970 tests never finish and
  `xcodebuild test` exits 65 on a clean checkout. Run per-suite with
  `-only-testing:` and do not chase it as a regression.
- **Sign builds with team `YL72VTKBR7`** (Apple Development,
  `-allowProvisioningUpdates`). `CODE_SIGNING_ALLOWED=NO` builds run but
  Firebase auth does not work at runtime.
- **Visual verification is a handoff.** Screen Recording is denied, so no
  agent can screenshot the running app. Layout IS measurable offscreen via
  `ImageRenderer` in an XCTest — but it renders nothing inside a `ScrollView`.
  Anything that cannot be measured that way is a specific question for Mona,
  not a claim from green tests.
- **UI changes get approved before implementation.** The spec's §5 mockups are
  already approved; anything that deviates from them is a question, not a
  judgement call.
- Base URL for all handlers:
  `https://us-central1-devpet-8f4b1.cloudfunctions.net`.

## File Structure

**Backend (one function):**
- `functions/src/engineering/engDiff.ts` — add `handleEngDiff` alongside the
  existing pure `parseCompare`. Same file: the handler is the parser's only
  consumer and they change together.
- `functions/src/index.ts` — export `engDiff`.

**Native, mirroring the shapes that already exist:**
- `codepet/Models/EngineeringRun.swift` — `EngineeringPhase`, `ReviewScope`,
  `EngFileDiff`, `EngApproval`. Pure value types, no Firebase, no SwiftUI.
- `codepet/Models/EngineeringFrame.swift` — the SSE frame union and its
  decoder. Separate from the model because it is a wire contract, and it is
  where the tests that protect that contract live.
- `codepet/Services/EngineeringRunning.swift` — the protocol seam, exactly as
  `CodeRunning.swift` does for the local runner.
- `codepet/Services/EngineeringClient.swift` — production conformer.
  `URLSession.bytes` through `SSEParser`, mirroring `VirtualCompanyClient`.
- `codepet/Services/MockEngineeringRunner.swift` — drives the whole flow
  offline, same role as `MockCodeRunner`.
- `codepet/Managers/EngineeringRunStore.swift` — `@MainActor
  ObservableObject`. `@Published phase`, `steps`, `approvals`, `diff`.
- `codepet/Views/Copilot/EngineeringResultBar.swift` — the collapsed card.
- `codepet/Views/Copilot/EngineeringApprovalCard.swift` — the inline ask.
- `codepet/Views/Engineering/EngineeringWorkspaceView.swift` — the two-pane
  expansion.
- `codepet/Views/Engineering/ReviewPane.swift` — scope selector + file list.
- `codepet/Views/Engineering/DiffLineView.swift` — one line, with its hit
  target. Separate file because the deferred comment affordance attaches here
  and nowhere else.

Tests live in `codepetTests/`, one suite per concern, matching the existing
convention.

---

### Task 1: `engDiff` — the endpoint the Review pane reads

**Files:**
- Modify: `functions/src/engineering/engDiff.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/engineering/__tests__/engDiff.test.ts`

**Interfaces:**
- Consumes: `parseCompare(payload) -> DiffSummary` (already written and
  tested), `loadRepo(uid, encKey) -> RepoLink | null`, `verifyAuth`.
- Produces: `GET /engDiff?runId=<id>&scope=<branch|turn|commit>` →
  `200 DiffSummary`, or `401` / `400` / `404` / `503`.

The three scopes are three bases against the same head — that is why one
compare call serves all of them:

| scope | base | head |
|---|---|---|
| `branch` | the repo's `defaultBranch` | the run's branch |
| `turn` | `lastTurnBaseSha` on the run doc | the run's branch |
| `commit` | the commit's first parent | that commit |

`turn` needs `lastTurnBaseSha`, which nothing writes yet. **Fail closed:** when
it is absent, return the `branch` diff and set `scopeFellBack: true` so the
client can say so, rather than silently showing a wider diff than the founder
asked for.

- [ ] **Step 1: Write the failing test**

```typescript
describe("handleEngDiff", () => {
  it("401s without a valid token, before any Firestore or GitHub call", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce(null);
    const res = makeRes();
    await handleEngDiff(makeReq({ runId: "run_1" }), res as never);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(loadRepo).not.toHaveBeenCalled();
  });

  it("rejects a runId that is not a safe path segment, before building a path", async () => {
    (verifyAuth as jest.Mock).mockResolvedValueOnce({ uid: "uid_1" });
    const res = makeRes();
    await handleEngDiff(makeReq({ runId: "../other" }), res as never);
    expect(res.status).toHaveBeenCalledWith(400);
  });

  it("falls back to the branch diff and says so when lastTurnBaseSha is absent", async () => {
    // Silently widening the diff would show the founder changes from earlier
    // turns as if they were this turn's.
    seedRun({ branch: "codepet/run_1", lastTurnBaseSha: undefined });
    const res = makeRes();
    await handleEngDiff(makeReq({ runId: "run_1", scope: "turn" }), res as never);
    expect(jsonBody(res).scopeFellBack).toBe(true);
  });

  it("never puts the GitHub token in the response or the logs", async () => {
    const TOKEN = "github_pat_11SECRET";
    seedRepo({ token: TOKEN });
    githubReturns(500, `upstream said: ${TOKEN}`);
    const spy = spyOnLogs();
    const res = makeRes();
    await handleEngDiff(makeReq({ runId: "run_1" }), res as never);
    expect(callsContainMarker(spy.allCalls(), TOKEN)).toBe(false);
    expect(JSON.stringify(res.json.mock.calls)).not.toContain(TOKEN);
    spy.restore();
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd functions && npx jest src/engineering/__tests__/engDiff.test.ts`
Expected: FAIL — `handleEngDiff` is not exported.

- [ ] **Step 3: Implement the handler**

Follow `engStream.ts`'s opening exactly — `verifyAuth`, then
`isSafePathSegment` on `runId` **before** it reaches `db.doc(...)`, then the
run lookup wrapped in try/catch with `safeErrorDetail`. Call GitHub's
`GET /repos/{owner}/{repo}/compare/{base}...{head}` with the sealed token,
hand the body to `parseCompare`, return it.

On a non-2xx from GitHub, respond `503` with `{ error: "diff_unavailable" }`
and log status only — never the body. A compare error can echo the request,
and the request carries the token.

- [ ] **Step 4: Run to verify they pass**

Run: `cd functions && npx jest src/engineering/__tests__/engDiff.test.ts`
Expected: PASS.

- [ ] **Step 5: Export it**

Add to `functions/src/index.ts`, matching `engStream`'s shape:

```typescript
export const engDiff = onRequest(
  { cors: false, secrets: ["ANTHROPIC_API_KEY", "CONNECTOR_ENC_KEY"] },
  handleEngDiff
);
```

- [ ] **Step 6: Full suite, then commit**

```bash
cd functions && npm run build && npx jest
git add functions/src/engineering/engDiff.ts functions/src/engineering/__tests__/engDiff.test.ts functions/src/index.ts
git commit -m "feat(eng): engDiff — serve the compare the Review pane renders"
```

---

### Task 2: The run model

**Files:**
- Create: `codepet/Models/EngineeringRun.swift`
- Test: `codepetTests/EngineeringRunTests.swift`

**Interfaces:**
- Produces:
  - `enum EngineeringPhase: Equatable { preparing, running, awaitingApproval, reviewing, budgetReached, failed(String) }`
  - `enum ReviewScope: String, CaseIterable { branch, turn, commit }`
  - `struct EngFileDiff: Identifiable, Equatable { id: String (== file), file, path, additions, deletions, status, patch: String? }`
  - `struct EngApproval: Identifiable, Equatable { id: String (toolUseId), name, input: String }`
  - `static func phase(fromStopReason:) -> EngineeringPhase`

Pure value types only. No Firebase import, no SwiftUI import — that is what
lets these be tested without touching the crashing host.

- [ ] **Step 1: Write the failing test**

```swift
final class EngineeringRunTests: XCTestCase {
    func testStopReasonMapsToPhase() {
        XCTAssertEqual(EngineeringRun.phase(fromStopReason: "end_turn"), .reviewing)
        XCTAssertEqual(EngineeringRun.phase(fromStopReason: "budget_reached"), .budgetReached)
        XCTAssertEqual(EngineeringRun.phase(fromStopReason: "requires_action"), .awaitingApproval)
    }

    func testUnknownStopReasonFailsRatherThanInvitingReview() {
        // Mirrors the backend's statusFor: an unhandled reason means "we do not
        // know this finished", not a card inviting the founder to ship.
        guard case .failed = EngineeringRun.phase(fromStopReason: "something_new") else {
            return XCTFail("unknown stop reason must not map to a reviewable phase")
        }
    }

    func testFileDiffIdentityIsTheFileNotTheDisplayLabel() {
        // A rename's `path` is "old → new" and changes between turns; `file` is
        // stable, and is what a fetch keys off.
        let d = EngFileDiff(file: "b.ts", path: "a.ts → b.ts", additions: 1,
                            deletions: 0, status: "renamed", patch: nil)
        XCTAssertEqual(d.id, "b.ts")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme codepet -only-testing:codepetTests/EngineeringRunTests`
Expected: FAIL — no such type.

- [ ] **Step 3: Implement, then re-run**

Expected: PASS. Keep `phase(fromStopReason:)` exhaustive over the backend's
`RunStatus` strings (`engClient.ts`) — those two lists are one contract in two
languages.

- [ ] **Step 4: Commit**

---

### Task 3: The wire contract

**Files:**
- Create: `codepet/Models/EngineeringFrame.swift`
- Test: `codepetTests/EngineeringFrameTests.swift`

**Interfaces:**
- Consumes: the five frames `engStream.ts` emits — `step`, `message`,
  `approval`, `done`, `error`. Nothing else exists on that stream.
- Produces: `enum EngineeringFrame { step(ExecStep), message(String), approval(EngApproval), done(stopReason: String), error(String) }`
  and `static func decode(event: String, data: Data) -> EngineeringFrame?`

- [ ] **Step 1: Write the failing tests, from the backend's exact payloads**

```swift
func testDecodesAStepFrame() {
    // engStream.ts:182 — writeFrame(res, "step", toExecStep(event))
    let data = #"{"id":"sevt_1","label":"read billing.ts","done":false}"#.data(using: .utf8)!
    guard case .step(let s)? = EngineeringFrame.decode(event: "step", data: data) else {
        return XCTFail("expected a step")
    }
    XCTAssertEqual(s.id, "sevt_1")
    XCTAssertFalse(s.done)
}

func testATrueDoneWithAnEmptyLabelIsACompletionMarker() {
    // engEvents.ts documents this shape explicitly — it completes an earlier
    // step by id rather than adding a row.
    let data = #"{"id":"sevt_1","label":"","done":true}"#.data(using: .utf8)!
    guard case .step(let s)? = EngineeringFrame.decode(event: "step", data: data) else {
        return XCTFail("expected a step")
    }
    XCTAssertTrue(s.done)
    XCTAssertTrue(s.label.isEmpty)
}

func testDecodesAnApprovalFrame() {
    // engStream.ts:193 — { toolUseId, name, input }
    let data = #"{"toolUseId":"tu_1","name":"bash","input":{"command":"npm install stripe"}}"#
        .data(using: .utf8)!
    guard case .approval(let a)? = EngineeringFrame.decode(event: "approval", data: data) else {
        return XCTFail("expected an approval")
    }
    XCTAssertEqual(a.id, "tu_1")
    XCTAssertTrue(a.input.contains("npm install stripe"))
}

func testAnUnknownEventNameIsIgnoredRatherThanCrashing() {
    // The relay may gain frames before this client knows them.
    XCTAssertNil(EngineeringFrame.decode(event: "something_new", data: Data("{}".utf8)))
}

func testMalformedJSONIsIgnoredRatherThanThrowing() {
    XCTAssertNil(EngineeringFrame.decode(event: "step", data: Data("not json".utf8)))
}
```

- [ ] **Step 2: Run to verify they fail, implement, re-run to green**

- [ ] **Step 3: Commit**

---

### Task 4: The client seam and its mock

**Files:**
- Create: `codepet/Services/EngineeringRunning.swift`
- Create: `codepet/Services/MockEngineeringRunner.swift`
- Test: `codepetTests/MockEngineeringRunnerTests.swift`

**Interfaces:**
- Produces:

```swift
protocol EngineeringRunning {
    func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String
    func send(runId: String, turn: EngineeringTurn) async throws
    func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary
}

enum EngineeringTurn { case text(String), approve(String), deny(String, reason: String?), interrupt }
```

`EngineeringTurn` mirrors `buildTurnEvents` in `engSendTurn.ts` exactly — the
four shapes that handler accepts, and no fifth.

The mock is not a test fixture. It is how the whole flow is demonstrated and
reviewed without credits, an Anthropic account, or a network — the same role
`MockCodeRunner` plays, and the only way to review this UI while the account
has no balance.

- [ ] **Step 1: Write the failing test** — the mock replays a scripted run:
      two steps, an approval, a resume after `.approve`, a `done`. Assert the
      frames arrive in order and that `.approve` is what unblocks it.

- [ ] **Step 2–3: Implement, verify green**

- [ ] **Step 4: Commit**

---

### Task 5: `EngineeringClient` — the real SSE

**Files:**
- Create: `codepet/Services/EngineeringClient.swift`
- Test: `codepetTests/EngineeringClientTests.swift`

**Interfaces:**
- Consumes: `SSEParser`, `EngineeringFrame.decode`, `EngineeringRunning`.
- Produces: the production conformer.

Mirror `VirtualCompanyClient` — `URLSession.bytes(for:)`, accumulate bytes to
newline, feed `SSEParser`. Do not invent a second SSE reading strategy; there
is one in this codebase and it works.

Two things the backend does that this client must survive:

- **`: heartbeat` comment frames** arrive every few seconds with no event.
  `SSEParser` drops comments; assert it, because a client that treats one as a
  frame will spam the transcript.
- **A run that pauses on `requires_action` holds the connection open
  indefinitely.** That is correct behaviour, not a hang — no timeout, no retry
  on silence.

- [ ] **Step 1: Write the failing tests** against a `URLProtocol` stub that
      emits a canned byte stream, including a heartbeat between two halves of
      a frame.

- [ ] **Step 2–3: Implement, verify green**

- [ ] **Step 4: Commit**

---

### Task 6: `EngineeringRunStore`

**Files:**
- Create: `codepet/Managers/EngineeringRunStore.swift`
- Test: `codepetTests/EngineeringRunStoreTests.swift`

**Interfaces:**
- Consumes: `EngineeringRunning` (injected — that is what makes this testable).
- Produces: `@Published phase`, `@Published steps: [ExecStep]`,
  `@Published approvals: [EngApproval]`, `@Published diff: EngDiffSummary?`,
  and `send(_:)`.

`CompanyStore` is testable through its injected closures; do the same here.
Never construct `EngineeringClient` inside the store.

- [ ] **Step 1: Write the failing tests**

```swift
func testACompletionMarkerCompletesTheEarlierStepRatherThanAddingARow() {
    // { id, label: "", done: true } completes an existing step by id.
    store.handle(.step(ExecStep(id: "s1", label: "ran npm test", done: false)))
    store.handle(.step(ExecStep(id: "s1", label: "", done: true)))
    XCTAssertEqual(store.steps.count, 1)
    XCTAssertTrue(store.steps[0].done)
    XCTAssertEqual(store.steps[0].label, "ran npm test")  // label survives
}

func testAnAnsweredApprovalLeavesTheList() {
    store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm i")))
    XCTAssertEqual(store.approvals.count, 1)
    store.answer(toolUseId: "tu_1", allow: true)
    XCTAssertTrue(store.approvals.isEmpty)
}

func testADuplicateApprovalIdDoesNotStackTwoCards() {
    // The relay replays history on reconnect; the same ask can arrive twice.
    let a = EngApproval(id: "tu_1", name: "bash", input: "npm i")
    store.handle(.approval(a))
    store.handle(.approval(a))
    XCTAssertEqual(store.approvals.count, 1)
}
```

- [ ] **Step 2–3: Implement, verify green**

- [ ] **Step 4: Commit**

---

### Task 7: `.engineering` mode

**Files:**
- Modify: `codepet/Models/ChatMode.swift`
- Test: `codepetTests/ChatModeTests.swift`

**Interfaces:**
- Produces: a fourth case. `ChatComposer` renders `ChatMode.allCases`, so the
  control appears with no view change.

- [ ] **Step 1: Write the failing tests**

```swift
func testEngineeringDoesNotConveneTheRoom() {
    // A room deliberates; engineering executes. Convening would also add
    // ~$0.20 to a mode that already spends real money on a run.
    XCTAssertFalse(ChatMode.engineering.convenesRoom)
}

func testEngineeringHasBothLabels() {
    XCTAssertFalse(ChatMode.engineering.label(.en).isEmpty)
    XCTAssertFalse(ChatMode.engineering.label(.vi).isEmpty)
}
```

- [ ] **Step 2: Run to verify they fail, add the case, re-run**

Vietnamese label: **ask Mona.** Every other mode has a considered translation
("Bắt tay làm" for Build, not a literal rendering); do not invent one.

- [ ] **Step 3: Commit**

---

### Task 8: The collapsed result bar

**Files:**
- Create: `codepet/Views/Copilot/EngineeringResultBar.swift`
- Test: `codepetTests/EngineeringResultBarLayoutTests.swift`

Renders the spec's §5.2 card: the ask, `Worked for Ns` (expandable to the
`ExecStep` rows in `.mono`), and the change summary with a `Review` button.
`Changed 3 files` collapsed, filenames on first expand — one tap, not two.

Accent is `CodepetTheme.accentBlue`. No preview chip: nothing serves one yet,
and a dead chip is worse than no chip.

- [ ] **Step 1: Write the layout test**

Measure offscreen with `ImageRenderer`, as
`DepartmentHeaderLayoutTests` already does. Assert the card is not clipped at
the dock's narrowest width and that the `Review` control keeps its hit area.
**`ImageRenderer` renders nothing inside a `ScrollView`** — measure the card
in isolation, not embedded in the transcript.

- [ ] **Step 2–3: Implement, verify green**

- [ ] **Step 4: Add a `#Preview` with a mock run**, so the gallery covers it
      (`-CODEPET_MOCK_GALLERY YES`).

- [ ] **Step 5: Commit, then HAND OFF.** Whether this *looks* right is Mona's
      call and cannot be claimed from a green test. Ask one specific question:
      "does the result bar read as engineering rather than copilot at dock
      width?"

---

### Task 9: The inline approval card

**Files:**
- Create: `codepet/Views/Copilot/EngineeringApprovalCard.swift`
- Test: `codepetTests/EngineeringApprovalCardTests.swift`

`Wants to run:` + the command in `.mono` + `[Allow] [Not this]`. Inline in the
transcript. Not a sheet, not an alert, not a confirmationDialog.

- [ ] **Step 1: Write the failing tests** — `Allow` sends `.approve(id)`;
      `Not this` sends `.deny(id, reason:)`; the card disappears once answered;
      the buttons disable while the turn is in flight so a double-tap cannot
      send two confirmations for one `tool_use_id`.

- [ ] **Step 2–4: Implement, verify green, commit**

---

### Task 10: The two-pane workspace

**Files:**
- Create: `codepet/Views/Engineering/EngineeringWorkspaceView.swift`
- Modify: `codepet/Views/Shell/AppShellView.swift`
- Test: `codepetTests/EngineeringWorkspaceLayoutTests.swift`

Review **swaps `AppShellView`'s content area** — not a sheet, not a nav
destination. Same thread, more room. Left: the transcript, exec log, approval
cards, composer. Right: the Review pane.

- [ ] **Step 1: Write the failing test** — entering review swaps the content
      area and leaves the dock's thread state untouched; leaving restores the
      previous destination.

- [ ] **Step 2–4: Implement, verify green, commit**

---

### Task 11: The Review pane

**Files:**
- Create: `codepet/Views/Engineering/ReviewPane.swift`
- Create: `codepet/Views/Engineering/DiffLineView.swift`
- Test: `codepetTests/ReviewPaneTests.swift`, `codepetTests/DiffLineViewTests.swift`

Scope selector (`Last turn` / `Branch` / `Commit`), total `+N −M`, per-file
rows expanding to the patch.

**`DiffLineView` owns a per-line hit target from day one.** Nothing is wired
to it at freeze; inline comments attach here after. Building the renderer
without it means rewriting it in v1.1.

Two honest states the pane must render rather than hide:

- **`truncated: true`** — GitHub caps compare at 300 files. Say the list is
  incomplete; do not show 300 files as if they were all of them.
- **`scopeFellBack: true`** — the founder asked for `Last turn` and got the
  branch diff. Say so.
- **`patch: nil`** — binary file. Show the name and the counts, not an empty
  body that reads like a bug.

- [ ] **Step 1: Write the failing tests** for all three states plus the hit
      target's presence and geometry.

- [ ] **Step 2–4: Implement, verify green, commit**

- [ ] **Step 5: HAND OFF** — long-format scroll is a known trap in this
      codebase: head/foot `flex: none`, body `overflow: auto`. Ask Mona to
      confirm a 60-file diff scrolls without the header collapsing.

---

### Task 12: Honest degradation

**Files:**
- Modify: `EngineeringRunStore.swift`, `EngineeringResultBar.swift`
- Test: `codepetTests/EngineeringDegradationTests.swift`

Every backend failure the founder can actually hit, with the wording it earns.
The status codes are already fixed by Plan 1 — this task only maps them.

| status | means | what the founder sees |
|---|---|---|
| `409 no_repo_linked` | no repo connected | connect-or-create (Plan 2 builds the sheet; until then, plain text) |
| `402 no_credits` | balance is zero | out of credits, with the number |
| `500 misconfigured` | deploy problem | "we broke something" — never blame the founder |
| `503` | Firestore/Anthropic fault | retryable, with a retry control |
| `budgetReached` | run paused at its cap | paused and **resumable** — never "failed" |

- [ ] **Step 1: Write the failing tests**, one per row. The `budgetReached`
      one matters most: telling a founder their work failed when it is sitting
      there intact makes them start over and pay twice.

- [ ] **Step 2–4: Implement, verify green, commit**

---

## Self-review notes

**Spec coverage.** §5.1 → Task 7. §5.2 → Task 8. §5.3 → Tasks 10, 11, 9. §5.4
→ **not covered, deferred to Plan 2 with the reason stated above.** §4.6 →
Tasks 2, 4, 5, 6. §7 → Task 12.

**Two deliberate divergences from the spec**, both flagged rather than
absorbed:
1. `engDiff` was not in any plan. The Review pane cannot exist without it.
2. "Ship this" and the preview URL are out. They need Plan 2.

**One thing to fix in the spec while here:** §11 claims "no SDK upgrade was
needed, `package.json` untouched." That was true of the spike and false of the
build — `budget`, `usage.list_cost` and `budget_reached` do not exist below
`@anthropic-ai/sdk` 0.116.0, and a cast was hiding it. Correct the spec so the
next reader does not trust the older claim.

**Open question for Mona:** the Vietnamese label for `.engineering` (Task 7).
