# Typed Deliverable Viewers — Native (A2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox (`- [ ]`) steps.

**Goal:** Render 4 typed deliverable viewers (checklist, doc, plan, dms) from the structured `payload` the runTask CF now returns; fall back to `MarkdownView(body)` for all other kinds.

**Architecture:** Add an optional `payload` (a `DeliverablePayload` with all-optional per-kind fields) to `Deliverable` + `RunTaskResponse`; `buildDeliverable` carries it through; `DeliverableDetailView` switches on kind → typed viewer when the payload is present, else the existing `MarkdownView`. Backend (A1) is deployed live. Payload round-trips in the `companies/{uid}.library` Codable JSON path.

**Tech Stack:** Swift, SwiftUI, XCTest.

## Global Constraints

- Branch `feat/typed-viewers-native` (off `origin/main`). Work in `~/Documents/Murror/codepet`.
- `payload` is additive/optional: legacy library items (no payload) and non-structured kinds render via `MarkdownView(body)` unchanged. `body` is always present.
- Payload shape mirrors the deployed CF contract (A1): checklist `{items:[{t,done}]}`, doc `{call,sections:[{h,p}],next:[String]}`, plan `{goal,steps:[String],changes:[{area,edit}],verify:[String],risks}`, dms `{messages:[{name,note,msg}]}`.
- Xcode 26.2 test caveat: struct-only tests (Deliverable Codable) run clean; CompanyStore (@MainActor) tests may crash on teardown — verify via assertion-green + build. SwiftUI viewers are build-verified.
- Build/verify: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`.

---

### Task 1: `Deliverable.payload` model

**Files:** Modify `codepet/Models/Deliverable.swift`; Test `codepetTests/DeliverablePayloadTests.swift`

**Interfaces:** Produces `DeliverablePayload` (+ `ChecklistItem`, `DocSection`, `PlanChange`, `DmMessage`) and `Deliverable.payload: DeliverablePayload?`. Consumed by Tasks 2-3.

- [ ] **Step 1: Add the payload types + field**

In `codepet/Models/Deliverable.swift`, add (before the `Deliverable` struct):

```swift
struct ChecklistItem: Codable, Hashable { var t: String; var done: Bool }
struct DocSection: Codable, Hashable { var h: String; var p: String }
struct PlanChange: Codable, Hashable { var area: String; var edit: String }
struct DmMessage: Codable, Hashable { var name: String; var note: String; var msg: String }

/// Structured per-kind fields returned by the runTask CF (A1). All optional — one
/// kind's fields are populated at a time; nil for legacy/markdown-only deliverables.
struct DeliverablePayload: Codable, Hashable {
    // checklist
    var items: [ChecklistItem]?
    // doc
    var call: String?
    var sections: [DocSection]?
    var next: [String]?
    // plan
    var goal: String?
    var steps: [String]?
    var changes: [PlanChange]?
    var verify: [String]?
    var risks: String?
    // dms
    var messages: [DmMessage]?
}
```

Add to the `Deliverable` struct (after `sourceTaskId`) and its init:
```swift
    var payload: DeliverablePayload?
```
Add `payload: DeliverablePayload? = nil` as the last init parameter and `self.payload = payload`.

- [ ] **Step 2: Round-trip test**

Create `codepetTests/DeliverablePayloadTests.swift`:
```swift
import XCTest
@testable import codepet

final class DeliverablePayloadTests: XCTestCase {
    func testChecklistPayloadRoundTrips() throws {
        let d = Deliverable(kind: .checklist, title: "T", body: "md",
            payload: DeliverablePayload(items: [ChecklistItem(t: "Step", done: false)]))
        let back = try JSONDecoder().decode(Deliverable.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.payload?.items?.first?.t, "Step")
    }
    func testLegacyDeliverableWithoutPayloadDecodes() throws {
        let legacy = #"{"id":"x","kind":"post","title":"T","body":"md"}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(legacy.utf8))
        XCTAssertNil(back.payload)
    }
    func testDecodesStructuredPayloadFromCFShape() throws {
        let json = #"{"id":"y","kind":"plan","title":"P","body":"md","payload":{"goal":"g","steps":["a"],"changes":[{"area":"x","edit":"y"}],"verify":[],"risks":"r"}}"#
        let back = try JSONDecoder().decode(Deliverable.self, from: Data(json.utf8))
        XCTAssertEqual(back.payload?.goal, "g")
        XCTAssertEqual(back.payload?.changes?.first?.area, "x")
    }
}
```

- [ ] **Step 3: Run test → pass**

`xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DeliverablePayloadTests` → PASS (struct-only, clean).

- [ ] **Step 4: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/Deliverable.swift codepetTests/DeliverablePayloadTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: DeliverablePayload (typed per-kind fields) on Deliverable

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Decode payload from the CF + carry through `buildDeliverable`

**Files:** Modify `codepet/Services/RunTaskClient.swift`, `codepet/Managers/CompanyStore.swift`; Test `codepetTests/CompanyStoreRunTaskTests.swift`

**Interfaces:** Consumes Task 1. Produces `RunTaskResponse.payload`; `buildDeliverable` carries `payload`.

- [ ] **Step 1: Add `payload` to `RunTaskResponse`**

In `codepet/Services/RunTaskClient.swift`, add to `struct RunTaskResponse` (after `body`):
```swift
    var payload: DeliverablePayload?
