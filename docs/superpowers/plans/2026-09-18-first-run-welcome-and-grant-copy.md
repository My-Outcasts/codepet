# First-Run Welcome + Grant Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Settings grant copy true, and turn the two-sentence first-run greeting into a project read the founder recognises plus an opt-in tour.

**Architecture:** Every new decision is a **pure static on an enum**, tested with no store and no SwiftUI — the pattern `BlockedOffer`, `ProviderGrantRow`, `OnboardingProviderStep` and `DraftPayloadPreview` all follow, and the reason is landmine 3 (the XCTest host crashes when a `@MainActor ObservableObject` deallocates). Views and `CompanyStore` only *call* these statics. Nothing new calls a model.

**Tech Stack:** Swift 5, SwiftUI, macOS 26.2, XCTest. Scheme `codepet`, test module `@testable import codepet`.

**Spec:** `docs/superpowers/specs/2026-09-18-first-run-welcome-and-grant-copy-design.md`

## Global Constraints

- **Run tests per-suite with `-only-testing:`.** Landmine 3: `xcodebuild test` exits 65 on a clean checkout and ~27 of ~970 tests never finish. That is not a regression you introduced.
- **Canonical test command:** `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -25`
- **Quit `codepet.app` before running tests.** A running app (or a sibling build) holds the Firestore lock and kills the test host, with a different victim each run.
- **Every string is bilingual.** `AppLanguage` is `.en` / `.vi`; there is no localisation table — copy is written out per case in Swift. A new string with no `.vi` counterpart is incomplete.
- **New `.swift` files need no project-file edit** (landmine 5: `PBXFileSystemSynchronizedRootGroup`).
- **`brief.goal`, `traction`, `problem`, `runway`, `constraints` are OFF LIMITS.** They are nil for every real founder — written only by the enrich interview, which has no caller — and non-nil only in the Murror demo fixture.
- **Do not commit to `main`.** Work on `spec/first-run-and-grant-copy`; PR at the end.
- **Do not move `greetIfNeeded` into `hydrate`.** Two tests pin that boundary; CLAUDE.md says so explicitly.
- **A guard needs a test that goes red when the guard is deleted.** A test that passes with and without the code it protects is not protecting anything.

## File Structure

| File | Responsibility | Tickets |
| --- | --- | --- |
| `codepet/Views/Settings/GrantCopy.swift` | **new** — pure per-provider grant copy + revoke-confirm decision | 1, 2 |
| `codepet/Views/Settings/ClaudeCodePanel.swift` | calls `GrantCopy`; hosts the confirm alert | 1, 2 |
| `codepet/Views/Onboarding/OnboardingProviderStep.swift` | gate subtitle copy | 3 |
| `codepet/Models/BriefRead.swift` | **new** — composes the "what I understood" paragraph | 4 |
| `codepet/Models/RoadmapShapeLine.swift` | **new** — composes the task/phase count line | 5 |
| `codepet/Models/FirstRunGreeting.swift` | assembles lead + read + shape + move; carries the tour offer | 6, 8 |
| `codepet/Models/TourScript.swift` | **new** — the locally-composed tour message | 7 |
| `codepet/Models/CopilotMessage.swift` | `tourOffer` + `tourConsumed` fields | 8 |
| `codepet/Views/Copilot/CopilotChatView.swift` | renders the tour chip after the primary action | 8 |
| `codepet/Managers/CompanyStore.swift` | `activateTour` appends the tour message | 8 |

Execution order puts **Part B (copy) first**: it is pure-string, independently shippable, and it is currently telling founders something false.

---

# PART B — the grant copy

### Ticket 1: Grant copy that matches behaviour

**Files:**
- Create: `codepet/Views/Settings/GrantCopy.swift`
- Modify: `codepet/Views/Settings/ClaudeCodePanel.swift` (delete `grantDescription`, call `GrantCopy`)
- Test: `codepetTests/GrantCopyTests.swift`

**Interfaces:**
- Produces: `GrantCopy.description(for: AIProvider, lang: AppLanguage) -> String`

**Why a new file:** `grantDescription` is a `private func` on a SwiftUI `View`, so the only way to assert its text is to build the view. Extracting it makes the copy testable and matches `ProviderGrantRow`, which already sits in this folder as a pure static for exactly this reason.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/GrantCopyTests.swift
import XCTest
@testable import codepet

/// The copy said "turn it off and Codepet goes back to the old route". There is no old
/// route: `ChatTransportRouter` and `LocalTransportRouter` both document that they have no
/// hosted case, and `CloudAIBlock.blockedPaths` refuses the endpoints outright. So the
/// toggle is the product's on/off switch, described as a preference — and a founder who
/// read it as optional declined it and landed in an app where nothing worked.
///
/// The Codex row had a second, different defect: it claimed chat and the department room,
/// which are `.claudeOnly` and have never run on Codex.
final class GrantCopyTests: XCTestCase {

    // MARK: - The retired lie

    /// The guard. Delete the rewrite and this goes red.
    func testNoProviderPromisesAFallbackRoute() {
        for provider in AIProvider.allCases {
            for lang in [AppLanguage.en, .vi] {
                let copy = GrantCopy.description(for: provider, lang: lang)
                XCTAssertFalse(copy.lowercased().contains("old route"),
                               "\(provider) \(lang) still promises a route that was deleted")
                XCTAssertFalse(copy.contains("đường cũ"),
                               "\(provider) \(lang) still promises a route that was deleted")
            }
        }
    }

    // MARK: - Claude: the kill switch says so

    func testClaudeSaysCodepetStopsWithoutIt() {
        let copy = GrantCopy.description(for: .claudeCode, lang: .en)
        XCTAssertTrue(copy.contains("Codepet needs this to work"))
        XCTAssertTrue(copy.contains("stops until you turn it back on"))
    }

    /// Benefit before cost: the founder learns what she gets before what it spends.
    func testClaudeLeadsWithTheBenefitNotTheCost() {
        let copy = GrantCopy.description(for: .claudeCode, lang: .en)
        let benefit = copy.range(of: "your own Claude plan")
        let cost = copy.range(of: "spends your Claude quota")
        XCTAssertNotNil(benefit); XCTAssertNotNil(cost)
        XCTAssertTrue(benefit!.lowerBound < cost!.lowerBound,
                      "cost is stated before the benefit it pays for")
    }

    func testClaudeKeepsTheTerminalReassurance() {
        XCTAssertTrue(GrantCopy.description(for: .claudeCode, lang: .en)
            .contains("terminal's Claude Code is unaffected"))
    }

    // MARK: - Codex: a different scope and a different off-state

    /// `BlockedOffer.Surface.claudeOnly` — chat streaming and the virtual company meeting
    /// run on Claude or nothing. Naming them here promised work Codex cannot do.
    func testCodexClaimsNoClaudeOnlySurface() {
        for lang in [AppLanguage.en, .vi] {
            let copy = GrantCopy.description(for: .codex, lang: lang).lowercased()
            XCTAssertFalse(copy.contains("chat"), "Codex copy still claims chat")
            XCTAssertFalse(copy.contains("department room"))
            XCTAssertFalse(copy.contains("phòng họp"))
        }
    }

    /// Codex off is not a kill switch: `LocalTransportRouter.chooseProvider` falls through
    /// Claude → Codex, so the one-shot work goes back to Claude when Claude is granted.
    func testCodexOffStateNamesTheClaudeFallback() {
        let copy = GrantCopy.description(for: .codex, lang: .en)
        XCTAssertTrue(copy.contains("goes back to Claude"))
        XCTAssertFalse(copy.contains("Codepet needs this to work"),
                       "Codex is not the kill switch; Claude is")
    }

    // MARK: - Both languages are real

