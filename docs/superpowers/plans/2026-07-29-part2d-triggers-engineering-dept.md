# Part 2D — Engineering-Task Trigger + Department Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route Engineering work to the local coding agent (`edit_code`) instead of the cloud (`run_task`) — **only when a project is linked** (else unchanged) — from both a roadmap Engineering task and the Engineering composer pill.

**Architecture:** A pure, additive extension of `RoadmapDispatch`: a new `.editCode` action, and `action(for:isEngineering:projectLinked:)` returns it for a `.codepetCanDo` Engineering task when a project is linked. A pure `EditCodeRouting.shouldRoute(department:projectLinked:)` covers the composer pill. The view/store dispatch then calls `CodingRunCoordinator.propose(...)` (2C-1) + navigates to chat. The two already-shipped triggers (user-asks-in-chat, companion-proposes) flow through the `edit_code` verb (2C-1 / 2C-server) and are unchanged.

**Tech Stack:** Swift, SwiftUI (`codepet`), XCTest, xcodebuild. Reuses `RoadmapDispatch`, `CodingRunCoordinator`, `DepartmentCatalog` (`eng`), `CompanyStore.activeProjectLink`. No new dependencies.

## Scope

**Part 2D.** In: the `.editCode` routing rules (testable) + the roadmap/tasks + composer dispatch wiring (build-verified). The overnight/autonomous trigger stays **foundation-only** (out of scope, per spec §3).

**Adaptive rule (from the 2D decision):** Engineering routes to `edit_code` **iff a project is linked**; with no link it keeps today's cloud `run_task` behavior exactly (zero disruption).

## Global Constraints

