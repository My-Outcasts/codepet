# Composer chips + state expression + companion-tinted send Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Real department chips (grounding-scope), a companion-tinted send, and idle/focused/busy state on the composer — no fake affordances, no CF change.

**Architecture:** `ChatContext.compose` gains a `focusDepartment`; `sendChat`/`sendMessage` thread a selected `Department` into it; `ChatComposer` gains a chip row + state-expressing border/opacity + companion-tinted send; `CopilotChatView` owns the selection and the companion hues.

**Tech Stack:** SwiftUI (macOS), CodepetTheme, Xcode.

## Global Constraints

- Repo/branch: `My-Outcasts/codepet`, `feat/chat-redesign` (PR #39). Held. Rebase over concurrent commits before pushing.
- Build/test **FOREGROUND** only: `xcodebuild <build|test> -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- Synchronized folder groups — new `.swift` auto-includes; **no `project.pbxproj` edit**.
- SourceKit "Cannot find … in scope" for these files are known FALSE POSITIVES; `xcodebuild` is authoritative.
- Baseline suite: **0 real failures**; trailing overall `** TEST FAILED **` = known `CompanyStoreScaffordOnboardingTests` Firebase-init flake (NOT a regression; wobbles the COUNT — judge by "0 failures").
- **No CF/schema/dependency change. No fake affordances.** The `+` quick-actions menu and the `Ask ▾` mode menu stay. `department == nil` must reproduce today's behaviour exactly.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Composer look (chips, focus glow, busy dim, tinted send) is human-verified on a signed build (controller builds & launches).

---

### Task 1: `ChatContext.focusDepartment` + thread through `sendChat`

**Files:**
- Modify: `codepet/Models/ChatContext.swift`
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/ChatContextFocusTests.swift`

**Interfaces:**
- Produces: `ChatContext.compose(..., focusDepartment: Department? = nil)`; `CompanyStore.sendChat(_:language:department:)`. Consumed by Task 2's wiring.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/ChatContextFocusTests.swift`:

```swift
import XCTest
@testable import codepet

final class ChatContextFocusTests: XCTestCase {
    private let brief = CompanyBrief()
    private let dep = DepartmentCatalog.all.first!   // e.g. product/engineering

    func testFocusDirectivePresentWhenSet() {
        let out = ChatContext.compose(brief: brief, tasks: [], focusDepartment: dep)
        XCTAssertTrue(out.contains("focused on the \(dep.name) department"),
                      "focus directive should name the department")
        XCTAssertTrue(out.contains(dep.focus), "focus directive should include the dept focus line")
    }

    func testNoDirectiveWhenNil() {
        let out = ChatContext.compose(brief: brief, tasks: [], focusDepartment: nil)
        XCTAssertFalse(out.contains("focused on the"))
    }

    func testNilBranchEqualsDefaultCompose() {
        // Parity: passing focusDepartment nil must equal omitting it (no drift).
        let a = ChatContext.compose(brief: brief, tasks: [], focusDepartment: nil)
        let b = ChatContext.compose(brief: brief, tasks: [])
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Run tests → RED**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "ChatContextFocus|error:" | tail -8`
Expected: compile failure — `compose` has no `focusDepartment:` parameter.

- [ ] **Step 3: Add `focusDepartment` to `ChatContext.compose`**

In `codepet/Models/ChatContext.swift`, change the `compose` signature to add the parameter (keep it defaulted so existing callers are unaffected):
```swift
    static func compose(brief: CompanyBrief, tasks: [RoadmapTask], decisions: [DecisionEntry] = [],
                         library: [Deliverable] = [], query: String? = nil,
                         focusDepartment: Department? = nil) -> String {
```
Immediately after the brief part is appended (after `parts.append(BriefContext.compose(brief) ?? "No brief yet.")`), insert:
```swift
        if let dep = focusDepartment {
            parts.append("The founder is focused on the \(dep.name) department right now — "
                + "prioritize \(dep.name) in your answer: \(dep.focus)")
        }
```
Nothing else changes (the full department block still follows as today).

- [ ] **Step 4: Run tests → GREEN**

Run: `xcodebuild test -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "ChatContextFocusTests|Executed [0-9]+ tests" | tail -6`
Expected: the 3 ChatContextFocus tests pass; suite 0 real failures.

- [ ] **Step 5: Thread `department` through `sendChat`/`sendMessage`**

In `codepet/Managers/CompanyStore.swift`:
- `sendChat` (line ~307): add the param and forward it —
```swift
    func sendChat(_ raw: String, language: AppLanguage, department: Department? = nil) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await sendMessage(text, language: language, department: department)
    }
```
- `sendMessage` (line ~457): add `department: Department? = nil` to its signature.
- In the `ChatContext.compose(...)` call inside `sendMessage` (line ~479–480), add `focusDepartment: department` as the final argument:
```swift
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks, decisions: company.decisions,
                                          library: company.library, query: text, focusDepartment: department),
```
Do NOT change the run-task compose call (line ~727) or any other `sendMessage`/`sendChat` caller — they default to nil (today's behaviour).

- [ ] **Step 6: Build**

Run: `xcodebuild build -project codepet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add codepet/Models/ChatContext.swift codepet/Managers/CompanyStore.swift codepetTests/ChatContextFocusTests.swift
git commit -m "feat(chat): department-focus grounding scope (real dept chips backend)

ChatContext.compose gains focusDepartment; sendChat/sendMessage thread a
selected Department into it so a chip genuinely refocuses the model's
grounding. nil = today's behaviour (parity test). No CF change.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Composer chips + state expression + tinted send + wiring

**Files:**
- Modify: `codepet/Views/Copilot/ChatComposer.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift`

**Interfaces:**
- Consumes: `CompanyStore.sendChat(_:language:department:)` (Task 1), `DepartmentCatalog.all`, `PetCharacter.color`/`.secondColor`.

- [ ] **Step 1: Add the new inputs to `ChatComposer`**

In `ChatComposer`, add stored inputs (near the existing `var canSend`/`var placeholder`):
```swift
    var accent: Color
    var accent2: Color
    var isBusy: Bool
    @Binding var selectedDept: Department?
```

- [ ] **Step 2: Add the department chip row**

Insert a chip row between the `TextField` and the control `HStack` in `body`. Add this computed view and call it (`deptChips`) right after the `TextField(...)` modifiers:

```swift
    private var deptChips: some View {
        HStack(spacing: 6) {
            ForEach(DepartmentCatalog.all.prefix(3)) { dep in
                chip(dep)
            }
            Menu {
                ForEach(DepartmentCatalog.all.dropFirst(3)) { dep in
                    Button {
                        selectedDept = (selectedDept?.key == dep.key) ? nil : dep
                    } label: {
                        Label(dep.name, systemImage: selectedDept?.key == dep.key ? "checkmark" : "")
                    }
                }
            } label: {
                Text("•••").font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 10).frame(height: 26)
                    .overlay(Capsule().stroke(CodepetTheme.hairline))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
    }

    private func chip(_ dep: Department) -> some View {
        let on = selectedDept?.key == dep.key
        return Button {
            selectedDept = on ? nil : dep
        } label: {
            Text(dep.name).font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(on ? dep.accent : CodepetTheme.bodyText)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(on ? dep.accent.opacity(0.15) : Color.clear))
                .overlay(Capsule().stroke(on ? dep.accent : CodepetTheme.hairline))
        }.buttonStyle(.plain)
    }
```
In `body`, the `VStack(alignment: .leading, spacing: 12)` becomes: `TextField(...)`, then `deptChips`, then the control `HStack`.

- [ ] **Step 3: State-express the card + companion-tint the border/glow**

Change the composer's background/overlay/shadow (currently a fixed purple→pink gradient border + always-on purple glow) to use the companion `accent` and react to focus/busy. Replace the `.overlay(...stroke(LinearGradient…))` + the two shadows with:
```swift
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(focus.wrappedValue ? 0.9 : 0.5),
                        lineWidth: focus.wrappedValue ? 1.5 : 1.2)
        )
        .codepetShadow(CodepetTheme.floatingShadow)
        .shadow(color: (focus.wrappedValue && !reduceTransparency) ? accent.opacity(0.28) : .clear, radius: 18)
        .opacity(isBusy ? 0.72 : 1.0)
