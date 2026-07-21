# Phase 6A — Deliverables Data Model + Library View — Design Spec

**Date:** 2026-07-21
**Phase:** 6A of the native=web-product rebuild (Phase 6 = deliverables + Library, decomposed into 6A model+view, 6B generation, 6C inline chat cards). Anchor: `2026-07-20-native-web-product-architecture.md`. Consumes `CompanyStore`/`CompanyData`/`CompanyState`, CodepetTheme, VI/EN.
**Goal:** A native `Deliverable` model (kind + markdown body), persisted in `companies/{uid}`, and a `LibraryView` that lists delivered work and opens each in one reusable markdown viewer. No generation this slice — the Library shows an honest empty state until 6B produces deliverables.

---

## Approved decisions (brainstorming)
1. **First slice = 6A** (model + Library view). Generation (6B) + inline chat cards (6C) are later phases.
2. **One markdown viewer + kind badge** — model every deliverable as `kind` + a markdown `body`; render all through a single `MarkdownView`. No 12 bespoke typed viewers.
3. **Field-array persistence** — `library` is a JSON-safe array field on the `companies/{uid}` doc (consistent with `tasks`), not a subcollection. (Subcollection is the future migration if bodies bloat past Firestore's 1 MB doc cap.)
4. **No `status` field this slice** — `library` *is* the delivered work; draft-in-chat is a 6C concept.

## Scope
**In:** `Deliverable` + `DeliverableKind` (replacing the placeholder `LibItem`); pure `MarkdownBlocks.parse`; `CompanyState.library: [Deliverable]` + `CompanyDoc.library` + `state(from:)` mapping; `MarkdownView`; `LibraryView` (+ card + detail); `AppShellView` `.library` route.
**Out (later):** generation / run-a-task + the save path (6B); inline chat deliverable cards + Approve/Redo + `status`/drafts (6C); bespoke typed viewers; export/share; editing.

## Components

### 1. `Deliverable` + `DeliverableKind` (`codepet/Models/Deliverable.swift`, replaces `LibItem`)
- `enum DeliverableKind: String, Codable, CaseIterable` — `doc, post, email, legal, screens, sheet, site, dms, calendar, checklist, plan, text, other` (mirrors the web `StructuredKind` + an `.other` fallback). `init(raw: String)` maps unknown → `.other`; a custom `init(from:)` decodes unknown strings to `.other` (fail-open). `func label(_ lang: AppLanguage) -> String` (VI/EN) + `var icon: String` (SF Symbol per kind).
- `struct Deliverable: Codable, Hashable, Identifiable` — `let id: String`; `var kind: DeliverableKind`; `var title: String`; `var body: String` (markdown); `var createdAt: String?` (ISO-8601 — JSON-safe; newest-first sort is lexicographic); `var sourceTaskId: String?` (the roadmap task that produced it — nullable, wired in 6B). Memberwise init defaults `id = UUID().uuidString`, `createdAt = nil`, `sourceTaskId = nil`.

### 2. `MarkdownBlocks` (`codepet/Models/MarkdownBlocks.swift`, pure)
- `enum MarkdownBlock: Equatable { case heading(level: Int, text: String); case bullet(String); case paragraph(String) }`.
- `static func parse(_ md: String) -> [MarkdownBlock]` — line-based: `# `/`## `/`### ` → heading (levels 1–3); `- `/`* ` → bullet; a blank line flushes the current paragraph; consecutive non-blank text lines join into one paragraph. Pure → unit-tested.

### 3. `MarkdownView` (`codepet/Views/Library/MarkdownView.swift`)
Renders `[MarkdownBlock]` in CodepetTheme: headings bold/larger by level, bullets as `•` + text, paragraphs as body text. Inline emphasis (`**bold**`, `*italic*`, `` `code` ``) via `AttributedString(markdown:)` with a plain-string fallback — no hand-rolled inline parsing. Takes the raw markdown string, parses via `MarkdownBlocks.parse`.

### 4. Persistence (`CompanyState` + `CompanyData`)
- `CompanyState.library` becomes `[Deliverable]` (was `[LibItem]`); `.empty` and the explicit init keep `library: []`. `LibItem` is removed.
- `CompanyDoc.library: [Deliverable]?` added; `CompanyData.state(from:)` maps `doc.library ?? []` (currently hardcodes `[]`). `Deliverable` is JSON-safe (strings/enum-as-string/optional strings) → decodes via the existing `JSONSerialization` load path.
- **No save path this slice** (generation/writes land in 6B).

### 5. `LibraryView` + wiring (`codepet/Views/Library/LibraryView.swift`)
- Reads `companyStore.company.library`, sorted newest-first by `createdAt` (nil sorts last). Empty → an honest empty card ("Delivered work will appear here" / "Once Codepet produces work, it collects here." + VI).
- Else → a scrolling list of `DeliverableCardView` (kind `icon` + `title` + short date), each tappable → presents `DeliverableDetailView` (a sheet: title, kind badge via `label`, `MarkdownView(body)`, close). Long bodies scroll.
- `AppShellView` content router gains `.library` → `LibraryView()` (mirroring the `.overview` → `OverviewBoardView` branch); other views stay `ShellPlaceholderView`.

## Data flow
`company.library` (@Published, hydrated from the doc) → `LibraryView` list → tap → `DeliverableDetailView` → `MarkdownBlocks.parse(body)` → `MarkdownView`. All read-only; no writes this slice.

## Error handling
Read-only + fail-soft (the existing doc load fail-soft covers it). Unknown `kind` strings decode to `.other` (fail-open). Malformed markdown still renders (worst case: everything is paragraphs). Empty library → honest empty state.

## Testing
- `DeliverableKind`: `label` non-empty + distinct per case in both languages; `icon` non-empty; `init(raw:)` unknown → `.other`; `init(from:)` decodes an unknown JSON string → `.other`.
- `MarkdownBlocks.parse`: headings (levels 1–3), bullets, paragraph joining, blank-line flush, a mixed document.
- `Deliverable`: Codable round-trip (incl. nil `createdAt`/`sourceTaskId`); `CompanyData.state(from:)` maps `library` (present → mapped, nil → `[]`).
- `LibraryView`/`MarkdownView`/`DeliverableDetailView` verified by build.

## Reuse / references
| Source | Native target |
|---|---|
| web `lib/ai/deliverableSchemas.ts` `StructuredKind` (12 kinds) | `DeliverableKind` (collapsed to kind + markdown) |
| web `LibraryView.tsx` (delivered-work list) | `LibraryView` + `DeliverableCardView` |
| web typed viewers | one `MarkdownView` |
| `CompanyState`/`CompanyData` (tasks field pattern) | `library` field + `state(from:)` mapping |
| `AppShellView` `.overview` router (3B) | `.library` router |

## Open decisions
None — resolved in brainstorming (6A first; single markdown viewer; field-array persistence; no status this slice). Ready for implementation planning.
