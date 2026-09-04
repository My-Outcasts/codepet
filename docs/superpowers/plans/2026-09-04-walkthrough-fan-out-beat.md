# Walkthrough Fan-Out Beat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The walkthrough shows three departments working at once, instead of demonstrating one of eight.

**Architecture:** One `Intent` case, one handler line in `MockFlowPlayer`, one beat tuple. `fanOutNextMoves` already exists and is already tested — this only gives the script a way to call it. The most valuable part of this plan is Task 2, an exhaustiveness guard covering the twelve intents that already exist.

**Tech Stack:** Swift 5, SwiftUI, XCTest, Xcode 26.2. `#if DEBUG` only — the whole demo layer is debug-gated.

**Spec:** `docs/superpowers/specs/2026-09-04-walkthrough-fan-out-beat-design.md`

## Global Constraints

- **Do NOT raise `maxFanOut`.** It is `3` at `CompanyStore.swift:171` and it is a production cost guard — three parallel model runs unattended is already the most expensive thing this product does. A prototype-only override would put a second code path inside a cost guard, which is the worst place to have one. Three departments show the shape; eight show the same shape more slowly.
- **The beat goes AFTER the existing run-and-approve pair**, not before. Breadth after depth: three parallel agents mean nothing to a founder who has not yet watched one produce something real.
- **The caption must mention approval.** A fan-out leaves three unapproved drafts, and three things appearing at once is exactly when to restate that none are committed.
- **Do NOT approve the fan-out's drafts in the script.** Chapter 5 already taught approval; three more approvals teach nothing and lengthen the tour. Leaving them unapproved is also truthful about what a fan-out gives you.
- **`beats` is built from `(chapter, seconds, Intent, caption)` tuples** via `MockFlowScript.build(_:)` (`:224`). Add a tuple; do not construct `Beat` directly.
- **The caption bar's total is `player.beats.count`** (`MockFlowCaptionBar.swift:119`), so `n/24` becomes `n/25` automatically. Do not hard-code a total anywhere.
- Everything in `codepet/Demo/` is inside `#if DEBUG`. Keep new code inside it.
- Commit with `git commit -F <file>`, never `-m`.
- **Never `git stash` bare** — shared stash stack, another session's entry is on it. Use a WIP commit.
- `xcodebuild test` exits 65 for unrelated reasons. **Read counts from `xcrun xcresulttool get test-results summary`, never the exit code.** A zero passed-count is a failure.
- **Before any `xcodebuild test`, stop the app:**

```bash
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}')
[ -n "$PID" ] && kill "$PID" && sleep 2
ps -eo pid,comm | awk '$2 ~ /codepet$/ {print "STILL RUNNING",$1}'
```

  Last line must print nothing. Never `pkill -f codepet`.

---

### Task 1: The `fanOut` intent, its handler, and the beat

**Files:**
- Modify: `codepet/Demo/MockFlowScript.swift` — the `Intent` enum, and the `beats` array
- Modify: `codepet/Demo/MockFlowPlayer.swift` — the intent switch (~line 145)
- Test: `codepetTests/MockFlowFanOutTests.swift` (create)

**Interfaces:**
- Consumes: `CompanyStore.fanOutNextMoves(language:)` (exists, `CompanyStore.swift:2732`), `CompanyStore.maxFanOut` (exists, `= 3`).
- Produces: `MockFlowScript.Intent.fanOut`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/MockFlowFanOutTests.swift`:

```swift
// codepetTests/MockFlowFanOutTests.swift
import XCTest
@testable import codepet

/// Guards on the walkthrough demonstrating more than one department.
///
/// Measured 4 Sep: the 24-chapter script contained exactly one `.runBeacon` and one
/// `.approveNewestDraft`, so ONE department produced work on camera — while the board carried
/// eight runnable tasks with eight real deliverables across eight kinds. Chapter 2 narrates
/// "eight departments, each speaking with its own pet" and the tour then demonstrated one.
///
/// The room (chapter 10) does convene four departments, but a room produces a decision, not an
/// artifact.
@MainActor
final class MockFlowFanOutTests: XCTestCase {

