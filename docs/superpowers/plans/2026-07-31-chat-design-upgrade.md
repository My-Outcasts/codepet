# Chat-Section Design Upgrade — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the docked copilot PR #39's chat polish — teammate reply cards (avatar + name + rounded surface), readable Inter text, nicer empty-state + thinking indicator — sized for the 380pt dock, with no behavior change and the coding-agent integration intact.

**Architecture:** Port two self-contained components from `feat/chat-redesign` (`MessageCard`, `CompanionOrb`), then surgically upgrade this branch's `CopilotChatView` — the `textBubble`, `greeting`, and `typingRow` — to use them. Do NOT wholesale-replace `CopilotChatView` (it carries the coding-agent card, Engineering toggle, thread header, dock fit).

**Tech Stack:** Swift 5, SwiftUI, macOS, XCTest, Xcode `codepet.xcodeproj` (scheme `codepet`).

## Global Constraints

- **Branch:** `feat/shell-web-parity` (PR #42; already has the shell + coding agent). Commit after each task.
- **Visual only, dock-sized:** body text ~13.5pt Inter (NOT #39's 18pt — the dock is 380pt); avatars ~22pt; card padding modest. No new behavior; do not touch the send/stream path, threads, the Engineering toggle, "Let's build", or the coding agent's logic.
- **Build (TEAM-signed):** `xcodebuild build -project codepet.xcodeproj -scheme codepet -configuration Debug -destination 'platform=macOS' CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development" -allowProvisioningUpdates`
- **Tests:** same flags + `test`. Close any running app first (`pkill -x codepet 2>/dev/null`) — a live app holds the Firestore lock (0-executed + no `Failing tests:` line = flake; re-run app-closed). The full suite is currently 502/0; it must stay green (this is view-layer).
- New `.swift` files auto-join the target (synchronized groups). Bilingual EN/VI on all copy.
- This branch's `CopilotMessage` has **no** per-message `companionId`/`deptName` fields — the teammate card shows the account companion's name/orb only (no per-reply dept attribution; don't invent it).
- Commit only each task's listed paths; never `git add -A` (stray untracked `HANDOFF-chat-redesign.md`).

---

### Task 1: Port `MessageCard` + `CompanionOrb` (resolve deps)

**Files:**
- Create: `codepet/Views/Copilot/MessageCard.swift`, `codepet/Views/Copilot/CompanionOrb.swift` (via `git show`)

**Interfaces:**
- Produces: `struct MessageCard<Content: View>: View { let hue: Color; @ViewBuilder var content }`; `struct CompanionOrb: View { var size; var glow; var isWorking; var companionId }`; `struct CompanionAvatar: View { var companionId; var size; var isWorking }`.

- [ ] **Step 1: Port both files**

```bash
git show feat/chat-redesign:codepet/Views/Copilot/MessageCard.swift > codepet/Views/Copilot/MessageCard.swift
git show feat/chat-redesign:codepet/Views/Copilot/CompanionOrb.swift > codepet/Views/Copilot/CompanionOrb.swift
```

- [ ] **Step 2: Resolve the three possibly-#39-only symbols `CompanionOrb` references**

Run these greps; for each, if it exists on this branch, do nothing — if NOT, apply the adaptation:
- `grep -rn "struct CharacterImage\|CharacterImage(" codepet | grep -v CompanionOrb.swift` — `CompanionAvatar`'s `if let id` branch calls `CharacterImage(id, size:)`. If `CharacterImage` doesn't exist on this branch, change that branch to also render `CompanionOrb(size: size, companionId: id)` (drop the sprite path — this branch never passes a per-message `companionId` anyway, so the sprite path is dead here).
- `grep -rn "chatOrbCore" codepet/Views/CodepetTheme.swift codepet/**/CodepetTheme*.swift 2>/dev/null` (or `grep -rn "chatOrbCore" codepet`) — if `CodepetTheme.chatOrbCore` is absent, replace it in `CompanionOrb.swift` with a near-black core color already on this branch (e.g. `Color.black` or an existing dark token — pick whatever `CodepetTheme` provides; the orb just needs a dark center).
- `grep -rn "secondColor" codepet/Models/Character.swift` — `hue2` uses `character?.secondColor`. If `PetCharacter` has no `secondColor` on this branch, change `hue2` to `character?.color ?? CodepetTheme.accentPink` (fall back to the single hue / a static accent).

Apply only the adaptations whose grep came back empty; note each in the report.

- [ ] **Step 3: Build**

Run the TEAM-signed build → `** BUILD SUCCEEDED **`. (Both components are unused so far; this confirms they compile on this branch.) Grep-confirm no other missing symbol.

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/MessageCard.swift codepet/Views/Copilot/CompanionOrb.swift
git commit -m "feat(chat): port MessageCard + CompanionOrb from the redesign"
```

---

### Task 2: Teammate-card replies + restyled user bubble (`textBubble`)

Upgrade the `else`-branch renderer in `CopilotBubble`. The current `textBubble` is a plain bubble for both sides.

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (the `CopilotBubble.textBubble` computed property + a small `companionAccent` helper)

**Interfaces:**
- Consumes: `MessageCard`, `CompanionOrb` (Task 1); existing `CopilotBubble.companionName`, `isMe`, `message.text`, `companyStore`.

- [ ] **Step 1: Add a companion-accent helper to `CopilotBubble`**

Next to `CopilotBubble.companionName` (~line 375), add:

```swift
    private var companionAccent: Color {
        PetCharacter.all[companyStore.company.companionId]?.color ?? CodepetTheme.accentPurple
    }
```

- [ ] **Step 2: Replace `textBubble`**

Replace the entire current `textBubble` computed property:

```swift
    private var textBubble: some View {
        HStack {
            if isMe { Spacer(minLength: 24) }
            Text(message.text)
                .font(.pixelSystem(size: 12))
                .foregroundColor(isMe ? .white : CodepetTheme.primaryText)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isMe ? CodepetTheme.accentPurple : CodepetTheme.surface))
                .fixedSize(horizontal: false, vertical: true)
            if !isMe { Spacer(minLength: 24) }
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
    }
```

with:

```swift
    @ViewBuilder private var textBubble: some View {
        if isMe {
            HStack {
                Spacer(minLength: 24)
                Text(message.text)
                    .font(CodepetTheme.inter(13.5))
                    .lineSpacing(3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(CodepetTheme.accentPurple))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            // Teammate card: companion orb + name header + reply in a tinted surface.
            HStack(alignment: .top, spacing: 8) {
                CompanionOrb(size: 22, glow: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(companionName)
                        .font(CodepetTheme.inter(12.5, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    MessageCard(hue: companionAccent) {
                        Text(message.text)
                            .font(CodepetTheme.inter(13.5))
                            .lineSpacing(3)
                            .foregroundColor(CodepetTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
```

- [ ] **Step 3: Build + offline visual sanity**

Build TEAM-signed → `** BUILD SUCCEEDED **`. Optionally `open <DerivedData>/…/codepet.app --args -CODEPET_MOCK_CHAT YES`, send a message, confirm the companion reply shows as an orb + name + card and the body text reads cleanly at dock width; then quit (`pkill -x codepet`). No unit test (view).

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): teammate-card companion replies + restyled user bubble"
```

---

### Task 3: Upgraded empty state + thinking row

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (`greeting`, `typingRow`)

**Interfaces:**
- Consumes: `CompanionOrb` (Task 1); existing `founderName`, `companyName`, `companionName`, `quickStarts`, `sendChat`, `isCompanionTyping`.

- [ ] **Step 1: Upgrade `greeting`**

Replace the current `greeting` body so it leads with the companion orb and uses cleaner spacing (keep the existing copy + `quickStarts` + `sendChat` wiring):

```swift
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                CompanionOrb(size: 26, glow: false)
                Text(companionName)
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
            }
            Text(lang == .vi
                 ? "Chào \(founderName). Hỏi mình bất cứ điều gì về \(companyName) — nên tập trung vào đâu, điều gì đang cản trở, hay xây gì tiếp theo."
                 : "Welcome, \(founderName). Ask me anything about \(companyName) — where to focus, what's blocking you, or what to build next.")
                .font(CodepetTheme.inter(13.5)).lineSpacing(3).foregroundColor(CodepetTheme.bodyText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(quickStarts, id: \.self) { chip in
                    Button { Task { await companyStore.sendChat(chip, language: lang) } } label: {
                        Text(chip).font(CodepetTheme.inter(12.5)).foregroundColor(CodepetTheme.accentPurple)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.1)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
```

- [ ] **Step 2: Upgrade `typingRow`**

Replace the plain `typingRow` with an orb + "thinking" beat:

```swift
    private var typingRow: some View {
        HStack(spacing: 8) {
            CompanionOrb(size: 20, glow: false, isWorking: true)
            Text(lang == .vi ? "\(companionName) đang trả lời…" : "\(companionName) is thinking…")
                .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            Spacer(minLength: 8)
        }
    }
```

- [ ] **Step 3: Build + offline visual sanity**

Build TEAM-signed → `** BUILD SUCCEEDED **`. Optional mock launch: new chat shows the orb-led greeting; while a reply streams, the thinking row shows the working orb. Quit after. No unit test.

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -m "feat(chat): orb-led empty state + thinking row"
```

---

### Task 4: Full-suite verification + founder visual pass

**Files:** none (verification; only commit if a real fix was needed).

- [ ] **Step 1: Full suite (app closed)**

`pkill -x codepet 2>/dev/null`; run the full `xcodebuild test`. Confirm the existing suite (currently 502) still passes 0 failures with a non-zero count (this is view-layer; no test should regress). Report the count.

- [ ] **Step 2: Launch + confirm no crash**

Build TEAM-signed; `open <DerivedData>/…/codepet.app`; confirm process alive + no new `~/Library/Logs/DiagnosticReports/codepet-*.ips` today; then `pkill -x codepet`.

- [ ] **Step 3: Founder visual pass (manual — hand to user)**

Report this checklist:
- Companion replies render as **orb + name + tinted card**; body text legible at dock width (not cramped, not oversized).
- User messages right-aligned, restyled, readable.
- New-chat **empty state** leads with the orb + starter chips; the **thinking row** shows the working orb while a reply streams.
- The coding-agent **run card** still renders correctly in the dock (unchanged).
- Nothing overflows the 380pt dock horizontally.

---

## Deferred / future
- Optional: re-skin `CodeRunCardView`'s header to `CompanionOrb` for avatar consistency (low priority; only if it reads inconsistently next to the teammate cards).
- Excluded by scope: fan-out agents row, composer dept chips, exec-log, #39's full-width layout.
