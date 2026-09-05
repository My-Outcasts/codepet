# Site Open-In-Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A founder can open a produced landing page in their real browser.

**Architecture:** One tiny pure helper (`SiteExport`) that names and writes the file, plus one button inside `SiteViewer`'s own content. `DeliverableFrame`'s shared `action:` API is deliberately NOT extended.

**Tech Stack:** Swift 5, SwiftUI, AppKit (`NSWorkspace`), XCTest, Xcode 26.2.

**Spec:** `docs/superpowers/specs/2026-09-04-site-open-in-browser-design.md`

## Global Constraints

- **Do NOT extend `DeliverableAction` or `DeliverableFrame`.** That frame's single `action:` is used by 9 viewers (`DeliverableViewers.swift`) and 13 deliverable kinds. Adding a second action slot to serve one kind changes a shared API for every one of them. The new button goes in `SiteViewer`'s own content, in the existing `HStack` beside the Preview/Code `Picker`.
- **Copy HTML stays exactly as it is** — `action: .copyLabelled(html, label:done:)` on the frame. Do not move or relabel it.
- **The file's name is derived from the deliverable id**, never random and never timestamped, so opening the same page twice replaces one file instead of littering the temp directory.
- **The label is "Open in browser", not "Open".** The chat card already carries an **Open the live page** cue that routes to this in-app viewer; two different "Open"s meaning two different destinations on one path is the confusion this avoids.
- **Bilingual.** en `Open in browser` / vi `Mở trong trình duyệt`. A missing translation renders an English string in a Vietnamese UI.
- **Fail-soft, and visible.** A failed write must not trap and must not silently do nothing. Never `try!`.
- **`file://` is not shareable, and nothing in the UI may imply it is.** No "Share", no "Copy link".
- Commit with `git commit -F <file>`, never `-m`.
- **Never `git stash` bare** — the stash stack is shared across worktrees and holds another session's entry. Use a temporary WIP commit.
- `xcodebuild test` exits 65 for unrelated reasons. **Never judge pass/fail from the exit code** — read `xcrun xcresulttool get test-results summary`. A zero passed-count is a failure, not a pass.
- **Before any `xcodebuild test`, stop the app:**

```bash
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}')
[ -n "$PID" ] && kill "$PID" && sleep 2
ps -eo pid,comm | awk '$2 ~ /codepet$/ {print "STILL RUNNING",$1}'
```

  Last line must print nothing. Never `pkill -f codepet`.

---

### Task 1: `SiteExport` — naming and writing, as pure functions

**Files:**
- Create: `codepet/Services/SiteExport.swift`
- Test: `codepetTests/SiteExportTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `SiteExport.fileURL(forDeliverableId: String) -> URL`, `SiteExport.write(html: String, to url: URL) throws`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/SiteExportTests.swift`:

