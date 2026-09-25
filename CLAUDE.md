# Codepet — Project Instructions

## What is Codepet?

Codepet is a macOS app by MURROR (murror.app) where a founder runs their company with an AI team. The founder describes what they are building, and the app produces a roadmap, runs tasks that generate real deliverables, and convenes departments to argue out decisions.

**Two layers coexist in this repo, and confusing them wastes time.** The virtual-company layer is the live product: departments, roadmap, tasks, library, deliverables, the copilot chat. The older learning-game layer — 7 pixel-art characters, kingdoms, lessons, hearts and coins — is still compiled and still in the tree (`Models/GameSystems.swift`, `Models/SkillData.swift`, `Views/Home`, `Views/Skills`), and the characters are reused as companion avatars. It is not where current work happens. If a request does not say which, assume the company layer.

## Tech Stack

- **Platform:** macOS, SwiftUI. Deployment target **26.2** (not 13 — an older version of this file said 13)
- **Language:** Swift 5, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (see Landmines)
- **Auth:** Firebase Authentication — email/password, Google, anonymous. Anonymous sign-in is currently disabled in the Firebase console
- **Database:** Firestore under `companies/{uid}` for company state, `users/{uid}` for the older game progress
- **Backend:** Firebase Cloud Functions in `functions/`, TypeScript, Node 22, project `devpet-8f4b1`, region `us-central1`
- **Bundle ID:** app.murror.codepet
- **Signing:** team `YL72VTKBR7`. A build with `CODE_SIGNING_ALLOWED=NO` runs but Firebase auth will not work at runtime — sign it if you need to test anything logged in

## Project Structure

**This repo is the single source of truth.** An older version of this file said `CodePet-Clean` was — it is not, and believing it cost a full consolidation PR. See Landmines.

```
codepet/               Swift sources
├── App/               CodePetApp.swift (@main), ContentView.swift (root router), AppEnvironment.swift
├── Models/            Company state, roadmap, deliverables, chat payloads, the game layer
├── Managers/          CompanyStore (the main store), AccountDataStore, CodingRunCoordinator
├── Services/          One file per Cloud Function it calls, plus SSEParser
├── Views/
│   ├── Shell/         AppShellView — topbar, nav, the docked copilot column
│   ├── Copilot/       The chat dock: CopilotChatView, cards, exec log, agents-at-work
│   ├── Company/       The department roster and department detail
│   ├── Roadmap/  Overview/  Tasks/  Library/  Environment/  SecondBrain/
│   ├── Onboarding/    CompanyOnboardingView and the brief editor it doubles as
│   └── Home/ Skills/ Sessions/ Insights/ Learn/ Dictionary/   ← the older game layer
└── Assets.xcassets/
codepetTests/          Unit tests, one suite per concern
functions/             Cloud Functions — the ONLY deploy source for this project
docs/superpowers/      specs/ (designs + the SSE contract), plans/, and the test runbook
redesign/              A standalone HTML prototype of the OLD game product. Not shipping
```

The root router is `ContentView.swift`: it waits until `companyStore.isOnboarding` is known, then shows `OnboardingView()` or `AppShellView()`. Read it rather than trusting a flow diagram — this file has had a stale one before.

## The Virtual Company

The feature that convenes departments to argue a decision. Backend in `functions/src/company/`, client in `Views/Copilot/VirtualCompanyCards.swift` plus the fan-out in `CompanyStore.sendChat`.

- **`docs/superpowers/specs/virtual-company-sse-contract.md` is the authority.** It outranks any design or plan written later, including anything in `docs/superpowers/plans/`. It has a nine-rule `## Rendering rules the backend depends on` section that a plan's own sample code violated in five places
- Nine departments can be convened — product, finance, engineering, design, marketing, sales, support, operations, legal — capped at **four per room**, enforced in `parseRoutingToolInput`
- `chief_of_staff` routes and synthesises and is deliberately not routable. `devils_advocate` is not a department and takes no seat in the cap
- **Only PLAN mode convenes the room.** A Plan message fans out to `companyChat` and `virtualCompanyRun` in parallel, and the router's escape hatch then decides whether the founder ever sees a room; Ask and Build never fan out at all. It was unconditional until `b42bc10` (Aug 7) — measured ~$0.20 per convened decision against ~$0.005 otherwise, so a casual Ask could cost forty times what it looked like. `ChatMode.convenesRoom` is the gate, and `sendChat`'s `convenesRoom:` defaults to FALSE, which is why a test that means to convene must pass it explicitly — eight interview tests were red for a day for missing exactly that
- **Adding a department means editing the `chief_of_staff` role prompt too.** The roster lives in prose there, and the router acts on that prose, not on the enum. Two tests in `companyRegistry.test.ts` enforce this
- **The ~$0.20 figure predates the effort change.** The position and negotiation phases now run at `POSITION_EFFORT` (`medium`) instead of the API default (`high`), which cuts thinking tokens on the two phases that fan out. Nobody has re-measured since; treat $0.20 as an upper bound until someone does
- Test procedure and every measured number: `docs/superpowers/virtual-company-test-runbook.md`. Read it before re-measuring anything

