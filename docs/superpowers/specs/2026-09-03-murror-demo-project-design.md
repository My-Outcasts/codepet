# A second demo company: Murror, and a run that produces a real website

**Date:** 2026-09-03
**Status:** approved, not implemented
**Branch:** `feat/murror-demo-project`, from `main` @ `ee0ef92`
**Surface:** `codepet/Services/MockChat.swift`, `codepet/Services/MockVirtualCompany.swift`,
`codepet/Models/PrototypeMode.swift` (read-only — the store seam), new
`codepet/Demo/DemoProject.swift`, new `codepet/Demo/DemoProjectCodepet.swift`, new
`codepet/Demo/DemoProjectMurror.swift`, new `codepetTests/DemoProjectMurrorTests.swift`

## Why

Prototype mode can already show the whole product on fixtures. What it cannot do is show *a
company* — it shows Codepet demoing Codepet, and it cannot produce a website at all.

Three specific holes, each verified in the code rather than assumed:

1. **The fixture is Codepet, not a project.** `MockChat.productName` substitutes a `{{product}}`
   token, so the *name* follows whatever the founder onboarded. Every word around the token does
   not: `deliverable(for:)` says "the AI cofounder that runs your company's busywork", "For solo
   founders drowning in scattered docs". Point it at another company and the demo reads as
   find-replace — which is precisely the conclusion `MockChat.swift:101` says the token exists to
   avoid.

2. **No run can produce a website.** `MockChat.runResult` ends
   `RunTaskResponse(kind:title:body:payload: nil)` — the payload is hardcoded nil. So the
   `.site` viewer, which renders a genuine landing page in a `WKWebView`, is unreachable from a
   run. The only `.site` in the app is `LibraryFixtures.site`, behind a separate `-seedLibrary
   YES` launch argument, unconnected to any project or task. The most demonstrable thing the
   product makes is the one thing the demo cannot make.

3. **Five departments never speak.** `DepartmentCatalog.roster` draws 8 cards and
   `DepartmentCompanions.map` casts 6 distinct pets across them, but `MockVirtualCompany` convenes
   exactly three agents (`fin`, `mkt`, `eng`) on one hardcoded question about Codepet's paywall.
   `sage` and `glitch` have no voice anywhere in the demo.

Murror is the natural second company: it is real, it is the founder's own other product, and it
is nothing like Codepet — a consumer app about loneliness rather than a founder tool — so it
proves the fixtures carry a *project* and not a coat of paint.

### One correction to an earlier reading

An in-repo comment chain says the founder-owned `mock-interviews` task is what locks the eight
downstream cards. That was true before 2026-08-05 and is no longer:
`RoadmapGating.awaitsApproval` was changed that day so **only an unapproved draft gates a phase**,
explicitly because "one parked founder-owned step switched the entire AI team off". No fixture
task sets `drafted`, so every phase is open today. What actually blocks the eight is
`RoadmapEngine.depsSatisfied` — they hang off `mock-interviews`, which is not `done`. The
distinction decides §3 below, so it is recorded here rather than left to be rediscovered.

## 1. `DemoProject` — the seam

One value type holds everything project-specific. `MockChat` and `MockVirtualCompany` read the
selected instance instead of their own literals.

```swift
struct DemoProject {
    let id: String                     // "codepet" | "murror"
    let brief: CompanyBrief
    let tasks: [RoadmapTask]
    let deliverables: [DemoDeliverable]
    let roomFrames: [SSEFrame]
}

struct DemoDeliverable {
    let keywords: [String]     // matched against the lowercased task title
    let kind: String           // DeliverableKind rawValue
    let body: String           // markdown, may contain {{product}}
    let payloadJSON: String?   // nil for every kind but .site
}
```

`DemoProject.codepet` carries today's content, moved verbatim. `DemoProject.murror` is new.

### Selection reads through `PrototypeMode.store`

Not `UserDefaults.standard`. That property is already redirected to a scratch suite, wiped on
creation, whenever `XCTestConfigurationFilePath` is set — the fix for #117, where a founder's
toggle changed what the test target exercised and a green run told nobody. A second
demo-mode preference read off `.standard` would re-open exactly that hole in a second place.
Reusing the one seam means the isolation is inherited, not re-implemented.

Selection, mirroring `PrototypeMode`'s own precedence:

- Launch argument `-CODEPET_DEMO_PROJECT murror` — wins, because `NSArgumentDomain` outranks
  every preference file
