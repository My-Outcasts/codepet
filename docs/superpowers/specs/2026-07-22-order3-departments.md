# Order 3 — Departments (Company + Department Detail + Tasks) — Design Spec (2026-07-22)

## Mandate

**Match the web `develop` design as closely as possible.** Native gets the web's 8-department
model as three views over one dept-tagged task list. This spec pins the exact web layout, copy,
states, colors, and abbreviations so the port is faithful, not approximate. Source of truth:
`components/views/{CompanyView,DepartmentDetail,TasksView}.tsx` + `lib/data.ts` in
`/private/tmp/codepet-web-develop`.

## Architecture (settled)

The web carries a `dept` on every roadmap task and renders that ONE task list three ways:
Overview by phase (native already does this), Company by department, Tasks by status. Native
mirrors this: add `dept` to `RoadmapTask`, have `generateRoadmap` emit it, and derive all three
department views from the single generated task list. No parallel data structure; no per-dept AI.

---

## 1. Data model

### `RoadmapTask.dept` — OPTIONAL
Add `var dept: String?` to `codepet/Models/RoadmapTask.swift`. **Must be optional.** `RoadmapTask`
uses default (strict) `Codable`, so a required field would fail to decode every EXISTING saved
roadmap (`companies/{uid}.tasks`) and blank the board. Optional → old tasks decode as `dept == nil`
("unassigned"); new generations carry a real key. Add `dept` to the initializer with default `nil`.

### `Department` model + `DEPARTMENTS` catalog
Replace the bare `Department {key, name}` stub with a full model and a static catalog of the **8
web departments, in this exact order** (matches web `DEPTS`):

| key | name | ab | accent (native) | web DCOL |
|-----|------|----|-----------------|----------|
| `eng` | Engineering | En | blue | --blue |
| `design` | Design | De | purple | --violet |
| `mkt` | Marketing | Mk | orange | --clay |
| `sales` | Sales | Sa | purple | --accent |
| `support` | Support | Su | pink | --rose |
| `fin` | Finance | Fi | gold | --gold |
| `ops` | Operations | Op | teal | --teal |
| `legal` | Legal | Lg | purple | --violet |

Each catalog entry: `key, name, ab (2-letter badge), accent (CodepetTheme accent), coverAsset
("dept-{key}"), rationale, focus`. `rationale` = the web's `d.need` equivalent (one line: what this
department must accomplish); `focus` = the web's `d.byte` equivalent (a short companion-style line).
**Write GENERIC per-department text** (about what the department is for, appropriate to any founder)
— NOT the web seed's stage-specific demo copy. Draft copy (revise for tone at implementation):

- **eng** — rationale: "Build and ship the product itself — the features, the technical foundation, the things users touch." focus: "This is where the thing you're building actually gets made."
- **design** — rationale: "Shape how the product looks and feels so the first run lands and people get it fast." focus: "Make it clear, make it yours, make it easy to fall into."
- **mkt** — rationale: "Get the product in front of the right people and tell its story clearly." focus: "The best product still needs someone to hear about it."
- **sales** — rationale: "Turn interest into real users and first customers, one conversation at a time." focus: "Early on, you land users personally — not by broadcasting."
- **support** — rationale: "Help your users succeed and turn their friction into what you build next." focus: "Every question is a signal about what to fix."
- **fin** — rationale: "Keep the money side sound — pricing, runway, and the basics that keep you shipping." focus: "Know your numbers before they force your hand."
- **ops** — rationale: "Stand up the machinery that lets the whole company run without you touching every step." focus: "The boring plumbing that makes everything else possible."
- **legal** — rationale: "Cover the legal and compliance minimum so shipping never becomes a liability." focus: "Not glamorous, but it protects everything you're building."

### Per-department derivation (from the dept-tagged tasks)
A pure helper computes, for a department key, from `company.tasks` filtered to that `dept`:
- `pending` — count of not-done tasks.
- `currentTask` — the first not-done task's title (else nil).
- `status` — mirrors web `STATUS`: **`attention`** ("needs you") if any task derives to `.needsYou`;
  else **`ready`** if any derives to `.codepetCanDo`; else **`idle`**. (Reuse `RoadmapEngine.status`.)
- A department with **zero tasks** is treated as **`later`** (web's dormant state → label "later",
  count "Later", task line "Comes later as you progress").

`needToday` = count of departments with `status == attention` (drives the header subtitle).

---

## 2. `generateRoadmap` CF — emit `dept`

Re-touch the just-shipped CF (functions repo). In `generateRoadmapCore.ts`:
- Add `dept` to the `record_roadmap` tool schema (per task) and to `RawTask`.
- `DEPT_KEYS = ["eng","design","mkt","sales","support","fin","ops","legal"]`; validate; **default an
  invalid/missing dept to `"ops"`** (never drop a task for a bad dept).
- Emit `dept` on each coerced `RoadmapTask`.
- `buildRoadmapPrompt`: instruct the model to assign each task the single owning department from the
  8 keys (mirror the web roadmap prompt).
Add a `coerceRoadmap` test: dept validated, unknown/missing → `"ops"`. Redeploy scoped from the
local-disk dir (`--only functions:generateRoadmap`). Existing saved tasks keep `dept == nil` until
the next regeneration; that's fine (optional field, handled below).

---

## 3. Cover assets

