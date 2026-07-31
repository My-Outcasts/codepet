# Part 2A — Project Linking Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a founder link a real project folder so Codepet recognizes it (git? CLAUDE.md?), bootstraps a CLAUDE.md from their brief + decisions when absent, and exposes it as the client-only `project` context slice the coding agent will use.

**Architecture:** A pure `ProjectLink` value type + a filesystem `ProjectProbe` (detects `.git` / `CLAUDE.md` at a path) + a pure `ClaudeMdBootstrap` composer (brief + decisions → seed markdown). `CompanyStore` gains an `activeProjectLink` and a `linkProject(path:)` method that probes, builds the link, persists a security-scoped bookmark, and feeds the link's `slice` into the (client-only) `CompanyContext.project` at the chat-send site. No subprocess and no code editing yet — that's 2B/2C.

**Tech Stack:** Swift, SwiftUI app (`codepet`), XCTest, xcodebuild. No new dependencies.

## Scope

This is **Part 2A** — the first of four Part-2 sub-plans (2A linking → 2B run+commit engine → 2C edit_code verb+chat UI → 2D triggers+Engineering dept). 2A is the foundation the others build on.

**In 2A:** `ProjectLink` model, `.git`/`CLAUDE.md` detection, CLAUDE.md bootstrap composition + write, the active-link store method + security-scoped bookmark persistence, and populating the client-only `project` slice.

**Explicitly deferred:**
- **The picker UI + auto-detect suggestion chips** — building a new UI surface needs a design discussion first (per project convention: propose UI before implementing). 2A ships the logic behind a `linkProject(path:)` call; the picker is thin later wiring. `linkProject` is fully testable with a path, no picker needed.
- Subprocess / editing / commit — 2B/2C.
- `recentChangeSummary` on the slice stays `nil` in 2A (filled once the runner lands in 2B).

## Global Constraints

