# Order 4 — Top bar + Overview node-graph map + Chat parity — Design Spec (2026-07-22)

## Mandate

Make the native **top bar**, **Overview**, and **chat** match the web `develop` as closely as
possible. This is the biggest visual gap remaining. One spec, built in **three phases**:
Phase A (top bar / nav), Phase B (Overview node-graph map + chrome), Phase C (chat parity).
Web source of truth: `components/{Topbar,AccountMenu,Copilot}.tsx` + `components/views/overview/RoadmapView.tsx`
+ `components/views/OverviewSection.tsx` in `/private/tmp/codepet-web-develop`.

Settled decisions: web-style **top-bar tabs** (retire the sidebar); **full node-graph map**;
**full web account menu** (incl. a Support screen + a dedicated Billing view). Second Brain and
"Wake up = install toolkit" are **stubs** (order-5 / not applicable natively).

---

# PHASE A — Top bar (retire the sidebar)

`AppShellView` is restructured: remove the left `sidebar`; a full-width top bar carries nav.

**Layout (faithful to `Topbar.tsx`):**
- **Left:** pixel **"Codepet"** brand, then the **account menu** (`AccountMenuView`).
- **Center:** nav tabs — **Overview · Company · Tasks · Library · Environment** (exact order/labels).
  Active tab accent-colored + underline. Tap → `companyStore.select(view)`. **Count badges:**
  - Tasks: `company.tasks.filter { !$0.done && ($0.who == .you || $0.who == .draft) }.count`
  - Library: `company.library.count`
  - Environment: toolkit items still off = `Toolkit.all.count - company.enabledTools.count` (clamped ≥0)
  A badge renders only when count > 0.
- **Right:** **"⚡ Wake {companion} up"** pill → `companyStore.select(.environment)` (native has no
  install flow; navigates to the toolkit). Then **"Upgrade"** button → opens Billing (see account menu).

**Routing changes:** the nav shows 5 tabs. `.settings` leaves the nav (reachable via the account
menu). `.roadmap` is dropped from nav (Overview *is* the roadmap). Add `.billing` and `.support` to
`AppView` (or route them via a `@State` in the shell) so the account menu can open them in the content
area. The Copilot panel stays docked right (Phase C restyles it).

**`AccountMenuView`** (new; faithful to `AccountMenu.tsx`): a `Menu`/popover triggered by an avatar
(companion image or initial) + the founder's name. Items:
- Identity block: `brief.founderName` (fallback "You") + the account email (`AuthManager.currentUser?.email`).
- **Settings** → `select(.settings)`
- **Billing & Usage** → `select(.billing)`
- **Support** → `select(.support)`
- **Appearance** — a 3-way System / Light / Dark control (drives `appState.appTheme`, the existing
  `AppTheme`), matching the web's segmented control.
- **Log out** → `authManager.signOut()` (confirm first).

**`BillingView`** (new; faithful to `BillingView.tsx`, native-appropriate): a Usage card ("Credits
this month", `{used}/{allowance}`, meter — native has no live metering, so show the static
Trial/Pro plan info currently in `SettingsView`'s Plan section, moved here) + a Plan card (Trial
current, "Upgrade to Pro" — disabled "coming soon", matching web). No BYOK (absent natively).
`SettingsView`'s Plan section is **removed** (it lives in Billing now); Settings keeps
companion / language / theme / edit-brief / sign-out.

**`SupportView`** (new; faithful to `SupportModal.tsx`): a message `TextEditor` + Send (gated on
non-empty) → writes to the existing feedback path (`FeatureFeedbackManager` / Firestore `feedback`)
+ a success confirmation. Reuse the existing feedback plumbing.

**Tests (pure):** `TopbarCountsTests` — the three count formulas (tasks you/draft-open, library,
env pending) from a fixture `CompanyState`.

---

# PHASE B — Overview node-graph map + chrome

Replace `OverviewBoardView`'s phase-**column** board with a node-graph **map**, faithful to
`RoadmapView.tsx`. Two parts: a pure layout engine + the map view + the chrome above it.

## B1 — `RoadmapMapLayout` (pure, testable) — `codepet/Models/RoadmapMapLayout.swift`

From `[RoadmapTask]` compute positions + edges. Pure geometry; no SwiftUI.

- `struct MapNode { let id: String; let task: RoadmapTask?; let x: CGFloat; let y: CGFloat }`
  (the company **root** node has `task == nil`, id `"__root__"`).
- `struct MapEdge { let fromId: String; let toId: String; let critical: Bool }`
- `struct RoadmapMap { let nodes: [MapNode]; let edges: [MapEdge]; let width: CGFloat; let height: CGFloat }`
- `static func layout(_ tasks: [RoadmapTask], colWidth: CGFloat = 260, rowHeight: CGFloat = 96, cardW: CGFloat = 200, cardH: CGFloat = 72) -> RoadmapMap`:
  - **Columns = phases** in order (find…launch); the **root** node occupies a column to the left of `find`.
  - Within a phase, tasks are laid out **top→bottom in their array order**; `y = rowHeight * rowIndex`.
  - `x = colWidth * (phaseOrder + 1)` (root at `x = 0`). Center each column's rows vertically against the
    tallest column so the map reads balanced (offset each column by `(maxRows - rows)/2 * rowHeight`).
  - **Edges:** for each task, one edge per `dependsOn` id (from the dep → this task). Tasks in the FIRST
    phase with no deps get a **root→task** edge (so the company node connects to entry points).
  - **Critical path:** mark an edge `critical` if either endpoint is the **beacon** task
    (`RoadmapEngine.nextStep`) or a transitive dependency of it (walk `dependsOn` from the beacon).
  - `width/height` = bounding box for the scroll content.
