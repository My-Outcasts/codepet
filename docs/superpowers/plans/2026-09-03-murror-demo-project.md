# Murror Demo Project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Murror as a second selectable prototype-mode demo company whose eight departments each have a runnable task, and make one of those runs produce a genuinely rendered website.

**Architecture:** Extract everything project-specific out of `MockChat`/`MockVirtualCompany` into a `DemoProject` value type with two instances (`.codepet`, carrying today's content verbatim, and `.murror`, new). Selection reads through `PrototypeMode.store` so XCTest isolation is inherited, and defaults to `.codepet` so all 236 existing test files stay green with no edit. `MockChat.runResult` gains payload support — the one mechanism change — which is what lets a run emit a `.site` deliverable that `SiteViewer` renders in a `WKWebView`.

**Tech Stack:** Swift 5, SwiftUI, XCTest, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Xcode 26.2, macOS deployment target 26.2.

**Spec:** `docs/superpowers/specs/2026-09-03-murror-demo-project-design.md`

## Global Constraints

- Everything added here is `#if DEBUG` — `MockChat`, `MockVirtualCompany` and `LibraryFixtures` all are, and the fixtures this touches compile out of a release build.
- `DemoProject.current` MUST read through `PrototypeMode.store`, never `UserDefaults.standard`. That property is redirected to a scratch suite wiped on creation under XCTest; reading `.standard` re-opens issue #117 in a second place.
- Default selection is `.codepet`. Existing suites (`MockFixtureRunnableTests`, `PrototypeParityTests`, `MockFlowTests`) must pass **unedited**.
- Codepet's deliverable entries are transcribed in the existing `if`-chain's order. The order is load-bearing: `t.contains("landing") || t.contains("copy")` precedes the generic fallback.
- Payloads are **decoded from JSON, never built memberwise**. `SitePayload` declares `init(from:)` so has no memberwise init, and a hand-built value could be a shape the decoder rejects.
- Room frames stay wire JSON decoded by the real `VirtualCompanyEvent.from(frame:)`.
- Site accent is `#0a1430`. `buildHTML` paints `accent` behind white text (`.btn.p`, `.step .n`, `.final`), so a light colour renders unreadable and `safeHex` will not catch it.
- New `.swift` files need no project-file edit — `PBXFileSystemSynchronizedRootGroup` means target membership follows the folder on disk.
- Commit messages via `git commit -F <file>`, never `-m`: bodies contain backticks and zsh would execute them.
- `xcodebuild test` exits 65 on a clean checkout because the XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates (~27 tests never finish, none actually fail). Run per-suite with `-only-testing:` and read counts from `xcresulttool get test-results summary`, never from the exit code.
- Quit the running `codepet.app` before any `xcodebuild test`: a live app (or a sibling build mid-run) kills the test host, with a different victim each run.

---

### Task 1: The `DemoProject` seam

Introduce the type and repoint every project-specific read at it, with `.codepet` as the only instance. No behaviour change — the existing suites are the regression gate.

**Files:**
- Create: `codepet/Demo/DemoProject.swift`
- Create: `codepet/Demo/DemoProjectCodepet.swift`
- Modify: `codepet/Services/MockChat.swift` — `productName`, `company()`, `roadmap()`, `deliverable(for:)`
- Modify: `codepet/Services/MockVirtualCompany.swift` — `frames(ask:)`
- Test: `codepetTests/DemoProjectTests.swift`

**Interfaces:**
- Consumes: `PrototypeMode.store` (existing, `UserDefaults`), `CompanyBrief`, `RoadmapTask`, `SSEFrame`
- Produces: `DemoProject` (`.id`, `.brief`, `.tasks`, `.deliverables`, `.roomFrames`, `.deliverable(for:)`), `DemoDeliverable`, `DemoProject.current`, `DemoProject.select(_:)`, `DemoProject.codepet`, `DemoProject.launchKey` = `"CODEPET_DEMO_PROJECT"`, `DemoProject.key` = `"cp_demoProject"`

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/DemoProjectTests.swift`:

```swift
// codepetTests/DemoProjectTests.swift
import XCTest
@testable import codepet

/// Guards on the demo-project selector.
///
/// The selector is a second prototype-mode preference, and #117 was caused by the first one
/// being read off `UserDefaults.standard` — the XCTest host IS the app, so it shares that
/// domain and a founder's toggle changed what the suite exercised. `isolation` below is the
/// test that would have caught it.
final class DemoProjectTests: XCTestCase {

    override func tearDown() {
        PrototypeMode.store.removeObject(forKey: DemoProject.key)
        super.tearDown()
    }

    func testDefaultsToCodepet() {
        PrototypeMode.store.removeObject(forKey: DemoProject.key)
        XCTAssertEqual(DemoProject.current.id, "codepet")
    }

    func testSelectionIsIsolatedFromStandardDefaults() {
        UserDefaults.standard.removeObject(forKey: DemoProject.key)
        DemoProject.select("murror")
        XCTAssertNil(UserDefaults.standard.object(forKey: DemoProject.key),
                     "the selector must not write to the founder's real preferences (#117)")
    }

    func testSelectionRoundTrips() {
        DemoProject.select("murror")
        XCTAssertEqual(DemoProject.current.id, "murror")
    }

    func testUnknownIdFallsBackToCodepet() {
        DemoProject.select("nonesuch")
        XCTAssertEqual(DemoProject.current.id, "codepet")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectTests test 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'DemoProject' in scope`.

- [ ] **Step 3: Create the type and the selection seam**

Create `codepet/Demo/DemoProject.swift`:

```swift
// codepet/Demo/DemoProject.swift
#if DEBUG
import Foundation

/// One canned deliverable a demo project's pet can produce.
///
/// `payloadJSON` is nil for every kind but `.site`: the structured viewers decode a payload,
/// and the markdown ones read `body`. It stays a JSON string rather than a decoded value so
/// the fixture is the exact shape the Cloud Function puts on the wire — a payload built from
/// Swift values could be a shape the decoder rejects.
struct DemoDeliverable {
    /// Matched against the lowercased task title, first match wins.
    let keywords: [String]
    /// A `DeliverableKind` rawValue.
    let kind: String
    /// Markdown. May contain the `{{product}}` token.
    let body: String
    let payloadJSON: String?

    init(keywords: [String], kind: String, body: String, payloadJSON: String? = nil) {
        self.keywords = keywords
        self.kind = kind
        self.body = body
        self.payloadJSON = payloadJSON
    }
}

/// A whole demo company: the brief, the board, what each pet produces, and the room.
///
/// This exists because prototype mode could show the product but not a *project*. Every
/// fixture read used to be a literal inside `MockChat`, so the demo was Codepet demoing
/// Codepet — `productName` substituted the project NAME while every word around the token
/// stayed Codepet's, which is the find-replace feel `MockChat.swift`'s token comment says the
/// token exists to prevent.
struct DemoProject {
    let id: String
    let brief: CompanyBrief
    let tasks: [RoadmapTask]
    let deliverables: [DemoDeliverable]
    let roomFrames: [SSEFrame]

    /// First entry whose keyword appears in the title. Order is load-bearing — specific
    /// entries must precede the catch-all.
    func deliverable(for title: String) -> DemoDeliverable {
        let t = title.lowercased()
        return deliverables.first { d in d.keywords.contains { t.contains($0) } }
            ?? deliverables[deliverables.count - 1]
    }

    // MARK: - Selection

    /// Forced from the command line: `-CODEPET_DEMO_PROJECT murror`.
    static let launchKey = "CODEPET_DEMO_PROJECT"
    /// The persisted preference.
    static let key = "cp_demoProject"

    static let all: [DemoProject] = [.codepet, .murror]

    /// **Read through `PrototypeMode.store`, not `UserDefaults.standard`.**
    ///
    /// That property is already redirected to a scratch suite, wiped on creation, whenever
    /// `XCTestConfigurationFilePath` is set — the fix for #117, where a founder clicking the
    /// prototype toggle changed what the test target exercised and a green run told nobody.
    /// A second demo-mode preference read off `.standard` would re-open exactly that hole in
    /// a second place, so the seam is reused rather than re-implemented.
    ///
    /// A launch argument wins, because `NSArgumentDomain` outranks every preference file —
    /// the same precedence that makes `PrototypeMode.launchKeys` reliable.
    static var current: DemoProject {
        let chosen = PrototypeMode.store.string(forKey: launchKey)
            ?? PrototypeMode.store.string(forKey: key)
        return all.first { $0.id == chosen } ?? .codepet
    }

    static func select(_ id: String) {
        PrototypeMode.store.set(id, forKey: key)
    }
}
#endif
```

- [ ] **Step 4: Move Codepet's content into `.codepet`**

Create `codepet/Demo/DemoProjectCodepet.swift`. Transcribe, verbatim and in existing order:

- `brief` — from `MockChat.company()`'s fallback: `founderName` "Mona", `projectName` "Codepet", `oneLiner` "Your AI cofounder that runs the whole company with you.", `stage` "building"
- `tasks` — the 13 entries of `MockChat.roadmap()`, unchanged, including the `dependsOn` graph and its comments
- `deliverables` — each branch of `MockChat.deliverable(for:)` in chain order, keywords taken from that branch's `t.contains(...)` terms, ending with the existing fallback as the last entry
- `roomFrames` — the array returned by `MockVirtualCompany.frames(ask:)`

`frames(ask:)` interpolates the founder's question into `real_question`. Keep that: give `DemoProject` a `roomFrames` array built by a function taking the ask, i.e. change the stored property to:

```swift
let roomFrames: (String) -> [SSEFrame]
```

and have `MockVirtualCompany.frames(ask:)` become `DemoProject.current.roomFrames(ask)`.

- [ ] **Step 5: Repoint MockChat and MockVirtualCompany**

In `codepet/Services/MockChat.swift`:

```swift
static var productName: String {
    let typed = (flowBrief?.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !typed.isEmpty { return typed }
    return DemoProject.current.brief.projectName ?? "Codepet"
}

static func company() -> CompanyState {
    var brief = flowBrief ?? DemoProject.current.brief
    if (brief.stage ?? "").isEmpty { brief.stage = "building" }
    return CompanyState(brief: brief, departments: [], library: [], stage: .building,
                        companionId: "byte", onboardedAt: Date(), tasks: roadmap())
}

static func roadmap() -> [RoadmapTask] { DemoProject.current.tasks }

private static func deliverable(for title: String) -> (kind: String, body: String) {
    let d = DemoProject.current.deliverable(for: title)
    return (d.kind, d.body)
}
```

In `codepet/Services/MockVirtualCompany.swift`, replace the body of `frames(ask:)`:

```swift
static func frames(ask: String) -> [SSEFrame] { DemoProject.current.roomFrames(ask) }
```

Keep the file's doc comment — it records the nine rendering rules and why the frames are wire JSON.

- [ ] **Step 6: Run the new tests plus the three regression suites**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectTests \
  -only-testing:codepetTests/MockFixtureRunnableTests \
  -only-testing:codepetTests/PrototypeParityTests \
  -only-testing:codepetTests/MockFlowTests \
  -resultBundlePath /tmp/t1.xcresult test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/t1.xcresult | head -30
```

Expected: all four suites pass, 0 failures. `.murror` does not exist yet, so `testSelectionRoundTrips` will fail — add a placeholder `static let murror = codepet` renamed with `id: "murror"` **only if** you need Task 1 green in isolation; otherwise leave that one test failing and let Task 2 turn it green. Note which you chose in the commit message.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet-two-mode
cat > /tmp/c1.txt <<'EOF'
refactor(demo): extract the fixture content behind a DemoProject seam

No behaviour change: `.codepet` carries today's brief, board, deliverables
and room frames verbatim, and `DemoProject.current` defaults to it, so the
existing suites pass unedited.

Selection reads `PrototypeMode.store` rather than `UserDefaults.standard`.
That property is already redirected to a scratch suite under XCTest (the
#117 fix); a second prototype-mode preference read off `.standard` would
re-open the same hole in a second place.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add codepet/Demo/DemoProject.swift codepet/Demo/DemoProjectCodepet.swift \
        codepet/Services/MockChat.swift codepet/Services/MockVirtualCompany.swift \
        codepetTests/DemoProjectTests.swift
git commit -F /tmp/c1.txt
```

---

### Task 2: Murror's brief and board

**Files:**
- Create: `codepet/Demo/DemoProjectMurror.swift`
- Test: `codepetTests/DemoProjectMurrorTests.swift`

**Interfaces:**
- Consumes: `DemoProject`, `DemoDeliverable`, `CompanyBrief`, `RoadmapTask`, `RoadmapEngine.status(for:in:)`, `DepartmentCatalog.roster`, `DepartmentCompanions.companionId(for:)`
- Produces: `DemoProject.murror` with `brief`, `tasks` (11 entries), and — filled in Tasks 3 and 4 — `deliverables` and `roomFrames`

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/DemoProjectMurrorTests.swift`:

```swift
// codepetTests/DemoProjectMurrorTests.swift
import XCTest
@testable import codepet

/// Guards on the Murror demo company.
///
/// The claim this suite exists to hold is "all eight pets are runnable the moment the demo
/// opens". That is not a property of any one task — it is a property of the dependency graph,
/// and `RoadmapEngine.status` is the only thing that can confirm it. So the tests assert
/// through the engine rather than reading fields and inferring.
final class DemoProjectMurrorTests: XCTestCase {

    private var murror: DemoProject { DemoProject.murror }
    private var runnable: [RoadmapTask] { murror.tasks.filter { !$0.done } }

    /// The invariant behind "all eight runnable": a task is blocked unless every id in
    /// `dependsOn` resolves to a task that is `done`. Adding a dep on an open task would
    /// silently un-run a pet, and the roster would look identical.
    func testEveryRunnableDependsOnlyOnDoneTasks() {
        let byId = Dictionary(uniqueKeysWithValues: murror.tasks.map { ($0.id, $0) })
        for task in runnable {
            for dep in task.dependsOn {
                guard let prereq = byId[dep] else {
                    return XCTFail("\(task.id) depends on \(dep), which is not in the fixture")
                }
                XCTAssertTrue(prereq.done,
                              "\(task.id) depends on \(dep), which is not done — \(task.id) is blocked")
            }
        }
    }

    func testAllEightRosterDepartmentsHaveExactlyOneRunnable() {
        let byDept = Dictionary(grouping: runnable) { $0.dept ?? "" }
        let expected = Set(DepartmentCatalog.roster.map(\.key))
        XCTAssertEqual(Set(byDept.keys), expected)
        for (dept, tasks) in byDept {
            XCTAssertEqual(tasks.count, 1, "\(dept) has \(tasks.count) runnable tasks, expected 1")
        }
    }

    /// The end-to-end claim: the engine itself says every one of the eight is runnable.
    func testEveryRunnableIsCodepetCanDo() {
        for task in runnable {
            XCTAssertEqual(RoadmapEngine.status(for: task, in: murror.tasks), .codepetCanDo,
                           "\(task.id) is not runnable")
        }
    }

    /// A task tagged with a pet-less department (`product`) would render a roster card with
    /// no pet to speak for it.
    func testEveryMurrorDeptHasAPet() {
        for task in murror.tasks {
            let dept = task.dept ?? ""
            XCTAssertNotNil(DepartmentCompanions.companionId(for: dept),
                            "\(task.id) is tagged \(dept), which has no pet")
        }
    }

    func testFindPhaseIsComplete() {
        let find = murror.tasks.filter { $0.phase == .find }
        XCTAssertFalse(find.isEmpty)
        XCTAssertTrue(find.allSatisfy(\.done), "the mid-flight start state needs .find complete")
    }

    /// No fixture task may set `drafted`: an unapproved draft closes the phase window and
    /// would block everything behind it regardless of the dependency graph.
    func testNoTaskIsDrafted() {
        XCTAssertTrue(murror.tasks.allSatisfy { !$0.drafted })
    }

    func testBriefIsMurror() {
        XCTAssertEqual(murror.brief.projectName, "Murror")
        XCTAssertEqual(murror.id, "murror")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectMurrorTests test 2>&1 | tail -20
```

Expected: FAIL — `type 'DemoProject' has no member 'murror'`.

- [ ] **Step 3: Write the brief and the eleven tasks**

Create `codepet/Demo/DemoProjectMurror.swift` with `extension DemoProject { static let murror = ... }`.

Brief — Murror's real positioning, from murror.app:

```swift
var b = CompanyBrief()
b.founderName = "Mona"
b.projectName = "Murror"
b.oneLiner = "AI that brings people closer."
b.audience = "Adults who feel lonely and want to be closer to the people they love"
b.problem = "Most of us were never taught how to understand what we feel, or how to show up for someone else."
b.goal = "Get 20 people through a first week of the practice and see who comes back."
b.stage = "building"
```

Tasks — exactly these eleven. Three `done` form the completed spine; the eight runnable depend **only** on done tasks, which is what `testEveryRunnableDependsOnlyOnDoneTasks` holds:

| id | title | phase | who | done | dept | dependsOn |
|---|---|---|---|---|---|---|
| `mur-interviews` | Talk to 12 people about being lonely | `.find` | `.you` | ✓ | `mkt` | — |
| `mur-landscape` | Scan the journaling and companion apps | `.find` | `.draft` | ✓ | `mkt` | — |
| `mur-brand` | Shape the Murror visual direction | `.foundation` | `.draft` | ✓ | `design` | `mur-landscape` |
| `mur-site` | Build the Murror landing page | `.foundation` | `.draft` | | `mkt` | `mur-brand`, `mur-landscape` |
| `mur-screens` | Design the first-run flow | `.foundation` | `.draft` | | `design` | `mur-brand` |
| `mur-pricing` | Decide what free and paid mean | `.foundation` | `.draft` | | `fin` | `mur-landscape` |
| `mur-signup` | Ship an email capture | `.build` | `.does` | | `eng` | `mur-brand` |
| `mur-outreach` | Find the first 20 users | `.build` | `.draft` | | `sales` | `mur-interviews`, `mur-landscape` |
| `mur-faq` | Answer the first questions | `.build` | `.draft` | | `support` | `mur-interviews` |
| `mur-launch` | Write the launch checklist | `.ship` | `.does` | | `ops` | `mur-brand` |
| `mur-privacy` | Draft the privacy policy | `.ship` | `.draft` | | `legal` | `mur-interviews` |

Each `detail` is one sentence in the founder's register — e.g. `mur-site`: "One page that says what the practice is, for someone who has never heard of it."

Document the routing intent in a doc comment, as `MockChat.roadmap()` does, so the graph is not "tidied" away: `mur-site` is the fan-IN and its `mur-landscape` leg is a shared-lane straight run (`mkt`→`mkt`); `mur-brand`→`mur-screens` is the in-column `sideElbow` case; `mur-brand`→`mur-launch` and `mur-interviews`→`mur-privacy` are the skip-level cases.

Leave `deliverables` and `roomFrames` referencing Task 3/4 stubs so the file compiles: set `deliverables: DemoProject.codepet.deliverables` and `roomFrames: DemoProject.codepet.roomFrames` for now, and replace both in the next tasks.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectMurrorTests \
  -only-testing:codepetTests/DemoProjectTests \
  -resultBundlePath /tmp/t2.xcresult test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/t2.xcresult | head -30
```

Expected: PASS, 0 failures, including `testSelectionRoundTrips` from Task 1.

- [ ] **Step 5: Break one guard on purpose and watch it go red**

The fixture-tracing rule: a test whose fixture cannot fail is not a test. Temporarily change `mur-site`'s `dependsOn` to include `mur-screens` (which is not done), re-run, and confirm both `testEveryRunnableDependsOnlyOnDoneTasks` and `testEveryRunnableIsCodepetCanDo` fail. Then revert.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-two-mode
cat > /tmp/c2.txt <<'EOF'
feat(demo): Murror's brief and board, with all eight pets runnable

Eleven tasks: a three-task completed spine in .find/.foundation, and eight
runnable tasks across the eight roster departments.

The eight depend ONLY on done tasks, which is what makes them runnable at
all — `RoadmapEngine.depsSatisfied` blocks a task whose prerequisite is
open, and the roster would look identical either way. A test asserts it
through the engine rather than by reading fields.

The graph still exercises each routing case once: fan-IN on mur-site,
in-column brand->screens, and two skip-level edges.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add codepet/Demo/DemoProjectMurror.swift codepetTests/DemoProjectMurrorTests.swift
git commit -F /tmp/c2.txt
```

---

### Task 3: The eight deliverables, and the website

**Files:**
- Modify: `codepet/Demo/DemoProjectMurror.swift` — replace the `deliverables` stub
- Modify: `codepet/Services/MockChat.swift` — `runResult` payload support
- Test: `codepetTests/DemoProjectMurrorTests.swift` — add the cases below

**Interfaces:**
- Consumes: `DemoDeliverable`, `DeliverablePayload`, `SitePayload`, `RunTaskRequest`, `RunTaskResponse`
- Produces: `MockChat.runResult` returning a non-nil `payload` when the matched entry carries `payloadJSON`

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/DemoProjectMurrorTests.swift`:

```swift
extension DemoProjectMurrorTests {

    /// Eight tasks, eight different viewers — so the demo walks eight of the twelve without
    /// any task being chosen to fill a slot.
    func testEveryRunnableResolvesToADistinctKind() {
        let kinds = runnable.map { murror.deliverable(for: $0.title).kind }
        XCTAssertEqual(kinds.count, 8)
        XCTAssertEqual(Set(kinds).count, 8, "kinds collide: \(kinds.sorted())")
    }

    /// `SitePayload.init(from:)` hard-decodes six anchor fields and throws when any is
    /// absent, so this fails the moment the fixture would render a broken page.
    func testSitePayloadDecodes() throws {
        let entry = murror.deliverable(for: "Build the Murror landing page")
        XCTAssertEqual(entry.kind, "site")
        let json = try XCTUnwrap(entry.payloadJSON)
        let payload = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
        let site = try XCTUnwrap(payload.site, "the site payload did not decode")
        XCTAssertEqual(site.brand, "Murror")
        XCTAssertFalse(site.headline.isEmpty)
        XCTAssertEqual(site.steps.count, 3)
        XCTAssertEqual(site.features.count, 4)
    }

    /// `buildHTML` paints `accent` behind white text in three places and `safeHex` validates
    /// hex SYNTAX, not contrast — so nothing else in the codebase would catch a brand colour
    /// that renders white-on-pale. Murror's warm gold (#ffecb4) is exactly that trap.
    func testSiteAccentIsDarkEnoughForWhiteText() throws {
        let entry = murror.deliverable(for: "Build the Murror landing page")
        let json = try XCTUnwrap(entry.payloadJSON)
        let payload = try JSONDecoder().decode(DeliverablePayload.self, from: Data(json.utf8))
        let hex = try XCTUnwrap(payload.site?.accent)
        let luminance = try relativeLuminance(hex)
        XCTAssertLessThan(luminance, 0.4,
                          "\(hex) is too light to sit behind white text")
    }

    private func relativeLuminance(_ hex: String) throws -> Double {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let n = try XCTUnwrap(UInt32(digits, radix: 16))
        func channel(_ raw: UInt32) -> Double {
            let c = Double(raw) / 255.0
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((n >> 16) & 0xFF)
             + 0.7152 * channel((n >> 8) & 0xFF)
             + 0.0722 * channel(n & 0xFF)
    }

    /// The one mechanism change: `runResult` used to hardcode `payload: nil`, which is why
    /// no run could ever produce a website.
    func testRunResultCarriesTheSitePayload() async {
        DemoProject.select("murror")
        defer { PrototypeMode.store.removeObject(forKey: DemoProject.key) }
        let req = RunTaskRequest(taskId: "mur-site", taskTitle: "Build the Murror landing page")
        let res = await MockChat.runResult(req)
        XCTAssertEqual(res?.kind, "site")
        XCTAssertNotNil(res?.payload?.site, "the run produced no site payload")
    }
}
```

`RunTaskRequest`'s initialiser may need more arguments — read `codepet/Services/RunTaskClient.swift` and pass whatever it requires; `taskId` and `taskTitle` are the two the mock reads.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectMurrorTests test 2>&1 | tail -20
```

Expected: FAIL — kinds collide (the stub is Codepet's table) and `payload` is nil.

- [ ] **Step 3: Write the site payload**

In `codepet/Demo/DemoProjectMurror.swift`, the `mur-site` entry. Content is Murror's own, and `accent` is its dominant midnight navy — see Global Constraints for why the gold cannot be used:

```swift
DemoDeliverable(
    keywords: ["landing page", "landing", "website", "site"],
    kind: "site",
    body: """
    The page is live in your Library — open it to see it rendered.

    **What it says** — the practice, not the technology. The headline is the promise
    (*"AI that brings people closer"*), the three steps are the loop someone actually
    repeats, and the four features are what makes it feel safe enough to be honest in.

    **What it leaves out** — the model, the roadmap, and the word "AI" anywhere except
    the headline, where it is the thing being promised rather than the thing being sold.
    """,
    payloadJSON: """
    {"title":"Murror","brand":"Murror","kicker":"THE CONNECTION PRACTICE",
     "headline":"AI that brings people","headlineHi":"closer",
     "sub":"Most of us were never taught how to understand what we feel, or how to show up for the people we love. Murror is a daily practice for both.",
     "ctaPrimary":"Start free","ctaSecondary":"See how it works",
     "howEyebrow":"How it works","howTitle":"Three steps, every day",
     "steps":[{"h":"Name what you feel","p":"Say it badly, in your own words. Murror helps you find the more accurate word for it."},
              {"h":"See the pattern","p":"The same feeling keeps arriving on the same kind of day. That is the useful part."},
              {"h":"Reach out","p":"One small, specific message to one real person — written by you, unstuck by us."}],
     "featEyebrow":"What you get","featTitle":"A practice, not a feed",
     "features":[{"h":"Emotion recognition","p":"See what you feel, in words precise enough to act on."},
                 {"h":"Relationship insights","p":"Who you have drifted from, and what you last talked about."},
                 {"h":"Small acts of care","p":"A prompt when someone you love has gone quiet."},
                 {"h":"Private by design","p":"Your feelings are not training data, and never leave with your name on them."}],
     "quote":"I used the word lonely out loud for the first time in a year, and it was to an app. Then I sent the message.",
     "quoteBy":"an early user",
     "finalTitle":"Start with one feeling","finalSub":"Free to start.","finalCta":"Open Murror",
     "accent":"#0a1430","footNote":"Made by MURROR"}
    """)
```

- [ ] **Step 4: Write the other seven deliverables**

Same file, in this order — specific keywords first, and the last entry is the catch-all so `deliverable(for:)`'s fallback is never reached by accident:

| keywords | kind | body |
|---|---|---|
| `first-run`, `flow`, `screens`, `onboarding` | `screens` | 4 screens: welcome, name a feeling, the pattern, the first message. Payload JSON per `Screen`'s shape. |
| `free and paid`, `pricing`, `price` | `sheet` | Free vs Practice ($6/mo): what each includes, with the reasoning that the paid tier sells *history*, not more AI |
| `email capture`, `signup`, `sign up`, `capture` | `checklist` | 5 steps to ship a one-field capture with no backend |
| `first 20`, `outreach`, `users` | `dms` | 3 messages to 3 real audiences (a subreddit, a group chat, a therapist), each specific and none pitching |
| `first questions`, `faq`, `support` | `doc` | 6 Q&As, opening with "Is this therapy?" — answered honestly with "No" |
| `launch checklist`, `launch` | `plan` | A dated pre/launch/after plan with a crisis-path check as a blocking item |
| `privacy`, `policy` | `legal` | Plain-language policy: what is collected, what is never trained on, how to delete everything |

Every body is written in that pet's register — `crash` (fin) is blunt and short, `sage` (support) is patient, `glitch` (ops/legal) is precise about edges, `luna` (design) talks about how it feels, `nova` (mkt/sales) leads with the promise, `byte` (eng) is concrete about mechanics. Use `{{product}}` for the name so the token keeps working.

Only `mur-site` carries a `payloadJSON` beyond `screens`; the rest read `body`.

- [ ] **Step 5: Give `runResult` payload support**

In `codepet/Services/MockChat.swift`, replace `runResult`:

```swift
static func runResult(_ req: RunTaskRequest) async -> RunTaskResponse? {
    try? await Task.sleep(nanoseconds: 700_000_000)  // "producing…" beat
    let entry = DemoProject.current.deliverable(for: req.taskTitle)
    let note = req.reviseNote.map { "\n\n_Revised per your note: \($0)_" } ?? ""
    // Decoded, not built memberwise: `SitePayload.init(from:)` throws on a missing anchor
    // field, so a fixture that would render a broken page fails here instead of on screen.
    let payload = entry.payloadJSON.flatMap {
        try? JSONDecoder().decode(DeliverablePayload.self, from: Data($0.utf8))
    }
    return RunTaskResponse(kind: entry.kind, title: req.taskTitle,
                           body: fill(entry.body + note), payload: payload)
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectMurrorTests \
  -only-testing:codepetTests/MockFixtureRunnableTests \
  -only-testing:codepetTests/LibraryFixturesTests \
  -resultBundlePath /tmp/t3.xcresult test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/t3.xcresult | head -30
```

Expected: PASS, 0 failures.

- [ ] **Step 7: Render the page and look at it**

`buildHTML` is a pure `SitePayload → String`, so the real HTML can be produced without the app. Write a temporary test that decodes the payload, calls `SiteViewer.buildHTML`, and writes the result to `/tmp/murror-site.html`; run it, then `open /tmp/murror-site.html`. Confirm: white CTA text is readable on the navy, the three steps and four features all render, and nothing is blank. Delete the temporary test afterwards.

- [ ] **Step 8: Commit**

```bash
cd ~/Developer/codepet-two-mode
cat > /tmp/c3.txt <<'EOF'
feat(demo): eight Murror deliverables, and a run that produces a website

`runResult` hardcoded `payload: nil`, which is why the .site viewer — a real
landing page in a WKWebView — was unreachable from a run. It now decodes the
matched entry's payloadJSON, so "run the landing page" produces a page.

Eight deliverables across eight distinct kinds, one per department, each in
its pet's register.

The accent is Murror's midnight navy, not its gold. `buildHTML` paints
`accent` behind white text in three places and `safeHex` validates hex
syntax rather than contrast, so the gold would have rendered white-on-pale
with nothing to catch it. A luminance test now does.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add codepet/Demo/DemoProjectMurror.swift codepet/Services/MockChat.swift \
        codepetTests/DemoProjectMurrorTests.swift
git commit -F /tmp/c3.txt
```

---

### Task 4: Murror's room

**Files:**
- Modify: `codepet/Demo/DemoProjectMurror.swift` — replace the `roomFrames` stub
- Test: `codepetTests/DemoProjectMurrorTests.swift` — add the cases below

**Interfaces:**
- Consumes: `SSEFrame`, `VirtualCompanyEvent.from(frame:)`
- Produces: `DemoProject.murror.roomFrames`

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/DemoProjectMurrorTests.swift`:

```swift
extension DemoProjectMurrorTests {

    /// The whole value of building the fixture on the wire format: a renamed key shows up
    /// here rather than as a missing card in the app.
    func testEveryRoomFrameDecodes() {
        let frames = murror.roomFrames("Should we ship emotion detection before a clinician reviews it?")
        XCTAssertFalse(frames.isEmpty)
        for frame in frames {
            XCTAssertNotNil(VirtualCompanyEvent.from(frame: frame),
                            "frame '\(frame.event)' did not decode")
        }
    }

    /// Contract rule 2: never collapse the positions into consensus. Consensus is what a
    /// fixture fakes most easily, so the room must still be unresolved at the end.
    func testRoomDoesNotResolve() throws {
        let frames = murror.roomFrames("anything")
        let brief = try XCTUnwrap(frames.first { $0.event == "brief" })
        XCTAssertTrue(brief.data.contains("\"unresolved\":true"))
    }

    func testRoomConvenesFourDepartments() throws {
        let frames = murror.roomFrames("anything")
        let starts = frames.filter { $0.event == "agent_position" }
        XCTAssertEqual(starts.count, 4)
        for dept in ["legal", "design", "support", "eng"] {
            XCTAssertTrue(frames.contains { $0.data.contains("\"department_key\":\"\(dept)\"") },
                          "\(dept) has no position in the room")
        }
    }

    /// The ask is interpolated into `real_question`, so a quote mark in it must not produce
    /// invalid JSON and silently drop the routing frame — which is the whole room.
    func testRoomSurvivesAQuotedAsk() {
        let frames = murror.roomFrames("do we ship \"emotion detection\" now?")
        let routing = frames.first { $0.event == "routing" }
        XCTAssertNotNil(routing.flatMap { VirtualCompanyEvent.from(frame: $0) })
    }

    /// Nothing was spent. A fixture reporting a dollar figure would be inventing a charge in
    /// the one place the founder checks for real ones.
    func testRoomReportsZeroCost() throws {
        let frames = murror.roomFrames("anything")
        let telemetry = try XCTUnwrap(frames.first { $0.event == "telemetry" })
        XCTAssertTrue(telemetry.data.contains("\"cost_estimate_usd\":0"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectMurrorTests test 2>&1 | tail -20
```

Expected: FAIL — `testRoomConvenesFourDepartments` finds 3 (the Codepet stub) and the depts are `fin`/`mkt`/`eng`.

- [ ] **Step 3: Write the room**

In `codepet/Demo/DemoProjectMurror.swift`, mirroring `MockVirtualCompany`'s frame order exactly: `run_started`, `routing`, then `agent_start`+`agent_position` per agent, `conflicts`, `negotiation_round`, `devils_advocate`, `brief`, `telemetry`, `done`.

The question: **should emotion detection ship before a clinician reviews it?**

| agent | `department_key` | `stance` | position | `hard_blocker` |
|---|---|---|---|---|
| legal | `legal` | `do_not_proceed` | Naming someone's emotional state is a claim. Unreviewed, it is a health claim. | "No clinician has read a single one of the labels we generate." |
| design | `design` | `proceed` | Without it the app is a blank text box, and a blank box teaches nobody anything. | `null` |
| support | `support` | `proceed_with_conditions` | Ship it only behind a crisis path. Someone will type the worst day of their life into this. | `null` |
| engineering | `eng` | `proceed_with_conditions` | The model is ready. The crisis routing is two weeks and cannot be faked. | `null` |

`routing` must carry `agent_meta` with all four `agent_id`/`department_key` pairs, `reason_per_agent` for each, and `excluded` for `mkt` and `fin`. `conflicts`: a `BLOCKER` between legal and design, a `TENSION` between support and design. One `negotiation_round` where each turn carries `precise_disagreement`, `what_would_change_my_mind`, `proposal`, `resolved: false`.

`devils_advocate` gets `department_key: null` — the contract is explicit that it must not wear a department colour. Its `load_bearing_assumption`: that a label helps at all, when the useful thing might be the act of typing rather than what comes back.

`brief` ends `unresolved: true`, with `tradeoff_founder_must_own` stated as a real either/or. `telemetry` reports `cost_estimate_usd: 0`.

Reuse the private `json(_:)` encoder for the ask — copy it into this file or make it internal on `DemoProject`; `testRoomSurvivesAQuotedAsk` is what holds it.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectMurrorTests \
  -only-testing:codepetTests/MockVirtualCompanyTests \
  -resultBundlePath /tmp/t4.xcresult test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/t4.xcresult | head -30
```

Expected: PASS, 0 failures. If `MockVirtualCompanyTests` does not exist, drop that flag.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet-two-mode
cat > /tmp/c5.txt <<'EOF'
feat(demo): Murror's room — four departments, one hard blocker

Codepet's room convenes three departments on its own paywall question, so
sage and glitch had no voice anywhere in the demo. Murror's asks whether
emotion detection ships before a clinician reviews it: legal hard-blocks,
design pushes, support and engineering set conditions.

Ends `unresolved: true` per contract rule 6, and reports zero cost because
nothing was spent. Frames stay wire JSON decoded by the real
`VirtualCompanyEvent.from(frame:)`, so a renamed key fails a test rather
than dropping a card on screen.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add codepet/Demo/DemoProjectMurror.swift codepetTests/DemoProjectMurrorTests.swift
git commit -F /tmp/c5.txt
```

---

### Task 5: End-to-end verification

**Files:**
- Modify: `CLAUDE.md` — document `-CODEPET_DEMO_PROJECT`
- No source changes expected; this task proves the whole thing works in the real app.

**Interfaces:**
- Consumes: everything above

- [ ] **Step 1: Run the full affected suite set**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
for s in DemoProjectTests DemoProjectMurrorTests MockFixtureRunnableTests \
         PrototypeParityTests PrototypeModeTests PrototypeModeIsolationTests \
         MockFlowTests LibraryFixturesTests; do
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/r-$s.xcresult test \
    > /tmp/log-$s.txt 2>&1
  echo "$s: $(xcrun xcresulttool get test-results summary --path /tmp/r-$s.xcresult 2>/dev/null | grep -iE 'passed|failed' | head -2 | tr '\n' ' ')"
done
```

Expected: every suite passes. A zero count means the suite did not run — treat it as a failure, not a pass.

- [ ] **Step 2: Build signed and launch into the Murror demo**

```bash
cd ~/Developer/codepet-two-mode
./scripts/build-sidecar.sh
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build 2>&1 | tail -5
APP=~/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app
open "$APP" --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
```

The launch argument is used rather than the toggle because `NSArgumentDomain` outranks the preference file, so the demo cannot be half-on.

- [ ] **Step 3: Confirm on screen**

Screen Recording is denied on this machine, so this step is the founder's. Check:
1. The company reads **Murror**, not Codepet
2. The Company page shows 8 department cards, each with a pet and a pending task
3. The roadmap shows `.find` complete and 8 runnable cards with real edges — not an 8-way spray
4. "run the landing page" produces a card; Approve files it; opening it in the Library renders **the website**
5. Convening the room brings in legal, design, support and engineering, and it ends unresolved

- [ ] **Step 4: Document the flag**

Add to `CLAUDE.md` under the prototype-mode notes:

```markdown
- **`-CODEPET_DEMO_PROJECT murror`** picks the second demo company. Default is `codepet`.
  Selection is read through `PrototypeMode.store`, so it is scratch-isolated under XCTest —
  a test cannot retarget the suite and a founder's choice cannot leak into it (#117).
  `DemoProject.murror` is the only fixture whose run produces a `.site`.
```

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet-two-mode
cat > /tmp/c6.txt <<'EOF'
docs: how to launch the Murror demo

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
git add CLAUDE.md
git commit -F /tmp/c6.txt
```

---

## Self-Review

**Spec coverage.** §1 `DemoProject` seam → Task 1. §2 website + `runResult` payload + accent → Task 3. §3 board → Task 2. §4 room → Task 4. §5's eleven tests → distributed: `defaultsToCodepet`/`selectionIsIsolatedFromStandardDefaults` in Task 1; `everyRunnableDependsOnlyOnDoneTasks`/`allEightRosterDepartmentsHaveExactlyOneRunnable`/`everyRunnableIsCodepetCanDo`/`everyMurrorDeptHasAPet` in Task 2; `everyRunnableResolvesToADistinctKind`/`sitePayloadDecodes`/`siteAccentIsDarkEnoughForWhiteText` in Task 3; `everyRoomFrameDecodes`/`roomDoesNotResolve` in Task 4. All ten spec tests are placed, plus six the plan adds (`selectionRoundTrips`, `unknownIdFallsBackToCodepet`, `findPhaseIsComplete`, `noTaskIsDrafted`, `briefIsMurror`, `runResultCarriesTheSitePayload`, `roomConvenesFourDepartments`, `roomSurvivesAQuotedAsk`, `roomReportsZeroCost`).

**Gap found and closed.** The spec did not say what happens to `frames(ask:)`'s ask interpolation when the frames move behind `DemoProject`. Task 1 Step 4 changes `roomFrames` to `(String) -> [SSEFrame]` and Task 4 adds `roomSurvivesAQuotedAsk`, since a quote mark in the ask would otherwise produce invalid JSON and drop the routing frame — the whole room.

**Type consistency.** `DemoProject.key`/`launchKey` are used identically in Tasks 1, 3 and 5. `deliverable(for:)` returns `DemoDeliverable` throughout; `MockChat.deliverable(for:)` keeps its `(kind:body:)` tuple so its existing callers are untouched. `roomFrames` is a closure in every task that references it.

**Known deviation from the skill's granularity rule.** Tasks 3 Step 4 and 4 Step 3 specify authored prose by content requirement and register rather than pasting ~400 lines of finished copy twice. Pasting it would double the drift risk on the one part of this work that is content, not code. Every structural artifact — the site payload JSON, all test code, every signature — is given in full.
