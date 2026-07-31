# Coding Agent in the Copilot Column — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the local Coding Agent from `feat/chat-redesign` into `main`'s web-parity "Your team" copilot column — describe an engineering change, watch it run against a linked repo (live steps + real diffs), approve into a safe throwaway git commit.

**Architecture:** `main` already ships the execution engine (`ClaudeCodeRunner`) and `ProjectStore`. The redesign's coding-agent layer (`CodingRunCoordinator`, `CodeCommitService`, `GitRunner`, pure models) is UI-free and ports verbatim. We reuse `main`'s runner, lift that layer over via `git show`, then build a single coordinator-driven run **card** on `main`'s `CodepetCard` chrome and wire three local triggers (Let's build / Engineering toggle / Engineering-task Start). The card is rendered in the message list keyed off `companyStore.codingRunAnchorId` (no `CopilotMessage` field — this matches the source implementation and avoids stale-run bugs).

**Tech Stack:** Swift 5, SwiftUI, macOS (non-sandboxed app), XCTest, Xcode project `codepet.xcodeproj` (scheme `codepet`).

## Global Constraints

- **Source of ported files:** verbatim from `feat/chat-redesign` via `git show feat/chat-redesign:<path> > <path>`. Do not re-transcribe.
- **New files auto-join the target:** the project uses `PBXFileSystemSynchronizedRootGroup`. A `.swift` file written under `codepet/` joins the app target; under `codepetTests/` joins the test target. No `.pbxproj` edits.
- **Build (TEAM-signed, required — adhoc breaks keychain/sign-in):**
  `xcodebuild build -project codepet.xcodeproj -scheme codepet -configuration Debug -destination 'platform=macOS' CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`
- **Tests:** `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/<Class>` plus the signing flags above. **Close any running `codepet.app` first** (`pkill -x codepet` or quit) — a live app holds the Firestore LevelDB LOCK and the test host aborts in `FirestoreClient::Initialize`. `** TEST FAILED **` with **0 tests executed** and no `Failing tests:` line = that environmental flake, not a real failure; re-run with the app closed and confirm the test count.
- **Coding-agent safety (never change):** commits only to a throwaway local `codepet/<slug>` branch; never pushes, merges, or deploys.
- **Bilingual copy:** every user-facing string is EN + VI via `@Environment(\.uiLanguage)`.
- **Branch:** work on `feat/coding-agent-copilot` (already created off `main`). Commit after every task.

---

### Task 1: Foundation types — `ExecStep` + `GitRunner`