```swift
// codepetTests/SiteExportTests.swift
import XCTest
@testable import codepet

/// Guards on a produced landing page being able to leave the app.
///
/// `SiteViewer` had exactly two affordances — a Preview/Code picker and Copy HTML — over an
/// in-app `WKWebView` fed an HTML string that was never written anywhere. So a founder could
/// look at their page in a dock column or paste raw markup onto the clipboard, and had no way
/// to open it in a browser. Reported by the founder, 4 Sep.
final class SiteExportTests: XCTestCase {

    /// Derived, not random: opening the same page twice must replace one file rather than
    /// litter the temp directory, and a browser reload must show the current draft.
    func testTheFilenameIsDerivedFromTheDeliverableId() {
        let a = SiteExport.fileURL(forDeliverableId: "demo-mur-site")
        let b = SiteExport.fileURL(forDeliverableId: "demo-mur-site")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.lastPathComponent.contains("demo-mur-site"), a.lastPathComponent)
        XCTAssertEqual(a.pathExtension, "html")
    }

    func testDifferentDeliverablesGetDifferentFiles() {
        XCTAssertNotEqual(SiteExport.fileURL(forDeliverableId: "a"),
                          SiteExport.fileURL(forDeliverableId: "b"))
    }

    /// **The one that matters for safety.** Ids are UUIDs in production and `demo-mur-site` in
    /// fixtures, but an id is a `String` and nothing in the type system stops a future one
    /// containing a path separator. `../../etc/passwd.html` must not escape the directory.
    func testAnIdWithPathSeparatorsCannotEscapeTheDirectory() {
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        for nasty in ["../escape", "a/b/c", "..", "/absolute", "with space", ""] {
            let url = SiteExport.fileURL(forDeliverableId: nasty).standardizedFileURL
            XCTAssertTrue(url.deletingLastPathComponent().path.hasPrefix(tmp),
                          "\(nasty) escaped to \(url.path)")
            XCTAssertEqual(url.pathExtension, "html", nasty)
        }
    }

    func testWritingProducesExactlyTheHTMLGiven() throws {
        let url = SiteExport.fileURL(forDeliverableId: "write-test")
        defer { try? FileManager.default.removeItem(at: url) }
        let html = "<!doctype html><html><body>hi</body></html>"
        try SiteExport.write(html: html, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), html)
    }

    func testWritingIsIdempotentAndOverwrites() throws {
        let url = SiteExport.fileURL(forDeliverableId: "overwrite-test")
        defer { try? FileManager.default.removeItem(at: url) }
        try SiteExport.write(html: "<p>first</p>", to: url)
        try SiteExport.write(html: "<p>second</p>", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "<p>second</p>")
    }

    /// Fail-soft: an unwritable destination throws so the caller can surface an error. It must
    /// never trap — a founder pressing a button should not crash the app.
    func testAnUnwritableDestinationThrows() {
        let bad = URL(fileURLWithPath: "/System/definitely-not-writable/x.html")
        XCTAssertThrowsError(try SiteExport.write(html: "<p>x</p>", to: bad))
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
  -only-testing:codepetTests/SiteExportTests test 2>&1 | tail -12
```

Expected: FAIL — `cannot find 'SiteExport' in scope`.

- [ ] **Step 3: Create the helper**

Create `codepet/Services/SiteExport.swift`:

```swift
// codepet/Services/SiteExport.swift
import Foundation

/// Writing a produced landing page somewhere a browser can open it.
///
/// **Why this exists.** `SiteViewer` rendered the page in an in-app `WKWebView` from an HTML
/// string and never wrote it anywhere, so a founder could look at their own landing page inside
/// a dock column or copy raw markup, and could not open it in a browser. There is no
/// `NSWorkspace.shared.open` anywhere near the deliverable path.
///
/// Split from the view so the naming and the failure path are testable without `NSWorkspace`
/// and without launching a browser. The view keeps only the `open` call, which is untestable by
/// nature and is therefore the only untested line.
enum SiteExport {

    /// A stable per-deliverable location in the temp directory.
    ///
    /// **Derived from the id, not random and not timestamped**, so opening the same page twice
    /// replaces one file instead of accumulating them, and a browser reload after a Redo shows
    /// the current draft.
    ///
    /// **Sanitised, because an id is only a `String`.** Ids are UUIDs in production and
    /// `demo-mur-site` in fixtures, and nothing in the type system stops a future one carrying
    /// a path separator. Anything outside a safe set becomes `-`, so the result cannot climb
    /// out of the temp directory. An empty id still yields a valid filename.
    static func fileURL(forDeliverableId id: String) -> URL {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let safe = String(id.map { allowed.contains($0) ? $0 : "-" })
        let name = safe.isEmpty ? "site" : safe
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("codepet-site-\(name)")
            .appendingPathExtension("html")
    }

    /// Write the page, replacing whatever was there. Throws rather than trapping: a founder
    /// pressing a button must never crash the app, and the caller surfaces the error.
    static func write(html: String, to url: URL) throws {
        try Data(html.utf8).write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
rm -rf /tmp/se1.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/SiteExportTests \
  -resultBundlePath /tmp/se1.xcresult test > /tmp/se1.log 2>&1
grep -E '^/Users.*error:' /tmp/se1.log | head -5
xcrun xcresulttool get test-results summary --path /tmp/se1.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 6`.

