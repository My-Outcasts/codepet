# VC Room Streamlined Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a landed virtual-company room read as one decision with the room's work available, instead of a stack of competing bordered panels.

**Architecture:** Three surfaces stop being `MessageCard`s. The disagreement block and the three department cards keep every word they carry and lose only their border and tint, so the founder's actual complaint — competing panels — goes away without hiding anything the display contract requires. Departments additionally gain a per-row disclosure so the expanded list is three lines rather than three panels.

**Tech Stack:** Swift 5, SwiftUI, macOS 26.2, XCTest. No new dependencies, no `functions/` change, no API cost.

**Spec:** `docs/superpowers/specs/2026-08-24-vc-room-streamlined-design.md`. Read amendment **[A1]** before Task 1 — the spec originally merged the two summary cards and that was withdrawn after reading the code.

## Global Constraints

**The display contract binds this work and is not a style guide.** `docs/superpowers/specs/virtual-company-sse-contract.md` opens its display rules with: *"These are not style preferences. They are the reasons the feature exists (spec §4.3), and several are already enforced server-side."*

- **Rule 1 — never collapse the process into a spinner plus an answer.** The room's work stays reachable. Nothing in this plan may put the disagreement, or the department positions, behind a click that did not already exist.
- **Rule 2 — never summarise the positions into one "we agree" paragraph.** `runSynthesis` throws server-side on a brief that buries dissent. Every department keeps its own row and its own words.
- **Rule 3 — show `the_real_disagreement` verbatim.** No paraphrase, no softening, **no truncation and no line clamp.**
- **Rule 5 — end on the either/or.** `tradeoffFounderMustOwn` stays LAST inside `theCall`, and stays unclamped. A note in the file records the founder's ruling that clamping it "cuts before the 'or'", which is the "it's up to you" the rule forbids.
- **Rule 7 — confidence as dots, never a number.** `confidenceDots` stays everywhere it appears.
- **Rule 9 — no human avatars or personal names for agents.** Department names only.

**Other constraints:**

- Swift only. No file under `functions/` may be touched. This is presentation only — nothing about what the backend sends changes.
- **No colour token value may change.** This plan changes which container a view uses, never what a token is.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Render tests are `@MainActor`.
- **`ImageRenderer` renders NOTHING inside a `ScrollView`.** Render `VCRunCards` directly, never the transcript that hosts it.
- A nil render must `XCTFail` plus `throw` — never `throw XCTSkip`. A skip lets CI go green with the guard silently gone.
- **A guard with no measured RED is not a guard.** Every threshold comes from a measured RED/GREEN pair with both numbers in a comment beside it, and each guard must be **watched failing** before it ships. Three guards in recent work passed with the bug present: one compared against an ideal hex instead of a render, one asserted hex arithmetic instead of reading a token, one measured a property the change did not affect.
- **Compare rendered pixels against a rendered reference, never against a computed colour.** Dark near-blacks render 0.03–0.07 brighter per channel than their hex. A contrast "regression" was diagnosed from hex arithmetic in recent work and turned out not to exist.
- Count tests with `xcresulttool`, never by grepping the log.
- **Locate every anchor by `grep`, never by line number.**

**Per-suite test command:**

```bash
cd /Users/monatruong/Developer/codepet-vc-design
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/SUITE_NAME \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-vc \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

`-derivedDataPath build/dd-vc` is load-bearing: without it the unsigned test build overwrites the signed `codepet.app` in shared DerivedData and Firebase sign-in silently breaks for the next human launch. **Never run two `xcodebuild` invocations at once** — check `pgrep -fl xcodebuild` first. Two of my own agents collided on one DerivedData path recently; the constraint is not only about other sessions.

**Full suite before the PR:** `./scripts/ci-test.sh`. This worktree branches from `origin/main` at `58777fe`; take the current green count from `.superpowers/sdd/progress.md` rather than this line.

**A concurrent session shares this repository** (different worktree). `codepet.app` may be running and is **theirs — do not kill it.** Its Firestore lock can kill a test host; the symptom is tests failing to *finish*, not wrong numbers.

---

## File structure

| File | Change | Responsibility after |
|---|---|---|
| `codepet/Views/Copilot/VirtualCompanyCards.swift` | modify 3 functions | `landedDisagreement` and `departmentsSaid` render without cards; `theCall` carries one eyebrow |
| `codepetTests/VCRoomLayoutTests.swift` | **create** | renders `VCRunCards` offscreen and asserts the tinted card fills are gone |

`VirtualCompanyCards.swift` is 1018 lines and already large. It is not split here: every change is inside three existing functions, and carving up a file whose parts are this interdependent is its own piece of work rather than a side effect of a layout change.

---

### Task 1: The disagreement block stops being a card

**Files:**
- Modify: `codepet/Views/Copilot/VirtualCompanyCards.swift` (`landedDisagreement`)
- Create: `codepetTests/VCRoomLayoutTests.swift`

**Interfaces:**
- Consumes: `MessageCard(hue:)` from `codepet/Views/Copilot/MessageCard.swift` — `surface` fill, then `hue.opacity(0.12)` overlay, then `hue.opacity(0.9)` 1px stroke.
- Produces: `VCRoomLayoutTests.renderRoom(_ state:scheme:)` and `VCRoomLayoutTests.cardFill(hue:scheme:)`, both reused by Task 3.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/VCRoomLayoutTests.swift`. The test asserts the room contains **no pixels matching an orange tinted card fill** — measured from a rendered reference, not computed.

