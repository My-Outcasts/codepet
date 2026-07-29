# Part 2C-1 — edit_code Verb + Run Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the `edit_code` verb into the client contract and build the testable logic core that drives a coding run through its lifecycle — plan-preview gate → git/shadow session → run → review → commit/abort — with no UI and no dependence on the `claude` CLI in tests.

**Architecture:** `edit_code` joins the companion-reply contract as an additive verb (like 1B's `walkthrough`). A new `CodingRunCoordinator` drives the run over an injected `CodeRunning` seam (so `ClaudeCodeRunner`'s subprocess is faked in tests) and the **real** `CodeCommitService` from 2B (tests run it against temp git repos / dirs, with the fake runner simulating claude's edits). A pure `EditCodePlanner` + `EditCodeRun` state model hold the decisions (preview gate, backend selection, phase transitions). The streamed exec-log and diff-review **UI are 2C-2**; the Environment link UI is **2C-3**; the CF `edit_code` tool is **2C-server**.

**Tech Stack:** Swift, SwiftUI app (`codepet`), XCTest, xcodebuild, system `git`. Reuses `ClaudeCodeRunner`, `CodeCommitService`, `ProjectLink` (2A/2B). No new dependencies.

## Scope

**Part 2C-1** — the logic core of the coding agent's run lifecycle. In: the `edit_code` reply-contract verb (client parse + dispatch), the pure planner + run-state model, and the `CodingRunCoordinator` (with the `CodeRunning` seam + a `ClaudeCodeRunner` adapter).

**Explicitly deferred:**
- **2C-2:** the streamed exec-log + inline per-file diff-review chat card (the agreed UI); wiring the coordinator's `@Published` run into that card.
- **2C-3:** the Environment "Linked project" UI + the inline "link your project" chat offer + composer chip (design agreed in the 2C UI discussion).
- **2C-server:** a CF `edit_code` tool so the companion *proposes* it (1B-server-style). Until then, 2C-1 is exercised via `MockChat` + unit tests.
- The honest-plan fallback *rendering* (2C-2); 2C-1 surfaces the failure reason on the run state.

## Global Constraints

- Native macOS SwiftUI; scheme `codepet` (lowercase); `@testable import codepet`; XCTest.
- **Additive contract:** `edit_code` is a new optional reply field; existing verbs and their tests unchanged (mirror 1B's additive discipline).
- **Client-only:** `edit_code` executes LOCALLY against `activeProjectLink`; it is never sent to the cloud. If no project is linked, the coordinator surfaces an honest "link a project first" state (it does not run).
- **Safety (from 2B / spec §4):** the coordinator only ever commits to `codepet/<slug>` (git) or applies-with-backup (shadow); never merges/pushes/deploys; a failed run leaves the repo restored.
- Testability: the coordinator depends on `CodeRunning` (injected) — tests use a fake that simulates claude by writing files into the working dir; the coordinator uses the real `CodeCommitService` against temp repos.
- Build/test signing + close-app-before-test (Firestore lock) as in prior plans. New tests here are pure / temp-repo / subprocess (git) and run in the host like `CodeCommitServiceTests`.
- Branch `feat/chat-redesign` (PR #39, held); do not push.

## File Structure

- **Modify** `codepet/Services/CompanyChatClient.swift` — add `EditCodeAction` DTO + `editCode` field to `CompanyChatResponse`/`CompanyChatReply`/`ChatDoneAction`/`DonePayload` (mirrors `walkthrough`).
- **Create** `codepet/Models/EditCodeRun.swift` — the pure run-state model + `EditCodePlanner` (preview gate, backend selection).
- **Create** `codepet/Services/CodeRunning.swift` — the `CodeRunning` protocol + `CodeRunOutcome`, and `ClaudeCodeRunAdapter` (bridges `ClaudeCodeRunner` to it).
- **Create** `codepet/Managers/CodingRunCoordinator.swift` — the run lifecycle driver.
- **Modify** `codepet/Managers/CompanyStore.swift` — hold a `CodingRunCoordinator`; route `edit_code` from `handleDoneAction` to `coordinator.propose(...)` with the active link.
- **Create tests:** `codepetTests/EditCodeRunTests.swift`, `codepetTests/CodingRunCoordinatorTests.swift`; extend `codepetTests/CompanyChatClientTests.swift`.

---

## Task 1: `edit_code` reply-contract verb (client parse)

**Files:**
- Modify: `codepet/Services/CompanyChatClient.swift`
- Test: `codepetTests/CompanyChatClientTests.swift`

**Interfaces:**
- Produces:
  - `struct EditCodeAction: Codable, Equatable { let ask: String; let plannedFiles: Int; let needsBash: Bool }` — JSON keys `ask`, `planned_files`, `needs_bash`.
  - `editCode: EditCodeAction?` on `CompanyChatResponse` (key `edit_code`), `CompanyChatReply`, `ChatDoneAction` (defaulted nil), and the SSE `DonePayload`.

- [ ] **Step 1: Write the failing decode tests**

Add to `codepetTests/CompanyChatClientTests.swift`:

```swift
    func testResponseDecodesEditCode() throws {
        let data = "{\"reply\":\"On it\",\"edit_code\":{\"ask\":\"fix signup\",\"planned_files\":2,\"needs_bash\":true}}".data(using: .utf8)!
        let r = try JSONDecoder().decode(CompanyChatResponse.self, from: data)
        XCTAssertEqual(r.editCode, EditCodeAction(ask: "fix signup", plannedFiles: 2, needsBash: true))
    }

    func testSendStreamDoneCarriesEditCode() async throws {
        CompanyChatMockURLProtocol.reset()
        CompanyChatMockURLProtocol.responseChunks = [
            "event: done\ndata: {\"model\":\"m\",\"cache_hit\":false,\"edit_code\":{\"ask\":\"x\",\"planned_files\":1,\"needs_bash\":false}}\n\n".data(using: .utf8)!
        ]
        var collected: [CompanyChatStreamEvent] = []
        for try await ev in CompanyChatClient.sendStream(
            makeMinimalRequest(), session: mockedCompanyChatSession(), authTokenProvider: { "fake" }
        ) { collected.append(ev) }
        guard case let .done(_, _, action) = collected.last else { return XCTFail("expected .done") }
        XCTAssertEqual(action.editCode, EditCodeAction(ask: "x", plannedFiles: 1, needsBash: false))
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyChatClientTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `EditCodeAction` / `editCode` not found.

- [ ] **Step 3: Implement in `CompanyChatClient.swift`**

3a. Add the DTO next to `WalkthroughAction`:

```swift
/// A local coding-agent request from byte: the founder wants real code changed.
/// Executed LOCALLY against the active linked project (never sent to the cloud);
/// `plannedFiles`/`needsBash` are a scope estimate that drives the plan-preview gate.
struct EditCodeAction: Codable, Equatable {
    let ask: String
    let plannedFiles: Int
    let needsBash: Bool
    enum CodingKeys: String, CodingKey {
        case ask
        case plannedFiles = "planned_files"
        case needsBash = "needs_bash"
    }
}
```

3b. `CompanyChatResponse`: add `let editCode: EditCodeAction?` + `case editCode = "edit_code"` in its `CodingKeys`.

3c. `CompanyChatReply`: add `let editCode: EditCodeAction?`; add `editCode: EditCodeAction? = nil` to its `init` (after `walkthrough`), assign it.

3d. `ChatDoneAction`: add `let editCode: EditCodeAction?`; add `editCode: EditCodeAction? = nil` to its `init`, assign it.

3e. `send(_:)`: extend the returned `CompanyChatReply` with `editCode: decoded.editCode`.

3f. `handleStreamFrame` `DonePayload`: add `let editCode: EditCodeAction?` + `case editCode = "edit_code"`; extend the built `ChatDoneAction` with `editCode: d.editCode`.

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CompanyChatClientTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: PASS — the two new tests + all pre-existing `CompanyChatClientTests` (no regression).

- [ ] **Step 5: Commit**

```bash
git add codepet/Services/CompanyChatClient.swift codepetTests/CompanyChatClientTests.swift
git commit -F - <<'EOF'
feat(coding-agent): parse edit_code reply verb (Part 2C-1)

Additive EditCodeAction {ask, planned_files, needs_bash} on the reply
contract + SSE done frame; executed locally, never sent to the cloud.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 2: `EditCodeRun` state model + `EditCodePlanner`

**Files:**
- Create: `codepet/Models/EditCodeRun.swift`
- Test: `codepetTests/EditCodeRunTests.swift`

**Interfaces:**
- Produces:
  - `enum CodeBackend: Equatable { case git(branch: String); case shadow }`
  - `enum EditCodePhase: Equatable { case previewing, readyToRun, running, reviewing, committed, discarded, failed(String), noProject }`
  - `struct EditCodeRun: Equatable { let ask: String; let backend: CodeBackend; var phase: EditCodePhase; var diffs: [ClaudeCodeRunner.FileDiff]; var acceptedPaths: Set<String> }`
  - `enum EditCodePlanner { static func needsPreview(plannedFiles: Int, needsBash: Bool) -> Bool; static func backend(for link: ProjectLink) -> CodeBackend }`

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/EditCodeRunTests.swift`:

```swift
import XCTest
@testable import codepet

final class EditCodeRunTests: XCTestCase {

    func test_needsPreview_showsForMultiFileOrBash_skipsSmall() {
        XCTAssertFalse(EditCodePlanner.needsPreview(plannedFiles: 1, needsBash: false)) // small, safe → skip
        XCTAssertTrue(EditCodePlanner.needsPreview(plannedFiles: 2, needsBash: false))  // multi-file → show
        XCTAssertTrue(EditCodePlanner.needsPreview(plannedFiles: 1, needsBash: true))   // Bash → show
        XCTAssertFalse(EditCodePlanner.needsPreview(plannedFiles: 0, needsBash: false)) // nothing planned → skip
    }

    func test_backend_gitVsShadowFromLink() {
        let git = ProjectLink(path: "/p", isGitRepo: true, hasClaudeMd: true)
        let plain = ProjectLink(path: "/p", isGitRepo: false, hasClaudeMd: false)
        if case .git = EditCodePlanner.backend(for: git) {} else { XCTFail("git repo → .git") }
        XCTAssertEqual(EditCodePlanner.backend(for: plain), .shadow)
    }

    func test_gitBackend_branchSlugFromAsk() {
        let link = ProjectLink(path: "/p", isGitRepo: true, hasClaudeMd: false)
        guard case let .git(branch) = EditCodePlanner.backend(for: link, ask: "Fix Signup!") else {
            return XCTFail("expected .git")
        }
        XCTAssertEqual(branch, "codepet/fix-signup")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/EditCodeRunTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — types not found.

- [ ] **Step 3: Implement**

Create `codepet/Models/EditCodeRun.swift`:

```swift
import Foundation

/// Which safe-commit backend a coding run uses (chosen from the linked project).
enum CodeBackend: Equatable {
    case git(branch: String)   // throwaway codepet/<slug> branch
    case shadow                // temp shadow copy + apply-with-backup
}

/// The lifecycle phase of a coding run (spec §2). UI (2C-2) renders from this.
enum EditCodePhase: Equatable {
    case noProject          // no linked project → can't run; UI offers to link
    case previewing         // multi-file/Bash → show the plan-preview, await confirm
    case readyToRun         // small/safe → run immediately
    case running
    case reviewing          // diffs ready, awaiting Approve/Reject
    case committed
    case discarded
    case failed(String)     // honest reason (e.g. "claude not installed")
}

/// The state of one coding run. Pure value type — the coordinator mutates `phase`,
/// `diffs`, and `acceptedPaths` as the run progresses.
struct EditCodeRun: Equatable {
    let ask: String
    let backend: CodeBackend
    var phase: EditCodePhase
    var diffs: [ClaudeCodeRunner.FileDiff]
    var acceptedPaths: Set<String>

    init(ask: String, backend: CodeBackend, phase: EditCodePhase,
         diffs: [ClaudeCodeRunner.FileDiff] = [], acceptedPaths: Set<String> = []) {
        self.ask = ask; self.backend = backend; self.phase = phase
        self.diffs = diffs; self.acceptedPaths = acceptedPaths
    }
}

/// Pure decisions for a coding run.
enum EditCodePlanner {
    /// Show the plan-preview for a multi-file change or anything that may run Bash;
    /// skip it for a single-file, no-Bash edit (the diff review is the real gate).
    static func needsPreview(plannedFiles: Int, needsBash: Bool) -> Bool {
        needsBash || plannedFiles > 1
    }

    static func backend(for link: ProjectLink, ask: String = "") -> CodeBackend {
        link.isGitRepo ? .git(branch: "codepet/" + CommitSlug.make(from: ask)) : .shadow
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/EditCodeRunTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/EditCodeRun.swift codepetTests/EditCodeRunTests.swift
git commit -F - <<'EOF'
feat(coding-agent): EditCodeRun state model + EditCodePlanner (Part 2C-1)

Pure lifecycle phases + preview-gate (multi-file/Bash → preview) + backend
selection (git branch vs shadow) from the linked project.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 3: `CodingRunCoordinator` (runner seam + lifecycle driver)

**Files:**
- Create: `codepet/Services/CodeRunning.swift`
- Create: `codepet/Managers/CodingRunCoordinator.swift`
- Test: `codepetTests/CodingRunCoordinatorTests.swift`

**Interfaces:**
- Consumes: `EditCodeRun`/`EditCodePlanner`/`CodeBackend` (Task 2), `CodeCommitService`/`GitSession`/`ShadowSession` (2B), `ProjectLink` (2A), `ClaudeCodeRunner.FileDiff`.
- Produces:
  - `struct CodeRunOutcome: Equatable { let diffs: [ClaudeCodeRunner.FileDiff]; let failure: String? }`
  - `protocol CodeRunning { func run(prompt: String, workingDir: String) async -> CodeRunOutcome }`
  - `final class ClaudeCodeRunAdapter: CodeRunning` — wraps `ClaudeCodeRunner`, awaits completion, returns the outcome. (Adapter; build-verified, not unit-tested.)
  - `@MainActor final class CodingRunCoordinator: ObservableObject` with `@Published private(set) var run: EditCodeRun?` and:
    - `func propose(ask:plannedFiles:needsBash:link:)` — sets `run` to `.previewing`/`.readyToRun` (or `.noProject` if `link == nil`). Pure/sync.
    - `func execute() async` — begins the backend session, runs the runner in its working dir, sets `.reviewing` with diffs (or `.failed` on `outcome.failure`).
    - `func approve(acceptedPaths:) async` — commits accepted files (git) / applies with backup (shadow); `.committed`.
    - `func reject() async` — aborts (git) / discards (shadow); `.discarded`.

- [ ] **Step 1: Write the failing coordinator tests**

Create `codepetTests/CodingRunCoordinatorTests.swift`:

```swift
import XCTest
@testable import codepet

/// A fake runner that simulates claude by writing `edits` (relPath → contents) into
/// the working dir, then reporting diffs for them (or a failure).
private final class FakeRunner: CodeRunning {
    let edits: [String: String]
    let failure: String?
    init(edits: [String: String] = [:], failure: String? = nil) { self.edits = edits; self.failure = failure }
    func run(prompt: String, workingDir: String) async -> CodeRunOutcome {
        if let failure { return CodeRunOutcome(diffs: [], failure: failure) }
        var diffs: [ClaudeCodeRunner.FileDiff] = []
        for (rel, contents) in edits {
            let url = URL(fileURLWithPath: workingDir).appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let isNew = !FileManager.default.fileExists(atPath: url.path)
            try? contents.write(to: url, atomically: true, encoding: .utf8)
            diffs.append(ClaudeCodeRunner.FileDiff(path: url.path, isNewFile: isNew, lines: []))
        }
        return CodeRunOutcome(diffs: diffs, failure: nil)
    }
}

@MainActor
final class CodingRunCoordinatorTests: XCTestCase {

    private func gitRepo() -> String {
        let base = NSTemporaryDirectory() + "codepet-2c1-git-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
        for a in [["init"],["config","user.email","t@t.co"],["config","user.name","t"]] { _ = GitRunner.run(a, in: base) }
        try? "v1".write(toFile: base + "/app.txt", atomically: true, encoding: .utf8)
        _ = GitRunner.run(["add","."], in: base); _ = GitRunner.run(["commit","-m","init"], in: base)
        return base
    }

    func test_propose_previewsMultiFile_readyForSmall() {
        let link = ProjectLink(path: "/p", isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner())
        c.propose(ask: "x", plannedFiles: 1, needsBash: false, link: link)
        XCTAssertEqual(c.run?.phase, .readyToRun)
        c.propose(ask: "x", plannedFiles: 3, needsBash: false, link: link)
        XCTAssertEqual(c.run?.phase, .previewing)
    }

    func test_propose_noProject_whenLinkNil() {
        let c = CodingRunCoordinator(runner: FakeRunner())
        c.propose(ask: "x", plannedFiles: 1, needsBash: false, link: nil)
        XCTAssertEqual(c.run?.phase, .noProject)
    }

    func test_execute_thenApprove_commitsOnBranch_git() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"]))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        XCTAssertEqual(c.run?.phase, .reviewing)
        XCTAssertEqual(c.run?.diffs.count, 1)
        await c.approve(acceptedPaths: ["app.txt"])
        XCTAssertEqual(c.run?.phase, .committed)
        // Commit landed on the codepet branch; original ref still has v1.
        _ = GitRunner.run(["checkout","-"], in: repo)   // back to original
        XCTAssertEqual(try? String(contentsOfFile: repo + "/app.txt", encoding: .utf8), "v1")
    }

    func test_execute_thenReject_restores_git() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(edits: ["app.txt": "v2"]))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        await c.reject()
        XCTAssertEqual(c.run?.phase, .discarded)
        XCTAssertEqual(try? String(contentsOfFile: repo + "/app.txt", encoding: .utf8), "v1", "reject restores original")
    }

    func test_execute_runnerFailure_surfacesHonestReason() async {
        let repo = gitRepo()
        let link = ProjectLink(path: repo, isGitRepo: true, hasClaudeMd: true)
        let c = CodingRunCoordinator(runner: FakeRunner(failure: "claude not installed"))
        c.propose(ask: "edit", plannedFiles: 1, needsBash: false, link: link)
        await c.execute()
        XCTAssertEqual(c.run?.phase, .failed("claude not installed"))
        // A failed run must leave no dangling codepet branch.
        XCTAssertFalse(GitRunner.run(["branch"], in: repo).stdout.contains("codepet/"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodingRunCoordinatorTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `CodeRunning`/`CodingRunCoordinator` not found.

- [ ] **Step 3: Implement the seam**

Create `codepet/Services/CodeRunning.swift`:

```swift
import Foundation

/// The final outcome of a coding-agent run. Streaming is a UI concern (2C-2); the
/// coordinator only needs the resulting diffs or an honest failure reason.
struct CodeRunOutcome: Equatable {
    let diffs: [ClaudeCodeRunner.FileDiff]
    let failure: String?   // nil = success
}

/// Seam over the code-editing runner so the coordinator is testable without the
/// real `claude` subprocess. Production conformer is `ClaudeCodeRunAdapter`.
protocol CodeRunning {
    func run(prompt: String, workingDir: String) async -> CodeRunOutcome
}

/// Bridges `ClaudeCodeRunner` (an ObservableObject that streams to `@Published`
/// state) to the async `CodeRunning` seam: kicks off the run and resolves once the
/// runner reaches a terminal state, returning its computed `fileDiffs` (or the
/// failure reason). Build-verified glue — not unit-tested (needs the CLI).
@MainActor
final class ClaudeCodeRunAdapter: CodeRunning {
    private let runner = ClaudeCodeRunner()
    private var cancellable: Any?

    func run(prompt: String, workingDir: String) async -> CodeRunOutcome {
        await withCheckedContinuation { (cont: CheckedContinuation<CodeRunOutcome, Never>) in
            // Observe the runner's terminal state, then resume once.
            var resumed = false
            let finish: (CodeRunOutcome) -> Void = { outcome in
                guard !resumed else { return }; resumed = true
                cont.resume(returning: outcome)
            }
            cancellable = runner.$state.sink { state in
                switch state {
                case .finished: finish(CodeRunOutcome(diffs: self.runner.fileDiffs, failure: nil))
                case .failed(let reason): finish(CodeRunOutcome(diffs: [], failure: reason))
                default: break
                }
            }
            runner.run(prompt: prompt, projectDir: workingDir)
        }
    }
}
```

(Note: `ClaudeCodeRunner` exposes `@Published state: RunState` with `.finished(exitCode:)`/`.failed(reason:)` and `@Published fileDiffs`. If the actual case labels differ, match them — the adapter is the only place that touches them, and it's build-verified. Requires `import Combine` for `.sink`.)

- [ ] **Step 4: Implement the coordinator**

Create `codepet/Managers/CodingRunCoordinator.swift`:

```swift
import Foundation
import Combine

/// Drives one coding run through its lifecycle over a `CodeRunning` seam and the
/// real `CodeCommitService`. UI (2C-2) renders from `run`; nothing here draws.
@MainActor
final class CodingRunCoordinator: ObservableObject {
    @Published private(set) var run: EditCodeRun?

    private let runner: CodeRunning
    private let link: () -> ProjectLink?
    // Live backend session handles, set during `execute`.
    private var gitSession: GitSession?
    private var shadowSession: CodeCommitService.ShadowSession?
    private var proposedLink: ProjectLink?

    init(runner: CodeRunning, link: @escaping () -> ProjectLink? = { nil }) {
        self.runner = runner
        self.link = link
    }

    /// Stage a run: no linked project → `.noProject`; else pick the backend and
    /// decide whether the plan-preview is needed. Does not execute.
    func propose(ask: String, plannedFiles: Int, needsBash: Bool, link: ProjectLink?) {
        guard let link else { run = EditCodeRun(ask: ask, backend: .shadow, phase: .noProject); return }
        proposedLink = link
        let backend = EditCodePlanner.backend(for: link, ask: ask)
        let phase: EditCodePhase = EditCodePlanner.needsPreview(plannedFiles: plannedFiles, needsBash: needsBash)
            ? .previewing : .readyToRun
        run = EditCodeRun(ask: ask, backend: backend, phase: phase)
    }

    /// Begin the backend session, run the agent in its working dir, land in
    /// `.reviewing` (diffs) or `.failed`. A failure tears the session down so no
    /// dangling branch / shadow remains.
    func execute() async {
        guard var current = run, let link = proposedLink else { return }
        current.phase = .running; run = current

        let workingDir: String
        switch current.backend {
        case .git:
            guard let s = CodeCommitService.beginGit(projectPath: link.path, taskTitle: current.ask) else {
                current.phase = .failed("Couldn't start a git branch for this run."); run = current; return
            }
            gitSession = s; workingDir = link.path
        case .shadow:
            guard let s = CodeCommitService.beginShadow(projectPath: link.path) else {
                current.phase = .failed("Couldn't prepare a safe copy for this run."); run = current; return
            }
            shadowSession = s; workingDir = s.shadowDir
        }

        let outcome = await runner.run(prompt: current.ask, workingDir: workingDir)
        guard var after = run else { return }
        if let failure = outcome.failure {
            await teardownOnFailure()
            after.phase = .failed(failure); run = after; return
        }
        after.diffs = outcome.diffs
        after.acceptedPaths = Set(outcome.diffs.map { relPath($0.path, under: link.path, shadow: shadowSession?.shadowDir) })
        after.phase = .reviewing
        run = after
    }

    func approve(acceptedPaths: Set<String>) async {
        guard var current = run else { return }
        switch current.backend {
        case .git(let branch):
            if let s = gitSession {
                _ = CodeCommitService.commitGit(s, files: Array(acceptedPaths), message: "codepet: \(current.ask)")
            }
            _ = branch
        case .shadow:
            if let s = shadowSession {
                _ = CodeCommitService.applyShadow(s, acceptedRelPaths: Array(acceptedPaths))
                CodeCommitService.discardShadow(s)
            }
        }
        current.phase = .committed; run = current
        clearSessions()
    }

    func reject() async {
        guard var current = run else { return }
        switch current.backend {
        case .git: if let s = gitSession { CodeCommitService.abortGit(s) }
        case .shadow: if let s = shadowSession { CodeCommitService.discardShadow(s) }
        }
        current.phase = .discarded; run = current
        clearSessions()
    }

    // MARK: - Helpers
    private func teardownOnFailure() async {
        if let s = gitSession { CodeCommitService.abortGit(s) }
        if let s = shadowSession { CodeCommitService.discardShadow(s) }
        clearSessions()
    }
    private func clearSessions() { gitSession = nil; shadowSession = nil; proposedLink = nil }

    /// Absolute diff path → path relative to the commit root (project root for git,
    /// shadow dir for shadow — both map to the same relative layout).
    private func relPath(_ abs: String, under projectRoot: String, shadow: String?) -> String {
        let root = shadow ?? projectRoot
        if abs.hasPrefix(root + "/") { return String(abs.dropFirst(root.count + 1)) }
        return (abs as NSString).lastPathComponent
    }
}
```

- [ ] **Step 5: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodingRunCoordinatorTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -25
```
Expected: PASS — 5 coordinator tests (propose preview/ready, noProject, git approve→commit-on-branch, git reject→restore, runner-failure→honest reason + no dangling branch).

- [ ] **Step 6: Wire `edit_code` dispatch on `CompanyStore`**

Add a coordinator to `CompanyStore` and route the verb. In `CompanyStore.init` (or lazily), construct `CodingRunCoordinator(runner: ClaudeCodeRunAdapter(), link: { [weak self] in self?.activeProjectLink })` and store it as `let codingRun: CodingRunCoordinator`. In `handleDoneAction`, after the walkthrough return handling, dispatch edit_code (it does NOT block the reply — it stages the run for the UI/2C-2 to drive):

```swift
        if let ec = action.editCode {
            codingRun.propose(ask: ec.ask, plannedFiles: ec.plannedFiles, needsBash: ec.needsBash,
                              link: activeProjectLink)
        }
```

(Place this alongside the other orthogonal verb handling in `handleDoneAction`; `edit_code` is orthogonal to run_task/nav/setup — it targets the local backend. Keep the existing `walkthrough` return contract unchanged.)

- [ ] **Step 7: Build + commit**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
git add codepet/Services/CodeRunning.swift codepet/Managers/CodingRunCoordinator.swift codepet/Managers/CompanyStore.swift codepetTests/CodingRunCoordinatorTests.swift
git commit -F - <<'EOF'
feat(coding-agent): CodingRunCoordinator + edit_code dispatch (Part 2C-1)

Drives a coding run over a CodeRunning seam (ClaudeCodeRunAdapter in prod,
fake in tests) + the real CodeCommitService: propose (preview gate + backend
select), execute (begin session → run → reviewing/failed with teardown),
approve (commit git / apply shadow), reject (abort/discard). CompanyStore
routes edit_code from the reply to the coordinator. UI is 2C-2.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**1. Spec coverage (2C-1 logic core):**
- `edit_code` verb parsed on the client contract (additive) → Task 1. ✅
- Adaptive plan-preview gate + git/shadow backend selection (pure) → Task 2. ✅
- Full run lifecycle driven + tested without the CLI (fake runner) or UI, using the real `CodeCommitService` → Task 3. ✅
- Honest failure surfaced + session torn down on failure → Task 3 (`.failed`, `teardownOnFailure`). ✅
- No linked project → `.noProject` (never runs) → Task 3. ✅
- UI (2C-2), Environment link UI (2C-3), CF tool (2C-server), honest-plan *rendering* → deferred. Not gaps.

**2. Placeholder scan:** No TBD/TODO; each code step complete; commands show expected output. The adapter notes the exact `ClaudeCodeRunner` state labels to match at implementation.

**3. Type consistency:** `EditCodeAction`(`ask`/`planned_files`/`needs_bash`), `EditCodePhase`, `EditCodeRun`, `EditCodePlanner.needsPreview`/`.backend(for:ask:)`, `CodeBackend`, `CodeRunning`/`CodeRunOutcome`/`ClaudeCodeRunAdapter`, and `CodingRunCoordinator.propose/execute/approve/reject` are named identically across tasks/tests. `CodeCommitService.beginGit/commitGit/abortGit/beginShadow/applyShadow/discardShadow` and `GitSession`/`ShadowSession` match 2B. `ClaudeCodeRunner.FileDiff(path:isNewFile:lines:)` matches the 2B-era runner.

**Open item to confirm at implementation (Task 3, Step 3):** the exact `ClaudeCodeRunner.RunState` case labels (`.finished` vs `.finished(exitCode:)`, `.failed(reason:)`) — the adapter is the only consumer; match the real enum. If bridging `@Published` proves awkward, an equally valid adapter reads `runner.events`/`state` via a short polling `Task` — behavior-identical to the seam's contract.

**Deferred:** 2C-2 (exec-log + diff-review card UI), 2C-3 (Environment link UI + inline offer + composer chip), 2C-server (CF `edit_code` tool), and streaming the runner's live steps into the card (the adapter currently only needs the terminal outcome).
