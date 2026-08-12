# Department Detail Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `DepartmentDetailView` adopt the shared page system every other company-layer page already uses, and delete the content it says twice.

**Architecture:** Four mechanical changes to one view, plus one small shared component lifted out of `EnvironmentView`. No model, store, or service changes. The view's skeleton becomes a copy of `CompanyView`'s: a fixed header with `viewHeadPadding()`, then a `ScrollView` whose content carries `Space.headToBody` / `26` / `Space.pageBottom` and `pageColumn()`.

**Tech Stack:** Swift 5, SwiftUI, macOS 26.2 deployment target, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-11-department-detail-layout-design.md` — it is the authority; this plan implements it and adds nothing.

## Global Constraints

- Work in `~/Developer/codepet-dept-layout` on branch `feat/dept-detail-layout`.
- Do **not** run `xcodegen`. New `.swift` files need no project-file edit — `PBXFileSystemSynchronizedRootGroup` makes target membership follow the folder on disk.
- Scheme is `codepet`, lowercase. Test module import is `@testable import codepet`, lowercase.
- Build: `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- SourceKit background diagnostics ("No such module XCTest", "Cannot find type X in scope") are **false positives** across this repo. The `xcodebuild` result is authoritative — do not chase them.
- `xcodebuild test` exits 65 on a clean checkout because ~27 tests never finish when a `@MainActor ObservableObject` deallocates on Xcode 26.2. This is a known non-regression. Run per-suite with `-only-testing:` and count results only via `xcresulttool get test-results summary`.
- Do not commit to `main`. Commit to `feat/dept-detail-layout`.
- Exact spacing values, copied verbatim from `CodepetTokens.Space`: `headToBody = 34`, `sectionAbove = 36`, `sectionBelow = 10`, `itemGap = 14`, `pageBottom = 56`. Horizontal page margin is the literal `26`. `pageColumnWidth = 1280`.

## A note on testing this change

Be honest about what is verifiable here, and do not invent assertions to fill a TDD template.

This change is almost entirely layout constants on a platform where the agent cannot screenshot the running app (Screen Recording is denied). There is exactly one piece of real logic — the section-label string — and Task 1 tests it properly. Everything else is verified by a green `xcodebuild build` plus a founder visual check on the real app.

**Do not** write a test that greps the source file for `pageColumn()`, and **do not** write a test that asserts a token equals its own literal. Both pass without protecting anything, which the repo's working agreements explicitly rule out. If a step below does not name a test, it does not have one on purpose.

## File Structure

| File | Change | Responsibility after the change |
|---|---|---|
| `codepet/Views/CodepetTokens.swift` | Modify (add ~14 lines near `viewHeadPadding()`, line ~159) | Gains `SectionEyebrow`, the one uppercase section label used by every tab |
| `codepet/Views/Environment/EnvironmentView.swift` | Modify (2 call sites at 36/38, delete private func at 98-108) | Stops owning the eyebrow; consumes the shared one |
| `codepet/Views/Company/DepartmentDetailView.swift` | Modify (rewrite `body` and `hero`, add `DepartmentHeader`, edit card chrome) | The page under repair |
| `codepetTests/DepartmentDetailLabelTests.swift` | Create | Covers the section-label string |

`DepartmentHeader` is extracted as its own small `View` struct rather than left as a private computed property. It takes plain values, not `CompanyStore`, which keeps it independently readable and removes a Firebase dependency from anything that renders it.

---

### Task 1: Shared `SectionEyebrow` and the department's label string

**Files:**
- Modify: `codepet/Views/CodepetTokens.swift` (insert after `viewHeadPadding()`, currently lines 155-161)
- Modify: `codepet/Views/Environment/EnvironmentView.swift:36`, `:38`, delete `:98-108`
- Create: `codepetTests/DepartmentDetailLabelTests.swift`

