# Roadmap (core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the native app's Project Health (departments × stage) with an AI-generated, stage-appropriate build roadmap — bespoke tasks per department plus a pure next-step — surfaced in the project folder view.

**Architecture:** New Swift `RoadmapTask`/`RoadmapNextStep` models ride on `Project` (persisted like `companyBrief`). A new `scaffoldRoadmap` Cloud Function generates tasks per department from the brief + stage; a `ReflectionAPIClient.scaffoldRoadmap` client fetches them; a pure `RoadmapEngine.nextStep` picks the one task to do next (no LLM). A `RoadmapSectionView` renders a next-step beacon + per-department "To build" list + a Generate/Re-plan action inside `ProjectFolderView`, alongside the existing health checks.

**Tech Stack:** Swift/SwiftUI (macOS 13+), Firebase Auth/Firestore, Firebase Functions v2 (TypeScript, Anthropic SDK, Jest). Reuses `HealthPillar` (engineering/business/marketing/growth) + `ProjectStage` (idea/building/launch/growth). Spec: `docs/superpowers/specs/2026-07-20-roadmap-core-design.md`.

## Global Constraints

- **Two repos.** Swift app: worktree `~/Documents/codepet-roadmap-wt` (`My-Outcasts/codepet`), branch `feat/roadmap` off `origin/main`. Function: `Murror/CodePet-Clean` functions on branch `feat/project-health-reflection-sync` (the authoritative functions source, 9 `onRequest`, deploys to `devpet-8f4b1`) — same home as `enrichBrief`. Work the function in a worktree off that branch; **never blanket-deploy**.
- **Reuse native enums as the backbone:** `HealthPillar` (engineering/business/marketing/growth, has `.order` + `.label: L10n`) is the department key; `ProjectStage` (idea/building/launch/growth, has `.order` + `.label`). Do NOT invent new department/stage types.
- **Extend, don't replace:** do not modify the existing health rubric (`ProjectHealthEngine.allRules`) or `generatePlan`. Health checks and roadmap tasks coexist as two labeled groups. Do not merge failing checks into tasks.
- **Next-step is pure** (no network/LLM): `RoadmapEngine.nextStep` picks by `HealthPillar.order` then task order.
- **Fail-open generation:** `scaffoldRoadmap` returns HTTP 200 with empty departments on model error; the client maps that to "no tasks added," leaving prior tasks + the health rubric intact.
- **Swift conventions:** `Codable` models; UserDefaults key prefix `cp_`; new `ReflectionAPIClientProtocol` methods get a default-throw extension; `Logger(subsystem: "app.murror.codepet", ...)`.
- **Out of scope (later):** deliverable-per-task (run-task, SP5), chat reading next-step (SP4), map/breadcrumb/overview visualizations, task pending/run states, paywall. Do NOT edit `CLAUDE.md`.
- **Swift test command:** `cd ~/Documents/codepet-roadmap-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -25`. Scheme `codepet` (lowercase); NO `xcodegen` (`.xcodeproj` auto-syncs new files); test module `@testable import codepet`. SourceKit cross-file "cannot find type" diagnostics are false positives — the `xcodebuild` result is authoritative.
- **Functions test command:** `cd <fn-worktree>/functions && npm test -- scaffoldRoadmap` and `npx tsc --noEmit`. Deploy is `firebase deploy --only functions:scaffoldRoadmap` and is **human-gated** (do NOT deploy in-task).

---

## File Structure

**Swift app (worktree `~/Documents/codepet-roadmap-wt`):**
- Create `codepet/Models/RoadmapTask.swift` — `TaskWho`, `RoadmapTask`, `RoadmapNextStep` (Task 1); make `HealthPillar` Codable (Task 1).
- Create `codepet/Models/RoadmapEngine.swift` — pure next-step picker (Task 2).
- Modify `codepet/Services/ReflectionAPIClient.swift` — DTOs, endpoint, method, protocol (Task 4).
- Modify `codepet/Models/Project.swift` + `codepet/Managers/ProjectStore.swift` — persist tasks (Task 5).
- Create `codepet/Views/Tips/RoadmapSectionView.swift`; modify `codepet/Views/Tips/ProjectFolderView.swift` — surfacing (Task 6).
- Tests under `codepetTests/`.

**Functions (`Murror/CodePet-Clean` @ `feat/project-health-reflection-sync`):**
- Create `functions/src/scaffoldRoadmap.ts` + test; modify `functions/src/index.ts` (Task 3).

---

### Task 1: Roadmap models

**Files:**
- Create: `codepet/Models/RoadmapTask.swift`
- Modify: `codepet/Models/ProjectHealthCheck.swift` (make `HealthPillar` Codable)
- Test: `codepetTests/RoadmapTaskTests.swift`

