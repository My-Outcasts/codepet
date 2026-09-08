# Deliverable Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every deliverable kind can be saved to a real file on the founder's disk, so work made in Codepet can reach an investor, a customer, or a web host.

**Architecture:** A pure core (`DeliverableExport`) turns a `Deliverable` into `[ExportFile]` — name plus bytes — with no AppKit and no view, so every kind's rendering is unit-testable. A thin AppKit seam (`DeliverableExporter`) owns the `NSSavePanel`, following the rule `AttachmentPicker` already states: "the one place an `NSOpenPanel` is allowed to exist, so no view has to know about AppKit." `DeliverableFrame` gains an `export:` slot beside its existing `action:`, so copy and export sit side by side without disturbing the seven call sites that already pass `action:`.

**Tech Stack:** Swift 5, SwiftUI, AppKit (`NSSavePanel`), XCTest. macOS target 26.2.

## Global Constraints

- **Scope is pure-data exports only:** `.md`, `.txt`, `.csv`, `.ics`, `.html`. `.pdf` and `screens` → `.png` need `ImageRenderer` over a live view and are a separate plan.
- **The app writes, never uploads.** No network call anywhere in this plan.
- **Nothing leaves without the founder choosing it** — every write is behind a save panel the founder confirms.
- **Spec:** `docs/superpowers/specs/2026-09-08-department-output-contract-design.md`, Layer 4 → Export.
- **Run tests per-suite with `-only-testing:`** — `xcodebuild test` exits 65 on a clean checkout because the XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates (CLAUDE.md landmine 3). That is not a regression; do not chase it.
- **No running `codepet.app`** while testing, and no sibling build mid-run — either kills the test host (`codepet-firestore-lock-blocks-tests`).
- **New `.swift` files need no project-file edit** — `PBXFileSystemSynchronizedRootGroup` means target membership follows the folder on disk (landmine 5).
- **Build team-signed:** `DEVELOPMENT_TEAM=YL72VTKBR7`, `CODE_SIGN_STYLE=Automatic`, `-allowProvisioningUpdates`. Adhoc breaks the keychain.
- **Filenames are ASCII-slugged** from the deliverable title, never the raw title — a title contains `/`, `:` and emoji, and a Vietnamese title contains diacritics.

---

### Task 1: The pure core and markdown kinds

`doc`, `legal`, `plan`, `checklist`, `text`, `other` all export as one `.md` file. This task also establishes `ExportFile`, the slug helper, and the dispatch every later task extends.

**Files:**
- Create: `codepet/Models/DeliverableExport.swift`
- Test: `codepetTests/DeliverableExportTests.swift`

**Interfaces:**
- Consumes: `Deliverable`, `DeliverableKind`, `DeliverablePayload`, `ChecklistItem`, `DocSection`, `PlanChange` (all in `codepet/Models/Deliverable.swift`).
- Produces:
  - `struct ExportFile { let name: String; let data: Data }`
  - `enum DeliverableExport` with:
    - `static func files(for d: Deliverable) -> [ExportFile]`
    - `static func slug(_ title: String, fallback: String = "deliverable") -> String`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DeliverableExportTests.swift`:

```swift
import XCTest
@testable import codepet

/// `DeliverableExport` is a pure function from a deliverable to file bytes, which is the
/// whole reason it is a type and not view code: a `WKWebView` or an `NSSavePanel` cannot be
/// asserted on, and these can.
final class DeliverableExportTests: XCTestCase {

    private func deliverable(
        _ kind: DeliverableKind,
        title: String = "Untitled",
        body: String = "body text",
        payload: DeliverablePayload? = nil
    ) -> Deliverable {
        Deliverable(kind: kind, title: title, body: body, payload: payload)
    }

    /// Some payload fixtures are DECODED from JSON rather than constructed.
    ///
    /// `SitePayload`, `CalendarItem` and `CalendarWeek` each declare their own
    /// `init(from decoder:)`, which **suppresses Swift's memberwise initialiser** — so
    /// `SitePayload(title:brand:…)` does not exist and will not compile. Decoding is also
    /// how these arrive in production, which makes it the more honest fixture.
    ///
    /// `ChecklistItem`, `DocSection`, `PlanChange`, `DmMessage`, `SheetInput`,
    /// `SheetPayload`, `SiteContent` and `CalendarPayload` declare no initialiser and DO
    /// have a memberwise init, so those are constructed directly below.
    private func payload(json: String) throws -> DeliverablePayload {
        try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
    }

    // MARK: - slug

    func testSlugStripsPathAndPunctuationThatBreaksAFilename() {
        XCTAssertEqual(DeliverableExport.slug("Q4 Pricing / Model: v2"), "q4-pricing-model-v2")
    }

    func testSlugFoldsVietnameseDiacriticsRatherThanDroppingTheName() {
        XCTAssertEqual(DeliverableExport.slug("Kế hoạch ra mắt"), "ke-hoach-ra-mat")
    }

    func testSlugFallsBackWhenNothingSurvives() {
        XCTAssertEqual(DeliverableExport.slug("///", fallback: "deliverable"), "deliverable")
    }

    // MARK: - markdown kinds