    func testEveryProviderHasDistinctVietnamese() {
        for provider in AIProvider.allCases {
            let en = GrantCopy.description(for: provider, lang: .en)
            let vi = GrantCopy.description(for: provider, lang: .vi)
            XCTAssertFalse(vi.isEmpty)
            XCTAssertNotEqual(en, vi, "\(provider) has untranslated Vietnamese")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/GrantCopyTests 2>&1 | tail -25`

Expected: FAIL — `cannot find 'GrantCopy' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Views/Settings/GrantCopy.swift
import Foundation

/// What the Permission rows in `ClaudeCodePanel` actually say.
///
/// **Extracted from the view because the copy was wrong and untestable.** It said "turn it
/// off and Codepet goes back to the old route". There is no old route: `ChatTransportRouter`
/// and `LocalTransportRouter` each document that they have deliberately no hosted case, and
/// `CloudAIBlock.blockedPaths` refuses those endpoints before they leave the app. The Claude
/// toggle is the product's on/off switch, and describing it as a preference with a safe
/// fallback is what made founders decline it and land in an app where nothing ran.
///
/// **The two rows are not symmetric and must stop being written as if they were.** Claude off
/// stops everything. Codex off sends the one-shot ops back to Claude
/// (`LocalTransportRouter.chooseProvider` falls through Claude → Codex) and never touched chat
/// or the department room at all, which are `.claudeOnly`.
///
/// Kept as a static on an enum, outside any `@MainActor ObservableObject` — landmine 3, the
/// XCTest host crash on Xcode 26.2 — so a test asserts the strings with no SwiftUI. Same
/// reasoning as `ProviderGrantRow` beside it.
enum GrantCopy {

    /// Written out per provider rather than templated. The plan name, the scope and the
    /// off-state are three provider-specific facts, not one sentence with a hole in it —
    /// the same rule `ProviderAuthorisation.key` follows.
    static func description(for provider: AIProvider, lang: AppLanguage) -> String {
        switch provider {
        case .claudeCode:
            return lang == .vi
                ? """
                  Mọi thứ chạy trên gói Claude của chính bạn, ngay trên máy bạn — chat, lộ trình, \
                  nhiệm vụ, brief, quyết định, phòng họp các bộ phận, và Build khi bạn đã liên kết \
                  thư mục. Mỗi lượt tiêu hạn mức Claude của bạn.

                  Codepet cần quyền này để hoạt động. Tắt đi là Codepet dừng cho tới khi bạn bật \
                  lại. Claude Code trong terminal của bạn không bị ảnh hưởng.
                  """
                : """
                  Everything runs on your own Claude plan, on your Mac — chat, your roadmap, \
                  tasks, briefs, decisions, the department room, and Build once a folder is \
                  linked. Each turn spends your Claude quota.

                  Codepet needs this to work. Turn it off and it stops until you turn it back \
                  on. Your terminal's Claude Code is unaffected.
                  """
        case .codex:
            // No chat, no department room: both are `.claudeOnly`.
            return lang == .vi
                ? """
                  Nhiệm vụ, brief, quyết định và Build có thể chạy trên gói Codex của bạn, ngay \
                  trên máy bạn. Mỗi lượt tiêu hạn mức Codex của bạn.

                  Tắt đi thì phần việc này quay lại Claude nếu bạn đã cấp quyền Claude. Codex \
                  trong terminal của bạn không bị ảnh hưởng.
                  """
                : """
                  Tasks, briefs, decisions and Build can run on your Codex plan, on your Mac. \
                  Each turn spends your Codex quota.

                  Turn it off and that work goes back to Claude, when Claude is granted. Your \
                  terminal's Codex is unaffected.
                  """
        }
    }
}
```

- [ ] **Step 4: Point the panel at it**

In `codepet/Views/Settings/ClaudeCodePanel.swift`, delete the whole `private func grantDescription(for:)` method and replace its two call sites inside `grantRow(provider:companyId:)`:

```swift
            description: reachable
                ? GrantCopy.description(for: provider, lang: lang)
                : GrantCopy.description(for: provider, lang: lang) + "\n\n" + unreachableNote(for: provider)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/GrantCopyTests 2>&1 | tail -25`

Expected: PASS, 6 tests.

- [ ] **Step 6: Check nothing else asserted the old strings**

Run: `cd ~/Developer/codepet-firstrun && grep -rn "old route\|đường cũ" codepet codepetTests`

Expected: no output. If `ProviderGrantPanelTests` matches, update it in this ticket — do not leave a red suite for the next one.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet-firstrun
git add codepet/Views/Settings/GrantCopy.swift codepet/Views/Settings/ClaudeCodePanel.swift codepetTests/GrantCopyTests.swift
git commit -F - <<'EOF'
fix(settings): the grant copy described a route that was deleted

"Turn it off and Codepet goes back to the old route" named a fallback that
does not exist. ChatTransportRouter and LocalTransportRouter each document
having deliberately no hosted case, and CloudAIBlock.blockedPaths refuses
those endpoints before they leave the app. So the Claude toggle is the
product's on/off switch and the copy called it a preference -- a founder who
read it as optional declined it and landed in an app where nothing ran.

The Codex row had a separate defect: it claimed chat and the department room,
which are .claudeOnly and have never run on Codex. It now names only the
one-shot work, and says that work returns to Claude when Codex is off.

Copy moved out of the view into GrantCopy so the strings are asserted without
building SwiftUI -- the ProviderGrantRow pattern, for landmine 3.
EOF
```

---

### Ticket 2: Turning Claude off asks first

**Files:**
- Modify: `codepet/Views/Settings/GrantCopy.swift` (add the confirm decision + its copy)
- Modify: `codepet/Views/Settings/ClaudeCodePanel.swift` (alert + pending state)
- Test: `codepetTests/GrantRevokeConfirmTests.swift`

**Interfaces:**
- Consumes: `GrantCopy.description(for:lang:)` from Ticket 1
- Produces: `GrantCopy.needsRevokeConfirm(_ provider: AIProvider) -> Bool`, `GrantCopy.revokeTitle(lang:)`, `GrantCopy.revokeBody(lang:)`

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/GrantRevokeConfirmTests.swift
import XCTest
@testable import codepet

/// Turning the Claude grant off stops the product. While the copy promised a fallback that
/// was a one-click accident waiting to happen; with the copy fixed (see `GrantCopyTests`) it
/// is still worth one question, because the consequence is total.
///
/// Revocation stays fully possible — consent that cannot be withdrawn is not consent. This
/// only stops it happening unintentionally.
final class GrantRevokeConfirmTests: XCTestCase {

    /// Claude off = nothing runs. `ChatTransportRouter.transport` blocks on the grant, and
    /// `LocalTransportRouter.chooseProvider` has no other provider to fall through to.
    func testClaudeNeedsAConfirm() {
        XCTAssertTrue(GrantCopy.needsRevokeConfirm(.claudeCode))
    }

    /// Codex off is not a kill switch: the one-shot ops fall through to Claude. A confirm
    /// here would be ceremony for a consequence that does not occur.
    func testCodexDoesNotNeedAConfirm() {
        XCTAssertFalse(GrantCopy.needsRevokeConfirm(.codex))
    }

    /// The guard: if someone makes the confirm unconditional, this goes red.
    func testTheConfirmIsNotUnconditional() {
        let needing = AIProvider.allCases.filter(GrantCopy.needsRevokeConfirm)
        XCTAssertEqual(needing, [.claudeCode])
    }

    func testTheBodyNamesTheConsequenceAndTheTerminal() {
        let body = GrantCopy.revokeBody(lang: .en)
        XCTAssertTrue(body.contains("stops working until you turn this back on"))
        XCTAssertTrue(body.contains("terminal's Claude Code is unaffected"))
    }

    func testBothLanguagesArePresent() {
        XCTAssertFalse(GrantCopy.revokeTitle(lang: .vi).isEmpty)
        XCTAssertNotEqual(GrantCopy.revokeBody(lang: .en), GrantCopy.revokeBody(lang: .vi))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/GrantRevokeConfirmTests 2>&1 | tail -25`

Expected: FAIL — `type 'GrantCopy' has no member 'needsRevokeConfirm'`.

- [ ] **Step 3: Add the decision and copy to `GrantCopy`**

Append inside `enum GrantCopy`:

```swift
    /// Whether switching this provider OFF costs enough to ask about first.
    ///
    /// **Claude only, and that asymmetry is the whole point.** Claude off stops the product:
    /// `ChatTransportRouter.transport` blocks on the grant and `LocalTransportRouter` has no
    /// other provider to fall through to. Codex off sends the one-shot ops back to Claude, so
    /// a confirm there would be ceremony for a consequence that does not happen.
    ///
    /// Written as a switch rather than `provider == .claudeCode` so a third provider has to
    /// state its own answer instead of silently inheriting Codex's.
    static func needsRevokeConfirm(_ provider: AIProvider) -> Bool {
        switch provider {
        case .claudeCode: return true
        case .codex:      return false
        }
    }

    static func revokeTitle(lang: AppLanguage) -> String {
        lang == .vi ? "Tắt quyền dùng gói Claude?" : "Turn off Claude plan access?"
    }

    static func revokeBody(lang: AppLanguage) -> String {
        lang == .vi
            ? "Codepet sẽ dừng hoạt động cho tới khi bạn bật lại — chat, lộ trình, nhiệm vụ, brief, quyết định và Build. Claude Code trong terminal của bạn không bị ảnh hưởng dù bật hay tắt."
            : "Codepet stops working until you turn this back on — chat, roadmap, tasks, briefs, decisions and Build. Your terminal's Claude Code is unaffected either way."
    }

    static func revokeConfirm(lang: AppLanguage) -> String { lang == .vi ? "Tắt" : "Turn off" }
    static func revokeCancel(lang: AppLanguage) -> String { lang == .vi ? "Huỷ" : "Cancel" }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/GrantRevokeConfirmTests 2>&1 | tail -25`

Expected: PASS, 5 tests.

- [ ] **Step 5: Wire the alert into the panel**

In `ClaudeCodePanel.swift`, add state beside the existing `@State` properties:

```swift
    /// The provider whose revoke is waiting on the founder's answer. Nil when nothing is asked.
    @State private var pendingRevoke: AIProvider?
```

Change the `Toggle` binding inside `grantRow(provider:companyId:)` so turning OFF a
confirm-worthy provider defers the write instead of performing it:

```swift
            Toggle("", isOn: Binding(
                get: { granted.contains(provider) },
                set: { on in
                    // Turning OFF the kill switch asks first. Turning ON never does: granting
                    // is the recoverable direction, and a prompt there would be friction on
                    // the move we want the founder to make.
                    if !on, GrantCopy.needsRevokeConfirm(provider) {
                        pendingRevoke = provider
                        return
                    }
                    applyGrant(provider: provider, companyId: companyId, on: on)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
```

Add the writer next to `grantRow`, so the confirm and the direct path cannot drift:

```swift
    /// The one place a grant is written from this panel. Both the confirmed revoke and every
    /// unconfirmed flip land here, so they can never disagree about what "off" does.
    private func applyGrant(provider: AIProvider, companyId: String, on: Bool) {
        if on { granted.insert(provider) } else { granted.remove(provider) }
        authorisation.setAuthorised(provider, companyId, on)
        Task { await refresh() }
    }
```

Attach the alert to the same view that already carries the panel's modifiers (alongside the
existing `.task`/`.onAppear`), passing the company id the row was built with:

```swift
        .alert(GrantCopy.revokeTitle(lang: lang),
               isPresented: Binding(get: { pendingRevoke != nil },
                                    set: { if !$0 { pendingRevoke = nil } })) {
            Button(GrantCopy.revokeCancel(lang: lang), role: .cancel) { pendingRevoke = nil }
            Button(GrantCopy.revokeConfirm(lang: lang), role: .destructive) {
                if let p = pendingRevoke, let cid = companyId {
                    applyGrant(provider: p, companyId: cid, on: false)
                }
                pendingRevoke = nil
            }
        } message: {
            Text(GrantCopy.revokeBody(lang: lang))
        }
```

> **Note for the implementer:** read how `ClaudeCodePanel` currently obtains `companyId` — the
> grant rows receive it as a parameter (`grantGroup(companyId:)`). If it is not reachable where
> you attach the alert, thread it through rather than reading a global. Cancelling must leave
> the toggle ON; because the binding's `get` reads `granted`, which the deferred path never
> mutated, this happens for free — Step 6 proves it.

- [ ] **Step 6: Verify Cancel does not revoke**

Build and run the app signed, open Settings ▸ Permission, switch Claude off, press Cancel:

```bash
cd ~/Developer/codepet-firstrun && xcodebuild -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 build 2>&1 | tail -5
```

Expected: the toggle snaps back ON and chat still answers. Then switch off and press **Turn off**:
the toggle goes OFF and a chat turn reports the grant block with an inline grant button. Turn it
back on to leave the machine usable.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet-firstrun
git add codepet/Views/Settings/GrantCopy.swift codepet/Views/Settings/ClaudeCodePanel.swift codepetTests/GrantRevokeConfirmTests.swift
git commit -F - <<'EOF'
feat(settings): turning the Claude grant off asks once

Claude off stops the product -- ChatTransportRouter blocks on the grant and
LocalTransportRouter has no other provider to fall through to. It was a
one-click accident, under copy that promised a fallback.

Claude only. Codex off sends the one-shot ops back to Claude, so a confirm
there would be ceremony for a consequence that does not occur;
needsRevokeConfirm is a switch, not provider == .claudeCode, so a third
provider must state its own answer.

Revocation stays possible -- consent that cannot be withdrawn is not consent.
Both the confirmed revoke and every unconfirmed flip now write through one
applyGrant, so they cannot drift on what "off" means.
EOF
```

---

### Ticket 3: Onboarding stops promising a choice

**Files:**
- Modify: `codepet/Views/Onboarding/OnboardingProviderStep.swift:61`
- Test: `codepetTests/OnboardingProviderCopyTests.swift`

**Interfaces:**
- Produces: `OnboardingProviderStep.gateSubtitle(lang: AppLanguage) -> String`

**Why:** the screen says "Install either one; **you'll choose whether to use it later**." There is
no choice — without a grant nothing runs. The honest version states what happens instead: Codepet
runs on the plan, and it asks before spending it the first time. The copy moves onto the existing
`OnboardingProviderStep` enum (already a pure static for landmine 3) so it is assertable.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/OnboardingProviderCopyTests.swift
import XCTest
@testable import codepet

/// The gate told the founder she would "choose whether to use it later". She does not choose:
/// without a grant nothing in the product runs. What is true is that nothing is spent until
/// she is asked, which is a promise worth making and a different sentence.
final class OnboardingProviderCopyTests: XCTestCase {

    func testTheGateNoLongerOffersAChoiceThatDoesNotExist() {
        for lang in [AppLanguage.en, .vi] {
            let copy = OnboardingProviderStep.gateSubtitle(lang: lang).lowercased()
            XCTAssertFalse(copy.contains("choose whether"))
            XCTAssertFalse(copy.contains("chọn xem"))
        }
    }

    /// It must still say installation is all that is wanted here — the screen has no toggle
    /// and asks for no grant, and saying otherwise would make the install look insufficient.
    func testItStillAsksOnlyForAnInstall() {
        let copy = OnboardingProviderStep.gateSubtitle(lang: .en)
        XCTAssertTrue(copy.contains("Install either one"))
    }

    /// The promise that replaces the false choice: nothing is spent unasked.
    func testItPromisesToAskBeforeSpending() {
        XCTAssertTrue(OnboardingProviderStep.gateSubtitle(lang: .en)
            .contains("ask before it spends"))
        XCTAssertFalse(OnboardingProviderStep.gateSubtitle(lang: .vi).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingProviderCopyTests 2>&1 | tail -25`

Expected: FAIL — no member `gateSubtitle`.

- [ ] **Step 3: Add the static and use it**

Inside `enum OnboardingProviderStep`, after `passes(installed:)`:

```swift
    /// The gate's subtitle.
    ///
    /// It used to end "you'll choose whether to use it later", which is not true — without a
    /// grant nothing in the product runs, so the later moment is a delay rather than a choice.
    /// What IS true is that nothing is spent until she is asked, which is the promise this
    /// screen can actually keep (`ProviderConsentFlow`, and the grant button on a blocked card).
    static func gateSubtitle(lang: AppLanguage) -> String {
        lang == .vi
            ? "Codepet chạy mọi việc trên CLI bạn đã có — Claude Code hoặc Codex. Hãy cài một trong hai; Codepet sẽ hỏi bạn trước khi dùng tới hạn mức của bạn."
            : "Codepet runs every task on a CLI you already have — Claude Code, or Codex. Install either one; Codepet will ask before it spends your plan."
    }
```

Then in `OnboardingProviderGateView.body`, replace the hardcoded subtitle `Text(...)` with:

```swift
            Text(OnboardingProviderStep.gateSubtitle(lang: lang))
```

> `OnboardingProviderGateView` does not currently read the language. Add
> `@Environment(\.uiLanguage) private var lang` to the struct — the same declaration
> `OverviewIntroSheet` and `ClaudeCodePanel` use.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/OnboardingProviderCopyTests 2>&1 | tail -25`

Expected: PASS, 3 tests.

- [ ] **Step 5: Confirm the neighbouring suite still passes**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ProviderConsentTests -only-testing:codepetTests/ProviderGrantPanelTests 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-firstrun
git add codepet/Views/Onboarding/OnboardingProviderStep.swift codepetTests/OnboardingProviderCopyTests.swift
git commit -F - <<'EOF'
fix(onboarding): the gate promised a choice the product does not offer

"You'll choose whether to use it later" is not true -- without a grant
nothing runs, so the later moment is a delay, not a choice. Replaced with the
promise the screen can keep: Codepet asks before it spends the plan, which is
what ProviderConsentFlow and the blocked card's grant button actually do.

Copy moved onto the OnboardingProviderStep enum so it is asserted without
building the view, matching how passes(installed:) is already tested.
EOF
```

---

# PART A — the welcome

### Ticket 4: `BriefRead` — what Codepet understood

**Files:**
- Create: `codepet/Models/BriefRead.swift`
- Test: `codepetTests/BriefReadTests.swift`

**Interfaces:**
- Produces: `BriefRead.compose(brief: CompanyBrief, language: AppLanguage) -> String?` — nil when there is no anchor.

**The rules this encodes, all from the spec:**
1. Anchor is `summary` when present, else `oneLiner`. **No anchor → nil**, even though `stage` is always set: a bare stage label tells the founder only what she picked from a slider.
2. Every field goes through `MeaningfulText.clean` — the convention at `RoadmapView.swift:62`.
3. `goal` is never read. It is nil for every real founder.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/BriefReadTests.swift
import XCTest
@testable import codepet

/// The greeting named the founder's project and never said anything about it. This composes
/// the missing "here's what I understood" paragraph from what she actually typed.
///
/// **Why not the model's own summary alone.** `brief.summary` is written by onboarding's
/// enrich step, which runs on the founder's Claude — and she has not granted it yet, because
/// consent is asked at first use and onboarding comes first. `localOneShot` throws
/// `.blocked(.notGranted)` and `CompanyStore:807` fails open, so `summary` is nil on first
/// run for everyone. It IS filled later, for a founder who edits her brief after granting,
/// which is why it still wins when present.
final class BriefReadTests: XCTestCase {

    private func brief(oneLiner: String? = nil, summary: String? = nil,
                       audience: String? = nil, stage: String? = "Building",
                       goal: String? = nil) -> CompanyBrief {
        CompanyBrief(stage: stage, oneLiner: oneLiner, summary: summary,
                     audience: audience, goal: goal)
    }

    // MARK: - The anchor rule

    /// `stage` is the one field that is ALWAYS non-nil (`CompanyOnboardingModel` defaults it
    /// to "Building"). Composing off it alone would tell the founder what she picked from a
    /// slider and call it a read.
    func testStageAloneProducesNothing() {
        XCTAssertNil(BriefRead.compose(brief: brief(), language: .en))
    }

    func testAudienceWithoutAnAnchorProducesNothing() {
        XCTAssertNil(BriefRead.compose(brief: brief(audience: "solo founders"), language: .en))
    }

    func testOneLinerIsEnoughToRender() {
        let out = BriefRead.compose(brief: brief(oneLiner: "A macOS AI coding companion"),
                                    language: .en)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("A macOS AI coding companion"))
    }

    // MARK: - summary wins, and they never both render

    func testSummaryBeatsOneLiner() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "RAW ONE LINER", summary: "ENRICHED READ"),
            language: .en)!
        XCTAssertTrue(out.contains("ENRICHED READ"))
        XCTAssertFalse(out.contains("RAW ONE LINER"), "both anchors rendered")
    }

    // MARK: - MeaningfulText, not a bare ??

    /// A bare `??` would render "Here's what I understood: x".
    func testPlaceholderyAnchorIsTreatedAsAbsent() {
        XCTAssertNil(BriefRead.compose(brief: brief(oneLiner: "x"), language: .en))
        XCTAssertNil(BriefRead.compose(brief: brief(oneLiner: "12345"), language: .en))
        XCTAssertNil(BriefRead.compose(brief: brief(oneLiner: "me@example.com"), language: .en))
    }

    func testPlaceholderyAudienceIsDroppedButTheAnchorSurvives() {
        let out = BriefRead.compose(brief: brief(oneLiner: "A coding companion", audience: "x"),
                                    language: .en)!
        XCTAssertTrue(out.contains("A coding companion"))
        XCTAssertFalse(out.contains(" x"), "placeholder audience rendered")
    }

    // MARK: - goal is off limits

    /// `brief.goal` is written only by the enrich-interview handler (`CompanyStore:694`) and
    /// the Murror fixture, and `startEnrichInterviewIfNeeded` has no caller in the app. A read
    /// built on it would be blank for every real founder and correct only in the demo.
    func testGoalIsNeverRead() {
        let withGoal = brief(oneLiner: "A coding companion", goal: "Launch in August")
        let without  = brief(oneLiner: "A coding companion")
        XCTAssertEqual(BriefRead.compose(brief: withGoal, language: .en),
                       BriefRead.compose(brief: without, language: .en),
                       "goal leaked into the read")
    }

    // MARK: - Trimmings

    func testAudienceAndStageAreAddedWhenPresent() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "A coding companion", audience: "solo founders",
                         stage: "Prototype"),
            language: .en)!
        XCTAssertTrue(out.contains("solo founders"))
        XCTAssertTrue(out.lowercased().contains("prototype"))
    }

    func testVietnameseIsADifferentSentence() {
        let b = brief(oneLiner: "Một trợ lý lập trình", audience: "nhà sáng lập")
        let vi = BriefRead.compose(brief: b, language: .vi)!
        let en = BriefRead.compose(brief: b, language: .en)!
        XCTAssertNotEqual(vi, en)
        XCTAssertTrue(vi.contains("Một trợ lý lập trình"))
    }

    /// The five stage values are English literals in `CompanyOnboardingModel.stages`, so the
    /// Vietnamese read must translate them rather than splicing an English word mid-sentence.
    func testKnownStagesAreTranslatedForVietnamese() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "Một trợ lý", stage: "Building"), language: .vi)!
        XCTAssertFalse(out.contains("Building"), "English stage label spliced into Vietnamese")
    }

    /// An unknown stage (an older brief, a hand-edited document) must pass through rather
    /// than vanish or crash.
    func testUnknownStageFallsBackToItsRawValue() {
        let out = BriefRead.compose(
            brief: brief(oneLiner: "A coding companion", stage: "Scaling"), language: .en)!
        XCTAssertTrue(out.contains("Scaling"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/BriefReadTests 2>&1 | tail -25`

Expected: FAIL — `cannot find 'BriefRead' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Models/BriefRead.swift
import Foundation

/// The greeting's "here's what I understood" paragraph, composed from the founder's own brief.
///
/// **Composed locally, on purpose.** Chat is `.claudeOnly` and blocked until the founder grants
/// her plan, so a model-written welcome would either arrive blocked on a fresh account or force
/// the permission ask to the front of onboarding — the trade `OnboardingProviderStep` exists to
/// avoid. This is a pure function over `CompanyBrief`.
///
/// **What it may read.** Only the fields `CompanyOnboardingModel.brief` actually fills:
/// `oneLiner`, `audience`, `stage`, plus `summary` when a later brief edit enriched it.
/// `goal`, `traction`, `problem`, `runway` and `constraints` are nil for every real founder —
/// written only by the enrich interview, which has no caller in the app — and non-nil only in
/// the Murror fixture, which is the worst possible place for a paragraph to look correct.
///
/// Kept outside any `@MainActor ObservableObject` — landmine 3 — so a test exercises it with no
/// store and no view.
enum BriefRead {

    /// The paragraph, or nil when there is nothing worth saying.
    ///
    /// **The anchor rule.** `stage` is the only field that is always present
    /// (`CompanyOnboardingModel` defaults it to "Building"), so a naive composition would emit
    /// "You're at the Building stage." for a founder who typed nothing else — telling her what
    /// she picked from a slider and calling it a read. The paragraph therefore requires
    /// `summary` or `oneLiner`; audience and stage are trimmings on that anchor, never the
    /// whole sentence.
    static func compose(brief: CompanyBrief, language: AppLanguage) -> String? {
        // `MeaningfulText.clean`, not `??` — it rejects a one-character answer, an all-digits
        // one and an email address. The convention for this exact field at `RoadmapView:62`.
        guard let anchor = MeaningfulText.clean(brief.summary)
                        ?? MeaningfulText.clean(brief.oneLiner) else { return nil }

        let vi = language == .vi
        var out = vi ? "Đây là những gì mình hiểu: \(sentence(anchor))"
                     : "Here's what I understood: \(sentence(anchor))"

        if let audience = MeaningfulText.clean(brief.audience) {
            out += vi ? " Dành cho \(sentence(audience))" : " It's for \(sentence(audience))"
        }
        if let stage = MeaningfulText.clean(brief.stage) {
            out += vi ? " Bạn đang ở giai đoạn \(stageLabel(stage, vi: true))."
                      : " You're at the \(stageLabel(stage, vi: false)) stage."
        }
        return out
    }

    /// Ends a founder-typed fragment with a full stop without doubling one she already typed.
    private static func sentence(_ raw: String) -> String {
        let last = raw.last
        return (last == "." || last == "!" || last == "?") ? raw : raw + "."
    }

    /// The five values `CompanyOnboardingModel.stages` can produce, translated.
    ///
    /// They are English literals in that array, so the Vietnamese read has to map them or it
    /// splices an English word into a Vietnamese sentence. Anything else — an older brief, a
    /// hand-edited document — passes through unchanged rather than vanishing.
    private static func stageLabel(_ raw: String, vi: Bool) -> String {
        guard vi else { return raw.lowercased() }
        switch raw {
        case "Idea":         return "ý tưởng"
        case "Prototype":    return "nguyên mẫu"
        case "Building":     return "đang xây dựng"
        case "Private beta": return "beta kín"
        case "Launched":     return "đã ra mắt"
        default:             return raw
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/BriefReadTests 2>&1 | tail -25`

Expected: PASS, 11 tests.

- [ ] **Step 5: Break the anchor guard on purpose**

Temporarily change the `guard` to `let anchor = MeaningfulText.clean(brief.summary) ?? brief.oneLiner ?? ""`, re-run, and confirm `testStageAloneProducesNothing` and `testPlaceholderyAnchorIsTreatedAsAbsent` go RED. Then revert.

This is the step that proves the guard is protecting something — per the working agreement, a test that passes with and without the code it guards is not a test.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-firstrun
git add codepet/Models/BriefRead.swift codepetTests/BriefReadTests.swift
git commit -F - <<'EOF'
feat(first-run): compose the project read from the founder's own brief

The greeting named the project and never said anything about it. BriefRead
writes the missing paragraph from what she typed -- locally, because chat is
.claudeOnly and blocked until she grants her plan, so a model-written welcome
would arrive blocked on a fresh account.

Anchored on summary-or-oneLiner and nil without one. stage is the only field
always present (defaulted to "Building"), so composing off it alone would
report the founder's own slider pick back to her as a read.

Reads nothing that is not actually filled: goal/traction/problem/runway/
constraints come from the enrich interview, which has no caller in the app,
so they are nil for every real founder and non-nil only in the Murror
fixture. A test pins that goal never leaks in.

Every field goes through MeaningfulText.clean rather than ??, the convention
at RoadmapView:62 -- otherwise a founder who typed "x" reads "Here's what I
understood: x".
EOF
```

---

### Ticket 5: `RoadmapShapeLine` — the board in one sentence

**Files:**
- Create: `codepet/Models/RoadmapShapeLine.swift`
- Test: `codepetTests/RoadmapShapeLineTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask`, `RoadmapPhase` (existing)
- Produces: `RoadmapShapeLine.compose(tasks: [RoadmapTask], language: AppLanguage) -> String?`

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/RoadmapShapeLineTests.swift
import XCTest
@testable import codepet

/// One sentence telling the founder how much was lined up for her. The greeting jumped
/// straight from "your company is ready" to a single task, which undersold a board of a dozen.
final class RoadmapShapeLineTests: XCTestCase {

    private func task(_ id: String, _ phase: RoadmapPhase) -> RoadmapTask {
        RoadmapTask(id: id, title: id, phase: phase)
    }

    func testNoTasksProducesNothing() {
        XCTAssertNil(RoadmapShapeLine.compose(tasks: [], language: .en))
    }

    /// The plural trap: "1 tasks across 1 phases".
    func testOneTaskInOnePhaseIsSingular() {
        let out = RoadmapShapeLine.compose(tasks: [task("a", .foundation)], language: .en)!
        XCTAssertTrue(out.contains("1 task"))
        XCTAssertFalse(out.contains("1 tasks"))
        XCTAssertTrue(out.contains("1 phase"))
        XCTAssertFalse(out.contains("1 phases"))
    }

    func testManyTasksAcrossManyPhasesIsPlural() {
        let tasks = [task("a", .foundation), task("b", .foundation), task("c", .find)]
        let out = RoadmapShapeLine.compose(tasks: tasks, language: .en)!
        XCTAssertTrue(out.contains("3 tasks"))
        XCTAssertTrue(out.contains("2 phases"))
    }

    /// Phases are counted DISTINCT, not as the number of tasks.
    func testPhasesAreCountedOnce() {
        let tasks = [task("a", .foundation), task("b", .foundation), task("c", .foundation)]
        let out = RoadmapShapeLine.compose(tasks: tasks, language: .en)!
        XCTAssertTrue(out.contains("3 tasks"))
        XCTAssertTrue(out.contains("1 phase"))
    }

    func testVietnameseIsADifferentSentence() {
        let tasks = [task("a", .foundation), task("b", .find)]
        XCTAssertNotEqual(RoadmapShapeLine.compose(tasks: tasks, language: .vi),
                          RoadmapShapeLine.compose(tasks: tasks, language: .en))
    }
}
```

> **Before writing the implementation:** confirm `RoadmapTask`'s initialiser and `RoadmapPhase`'s
> case names by reading `codepet/Models/RoadmapTask.swift`. The helper above assumes
> `RoadmapTask(id:title:phase:)` and cases `.foundation` / `.find`, which is what
> `BeaconOffer.candidates` and `DemoProject` use — if the real initialiser needs more
> arguments, fix the helper, not the assertions.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapShapeLineTests 2>&1 | tail -25`

Expected: FAIL — `cannot find 'RoadmapShapeLine' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Models/RoadmapShapeLine.swift
import Foundation

/// "I've lined up 14 tasks across 4 phases." — the board in one sentence.
///
/// The greeting went straight from "your company is ready" to a single next move, which
/// undersold a board of a dozen tasks. Pure, and separate from `BriefRead` so a reviewer can
/// reject one without the other.
///
/// Outside any `@MainActor ObservableObject` — landmine 3.
enum RoadmapShapeLine {

    static func compose(tasks: [RoadmapTask], language: AppLanguage) -> String? {
        guard !tasks.isEmpty else { return nil }
        let taskCount = tasks.count
        // DISTINCT phases. Counting `tasks.count` twice is the obvious wrong answer here.
        let phaseCount = Set(tasks.map(\.phase)).count

        if language == .vi {
            // Vietnamese does not inflect for number, so one form covers both.
            return "Mình đã chuẩn bị \(taskCount) việc trong \(phaseCount) giai đoạn."
        }
        let t = taskCount == 1 ? "1 task" : "\(taskCount) tasks"
        let p = phaseCount == 1 ? "1 phase" : "\(phaseCount) phases"
        return "I've lined up \(t) across \(p)."
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/RoadmapShapeLineTests 2>&1 | tail -25`

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet-firstrun
git add codepet/Models/RoadmapShapeLine.swift codepetTests/RoadmapShapeLineTests.swift
git commit -F - <<'EOF'
feat(first-run): say how much was lined up, in one sentence

The greeting jumped from "your company is ready" to a single next move, which
undersold a board of a dozen tasks.

Phases are counted distinct rather than as the task count, and the English
form inflects -- "1 tasks across 1 phases" is the trap a plural-blind version
walks into. Vietnamese does not inflect for number, so it takes one form.

Kept separate from BriefRead so a reviewer can reject the read composition
without rejecting the counts.
EOF
```

---

### Ticket 6: Assemble the greeting

**Files:**
- Modify: `codepet/Models/FirstRunGreeting.swift`
- Test: `codepetTests/FirstRunGreetingTests.swift` (extend the existing suite)

**Interfaces:**
- Consumes: `BriefRead.compose(brief:language:)` (Ticket 4), `RoadmapShapeLine.compose(tasks:language:)` (Ticket 5)
- Produces: `FirstRunGreetingBuilder.build(brief:nextStep:tasks:language:)` — **note the new `tasks:` parameter**

**Breaking change:** `build` gains a `tasks: [RoadmapTask]` argument, because the shape line needs
the whole board and `nextStep` is only one task. Every existing caller must be updated in this
ticket: `CompanyStore.seedFirstRunGreeting` and whatever `FirstRunGreetingTests` /
`CompanyStoreFirstRunGreetingTests` pass today.

- [ ] **Step 1: Read the existing suites first**

Run: `cd ~/Developer/codepet-firstrun && grep -n "FirstRunGreetingBuilder.build" codepet codepetTests -r`

Note every call site. You will update all of them in Step 4.

- [ ] **Step 2: Write the failing tests**

Append to `codepetTests/FirstRunGreetingTests.swift`:

```swift
    // MARK: - The paragraphs added 2026-09-18

    /// Order is load-bearing: the founder should meet her project before her first task.
    func testTheReadComesBetweenTheLeadAndTheMove() {
        let brief = CompanyBrief(stage: "Building", founderName: "Mona",
                                 projectName: "Codepet",
                                 oneLiner: "A macOS AI coding companion")
        let tasks = [RoadmapTask(id: "t1", title: "Lock the pricing copy", phase: .foundation)]
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: tasks[0],
                                              tasks: tasks, language: .en)

        let lead = g.text.range(of: "Mona, your company for Codepet is ready.")
        let read = g.text.range(of: "Here's what I understood")
        let move = g.text.range(of: "The best first move is")
        XCTAssertNotNil(lead); XCTAssertNotNil(read); XCTAssertNotNil(move)
        XCTAssertTrue(lead!.lowerBound < read!.lowerBound)
        XCTAssertTrue(read!.lowerBound < move!.lowerBound)
    }

    func testTheShapeLineIsIncludedWhenThereAreTasks() {
        let brief = CompanyBrief(stage: "Building", projectName: "Codepet",
                                 oneLiner: "A macOS AI coding companion")
        let tasks = [RoadmapTask(id: "a", title: "A", phase: .foundation),
                     RoadmapTask(id: "b", title: "B", phase: .find)]
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: tasks[0],
                                              tasks: tasks, language: .en)
        XCTAssertTrue(g.text.contains("2 tasks across 2 phases"))
    }

    /// A brief with no anchor must not produce a dangling "Here's what I understood:" —
    /// the paragraph is dropped whole and the greeting still reads as prose.
    func testAnUnreadableBriefDropsTheParagraphNotTheGreeting() {
        let brief = CompanyBrief(stage: "Building", founderName: "Mona", projectName: "Codepet")
        let tasks = [RoadmapTask(id: "t1", title: "Lock the pricing copy", phase: .foundation)]
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: tasks[0],
                                              tasks: tasks, language: .en)
        XCTAssertFalse(g.text.contains("Here's what I understood"))
        XCTAssertTrue(g.text.contains("Mona, your company for Codepet is ready."))
        XCTAssertTrue(g.text.contains("The best first move is"))
        XCTAssertFalse(g.text.contains("\n\n\n"), "a dropped paragraph left a hole")
    }

    /// The existing no-task branch keeps its own tail and gains no shape line.
    func testNoTasksKeepsTheLookAroundTailAndNoShapeLine() {
        let brief = CompanyBrief(stage: "Building", projectName: "Codepet",
                                 oneLiner: "A macOS AI coding companion")
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: nil,
                                              tasks: [], language: .en)
        XCTAssertTrue(g.text.contains("Take a look around"))
        XCTAssertFalse(g.text.contains("lined up"))
        XCTAssertNil(g.action)
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/FirstRunGreetingTests 2>&1 | tail -25`

Expected: FAIL — `extra argument 'tasks' in call`.

- [ ] **Step 4: Change the builder**

In `codepet/Models/FirstRunGreeting.swift`, replace the body of `FirstRunGreetingBuilder.build`
with a version that takes `tasks` and assembles paragraphs. Keep the existing lead and tail copy
byte-for-byte — they are asserted by the existing tests and are not what this ticket changes:

```swift
    /// - Parameter tasks: the whole board. `nextStep` names ONE task; the shape line counts
    ///   them all, and deriving a count from `nextStep` is not possible.
    static func build(brief: CompanyBrief, nextStep: RoadmapTask?,
                      tasks: [RoadmapTask], language: AppLanguage) -> FirstRunGreeting {
        let who = (brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let projRaw = (brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let proj = projRaw.isEmpty ? (language == .vi ? "sản phẩm của bạn" : "your product") : projRaw

        let lead: String
        if who.isEmpty {
            lead = language == .vi
                ? "Công ty cho \(proj) đã sẵn sàng."
                : "Your company for \(proj) is ready."
        } else {
            lead = language == .vi
                ? "\(who), công ty cho \(proj) đã sẵn sàng."
                : "\(who), your company for \(proj) is ready."
        }

        // Paragraphs, assembled by filtering nils and joining ONCE. Appending to a string
        // with conditional "\n\n" prefixes is how a dropped middle paragraph leaves a hole;
        // `compactMap` cannot.
        let middle = [BriefRead.compose(brief: brief, language: language),
                      RoadmapShapeLine.compose(tasks: tasks, language: language)]

        guard let task = nextStep else {
            let tail = language == .vi
                ? "Cứ khám phá xung quanh — mở bất kỳ phần nào trong công ty để xem mình đã chuẩn bị gì, và mình sẽ làm cùng bạn khi bạn sẵn sàng."
                : "Take a look around — open any part of your company to see what I've lined up, and I'll produce the work with you whenever you're ready."
            // No board, so no shape line: `RoadmapShapeLine.compose` already returns nil on
            // an empty array, and this branch is only reached when `nextStep` is nil.
            return FirstRunGreeting(text: paragraphs([lead] + middle + [tail]), action: nil)
        }

        let tail = language == .vi
            ? "Bước đầu tốt nhất là \"\(task.title)\". Bạn muốn mình làm cùng bạn ngay tại đây chứ? Mình soạn bản nháp, bạn duyệt — không có gì được xuất bản nếu bạn chưa đồng ý."
            : "The best first move is \"\(task.title)\". Want me to do it with you, right here? I'll draft it and you approve — nothing ships without your say-so."
        return FirstRunGreeting(text: paragraphs([lead] + middle + [tail]),
                                action: FirstRunAction(taskId: task.id, taskTitle: task.title))
    }

    /// Joins the paragraphs that exist. `CopilotChatView.prose` splits on blank lines and
    /// renders one block per paragraph, so "\n\n" is the separator it expects.
    private static func paragraphs(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
             .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
             .joined(separator: "\n\n")
    }
```

> **Note:** the original built its tail by string concatenation with a leading space
> (`lead + tail`). The version above makes the lead and tail separate paragraphs. If an existing
> assertion in `FirstRunGreetingTests` or `CompanyStoreFirstRunGreetingTests` checks the joined
> single-line form (e.g. `"is ready. The best first move"`), update that assertion to match the
> new paragraph break — and say so in the commit message. Do not reintroduce single-line joining
> to satisfy it; the paragraph break is the point.

- [ ] **Step 5: Update `CompanyStore.seedFirstRunGreeting`**

```swift
    private func seedFirstRunGreeting(language: AppLanguage) {
        guard companyId != nil else { return }
        let next = RoadmapEngine.nextStep(company.tasks)
        let g = FirstRunGreetingBuilder.build(brief: company.brief, nextStep: next,
                                              tasks: company.tasks, language: language)
        chatMessages.append(CopilotMessage(role: .companion, text: g.text, firstRunAction: g.action))
    }
```

- [ ] **Step 6: Run the three affected suites**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/FirstRunGreetingTests -only-testing:codepetTests/CompanyStoreFirstRunGreetingTests -only-testing:codepetTests/FirstRunGreetingWiringTests 2>&1 | tail -30`

Expected: PASS. If the host dies rather than failing an assertion, read the count with
`xcrun xcresulttool get test-results summary --path <the .xcresult>` — landmine 3 and the
Firestore-lock note both produce that shape, and neither is a failure you caused.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet-firstrun
git add codepet/Models/FirstRunGreeting.swift codepet/Managers/CompanyStore.swift codepetTests/FirstRunGreetingTests.swift
git commit -F - <<'EOF'
feat(first-run): the greeting now describes the project and the board

Assembles lead + read + shape + move. build() gains a tasks: parameter --
nextStep names one task and the shape line counts them all, so the count
cannot be derived from what was already passed.

Paragraphs are compactMap'd and joined once rather than appended with
conditional "\n\n" prefixes: a dropped middle paragraph is exactly how that
approach leaves a hole, and a brief with no readable anchor is the common
case on first run.

Lead and tail copy are unchanged byte-for-byte; they are covered by existing
assertions and are not what this changes.
EOF
```

---

### Ticket 7: `TourScript` — the tour, composed locally

**Files:**
- Create: `codepet/Models/TourScript.swift`
- Test: `codepetTests/TourScriptTests.swift`

**Interfaces:**
- Produces: `TourScript.message(language: AppLanguage) -> String`, `TourScript.chip() -> NavAction`, `TourScript.offerLabel(lang: AppLanguage) -> String`

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/TourScriptTests.swift
import XCTest
@testable import codepet

/// "Show me around" must answer without a model call.
///
/// Chat is `.claudeOnly` (`BlockedOffer.Surface`) and `ChatTransportRouter.transport` blocks
/// on the grant, so a tour that asked the model would return the grant wall on a fresh
/// account — teaching a brand-new founder that the button is broken at the exact moment we
/// are trying to build confidence. So it is a script, like the greeting.
final class TourScriptTests: XCTestCase {

    func testTheTourNamesTheSurfacesAFounderCanReach() {
        let out = TourScript.message(language: .en)
        for surface in ["Roadmap", "Tasks", "Library"] {
            XCTAssertTrue(out.contains(surface), "the tour never mentions \(surface)")
        }
    }

    /// `AppView.from(navDestination:)` resolves five strings. A chip pointing anywhere else
    /// makes `activateNav` return early and renders a button that silently does nothing.
    func testTheChipPointsSomewhereTheRouterCanResolve() {
        let nav = TourScript.chip()
        XCTAssertNotNil(AppView.from(navDestination: nav.destination),
                        "the tour chip's destination is unroutable")
        XCTAssertEqual(nav.destination, "roadmap")
    }

    /// The tour hands off to `OverviewIntroSheet`, which lives on Roadmap and holds
    /// "How to read this map". Pointing elsewhere would duplicate shipped work.
    func testTheChipGoesToRoadmapSoTheExistingBriefingFires() {
        XCTAssertEqual(TourScript.chip().destination, "roadmap")
        XCTAssertNil(TourScript.chip().target, "roadmap takes no target")
    }

    /// `environment` is tooling, not part of understanding what Codepet does for you.
    func testTheTourDoesNotAdvertiseTheEnvironmentTab() {
        XCTAssertFalse(TourScript.message(language: .en).contains("Environment"))
    }

    func testBothLanguagesAreReal() {
        XCTAssertNotEqual(TourScript.message(language: .en), TourScript.message(language: .vi))
        XCTAssertFalse(TourScript.message(language: .vi).isEmpty)
        XCTAssertFalse(TourScript.offerLabel(lang: .vi).isEmpty)
    }

    /// `CopilotChatView.prose` splits on blank lines, so the tour must be paragraphs rather
    /// than one wall.
    func testTheTourIsParagraphs() {
        XCTAssertTrue(TourScript.message(language: .en).contains("\n\n"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/TourScriptTests 2>&1 | tail -25`

Expected: FAIL — `cannot find 'TourScript' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// codepet/Models/TourScript.swift
import Foundation

/// What "Show me around" says.
///
/// **A script, not a model call, for the same reason the greeting is one.** Chat is
/// `.claudeOnly` (`BlockedOffer.Surface`) and `ChatTransportRouter.transport` blocks on the
/// grant, so a tour that asked the model would answer a brand-new founder with the grant wall.
/// A button whose first press returns an error teaches her the app is broken, at the one moment
/// she has no other evidence.
///
/// **It ends by handing off to shipped work.** The chip goes to Roadmap, where
/// `OverviewIntroSheet` already auto-shows once per account with the phase briefing and "How to
/// read this map". Re-describing that here would be two copies of one explanation — and that
/// sheet currently never fires for a founder who stays in chat, which this closes as a side
/// effect.
///
/// Outside any `@MainActor ObservableObject` — landmine 3.
enum TourScript {

    /// The chip on the greeting that offers the tour.
    static func offerLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Dẫn mình đi một vòng" : "Show me around"
    }

    /// Only the destinations `AppView.from(navDestination:)` can resolve are named —
    /// "roadmap", "tasks", "library", "company"/"department". `environment` is deliberately
    /// left out: it is tooling, not part of understanding what Codepet does for you.
    static func message(language: AppLanguage) -> String {
        language == .vi
            ? """
              Đây là bố cục của chỗ này. Chỗ mình đang nói chuyện là Chat — hỏi mình bất cứ điều \
              gì, hoặc bảo mình chạy việc gì đó.

              Lộ trình là kế hoạch của bạn, theo từng giai đoạn. Nhiệm vụ là cùng phần việc đó \
              nhưng ở dạng danh sách để chạy. Thư viện giữ mọi sản phẩm sau khi bạn duyệt. Và \
              Các bộ phận là đội của bạn — mỗi bộ phận tự viết phần việc của mình.

              Bắt đầu từ lộ trình thì dễ nhất — nó là bản đồ cho mọi thứ còn lại.
              """
            : """
              Here's the shape of the place. Chat is where we're talking now — ask me anything, \
              or tell me to run something.

              Roadmap is your plan, phase by phase. Tasks is the same work as a list you can run. \
              Library keeps every deliverable once you approve it. And Departments is your team — \
              each one writes its own work.

              Start with the roadmap; it's the map for everything else.
              """
    }

    /// Where the tour sends her. `nil` target: "roadmap" is not a department, and
    /// `activateNav` only reads `target` for `destination == "department"`.
    static func chip() -> NavAction { NavAction(destination: "roadmap", target: nil) }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/TourScriptTests 2>&1 | tail -25`

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet-firstrun
git add codepet/Models/TourScript.swift codepetTests/TourScriptTests.swift
git commit -F - <<'EOF'
feat(first-run): the tour is a script, not a model call

Chat is .claudeOnly and blocks on the grant, so a tour that asked the model
would answer a brand-new founder with the grant wall -- a button whose first
press errors teaches her the app is broken, at the moment she has no other
evidence.

It names only destinations AppView.from(navDestination:) can resolve; a chip
pointing anywhere else makes activateNav return early and renders a control
that silently does nothing. environment is left out as tooling.

The chip goes to Roadmap so OverviewIntroSheet's existing briefing fires --
that sheet holds "How to read this map" and currently never reaches a founder
who stays in chat.
EOF
```

---

### Ticket 8: The tour chip on the greeting

**Files:**
- Modify: `codepet/Models/CopilotMessage.swift` (two fields)
- Modify: `codepet/Models/FirstRunGreeting.swift` (carry the offer)
- Modify: `codepet/Managers/CompanyStore.swift` (`activateTour`, and set the flag when seeding)
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (render after the primary action)
- Test: `codepetTests/TourOfferWiringTests.swift`

**Interfaces:**
- Consumes: `TourScript` (Ticket 7), `FirstRunGreeting` (Ticket 6)
- Produces: `CopilotMessage.tourOffer: Bool`, `CopilotMessage.tourConsumed: Bool`, `CompanyStore.activateTour(messageId: UUID)`

**Two constraints from the spec, both verified in the code:**
1. **Its own consumed flag.** `actionConsumed` is already shared by `firstRunAction`,
   `runProposal`, `chainOffer` and `vcRun` (`CopilotChatView.swift:1542,1595,1642,1701`).
   Reusing it would make "Do it with me" retire the tour chip and the reverse.
2. **Order.** `inlineActions` is composed *inside* `textBubble` (`:2402`), and the
   `firstRunAction` branch (`:1561`) renders `textBubble` then `actionButton`. A naive
   `navChip`-based tour chip would therefore draw **above** the primary button. The primary
   action leads.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/TourOfferWiringTests.swift
import XCTest
@testable import codepet

/// The greeting's tour chip: offered, tappable once, and never entangled with the primary
/// "Do it with me" action.
@MainActor
final class TourOfferWiringTests: XCTestCase {

    // MARK: - The two flags stay independent

    /// `actionConsumed` is shared by firstRunAction, runProposal, chainOffer and vcRun.
    /// Reusing it here would make "Do it with me" retire the tour chip, and the reverse.
    func testConsumingThePrimaryActionLeavesTheTourOffered() {
        var m = CopilotMessage(role: .companion, text: "hi",
                               firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T"))
        m.tourOffer = true
        m.actionConsumed = true
        XCTAssertTrue(m.tourOffer)
        XCTAssertFalse(m.tourConsumed, "the tour was retired by an unrelated action")
    }

    func testConsumingTheTourLeavesThePrimaryActionAlone() {
        var m = CopilotMessage(role: .companion, text: "hi",
                               firstRunAction: FirstRunAction(taskId: "t1", taskTitle: "T"))
        m.tourOffer = true
        m.tourConsumed = true
        XCTAssertFalse(m.actionConsumed, "the primary action was retired by the tour")
        XCTAssertNotNil(m.firstRunAction)
    }

    /// A message with no tour offer must not accidentally render one.
    func testTourIsNotOfferedByDefault() {
        let m = CopilotMessage(role: .companion, text: "hi")
        XCTAssertFalse(m.tourOffer)
        XCTAssertFalse(m.tourConsumed)
    }

    // MARK: - The greeting carries it

    func testTheGreetingOffersTheTour() {
        let brief = CompanyBrief(stage: "Building", projectName: "Codepet",
                                 oneLiner: "A macOS AI coding companion")
        let tasks = [RoadmapTask(id: "t1", title: "Lock the pricing copy", phase: .foundation)]
        let g = FirstRunGreetingBuilder.build(brief: brief, nextStep: tasks[0],
                                              tasks: tasks, language: .en)
        XCTAssertTrue(g.offersTour)
    }

    // MARK: - Tapping it appends the script and retires the chip

    func testActivatingTheTourAppendsTheScriptAndRetiresTheChip() async {
        let s = CompanyStore.testStore(tasks: [RoadmapTask(id: "t1", title: "T",
                                                           phase: .foundation)])
        await s.greetIfNeeded(language: .en)
        guard let greeting = s.chatMessages.first else {
            return XCTFail("nothing was seeded")
        }
        XCTAssertTrue(greeting.tourOffer)

        s.activateTour(messageId: greeting.id)

        XCTAssertTrue(s.chatMessages[0].tourConsumed, "the chip was not retired")
        XCTAssertEqual(s.chatMessages.count, 2, "the tour message was not appended")
        XCTAssertTrue(s.chatMessages[1].text.contains("Roadmap"))
        XCTAssertEqual(s.chatMessages[1].navChip?.destination, "roadmap")
    }

    /// A second tap must not append the tour twice.
    func testASecondTapIsANoOp() async {
        let s = CompanyStore.testStore(tasks: [RoadmapTask(id: "t1", title: "T",
                                                           phase: .foundation)])
        await s.greetIfNeeded(language: .en)
        let id = s.chatMessages[0].id
        s.activateTour(messageId: id)
        s.activateTour(messageId: id)
        XCTAssertEqual(s.chatMessages.count, 2, "the tour was appended twice")
    }
}
```

> **`CompanyStore.testStore(tasks:)` does not exist.** `FirstRunGreetingWiringTests` already
> builds a store through injected closures — read its private `store(tasks:greetedAt:)` helper
> (around `:78-90`) and copy that construction into this suite rather than adding a new
> production-visible factory. If that helper is already `fileprivate` to its own suite,
> duplicate it here; a shared test factory across suites is a separate refactor.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/TourOfferWiringTests 2>&1 | tail -25`

Expected: FAIL — `value of type 'CopilotMessage' has no member 'tourOffer'`.

- [ ] **Step 3: Add the message fields**

In `codepet/Models/CopilotMessage.swift`, beside `firstRunAction` / `actionConsumed`:

```swift
    /// True when this message offers the first-run tour (the greeting only).
    ///
    /// **Its own pair of flags, not `actionConsumed`.** That Bool is already shared by
    /// `firstRunAction`, `runProposal`, `chainOffer` and `vcRun`, so reusing it would make
    /// "Do it with me" retire the tour chip and the reverse — two unrelated offers, one
    /// switch. A test pins both directions.
    var tourOffer: Bool = false
    /// True once the tour has been asked for — hides the chip.
    var tourConsumed: Bool = false
```

> These are `var`s with defaults declared outside the memberwise initialiser, matching
> `supersededByRoom` and `blockedOffer`, which the store also writes onto an already-appended
> message. Do **not** add them to `init` — every existing call site would need updating for no
> gain.

- [ ] **Step 4: Have the greeting carry the offer**

In `codepet/Models/FirstRunGreeting.swift`, add to `struct FirstRunGreeting`:

```swift
    /// Whether this greeting offers the tour. Always true today; carried as a field rather
    /// than assumed at the call site so the store does not have to know which greetings do.
    let offersTour: Bool
```

Update the three `FirstRunGreeting(...)` constructions in `build` to pass `offersTour: true`.

- [ ] **Step 5: Set the flag when seeding, and add `activateTour`**

In `CompanyStore.seedFirstRunGreeting`:

```swift
        var msg = CopilotMessage(role: .companion, text: g.text, firstRunAction: g.action)
        msg.tourOffer = g.offersTour
        chatMessages.append(msg)
```

Add beside `activateNav`:

```swift
    /// "Show me around" — appends the locally-composed tour and retires the chip.
    ///
    /// **Guarded on `tourConsumed`**, not merely hiding the button: a stray second tap (or a
    /// re-render racing the first) would otherwise append the tour twice. `activateSetup`
    /// carries the same guard for the same reason.
    ///
    /// No `await` and no transport: `TourScript` is a pure builder, so the tour answers a
    /// founder who has granted nothing. See its doc comment for why that matters.
    func activateTour(messageId: UUID) {
        guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
              chatMessages[i].tourOffer, !chatMessages[i].tourConsumed else { return }
        chatMessages[i].tourConsumed = true
        var tour = CopilotMessage(role: .companion, text: TourScript.message(language: language))
        tour.navChip = TourScript.chip()
        chatMessages.append(tour)
    }
```

> Check how `CompanyStore` reaches the current language elsewhere (`seedFirstRunGreeting` takes
> it as a parameter). If there is no stored `language`, give `activateTour` a
> `language: AppLanguage` parameter and pass it from the view, which has `@Environment(\.uiLanguage)`.

- [ ] **Step 6: Render the chip after the primary action**

In `CopilotChatView.swift`, in the `firstRunAction` branch (around `:1561`), add the tour chip
**below** `actionButton` so the primary action leads:

```swift
        } else if let action = message.firstRunAction, !message.actionConsumed {
            VStack(alignment: .leading, spacing: 8) {
                textBubble
                HStack(spacing: 8) {
                    actionButton(action)
                    if message.tourOffer, !message.tourConsumed { tourButton }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
```

Add the button beside `navChipButton`:

```swift
    /// Quiet, secondary — the tour is offered, never pushed. Styled off `navChipButton`'s
    /// capsule but in the muted treatment, so it cannot compete with the primary action.
    private var tourButton: some View {
        Button { companyStore.activateTour(messageId: message.id) } label: {
            Text(TourScript.offerLabel(lang: lang))
                .font(.pixelSystem(size: 11, weight: .semibold))
                .foregroundColor(CodepetTheme.bodyText)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.hairline)).hoverAffordance(Capsule())
        }
        .buttonStyle(.plain)
    }
```

**Also handle the greeting with no task.** When `nextStep` is nil there is no `firstRunAction`,
so the branch above never runs and the chip would not render. Add the offer to the plain-text
path by extending `inlineActions` (inside `textBubble`), which every branch reaches:

```swift
        if message.tourOffer, !message.tourConsumed, message.firstRunAction == nil {
            tourButton
        }
```

> The `firstRunAction == nil` condition is what keeps the chip from rendering twice — once from
> `inlineActions` inside `textBubble` and again from the `HStack` above it. Verify by eye in
> Step 8; a duplicated chip is the specific defect this guards.

- [ ] **Step 7: Run the tests**

Run: `cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/TourOfferWiringTests -only-testing:codepetTests/FirstRunGreetingTests -only-testing:codepetTests/FirstRunGreetingWiringTests 2>&1 | tail -30`

Expected: PASS.

- [ ] **Step 8: See it on screen**

The greeting only fires for an ungreeted account, so use prototype mode, which re-greets every
launch (`saveGreeted` is silent there):

```bash
cd ~/Developer/codepet-firstrun && xcodebuild -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 build 2>&1 | tail -5
# then launch the built app with:
#   open <built path>/codepet.app --args -CODEPET_MOCK_CHAT YES
```

Confirm, by eye: the greeting reads as four paragraphs; **"Do it with me" sits left of "Show me
around"**; exactly one tour chip renders; tapping it appends the tour with a "Go to Roadmap"
chip and the offer chip disappears; tapping "Go to Roadmap" opens Roadmap and the intro sheet
appears.

Per the build-verify rule: if it "looks the same", it is a stale build — confirm the binary you
launched is the one you just built.

- [ ] **Step 9: Commit**

```bash
cd ~/Developer/codepet-firstrun
git add codepet/Models/CopilotMessage.swift codepet/Models/FirstRunGreeting.swift codepet/Managers/CompanyStore.swift codepet/Views/Copilot/CopilotChatView.swift codepetTests/TourOfferWiringTests.swift
git commit -F - <<'EOF'
feat(first-run): offer the tour on the greeting, never push it

The chip carries its own tourOffer/tourConsumed pair rather than reusing
actionConsumed, which is already shared by firstRunAction, runProposal,
chainOffer and vcRun -- reusing it would make "Do it with me" retire the tour
and the reverse. Tests pin both directions.

Drawn to the RIGHT of the primary action. inlineActions is composed inside
textBubble and the firstRunAction branch renders textBubble then
actionButton, so a navChip-based chip would have drawn above the primary
button. The no-task greeting has no firstRunAction and gets the chip through
inlineActions instead, guarded on firstRunAction == nil so it cannot render
twice.

activateTour is guarded on tourConsumed rather than only hiding the button, so
a stray second tap cannot append the tour twice -- the guard activateSetup
already carries.
EOF
```

---

## Final verification

- [ ] **Run every suite this plan touched or renamed**

```bash
cd ~/Developer/codepet-firstrun && xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/GrantCopyTests \
  -only-testing:codepetTests/GrantRevokeConfirmTests \
  -only-testing:codepetTests/OnboardingProviderCopyTests \
  -only-testing:codepetTests/BriefReadTests \
  -only-testing:codepetTests/RoadmapShapeLineTests \
  -only-testing:codepetTests/TourScriptTests \
  -only-testing:codepetTests/TourOfferWiringTests \
  -only-testing:codepetTests/FirstRunGreetingTests \
  -only-testing:codepetTests/FirstRunGreetingWiringTests \
  -only-testing:codepetTests/CompanyStoreFirstRunGreetingTests \
  -only-testing:codepetTests/ProviderConsentTests \
  -only-testing:codepetTests/ProviderGrantPanelTests 2>&1 | tail -30
```

Read the count from `xcrun xcresulttool get test-results summary --path <.xcresult>` rather than
trusting a tail that may have been truncated by a host crash.

- [ ] **Confirm the retired copy is gone repo-wide**

```bash
cd ~/Developer/codepet-firstrun && grep -rn "old route\|đường cũ\|choose whether\|chọn xem" codepet codepetTests
```

Expected: no output.

- [ ] **Confirm nothing reads the unpopulated brief fields**

```bash
cd ~/Developer/codepet-firstrun && grep -rn "brief.goal\|brief.traction\|brief.problem\|brief.runway\|brief.constraints" codepet/Models/BriefRead.swift codepet/Models/FirstRunGreeting.swift codepet/Models/TourScript.swift
```

Expected: no output.

- [ ] **Open a PR** — a pushed branch runs no CI; only a PR does, even a draft.

```bash
cd ~/Developer/codepet-firstrun && git push -u origin spec/first-run-and-grant-copy
gh pr create --draft --title "First-run welcome that orients, and grant copy that is true" \
  --body-file docs/superpowers/specs/2026-09-18-first-run-welcome-and-grant-copy-design.md
```

---

## Self-review notes

**Spec coverage.** B1 → Ticket 1. B2 → Ticket 1. B3 → Ticket 2. B4 → Ticket 3. A1 → Tickets 4, 5, 6. A2 → Ticket 4 (+ Ticket 6's dropped-paragraph test). A3 → Ticket 7. A4 (ordering, own flag) → Ticket 8. A5 (gating unchanged) → no task, deliberately: `FirstRunGreetingGate` is not modified, and Ticket 6 Step 6 re-runs the suites that pin it.

**Deliberately not covered**, both listed out-of-scope in the spec: pointing `OverviewIntroSheet` at the composed read, and repairing or deleting the dead `enrichBrief` path.

**Known uncertainties an implementer must resolve by reading, flagged inline rather than guessed:** `RoadmapTask`'s initialiser and `RoadmapPhase`'s case names (Ticket 5 Step 1); whether `CompanyStore` has a stored `language` (Ticket 8 Step 5); how `ClaudeCodePanel` reaches `companyId` where the alert attaches (Ticket 2 Step 5); and whether an existing assertion depends on the lead and tail being one line (Ticket 6 Step 4).
