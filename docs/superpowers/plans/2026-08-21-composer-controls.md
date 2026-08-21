# Composer Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the composer's shape-shifting department chip row with one collapsed button, and rebuild the `+` menu as a real capability door that can pin company context into the next turn.

**Architecture:** Three pure value types and one pure grounding function do the work; the views only bind to them. `ContextPin` is a new value type beside `ApprovalTier` and `RoomOffer`. Pinned items reach the model through the single chokepoint that already exists — `ChatContext.compose(…)` → `CompanyChatRequest.context` — so no new wire format and no `functions/` change. The department chips collapse into one `Menu` reading the same `DepartmentCatalog.roster` and the same `DepartmentCompanions.specialistId` the send already reads.

**Tech Stack:** Swift 5, SwiftUI, macOS deployment target 26.2, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-21-composer-controls-design.md`. Read it before Task 1 — the §6 double-count trap is the reason Task 2 exists.

## Global Constraints

- **Swift only.** No file under `functions/` may be touched. A `functions/` deploy uploads the working tree, and this branch is behind `main` there.
- **New `.swift` files need no project-file edit.** `PBXFileSystemSynchronizedRootGroup` — target membership follows the folder on disk.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** View and store code is already main-actor; test classes that touch them are annotated `@MainActor`, as every existing suite is.
- **Chrome is bilingual, content is EN.** Every founder-visible string added here takes `_ lang: AppLanguage` and switches on `lang == .vi`. Follow `ApprovalTier.label(_:)`.
- **Credits, never dollars.** The room's price comes from `RoomOffer.credits` and `RoomOffer.label(_:)`. Never hardcode `10` or any `$` figure in a view.
- **Additive parameters only.** Every new parameter on an existing function or view gets a default that reproduces today's behaviour exactly (`pinned: [ContextPin] = []`, `pins: Binding<[ContextPin]>? = nil`). This is the same rule `ChatSurface` and `tier:` already follow, and Task 2 has a test that enforces it.
- **Quit `codepet.app` before running tests.** A running instance holds the Firestore lock and kills the `xcodebuild test` host, a different victim each run.
- **Count tests with `xcresulttool`, never by grepping the log.** `xcodebuild`'s own "Executed N tests" line is truncated on large runs and `^Test Case .*passed` double-counts.

**Per-suite test command** (substitute the suite name):

```bash
cd /Users/monatruong/Developer/codepet-two-mode
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/SUITE_NAME \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
```

`-derivedDataPath build/dd-ci` is load-bearing, not tidiness: without it the unsigned test build overwrites the signed `codepet.app` in shared DerivedData and Firebase sign-in silently breaks for the next human launch.

**Full-suite command, required before the PR:** `./scripts/ci-test.sh`

---

### Task 1: `ContextPin` — what the founder pinned for the next turn

**Files:**
- Create: `codepet/Models/ContextPin.swift`
- Create: `codepetTests/ContextPinTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum ContextPin: Identifiable, Equatable` with cases `.deliverable(id: String, title: String)` and `.task(id: String, title: String)`
  - `var id: String` — namespaced, `"deliverable:<id>"` / `"task:<id>"`
  - `var title: String`
  - `var icon: String` — SF Symbol name
  - `var deliverableId: String?` — non-nil only for `.deliverable`
  - `static let max = 3`
  - `static func adding(_ pin: ContextPin, to pins: [ContextPin]) -> [ContextPin]`
  - `static func removing(_ pin: ContextPin, from pins: [ContextPin]) -> [ContextPin]`
  - `static func label(_ lang: AppLanguage) -> String` — the pinned-block heading, consumed by Task 2

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ContextPinTests.swift`:

```swift
import XCTest
@testable import codepet

/// The pin is a value type with three rules worth protecting: it is namespaced by
/// case, it de-dupes, and it caps. All three are here because the alternative to
/// each one is a real defect — a task id colliding with a deliverable id, the same
/// document pinned twice, or a founder pinning her whole Library into one prompt.
final class ContextPinTests: XCTestCase {

    func testIdIsNamespacedByCase() {
        // Deliverable ids and task ids come from different collections. Without the
        // namespace, a collision would make one pin silently replace the other.
        let d = ContextPin.deliverable(id: "abc", title: "Pricing page")
        let t = ContextPin.task(id: "abc", title: "Ship billing")
        XCTAssertNotEqual(d.id, t.id)
        XCTAssertEqual(d.id, "deliverable:abc")
        XCTAssertEqual(t.id, "task:abc")
    }

    func testAddingTheSamePinTwiceIsANoOp() {
        let pin = ContextPin.deliverable(id: "abc", title: "Pricing page")
        let once = ContextPin.adding(pin, to: [])
        let twice = ContextPin.adding(pin, to: once)
        XCTAssertEqual(twice.count, 1, "the same deliverable pinned twice is two pills and two grounding blocks")
    }

    func testAddingStopsAtTheCap() {
        // The cap matches selectPriorWork's own max: 3 and keeps the pill row to one
        // line at the 380pt dock width.
        var pins: [ContextPin] = []
        for i in 0..<10 {
            pins = ContextPin.adding(.task(id: "t\(i)", title: "Task \(i)"), to: pins)
        }
        XCTAssertEqual(pins.count, ContextPin.max)
        XCTAssertEqual(ContextPin.max, 3)
        XCTAssertEqual(pins.first?.title, "Task 0", "the cap must drop the NEW pin, not silently evict the founder's first choice")
    }

    func testRemovingTakesOutOnlyThatPin() {
        let a = ContextPin.deliverable(id: "a", title: "A")
        let b = ContextPin.task(id: "b", title: "B")
        let left = ContextPin.removing(a, from: [a, b])
        XCTAssertEqual(left, [b])
    }

    func testDeliverableIdIsNilForATask() {
        // Task 2's exclusion set is built from this. A task leaking into it would
        // silently drop a Library entry from the automatic prior-work block.
        XCTAssertEqual(ContextPin.deliverable(id: "abc", title: "A").deliverableId, "abc")
        XCTAssertNil(ContextPin.task(id: "abc", title: "B").deliverableId)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ContextPinTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t1.xcresult 2>&1 | tail -25
```

Expected: the **test target does not build** — `cannot find 'ContextPin' in scope`. Per `scripts/ci-test.sh`, a non-building test target is a regression, not a pass; here it is the expected red.

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Models/ContextPin.swift`:

```swift
// codepet/Models/ContextPin.swift
import Foundation

/// What the founder pinned for the NEXT turn — spec §6.
///
/// **Why this exists at all.** Relevant prior work already reaches the model on
/// every turn: `ChatContext.selectPriorWork` ranks up to three Library deliverables
/// by token overlap against the founder's message. A pin does not add grounding, it
/// replaces the ranker's guess with the founder's choice and gives the choice more
/// room. Describing it as "attaching a document" would oversell it.
///
/// **Consumed by the send, like the department chip.** A pin is context for the next
/// message, not a session setting. `CopilotChatView.send` clears it, for the reason
/// written on `selectedDept` there: a selection that survives its send goes stale
/// out of the founder's eyeline, and she pays for the stale grounding every turn.
enum ContextPin: Identifiable, Equatable {
    /// A Library deliverable, by `Deliverable.id`.
    case deliverable(id: String, title: String)
    /// A roadmap task, by `RoadmapTask.id`.
    case task(id: String, title: String)

    /// **Namespaced by case, not the bare id.** Deliverable ids and task ids come
    /// from two different collections and nothing guarantees they don't collide; an
    /// un-namespaced id would let one pin silently replace the other.
    var id: String {
        switch self {
        case .deliverable(let id, _): return "deliverable:\(id)"
        case .task(let id, _):        return "task:\(id)"
        }
    }

    var title: String {
        switch self {
        case .deliverable(_, let title), .task(_, let title): return title
        }
    }

    var icon: String {
        switch self {
        case .deliverable: return "books.vertical"
        case .task:        return "map"
        }
    }

    /// The `Deliverable.id` when this pin is one. `ChatContext.compose` builds its
    /// exclusion set from this, so a task must return nil here — a task id leaking
    /// into that set would drop an unrelated Library entry from the automatic block.
    var deliverableId: String? {
        if case .deliverable(let id, _) = self { return id }
        return nil
    }

    /// Matches `selectPriorWork`'s own `max: 3`, and keeps the pill row to one line
    /// at the 380pt dock width.
    static let max = 3

    /// Add, de-duped by `id` and capped at `max`.
    ///
    /// At the cap the NEW pin is dropped rather than the oldest evicted: silently
    /// removing a choice the founder already made and can see on screen is worse
    /// than declining one she has not made yet. The menu row disables at the cap
    /// (Task 6) so this path is the backstop, not the UI.
    static func adding(_ pin: ContextPin, to pins: [ContextPin]) -> [ContextPin] {
        guard !pins.contains(where: { $0.id == pin.id }) else { return pins }
        guard pins.count < max else { return pins }
        return pins + [pin]
    }

    static func removing(_ pin: ContextPin, from pins: [ContextPin]) -> [ContextPin] {
        pins.filter { $0.id != pin.id }
    }

