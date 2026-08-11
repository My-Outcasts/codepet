# Department detail — layout alignment

**Date:** 2026-08-11
**Surface:** `codepet/Views/Company/DepartmentDetailView.swift`
**Status:** approved (founder, Aug 11)

## Problem

`DepartmentDetailView` is the only page in the company layer that opts out of the
shared page system introduced on Aug 5 (`CodepetTokens.Space`, `viewHeadPadding()`,
`pageColumn()`). Every other tab adopted it; this one still carries its own numbers.

| | Main pages | Department detail (today) |
|---|---|---|
| Horizontal margin | `26` | `20` |
| Top padding | `32` via `viewHeadPadding()` | `20` |
| Bottom padding | `56` (`Space.pageBottom`) | `20` |
| Width cap | `pageColumn()` → 1280, centred | **none — runs the full window** |
| Masthead | `inter(28, .semibold)` + `inter(15)` sub | 21pt, inside the hero image |
| Vertical rhythm | `headToBody 34` / `sectionAbove 36` / `sectionBelow 10` / `itemGap 14` | flat `spacing: 14` |
| Card chrome | `.cardChrome(radius:dark:)` | hand-rolled `surface` + `hairline`, no shadow |

Call sites for the main-page column: `CompanyView:40`, `TasksView:85`,
`LibraryView:225`, `EnvironmentView:41`.

The missing `pageColumn()` is the most visible defect: the department hero spans the
entire window while the Company roster that links to it is capped at 1280 and centred,
so the two pages do not read as the same application. `pageColumn()`'s own doc comment
states that header and body must both use it.

