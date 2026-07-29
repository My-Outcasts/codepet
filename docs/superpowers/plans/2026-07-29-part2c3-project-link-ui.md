# Part 2C-3 — Project-Link UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the founder a way to link a project for the coding agent — a "Linked project" surface in Environment (link button + auto-detect suggestions + CLAUDE.md-bootstrap consent), an inline "link your project" offer when a code run has none, and an active-project chip in the composer.

**Architecture:** The link *logic* already exists (`CompanyStore.linkProject(path:bootstrapClaudeMd:)` + `activeProjectLink`, 2A). 2C-3 is almost entirely **SwiftUI views** wiring that logic to the agreed surfaces (from the 2C UI discussion: "Environment view + inline chat offer"). The one testable piece is a pure "which detected roots to suggest" helper over `ProjectStore.sortedProjects`. Views are build-verified + the founder's visual pass (no agent screenshots).

**Tech Stack:** Swift, SwiftUI (`codepet`), XCTest, xcodebuild. Reuses `ProjectStore`, `Project`, `CompanyStore.linkProject`, `CodepetTheme`, `MessageCard`. No new dependencies.

## Scope

**Part 2C-3.** In: the suggestion helper (testable), the Environment "Linked project" section, the `.noProject` inline offer, and the composer chip. Everything user-facing here is a view — build-verified + visually checked by the founder.

**Note:** the `.noProject` card state already exists (2C-2's `CodeRunCardView`); 2C-3 gives it a real "Link a project" action. The `CodeRunCardView` itself is 2C-2 (founder's).

## Global Constraints

