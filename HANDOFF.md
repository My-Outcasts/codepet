# HANDOFF — feat/chat-redesign (Task 1: chat)

_Last updated: Jul 28 2026, end of session. Tip `1447f62`._

## Status
- **Branch `feat/chat-redesign` (PR #39) — OPEN, HELD. Do NOT merge to `main` without the founder's explicit go.** GitHub reports CLEAN / MERGEABLE (main not diverged), 64 commits today.
- PR **#37** (chat-first shell) and **#40** (Firebase test-host flake fix) already **merged to main**.
- **Chat UI/UX workstream = 16/16 Done** on the W1 board (page `3aa3af4aaa9281b1bc09d051a59b0ca6`). "Done" = work-complete + founder-verified; still branch-held (Done-on-board ≠ merged).
- **AI is DOWN** — no Anthropic credits/key. Use the **mock** for any front-end display (below).

## What's built on this branch
Redesign (un-bubbled messages + thumbs, one card grammar, luminous orb, dept chips, live empty-state) · **streaming execute-log** · **dept→companion handoff** (specialists appear as pet sprites) · **thread header** (dropdown switcher + Share=copy transcript) · **dark mode** (Light/Dark toggle works via `NSApp.appearance`; `onAccent` text) · **responsive** column (760 + 24pt gutter, shrink-to-fit) · **chat persistence** (Firestore `companies/{uid}/threads/{id}`, survives restart) · **DEBUG mock harness**.

## Run it (mock, no key needed)
```
# build TEAM-SIGNED, signed build LAST (tests clobber signing), then verify:
xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=YL72VTKBR7 "CODE_SIGN_IDENTITY=Apple Development"
codesign -dv <app> 2>&1 | grep TeamIdentifier   # MUST be YL72VTKBR7 (not adhoc — else Firebase keychain breaks)
# launch with the offline mock ON:
open -n <app> --args -CODEPET_MOCK_CHAT YES
```
Mock is keyword-routed: any question → advisor reply; `run my first task` → execute-log → tailored draft (positioning / landing copy / waitlist / pricing / interview); `remember…` → Noted chip; `connect…` → enable card; `roadmap`/dept chip → nav/handoff. Seed the board via **Roadmap** first if "no task to run".

## Gotchas
- `xcodebuild test … CODE_SIGNING_ALLOWED=NO` rebuilds the app **ad-hoc** into the same DerivedData → breaks Firebase keychain on launch. Always: tests first, **signed build last**, verify TeamIdentifier, then launch.
- Canonical work checkout drifted to `~/Developer/codepet` (iCloud evicted ~/Documents & ~/Desktop repos; `~/codepet-chat` is behind origin). Prefer a fresh non-iCloud checkout of `feat/chat-redesign`.
- **Two parallel sessions** run — own branch, own worktree, serialized app testing (one launches at a time). See memory `codepet-parallel-session-protocol`.

## Next candidates (not started)
Resume-last-thread on launch · message-cap per thread · search Recent · clear-all-history. Add a W1 board row before building (the board is the source of truth).
