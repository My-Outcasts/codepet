# Onboarding Fidelity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the native cinematic onboarding to match the live 9-step web flow: vertically-centered questions, a "Step N of 9" counter, byte→Codepet copy, and a new "Choose your companion" step before finish.

**Architecture:** View-layer only. Three edits + one new sub-view over the existing `OnboardingView`. Reuses `CompanyStore.setCompanion`, `PetCharacter`, and the existing `ChipFlowLayout`. Inherits the dynamic dark theming already on the branch.

**Tech Stack:** Swift 5 / SwiftUI (macOS 13+), XCTest.

## Global Constraints

- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/splash-onboarding-web-port`.
- **Toolchain:** scheme **`codepet`** (lowercase). Build: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20`. Test: `... xcodebuild test ... 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail`. FOREGROUND. Signed build (drop `CODE_SIGNING_ALLOWED=NO`) only for the Task-3 launch. SourceKit cross-file diagnostics are FALSE POSITIVES.
- **iCloud git:** `GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 … --no-verify`; `rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock"` before each git write; commits may hang → background, confirm HEAD advanced.
- **Exact copy (verbatim):** analysis heading `"Codepet is reading \(projectName)…"` (projectName empty → `"your project"`); companion step heading `"Choose your companion."`, subcopy `"Pick who'll accompany you as you build. You can change this anytime in the sidebar."`; reveal button `"Choose your companion"`; companion-step button `"Start building"`.
- **9 steps, 0-indexed:** 0 cold · 1 name · 2 role · 3 tech · 4 project(tall) · 5 stage · 6 analysis · 7 reveal · 8 companion. Counter = `step+1` of 9. Tall (top-align + scroll): steps 4 and 8. All others vertically centered.
- Don't touch Giang's Build Coach files or `CLAUDE.md`. `CompanyStore.setCompanion(id:) async`, `PetCharacter.starters` (`[String]`), `PetCharacter.all` (`[String: PetCharacter]`), `CharacterImage(_ id:size:)`, `ChipFlowLayout`, `CodepetTheme.body` all exist.

---

### Task 1: `total = 9` + `stepArt[8]` + analysis copy

**Files:**
- Modify: `codepet/Models/OnboardingContent.swift` (`total`, `stepArt`)
- Modify: `codepet/Views/Onboarding/OnboardingAnalysisView.swift` (heading copy)
- Test: `codepetTests/OnboardingContentTests.swift` (update counts)

- [ ] **Step 1: Update the failing test**

In `codepetTests/OnboardingContentTests.swift`, change the two count assertions:
```swift
        XCTAssertEqual(OnboardingContent.total, 9)
        // step art covers steps 0...8 (9 entries)
        XCTAssertEqual(OnboardingContent.stepArt.count, 9)
```
(Leave the other assertions unchanged.)

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingContentTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)|failed" | tail`
Expected: FAIL — `total` is 8 / `stepArt.count` is 8.

- [ ] **Step 3: Update OnboardingContent**

In `codepet/Models/OnboardingContent.swift`, set `total` to 9 and add a 9th `stepArt` entry (step 8 reuses the team scene — the source's per-step-8 art isn't ported):
```swift
    static let stepArt = [
        "ob-team", "ob-couch", "ob-chess", "ob-drummer",
        "ob-observatory", "ob-isometric", "ob-boardroom", "ob-team", "ob-team",
    ]
```
```swift
    static let total = 9
```

- [ ] **Step 4: Fix the analysis copy**

In `codepet/Views/Onboarding/OnboardingAnalysisView.swift`, change the heading:
```swift
            Text("Codepet is reading \(projectName.isEmpty ? "your project" : projectName)…")
                .font(CodepetTheme.body(20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingContentTests 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit (background)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Models/OnboardingContent.swift codepet/Views/Onboarding/OnboardingAnalysisView.swift codepetTests/OnboardingContentTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: onboarding total=9 + stepArt[8] + Codepet-is-reading copy" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `OnboardingCompanionStep` — the companion picker view

**Files:**
- Create: `codepet/Views/Onboarding/OnboardingCompanionStep.swift`

**Interfaces:**
- Produces: `struct OnboardingCompanionStep: View` — `init(pickedId: Binding<String>)`. Renders the heading + subcopy + a `PetCharacter.starters` grid; tapping a character sets `pickedId`.

- [ ] **Step 1: Create the view**

```swift
// codepet/Views/Onboarding/OnboardingCompanionStep.swift
import SwiftUI