- Otherwise the persisted key `cp_demoProject`
- Otherwise **`.codepet`**

The default is what keeps `MockFixtureRunnableTests`, `PrototypeParityTests` and `MockFlowTests`
passing with no edit: absent an explicit choice, every caller sees exactly the bytes it sees today.

### `deliverable(for:)` becomes a table walk

The current 130-line `if t.contains(...)` chain becomes a walk over `deliverables`, first match
wins. Codepet's entries are transcribed **in the chain's existing order**, because the chain's
order is load-bearing — `t.contains("landing") || t.contains("copy")` precedes the generic
fallback, and reordering would silently change which body a title resolves to.

## 2. The website

`MockChat.runResult` gains payload support — the one mechanism change in this spec:

```swift
let entry = DemoProject.current.deliverable(for: req.taskTitle)
let payload = entry.payloadJSON.flatMap {
    try? JSONDecoder().decode(DeliverablePayload.self, from: Data($0.utf8))
}
return RunTaskResponse(kind: entry.kind, title: req.taskTitle,
                       body: fill(entry.body + note), payload: payload)
```

So the flow becomes:

```
"run the landing page"
  → nova · Marketing
  → RunTaskResponse(kind: "site", payload: SitePayload)
  → Approve → filed to company.library
  → SiteViewer.buildHTML → WKWebView → a real rendered page
```

**Decoded from JSON, never built memberwise.** `SitePayload` declares `init(from:)` and so has no
memberwise init anyway, but the better reason is `LibraryFixtures`': this is the exact shape the
Cloud Function puts on the wire, and a payload built from Swift values could be a shape the
decoder rejects. `SitePayload.init(from:)` hard-decodes six anchor fields — `title`, `brand`,
`headline`, `ctaPrimary`, `finalTitle`, `finalCta` — and throws when any is absent, so a fixture
that would render a broken page fails at decode instead.

### Content

Murror's own positioning, taken from the live site rather than invented:

| Field | Value |
|---|---|
| `brand` / `title` | Murror |
| `kicker` | THE CONNECTION PRACTICE |
| `headline` + `headlineHi` | "AI that brings people" + "closer" |
| `sub` | Most of us were never taught how to understand what we feel, or how to show up for the people we love. Murror is a daily practice for both. |
| `ctaPrimary` / `ctaSecondary` | Start free · See how it works |
| `steps` | Name what you feel · See the pattern · Reach out |
| `features` | Emotion recognition · Relationship insights · Small acts of care · Private by design |
| `finalTitle` / `finalSub` / `finalCta` | Start with one feeling · Free to start. · Open Murror |
| `footNote` | Made by MURROR |

### The accent is `#0a1430`, and the reason is contrast

`buildHTML` renders a **light** page — `--page:#efece4`, `--ink:#2b2a26` — and uses `accent` as a
*background* behind white text in three places (`.btn.p`, `.step .n`, and the whole `.final`
block, each `color:#fff`).

Murror's site yields two brand colours: midnight navy `#0a1430` (its dominant value) and a warm
starlight gold `rgba(255,236,180,.7)` ≈ `#ffecb4` (its most-repeated accent). **The gold cannot be
used here** — white text on pale gold is unreadable, and `safeHex` would happily accept it because
it validates hex *syntax*, not contrast. The navy is both the faithful choice and the legible one:
white on midnight navy, over a warm cream page, is a true rendering of Murror's cosmic palette.

`accent2 = shade(accent, by: 0.16)` darkens toward `#081028`, used for the small letterspaced
kicker/eyebrow text on cream and for the final section's button label — dark on light in both
cases, so it reads.

## 3. The board — eight runnable pets, real edges

A task is `.codepetCanDo` only when it is not `done`, not `drafted`, in an open phase, has every
`dependsOn` satisfied, and `who != .you` (`RoadmapEngine.status`). `depsSatisfied` is
`!task.dependsOn.contains { index[$0]?.done == false }`.

So for all eight to be live at once, **every runnable task may depend only on `done` tasks.** The
edges therefore come from a completed spine rather than from chains among the runnables.

