# Departments that build on each other, and cards that show the work

**Date:** 2026-09-03
**Status:** approved, not implemented
**Stacked on:** PR #123 `feat/murror-demo-project` (green). §1 edits `draftCard`, which that
branch does not touch, but the Murror fixtures are what both halves are demonstrated against —
so this work branches from `main` after #123 merges.
**Surface:** `codepet/Views/Copilot/CopilotChatView.swift` (`draftCard`), new
`codepet/Views/Copilot/DraftPayloadPreview.swift`, new
`codepet/Views/Copilot/UpstreamCredit.swift`, `codepet/Services/RunTaskClient.swift`,
`codepet/Managers/CompanyStore.swift`, `codepet/Services/MockChat.swift`,
`functions/src/runTaskCore.ts`, `functions/src/runTask.ts`,
`functions/src/local/oneShotOps.ts`

## Why

Two founder reports from testing the Murror demo, both about the same thing seen from different
angles: **the work is real, and the product does not show it.**

> *"each department's output should appear on the card as soon as it's completed — for example,
> if it's a website link, display the link right away, or if it's a spreadsheet, display the
> spreadsheet directly on the card"*

> *"the workflow isn't quite complete when departments collaborate with each other, and let's
> assume this is the case for a completely new user"*

### The card never shows the deliverable

`draftCard` (`CopilotChatView.swift:2221`) renders `DraftPreview.plain(d.body)` under a
`lineLimit`, and **`d.payload` is not read at all.** Every structured viewer already exists and
only the Library mounts them. So Finance's pricing model — a four-input interactive model — is
a truncated paragraph ending in `....`, and the landing page is a sentence that says *"The page
is live in your Library — open it to see it rendered."*

That sentence is the whole problem in miniature: the card explains where the work is instead of
being it.

### Departments do not actually collaborate

`mur-site` depends on `mur-brand`. Running it passes **nothing** of Luna's output to Nova:
`RunTaskRequest` has no field for it, `CompanyStore` never assembles one, and
`buildRunTaskPrompt` has nowhere to put one. The dependency graph gates **order** and never
**information**.

This is the same shape as a bug already fixed in this file. `runTaskCore.ts:60-63` records it:

> *"A run has always been performed BY a department — its pet is credited on the execute log and
> on the draft card — but the prompt was never told which one, so a marketing deliverable was
> written with no marketing knowledge behind it."*

Identical structure: the arrows are on screen, the model never hears about them. A founder sees
Design → Marketing on the board and gets a page that could not have read the brand direction.

### Why the new-user case is the sharp one

A brand-new founder has nothing approved, so feed-forward has nothing to feed. Today the
downstream task simply reads `.blocked` and the founder is told to go away and do something
else first — which is precisely when they are least equipped to know what.

## 1. The card shows the deliverable

A new view, `DraftPayloadPreview(deliverable:)`, sits in `draftCard` between the title block and
the exec-log chip. It reads the payload that is already on the `Deliverable` and renders the
treatment that fits the kind.

| Kind | On the card | Payload read |
|---|---|---|
| `site` | brand, headline, accent swatch, CTA label, then **Open** | `SitePayload` |
| `sheet` | the four inputs as read-only rows with their values, plus `summary` | `SheetPayload` |
| `screens` | horizontal row of screen thumbnails (name + title + `artStandIn`) | `ScreensPayload` |
| `checklist` | first 3 `items` with real checkboxes, then "+N more" | `[ChecklistItem]` |
| `dms` | first message's `name` + `msg`, then "N recipients" | `[DmMessage]` |
| `doc` | `call` verbatim, then section headings only | `call`, `sections` |
| `plan` | `goal`, then "N steps · M changes" | `goal`, `steps`, `changes` |
| everything else | today's `DraftPreview.plain` body, unchanged | — |

**Capped at 180pt** with no internal scrolling. A card that scrolls inside a scrolling
transcript is worse than a card that truncates, and the full viewer is one tap away — the title
block already opens it (`showDetail`).

### The site preview is native, not a screenshot

