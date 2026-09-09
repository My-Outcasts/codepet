# Environment Honesty Pass — Design

Date: 2026-09-09
Status: approved, ready for an implementation plan
Branch: `docs/environment-honesty-pass`

## Goal

Make the Environment tab incapable of claiming an unbuilt toolkit item is on.

This is deliberately **not** a pass that builds capability. It is the pass that
stops the tab lying, so that anything built afterwards is built on truth.

## The problem, measured

Of the 13 items in `Toolkit.catalog`, **three do something**:

| Category | Item | Real? | Where the truth lives |
|---|---|---|---|
| Skills | `web-research` | yes | `companyChatCore.ts:1176` adds `WEB_SEARCH_TOOL` |
| Skills | `prd-writer` | yes | `buildSkillsBlock` injects a prompt block |
| Skills | `code-review`, `changelog` | **no** | `IMPLEMENTED_SKILLS = ["web-research","prd-writer"]`; `parseEnabledSkills` drops the rest |
| Connectors | `github` | yes | OAuth → sealed token → `mcp_servers` + `mcp_toolset` |
| Connectors | `notion`, `figma`, `slack`, `linear` | **no** | `ConnectorProvider` has one case: `.github` |
| Agents | `code-reviewer`, `explorer`, `test-writer`, `migrator` | **no** | zero references outside the catalog and tests |

Two consequences are worse than "ten items are unbuilt":

1. **The toggle confirms a fiction.** Flipping `code-review` writes to
   `enabledTools`, the row renders "Active", and the Cloud Function silently
   drops the id. `explorer` ships `defaultOn: true`, so *every* company
   starts with a fake agent enabled.
2. **The companion sells it.** `companyChatCore.ts:307` lets `setup_capability`
   proactively offer any currently-off item — including all four agents. The pet
   can talk a founder into enabling something that does not exist.

A third, found while auditing: `EnvironmentView:21` `needsYouCount` counts
recommended-but-off *connectors*, and `notion` is recommended with no provider
case. The header tells founders an account is waiting to be connected that
cannot be connected.

And **three of the five** recommendation cards (`code-review`, `notion`,
`test-writer`) pitch a benefit the founder cannot get.

## Decisions

### 1. Honesty before capability

Ship this pass first; then pick **one** subsystem to build for real. Skills,
connectors, and agents are three independent subsystems (a backend deploy, four
OAuth registrations, and a mechanism that does not exist yet respectively) and
each needs its own spec → plan → implementation cycle.

### 2. `isBuilt` is a pure function; three honest authorities behind it

```swift
extension ToolItem {
    func isBuilt(builtSkills: Set<String>) -> Bool {
        switch category {
        case .skills:     return builtSkills.contains(id)
        case .connectors: return ConnectorProvider(rawValue: id) != nil
        case .agents:     return false        // no mechanism exists yet
        }
    }
}
```

- **Connectors** — `ConnectorProvider(rawValue:)` already *is* the authority: the
  enum is the OAuth implementation, so truth sits beside the code providing it.
  Adding `case notion` flips that row with no other change.
- **Agents** — `false` until a mechanism exists. This is the single line that
  changes when local Claude Code subagents land.
- **Skills** — the only category needing transport, because `Toolkit.swift:113`
  records an intent worth preserving: *"the CF is the authority on that (see
  `IMPLEMENTED_SKILLS`), so shipping a skill is a backend deploy, not a client
  release."*

A pure function, not a `Capabilities.shared` singleton. Two reasons: hidden
global state makes every gate untestable, and landmine 3 (the XCTest host on
Xcode 26.2 crashes when a `@MainActor ObservableObject` deallocates) makes a new
observable service type actively hostile to tests. Passing a `Set<String>` costs
nothing and every gate becomes a one-line assertion.

### 3. Skills manifest: an `onRequest` endpoint returning `IMPLEMENTED_SKILLS`

A new small `capabilities` endpoint exports `IMPLEMENTED_SKILLS` directly.
`onRequest`, not `onCall` — every one of the 27 functions in `index.ts` is
`onRequest` and this repo has no `onCall` at all.

It needs **no authentication**: the payload is a static constant naming which
skills the backend implements, with no founder data in it. That is deliberate,
not an oversight — an unauthenticated read means the Environment tab can resolve
its state on first paint without waiting on a token round-trip.

