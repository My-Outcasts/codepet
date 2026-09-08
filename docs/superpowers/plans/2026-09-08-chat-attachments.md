# Chat Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attached files appear as thumbnails in the founder's own transcript and in the composer, up to ten per message, with every refusal explained and drag-and-drop as a second way in.

**Architecture:** One decider (`AttachmentBudget.admit`), one encoder (`AttachmentPicker`), one tile view shared by the composer and the transcript. The bug being fixed is a second, unreported limit inside the picker; the fix is deleting it so the existing refusal machinery becomes reachable.

**Tech Stack:** Swift 5, SwiftUI, macOS deployment target 26.2, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-08-chat-attachments-design.md`

**Worktree:** `~/Developer/codepet-chat-attachments`, branch `feat/chat-attachments`, off `main` at `4f41034`. Run every command from that directory.

## Global Constraints

- **Files per message: 10.** `ChatAttachment.max = 10`. `ContextPin.max` stays **3** — do not touch it.
- **Total base64 per request: `AttachmentBudget.maxTotalBase64Bytes` (20 MB), unchanged.** This is the cap that binds.
- **Only `AttachmentBudget.admit` may refuse a file.** No count or size limit may exist in `AttachmentPicker` or in any view. Every refusal must produce text via `refusalMessage` or `unsupportedMessage`.
- **New `.swift` files need no Xcode project edit** (`PBXFileSystemSynchronizedRootGroup`, CLAUDE.md landmine 5).
- **Run tests per-suite with `-only-testing:`** (landmine 3: the XCTest host crashes on unrelated suites; `xcodebuild test` exits 65 on a clean checkout).
- **Quit the running `codepet.app` before any `xcodebuild test`** — a running instance kills the test host.
- **Sign builds with `DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates`.**
- **Debug code lands in `codepet.debug.dylib`, not the executable** (landmine 6) — verify built symbols there.
- **Mutation-test every new rule.** A test that passes with and without the code it protects is not protecting anything (CLAUDE.md, Working agreements).
- Commit messages carry the reasoning: the why, the measurement, the rejected alternative.

---

## File Structure

| File | Responsibility |
|---|---|
| `codepet/Views/Copilot/MessageAttachments.swift` | **Create.** Thumbnail cache, the split rule, and `AttachmentTile` — the one tile both surfaces draw. |
| `codepet/Views/Copilot/WrapLayout.swift` | **Create.** A `Layout` that wraps children onto rows. Used by the composer's attachment row. |
| `codepetTests/MessageAttachmentStripTests.swift` | **Create.** Split + cache. |
| `codepetTests/AttachmentPickerEncodeTests.swift` | **Create.** The picker encodes everything and decides nothing. |
| `codepetTests/WrapLayoutTests.swift` | **Create.** Row-breaking arithmetic. |
| `codepet/Views/Copilot/CopilotChatView.swift` | **Modify.** Draw the strip in the founder's bubble; stop swallowing an images-only turn. |
| `codepet/Views/Environment/AttachmentPicker.swift` | **Modify.** Delete `prefix(limit)`; add the pure `encodeAll`. |
| `codepet/Models/ChatAttachment.swift` | **Modify.** `max` 3 → 10, and rewrite the doc that justified 3. |
| `codepet/Views/Copilot/ChatComposer.swift` | **Modify.** Tiles in `pillRow`; call the picker without a limit; accept drops. |
| `codepetTests/AttachmentBudgetTests.swift` | **Modify.** Pin the new cap and the count-refusal message. |

---

## Task 1: Port the transcript strip onto this branch

The fix exists as uncommitted files in `~/Developer/codepet`, written against a branch **125 commits behind main**. `CopilotChatView.swift` differs. Re-apply it; do not copy the file blindly.

**Files:**
- Create: `codepet/Views/Copilot/MessageAttachments.swift`
- Create: `codepetTests/MessageAttachmentStripTests.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` (in `CopilotBubble.textBubble`)

**Interfaces:**
- Consumes: `ChatAttachment` (`id`, `kind`, `filename`, `data`, `icon`, `gloss`, `fittedSize(for:longEdge:)`), `CopilotMessage.attachments`.
- Produces: `MessageAttachmentLayout.split(_:) -> Split` with `.previews`, `.chips`, `.isEmpty`; `AttachmentThumbnailCache` with `image(for:) -> NSImage?`; `MessageAttachmentStrip(attachments:)`.

- [ ] **Step 1: Copy the two new files from the other checkout**

```bash
cd ~/Developer/codepet-chat-attachments
cp ~/Developer/codepet/codepet/Views/Copilot/MessageAttachments.swift codepet/Views/Copilot/
cp ~/Developer/codepet/codepetTests/MessageAttachmentStripTests.swift codepetTests/
```

- [ ] **Step 2: Run the suite to verify it passes on main's code**

```bash
osascript -e 'quit app "codepet"'
xcodebuild test -scheme codepet -configuration Debug -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates \
  -only-testing:codepetTests/MessageAttachmentStripTests 2>&1 | tail -20
