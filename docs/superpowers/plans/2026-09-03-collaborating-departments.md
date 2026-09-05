# Collaborating Departments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a department's real output render on its chat card the moment it lands, and make a downstream department's run actually receive the upstream work it depends on.

**Architecture:** §1 is a pure view addition — one new `Deliverable → View` that reads the payload already sitting unread on the model, mounted into `draftCard`. §2/§3 widen the run contract: a new `upstream` array travels Swift → wire → `buildRunTaskPrompt`, assembled in `CompanyStore` from the task's `dependsOn` and credited back on the card. Every decision that can be a pure function is one, because the bug §2 fixes is invisible to fixture tests and only catchable at that level.

**Tech Stack:** Swift 5, SwiftUI, XCTest, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Xcode 26.2, macOS target 26.2; TypeScript / Node 22 / jest in `functions/`.

**Spec:** `docs/superpowers/specs/2026-09-03-collaborating-departments-design.md`

## Global Constraints

- **Card previews cap at 180pt with no internal scrolling.** A card that scrolls inside a scrolling transcript is worse than one that truncates; the full viewer is one tap away via the existing `showDetail`.
- **A nil payload falls back to `DraftPreview.plain`.** Never render an empty structured view — three blank slider rows read as a broken card, and the founder cannot distinguish that from an absent payload.
- **`site` accent goes through `SiteViewer`'s `safeHex` semantics.** It validates hex *syntax*, not contrast; a malformed value must degrade to the fallback rather than paint a broken swatch.
- **The site preview is native, not a `WKWebView`.** One web view per message is the wrong price for a preview. Render the page's identity — brand, headline, accent swatch, CTA — and let **Open** reach the true render.
- **`upstream` caps at 3 items, 1500 characters of body each, in `dependsOn` order.** The fixture authors that array deliberately, so its order is the intended precedence.
- **`upstream` must be added in all three places** — `RunTaskArgs` (`functions/src/runTaskCore.ts`), the `runTask.ts` handler, and the `runTask` entry in `functions/src/local/oneShotOps.ts`. Miss the third and the local path silently drops it.
- **Chained runs do not stop for approval** (founder decision, 2026-09-03). The upstream draft passes forward unapproved and the downstream credit says `(unapproved draft)`.
- **`RoadmapGating.awaitsApproval` is untouched.** Chaining moves work forward inside the already-open phase window; it never opens a phase.
- Theme colours come from `CodepetTheme` (`Color.dyn(light, dark)`) — never a bare literal, or the card breaks in one theme.
- New `.swift` files need no project-file edit: `PBXFileSystemSynchronizedRootGroup` means target membership follows the folder on disk.
- Commit with `git commit -F <file>`, never `-m`: bodies contain backticks and zsh would execute them.
- `xcodebuild test` exits 65 on a clean checkout — the XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates (~27 tests never finish, none actually fail). Run per-suite with `-only-testing:` and read counts from `xcresulttool get test-results summary`, **never from the exit code**.
- Quit the running `codepet.app` before any `xcodebuild test`: a live app kills the test host, different victim each run.
- Re-run `scripts/build-sidecar.sh` after any `functions/src/` change, or the routers report `localUnavailable`.

---

### Task 1: `DraftPayloadPreview` — the structured previews

The whole of §1. One new file, one call site.

**Files:**
- Create: `codepet/Views/Copilot/DraftPayloadPreview.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` — insert into `draftCard`
- Test: `codepetTests/DraftPayloadPreviewTests.swift`

**Interfaces:**
- Consumes: `Deliverable` (`.kind`, `.payload`, `.title`, `.body`), `DeliverablePayload` (`.site`, `.sheet`, `.screens`, `.messages`, `.items`, `.call`, `.sections`, `.goal`, `.steps`, `.changes`), `CodepetTheme`, `DraftPreview.plain(_:title:)`
- Produces: `DraftPayloadPreview(deliverable:)` (a `View`), `DraftPayloadPreview.hasStructuredPreview(_ d: Deliverable) -> Bool`, `DraftPayloadPreview.maxHeight: CGFloat = 180`, `DraftPayloadPreview.safeAccent(_ hex: String) -> Color`

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/DraftPayloadPreviewTests.swift`:

```swift
// codepetTests/DraftPayloadPreviewTests.swift
import XCTest
import SwiftUI
@testable import codepet

/// Guards on the card showing the deliverable rather than describing it.
///
/// `draftCard` rendered `DraftPreview.plain(d.body)` under a lineLimit and never read
/// `d.payload` at all — so Finance's four-input pricing model was a truncated paragraph and the
/// landing page was a sentence saying "open it to see it rendered". The dispatch decision is
/// pulled out as `hasStructuredPreview` precisely so it is testable without rendering.
final class DraftPayloadPreviewTests: XCTestCase {