`CompanyStore.builtSkills` holds the live set, fetched beside the existing
`refreshConnectorStatus()` that `EnvironmentView` already calls in `.task`, and
falls back to a bundled `["web-research", "prd-writer"]` when offline or on
first paint.

**Rejected: a Firestore `config/capabilities` doc.** It needs no new endpoint and
matches how `loadConnectorStatus` already reads, but it must be hand-synced with
`IMPLEMENTED_SKILLS` and can therefore *disagree* with the array that actually
gates behaviour. That reintroduces the exact bug class this pass exists to kill.
Exporting the constant itself cannot drift.

### 4. Unbuilt rows: visible, labelled, not toggleable

The row keeps its place with its real state named. **"Not built yet" replaces the
toggle entirely** — no control to press, no on-state to fake.

```
BROWSE ALL / Agents

  Cr  Code Reviewer
      A subagent that audits changes     Not built yet
      for correctness.
  ------------------------------------------------
  Ex  Explorer
      Searches the codebase to answer    Not built yet
      questions fast.
```

Rejected: **hiding** unbuilt items. That is the suppression pattern that already
cost us once — a suppression needing two conditions in sync killed the first
message of every conversation. Rendering the real state needs no condition to
stay in sync, and the catalog keeps its roadmap-of-capability value.

Also rejected: a toggleable row with a warning. A persisted on-state that does
nothing is a softer version of the same lie.

### 5. Recommendations show only what can be acted on

`Toolkit.recommended` filters to built items. The other three stay visible in
Browse all, labelled.

The line is drawn at **intent**: a catalog may honestly show the future; a pitch
headed "Recommended for your project" may only offer what exists. The grid
shrinks from five cards to two until more ships, and that is the honest size.

Because `needsYouCount` reads this same accessor, it needs no separate gate.

### 6. Existing stored state: leave the data, fix the read

Founders already have unbuilt ids in `enabledTools` — `explorer` for everyone.
**Nothing writes to founder prefs.** `isBuilt` gates rendering and the
`env_setup` payload, so a stored `explorer` reads as "Not built yet" and sends
nothing.

```
Firestore (untouched):  enabledTools: [prd-writer, github, explorer]
Render:                 explorer -> "Not built yet"  (no toggle)
env_setup:              explorer omitted
enabled_skills:         [prd-writer]
Later, explorer ships:  isBuilt true -> already ON
```

Two reasons this beats cleaning up. Writing to real founder prefs is a known
hazard — mock flags once leaked into the founder's *real* preferences, in both
directions. And the stored id is the founder's original intent: preserving it
means a later-shipped item arrives already on, which is what they asked for.

### 7. `defaultEnabledIds` is fixed as data, not as a filter

`explorer`'s `defaultOn` becomes `false`. First-run seeding must be
deterministic: routing it through a network fetch would seed a founder's first
company differently depending on connectivity, so nothing here reads the live
manifest.

**`defaultEnabledIds` itself stays unfiltered, and the guard test asserts on the
raw `defaultOn` data.** This distinction is the whole point. Filtering the
accessor through `isBuilt` would look like belt-and-braces and would in fact
destroy the guard: a future default-on fake would be silently masked rather than
caught, and the test would pass forever. The data is fixed as data; the test
watches the data.

## Call sites

Each verified against `origin/main` @ `977a633`.

| # | Site | Change |
|---|---|---|
| 1 | `codepet/Models/Toolkit.swift` | `ToolItem.isBuilt(builtSkills:)`; `bundledBuiltSkills` constant |
| 2 | `Toolkit.recommended` | filter to built (covers `EnvironmentView:21` `needsYouCount`) |
| 3 | `Toolkit.catalog` — `explorer` | `defaultOn: true` → `false` |
| 4 | `CompanyStore` | `builtSkills` property + fetch beside `refreshConnectorStatus` |
| 5 | `CompanyStore:1672` | `env_setup` filter gains `&& $0.isBuilt(builtSkills:)` |
| 6 | `CompanyStore.toggleTool:3475` | early-return guard on an unbuilt id |
| 7 | `EnvironmentView:379` (browse row) | "Not built yet" in place of the toggle |
| 8 | `functions/src/` | new `capabilities` endpoint exporting `IMPLEMENTED_SKILLS` |
| 9 | `SetupCardState.swift` + `CopilotChatView:2047` | a `notBuilt` case, so a chat enable-card draws no pill |
| 10 | `EnvironmentView:178` (EN `companionText`) | drop "I've turned on the skills and agents I can" |