```
(Keep the `.background(RoundedRectangle(cornerRadius: 16).fill(CodepetTheme.surface))` as-is. `focus` is the existing `FocusState<Bool>.Binding`; `reduceTransparency` is the existing env var.)

- [ ] **Step 4: Companion-tint the send button**

In `sendButton`, change the `canSend` fill gradient from `[CodepetTheme.accentPurple, CodepetTheme.accentPink]` to `[accent, accent2]`, and the `canSend` glow from `accentPurple.opacity(0.55)` to `accent.opacity(0.55)`. The disabled fill (`mutedText`) and everything else unchanged.

- [ ] **Step 5: Update the `#Preview` host**

The `ChatComposerPreviewHost` (in `ChatComposer.swift`) must supply the new inputs. Add `@State private var dept: Department? = nil` and pass `accent: CodepetTheme.accentPurple, accent2: CodepetTheme.accentPink, isBusy: false, selectedDept: $dept` to the `ChatComposer(...)` init.

- [ ] **Step 6: Wire `CopilotChatView`**

In `CopilotChatView`:
- Add `@State private var selectedDept: Department?`.
- Add computed hues:
```swift
    private var companionAccent: Color { PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple }
    private var companionAccent2: Color { PetCharacter.all[companyStore.company.companionId]?.secondColor ?? CodepetTheme.accentPink }
```
- In `composerView`, pass the new inputs to `ChatComposer(...)`: `accent: companionAccent, accent2: companionAccent2, isBusy: companyStore.isCompanionTyping || companyStore.isStreaming, selectedDept: $selectedDept`.
- In `send()`, thread the department: change `Task { await companyStore.sendChat(text, language: lang) }` to `Task { await companyStore.sendChat(text, language: lang, department: selectedDept) }`.
- In `runQuickAction(_:)`, likewise pass `department: selectedDept` to its `sendChat` call (keeps the focus consistent for quick actions).