`ExecStep` (a run's execute-log line) lived inside the redesign's `CopilotMessage.swift`; on `main` it becomes its own file. `GitRunner` is a dependency-free `/usr/bin/git` wrapper + `CommitSlug`.

**Files:**
- Create: `codepet/Models/ExecStep.swift`
- Create: `codepet/Services/GitRunner.swift` (via `git show`)
- Test: `codepetTests/CommitSlugTests.swift`

**Interfaces:**
- Produces: `struct ExecStep: Identifiable, Equatable, Codable { let id: String; let label: String; var done: Bool }`; `enum GitRunner { static func run(_ args: [String], in dir: String) -> GitResult }`; `enum CommitSlug { static func make(from title: String) -> String }`.

- [ ] **Step 1: Create `codepet/Models/ExecStep.swift`**

```swift
// codepet/Models/ExecStep.swift
import Foundation

/// One line in a run's execute-log — the "how the agent is working" transparency
/// shown while a task runs. `done` flips as the step completes.
struct ExecStep: Identifiable, Equatable, Codable {
    let id: String
    let label: String
    var done: Bool
    init(id: String = UUID().uuidString, label: String, done: Bool = false) {
        self.id = id; self.label = label; self.done = done
    }
}
```

- [ ] **Step 2: Port `GitRunner`**

Run: `git show feat/chat-redesign:codepet/Services/GitRunner.swift > codepet/Services/GitRunner.swift`

- [ ] **Step 3: Write the failing test for `CommitSlug`**

```swift
// codepetTests/CommitSlugTests.swift
import XCTest
@testable import codepet

final class CommitSlugTests: XCTestCase {
    func test_make_lowercasesAndHyphenates() {
        XCTAssertEqual(CommitSlug.make(from: "Add Landing Page Copy"), "add-landing-page-copy")
    }
    func test_make_stripsPunctuationAndCollapsesSpaces() {
        XCTAssertFalse(CommitSlug.make(from: "Fix: the  bug!!").contains(" "))
    }
    func test_make_nonEmptyForEmptyInput() {
        XCTAssertFalse(CommitSlug.make(from: "").isEmpty)
    }
}
```

- [ ] **Step 4: Run the test — verify it compiles & passes**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' -only-testing:codepetTests/CommitSlugTests CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`
Expected: PASS (3 tests). If an assertion mismatches `CommitSlug`'s real normalization, read `codepet/Services/GitRunner.swift`'s `CommitSlug.make` and adjust the expected strings to match its actual rules — do not change the source.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ExecStep.swift codepet/Services/GitRunner.swift codepetTests/CommitSlugTests.swift
git commit -m "feat(coding-agent): port ExecStep + GitRunner foundation"
```

---

### Task 2: Reconcile `ClaudeCodeRunner`

`main` already has `ClaudeCodeRunner` (used by the Skills screens). The redesign made a small (+13/−7) change. Adopt the redesign's version, then prove the Skills consumers still build.

**Files:**
- Modify: `codepet/Services/ClaudeCodeRunner.swift` (replace with redesign's version)

**Interfaces:**
- Produces (unchanged names, relied on by later tasks): `ClaudeCodeRunner` (`ObservableObject`) with `@Published state/events/touchedFiles/fileDiffs`, `func run(prompt:projectDir:allowedTools:maxTurns:)`, nested `RunState`, `StreamEvent`, `FileDiff`.

- [ ] **Step 1: Review the diff you're about to adopt**

Run: `git diff main feat/chat-redesign -- codepet/Services/ClaudeCodeRunner.swift`
Confirm it's additive/compatible (no removed public members the Skills views use). If it removes/renames a member, note it — the reconciliation must keep those members.

- [ ] **Step 2: Adopt the redesign's version**

Run: `git show feat/chat-redesign:codepet/Services/ClaudeCodeRunner.swift > codepet/Services/ClaudeCodeRunner.swift`

- [ ] **Step 3: Build the whole app — the real test is that Skills consumers still compile**

Run the TEAM-signed **build** command (Global Constraints).
Expected: `** BUILD SUCCEEDED **`. `ExerciseWorkspaceView.swift` and `RunForRealSection.swift` consume `ClaudeCodeRunner`; a compile error there means a member was dropped — restore it.

- [ ] **Step 4: Commit**

```bash
git add codepet/Services/ClaudeCodeRunner.swift
git commit -m "feat(coding-agent): reconcile ClaudeCodeRunner with redesign version"
```

---

### Task 3: Port the pure models

Pure, UI-free model types. `RoadmapDispatch` is deferred to Task 12 (it couples to the task/roadmap types its trigger uses).

**Files (all via `git show`):**
- Create: `codepet/Models/EditCodeRun.swift`, `codepet/Models/EditCodeRouting.swift`, `codepet/Models/CodeExecSteps.swift`, `codepet/Models/ProjectLink.swift`, `codepet/Models/ClaudeMdBootstrap.swift`
- Test: `codepetTests/EditCodeModelsTests.swift`

**Interfaces:**
- Produces: `enum EditCodePhase { noProject, previewing, readyToRun, running, reviewing, committed, discarded, failed(String) }`; `struct EditCodeRun { let ask; let backend; var phase; var diffs; var acceptedPaths }`; `enum CodeBackend { git(branch:), shadow }`; `enum EditCodePlanner { static func needsPreview(plannedFiles:needsBash:) -> Bool; static func backend(for:ask:) -> CodeBackend }`; `enum EditCodeRouting { static func shouldRoute(department:projectLinked:) -> Bool }`; `enum CodeExecSteps { static func step(for: ClaudeCodeRunner.StreamEvent) -> ExecStep? }`; `struct ProjectLink`, `enum ProjectProbe`.

- [ ] **Step 1: Port the five model files**

```bash
for f in EditCodeRun EditCodeRouting CodeExecSteps ProjectLink ClaudeMdBootstrap; do
  git show feat/chat-redesign:codepet/Models/$f.swift > codepet/Models/$f.swift
done
```

- [ ] **Step 2: Write failing tests for the pure logic**

```swift
// codepetTests/EditCodeModelsTests.swift
import XCTest
@testable import codepet

final class EditCodeModelsTests: XCTestCase {
    // EditCodePlanner: multi-file or bash ⇒ preview; single simple ⇒ no preview.
    func test_needsPreview_multiFile() {
        XCTAssertTrue(EditCodePlanner.needsPreview(plannedFiles: 2, needsBash: false))
    }
    func test_needsPreview_bash() {
        XCTAssertTrue(EditCodePlanner.needsPreview(plannedFiles: 1, needsBash: true))
    }
    func test_needsPreview_singleSimple() {
        XCTAssertFalse(EditCodePlanner.needsPreview(plannedFiles: 1, needsBash: false))
    }
    // Routing: engineering + linked ⇒ route.
    func test_shouldRoute_engAndLinked() {
        let eng = Department.all.first { $0.key == "eng" }
        XCTAssertTrue(EditCodeRouting.shouldRoute(department: eng, projectLinked: true))
    }
    func test_shouldRoute_notLinked() {
        let eng = Department.all.first { $0.key == "eng" }
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: eng, projectLinked: false))
    }
    func test_shouldRoute_nonEng() {
        let mkt = Department.all.first { $0.key != "eng" }
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: mkt, projectLinked: true))
    }
}
```

- [ ] **Step 3: Run the tests — verify pass**

Run: `xcodebuild test … -only-testing:codepetTests/EditCodeModelsTests …` (signing flags).
Expected: PASS. If `Department.all` is named differently on `main`, grep `codepet/Models/Department.swift` for the catalog accessor and use it. If `needsPreview`'s real rule differs, read `EditCodeRun.swift`'s `EditCodePlanner` and align the expected values to the source.

- [ ] **Step 4: Commit**

```bash
git add codepet/Models/EditCodeRun.swift codepet/Models/EditCodeRouting.swift codepet/Models/CodeExecSteps.swift codepet/Models/ProjectLink.swift codepet/Models/ClaudeMdBootstrap.swift codepetTests/EditCodeModelsTests.swift
git commit -m "feat(coding-agent): port pure edit-code models + tests"
```

---

### Task 4: Port `CodeCommitService` (+ its tests)

The safe-commit engine — throwaway git branch or shadow-copy backend. The redesign ships tests; port them.

**Files:**
- Create: `codepet/Services/CodeCommitService.swift` (via `git show`)
- Test: `codepetTests/CodeCommitServiceTests.swift` (via `git show`)

**Interfaces:**
- Produces: `enum CodeCommitService` with `beginGit(projectPath:taskTitle:) -> GitSession?`, `commitGit(_:files:message:) -> GitCommitResult`, `abortGit(_:)`, `beginShadow`, `applyShadow(_:acceptedRelPaths:)`, `undoShadow`, `discardShadow`; structs `GitSession`, `GitCommitResult`, `ShadowSession`.

- [ ] **Step 1: Port the service and its tests**

```bash
git show feat/chat-redesign:codepet/Services/CodeCommitService.swift > codepet/Services/CodeCommitService.swift
git show feat/chat-redesign:codepetTests/CodeCommitServiceTests.swift > codepetTests/CodeCommitServiceTests.swift
```

- [ ] **Step 2: Run the ported tests — verify pass**

Run: `xcodebuild test … -only-testing:codepetTests/CodeCommitServiceTests …` (signing flags). These create temp git repos under the OS temp dir.
Expected: PASS (all cases). A failure here is real (git behavior), not the Firestore flake — read the failing assertion and the service.

- [ ] **Step 3: Commit**

```bash
git add codepet/Services/CodeCommitService.swift codepetTests/CodeCommitServiceTests.swift
git commit -m "feat(coding-agent): port CodeCommitService + tests"
```

---

### Task 5: Port the runner seam — `CodeRunning` + `MockCodeRunner`

`CodeRunning` is the async protocol + `ClaudeCodeRunAdapter` (bridges `main`'s Combine runner). `MockCodeRunner` fakes the AI but makes a real on-disk edit so the commit path still runs — zero `claude` cost, used for tests and the offline flag.

**Files:**
- Create: `codepet/Services/CodeRunning.swift`, `codepet/Services/MockCodeRunner.swift` (via `git show`)
- Test: `codepetTests/MockCodeRunnerTests.swift`

**Interfaces:**
- Produces: `struct CodeRunOutcome { let diffs: [ClaudeCodeRunner.FileDiff]; let failure: String? }`; `protocol CodeRunning { func run(prompt:workingDir:onStep:) async -> CodeRunOutcome }`; `final class ClaudeCodeRunAdapter: CodeRunning`; `final class MockCodeRunner: CodeRunning`.

- [ ] **Step 1: Port both files**

```bash
git show feat/chat-redesign:codepet/Services/CodeRunning.swift > codepet/Services/CodeRunning.swift
git show feat/chat-redesign:codepet/Services/MockCodeRunner.swift > codepet/Services/MockCodeRunner.swift
```

- [ ] **Step 2: Write the failing test**

```swift
// codepetTests/MockCodeRunnerTests.swift
import XCTest
@testable import codepet