**Rows 9 and 10 were found while writing the implementation plan**, and row 9 is
the important one: the guard at #6 would otherwise *create* a bug. A stale
transcript can still hold an enable-card for an unbuilt item after #5 stops the
CF offering new ones. `SetupCardState.of` returns `.offer` for anything
resolvable and off, so the founder presses Enable, the guard silently returns,
and a working-looking button does nothing — the exact 7 Sep incident that
`SetupCardState` was written to prevent, and its own doc comment states the rule
being broken: *"a card that cannot act must not show a pill that pretends it
can."*

Row 10 is the same lie in prose: the EN copy had the companion reporting that it
had turned on agents, which it cannot do. The VI string never made that claim, so
fixing it also brings the two languages into parity.

**The guard at #6 is the invariant; #7 is only the UX.** Views not rendering a
control is what the founder sees, but the chokepoint in `toggleTool` is what
makes the fake on-state unreachable from *any* call site — including
`applySetup:2735` and any future one. This mirrors the lesson that `founderAsk`
must be stamped at exactly one site.

Two toggle call sites need no gate because they are built by construction:
`CompanyStore:3470` (the github mirror) and `ChatComposer:708` (web-research).

`EnvironmentView:236` (the recommendation card's toggle) is absent from the table
on purpose. Decision 5 filters `Toolkit.recommended` to built items, so an
unbuilt item never renders a card there at all and the toggle is unreachable.
Should that filter ever be relaxed, this site needs the same treatment as #7.

## Testing

Every fixture is hand-traced, and each guard is removed to watch the test go red
before it is claimed to pass. Five tests in one earlier plan could not fail; that
is the failure mode this discipline exists to prevent.

1. `isBuilt` per category — a skill in and out of the set; `github` true vs
   `notion` false; all four agents false
2. `builtSkills` falls back to the bundled pair when the fetch fails
3. `toggleTool` on an unbuilt id: `enabledTools` unchanged **and** the injected
   `toolsSaver` never called — proving no write, not just no visible change
4. `env_setup` payload omits unbuilt items
5. `defaultEnabledIds` ⊆ bundled built set — the drift guard that makes shipping
   another default-on fake impossible
6. `Toolkit.recommended` contains only built items
7. `ToolkitTests:11` updated: `["prd-writer","github","explorer"]` →
   `["prd-writer","github"]` (a real behaviour change, correctly caught)
8. A stored unbuilt id survives untouched — asserts decision 6

`CompanyStoreChatTests.swift` already constructs `CompanyStore` with injected
`loader`/`saver`, so 3, 4 and 8 follow an established pattern.

### Run constraints

- **Quit `codepet.app` first.** A running app (or a sibling build) kills the
  `xcodebuild test` host, with a different victim each run.
- Count results **only** via `xcresulttool get test-results summary`.
- A `-only-testing:` run is not a verified branch, and **pushing a branch runs no
  CI at all** — this needs a PR, even a draft.

## Non-goals

Recorded so nobody re-litigates them. This pass does not:

- add any OAuth provider
- implement `code-review` or `changelog`
- build any agent mechanism
- change `IMPLEMENTED_SKILLS` or `buildSkillsBlock`
- touch `SkillsView.swift` or `ChallengeTool` (game-era types, unrelated to the
  toolkit despite the names)
- write to any founder's stored preferences

## What comes after

One subsystem, its own spec. In ascending cost:

1. **Skills** — extend `IMPLEMENTED_SKILLS` + `buildSkillsBlock`. Backend-only,
   and with the manifest in place every existing client picks it up on deploy.
2. **Connectors** — one provider at a time: an OAuth app registration, a secret,
   a `ConnectorProvider` case, an MCP URL. The rails already work end to end for
   github, so each is additive rather than architectural.
3. **Agents** — needs a mechanism that does not exist. The path is the local
   Claude Code execution design (`2026-08-25-local-claude-code-execution-design.md`),
   whose hand-rolled MCP stdio server is measured working. Note that spec's open
   question 1 (whether a third-party app may drive a personal Claude
   subscription) gates shipping it, and is the one question that can end that
   route.
