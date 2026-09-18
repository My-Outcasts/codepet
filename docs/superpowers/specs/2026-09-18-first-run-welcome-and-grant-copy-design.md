# The first five minutes: a welcome that orients, and grant copy that is true

Two changes to what a founder meets immediately after onboarding. They are separate features
with separate risk, recorded together because they collide on one question — **when is the
founder asked to spend her plan** — and answering it twice, differently, is how the product
ends up contradicting itself on two screens.

## The finding

### 1. The greeting names the project but never describes it

`FirstRunGreetingGate` → `CompanyStore.seedFirstRunGreeting` → `FirstRunGreetingBuilder` ships
today and is covered by `FirstRunGreetingWiringTests`. It produces two sentences:

> {Name}, your company for {Project} is ready. The best first move is "{task}". Want me to do it
> with you, right here?

It *names* the project. It never says what Codepet understood about it, and nothing anywhere
explains what the app's surfaces are for.

### 2. A briefing that already exists, on a screen first-run founders never open

`OverviewIntroSheet` holds exactly the missing content — `brief.summary`, a phase read, and a
"How to read this map" explainer, auto-shown once per account. It is presented from
`RoadmapView.swift:94`. **A founder who lands on home and stays in chat never sees it.**

### 3. The Settings grant copy describes a route that was deleted

`ClaudeCodePanel.grantDescription` says:

> Turn it off and Codepet goes back to the old route.

There is no old route. `ChatTransportRouter` and `LocalTransportRouter` both record it:

> *"There is deliberately no hosted case: Codepet holds no Anthropic key, so 'fall back to the
> Cloud Function' is not a slower success, it is a 401 the founder cannot act on."*

The key was deleted 26 Aug 2026 (`a0575ad`, `e1c5792`). `2026-09-15-claude-code-only-design.md`
reaches the same finding from production logs. **That toggle is not a preference. It is the
product's on/off switch**, and the copy tells the founder the opposite.