final class MockCodeRunnerTests: XCTestCase {
    func test_run_makesRealEditAndReportsDiff() async throws {
        // Arrange a temp working dir with one editable file.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mockrun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("main.swift")
        try "let x = 1\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Act
        var steps: [ExecStep] = []
        let outcome = await MockCodeRunner().run(
            prompt: "tweak the file", workingDir: dir.path, onStep: { steps.append($0) })

        // Assert: no failure, a real diff, and the file actually changed on disk.
        XCTAssertNil(outcome.failure)
        XCTAssertFalse(outcome.diffs.isEmpty, "mock should produce at least one file diff")
        let after = try String(contentsOf: file, encoding: .utf8)
        XCTAssertNotEqual(after, "let x = 1\n", "mock must make a real on-disk edit")
    }
}
```

- [ ] **Step 3: Run — verify pass**

Run: `xcodebuild test … -only-testing:codepetTests/MockCodeRunnerTests …` (signing flags).
Expected: PASS. If `MockCodeRunner.run`'s parameter labels differ, read `codepet/Services/MockCodeRunner.swift` and match them (it conforms to `CodeRunning`, so the labels are `prompt:workingDir:onStep:`).

- [ ] **Step 4: Commit**

```bash
git add codepet/Services/CodeRunning.swift codepet/Services/MockCodeRunner.swift codepetTests/MockCodeRunnerTests.swift
git commit -m "feat(coding-agent): port CodeRunning seam + MockCodeRunner + test"
```

---

### Task 6: Port the coordinator — `CodingRunCoordinator` (+ phase tests)

The `@MainActor ObservableObject` state machine that every card phase reads from.

**Files:**
- Create: `codepet/Managers/CodingRunCoordinator.swift` (via `git show`)
- Test: `codepetTests/CodingRunCoordinatorTests.swift`

**Interfaces:**
- Produces: `@MainActor final class CodingRunCoordinator: ObservableObject` with `@Published private(set) var run: EditCodeRun?`, `@Published private(set) var steps: [ExecStep]`, `init(runner: CodeRunning)`, `func propose(ask:plannedFiles:needsBash:link:)`, `func execute() async`, `func approve(acceptedPaths:) async`, `func reject() async`, `func cancel()`.

- [ ] **Step 1: Port the coordinator**

Run: `git show feat/chat-redesign:codepet/Managers/CodingRunCoordinator.swift > codepet/Managers/CodingRunCoordinator.swift`

- [ ] **Step 2: Write failing phase tests (driven by `MockCodeRunner` on a temp git repo)**

```swift
// codepetTests/CodingRunCoordinatorTests.swift
import XCTest
@testable import codepet