    /// The grounding block's heading. EN only on the wire — this is prompt text the
    /// model reads, not chrome the founder reads, and the rest of `ChatContext` is
    /// composed in English regardless of `uiLanguage`.
    static let groundingHeading =
        "The founder pinned this for this question — use it directly:"
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ContextPinTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t1.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t1.xcresult | head -20
```

Expected: 5 tests, 5 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/ContextPin.swift codepetTests/ContextPinTests.swift
git commit -F - <<'MSG'
feat(model): ContextPin — what the founder pinned for the next turn

Namespaced by case, because a deliverable id and a task id come from two
different collections and nothing stops them colliding; un-namespaced, one
pin would silently replace the other.

At the cap the NEW pin is dropped rather than the oldest evicted. Silently
removing a choice the founder already made and can see on screen is worse
than declining one she has not made yet.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 2: The pinned grounding block, and the double-count guard

This is the task the spec was written for. Everything else is chrome.

**Files:**
- Modify: `codepet/Models/ChatContext.swift` — `selectPriorWork` gains `excluding:`, new `composePinned`, `compose` gains `pinned:`
- Create: `codepetTests/ChatContextPinTests.swift`

**Interfaces:**
- Consumes: `ContextPin` (`.deliverable`/`.task`, `deliverableId`, `groundingHeading`) from Task 1.
- Produces:
  - `ChatContext.selectPriorWork(_ library: [Deliverable], query: String? = nil, max: Int = 3, excluding: Set<String> = []) -> [Deliverable]`
  - `ChatContext.compose(brief:tasks:decisions:library:query:focusDepartment:memoryEnabled:pinned:) -> String` — `pinned: [ContextPin] = []` is the new last parameter
  - `ChatContext.pinnedExcerptCap` is `private`; tests assert on rendered output, not on the constant

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ChatContextPinTests.swift`:

```swift
import XCTest
@testable import codepet

/// The pinned block, and the one defect it can introduce.
///
/// `selectPriorWork` ALREADY ranks up to three Library deliverables into grounding on
/// every turn. Pin one of those and it lands twice — once at the 240-char automatic
/// excerpt and once at the 1200-char pinned excerpt. That does not emphasise it; it
/// tells the model there are two different documents with the same title. The
/// exclusion assertion below is the guard, and it is the reason this suite exists.
final class ChatContextPinTests: XCTestCase {

    /// A brief with enough in it that `BriefContext.compose` returns real text.
    /// Field names verified against `codepet/Models/CompanyBrief.swift` — it has
    /// `projectName`/`oneLiner`, not `name`/`idea`. Same two fields
    /// `ChatContextTests` uses.
    private func brief() -> CompanyBrief {
        CompanyBrief(projectName: "Codepet", oneLiner: "AI coding companion")
    }

    private func deliverable(id: String, title: String, body: String) -> Deliverable {
        Deliverable(id: id, kind: .doc, title: title, body: body, createdAt: "2026-08-20T10:00:00Z")
    }

    /// `TaskWho` is `does | draft | you` — there is no `.codepet` or `.founder`.
    private func task(id: String, title: String, detail: String = "") -> RoadmapTask {
        RoadmapTask(id: id, title: title, detail: detail, phase: .build, who: .does)
    }

    // MARK: - The regression guard

    /// **`pinned:` must be additive.** Every existing caller passes nothing, and the
    /// grounding they get must be byte-identical to what they got before this
    /// parameter existed. If this fails, every prompt in the app changed.
    func testEmptyPinnedChangesNothing() {
        let lib = [deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro.")]
        let tasks = [task(id: "t1", title: "Ship billing")]
        let withDefault = ChatContext.compose(brief: brief(), tasks: tasks, library: lib, query: "pricing")
        let withEmpty = ChatContext.compose(brief: brief(), tasks: tasks, library: lib, query: "pricing",
                                            pinned: [])
        XCTAssertEqual(withDefault, withEmpty)
        XCTAssertFalse(withDefault.contains(ContextPin.groundingHeading),
                       "the pinned heading appeared with no pins")
    }

    // MARK: - The double-count guard

    /// The defect this design could introduce, asserted directly: a pinned
    /// deliverable's title appears ONCE in the grounding, not once per block.
    func testAPinnedDeliverableIsNotAlsoAutoSelected() {
        let lib = [
            deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro."),
            deliverable(id: "d2", title: "Launch checklist", body: "Freeze, then beta, then ship."),
        ]
        let out = ChatContext.compose(
            brief: brief(), tasks: [task(id: "t1", title: "Ship billing")],
            library: lib, query: "pricing",
            pinned: [.deliverable(id: "d1", title: "Pricing page")])

        let occurrences = out.components(separatedBy: "Pricing page").count - 1
        XCTAssertEqual(occurrences, 1,
                       "\"Pricing page\" appears \(occurrences) times — pinned AND auto-selected, "
                       + "which tells the model there are two documents with that title")
    }

    /// The exclusion is scoped to the pinned id and does not suppress the rest of
    /// the Library. An over-broad filter would quietly cost the founder grounding
    /// she was getting for free before she pinned anything.
    func testExcludingOnePinnedItemLeavesTheOthers() {
        let lib = [
            deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro."),
            deliverable(id: "d2", title: "Launch checklist", body: "Freeze, then beta, then ship."),
        ]
        let out = ChatContext.compose(
            brief: brief(), tasks: [], library: lib, query: "pricing launch",
            pinned: [.deliverable(id: "d1", title: "Pricing page")])
        XCTAssertTrue(out.contains("Launch checklist"),
                      "the unpinned deliverable was dropped too — the exclusion is over-broad")
    }

    /// A pinned TASK must not filter the Library. `deliverableId` is nil for a task,
    /// and if that ever changes an unrelated Library entry disappears.
    func testAPinnedTaskDoesNotFilterTheLibrary() {
        let lib = [deliverable(id: "t1", title: "Pricing page", body: "We charge $20/mo for Pro.")]
        // Same raw id as the deliverable, deliberately.
        let out = ChatContext.compose(
            brief: brief(), tasks: [task(id: "t1", title: "Ship billing")],
            library: lib, query: "pricing",
            pinned: [.task(id: "t1", title: "Ship billing")])
        XCTAssertTrue(out.contains("Pricing page"),
                      "a pinned task with a colliding id filtered a Library entry")
    }

    // MARK: - The block itself

    func testThePinnedBlockNamesTheHeadingAndTheItem() {
        let lib = [deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro.")]
        let out = ChatContext.compose(brief: brief(), tasks: [], library: lib,
                                       pinned: [.deliverable(id: "d1", title: "Pricing page")])
        XCTAssertTrue(out.contains(ContextPin.groundingHeading))
        XCTAssertTrue(out.contains("Pricing page"))
        XCTAssertTrue(out.contains("We charge $20/mo for Pro."))
    }

    /// A pin gets more room than a guess — that is the whole difference between a
    /// choice and a ranking. 600 chars of body survives pinned; the automatic block
    /// would have clipped it at 240.
    func testAPinnedBodyGetsMoreRoomThanAnAutoSelectedOne() {
        let long = String(repeating: "pricing detail. ", count: 100)   // 1600 chars
        let lib = [deliverable(id: "d1", title: "Pricing page", body: long)]

        let auto = ChatContext.compose(brief: brief(), tasks: [], library: lib, query: "pricing")
        let pinned = ChatContext.compose(brief: brief(), tasks: [], library: lib, query: "pricing",
                                          pinned: [.deliverable(id: "d1", title: "Pricing page")])
        XCTAssertGreaterThan(pinned.count, auto.count + 800,
                             "the pinned excerpt is not meaningfully longer than the 240-char guess")
    }

    func testAPinnedTaskCarriesItsDetail() {
        let tasks = [task(id: "t1", title: "Ship billing", detail: "Stripe checkout, then the paywall.")]
        let out = ChatContext.compose(brief: brief(), tasks: tasks,
                                       pinned: [.task(id: "t1", title: "Ship billing")])
        XCTAssertTrue(out.contains(ContextPin.groundingHeading))
        XCTAssertTrue(out.contains("Stripe checkout, then the paywall."))
    }

    // MARK: - Error handling

    /// A pin whose target is gone contributes nothing and takes nothing down with
    /// it. This is reachable in the app: pin a deliverable, delete it in Library,
    /// then send. It must not render a heading over an empty list.
    func testAPinToADeletedItemIsSkippedEntirely() {
        let out = ChatContext.compose(brief: brief(), tasks: [], library: [],
                                       pinned: [.deliverable(id: "gone", title: "Deleted doc")])
        XCTAssertFalse(out.contains(ContextPin.groundingHeading),
                       "a heading was composed over zero resolvable pins")
        XCTAssertFalse(out.contains("Deleted doc"),
                       "the pin's cached title was sent as though the document still existed")
    }

    /// One resolvable pin among two still composes, carrying only what exists.
    func testAMissingPinDoesNotSuppressAResolvableOne() {
        let lib = [deliverable(id: "d1", title: "Pricing page", body: "We charge $20/mo for Pro.")]
        let out = ChatContext.compose(
            brief: brief(), tasks: [], library: lib,
            pinned: [.deliverable(id: "gone", title: "Deleted doc"),
                     .deliverable(id: "d1", title: "Pricing page")])
        XCTAssertTrue(out.contains("Pricing page"))
        XCTAssertFalse(out.contains("Deleted doc"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ChatContextPinTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t2.xcresult 2>&1 | tail -25
```

Expected: test target does not build — `extra argument 'pinned' in call`.

If `CompanyBrief`'s or `RoadmapTask`'s initializer signature differs from the helpers above, fix the **helpers** to match the models. Do not change the models.

- [ ] **Step 3: Write minimal implementation**

In `codepet/Models/ChatContext.swift`, add the cap constant next to the existing `excerptCap`:

```swift
    // Per-excerpt body clip in the rendered prior-work block.
    private static let excerptCap = 240
    /// Per-excerpt clip for a PINNED item. Five times the automatic cap, because a
    /// choice deserves more room than a guess — that is the entire difference
    /// between this block and the one below it.
    private static let pinnedExcerptCap = 1200
```

Change `selectPriorWork` to accept an exclusion set. Replace its `usable` filter:

```swift
    /// `excluding` holds `Deliverable.id`s the founder pinned explicitly. They are
    /// rendered by `composePinned` at a longer cap, and an item in both blocks does
    /// not read as emphasis — it reads as two documents with one title.
    static func selectPriorWork(_ library: [Deliverable], query: String? = nil, max: Int = 3,
                                excluding: Set<String> = []) -> [Deliverable] {
        let usable = library.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !excluding.contains($0.id)
        }
```

Leave the rest of `selectPriorWork` untouched.

Add `composePinned` directly above `composePriorWork`:

```swift
    /// The founder's own choice of grounding, rendered above the ranked guesses.
    ///
    /// A pin that no longer resolves — pinned, then deleted in Library — contributes
    /// nothing rather than sending its cached title as though the document still
    /// existed. If none resolve, the block is empty and no heading is composed: a
    /// heading over an empty list would instruct the model to "use it directly"
    /// about nothing.
    private static func composePinned(_ pins: [ContextPin],
                                      library: [Deliverable],
                                      tasks: [RoadmapTask]) -> String {
        guard !pins.isEmpty else { return "" }
        var lines: [String] = []
        for pin in pins {
            switch pin {
            case .deliverable(let id, _):
                guard let d = library.first(where: { $0.id == id }) else { continue }
                let flattened = d.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                let excerpt = flattened.count > pinnedExcerptCap
                    ? String(flattened.prefix(pinnedExcerptCap)) + "…"
                    : flattened
                lines.append("- \(d.title) (\(d.kind.rawValue)): \(excerpt)")
            case .task(let id, _):
                guard let t = tasks.first(where: { $0.id == id }) else { continue }
                let detail = t.detail.trimmingCharacters(in: .whitespacesAndNewlines)
                let state = t.done ? "done" : "open"
                lines.append("- \(t.title) (roadmap task, \(state))"
                             + (detail.isEmpty ? "" : ": \(detail)"))
            }
        }
        guard !lines.isEmpty else { return "" }
        return ContextPin.groundingHeading + "\n" + lines.joined(separator: "\n")
    }
```

Change `compose`'s signature and its prior-work lines. The signature gains one defaulted parameter:

```swift
    static func compose(brief: CompanyBrief, tasks: [RoadmapTask], decisions: [DecisionEntry] = [],
                         library: [Deliverable] = [], query: String? = nil,
                         focusDepartment: Department? = nil, memoryEnabled: Bool = true,
                         pinned: [ContextPin] = []) -> String {
```

Then replace the single `priorBlock` line near the end of `compose` with:

```swift
        // Pinned first: the founder's explicit choice reads before the ranker's
        // guesses, and the guesses are filtered by it.
        let pinnedBlock = composePinned(pinned, library: library, tasks: tasks)
        if !pinnedBlock.isEmpty { parts.append(pinnedBlock) }
        let priorBlock = composePriorWork(
            selectPriorWork(library, query: query,
                            excluding: Set(pinned.compactMap { $0.deliverableId })))
        if !priorBlock.isEmpty { parts.append(priorBlock) }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ChatContextPinTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t2.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t2.xcresult | head -20
```

Expected: 9 tests, 9 passed, 0 failed.

- [ ] **Step 5: Run the existing grounding suites — `selectPriorWork` and `compose` both changed**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ChatContextTests \
  -only-testing:codepetTests/CompanyStoreChatTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t2b.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t2b.xcresult | head -20
```

There are five existing grounding suites and `compose`/`selectPriorWork` are shared by all of them, so run the lot:

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ChatContextTests \
  -only-testing:codepetTests/ChatContextDecisionsTests \
  -only-testing:codepetTests/ChatContextFocusTests \
  -only-testing:codepetTests/MarkDoneGroundingTests \
  -only-testing:codepetTests/ReflectionCompositionChatContextTests \
  -only-testing:codepetTests/CompanyStoreChatTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t2b.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t2b.xcresult | head -20
```

Expected: all pass, 0 failed. A red test here means the defaulted parameter was not actually additive — fix the implementation, not the test.

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/ChatContext.swift codepetTests/ChatContextPinTests.swift
git commit -F - <<'MSG'
feat(grounding): a pinned item, and the guard against sending it twice

selectPriorWork already ranks up to three Library deliverables into grounding
on every turn, so a pinned deliverable would land twice — once at the 240-char
automatic excerpt and once at the 1200-char pinned one. That is not emphasis.
It tells the model there are two different documents with the same title. So
pinned ids are excluded from the automatic set, and a test asserts the title
appears exactly once.

Three more failure modes have assertions rather than comments: an empty
`pinned:` produces byte-identical grounding to before the parameter existed;
a pinned TASK whose id collides with a deliverable's does not filter the
Library; and a pin whose target was deleted contributes nothing rather than
sending its cached title as though the document still existed.

Pinned renders ABOVE prior work — the founder's choice reads before the
ranker's guesses.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 3: Thread `pinned:` from the store to the grounding

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` — `sendChat` and `sendMessage` gain `pinned:`; the `ChatContext.compose` call passes it
- Create: `codepetTests/ContextPinSendTests.swift`

**Interfaces:**
- Consumes: `ContextPin` (Task 1); `ChatContext.compose(…, pinned:)` (Task 2).
- Produces:
  - `CompanyStore.sendChat(_ raw: String, language: AppLanguage, department: Department? = nil, founderAsk: String? = nil, convenesRoom: Bool = false, pinned: [ContextPin] = []) async`
  - The composed `CompanyChatRequest.context` carries the pinned block.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ContextPinSendTests.swift`:

```swift
import XCTest
@testable import codepet

/// The pin has to survive the trip from the composer to the wire. `CompanyStore` is
/// driven through injected closures, so this asserts on the request the store built
/// rather than on a network call.
@MainActor
final class ContextPinSendTests: XCTestCase {

    /// A `chatStreamer` that throws before yielding — this is what makes the
    /// non-streaming `chatSender` path run deterministically, with no network and no
    /// `Auth.auth()` (unconfigured under XCTest, and it TRAPS rather than throwing).
    /// Copied from `CompanyStoreChatTests`, which is the pattern of record.
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    /// `CompanyStore.company` is `private(set)` — state is seeded through the
    /// LOADER and `hydrate`, never by assigning to `store.company`.
    private func store(capturing onRequest: @escaping (CompanyChatRequest) -> Void) -> CompanyStore {
        CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(projectName: "Codepet", oneLiner: "AI coding companion"),
                             departments: [],
                             library: [Deliverable(id: "d1", kind: .doc, title: "Pricing page",
                                                   body: "We charge $20/mo for Pro.",
                                                   createdAt: "2026-08-20T10:00:00Z")],
                             stage: .idea, companionId: "byte", onboardedAt: Date(),
                             tasks: [RoadmapTask(id: "t1", title: "Ship billing", detail: "",
                                                 phase: .build, who: .does)])
            },
            saver: { _, _ in true },
            chatSender: { req in
                onRequest(req)
                return CompanyChatReply(text: "ok", runTaskId: nil)
            },
            chatStreamer: Self.failingStreamer)
    }

    func testAPinnedDeliverableReachesTheRequestContext() async {
        var captured: CompanyChatRequest?
        let s = store { captured = $0 }
        await s.hydrate(companyId: "u")

        await s.sendChat("What should we charge?", language: .en,
                         pinned: [.deliverable(id: "d1", title: "Pricing page")])

        guard let req = captured else { return XCTFail("no request was composed") }
        XCTAssertTrue(req.context.contains(ContextPin.groundingHeading),
                      "the pinned block never reached the wire")
        XCTAssertTrue(req.context.contains("We charge $20/mo for Pro."))
    }

    /// The default path is untouched: no `pinned:` argument, no pinned block.
    func testAnUnpinnedSendCarriesNoPinnedBlock() async {
        var captured: CompanyChatRequest?
        let s = store { captured = $0 }
        await s.hydrate(companyId: "u")

        await s.sendChat("What should we charge?", language: .en)

        guard let req = captured else { return XCTFail("no request was composed") }
        XCTAssertFalse(req.context.contains(ContextPin.groundingHeading))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ContextPinSendTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t3.xcresult 2>&1 | tail -25
```

Expected: does not build — `extra argument 'pinned' in call`.

The scaffolding above was verified against `codepetTests/CompanyStoreChatTests.swift`, which is the pattern of record: `CompanyStore(loader:saver:chatSender:chatStreamer:)`, a `failingStreamer` to force the non-streaming path, `CompanyChatReply(text:runTaskId:)` for the reply, and `hydrate(companyId:)` before any send. Read that file if anything here does not compile — do not invent a different injection route.

- [ ] **Step 3: Write minimal implementation**

In `codepet/Managers/CompanyStore.swift`, add the parameter to `sendChat` (around line 636):

```swift
    func sendChat(_ raw: String, language: AppLanguage, department: Department? = nil,
                  founderAsk: String? = nil, convenesRoom: Bool = false,
                  pinned: [ContextPin] = []) async {
```

and pass it through on the `sendMessage` call at the end of that function:

```swift
        await sendMessage(text, language: language, department: department,
                          convene: convenesRoom ? words : nil, display: words,
                          founderAsk: founderAsk, pinned: pinned)
```

**Do not retype that call from this plan.** Open the existing call, add only `pinned: pinned` to its argument list, and leave every other argument exactly as it is — the `convene:`/`display:`/`founderAsk:` values encode decisions this task is not making.

Add the parameter to `sendMessage` (around line 1218):

```swift
    private func sendMessage(_ text: String, language: AppLanguage, department: Department? = nil,
                             convene: String? = nil, display: String? = nil,
                             founderAsk: String? = nil, pinned: [ContextPin] = []) async {
```

and pass it into the `ChatContext.compose` call inside `CompanyChatRequest` (around line 1266):

```swift
            context: ChatContext.compose(brief: company.brief, tasks: company.tasks,
                                          decisions: company.decisions,
                                          library: company.library, query: text,
                                          focusDepartment: department,
                                          memoryEnabled: company.founderPrefs.memoryEnabled,
                                          pinned: pinned),
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ContextPinSendTests \
  -only-testing:codepetTests/CompanyStoreChatTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t3.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t3.xcresult | head -20
```

Expected: 2 new tests pass and every `CompanyStoreChatTests` test still passes, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepetTests/ContextPinSendTests.swift
git commit -F - <<'MSG'
feat(store): carry pinned context from sendChat to the grounding

Two defaulted parameters and one argument. Everything the `+` menu brings in
already had a chokepoint — ChatContext.compose → CompanyChatRequest.context —
so pinning needs no new wire field and no functions change.

The second test is the one worth keeping: a send with no `pinned:` argument
carries no pinned block, which is what makes this safe to land while every
existing call site is untouched.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 4: The departments control — one button instead of a chip row

**Files:**
- Modify: `codepet/Views/Copilot/ChatComposer.swift` — delete `deptChips`, `chip(_:)`, `deptOverflowItems`; add `departmentControl`
- Modify: `codepet/Models/ChatSurface.swift` — delete `visibleDeptChips`
- Modify: `codepetTests/TwoModeHeroTests.swift` — delete the two `visibleDeptChips` assertions
- Create: `codepetTests/DepartmentMenuTests.swift`

**Interfaces:**
- Consumes: `DepartmentCatalog.roster`, `DepartmentCompanions.specialistId(for:host:)`, `PetCharacter.all`, `CharacterImage`.
- Produces:
  - `ChatComposer.departmentControl` — private view, replaces `deptChips` at both call sites
  - `DepartmentMenu.rosterOrder: [Department]`, `DepartmentMenu.pet(for:host:) -> String?`, `DepartmentMenu.rowTitle(_:host:) -> String`, `DepartmentMenu.restLabel(_:)`, `DepartmentMenu.anyoneLabel(_:)`, `DepartmentMenu.clearHelp(_:)` — a testable seam, because a SwiftUI `Menu`'s contents cannot be asserted on directly

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentMenuTests.swift`:

```swift
import XCTest
@testable import codepet

/// A SwiftUI `Menu`'s rendered rows are not reachable from a test, so the menu's
/// CONTENT is a pure type and the view is a thin reader of it. What matters is that
/// the rows and the send agree about who answers.
final class DepartmentMenuTests: XCTestCase {