- Native macOS SwiftUI; scheme `codepet` (lowercase); `@testable import codepet`; XCTest.
- Follow existing surfaces: Environment is a `ScrollView` of sections (`EnvironmentView`); the composer's chip row is `ChatComposer.deptChips`. Reuse `CodepetTheme` tokens, `MessageCard`; no new hardcoded colors, no decorative icons (design memory).
- The app is non-sandboxed → `NSOpenPanel` directory selection is the link primitive; on pick, call `companyStore.linkProject(path:bootstrapClaudeMd:)` (2A).
- **CLAUDE.md consent:** when the picked folder has no `CLAUDE.md`, ASK before writing one ("Create a CLAUDE.md from your brief so I have standing context?") and pass the answer as `bootstrapClaudeMd:`. Never write without consent (2A already never clobbers an existing one).
- Views are build-verified here; **the founder does the visual pass**.
- Build/test signing + close-app-before-test as before. Only Task 1 adds a unit test.
- Branch `feat/chat-redesign` (PR #39, held); do not push.

## File Structure

- **Create** `codepet/Models/ProjectLinkSuggestions.swift` — pure suggestion helper.
- **Create test** `codepetTests/ProjectLinkSuggestionsTests.swift`.
- **Modify** `codepet/Views/Environment/EnvironmentView.swift` — a "Linked project" section (Task 2, founder).
- **Modify** `codepet/Views/Copilot/CodeRunCardView.swift` — wire the `.noProject` "Link a project" action (Task 3, founder; the view is 2C-2's).
- **Modify** `codepet/Views/Copilot/ChatComposer.swift` — an active-project chip (Task 3, founder).

---

## Task 1: Suggestion helper (testable) — I execute this

**Files:**
- Create: `codepet/Models/ProjectLinkSuggestions.swift`
- Test: `codepetTests/ProjectLinkSuggestionsTests.swift`

**Interfaces:**
- Produces: `enum ProjectLinkSuggestions { static func suggest(from detected: [Project], excluding activePath: String?, max: Int = 4) -> [Project] }` — detected roots to offer as one-tap link chips: `ProjectStore.sortedProjects` order (most-recent first), excluding the already-active link, capped.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ProjectLinkSuggestionsTests.swift`:

```swift
import XCTest
@testable import codepet

final class ProjectLinkSuggestionsTests: XCTestCase {
    private func proj(_ path: String) -> Project {
        Project(id: path, displayName: Project.nameFromPath(path), brief: "",
                firstSeenAt: Date(), lastSeenAt: Date())
    }

    func test_excludesActiveLink_capsAndPreservesOrder() {
        let detected = [proj("/a"), proj("/b"), proj("/c"), proj("/d"), proj("/e")]
        let out = ProjectLinkSuggestions.suggest(from: detected, excluding: "/b", max: 3)
        XCTAssertEqual(out.map(\.id), ["/a", "/c", "/d"])   // /b excluded, order kept, capped to 3
    }

    func test_nilActive_returnsCappedFront() {
        let detected = [proj("/a"), proj("/b")]
        XCTAssertEqual(ProjectLinkSuggestions.suggest(from: detected, excluding: nil, max: 4).map(\.id), ["/a", "/b"])
    }

    func test_empty() {
        XCTAssertTrue(ProjectLinkSuggestions.suggest(from: [], excluding: nil).isEmpty)
    }
}
```

(Confirm `Project`'s memberwise init at implementation — `Project(id:displayName:brief:firstSeenAt:lastSeenAt:)` per the model, other fields defaulted.)

- [ ] **Step 2: Run to verify it fails**

```bash
ps aux | grep -i codepet.app | grep -v grep
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ProjectLinkSuggestionsTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: FAIL — `ProjectLinkSuggestions` not found.

- [ ] **Step 3: Implement**

Create `codepet/Models/ProjectLinkSuggestions.swift`:

```swift
import Foundation

/// Which auto-detected project roots to offer as one-tap "link this" chips in the
/// Environment link surface: `ProjectStore.sortedProjects` order (most-recent
/// first), minus the already-active link, capped. Pure.
enum ProjectLinkSuggestions {
    static func suggest(from detected: [Project], excluding activePath: String?, max: Int = 4) -> [Project] {
        Array(detected.filter { $0.id != activePath }.prefix(max))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ProjectLinkSuggestionsTests \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 \
  "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates 2>&1 | tail -15
```
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ProjectLinkSuggestions.swift codepetTests/ProjectLinkSuggestionsTests.swift
git commit -m "feat(coding-agent): project-link suggestion helper (Part 2C-3 Task 1)" -m "Pure ProjectLinkSuggestions.suggest over ProjectStore.sortedProjects (excludes the active link, capped) for the Environment link chips. 3/3 tests." -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Environment "Linked project" section (view — founder builds + visually verifies)

**Files:** Modify `codepet/Views/Environment/EnvironmentView.swift` (also needs `@EnvironmentObject var projectStore: ProjectStore` for suggestions — confirm it's injected in the shell; if not, inject it).

- [ ] Add a "Linked project" section (place after `companionLine`, before `recommendations`):
  - **When `companyStore.activeProjectLink != nil`:** a `MessageCard`-style row showing the linked path (last component bold, full path muted) + small badges: git (`⑂` if `isGitRepo`) and "CLAUDE.md ✓/–" (`hasClaudeMd`), and a "Change…" button (re-opens the picker).
  - **When nil:** a "Link a project folder" primary button + a row of suggestion chips from `ProjectLinkSuggestions.suggest(from: projectStore.sortedProjects, excluding: companyStore.activeProjectLink?.path)` — each chip labeled `Project.displayName`, tapping it links that path.
  - **Picker:** the button opens `NSOpenPanel` (directory, single, no multiple). On pick: if `ProjectProbe.probe(path:).hasClaudeMd == false`, present a confirm ("Create a CLAUDE.md from your brief?") → `companyStore.linkProject(path: url.path, bootstrapClaudeMd: confirmed)`; else `bootstrapClaudeMd: false`.
- [ ] Copy: match the "senior environment" voice; one line explaining what linking enables ("Link a project and I can make real code changes in it — on your machine, for your review, on your Claude subscription"). No credits framing needed here.
- [ ] Build (`** BUILD SUCCEEDED **`) + add a `#Preview` for both states. **Founder visual pass.**

---

## Task 3: Inline `.noProject` offer + composer chip (views — founder builds + visually verifies)

**Files:** Modify `codepet/Views/Copilot/CodeRunCardView.swift` (2C-2) + `codepet/Views/Copilot/ChatComposer.swift`.

- [ ] **`.noProject` offer:** in `CodeRunCardView`'s `.noProject` branch, make the "Link a project so I can make real changes" line a **button** that opens the same picker flow as Task 2 (extract the picker+consent into a small shared helper/view so both call sites use it), then re-proposes the run (or tells the founder to ask again once linked).
- [ ] **Composer chip:** in `ChatComposer.deptChips` (or the control row), when `companyStore.activeProjectLink != nil`, show a compact chip — the linked project's name + a small `⑂`/folder marker — so the founder always sees which project the coding agent will touch. Tapping it opens the Environment link surface (or a quick menu). Keep it visually quiet (it's context, not a primary control).
- [ ] Build (`** BUILD SUCCEEDED **`). **Founder visual pass** (mock mode: `-CODEPET_MOCK_CHAT YES`, trigger a code run with no link → see the offer; link a project → see the chip).

---

## Self-Review

**1. UI-design coverage:** matches the agreed 2C decision (Environment home + inline offer + composer chip). The link *logic* (2A `linkProject`) is reused; 2C-3 only adds surfaces + the pure suggestion helper.
**2. Placeholder scan:** Task 1 has complete code + tests. Tasks 2–3 are views — specified by their contract (what they show, which store calls they make, the consent rule) + build-verified + `#Preview` + the founder's visual pass; not over-specified as exact SwiftUI (the founder iterates visually).
**3. Type consistency:** `ProjectLinkSuggestions.suggest(from:excluding:max:)`, `CompanyStore.linkProject(path:bootstrapClaudeMd:)`, `ProjectProbe.probe(path:)`, `activeProjectLink`, `Project.displayName`/`.id`/`nameFromPath` all match 2A/the models.
**Confirm at implementation:** whether `EnvironmentView` has `ProjectStore` injected (Task 2) — inject via the shell if not. **Deferred:** none beyond the founder's visual build of Tasks 2–3; the coordinated deploy (PR #39 + 2C-server) still gates users seeing any of this.