```
FIND · complete
  ✓ mur-interviews   Talk to 12 people about being lonely      who .you    mkt
  ✓ mur-landscape    Scan the journaling + companion apps      who .draft  mkt
FOUNDATION · open
  ✓ mur-brand        Shape the Murror visual direction         who .draft  design
  ▸ mur-site         Build the Murror landing page      nova   · mkt      ← .site
  ▸ mur-screens      Design the first-run flow          luna   · design
  ▸ mur-pricing      Decide what free and paid mean     crash  · fin
BUILD · open
  ▸ mur-signup       Ship an email capture              byte   · eng
  ▸ mur-outreach     Find the first 20 users            nova   · sales
  ▸ mur-faq          Answer the first questions         sage   · support
SHIP · open
  ▸ mur-launch       Write the launch checklist         glitch · ops
  ▸ mur-privacy      Draft the privacy policy           glitch · legal
```

Dependencies, chosen so each of `RoadmapLayoutEngine`'s routing cases is exercised exactly once —
the same discipline `MockChat.roadmap()`'s graph was built with, and for the same reason (an empty
graph made every task an entry task and the board drew zero edges):

| Task | `dependsOn` | Routing case |
|---|---|---|
| `mur-site` | `mur-brand`, `mur-landscape` | **fan-IN** — two sources, one target; its `mur-landscape` leg is also a shared-lane straight run (`mkt` → `mkt`) |
| `mur-screens` | `mur-brand` | **in-column** (both `.foundation`) → `sideElbow`'s left-gutter hook |
| `mur-pricing` | `mur-landscape` | cross-lane run, `mkt` → `fin` |
| `mur-signup` | `mur-brand` | cross-lane run, `design` → `eng` |
| `mur-outreach` | `mur-interviews`, `mur-landscape` | second **fan-IN**, both from `.find` |
| `mur-faq` | `mur-interviews` | straight run |
| `mur-launch` | `mur-brand` | **skip-level** — `.foundation` → `.ship`, skipping BUILD |
| `mur-privacy` | `mur-interviews` | **skip-level** across two phases |

`.find` is entirely `done` → `RoadmapGating.states` marks it `.complete`. `.foundation` holds one
done task and three open → `.open`. No task sets `drafted`, so `openPhases` returns every phase
and nothing is window-blocked.

Eight runnable tasks, eight distinct department keys, six distinct pets — `nova` twice
(`mkt` + `sales`) and `glitch` twice (`ops` + `legal`), which is what `DepartmentCompanions.map`
casts.

`who` is `.draft` on every runnable except `mur-signup` and `mur-launch`, which are `.does` —
mirroring `mock-waitlist` and `mock-deploy` in Codepet's fixture, where shipping work Codepet
performs rather than drafts. What matters for §5's runnability claim is only that none of the
eight is `.you`, since `who == .you` resolves to `.needsYou` instead of `.codepetCanDo`.

### What each pet produces

Kinds are distinct across all eight, so the demo also walks eight of the twelve viewers without
any task being chosen to fill a slot:

| Task | Pet · dept | `kind` |
|---|---|---|
| `mur-site` | nova · mkt | `site` — **the website** |
| `mur-screens` | luna · design | `screens` |
| `mur-pricing` | crash · fin | `sheet` |
| `mur-signup` | byte · eng | `checklist` |
| `mur-outreach` | nova · sales | `dms` |
| `mur-faq` | sage · support | `doc` |
| `mur-launch` | glitch · ops | `plan` |
| `mur-privacy` | glitch · legal | `legal` |

`.dms` is deliberate rather than incidental: `LibraryFixtures` records it as the one viewer that
overrides the no-card-in-a-sheet rule, and it suits Murror, whose own product is built on
message prompts.

## 4. The room

Murror's room asks something the product genuinely has to answer: **should emotion detection ship
before a clinician reviews it?** Four agents, one hard blocker, ending `unresolved: true`.

| Agent | dept | stance | position |
|---|---|---|---|
| legal | `legal` | `do_not_proceed` | Naming a user's emotional state is a claim; unreviewed, it is a health claim. **hard blocker** |
| design | `design` | `proceed` | Without it the app is a blank text box, and a blank box teaches nobody anything |
| support | `support` | `proceed_with_conditions` | Ship it only behind a crisis path — someone will type the worst day of their life into this |
| eng | `eng` | `proceed_with_conditions` | The model is ready; the crisis routing is two weeks and cannot be faked |

Two conflicts (`BLOCKER` legal↔design, `TENSION` support↔design) and one negotiation round, each
turn carrying `what_would_change_my_mind` — rule 4 of the SSE contract, and the thing that teaches
disagreement is settled by evidence rather than authority.