@MainActor
final class CodingRunCoordinatorTests: XCTestCase {
    /// A temp git repo with one committed file, so the git backend engages.
    private func makeRepo() throws -> ProjectLink {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "let x = 1\n".write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        _ = GitRunner.run(["init"], in: dir.path)
        _ = GitRunner.run(["add", "."], in: dir.path)
        _ = GitRunner.run(["-c", "user.email=t@t.co", "-c", "user.name=t", "commit", "-m", "init"], in: dir.path)
        return ProjectProbe.probe(path: dir.path)
    }

    func test_propose_multiFile_entersPreviewing() throws {
        let c = CodingRunCoordinator(runner: MockCodeRunner())
        c.propose(ask: "do a thing", plannedFiles: 2, needsBash: false, link: try makeRepo())
        XCTAssertEqual(c.run?.phase, .previewing)
    }

    func test_propose_noLink_entersNoProject() {
        let c = CodingRunCoordinator(runner: MockCodeRunner())
        c.propose(ask: "do a thing", plannedFiles: 2, needsBash: false, link: nil)
        XCTAssertEqual(c.run?.phase, .noProject)
    }

    func test_execute_thenApprove_reachesCommitted() async throws {
        let c = CodingRunCoordinator(runner: MockCodeRunner())
        c.propose(ask: "tweak main", plannedFiles: 1, needsBash: false, link: try makeRepo())
        await c.execute()
        XCTAssertEqual(c.run?.phase, .reviewing)
        await c.approve(acceptedPaths: c.run?.acceptedPaths ?? [])
        XCTAssertEqual(c.run?.phase, .committed)
    }
}
```

- [ ] **Step 3: Run — verify pass**

Run: `xcodebuild test … -only-testing:codepetTests/CodingRunCoordinatorTests …` (signing flags).
Expected: PASS. If `.readyToRun` is reached instead of `.previewing` for a single-file ask, that matches `EditCodePlanner` — align the test to the source's rule. Read the coordinator if a transition differs.

- [ ] **Step 4: Commit**

```bash
git add codepet/Managers/CodingRunCoordinator.swift codepetTests/CodingRunCoordinatorTests.swift
git commit -m "feat(coding-agent): port CodingRunCoordinator + phase tests"
```

---

### Task 7: Wire the coordinator + project link into `main`'s `CompanyStore`

Add the coordinator, the linked-project state, `linkProject`, and a `startCodeRun(ask:)` trigger. `main`'s `CompanyStore` already `import Combine` and is `final class CompanyStore: ObservableObject` (line 9).

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreCodeRunTests.swift`

**Interfaces:**
- Produces: `@Published private(set) var activeProjectLink: ProjectLink?`; `lazy var codingRun: CodingRunCoordinator`; `@Published var codingRunAnchorId: String?`; `@discardableResult func linkProject(path:bootstrapClaudeMd:) -> ProjectLink`; `func startCodeRun(ask: String)`.

- [ ] **Step 1: Add the state + lazy coordinator**

Add these members to `CompanyStore` (place near the other `@Published` chat state, e.g. just after `@Published var chatMessages`):