    private func deliverable(_ kind: DeliverableKind, payloadJSON: String?) throws -> Deliverable {
        let payload = try payloadJSON.map {
            try JSONDecoder().decode(DeliverablePayload.self, from: Data($0.utf8))
        }
        // NOTE the argument order: `Deliverable.init` takes `kind` BEFORE `title`.
        return Deliverable(id: "t", kind: kind, title: "T", body: "Body text.", payload: payload)
    }

    /// The dispatch must key on the PAYLOAD being present, not on the kind alone. Keying on
    /// kind renders an empty structured view for a kind whose payload never arrived.
    func testStructuredPreviewRequiresAPayload() throws {
        let withNone = try deliverable(.sheet, payloadJSON: nil)
        XCTAssertFalse(DraftPayloadPreview.hasStructuredPreview(withNone),
                       "a nil payload must fall back to prose, not render an empty sheet")
    }

    func testSheetWithAPayloadGetsAStructuredPreview() throws {
        let d = try deliverable(.sheet, payloadJSON: """
        {"price":{"val":6,"min":0,"max":20,"step":1},
         "waitlist":{"val":400,"min":50,"max":5000,"step":50},
         "conversion":{"val":8,"min":1,"max":40,"step":1},
         "churn":{"val":9,"min":1,"max":25,"step":1},"summary":"S"}
        """)
        XCTAssertTrue(DraftPayloadPreview.hasStructuredPreview(d))
    }

    /// Every Murror deliverable that carries a payload must reach a structured branch — this is
    /// the end-to-end claim of §1, asserted against the real fixtures rather than a stub.
    func testEveryMurrorPayloadReachesAStructuredPreview() throws {
        for entry in DemoProject.murror.deliverables where entry.payloadJSON != nil {
            let d = try deliverable(XCTUnwrap(DeliverableKind(rawValue: entry.kind)),
                                    payloadJSON: entry.payloadJSON)
            XCTAssertTrue(DraftPayloadPreview.hasStructuredPreview(d),
                          "\(entry.kind) carries a payload but renders prose")
        }
    }