**Interfaces:**
- Consumes: `CodepetTheme.inter(_:weight:)`, `CodepetTokens.faint`, `CodepetTokens.Space.sectionAbove`, `CodepetTokens.Space.sectionBelow` — all existing.
- Produces:
  - `SectionEyebrow(_ text: String)` — a `View`. Uppercases its argument at render time.
  - `DepartmentDetailView.tasksLabel(left: Int, total: Int, lang: AppLanguage) -> String` — a `static func`, sentence-case. (The enum is `AppLanguage`, defined at `codepet/Models/AppLanguage.swift:10`. `UILanguage` is not a type — only `UILanguageKey`, the environment key, carries that name.) `SectionEyebrow` does the uppercasing, so this returns `"What needs doing · 4 of 6 left"`, not the shouted form. Task 2 renders it.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentDetailLabelTests.swift`:

```swift
// codepetTests/DepartmentDetailLabelTests.swift
import XCTest
@testable import codepet

/// The section label is the one piece of real logic in the department-detail
/// layout change. `SectionEyebrow` uppercases at render time, so this function
/// must return sentence case — a string that arrives pre-shouted would render
/// correctly and still be wrong the moment the eyebrow is reused elsewhere.
final class DepartmentDetailLabelTests: XCTestCase {

    func testEnglishLabelCountsWhatIsLeftOutOfTheTotal() {
        let label = DepartmentDetailView.tasksLabel(left: 4, total: 6, lang: .en)
        XCTAssertEqual(label, "What needs doing · 4 of 6 left")
    }

    func testVietnameseLabelCountsWhatIsLeftOutOfTheTotal() {
        let label = DepartmentDetailView.tasksLabel(left: 4, total: 6, lang: .vi)
        XCTAssertEqual(label, "Việc cần làm · còn 4/6")
    }

    func testLabelIsSentenceCaseSoTheEyebrowOwnsTheUppercasing() {
        let label = DepartmentDetailView.tasksLabel(left: 1, total: 3, lang: .en)
        XCTAssertNotEqual(label, label.uppercased(),
                          "tasksLabel must not pre-shout; SectionEyebrow uppercases")
    }