- Native macOS SwiftUI; scheme `codepet`; `@testable import codepet`; XCTest.
- **Additive / no regression:** `RoadmapDispatch.action(for:)`'s existing behavior is preserved via defaulted new params (`isEngineering: false, projectLinked: false`) — existing callers/tests unchanged. `.editCode` only ever arises when both flags are true for a `.codepetCanDo` task.
- Engineering = `DepartmentCatalog` key `"eng"`. "Project linked" = `companyStore.activeProjectLink != nil`.
- Work-lands-in-chat (Layer 4): `.editCode` navigates to chat (like `.run`/`.walkThrough`).
- `.editCode` dispatch calls `companyStore.codingRun.propose(...)`; since a roadmap/pill trigger carries no CF scope estimate, propose with conservative estimates so the plan-preview shows (`plannedFiles: 2`), letting the founder confirm before a substantial change.
- The run **card** that renders the staged run is 2C-2 (founder's); 2D correctly stages the run regardless — build-verified.
- Build/test signing + close-app-before-test as before.
- Branch `feat/chat-redesign` (PR #39, held); do not push.

## File Structure

- **Modify** `codepet/Models/RoadmapDispatch.swift` — add `.editCode`; extend `action(...)`; `navigatesToChat(.editCode)`.
- **Create** `codepet/Models/EditCodeRouting.swift` — pure composer-pill routing rule.
- **Modify** `codepetTests/RoadmapDispatchTests.swift` + **create** `codepetTests/EditCodeRoutingTests.swift`.
- **Modify** `codepet/Views/Roadmap/RoadmapView.swift`, `codepet/Views/Roadmap/RoadmapMapView.swift`, `codepet/Views/Tasks/TasksView.swift` — dispatch `.editCode` (build-verified).
- **Modify** `codepet/Managers/CompanyStore.swift` — the composer send routes an Engineering+linked ask to `codingRun.propose` (build-verified).

---

## Task 1: `.editCode` routing rules (testable)

**Files:**
- Modify: `codepet/Models/RoadmapDispatch.swift`
- Create: `codepet/Models/EditCodeRouting.swift`
- Test: `codepetTests/RoadmapDispatchTests.swift`, `codepetTests/EditCodeRoutingTests.swift`

**Interfaces:**
- `RoadmapAction` gains `case editCode`.
- `RoadmapDispatch.action(for status: TaskStatus, isEngineering: Bool = false, projectLinked: Bool = false) -> RoadmapAction` — returns `.editCode` when `status == .codepetCanDo && isEngineering && projectLinked`; otherwise the existing mapping. `navigatesToChat(.editCode) == true`.
- `EditCodeRouting.shouldRoute(department: Department?, projectLinked: Bool) -> Bool` — true when `department?.key == "eng" && projectLinked`.

- [ ] **Step 1: Write the failing tests**

Add to `codepetTests/RoadmapDispatchTests.swift`:

```swift
    func test_engineeringCanDo_withLinkedProject_routesToEditCode() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo, isEngineering: true, projectLinked: true), .editCode)
    }
    func test_engineeringCanDo_noLink_staysCloudRun() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo, isEngineering: true, projectLinked: false), .run)
    }
    func test_nonEngineeringCanDo_staysRun_evenWhenLinked() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo, isEngineering: false, projectLinked: true), .run)
    }
    func test_engineeringNonCanDo_unaffected() {
        XCTAssertEqual(RoadmapDispatch.action(for: .needsYou, isEngineering: true, projectLinked: true), .walkThrough)
        XCTAssertEqual(RoadmapDispatch.action(for: .done, isEngineering: true, projectLinked: true), .openDeliverable)
    }
    func test_editCode_navigatesToChat() {
        XCTAssertTrue(RoadmapDispatch.navigatesToChat(.editCode))
    }
    func test_defaultParams_preserveLegacyMapping() {
        XCTAssertEqual(RoadmapDispatch.action(for: .codepetCanDo), .run)  // no flags → unchanged
    }
```

Create `codepetTests/EditCodeRoutingTests.swift`:

```swift
import XCTest
@testable import codepet

final class EditCodeRoutingTests: XCTestCase {
    private var eng: Department? { DepartmentCatalog.find("eng") }
    private var mkt: Department? { DepartmentCatalog.find("mkt") }

    func test_engineeringPill_withLink_routes() {
        XCTAssertTrue(EditCodeRouting.shouldRoute(department: eng, projectLinked: true))
    }
    func test_engineeringPill_noLink_doesNotRoute() {
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: eng, projectLinked: false))
    }
    func test_otherDept_orNil_doesNotRoute() {
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: mkt, projectLinked: true))
        XCTAssertFalse(EditCodeRouting.shouldRoute(department: nil, projectLinked: true))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapDispatchTests -only-testing:codepetTests/EditCodeRoutingTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `.editCode` / `EditCodeRouting` not found.

- [ ] **Step 3: Implement**

In `codepet/Models/RoadmapDispatch.swift`:

```swift
enum RoadmapAction: Equatable {
    case run
    case walkThrough
    case approve
    case openDeliverable
    case editCode          // Engineering + a linked project → the local coding agent
    case none
}

enum RoadmapDispatch {
    static func action(for status: TaskStatus,
                       isEngineering: Bool = false,
                       projectLinked: Bool = false) -> RoadmapAction {
        switch status {
        case .codepetCanDo:
            // Engineering work runs LOCALLY when a project is linked; otherwise it
            // stays on the cloud run path (unchanged).
            return (isEngineering && projectLinked) ? .editCode : .run
        case .needsYou:      return .walkThrough
        case .needsApproval: return .approve
        case .done:          return .openDeliverable
        case .blocked:       return .none
        }
    }

    static func navigatesToChat(_ action: RoadmapAction) -> Bool {
        action == .run || action == .walkThrough || action == .editCode
    }
}
```

Create `codepet/Models/EditCodeRouting.swift`:

```swift
import Foundation

/// Whether a chat ask should route to the LOCAL coding agent (`edit_code`) rather
/// than a normal cloud turn: true only when the founder picked the Engineering
/// department AND a project is linked. Pure.
enum EditCodeRouting {
    static func shouldRoute(department: Department?, projectLinked: Bool) -> Bool {
        department?.key == "eng" && projectLinked
    }
}
```

- [ ] **Step 4: Run to verify green** (both suites, incl. the pre-existing RoadmapDispatch tests — the defaulted params keep them passing).

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/RoadmapDispatchTests -only-testing:codepetTests/EditCodeRoutingTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 5: Commit** (`feat(coding-agent): Engineering→edit_code routing rules (Part 2D Task 1)`).

---

## Task 2: Wire the dispatch (roadmap + tasks + composer) — build-verified

**Files:** `RoadmapView.swift`, `RoadmapMapView.swift`, `TasksView.swift`, `CompanyStore.swift`.

**Interfaces:** consumes `RoadmapDispatch.action(for:isEngineering:projectLinked:)`, `EditCodeRouting.shouldRoute(...)`, `CodingRunCoordinator.propose(...)`, `companyStore.activeProjectLink`.

- [ ] **Step 1: Roadmap + Tasks dispatch.** Where each computes `RoadmapDispatch.action(for: status)`, pass the flags: `isEngineering: task.dept == "eng"`, `projectLinked: companyStore.activeProjectLink != nil`. Add an `.editCode` branch to the dispatch switch:
```swift
case .editCode:
    let ask = task.detail.isEmpty ? task.title : "\(task.title): \(task.detail)"
    companyStore.codingRun.propose(ask: ask, plannedFiles: 2, needsBash: false,
                                   link: companyStore.activeProjectLink)
```
`navigatesToChat(.editCode)` is already true, so the existing `if navigatesToChat(action) { select(.chat) }` sends the founder to chat where the run card (2C-2) shows it. (TasksView uses the same shared rule — update its `RoadmapDispatch.action(for: st)` call the same way and add the `.editCode` handling to its tap.)

- [ ] **Step 2: Composer pill routing.** In `CompanyStore.sendChat(_:language:department:)` (or the send core), before the normal chat turn: if `EditCodeRouting.shouldRoute(department: department, projectLinked: activeProjectLink != nil)`, route to the coding agent instead — `codingRun.propose(ask: text, plannedFiles: 2, needsBash: false, link: activeProjectLink)` + `select(.chat)` — and return (don't also send a cloud chat turn). Otherwise, unchanged. Keep it a small, clearly-guarded branch at the top of the send.

- [ ] **Step 3: Build**
```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: (optional) A store test** for the composer routing if the send path is reachable with injected fakes: Engineering pill + a linked project → `codingRun.run != nil` (a run staged) and no cloud chat turn sent. If the send path is hard to isolate, rely on the pure `EditCodeRouting` test + build. Note which.

- [ ] **Step 5: Commit** (`feat(coding-agent): dispatch Engineering tasks + pill to edit_code (Part 2D Task 2)`).

---

## Self-Review

**1. Spec coverage (§3 triggers, §6 department):** Engineering roadmap task → `edit_code` (adaptive) + Engineering composer pill → `edit_code` (adaptive) — Tasks 1–2. User-asks / companion-proposes already ship via the verb (2C-1/2C-server). Overnight = foundation-only (out of scope). ✅
**2. Placeholder scan:** Task 1 complete code + tests. Task 2 is wiring (build-verified) with the routing decisions pushed into the pure, tested rules.
**3. Type consistency:** `RoadmapAction.editCode`, `RoadmapDispatch.action(for:isEngineering:projectLinked:)`, `EditCodeRouting.shouldRoute(department:projectLinked:)`, `CodingRunCoordinator.propose(ask:plannedFiles:needsBash:link:)`, `activeProjectLink`, dept key `"eng"` all match existing code.
**Confirm at implementation:** the exact `RoadmapDispatch.action(for:)` call sites (RoadmapView/RoadmapMapView/TasksView) to pass the two flags; the composer send entry (`sendChat`) for the pill branch. **Deferred:** overnight/autonomous trigger; the run card that visualizes the staged run (2C-2); the coordinated ship.