    /// A kind with no structured branch at all keeps prose even when a payload decodes.
    func testAnUnhandledKindFallsBackToProse() throws {
        let d = try deliverable(.email, payloadJSON: #"{"items":[{"t":"a","done":false}]}"#)
        XCTAssertFalse(DraftPayloadPreview.hasStructuredPreview(d))
    }

    /// `safeHex` validates SYNTAX, not contrast — so nothing else would catch a malformed
    /// accent painting a broken swatch.
    func testMalformedAccentFallsBackToTheHouseAccent() {
        XCTAssertEqual(DraftPayloadPreview.safeAccent("not-a-hex"),
                       CodepetTheme.accentPurple)
        XCTAssertEqual(DraftPayloadPreview.safeAccent(""), CodepetTheme.accentPurple)
        XCTAssertNotEqual(DraftPayloadPreview.safeAccent("#0a1430"),
                          CodepetTheme.accentPurple)
    }

    func testHeightCapIsTheSpecValue() {
        XCTAssertEqual(DraftPayloadPreview.maxHeight, 180)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DraftPayloadPreviewTests test 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'DraftPayloadPreview' in scope`.

- [ ] **Step 3: Create the view**

Create `codepet/Views/Copilot/DraftPayloadPreview.swift`. Structure:

```swift
import SwiftUI

struct DraftPayloadPreview: View {
    let deliverable: Deliverable

    static let maxHeight: CGFloat = 180

    /// Pure, and keyed on the PAYLOAD rather than the kind.
    static func hasStructuredPreview(_ d: Deliverable) -> Bool {
        guard let p = d.payload else { return false }
        switch d.kind {
        case .site:      return p.site != nil
        case .sheet:     return p.sheet != nil
        case .screens:   return p.screens != nil
        case .dms:       return !(p.messages ?? []).isEmpty
        case .checklist: return !(p.items ?? []).isEmpty
        case .doc:       return !(p.call ?? "").isEmpty || !(p.sections ?? []).isEmpty
        case .plan:      return !(p.goal ?? "").isEmpty
        default:         return false
        }
    }

    /// Mirrors `SiteViewer.safeHex`'s validation, returning a `Color` and falling back to the
    /// house accent rather than to the viewer's violet literal.
    static func safeAccent(_ hex: String) -> Color {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return CodepetTheme.accentPurple }
        let digits = s.dropFirst()
        guard digits.count == 6 || digits.count == 3,
              digits.allSatisfy(\.isHexDigit) else { return CodepetTheme.accentPurple }
        return Color(hex: String(digits.count == 3 ? String(digits.flatMap { [$0, $0] }) : String(digits)))
    }

    var body: some View { /* switch on kind → the six branches below */ }
}
```

Branches, each a small `@ViewBuilder` private func:

- `site(_ p: SitePayload)` — a bordered strip: `p.brand` uppercased at 10pt tracked in `mutedText`; `p.headline` + `p.headlineHi` at 15pt `primaryText`; a row with a 13×13 rounded swatch filled `Self.safeAccent(p.accent)` and `p.ctaPrimary` at 11pt.
- `sheet(_ p: SheetPayload)` — four rows (`Price`/`Signups`/`Convert`/`Churn`), each `label · value · track`, value `.monospacedDigit()`, track a 3pt `hairline` capsule with an `accentPurple` dot positioned at `(val - min) / (max - min)`; then `p.summary` clamped to 2 lines.
- `screens(_ p: ScreensPayload)` — `HStack` of up to 4 tiles, each a 1pt-hairline rounded rect with the screen's `kick` and `title` at 10.5/11.5pt.
- `dms(_ m: [DmMessage])` — first message's `name` semibold 11.5pt, `msg` clamped to 3 lines, then `"N recipients"` when `m.count > 1`.
- `checklist(_ items: [ChecklistItem])` — first 3 rows with `checkmark.circle.fill` / `circle` in `accentTeal` / `hairline`, then `"+N more"`.
- `doc(call:sections:)` / `plan(goal:steps:changes:)` — the call/goal at 12.5pt `bodyText`, then a single 11pt `mutedText` line of section headings, or `"N steps · M changes"`.

Wrap `body` in `.frame(maxHeight: Self.maxHeight, alignment: .top).clipped()` — the cap, without a `ScrollView`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DraftPayloadPreviewTests \
  -resultBundlePath /tmp/p1.xcresult test 2>&1 | tail -10
xcrun xcresulttool get test-results summary --path /tmp/p1.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: PASS, 0 failures.

- [ ] **Step 5: Mount it in `draftCard`**

In `codepet/Views/Copilot/CopilotChatView.swift`, immediately after the title/body block's closing `.padding(-6).padding(.horizontal, -2)` and **before** the `if let steps = message.execSteps` block:

```swift
// The deliverable itself, not a description of it. `d.payload` was decoded, stored and
// never read by this card — so a four-input pricing model rendered as a truncated
// paragraph and a landing page rendered as a sentence telling the founder to go and
// look. Prose stays the fallback for a kind with no payload: an empty structured view
// reads as a broken card, and the founder cannot tell that from an absent payload.
if DraftPayloadPreview.hasStructuredPreview(d) {
    DraftPayloadPreview(deliverable: d)
}
```

The prose `Text` above it stays exactly as is — it is still the fallback path and still the tap target that opens the full viewer.

- [ ] **Step 6: Look at it, since tests cannot**

`DraftPayloadPreview` takes no `@EnvironmentObject`, which is what makes this possible. Add a temporary test that renders each Murror payload through `ImageRenderer` and writes PNGs to `NSTemporaryDirectory()`, `NSLog` the paths, run it, and open them. Confirm: the swatch is Murror's navy, the four slider dots sit at different offsets, nothing is clipped mid-glyph. Delete the temporary test afterwards.

**Do not gate the dump on an env var.** `xcodebuild` does not forward the parent environment to a unit-test host, and a `TEST_RUNNER_`-prefixed build setting does not either — both write nothing while the test still reports success.

- [ ] **Step 7: Run the neighbouring suites, then commit**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DraftPayloadPreviewTests \
  -only-testing:codepetTests/DemoProjectMurrorTests \
  -only-testing:codepetTests/LibraryFixturesTests \
  -resultBundlePath /tmp/p1b.xcresult test 2>&1 | tail -10
xcrun xcresulttool get test-results summary --path /tmp/p1b.xcresult | grep -E '"(passedTests|failedTests)"'
```

```bash
cat > /tmp/c-t1.txt <<'EOF'
feat(chat): the draft card shows the deliverable, not a description of it

`draftCard` rendered `DraftPreview.plain(d.body)` under a lineLimit and never
read `d.payload` at all, so every structured viewer was reachable only from
the Library. Finance's four-input pricing model arrived as a truncated
paragraph; the landing page arrived as a sentence saying "open it to see it
rendered". That sentence was the whole problem: the card explained where the
work was instead of being it.

Dispatch keys on the PAYLOAD, not the kind — keying on kind renders an empty
structured view when a payload never arrived, and a founder cannot tell that
from a broken card. Prose stays the fallback.

Capped at 180pt with no inner scroll: a card that scrolls inside a scrolling
transcript is worse than one that truncates, and the full viewer is one tap
away already.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add codepet/Views/Copilot/DraftPayloadPreview.swift \
        codepet/Views/Copilot/CopilotChatView.swift \
        codepetTests/DraftPayloadPreviewTests.swift
git commit -F /tmp/c-t1.txt
```

---

### Task 2: `UpstreamWork` on the wire, and its assembly

**Files:**
- Modify: `codepet/Services/RunTaskClient.swift` — the type and the request field
- Modify: `codepet/Managers/CompanyStore.swift:2540` — assemble it
- Test: `codepetTests/UpstreamWorkTests.swift`

**Interfaces:**
- Consumes: `RoadmapTask.dependsOn`, `RoadmapEngine.deliverable(for:in:)`, `DepartmentCatalog.find(_:)`, `DepartmentCompanions.companionId(for:)`, `PetCharacter.all`
- Produces: `UpstreamWork` (`taskTitle`, `deptName`, `petName`, `kind`, `body`, `unapproved: Bool`), `RunTaskRequest.upstream: [UpstreamWork]`, `UpstreamWork.assemble(for:in:library:) -> [UpstreamWork]`, `UpstreamWork.cap = 3`, `UpstreamWork.bodyLimit = 1500`

- [ ] **Step 1: Write the failing tests**

```swift
// codepetTests/UpstreamWorkTests.swift
import XCTest
@testable import codepet

/// Guards on outputs feeding forward.
///
/// `mur-site` depends on `mur-brand` and the run passed Nova nothing of Luna's output: no field
/// on the request, no assembly, nowhere in the prompt. The graph gated ORDER and never
/// INFORMATION — the same shape as the fixed bug `runTaskCore.ts:60-63` records, where a run was
/// performed BY a department the prompt was never told about.
final class UpstreamWorkTests: XCTestCase {

    private func filed(_ taskId: String, _ title: String, body: String = "B") -> Deliverable {
        // `kind` before `title` — see `Deliverable.init` in Models/Deliverable.swift.
        Deliverable(id: "d-\(taskId)", kind: .doc, title: title, body: body, sourceTaskId: taskId)
    }

    func testAssemblesInDependsOnOrder() {
        let tasks = DemoProject.murror.tasks
        let site = tasks.first { $0.id == "mur-site" }!   // dependsOn brand, landscape
        let library = [filed("mur-landscape", "Landscape"), filed("mur-brand", "Brand")]
        let up = UpstreamWork.assemble(for: site, in: tasks, library: library)
        XCTAssertEqual(up.map(\.taskTitle), ["Brand", "Landscape"],
                       "must follow dependsOn order, not library order")
    }

    /// A pet and a department name, or the credit on the card cannot say who did the work.
    func testCarriesTheDepartmentAndItsPet() {
        let tasks = DemoProject.murror.tasks
        let site = tasks.first { $0.id == "mur-site" }!
        let up = UpstreamWork.assemble(for: site, in: tasks,
                                       library: [filed("mur-brand", "Brand")])
        XCTAssertEqual(up.first?.deptName, "Design")
        XCTAssertEqual(up.first?.petName, "Luna")
    }

    func testSkipsDependenciesWithNoFiledDeliverable() {
        let tasks = DemoProject.murror.tasks
        let site = tasks.first { $0.id == "mur-site" }!
        let up = UpstreamWork.assemble(for: site, in: tasks, library: [])
        XCTAssertTrue(up.isEmpty, "an unfiled dependency must be absent, not a placeholder")
    }

    func testCapsAtThreeAndClipsBodies() {
        var task = RoadmapTask(id: "x", title: "X", detail: "", phase: .build, who: .draft,
                               dependsOn: ["a", "b", "c", "d", "e"], dept: "mkt")
        let deps = ["a", "b", "c", "d", "e"].map {
            RoadmapTask(id: $0, title: $0.uppercased(), detail: "", phase: .find,
                        who: .draft, done: true, dept: "design")
        }
        let library = deps.map { filed($0.id, $0.title, body: String(repeating: "x", count: 4000)) }
        let up = UpstreamWork.assemble(for: task, in: deps + [task], library: library)
        XCTAssertEqual(up.count, UpstreamWork.cap)
        for item in up { XCTAssertLessThanOrEqual(item.body.count, UpstreamWork.bodyLimit) }
        task.dependsOn = []
        XCTAssertTrue(UpstreamWork.assemble(for: task, in: deps, library: library).isEmpty)
    }

    func testEncodesToTheWireShape() throws {
        let w = UpstreamWork(taskTitle: "Brand", deptName: "Design", petName: "Luna",
                             kind: "doc", body: "B", unapproved: true)
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(w)) as? [String: Any]
        XCTAssertEqual(json?["taskTitle"] as? String, "Brand")
        XCTAssertEqual(json?["petName"] as? String, "Luna")
        XCTAssertEqual(json?["unapproved"] as? Bool, true)
    }
}
```

`Deliverable.init` is `(id:kind:title:body:createdAt:sourceTaskId:payload:)` — **`kind` comes before `title`**, which is easy to get wrong from the field order in the struct.

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/UpstreamWorkTests test 2>&1 | tail -15
```

Expected: FAIL — `cannot find 'UpstreamWork' in scope`.

- [ ] **Step 3: Add the type and the assembly**

In `codepet/Services/RunTaskClient.swift`, above `RunTaskRequest`:

```swift
/// One upstream department's finished work, travelling with a downstream run.
struct UpstreamWork: Codable, Hashable {
    let taskTitle: String
    let deptName: String
    let petName: String
    let kind: String
    let body: String
    /// True when the work was produced by a chained run and not yet approved. Surfaced on the
    /// card rather than hidden — a chain that conceals this is the fixture-lie failure mode.
    var unapproved: Bool = false

    static let cap = 3
    static let bodyLimit = 1500

    /// In `dependsOn` order: the fixture authors that array deliberately, so its order is the
    /// intended precedence rather than an arbitrary notion of "nearest".
    static func assemble(for task: RoadmapTask,
                         in tasks: [RoadmapTask],
                         library: [Deliverable]) -> [UpstreamWork] {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return task.dependsOn.prefix(cap * 3).compactMap { depId -> UpstreamWork? in
            guard let dep = byId[depId],
                  let filed = RoadmapEngine.deliverable(for: dep, in: library) else { return nil }
            let dept = DepartmentCatalog.find(dep.dept)
            let pet = DepartmentCompanions.companionId(for: dep.dept ?? "")
                .flatMap { PetCharacter.all[$0] }
            return UpstreamWork(taskTitle: filed.title,
                                deptName: dept?.name ?? "",
                                petName: pet?.name ?? "",
                                kind: filed.kind.rawValue,
                                body: String(filed.body.prefix(bodyLimit)))
        }.prefix(cap).map { $0 }
    }
}
```

Then `RunTaskRequest` gains `var upstream: [UpstreamWork] = []`.

- [ ] **Step 4: Assemble it at the one call site**

In `codepet/Managers/CompanyStore.swift`, in the `RunTaskRequest(` construction at line 2540, add:

```swift
upstream: UpstreamWork.assemble(for: task, in: company.tasks, library: company.library),
```

Read the surrounding function first to confirm the local name of the task being run; if it is not `task`, use whatever that function calls it.

- [ ] **Step 5: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/UpstreamWorkTests \
  -resultBundlePath /tmp/p2.xcresult test 2>&1 | tail -10
xcrun xcresulttool get test-results summary --path /tmp/p2.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: PASS, 0 failures.

- [ ] **Step 6: Commit**

```bash
cat > /tmp/c-t2.txt <<'EOF'
feat(run): a task's run carries the upstream work it depends on

`mur-site` depends on `mur-brand` and the run passed Nova nothing of Luna's
output: no field on the request, no assembly in the store, nowhere in the
prompt to put it. The dependency graph gated ORDER and never INFORMATION.

Assembled in `dependsOn` order, because the fixture authors that array
deliberately. Capped at 3 items and 1500 characters of body each: four
dependencies would otherwise push four full deliverables into a prompt
already carrying 4000 characters of company context.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add codepet/Services/RunTaskClient.swift codepet/Managers/CompanyStore.swift \
        codepetTests/UpstreamWorkTests.swift
git commit -F /tmp/c-t2.txt
```

---

### Task 3: The prompt actually uses it (TypeScript)

**Files:**
- Modify: `functions/src/runTaskCore.ts` — `RunTaskArgs`, `buildRunTaskPrompt`
- Modify: `functions/src/runTask.ts` — pass through
- Modify: `functions/src/local/oneShotOps.ts` — pass through in the `runTask` op
- Test: `functions/src/__tests__/runTaskUpstream.test.ts` (match the directory the existing jest specs use)

**Interfaces:**
- Consumes: `clip`, `departmentBrief`, `DEPARTMENT_NAMES` (all already in `runTaskCore.ts`)
- Produces: `RunTaskArgs.upstream?: UpstreamWork[]`, `interface UpstreamWork { taskTitle, deptName, petName, kind, body, unapproved? }`

- [ ] **Step 1: Write the failing jest tests**

```ts
import { buildRunTaskPrompt } from "../runTaskCore";

const base = {
  companionId: "nova", language: "en", context: "Murror",
  taskTitle: "Build the Murror landing page", taskDetail: "", deptKey: "mkt",
};

describe("upstream work in the run prompt", () => {
  it("names the pet, the department and the body, and asks the model to credit it", () => {
    const p = buildRunTaskPrompt({
      ...base,
      upstream: [{ taskTitle: "Shape the Murror visual direction", deptName: "Design",
                   petName: "Luna", kind: "doc", body: "Night sky, warm light." }],
    });
    expect(p).toContain("Luna (Design)");
    expect(p).toContain("Shape the Murror visual direction");
    expect(p).toContain("Night sky, warm light.");
    expect(p).toMatch(/build on this/i);
    expect(p).toMatch(/say so in one short phrase/i);
  });

  it("omits the block entirely when there is no upstream", () => {
    expect(buildRunTaskPrompt(base)).not.toMatch(/already produced work/i);
    expect(buildRunTaskPrompt({ ...base, upstream: [] })).not.toMatch(/already produced work/i);
  });

  it("marks an unapproved draft as one", () => {
    const p = buildRunTaskPrompt({
      ...base,
      upstream: [{ taskTitle: "T", deptName: "Design", petName: "Luna",
                   kind: "doc", body: "B", unapproved: true }],
    });
    expect(p).toMatch(/not yet approved/i);
  });
});
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode/functions
npx jest src/__tests__/runTaskUpstream.test.ts 2>&1 | tail -15
```

Expected: FAIL — the prompt contains none of those strings.

- [ ] **Step 3: Add the field and the block**

In `runTaskCore.ts`, above `RunTaskArgs`:

```ts
export interface UpstreamWork {
  taskTitle: string;
  deptName: string;
  petName: string;
  kind: string;
  body: string;
  unapproved?: boolean;
}
```

`RunTaskArgs` gains:

```ts
  /** Finished work from the departments this task depends on. The graph used to gate order
   *  and never information — see the deptKey comment below for the same bug, already fixed. */
  upstream?: UpstreamWork[];
```

In `buildRunTaskPrompt`, after `deptBlock` is computed:

```ts
  const upstream = (args.upstream ?? []).slice(0, 3);
  const upstreamBlock = upstream.length
    ? `Other departments have already produced work this task must build on:\n\n` +
      upstream
        .map(
          (u) =>
            `— ${u.petName} (${u.deptName}) produced "${clip(u.taskTitle, 200)}"` +
            `${u.unapproved ? " (a draft, not yet approved)" : ""}:\n${clip(u.body, 1500)}`
        )
        .join("\n\n") +
      `\n\nBuild on this. Do not contradict it, and do not re-derive what it already decided. ` +
      `Where you rely on it, say so in one short phrase.\n\n`
    : "";
```

and insert `upstreamBlock` into the returned template immediately after `deptBlock`.

- [ ] **Step 4: Pass it through both transports**

In `functions/src/runTask.ts`, add `upstream` to the args object handed to `buildRunTaskPrompt`, alongside `deptKey`. In `functions/src/local/oneShotOps.ts`, do the same in the `runTask` entry (around line 318). **Both, or the local path silently drops it** — `ONE_SHOT_OPS` is the registry a rename must fail in jest rather than on a founder's machine.

- [ ] **Step 5: Run jest, then rebuild the sidecars**

```bash
cd ~/Developer/codepet-two-mode/functions
npx jest src/__tests__/runTaskUpstream.test.ts 2>&1 | tail -8
npx jest 2>&1 | tail -8
cd .. && ./scripts/build-sidecar.sh 2>&1 | tail -8
```

Expected: both jest runs pass; the sidecar script prints three bundles and its three self-checks.

- [ ] **Step 6: Commit**

```bash
cat > /tmp/c-t3.txt <<'EOF'
feat(functions): the run prompt is told what upstream departments produced

Mirrors the deptKey fix this file already records: "a run has always been
performed BY a department ... but the prompt was never told which one, so a
marketing deliverable was written with no marketing knowledge behind it."
Same shape — the dependency arrows were on screen and the model never heard
about them.

The block asks the model to name what it relied on, which is what makes the
credit on the card honest rather than decorative.

Added in all three places: RunTaskArgs, the runTask handler, and the runTask
entry in ONE_SHOT_OPS. Miss the third and the local path drops it silently.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add functions/src/runTaskCore.ts functions/src/runTask.ts \
        functions/src/local/oneShotOps.ts functions/src/__tests__/runTaskUpstream.test.ts
git commit -F /tmp/c-t3.txt
```

---

### Task 4: `UpstreamCredit` on the card, and the chain

**Files:**
- Create: `codepet/Views/Copilot/UpstreamCredit.swift`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` — mount above the payload preview
- Modify: `codepet/Managers/CompanyStore.swift` — the chained run
- Modify: `codepet/Services/MockChat.swift` — reflect `upstream`, and answer needs-upstream
- Test: `codepetTests/UpstreamCreditTests.swift`

**Interfaces:**
- Consumes: `UpstreamWork`, `DraftPayloadPreview.maxHeight`
- Produces: `UpstreamCredit(work: [UpstreamWork], onOpen: (UpstreamWork) -> Void)`, `UpstreamCredit.line(_ work: [UpstreamWork]) -> String?`, `CompanyStore.runChained(taskId:language:)`

- [ ] **Step 1: Write the failing tests**

```swift
// codepetTests/UpstreamCreditTests.swift
import XCTest
@testable import codepet

final class UpstreamCreditTests: XCTestCase {

    private func work(_ title: String, unapproved: Bool = false) -> UpstreamWork {
        UpstreamWork(taskTitle: title, deptName: "Design", petName: "Luna",
                     kind: "doc", body: "B", unapproved: unapproved)
    }

    /// Absent, not empty: a first task must not be decorated with a blank row.
    func testNoLineWithoutUpstream() {
        XCTAssertNil(UpstreamCredit.line([]))
    }

    func testNamesThePetAndTheWork() {
        let line = UpstreamCredit.line([work("brand direction")])
        XCTAssertEqual(line, "Built on Luna's brand direction")
    }

    /// The founder decision: a chained run passes the draft forward unapproved and the card
    /// SAYS so. Hiding it is the fixture-lie failure mode this codebase keeps paying for.
    func testSaysWhenTheDraftIsUnapproved() throws {
        let line = try XCTUnwrap(UpstreamCredit.line([work("brand direction", unapproved: true)]))
        XCTAssertTrue(line.contains("unapproved draft"), line)
    }

    func testSummarisesMoreThanOne() throws {
        let line = try XCTUnwrap(UpstreamCredit.line([work("brand direction"), work("the scan")]))
        XCTAssertTrue(line.contains("Luna's brand direction"), line)
        XCTAssertTrue(line.contains("2"), "a second contribution must be counted: \(line)")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/UpstreamCreditTests test 2>&1 | tail -12
```

Expected: FAIL — `cannot find 'UpstreamCredit' in scope`.

- [ ] **Step 3: Create the view**

`codepet/Views/Copilot/UpstreamCredit.swift` — a `line(_:)` static returning `nil` for empty, `"Built on Luna's brand direction"` for one, `"Built on Luna's brand direction + 1 more"` for several, with `" (unapproved draft)"` appended when any item is `unapproved`. The view renders that line at 11.5pt in `CodepetTheme.accentPurple` behind a 2pt leading rule, with `.cursorOnHover(.pointingHand)` and `onOpen` on tap.

- [ ] **Step 4: Mount it, above the payload preview**

In `draftCard`, immediately before the `DraftPayloadPreview` block from Task 1:

```swift
if let up = message.upstream, !up.isEmpty {
    UpstreamCredit(work: up) { _ in showDetail = true }
}
```

`ChatMessage` needs an `upstream: [UpstreamWork]?` field, set when the run result is filed. Read `CompanyStore`'s draft-filing path and add it alongside `execSteps`, which already travels the same way.

- [ ] **Step 5: The chain**

`CompanyStore.runChained(taskId:language:)`: resolve the task, find its `dependsOn` entries with no filed deliverable, run the first of those, file it as a draft, then run the requested task with `UpstreamWork.assemble` now including it — with `unapproved: true` on that item. **No approval gate between the two** (founder decision). In `MockChat`, answer a run whose dependencies are unfiled with a needs-upstream reply carrying `[Run both]` / `[Just mine]`, and have `runResult` mention `req.upstream` in the body so the demo demonstrates the mechanism.

- [ ] **Step 6: Run the tests, then commit**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
for s in UpstreamCreditTests UpstreamWorkTests DraftPayloadPreviewTests \
         DemoProjectMurrorTests MockFixtureRunnableTests; do
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/r-$s.xcresult test \
    > /tmp/log-$s.txt 2>&1
  echo "$s: $(xcrun xcresulttool get test-results summary --path /tmp/r-$s.xcresult 2>/dev/null | grep -E '"(passedTests|failedTests)"' | tr -d ' \n')"
done
```

A zero count means the suite did not run — treat that as a failure, not a pass.

```bash
cat > /tmp/c-t4.txt <<'EOF'
feat(chat): the card credits the departments it built on, and can run the chain

The credit names what the work inherited, and says "(unapproved draft)" when
a chained run passed it forward before approval. Founder decision: chained
runs do NOT stop for approval — halting stalls the founder who least knows
what they are approving — so the state is surfaced rather than hidden.

`RoadmapGating.awaitsApproval` is untouched: chaining moves work forward
inside the already-open phase window and never opens a phase.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add codepet/Views/Copilot/UpstreamCredit.swift codepet/Views/Copilot/CopilotChatView.swift \
        codepet/Managers/CompanyStore.swift codepet/Services/MockChat.swift \
        codepetTests/UpstreamCreditTests.swift
git commit -F /tmp/c-t4.txt
```

---

### Task 5: End-to-end verification

- [ ] **Step 1: Build signed and launch into Murror**

```bash
cd ~/Developer/codepet-two-mode
./scripts/build-sidecar.sh
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build 2>&1 | grep -oE "BUILD (SUCCEEDED|FAILED)"
APP=~/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app
open "$APP" --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
```

- [ ] **Step 2: Confirm on screen — the founder's step**

Screen Recording is denied on this machine, so these are checks only the founder can make:

1. "run pricing" → the card shows **four slider rows with values**, not a truncated paragraph
2. "run the landing page" → the card shows **Murror's navy swatch, brand and headline**, with Open
3. Approve the brand direction first, then run the landing page → the card reads **"Built on Luna's brand direction"**
4. On a fresh company, run the landing page → **needs-upstream card** with `[Run both]` / `[Just mine]`
5. "Run both" → two cards land in order, the second crediting **"(unapproved draft)"**

- [ ] **Step 3: Document the flag, and commit**

Add to `CLAUDE.md` under the prototype-mode section: a run now carries the approved deliverables of its `dependsOn` tasks, capped at 3 × 1500 chars in `dependsOn` order, and the card credits them; chained runs pass unapproved drafts forward and label them.

---

## Self-Review

**Spec coverage.** §1 → Task 1. §2 wire/assembly → Task 2; §2 prompt → Task 3. §3 chain and credit → Task 4. §4's thirteen tests are distributed: `everyKindWithAPayloadGetsAStructuredPreview`, `aNilPayloadFallsBackToProse`, `siteAccentGoesThroughSafeHex`, `previewIsHeightCapped` in Task 1; `upstreamIsAssembledFromDependsOn`, `upstreamSkipsUnfiledDependencies`, `upstreamIsCappedAtThreeAndClipped` in Task 2; `promptIncludesUpstreamAndItsInstruction`, `promptOmitsTheBlockWhenUpstreamIsEmpty`, `oneShotRunTaskForwardsUpstream` in Task 3; `creditIsAbsentWithoutUpstream`, `creditNamesTheDraftAsUnapproved`, `chainRunsUpstreamThenDownstream` in Task 4. §5's sidecar rebuild is Task 3 Step 5 and Task 5 Step 1.

**Gap found and closed.** The spec's `UpstreamWork` had five fields and no way to express "this came from a chained run and is not approved" — yet §3 requires the card to say exactly that. Added `unapproved: Bool = false`, threaded through the prompt block and `UpstreamCredit.line`. Without it Task 4's founder decision was unimplementable.

**Second gap.** The spec did not say how the credit reaches the card. `message.upstream` is added in Task 4 Step 4, alongside `execSteps`, which already travels that path.

**Type consistency.** `UpstreamWork`'s field names match across Swift and the TypeScript interface. `hasStructuredPreview`, `safeAccent`, `maxHeight`, `cap`, `bodyLimit`, `assemble(for:in:library:)` and `line(_:)` are used with the same names everywhere they appear.

**Known deviation.** Task 1 Step 3 and Task 4 Steps 3/5 specify the view bodies by structure, values and token names rather than as complete SwiftUI source. Every pure decision — the dispatch, the accent fallback, the caps, the credit string — is given as literal code because those are what the tests pin; the layout is specified tightly enough to build without inventing behaviour.