If `testAnUnwritableDestinationThrows` fails because `/System/...` is somehow writable in this environment, change the bad URL to a path inside a file rather than a directory (e.g. append a component to an existing FILE path) — that is guaranteed to fail. Record the change in your report.

- [ ] **Step 5: Commit**

```bash
cat > /tmp/c-se1.txt <<'EOF'
feat(library): SiteExport — name and write a page a browser can open

`SiteViewer` rendered the landing page from an HTML string in an in-app web
view and never wrote it anywhere, so the only ways to see a produced page were
a 620pt dock column or pasting raw markup somewhere. No export, no file, no
URL.

Pure by design: the naming and the write are testable without NSWorkspace and
without launching a browser, so the view keeps only the `open` call — the one
line that cannot be tested.

The filename is derived from the deliverable id so opening twice replaces
rather than litters, and SANITISED because an id is only a String: ids are
UUIDs in production and `demo-mur-site` in fixtures, and nothing in the type
system stops a future one carrying a path separator. A test walks `../escape`,
`/absolute` and an empty id and asserts none of them leave the temp directory.

Throws rather than traps: a founder pressing a button must not crash the app.

6 passed / 0 failed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Services/SiteExport.swift codepetTests/SiteExportTests.swift
git commit -F /tmp/c-se1.txt
```

---

### Task 2: The button in `SiteViewer`

**Files:**
- Modify: `codepet/Views/Library/DeliverableViewers.swift` — `SiteViewer` (~lines 754-790)
- Test: `codepetTests/SiteExportTests.swift` (append)

**Interfaces:**
- Consumes: `SiteExport.fileURL(forDeliverableId:)`, `SiteExport.write(html:to:)` (Task 1); `SiteViewer.buildHTML(_:)` (exists).
- Produces: `SiteViewer.openLabel(_ lang: AppLanguage) -> String`.

- [ ] **Step 1: Write the failing tests**

Append inside `SiteExportTests`:

```swift
    // MARK: - Task 2: the label

    /// Not "Open" alone. The chat draft card already carries an "Open the live page" cue that
    /// routes to this in-app viewer; a second, differently-destined "Open" on the same path is
    /// the confusion this wording avoids.
    func testTheLabelNamesTheBrowser() {
        XCTAssertEqual(SiteViewer.openLabel(.en), "Open in browser")
        XCTAssertEqual(SiteViewer.openLabel(.vi), "Mở trong trình duyệt")
    }

    /// The app ships bilingual; a missing translation renders English in a Vietnamese UI.
    func testBothLabelsAreNonEmptyAndDifferent() {
        XCTAssertFalse(SiteViewer.openLabel(.en).isEmpty)
        XCTAssertFalse(SiteViewer.openLabel(.vi).isEmpty)
        XCTAssertNotEqual(SiteViewer.openLabel(.en), SiteViewer.openLabel(.vi))
    }

    /// The browser must show the same page the preview does, not a re-derivation. Asserted
    /// against the real Murror fixture rather than a stub.
    func testTheWrittenFileMatchesWhatThePreviewRenders() throws {
        let entry = try XCTUnwrap(DemoProject.murror.deliverables.first { $0.kind == "site" })
        let payload = try JSONDecoder().decode(
            DeliverablePayload.self, from: Data(try XCTUnwrap(entry.payloadJSON).utf8))
        let site = try XCTUnwrap(payload.site)
        let html = SiteViewer.buildHTML(site)
        let url = SiteExport.fileURL(forDeliverableId: "fixture-parity")
        defer { try? FileManager.default.removeItem(at: url) }
        try SiteExport.write(html: html, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), html)
        XCTAssertTrue(html.contains("<!doctype html"), "not a whole document")
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/SiteExportTests test 2>&1 | tail -10
```

Expected: FAIL — `type 'SiteViewer' has no member 'openLabel'`.