    func testDocExportsOneMarkdownFileNamedFromTheTitle() throws {
        let d = deliverable(.doc, title: "What the app is built on")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "what-the-app-is-built-on.md")
    }

    func testDocMarkdownLeadsWithTheCallBecauseTheViewerDoes() throws {
        let d = deliverable(.doc, title: "Stack", body: "ignored for doc",
                            payload: DeliverablePayload(
                                call: "Run on-device where the entry can stay.",
                                sections: [DocSection(h: "Why", p: "Privacy is the product.")],
                                next: ["Measure recall past 3k entries"]))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("# Stack\n\nRun on-device where the entry can stay."), text)
        XCTAssertTrue(text.contains("## Why"), text)
        XCTAssertTrue(text.contains("Privacy is the product."), text)
        XCTAssertTrue(text.contains("- Measure recall past 3k entries"), text)
    }

    func testChecklistExportsTickBoxesSoTheStateSurvivesTheFile() throws {
        let d = deliverable(.checklist, title: "Release rhythm",
                            payload: DeliverablePayload(items: [
                                ChecklistItem(t: "Tag the build", done: true),
                                ChecklistItem(t: "Notarise", done: false),
                            ]))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(text.contains("- [x] Tag the build"), text)
        XCTAssertTrue(text.contains("- [ ] Notarise"), text)
    }

    func testPlanExportsGoalStepsChangesVerifyAndRisk() throws {
        let d = deliverable(.plan, title: "Add export",
                            payload: DeliverablePayload(
                                goal: "Let a founder save a deliverable",
                                steps: ["Add the pure core", "Add the panel"],
                                changes: [PlanChange(area: "Library viewers", edit: "one export slot")],
                                verify: ["A saved .md opens in any editor"],
                                risks: "A title with a slash breaks the filename"))
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        for expected in ["Let a founder save a deliverable", "1. Add the pure core",
                         "Library viewers", "one export slot",
                         "A saved .md opens in any editor",
                         "A title with a slash breaks the filename"] {
            XCTAssertTrue(text.contains(expected), "missing \(expected) in:\n\(text)")
        }
    }

    /// A kind with no payload still exports — the body is the deliverable. `.legal` is the
    /// case that matters: its viewer reads only `body`, and the schema's `sections` is dead
    /// for it (see the spec's Layer 2 note).
    func testLegalAndTextFallBackToTheMarkdownBody() throws {
        for kind in [DeliverableKind.legal, .text, .other] {
            let d = deliverable(kind, title: "Deletion promise", body: "One tap. Permanent.")
            let files = DeliverableExport.files(for: d)
            XCTAssertEqual(files.count, 1, "\(kind)")
            XCTAssertEqual(files[0].name, "deletion-promise.md", "\(kind)")
            let text = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
            XCTAssertTrue(text.contains("One tap. Permanent."), "\(kind): \(text)")
        }
    }

    func testEveryKindProducesAtLeastOneFile() {
        for kind in DeliverableKind.allCases {
            let d = deliverable(kind, title: "Anything", body: "some body")
            XCTAssertFalse(DeliverableExport.files(for: d).isEmpty,
                           "\(kind) exported nothing — a founder would see a dead button")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DeliverableExportTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: FAIL to compile — "cannot find 'DeliverableExport' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Models/DeliverableExport.swift`:

```swift
// codepet/Models/DeliverableExport.swift
import Foundation

/// One file the founder is about to save: a filename and its bytes.
struct ExportFile {
    let name: String
    let data: Data
}

/// Turns a `Deliverable` into files on disk.
///
/// **Pure on purpose.** No AppKit, no view, no `NSSavePanel` — those live in
/// `DeliverableExporter`, the same split `AttachmentPicker` states for the panel it owns.
/// A viewer cannot be asserted on; this can, so every kind's rendering is a unit test.
///
/// `files(for:)` never returns an empty array. A kind whose payload is missing or malformed
/// falls back to the markdown `body`, because `body` is always written — the generator's
/// prompt says "ALWAYS write the markdown `body`" — and a founder pressing Export must never
/// get nothing.
enum DeliverableExport {

    /// A filename the filesystem will accept, from a title that may contain anything.
    ///
    /// Diacritics are FOLDED, not dropped: a Vietnamese title stripped of its accents is
    /// still recognisable ("ke-hoach-ra-mat"), whereas dropping the characters leaves "".
    static func slug(_ title: String, fallback: String = "deliverable") -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US"))
        var out = ""
        var lastWasDash = false
        for ch in folded {
            if ch.isASCII && (ch.isLetter || ch.isNumber) {
                out.append(ch)
                lastWasDash = false
            } else if !lastWasDash && !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? fallback : out
    }

    static func files(for d: Deliverable) -> [ExportFile] {
        let base = slug(d.title)
        switch d.kind {
        case .doc:
            return [md(base, docMarkdown(d))]
        case .checklist:
            return [md(base, checklistMarkdown(d))]
        case .plan:
            return [md(base, planMarkdown(d))]
        case .legal, .text, .other, .post, .email, .dms, .sheet, .calendar, .site, .screens:
            // Extended by later tasks; every one of these is markdown-safe today.
            return [md(base, titled(d, d.body))]
        }
    }

    // MARK: - builders

    private static func md(_ base: String, _ text: String) -> ExportFile {
        ExportFile(name: "\(base).md", data: Data(text.utf8))
    }

    private static func titled(_ d: Deliverable, _ body: String) -> String {
        "# \(d.title)\n\n\(body)\n"
    }

    private static func docMarkdown(_ d: Deliverable) -> String {
        guard let p = d.payload, let call = p.call, !call.isEmpty else {
            return titled(d, d.body)
        }
        var out = "# \(d.title)\n\n\(call)\n"
        for s in p.sections ?? [] {
            out += "\n## \(s.h)\n\n\(s.p)\n"
        }
        let next = p.next ?? []
        if !next.isEmpty {
            out += "\n## Next\n\n"
            for n in next { out += "- \(n)\n" }
        }
        return out
    }

    private static func checklistMarkdown(_ d: Deliverable) -> String {
        guard let items = d.payload?.items, !items.isEmpty else { return titled(d, d.body) }
        var out = "# \(d.title)\n\n"
        for i in items { out += "- [\(i.done ? "x" : " ")] \(i.t)\n" }
        return out
    }

    private static func planMarkdown(_ d: Deliverable) -> String {
        guard let p = d.payload, let goal = p.goal, !goal.isEmpty else {
            return titled(d, d.body)
        }
        var out = "# \(d.title)\n\n\(goal)\n"
        let steps = p.steps ?? []
        if !steps.isEmpty {
            out += "\n## Steps\n\n"
            for (i, s) in steps.enumerated() { out += "\(i + 1). \(s)\n" }
        }
        let changes = p.changes ?? []
        if !changes.isEmpty {
            out += "\n## Changes\n\n"
            for c in changes { out += "- **\(c.area)** — \(c.edit)\n" }
        }
        let verify = p.verify ?? []
        if !verify.isEmpty {
            out += "\n## Verify\n\n"
            for v in verify { out += "- \(v)\n" }
        }
        if let r = p.risks, !r.isEmpty { out += "\n## Risk\n\n\(r)\n" }
        return out
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, 9 tests.

- [ ] **Step 5: Prove the guards are real**

Break each guard in turn and confirm a specific test goes red, then restore:
1. In `slug`, change the diacritic fold to `title` unchanged → `testSlugFoldsVietnameseDiacriticsRatherThanDroppingTheName` fails.
2. In `checklistMarkdown`, always write `- [ ]` → `testChecklistExportsTickBoxesSoTheStateSurvivesTheFile` fails.
3. In `files(for:)`, `return []` for `.doc` → `testEveryKindProducesAtLeastOneFile` and two others fail.

A test that passes with and without the code it protects is not protecting anything.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-dept-outputs
git add codepet/Models/DeliverableExport.swift codepetTests/DeliverableExportTests.swift
git commit -F - <<'EOF'
Deliverables can become files: the pure core, and the markdown kinds

Copy to clipboard was the only way anything left Codepet — SiteViewer's
own comment said so ("No Share affordance, no Copy link"), which meant
the landing page Design renders could not be deployed and the business
plan Finance writes could not be sent.

This is the core the rest of export hangs off, and it is pure by design:
no AppKit, no view, no panel. A viewer cannot be asserted on and this
can, so every kind's rendering is a unit test. The panel comes in a
later task, isolated the way AttachmentPicker already isolates its own.

files(for:) never returns empty. A missing or malformed payload falls
back to the markdown body, because the generator's prompt guarantees a
body is always written and a founder pressing Export must never get
nothing.

Slugs FOLD diacritics rather than stripping them: a Vietnamese title
with the accents removed is still recognisable, where dropping the
characters leaves an empty filename.

Spec: docs/superpowers/specs/2026-09-08-department-output-contract-design.md
EOF
```

---

### Task 2: Sendable text kinds

`post`, `dms` and `email` are things the founder pastes somewhere. They export as `.txt`, and `dms` exports **one file per message** because each goes to a different person.

**Files:**
- Modify: `codepet/Models/DeliverableExport.swift`
- Modify: `codepetTests/DeliverableExportTests.swift`

**Interfaces:**
- Consumes: `ExportFile`, `DeliverableExport.files(for:)`, `DeliverableExport.slug(_:fallback:)` from Task 1; `DmMessage { name, note, msg }`.
- Produces: no new symbols — extends `files(for:)` dispatch.

- [ ] **Step 1: Write the failing test**

Append to `DeliverableExportTests`:

```swift
    // MARK: - sendable text

    func testPostExportsPlainTextNotMarkdown() throws {
        let d = deliverable(.post, title: "Launch post", body: "We built a journal that answers.")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "launch-post.txt")
        let text = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
        XCTAssertEqual(text, "We built a journal that answers.\n")
    }

    /// No `# Title` heading: a post is pasted into a composer, and a markdown heading pasted
    /// into X is a literal hash.
    func testPostCarriesNoMarkdownHeading() throws {
        let d = deliverable(.post, title: "Launch post", body: "Body only.")
        let text = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertFalse(text.contains("#"), text)
    }

    func testDmsExportsOneFilePerMessageBecauseEachGoesToSomeoneElse() throws {
        let d = deliverable(.dms, title: "Early access",
                            payload: DeliverablePayload(messages: [
                                DmMessage(name: "Lapsed journaler", note: "quit over streaks",
                                          msg: "We cut the streak counter. Want the first build?"),
                                DmMessage(name: "Privacy-first buyer", note: "asked about training",
                                          msg: "Nothing leaves your phone unless you ask."),
                            ]))
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].name, "early-access-1-lapsed-journaler.txt")
        XCTAssertEqual(files[1].name, "early-access-2-privacy-first-buyer.txt")
        let first = try XCTUnwrap(String(data: files[0].data, encoding: .utf8))
        XCTAssertTrue(first.contains("We cut the streak counter."), first)
        XCTAssertTrue(first.contains("quit over streaks"), "the note says why this target — keep it")
    }

    func testDmsWithNoMessagesStillExportsTheBody() throws {
        let d = deliverable(.dms, title: "Outreach", body: "the prose version")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "outreach.txt")
    }

    func testEmailExportsAsText() throws {
        let d = deliverable(.email, title: "Day 14 check-in", body: "How has the first fortnight been?")
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files[0].name, "day-14-check-in.txt")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DeliverableExportTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: FAIL — `launch-post.md` is produced where `launch-post.txt` was expected.