- [ ] **Step 7: Build + full suite**

Run build then test:
`xcodebuild build … CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3` → `** BUILD SUCCEEDED **`
`xcodebuild test … CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "codepetTests.xctest' (passed|failed)|Executed [0-9]+ tests" | tail -3` → `codepetTests.xctest` 0 real failures.

- [ ] **Step 8: Commit**

```bash
git add codepet/Views/Copilot/ChatComposer.swift codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): composer department chips + focus/busy states + tinted send

Real dept chips (first 3 + overflow) that scope the answer's grounding via
selectedDept -> sendChat(department:); border/glow follow focus in the
companion hue; card dims while busy; send fills the companion's colors.
Keeps the + quick-actions and Ask/Plan/Build menu.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation (controller, human sign-off)

Rebase over concurrent commits, push, build & launch signed. Founder verifies: chips render (3 + •••), toggle + tint on tap; focusing the field brightens the border to the companion hue with a glow; card dims + send greys while a reply streams; send shows the companion's colors; `+`/`Ask ▾` still work; and picking a department then asking yields a visibly department-focused reply. Watch the composer height on a small window (chips row).

---

## Self-Review

**1. Spec coverage:** grounding scope → Task 1 (compose + threading). Real chips → Task 2 Step 2 + Task 1 threading. State expression → Step 3. Companion-tinted send → Step 4. Keep `+`/mode → untouched in Step 2 (only inserts a row). Wiring/persist-selection → Step 6. Tests (directive present/absent + nil parity) → Task 1. ✓

**2. Placeholder scan:** Full code for the compose change, the tests, the chip row, the state modifiers, the send tint, the preview, and the wiring. No vague steps. ✓

**3. Type consistency:** `focusDepartment: Department?` defined Task 1, threaded via `sendChat(_:language:department:)` (Task 1) and called with `department: selectedDept` in Task 2 Step 6. `ChatComposer` new inputs (`accent`/`accent2`/`isBusy`/`selectedDept`) defined Step 1, supplied by `CopilotChatView` Step 6 and the preview Step 5. `DepartmentCatalog.all: [Department]` and `Department.{key,name,accent,focus}` confirmed present. `focus.wrappedValue`/`reduceTransparency` are existing members of `ChatComposer`. ✓