Convert the web's 8 covers (`public/covers/{key}.avif` — all 8 present: eng, design, mkt, sales,
support, fin, ops, legal) to PNG and add to `Assets.xcassets` as image sets named `dept-{key}`
(SwiftUI doesn't reliably decode avif/webp from asset catalogs; PNG is safe). Use `sips` or
equivalent for the conversion. Rendered with the cover filling the card/hero, dept-accent tint
overlay for legibility (matches web's `dr-img` / `dhero2` + tint gradient).

---

## 4. CompanyView (replaces `.company` placeholder) — faithful to `CompanyView.tsx`

`codepet/Views/Company/CompanyView.swift`.
- **Header row:** H1 "Your company"; sub "Eight departments · {needToday} need you today"; right-aligned
  **"Re-plan for my stage"** button → calls `companyStore.generateRoadmap(language:)`; shows
  "Re-planning…" + disabled while running.
- **Department list** — one row per department (all 8, catalog order):
  - **Cover thumbnail** (`dept-{key}` image) with the **2-letter badge** (`ab`) tinted by dept accent.
  - **Body:** dept name + **status pill** (colored dot + label: "needs you" / "ready" / "idle" /
    "later"); below it the **current task** line (`currentTask` or "All clear"; "Comes later as you
    progress" when `later`).
  - **Right:** count — "{pending} to do" (bold number) / "All clear" / "Later"; and "Open" (hidden
    when `later`).
  - Row tap → push Department detail for that key. `later` rows read dimmed (web `.later`).

## 5. DepartmentDetail (new) — faithful to `DepartmentDetail.tsx`

`codepet/Views/Company/DepartmentDetailView.swift` (pushed from CompanyView).
- **Back control** "‹ Company" → pop to CompanyView.
- **Hero** (`dhero2`): the `dept-{key}` cover, dept-accent tint gradient bottom→up, overlaid with the
  mono **abbreviation** + dept **name** (H2).
- **Rationale line** (`dneed`): the catalog `rationale`.
- **Byteline:** the chosen companion's avatar (`company.companionId`, small) + the catalog `focus` text.
- **Section head:** "What needs doing · {left} of {total} left" (left = not-done count for this dept).
- **Task cards** — a web-faithful card per task (reuses `CompanyStore` actions, NOT the Overview's
  `TaskCardView` styling; this matches the web `TaskCard`):
  - **Not done:** title + detail + status pill (done/needsApproval/blocked/needsYou/codepetCanDo →
    web labels), and ONE action button by state (exact web copy):
    - `drafted` → **"Review & approve"**
    - `who == .you` → **"Walk me through it"** (ghost style)
    - `who == .draft` → **"Have Codepet draft it"**
    - else (`who == .does`) → **"Have Codepet do it"**
    - Tapping runs `companyStore.runTask` (walkThrough when `who == .you`), producing a deliverable.
  - **Done:** title + detail + "✓ Approved · delivered" row; if a matching library deliverable exists,
    a compact "Delivered" preview card (head + first ~4 lines + "Read") opening the deliverable.

## 6. TasksView (replaces `.tasks` placeholder) — faithful to `TasksView.tsx`

`codepet/Views/Tasks/TasksView.swift`.
- **Header:** H1 "Tasks"; sub "What {companionName} is doing, drafting, or waiting on you for."
- **4 kanban columns** (exact labels, colors, order), each with a colored dot + label + count:
  1. **Up next** (violet) — tasks whose derived state is Codepet-queued: `who` is `does`/`draft`, not
     done, not awaiting-approval, not needs-you (i.e. `.codepetCanDo` OR `.blocked` for a does/draft
     task — web folds "does + draft-not-yet" here).
  2. **Awaiting your approval** (gold) — `.needsApproval` (a produced draft).
  3. **Your move** (blue) — `.needsYou`.
  4. **Done** (green `#10B981`) — `done == true`.
- **Card:** dept name (from the task's `dept` via catalog; nil dept → omit or "Company") + task title;
  tap → not-done runs `runTask` (walkThrough when `who == .you`), done opens its deliverable.
- Empty column → **"Nothing here"**.

## 7. Sidebar wiring & navigation

- `AppShellView`: route `.company` → `CompanyView`, `.tasks` → `TasksView` (remove their
  `ShellPlaceholderView`). `.roadmap` stays a placeholder (its board is Overview — separate concern).
- Department detail is a navigation push within the Company destination (a `NavigationStack` around
  CompanyView, or a `@State selectedDept` swap). Keep the always-visible Copilot panel intact.

## Reuse vs. new
- **Reuse:** `CompanyStore.runTask` / `toggleTaskDone` / `approveDraft`, `RoadmapEngine.status`,
  `generateRoadmap`, `Deliverable`/library lookup, `CodepetTheme` accents, `PixelCard`/tinted-card style.
- **New:** `Department` model + `DEPARTMENTS` catalog, per-dept derivation helper, `dept` on
  RoadmapTask + CF, cover assets, `CompanyView`, `DepartmentDetailView`, a web-faithful department
  task card, `TasksView`.

## Out of scope (explicit)
- `.roadmap` node-graph map + typed deliverable viewers + richer Overview/chat (order 4).
- Any per-dept AI commentary / personalize pass (rationale + focus are static catalog copy).
- The `scaffoldRoadmap` CF (dept-grouped) stays unused — the single dept-tagged list feeds everything.

## Risks / gotchas
- **`dept` MUST be optional** on `RoadmapTask` (strict Codable) — else existing saved boards blank out.
- **Existing tasks have `dept == nil`** until regeneration: Company groups them nowhere (or a
  "Company" catch-all in Tasks); the board auto-regenerates when empty and "Re-plan" refills with
  real depts. Don't crash on nil dept.
- **Cover format:** avif/webp don't reliably load from asset catalogs → convert to PNG.
- **Task-card divergence:** DepartmentDetail uses a web-faithful card, distinct from the Overview's
  `TaskCardView` (which stays as-is this build). Aligning the Overview card is order 4.
- **CF redeploy:** adding `dept` re-touches the live `generateRoadmap` — redeploy scoped from
  `/private/tmp/cc-deploy`, verify 401 + a fresh generation carries `dept`.
