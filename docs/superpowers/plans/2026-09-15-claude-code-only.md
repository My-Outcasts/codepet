# Claude-Code-Only (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the founder's own Claude Code the only way Codepet runs a model, and delete the hosted AI path from the repo.

**Architecture:** An existing `URLProtocol` interceptor (`CloudAIBlock`) becomes unconditional, so no client can reach a key-spending endpoint even if someone forgets to update it. The two transport routers drop their `.cloud` case in favour of `.blocked(reason)`, which every caller must handle. Entitlements move client-side. The 18 hosted AI functions leave the repo; production is left deployed and untouched.

**Tech Stack:** Swift 5 / SwiftUI (macOS 26.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), TypeScript Cloud Functions on Node 22, XCTest, jest.

**Spec:** `docs/superpowers/specs/2026-09-15-claude-code-only-design.md` — read it first. It outranks this plan.

## Global Constraints

- **Never commit to `main`.** Branch, PR, and state what was verified.
- **Run `./scripts/build-sidecar.sh` after ANY change under `functions/src/`** — without it the routers report `localUnavailable` and the founder is told the runner is missing. The bundles are gitignored, so this never shows up in `git status`.
- **Never delete a `*Core.ts` builder.** They are what the sidecars bundle. Deleting a handler must not take its builder with it. This is the single most likely way to get this change wrong.
- **Run Swift suites with `-only-testing:`.** The XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates; a whole-suite run exits 65 on a clean checkout and is not a regression.
- **No `codepet.app` may be running** while `xcodebuild test` runs — it kills the test host.
- **CI is the only place the full Swift suite runs.** A green local run is evidence, not proof. Open a PR (even draft) to get CI; pushing a branch alone runs nothing.
- **Never run a full `firebase deploy --only functions`.** `extractKnowledge` and `scaffoldRoadmap` are live in production and absent from `main`; a full deploy deletes them silently. Phase 1 deploys nothing at all.
- **A guard needs a test that goes red when the guard is deleted.** If a test passes with and without the code it protects, it protects nothing.
- Build signed: `DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates`.

## File Structure

| File | Responsibility after this plan |
| --- | --- |
| `codepet/Services/CloudAIBlock.swift` | Unconditional refusal of the 17 key-spending paths. Loses the per-company switch. |
| `codepet/Services/LocalTransportRouter.swift` | Answers `.local` or `.blocked(Reason)`. No hosted case. |
| `codepet/Services/ChatTransportRouter.swift` | Same, for streaming chat. |
| `codepet/Services/BlockReason.swift` | **New.** The founder-facing reason a run cannot start, shared by both routers. |
| `codepet/Managers/PlanTier.swift` | **New.** Client-side `resolvePlanTier`, reading `entitlements/{uid}`. |
| `codepet/Views/Settings/ClaudeCodePanel.swift` | Loses the "never use API key" switch; keeps grant + probe. |
| `functions/src/` | 18 AI handlers, `anthropic.ts`, `rateLimit.ts`, `entitlements.ts` deleted. All `*Core.ts` untouched. |

---

### Task 1: `CloudAIBlock` refuses unconditionally

The interceptor already exists and already covers all six clients. This removes the choice.

**Files:**
- Modify: `codepet/Services/CloudAIBlock.swift:45-73`
- Modify: `codepet/Views/Settings/ClaudeCodePanel.swift:206-212,335`
- Modify: `codepet/Managers/CompanyStore.swift:456`
- Test: `codepetTests/CloudAIBlockTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `CloudAIBlock.shouldRefuse(_ request: URLRequest) -> Bool` now returns `true` for any blocked path regardless of company or settings. `CloudAIBlock.apply(companyId:defaults:)`, `isEnabled`, `setEnabled` and `forcedOn` are **deleted**.

- [ ] **Step 1: Write the failing test**

Append to `codepetTests/CloudAIBlockTests.swift`:

```swift
/// **The refusal is no longer a preference.** Codepet does not hold an Anthropic key any more,
/// so a request to a key-spending endpoint cannot succeed — it can only fail slowly, after a
/// round trip, with a 401 the founder cannot act on. Refusing locally is the honest answer.
func testRefusesWithoutAnyCompanyOrSetting() {
    let url = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/runTask")!
    XCTAssertTrue(CloudAIBlock.shouldRefuse(URLRequest(url: url)),
                  "a key-spending path was allowed through with no company set")
}