The page also states its purpose twice. `d.rationale` ("Build and ship the product
itself — the features, the technical foundation, the things users touch.") is followed
by a companion avatar and `d.focus` ("This is where the thing you're building actually
gets made."). Design shows the same duplication: "Shape how the product looks and
feels…" then "Make it clear, make it yours, make it easy to fall into."

## Decisions

Recorded with the alternatives that were rejected, so a later reader does not re-open them.

1. **Masthead above a contained hero.** The department name moves out of the cover art
   into a real 28pt masthead; the art stays as a shorter band below, inside the column.
   *Rejected:* keeping the name inside the hero (page stays typographically the odd one
   out); dropping the art entirely (the roster sets up a visual identity per department,
   and clicking a card with art to land somewhere with none breaks the handoff).
2. **`d.rationale` survives, the pet line is deleted.** Rationale says what the
   department does; `d.focus` is flavour. Keeping rationale also makes the masthead
   structurally identical to the other four pages: title plus one subtitle, nothing else.
   *Rejected:* keeping the pet's voice as the subtitle (the avatar breaks the shared
   masthead pattern); keeping both but separating them (still one sentence twice).
3. **Pinned header, scrolling body.** Three of four main pages put the header outside
   the `ScrollView` (`CompanyView:25`, `TasksView`, `EnvironmentView`); only Library
   scrolls everything. On a six-task department the way back stays reachable.

## Design

### Structure

Adopt `CompanyView`'s skeleton exactly. The uniform `padding(20)` is deleted.

```swift
VStack(alignment: .leading, spacing: 0) {
    header.viewHeadPadding()                 // top 32 · horizontal 26 · pageColumn()
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            hero(d)
            sectionEyebrow(needsDoingLabel)
            VStack(spacing: CodepetTokens.Space.itemGap) {
                ForEach(tasks) { DepartmentTaskCard(task: $0) }
            }
        }
        .padding(.top, CodepetTokens.Space.headToBody)      // 34
        .padding(.horizontal, 26)
        .padding(.bottom, CodepetTokens.Space.pageBottom)   // 56
        .pageColumn()
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
```

Outer `VStack` spacing is `0`; all vertical air comes from the `Space` tokens, so the
page cannot drift from the house rhythm again.

### Header (fixed)

```swift
VStack(alignment: .leading, spacing: 10) {
    backButton                                  // ‹ Company — 13pt, bodyText, unchanged
    VStack(alignment: .leading, spacing: 4) {
        Text(d.name)
            .font(CodepetTheme.inter(28, weight: .semibold))
            .tracking(-0.5)
            .foregroundColor(CodepetTheme.primaryText)
        Text(d.rationale)
            .font(CodepetTheme.inter(15))
            .foregroundColor(CodepetTheme.mutedText)
    }
}
```

The inner pair matches `CompanyView:51-59` exactly. `spacing: 10` separates the back
link from the title block. The back link is a functional control, not decoration, so
it stays.

Deleted: the `HStack` holding `CharacterImage(companyStore.company.companionId, size: 28)`
and `Text(d.focus)`.

### Hero

- Height `140 → 104`. The band no longer hosts a text block, and 104 keeps the first
  task card above the fold on a 900pt-tall window.
- `cornerRadius(14)` unchanged.
- Add `.interpolation(.high)`, matching the roster cover at `CompanyView:133`.
- **Image only.** The name, the `ab` badge and the `LinearGradient` accent wash are all
  removed. The gradient existed to make white text legible over the art; with no text
  on the art it only tints the image. The `ab` badge stays on the roster cover, where it
  is a marker on otherwise unlabelled art — beside a spelled-out "Engineering" it is
  decoration.

### Section label

`"What needs doing · N of M left"` at `inter(13, .semibold)` sentence-case with a
`padding(.top, 4)` hack becomes the house eyebrow: uppercased, `inter(10)`,
`tracking(1)`, `CodepetTokens.faint`, `sectionAbove 36` above and `sectionBelow 10`
below. Both language strings are uppercased at render time via `.uppercased()`, as
`EnvironmentView` already does.

`sectionEyebrow` is `private` to `EnvironmentView:101`. Lift it to `CodepetTokens.swift`
beside `viewHeadPadding()` and have both call sites use the shared one. This is the
alternative to copy-pasting a fourth variant of the same label.

### Task card chrome

`DepartmentTaskCard:109-110` hand-rolls `RoundedRectangle(cornerRadius: 12).fill(surface)`
plus a `hairline` stroke and no shadow. Replace with `.cardChrome(radius: 12, dark: scheme == .dark)`
— the treatment used by `TasksView:222`, `EnvironmentView:312` and `CopilotChatView:1200`.
The department card and the Tasks board card render the same `RoadmapTask` and should
not look like different objects. Requires `@Environment(\.colorScheme) private var scheme`
on `DepartmentTaskCard`.

Card internals (title, detail, status pill, action button, the blocked-task rule from
Aug 5) are unchanged.

## Out of scope

- `DepartmentTaskCard`'s behaviour: the action-button matrix, the blocked-task rule, the
  deliverable and draft-preview sheets.
- `CompanyView`, the roster rows, and the cover art assets themselves.
- The `d.focus` field on `Department` — the model keeps it; only this view stops
  rendering it.

## Verification

- `xcodebuild build -scheme codepet -destination 'platform=macOS'` green, TEAM-signed
  (`YL72VTKBR7`, `-allowProvisioningUpdates`) so the app is actually runnable.
- Layout is measurable offscreen with `ImageRenderer` in an XCTest, but it renders
  nothing inside a `ScrollView`. The assertable part is therefore the fixed header
  block: that it starts at x=26 and that its width caps at 1280 in a wider window.
- Everything below the fold is a founder visual check on the real app — screen
  recording is denied to the agent, so native UI confirmation is a handoff.
- Existing suites that touch this surface must stay green:
  `VirtualCompanyDepartmentTests`, `DepartmentCatalogTests`, `DepartmentCompanionsTests`,
  `DepartmentAddressingTests`. Run per-suite with `-only-testing:`; the XCTest host
  crash on Xcode 26.2 is a known non-regression.