### Team Build

Spec: `docs/superpowers/specs/2026-09-24-team-build-design.md`. Convenes the room to produce a
real multi-file project instead of a decision.

- Flow: Team build button → room → `planTeamWork` (`ONE_SHOT_OPS`) → one approval →
  `TeamRunCoordinator` runs department steps, ≤3 at once, each fed its direct deps' drafts →
  `ProjectAssembler` writes `docs/` and runs `claude -p` with file-only tools (`Read`, `Write`,
  `Edit`, `Glob`, `Grep`) for ≤15 min → a guaranteed `CLAUDE.md` → `git commit` → Approve files
  the project plus every department draft (`CompanyStore.approveTeamRun`)
- **File-only is enforced, not just granted.** `--allowedTools` denies nothing on its own (the
  founder's `~/.claude/settings.json` allow rules still apply under `-p`), so the build also
  passes `--disallowedTools "Bash,WebFetch,WebSearch,NotebookEdit,Task"` and
  `--permission-mode acceptEdits` (`TeamBuildPrompt`, via `CLIRunner.claudeCommand`). The
  existing Build path's command is unchanged and pinned by `CLIRunnerCommandTests`
- **The linked folder is read-only reference, in both chat and the build** (2026-09-25). Chat
  gets `--add-dir <folder>` + Read/Glob/Grep, always under `--restricted` (file tools confined
  to the run dir and that folder). The build gets `--add-dir` plus an `Edit(//<folder>/**)`
  deny — `acceptEdits` otherwise auto-accepts edits in every added dir, and only an `Edit(...)`
  rule covers all file-editing tools (`Write(...)` is reported unmatched). Both measured on
  2.1.282 against the exact generated command. The department steps still see no folder
- **The team knows the product through a `ProductDossier`** (2026-09-25). Linking a folder
  starts ONE read-only `claude -p` pass (`--restricted`, Read/Glob/Grep, ~80 s on this repo)
  that writes a product summary + up to 12 image paths, cached per account and folder under
  `~/.codepet/accounts/<uid>/dossiers/`. The text rides `ChatContext.compose(product:)` (chat,
  every department run, live lines), the room's founder profile, and the planner's company
  facts; the build prompt gets it plus a quality bar, and the images are copied into
  `public/product/`. Written by a model, not scraped, because this repo's README still
  describes the retired learning game. A Team build press waits for it. Before it existed a
  "landing page for Codepet" came out as one headline and an email box — the room had said
  "Nothing is on record about what codepet is" and chose the smallest page
- Web projects are Next.js 15 (App Router, TS, Tailwind v4, pinned versions). The build is
  file-only; the APP runs `npm install` + `npm run build` after it, gives one file-only repair
  pass on failure, and writes `BUILD-ERRORS.md` if it still fails (`ProjectAssembler.verifyBuild`)
- Projects land in `~/Codepet Projects/<slug>/`. The commit falls back to the identity
  `Codepet <team-build@codepet.local>` for whatever of user.name/user.email the Mac lacks
- Runs persist as `teamRuns` on `companies/{uid}` — **bounded**: a filed or cancelled run drops
  its drafts and at most 10 runs are kept (`TeamRun.retained`), because the array lives inside
  the company doc (1 MiB limit). It decodes per element, so one bad run cannot empty the company
- A draft's `sourceTaskId` is `team-<runId>-<stepId>`, never `team-<stepId>`: every plan
  numbers its steps s1, s2…, and the bare form resolved older runs' drafts to the newest run's
  department. The project entry is sourced to the `build` step, so it groups under Engineering
- **The build prompt lives in Swift** (`TeamBuildPrompt.swift`), on purpose — it has no cloud
  path, unlike every other prompt in this project
- `LocalOneShotRunner` now bounds every one-shot call, including `planTeamWork`, at 180 s, and
  **cancelling the calling Task terminates the process** (Stop). The shell `exec`s node, and
  the one-shot and meeting sidecars end their own `claude` children on SIGTERM
  (`installSigtermHandler` in `cliAdapter.ts`, children spawned detached and killed by process
  group) — without that, `claude` was orphaned and ran on to completion on the founder's plan
- Hidden in prototype mode — no Team build button when `PrototypeMode.isOn`

## Running on the founder's Claude plan, not the API key

The Anthropic API key was deleted from the console on 26 Aug 2026, so every Cloud Function
declaring `ANTHROPIC_API_KEY` answers 401 at runtime. **Every one of them now has a local
path** — all seventeen entries in `CloudAIBlock.blockedPaths`, company layer and learning
layer both. The Cloud Functions are still deployed and now inert: nothing in the app routes to
them any more, and a founder who has not granted their plan gets `.blocked(.notGranted)` — a
reason on screen — rather than a silent fall back to the cloud.

- **`CloudAIBlock.blockedPaths` (`codepet/Services/CloudAIBlock.swift`) is the checklist** of
  every endpoint that spends the key. Derive from it, not from memory of which features feel
  AI-ish
- **`ClaudeCodeAuthorisation` is the one switch.** Keyed per company id. It means "Codepet may
  spend my Claude plan" — not "for chat". Every transport reads it, and nothing falls back to
  the Cloud Function when the local path is unavailable: that would spend the key the grant
  exists to stop spending
- Three bundles, built by `scripts/build-sidecar.sh` into `codepet/Resources/` (gitignored) —
  `chatSidecar.js` (streaming chat with MCP tools), `oneShotSidecar.js` (the twelve ops in
  `ONE_SHOT_OPS`), `vcSidecar.js` (the department room). **Run that script after any change
  under `functions/src/`, and before archiving** — without it the routers report
  `localUnavailable` and the founder is told the runner is missing
- Adding a local op means adding it to `ONE_SHOT_OPS` **and** naming it at its Swift call site.
  A test pins the registry's key list for exactly that reason: a rename has to fail in `jest`
  rather than at run time on a founder's machine
- **Prompts are never re-implemented for the local path.** Every op imports the same builder
  the HTTP handler calls and renders the same forced tool's `input_schema`. Where a builder
  lived in a handler it was split into a `*Core.ts` — esbuild inlines the whole import graph,
  and reaching a builder through a handler shipped the Anthropic SDK, express and
  firebase-admin (measured: 7.5 MB of app resource for a prompt and a merge)
- `claude -p` cannot force a tool call, so the schema is asked for in prose and the reply
  parsed (`extractJson`). Every op validates or coerces what it got — that coercion IS the
  safety story on this transport
- Build (`startBuild`) sends a granted founder with a linked folder to `ClaudeCodeRunner`
  instead of the cloud coding agent. A grant is not a folder — but **with no folder linked,
  both Build entry points now stage `.noProject`** rather than the cloud agent, because that
  agent spends the deleted key and 401s: a card that says "Link a project" is the refusal, and
  it carries the button that fixes it
- **What the local path does not reproduce, per feature:** no server-side caches (the
  narrative cache, the dictionary term cache, prompt caching) — work the cloud would have
  served free is regenerated on the founder's quota; no blackboard write for a meeting; no
  rate limit; no kill switch; and `generatePlan` answers `tier: "full"` because there is no
  entitlement to read on the founder's own machine and the tokens are theirs
- **One state still reaches the cloud coding agent:** `startBuild` with a folder linked and no
  grant. It is not the folder gate's business — routing that founder to `ClaudeCodeRunner`
  would spend the Claude plan they were never asked about, and `ClaudeCodeAuthorisation` is the
  one switch. `BlockReason.notGranted` is the affordance it wants; the Build card cannot render
  a `BlockReason` yet. `startSessionBuild` with no folder was the other one and is now closed

## Landmines

Each of these cost real time to learn.

1. **`functions/` is the only deploy source.** A second checkout (`~/Documents/Claude/CodePet-Clean`) used to deploy to the same Firebase codebase, so a deploy from either offered to delete the other's functions. Before deploying, compare the export set against `firebase functions:list` and confirm it is a superset. Prefer `--only functions:<name>`
2. **Never name a local secrets file `.env` inside `functions/`.** `firebase deploy` loads every `.env*` as ordinary env vars, which collides with `secrets: ["ANTHROPIC_API_KEY"]` and fails the deploy with a 400. Use `functions/local.env` (gitignored)
3. **The XCTest host crashes on Xcode 26.2** when a `@MainActor ObservableObject` deallocates. ~27 tests never finish out of ~970, no test actually fails, and `xcodebuild test` exits 65 on a clean checkout. Run per-suite with `-only-testing:` and do not chase it as a regression. `CompanyStore` IS testable through its injected closures
4. **A crash that mimics that bug:** `Auth.auth()` traps rather than throwing when `FirebaseApp` is unconfigured. Rule out an unconfigured Firebase before blaming the toolchain
5. **New `.swift` files need no project-file edit.** `PBXFileSystemSynchronizedRootGroup`: target membership follows the folder on disk
6. **Debug builds put the code in `codepet.debug.dylib`,** not in the `codepet` executable. Grepping the executable for a string finds nothing, including strings that are definitely there
7. **A `#if DEBUG` type can have a DIFFERENT, still-compiling meaning in Release — and `PrototypeMode` does.** Outside DEBUG, `PrototypeMode.isLocked` is hardcoded `true` (correct for the one thing it was written for: whether the in-app toggle may be *offered*, since the mode is not switchable there). `ContentView` read that as "a launch argument is forcing the demo" and returned before `hydrate`, so **every release build ever produced sat on "Loading…" forever for a signed-in founder**. Fixed 2026-09-22 (`acceptsRealSession`); the general lesson is the landmine. Before reading any `PrototypeMode` member outside a `#if DEBUG` block, open `Models/PrototypeMode.swift` and read its `#else` branch — several members are constants there, and none of them fail to compile

## Design System
- **Background colors:** `#F5F3FA` (pale purple - splash), `#F7F5FC` (onboarding)
- **Primary dark:** `#2D2B26`
- **Accent purple:** `#7B6BD8`, `#534AB7`
- **Logo colors:** K=#2D2664 (outline), S=#1E1848 (shadow), F=#8B7BE8 (fill), L=#A89BF2 (light)
- **Pixel art:** Always use `.interpolation(.none)` and `Image.NEAREST` for scaling
- **App icon:** `codepet-official-logo.png` — C at 55% width × 63% height, white background

## Characters (7 starters)
byte, nova, crash, luna, sage, glitch, null

## Important Files
- `codepet-official-logo.png` — Final app icon (do not modify)
- `codepet-text-original.png` — Original text logo (848x221, do not modify)
- `AppIcon.appiconset/` — All macOS icon sizes generated from official logo

## Key Rules
- Never modify `codepet-official-logo.png` or `codepet-text-original.png` without explicit approval
- Always use NEAREST neighbor scaling for pixel art (never bilinear/bicubic)
- Firebase auth state changes must NOT disrupt the onboarding flow (see `isOnboarding` guard in ContentView)
- UserDefaults keys are prefixed with `cp_` (e.g., `cp_onboardingComplete`)
- Cloud sync has two destinations: company state under `companies/{uid}`, the older game progress under `users/{uid}`

## Prototype mode: two demo companies

Prototype mode runs the whole product on fixtures. **Which company those fixtures describe is a
second switch,** `DemoProject` (`codepet/Demo/`), and there are two:

```
open <path>/codepet.app --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
```

- Default is `codepet` — Codepet demoing Codepet, the content the fixtures always had. Every
  suite written against those literals depends on this default, so do not change it.
- `murror` is the second company: 11 tasks, **8 runnable at once — one per roster department**,
  and the only fixture whose run produces a `.site`, i.e. an actual rendered landing page in the
  Library's `WKWebView`. Ask for "the landing page" to see it.
- **Selection is read through `PrototypeMode.store`**, which is redirected to a scratch suite
  under XCTest. That is deliberate and load-bearing: reading `UserDefaults.standard` here would
  re-open issue #117, where the test host sharing the app's defaults domain meant a founder's
  toggle silently changed what the suite exercised.
- A launch argument outranks the stored preference (`NSArgumentDomain`), so the demo cannot be
  left half-selected between the two.
- **All eight Murror tasks are runnable only because each depends solely on `done` tasks.**
  `RoadmapEngine.depsSatisfied` blocks a task whose prerequisite is open, and the roster looks
  identical either way — `DemoProjectMurrorTests` asserts it through the engine for that reason.

### The Murror Library shows all eight departments

Nine filed artifacts (`DemoProject.filed`) across all eight roster departments. Added 5 Sep,
because `LibraryView` already groups deliverables BY DEPARTMENT and had only `mkt` and `design`
work to show — two groups, not eight — so the demo narrated "eight departments, each speaking
with its own pet" and demonstrated one.

- **The board carries BOTH halves**: nine `done` tasks with filed deliverables AND eight
  runnable ones. Those pull against each other — a task cannot be both done with work behind it
  and open to be run — so `DemoProjectEightDepartmentsTests` asserts both in one suite. **Do not
  trade one for the other.**
- New `done` fixture tasks go in **`.foundation`, never `.find`** — `.find` must stay complete or
  the board stops being the mid-flight state the fixture exists to show
- **New deliverable entries go after every specific entry and before the catch-all.**
  `deliverable(for:)` returns the FIRST keyword match, so a broad keyword early in the table
  silently steals another department's work — no error, just Sales showing Engineering's
- **There is exactly ONE `.go(.library)` walkthrough beat.** It was re-captioned, not duplicated;
  a test pins the count. The script enforces two time budgets — caption readability
  (chars/45 ÷ 1.5) and a 100s total whose comment records that a raise was twice refused. Measure
  before spending either

### A new account is greeted, once

`CompanyStore.greetIfNeeded(language:)` seeds the first-run greeting — the founder's name, the
project, the best first move, and "nothing ships without your say-so". Wired 2026-09-04; before
that it had **no caller at all** and no new founder had ever seen it.

- **It is NOT part of `hydrate`, and that is deliberate.** It was, for one commit: 34 suites call
  `hydrate` and 14 assert on `chatMessages`, so seeding a message there shifted the whole store
  suite's baseline. `hydrate` loads company DATA; starting a conversation is a separate concern.
  `ContentView` calls both in order. **Do not move it back** — two tests pin the boundary
- Gated on `CompanyState.greetedAt`, the third field of that shape after `introSeenAt` and
  `firstApprovalAt`. **Never gate it on an empty transcript** — `newChat()` empties it, so that
  condition is true again every time the founder starts a conversation
- Called after hydrate rather than at the onboarding→app edge because prototype mode boots an
  already-onboarded company and never crosses that edge — which is exactly why this message went
  unseen. `saveGreeted` is silent under prototype mode, so the demo greets every launch, and a
  test asserts the fixture stays ungreeted
- `startEnrichInterviewIfNeeded` is still uncalled. Separate decision; its comment is the record
  of why the greeting was dead

### A first draft says it is not saved yet

Until the founder's first approval, the chat draft card carries **"Not saved yet — approving
files it in your Library."** Added 2026-09-04. The rule it teaches is already stated before a
run (`BeaconOffer`: "you approve before it is filed") and confirmed after ("Added to Library");
this fills the moment in between, where the founder is looking at a finished-LOOKING deliverable
beside a button marked Approve.

- Gated on `CompanyState.firstApprovalAt`, set in `CompanyStore.fileApproval` — **the one path
  both `approveDraft` and `approveTask` call**. `ApprovalParityTests` exists because those two
  once drifted; write anything approval-related there, not in the callers
- **Never derive "has never approved" from an empty library.** It reads as a free proxy since
  approving is the only thing that files there, and it is wrong exactly where it matters: the
  demo pre-files three artifacts (`DemoProject.filed`), so a derived signal goes quiet in
  prototype mode. `FirstApprovalNoteTests` pins this
- The decision is `DraftCardCopy.shouldShowNotFiledNote(hasApproved:draftApproved:)`, a pure
  static — same reasoning as `DraftPayloadPreview.hasStructuredPreview`
- **Adding any new saver to `fileApproval` breaks every test suite that approves without
  injecting it.** The real savers call `Firestore.firestore()`, which TRAPS rather than throwing
  under an unconfigured `FirebaseApp`, so the test host dies and the log reads "Restarting after
  unexpected exit" — which looks like an assertion failure and is not. Four suites had to be
  updated when this landed. If you add one, sweep the neighbours in the same change

### Departments that build on each other

A run now carries the finished work of its `dependsOn` tasks — capped at 3 items × 1500
characters, in `dependsOn` order — and the draft card credits them ("Built on Luna's brand
direction"). Added 2026-09-03.

- **`UpstreamWork` (`Services/RunTaskClient.swift`) is the one type**, and its field names are
  camelCase on purpose: the TypeScript `UpstreamWork` in `runTaskCore.ts` reads them by name.
  Adding a field means editing both, plus `RunTaskRequest.CodingKeys` — that enum renames every
  field for the wire, and a stored property missing from it is silently never encoded
- **`parseUpstream` is the only narrowing**, shared by `handleRunTask` and the `runTask` entry
  in `ONE_SHOT_OPS`. It re-enforces the caps rather than trusting the client's
- **The card's credit is read off the request that was sent**, not re-derived. `message.upstream`
  is set from `RunTaskRequest.upstream` in `produceDraftInline`, so the credit and the prompt
  cannot disagree
- **Chained runs do not stop for approval** (founder decision). `runChained` runs the missing
  dependency, feeds its DRAFT forward with `unapproved: true`, and the card says
  `(unapproved draft)`. The upstream draft is never filed to the library — it was not approved —
  which is why `UpstreamWork.fromDraft` exists alongside `assemble`
- **A runnable task whose dependency produced nothing offers `[Run both]` / `[Just mine]`**
  rather than guessing (`ChainOffer`). On a fresh Murror company that is 8 of 8 runnable tasks,
  because `mur-brand` and `mur-landscape` are `done` with no deliverables behind them — so the
  offer is currently the demo's first screen for every department. To make the demo lead with
  the credit instead, give those two prerequisite tasks real deliverables in the fixture
- `RoadmapGating.awaitsApproval` is untouched: chaining never opens a phase

### The day-one simulation (`DemoProject.murrorDayOne`)

Day one and mid-flight are ONE task list. Four things break the bridge between them:

1. **Do not give day one its own task array.** It is `murrorTasks` with nine `done` flags
   cleared. Two arrays drift, and `DayOneBridgeTests` is what notices.
2. **Do not remove an existing `dependsOn` id when adding a chain edge.** `mur-brand` keeps its
   `mur-landscape` edge AND gains `mur-notfor`. Replacing rewrites mid-flight's roadmap.
3. **Keep `DemoProject.dayOneChain` equal to `DemoProject.murror.filed`.** The bridge claim is
   that running the nine lands on mid-flight; different sets make it false.
4. **A new `who: .you` task needs a `.recordFounderTask` beat if anything depends on it.**
   `toggleTaskDone` files nothing, so a founder-only task completed any other way leaves the
   dependency arrow pointing at nothing and every downstream credit line empty.

---

# Daily Summary Format

When summarizing work at the end of a session, use this format:

**Codepet macOS app**
- [bullet points of work done]

**Codepet macOS app — App Store**
- [bullet points or "No work today"]

**Codepet macOS app — TestFlight**
- [bullet points or "No work today"]

**Codepet macOS app — GitHub**
- [bullet points or "No work today"]

**Codepet multi agent**
- [bullet points or "No work today"]

---

# Where things stand

This section is the one most likely to go stale. Treat it as a pointer, not a fact — check git and the docs before relying on it.

- Work happens on `main` via PRs. There is no long-lived feature branch
- The Virtual Company shipped and is deployed; its remaining items are product decisions, listed at the end of `docs/superpowers/specs/2026-08-03-virtual-company-in-chat-design.md`
- Known and deliberately unfixed: five brief fields (`goal`, `traction`, `problem`, `runway`, `constraints`) are collected by interviews and displayed nowhere; `detectConflicts` reports a false `BLOCKER` when two departments block the same way; `dept-product` has placeholder art so Product is kept off the roster
- The older game layer (kingdoms, lessons, hearts, coins) is compiled but not being developed
- Every model call runs on the founder's own Claude Code when they grant it — see the section
  above. Nothing is left that only the API key can answer

## Shipping the app from the website

**Codepet ships. `v1.0-build2`, published 2026-09-22 — the first public release this
project has ever had**, and the end of a long stretch where this section described a
pipeline nobody could run. Verified after publishing, not before:

```
releases/latest/download/Codepet.dmg   200   (404 for as long as it had existed)
code-pet.com/download/Codepet.dmg      200
sha256 of the downloaded file          identical to the locally verified build
spctl -a -t open on it                 accepted / source=Notarized Developer ID
```

- **`gh release list` is not empty, and was not empty before this either.** An earlier
  version of this section said it was, and that claim was repeated twice in one day without
  anyone running the command. `v1.0-build2-internal` (17 Sep) is a **pre-release** carrying
  `Codepet-internal.dmg`; the download page 404ed anyway, because GitHub resolves `latest`
  PAST pre-releases and the asset name has to match exactly. Two different reasons for the
  same 404, and only one of them was written down
- **That internal pre-release carries the landmine 7 deadlock.** It is a `Release` build from
  17 Sep, so any tester who signed in and relaunched has been stuck on "Loading…" since. It
  wants re-cutting from `main`
- `./scripts/preflight-release.sh` passes all three credentials on this machine

- **The Developer ID Application certificate landed 2026-09-22.** It came by the CSR route,
  NOT the `.p12` route `docs/developer-id-request.md` originally asked for: the private key
  was generated on this Mac and has never left it, the Account Holder signed the
  `.certSigningRequest` and sent back a `.cer`. The Account Holder limit is about who clicks
  *Create*; whose key it is was never the constraint, and the CSR flow is the portal's own
  ("Choose File… select the certificate request file"). Issuer **OU=G2**,
  valid to **2031-09-17**, serial `6A3F310C8D1F25E123D309F78F8AF176`. Verified by
  `security find-identity -v -p codesigning`, which lists exactly one Developer ID
  Application line — proof the cert pairs with the local private key, which `security import`
  reporting success does NOT prove
- **Creating a cert asks which intermediate to chain to, and DEFAULTS to the wrong one.**
  *Previous Sub-CA* expires 2027-02-01; *G2* runs to 2031-09-16. "Previous" reads as the
  conservative choice and is the trap — accepting the default yields a cert with a few months
  of life. Whoever creates the next one has to switch it by hand
- **A Developer ID cert cannot be self-revoked.** Apple's console does not offer it; it takes
  an email to `product-security@apple.com` and an unknown wait. Two consequences: the 5-cert
  cap is effectively permanent, so **never create one to test the flow**; and a revocation,
  once granted, stops already-installed copies from launching. That is revoke, not expiry —
  an app signed while the cert was valid keeps running forever after the cert expires
- **Still owed: a `.p12` backup in the company password vault.** The key exists on exactly one
  Mac and no slot can be reclaimed, so a dead disk costs the company 1 of its 5 certs
  permanently. This is the CSR route's one weakness and the `.p12` route's accidental strength
- **Notarization is a separate credential and never touches the signing key.** Stored as
  keychain profile `codepet-notary`, currently from an app-specific password on an individual
  Apple ID. An App Store Connect API key (`--key` / `--key-id` / `--issuer`) is the better
  long-term form because it is not tied to one person's Apple ID — switch by re-running
  `notarytool store-credentials` under the same profile name
- **The Mac App Store is not the escape hatch.** The account already holds the App Store
  cert pair, and it is unusable here: the App Store requires App Sandbox, while the app sets
  `ENABLE_APP_SANDBOX = NO` and spawns `/bin/sh`, `node` and `claude` as its core loop.
  Sandboxing it turns off every AI feature. Developer ID is the only route
- **An unsigned build is not a stopgap either.** `codepet/codepet.entitlements` declares
  `keychain-access-groups` under `$(AppIdentifierPrefix)`, which only resolves for a
  team-signed binary — so an ad-hoc build cannot reach its keychain group and Firebase auth
  fails at runtime (landmine 4's neighbour). The founder would download an app and get stuck
  on the sign-in screen. Since macOS 15 the right-click ▸ Open bypass is gone too
- `./scripts/preflight-release.sh` checks both credentials in a second and refuses to start,
  because `package-macos.sh` otherwise archives for minutes before `-exportArchive` reports
  the missing certificate
- The whole thing is two commands — `package-macos.sh` then `release-github.sh`. Neither
  website needs a deploy: both buttons point at the `latest` permalink, which means
  `release-github.sh` **publishes publicly** and the download page goes live the moment it
  runs
- **The live download page is `code-pet.com/download`, not `murror.app`.** It is served from
  `Murror/devpet-landing`'s `main` and already carries the `/download/Codepet.dmg` → GitHub
  307 (`1e37a2b`). `murror.app` answers `/` but 404s `/download`, `/v2` and `/academy`, so it
  is a different deployment
- **Verified 17 Sep:** a `-configuration Release` archive carries all three sidecars. The
  only build ever checked before was Debug

### What the first real run of the pipeline found

The pipeline was written long before there was a certificate to run it with, so 2026-09-22 was
the first time it ever executed. It failed four times, in four different ways, **none of them
the certificate**. All four are fixed; they are recorded because each one passed every check
that existed at the time.

1. **`signingStyle: automatic` can never work on this account.** It does not read the
   provisioning profiles on disk at all — it only mints one through cloud signing, which
   answers `403 FORBIDDEN_ERROR` here ("You haven't been given access to cloud-managed
   distribution certificates") *even though that permission is ticked in App Store Connect*.
   The explanation appears only in `IDEDistribution.verbose.log`, never in the terminal:
   `Automatic signing is disabled and unable to generate a profile`. `ExportOptions.plist` now
   uses `manual` with an explicit profile name. **Do not change it back**
2. **A Developer ID build of this app REQUIRES a provisioning profile**, because it declares
   `keychain-access-groups`. The certificate alone is not enough. A copy lives at
   `scripts/Codepet_Developer_ID.provisionprofile` — not a secret, it holds the public cert,
   the team id and the entitlements. **Double-clicking a `.provisionprofile` does NOT install
   it where `xcodebuild` looks**; on macOS it goes to System Settings ▸ Device Management, so
   it reads as installed while every build keeps failing. `cp` it into
   `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`
3. **`ENABLE_HARDENED_RUNTIME` had never been set**, in either configuration, while the export
   step's comment claimed the build was "notarization-ready". Notarization rejects a build
   without it
4. **The `.dmg` was never signed, and nothing could tell.** A disk image is a separate code
   object and neither `hdiutil` nor `create-dmg` signs it. `notarytool` still answered
   `Accepted` and `stapler` still answered `worked`, while `spctl -a -t open` answered
   `rejected — source=no usable signature`. The script exited 0 and printed `✅ Done` for a
   file every user's Mac would refuse. Signing must happen BEFORE notarization; re-signing a
   stapled image invalidates the ticket

Two habits came out of it, and they generalise past this script:

- **`|| true` on a verification deletes the verification.** `spctl` was the only check that
  caught (4), and its exit code was being swallowed, so the build stayed green. It gates now
- **Do not let a build write to a tracked file.** Step 3 ran `PlistBuddy` against
  `scripts/ExportOptions.plist` itself, and PlistBuddy rewrites what it is handed — canonical
  XML, sorted keys, **every comment deleted**. The comments explaining why that plist uses
  manual signing were destroyed by the next build before they were ever committed. It copies
  to `build/` first now

**`./scripts/package-internal.sh` is still the fast internal route**, and was the ONLY route
before 2026-09-22. It builds an Apple-Development-signed, development-provisioned `.dmg` that
runs on the Macs registered to the team — 4 of them as of 17 Sep, and the profile now runs to
2027-09-17. It skips notarization, so it stays the quicker way to hand a build to a registered
teammate; anyone outside the team needs the Developer ID route above.

- It works where an unsigned build does not for one reason: the profile grants
  `YL72VTKBR7.*`, so the `keychain-access-groups` entitlement resolves and Firebase auth
  works. Ad-hoc signing is what breaks sign-in, not the lack of notarization
- **Adding a tester does NOT need the Account Holder.** An Admin registers the Mac's
  Provisioning UDID at developer.apple.com ▸ Devices, then re-runs the script;
  `-allowProvisioningUpdates` bakes the new device in
- Anything arriving by download, AirDrop or chat is quarantined, and a dev-signed app is not
  notarized, so `spctl` rejects it — measured. The tester runs
  `xattr -dr com.apple.quarantine` once. A README inside the `.dmg` says so, because
  "damaged or incomplete" reads as a broken download rather than an unregistered Mac
- Verified end to end 17 Sep: exported, launched from the exported path, stayed up, quit
  cleanly, and the `.dmg` re-verified after mounting
- **That verification was signed OUT, and it mattered.** This script builds `Release` too, so
  every internal `.dmg` handed to a tester carried the splash deadlock in landmine 7 below —
  a tester who signed in and relaunched sat on "Loading…" forever. Signed out, a release build
  renders `ReturningSignInView` and looks perfectly healthy, which is exactly what "launched,
  stayed up" recorded. **Launching a release build is not a check until someone signs in**

# Working agreements

- **Verify, do not infer.** Several expensive detours here came from reading fallback code and concluding a Cloud Function was undeployed. `curl` the endpoint (401 means alive, 404 means absent) and read `firebase functions:log`
- **Do not commit to `main` directly** unless asked. Branch, PR, and say what you verified
- Commit messages carry the reasoning — the why, the measurement, the rejected alternative. They are the only durable record once scratch files are gone
- When a guard exists, there should be a test that goes red if the guard is deleted. If a test passes with and without the code it protects, it is not protecting anything