    func testEveryTaskDoneStillReadsAsZeroLeft() {
        let label = DepartmentDetailView.tasksLabel(left: 0, total: 6, lang: .en)
        XCTAssertEqual(label, "What needs doing · 0 of 6 left")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ~/Developer/codepet-dept-layout
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/DepartmentDetailLabelTests 2>&1 | tail -30
```

Expected: compile failure — `type 'DepartmentDetailView' has no member 'tasksLabel'`.

- [ ] **Step 3: Add `SectionEyebrow` to `CodepetTokens.swift`**

Insert immediately after the closing brace of `viewHeadPadding()` (currently line 161), at file scope — **not** inside the `View` extension:

```swift
/// The one section label. Uppercase, 10pt, 1px tracking, `--t-4`, with a large
/// gap above and a small one below so the label reads as belonging to the group
/// it introduces rather than the group above it.
///
/// This was `private func sectionEyebrow` inside `EnvironmentView`. The
/// department page needed the same label and a third hand-rolled variant was
/// the alternative. It is a `View` struct rather than a free function so it
/// cannot be shadowed by the unrelated `sectionEyebrow(icon:label:)` that the
/// older game layer's `LearnTabView` keeps for itself.
struct SectionEyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(CodepetTheme.inter(10, weight: .regular))
            .tracking(1)
            .foregroundColor(CodepetTokens.faint)
            .padding(.top, CodepetTokens.Space.sectionAbove)
            .padding(.horizontal, 2)
            .padding(.bottom, CodepetTokens.Space.sectionBelow)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 4: Point `EnvironmentView` at the shared component**

In `codepet/Views/Environment/EnvironmentView.swift`, replace line 36:

```swift
                    sectionEyebrow(lang == .vi ? "Đề xuất cho dự án của bạn" : "Recommended for your project")
```

with:

```swift
                    SectionEyebrow(lang == .vi ? "Đề xuất cho dự án của bạn" : "Recommended for your project")
```

and line 38:

```swift
                    sectionEyebrow(lang == .vi ? "Xem tất cả" : "Browse all")
```

with:

```swift
                    SectionEyebrow(lang == .vi ? "Xem tất cả" : "Browse all")
```

Then delete the now-unused private function — the whole block at lines 98-108, comment included:

```swift
    /// web `.env-sech` — 10px, 1px tracking, uppercase, --t-4. Spacing is the shared
    /// section rhythm: a large gap above, a small one below, so the label reads as
    /// belonging to the group it introduces.
    private func sectionEyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(CodepetTheme.inter(10, weight: .regular))
            .tracking(1)
            .foregroundColor(CodepetTokens.faint)
            .padding(.top, CodepetTokens.Space.sectionAbove).padding(.horizontal, 2).padding(.bottom, CodepetTokens.Space.sectionBelow)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
```

Its doc comment moved onto `SectionEyebrow` in Step 3, so nothing is lost.

- [ ] **Step 5: Add `tasksLabel` to `DepartmentDetailView`**

In `codepet/Views/Company/DepartmentDetailView.swift`, add this `static func` inside `struct DepartmentDetailView`, directly below the `left` computed property (currently line 12):

```swift
    /// Sentence case on purpose — `SectionEyebrow` uppercases at render time.
    static func tasksLabel(left: Int, total: Int, lang: AppLanguage) -> String {
        lang == .vi ? "Việc cần làm · còn \(left)/\(total)"
                    : "What needs doing · \(left) of \(total) left"
    }
```

This is the string that is inline at lines 33-34 today, lifted out unchanged so it can be tested. Leave the inline copy in place for now; Task 2 replaces the block that holds it.

- [ ] **Step 6: Run the test to verify it passes**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/DepartmentDetailLabelTests 2>&1 | tail -30
```

Expected: PASS, 4 tests.

If the run exits 65 with no failing assertion, count results properly rather than trusting the exit code:

```bash
xcrun xcresulttool get test-results summary --path \
  "$(ls -td ~/Library/Developer/Xcode/DerivedData/codepet-*/Logs/Test/*.xcresult | head -1)"
```

- [ ] **Step 7: Confirm the Environment tab still builds**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. This is what catches a missed `sectionEyebrow` call site.

- [ ] **Step 8: Commit**

```bash
git add codepet/Views/CodepetTokens.swift \
        codepet/Views/Environment/EnvironmentView.swift \
        codepet/Views/Company/DepartmentDetailView.swift \
        codepetTests/DepartmentDetailLabelTests.swift
git commit -F - <<'EOF'
refactor(tokens): one section eyebrow instead of a per-tab copy

The department page needs the same uppercase section label Environment
already had, and the alternative was a third hand-rolled variant — the page
was carrying its own 13pt sentence-case version with a padding(.top, 4)
hack.

A View struct rather than a free function: the older game layer's
LearnTabView keeps a private sectionEyebrow(icon:label:) of its own, and a
free function of the same base name would be shadowed inside that type.

tasksLabel comes out of the view body so the string is testable. It stays
sentence case — SectionEyebrow uppercases at render time, so a pre-shouted
string would look right here and be wrong the first time the label is
reused.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: The page skeleton — margins, column cap, pinned header

**Files:**
- Modify: `codepet/Views/Company/DepartmentDetailView.swift:14-46` (the `body`), add `DepartmentHeader` below the struct

**Interfaces:**
- Consumes: `DepartmentDetailView.tasksLabel(left:total:lang:)` and `SectionEyebrow` from Task 1; `viewHeadPadding()`, `pageColumn()`, `CodepetTokens.Space` — all existing.
- Produces: `DepartmentHeader(name: String, rationale: String, onBack: () -> Void)` — a `View`. Takes plain values, no `CompanyStore`.

No test. This task moves layout constants; the verification is a green build plus the founder's eyes. See the testing note above.

- [ ] **Step 1: Replace the `body`**

In `codepet/Views/Company/DepartmentDetailView.swift`, replace the whole of `var body: some View { … }` (lines 14-46) with:

```swift
    var body: some View {
        guard let d = dept else { return AnyView(EmptyView()) }
        // The skeleton is CompanyView's, deliberately: fixed header with
        // viewHeadPadding(), then a ScrollView whose content carries the shared
        // page rhythm and pageColumn(). Before this the page used padding(20) on
        // all four sides and never called pageColumn(), so its hero ran the full
        // width of the window while the roster that links to it capped at 1280.
        return AnyView(VStack(alignment: .leading, spacing: 0) {
            DepartmentHeader(name: d.name, rationale: d.rationale, onBack: onBack)
                .viewHeadPadding()
            ScrollView {
                // spacing: 0 — every vertical gap comes from CodepetTokens.Space,
                // so this page cannot drift off the house rhythm again.
                VStack(alignment: .leading, spacing: 0) {
                    hero(d)
                    SectionEyebrow(Self.tasksLabel(left: left, total: tasks.count, lang: lang))
                    if tasks.isEmpty {
                        Text(lang == .vi ? "Chưa có việc trong phòng ban này." : "No tasks in this department yet.")
                            .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                    } else {
                        VStack(spacing: CodepetTokens.Space.itemGap) {
                            ForEach(tasks) { t in DepartmentTaskCard(task: t) }
                        }
                    }
                }
                .padding(.top, CodepetTokens.Space.headToBody)
                .padding(.horizontal, 26)
                .padding(.bottom, CodepetTokens.Space.pageBottom)
                .pageColumn()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading))
    }
```

What this deletes, all of it intended by the spec: the inline back `Button` (it moves into `DepartmentHeader`), the standalone `Text(d.rationale)` (it becomes the masthead subtitle), the `HStack` holding `CharacterImage` + `Text(d.focus)`, the inline 13pt label, and `.padding(20)`.

- [ ] **Step 2: Add `DepartmentHeader`**

Add at file scope in the same file, between the closing brace of `DepartmentDetailView` (currently line 59) and the `DepartmentTaskCard` doc comment:

```swift
/// The masthead. Plain values rather than the store, so it carries no Firebase
/// dependency and can be rendered on its own.
///
/// The title/subtitle pair is CompanyView:51-59 exactly — 28pt semibold at
/// -0.5 tracking over 15pt muted, four points apart. The back link sits ten
/// points above it: it is a control, not decoration, so it survives the
/// no-decorative-icons rule, and pinning it outside the ScrollView keeps the
/// way out reachable on a six-task department.
private struct DepartmentHeader: View {
    let name: String
    let rationale: String
    let onBack: () -> Void
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text(lang == .vi ? "Công ty" : "Company").font(CodepetTheme.inter(13))
                }
                .foregroundColor(CodepetTheme.bodyText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(CodepetTheme.inter(28, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(CodepetTheme.primaryText)
                Text(rationale)
                    .font(CodepetTheme.inter(15))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

`.fixedSize(horizontal: false, vertical: true)` on the subtitle is carried over from the old `Text(d.rationale)` at line 27 — without it a two-line rationale truncates.

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

If it fails on `CharacterImage` being unused, that is expected fallout — the import stays, but check no other symbol went unreferenced.

- [ ] **Step 4: Re-run the label suite**

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/DepartmentDetailLabelTests 2>&1 | tail -20
```

Expected: PASS, 4 tests. `tasksLabel` is now the only source of that string.

- [ ] **Step 5: Commit**

```bash
git add codepet/Views/Company/DepartmentDetailView.swift
git commit -F - <<'EOF'
fix(company): the department page joins the shared page system

It was the only company-layer page still opted out of the Aug 5 rhythm:
padding(20) on all four sides against a house 26 horizontal / 32 top / 56
bottom, a flat spacing:14 instead of the Space tokens, and — the one that
actually shows — no pageColumn(). Its hero spanned the whole window while
the Company roster that links to it capped at 1280 and centred, so the two
pages did not read as the same app. pageColumn()'s own doc comment says
header and body must both use it.

The header moves outside the ScrollView, matching CompanyView, TasksView and
EnvironmentView; only Library scrolls its masthead. On a six-task department
the way back stays reachable.

Drops the companion + d.focus row. The page stated its purpose twice —
"Shape how the product looks and feels…" followed by "Make it clear, make it
yours, make it easy to fall into." Rationale survives because it says what
the department does; the avatar is also what broke the title-plus-one-
subtitle masthead the other four pages share. The model keeps the field.

DepartmentHeader takes plain values rather than the store so it has no
Firebase dependency and can be rendered on its own.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: The hero becomes a plain image band

**Files:**
- Modify: `codepet/Views/Company/DepartmentDetailView.swift` — the `hero(_:)` function (currently lines 48-58)

**Interfaces:**
- Consumes: `Department.coverAsset`. Stops consuming `Department.ab`, `Department.name` and `Department.accent` in this view.
- Produces: nothing new. `hero(_:)` keeps its signature.

No test — this is a height constant and three deletions.

- [ ] **Step 1: Replace `hero(_:)`**

Replace the whole function:

```swift
    /// A plain image band. The name, the two-letter badge and the accent
    /// gradient all came out when the masthead took over: the gradient existed
    /// only to make white text legible over the art, and with no text on the art
    /// it was tinting the image for nothing. The badge earns its place on the
    /// roster cover, where it marks otherwise unlabelled art — beside a
    /// spelled-out "Engineering" it is decoration.
    ///
    /// 104 rather than 140 because the band no longer holds a text block, and
    /// the shorter one keeps the first task card above the fold on a 900pt
    /// window. `.interpolation(.high)` matches the roster cover (CompanyView:133).
    private func hero(_ d: Department) -> some View {
        Image(d.coverAsset)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(14)
    }
```

`.frame(maxWidth: .infinity)` before `.clipped()` is load-bearing: `scaledToFill` on its own lets the image overflow the column horizontally, and the clip needs a bounded width to cut against.

- [ ] **Step 2: Build**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Company/DepartmentDetailView.swift
git commit -F - <<'EOF'
design(company): the department hero is just the art now

The name moved to the masthead, so everything that existed to support text
on the image goes with it. The LinearGradient was a legibility wash for
white type — with no type on the art it only tints the picture. The ab badge
marks unlabelled cover art on the roster; next to a spelled-out department
name it is decoration.

140 -> 104 because the band no longer holds a text block, and the shorter
one keeps the first task card above the fold on a 900pt window.

interpolation(.high) matches the roster cover at CompanyView:133, which the
detail hero never set.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: Task cards use the house chrome

**Files:**
- Modify: `codepet/Views/Company/DepartmentDetailView.swift` — `DepartmentTaskCard`, the `@State`/`@Environment` block near line 70 and the background at lines 108-110

**Interfaces:**
- Consumes: `cardChrome(radius:dark:)` from `CodepetTokens.swift:179`.
- Produces: nothing new.

No test. Chrome is a visual property; `cardChrome` is already exercised by the three views that use it.

- [ ] **Step 1: Add the colour-scheme environment read**

In `private struct DepartmentTaskCard`, add below `@Environment(\.uiLanguage) private var lang`:

```swift
    @Environment(\.colorScheme) private var scheme
```

- [ ] **Step 2: Swap the hand-rolled background for `cardChrome`**

Replace these two lines (currently 109-110):

```swift
        .background(RoundedRectangle(cornerRadius: 12).fill(CodepetTheme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
```

with:

```swift
        .cardChrome(radius: 12, dark: scheme == .dark)
```

Leave `.padding(12)` above it and both `.sheet(item:)` modifiers below it untouched.

- [ ] **Step 3: Build**

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add codepet/Views/Company/DepartmentDetailView.swift
git commit -F - <<'EOF'
design(company): department task cards get the house chrome

The card hand-rolled surface + hairline with no shadow while TasksView:222,
EnvironmentView:312 and CopilotChatView:1200 all use cardChrome. The
department card and the Tasks board card render the same RoadmapTask, and
one read visibly flatter than the other.

Addition to the original ask, raised and approved before starting.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 5: Regression sweep and founder handoff

**Files:** none modified.

- [ ] **Step 1: Run every suite that touches this surface**

One at a time — a whole-target run exits 65 on the known host crash and tells you nothing.

```bash
for suite in VirtualCompanyDepartmentTests DepartmentCatalogTests \
             DepartmentCompanionsTests DepartmentAddressingTests \
             DepartmentDetailLabelTests AppThemeTests; do
  echo "===== $suite"
  xcodebuild test -scheme codepet -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/$suite 2>&1 \
    | grep -E "Test Suite.*(passed|failed)|error:" | tail -5
done
```

Expected: every suite passes. A suite that hangs rather than fails is the Xcode 26.2 host crash — confirm with `xcresulttool get test-results summary` before treating it as a regression.

- [ ] **Step 2: Build signed, so the founder can actually run it**

An unsigned build runs but Firebase auth does not, which means no company data and an empty department page.

```bash
xcodebuild build -scheme codepet -destination 'platform=macOS' \
  DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. Do not use adhoc signing — it breaks the keychain.

Before launching, check whether a sibling session already has the app running. Firestore's lock means a second instance kills the other's test host.

```bash
pgrep -l codepet
```

If it prints anything, stop at build and say so — do not `pkill`.

- [ ] **Step 3: Hand off for the visual check**

The agent cannot screenshot the native app; Screen Recording is denied. State plainly what was and was not verified, and ask one specific question rather than a general "does it look right":

> Engineering and Design department pages, on a wide window: does the cover art now stop at the same width as the Company roster cards behind it, instead of running to the window edge?

- [ ] **Step 4: Push and open the PR**

Only after the founder confirms. Both are outward-facing — ask first.

```bash
git push -u origin feat/dept-detail-layout
gh pr create --base main --title "design(company): the department page joins the shared page system" --body "$(cat <<'EOF'
## What

`DepartmentDetailView` was the only company-layer page still opted out of the Aug 5 page system.

| | Main pages | Department detail (before) |
|---|---|---|
| Horizontal margin | 26 | 20 |
| Top / bottom | 32 / 56 | 20 / 20 |
| Width cap | `pageColumn()` → 1280, centred | none — full window |
| Masthead | 28pt + 15pt sub | 21pt, inside the hero image |
| Rhythm | `Space` tokens | flat `spacing: 14` |
| Card chrome | `cardChrome` | hand-rolled, no shadow |

The missing `pageColumn()` was the visible one: the hero spanned the window while the roster linking to it capped at 1280.

Also drops the duplicated subtitle — `d.rationale` was immediately followed by the companion repeating it as `d.focus`. The model keeps the field; only this view stops rendering it.

## Verified

- `xcodebuild build` green, TEAM-signed.
- `DepartmentDetailLabelTests` (new, 4 cases) plus `VirtualCompanyDepartmentTests`, `DepartmentCatalogTests`, `DepartmentCompanionsTests`, `DepartmentAddressingTests`, `AppThemeTests` all pass per-suite.
- Layout confirmed visually by the founder on the running app — the agent cannot screenshot native UI.

Spec: `docs/superpowers/specs/2026-08-11-department-detail-layout-design.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| Structure — skeleton, `pageColumn()`, `Space` tokens, `padding(20)` deleted | 2 |
| Header — pinned, 28/15 pair, `spacing: 10`, pet line deleted | 2 |
| Hero — 104, `interpolation(.high)`, badge + gradient + name removed | 3 |
| Section label — house eyebrow, `sectionEyebrow` lifted to `CodepetTokens` | 1 |
| Task card chrome — `cardChrome(radius: 12, dark:)` | 4 |
| Out of scope — card behaviour, `CompanyView`, `Department.focus` the field | Untouched by every task |
| Verification — build, per-suite tests, founder visual handoff | 5 |

No gaps.

**Placeholder scan:** none — every code step carries the full replacement text.

**Type consistency:** `tasksLabel(left:total:lang:)` is defined in Task 1 Step 5 and called in Task 2 Step 1 with the same label order and `Self.` qualification. `SectionEyebrow(_:)` is defined in Task 1 Step 3 and called in Task 1 Step 4 and Task 2 Step 1 with the same single unlabelled argument. `DepartmentHeader(name:rationale:onBack:)` is defined in Task 2 Step 2 and called in Task 2 Step 1 with matching labels. `hero(_:)` keeps its existing signature in Task 3.

**One ordering note for the executor:** Task 1 Step 5 adds `tasksLabel` while the old inline string at lines 33-34 is still present. That is deliberate — it keeps Task 1 independently committable and green. Task 2 Step 1 removes the duplicate. If you run the tasks out of order, the string exists twice in between and the label suite still passes.