- **Tests** (`RoadmapMapLayoutTests`): root node present + at x=0; a task's x matches its phase column;
  root→entry edges for depless first-phase tasks; a dep edge exists per dependsOn; the beacon's
  dependency chain is flagged critical; empty tasks → just the root node.

## B2 — `RoadmapMapView` — `codepet/Views/Overview/RoadmapMapView.swift`

- A **horizontally + vertically scrollable** container sized `map.width × map.height`.
- **Edge layer** (`Canvas`): for each `MapEdge`, stroke a path from the source node's right-center to
  the target node's left-center (a smooth cubic/elbow). **Non-critical**: 1px dashed, `CodepetTheme.hairline`.
  **Critical**: 2.5px solid `CodepetTheme.accentPurple` with a soft glow underlay.
- **Node layer:** each `MapNode` rendered `.position(x:y:)`:
  - **Root** node: a distinct card — companion/Codepet glyph + company name + one-line tagline, accent aura.
  - **Task** node: a card colored by `RoadmapEngine.status`:
    - `.done` → green tint + "Done"
    - `.codepetCanDo` (== beacon) → accent gradient + glow + a floating **"{companion} is here"** pill;
      otherwise codepetCanDo → normal card + a filled **"Start"** chip
    - `.needsApproval` → "Review" chip; `.needsYou` → "Add your input" chip; `.blocked` → padlock +
      dimmed body + "Needs earlier steps"
    - dot-icon colored per the KEY legend; 2-line title.
  - Tap a runnable/blocked/you card → `companyStore.runTask` (as the board did) or a portal to the task.
  - **Hover peek** (`.onHover`): a tooltip with `dept·phase` + a plain sentence + "Unlocks after: {dep titles}"
    / "Leads to: {dependent titles}".
- Auto-scroll so the **beacon** is visible on first appearance (ScrollViewReader). Scroll-edge fade masks.
- Phase-header pill row pinned above the columns: `FIND {done}/{total}` … per phase.

## B3 — Overview chrome — `codepet/Views/Overview/OverviewView.swift` (wraps the map)

Faithful to `OverviewSection.tsx`. Above the map:
- H1 **"Overview"** + subtitle = `brief.projectName — brief.oneLiner` (or a fallback line).
- Top-right: a **Roadmap / Second Brain** segmented toggle (Second Brain tab shows a "Coming soon"
  placeholder this cut) + a **"How to read this map"** button that opens the KEY/intro.
- **Project Progress** card: `{percent}%`, a phase pill (current stage), animated bar, **"needs you {n}"**,
  **"Next: {nextPhaseName}"**. (percent = `RoadmapEngine.progressPercent`; needs-you = count of `.needsYou`.)
- **"{companion} · DO THIS NEXT"** beacon card: the beacon title, a **"Start"** button (runs/opens the
  beacon task), and **"Also needs you: {second needsYou task}"** when present.
- **KEY legend** column: Done · Codepet can do this · Needs your input · Needs approval · Needs earlier
  steps (5 dots + labels, exact web copy/colors).

`AppShellView` routes `.overview` → `OverviewView` (which contains `RoadmapMapView`). `OverviewBoardView`
(the old column board) is retired from the route (leave the file or delete; it's superseded).

---

# PHASE C — Chat parity — `codepet/Views/Copilot/CopilotChatView.swift`

Faithful to `Copilot.tsx` (the reply/streaming engine already works via companyChat — this is the shell).
- **Header:** "Your team" + "guiding · {company name}" + a **History** control (a stub toggle this cut if
  threads aren't modeled) + the existing collapse control.
- **Empty state:** personalized — "Welcome, {brief.founderName || 'there'}. Ask me anything about
  {company name} — where to focus, what's blocking you, or what to build next."
- **3 quick-start chips** (exact web copy): "What should I focus on first?" · "Summarize where my company
  is" · "What's blocking my launch?" — tap sends that text via `companyStore.sendChat`.
- **"Let's build"** CTA at the foot (a stub button this cut — the build flow is order-5; label + styling
  for fidelity, opens a "coming soon" note or is visually present/disabled).
- Input placeholder → "Ask Codepet anything about your company…".

---

## Reuse vs. new
- **Reuse:** `companyStore.select/runTask/sendChat`, `RoadmapEngine` (status/nextStep/progressPercent),
  `AppTheme`, `AuthManager`, `Toolkit`, `FeatureFeedbackManager`, `CodepetTheme`, `PetCharacter`/`CharacterImage`.
- **New:** `AccountMenuView`, `BillingView`, `SupportView`, `RoadmapMapLayout` (+ tests), `RoadmapMapView`,
  `OverviewView`; top-bar rewrite of `AppShellView`; chat shell enhancements; `TopbarCountsTests`.

## Out of scope (explicit)
- The 3D "Second Brain" WebGL map (toggle is a stub). "Wake up = install Claude Code toolkit" (pill just
  navigates to Environment). The build-session "Let's build" flow (stub). BYOK. Chat thread History
  persistence (control is a stub unless threads are already modeled). Typed deliverable viewers (separate).

## Risks / gotchas
- **Map rendering is the hard part** — `Canvas` edge drawing + `.position` node layout + scroll/scale.
  Keep the layout engine pure + tested; the view consumes it. Budget the most time here.
- **Nav rewrite touches the shell** — `.settings` moving to the account menu + new `.billing`/`.support`
  routes must not break existing view routing; keep the Copilot panel docked.
- **Second Brain / Let's build / History / Wake-install are visible-but-stub** — label them faithfully but
  wire to "coming soon"/navigate, so the UI matches without implying unbuilt features work.
- **Beacon = single source** — the map's "is here" node, the progress card, and the beacon card must all
  read the SAME `RoadmapEngine.nextStep`, or the app contradicts itself (the web's one-beacon rule).