```

- [ ] **Step 2: Carry it in `buildDeliverable`**

In `codepet/Managers/CompanyStore.swift`, read the current `buildDeliverable(from:task:)`. In the `Deliverable(...)` it constructs, add `payload: result.payload` as the last argument (alongside id/kind/title/body/createdAt/sourceTaskId).

- [ ] **Step 3: Test payload carry**

Add to `codepetTests/CompanyStoreRunTaskTests.swift` (read the file's stub pattern first; the `taskRunner` stub returns a `RunTaskResponse`):
```swift
func testRunTaskCarriesStructuredPayloadOntoDraft() async {
    let drafted = RoadmapTask(id: "t1", title: "T", detail: "", phase: .find, who: .does)
    let seed = CompanyState(brief: .init(), departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(), tasks: [drafted])
    let s = CompanyStore(loader: { _ in seed },
        taskRunner: { _ in RunTaskResponse(kind: "checklist", title: "C", body: "md",
            payload: DeliverablePayload(items: [ChecklistItem(t: "Step", done: false)])) })
    await s.hydrate(companyId: "u")
    await s.runTask(s.company.tasks[0], language: .en)
    XCTAssertEqual(s.company.tasks[0].draft?.payload?.items?.first?.t, "Step")
}
```
(If `RunTaskResponse`'s memberwise init requires all fields in order, match it — read the struct. `RunTaskResponse` is Codable so it has a memberwise init.)

- [ ] **Step 4: Run test + build**

`xcodebuild test … -only-testing:codepetTests/CompanyStoreRunTaskTests` (assertion-green; Xcode 26.2 teardown caveat) then `xcodebuild build …` → SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Services/RunTaskClient.swift codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreRunTaskTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: decode + carry structured deliverable payload through runTask

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: 4 typed viewers + DeliverableDetailView dispatch

**Files:** Create `codepet/Views/Library/DeliverableViewers.swift`; Modify `codepet/Views/Library/LibraryView.swift`

**Interfaces:** Consumes `DeliverablePayload` (Task 1).

- [ ] **Step 1: Create the 4 viewers**

Create `codepet/Views/Library/DeliverableViewers.swift` — four SwiftUI views reading the payload, styled with `CodepetTheme`/`.pixelSystem` like the surrounding library UI. Each takes the relevant payload slice; render:
- **ChecklistViewer(items:)** — a `ProgressView(value: doneCount/total)` + a `VStack` of rows, each `Image(systemName: item.done ? "checkmark.square.fill" : "square")` + `Text(item.t)` (strikethrough when done). Local `@State` copy of items so taps toggle visually (view-only; not persisted this slice).
- **DocViewer(call:sections:next:)** — a tinted call-out box (`CodepetTheme.accentPurple.opacity(0.1)`) with the `call`; then each section as `Text(h).bold()` + `Text(p)`; then a "Next" list of `next` bullets.
- **PlanViewer(payload:)** — labeled sections: Goal, Steps (numbered), Changes (`area` → `edit`), Verify (checks), Risks.
- **DmsViewer(messages:)** — per-message cards: `name` + `note` chip + `msg`, with a Copy button (`NSPasteboard.general.setString(msg, forType: .string)`) and a local `@State` "Mark sent" toggle.

Keep each viewer self-contained, wrapped in a `ScrollView` by the caller. Read the existing `MarkdownView.swift` + `DeliverableCardView` for the house style (fonts, colors, spacing).

- [ ] **Step 2: Dispatch in `DeliverableDetailView`**

In `codepet/Views/Library/LibraryView.swift`, replace the body's `ScrollView { MarkdownView(markdown: deliverable.body).padding(16) }` (line ~92) with a kind-switched `ScrollView`:
```swift
            ScrollView {
                Group {
                    switch deliverable.kind {
                    case .checklist where deliverable.payload?.items != nil:
                        ChecklistViewer(items: deliverable.payload!.items!)
                    case .doc where deliverable.payload?.call != nil:
                        DocViewer(call: deliverable.payload!.call!,
                                  sections: deliverable.payload?.sections ?? [],
                                  next: deliverable.payload?.next ?? [])
                    case .plan where deliverable.payload?.goal != nil:
                        PlanViewer(payload: deliverable.payload!)
                    case .dms where deliverable.payload?.messages != nil:
                        DmsViewer(messages: deliverable.payload!.messages!)
                    default:
                        MarkdownView(markdown: deliverable.body)
                    }
                }
                .padding(16)
            }
```

- [ ] **Step 3: Build**

`xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`. (Viewers are visual — confirmed at runtime by the product owner.)

- [ ] **Step 4: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Views/Library/DeliverableViewers.swift codepet/Views/Library/LibraryView.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: typed deliverable viewers (checklist/doc/plan/dms) + dispatch

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** payload model (T1), CF decode + carry (T2), 4 viewers + dispatch (T3). ✓
**Placeholders:** concrete code for model/wiring/dispatch; viewers described with exact payload fields + house-style references (SwiftUI layout is build-verified, not unit-tested). ✓
**Type consistency:** `DeliverablePayload` + sub-structs (T1) used in RunTaskResponse/buildDeliverable (T2) and the viewers/dispatch (T3). Backward-compat: `payload?` optional, default nil, legacy decode test. ✓
**No CF change:** A1 already deployed; A2 is client-only. Fallback to `MarkdownView(body)` for all non-4 kinds + missing payload. ✓
