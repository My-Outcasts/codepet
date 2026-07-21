# Phase 7 — Environment (Toolkit) — Design Spec

**Date:** 2026-07-21
**Phase:** 7 of the native=web-product rebuild. Replaces the `.environment` placeholder with the toolkit. Anchor: `2026-07-20-native-web-product-architecture.md`. First CF-free phase since 3A.
**Goal:** The Environment view — the tools/stack the company runs on. A static catalog of skills/connectors/agents the founder can enable/disable, with recommendations, persisted per company.

---

## Approved decisions (brainstorming)
1. **Static ported catalog** — port the web `ENV` (13 items) as a static native catalog. No Cloud Function; Phase 7 is fully live immediately. Only the per-company on/off state persists.
2. **Include the recommendations strip** — recommended-but-off items surface at the top with their "why".
3. **Defer** feeding enabled tools into the companion's chat/generation context (a small follow-up).
4. Persistence = a **per-company enabled-id set** (nil → first-run defaults, `[]` → all-off).

## Scope
**In:** `ToolCategory` + `ToolItem` + the static `Toolkit` catalog + helpers; `CompanyState.enabledTools` + `CompanyDoc.enabledTools` + `state(from:)` mapping; `CompanyStore.toggleTool` + `CompanyData.enabledToolsPayload`/`saveEnabledTools`; `EnvironmentView` (recommendations strip + category sections + toggle) + `.environment` route.
**Out (later):** feeding enabled tools into `ChatContext`/generation; usage evidence ("Used in N tasks"); `/setup/[slug]` subpages; the chat `setup_capability` tool; OAuth; localizing catalog item content (chrome is VI/EN; item name/detail/why stay EN, matching the web source).

## Components

### 1. Toolkit catalog (`codepet/Models/Toolkit.swift`, static + pure)
- `enum ToolCategory: String, CaseIterable { case skills, connectors, agents }` with `label(_ lang)` (Skills/Connectors/Agents + VI), `enableVerb(_ lang)` (Turn on/Connect/Enable + VI), `onLabel(_ lang)` (Active/Connected/Enabled + VI), and `var tint: Color` (`accentPurple`/`accentBlue`/`accentTeal`).
- `struct ToolItem: Identifiable, Equatable { let id: String; let name: String; let badge: String; let detail: String; let category: ToolCategory; let recommended: Bool; let why: String?; let defaultOn: Bool }`.
- `enum Toolkit`:
  - `static let catalog: [ToolItem]` — the 13 web `ENV` items, ported with stable slug ids (`web-research`, `prd-writer`, `code-review`, `changelog`, `github`, `notion`, `figma`, `slack`, `linear`, `code-reviewer`, `explorer`, `test-writer`, `migrator`), `defaultOn` from `s`, `recommended`/`why` from `rec`/`why`. Descriptions genericized (no hard-coded companion name).
  - `static func items(in category: ToolCategory) -> [ToolItem]`; `static var recommended: [ToolItem]` (recommended items); `static var defaultEnabledIds: Set<String>` (ids where `defaultOn`).
- **Defaults:** `defaultOn` = `prd-writer`, `github`, `explorer`. **Recommended** = `prd-writer`, `code-review`, `github`, `notion`, `test-writer`.

### 2. Per-company enabled state + persistence
- `CompanyState.enabledTools: Set<String>` (enabled item ids), the explicit init defaulting it to `Toolkit.defaultEnabledIds` (so `.empty` / fresh accounts start with the default toolkit on).
- `CompanyDoc.enabledTools: [String]?`; `state(from:)` maps `doc.enabledTools.map(Set.init) ?? Toolkit.defaultEnabledIds` — **nil → defaults**, **`[]` → all-off**, `[ids]` → that set.
- `CompanyData.enabledToolsPayload(_ tools: [String]) -> [String: Any]` (`["enabledTools": tools]`); `saveEnabledTools(companyId:tools:) async -> Bool` (merge, fail-soft).
- `CompanyStore.toggleTool(id: String) async` — flip `id` in `company.enabledTools`; persist via injectable `toolsSaver: (String, [String]) async -> Bool` (default `CompanyData.saveEnabledTools`); fail-soft.

### 3. `EnvironmentView` + wiring (`codepet/Views/Environment/EnvironmentView.swift`)
- Reads `companyStore.company.enabledTools` + `@Environment(\.uiLanguage)`.
- **Recommendations strip** (top): `Toolkit.recommended` items whose id is **not** in `enabledTools` → a card each (badge + name + `why` + a `enableVerb` button → `toggleTool`). The whole strip hides when none remain.
- **Category sections**: for each `ToolCategory` in order, a header (`label` + `{on}/{total}` count) over `Toolkit.items(in:)`; each item = a `ToolRowView` (badge tinted by `category.tint`, name, detail, and a toggle showing on/off from `enabledTools.contains(id)`) → `toggleTool(id:)`.
- `AppShellView` routes `.environment` → `EnvironmentView()` (mirroring `.overview`/`.library`).

## Data flow
`company.enabledTools` (@Published, hydrated from the doc or first-run defaults) → `EnvironmentView` (recs + category toggles). Toggle → `toggleTool` → mutate `enabledTools` + persist. No CF, no generation.

## Error handling
No CF / no fail-open generation. Persistence **fail-soft** (a failed `saveEnabledTools` keeps the in-memory toggle). `enabledTools` rides `company` (hydrate/reset already clear/reload it per account).

## Testing
- `Toolkit`: `catalog` has 13 items with **unique ids**; `defaultEnabledIds ⊆` catalog ids and equals `{prd-writer, github, explorer}`; `items(in:)` across the 3 categories partitions all 13; `recommended` is non-empty and all `recommended` items have a non-nil `why`.
- `ToolCategory`: `label`/`enableVerb`/`onLabel` non-empty + distinct per case in both languages.
- `CompanyState.enabledTools` + `state(from:)`: nil doc → `defaultEnabledIds`; `[]` → empty; `["github"]` → `{github}`. `CompanyStore.toggleTool` flips on↔off + persists (via a stub `toolsSaver`). `CompanyData.enabledToolsPayload` shape.
- `EnvironmentView`/`ToolRowView` verified by build.

## Reuse / references
| Source | Native target |
|---|---|
| web `lib/data.ts` `ENV` (13 items) + `ENV_CATS`/`ENV_META` | `Toolkit.catalog` + `ToolCategory` |
| web `EnvironmentView.tsx` (recs + category toggles) | `EnvironmentView` + `ToolRowView` |
| `CompanyData` tasks/library field-array pattern | `enabledTools` field + `saveEnabledTools` |
| `AppShellView` `.overview`/`.library` router | `.environment` route |

## Open decisions
None — resolved in brainstorming (static catalog; recommendations strip; defer chat-context; enabled-id-set persistence nil→defaults / []→off). Ready for implementation planning.