- [ ] **Step 3: Write minimal implementation**

In `DeliverableExport.swift`, replace the catch-all `case` in `files(for:)` with:

```swift
        case .post, .email:
            return [txt(base, d.body)]
        case .dms:
            return dmsFiles(d, base: base)
        case .legal, .text, .other, .sheet, .calendar, .site, .screens:
            return [md(base, titled(d, d.body))]
```

And add to the builders section:

```swift
    private static func txt(_ base: String, _ text: String) -> ExportFile {
        ExportFile(name: "\(base).txt", data: Data((text + "\n").utf8))
    }

    /// One file per message. A `dms` deliverable is four different conversations, and a
    /// single file would make the founder cut them apart by hand before sending any.
    ///
    /// The `note` is kept in the file. It is the reason this person is worth writing to,
    /// and it is the part the founder needs in front of them when they personalise the
    /// message — dropping it would export the words and lose the intent.
    private static func dmsFiles(_ d: Deliverable, base: String) -> [ExportFile] {
        let messages = d.payload?.messages ?? []
        guard !messages.isEmpty else { return [txt(base, d.body)] }
        return messages.enumerated().map { i, m in
            let who = slug(m.name, fallback: "recipient")
            let text = "To: \(m.name)\nWhy: \(m.note)\n\n\(m.msg)"
            return ExportFile(name: "\(base)-\(i + 1)-\(who).txt", data: Data((text + "\n").utf8))
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, 14 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet-dept-outputs
git add codepet/Models/DeliverableExport.swift codepetTests/DeliverableExportTests.swift
git commit -F - <<'EOF'
What you send exports as text, and DMs export one file each

post, dms and email are pasted into somebody else's composer, so they
export as .txt with no markdown heading — a "# Title" pasted into X is
a literal hash, not a heading.

dms exports one file per message rather than one file for the set. Four
messages in one file is four conversations the founder has to cut apart
before sending any of them. Each file keeps its `note`: that is the
reason the person is worth writing to, and it is what the founder needs
in front of them while personalising. Exporting the words and losing
the intent would be the wrong half.
EOF
```