If it also fails on `SiteViewer.buildHTML` being inaccessible, that function is `private` — change it to `static` internal (drop `private`) and note it in your report. Do not duplicate the HTML builder.

- [ ] **Step 3: Add the label and the button**

In `codepet/Views/Library/DeliverableViewers.swift`, inside `SiteViewer`, immediately after the `private var html: String { SiteViewer.buildHTML(payload) }` line, add:

```swift
    /// **"Open in browser", not "Open".** The chat draft card already carries an "Open the live
    /// page" cue routing to THIS viewer; a second differently-destined "Open" on one path is
    /// the confusion this avoids. A `file://` URL is a real browser page and is NOT shareable —
    /// nothing here may imply otherwise.
    static func openLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở trong trình duyệt" : "Open in browser"
    }

    /// Surfaced next to the button when the write fails, rather than the button doing nothing.
    @State private var openFailed = false
```

Then, inside `body`, in the existing `HStack` that holds the `Picker` — after `Spacer()` and BEFORE the `Picker` — add:

```swift
                    Button {
                        do {
                            let url = SiteExport.fileURL(
                                forDeliverableId: deliverableId ?? "site")
                            try SiteExport.write(html: html, to: url)
                            NSWorkspace.shared.open(url)
                            openFailed = false
                        } catch {
                            // A button that sometimes does nothing is worse than one that says
                            // why. Fail-soft: no trap, no thrown error reaching the view.
                            openFailed = true
                        }
                    } label: {
                        Text(SiteViewer.openLabel(lang))
                            .font(.pixelSystem(size: 11, weight: .semibold))
                            .foregroundColor(CodepetTheme.accentPurple)
                    }
                    .buttonStyle(.plain)
                    .cursorOnHover(.pointingHand)

                    if openFailed {
                        Text(lang == .vi ? "Không mở được" : "Couldn't open")
                            .font(.pixelSystem(size: 11))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
```

`SiteViewer` currently takes only `payload: SitePayload` — it has no deliverable id. **Add `let deliverableId: String?` to `SiteViewer`** and thread it from the call site in `DeliverableDetailView` (`LibraryView.swift:481-482`, `SiteViewer(payload: deliverable.payload!.site!)` becomes `SiteViewer(payload: deliverable.payload!.site!, deliverableId: deliverable.id)`). Make it optional with a `nil` default so any other call site keeps compiling; grep for `SiteViewer(` first and update every one you find.

`import AppKit` may be needed at the top of the file for `NSWorkspace` — check whether it is already imported (SwiftUI on macOS often re-exports it) and add it only if the build says so.

- [ ] **Step 4: Run the tests and the neighbours**

`DeliverableViewers.swift` holds 9 viewers behind a shared frame, so a change there can disturb any of them.

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
for s in SiteExportTests DraftPayloadPreviewTests DraftPreviewTests LibraryFixturesTests \
         DemoProjectMurrorTests DemoProjectFiledTests; do
  rm -rf /tmp/se-$s.xcresult
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/se-$s.xcresult test > /tmp/se-$s.log 2>&1
  p=$(xcrun xcresulttool get test-results summary --path /tmp/se-$s.xcresult 2>/dev/null | grep '"passedTests"' | head -1 | tr -dc 0-9)
  f=$(xcrun xcresulttool get test-results summary --path /tmp/se-$s.xcresult 2>/dev/null | grep '"failedTests"' | head -1 | tr -dc 0-9)
  printf "%-28s pass=%-4s fail=%s\n" "$s" "${p:-0}" "${f:-0}"
done
```

Every row must read `fail=0` with `pass>0`.

- [ ] **Step 5: Commit**

```bash
cat > /tmp/c-se2.txt <<'EOF'
feat(library): open a produced landing page in the real browser

Beside the Preview/Code picker, not on the shared `DeliverableFrame` action:
that frame's single `action:` slot serves 9 viewers and 13 deliverable kinds,
and widening a shared API to serve one kind is the wrong trade. Copy HTML
keeps its slot untouched.

Labelled "Open in browser" rather than "Open" — the chat draft card already
carries an "Open the live page" cue routing to this same in-app viewer, and two
differently-destined "Open"s on one path is the confusion worth avoiding.

Honest about what it is: a `file://` URL is a real browser page with a real URL
bar, zoom, devtools and print-to-PDF, and it is NOT shareable with anyone. No
Share affordance, no Copy link. A hosted https URL is a separate project.

A failed write shows "Couldn't open" rather than the button doing nothing.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Views/Library/DeliverableViewers.swift codepet/Views/Library/LibraryView.swift \
        codepetTests/SiteExportTests.swift
git commit -F /tmp/c-se2.txt
```

---

### Task 3: Open it for real, then document it

- [ ] **Step 1: Build signed, launch, and open a page**

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

- [ ] **Step 2: Confirm the file half without the GUI**

The write and the naming are testable; the `open` is not. Verify the artifact directly rather than trusting the button:

```bash
ls -l "$(getconf DARWIN_USER_TEMP_DIR)"codepet-site-*.html 2>/dev/null || \
  ls -l /var/folders/*/*/T/codepet-site-*.html 2>/dev/null || echo "no file written yet"
```

After pressing the button once, that glob must show exactly ONE file per deliverable, and pressing it again must not add a second.

- [ ] **Step 3: Confirm on screen — the founder's step**

1. Library → the Murror landing page → **Open in browser** → the page opens in the default browser and renders as a real page
2. The browser's URL bar shows a `file://` path — expected; it is not shareable
3. Press it twice → one browser tab per press is fine, but only ONE file in temp
4. Redo the draft, press again → the browser shows the NEW copy, not a stale one

- [ ] **Step 4: Document it, and commit**

Add to `CLAUDE.md`, near the deliverables notes:

```markdown
- **A `.site` deliverable can be opened in the real browser** — `SiteExport` writes it to the
  temp directory under a name derived from the deliverable id, and `SiteViewer` opens it. The
  URL is `file://` and therefore **not shareable**; a hosted https link is a separate project.
  The button lives in `SiteViewer`'s own content, NOT on `DeliverableFrame.action`, which is
  shared by 9 viewers.
```

```bash
cat > /tmp/c-se3.txt <<'EOF'
docs: a site can reach a browser, and cannot reach anyone else

Records the boundary as much as the feature: `file://` gets a real browser
page and gets the founder nothing they can send to another person. Anyone
reading this later should not have to rediscover that the shareable-link
question is untouched.

Also records why the button is not on `DeliverableFrame.action` — that slot is
shared by 9 viewers, and widening it for one kind would change the API for 13.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add CLAUDE.md
git commit -F /tmp/c-se3.txt
```

---

## Self-Review

**Spec coverage.** Temp-directory write, id-derived name → Task 1. Fail-soft with a visible error → Tasks 1 and 2. `Open in browser` label in both languages → Task 2. Site-only → Task 2 (the button lives inside `SiteViewer`, so no other kind can reach it). Pure/impure split → Task 1 holds everything testable, Task 2 holds only `NSWorkspace.shared.open`. Every spec test row maps, and the "filesystem-safe for an arbitrary id" row became the sanitisation test in Task 1 Step 1.

**Two deliberate unknowns, flagged rather than guessed.** `SiteViewer.buildHTML` may be `private` (Task 2 Step 2 says how to resolve and to report it); `import AppKit` may or may not be needed (Task 2 Step 3 says to let the build decide). Both are reported, neither is silently assumed.

**One design decision worth re-stating.** `SiteViewer` gains a `deliverableId: String?` parameter, which changes its initializer. Task 2 Step 3 requires grepping every `SiteViewer(` call site rather than assuming the one in `LibraryView.swift:481` is the only one.

**Type consistency.** `SiteExport.fileURL(forDeliverableId:)` and `write(html:to:)` are used with identical labels in Tasks 1, 2 and 3. `SiteViewer.openLabel(_:)` takes `AppLanguage` and is called with `.en`/`.vi` in tests and `lang` in the view.