```swift
// codepetTests/VCRoomLayoutTests.swift
import SwiftUI
import XCTest
@testable import codepet

/// The founder's complaint about a landed room was competing panels: six bordered
/// regions of equal weight, each with its own tint. These tests assert the panels that
/// should no longer be cards are not cards — by rendering the room and looking for the
/// tinted fill a `MessageCard` produces.
///
/// Compared against a RENDERED reference, never a computed blend. `MessageCard` fills
/// `surface` then overlays `hue.opacity(0.12)`, and the render pipeline shifts dark
/// near-blacks 0.03–0.07 brighter per channel — a recent "regression" was diagnosed
/// from exactly that arithmetic and turned out not to exist.
///
/// `ImageRenderer` draws NOTHING inside a `ScrollView`, so `VCRunCards` is rendered
/// directly rather than through the transcript that hosts it.
final class VCRoomLayoutTests: XCTestCase {

    private enum RenderFailure: Error { case producedNothing }

    /// A landed room with three departments that disagree — the shape in the founder's
    /// screenshots. Built through `apply` like `VirtualCompanyInterviewTests.finishedRun`.
    private func landedRoom() -> VirtualCompanyRunState {
        var s = VirtualCompanyRunState()
        let routing: [String: Any] = ["decision": "multi_agent",
                                      "agents": ["finance", "marketing", "engineering"],
                                      "real_question": "Should we ship the paywall before launch?",
                                      "request_type": "DECISION"]
        s.apply(.routing(try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: routing))))
        s.apply(.brief(VCBrief(
            recommendation: "Put the price on the page at launch and switch billing on two weeks later.",
            confidence: 3, confidenceReason: "c",
            theRealDisagreement: "Whether a price is a promise you must be able to keep, or a positioning statement you are allowed to revise.",
            tradeoffFounderMustOwn: "Either you launch with a number you may have to change, or you launch without one and give up the only day the product gets free attention.",
            killCriteria: ["k"],
            nextAction: VCNextAction(action: "a", owner: "Founder"),
            whatWeDontKnow: "u", unresolved: true)))
        s.apply(.done(runId: "r1", unresolved: true, skipped: nil))
        return s
    }

    @MainActor
    private func render<V: View>(_ view: V, _ name: String) throws -> (rep: NSBitmapImageRep, url: URL) {
        let dir = ProcessInfo.processInfo.environment["CODEPET_RENDER_DIR"] ?? NSTemporaryDirectory()
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("ImageRenderer produced nothing for \(name)")
            throw RenderFailure.producedNothing
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("[render] \(url.path)")
        return (rep, url)
    }

    /// The room, rendered at a width close to the chat column.
    @MainActor
    func renderRoom(_ state: VirtualCompanyRunState, scheme: ColorScheme,
                    name: String) throws -> (rep: NSBitmapImageRep, url: URL) {
        let room = VCRunCards(state: state, lockedIn: false, onLockIn: {})
            .frame(width: 620, alignment: .topLeading)
            .background(CodepetTheme.pageBackground)
            .environment(\.colorScheme, scheme)
        return try render(room, name)
    }

    /// The interior fill a `MessageCard` of this hue actually produces, measured.
    @MainActor
    func cardFill(hue: Color, scheme: ColorScheme) throws -> NSColor {
        let swatch = MessageCard(hue: hue) {
            Rectangle().fill(Color.clear).frame(width: 120, height: 60)
        }
        .frame(width: 160)
        .environment(\.colorScheme, scheme)
        let (rep, _) = try render(swatch, "cardfill-swatch")
        guard let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?
            .usingColorSpace(.sRGB) else {
            XCTFail("card fill swatch produced no centre pixel")
            throw RenderFailure.producedNothing
        }
        return c
    }

    private func count(_ rep: NSBitmapImageRep, matching target: NSColor,
                       tolerance: CGFloat) -> Int {
        var n = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let d = abs(c.redComponent - target.redComponent)
                    + abs(c.greenComponent - target.greenComponent)
                    + abs(c.blueComponent - target.blueComponent)
                if d < tolerance { n += 1 }
            }
        }
        return n
    }

    /// The disagreement block must not be a tinted card.
    ///
    /// It keeps every word — `the_real_disagreement` verbatim per rule 3, the conflict
    /// pairs, the aligned line — and loses only its border and fill, so it reads as a
    /// continuation of the call rather than a second panel competing with it.
    @MainActor
    func testTheDisagreementBlockIsNotACard() throws {
        let (rep, url) = try renderRoom(landedRoom(), scheme: .dark, name: "room-dark")
        let orange = try cardFill(hue: CodepetTheme.accentOrange, scheme: .dark)
        let n = count(rep, matching: orange, tolerance: 0.02)
        print("[measure] orange card-fill pixels = \(n)")
        XCTAssertLessThan(n, 40,
                          "the disagreement block still renders as an orange tinted card "
                          + "(\(n) matching pixels). See \(url.path)")
    }
}
```