/// The neighbours must still pass. Blocking the whole host would break repo connection for a
/// change that says nothing about GitHub.
func testStillAllowsTheNonAIneighbours() {
    for path in ["githubOAuthStart", "githubOAuthCallback", "engShip", "engPreview",
                 "engDiff", "engListRepos", "engLinkRepo", "engCreateRepo",
                 "revenueCatWebhook", "capabilities"] {
        let url = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/\(path)")!
        XCTAssertFalse(CloudAIBlock.shouldRefuse(URLRequest(url: url)),
                       "\(path) spends no Anthropic key and must not be refused")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/CloudAIBlockTests 2>&1 | grep -E "Test Case .*(passed|failed)|Executed"
```

Expected: `testRefusesWithoutAnyCompanyOrSetting` FAILS — `isRefusing` defaults to `false`.

- [ ] **Step 3: Make the refusal unconditional**

In `codepet/Services/CloudAIBlock.swift`, delete `isRefusing`, `apply`, `isEnabled`, `setEnabled` and `forcedOn`, and change `shouldRefuse` to:

```swift
    /// Whether this request would spend the API key. Pure, so it is testable without a
    /// network or a registered protocol.
    ///
    /// **No longer gated on a setting.** Codepet holds no Anthropic key: every one of these
    /// endpoints answers 401, and every one of them has a local path. Refusing here turns a
    /// slow remote failure the founder cannot act on into an immediate local one that names
    /// the real problem.
    static func shouldRefuse(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              url.host?.contains(hostFragment) == true else { return false }
        return blockedPaths.contains(url.lastPathComponent)
    }
```

- [ ] **Step 4: Remove the switch from Settings**

In `codepet/Views/Settings/ClaudeCodePanel.swift`, delete the `neverUseApiKey` toggle block (around lines 200-215) and its `@State`/assignment at line 335. Leave the grant switch and the install probe untouched.

In `codepet/Managers/CompanyStore.swift`, delete line 456 (`CloudAIBlock.apply(companyId: companyId)`).

- [ ] **Step 5: Run the tests**

Same command as Step 2, plus `-only-testing:codepetTests/ClaudeCodePanelTests` if that suite exists.

Expected: PASS. Fix compile errors from the deleted symbols before re-running.

- [ ] **Step 6: Commit**

```bash
git add codepet/Services/CloudAIBlock.swift codepet/Views/Settings/ClaudeCodePanel.swift \
        codepet/Managers/CompanyStore.swift codepetTests/CloudAIBlockTests.swift
git commit -F - <<'EOF'
Refusing the API key is no longer a choice

CloudAIBlock was an opt-in switch: a founder could decide Codepet may not spend its Anthropic
key. There is no key left to spend — it was deleted from the console on 26 Aug and every
endpoint behind it answers 401 — so the switch only chose between failing immediately and
failing after a round trip with an error the founder cannot act on.

The interceptor stays exactly where it was, below all six HTTP clients, because that is the
half of the guarantee that covers a client nobody remembered to update. It simply no longer
asks permission. The neighbours are still allowed through, and a test names all ten of them:
GitHub OAuth and the repo handlers spend a GitHub secret, not this one.
EOF
```

---

### Task 2: A shared `BlockReason`

Both routers need to say *why* a run cannot start, in words a founder can act on. One type, so the two cannot drift.

**Files:**
- Create: `codepet/Services/BlockReason.swift`
- Test: `codepetTests/BlockReasonTests.swift`

**Interfaces:**
- Produces: `enum BlockReason: Equatable { case notGranted, claudeCodeMissing, sidecarMissing, noFolderLinked }` with `var founderText: String` and `var founderTextVi: String`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/BlockReasonTests.swift`:

```swift
import XCTest
@testable import codepet

/// **Three problems with three fixes must not share one sentence.** "Codepet can't reach its
/// local runner" was the only copy the old `.localUnavailable(String)` carried, and it was
/// shown for a missing grant, a missing CLI and a missing sidecar alike — a founder told to
/// check the wrong thing three times.
final class BlockReasonTests: XCTestCase {

    func testEveryReasonHasItsOwnWords() {
        let all: [BlockReason] = [.notGranted, .claudeCodeMissing, .sidecarMissing, .noFolderLinked]
        let texts = Set(all.map(\.founderText))
        XCTAssertEqual(texts.count, all.count, "two reasons share a sentence")
        for r in all {
            XCTAssertFalse(r.founderText.isEmpty)
            XCTAssertFalse(r.founderTextVi.isEmpty, "\(r) has no Vietnamese copy")
        }
    }

    /// The copy names the fix, not the internal state. "not authorised" is our word for it.
    func testTheCopyNamesAnActionTheFounderCanTake() {
        // Case-insensitive: the copy reads "Install it, then try again." A case-sensitive
        // `contains("install")` fails against it, and the cheapest way to make it pass is to
        // lowercase the copy — shipping a sentence that starts with a small letter.
        XCTAssertTrue(BlockReason.claudeCodeMissing.founderText.lowercased().contains("install"))
        XCTAssertTrue(BlockReason.noFolderLinked.founderText.lowercased().contains("folder"))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/BlockReasonTests 2>&1 | grep -E "error:|Executed"
```

Expected: FAIL to compile — `cannot find type 'BlockReason' in scope`.

- [ ] **Step 3: Write it**

Create `codepet/Services/BlockReason.swift`:

```swift
// codepet/Services/BlockReason.swift
import Foundation

/// Why a run cannot start on this Mac.
///
/// **One type for both routers.** `LocalTransportRouter` and `ChatTransportRouter` each carried
/// their own `localUnavailable(String)`, and the string was written at the throw site — so the
/// same missing sidecar produced different words depending on which feature hit it first.
///
/// The copy names the FIX rather than the state. A founder cannot act on "not authorised"; she
/// can act on "turn on Codepet's access to your Claude plan in Settings".
enum BlockReason: Equatable {
    /// Signed in, Claude Code present, but this company has not granted it.
    case notGranted
    /// The `claude` CLI is not installed on this Mac.
    case claudeCodeMissing
    /// Granted and installed, but the bundled runner is missing — a build problem, not a
    /// founder one. Almost always `scripts/build-sidecar.sh` was not run.
    case sidecarMissing
    /// A build was asked for with no project folder linked to this session.
    case noFolderLinked

    var founderText: String {
        switch self {
        case .notGranted:
            return "Codepet needs permission to use your Claude plan. Turn it on in Settings."
        case .claudeCodeMissing:
            return "Codepet runs on Claude Code. Install it, then try again."
        case .sidecarMissing:
            return "Codepet can't reach its local runner on this Mac. Reinstalling Codepet should restore it."
        case .noFolderLinked:
            return "Link a project folder to this session before building."
        }
    }

    var founderTextVi: String {
        switch self {
        case .notGranted:
            return "Codepet cần quyền dùng gói Claude của bạn. Bật trong Cài đặt."
        case .claudeCodeMissing:
            return "Codepet chạy trên Claude Code. Hãy cài đặt rồi thử lại."
        case .sidecarMissing:
            return "Codepet không tìm thấy trình chạy cục bộ trên máy này. Cài đặt lại Codepet sẽ khôi phục nó."
        case .noFolderLinked:
            return "Hãy liên kết thư mục dự án cho phiên này trước khi build."
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/BlockReason.swift codepetTests/BlockReasonTests.swift
git commit -F - <<'EOF'
One reason type, so the two routers cannot disagree

Both transport routers carried `localUnavailable(String)`, with the string written at each
throw site. The same missing sidecar therefore produced different words depending on which
feature reached it first, and a missing grant, a missing CLI and a missing bundle all shared
one sentence about the local runner — a founder told to check the wrong thing twice out of
three times.

The copy names the fix rather than the state, because "not authorised" is our word for it and
not something a founder can act on. A test asserts the four reasons never share a sentence and
that both languages are filled in.
EOF
```

---

### Task 3: `LocalTransportRouter` drops `.cloud`

**Files:**
- Modify: `codepet/Services/LocalTransportRouter.swift:29-35,85-126`
- Modify: `codepet/Services/RunTaskClient.swift:184-200`
- Modify: `codepet/Services/DecisionsClient.swift:41`
- Modify: `codepet/Services/CompanyData.swift:377`
- Modify: `codepet/Services/ReflectionAPIClient.swift:723`
- Test: `codepetTests/LocalTransportRouterTests.swift`

**Interfaces:**
- Consumes: `BlockReason` from Task 2.
- Produces: `LocalTransportRouter.Transport` is now `enum Transport: Equatable { case local; case blocked(BlockReason) }`. `transport(companyId:authorisation:sidecarAvailable:)` keeps its signature and return type name.

- [ ] **Step 1: Write the failing test**

Append to `codepetTests/LocalTransportRouterTests.swift`:

```swift
/// **There is no hosted runner to fall back to.** This is a totality check rather than a
/// behaviour one: it fails to compile the day someone adds a case that reaches a Cloud
/// Function, which is the only moment the mistake is cheap to fix.
func testTransportIsOnlyEverLocalOrBlocked() {
    let cases: [LocalTransportRouter.Transport] = [.local, .blocked(.notGranted)]
    for c in cases {
        switch c {
        case .local, .blocked: continue   // exhaustive: adding a case breaks the build
        }
    }
}

func testAnUngrantedCompanyIsBlockedRatherThanSentToTheCloud() {
    var auth = ClaudeCodeAuthorisation()
    auth.isAuthorised = { _ in false }
    let t = LocalTransportRouter.transport(companyId: "c1", authorisation: auth,
                                           sidecarAvailable: { true })
    XCTAssertEqual(t, .blocked(.notGranted))
}

func testAGrantedCompanyWithNoSidecarSaysSo() {
    var auth = ClaudeCodeAuthorisation()
    auth.isAuthorised = { _ in true }
    let t = LocalTransportRouter.transport(companyId: "c1", authorisation: auth,
                                           sidecarAvailable: { false })
    XCTAssertEqual(t, .blocked(.sidecarMissing))
}

/// No company id used to mean "cloud". It now means the same thing an ungranted one does.
func testNoCompanyIdIsBlockedNotCloud() {
    let t = LocalTransportRouter.transport(companyId: nil, authorisation: ClaudeCodeAuthorisation(),
                                           sidecarAvailable: { true })
    XCTAssertEqual(t, .blocked(.notGranted))
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/LocalTransportRouterTests 2>&1 | grep -E "error:|Executed"
```

Expected: FAIL to compile — `type 'LocalTransportRouter.Transport' has no member 'blocked'`.

- [ ] **Step 3: Change the enum and the decision**

In `codepet/Services/LocalTransportRouter.swift`, replace the enum (lines 29-35):

```swift
    enum Transport: Equatable {
        case local
        /// Cannot run here, and why. **There is deliberately no hosted case**: Codepet holds
        /// no Anthropic key, so "fall back to the Cloud Function" is not a slower success, it
        /// is a 401 the founder cannot act on.
        case blocked(BlockReason)
    }
```

Replace the body of `transport(companyId:authorisation:sidecarAvailable:)` (lines ~105-126):

```swift
    static func transport(
        companyId: String? = activeCompanyId,
        authorisation: ClaudeCodeAuthorisation = ClaudeCodeAuthorisation(),
        sidecarAvailable: () -> Bool
    ) -> Transport {
        guard let companyId, !companyId.isEmpty else {
            log.error("transport: blocked — no companyId (mirror unset)")
            return .blocked(.notGranted)
        }
        guard authorisation.isAuthorised(companyId) else {
            log.error("transport: blocked — companyId=\(companyId, privacy: .public) not granted")
            return .blocked(.notGranted)
        }
        guard sidecarAvailable() else {
            log.error("transport: blocked — companyId=\(companyId, privacy: .public) granted but sidecar missing")
            return .blocked(.sidecarMissing)
        }
        log.error("transport: local — companyId=\(companyId, privacy: .public) granted, sidecar available")
        return .local
    }
```

- [ ] **Step 4: Update the four callers**

In each of `RunTaskClient.swift:198`, `DecisionsClient.swift:41`, `CompanyData.swift:377` and `ReflectionAPIClient.swift:723`, delete the `case .cloud:` branch and everything below it that builds and sends the HTTP request, replacing the switch's remaining arm. `RunTaskClient` becomes:

```swift
        switch LocalTransportRouter.forOneShot() {
        case .local:
            do {
                let body = try JSONEncoder().encode(req)
                let out = try await LocalOneShotRunner.run(op: "runTask", body: body)
                let decoded = try JSONDecoder().decode(RunTaskResponse.self, from: out)
                LocalTransportRouter.log.error(
                    "local runTask succeeded: kind=\(decoded.kind, privacy: .public) title=\(decoded.title, privacy: .public) bodyLen=\(decoded.body.count, privacy: .public)")
                return decoded
            } catch {
                LocalTransportRouter.log.error(
                    "local runTask failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        case .blocked(let reason):
            LocalTransportRouter.log.error(
                "runTask blocked: \(String(describing: reason), privacy: .public)")
            return nil
        }
```

Apply the same shape to the other three: `.blocked` logs the reason and returns the same "no answer" value the old `.localUnavailable` path returned. Delete any now-unused `endpoint` constants and `URLRequest` construction the compiler flags.

- [ ] **Step 5: Run the tests**

```bash
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/LocalTransportRouterTests \
  -only-testing:codepetTests/RunTaskClientTests 2>&1 | grep -E "Test Case .*failed|Executed"
```

Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add codepet/Services/LocalTransportRouter.swift codepet/Services/RunTaskClient.swift \
        codepet/Services/DecisionsClient.swift codepet/Services/CompanyData.swift \
        codepet/Services/ReflectionAPIClient.swift codepetTests/LocalTransportRouterTests.swift
git commit -F - <<'EOF'
The one-shot router has nowhere else to send a run

`.cloud` is gone from `LocalTransportRouter`, and with it the four call sites that built an
HTTP request to a function that answers 401. What used to be "not granted, so use the Cloud
Function" is now `.blocked(.notGranted)` — the same outcome the code already produced in
practice, said honestly.

The seam itself stays. The router now answers "which runner, or why not" instead of "whose
machine", which is the question a second provider extends rather than replaces.

The totality test is the load-bearing one: it fails to compile the day someone adds a case
that reaches a hosted endpoint, which is the only moment that mistake is cheap.
EOF
```

---

### Task 4: `ChatTransportRouter` drops `.cloud`

Streaming chat has its own enum and two `case .cloud` branches. Same change, separate task because it can be reviewed and reverted independently.

**Files:**
- Modify: `codepet/Services/ChatTransportRouter.swift:33,73,126`
- Modify: `codepet/Models/ChatTailAction.swift:69`
- Modify: `codepet/Managers/CompanyStore.swift:1877,2311`
- Modify: `codepet/Diagnostics/ChatTurnDiagnostic.swift:49`
- Test: `codepetTests/ChatTransportRouterTests.swift`

**Interfaces:**
- Consumes: `BlockReason` from Task 2.
- Produces: `ChatTransportRouter.Transport` becomes `{ case local; case blocked(BlockReason) }`. `CompanyStore.localUnavailableCopy(_:language:)` is replaced by `BlockReason.founderText` / `.founderTextVi`; delete the old static.

- [ ] **Step 1: Write the failing test**

Append to `codepetTests/ChatTransportRouterTests.swift`:

```swift
func testChatTransportIsOnlyEverLocalOrBlocked() {
    let cases: [ChatTransportRouter.Transport] = [.local, .blocked(.notGranted)]
    for c in cases {
        switch c {
        case .local, .blocked: continue
        }
    }
}

/// The tail action shows the reason's own words, not a generic runner sentence.
func testTheChatTailShowsTheReasonsOwnCopy() {
    XCTAssertEqual(BlockReason.notGranted.founderText,
                   "Codepet needs permission to use your Claude plan. Turn it on in Settings.")
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/ChatTransportRouterTests 2>&1 | grep -E "error:|Executed"
```

Expected: FAIL to compile — no `blocked` member.

- [ ] **Step 3: Change the enum and both branches**

In `ChatTransportRouter.swift`, replace `case cloud` and `case localUnavailable(String)` with `case blocked(BlockReason)`, and delete the two `case .cloud:` arms at lines 73 and 126 together with the request-building code beneath them.

- [ ] **Step 4: Route the copy through `BlockReason`**

In `CompanyStore.swift`, delete `localUnavailableCopy(_:language:)` (line 2311) and change line 1877 to:

```swift
                chatMessages[i].text = language == .vi ? reason.founderTextVi : reason.founderText
```

In `ChatTailAction.swift:69` and `ChatTurnDiagnostic.swift:49`, replace the `.localUnavailable` pattern matches with `.blocked`.

- [ ] **Step 5: Run the tests**

```bash
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/ChatTransportRouterTests \
  -only-testing:codepetTests/CompanyStoreTests 2>&1 | grep -E "Test Case .*failed|Executed"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add codepet/Services/ChatTransportRouter.swift codepet/Models/ChatTailAction.swift \
        codepet/Managers/CompanyStore.swift codepet/Diagnostics/ChatTurnDiagnostic.swift \
        codepetTests/ChatTransportRouterTests.swift
git commit -F - <<'EOF'
Streaming chat loses its hosted branch too

The same change as the one-shot router, kept separate so it could be reverted on its own. Two
`case .cloud:` arms went, along with the request building beneath them.

`CompanyStore.localUnavailableCopy` went with them. It existed to turn a reason string into
founder-facing words, which is now `BlockReason`'s job — and doing it in one place is what
stops the chat tail and the run card describing the same blocker differently.
EOF
```

---

### Task 5: A build with no folder linked is blocked, not sent to the cloud agent

`CLAUDE.md` names `startSessionBuild` with no folder as the only call that can still reach the cloud agent by design. With the agent's functions deleted, that route has to close.

**Files:**
- Modify: `codepet/Managers/CodingRunCoordinator.swift` (the `startSessionBuild` / `startBuild` dispatch)
- Test: `codepetTests/CodingRunCoordinatorTests.swift`

**Interfaces:**
- Consumes: `BlockReason.noFolderLinked` from Task 2.
- Produces: `startSessionBuild` returns/If it currently dispatches to the cloud agent, it now sets the run to `.failed(BlockReason.noFolderLinked.founderText)`.

- [ ] **Step 1: Find the dispatch and write the failing test**

```bash
grep -n "startSessionBuild" -A 20 codepet/Managers/CodingRunCoordinator.swift | head -30
```

Append to `codepetTests/CodingRunCoordinatorTests.swift`:

```swift
/// **A grant is not a folder.** `startBuild` sends a granted founder WITH a linked folder to
/// `ClaudeCodeRunner`; without one it used to reach the cloud coding agent, because a local
/// run would land in `.noProject`. That agent's functions no longer exist, so the call would
/// now fail remotely with nothing to say. It fails here instead, naming the fix.
func testABuildWithNoFolderLinkedIsBlockedAndSaysWhy() async {
    let coordinator = CodingRunCoordinator()
    await coordinator.startSessionBuild(folder: nil, prompt: "add a button")
    guard case .failed(let message) = coordinator.state else {
        return XCTFail("a build with no folder did not fail; state was \(coordinator.state)")
    }
    XCTAssertEqual(message, BlockReason.noFolderLinked.founderText)
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/CodingRunCoordinatorTests 2>&1 | grep -E "Test Case .*failed|error:|Executed"
```

Expected: FAIL — the run dispatches instead of failing.

- [ ] **Step 3: Close the route**

Replace the cloud-agent dispatch in `startSessionBuild` with:

```swift
        guard folder != nil else {
            // The cloud coding agent's functions are gone; there is nothing on the other end
            // of this call. Say what to do instead of failing on a 404 a minute from now.
            state = .failed(BlockReason.noFolderLinked.founderText)
            return
        }
```

- [ ] **Step 4: Run the tests**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Managers/CodingRunCoordinator.swift codepetTests/CodingRunCoordinatorTests.swift
git commit -F - <<'EOF'
A build with no folder asks for a folder

CLAUDE.md named `startSessionBuild` with no folder linked as the only call that could still
reach the cloud coding agent by design. Those functions are being deleted, so the route would
have become the one thing the rest of this change exists to prevent: a live call to something
that is not there.

It fails locally now, with the fix in the message, rather than after a round trip to a handler
that no longer exists.
EOF
```

---

### Task 6: `resolvePlanTier` moves into the app

**Files:**
- Create: `codepet/Managers/PlanTier.swift`
- Test: `codepetTests/PlanTierTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `enum PlanTier: String { case free, full }` and `struct PlanTierResolver { var read: (String) async -> [String: Any]?; func tier(uid: String) async -> PlanTier }`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/PlanTierTests.swift`:

```swift
import XCTest
@testable import codepet

/// The tier used to be resolved server-side by `generatePlan`, which is being deleted. The
/// RevenueCat webhook still writes `entitlements/{uid}`; this reads it.
///
/// **The absent document is the important case.** A founder who has never subscribed has no
/// document at all, and Firestore answers nil rather than `{pro: false}` — reading that as
/// "no answer, assume full" would hand every feature to everyone.
final class PlanTierTests: XCTestCase {

    private func resolver(_ doc: [String: Any]?) -> PlanTierResolver {
        PlanTierResolver(read: { _ in doc })
    }

    func testAProSubscriberGetsFull() async {
        let t = await resolver(["pro": true]).tier(uid: "u1")
        XCTAssertEqual(t, .full)
    }

    func testAnExplicitlyNonProAccountGetsFree() async {
        let t = await resolver(["pro": false]).tier(uid: "u1")
        XCTAssertEqual(t, .free)
    }

    func testAMissingDocumentIsFreeNotFull() async {
        let t = await resolver(nil).tier(uid: "u1")
        XCTAssertEqual(t, .free, "an absent entitlement was read as a subscription")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/PlanTierTests 2>&1 | grep -E "error:|Executed"
```

Expected: FAIL to compile — `cannot find 'PlanTierResolver' in scope`.

- [ ] **Step 3: Write it**

Create `codepet/Managers/PlanTier.swift`:

```swift
// codepet/Managers/PlanTier.swift
import Foundation
import FirebaseFirestore

/// What the founder has paid for.
///
/// This used to be answered by `generatePlan` on the server, reading `entitlements/{uid}`.
/// That function is gone with the rest of the hosted AI path, and the work it gated now runs
/// on the founder's own machine — so the check comes to the client.
///
/// **Spoofable, and accepted.** A founder willing to edit her own Firestore document can lift
/// her own tier. What is protected is a feature tier, not somebody else's compute, and the
/// previous arrangement was not stronger: on the local path `generatePlan` already answered
/// `tier: "full"` because there was no entitlement to read.
enum PlanTier: String, Equatable {
    case free
    case full
}

/// Reads the entitlement. The read is a closure so the rule is testable without Firestore —
/// `Firestore.firestore()` traps rather than throwing under an unconfigured `FirebaseApp`,
/// which kills the XCTest host and reads as an assertion failure.
struct PlanTierResolver {

    var read: (String) async -> [String: Any]? = { uid in
        try? await Firestore.firestore()
            .collection("entitlements").document(uid).getDocument().data()
    }

    func tier(uid: String) async -> PlanTier {
        guard let doc = await read(uid), let pro = doc["pro"] as? Bool else { return .free }
        return pro ? .full : .free
    }
}
```

- [ ] **Step 4: Run the tests**

Same command as Step 2. Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Managers/PlanTier.swift codepetTests/PlanTierTests.swift
git commit -F - <<'EOF'
The tier is read on the machine that uses it

`resolvePlanTier` lived in `entitlements.ts` and had exactly one caller, `generatePlan`, which
is being deleted with the rest of the hosted path. The work it gated now runs on the founder's
own Claude plan, so the check follows it to the client.

The read is injected rather than called directly: `Firestore.firestore()` traps instead of
throwing under an unconfigured FirebaseApp, and that kills the XCTest host in a way that reads
as an assertion failure rather than a configuration one.

The absent-document case is the one worth a test. A founder who never subscribed has no
document, Firestore answers nil rather than `{pro: false}`, and treating "no answer" as "no
gate" would hand every paid feature to everyone.
EOF
```

---

### Task 7: The onboarding gate — DEFERRED, needs its own plan

**Not implementable from this document, and deliberately not written as steps.** The project's
working agreement is that UI changes are proposed and approved before they are built, so writing
view code here would be guessing at a screen nobody has agreed. Steps without code are how a plan
lies about being ready.

**What it will need when it is planned:**
- The three failure states are already modelled by `BlockReason` (Task 2): `claudeCodeMissing`,
  `notGranted`, `sidecarMissing`. The screen decides what each one OFFERS — an install link, a
  grant switch, a rebuild instruction.
- The parts exist in `codepet/Views/Settings/ClaudeCodePanel.swift`: a `.notInstalled` blocker
  with an install path, the probe, and the grant switch. This is a promotion, not a new feature.
- The decision belongs in a pure static beside a thin view, the way `PrototypeModeToggle` keeps
  `PrototypeMode.isLocked` testable and `DraftCardCopy.shouldShowNotFiledNote` keeps its rule out
  of the view. That is what makes the gate testable at all.

**Sequencing:** Tasks 1-6 and 8-10 do not depend on it. The gate is what makes the hosted branch
unreachable *by construction*; until it lands, `CloudAIBlock` (Task 1) and the `.blocked` routers
(Tasks 3-4) are what make it unreachable *in fact*. Both are real; the gate is what stops a
founder reaching an AI feature before she has a runner, rather than being told mid-run.

Propose the screen, get approval, then write a plan for it.

---

### Task 8: Delete the hosted AI functions

Do this LAST on the TypeScript side, after the Swift no longer routes to any of them.

**Files:**
- Delete: the 18 handler files for `summarizeTurn`, `summarizeSession`, `chatSession`, `enrichBrief`, `companyChat`, `runTask`, `engStartRun`, `engStream`, `engWebhook`, `engSendTurn`, `generateRoadmap`, `extractDecisions`, `generateGuidance`, `generatePlan`, `distillReference`, `synthesizeBrief`, `generateDictionary`, `virtualCompanyRun`
- Delete: `functions/src/anthropic.ts`, `functions/src/rateLimit.ts`, `functions/src/entitlements.ts`
- Modify: `functions/src/index.ts` — remove those 18 exports
- Test: `functions/src/__tests__/sidecarBuildersSurvive.test.ts` (new)

**Interfaces:**
- Consumes: nothing.
- Produces: `functions/src/index.ts` exports exactly 10 names: `capabilities`, `githubOAuthStart`, `githubOAuthCallback`, `engListRepos`, `engLinkRepo`, `engCreateRepo`, `engShip`, `engPreview`, `engDiff`, `revenueCatWebhook`.

- [ ] **Step 1: Write the guard test FIRST**

Create `functions/src/__tests__/sidecarBuildersSurvive.test.ts`:

```typescript
import { ONE_SHOT_OPS } from "../local/oneShotOps";

/**
 * The deletion's one real risk.
 *
 * The `*Core.ts` builders live in `functions/` beside the handlers being deleted, but they are
 * not hosted code — `scripts/build-sidecar.sh` bundles them into the app, and they carry the
 * department output contract. Deleting a handler and its builder together would take the local
 * path down with the hosted one, and nothing else in this suite would notice.
 */
describe("the sidecar's builders survive the deletion", () => {
  test("every one-shot op still resolves", () => {
    const names = Object.keys(ONE_SHOT_OPS);
    expect(names.length).toBeGreaterThanOrEqual(12);
    for (const n of names) {
      expect(typeof ONE_SHOT_OPS[n].plan).toBe("function");
      expect(typeof ONE_SHOT_OPS[n].respond).toBe("function");
    }
  });

  test("runTask still builds a department-contracted prompt", () => {
    const plan = ONE_SHOT_OPS.runTask.plan({ task_title: "Cost of inference", dept_key: "fin" });
    expect(plan.prompt).toContain("This function produces sheet, doc.");
    expect(plan.prompt).not.toContain("screens");
  });
});
```

- [ ] **Step 2: Run it and watch it pass BEFORE deleting anything**

```bash
cd functions && npx jest src/__tests__/sidecarBuildersSurvive.test.ts
```

Expected: PASS. This is the baseline — it must still pass after Step 3.

- [ ] **Step 3: List the files first, then delete what the list found**

`rm -f` succeeds silently on a path that does not exist, which would leave a handler behind and
the export set wrong. Resolve the paths from the export names instead of typing them:

```bash
cd ~/Developer/codepet-dept-outputs/functions/src
for n in summarizeTurn summarizeSession chatSession enrichBrief companyChat runTask \
         generateRoadmap extractDecisions generateGuidance generatePlan distillReference \
         synthesizeBrief generateDictionary virtualCompanyRun engStartRun engStream \
         engWebhook engSendTurn anthropic rateLimit entitlements; do
  f=$(find . -name "$n.ts" -not -path "*/__tests__/*")
  [ -n "$f" ] && echo "DELETE $f" || echo "MISSING $n.ts  <-- resolve before continuing"
done
```

Every line must read `DELETE`. A `MISSING` line means the file is named differently or already
gone — find out which before going on. Then delete exactly those paths, and remove the matching
`export const` blocks and `import` lines from `functions/src/index.ts`.

**Do not delete any `*Core.ts` file.** The `find` above cannot match one, because no core file is
named after an export — that is the point of the naming.

Then remove the matching `export const` blocks and their `import` lines from `functions/src/index.ts`. **Do not delete any `*Core.ts` file.**

- [ ] **Step 4: Verify the builders survived and the suite is green**

```bash
cd ~/Developer/codepet-dept-outputs/functions
npx tsc --noEmit && npx jest 2>&1 | tail -6
```

Expected: `tsc` clean; jest green. Delete the `__tests__` files belonging to deleted handlers — they will fail to compile, and that is correct.

- [ ] **Step 5: Confirm the export set**

```bash
grep -oE "^export const [a-zA-Z]+" src/index.ts | awk '{print $3}' | sort
```

Expected exactly: `capabilities`, `engCreateRepo`, `engDiff`, `engLinkRepo`, `engListRepos`, `engPreview`, `engShip`, `githubOAuthCallback`, `githubOAuthStart`, `revenueCatWebhook`.

- [ ] **Step 6: Rebuild the sidecars — REQUIRED**

```bash
cd ~/Developer/codepet-dept-outputs && ./scripts/build-sidecar.sh
grep -c "This function produces" codepet/Resources/oneShotSidecar.js
```

Expected: `1`. If the bundle fails to build, a `*Core.ts` was deleted — restore it.

- [ ] **Step 7: Commit**

```bash
git add -A functions/src
git commit -F - <<'EOF'
Delete the hosted AI path

Eighteen exports that declared ANTHROPIC_API_KEY, plus the `getClient` chokepoint, the daily
rate limiter, and `entitlements.ts` whose only caller went with them. Nothing in the surviving
ten imports any of it — the repo handlers spend a GitHub secret and the webhook writes a
document it never reads back through that module.

**No `*Core.ts` was touched.** Those are not hosted code that happens to live here: esbuild
bundles them into the app's sidecars, and they carry the department output contract. A test
added before the deletion asserts every one-shot op still resolves and that runTask still
builds Finance a contracted prompt — it passed before this commit and passes after, which is
the only reason to trust the deletion.

Production is deliberately untouched. The functions stay deployed and inert; undeploying is a
separate deliberate step, and must not be a full `firebase deploy --only functions` while
`extractKnowledge` and `scaffoldRoadmap` are live and absent from main.
EOF
```

---

### Task 9: Remove the credit economics

**Files:**
- Modify: `functions/src/engineering/engBudget.ts`
- Test: `functions/src/engineering/__tests__/engBudget.test.ts`

**Interfaces:**
- Produces: `engBudget.ts` keeps any non-credit helpers; `CREDIT_CENTS`, `DEFAULT_RUN_CREDITS`, `creditsToBudget` and `listCostToCredits` are gone.

- [ ] **Step 1: Delete the credit tests that no longer describe anything**

Remove the cases in `functions/src/engineering/__tests__/engBudget.test.ts` that assert on `CREDIT_CENTS`, `DEFAULT_RUN_CREDITS`, `creditsToBudget` or `listCostToCredits`.

- [ ] **Step 2: Run the suite and watch it fail to compile**

```bash
cd functions && npx jest src/__tests__/engBudget.test.ts
```

Expected: FAIL — the file still imports symbols the test no longer uses, or the remaining tests reference deleted ones.

- [ ] **Step 3: Delete the four symbols** from `functions/src/engineering/engBudget.ts`.

Their only non-test consumers are `engStartRun.ts` (`creditsToBudget`) and `engWebhook.ts`
(`listCostToCredits`), and **both files are deleted in Task 8** — so if Task 8 is complete there
is nothing else to update. Verify rather than assume:

```bash
cd ~/Developer/codepet-dept-outputs/functions
grep -rn "CREDIT_CENTS\|DEFAULT_RUN_CREDITS\|creditsToBudget\|listCostToCredits" src \
  --exclude-dir=__tests__ | grep -v "engBudget.ts:"
```

Expected: no output. Any line here is a consumer Task 8 did not remove — resolve it before deleting.

- [ ] **Step 4: Verify**

```bash
cd functions && npx tsc --noEmit && npx jest 2>&1 | tail -5
```

Expected: `tsc` clean, jest green.

- [ ] **Step 5: Rebuild the sidecars and commit**

```bash
cd ~/Developer/codepet-dept-outputs && ./scripts/build-sidecar.sh
git add -A functions/src && git commit -F - <<'EOF'
Credits stop existing

`CREDIT_CENTS`, `DEFAULT_RUN_CREDITS`, `creditsToBudget` and `listCostToCredits` priced runs
Codepet paid for. Codepet pays for no runs now — the founder's own Claude plan does — so a
credit is a unit of nothing.

The subscription survives: RevenueCat still writes `entitlements/{uid}` and the app still
reads it. What is gone is metering inference nobody is billed for.
EOF
```

---

### Task 10: Full verification and PR

- [ ] **Step 1: Quit the app, then run the affected Swift suites**

```bash
osascript -e 'tell application id "app.murror.codepet" to quit'
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -only-testing:codepetTests/CloudAIBlockTests \
  -only-testing:codepetTests/BlockReasonTests \
  -only-testing:codepetTests/LocalTransportRouterTests \
  -only-testing:codepetTests/ChatTransportRouterTests \
  -only-testing:codepetTests/PlanTierTests \
  -only-testing:codepetTests/CodingRunCoordinatorTests 2>&1 | grep -E "Executed|TEST"
```

Expected: `** TEST SUCCEEDED **`, 0 failures.

- [ ] **Step 2: Run the functions suite**

```bash
cd functions && npx tsc --noEmit && npx jest 2>&1 | tail -5
```

- [ ] **Step 3: Rebuild the sidecars one final time and confirm the contract is in the bundle**

```bash
cd ~/Developer/codepet-dept-outputs && ./scripts/build-sidecar.sh
grep -c "This function produces" codepet/Resources/oneShotSidecar.js   # expect 1
```

- [ ] **Step 4: Build the app signed**

```bash
xcodebuild -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Push and open a PR** so CI runs the whole Swift suite — the only place it runs.

```bash
git push -u origin <branch>
gh pr create --base main --title "Phase 1: Codepet runs on the founder's own Claude" --body-file <notes>
```

- [ ] **Step 6: Wait for CI green** on both the `test` and `functions` jobs before requesting review. Do not merge on a local run.

---

## Not in this plan

- **Undeploying the 18 functions from production.** A separate deliberate step, and never a full `firebase deploy --only functions` while `extractKnowledge` and `scaffoldRoadmap` are live in prod and absent from `main`.
- **A second provider** (Phase 2). The `.blocked` seam is what it extends.
- **Replacing the server-side caches or the kill switch.** The kill switch is carried as the spec's open question.