```

Expected: `Executed 7 tests, with 0 failures`. If it fails to compile, `ChatAttachment` has changed on main — read it and adapt, do not weaken the test.

- [ ] **Step 3: Re-apply the two `textBubble` edits by hand**

Find `@ViewBuilder private var textBubble` in `codepet/Views/Copilot/CopilotChatView.swift`. Two changes.

First, the empty guard. Replace:

```swift
        if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
```

with:

```swift
        // **`&& attachments.isEmpty` is load-bearing.** Dropping screenshots in with no
        // typed words is a complete turn — the backend renders it as media blocks alone,
        // deliberately (`renderTurn`: "a media turn with no text returns the media blocks
        // alone"). Without this clause the founder sent that turn, got an answer about
        // images, and her own message drew nothing whatsoever above it.
        if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && message.attachments.isEmpty {
            EmptyView()
```

Second, the strip. Inside the `} else if isMe {` branch, find `let pad: CGFloat = 14` followed by `HStack {`. Wrap the existing `HStack` so the branch reads:

```swift
            let quiet = surface == .twoMode
            let pad: CGFloat = 14
            VStack(alignment: .trailing, spacing: 6) {
                // What she attached to THIS turn, above her words — the order the model
                // receives the turn in, because the question is about the picture. Draws
                // nothing when she attached nothing, i.e. on every turn to date.
                MessageAttachmentStrip(attachments: message.attachments)
                // Guarded, so an images-only turn shows its images and NOT an empty
                // bubble underneath them — see the `attachments.isEmpty` note above.
                if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack {
                        Spacer(minLength: 24)
                        Text(message.text)
                            // ... every existing modifier on this Text, unchanged ...
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
```

Keep every existing modifier on `Text(message.text)` exactly as main has it. Re-indent the moved block; do not leave it at the old depth.

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme codepet -configuration Debug -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Mutation-check the cache**

Delete the line `if let hit = decoded[attachment.id] { return hit }` from `MessageAttachments.swift`, re-run the suite from Step 2, and confirm **exactly one** test fails: `testSecondLookupReturnsTheCachedInstance`. Restore the line and re-run to green. (Without this the test would pass with no cache at all — `XCTAssertEqual` on two `NSImage`s cannot tell.)

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Copilot/MessageAttachments.swift codepetTests/MessageAttachmentStripTests.swift codepet/Views/Copilot/CopilotChatView.swift
git commit -m "fix(chat): the founder's own bubble shows what she attached

`CopilotMessage.attachments` was written by `CompanyStore.sendMessage` and read
back by the same method to rebuild `history[].attachments` — a correct round trip
with no view reading the field. So the model saw five screenshots and her
transcript showed one sentence (reported 8 Sep).

Images are thumbnails above the text, in the order the model receives the turn;
a PDF or source file has nothing to preview and stays a chip. Decoded once and
resampled to 200px, keyed on \`ChatAttachment.id\` (\`path#byteCount\`, so an edited
file re-decodes): \`data\` is base64 of an image up to 2576px and \`body\` is the hot
path, which is the per-frame cost class of the dock divider.

The empty-text guard now also checks attachments. An images-only turn is a
complete turn the backend renders as media blocks alone, and it was drawing
nothing at all."
```

---

## Task 2: The picker encodes; only the budget decides

**Files:**
- Modify: `codepet/Views/Environment/AttachmentPicker.swift:23-41`
- Create: `codepetTests/AttachmentPickerEncodeTests.swift`

**Interfaces:**
- Consumes: `AttachmentPicker.encode(_ url: URL) -> ChatAttachment?` (already exists, already internal).
- Produces: `AttachmentPicker.encodeAll(_ urls: [URL]) -> (attachments: [ChatAttachment], rejected: [String])`, and `pickAndEncode()` with **no `limit:` parameter**. Task 4 calls both.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/AttachmentPickerEncodeTests.swift`:

```swift
import XCTest
@testable import codepet

/// The picker encodes. It does not decide.
///
/// This suite exists because it used to decide, invisibly. `pickAndEncode` trimmed with
/// `panel.urls.prefix(limit)`, and `rejected` collected only files that FAILED TO ENCODE —
/// so a file removed by the trim was reported nowhere. The founder picked four images, three
/// appeared, and nothing was said (8 Sep). `AttachmentBudget.admit` never saw the fourth, so
/// the refusal machinery that would have named it was never reachable.
@MainActor
final class AttachmentPickerEncodeTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cp-picker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// A 1x1 PNG on disk, named `name`.
    private func png(_ name: String) throws -> URL {
        let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let url = dir.appendingPathComponent(name)
        try Data(base64Encoded: b64)!.write(to: url)
        return url
    }

    /// **The reported bug.** More files than the cap must all be encoded and handed on, so
    /// that `admit` — the only thing allowed to refuse — can name the ones that do not fit.
    func testEncodesEveryFileEvenPastTheCap() throws {
        let urls = try (0..<(ChatAttachment.max + 4)).map { try png("shot\($0).png") }
        let out = AttachmentPicker.encodeAll(urls)
        XCTAssertEqual(out.attachments.count, ChatAttachment.max + 4)
        XCTAssertTrue(out.rejected.isEmpty)
    }

    /// Order is the founder's pick order, because the notice names files in that order.
    func testKeepsPickOrder() throws {
        let urls = try ["b.png", "a.png", "c.png"].map { try png($0) }
        XCTAssertEqual(AttachmentPicker.encodeAll(urls).attachments.map(\.filename),
                       ["b.png", "a.png", "c.png"])
    }

    /// `rejected` keeps its ONE meaning: the picker could not read this file. It is no
    /// longer overloaded with "silently over the count", which is what hid the bug.
    func testRejectedMeansUnreadableAndNothingElse() throws {
        let good = try png("ok.png")
        let bad = dir.appendingPathComponent("notes.sketch")
        try Data("x".utf8).write(to: bad)
        let out = AttachmentPicker.encodeAll([good, bad])
        XCTAssertEqual(out.attachments.map(\.filename), ["ok.png"])
        XCTAssertEqual(out.rejected, ["notes.sketch"])
    }

    /// Everything the picker returns must be admissible input: `admit` decides, and with
    /// room for all of them it takes all of them.
    func testWhatItReturnsIsWhatAdmitJudges() throws {
        let urls = try (0..<3).map { try png("s\($0).png") }
        let out = AttachmentPicker.encodeAll(urls)
        let admission = AttachmentBudget.admit(out.attachments, to: [])
        XCTAssertEqual(admission.accepted.count, 3)
        XCTAssertTrue(admission.refused.isEmpty)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
osascript -e 'quit app "codepet"'
xcodebuild test -scheme codepet -configuration Debug -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates \
  -only-testing:codepetTests/AttachmentPickerEncodeTests 2>&1 | tail -20
```

Expected: compile failure — `type 'AttachmentPicker' has no member 'encodeAll'`.

- [ ] **Step 3: Implement**

In `codepet/Views/Environment/AttachmentPicker.swift`, replace `pickAndEncode(limit:)` entirely with:

```swift
    /// Open the panel and encode whatever the founder picked.
    ///
    /// **This function no longer has a limit, and that is the fix.** It used to take one
    /// and trim with `panel.urls.prefix(limit)` — while `rejected` collected only files that
    /// FAILED TO ENCODE, so a file removed by the trim was reported nowhere. The founder
    /// picked four images, three appeared, and nothing was said (8 Sep). The panel had
    /// offered her a fourth selection and then taken it back in silence.
    ///
    /// `AttachmentBudget.admit` owns both caps, is pure and is tested, and its `.tooMany`
    /// refusal has always rendered a message naming the files. That machinery was simply
    /// unreachable, because this function trimmed the list before `admit` could see it. So
    /// there is now exactly one place a file can be refused, and it must say why.
    static func pickAndEncode() -> (attachments: [ChatAttachment], rejected: [String]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ChatAttachment.allowedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = "Attach"
        panel.message = "Screenshots, PDFs, and text files. Images are resized before sending."

        guard panel.runModal() == .OK else { return ([], []) }
        return encodeAll(panel.urls)
    }

    /// Encode a set of files, keeping the founder's order.
    ///
    /// Split out from the panel so it is reachable from a test with fixture URLs — the
    /// `NSOpenPanel` is the only part of this file a test cannot drive.
    ///
    /// **Deliberately has no cap of any kind.** A limit here is a second place a file can
    /// disappear, and the last one produced a defect the founder could see and we could
    /// not explain. `encode` already refuses a single file over `ChatAttachment.maxBytes`,
    /// which bounds the cost; everything else is `admit`'s to judge.
    static func encodeAll(_ urls: [URL]) -> (attachments: [ChatAttachment], rejected: [String]) {
        var out: [ChatAttachment] = []
        var rejected: [String] = []
        for url in urls {
            if let a = encode(url) { out.append(a) } else { rejected.append(url.lastPathComponent) }
        }
        return (out, rejected)
    }
```

**Update the one caller in the same step.** `codepetTests` does `@testable import codepet`,
so a broken app module means this task's OWN tests cannot compile — leaving it until Task 4
makes Step 4 below impossible, not merely untidy.

In `codepet/Views/Copilot/ChatComposer.swift`, inside `plusMenu`'s attach `Button`, delete
the two `room` lines and drop the argument:

```swift
                    Button {
                        // No `limit:` and no `room` guard. The picker encodes whatever she
                        // chose and `admit` alone decides — see `pickAndEncode`'s comment
                        // for the defect that rule exists to prevent.
                        let picked = AttachmentPicker.pickAndEncode()
```

That replaces these three lines:

```swift
                    Button {
                        let room = ChatAttachment.max - atts.wrappedValue.count
                        guard room > 0 else { return }
                        let picked = AttachmentPicker.pickAndEncode(limit: room)
```

Leave `let full = atts.wrappedValue.count >= ChatAttachment.max` and the `.disabled(full)`
alone — that greys the menu row when she is already at the cap, which is a statement, not a
silent trim. Everything from `let admission = ...` onward is unchanged.

- [ ] **Step 4: Run the tests and confirm green**

Same command as Step 2. Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Mutation-check**

Re-insert `.prefix(3)` on the `for url in urls` loop in `encodeAll`. Re-run. Expected: `testEncodesEveryFileEvenPastTheCap` fails and `testKeepsPickOrder` still passes. Remove it and re-run green. This proves the test targets the trim and not something incidental.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Environment/AttachmentPicker.swift codepetTests/AttachmentPickerEncodeTests.swift
git commit -m "fix(composer): the picker stops deciding, so refusals become sayable

She picked four images; three appeared; nothing was said. Not the cap working —
\`pickAndEncode\` trimmed with \`panel.urls.prefix(limit)\`, and \`rejected\` collects
only files that FAILED TO ENCODE, so a file removed by the trim was reported
nowhere. \`admit\` then saw three, accepted three, and \`refusalMessage\` returned
nil. The \`noticeRow\` that exists to explain exactly this was never handed
anything to say.

\`Reason.tooMany\` and its message have been correct the whole time and simply
unreachable. So the fix is deleting the trim, not adding copy: one place refuses
a file, and it must give a reason.

\`encodeAll\` is split out so a test can drive it from fixture URLs — the panel is
the only untestable part. It has no cap on purpose; a limit here is a second
place a file can vanish, which is the bug."
```

---

## Task 3: Raise the cap to ten

**Files:**
- Modify: `codepet/Models/ChatAttachment.swift:36-40`
- Modify: `codepetTests/AttachmentBudgetTests.swift`

**Interfaces:**
- Produces: `ChatAttachment.max == 10`. Tasks 4 and 5 rely on it.

- [ ] **Step 1: Write the failing test**

Append to `codepetTests/AttachmentBudgetTests.swift`, inside the class:

```swift
    /// **Ten, and the byte budget is what actually binds.** The count is a sanity guard;
    /// `maxTotalBase64Bytes` is what protects the request, and a downscaled screenshot is
    /// 1–3 MB, so a realistic set hits bytes long before it hits ten.
    func testTenFilesFitAndTheEleventhIsRefusedByName() {
        let candidates = (0..<11).map { att("s\($0).png", encoded: 1024) }
        let admission = AttachmentBudget.admit(candidates, to: [])
        XCTAssertEqual(admission.accepted.count, 10)
        XCTAssertEqual(admission.refused, ["s10.png"])
        XCTAssertEqual(admission.reason, .tooMany)
    }

    /// The refusal has to NAME the file and state the rule. "Some files were skipped" is
    /// not actionable; this is the sentence the founder reads instead of silence.
    func testTheCountRefusalNamesTheFileAndTheRule() {
        let admission = AttachmentBudget.admit((0..<11).map { att("s\($0).png", encoded: 1024) },
                                               to: [])
        let msg = AttachmentBudget.refusalMessage(admission, .en)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("s10.png"), "must name the refused file — got: \(msg!)")
        XCTAssertTrue(msg!.contains("10"), "must state the cap — got: \(msg!)")
    }

    /// A pin is grounding, a file is payload. They shared a ceiling only because they share
    /// a row, and raising one must not drag the other.
    func testPinsKeepTheirOwnCeiling() {
        XCTAssertEqual(ContextPin.max, 3)
        XCTAssertEqual(ChatAttachment.max, 10)
    }
```

- [ ] **Step 2: Run and watch it fail**

```bash
osascript -e 'quit app "codepet"'
xcodebuild test -scheme codepet -configuration Debug -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates \
  -only-testing:codepetTests/AttachmentBudgetTests 2>&1 | tail -25
```

Expected: `testTenFilesFitAndTheEleventhIsRefusedByName` fails — accepted is 3, not 10.

- [ ] **Step 3: Implement**

In `codepet/Models/ChatAttachment.swift`, replace the `max` declaration and its doc comment:

```swift
    /// How many files one message may carry.
    ///
    /// **This used to be 3 and matched `ContextPin.max`,** on the reasoning that pins and
    /// files are both "things riding the next message" and two ceilings for one pill row
    /// would be arbitrary. That reasoning is retired: a pin is GROUNDING (it replaces the
    /// ranker's guess) and a file is PAYLOAD (it is bytes on the wire), and only one of
    /// them has a transport cost. `ContextPin.max` stays 3.
    ///
    /// Ten is a sanity guard, not the real limit. `AttachmentBudget.maxTotalBase64Bytes`
    /// is what protects the request, and a downscaled screenshot runs 1–3 MB against a
    /// 20 MB budget — so in real use the bytes bind first and this number is never reached.
    static let max = 10
```

- [ ] **Step 4: Run and confirm green**

Same command as Step 2. Expected: 0 failures across the whole suite.

- [ ] **Step 5: Mutation-check**

Set `max = 3`, re-run, confirm `testTenFilesFitAndTheEleventhIsRefusedByName` and `testPinsKeepTheirOwnCeiling` both fail. Set it back to 10 and re-run green.

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/ChatAttachment.swift codepetTests/AttachmentBudgetTests.swift
git commit -m "feat(chat): ten files per message, with bytes still the binding cap

Three came from \`ContextPin.max\` — pins and files sharing a row, so sharing a
ceiling. Retired: a pin is grounding and a file is payload, and only one of them
costs anything on the wire. \`ContextPin.max\` stays 3.

Ten is a sanity guard. \`maxTotalBase64Bytes\` (20MB) is the cap that protects the
request, and a downscaled screenshot is 1-3MB, so a realistic set hits bytes
first and never reaches ten. Both refusals name the file and state their own
rule, which is why the two are distinguishable in the notice."
```

---

## Task 4: Tiles in the composer

**Files:**
- Create: `codepet/Views/Copilot/WrapLayout.swift`
- Create: `codepetTests/WrapLayoutTests.swift`
- Modify: `codepet/Views/Copilot/MessageAttachments.swift` (extract `AttachmentTile`)
- Modify: `codepet/Views/Copilot/ChatComposer.swift` (`pillRow`, and the `plusMenu` attach button)

**Interfaces:**
- Consumes: `MessageAttachmentLayout.split`, `AttachmentThumbnailCache`, `ChatAttachment.max == 10` (Task 3). The `plusMenu` call site was already updated in Task 2.
- Produces: `AttachmentTile(attachment:cache:onRemove:)` where `onRemove: (() -> Void)?`; `WrapLayout(spacing:rowSpacing:)`. Task 5 calls the composer's admit path.

- [ ] **Step 1: Write the failing layout test**

Create `codepetTests/WrapLayoutTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import codepet

/// Row-breaking arithmetic, separated from SwiftUI so it can be checked.
///
/// The composer must show every attached file — ten tiles cannot fit one 380pt row, and
/// hiding the overflow behind a counter puts invisible state in the control the founder is
/// about to spend credits from.
final class WrapLayoutTests: XCTestCase {

    /// Widths that fit on one row stay on one row.
    func testOneRowWhenEverythingFits() {
        let rows = WrapLayout.rows(widths: [50, 50, 50], available: 200, spacing: 6)
        XCTAssertEqual(rows, [[0, 1, 2]])
    }

    /// The item that does not fit starts the next row rather than being dropped or clipped.
    func testBreaksToASecondRow() {
        let rows = WrapLayout.rows(widths: [80, 80, 80], available: 200, spacing: 6)
        XCTAssertEqual(rows, [[0, 1], [2]])
    }

    /// Spacing counts toward the row width — without it the last tile on each row overhangs.
    func testSpacingCountsTowardTheRowWidth() {
        // 3x64 = 192 fits 200 on width alone; with 2 gaps of 6 it is 204 and must break.
        let rows = WrapLayout.rows(widths: [64, 64, 64], available: 200, spacing: 6)
        XCTAssertEqual(rows, [[0, 1], [2]])
    }

    /// An item wider than the row gets its own row rather than looping forever.
    func testAnOversizeItemGetsItsOwnRow() {
        let rows = WrapLayout.rows(widths: [400, 50], available: 200, spacing: 6)
        XCTAssertEqual(rows, [[0], [1]])
    }

    func testNoItemsIsNoRows() {
        XCTAssertEqual(WrapLayout.rows(widths: [], available: 200, spacing: 6), [])
    }
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
osascript -e 'quit app "codepet"'
xcodebuild test -scheme codepet -configuration Debug -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates \
  -only-testing:codepetTests/WrapLayoutTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'WrapLayout' in scope`.

- [ ] **Step 3: Implement the layout**

Create `codepet/Views/Copilot/WrapLayout.swift`:

```swift
// codepet/Views/Copilot/WrapLayout.swift
import SwiftUI

/// Lays children left to right, wrapping to a new row when the next one will not fit.
///
/// Exists because the composer must show EVERY attached file: ten tiles do not fit one 380pt
/// dock row, and an overflow counter would put state the founder cannot see into the control
/// she is about to send from.
///
/// The row-breaking is `rows(widths:available:spacing:)` — a static function over plain
/// numbers, so it is checkable without a view hierarchy. `sizeThatFits` and `placeSubviews`
/// are thin wrappers over it.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    /// Index groups, one per row. Pure arithmetic — see the type's comment.
    ///
    /// An item wider than `available` takes a row of its own rather than being skipped: a
    /// dropped child is an invisible failure, and this file exists because of one of those.
    static func rows(widths: [CGFloat], available: CGFloat, spacing: CGFloat) -> [[Int]] {
        var out: [[Int]] = []
        var row: [Int] = []
        var used: CGFloat = 0
        for (i, w) in widths.enumerated() {
            let gap = row.isEmpty ? 0 : spacing
            if !row.isEmpty && used + gap + w > available {
                out.append(row)
                row = [i]
                used = w
            } else {
                row.append(i)
                used += gap + w
            }
        }
        if !row.isEmpty { out.append(row) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(widths: sizes.map(\.width), available: available, spacing: spacing)
        let height = rows.reduce(CGFloat.zero) { acc, row in
            acc + (row.map { sizes[$0].height }.max() ?? 0)
        } + rowSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map { row in
            row.reduce(CGFloat.zero) { $0 + sizes[$1].width }
                + spacing * CGFloat(max(0, row.count - 1))
        }.max() ?? 0
        return CGSize(width: min(width, available), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(widths: sizes.map(\.width), available: bounds.width, spacing: spacing)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            for i in row {
                subviews[i].place(at: CGPoint(x: x, y: y + (rowHeight - sizes[i].height) / 2),
                                  proposal: ProposedViewSize(sizes[i]))
                x += sizes[i].width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }
}
```

- [ ] **Step 4: Run and confirm green**

Same command as Step 2. Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Mutation-check**

In `rows`, change `used + gap + w > available` to `used + w > available` (dropping the gap). Re-run: `testSpacingCountsTowardTheRowWidth` must fail and the others pass. Restore and re-run green.

- [ ] **Step 6: Extract `AttachmentTile` in `MessageAttachments.swift`**

Add this type, and change `MessageAttachmentStrip` to use it so there is one tile and not two. `onRemove` nil means no `×` — that is how the transcript and the composer differ.

```swift
/// One attached file, drawn the same way wherever it appears.
///
/// The composer passes `onRemove` and gets a hover `×`; the transcript passes nil and gets a
/// static thumbnail. One tile rather than two means a file cannot look like one thing before
/// sending and another after.
struct AttachmentTile: View {
    let attachment: ChatAttachment
    let cache: AttachmentThumbnailCache
    /// nil in the transcript: a sent attachment is a record, not something still removable.
    var onRemove: (() -> Void)?

    @State private var hovering = false
    private let side: CGFloat = 56

    var body: some View {
        Group {
            if attachment.kind == .image, let image = cache.image(for: attachment) {
                Image(nsImage: image)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                // No pixels to show — an unreadable image lands here too, so a torn file
                // still says what it was rather than drawing a broken box.
                VStack(spacing: 3) {
                    Image(systemName: attachment.icon).font(.system(size: 14))
                    Text(attachment.gloss).font(CodepetTheme.inter(9, weight: .medium))
                }
                .foregroundColor(CodepetTheme.mutedText)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CodepetTokens.well))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(CodepetTokens.cardEdge))
        .overlay(alignment: .topTrailing) {
            if let onRemove, hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Remove")
                .padding(3)
            }
        }
        .onHover { hovering = $0 }
        .help(attachment.filename)
    }
}
```

Then replace `MessageAttachmentStrip`'s body loops so both `split.previews` and `split.chips` render `AttachmentTile(attachment:cache:onRemove:nil)`, deleting the strip's private `thumbnail` and `chip` helpers. Run `-only-testing:codepetTests/MessageAttachmentStripTests` and confirm it is still green — the split and cache tests must not need changing.

- [ ] **Step 7: Rewrite `pillRow` in `ChatComposer.swift`**

Replace the `HStack(spacing: 6) { ForEach(attList) ... ForEach(pinList) ... Spacer() }` block with:

```swift
                if !pinList.isEmpty || !attList.isEmpty {
                    // Tiles for files, pills for pins — and one wrapping row for both,
                    // because to the founder they are still the same gesture. Ten tiles
                    // cannot fit a 380pt dock on one line, and an overflow counter would
                    // hide part of what she is about to send.
                    WrapLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(attList) { att in
                            AttachmentTile(attachment: att, cache: tileCache) {
                                attachments?.wrappedValue = ChatAttachment.removing(att, from: attList)
                            }
                        }
                        ForEach(pinList) { pin in
                            pill(icon: pin.icon, title: pin.title, gloss: pin.gloss) {
                                pins?.wrappedValue = ContextPin.removing(pin, from: pinList)
                            }
                        }
                    }
                }
```

Add the cache as state near `attachNotice` (line ~130):

```swift
    /// One decode per file for the life of the composer. See `AttachmentThumbnailCache` —
    /// `body` runs constantly and `data` is base64 of an image up to 2576px.
    @State private var tileCache = AttachmentThumbnailCache()
```

`pill(icon:title:gloss:remove:)` stays exactly as it is — it is now the **pins** presentation and nothing else. Do not delete it.

- [ ] **Step 8: Build and check by eye**

```bash
xcodebuild -scheme codepet -configuration Debug -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
open ~/Library/Developer/Xcode/DerivedData/CodePet-*/Build/Products/Debug/codepet.app
```

Attach 4 images: four tiles, no notice. Attach 11: ten tiles and a notice naming the eleventh. Hover a tile: `×` appears and removes it.

- [ ] **Step 9: Commit**

```bash
git add codepet/Views/Copilot/WrapLayout.swift codepetTests/WrapLayoutTests.swift codepet/Views/Copilot/MessageAttachments.swift codepet/Views/Copilot/ChatComposer.swift
git commit -m "feat(composer): thumbnail tiles, wrapped, so nothing is hidden

Filename pills answered every question except the one she had: which screenshot
is that. Three of them also filled a 380pt row, and the cap is now ten.

One tile serves both surfaces — \`onRemove\` nil in the transcript, present in the
composer — so a file cannot look like one thing before sending and another
after. \`pill()\` stays, now meaning PINS and nothing else.

\`WrapLayout\` wraps rather than counting overflow: hiding part of the payload
behind a \"+6\" puts invisible state in the control she is about to spend credits
from. Its row-breaking is a static over plain numbers so it is testable; the
spacing term is what a mutation check goes red on."
```

---

## Task 5: Drop files onto the composer

**Files:**
- Modify: `codepet/Views/Copilot/ChatComposer.swift` (`dockBody`, `twoModeBody`, plus one new helper)

**Interfaces:**
- Consumes: `AttachmentPicker.encodeAll(_:)` (Task 2), `AttachmentBudget.admit`, `ChatAttachment.adding`.
- Produces: nothing later tasks use.

- [ ] **Step 1: Add the shared admit helper**

The `+` menu and a drop must not grow two copies of the admit-and-explain sequence. Add near `plusMenu` in `ChatComposer.swift`:

```swift
    /// Take a freshly encoded pick and let `admit` decide — the ONE path for both the
    /// `+` menu and a drop. Two copies of this sequence would be two chances to skip the
    /// notice, and a skipped notice is the defect this whole change exists to end.
    private func absorb(_ picked: (attachments: [ChatAttachment], rejected: [String])) {
        guard let atts = attachments else { return }
        let admission = AttachmentBudget.admit(picked.attachments, to: atts.wrappedValue)
        var next = atts.wrappedValue
        for a in admission.accepted { next = ChatAttachment.adding(a, to: next) }
        atts.wrappedValue = next
        // Assigned every time, so a clean pick clears a stale refusal.
        let lines = [AttachmentBudget.refusalMessage(admission, lang),
                     AttachmentBudget.unsupportedMessage(picked.rejected, lang)]
            .compactMap { $0 }
        attachNotice = lines.isEmpty ? nil : lines.joined(separator: " ")
    }
```

Replace the body of the `+` menu's attach `Button` action with `absorb(AttachmentPicker.pickAndEncode())`.

- [ ] **Step 2: Add the drop state and modifier**

Add beside `tileCache`:

```swift
    /// True while a drag is over the composer. Drives the border highlight — an invisible
    /// drop target is indistinguishable from a broken one.
    @State private var dropTargeted = false
```

And a modifier both bodies apply:

```swift
    /// Files dropped on the composer go through the SAME encode-then-admit path as the
    /// `+` menu, so a drop cannot bypass the cap or the notice.
    private func acceptingDrops<V: View>(_ content: V) -> some View {
        content.onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard attachments != nil else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for p in providers {
                    if let item = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
                       let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                guard !urls.isEmpty else { return }
                absorb(AttachmentPicker.encodeAll(urls))
            }
            return true
        }
    }
```

Add `import UniformTypeIdentifiers` at the top of the file if absent.

- [ ] **Step 3: Apply it to both composer bodies**

`dockBody` and `twoModeBody` each end with a chain of modifiers on their outer `VStack`.
**Their corner radii differ — `dockBody` uses 16, `twoModeBody` uses 12** (verified against
main). Use each body's own value or the highlight will not sit on its border.

In `dockBody`, after the existing `.overlay(RoundedRectangle(cornerRadius: 16, ...).stroke(accent...))`, add:

```swift
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent, lineWidth: dropTargeted ? 2 : 0)
        )
```

In `twoModeBody`, after its `.overlay(RoundedRectangle(cornerRadius: 12, ...))`, add the same
with **12**:

```swift
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent, lineWidth: dropTargeted ? 2 : 0)
        )
```

Then make each body accept drops. Both are computed properties whose whole value is one
modifier chain, so convert each from an implicit return to an explicit one:

```swift
    private var dockBody: some View {
        let stack = VStack(alignment: .leading, spacing: 12) {
            // ... every existing child and modifier, unchanged ...
        }
        // ... every existing modifier, unchanged, including the new overlay above ...
        return acceptingDrops(stack)
    }
```

Do the same for `twoModeBody` with its own contents. Nothing inside either body changes.

- [ ] **Step 4: Build and verify by hand**

```bash
xcodebuild -scheme codepet -configuration Debug -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
```

Then, in the running app: drag 2 images from Finder over the composer — the border highlights — and drop. Two tiles appear. Drag a `.sketch` file: it is refused with "Codepet can't read …". Drag 11 images at once: ten tiles and a notice naming the eleventh.

There is no unit test for this task; the drop plumbing is `NSItemProvider` and AppKit. `absorb` is exercised through Tasks 2–4's suites. Say so in the commit rather than implying coverage.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Copilot/ChatComposer.swift
git commit -m "feat(composer): drop files straight onto the chat box

A drop takes the same road as the + menu: encode, then \`admit\` decides. That is
what \`absorb\` is for — two copies of the admit-and-explain sequence would be two
chances to skip the notice, and a skipped notice is the defect this change set
exists to end.

The border highlights while a drag is over the composer. An invisible drop
target is indistinguishable from a broken one, which this repo has now learned
twice.

No unit test: the plumbing is NSItemProvider and AppKit. \`absorb\`'s decision
path is covered by the picker and budget suites; the drop itself was verified by
hand with images, an unreadable .sketch, and eleven files at once."
```

---

## Task 6: Full-suite verification and PR

- [ ] **Step 1: Run every touched suite**

```bash
osascript -e 'quit app "codepet"'
for s in MessageAttachmentStripTests AttachmentPickerEncodeTests AttachmentBudgetTests WrapLayoutTests AttachmentSendTests; do
  echo "=== $s ==="
  xcodebuild test -scheme codepet -configuration Debug -destination 'platform=macOS' \
    DEVELOPMENT_TEAM=YL72VTKBR7 -allowProvisioningUpdates \
    -only-testing:codepetTests/$s 2>&1 | grep -E "Executed .* tests"
done
```

Expected: `0 failures` on every line. `AttachmentSendTests` is included because it exercises the real cap at the store boundary and Task 3 moved that number.

- [ ] **Step 2: Confirm the built app carries the new code**

```bash
D=$(find ~/Library/Developer/Xcode/DerivedData/CodePet-*/Build/Products/Debug/codepet.app -name codepet.debug.dylib | head -1)
for sym in AttachmentTile WrapLayout MessageAttachmentStrip; do printf "%s: %s\n" "$sym" "$(strings "$D" | grep -c "$sym")"; done
```

Expected: a non-zero count for each. Grepping `Contents/MacOS/codepet` instead finds nothing (landmine 6).

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin feat/chat-attachments
gh pr create --repo My-Outcasts/codepet --base main --head feat/chat-attachments \
  --title "Chat attachments: tiles, ten files, and a cap that explains itself" \
  --body-file <(cat <<'BODY'
Implements `docs/superpowers/specs/2026-09-08-chat-attachments-design.md`.

Three defects from one founder session on 8 Sep.

**Her own transcript never showed what she attached.** `CopilotMessage.attachments` was written and read back by `CompanyStore.sendMessage` to rebuild history — a correct round trip with no view reading the field.

**A fourth image was discarded in silence.** Not the cap working: `pickAndEncode` trimmed with `panel.urls.prefix(limit)`, and `rejected` collects only files that failed to ENCODE, so the trimmed file was reported nowhere. `admit` saw three, accepted three, `refusalMessage` returned nil. `Reason.tooMany` and its message were correct all along and simply unreachable. **Deleting the trim is the fix** — no new copy.

**Filename pills could not answer "which screenshot is that."**

Cap is now 10; `maxTotalBase64Bytes` (20 MB) still binds in real use. `ContextPin.max` stays 3 — a pin is grounding, a file is payload.

Verified: every touched suite green, each new rule mutation-checked (break it, watch the named test go red, restore). Drag-and-drop verified by hand — no unit test, the plumbing is NSItemProvider.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)
```

- [ ] **Step 4: Watch CI, then report**

```bash
gh pr checks --repo My-Outcasts/codepet --watch
```

Do not merge without asking.