---

### Task 3: `sheet` exports a spreadsheet with its formula

**Files:**
- Modify: `codepet/Models/DeliverableExport.swift`
- Modify: `codepetTests/DeliverableExportTests.swift`

**Interfaces:**
- Consumes: Task 1's helpers; `SheetPayload { price, waitlist, conversion, churn: SheetInput, summary: String? }`, `SheetInput { val, min, max, step: Double }`.
- Produces: no new public symbols.

- [ ] **Step 1: Write the failing test**

Append to `DeliverableExportTests`:

```swift
    // MARK: - sheet

    private func sheetPayload() -> DeliverablePayload {
        DeliverablePayload(sheet: SheetPayload(
            price: SheetInput(val: 6, min: 0, max: 20, step: 1),
            waitlist: SheetInput(val: 1200, min: 0, max: 5000, step: 50),
            conversion: SheetInput(val: 8, min: 0, max: 50, step: 1),
            churn: SheetInput(val: 6, min: 0, max: 30, step: 1),
            summary: "At $6 and 8% conversion the model clears cost."))
    }

    func testSheetExportsCsvNotMarkdown() {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "pricing-model.csv")
    }

    func testSheetCsvCarriesEveryInputWithItsRange() throws {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(csv.hasPrefix("input,value,min,max,step\n"), csv)
        XCTAssertTrue(csv.contains("price,6,0,20,1"), csv)
        XCTAssertTrue(csv.contains("waitlist,1200,0,5000,50"), csv)
        XCTAssertTrue(csv.contains("conversion,8,0,50,1"), csv)
        XCTAssertTrue(csv.contains("churn,6,0,30,1"), csv)
    }

    /// The point of exporting a model rather than a number: the reader can see how it was
    /// derived and disagree with it.
    func testSheetCsvCarriesTheDerivedOutputsAndTheirFormulas() throws {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(csv.contains("output,value,formula"), csv)
        XCTAssertTrue(csv.contains("subscribers,96,"), "1200 × 8% = 96 — got:\n\(csv)")
        XCTAssertTrue(csv.contains("mrr,576,"), "96 × $6 = 576 — got:\n\(csv)")
    }

    func testSheetCsvQuotesTheSummarySoACommaCannotSplitIt() throws {
        let d = deliverable(.sheet, title: "Pricing model", payload: sheetPayload())
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(csv.contains("\"At $6 and 8% conversion the model clears cost.\""), csv)
    }

    func testSheetWithNoPayloadFallsBackToMarkdown() {
        let d = deliverable(.sheet, title: "Pricing model", body: "prose only")
        XCTAssertEqual(DeliverableExport.files(for: d)[0].name, "pricing-model.md")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DeliverableExportTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: FAIL — `pricing-model.md` produced, `.csv` expected.

- [ ] **Step 3: Write minimal implementation**

In `files(for:)`, move `.sheet` out of the markdown group:

```swift
        case .sheet:
            return [sheetFile(d, base: base)]
        case .legal, .text, .other, .calendar, .site, .screens:
            return [md(base, titled(d, d.body))]