    func testTheMenuListsTheWholeRosterInCatalogOrder() {
        XCTAssertEqual(DepartmentMenu.rosterOrder.map(\.key),
                       DepartmentCatalog.roster.map(\.key))
        XCTAssertEqual(DepartmentMenu.rosterOrder.count, 8)
    }

    /// `product` has no pet and placeholder art. It is filtered out of `roster` and
    /// must stay out of the menu — a row wearing Engineering's identity is worse
    /// than a missing row.
    func testProductIsNotOffered() {
        XCTAssertFalse(DepartmentMenu.rosterOrder.contains { $0.key == "product" })
    }

    /// **The invariant this control inherits from the chip it replaces.** The pet a
    /// row shows must be the pet that signs the reply, which means it must come from
    /// the same function the send calls — `DepartmentCompanions.specialistId`. A
    /// second source here would let the menu promise a pet the answer never signs.
    func testEveryRowsPetMatchesWhatTheSendWouldPick() {
        for dep in DepartmentMenu.rosterOrder {
            XCTAssertEqual(DepartmentMenu.pet(for: dep, host: "byte"),
                           DepartmentCompanions.specialistId(for: dep.key, host: "byte"),
                           "\(dep.key)'s menu row and its reply would disagree")
        }
    }

    /// The pet name leads, then the department — the order the reply is signed in
    /// (`CopilotChatView.headerName` renders "Nova · Marketing").
    func testTheRowTitlePutsThePetFirst() {
        guard let eng = DepartmentCatalog.find("eng") else { return XCTFail("no eng") }
        let title = DepartmentMenu.rowTitle(eng, host: "byte")
        XCTAssertTrue(title.hasSuffix("· Engineering"), "got \(title)")
        XCTAssertNotEqual(title, "Engineering", "the pet's name is missing from the row")
    }