    private var beats: [MockFlowScript.Beat] { MockFlowScript.beats }

    func testThereIsExactlyOneFanOutBeat() {
        let n = beats.filter { $0.intent == .fanOut }.count
        XCTAssertEqual(n, 1, "one beat, not a repeated one")
    }

    /// Breadth AFTER depth. Three parallel agents mean nothing to a founder who has not yet
    /// watched one produce something real, so a reordering that puts the fan-out first should
    /// go red.
    func testTheFanOutFollowsTheRunAndApprovePair() throws {
        let fan = try XCTUnwrap(beats.firstIndex { $0.intent == .fanOut })
        let run = try XCTUnwrap(beats.firstIndex { $0.intent == .runBeacon })
        let approve = try XCTUnwrap(beats.firstIndex { $0.intent == .approveNewestDraft })
        XCTAssertLessThan(run, fan, "the founder must see one run finish first")
        XCTAssertLessThan(approve, fan, "and see approval file it first")
    }

    /// A fan-out leaves three UNAPPROVED drafts. Three things landing at once is exactly when
    /// the founder needs telling that none of them are committed.
    func testTheFanOutCaptionMentionsApproval() throws {
        let beat = try XCTUnwrap(beats.first { $0.intent == .fanOut })
        XCTAssertTrue(beat.caption.lowercased().contains("approve"), beat.caption)
    }

    /// The cap is a production cost guard, not a demo dial. If someone raises it to make the
    /// demo look better, this fails and says why.
    func testTheProductionFanOutCapIsUnchanged() {
        XCTAssertEqual(CompanyStore.maxFanOut, 3,
                       "maxFanOut is a cost guard — three parallel model runs unattended is "
                       + "already the most expensive unattended thing this product does")
    }