```

Add to the builders section:

```swift
    /// A model, not a number. The inputs carry their ranges so the reader can see what the
    /// author considered plausible, and the outputs carry their formulas so the reader can
    /// disagree with the derivation rather than only with the result.
    ///
    /// The two derived rows mirror `SheetViewer`'s own arithmetic. They are recomputed here
    /// rather than read off the view, because export must work on a deliverable that is not
    /// on screen.
    private static func sheetFile(_ d: Deliverable, base: String) -> ExportFile {
        guard let s = d.payload?.sheet else {
            return md(base, titled(d, d.body))
        }
        func n(_ v: Double) -> String {
            v == v.rounded() ? String(Int(v)) : String(format: "%.4g", v)
        }
        func row(_ name: String, _ i: SheetInput) -> String {
            "\(name),\(n(i.val)),\(n(i.min)),\(n(i.max)),\(n(i.step))\n"
        }

        var out = "input,value,min,max,step\n"
        out += row("price", s.price)
        out += row("waitlist", s.waitlist)
        out += row("conversion", s.conversion)
        out += row("churn", s.churn)

        let subscribers = (s.waitlist.val * s.conversion.val / 100).rounded()
        let mrr = subscribers * s.price.val
        out += "\noutput,value,formula\n"
        out += "subscribers,\(n(subscribers)),waitlist * conversion / 100\n"
        out += "mrr,\(n(mrr)),subscribers * price\n"

        if let summary = s.summary, !summary.isEmpty {
            out += "\nsummary,\(csvQuoted(summary))\n"
        }
        return ExportFile(name: "\(base).csv", data: Data(out.utf8))
    }

    /// A CSV field that may contain a comma, a quote or a newline. Without this a summary
    /// sentence silently becomes several columns.
    private static func csvQuoted(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, 19 tests.

- [ ] **Step 5: Prove the quoting guard is real**

Change `csvQuoted` to return `s` unchanged. `testSheetCsvQuotesTheSummarySoACommaCannotSplitIt` must fail. Restore it.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-dept-outputs
git add codepet/Models/DeliverableExport.swift codepetTests/DeliverableExportTests.swift
git commit -F - <<'EOF'
A model exports as a model: inputs with ranges, outputs with formulas

sheet exports .csv rather than prose. The inputs carry min/max/step so
a reader can see what the author thought plausible, and the derived rows
carry their formula so a reader can disagree with the derivation instead
of only with the number. That is the difference between exporting a
model and exporting its output.

The arithmetic is recomputed here rather than read off SheetViewer,
because export has to work on a deliverable that is not on screen.

Summary text is CSV-quoted. Without it one sentence with a comma
silently becomes several columns, which is the classic way a CSV export
looks fine and is wrong.
EOF
```

---

### Task 4: `calendar` exports a spreadsheet and a real calendar file

**Files:**
- Modify: `codepet/Models/DeliverableExport.swift`
- Modify: `codepetTests/DeliverableExportTests.swift`

**Interfaces:**
- Consumes: Task 1 and Task 3 helpers; `CalendarPayload { weeks: [CalendarWeek] }`, `CalendarWeek { label, items: [CalendarItem] }`, `CalendarItem { day, kind, body }`.
- Produces: no new public symbols. Two files per calendar.

- [ ] **Step 1: Write the failing test**

Append to `DeliverableExportTests`:

```swift
    // MARK: - calendar

    /// Decoded, not constructed — `CalendarWeek` and `CalendarItem` both declare
    /// `init(from:)` and therefore have no memberwise initialiser. See `payload(json:)`.
    private func calendarPayload() throws -> DeliverablePayload {
        try payload(json: """
        {"calendar": {"weeks": [
          {"label": "Week 1", "items": [
            {"day": "Mon", "kind": "thread", "body": "Why I'm building a journal that answers"},
            {"day": "Fri", "kind": "post", "body": "What we refuse to do on a bad night"}
          ]},
          {"label": "Week 2", "items": [
            {"day": "Tue", "kind": "post", "body": "On-device vs server"}
          ]}
        ]}}
        """)
    }

    func testCalendarExportsBothASpreadsheetAndACalendarFile() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let names = DeliverableExport.files(for: d).map(\.name)
        XCTAssertEqual(names, ["content-calendar.csv", "content-calendar.ics"])
    }

    /// Every field is quoted, including week/day/kind. They are model-authored strings and
    /// can contain a comma; a reader never sees the difference and a stray comma cannot shift
    /// a column.
    func testCalendarCsvHasOneRowPerItemWithItsWeek() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let csv = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(csv.hasPrefix("week,day,kind,body\n"), csv)
        XCTAssertEqual(csv.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 4,
                       "header + 3 items — got:\n\(csv)")
        XCTAssertTrue(csv.contains("\"Week 1\",\"Mon\",\"thread\",\"Why I'm building a journal that answers\""), csv)
    }

    /// An .ics with no VEVENT is a file that opens to nothing.
    func testIcsWrapsEveryItemAsAnEvent() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let ics = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[1].data, encoding: .utf8))
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"), ics)
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"), ics)
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 3, ics)
        XCTAssertTrue(ics.contains("SUMMARY:Why I'm building a journal that answers"), ics)
    }

    /// The founder's calendar app must not reject the file. Every VEVENT needs a UID.
    func testEveryEventCarriesAUid() throws {
        let d = deliverable(.calendar, title: "Content calendar", payload: try calendarPayload())
        let ics = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[1].data, encoding: .utf8))
        XCTAssertEqual(ics.components(separatedBy: "UID:").count - 1, 3, ics)
    }

    func testCalendarWithNoPayloadFallsBackToMarkdown() {
        let d = deliverable(.calendar, title: "Content calendar", body: "prose only")
        XCTAssertEqual(DeliverableExport.files(for: d).map(\.name), ["content-calendar.md"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DeliverableExportTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: FAIL — one `.md` file produced, two files expected.

- [ ] **Step 3: Write minimal implementation**

In `files(for:)`:

```swift
        case .calendar:
            return calendarFiles(d, base: base)
        case .legal, .text, .other, .site, .screens:
            return [md(base, titled(d, d.body))]
```

Add to the builders section:

```swift
    /// Two files, because a content calendar is read two ways: as a table to edit, and as
    /// events to drop into the calendar the founder actually lives in.
    ///
    /// **The .ics carries no dates.** `CalendarItem.day` is "Mon", not 2026-09-14 — the
    /// generator produces a relative schedule, and inventing absolute dates would be
    /// inventing data (the rule `PostViewer` states: never render what the app does not
    /// know). Each event is therefore an all-day VEVENT on a floating day counted from the
    /// export date, and the description says so. A founder who wants real dates moves them
    /// once, in their own calendar.
    private static func calendarFiles(_ d: Deliverable, base: String) -> [ExportFile] {
        guard let weeks = d.payload?.calendar?.weeks, !weeks.isEmpty else {
            return [md(base, titled(d, d.body))]
        }

        var csv = "week,day,kind,body\n"
        for w in weeks {
            for i in w.items {
                csv += "\(csvQuoted(w.label)),\(csvQuoted(i.day)),\(csvQuoted(i.kind)),\(csvQuoted(i.body))\n"
            }
        }
        // Plain values read better than quoted ones where the field cannot contain a comma,
        // but week/day/kind are model-authored strings and can. Quote them all; a reader
        // never sees the difference and a stray comma cannot shift a column.

        var ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Murror//Codepet//EN\r\n"
        var n = 0
        for (wi, w) in weeks.enumerated() {
            for i in w.items {
                n += 1
                let day = icsDate(weekIndex: wi, dayLabel: i.day)
                ics += "BEGIN:VEVENT\r\n"
                ics += "UID:\(d.id)-\(n)@codepet.murror.app\r\n"
                ics += "DTSTART;VALUE=DATE:\(day)\r\n"
                ics += "SUMMARY:\(icsEscaped(i.body))\r\n"
                ics += "DESCRIPTION:\(icsEscaped("\(w.label) · \(i.kind) — day is relative to export"))\r\n"
                ics += "END:VEVENT\r\n"
            }
        }
        ics += "END:VCALENDAR\r\n"

        return [ExportFile(name: "\(base).csv", data: Data(csv.utf8)),
                ExportFile(name: "\(base).ics", data: Data(ics.utf8))]
    }

    /// A floating all-day date: today, plus the week offset, plus the weekday the label names.
    /// An unrecognised label lands on the Monday of its week rather than failing the export.
    private static func icsDate(weekIndex: Int, dayLabel: String) -> String {
        let offsets = ["mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6]
        let key = dayLabel.lowercased().prefix(3)
        let within = offsets[String(key)] ?? 0
        let days = weekIndex * 7 + within
        let date = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: days, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    /// RFC 5545 text escaping: backslash, semicolon, comma and newline.
    private static func icsEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, 24 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet-dept-outputs
git add codepet/Models/DeliverableExport.swift codepetTests/DeliverableExportTests.swift
git commit -F - <<'EOF'
A content calendar exports as a table and as calendar events

Two files, because a calendar is read two ways: a .csv to edit, and an
.ics to drop into the calendar the founder actually lives in.

The .ics carries no real dates, deliberately. CalendarItem.day is "Mon",
not a date — the generator produces a relative schedule, so absolute
dates would be invented data. That is the rule PostViewer already
states, where fake engagement counts were deleted because they are
indistinguishable from real ones. Each event is an all-day floating
VEVENT counted from the export date and its DESCRIPTION says so.

Every VEVENT carries a UID; without one, calendar apps reject the file.
EOF
```

---

### Task 5: `site` exports a page that can be hosted

`SiteViewer` already builds a complete HTML document to render the page in its `WKWebView`. Export reuses that builder rather than writing a second one that can drift from what the founder approved.

**Files:**
- Modify: `codepet/Models/DeliverableExport.swift`
- Modify: `codepetTests/DeliverableExportTests.swift`
- Read: `codepet/Views/Library/DeliverableViewers.swift:754-800` (`SiteViewer.buildHTML`)

**Interfaces:**
- Consumes: `SiteViewer.buildHTML(_ payload: SitePayload) -> String` — a static already used by the viewer's `html` property.
- Produces: no new public symbols.

- [ ] **Step 1: Confirm the builder is still reachable**

Run:
```bash
cd ~/Developer/codepet-dept-outputs
grep -n "func buildHTML" codepet/Views/Library/DeliverableViewers.swift
```
Expected: `867:    static func buildHTML(_ p: SitePayload) -> String {` — already non-private and
already static, so no change is needed. If a later refactor has made it `private`, drop the
`private` and add this comment above it:

```swift
    /// Not private: `DeliverableExport` renders the same document to disk. One builder, so an
    /// exported page cannot drift from the page the founder approved on screen.
```

- [ ] **Step 2: Write the failing test**

Append to `DeliverableExportTests`:

```swift
    // MARK: - site

    /// Decoded, not constructed — `SitePayload` declares `init(from:)` and so has no
    /// memberwise initialiser. `title`, `brand`, `headline`, `ctaPrimary`, `finalTitle` and
    /// `finalCta` are REQUIRED anchors that throw when absent; everything else is soft.
    private func sitePayload() throws -> DeliverablePayload {
        try payload(json: """
        {"site": {
          "title": "Murror — a journal that answers",
          "brand": "Murror",
          "headline": "A journal that answers",
          "sub": "Private by design. Nothing leaves your phone unless you ask.",
          "ctaPrimary": "Get early access",
          "howEyebrow": "How it works",
          "howTitle": "Three steps",
          "steps": [{"h": "Write", "p": "Say anything."}],
          "featEyebrow": "Why",
          "featTitle": "What makes it different",
          "features": [{"h": "No streaks", "p": "We cut them."}],
          "finalTitle": "Start tonight",
          "finalCta": "Get early access",
          "accent": "80C830",
          "footNote": "Murror"
        }}
        """)
    }

    func testSiteExportsOneHtmlFile() throws {
        let d = deliverable(.site, title: "Landing page", payload: try sitePayload())
        let files = DeliverableExport.files(for: d)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].name, "landing-page.html")
    }

    /// Ready to host means a complete document, not a fragment.
    func testExportedSiteIsACompleteDocument() throws {
        let d = deliverable(.site, title: "Landing page", payload: try sitePayload())
        let html = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertTrue(html.lowercased().contains("<!doctype html"), String(html.prefix(200)))
        XCTAssertTrue(html.contains("</html>"), String(html.suffix(200)))
        XCTAssertTrue(html.contains("A journal that answers"), "the headline is missing")
    }

    /// The exported file and the on-screen page come from ONE builder. If this ever fails,
    /// export has grown a second renderer and the two can disagree.
    func testExportedHtmlIsByteIdenticalToWhatTheViewerRenders() throws {
        let fixture = try sitePayload()
        let p = try XCTUnwrap(fixture.site)
        let d = deliverable(.site, title: "Landing page", payload: fixture)
        let exported = try XCTUnwrap(String(data: DeliverableExport.files(for: d)[0].data, encoding: .utf8))
        XCTAssertEqual(exported, SiteViewer.buildHTML(p))
    }

    func testSiteWithNoPayloadFallsBackToMarkdown() {
        let d = deliverable(.site, title: "Landing page", body: "copy only")
        XCTAssertEqual(DeliverableExport.files(for: d)[0].name, "landing-page.md")
    }
```

- [ ] **Step 3: Run test to verify it fails**

Run:
```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DeliverableExportTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: FAIL — `landing-page.md` produced, `.html` expected.

- [ ] **Step 4: Write minimal implementation**

In `files(for:)`:

```swift
        case .site:
            return [siteFile(d, base: base)]
        case .legal, .text, .other, .screens:
            return [md(base, titled(d, d.body))]
```

Add to the builders section:

```swift
    /// One `.html` file, ready to open in a browser or drop on a host.
    ///
    /// **Reuses `SiteViewer.buildHTML`.** The spec called for an ".html folder"; a single
    /// self-contained document satisfies the intent with less machinery, because the builder
    /// already inlines its own styles — there are no sibling assets to place beside it.
    /// Sharing the builder is the load-bearing part: a second renderer here could drift from
    /// the page the founder looked at and approved.
    private static func siteFile(_ d: Deliverable, base: String) -> ExportFile {
        guard let site = d.payload?.site else {
            return md(base, titled(d, d.body))
        }
        return ExportFile(name: "\(base).html", data: Data(SiteViewer.buildHTML(site).utf8))
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 3.
Expected: PASS, 28 tests.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-dept-outputs
git add codepet/Models/DeliverableExport.swift codepetTests/DeliverableExportTests.swift codepet/Views/Library/DeliverableViewers.swift
git commit -F - <<'EOF'
A landing page exports as a page you can host

site exports one self-contained .html through SiteViewer.buildHTML —
the same builder the WKWebView already renders. Sharing it is the
load-bearing part: a second renderer could drift from the page the
founder looked at and approved, and a test asserts the exported bytes
equal what the viewer produces.

The spec asked for an ".html folder". One document satisfies the intent
with less machinery: buildHTML inlines its own styles, so there are no
sibling assets to place beside it.
EOF
```

---

### Task 6: The founder can press Export

Everything above is unreachable until the frame offers it. This task adds the AppKit seam and the button, and wires every viewer.

**Files:**
- Create: `codepet/Views/Library/DeliverableExporter.swift`
- Modify: `codepet/Views/Library/DeliverableStyle.swift` (the `DeliverableFrame` struct and its `actionButton`)
- Modify: `codepet/Views/Library/DeliverableViewers.swift` (add `export:` at each `DeliverableFrame` call site)
- Test: `codepetTests/DeliverableExporterTests.swift`

**Interfaces:**
- Consumes: `ExportFile`, `DeliverableExport.files(for:)` from Tasks 1–5.
- Produces:
  - `enum DeliverableExporter` with `static func write(_ files: [ExportFile], to directory: URL) throws -> [URL]` and `static func save(_ d: Deliverable)`
  - `DeliverableFrame.export: Deliverable?` (defaults `nil`)

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DeliverableExporterTests.swift`:

```swift
import XCTest
@testable import codepet

/// The panel itself cannot be tested — the same limit `AttachmentPicker` records for its
/// `NSOpenPanel`. `write(_:to:)` is split out for exactly that reason: it is everything the
/// panel does once the founder has chosen, and it runs from a temp directory.
final class DeliverableExporterTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testWritesEveryFileAndReturnsWhereTheyLanded() throws {
        let files = [ExportFile(name: "a.md", data: Data("alpha".utf8)),
                     ExportFile(name: "b.txt", data: Data("beta".utf8))]
        let urls = try DeliverableExporter.write(files, to: dir)
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(try String(contentsOf: urls[0], encoding: .utf8), "alpha")
        XCTAssertEqual(try String(contentsOf: urls[1], encoding: .utf8), "beta")
    }

    /// Exporting the same deliverable twice must not silently destroy the first file.
    func testASecondExportDoesNotOverwriteTheFirst() throws {
        let files = [ExportFile(name: "plan.md", data: Data("first".utf8))]
        _ = try DeliverableExporter.write(files, to: dir)
        let second = try DeliverableExporter.write(
            [ExportFile(name: "plan.md", data: Data("second".utf8))], to: dir)
        XCTAssertEqual(second[0].lastPathComponent, "plan-2.md")
        let firstURL = dir.appendingPathComponent("plan.md")
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "first")
    }

    /// A name cannot escape the directory the founder chose.
    func testANameCannotClimbOutOfTheChosenDirectory() throws {
        let urls = try DeliverableExporter.write(
            [ExportFile(name: "../escaped.md", data: Data("x".utf8))], to: dir)
        XCTAssertEqual(urls[0].deletingLastPathComponent().standardizedFileURL,
                       dir.standardizedFileURL)
    }

    func testEndToEndADeliverableBecomesFilesOnDisk() throws {
        let d = Deliverable(kind: .checklist, title: "Release rhythm", body: "",
                            payload: DeliverablePayload(items: [
                                ChecklistItem(t: "Tag the build", done: false)]))
        let urls = try DeliverableExporter.write(DeliverableExport.files(for: d), to: dir)
        XCTAssertEqual(urls[0].lastPathComponent, "release-rhythm.md")
        let text = try String(contentsOf: urls[0], encoding: .utf8)
        XCTAssertTrue(text.contains("- [ ] Tag the build"), text)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DeliverableExporterTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: FAIL to compile — "cannot find 'DeliverableExporter' in scope".

- [ ] **Step 3: Write the exporter**

Create `codepet/Views/Library/DeliverableExporter.swift`:

```swift
// codepet/Views/Library/DeliverableExporter.swift
import AppKit
import Foundation

/// Saves a deliverable's files to disk.
///
/// Lives beside the viewers because it is the same kind of thing `AttachmentPicker` is: the
/// one place an AppKit panel is allowed to exist, so no view has to know about AppKit. All
/// the rendering happens in `DeliverableExport`, which is pure and fully tested; this file
/// is the panel plus the write.
///
/// **The app writes and never uploads.** There is no network call here and there must not be
/// one: export is the founder moving their own work to their own disk.
enum DeliverableExporter {

    /// Write files into a directory the founder chose, returning where each landed.
    ///
    /// Split out from `save(_:)` so it is testable — the panel is the only part a test
    /// cannot drive, which is the limit `AttachmentPicker` already records for its own.
    ///
    /// Never overwrites. A repeat export becomes `plan-2.md`, because the founder pressing
    /// Export twice is asking for a second copy, not asking to destroy the first.
    /// A name is reduced to its last path component first, so nothing can be written
    /// outside the chosen directory.
    static func write(_ files: [ExportFile], to directory: URL) throws -> [URL] {
        var out: [URL] = []
        for f in files {
            let safe = (f.name as NSString).lastPathComponent
            let url = try unusedURL(in: directory, name: safe.isEmpty ? "deliverable" : safe)
            try f.data.write(to: url)
            out.append(url)
        }
        return out
    }

    private static func unusedURL(in directory: URL, name: String) throws -> URL {
        let fm = FileManager.default
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            n += 1
            let next = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            candidate = directory.appendingPathComponent(next)
        }
        return candidate
    }

    /// Ask the founder where to put it, then write.
    ///
    /// One file gets a save panel with the name pre-filled; several get a directory picker,
    /// because `dms` and `calendar` produce a set and asking once per file would be four
    /// panels for one press.
    @MainActor
    static func save(_ d: Deliverable) {
        let files = DeliverableExport.files(for: d)
        guard !files.isEmpty else { return }

        if files.count == 1 {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = files[0].name
            panel.prompt = "Export"
            panel.message = "Save \(d.title)"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? files[0].data.write(to: url)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Save \(files.count) files from \(d.title)"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        _ = try? write(files, to: dir)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, 4 tests.

- [ ] **Step 5: Add the frame slot and the button**

In `codepet/Views/Library/DeliverableStyle.swift`, add the stored property to `DeliverableFrame` immediately after `var action: DeliverableAction = .none`:

```swift
    /// The deliverable to export, or nil for a frame that offers no export.
    ///
    /// A separate slot rather than another `DeliverableAction` case, because copy and export
    /// are two different affordances the founder may want in either order — not two variants
    /// of one. Keeping it separate also leaves all seven existing `action:` call sites alone.
    var export: Deliverable? = nil
```

Then replace `actionButton` with:

```swift
    @ViewBuilder private var actionButton: some View {
        HStack(spacing: 10) {
            switch action {
            case .none:
                EmptyView()
            case let .copy(text):
                DeliverableCopyButton(text: text)
            case let .copyLabelled(text, label, done):
                DeliverableCopyButton(text: text, label: label, doneLabel: done)
            }
            if let export {
                DeliverableExportButton(deliverable: export)
            }
        }
    }
```

Add at the end of `DeliverableStyle.swift`:

```swift
/// Save this deliverable to disk. Sits beside Copy in every viewer's frame.
///
/// Labelled "Export", not "Save" — nothing in Codepet is unsaved (approving files it), so
/// "Save" would imply work is at risk. What this does is move a copy out of the app.
struct DeliverableExportButton: View {
    let deliverable: Deliverable
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        Button {
            DeliverableExporter.save(deliverable)
        } label: {
            Text(lang == .vi ? "Xuất" : "Export")
                .font(.pixelSystem(size: DeliverableStyle.eyebrow, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundColor(CodepetTheme.accentPurple)
        .help(lang == .vi ? "Lưu ra tệp" : "Save to a file")
    }
}
```

- [ ] **Step 6: Wire every viewer**

In `codepet/Views/Library/DeliverableViewers.swift`, add `export: deliverable,` beside each of the seven existing `action:` arguments, and add `export: deliverable` to any `DeliverableFrame` that currently passes no action. Find them all:

```bash
cd ~/Developer/codepet-dept-outputs
grep -n "DeliverableFrame(" codepet/Views/Library/DeliverableViewers.swift
```

Every match must end up with an `export:` argument. Example — `ChecklistViewer` around line 53 becomes:

```swift
        DeliverableFrame(eyebrow: lang == .vi ? "Danh sách" : "Checklist",
                         action: .copy(copyText),
                         export: deliverable) {
```

- [ ] **Step 7: Build and confirm every viewer offers it**

Run:
```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild build -project codepet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

Then confirm no frame was missed:
```bash
cd ~/Developer/codepet-dept-outputs
echo "frames: $(grep -c 'DeliverableFrame(' codepet/Views/Library/DeliverableViewers.swift)"
echo "exports: $(grep -c 'export: deliverable' codepet/Views/Library/DeliverableViewers.swift)"
```
Expected: the two counts are equal.

- [ ] **Step 8: Run the neighbouring suites**

Export changed a frame nine viewers share, so sweep what renders through it:
```bash
cd ~/Developer/codepet-dept-outputs
xcodebuild test -project codepet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DeliverableExportTests \
  -only-testing:codepetTests/DeliverableExporterTests \
  -only-testing:codepetTests/DemoProjectParityTests \
  -only-testing:codepetTests/DemoProjectEightDepartmentsTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates 2>&1 | tail -20
```
Expected: all pass, 0 failures.

- [ ] **Step 9: Look at it, since tests cannot**

Build team-signed, launch the Murror demo, open the Library, and confirm Export sits beside Copy and produces a file:

```bash
cd ~/Developer/codepet-dept-outputs
open ~/Library/Developer/Xcode/DerivedData/CodePet-*/Build/Products/Debug/codepet.app \
  --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
```

Check, on screen: the Library shows all eight departments; opening a `sheet` artifact shows **Copy** and **Export**; pressing Export opens a save panel; the saved `.csv` opens with the inputs and the formula rows. Then open the `site` artifact and confirm the exported `.html` opens in a browser as the same page.

Delete any screenshots taken afterwards — full-screen captures accumulate.

- [ ] **Step 10: Commit**

```bash
cd ~/Developer/codepet-dept-outputs
git add codepet/Views/Library/DeliverableExporter.swift \
        codepet/Views/Library/DeliverableStyle.swift \
        codepet/Views/Library/DeliverableViewers.swift \
        codepetTests/DeliverableExporterTests.swift
git commit -F - <<'EOF'
The founder can press Export

DeliverableFrame gains an `export:` slot beside its existing `action:`,
so Copy and Export sit together. A separate slot rather than another
DeliverableAction case: copy and export are two affordances a founder
may want in either order, not two variants of one — and it leaves all
seven existing action: call sites untouched.

The frame's own comment warned that "widening a shared API to serve one
kind is the wrong trade". Export is the case that inverts it: it serves
every kind, which is exactly why widening the shared frame is right
here.

DeliverableExporter owns the panel and nothing else, the split
AttachmentPicker states for its NSOpenPanel — so the rendering stays
pure and tested and only the panel is untestable. One file gets a save
panel; a set (dms, calendar) gets a directory picker, because four
panels for one press is not a feature.

Never overwrites: a repeat export becomes plan-2.md. Pressing Export
twice asks for a second copy, not for the first to be destroyed. A
filename is reduced to its last path component, so nothing can be
written outside the directory the founder chose.

Labelled "Export", not "Save": approving already files a deliverable, so
"Save" would imply the work is at risk.
EOF
```

---

## Self-review

**Spec coverage.** The spec's export table maps to tasks as follows: `doc`/`legal`/`plan`/`checklist` → Task 1; `post`/`dms`/`email` → Task 2; `sheet` → Task 3; `calendar` → Task 4; `site` → Task 5; the `action:` slot and `NSSavePanel` → Task 6. **Two rows are deliberately not covered and are named in Global Constraints:** `.pdf` for the doc family and `screens` → `.png`, both of which need `ImageRenderer` over a live view. `bizplan` does not exist until phase 4, and falls through to the markdown default meanwhile.

**Deviation from the spec, stated.** The spec says `site` exports "an `.html` folder"; Task 5 writes a single self-contained `.html` because `SiteViewer.buildHTML` inlines its own styles and there are no sibling assets. The intent — ready to host — is met.

**Type consistency.** `ExportFile { name, data }`, `DeliverableExport.files(for:)`, `DeliverableExport.slug(_:fallback:)`, `DeliverableExporter.write(_:to:)`, `DeliverableExporter.save(_:)` and `DeliverableFrame.export` are spelled identically everywhere they appear. `csvQuoted` is introduced in Task 3 and reused in Task 4 — Task 4 must not redefine it.

**Ordering.** Tasks 1–5 are pure and need no build of the app; Task 6 is the only one touching views, and is last so the founder-visible change lands on top of tested rendering.