- Native macOS SwiftUI; scheme `codepet` (lowercase); `@testable import codepet`; XCTest. App is NOT sandboxed (`CodePet.entitlements`: `app-sandbox = false`) — it can read/write real project dirs and create security-scoped bookmarks.
- **Client-only invariant (Part 1):** the `project` slice must never enter `groundingString`/`runTaskGroundingString` — only `projectSummary`. 1A's tests already lock this; 2A must not regress it (wiring the slice into the send-site `CompanyContext` must keep the cloud payload unchanged).
- Follow the existing pure-model pattern (`ChatContext`, `CompanyContext`, `RoadmapEngine`): SwiftUI-free, deterministic where possible; filesystem probes are deterministic against a temp fixture dir.
- Build/test signing: `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`.
- **Before `xcodebuild test`, close any running `codepet.app`** (Firestore lock). `ProjectLinkTests` and `CompanyContextTests` are pure/temp-dir and run cleanly; CompanyStore-based tests use the injected-fake pattern (`CompanyStoreFanOutTests` style) to avoid live Firestore.
- Branch `feat/chat-redesign` (PR #39, held); do not push.

## File Structure

- **Create** `codepet/Models/ProjectLink.swift` — `ProjectLink` value type + `ProjectProbe` (filesystem detection) + `var slice: CompanyContext.ProjectSlice`.
- **Create** `codepet/Models/ClaudeMdBootstrap.swift` — pure `compose(brief:decisions:) -> String` seed-markdown composer.
- **Create** `codepetTests/ProjectLinkTests.swift` — probe (temp dir), bootstrap composer, slice mapping.
- **Modify** `codepet/Managers/CompanyStore.swift` — `@Published activeProjectLink`, `linkProject(path:)`, bookmark persistence, and feed `activeProjectLink?.slice` into the chat-send `CompanyContext`.
- **Modify** `codepetTests/CompanyContextTests.swift` — confirm the client-only invariant still holds when a project slice is present at the send site (guard against regression).

Reference types (exist): `CompanyContext.ProjectSlice(path:isGitRepo:hasClaudeMd:recentChangeSummary:)`, `CompanyBrief` (`founderName`/`role`/`tech`/`stage`/`projectName`/`oneLiner`/`summary`), `DecisionEntry(topic:statement:source:updatedAt:)`, `Project` (from `ProjectStore`, for later suggestions).

---

## Task 1: `ProjectLink` model + filesystem detection

**Files:**
- Create: `codepet/Models/ProjectLink.swift`
- Test: `codepetTests/ProjectLinkTests.swift`

**Interfaces:**
- Produces:
  - `struct ProjectLink: Equatable { let path: String; let isGitRepo: Bool; let hasClaudeMd: Bool; var slice: CompanyContext.ProjectSlice }`
  - `enum ProjectProbe { static func probe(path: String) -> ProjectLink }` — reads the filesystem at `path` (`.git` dir → `isGitRepo`; `CLAUDE.md` file → `hasClaudeMd`) and returns a populated `ProjectLink`. Also `static func claudeMdURL(forProjectAt path: String) -> URL`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ProjectLinkTests.swift`:

```swift
import XCTest
@testable import codepet

final class ProjectLinkTests: XCTestCase {

    /// Make a throwaway project dir; optionally seed a .git dir and/or CLAUDE.md.
    private func tempProject(git: Bool, claudeMd: Bool) -> String {
        let base = NSTemporaryDirectory() + "codepet-2a-" + UUID().uuidString
        let fm = FileManager.default
        try? fm.createDirectory(atPath: base, withIntermediateDirectories: true)
        if git { try? fm.createDirectory(atPath: base + "/.git", withIntermediateDirectories: true) }
        if claudeMd { try? "# hi".write(toFile: base + "/CLAUDE.md", atomically: true, encoding: .utf8) }
        return base
    }

    func test_probe_detectsGitAndClaudeMd() {
        let p = tempProject(git: true, claudeMd: true)
        let link = ProjectProbe.probe(path: p)
        XCTAssertEqual(link.path, p)
        XCTAssertTrue(link.isGitRepo)
        XCTAssertTrue(link.hasClaudeMd)
    }

    func test_probe_detectsNeither() {
        let p = tempProject(git: false, claudeMd: false)
        let link = ProjectProbe.probe(path: p)
        XCTAssertFalse(link.isGitRepo)
        XCTAssertFalse(link.hasClaudeMd)
    }

    func test_slice_mapsFieldsAndHasNilRecentChange() {
        let p = tempProject(git: true, claudeMd: false)
        let slice = ProjectProbe.probe(path: p).slice
        XCTAssertEqual(slice.path, p)
        XCTAssertTrue(slice.isGitRepo)
        XCTAssertFalse(slice.hasClaudeMd)
        XCTAssertNil(slice.recentChangeSummary)   // filled in 2B, nil here
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ProjectLinkTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `ProjectLink` / `ProjectProbe` not found.

- [ ] **Step 3: Implement**

Create `codepet/Models/ProjectLink.swift`:

```swift
import Foundation

/// A project folder the founder deliberately linked for the coding agent. Pure
/// value type — the filesystem probe that builds it is `ProjectProbe`. Its
/// `slice` is the client-only `CompanyContext.project` view (never sent to the
/// cloud; see Part 1's client-only invariant).
struct ProjectLink: Equatable {
    let path: String
    let isGitRepo: Bool
    let hasClaudeMd: Bool

    /// The client-only context slice for this link. `recentChangeSummary` is nil
    /// until the runner (2B) can summarize local changes.
    var slice: CompanyContext.ProjectSlice {
        CompanyContext.ProjectSlice(
            path: path, isGitRepo: isGitRepo, hasClaudeMd: hasClaudeMd, recentChangeSummary: nil)
    }
}

/// Filesystem detection for a linked project. Deterministic given the directory's
/// contents (`.git` dir → git repo; `CLAUDE.md` file → has CLAUDE.md).
enum ProjectProbe {
    static func claudeMdURL(forProjectAt path: String) -> URL {
        URL(fileURLWithPath: path).appendingPathComponent("CLAUDE.md")
    }

    static func probe(path: String) -> ProjectLink {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let gitPath = (path as NSString).appendingPathComponent(".git")
        let isGit = fm.fileExists(atPath: gitPath, isDirectory: &isDir) && isDir.boolValue
        let hasClaude = fm.fileExists(atPath: claudeMdURL(forProjectAt: path).path)
        return ProjectLink(path: path, isGitRepo: isGit, hasClaudeMd: hasClaude)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ProjectLinkTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ProjectLink.swift codepetTests/ProjectLinkTests.swift
git commit -F - <<'EOF'
feat(coding-agent): ProjectLink model + filesystem probe (Part 2A)

Pure ProjectLink value type + ProjectProbe (.git / CLAUDE.md detection) +
its client-only CompanyContext.ProjectSlice mapping. No subprocess yet.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 2: CLAUDE.md bootstrap composer

**Files:**
- Create: `codepet/Models/ClaudeMdBootstrap.swift`
- Test: `codepetTests/ProjectLinkTests.swift` (add cases)

**Interfaces:**
- Produces: `enum ClaudeMdBootstrap { static func compose(brief: CompanyBrief, decisions: [DecisionEntry]) -> String }` — a seed CLAUDE.md the app offers to write when a linked project has none. Pure and deterministic.

- [ ] **Step 1: Write the failing test**

Add to `codepetTests/ProjectLinkTests.swift`:

```swift
    func test_bootstrap_includesProjectFounderAndDecisions() {
        var b = CompanyBrief()
        b.projectName = "Acme"; b.founderName = "Mona"; b.role = "Solo founder"
        b.tech = "Next.js"; b.stage = "building"; b.oneLiner = "AI coding companion"
        let decisions = [
            DecisionEntry(topic: "pricing", statement: "Charge $20/mo", source: "founder", updatedAt: 1),
        ]
        let md = ClaudeMdBootstrap.compose(brief: b, decisions: decisions)

        XCTAssertTrue(md.contains("Acme"))
        XCTAssertTrue(md.contains("Mona"))
        XCTAssertTrue(md.contains("Next.js"))
        XCTAssertTrue(md.contains("AI coding companion"))
        XCTAssertTrue(md.contains("Charge $20/mo"))
        XCTAssertTrue(md.contains("Codepet"))   // the managed-block marker
    }

    func test_bootstrap_handlesEmptyBriefAndDecisions() {
        let md = ClaudeMdBootstrap.compose(brief: CompanyBrief(), decisions: [])
        XCTAssertFalse(md.isEmpty)               // still a usable seed
        XCTAssertTrue(md.contains("Codepet"))
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ProjectLinkTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `ClaudeMdBootstrap` not found.

- [ ] **Step 3: Implement**

Create `codepet/Models/ClaudeMdBootstrap.swift`:

```swift
import Foundation

/// Composes a seed CLAUDE.md for a freshly-linked project that has none — the
/// coding agent's standing context, drawn from the founder's brief + decisions.
/// Pure and deterministic. The app writes this only with the founder's consent
/// and only when no CLAUDE.md already exists (never clobbers an existing one).
enum ClaudeMdBootstrap {
    static func compose(brief: CompanyBrief, decisions: [DecisionEntry]) -> String {
        let clip = { (s: String?) -> String? in
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let project = clip(brief.projectName) ?? "This project"
        var out = ["# \(project) — project context"]

        if let one = clip(brief.oneLiner) ?? clip(brief.summary) { out.append("\n\(one)") }

        var about: [String] = []
        if let f = clip(brief.founderName) {
            about.append("- Founder: \(f)" + (clip(brief.role).map { " (\($0))" } ?? ""))
        }
        if let s = clip(brief.stage) { about.append("- Stage: \(s)") }
        if let t = clip(brief.tech) { about.append("- Tech: \(t)") }
        if !about.isEmpty { out.append("\n## About\n" + about.joined(separator: "\n")) }

        let facts = decisions
            .map { ($0.topic.trimmingCharacters(in: .whitespacesAndNewlines),
                    $0.statement.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.0.isEmpty && !$0.1.isEmpty }
        if !facts.isEmpty {
            out.append("\n## Decisions\n" + facts.map { "- \($0.0): \($0.1)" }.joined(separator: "\n"))
        }

        out.append("\n<!-- Seeded by Codepet from your brief + decisions. Edit freely. -->")
        return out.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ProjectLinkTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: PASS — 5 tests total.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ClaudeMdBootstrap.swift codepetTests/ProjectLinkTests.swift
git commit -F - <<'EOF'
feat(coding-agent): CLAUDE.md bootstrap composer (Part 2A)

Pure seed-markdown from brief + decisions for a linked project that has no
CLAUDE.md — the coding agent's standing context. App writes it only on
consent and never clobbers an existing file.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Task 3: `CompanyStore.linkProject(path:)` + active link + slice wiring

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/ProjectLinkTests.swift` (add a store test) + `codepetTests/CompanyContextTests.swift` (regression: client-only invariant with a slice present)

**Interfaces:**
- Consumes: `ProjectProbe.probe(path:)`, `ClaudeMdBootstrap.compose(...)`, `ProjectProbe.claudeMdURL(...)`, `CompanyContext(company:query:focusDepartment:project:)`.
- Produces on `CompanyStore`:
  - `@Published private(set) var activeProjectLink: ProjectLink?`
  - `func linkProject(path: String, bootstrapClaudeMd: Bool) -> ProjectLink` — probes, sets `activeProjectLink`, persists a security-scoped bookmark, and (if `bootstrapClaudeMd` and no CLAUDE.md) writes the composed seed then re-probes so `hasClaudeMd` reflects the write. Returns the resulting link.

- [ ] **Step 1: Write the failing store test**

Add to `codepetTests/ProjectLinkTests.swift`:

```swift
    @MainActor
    func test_linkProject_setsActiveLinkAndBootstrapsClaudeMd() async {
        // Injected-fake store (no live Firestore), mirroring CompanyStoreFanOutTests.
        var brief = CompanyBrief(); brief.projectName = "Acme"; brief.founderName = "Mona"
        let seed = CompanyState(brief: brief, departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [])
        let store = CompanyStore(loader: { _ in seed },
                                 tasksSaver: { _, _ in true },
                                 librarySaver: { _, _ in true },
                                 threadSaver: { _, _ in true },
                                 threadsLoader: { _ in [] })
        await store.hydrate(companyId: "u")

        // A git project with NO CLAUDE.md → bootstrap should create one.
        let base = NSTemporaryDirectory() + "codepet-2a-store-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base + "/.git", withIntermediateDirectories: true)

        let link = store.linkProject(path: base, bootstrapClaudeMd: true)
        XCTAssertEqual(store.activeProjectLink, link)
        XCTAssertEqual(link.path, base)
        XCTAssertTrue(link.isGitRepo)
        XCTAssertTrue(link.hasClaudeMd, "bootstrap should have written CLAUDE.md and re-probed")
        let written = try? String(contentsOfFile: base + "/CLAUDE.md", encoding: .utf8)
        XCTAssertEqual(written?.contains("Acme"), true)
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ProjectLinkTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `activeProjectLink` / `linkProject` not members of `CompanyStore`.

- [ ] **Step 3: Implement on `CompanyStore`**

Add the published property near the other `@Published` state (e.g. beside `runningTaskIds`):

```swift
    /// The project folder the founder linked for the coding agent (Part 2). One
    /// active at a time; client-only (its `slice` never enters the cloud grounding).
    @Published private(set) var activeProjectLink: ProjectLink?
```

Add the method (place it near the other project/company helpers):

```swift
    /// Link a project folder for the coding agent: probe it, set it active, persist
    /// a security-scoped bookmark (survives relaunch; app is non-sandboxed), and —
    /// when `bootstrapClaudeMd` and the folder has no CLAUDE.md — write a seed from
    /// the brief + decisions (never clobbers an existing CLAUDE.md), then re-probe.
    @discardableResult
    func linkProject(path: String, bootstrapClaudeMd: Bool) -> ProjectLink {
        var link = ProjectProbe.probe(path: path)
        if bootstrapClaudeMd && !link.hasClaudeMd {
            let seed = ClaudeMdBootstrap.compose(brief: company.brief, decisions: company.decisions)
            try? seed.write(to: ProjectProbe.claudeMdURL(forProjectAt: path), atomically: true, encoding: .utf8)
            link = ProjectProbe.probe(path: path)   // re-probe so hasClaudeMd reflects the write
        }
        // Persist a security-scoped bookmark so access survives relaunch (best-effort).
        if let data = try? URL(fileURLWithPath: path)
            .bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: "cp_active_project_bookmark")
        }
        activeProjectLink = link
        return link
    }
```

- [ ] **Step 4: Wire the slice into the chat-send `CompanyContext` (client-only)**

Find the chat-send `CompanyContext` construction (added in 1A, ~line 595) and pass the active link's slice:

```swift
        let companyContext = CompanyContext(company: company, query: text, focusDepartment: department,
                                            project: activeProjectLink?.slice)
```

(The `project` slice is client-only — `groundingString` never references it — so the cloud payload is unchanged. Step 5's regression test proves this.)

- [ ] **Step 5: Add the client-only regression test**

Add to `codepetTests/CompanyContextTests.swift`:

```swift
    func test_projectSlice_fromLink_stillNeverLeaksIntoGroundingString() {
        let company = fixtureCompany()
        let slice = CompanyContext.ProjectSlice(
            path: "/Users/mona/secret", isGitRepo: true, hasClaudeMd: true, recentChangeSummary: nil)
        let ctx = CompanyContext(company: company, query: "x", project: slice)
        XCTAssertFalse(ctx.groundingString.contains("/Users/mona/secret"))
        XCTAssertEqual(ctx.projectSummary?.contains("/Users/mona/secret"), true)
    }
```

- [ ] **Step 6: Run tests + build**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ProjectLinkTests \
  -only-testing:codepetTests/CompanyContextTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -25
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
```
Expected: PASS (ProjectLinkTests incl. the store test; CompanyContextTests incl. the new regression) and `** BUILD SUCCEEDED **`. (If a CompanyStore-based test shows 0 executed + `** TEST FAILED **`, that's the Firestore host flake — close the app and re-run; the store test uses injected fakes so it should execute.)

- [ ] **Step 7: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepetTests/ProjectLinkTests.swift codepetTests/CompanyContextTests.swift
git commit -F - <<'EOF'
feat(coding-agent): CompanyStore.linkProject + active link + slice wiring (Part 2A)

Probes a linked folder, sets activeProjectLink, persists a security-scoped
bookmark, bootstraps CLAUDE.md when absent (never clobbers), and feeds the
client-only project slice into the chat-send CompanyContext (cloud payload
unchanged — regression test added). Picker UI deferred pending UI design.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**1. Spec coverage (Part 2 §1 Project linking):**
- `ProjectLink` model + `.git`/`CLAUDE.md` detection → Tasks 1. ✅
- CLAUDE.md bootstrap seeded from brief + decisions, never clobbering → Task 2 + Task 3 (`!link.hasClaudeMd` guard). ✅
- Active link + security-scoped bookmark persistence → Task 3. ✅
- `project` slice populated + wired (client-only) → Task 3, with a regression test that it never leaks to the cloud. ✅
- Auto-detect suggestions + picker UI → **deferred** (needs UI design discussion); `linkProject(path:)` is the seam the picker will call. Not a gap — a scoped deferral.

**2. Placeholder scan:** No TBD/TODO; every code step is complete; every command has expected output.

**3. Type consistency:** `ProjectLink`, `ProjectProbe.probe(path:)`/`claudeMdURL(forProjectAt:)`, `ClaudeMdBootstrap.compose(brief:decisions:)`, `activeProjectLink`, `linkProject(path:bootstrapClaudeMd:)`, and `.slice` are named identically across tasks. `CompanyContext.ProjectSlice(path:isGitRepo:hasClaudeMd:recentChangeSummary:)` and `CompanyContext(company:query:focusDepartment:project:)` match the 1A definitions. `DecisionEntry(topic:statement:source:updatedAt:)` and `CompanyBrief` fields match the real models. The injected-store initializer mirrors `CompanyStoreFanOutTests`.

**Deferred (later 2A follow-up / 2B+):** the picker UI + auto-detect suggestion chips (post UI-design discussion); resolving/using the security-scoped bookmark on relaunch; `recentChangeSummary` (2B); everything subprocess/edit/commit (2B/2C).