    /// A department whose specialist IS the host hands off to nobody, so the row
    /// carries the department alone rather than promising a pet that won't appear.
    func testARowWithNoSpecialistNamesTheDepartmentAlone() {
        // crash speaks for Engineering, so hosting AS crash means no handoff.
        guard let eng = DepartmentCatalog.find("eng") else { return XCTFail("no eng") }
        XCTAssertNil(DepartmentMenu.pet(for: eng, host: "crash"))
        XCTAssertEqual(DepartmentMenu.rowTitle(eng, host: "crash"), "Engineering")
    }

    func testChromeIsBilingual() {
        XCTAssertNotEqual(DepartmentMenu.restLabel(.en), DepartmentMenu.restLabel(.vi))
        XCTAssertNotEqual(DepartmentMenu.anyoneLabel(.en), DepartmentMenu.anyoneLabel(.vi))
        XCTAssertNotEqual(DepartmentMenu.clearHelp(.en), DepartmentMenu.clearHelp(.vi))
        XCTAssertEqual(DepartmentMenu.restLabel(.en), "Departments")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentMenuTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t4.xcresult 2>&1 | tail -25
```

Expected: does not build — `cannot find 'DepartmentMenu' in scope`.

- [ ] **Step 3: Write the menu's content type**

Create `codepet/Models/DepartmentMenu.swift`:

```swift
// codepet/Models/DepartmentMenu.swift
import Foundation

/// The contents of the composer's departments menu — spec §4.
///
/// **Why this is a type and not just view code.** A SwiftUI `Menu`'s rows cannot be
/// asserted on from a test, and the one rule this control must never break is
/// testable: the pet a row shows has to be the pet that signs the reply. That rule
/// has exactly one home, `DepartmentCompanions.specialistId`, which is also what
/// `CompanyStore.actingSpecialist` calls on send. This type reads it and nothing
/// else, so the menu and the answer cannot disagree.
enum DepartmentMenu {

    /// All eight, in catalog order. `product` is absent because `roster` filters it:
    /// it has no pet and `dept-product.png` is a byte-identical copy of
    /// `dept-eng.png`, so a row for it would wear Engineering's identity.
    static var rosterOrder: [Department] { DepartmentCatalog.roster }

    /// The pet this row summons, or nil when the turn would stay with the host.
    /// Delegates — see the type comment for why it must.
    static func pet(for department: Department, host: String) -> String? {
        DepartmentCompanions.specialistId(for: department.key, host: host)
    }

    /// `crash · Engineering`. The pet's name leads because that is the order the
    /// reply is signed in, so the row and the answer read alike. No mapped
    /// specialist means the department alone — the row never promises a pet that
    /// will not appear.
    static func rowTitle(_ department: Department, host: String) -> String {
        guard let id = pet(for: department, host: host),
              let name = PetCharacter.all[id]?.name else { return department.name }
        return "\(name) · \(department.name)"
    }

    /// The armed button's own label. Same string as the row, so picking a row and
    /// reading the button back cannot look like two different choices.
    static func armedLabel(_ department: Department, host: String) -> String {
        rowTitle(department, host: host)
    }

    static func restLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Phòng ban" : "Departments"
    }

    /// The off state, made nameable. Deselecting used to be reachable only by
    /// clicking an armed chip a second time; letting byte route it is a real choice
    /// and it should be a row you can pick, with a checkmark saying it is what you
    /// have.
    static func anyoneLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Ai cũng được — byte tự chọn" : "Anyone — byte routes it"
    }