```swift
    // MARK: - Coding agent (local edit_code)

    /// The project folder linked for the coding agent. Client-only; reset on account switch.
    @Published private(set) var activeProjectLink: ProjectLink?
    private static let activeProjectBookmarkKey = "cp_active_project_bookmark"

    /// The chat message a chat-triggered coding run anchors to, so its card renders
    /// inline right after that ask. `nil` for runs triggered outside chat (tasks/roadmap):
    /// those fall back to the transcript bottom.
    @Published var codingRunAnchorId: String?

    /// Drives local coding-agent runs. Lazy so the runner is built only on first use.
    /// The `-CODEPET_MOCK_CHAT` launch arg swaps in `MockCodeRunner` (no `claude`, no cost)
    /// while keeping the real diff-review + git-commit engine, so the flow is free to test.
    private var codingRunBag: AnyCancellable?
    lazy var codingRun: CodingRunCoordinator = {
        let mock = ProcessInfo.processInfo.arguments.contains("-CODEPET_MOCK_CHAT")
        let runner: CodeRunning = mock ? MockCodeRunner() : ClaudeCodeRunAdapter()
        let c = CodingRunCoordinator(runner: runner)
        // Re-publish the nested coordinator's changes so views observing only
        // CompanyStore re-render as the run progresses (otherwise the card "sticks").
        self.codingRunBag = c.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        return c
    }()
```

- [ ] **Step 2: Add `linkProject` and `startCodeRun`**

Add these methods to `CompanyStore` (near `sendChat`, line ~293):

```swift
    /// Link a local project folder for the coding agent. Optionally seeds CLAUDE.md
    /// from the brief/decisions (never clobbers an existing one), then probes.
    @discardableResult
    func linkProject(path: String, bootstrapClaudeMd: Bool) -> ProjectLink {
        var link = ProjectProbe.probe(path: path)
        if bootstrapClaudeMd && !link.hasClaudeMd {
            let seed = ClaudeMdBootstrap.compose(brief: company.brief, decisions: company.decisions)
            try? seed.write(to: ProjectProbe.claudeMdURL(forProjectAt: path), atomically: true, encoding: .utf8)
            link = ProjectProbe.probe(path: path)
        }
        if let data = try? URL(fileURLWithPath: path)
            .bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Self.activeProjectBookmarkKey)
        }
        activeProjectLink = link
        return link
    }

    /// Chat-triggered code run: show the founder's ask as a normal message, anchor the
    /// run card to it, and stage the run. With no linked project the coordinator lands
    /// in `.noProject` and the card offers "Link a project".
    func startCodeRun(ask: String) {
        let trimmed = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let msg = CopilotMessage(role: .me, text: trimmed)
        chatMessages.append(msg)
        codingRunAnchorId = msg.id
        codingRun.propose(ask: trimmed, plannedFiles: 2, needsBash: false, link: activeProjectLink)
    }
```

- [ ] **Step 3: Reset link on account switch**

Find where per-account `@Published` state resets (grep `CompanyStore.swift` for an existing reset, e.g. `chatMessages = []` in a sign-out/account-switch path) and add on the same line group:

```swift
        activeProjectLink = nil
        codingRunAnchorId = nil
```

- [ ] **Step 4: Write the failing test**

```swift
// codepetTests/CompanyStoreCodeRunTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreCodeRunTests: XCTestCase {
    func test_linkProject_setsActiveLink() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CompanyStore()
        store.linkProject(path: dir.path, bootstrapClaudeMd: false)
        XCTAssertNotNil(store.activeProjectLink)
    }

    func test_startCodeRun_appendsAskAndProposes() {
        let store = CompanyStore()
        let before = store.chatMessages.count
        store.startCodeRun(ask: "add a health check endpoint")
        XCTAssertEqual(store.chatMessages.count, before + 1)
        XCTAssertEqual(store.chatMessages.last?.role, .me)
        XCTAssertNotNil(store.codingRun.run)                 // a run was staged
        XCTAssertEqual(store.codingRunAnchorId, store.chatMessages.last?.id)
    }
}
```

- [ ] **Step 5: Run — verify pass**

Run: `xcodebuild test … -only-testing:codepetTests/CompanyStoreCodeRunTests …` (signing flags). Close any running app first.
Expected: PASS. (`CompanyStore()` must construct without Firebase — `main` skips Firebase under tests via `AppEnvironment.isRunningTests`.) If `CompanyStore`'s init requires args, mirror how existing `CompanyStore` tests build it.

- [ ] **Step 6: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreCodeRunTests.swift
git commit -m "feat(coding-agent): wire coordinator + project link into CompanyStore"
```

---

### Task 8: Port `ProjectLinker`

The folder-picker + CLAUDE.md-consent flow the card and Environment surface call.

**Files:**
- Create: `codepet/Views/Environment/ProjectLinker.swift` (via `git show`)

**Interfaces:**
- Produces: `enum ProjectLinker { static func pickAndLink(into: CompanyStore, …) }` (confirm the exact signature after porting).

- [ ] **Step 1: Port**

Run: `git show feat/chat-redesign:codepet/Views/Environment/ProjectLinker.swift > codepet/Views/Environment/ProjectLinker.swift`

- [ ] **Step 2: Build**

Run the TEAM-signed build. Expected: `** BUILD SUCCEEDED **`. If it references a redesign-only symbol, resolve it (it should only need `CompanyStore.linkProject` + AppKit's `NSOpenPanel`).

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Environment/ProjectLinker.swift
git commit -m "feat(coding-agent): port ProjectLinker"
```