/// Onboarding step 8 — pick the companion that rides along for the project.
/// Reuses the native PetCharacter roster; the selected one is highlighted with
/// its accent. Matches the web's "Choose your companion." step.
struct OnboardingCompanionStep: View {
    @Binding var pickedId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose your companion.")
                .font(CodepetTheme.body(20, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text("Pick who'll accompany you as you build. You can change this anytime in the sidebar.")
                .font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
                .padding(.top, 9)

            ChipFlowLayout(spacing: 12) {
                ForEach(PetCharacter.starters, id: \.self) { id in
                    let c = PetCharacter.all[id]
                    let sel = pickedId == id
                    let accent = c?.color ?? CodepetTheme.accentPurple
                    Button { pickedId = id } label: {
                        VStack(spacing: 6) {
                            CharacterImage(id, size: 44)
                            Text(c?.name ?? id)
                                .font(CodepetTheme.body(11, weight: .medium))
                                .foregroundColor(sel ? accent : CodepetTheme.mutedText)
                        }
                        .fixedSize()
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(sel ? accent.opacity(0.14) : CodepetTheme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(sel ? accent : CodepetTheme.hairline, lineWidth: sel ? 2 : 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail`
Expected: `** BUILD SUCCEEDED **`. (If `PetCharacter.starters` isn't `[String]` or `.all` isn't `[String: PetCharacter]`, adjust to the actual shape and note it — but both are used this way in `SplashView`/`SettingsView`.)

- [ ] **Step 3: Commit (background)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Views/Onboarding/OnboardingCompanionStep.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: OnboardingCompanionStep — the Choose-your-companion picker (step 8)" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: OnboardingView — step-8 wiring + reveal button + vertical centering

**Files:**
- Modify: `codepet/Views/Onboarding/OnboardingView.swift`

**Interfaces:**
- Consumes: `OnboardingCompanionStep` (Task 2), `CompanyStore.setCompanion(id:)`, `AppState.activeChar`, `OnboardingContent.total` (Task 1).

- [ ] **Step 1: Add `appState` + `pick`, default the pick**

In `codepet/Views/Onboarding/OnboardingView.swift`, add the environment object after `companyStore`:
```swift
    @EnvironmentObject var appState: AppState
```
Add `pick` to `ObDraft` (in the struct, after `stageIndex`):
```swift
        var pick = ""
```
Default the pick to the account's current companion when the view appears — add `.onAppear` to the root `Group` in `body` (the one with `.background(CodepetTheme.pageBackground…)`):
```swift
        .onAppear { if d.pick.isEmpty { d.pick = companyStore.company.companionId } }
```

- [ ] **Step 2: Center non-tall steps (replace the body wrapper)**

Replace the `ScrollView { stepBody … }` block inside `card` with a centered-vs-tall split:
```swift
                Group {
                    if step == 4 || step == 8 {   // tall: project + companion → top-align + scroll
                        ScrollView { stepBody.frame(maxWidth: 600, alignment: .leading) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {                       // vertically centered (SwiftUI .leading = leading + center-vertical)
                        stepBody.frame(maxWidth: 600, alignment: .leading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
```

- [ ] **Step 3: Add the step-8 body branch**

In `stepBody`, change the `default:` (reveal) to an explicit `case 7:` and add the companion `default:`:
```swift
        case 7:
            OnboardingRevealView(name: d.name, roleLabel: d.roleLabel, stageIndex: d.stageIndex, reveal: reveal ?? .empty)
        default:
            OnboardingCompanionStep(pickedId: $d.pick)
        }
```

- [ ] **Step 4: Reveal → "Choose your companion"; step 8 → "Start building"**

In `primaryButton`, change the reveal/default cases:
```swift
        case 7: bigButton("Choose your companion", enabled: true) { step = 8 }
        default: bigButton("Start building", enabled: true) { finishWithCompanion() }
```

- [ ] **Step 5: Add `finishWithCompanion()`**

Next to `finish()`:
```swift
    private func finishWithCompanion() {
        streamTask?.cancel(); scaffoldTask?.cancel()
        let token = companyStore.onboardingToken
        let id = d.pick.isEmpty ? companyStore.company.companionId : d.pick
        Task {
            await companyStore.setCompanion(id: id)
            appState.activeChar = id
            await companyStore.finishOnboarding(brief: brief(), token: token)
        }
    }
```

- [ ] **Step 6: Build the whole app**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" | tail`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Full test suite**

Run: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)" | tail -3`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Launch-verify (signed)**

```bash
cd ~/Documents/codepet-rebuild-wt
pkill -f "DerivedData/CodePet.*/codepet.app/Contents/MacOS/codepet" 2>/dev/null; sleep 1
xcodebuild build -scheme codepet -destination 'platform=macOS' 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)" | tail -1
open "/Users/monatruong/Library/Developer/Xcode/DerivedData/CodePet-dpobbamgdftkmwadibjmmhvazbcv/Build/Products/Debug/codepet.app"
```
Then (controller/human): Continue-without-signing → walk onboarding: questions **vertically centered**, counter reads **"Step N of 9"**, analysis says **"Codepet is reading"**, reveal button is **"Choose your companion"** → companion picker → **"Start building"** lands in the shell with the chosen companion. Repeat in Dark to confirm theming.

- [ ] **Step 9: Commit (background)**

```bash
cd ~/Documents/codepet-rebuild-wt
rm -f "/Users/monatruong/Documents/codepet/.git/worktrees/codepet-rebuild-wt/index.lock" 2>/dev/null
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 add codepet/Views/Onboarding/OnboardingView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -c gc.auto=0 commit --no-verify \
  -m "feat: onboarding step 8 (companion) + reveal wiring + vertical centering" \
  -m "Reveal → Choose your companion → picker → Start building (setCompanion + finish). Non-tall steps vertically centered." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final verification
Native onboarding: 9-step counter, vertically-centered questions (project + companion top-align/scroll), "Codepet is reading", reveal → "Choose your companion" → picker → "Start building" finishes with the chosen companion (`setCompanion` + `activeChar`). Build + full suite green; renders correctly in Light and Dark.

## Self-Review
**Spec coverage:** vertical centering (T3 S2 ✓); total 8→9 + stepArt[8] (T1 ✓); Codepet copy + reveal/companion button labels (T1 S4, T3 S4 ✓); new companion picker step (T2 + T3 S3/S5 ✓); default pick = current companion (T3 S1 ✓); setCompanion+activeChar+finish (T3 S5 ✓). No new screen removed; counter matches.

**Placeholder scan:** none — every code step is complete; commands have expected output.

**Type consistency:** `OnboardingCompanionStep(pickedId:)` (T2) matches its use `OnboardingCompanionStep(pickedId: $d.pick)` (T3 S3). `d.pick` added in T3 S1 and used in T3 S3/S5. `finishWithCompanion()` defined T3 S5, referenced T3 S4. `stepArt` (9) + `total` (9) consistent across T1 and their consumers. `setCompanion(id:)`/`activeChar` match the verified signatures.

**Known notes for the executor:** (a) `total`/`stepArt` are unit-checked; the views are build-verified; T3 S8 is the visual gate (launch). (b) `.frame(maxHeight:.infinity, alignment:.leading)` centers vertically (SwiftUI `.leading` = leading+center) — the mechanism behind step-2's centering. (c) controller transcribes verbatim, verifies FOREGROUND, commits in background; reviewers are the gate.