    static func clearHelp(_ lang: AppLanguage) -> String {
        lang == .vi ? "Bỏ chọn phòng ban" : "Clear the department"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentMenuTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t4.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t4.xcresult | head -20
```

Expected: 6 tests, 6 passed, 0 failed.

If `testARowWithNoSpecialistNamesTheDepartmentAlone` fails, read `DepartmentCompanions.map` and pick a host/department pair that genuinely maps to itself — the assertion is about the self-mapping case, not about `crash` specifically.

- [ ] **Step 5: Commit the content type**

```bash
git add codepet/Models/DepartmentMenu.swift codepetTests/DepartmentMenuTests.swift
git commit -F - <<'MSG'
feat(model): DepartmentMenu — the composer's department rows, as a testable type

A SwiftUI Menu's rows cannot be asserted on, and the one rule this control must
never break is testable: the pet a row shows has to be the pet that signs the
reply. That rule already has exactly one home — DepartmentCompanions.specialistId,
which is what actingSpecialist calls on send — so this type reads it and nothing
else, and a test walks all eight departments to prove the two agree.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

- [ ] **Step 6: Replace `deptChips` with the collapsed control**

In `codepet/Views/Copilot/ChatComposer.swift`, **delete** `deptChips`, `chip(_:)`, and `deptOverflowItems` entirely, and add:

```swift
    /// Departments, collapsed — spec §4.
    ///
    /// This replaces a row of three chips (two in the dock), a `•••` overflow, and a
    /// fourth chip that appeared only when the selection came from that overflow.
    /// The promoted chip existed because a choice made inside a menu was invisible;
    /// an armed BUTTON is visible, so the patch stops being needed.
    ///
    /// **One capsule, two hit targets.** The label opens the menu, the `✕` clears.
    /// A `✕` that only decorated would be worse than none, and SwiftUI gives a
    /// `Menu` its whole label as one target — hence the `HStack` of two controls
    /// sharing one background rather than a `Menu` with an overlay.
    private var departmentControl: some View {
        let host = companyStore.company.companionId
        let armed = selectedDept
        return HStack(spacing: 0) {
            Menu {
                Button { selectedDept = nil } label: {
                    if armed == nil {
                        Label(DepartmentMenu.anyoneLabel(lang), systemImage: "checkmark")
                    } else {
                        Text(DepartmentMenu.anyoneLabel(lang))
                    }
                }
                Divider()
                ForEach(DepartmentMenu.rosterOrder) { dep in
                    Button { selectedDept = dep } label: { deptRow(dep, host: host) }
                }
            } label: {
                HStack(spacing: 5) {
                    if let dep = armed, let pet = DepartmentMenu.pet(for: dep, host: host) {
                        CharacterImage(pet, size: 16)
                    }
                    Text(armed.map { DepartmentMenu.armedLabel($0, host: host) }
                         ?? DepartmentMenu.restLabel(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(armed?.accent ?? CodepetTheme.bodyText)
                        .lineLimit(1)
                    if armed == nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, armed == nil ? 10 : 6)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            if let dep = armed {
                Button { selectedDept = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(dep.accent)
                        .frame(width: 20, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(DepartmentMenu.clearHelp(lang))
            }
        }
        // The armed treatment is the retired chip's treatment, unchanged: two
        // treatments for one control would read as two features.
        .background(Capsule().fill(armed.map { $0.accent.opacity(0.15) } ?? CodepetTheme.surface))
        .overlay(Capsule().stroke(armed?.accent ?? CodepetTheme.hairline))
        .hoverAffordance(Capsule(), accent: armed?.accent ?? CodepetTheme.accentPurple)
    }

    /// One menu row: checkmark when armed, else the pet's sprite, then
    /// `crash · Engineering`.
    ///
    /// **The known risk (spec §4).** macOS decides how a menu draws a `Label`'s icon,
    /// and `char-*` are pixel-art assets rather than SF Symbols. If the sprite does
    /// not survive at menu-icon size, delete the `icon:` closure and keep the `Text`
    /// — the row stays cast-signed, which is the part that matters. Do NOT replace
    /// this with a custom popover; that shape was considered and rejected 21 Aug for
    /// costing its own keyboard and dismiss handling.
    @ViewBuilder private func deptRow(_ dep: Department, host: String) -> some View {
        let on = selectedDept?.key == dep.key
        let title = DepartmentMenu.rowTitle(dep, host: host)
        if on {
            Label(title, systemImage: "checkmark")
        } else if let pet = DepartmentMenu.pet(for: dep, host: host) {
            Label { Text(title) } icon: { Image("char-\(pet)").renderingMode(.original) }
        } else {
            Text(title)
        }
    }
```

Then swap the two call sites. In `dockBody`, replace the line `deptChips` with:

```swift
            HStack(spacing: 6) {
                departmentControl
                // The active-project chip keeps this row now that the chips are gone:
                // a standing reminder of which folder the agent will touch.
                if let link = companyStore.activeProjectLink {
                    Spacer(minLength: 8)
                    projectChip(link)
                }
            }
```

Move the existing active-project `Button { companyStore.select(.environment) }` body out of the deleted `deptChips` and into a new `private func projectChip(_ link: ProjectLink) -> some View` — same code, same styling, verbatim. In `twoModeBody`, replace `if showsDeptChips { deptChips }` with `if showsDeptChips { departmentControl }`.

- [ ] **Step 7: Delete `visibleDeptChips` and its assertions**

In `codepet/Models/ChatSurface.swift`, delete:

```swift
    /// The dock is 380pt wide and fits two chips + overflow; the pane fits the
    /// prototype's three.
    var visibleDeptChips: Int { self == .dock ? 2 : 3 }
```

In `codepetTests/TwoModeHeroTests.swift`, delete the two assertions at lines 215-216:

```swift
        XCTAssertEqual(ChatSurface.twoMode.visibleDeptChips, 3)
        XCTAssertEqual(ChatSurface.dock.visibleDeptChips, 2, "380pt fits two")
```

If deleting them leaves an empty test function, delete the function too and note it in the commit message. Do **not** touch `OnboardingColdOpen.deptChips` — that is an unrelated view with its own chips.

- [ ] **Step 8: Build and run the composer's suites**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentMenuTests \
  -only-testing:codepetTests/TwoModeHeroTests \
  -only-testing:codepetTests/ComposerMetricsTests \
  -only-testing:codepetTests/ChatLandingStateTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t4b.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t4b.xcresult | head -20
```

Expected: 0 failed. Any compile error naming `deptChips`, `chip(`, `deptOverflowItems`, or `visibleDeptChips` is a leftover reference — find it with `grep -rn "deptChips\|deptOverflowItems\|visibleDeptChips" codepet/ codepetTests/` (the only surviving hits should be in `OnboardingColdOpen.swift`).

- [ ] **Step 9: Commit**

```bash
git add codepet/Views/Copilot/ChatComposer.swift codepet/Models/ChatSurface.swift codepetTests/TwoModeHeroTests.swift
git commit -F - <<'MSG'
feat(composer): eight departments behind one button, not three chips and a •••

The row was three chips (two in the dock), a ••• overflow, and — when the
selection came from that overflow — a fourth promoted chip, because a choice
made inside a menu was otherwise invisible. So the row had no fixed width and
eight departments had three separate doors. `deptOverflowItems` was extracted
so two of those doors could not drift apart, which is the smell rather than
the fix.

One capsule now, two hit targets: the label opens the menu, the ✕ clears.
SwiftUI hands a Menu its whole label as one target, so this is an HStack of
two controls sharing one background rather than a Menu with an overlay — a ✕
that only decorated would be worse than none.

The off state gets a name and a checkmark. "Anyone — byte routes it" was
previously reachable only by clicking an armed chip a second time.

`visibleDeptChips` goes with the chips, and so do its two assertions. The
armed treatment is the retired chip's treatment unchanged — two treatments for
one control would read as two features.

Known risk, documented at the call site: macOS decides how a menu draws a
Label's icon, and char-* are pixel art rather than SF Symbols. If the sprite
does not survive at menu-icon size the row drops to text and stays
cast-signed. Not to a custom popover.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 5: Pin pills, and state that clears on send

**Files:**
- Modify: `codepet/Views/Copilot/ChatComposer.swift` — add `pins:` binding + the pill row
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` — own the state, pass it, clear it on send
- Create: `codepetTests/ContextPinLifecycleTests.swift`

**Interfaces:**
- Consumes: `ContextPin` (Task 1); `CompanyStore.sendChat(…, pinned:)` (Task 3).
- Produces:
  - `ChatComposer.pins: Binding<[ContextPin]>? = nil` — nil means the surface does not pin (Developer)
  - `ChatComposer.pinPills` — private view, rendered above the field when non-empty
  - `CopilotChatView.pins: [ContextPin]` — `@State`, cleared in `send()`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ContextPinLifecycleTests.swift`:

```swift
import XCTest
@testable import codepet

/// A pin is context for the NEXT message, not a session setting.
///
/// The rule and its reason are already written on `selectedDept` in
/// `CopilotChatView.send`: a selection that survives its send goes stale out of the
/// founder's eyeline. A pin is worse than a stale chip, because stale grounding is
/// re-sent — and re-billed — on every subsequent turn.
@MainActor
final class ContextPinLifecycleTests: XCTestCase {

    /// Same scaffolding as `ContextPinSendTests` — see the comments there for why
    /// the streamer must fail and why state is seeded through the loader.
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    func testPinsAreConsumedByTheSend() async {
        var contexts: [String] = []
        let s = CompanyStore(
            loader: { _ in
                CompanyState(brief: CompanyBrief(projectName: "Codepet", oneLiner: "AI coding companion"),
                             departments: [],
                             library: [Deliverable(id: "d1", kind: .doc, title: "Pricing page",
                                                   body: "We charge $20/mo for Pro.",
                                                   createdAt: "2026-08-20T10:00:00Z")],
                             stage: .idea, companionId: "byte", onboardedAt: Date(), tasks: [])
            },
            saver: { _, _ in true },
            chatSender: { req in
                contexts.append(req.context)
                return CompanyChatReply(text: "ok", runTaskId: nil)
            },
            chatStreamer: Self.failingStreamer)
        await s.hydrate(companyId: "u")

        // Turn 1 carries the pin; turn 2 must not.
        await s.sendChat("What should we charge?", language: .en,
                         pinned: [.deliverable(id: "d1", title: "Pricing page")])
        await s.sendChat("And what about the free tier?", language: .en)

        XCTAssertEqual(contexts.count, 2)
        XCTAssertTrue(contexts[0].contains(ContextPin.groundingHeading))
        XCTAssertFalse(contexts[1].contains(ContextPin.groundingHeading),
                       "the pin survived its send — the founder pays for that grounding again "
                       + "on every later turn, with nothing on screen saying why")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ContextPinLifecycleTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t5.xcresult 2>&1 | tail -25
```

Expected: PASS on the store level after Task 3 (the store is stateless about pins by construction, which is the point). If it fails, Task 3's threading is wrong — fix that before continuing. Keep the test: it pins the store's statelessness so a later refactor cannot make pins sticky in the store.

- [ ] **Step 3: Add the binding and the pill row to the composer**

In `ChatComposer`, add the property beside `tier`:

```swift
    /// What the founder pinned for the next turn, when the surface pins at all.
    ///
    /// nil on Developer: a code session's context is its branch and its folder, not
    /// a marketing deliverable, and the pins would be paid-for grounding nobody
    /// asked for. Same additive rule as `tier`.
    var pins: Binding<[ContextPin]>? = nil
```

Add the pill row:

```swift
    /// The pinned items, above the field — Claude's attachment chips, in Codepet's
    /// nouns. Above rather than beside the controls because they belong to the text
    /// being written, not to the controls that will send it.
    @ViewBuilder private var pinPills: some View {
        if let pins, !pins.wrappedValue.isEmpty {
            HStack(spacing: 6) {
                ForEach(pins.wrappedValue) { pin in
                    HStack(spacing: 4) {
                        Image(systemName: pin.icon).font(.system(size: 9))
                        Text(pin.title)
                            .font(CodepetTheme.inter(CodepetType.subheadline, weight: .medium))
                            .lineLimit(1)
                        Button {
                            pins.wrappedValue = ContextPin.removing(pin, from: pins.wrappedValue)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(CodepetTokens.well))
                    .overlay(Capsule().stroke(CodepetTokens.cardEdge))
                }
                Spacer(minLength: 0)
            }
        }
    }
```

Insert `pinPills` as the first child of the `VStack` in **both** `dockBody` and `twoModeBody`, directly above the `ComposerField(...)` line.

- [ ] **Step 4: Own the state in `CopilotChatView` and clear it on send**

Add beside `@State private var selectedDept: Department?` (around line 45):

```swift
    /// Pinned context for the next message. Lives here rather than in the store for
    /// the same reason `selectedDept` does — it is consumed by one send.
    @State private var pins: [ContextPin] = []
```

In `composer(showsDeptChips:)`, add to the `ChatComposer(...)` argument list:

```swift
            pins: $pins,
```

In `send()`, extend the existing consumption block. It currently reads:

```swift
        let dept = selectedDept
        selectedDept = nil
```

Make it:

```swift
        let dept = selectedDept
        selectedDept = nil
        // Same rule, same reason as the chip above: one message, one handoff. A pin
        // that survived its send would re-send — and re-bill — the same grounding on
        // every later turn.
        let pinned = pins
        pins = []
```

Then add `pinned: pinned` to the `companyStore.sendChat(...)` call in the `.ask, .plan` branch. Add it to that call only — the `.build` branch routes to a code run that never reads the chat grounding.

Also clear pins wherever `selectedDept` is cleared on a thread switch or new chat, if such a site exists:

```bash
grep -n "selectedDept = nil" codepet/Views/Copilot/CopilotChatView.swift
```

Add `pins = []` beside every hit. A pin surviving a thread switch is the same defect as a chip surviving one.

- [ ] **Step 5: Build and run**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ContextPinLifecycleTests \
  -only-testing:codepetTests/ChatLandingStateTests \
  -only-testing:codepetTests/ComposerMetricsTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t5.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t5.xcresult | head -20
```

Expected: 0 failed.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Copilot/ChatComposer.swift codepet/Views/Copilot/CopilotChatView.swift codepetTests/ContextPinLifecycleTests.swift
git commit -F - <<'MSG'
feat(composer): pinned context as removable pills, consumed by the send

The pills sit above the field, not beside the controls: they belong to the text
being written rather than to the buttons that will send it.

Cleared on send, on a thread switch, and on a new chat — the rule and the
reason are already written on selectedDept two lines up. A pin is worse than a
stale chip: stale grounding is re-sent, and re-billed, on every later turn,
with nothing on screen saying why.

`pins` is nil on Developer. A code session's context is its branch and its
folder, not a marketing deliverable.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 6: The `+` menu

**Files:**
- Modify: `codepet/Views/Copilot/ChatComposer.swift` — rewrite `quickActionsMenu` as `plusMenu`
- Create: `codepet/Models/PlusMenu.swift`
- Create: `codepetTests/PlusMenuTests.swift`

**Interfaces:**
- Consumes: `ContextPin` (Task 1), `pins` binding (Task 5), `RoomOffer`, `ProjectLinker.pickAndLink(into:language:)`, `CompanyStore.select(_ view: AppView)`, `CompanyStore.updateFounderPrefs(_:)`.
- Produces: `PlusMenu.bringInLabel(_:)`, `PlusMenu.goDeeperLabel(_:)`, `PlusMenu.libraryLabel(_:)`, `PlusMenu.taskLabel(_:)`, `PlusMenu.knowsLabel(_:)`, `PlusMenu.folderLabel(_:path:)`, `PlusMenu.setupLabel(_:)`, `PlusMenu.libraryRecentCap = 8`, `PlusMenu.recentLibrary(_:) -> [Deliverable]`, `PlusMenu.openTasks(_:) -> [RoadmapTask]`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/PlusMenuTests.swift`:

```swift
import XCTest
@testable import codepet

/// The `+` menu's data and copy. The rows themselves are a SwiftUI `Menu` and
/// unassertable, so what it OFFERS is a pure type.
final class PlusMenuTests: XCTestCase {

    private func deliverable(_ id: String, _ createdAt: String) -> Deliverable {
        Deliverable(id: id, kind: .doc, title: "Doc \(id)", body: "body", createdAt: createdAt)
    }

    func testRecentLibraryIsNewestFirstAndCapped() {
        let lib = (1...12).map { deliverable("d\($0)", "2026-08-\(String(format: "%02d", $0))T10:00:00Z") }
        let recent = PlusMenu.recentLibrary(lib)
        XCTAssertEqual(recent.count, PlusMenu.libraryRecentCap)
        XCTAssertEqual(PlusMenu.libraryRecentCap, 8)
        XCTAssertEqual(recent.first?.id, "d12", "the newest deliverable is not first")
        XCTAssertEqual(recent.last?.id, "d5")
    }

    /// A deliverable with no `createdAt` must not crash or jump the queue — legacy
    /// documents predate the field.
    func testALibraryEntryWithNoTimestampSortsLast() {
        let lib = [
            Deliverable(id: "old", kind: .doc, title: "No date", body: "body", createdAt: nil),
            deliverable("new", "2026-08-20T10:00:00Z"),
        ]
        XCTAssertEqual(PlusMenu.recentLibrary(lib).first?.id, "new")
    }

    func testOpenTasksExcludeDoneOnesAndKeepRoadmapOrder() {
        // `TaskWho` is `does | draft | you`.
        let tasks = [
            RoadmapTask(id: "t1", title: "One", detail: "", phase: .build, who: .does, done: true),
            RoadmapTask(id: "t2", title: "Two", detail: "", phase: .build, who: .does),
            RoadmapTask(id: "t3", title: "Three", detail: "", phase: .build, who: .you),
        ]
        XCTAssertEqual(PlusMenu.openTasks(tasks).map(\.id), ["t2", "t3"])
    }

    /// The folder row names the folder. A row reading "Linked folder" with no name
    /// makes the founder open it to find out which folder the agent will touch.
    func testTheFolderRowNamesTheFolder() {
        let label = PlusMenu.folderLabel(.en, path: "/Users/mona/Developer/codepet")
        XCTAssertTrue(label.contains("codepet"), "got \(label)")
    }

    func testTheFolderRowSaysSoWhenNothingIsLinked() {
        XCTAssertNotEqual(PlusMenu.folderLabel(.en, path: nil),
                          PlusMenu.folderLabel(.en, path: "/tmp/x"))
    }

    /// Credits come from RoomOffer, never from a view or from this type. Pricing is
    /// locked to credits and a second copy of the number is how the two drift.
    func testTheRoomsPriceIsNotRestatedHere() {
        XCTAssertTrue(RoomOffer.label(.en).contains("\(RoomOffer.credits)"))
    }

    func testChromeIsBilingual() {
        for pair in [(PlusMenu.bringInLabel(.en), PlusMenu.bringInLabel(.vi)),
                     (PlusMenu.goDeeperLabel(.en), PlusMenu.goDeeperLabel(.vi)),
                     (PlusMenu.libraryLabel(.en), PlusMenu.libraryLabel(.vi)),
                     (PlusMenu.taskLabel(.en), PlusMenu.taskLabel(.vi)),
                     (PlusMenu.knowsLabel(.en), PlusMenu.knowsLabel(.vi)),
                     (PlusMenu.setupLabel(.en), PlusMenu.setupLabel(.vi))] {
            XCTAssertNotEqual(pair.0, pair.1, "\(pair.0) is not translated")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/PlusMenuTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t6.xcresult 2>&1 | tail -25
```

Expected: does not build — `cannot find 'PlusMenu' in scope`.

- [ ] **Step 3: Write the content type**

Create `codepet/Models/PlusMenu.swift`:

```swift
// codepet/Models/PlusMenu.swift
import Foundation

/// The `+` menu's contents — spec §5.
///
/// **What the `+` is for.** One question: what does this turn get to see, and how
/// hard should it work. It previously held three prompt starters that are already
/// cards on the empty hero, plus the room, plus the department leftovers — its own
/// doc comment defended it as "a quick-actions menu (NOT a file picker)", which
/// describes a control with no idea what it is for.
///
/// Codepet's answer to "what does it see" is not files. It is the company: the
/// Library, the roadmap, what Codepet knows, the linked folder.
enum PlusMenu {

    /// Enough to recognise last week's work without turning a menu into a file
    /// browser. `Browse Library…` is the row for everything older.
    static let libraryRecentCap = 8

    /// Newest first. `createdAt` is ISO-8601 so a lexicographic sort is
    /// chronological; nil sorts last, because legacy deliverables predate the field
    /// and an undated document is not evidence of being new.
    static func recentLibrary(_ library: [Deliverable]) -> [Deliverable] {
        Array(library.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
                     .prefix(libraryRecentCap))
    }

    /// Open tasks in roadmap order. Order is not re-derived here: the roadmap's own
    /// sequence is the one the founder reads on the board, and a menu that sorted
    /// differently would be a second opinion about what comes next.
    static func openTasks(_ tasks: [RoadmapTask]) -> [RoadmapTask] {
        tasks.filter { !$0.done }
    }

    static func bringInLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "MANG VÀO" : "BRING SOMETHING IN"
    }

    static func goDeeperLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "ĐI SÂU HƠN" : "GO DEEPER"
    }

    static func libraryLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Từ Thư viện" : "From your Library"
    }

    static func browseLibraryLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở Thư viện…" : "Browse Library…"
    }

    static func taskLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Một việc trên lộ trình" : "A roadmap task"
    }

    static func openRoadmapLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở Lộ trình…" : "Open Roadmap…"
    }

    /// The Second Brain, as the switch that already gates it. `FounderPrefs.memoryEnabled`
    /// is the real control over whether decisions reach the model; a fact-PICKER here
    /// would be new machinery in front of an existing boolean.
    static func knowsLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Những gì Codepet biết" : "What Codepet knows"
    }

    /// Names the folder. A row reading only "Linked folder" makes the founder open it
    /// to find out which folder the agent is about to touch.
    static func folderLabel(_ lang: AppLanguage, path: String?) -> String {
        guard let path, !path.isEmpty else {
            return lang == .vi ? "Liên kết một thư mục…" : "Link a folder…"
        }
        let name = Project.nameFromPath(path)
        return lang == .vi ? "Thư mục — \(name)" : "Linked folder — \(name)"
    }

    static func changeFolderLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Đổi…" : "Change…"
    }

    static func openEnvironmentLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Mở Môi trường" : "Open Environment"
    }

    /// Codepet's answer to Claude's three separate Skills / Connectors / Add plugins
    /// doors. `Toolkit` already has all three categories with real `ConnectorAuth`,
    /// and turning a connector on mid-sentence is a trip to a settings page — it
    /// should look like one rather than wear a menu costume.
    static func setupLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Cài đặt kỹ năng & kết nối…" : "Set up skills & connectors…"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/PlusMenuTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t6.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t6.xcresult | head -20
```

Expected: 7 tests, 7 passed, 0 failed.

If `Project.nameFromPath` is not visible, confirm the symbol with `grep -rn "func nameFromPath" codepet/` — `ChatComposer` already calls it, so it exists.

- [ ] **Step 5: Rewrite the menu in `ChatComposer`**

Replace `quickActionsMenu` wholesale with:

```swift
    /// The capability door — spec §5. Two sections and a footer.
    ///
    /// `quickActions` no longer appears here. Those three are prompt STARTERS and
    /// they are already cards on the empty hero; the `+` was their second home, and
    /// a menu that mixes "say this for me" with "let the model see this" has no
    /// organising idea. `CopilotChatView` still builds them for the hero.
    private var plusMenu: some View {
        Menu {
            if let pins {
                Section(PlusMenu.bringInLabel(lang)) {
                    Menu(PlusMenu.libraryLabel(lang)) {
                        ForEach(PlusMenu.recentLibrary(companyStore.company.library)) { d in
                            Button(d.title) {
                                pins.wrappedValue = ContextPin.adding(
                                    .deliverable(id: d.id, title: d.title), to: pins.wrappedValue)
                            }
                            .disabled(pins.wrappedValue.count >= ContextPin.max)
                        }
                        Divider()
                        Button(PlusMenu.browseLibraryLabel(lang)) { companyStore.select(.library) }
                    }
                    Menu(PlusMenu.taskLabel(lang)) {
                        ForEach(PlusMenu.openTasks(companyStore.company.tasks)) { t in
                            Button(t.title) {
                                pins.wrappedValue = ContextPin.adding(
                                    .task(id: t.id, title: t.title), to: pins.wrappedValue)
                            }
                            .disabled(pins.wrappedValue.count >= ContextPin.max)
                        }
                        Divider()
                        Button(PlusMenu.openRoadmapLabel(lang)) { companyStore.select(.roadmap) }
                    }
                    // A toggle, not a picker: `memoryEnabled` is already the real gate
                    // on the decisions block in `ChatContext.compose`.
                    Button {
                        Task {
                            await companyStore.updateFounderPrefs { $0.memoryEnabled.toggle() }
                        }
                    } label: {
                        if companyStore.company.founderPrefs.memoryEnabled {
                            Label(PlusMenu.knowsLabel(lang), systemImage: "checkmark")
                        } else {
                            Text(PlusMenu.knowsLabel(lang))
                        }
                    }
                    Menu(PlusMenu.folderLabel(lang, path: companyStore.activeProjectLink?.path)) {
                        Button(PlusMenu.changeFolderLabel(lang)) {
                            _ = ProjectLinker.pickAndLink(into: companyStore, language: lang)
                        }
                        Button(PlusMenu.openEnvironmentLabel(lang)) {
                            companyStore.select(.environment)
                        }
                    }
                }
            }
            // Two-mode only, and this is a decision rather than an oversight: the
            // dock still reaches the room through its `.plan` mode pill
            // (`ChatMode.convenesRoom`), so a row here would be a SECOND door to
            // one ~10-credit act on the same surface. The pane has no mode pill,
            // which is why `RoomOffer` exists at all.
            if surface == .twoMode {
                Section(PlusMenu.goDeeperLabel(lang)) {
                    Button {
                        onConveneRoom()
                    } label: {
                        Label(RoomOffer.label(lang), systemImage: "person.3")
                    }
                    .disabled(!RoomOffer.canConvene(draft: draft) || isBusy)
                    .help(RoomOffer.detail(lang))
                }
            }
            Divider()
            Button(PlusMenu.setupLabel(lang)) { companyStore.select(.environment) }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: surface == .dock ? 15 : 12, weight: .medium))
                .foregroundColor(CodepetTheme.bodyText)
                .frame(width: surface == .dock ? 30 : 26,
                       height: surface == .dock ? 30 : 26)
                // Bare in the pane. Claude and Codex both draw their `+` as a glyph with
                // no container; ours was a fourth outlined pill in a row that already had
                // three, which is most of why the control row read as heavy.
                .overlay(
                    surface == .dock
                        ? AnyView(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(CodepetTheme.hairline))
                        : nil
                )
                .hoverAffordance(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
```

Rename both call sites from `quickActionsMenu` to `plusMenu`.

`quickActions` and `onQuickAction` stay as `ChatComposer` properties — `ChatEmptyState` reads them for the hero cards. Do not delete them.

- [ ] **Step 6: Build and run**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/PlusMenuTests \
  -only-testing:codepetTests/RoomOfferTests \
  -only-testing:codepetTests/ChatLandingStateTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t6b.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t6b.xcresult | head -20
```

Expected: 0 failed. `grep -rn "quickActionsMenu" codepet/` should return nothing.

- [ ] **Step 7: Commit**

```bash
git add codepet/Models/PlusMenu.swift codepetTests/PlusMenuTests.swift codepet/Views/Copilot/ChatComposer.swift
git commit -F - <<'MSG'
feat(composer): the + becomes a capability door instead of a junk drawer

It held three prompt starters that are already cards on the empty hero, plus
the room, plus the department leftovers. Its own doc comment defended it as "a
quick-actions menu (NOT a file picker)", which accurately describes a control
with no organising idea.

It now answers one question — what does this turn see, and how hard should it
work — and Codepet's answer to the first half is not files, it's the company:
Library, roadmap, what Codepet knows, the linked folder.

Three decisions worth keeping:

"What Codepet knows" is a TOGGLE over FounderPrefs.memoryEnabled, which is
already the real gate on the decisions block. A fact-picker would be new
machinery in front of an existing boolean.

"Set up skills & connectors…" is ONE footer link, not three submenus. Toolkit
already has skills/connectors/agents with real ConnectorAuth, and turning a
connector on mid-sentence is a trip to a settings page — it should look like
one rather than wear a menu costume.

The folder row names the folder. A row reading only "Linked folder" makes the
founder open it to find out which folder the agent is about to touch.

The room's price still comes from RoomOffer.credits. A second copy of that
number in a view is how the two drift.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 7: Measure the row, run everything, open the PR

**Files:**
- Create: `codepetTests/ComposerControlRowTests.swift`
- Modify: `codepet/Views/Copilot/ChatComposer.swift` — update the file's doc comment and the `#Preview` hosts

**Interfaces:**
- Consumes: everything above.
- Produces: nothing new.

- [ ] **Step 1: Write the layout measurement**

I cannot screenshot the running app — Screen Recording is denied — so "does the row fit" is normally a handoff. Layout is not: `ImageRenderer` lays a view out for real and reports its size. Create `codepetTests/ComposerControlRowTests.swift`:

```swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// Measures the composer offscreen at both surface widths.
///
/// The whole point of collapsing eight chips into one button is that the row stops
/// overflowing at 380pt. That is a measurable claim, and it is the one claim a green
/// unit suite would otherwise not check.
@MainActor
final class ComposerControlRowTests: XCTestCase {

    /// **State is seeded in `init`, never in `.onAppear`.** `ImageRenderer` lays a
    /// view out without a window and does not reliably fire `onAppear`, so an
    /// `onAppear`-seeded `armed` would leave every host measuring the BARE row —
    /// and `testArmingADepartmentDoesNotGrowTheDock` would then compare two
    /// identical bare rows and pass while asserting nothing.
    private struct Host: View {
        let width: CGFloat
        let surface: ChatSurface
        @State private var draft: String
        @State private var mode: ChatMode = .ask
        @FocusState private var focused: Bool
        @State private var dept: Department?
        @State private var pins: [ContextPin]

        init(width: CGFloat, surface: ChatSurface,
             armed: Department? = nil, pins: [ContextPin] = []) {
            self.width = width
            self.surface = surface
            _draft = State(initialValue: "What should we charge?")
            _dept = State(initialValue: armed)
            _pins = State(initialValue: pins)
        }

        var body: some View {
            ChatComposer(
                draft: $draft, mode: $mode, canSend: true, focus: $focused,
                placeholder: "Ask anything about your company…",
                quickActions: [], accent: CodepetTheme.accentPurple,
                accent2: CodepetTheme.accentPink, isBusy: false,
                pins: $pins, selectedDept: $dept,
                onSend: {}, onQuickAction: { _ in }
            )
            .frame(width: width)
            .environment(\.chatSurface, surface)
            .environmentObject(CompanyStore())
        }
    }

    private func size(_ view: some View) -> CGSize {
        ImageRenderer(content: view).nsImage?.size ?? .zero
    }

    /// **Guards the guard.** The test below asserts arming does NOT change the
    /// composer's height at 380pt — which means at 380pt a host that failed to arm
    /// is indistinguishable from one that armed correctly, and the assertion would
    /// pass while checking nothing.
    ///
    /// So prove the seeded state takes somewhere it cannot hide: at 150pt the armed
    /// label (sprite + pet name + department + `✕`) cannot share a line with `+` and
    /// the send button, so the row wraps and the composer grows. If this goes red,
    /// every height assertion in this suite is vacuous — fix the host, not this.
    func testTheArmedHostReallyArms() {
        let bare = size(Host(width: 150, surface: .dock))
        let armed = size(Host(width: 150, surface: .dock, armed: DepartmentCatalog.find("eng")))
        XCTAssertGreaterThan(bare.height, 0, "nothing laid out at all")
        XCTAssertGreaterThan(armed.height, bare.height,
                             "armed \(armed.height)pt vs bare \(bare.height)pt at 150pt wide — "
                             + "the seeded department never took, so the equality assertions "
                             + "in this suite are comparing identical views")
    }

    /// The dock at its real width, nothing armed. A row that wrapped would grow the
    /// composer's height past the two-line baseline.
    func testTheDockRowFitsAt380() {
        let bare = size(Host(width: 380, surface: .dock))
        XCTAssertGreaterThan(bare.height, 40, "the composer measured \(bare.height)pt — it did not lay out")
        XCTAssertLessThan(bare.height, 220,
                          "the dock composer is \(bare.height)pt tall — the control row wrapped")
    }

    /// **Arming must not change the composer's height.** The armed label is longer
    /// than "Departments" — it carries a sprite, a pet name and a `✕` — and if that
    /// wraps at 380pt the composer grows under the founder's cursor the moment she
    /// picks a department.
    func testArmingADepartmentDoesNotGrowTheDock() {
        let bare = size(Host(width: 380, surface: .dock))
        let armed = size(Host(width: 380, surface: .dock, armed: DepartmentCatalog.find("eng")))
        XCTAssertEqual(bare.height, armed.height, accuracy: 1,
                       "bare \(bare.height)pt vs armed \(armed.height)pt — the armed label wrapped")
    }

    /// Three pins is the cap, and it must stay one line rather than stacking three
    /// rows above the field.
    func testThreePinsAddOneRowNotThree() {
        let none = size(Host(width: 380, surface: .dock))
        let three = size(Host(width: 380, surface: .dock, pins: [
            .deliverable(id: "d1", title: "Pricing"),
            .task(id: "t1", title: "Ship billing"),
            .deliverable(id: "d2", title: "ICP"),
        ]))
        let added = three.height - none.height
        XCTAssertGreaterThan(added, 8, "the pins reserved no height — the pill row did not render")
        XCTAssertLessThan(added, 60,
                          "three pins added \(added)pt — the pill row is stacking instead of staying one line")
    }

    func testThePaneRowFitsAtItsWidth() {
        let pane = size(Host(width: 720, surface: .twoMode, armed: DepartmentCatalog.find("mkt")))
        XCTAssertGreaterThan(pane.height, 40)
        XCTAssertLessThan(pane.height, 220, "the pane composer is \(pane.height)pt tall — the row wrapped")
    }
}
#endif
```

- [ ] **Step 2: Run it**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ComposerControlRowTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/t7.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/t7.xcresult | head -20
```

Expected: 5 tests, 5 passed. A failure here is a **real layout defect**, not a bad threshold — read the measured number in the failure message and fix the view. Widen a threshold only if the measured number is plainly reasonable and the bound was wrong; say so in the commit if you do.

Per the `ImageRenderer` note in `MockFlowCaptionBarLayoutTests`: it renders nothing inside a `ScrollView`. The composer is not in one here, which is why this works.

- [ ] **Step 3: Refresh the file's doc comment and previews**

The header on `ChatComposer.swift` still describes the retired design. Replace the two stale paragraphs:

```swift
/// Honesty notes: the `+` button is a quick-actions menu (NOT a file picker —
/// the app has no attachments), and the mode control shapes the outgoing message
/// via `ChatMode` (no backend mode exists).
///
/// DOCK ADAPTATION (380pt): `deptChips` shows the first 2 department chips (PR#39
/// showed 3) + the `•••` overflow menu, so the chip row + the active-project chip
/// fit inside the 380pt dock width.
```

with:

```swift
/// Two controls, not four — spec `2026-08-21-composer-controls-design.md`.
/// `departmentControl` collapses all eight departments into one button (it replaced
/// three chips, a `•••` overflow, and a fourth chip that appeared only when the
/// selection came from that overflow), and `plusMenu` is the capability door: what
/// this turn gets to see, and how hard it should work.
///
/// Honesty notes: there are still NO attachments — `+` brings in company context
/// (Library, roadmap, the linked folder), not files. `📎 Attach` and a `🌐 Web search`
/// toggle are named follow-ups in §7 of that spec, deliberately absent rather than
/// greyed. The mode control shapes the outgoing message via `ChatMode` (no backend
/// mode exists).
```

Update the two `#Preview` blocks at the bottom: `ChatComposerPreviewHost` gains `@State private var pins: [ContextPin] = []` and passes `pins: $pins`. Retitle the second preview from `"ChatComposer (Marketing armed)"` to `"ChatComposer (Marketing armed + 2 pins)"` and seed it with two pins, so the two states worth comparing at 380pt are the bare row and the fullest one.

- [ ] **Step 4: Run the FULL suite**

A `-only-testing:` branch is an untested branch — the first full run on this branch's predecessor found three real regressions.

```bash
pkill -x codepet 2>/dev/null; ./scripts/ci-test.sh 2>&1 | tail -40
```

Expected: `All N test(s) passed.` If it reports the known `@MainActor ObservableObject` dealloc crash as a part-way host death, the run is **incomplete, not green** — re-run once. If it repeats, report what did and did not run rather than calling it a pass.

Do not `pkill` if a sibling session may be running the app — check first, and build-only if so.

- [ ] **Step 5: Commit and open a draft PR**

Pushing a branch runs NOTHING. Open a PR, even a draft, or CI never sees this.

```bash
git add codepetTests/ComposerControlRowTests.swift codepet/Views/Copilot/ChatComposer.swift
git commit -F - <<'MSG'
test(composer): measure the control row at both surface widths

The point of collapsing eight chips into one button is that the row stops
overflowing at 380pt, and that is the one claim a green unit suite does not
check. ImageRenderer lays the composer out for real and reports its size, so
it is checkable offscreen — which matters here because Screen Recording is
denied in this environment and the visual pass is a handoff.

The assertion worth keeping is that ARMING does not change the composer's
height. The armed label carries a sprite, a pet name and a ✕, so it is
materially longer than "Departments"; if it wrapped at 380pt the composer
would grow under the founder's cursor the moment she picks a department.

Also refreshes the file header, which still described the chips and called the
+ a quick-actions menu.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG

git push -u origin feat/composer-controls
gh pr create --draft --base feat/two-mode-shell \
  --title "Composer controls: one departments button, and a + that means something" \
  --body "$(cat <<'BODY'
Spec: `docs/superpowers/specs/2026-08-21-composer-controls-design.md`

The control row was four controls doing three jobs, and the department chips changed
shape depending on what was selected — three chips (two in the dock), a `•••`
overflow, and a fourth promoted chip when the selection came from that overflow.
Eight departments had three separate doors.

Now: one `Departments ▾` button that becomes the armed chip, and a `+` that answers
one question — what does this turn see, and how hard should it work.

**The part to review is the grounding.** `selectPriorWork` already ranks up to three
Library deliverables into every turn's grounding, so a pinned deliverable would land
twice: once at the 240-char automatic excerpt and once at the 1200-char pinned one.
That is not emphasis, it tells the model there are two documents with the same title.
Pinned ids are excluded from the automatic set and a test asserts the title appears
exactly once.

Which also means "From your Library" is not a new capability — it replaces the
ranker's guess with the founder's choice and gives the choice more room. The spec
says so in those words.

**Deliberately absent:** `📎 Attach` and a `🌐 Web search` toggle. Omitted rather than
greyed, which departs from this branch's own `ApprovalTier.isHonoured` precedent on
purpose — a founder who wrongly believes a run will prompt her faces a safety
failure, so the tier must show its gap; a missing paperclip just looks unfinished on
the most-used control in the app during a paid beta. Web search cannot ship honestly
yet either: the tool is registered server-side and fires at the model's discretion,
so OFF would have to actually strip it from the request.

Swift only — nothing under `functions/`, so no deploy risk across the freeze.

**Needs a human's eyes.** Screen Recording is denied in my environment, so layout is
measured offscreen with `ImageRenderer` and the *look* is unverified. One specific
question: **does the pet sprite render in the department menu rows, or does macOS drop
it?** If it drops, the documented fallback is text-only `crash · Engineering` — the
call site says so.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

- [ ] **Step 6: Confirm CI actually ran**

```bash
sleep 45; gh pr checks --watch
```

Expected: the `test` and `functions` jobs both report. A PR with no checks means the workflow did not trigger — investigate before calling this done.

---

## Self-Review

**Spec coverage.** §3 retires → Tasks 4 and 6. §4 departments control → Task 4. §5 `+` menu, all six rows → Task 6. §6 `ContextPin` and the double-count guard → Tasks 1, 2, 3, 5. §7 follow-ups → not built, restated in the PR body and the file header. §8 testing → the five suites are Tasks 1, 2, 4, 6, 7 plus `ContextPinLifecycleTests` in Task 5. §9 risks → the sprite fallback is documented at the call site (Task 4 Step 6), the handoff question is in the PR body (Task 7 Step 5). §10 open → Product stays off the roster, asserted in `DepartmentMenuTests.testProductIsNotOffered`.

**One spec item with no task, by design:** the dock's project chip. §3 says it "moves onto its own row"; Task 4 Step 6 does that inside the `dockBody` edit rather than as its own task, because it cannot compile separately from the `deptChips` deletion that frees the row.

**Type consistency.** `ContextPin.groundingHeading` is the single name used in Tasks 1, 2, 3 and 5 (an earlier draft called it `label(_:)` in the interface block — corrected). `ContextPin.max` is used in Tasks 1, 5 and 6. `DepartmentMenu.rowTitle(_:host:)` and `armedLabel(_:host:)` both take `host:` and are called with `companyStore.company.companionId` at the one call site. `PlusMenu.recentLibrary(_:)`/`openTasks(_:)` take the collection, not the store.

**Pre-flight corrections applied 21 Aug, before Task 2 was dispatched.** Five things in the first draft would not have compiled or would have asserted nothing, all found by reading the models rather than trusting the draft:

- `TaskWho` is `does | draft | you` — the draft used `.codepet` and `.founder` (Tasks 2 and 6)
- `CompanyBrief` has `projectName`/`oneLiner`, not `name`/`idea` (Task 2)
- `CompanyStore.company` is `private(set)` — state seeds through the **loader** and `hydrate`, never by assignment, and the reply type is `CompanyChatReply(text:runTaskId:)` behind a deliberately-failing `chatStreamer` (Tasks 3 and 5, both rewritten against `CompanyStoreChatTests`, the pattern of record)
- Task 7's host seeded `armed` in `.onAppear`, which `ImageRenderer` does not reliably fire — every height assertion would have compared identical bare rows. State now seeds in `init`, and `testTheArmedHostReallyArms` proves it took at 150pt where the armed label cannot hide
- Task 6's room row is gated to `surface == .twoMode`. The dock reaches the room through its `.plan` mode pill, so an ungated row would be a second door to one ~10-credit act on the same surface