---

### Task 9: Port + adapt `CodeRunCardView` to `main`'s chrome

Port the redesign card, then swap its two redesign-only chrome symbols (`MessageCard`, `CompanionAvatar`) for `main`'s `CodepetCard` / no-avatar. Everything else it uses (`CodepetTheme`, `EditCodeRun`, `ExecStep`, `CodingRunCoordinator`, `ProjectLinker`) now exists.

**Files:**
- Create: `codepet/Views/Copilot/CodeRunCardView.swift` (via `git show`, then edit)

**Interfaces:**
- Consumes: `CodingRunCoordinator` (Task 6), `ProjectLinker` (Task 8), `CodepetCard` (existing on `main`).
- Produces: `struct CodeRunCardView: View { @ObservedObject var coordinator: CodingRunCoordinator }`.

- [ ] **Step 1: Port the card**

Run: `git show feat/chat-redesign:codepet/Views/Copilot/CodeRunCardView.swift > codepet/Views/Copilot/CodeRunCardView.swift`

- [ ] **Step 2: Swap the card container `MessageCard` → `CodepetCard`**

In `codepet/Views/Copilot/CodeRunCardView.swift`, the `body` wraps content in `MessageCard(hue: hue) { … }`. Replace only that wrapper call:

```swift
        HStack {
            CodepetCard {
                if let run = coordinator.run {
                    content(for: run)
                }
            }
            Spacer(minLength: 24)
        }
```