`SiteViewer.buildHTML` produces a real page and `SiteHTMLWebView` renders it, but a
`WKWebView` per message is the wrong price for a preview: it is heavy, asynchronous, and a
transcript can hold many cards. A pixel-accurate thumbnail would need an offscreen snapshot,
which is a separate piece of work if it is ever wanted.

What ships instead is the page's **identity** at card size — its brand, its headline, its accent
as a real colour swatch, its primary CTA. Those are the fields a founder recognises the page by,
and **Open** reaches the true render.

`accent` is drawn through the same `safeHex` validation the viewer uses, so a malformed hex
degrades to the fallback rather than rendering a broken swatch.

### No payload, no invention

Only `site`, `screens`, `sheet` and `dms` carry a payload in the Murror fixtures. A kind with a
nil payload falls back to the prose preview. Rendering an empty structured view — three blank
slider rows, a checklist with no items — would look like a broken card rather than an absent
payload, and the founder cannot tell those apart.

## 2. Outputs feed forward

### The wire

```swift
struct UpstreamWork: Codable, Hashable {
    let taskTitle: String
    let deptName: String    // "Design"
    let petName: String     // "Luna"
    let kind: String
    let body: String
}
```

`RunTaskRequest` gains `var upstream: [UpstreamWork] = []`. `RunTaskArgs` in
`runTaskCore.ts` gains the matching optional field, `runTask.ts` passes it through, and the
`runTask` entry in `local/oneShotOps.ts` does too — **all three, or the local path silently
drops it.** `ONE_SHOT_OPS` is the registry a rename has to fail in `jest` rather than on a
founder's machine, and this adds a field to the op it already pins.

### Where it comes from

`CompanyStore`, at the one site that builds the request (`CompanyStore.swift:2540`): for each id
in the task's `dependsOn`, resolve the filed deliverable via
`RoadmapEngine.deliverable(for:in:)` over `company.library`, and map it with its department's
name and pet from `DepartmentCatalog` + `DepartmentCompanions`.

**Bodies are clipped, upstream is capped.** A task with four dependencies would otherwise put
four full deliverables into a prompt that already carries 4000 characters of company context.
Cap at **3 upstream items, 1500 characters each**, in `dependsOn` order (the fixture
authors that array deliberately, so its order is the intended precedence — not an arbitrary
notion of "nearest"). `clip` already
exists in `runTaskCore.ts` and every other field goes through it.

### What the prompt does with it

A block between `deptBlock` and the company context, mirroring `deptBlock`'s framing:

```
Other departments have already produced work this task must build on:

— Luna (Design) produced "Shape the Murror visual direction":
<body>

Build on this. Do not contradict it, and do not re-derive what it already decided.
Where you rely on it, say so in one short phrase.
```

That last line is what makes the credit on the card honest rather than decorative: the model is
asked to name its inheritance, so the card is reporting something the deliverable actually says.

### What the card shows

`UpstreamCredit` renders above the payload preview: *"Built on Luna's brand direction"*,
tappable to open that deliverable. Absent when `upstream` is empty, so a first task is not
decorated with an empty row.

## 3. The chain, for a founder with nothing upstream

When a run is asked for and any `dependsOn` task has no filed deliverable, the run does not
proceed silently. It answers with a **needs-upstream card**:

> *"This needs Luna's brand direction first."* — `[Run both]` `[Just mine]`

- **`Run both`** runs the upstream task, then the requested one with that output as `upstream`.
  Both cards land, in order.
- **`Just mine`** runs it alone, and the deliverable names what it had to assume.

### Chained runs do not stop for approval

**Founder decision, 2026-09-03.** Requiring approval between the two runs would stall the chain
on the exact founder who least knows what they are approving. So the upstream draft is passed
forward unapproved, and **the downstream card says so** — the credit reads *"Built on Luna's
brand direction (unapproved draft)"*.

The alternative was rejected as worse in both directions: a chain that halts teaches nothing,
and a chain that hides the unapproved state is the fixture-lie failure mode this codebase keeps
paying for. Saying it on the card costs one phrase.