This satisfies the two contract rules a fixture breaks most easily, per
`MockVirtualCompany.swift`: **rule 2** (never collapse positions into consensus — this room does
not resolve) and **rule 8** (no artificial delay — every frame is yielded at once).

Frames stay **wire JSON decoded by the real `VirtualCompanyEvent.from(frame:)`**. Constructing
events directly would be shorter and would also make a renamed wire key invisible; `from(frame:)`
drops an undecodable frame and logs it, so drift shows up as a missing card in a test that asserts
frame count.

## 5. Tests

Existing suites are untouched and must stay green — the `.codepet` default is what guarantees it,
so one test pins that default explicitly.

Each new test below was hand-traced against the code it exercises, and each names the edit that
turns it red. A test whose fixture cannot fail is the failure mode this list is written against.

| Test | Asserts | Goes red when |
|---|---|---|
| `defaultsToCodepet` | `DemoProject.current.id == "codepet"` with nothing set | the default flips, or a stray write reaches the store |
| `selectionIsIsolatedFromStandardDefaults` | choosing `.murror` leaves `UserDefaults.standard` with no `cp_demoProject` value | selection is read off `.standard` — the #117 regression |
| `everyRunnableDependsOnlyOnDoneTasks` | for each non-`done` Murror task, every `dependsOn` id resolves to a task with `done == true` | any dep is added on an open task, which would silently un-run a pet |
| `allEightRosterDepartmentsHaveExactlyOneRunnable` | grouping Murror's non-`done` tasks by `dept` yields all 8 `roster` keys, one each | a department is dropped, duplicated, or `product` leaks in |
| `everyRunnableIsCodepetCanDo` | `RoadmapEngine.status(for:in:) == .codepetCanDo` for all 8 | the graph, phase or `who` breaks runnability — the end-to-end claim of §3 |
| `everyRunnableResolvesToADistinctKind` | the 8 runnable titles map to 8 *different* `kind` values | two tasks collapse onto one kind, or a title stops matching its table entry |
| `sitePayloadDecodes` | Murror's `mur-site` `payloadJSON` decodes to a `DeliverablePayload` with non-nil `.site` | any of the six anchor fields is dropped |
| `siteAccentIsDarkEnoughForWhiteText` | the accent's relative luminance is below 0.4 | someone swaps in Murror's gold and makes `.btn.p` unreadable |
| `everyRoomFrameDecodes` | `frames(ask:).count == VirtualCompanyEvent`s produced | a wire key is renamed |
| `roomDoesNotResolve` | the room's terminal frame carries `unresolved: true` | the fixture is "tidied" into consensus, breaking contract rule 2 |
| `everyMurrorDeptHasAPet` | `DepartmentCompanions.companionId(for:)` is non-nil for all 8 dept keys | a task is tagged with a pet-less department such as `product` |

`siteAccentIsDarkEnoughForWhiteText` is the one test here that encodes a *judgement* rather than a
contract. It is included because `safeHex` validates syntax only, so nothing else in the codebase
would catch a legible-looking brand colour that renders white-on-pale.

## Out of scope

- **Product still has no pet.** `DepartmentCatalog.roster` filters `product` out because
  `dept-product.png` is a byte-identical copy of `dept-eng.png`, and `DepartmentCompanions.map`
  has no entry for it. No Murror task is tagged `product`, so this demo does not surface the gap
  and does not close it. It remains open and launch-blocking.
- **Live generation.** This is prototype mode: the site payload is authored here, not produced by
  a model at demo time. Driving the same Murror project against the local Claude Code path from
  #122 is a separate piece of work and needs prototype mode off.
- **Retiring `-seedLibrary`.** The all-kinds viewer harness stays as it is. Murror's eight
  deliverables cover eight of the twelve kinds; `post`, `email`, `calendar` and `text` are not
  reachable from a Murror run, so `-seedLibrary` remains the only way to audit those four.

## Verification

`xcodebuild test` cannot be trusted wholesale here — the XCTest host crashes on Xcode 26.2 when a
`@MainActor ObservableObject` deallocates, so a clean checkout exits 65 with nothing actually
failing. New suites run per-suite with `-only-testing:`, and counts come from
`xcresulttool get test-results summary` rather than from the exit code.

Screen Recording is denied for this machine, so the rendered Murror page cannot be screenshotted
from here. `SiteViewer.buildHTML` is a pure `SitePayload → String` function, so the generated HTML
can be asserted in a test and written to a file for the founder to open directly — but final
confirmation that the page *looks* right on screen is the founder's.