- [ ] **Step 2: Run it and confirm it fails, and record the count**

```bash
cd /Users/monatruong/Developer/codepet-vc-design
pgrep -fl xcodebuild | head -1
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/VCRoomLayoutTests/testTheDisagreementBlockIsNotACard \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-vc \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

Expected: **FAIL**, with a large `[measure] orange card-fill pixels` count. Record it — that is this task's RED.

Run it **twice and require identical counts.** A differing count means build contention, not signal.

The `40` threshold is a placeholder and **you must replace it in Step 5** with a value derived from the measured RED and GREEN. If RED comes back small (under ~200) the sampling stride or the tolerance is wrong, not the threshold — **open the printed PNG and check the disagreement block is actually in frame** before touching any number. A `.frame(width:)` with no height renders the full intrinsic height, but if the room is taller than the renderer produces, the block may be cropped out entirely and the test would then be measuring nothing.

- [ ] **Step 3: Make the disagreement block a plain block**

Find it with `grep -n "private func landedDisagreement" codepet/Views/Copilot/VirtualCompanyCards.swift`.

Replace the `MessageCard(hue:)` wrapper with a plain `VStack`, keeping every child unchanged. The hue moves from the container to the text that needs it:

```swift
    private func landedDisagreement(_ brief: VCBrief) -> some View {
        let real = brief.theRealDisagreement.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs = state.conflicts.filter { $0.kind != "ALIGNED" }
        let agreed = state.conflicts.filter { $0.kind == "ALIGNED" }
        // NOT a MessageCard any more. The founder's complaint about a landed room was
        // competing panels, and this was the second one — same border weight, same tint
        // strength, directly under the card it belongs to. It keeps every word it had:
        // the pairs, `the_real_disagreement` VERBATIM (rule 3), and the aligned line.
        //
        // The hue moved from the container to the pairs text, because it was carrying
        // information the border cannot carry once the border is gone: orange for a real
        // disagreement, teal for WHERE THEY AGREE. Losing that flip was the reason this
        // block is not merged into THE CALL — see the spec's [A1].
        let hue = pairs.isEmpty ? CodepetTheme.accentTeal : CodepetTheme.accentOrange
        return VStack(alignment: .leading, spacing: 8) {
            label(pairs.isEmpty ? (lang == .vi ? "HỌ ĐỒNG Ý" : "WHERE THEY AGREE")
                                : (lang == .vi ? "BẤT ĐỒNG THẬT SỰ" : "THE REAL DISAGREEMENT"))
            if !pairs.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, c in
                        Text("\(displayName(agentId: c.a)) ↔ \(displayName(agentId: c.b))"
                             + " · \(kindLabel(c.kind))")
                            .font(CodepetTheme.inter(12.5, weight: .semibold))
                            .foregroundColor(hue)
                    }
                }
            }
            if !real.isEmpty {
                Text(real).font(CodepetTheme.inter(14)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !agreed.isEmpty {
                Text(agreedLine(agreed))
                    .font(CodepetTheme.inter(12.5))
                    .foregroundColor(hue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
    }
```

Note what did **not** change: the label still flips, `real` is still rendered in full with `fixedSize` and no clamp (rule 3), and the aligned line still appears. The `.padding(.horizontal, 12)` keeps its text on the same vertical line as the card above, which `MessageCard`'s own `padding(12)` used to provide.

- [ ] **Step 4: Run it and record the GREEN count**

Same command as Step 2. Expected: **PASS**, with a much smaller `[measure]` count. Run twice, identical values required. Record it.

- [ ] **Step 5: Set the threshold from the measured pair**

Replace `40` with a value between the measured GREEN and RED, and write **both numbers** into the assertion's comment:

```swift
        // Measured: RED <n> (the block still a card) / GREEN <n> (a plain block).
        // Threshold sits between them with headroom on both sides.
        XCTAssertLessThan(n, <chosen>,
```

**If the RED/GREEN separation is under about 3x, stop and report it** rather than shipping a squeezed guard. A residual GREEN count above zero is expected and fine — the orange accent still appears in text, and text antialiasing produces pixels near the fill colour.

- [ ] **Step 6: Prove the guard can fail**

Temporarily restore `MessageCard(hue: hue) {` around the block's `VStack`, run, confirm FAIL, then restore the plain version and prove it with `git diff --stat codepet/Views/Copilot/VirtualCompanyCards.swift` showing only your intended change. Report both counts.

A guard nobody has watched fail is not yet known to work.

- [ ] **Step 7: Commit**

```bash
git add codepet/Views/Copilot/VirtualCompanyCards.swift codepetTests/VCRoomLayoutTests.swift
git status --porcelain   # confirm ONLY those two are staged
git commit -m "$(cat <<'EOF'
feat(vc): the disagreement stops competing with the call

A landed room showed two bordered, tinted panels of equal weight, the second
directly beneath the first. The founder's complaint was competing panels, and
this was the competitor.

It keeps every word — the conflict pairs, `the_real_disagreement` verbatim per
rule 3, the aligned line — and loses only its border and fill.

The hue moved from the container to the pairs text, because it was carrying
information: orange for a real disagreement, teal for WHERE THEY AGREE. That
flip is also why this block is NOT merged into THE CALL, which an earlier draft
of the spec proposed — a purple card cannot express it, and merging would have
put two long unclamped paragraphs in one card, which is a bigger card rather
than a tidier one.

Guard watched failing before shipping.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git diff --cached --name-only   # must be empty
```

---

### Task 2: One eyebrow in THE CALL, and an action row that stops inverting itself

**Files:**
- Modify: `codepet/Views/Copilot/VirtualCompanyCards.swift` (`theCall`)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: nothing later tasks depend on.

**This task has no automated assertion, and that is a real gap rather than an oversight.** It removes one ALL-CAPS label and changes a button's shape. Neither is pixel-assertable without a text-extraction facility this codebase does not have, and a small-text pixel count would be dominated by the body copy around it. Verification is the rendered PNG plus the founder's eye. Say so in your report; do not invent a threshold to look rigorous.

- [ ] **Step 1: Drop the trade-off eyebrow**

Find it with `grep -n "TRADE-OFF ONLY YOU" codepet/Views/Copilot/VirtualCompanyCards.swift`.

`THE CALL`, `THE TRADE-OFF ONLY YOU CAN MAKE` and (before Task 1) `THE REAL DISAGREEMENT` were three competing ALL-CAPS labels. An eyebrow orients you inside one dense region; three of them stop orienting anyone. Delete the trade-off's `label(...)` line and let spacing carry the separation:

```swift
                // The trade-off keeps its position — LAST of the reading content, rule 5 —
                // and loses its eyebrow. THE CALL is the only label this card needs; a
                // second one directly above the closing paragraph was competing with it
                // rather than orienting anyone. The extra top padding is what now says
                // "this is the part you must decide".
                Text(brief.tradeoffFounderMustOwn).font(CodepetTheme.inter(14)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
```

**Do not clamp this text and do not shorten it.** Rule 5 plus the founder's Aug 7 ruling: a clamp cuts before the "or", and half a trade-off is one option, which is the "it's up to you" the rule forbids.

- [ ] **Step 2: Make the action row read primary-first**

Find it with `grep -n "Read the full call" codepet/Views/Copilot/VirtualCompanyCards.swift`.

Today `Read the full call` is a full-width bordered ghost button that sits **above** the primary `Lock this decision in`. Two stacked full-width buttons, with the secondary first. Put them on one row, primary leading:

```swift
                // One row, primary first. `Read the full call` used to be a FULL-WIDTH
                // bordered button stacked ABOVE `Lock this decision in` — two competing
                // blocks with the secondary action on top. It is a link now.
                HStack(spacing: 14) {
                    if lockedIn {
                        Text("📌 " + (lang == .vi ? "Đã chốt — quyết định này giờ dẫn đường cho cả app."
                                                  : "Locked in — this decision now grounds the rest of the app."))
                            .font(CodepetTheme.inter(12, weight: .medium))
                            .foregroundColor(CodepetTheme.accentTeal)
                    } else if state.canLockIn {
                        Button(action: onLockIn) {
                            Text(lang == .vi ? "Chốt quyết định này" : "Lock this decision in")
                                .font(CodepetTheme.inter(12.5, weight: .semibold))
                                .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(CodepetTheme.accentPurple))
                        }
                        .buttonStyle(.plain)
                        .cursorOnHover(.pointingHand)
                    }
                    if BriefDocument.hasMore(brief) {
                        Button { readingCall = BriefDocument.document(brief, language: lang) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text").font(.system(size: 11, weight: .semibold))
                                Text(lang == .vi ? "Đọc toàn bộ quyết định" : "Read the full call")
                            }
                            .font(CodepetTheme.inter(12.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.accentPurple)
                        }
                        .buttonStyle(.plain)
                        .cursorOnHover(.pointingHand)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
```

Delete the two original standalone blocks this replaces — the `if BriefDocument.hasMore(brief)` button and the `if lockedIn / else if state.canLockIn` pair. **Read the surrounding code before deleting**: the locked-in branch and the lock button are adjacent but not identical to what is written above, and `onAccent(_:)` is the existing helper for readable text on an accent fill (`grep -n "func onAccent" codepet/Views/CodepetTheme.swift`).

- [ ] **Step 3: Confirm the room still renders and the guard from Task 1 still passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/VCRoomLayoutTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-vc \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: **1 passed, 0 failed, 0 skipped.** Open the printed PNG and confirm by eye: one eyebrow in the card, the two actions on one row with `Lock this decision in` leading, and the trade-off paragraph intact and unclamped. Report what the PNG showed — that is this task's only real verification.

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Copilot/VirtualCompanyCards.swift
git status --porcelain   # confirm ONLY that one is staged
git commit -m "$(cat <<'EOF'
feat(vc): one eyebrow in the call, and the primary action first

THE CALL, THE TRADE-OFF ONLY YOU CAN MAKE and THE REAL DISAGREEMENT were three
competing ALL-CAPS labels. An eyebrow orients you inside one dense region; three
stop orienting anyone. Only THE CALL survives; spacing separates the trade-off,
which keeps its rule-5 position and stays unclamped.

`Read the full call` was a full-width bordered button stacked ABOVE the primary
`Lock this decision in` — the secondary action on top, both full width. They are
one row now, primary leading, secondary a link.

No automated assertion covers either change: removing one small label and
reshaping a button are not pixel-assertable here, and a small-text pixel count
would be dominated by the body copy. Verified from the rendered PNG.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git diff --cached --name-only   # must be empty
```

---

### Task 3: Departments become rows

The task the founder pointed at. Three tinted bordered panels become three lines.

**Files:**
- Modify: `codepet/Views/Copilot/VirtualCompanyCards.swift` (`departmentsSaid`, `positionCard`)
- Modify: `codepetTests/VCRoomLayoutTests.swift`

**Interfaces:**
- Consumes: `renderRoom(_:scheme:name:)`, `cardFill(hue:scheme:)` and `count(_:matching:tolerance:)` from Task 1.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

The department cards are only rendered when the *"What each department said"* disclosure is open, and `Disclosure` defaults to `open = false` — so a plain render of the room will **not** contain them and a test would pass vacuously. Assert on the position rows the room renders with positions present, by rendering `departmentsSaid` through the parent view is not possible (it is private), so assert instead that **no department-hued card fill appears anywhere in the room render**, which holds whether or not the disclosure is open, and additionally covers `positionCard`'s other caller.

Add to `codepetTests/VCRoomLayoutTests.swift`:

```swift
    /// No department renders as a tinted card.
    ///
    /// `positionCard` wrapped each department in `MessageCard(hue: accent(meta))` — a
    /// tinted, bordered panel carrying a name, a stance pill, confidence dots, the
    /// position, a "costs their department" line and an optional blocker. Three stacked
    /// were denser than the summary above them.
    ///
    /// Checked against every department hue the room can use, because a single hue would
    /// pass while the other two still drew cards.
    @MainActor
    func testNoDepartmentRendersAsACard() throws {
        let (rep, url) = try renderRoom(landedRoom(), scheme: .dark, name: "room-depts-dark")
        for (name, hue) in [("gold", CodepetTheme.accentGold),
                            ("orange", CodepetTheme.accentOrange),
                            ("blue", CodepetTheme.accentBlue),
                            ("teal", CodepetTheme.accentTeal),
                            ("green", CodepetTheme.accentGreen),
                            ("pink", CodepetTheme.accentPink)] {
            let fill = try cardFill(hue: hue, scheme: .dark)
            let n = count(rep, matching: fill, tolerance: 0.02)
            print("[measure] \(name) card-fill pixels = \(n)")
            XCTAssertLessThan(n, 40,
                              "a department still renders as a \(name) tinted card "
                              + "(\(n) matching pixels). See \(url.path)")
        }
    }
```

- [ ] **Step 2: Run it and record every count**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/VCRoomLayoutTests/testNoDepartmentRendersAsACard \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-vc \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

**This may PASS at red, and if it does, stop and investigate before changing production code.** The disclosure defaults closed, so the department cards may not be in the render at all — in which case the test is measuring nothing and would keep passing after the change too. Open the printed PNG. If the departments are absent, the test needs the disclosure open, which means either exposing an initial-open parameter on `Disclosure` (a production change belonging to this task) or rendering with the disclosure toggled. Report which you did and why.

Record every one of the six counts either way.

- [ ] **Step 3: Turn each department into a row**

Find them with `grep -n "private var departmentsSaid\|private func positionCard" codepet/Views/Copilot/VirtualCompanyCards.swift`.

`departmentsSaid` loses its 12pt spacing in favour of hairline separators:

```swift
    private var departmentsSaid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(state.agents.enumerated()), id: \.element.agentId) { i, meta in
                if i > 0 {
                    Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
                }
                if let position = state.positions[meta.agentId] {
                    positionRow(meta, position)
                }
                if let error = state.agentErrors[meta.agentId] {
                    errorRow(meta, error)
                }
            }
        }
    }
```

`positionCard` becomes `positionRow` — a disclosure whose closed state is one line:

```swift
    /// One department, one line until asked.
    ///
    /// It was a `MessageCard(hue:)` carrying five things at once: name, stance pill,
    /// confidence dots, the position, "costs their department", and sometimes a blocker.
    /// Three of those stacked read denser than the call they sat beneath.
    ///
    /// Rule 2 — never summarise the positions — is better served by this, not worse. The
    /// three stances now sit adjacent instead of separated by paragraphs, so the split is
    /// legible at a glance rather than after reading three panels. Nothing is summarised:
    /// every word is one click away, and the stance and confidence never move.
    private func positionRow(_ meta: VCAgentMeta, _ position: VCPosition) -> some View {
        DepartmentRow(
            name: displayName(meta),
            stance: stanceLabel(position.stance),
            hue: accent(meta),
            confidence: position.confidence,
            position: position.position,
            cost: (lang == .vi ? "Cái này khiến họ mất: " : "Costs their department: ")
                  + position.costToMyDept,
            blocker: position.hardBlocker)
    }

    /// Chevron, name, stance, dots — then everything else behind the row.
    ///
    /// A separate small view rather than reusing `Disclosure`: that one draws its header
    /// as a bordered `surface` pill, which would put a border back on every department
    /// and undo the point of this change.
    private struct DepartmentRow: View {
        let name: String
        let stance: String
        let hue: Color
        let confidence: Int
        let position: String
        let cost: String
        let blocker: String?
        @State private var open = false

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { open.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(CodepetTheme.mutedText)
                        // NOT `sectionName()` — that is `inter(25)`, and a 25pt department
                        // name is a large part of why the current cards feel heavy. In the
                        // screenshots "Finance" renders bigger than the decision headline
                        // above it, which inverts the hierarchy. A row needs a row-sized name.
                        Text(name).font(CodepetTheme.inter(13.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Text(stance)
                            .font(CodepetTheme.inter(11, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(hue.opacity(0.12)))
                            .foregroundColor(hue)
                        Spacer(minLength: 8)
                        // Rule 7: dots, never a number.
                        VCConfidenceDots(value: confidence)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cursorOnHover(.pointingHand)
                if open {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(position).font(CodepetTheme.inter(14.5)).lineSpacing(6)
                            .foregroundColor(CodepetTheme.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(cost).font(CodepetTheme.inter(13.5)).lineSpacing(5)
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let blocker {
                            Text("🔒 " + blocker)
                                .font(CodepetTheme.inter(12, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 17)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }
```

**One thing to check while you are in here:** the old `positionCard` used
`CodepetTheme.sectionName()` for the department name, which resolves to `inter(25, weight:)`.
At 25pt a department name renders **larger than the decision headline** in `theCall`
(`inter(16, weight: .semibold)`) — the hierarchy is inverted, and that inversion is doing as
much of the "heavy" impression as the borders are. The row uses 13.5pt. If the founder finds
it too quiet, raise it toward 15 — but it must stay below the call's 16.

**`VCConfidenceDots` does not exist yet.** `confidenceDots(_:)` is a method on `VCRunCards`, not reachable from a nested struct. Extract it: find it with `grep -n "func confidenceDots" codepet/Views/Copilot/VirtualCompanyCards.swift`, move its body into a small `struct VCConfidenceDots: View { let value: Int }` at file scope, and have the existing `confidenceDots(_:)` call site(s) use the new struct so there is one implementation rather than two. Rule 7 depends on this rendering identically in both places.

- [ ] **Step 4: Run it and record the GREEN counts**

Same command as Step 2. Expected: all six assertions pass. Record all six counts. Run twice, identical values required.

- [ ] **Step 5: Set the thresholds from the measured pairs**

Replace `40` with a value derived from the largest measured GREEN and the smallest meaningful RED, and write both into the comment. **If any hue's RED/GREEN separation is under about 3x, stop and report it.**

- [ ] **Step 6: Prove the guard can fail**

Temporarily restore `MessageCard(hue: hue) {` around `DepartmentRow`'s outer `VStack`, run, confirm FAIL and record which hues failed, then restore and prove it with `git diff --stat`.

- [ ] **Step 7: Run the whole VC suite — nothing else may break**

Nine existing VC test files cover this feature's state machine and decision logic.

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/VCRoomLayoutTests \
  -only-testing:codepetTests/VirtualCompanyDecisionTests \
  -only-testing:codepetTests/VirtualCompanyDepartmentTests \
  -only-testing:codepetTests/VirtualCompanyRunStateTests \
  -only-testing:codepetTests/VirtualCompanyUnusableTurnTests \
  -only-testing:codepetTests/MockVirtualCompanyTests \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-vc \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

Expected: 0 failed, 0 skipped.

- [ ] **Step 8: Commit**

```bash
git add codepet/Views/Copilot/VirtualCompanyCards.swift codepetTests/VCRoomLayoutTests.swift
git status --porcelain   # confirm ONLY those two are staged
git commit -m "$(cat <<'EOF'
feat(vc): departments are rows until you ask

Each department was a tinted bordered panel carrying five things: name, stance
pill, confidence dots, the position, "costs their department", and sometimes a
blocker. Three stacked read denser than the call they sat beneath — this is the
part the founder pointed at.

Now one line each: chevron, name, stance, dots. Position, cost and blocker are
one click away.

Rule 2 — never summarise the positions — is better served, not worse. The three
stances sit adjacent instead of separated by paragraphs, so the split is legible
at a glance rather than after reading three panels. Nothing is summarised and
nothing is dropped.

Not built on `Disclosure`: that draws its header as a bordered surface pill,
which would have put a border back on every department.

`confidenceDots` extracted to `VCConfidenceDots` so rule 7 has one
implementation rather than two.

Guard watched failing before shipping, across all six department hues — one hue
alone would pass while the other two still drew cards.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
git diff --cached --name-only   # must be empty
```

---

### Task 4: Full suite, then the founder's eye

**Files:** none modified.

- [ ] **Step 1: Confirm no `MessageCard` remains where this plan removed one**

```bash
cd /Users/monatruong/Developer/codepet-vc-design
grep -n "MessageCard" codepet/Views/Copilot/VirtualCompanyCards.swift
```

Expected: `theCall` still uses one, and the in-flight `conflictCard` / `routingCard` / `roundCard` / `verdictCard` still use theirs — those are out of scope. **`landedDisagreement` and the department rows must not appear in the output.**

- [ ] **Step 2: Run the full suite**

```bash
pgrep -x codepet >/dev/null && echo "NOTE: sibling's app is running — expect a possible lock; confirm via xcresulttool"
./scripts/ci-test.sh 2>&1 | tail -30
xcrun xcresulttool get test-results summary --path build/ci.xcresult | head -20
```

Expected: 0 failed. Take the baseline count from `.superpowers/sdd/progress.md`. Around 27 tests never finishing with **no actual failure** is the known 26.2 toolchain bug plus the sibling's Firestore lock — confirm via `xcresulttool` that none of them are this plan's.

- [ ] **Step 3: Build signed**

```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 2>&1 | grep -E "error:|BUILD"
```

Do **not** launch it if `pgrep -x codepet` finds the sibling's instance — one bundle id, one keychain session. Report the build as ready and let the founder launch, or wait until it is free. The launch argument is required and `defaults write` does not work for it:

```bash
open ~/Library/Developer/Xcode/DerivedData/CodePet-*/Build/Products/Debug/codepet.app --args -CODEPET_TWO_MODE YES
```

- [ ] **Step 4: Ask four questions, then stop**

The founder must drive a room to a landed brief to see this. Ask a decision question with a real trade-off — *"Should we raise the price to $49 and lose the self-serve tier?"* — because the router only convenes a room when something is genuinely at stake. **A convened decision costs roughly $0.20 of real API budget; do not loop on it.**

> 1. Does the room read as one decision now, rather than a stack of competing panels?
> 2. Open "What each department said" — is three lines better than three cards, and can you still see who disagreed at a glance?
> 3. In THE CALL, is one label enough, or did the trade-off need its own heading to be findable?
> 4. If the room comes back with no disagreement, does the block still read as agreement now that it has no border and no label of its own?

Question 4 is the risk the spec names explicitly: the block's identity moved from a border and a heading onto its hue alone. `WHERE THEY AGREE` is documented in the contract as a normal outcome, not an edge case, and it is the case least likely to appear in casual testing. **If it reads as ambiguous, restore that label for the aligned case only** — do not restore the border.

- [ ] **Step 5: Open a PR — only after Step 4 gets answers**

Pushing a branch runs **nothing** in CI. Open the PR, even as a draft, or the suite never runs on it. This branch was created from `origin/main` at `58777fe`, so it does not need the sibling's `feat/composer-controls` or `feat/diagnostics-reporting`.

```bash
git push -u origin feat/vc-room-streamlined
gh pr create --draft --base main --title "The room reads as one decision" --body "…"
```

---

## Self-review

**Spec coverage.** §1 (one border, two blocks) → Task 1. §1's one-eyebrow change and the action row → Task 2. §2 (department rows) → Task 3. Verification and the handoff → Tasks 1, 3 and 4. The spec's named-but-unfixed duplication between the department positions and `THE REAL QUESTION`'s ✓ list is out of scope in both documents and appears in neither task.

**The withdrawn merge is reflected correctly.** Task 1 keeps two blocks and one card, matching amendment **[A1]**. No task merges `theCall` and `landedDisagreement`.

**Rule coverage, since the contract is the binding document.** Rule 1: nothing moves behind a click that was not already behind one, and the departments' disclosure already existed. Rule 2: every department keeps its own row, its stance and its confidence, and Task 3's comment argues the adjacency serves the rule better. Rule 3: `theRealDisagreement` stays verbatim with `fixedSize` and no clamp in Task 1's replacement code. Rule 5: the trade-off keeps its last position in Task 2 and stays unclamped. Rule 7: Task 3 extracts `VCConfidenceDots` specifically so the dots have one implementation. Rule 9: no names or avatars are introduced.

**Placeholder scan.** No TBD, TODO, or "similar to Task N". Every code step carries the code. Two thresholds are explicitly labelled placeholders with a required calibration step and a stop-and-report condition — that is the opposite of a placeholder left to rot.

**Type consistency.** `renderRoom(_:scheme:name:)`, `cardFill(hue:scheme:)` and `count(_:matching:tolerance:)` are defined in Task 1 and consumed in Task 3. `positionCard` becomes `positionRow` in Task 3, and `departmentsSaid` is updated in the same step to call the new name. `DepartmentRow` and `VCConfidenceDots` are both introduced in Task 3, and the plan states that `VCConfidenceDots` must replace the existing `confidenceDots(_:)` body rather than duplicating it.

**Two honest gaps, stated rather than papered over.** Task 2 has no automated assertion at all, because removing one small label and reshaping a button are not pixel-assertable here — its verification is a PNG and the founder's eye, and the plan says so instead of inventing a threshold. Task 3 Step 2 may pass at red because the department disclosure defaults closed; the plan tells the implementer to stop and investigate rather than proceed, since a test that cannot fail is worse than none.