Approval remains the gate on the *phase window* — `RoadmapGating.awaitsApproval` is untouched, so
an unapproved draft still holds the next phase shut. Chaining moves work forward within what is
already open; it does not open anything.

## 4. Testing

`DraftPayloadPreview` and `UpstreamCredit` are `Deliverable`/`[UpstreamWork]` → `View`, so they
are testable through `ImageRenderer` for layout and directly for their decisions. The prompt and
the assembly are pure functions and are tested as such.

Each row names the edit that turns it red — the fixture-tracing rule.

| Test | Asserts | Goes red when |
|---|---|---|
| `everyKindWithAPayloadGetsAStructuredPreview` | for each Murror deliverable carrying a payload, the preview is the structured branch, not prose | a kind is added to the table without a branch |
| `aNilPayloadFallsBackToProse` | `site` kind with nil payload renders the prose preview | the switch dispatches on kind alone and renders an empty structured view |
| `siteAccentGoesThroughSafeHex` | a malformed accent renders the fallback colour | the swatch reads the raw string |
| `previewIsHeightCapped` | rendered height ≤ 180pt for the longest fixture | a kind's branch grows unbounded |
| `upstreamIsAssembledFromDependsOn` | a task with two satisfied deps yields two `UpstreamWork`, in `dependsOn` order | the resolve or the ordering breaks |
| `upstreamSkipsUnfiledDependencies` | a dep with no filed deliverable is absent, not a placeholder | an empty entry is emitted |
| `upstreamIsCappedAtThreeAndClipped` | 5 deps → 3 items, each body ≤ 1500 chars | either cap is removed |
| `promptIncludesUpstreamAndItsInstruction` | `buildRunTaskPrompt` contains the pet, the dept, the body and the "build on this" instruction | the block is dropped or the instruction is softened |
| `promptOmitsTheBlockWhenUpstreamIsEmpty` | no upstream heading in the prompt | an empty block is emitted, costing tokens and confusing the model |
| `oneShotRunTaskForwardsUpstream` (jest) | the local op passes `upstream` through | the registry entry is not updated with the field |
| `creditIsAbsentWithoutUpstream` | no credit row on a first task | the row renders empty |
| `creditNamesTheDraftAsUnapproved` | a chained run's credit says "unapproved draft" | the state is hidden |
| `chainRunsUpstreamThenDownstream` | "Run both" produces two deliverables, the second carrying the first as upstream | the chain runs them in parallel or drops the hand-off |

## 5. Sequencing

§1 is a view change and lands first — it is visible immediately and depends on nothing else.
§2 and §3 change the run contract across Swift and TypeScript and land together, because §3's
chain is meaningless without §2's feed-forward.

`scripts/build-sidecar.sh` must be re-run after the `functions/src/` change and before any
build that exercises the local path, or the routers report `localUnavailable`.

## Out of scope

- **A pixel-accurate site thumbnail.** Needs an offscreen `WKWebView` snapshot; the native hero
  strip carries the page's identity at card size and **Open** reaches the real render.
- **Departments negotiating before producing.** Connecting the Virtual Company room to real
  output is the third reading of "collaborate" and a much larger piece. The room still produces
  no deliverable.
- **Re-running downstream work when upstream changes.** Approving a revised brand direction does
  not invalidate a page already built on the old one. Worth doing, and a reconciliation problem
  rather than a hand-off one.
- **`product` still has no pet.** Unchanged and still launch-blocking.

## Verification

`xcodebuild test` exits 65 on a clean checkout — the XCTest host crashes on Xcode 26.2 when a
`@MainActor ObservableObject` deallocates. Run per-suite with `-only-testing:` and read counts
from `xcresulttool get test-results summary`, never from the exit code. `functions/` runs jest.

Screen Recording is denied on this machine, so the card cannot be screenshotted from here.
`DraftPayloadPreview` takes no `@EnvironmentObject`, which is what makes `ImageRenderer` → PNG
viable for it — and that is the only way the layout gets looked at before the founder sees it.
Final judgement on whether the previews read well on screen is the founder's.