This inverts the question that prompted this spec ("is stating the cost so plainly putting
founders off?"). The copy is not too forthcoming. It is **inaccurate in the direction that costs
activation**: it reads as an optional extra with a safe fallback, so a founder declines it and
lands in an app where nothing works and nothing says why.

### 4. The Codex row claims surfaces Codex has never run

The Codex description lists "Chat … the department room". `BlockedOffer.Surface` is explicit that
chat streaming and the virtual company meeting are `.claudeOnly`, and `ChatTransportRouter`
answers `.claudeCode` unconditionally. Those two surfaces have never run on Codex.

### 5. `brief.summary` is empty at the moment the greeting is built

Onboarding's enrich step runs on the founder's own Claude, which she has not granted yet —
consent is asked at first use, and onboarding comes first. The call throws `.blocked(.notGranted)`
and `CompanyStore:807` fails open (full chain in A1). Nothing errors on screen and the field is
simply never written.

This matters beyond the greeting: the summary paragraph of `OverviewIntroSheet` — the briefing
finding (2) is about — is **also blank** on first run, so the one screen that explains the product
currently opens without its opening paragraph. Neither surface says so, because both omit the
paragraph rather than render it empty.

### 6. Onboarding promises a choice that does not exist

`OnboardingProviderStep.swift:61` — "Install either one; **you'll choose whether to use it
later**." Without a grant, nothing runs. There is no choice, only a delay.

## What was decided

| Question | Decision |
| --- | --- |
| Where does the welcome's project read come from? | **Founder-typed brief fields**, composed locally, with `brief.summary` preferred when present. No model call. |
| How does the feature tour reach the founder? | **Chat-native and on demand** — offered by a chip, never pushed. |
| Does the tour call a model? | **No.** A pure builder, for the same reason the greeting is one. |
| Is the Claude toggle still revocable? | **Yes** — with a confirm on turn-off. |
| When is consent asked for? | **At first use**, unchanged. This spec does not move it. |

### On the conflict with `2026-09-15-claude-code-only-design.md`

That spec decided "a hard gate in onboarding — nothing AI-shaped is reachable until Claude Code
is detected **and granted**". The shipped `OnboardingProviderStep` does not do this: it gates on
installation and defers consent, matching `2026-09-16-provider-choice-ui-design.md`
("onboarding detects installation only; it never asks to spend anything").

**Shipped code and the later spec agree, so the hard gate is treated as superseded.** This spec
does not re-open it. Everything below is compatible with consent-at-first-use.

---

## Part A: the welcome

### A1. The greeting composes from the brief, locally

`FirstRunGreetingBuilder.build` gains two paragraphs between the existing lead and the existing
call to action:

| Paragraph | Source | Status |
| --- | --- | --- |
| Lead — "{Name}, your company for {Project} is ready." | `brief.founderName`, `brief.projectName` | ships today |
| **The read** — what Codepet understood | founder-typed brief fields; `brief.summary` preferred when present | new |
| **The shape** — task and phase counts | pure function over `[RoadmapTask]` | new |
| The move — "The best first move is …" | `RoadmapEngine.nextStep` | ships today |

**The read cannot be built on `brief.summary` alone.** An earlier draft of this spec did exactly
that, on the grounds that onboarding's enrich step writes it. It does not, for anyone onboarding
today:

- `CompanyStore.swift:385` enriches via `ReflectionAPIClient().enrichBrief`
- that calls `localOneShot(op: "enrichBrief", …)` (`ReflectionAPIClient.swift:1098`), which runs
  on the founder's own Claude — **and which never returns nil**: it either returns a decoded
  response or throws `ReflectionAPIError.blocked` (`:727-752`). The cloud `POST` written below it
  is unreachable, and would be refused by `CloudAIBlock.blockedPaths` anyway, which lists
  `enrichBrief` (`CloudAIBlock.swift:35`)
- a founder in onboarding has **not granted yet** — consent is asked at first use — so
  `LocalTransportRouter.forOneShot()` answers `.blocked(.notGranted)` and the call throws
- `CompanyStore.swift:807` is `(try? await enricher(brief)) ?? brief` — **fail-open**, so the
  throw is swallowed and the unenriched brief is saved

So `brief.summary` is nil for every founder at the moment the greeting is built, because
onboarding necessarily precedes the grant. It is not nil forever: `CompanyOnboardingView` doubles
as the brief editor, so a founder who returns and edits their brief **after** granting does get an
enriched summary. That is exactly why the read prefers `summary` when present rather than ignoring
it.

The tests that appear to prove enrichment works
(`CompanyStoreOnboardingTests.swift:98,120`) inject a stub enricher and assert on the stub.

*(An earlier revision of this spec blamed the deleted `ANTHROPIC_API_KEY`. That is the wrong
mechanism — `enrichBrief` has a local path, per CLAUDE.md's "every one of them now has a local
path". The conclusion is unchanged; the reason is the missing grant, not the dead key.)*

The read is therefore composed from what the **founder typed**. `CompanyOnboardingModel.brief`
(`:26-28`) shows exactly which fields that is, and it is the only list this spec may draw on:

| Field | Availability |
| --- | --- |
| `projectName`, `oneLiner`, `audience`, `role`, `founderName` | typed in onboarding; may be blank |
| `stage` | **always non-nil** — `stages[stageIndex]`, defaulting to "Building" |
| `summary`, `categories` | enrich-only, so nil on first run (above) |
| `goal`, `traction`, `problem`, `runway`, `constraints` | **never populated** — see below |

**`goal` is not available and must not be used.** It is written at exactly two places:
`CompanyStore.swift:694`, the enrich-interview answer handler, and the Murror demo fixture.
That interview is started by `startEnrichInterviewIfNeeded` (`CompanyStore.swift:660`), which
**has no caller in the app** — only `VirtualCompanyInterviewTests:370`. CLAUDE.md records the
same fact from the other direction ("five brief fields … are collected by interviews and
displayed nowhere"). A read paragraph built on `goal` would be blank for every real founder and
correct only in the demo, which is the worst possible place for it to look right.

So the read is `oneLiner` (the anchor), `audience`, and `stage`. `brief.summary` is used in
preference when non-nil — a founder who edits her brief after granting — so the welcome still
cannot contradict `RoadmapView` and `OverviewIntroSheet`, which render the same field.

**`stage` alone is not a read.** It is the one field that is always present, so a naive
composition would emit "Codepet is at Building stage." for a founder who typed nothing else —
a sentence that tells her only what she picked from a slider. The paragraph therefore requires
`oneLiner` **or** `summary` to render at all; `audience` and `stage` are trimmings on that
anchor, never the whole sentence.

Every read of an optional brief field goes through **`MeaningfulText.clean`**, not a bare `??`.
That helper rejects placeholder-y values (under two characters, all digits, an email address) and
is already the convention for this exact field at `RoadmapView.swift:62`. A bare `??` would let a
founder who typed `x` into the one-liner see "Here's what I understood: x".

**Why local, not a model call.** Chat is `.claudeOnly` and blocked without a grant. A
model-written welcome on a fresh account is either blocked on arrival or forces the permission
ask to the front of onboarding — the trade `OnboardingProviderStep` exists to avoid.

### A2. Every field is optional, so every omission is a case

`CompanyBrief` has sixteen optional fields. The builder must degrade, and each path gets a test
that is **hand-traced and watched to fail before it passes**:

- no `founderName` → lead drops the name, keeps the sentence
- no `oneLiner` **and** no `summary` → the read paragraph is omitted entirely, even though
  `stage` is non-nil, per the anchor rule in A1. Never rendered as a bare "Here's what I
  understood:" with nothing after it, and never as a bare stage label
- `summary` nil but `oneLiner` present (**the default case today** — see A1) → the read composes
  from typed fields and reads as a sentence, not a field dump
- `summary` present → it wins over the composed version; the two never both render
- a field that is placeholder-y rather than absent (`oneLiner` = "x", `stage` = "1") → dropped by
  `MeaningfulText.clean`, indistinguishable from absent
- no tasks → `shouldGreet` is already false; nothing is seeded
- one task in one phase → the shape line must not read "1 tasks across 1 phases"

### A3. The tour is a script, not a call

Tapping **Show me around** appends one locally-composed message naming the surfaces in byte's
voice, carrying a `navChip` to Roadmap (`NavAction(destination: "roadmap")`).

The surfaces named are the ones `AppView.from(navDestination:)` can actually reach — **roadmap,
tasks, library, and the company/department room** — plus chat, which is where the founder already
is. `environment` is omitted: it is tooling, not part of understanding what Codepet does for you.
Naming a destination the router cannot resolve would render a chip that silently does nothing
(`activateNav` returns early on an unknown destination).

That chip does double duty: landing on Roadmap fires the existing `OverviewIntroSheet` (gated by
`showMapIntro` / `markIntroSeen`, once per account), which already holds "How to read this map".
The tour hands off to shipped work rather than duplicating it, and finding (2) — a briefing that
never fires for chat-first founders — is closed as a consequence rather than as separate work.

**The sheet arrives one paragraph short**, per finding (5): its summary line reads
`brief.summary`, which is nil today. This spec does not fix that — the greeting's own read is
composed locally and is unaffected — but the handoff is to a slightly thinner screen than the
code suggests. Pointing `OverviewIntroSheet` at the same composed read is the obvious follow-up
and is deliberately left out of scope, because it changes a screen this spec is otherwise only
navigating to.

No stepper, no coachmarks, no per-surface state.

### A4. Two render details that are not cosmetic

**Ordering.** `inlineActions` is composed *inside* `textBubble` (`CopilotChatView.swift:2402`),
and the `firstRunAction` branch (`:1561`) renders `textBubble` then `actionButton`. A message
carrying both payloads therefore draws the tour chip **above** the primary button. The primary
action leads; the tour chip follows.

**Its own consumed flag.** `actionConsumed` is already shared by `firstRunAction`,
`runProposal`, `chainOffer` and `vcRun`. Reusing it would make "Do it with me" retire the tour
chip and the reverse. The tour carries its own flag.

### A5. Gating is unchanged

`FirstRunGreetingGate.shouldGreet(hasBeenGreeted:transcriptIsEmpty:hasTasks:)` is not touched.
The tour chip rides the greeting only.

---

## Part B: the grant copy

### B1. Claude — say what off actually does

> **Let Codepet use your Claude Code plan**
>
> Everything runs on your own Claude plan, on your Mac — chat, your roadmap, tasks, briefs,
> decisions, the department room, and Build once a folder is linked. Each turn spends your
> Claude quota.
>
> Codepet needs this to work. Turn it off and it stops until you turn it back on. Your
> terminal's Claude Code is unaffected.

Order is benefit → scope → cost → honest off-state. `"Codepet never sees or stores your token.
Claude Code keeps it in your Mac's Keychain"` is unchanged — it is the line doing the trust work.

Leading with "Everything runs on your own Claude plan" also retires the maintenance burden the
current comment describes ("every feature moved onto this path gets added to this line"): the
list becomes an example, not an inventory that must stay exhaustive.

**Two claims deliberately not made**, because neither is verifiable on `main` today: anything
about Codepet credits (`2026-09-15` removes them, and what a subscription buys is that spec's
question, not this one), and any privacy claim stronger than "on your Mac".

### B2. Codex — a different scope and a different off-state

The rows are not symmetric and must stop being written as if they were.

|  | Claude off | Codex off |
| --- | --- | --- |
| Chat, department room | **stop** — nothing else runs them | unaffected; never ran on Codex |
| Build, tasks, briefs, decisions | stop | fall back to Claude when granted |

So the Codex description drops chat and the department room, and its off-line says what is true
for Codex: the one-shot work goes back to Claude when Claude is granted, and stops when it is not.

### B3. The turn-off confirm

Switching **Claude** off asks once:

> **Turn off Claude plan access?**
> Codepet stops working until you turn this back on — chat, roadmap, tasks, briefs, decisions
> and Build. Your terminal's Claude Code is unaffected either way.
> `[Cancel]` `[Turn off]`

Revocation stays fully possible — consent that cannot be withdrawn is not consent. The confirm
exists so it cannot happen *by accident*, which is the live risk while the copy promises a
fallback.

**Claude only.** Codex off is not a kill switch, and a confirm there would be ceremony for a
consequence that does not occur. `grantRow` is shared, so the confirm is conditioned on the
provider rather than attached to the row.

### B4. Onboarding, same sentence

`OnboardingProviderStep` — "you'll choose whether to use it later" becomes a statement of what
happens rather than a promise of optionality: Codepet runs on the plan, and it will ask before
spending it the first time.

---

## Testing

Pure builders, tested directly with no store and no SwiftUI — the pattern `ProvenanceRow`,
`ProviderGrantRow`, `BlockedOffer` and `OnboardingProviderStep` all follow, and the reason is
landmine 3 in CLAUDE.md (the XCTest host crash on `@MainActor ObservableObject` deallocation).

| Unit | Asserts |
| --- | --- |
| `FirstRunGreetingBuilder` | each A2 degradation path; `summary` wins when present; composed read when it is nil; anchor rule (stage alone renders nothing); `MeaningfulText.clean` drops "x" and "1"; singular/plural |
| brief-field availability | a guard test that fails if `goal` is ever read by the builder — it is nil for every real founder and non-nil only in the Murror fixture |
| tour script builder | names every surface; is reachable with no grant |
| `grantDescription` | Codex copy names no `.claudeOnly` surface; neither row says "old route" |
| turn-off confirm | fires for Claude, not for Codex; Cancel leaves the grant intact |

The copy assertions are the point, not decoration: findings (3) and (4) are both **copy that
drifted from behaviour**, and only a test that reads the string keeps them from drifting back.

## Out of scope

- Moving when consent is asked (settled by `2026-09-16`).
- What a subscription buys with no inference cost (`2026-09-15`).
- A paused-state banner on home. Considered; it adds an app-wide state for a case the confirm
  in B3 mostly prevents. Revisit if founders still arrive at a blocked app.
- Per-surface progressive tour reveals.
- **Repairing or removing the dead `enrichBrief` path** (finding 5). It is a hosted AI function
  and therefore belongs to `2026-09-15-claude-code-only-design.md`'s deletion sweep, not here.
  This spec only stops depending on it.
- **Pointing `OverviewIntroSheet` at the composed read** so its blank paragraph fills too. Worth
  doing, and small once the builder exists — but it edits a screen this spec otherwise only
  navigates to.