**Interfaces:**
- Produces: `enum TaskWho: String, Codable`; `struct RoadmapTask: Codable, Hashable, Identifiable`; `struct RoadmapNextStep: Hashable`; `HealthPillar: Codable`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/RoadmapTaskTests.swift
import XCTest
@testable import codepet

final class RoadmapTaskTests: XCTestCase {
    func testRoadmapTaskRoundTripsCodable() throws {
        let t = RoadmapTask(id: "eng-0", deptKey: .engineering, title: "Ship auth",
                            detail: "Wire Firebase email sign-in", who: .draft, kind: "build", done: false)
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(RoadmapTask.self, from: data)
        XCTAssertEqual(back, t)
    }

    func testTaskWhoDefaultsAndDoneToggleField() {
        let t = RoadmapTask(id: "x", deptKey: .marketing, title: "T", detail: "D")
        XCTAssertEqual(t.who, .draft)
        XCTAssertEqual(t.kind, "build")
        XCTAssertFalse(t.done)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-roadmap-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapTaskTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'RoadmapTask' in scope`.

- [ ] **Step 3: Make `HealthPillar` Codable**

In `codepet/Models/ProjectHealthCheck.swift`, change the enum declaration:

```swift
enum HealthPillar: String, Codable, CaseIterable {
```
(add `Codable` — it is `String`-backed so no custom coding is needed; `.order`/`.label` are unchanged.)

- [ ] **Step 4: Write the models**

```swift
// codepet/Models/RoadmapTask.swift
import Foundation

/// Who acts on a roadmap task — mirrors the web `Who`: the companion drafts it,
/// the companion does it, or the founder must.
enum TaskWho: String, Codable, Hashable {
    case draft    // companion drafts a deliverable for the founder to review
    case does     // companion can do it outright
    case needsYou // only the founder can do it
}

/// One AI-generated, stage-appropriate build task under a department. Rides on
/// `Project` (persisted with the projects dict), alongside the fixed health rubric.
struct RoadmapTask: Codable, Hashable, Identifiable {
    let id: String            // stable, e.g. "engineering-0"
    let deptKey: HealthPillar
    var title: String
    var detail: String
    var who: TaskWho
    var kind: String
    var done: Bool

    init(id: String, deptKey: HealthPillar, title: String, detail: String,
         who: TaskWho = .draft, kind: String = "build", done: Bool = false) {
        self.id = id; self.deptKey = deptKey; self.title = title; self.detail = detail
        self.who = who; self.kind = kind; self.done = done
    }
}

/// The single "do this next" pick across a project's open roadmap tasks.
/// Mirrors the web `NextStep { deptK, taskTitle, why }`.
struct RoadmapNextStep: Hashable {
    let deptKey: HealthPillar
    let taskTitle: String
    let why: String
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-roadmap-wt
git add codepet/Models/RoadmapTask.swift codepet/Models/ProjectHealthCheck.swift codepetTests/RoadmapTaskTests.swift
git commit -m "feat(roadmap): RoadmapTask/RoadmapNextStep models + HealthPillar Codable"
```

---

### Task 2: `RoadmapEngine.nextStep` (pure)

**Files:**
- Create: `codepet/Models/RoadmapEngine.swift`
- Test: `codepetTests/RoadmapEngineTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask`, `RoadmapNextStep`, `HealthPillar`, `ProjectStage` (Task 1).
- Produces: `enum RoadmapEngine { static func nextStep(_ tasks: [RoadmapTask], stage: ProjectStage) -> RoadmapNextStep? }`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/RoadmapEngineTests.swift
import XCTest
@testable import codepet

final class RoadmapEngineTests: XCTestCase {
    private func task(_ id: String, _ dept: HealthPillar, done: Bool = false) -> RoadmapTask {
        RoadmapTask(id: id, deptKey: dept, title: "T-\(id)", detail: "d", done: done)
    }

    func testPicksFirstOpenTaskByPillarOrderThenPosition() {
        // marketing(order 2) task appears first in the array, but engineering(order 0) wins.
        let tasks = [task("m0", .marketing), task("e0", .engineering), task("e1", .engineering)]
        let next = RoadmapEngine.nextStep(tasks, stage: .building)
        XCTAssertEqual(next?.taskTitle, "T-e0")
        XCTAssertEqual(next?.deptKey, .engineering)
        XCTAssertFalse(next?.why.isEmpty ?? true)
    }

    func testSkipsDoneTasks() {
        let tasks = [task("e0", .engineering, done: true), task("e1", .engineering)]
        XCTAssertEqual(RoadmapEngine.nextStep(tasks, stage: .idea)?.taskTitle, "T-e1")
    }

    func testNilWhenNothingOpen() {
        XCTAssertNil(RoadmapEngine.nextStep([], stage: .idea))
        XCTAssertNil(RoadmapEngine.nextStep([task("e0", .engineering, done: true)], stage: .idea))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-roadmap-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapEngineTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'RoadmapEngine' in scope`.

- [ ] **Step 3: Write the engine**

```swift
// codepet/Models/RoadmapEngine.swift
import Foundation

/// Pure "what to do next" picker over a project's roadmap tasks. No network, no
/// LLM — mirrors the web's pure next-step engine. The single pick is the first
/// not-done task ordered by department (`HealthPillar.order`) then array position.
enum RoadmapEngine {
    static func nextStep(_ tasks: [RoadmapTask], stage: ProjectStage) -> RoadmapNextStep? {
        let indexed = tasks.enumerated().filter { !$0.element.done }
        guard let pick = indexed.min(by: { a, b in
            if a.element.deptKey.order != b.element.deptKey.order {
                return a.element.deptKey.order < b.element.deptKey.order
            }
            return a.offset < b.offset
        })?.element else { return nil }
        let why = "Next up in \(pick.deptKey.label.en) for the \(stage.label.en.lowercased()) stage."
        return RoadmapNextStep(deptKey: pick.deptKey, taskTitle: pick.title, why: why)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-roadmap-wt
git add codepet/Models/RoadmapEngine.swift codepetTests/RoadmapEngineTests.swift
git commit -m "feat(roadmap): pure RoadmapEngine.nextStep picker"
```

---

### Task 3: `scaffoldRoadmap` Cloud Function

**Files (functions repo):**
- Create: `functions/src/scaffoldRoadmap.ts`
- Modify: `functions/src/index.ts` (add export)
- Test: `functions/src/__tests__/scaffoldRoadmap.test.ts`

**Interfaces:**
- Produces (HTTP): `POST /scaffoldRoadmap`, Bearer auth, body `{ brief, stage, departments: [{key,name,expertise}] }` → `200 { departments: [{ key, tasks: [{title,detail,who,kind}] }] }` (empty on fail-open).
- Produces (pure, exported for tests): `buildScaffoldPrompt(brief, stage, departments)`, `coerceScaffold(raw, departments)`.

- [ ] **Step 1: Pre-flight — work off the authoritative functions branch (no deploy)**

```bash
cd ~/Documents/Claude/CodePet-Clean
git fetch origin
git worktree add -b feat/scaffold-roadmap-fn ~/Documents/codepet-scaffoldfn-wt origin/feat/project-health-reflection-sync
cd ~/Documents/codepet-scaffoldfn-wt/functions
[ -d node_modules ] || npm install
grep -c "onRequest" src/index.ts   # expect 9 (authoritative source)
```
If `functions/` is absent or the count is far from 9, STOP and report — you may be on the wrong branch. **Do NOT run `firebase deploy` in this task** (human-gated).

- [ ] **Step 2: Write the failing test** (pure helpers)

```ts
// functions/src/__tests__/scaffoldRoadmap.test.ts
import { buildScaffoldPrompt, coerceScaffold } from "../scaffoldRoadmap";

const DEPTS = [
  { key: "engineering", name: "Engineering", expertise: "ship the product" },
  { key: "marketing", name: "Marketing", expertise: "reach users" },
];

describe("buildScaffoldPrompt", () => {
  it("includes the founder product, stage, and each department", () => {
    const p = buildScaffoldPrompt({ projectName: "Codepet", oneLiner: "a recap tool" }, "building", DEPTS);
    expect(p).toContain("Codepet");
    expect(p).toContain("building");
    expect(p).toContain("Engineering");
    expect(p).toContain("Marketing");
    expect(p).toContain("do not invent");
  });
});

describe("coerceScaffold", () => {
  it("keeps only known departments and clamps task fields", () => {
    const out = coerceScaffold(
      { departments: [
        { key: "engineering", tasks: [{ title: "  Ship auth ", detail: "d", who: "draft", kind: "build" }] },
        { key: "unknown", tasks: [{ title: "x", detail: "y", who: "does", kind: "build" }] },
      ] },
      DEPTS,
    );
    expect(out.departments.map((d) => d.key)).toEqual(["engineering"]);
    expect(out.departments[0].tasks[0].title).toBe("Ship auth");
  });

  it("returns empty departments for malformed input (fail-open shape)", () => {
    expect(coerceScaffold(null, DEPTS).departments).toEqual([]);
    expect(coerceScaffold({ departments: "nope" }, DEPTS).departments).toEqual([]);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/Documents/codepet-scaffoldfn-wt/functions && npm test -- scaffoldRoadmap 2>&1 | tail -20`
Expected: FAIL — cannot find module `../scaffoldRoadmap`.

- [ ] **Step 4: Write the function** (mirrors `enrichBrief.ts`: tool-based structured output, auth, rate limit, fail-open)

```ts
// functions/src/scaffoldRoadmap.ts
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL } from "./anthropic";

export interface DeptInput { key: string; name: string; expertise: string; }
export interface ScaffoldTask { title: string; detail: string; who: string; kind: string; }
export interface ScaffoldDept { key: string; tasks: ScaffoldTask[]; }
export interface ScaffoldResult { departments: ScaffoldDept[]; }

const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");
const WHO = new Set(["draft", "does", "needsYou"]);

export function buildScaffoldPrompt(brief: any, stage: string, depts: DeptInput[]): string {
  const lines = [
    `Product: ${clip(brief?.projectName, 120) || "(unnamed)"}${brief?.oneLiner ? " — " + clip(brief.oneLiner, 300) : ""}`,
    brief?.summary ? `Summary: ${clip(brief.summary, 400)}` : null,
    brief?.audience ? `Audience: ${clip(brief.audience, 200)}` : null,
    `Stage: ${clip(stage, 40) || "building"}`,
    "",
    "Departments (generate 2-4 concrete, stage-appropriate build tasks for EACH):",
    ...depts.map((d) => `- ${d.name} (${d.key}): ${clip(d.expertise, 300)}`),
  ].filter(Boolean);
  return (
    "You are planning a founder's next concrete build tasks, department by department, grounded ONLY in what the founder told you.\n\n" +
    lines.join("\n") +
    "\n\nFor each department produce 2-4 tasks: a short imperative title, a 1-2 sentence detail, a `who` of exactly 'draft' | 'does' | 'needsYou', and kind 'build'. Ground everything in this product and stage — do not invent a different product, and do not invent facts the founder did not give you."
  );
}

/** Keep only known departments; trim/validate task fields. Never throws — returns empty on junk. */
export function coerceScaffold(raw: any, depts: DeptInput[]): ScaffoldResult {
  const known = new Set(depts.map((d) => d.key));
  const inDepts = raw && Array.isArray(raw.departments) ? raw.departments : [];
  const departments: ScaffoldDept[] = [];
  for (const d of inDepts) {
    if (!d || !known.has(d.key) || !Array.isArray(d.tasks)) continue;
    const tasks: ScaffoldTask[] = [];
    for (const t of d.tasks.slice(0, 4)) {
      const title = clip(t?.title, 120);
      if (!title) continue;
      tasks.push({
        title,
        detail: clip(t?.detail, 400),
        who: WHO.has(t?.who) ? t.who : "draft",
        kind: clip(t?.kind, 40) || "build",
      });
    }
    if (tasks.length) departments.push({ key: d.key, tasks });
  }
  return { departments };
}

const SCAFFOLD_TOOL = {
  name: "record_roadmap",
  description: "Record the generated build tasks per department.",
  input_schema: {
    type: "object",
    properties: {
      departments: {
        type: "array",
        items: {
          type: "object",
          properties: {
            key: { type: "string", description: "The department key exactly as given." },
            tasks: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  title: { type: "string" }, detail: { type: "string" },
                  who: { type: "string", description: "'draft' | 'does' | 'needsYou'" },
                  kind: { type: "string" },
                },
                required: ["title", "detail", "who", "kind"],
              },
            },
          },
          required: ["key", "tasks"],
        },
      },
    },
    required: ["departments"],
  },
} as const;

const SYSTEM = "You plan a founder's concrete next build tasks per department. You never invent details the founder did not give you.";

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const k = process.env.ANTHROPIC_API_KEY;
    if (!k) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey: k });
  }
  return _client;
}

export async function handleScaffoldRoadmap(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) { res.status(401).json({ error: "invalid_token" }); return; }
  const body = req.body ?? {};
  const depts: DeptInput[] = Array.isArray(body.departments) ? body.departments : [];
  if (!depts.length) { res.status(400).json({ error: "invalid_payload", detail: "departments required" }); return; }
  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) { res.status(429).json({ error: "daily_limit_reached", reset_at: limit.resetAt.toISOString(), limit: limit.limit }); return; }
  try {
    const response = await client().messages.create({
      model: MODEL, max_tokens: 2048, system: SYSTEM,
      tools: [SCAFFOLD_TOOL as any], tool_choice: { type: "tool", name: "record_roadmap" },
      messages: [{ role: "user", content: buildScaffoldPrompt(body.brief, body.stage, depts) }],
    });
    const block = response.content.find((b) => b.type === "tool_use") as any;
    res.status(200).json(coerceScaffold(block?.input, depts));
  } catch (err) {
    logger.error("scaffoldRoadmap failed", { uid: auth.uid, err: String(err) });
    res.status(200).json({ departments: [] }); // fail-open
  }
}
```

- [ ] **Step 5: Export the function**

In `functions/src/index.ts` add the import with the others and the export after `chatSession`:

```ts
import { handleScaffoldRoadmap } from "./scaffoldRoadmap";
// ...
export const scaffoldRoadmap = onRequest(
  { cors: false, secrets: ["ANTHROPIC_API_KEY"] },
  handleScaffoldRoadmap
);
```

- [ ] **Step 6: Run tests + typecheck**

Run: `cd ~/Documents/codepet-scaffoldfn-wt/functions && npm test -- scaffoldRoadmap 2>&1 | tail -20 && npx tsc --noEmit 2>&1 | tail -20`
Expected: Jest PASS (both describe blocks), `tsc` clean.

- [ ] **Step 7: Commit (no deploy)**

```bash
cd ~/Documents/codepet-scaffoldfn-wt
git add functions/src/scaffoldRoadmap.ts functions/src/index.ts functions/src/__tests__/scaffoldRoadmap.test.ts
git commit -m "feat(functions): scaffoldRoadmap — generate bespoke build tasks per department"
```
Deployment (`firebase deploy --only functions:scaffoldRoadmap`) is **human-gated** — leave it for the controller/human.

---

### Task 4: `ReflectionAPIClient.scaffoldRoadmap` client method

**Files:**
- Modify: `codepet/Services/ReflectionAPIClient.swift`
- Test: `codepetTests/ReflectionAPIClientScaffoldTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief`, `RoadmapTask`, `TaskWho`, `HealthPillar`, `ProjectStage` (Tasks 1 + SP1).
- Produces: `func scaffoldRoadmap(brief:stage:departments:) async throws -> [RoadmapTask]` on the protocol (default-throw) + concrete client; `RoadmapDeptInput` DTO.

- [ ] **Step 1: Write the failing test** (reuses the `StubURLProtocol` added in SP1's `ReflectionAPIClientEnrichTests.swift`)

```swift
// codepetTests/ReflectionAPIClientScaffoldTests.swift
import XCTest
@testable import codepet

final class ReflectionAPIClientScaffoldTests: XCTestCase {
    private func client(_ status: Int, _ body: String) -> ReflectionAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
        return ReflectionAPIClient(session: URLSession(configuration: config)) { "t" }
    }

    func testMapsServerTasksToRoadmapTasks() async throws {
        let body = #"{"departments":[{"key":"engineering","tasks":[{"title":"Ship auth","detail":"Wire sign-in","who":"draft","kind":"build"}]}]}"#
        let tasks = try await client(200, body).scaffoldRoadmap(
            brief: CompanyBrief(projectName: "Codepet"), stage: .building,
            departments: [RoadmapDeptInput(key: "engineering", name: "Engineering", expertise: "ship")])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].deptKey, .engineering)
        XCTAssertEqual(tasks[0].title, "Ship auth")
        XCTAssertEqual(tasks[0].who, .draft)
        XCTAssertEqual(tasks[0].id, "engineering-0")
    }

    func testEmptyDepartmentsYieldsNoTasks() async throws {
        let tasks = try await client(200, #"{"departments":[]}"#).scaffoldRoadmap(
            brief: CompanyBrief(), stage: .idea, departments: [RoadmapDeptInput(key: "engineering", name: "E", expertise: "x")])
        XCTAssertTrue(tasks.isEmpty)
    }

    func testHTTPErrorThrows() async {
        do { _ = try await client(429, #"{"error":"daily_limit_reached"}"#).scaffoldRoadmap(
            brief: CompanyBrief(), stage: .idea, departments: [RoadmapDeptInput(key: "engineering", name: "E", expertise: "x")])
            XCTFail("expected throw") } catch { /* ok */ }
    }
}
```

> If `StubURLProtocol` is not visible to this test file (it was added in `ReflectionAPIClientEnrichTests.swift` in SP1), confirm it's accessible in the test target; if the two files can't share it, hoist `StubURLProtocol` into a small `codepetTests/StubURLProtocol.swift` helper and have both use it.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-roadmap-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ReflectionAPIClientScaffoldTests 2>&1 | tail -25`
Expected: FAIL — no member `scaffoldRoadmap` / no type `RoadmapDeptInput`.

- [ ] **Step 3: Add DTOs, endpoint, protocol entry (+ default-throw), and method**

Add DTOs near the other request/response structs:

```swift
struct RoadmapDeptInput: Codable { let key: String; let name: String; let expertise: String }

private struct ScaffoldRoadmapRequest: Codable { let brief: CompanyBrief; let stage: String; let departments: [RoadmapDeptInput] }
private struct ScaffoldRoadmapResponse: Codable {
    struct Dept: Codable { let key: String; let tasks: [Task] }
    struct Task: Codable { let title: String; let detail: String; let who: String; let kind: String }
    let departments: [Dept]
}
```

Add the endpoint constant next to `enrichBriefEndpoint`:

```swift
private static let scaffoldRoadmapEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/scaffoldRoadmap")!
```

Add to the protocol + default-throw extension (mirror `enrichBrief`):

```swift
// in protocol ReflectionAPIClientProtocol { ... }
func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask]

// in extension ReflectionAPIClientProtocol { ... }
func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask] {
    throw ReflectionAPIError.malformedResponse
}
```

Add the concrete method (mirror `enrichBrief`'s POST + Bearer shape), mapping the response to `[RoadmapTask]`:

```swift
func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask] {
    let token = try await authTokenProvider()
    var urlRequest = URLRequest(url: Self.scaffoldRoadmapEndpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    urlRequest.httpBody = try JSONEncoder().encode(
        ScaffoldRoadmapRequest(brief: brief, stage: stage.rawValue, departments: departments))

    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse else { throw ReflectionAPIError.malformedResponse }
    guard http.statusCode == 200 else { throw ReflectionAPIError.http(status: http.statusCode, body: nil) }
    let decoded: ScaffoldRoadmapResponse
    do { decoded = try JSONDecoder().decode(ScaffoldRoadmapResponse.self, from: data) }
    catch { throw ReflectionAPIError.malformedResponse }

    var out: [RoadmapTask] = []
    for dept in decoded.departments {
        guard let pillar = HealthPillar(rawValue: dept.key) else { continue }
        for (i, t) in dept.tasks.enumerated() {
            out.append(RoadmapTask(
                id: "\(dept.key)-\(i)", deptKey: pillar, title: t.title, detail: t.detail,
                who: TaskWho(rawValue: t.who) ?? .draft, kind: t.kind, done: false))
        }
    }
    return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-roadmap-wt
git add codepet/Services/ReflectionAPIClient.swift codepetTests/ReflectionAPIClientScaffoldTests.swift
git commit -m "feat(roadmap): ReflectionAPIClient.scaffoldRoadmap client method"
```

---

### Task 5: Persist roadmap tasks in `ProjectStore`

**Files:**
- Modify: `codepet/Models/Project.swift` (add field)
- Modify: `codepet/Managers/ProjectStore.swift` (set/get/toggle)
- Test: `codepetTests/ProjectStoreRoadmapTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask` (Task 1).
- Produces: `Project.roadmapTasks: [RoadmapTask]`; `ProjectStore.roadmapTasks(for:)`, `.setRoadmapTasks(projectId:tasks:)`, `.toggleRoadmapTask(projectId:taskId:)`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/ProjectStoreRoadmapTests.swift
import XCTest
@testable import codepet

@MainActor
final class ProjectStoreRoadmapTests: XCTestCase {
    func testSetReadToggleTasksPersistInMemory() {
        let store = ProjectStore()
        let id = store.detectProject(cwd: "/tmp/rm")!.id
        let tasks = [RoadmapTask(id: "engineering-0", deptKey: .engineering, title: "Ship auth", detail: "d")]
        store.setRoadmapTasks(projectId: id, tasks: tasks)
        XCTAssertEqual(store.roadmapTasks(for: id).count, 1)
        XCTAssertFalse(store.roadmapTasks(for: id)[0].done)
        store.toggleRoadmapTask(projectId: id, taskId: "engineering-0")
        XCTAssertTrue(store.roadmapTasks(for: id)[0].done)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-roadmap-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ProjectStoreRoadmapTests 2>&1 | tail -25`
Expected: FAIL — no member `setRoadmapTasks`.

- [ ] **Step 3: Add the field + store methods**

In `codepet/Models/Project.swift`, add after `var companyBrief: CompanyBrief? = nil`:

```swift
    /// AI-generated build tasks (the roadmap), per department. Defaulted empty so
    /// projects persisted before this field decode cleanly. Coexists with the
    /// fixed health rubric.
    var roadmapTasks: [RoadmapTask] = []
```

In `codepet/Managers/ProjectStore.swift`, add near the brief methods:

```swift
    func roadmapTasks(for projectPath: String?) -> [RoadmapTask] {
        guard let path = projectPath else { return [] }
        return projects[path]?.roadmapTasks ?? []
    }

    func setRoadmapTasks(projectId: String, tasks: [RoadmapTask]) {
        guard var project = projects[projectId] else { return }
        project.roadmapTasks = tasks
        projects[projectId] = project
        persist()
        logger.info("Set \(tasks.count) roadmap tasks for \(project.displayName)")
    }

    func toggleRoadmapTask(projectId: String, taskId: String) {
        guard var project = projects[projectId],
              let i = project.roadmapTasks.firstIndex(where: { $0.id == taskId }) else { return }
        project.roadmapTasks[i].done.toggle()
        projects[projectId] = project
        persist()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-roadmap-wt
git add codepet/Models/Project.swift codepet/Managers/ProjectStore.swift codepetTests/ProjectStoreRoadmapTests.swift
git commit -m "feat(roadmap): persist roadmap tasks per project"
```

---

### Task 6: Surface the roadmap in `ProjectFolderView`

**Files:**
- Create: `codepet/Views/Tips/RoadmapSectionView.swift`
- Modify: `codepet/Views/Tips/ProjectFolderView.swift`
- Test: `codepetTests/RoadmapSectionModelTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask`, `RoadmapNextStep`, `RoadmapEngine`, `HealthPillar`, `ProjectStage`, `ProjectStore.roadmapTasks/setRoadmapTasks/toggleRoadmapTask`, `ReflectionAPIClientProtocol.scaffoldRoadmap` (Tasks 1–5).
- Produces: `RoadmapSectionView` + a testable `@MainActor final class RoadmapSectionModel: ObservableObject` with `func generate(projectId:brief:stage:store:api:) async` and `static func departmentsInput() -> [RoadmapDeptInput]`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/RoadmapSectionModelTests.swift
import XCTest
@testable import codepet

@MainActor
final class RoadmapSectionModelTests: XCTestCase {
    func testDepartmentsInputCoversAllFourPillars() {
        let keys = RoadmapSectionModel.departmentsInput().map(\.key).sorted()
        XCTAssertEqual(keys, ["business", "engineering", "growth", "marketing"])
    }

    func testGeneratePersistsFetchedTasks() async {
        let store = ProjectStore()
        let id = store.detectProject(cwd: "/tmp/rmv")!.id
        let api = ScaffoldStub(returning: [RoadmapTask(id: "engineering-0", deptKey: .engineering, title: "Ship", detail: "d")])
        let model = RoadmapSectionModel()
        await model.generate(projectId: id, brief: CompanyBrief(projectName: "C"), stage: .building, store: store, api: api)
        XCTAssertEqual(store.roadmapTasks(for: id).map(\.title), ["Ship"])
    }
}

/// Stub returning fixed tasks; only scaffoldRoadmap implemented (others default-throw).
final class ScaffoldStub: ReflectionAPIClientProtocol {
    let out: [RoadmapTask]
    init(returning: [RoadmapTask]) { self.out = returning }
    func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask] { out }
    func summarizeTurn(_ r: SummarizeTurnRequest) async throws -> SummarizeTurnResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeTurnStream(_ r: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> { .init { $0.finish() } }
    func summarizeSession(_ r: SummarizeSessionRequest) async throws -> SummarizeSessionResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeSessionStream(_ r: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> { .init { $0.finish() } }
    func chatSessionStream(_ r: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> { .init { $0.finish() } }
    func fetchGuidance(_ r: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse { throw ReflectionAPIError.malformedResponse }
}
```

> Trim `ScaffoldStub`'s explicit methods to exactly the protocol's non-defaulted requirements (the compiler will tell you which). Methods with default-throw extensions (`enrichBrief`, `fetchPlan`, `fetchReferenceDistillation`, `scaffoldRoadmap`, `synthesizeBrief`) need not be repeated except the one under test.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-roadmap-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapSectionModelTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'RoadmapSectionModel' in scope`.

- [ ] **Step 3: Write the model + view**

```swift
// codepet/Views/Tips/RoadmapSectionView.swift
import SwiftUI

/// Drives the roadmap section: the department inputs, the generate call, and the
/// busy flag. Kept separate from the View so it is unit-testable.
@MainActor
final class RoadmapSectionModel: ObservableObject {
    @Published var isGenerating = false

    /// The 4 native departments as scaffold inputs (english names + short expertise).
    static func departmentsInput() -> [RoadmapDeptInput] {
        HealthPillar.allCases.map { p in
            RoadmapDeptInput(key: p.rawValue, name: p.label.en, expertise: Self.expertise(p))
        }
    }

    private static func expertise(_ p: HealthPillar) -> String {
        switch p {
        case .engineering: return "Shipping the product: architecture, tests, CI/CD, reliability."
        case .business:    return "Model, pricing, legal basics, and validating demand."
        case .marketing:   return "Positioning, launch, audience, and content."
        case .growth:      return "Retention, activation, analytics, and scaling users."
        }
    }

    /// Generate + persist the roadmap. Fail-open: on error, leaves existing tasks intact.
    func generate(projectId: String, brief: CompanyBrief, stage: ProjectStage,
                  store: ProjectStore, api: ReflectionAPIClientProtocol) async {
        isGenerating = true
        defer { isGenerating = false }
        guard let tasks = try? await api.scaffoldRoadmap(
            brief: brief, stage: stage, departments: Self.departmentsInput()), !tasks.isEmpty else { return }
        store.setRoadmapTasks(projectId: projectId, tasks: tasks)
    }
}

/// Roadmap section: a next-step beacon, a "To build" list per department, and a
/// Generate/Re-plan action. Rendered inside ProjectFolderView beside the checks.
struct RoadmapSectionView: View {
    let projectPath: String
    let stage: ProjectStage
    let brief: CompanyBrief
    @EnvironmentObject var projectStore: ProjectStore
    @StateObject private var model = RoadmapSectionModel()
    private let api: ReflectionAPIClientProtocol = ReflectionAPIClient()

    private var tasks: [RoadmapTask] { projectStore.roadmapTasks(for: projectPath) }
    private var next: RoadmapNextStep? { RoadmapEngine.nextStep(tasks, stage: stage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let next = next {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next step").font(.caption).foregroundColor(.secondary)
                    Text(next.taskTitle).font(.headline)
                    Text(next.why).font(.caption).foregroundColor(.secondary)
                }
            }
            ForEach(HealthPillar.allCases, id: \.self) { pillar in
                let group = tasks.filter { $0.deptKey == pillar }
                if !group.isEmpty {
                    Text("To build — \(pillar.label.en)").font(.subheadline.weight(.semibold))
                    ForEach(group) { task in
                        Button { projectStore.toggleRoadmapTask(projectId: projectPath, taskId: task.id) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text(task.title).strikethrough(task.done)
                                    Text(task.detail).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button {
                Task { await model.generate(projectId: projectPath, brief: brief, stage: stage, store: projectStore, api: api) }
            } label: {
                Text(model.isGenerating ? "Planning…" : (tasks.isEmpty ? "Generate roadmap" : "Re-plan for my stage"))
            }
            .buttonStyle(.plain)
            .disabled(model.isGenerating)
        }
    }
}
```

- [ ] **Step 4: Wire into `ProjectFolderView`**

Read `codepet/Views/Tips/ProjectFolderView.swift` and render `RoadmapSectionView` inside the per-project card, below the existing health checks. It needs the project's path, stage, and brief:

```swift
// inside ProjectFolderView's body, after the health-checks section:
RoadmapSectionView(
    projectPath: project.id,
    stage: project.stage ?? ProjectHealthEngine.inferStage(for: project, tags: []),
    brief: project.companyBrief ?? CompanyBrief(projectName: project.displayName)
)
.environmentObject(projectStore)
```

> Confirm `ProjectFolderView`'s available bindings for the project (`project`/`projectStore`) and where the checks render; place the section as a sibling below them. If `ProjectHealthEngine.inferStage`'s signature differs, use the folder's already-resolved stage value.

- [ ] **Step 5: Run tests + full build**

Run: `cd ~/Documents/codepet-roadmap-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapSectionModelTests 2>&1 | tail -25`
Then a full build (this touches a rendered view): `cd ~/Documents/codepet-roadmap-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: tests PASS; `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-roadmap-wt
git add codepet/Views/Tips/RoadmapSectionView.swift codepet/Views/Tips/ProjectFolderView.swift codepetTests/RoadmapSectionModelTests.swift
git commit -m "feat(roadmap): surface roadmap (next-step + To-build) in ProjectFolderView"
```

---

## Final verification

Run the full Swift suite: `cd ~/Documents/codepet-roadmap-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30` — all pass, app builds.
Functions: `cd ~/Documents/codepet-scaffoldfn-wt/functions && npm test 2>&1 | tail -20 && npx tsc --noEmit` — pass, clean. (Deploy `--only functions:scaffoldRoadmap` remains human-gated.)

---

## Self-Review

**Spec coverage:** models (Task 1), pure next-step (Task 2), scaffoldRoadmap function + fail-open (Task 3), client method (Task 4), persistence (Task 5), surfacing beacon + per-dept To-build + Generate/Re-plan (Task 6). Reuses `HealthPillar`/`ProjectStage` ✓; extends (doesn't replace) health ✓; deliverable-per-task/map/chat deferred ✓; CLAUDE.md untouched ✓.

**Type consistency:** `RoadmapTask`/`RoadmapNextStep`/`TaskWho`/`RoadmapDeptInput`/`HealthPillar` used identically across model, engine, client, store, view. `deptKey: HealthPillar` throughout; task `id` format `"<pillarRaw>-<index>"` produced in Task 4 and asserted in Tasks 4/5. `RoadmapEngine.nextStep(_:stage:)` defined Task 2, consumed Task 6. `scaffoldRoadmap(brief:stage:departments:)` signature identical in protocol/default/concrete/stub.

**Known verification gaps for the implementer (resolve inline, not blockers):** (a) confirm `StubURLProtocol` is shareable across test files (SP1 added it in `ReflectionAPIClientEnrichTests.swift`) — hoist to its own file if not; (b) confirm `ProjectFolderView`'s project/stage bindings + `ProjectHealthEngine.inferStage` signature for the Task 6 wiring; (c) trim `ScaffoldStub` to the compiler's exact non-defaulted protocol set; (d) the functions worktree (`~/Documents/codepet-scaffoldfn-wt`) is created in Task 3 Step 1.