(`hue` stays as a property; it's still used by the header/pill colors.)

- [ ] **Step 3: Remove the redesign avatar from the header**

In `header(_:)`, delete the line:

```swift
            CompanionAvatar(size: 22, isWorking: run.phase == .running)
```

`main`'s copilot cards have no per-bubble avatar; the `ENGINEERING` label + phase pill remain. (Leave the surrounding `HStack`/`VStack` intact.)

- [ ] **Step 4: Build — verify the card compiles on `main`'s chrome**

Run the TEAM-signed build. Expected: `** BUILD SUCCEEDED **`. Any remaining error names a symbol that didn't port — resolve against the earlier tasks. Grep to confirm no stragglers: `grep -nE "MessageCard|CompanionAvatar|CompanionOrb" codepet/Views/Copilot/CodeRunCardView.swift` should return nothing.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Copilot/CodeRunCardView.swift
git commit -m "feat(coding-agent): CodeRunCardView on main's CodepetCard chrome"
```

---

### Task 10: Render the card in the copilot column + live-update bridges

Show the coordinator-driven card in `main`'s `messageList`, anchored inline after its ask (or at the bottom for task/roadmap runs), and port the two `onReceive` bridges that keep it live.

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`

**Interfaces:**
- Consumes: `companyStore.codingRun` / `.codingRunAnchorId` (Task 7), `CodeRunCardView` (Task 9).

- [ ] **Step 1: Add the live-tick state**

In `struct CopilotChatView`, add near the other `@State`:

```swift
    /// Bumped from the coordinator's publishers so a nested-object change reliably
    /// re-renders the run card live (see the onReceive bridges below).
    @State private var codingRunTick = 0
```

- [ ] **Step 2: Render the card inline after its anchor, and as a bottom fallback**

In `messageList`, change the `ForEach` block and the area after it:

```swift
                    ForEach(companyStore.chatMessages) { m in
                        CopilotBubble(message: m).id(m.id)
                        if companyStore.codingRun.run != nil,
                           companyStore.codingRunAnchorId == m.id {
                            CodeRunCardView(coordinator: companyStore.codingRun).id("coding-run")
                        }
                    }
                    // A run with no chat anchor (triggered from tasks/roadmap) falls to the bottom.
                    if companyStore.codingRun.run != nil,
                       !companyStore.chatMessages.contains(where: { $0.id == companyStore.codingRunAnchorId }) {
                        CodeRunCardView(coordinator: companyStore.codingRun).id("coding-run")
                    }
                    if companyStore.isCompanionTyping { typingRow.id("typing") }
```

- [ ] **Step 3: Port the two live-update bridges**

On the `ScrollView` inside `messageList`'s `ScrollViewReader` (where the existing `.onChange` handlers are), append:

```swift
            // Nested-ObservableObject publishers emit in willSet (before the new value
            // is assigned), so defer one runloop turn to re-render on the committed value —
            // otherwise the card sticks on "running" until a tab switch.
            .onReceive(companyStore.codingRun.$run) { _ in
                DispatchQueue.main.async {
                    codingRunTick &+= 1
                    if companyStore.codingRun.run != nil {
                        withAnimation { proxy.scrollTo("coding-run", anchor: .bottom) }
                    }
                }
            }
            .onReceive(companyStore.codingRun.$steps) { _ in
                DispatchQueue.main.async {
                    codingRunTick &+= 1
                    if companyStore.codingRun.run != nil {
                        withAnimation { proxy.scrollTo("coding-run", anchor: .bottom) }
                    }
                }
            }
```

- [ ] **Step 4: Build**

Run the TEAM-signed build. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(coding-agent): render run card in copilot column + live bridges"
```

---

### Task 11: Trigger — the "Let's build" button

Wire the existing stub so it runs the composer text as an engineering ask.

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`

- [ ] **Step 1: Wire `letsBuild`**

Replace the empty-action `letsBuild` button with one that starts a run from the draft and gates on non-empty text:

```swift
    // "Let's build" — runs the composer text as a local engineering ask.
    private var canBuild: Bool {
        !companyStore.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !companyStore.isCompanionTyping && !companyStore.isStreaming
    }
    private var letsBuild: some View {
        Button {
            let ask = companyStore.chatDraft
            companyStore.chatDraft = ""
            showHistory = false
            companyStore.startCodeRun(ask: ask)
        } label: {
            Text("🔨 " + (lang == .vi ? "Cùng xây" : "Let's build"))
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(canBuild ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(CodepetTheme.accentPurple.opacity(0.08))
        }
        .buttonStyle(.plain)
        .disabled(!canBuild)
    }
```

- [ ] **Step 2: Build + manual smoke (mock)**

Build TEAM-signed, then launch offline and drive it:
`open <DerivedData>/…/codepet.app --args -CODEPET_MOCK_CHAT YES` — type an ask, click **Let's build**, confirm the ask appears and a run card streams (mock makes a real edit; Approve reaches "Committed"). Close the app before any later `xcodebuild test`.

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(coding-agent): wire the Let's build trigger"
```

---

### Task 12: Trigger — Engineering toggle in the composer

A slim Chat/Engineering control; in Engineering mode `send()` routes to a code run.

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`

- [ ] **Step 1: Add the mode state + toggle UI**

Add state to `CopilotChatView`:

```swift
    /// Composer mode: normal chat vs. an engineering code-edit ask.
    @State private var engineeringMode = false
```

Add this control at the top of `inputBar`'s `HStack` (before the `TextField`):

```swift
            Button { engineeringMode.toggle() } label: {
                Text(engineeringMode ? (lang == .vi ? "Kỹ thuật" : "Engineering")
                                     : (lang == .vi ? "Trò chuyện" : "Chat"))
                    .font(CodepetTheme.inter(10, weight: .semibold))
                    .foregroundColor(engineeringMode ? .white : CodepetTheme.mutedText)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(engineeringMode ? CodepetTheme.accentBlue
                                                               : CodepetTheme.accentBlue.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Bật để yêu cầu sửa code trên dự án đã liên kết"
                              : "On to ask for a code edit on the linked project")
```

- [ ] **Step 2: Route `send()` on the mode**

Change `send()` to branch:

```swift
    private func send() {
        guard canSend else { return }
        let text = companyStore.chatDraft
        companyStore.chatDraft = ""
        showHistory = false
        if engineeringMode {
            companyStore.startCodeRun(ask: text)   // shows .noProject card if nothing linked
        } else {
            Task { await companyStore.sendChat(text, language: lang) }
        }
    }
```

- [ ] **Step 3: Build + manual smoke (mock)**

Build; launch with `-CODEPET_MOCK_CHAT YES`; toggle **Engineering**, send an ask, confirm it routes to a run card (not a chat reply). Close the app afterward.

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(coding-agent): Engineering composer toggle routes to a code run"
```

---

### Task 13: Trigger — Engineering task Start (Tasks/Roadmap)

Port `RoadmapDispatch` and dispatch a code run when an **Engineering** task is started and a project is linked; its card streams into the copilot column (unanchored → bottom).

**Files:**
- Create: `codepet/Models/RoadmapDispatch.swift` (via `git show`)
- Modify: `codepet/Views/Tasks/TasksView.swift`, `codepet/Views/Roadmap/RoadmapView.swift`

**Interfaces:**
- Consumes: `companyStore.codingRun`, `companyStore.activeProjectLink`, `companyStore.select(_:)` (navigate to chat).
- Produces: `enum RoadmapDispatch { static func editCodeAsk(for: <Task>) -> String }` and `RoadmapAction.editCode` (confirm the `<Task>` type matches `main`'s after porting).

- [ ] **Step 1: Port `RoadmapDispatch` and verify its task type matches `main`**

Run: `git show feat/chat-redesign:codepet/Models/RoadmapDispatch.swift > codepet/Models/RoadmapDispatch.swift`
Then build. If it references a task/department shape that differs on `main`, adjust the signatures to `main`'s task model (grep `codepet/Models` for the roadmap task type used by `TasksView`). It must compile against `main`'s types before proceeding.

- [ ] **Step 2: Add the dispatch at the Tasks action site**

`main`'s task action is a `Button` at `codepet/Views/Tasks/TasksView.swift:90`. Read its surrounding context to see the task in scope, then wrap its action so an Engineering task with a linked project dispatches a code run instead of the normal action:

```swift
        // Inside the task-row Button action, with `task` (the row's task) in scope:
        if task.department?.key == "eng", companyStore.activeProjectLink != nil {
            companyStore.codingRunAnchorId = nil                 // no ask message → card falls to bottom
            companyStore.select(.chat)                           // show the copilot column
            companyStore.codingRun.propose(
                ask: RoadmapDispatch.editCodeAsk(for: task),
                plannedFiles: 2, needsBash: false, link: companyStore.activeProjectLink)
        } else {
            // …existing task action…
        }
```

Match the exact property names to `main`'s task model (`task.department?.key` vs `task.dept`, etc.) after reading the file. Use `companyStore`'s real navigation call for "show chat" (grep for how other views navigate to `.chat`).

- [ ] **Step 3: Mirror the dispatch in `RoadmapView`**

Apply the same eng-and-linked branch at `RoadmapView`'s task-start/tap site (grep `codepet/Views/Roadmap/RoadmapView.swift` for its task action). Keep the code identical to Step 2.

- [ ] **Step 4: Build + manual smoke (mock)**

Build; launch with `-CODEPET_MOCK_CHAT YES`; link a project (Task 14 provides the UI, or link via the in-card `.noProject` offer first); start an Engineering task; confirm it navigates to the copilot and streams a run card at the bottom. Close the app afterward.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/RoadmapDispatch.swift codepet/Views/Tasks/TasksView.swift codepet/Views/Roadmap/RoadmapView.swift
git commit -m "feat(coding-agent): Engineering-task Start dispatches a copilot run"
```

---

### Task 14: Environment — "Linked project" surface

Add a section to `main`'s `EnvironmentView` to link / change / unlink the project the agent edits.

**Files:**
- Modify: `codepet/Views/Environment/EnvironmentView.swift`

**Interfaces:**
- Consumes: `companyStore.activeProjectLink`, `companyStore.linkProject`, `ProjectLinker.pickAndLink` (Task 8).

- [ ] **Step 1: Add the section view**

Add to `EnvironmentView` (it already has `@EnvironmentObject var companyStore` — if not, add it) and render it in `body` after `companionLine` (the body composes `header`, `companionLine`, `recommendations`, `categorySection(...)`; insert `linkedProjectSection` after `companionLine`):

```swift
    private var linkedProjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((lang == .vi ? "Dự án đã liên kết" : "Linked project").uppercased())
                .font(CodepetTheme.inter(11, weight: .semibold))
                .foregroundColor(CodepetTheme.mutedText)
            if let link = companyStore.activeProjectLink {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.displayName)
                            .font(CodepetTheme.inter(13, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Text(link.path)
                            .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button(lang == .vi ? "Đổi" : "Change") {
                        ProjectLinker.pickAndLink(into: companyStore)
                    }.buttonStyle(.plain).foregroundColor(CodepetTheme.accentPurple)
                }
            } else {
                Button {
                    ProjectLinker.pickAndLink(into: companyStore)
                } label: {
                    Text(lang == .vi ? "Liên kết một dự án…" : "Link a project…")
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(CodepetTheme.accentPurple))
                }.buttonStyle(.plain)
            }
        }
    }
```

Confirm `ProjectLinker.pickAndLink`'s real signature (Task 8) and `ProjectLink`'s `displayName`/`path` property names after porting; adjust if they differ.

- [ ] **Step 2: Build**

Run the TEAM-signed build. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Environment/EnvironmentView.swift
git commit -m "feat(coding-agent): Linked-project surface in Environment"
```

---

### Task 15: Full-suite verification + offline end-to-end

**Files:** none (verification only).

- [ ] **Step 1: Close any running app, run the whole test suite**

`pkill -x codepet 2>/dev/null; ` then `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS'` + signing flags.
Expected: all tests pass. If you see `** TEST FAILED **` with 0 executed and no `Failing tests:` list, that's the Firestore-lock flake — ensure no `codepet.app` is running and re-run; confirm the executed-test count is non-zero.

- [ ] **Step 2: Offline end-to-end via mock**

Build TEAM-signed; `open <DerivedData>/…/codepet.app --args -CODEPET_MOCK_CHAT YES`. Verify all three triggers reach a committed run: (a) type + **Let's build**; (b) **Engineering** toggle + send; (c) start an Engineering task. For each, confirm the card streams steps, shows per-file diffs, and **Approve** reaches "Committed"; **Reject** discards. Confirm nothing was pushed (`git -C <linked repo> branch` shows a local `codepet/<slug>` only). Close the app.

- [ ] **Step 3: Final commit (if any verification tweaks)**

```bash
git add -A && git commit -m "test(coding-agent): full-suite + offline end-to-end verification" || echo "nothing to commit"
```

---

## Deferred (not in this plan)

- `byte` (cloud) auto-initiating `edit_code`: needs `companyChat` Cloud Function support + `CompanyChatClient` decoding an `EditCodeAction` + a `handleDoneAction` arm. Out of scope, as agreed.