    /// The caption bar renders `index+1 / beats.count`, so adding a beat must not require
    /// editing a hard-coded total anywhere.
    func testNoHardCodedChapterTotalExists() {
        XCTAssertGreaterThan(beats.count, 24, "a beat was added")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/MockFlowFanOutTests test 2>&1 | tail -12
```

Expected: FAIL — `type 'MockFlowScript.Intent' has no member 'fanOut'`.

- [ ] **Step 3: Add the intent**

In `codepet/Demo/MockFlowScript.swift`, in the `Intent` enum, immediately after the `case approveNewestDraft` line and its doc comment, add:

```swift
        /// Fan out the next moves — `CompanyStore.fanOutNextMoves`, three departments working
        /// in parallel, each on the task its own roadmap says is next.
        ///
        /// **Why this beat exists.** The script ran ONE task and approved it, so one department
        /// of eight produced work on camera while chapter 2 narrated "eight departments, each
        /// speaking with its own pet". The board has eight runnable tasks with eight real
        /// deliverables; the tour demonstrated one of them.
        ///
        /// Capped at `CompanyStore.maxFanOut` (3), which is a production cost guard and is NOT
        /// raised for the demo's benefit. Three shows the shape of a team; eight shows the same
        /// shape more slowly. It also costs about what ONE run costs in wall-clock, because the
        /// three go in parallel — which is why this is one beat rather than three sequential
        /// run-and-approve pairs.
        case fanOut
```

- [ ] **Step 4: Add the handler**

In `codepet/Demo/MockFlowPlayer.swift`, immediately after the `case .runBeacon:` block (which ends with its `Task { await store.runTask(task, language: language) }` line), add:

```swift
        case .fanOut:
            store.view = .chat
            Task { await store.fanOutNextMoves(language: language) }
```

- [ ] **Step 5: Add the beat**

In the `beats` array in `MockFlowScript.swift`, immediately after the beat whose intent is `.approveNewestDraft` (chapter `"A real deliverable"`, the one captioned "Approving is what files it…"), insert:

```swift
        ("A whole team", 4.4, .fanOut,
         "Three departments at once, each on the task its own roadmap says is next. "
         + "Nothing is filed until you approve each one."),
```

The chapter name `"A whole team"` is new; the caption bar lists chapter names, so it will appear there. Keep it short — the bar truncates.

- [ ] **Step 6: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
rm -rf /tmp/fo1.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/MockFlowFanOutTests \
  -resultBundlePath /tmp/fo1.xcresult test > /tmp/fo1.log 2>&1
grep -E '^/Users.*error:' /tmp/fo1.log | head -5
xcrun xcresulttool get test-results summary --path /tmp/fo1.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 5`.

If `Beat` or `Intent` is not `Equatable` and `$0.intent == .fanOut` will not compile, compare with a `if case .fanOut = $0.intent` closure instead of adding a conformance — do not change the type's conformances to satisfy a test. Note the change in your report.

- [ ] **Step 7: Run the script suites**

`MockFlowScriptTests` and `MockFlowTests` assert on the script's shape and will notice a new beat.

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
for s in MockFlowFanOutTests MockFlowScriptTests MockFlowTests MockFlowCaptionBarLayoutTests \
         DemoScriptControllerTests CompanyStoreFanOutTests; do
  rm -rf /tmp/fo-$s.xcresult
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/fo-$s.xcresult test > /tmp/fo-$s.log 2>&1
  p=$(xcrun xcresulttool get test-results summary --path /tmp/fo-$s.xcresult 2>/dev/null | grep '"passedTests"' | head -1 | tr -dc 0-9)
  f=$(xcrun xcresulttool get test-results summary --path /tmp/fo-$s.xcresult 2>/dev/null | grep '"failedTests"' | head -1 | tr -dc 0-9)
  printf "%-32s pass=%-4s fail=%s\n" "$s" "${p:-0}" "${f:-0}"
done
```

A suite asserting a hard-coded beat count will fail here. That is a real expectation this change invalidates — update the number and say so in your report. Do NOT weaken an assertion into a range to make it pass.

- [ ] **Step 8: Commit**

```bash
cat > /tmp/c-fo1.txt <<'EOF'
feat(demo): the walkthrough shows three departments, not one

Measured before changing anything: the 24-chapter script contained exactly one
`.runBeacon` and one `.approveNewestDraft`, so ONE department produced work on
camera — while the Murror board carries eight runnable tasks with eight real,
hand-written deliverables across eight kinds. Chapter 2 narrates "eight
departments, each speaking with its own pet", and the tour then demonstrated
one of them. The room does bring four departments in, but a room produces a
decision, not an artifact.

`fanOutNextMoves` already existed, was already capped and guarded, and was
already covered by 9 tests. The only thing missing was a way for the script to
call it: `Intent` had twelve cases and none for a fan-out. So this is one enum
case, one handler line, one beat.

Placed AFTER the run-and-approve pair on purpose. Three parallel agents mean
nothing to a founder who has not yet watched one produce something real —
breadth after depth.

The caption says "Nothing is filed until you approve each one", because a
fan-out leaves three UNAPPROVED drafts and three things landing at once is
exactly when that needs restating.

`maxFanOut` stays at 3. It is a production cost guard, not a demo dial, and a
test now fails if someone raises it to make the tour look better. Three shows
the shape of a team; eight shows the same shape more slowly, and costs three
times as much on a founder's own quota.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Demo/MockFlowScript.swift codepet/Demo/MockFlowPlayer.swift \
        codepetTests/MockFlowFanOutTests.swift
git commit -F /tmp/c-fo1.txt
```

---

### Task 2: Every intent has a handler — the guard worth more than the feature

**Files:**
- Test: `codepetTests/MockFlowFanOutTests.swift` (append)
- Possibly modify: `codepet/Demo/MockFlowPlayer.swift`, if the guard finds a gap

**Interfaces:**
- Consumes: `MockFlowScript.Intent`, `MockFlowPlayer`.
- Produces: nothing.

**Why this task exists.** `Intent` now has thirteen cases and `MockFlowPlayer`'s switch handles them by hand. An intent with no handler is not a compile error if the switch has a `default:` — it is a beat that silently does nothing, and the tour plays on as though it worked. That is exactly how a chapter could narrate something never shown. This task covers the twelve pre-existing cases as much as the new one.

- [ ] **Step 1: Check whether the switch is already exhaustive**

```bash
cd ~/Developer/codepet-two-mode
grep -n "default:" codepet/Demo/MockFlowPlayer.swift
grep -c "case \." codepet/Demo/MockFlowScript.swift
grep -c "case \." codepet/Demo/MockFlowPlayer.swift
```

**If the switch has NO `default:`**, Swift's exhaustiveness checking is already the guard — a new case without a handler will not compile. In that case write the test below anyway as documentation of the invariant, note in your report that the compiler enforces it, and skip Step 3.

**If the switch HAS a `default:`**, the compiler is not helping, and Step 3 removes it.

- [ ] **Step 2: Write the test**

Append inside `MockFlowFanOutTests`:

```swift
    // MARK: - Task 2: every intent is actually handled

    /// An `Intent` case with no handler in `MockFlowPlayer` is not a compile error when the
    /// switch carries a `default:` — it is a beat that silently does nothing while the caption
    /// narrates it. Every beat in the script must therefore correspond to an intent the player
    /// acts on.
    ///
    /// This asserts the property the script can actually observe: every beat's intent appears
    /// in the player's switch. It covers the twelve cases that predate the fan-out.
    func testEveryBeatsIntentIsHandledByThePlayer() throws {
        let src = try String(
            contentsOfFile: "\(ProcessInfo.processInfo.environment["SRCROOT"] ?? ".")"
                + "/codepet/Demo/MockFlowPlayer.swift", encoding: .utf8)
        XCTAssertFalse(src.contains("default:"),
                       "MockFlowPlayer's intent switch must stay exhaustive — a `default:` turns "
                       + "an unhandled intent into a silent no-op beat")
        for beat in beats {
            let name = String(describing: beat.intent).split(separator: "(").first.map(String.init) ?? ""
            XCTAssertTrue(src.contains("case .\(name)"),
                          "beat \(beat.id) (\(beat.chapter)) has intent .\(name) with no handler")
        }
    }
```

`SRCROOT` may not be set in the test environment. If the file cannot be read, replace the path with a `#filePath`-relative one:
`URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("codepet/Demo/MockFlowPlayer.swift")`.
Resolve this before writing and report which you used — a test that silently reads nothing and passes is worse than no test.

- [ ] **Step 3: If the switch has a `default:`, remove it**

Replace `default: break` (or equivalent) with explicit cases for every unhandled intent. If an intent genuinely should do nothing, write `case .x: break` with a comment saying why — an explicit no-op is a decision; a `default:` is an accident waiting.

- [ ] **Step 4: Run**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
rm -rf /tmp/fo2.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/MockFlowFanOutTests \
  -resultBundlePath /tmp/fo2.xcresult test > /tmp/fo2.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/fo2.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 6`.

**Prove it can fail.** Temporarily rename the `.fanOut` handler case in `MockFlowPlayer` to `.fanOutX`, confirm the new test goes red, then revert. Record the result — this test reads source text, which is a fragile technique, and an unfalsifiable version of it is worthless.

- [ ] **Step 5: Commit**

```bash
cat > /tmp/c-fo2.txt <<'EOF'
test(demo): every walkthrough intent must have a handler

`Intent` has thirteen cases and `MockFlowPlayer` handles them by hand. A case
with no handler is not a compile error when the switch carries a `default:` —
it is a beat that silently does nothing while its caption narrates it, which
is precisely how a tour claims to show something it never shows.

Covers the twelve cases that predate the fan-out, not just the new one, and
asserts the switch stays exhaustive so the compiler keeps doing the work.

Verified falsifiable: renaming the handler case turns it red.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepetTests/MockFlowFanOutTests.swift codepet/Demo/MockFlowPlayer.swift
git commit -F /tmp/c-fo2.txt
```

---

### Task 3: Watch it, then document it

- [ ] **Step 1: Build signed and launch**

```bash
cd ~/Developer/codepet-two-mode
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build 2>&1 | grep -oE "BUILD (SUCCEEDED|FAILED)"
APP=~/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app
ls -l "$APP/Contents/MacOS/codepet" | awk '{print "binary:",$6,$7,$8}'
git log -1 --format="commit: %ad" --date=format:'%b %d %H:%M'
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 3
open "$APP" --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
sleep 14
ps -eo pid,comm | awk '$2 ~ /codepet$/ {print "running pid",$1}'
```

- [ ] **Step 2: Confirm on screen**

1. Dismiss the intro, press **Play** on the caption bar
2. The bar reads **n/25**, not n/24 — proving nothing hard-codes the total
3. After the approve beat, a chapter called **"A whole team"** plays and **three** agent rows appear at once, each attributed to a different pet
4. Three draft cards land, each carrying **"Not saved yet — approving files it in your Library."** if this is a fresh company — three unapproved drafts is what a fan-out leaves, and the caption said so
5. The tour continues into "Work only you can do" without stalling

Check 4 is the one worth watching for: the fan-out and the first-draft note landed within a day of each other and have never been seen together.

- [ ] **Step 3: Document it, and commit**

Add to `CLAUDE.md`, in the prototype-mode section:

```markdown
- **The walkthrough fans out three departments** after its run-and-approve pair
  (`MockFlowScript.Intent.fanOut` → `CompanyStore.fanOutNextMoves`). It ran ONE task until
  4 Sep, so one department of eight produced work on camera while chapter 2 narrated eight.
  **`maxFanOut` (3) is a production cost guard and is not a demo dial** — a test fails if it is
  raised. The caption states that nothing is filed until each is approved, because a fan-out
  leaves three unapproved drafts.
- `MockFlowPlayer`'s intent switch must stay exhaustive: with a `default:`, an unhandled intent
  is a silent no-op beat whose caption still narrates it.
```

```bash
cat > /tmp/c-fo3.txt <<'EOF'
docs: the fan-out beat, and the two things not to do to it

Do not raise `maxFanOut` to make the demo look better — it is a production
cost guard, and a test now says so. Do not put a `default:` in the player's
intent switch — an unhandled intent becomes a beat that does nothing while its
caption narrates it.

Also records the measurement that prompted the beat: one `.runBeacon` and one
`.approveNewestDraft` in a 24-chapter tour, against a board of eight runnable
tasks with eight real deliverables.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add CLAUDE.md
git commit -F /tmp/c-fo3.txt
```

---

## Self-Review

**Spec coverage.** The `fanOut` case, handler and beat → Task 1. Placement after run-and-approve → Task 1 Step 5, pinned by a test. Caption mentioning approval → Task 1, pinned. Refusing to raise `maxFanOut` → Task 1's constraint plus a test that fails if it changes. The exhaustiveness guard the spec called "worth more than this change" → Task 2. Chapter-total consistency → Task 1's test asserting `beats.count > 24` plus Task 3 Step 2 check 2 on screen.

**Three deliberate unknowns, each flagged with a resolution rather than guessed.** Whether `Intent` is `Equatable` (Task 1 Step 6 gives the fallback); whether the player's switch has a `default:` (Task 2 Step 1 branches on it and says what to do either way); whether `SRCROOT` is set in the test environment (Task 2 Step 2 gives the `#filePath` alternative and insists the choice be reported, because a source-reading test that silently reads nothing would pass while asserting nothing).

**One test technique called out as fragile, on purpose.** Task 2's test reads `MockFlowPlayer.swift` as text. That is not a technique to reach for casually, which is why Step 4 requires proving it falsifiable by renaming a handler and watching it go red. Without that step it would be exactly the kind of test this codebase has been bitten by.

**Type consistency.** `Intent.fanOut` is spelled identically in the enum, the handler, the beat and all tests. `CompanyStore.fanOutNextMoves(language:)` and `CompanyStore.maxFanOut` are used with their existing names and signatures; neither is modified.
