# Department Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the composer's department `Menu` with a custom popover whose rows are pets, not departments, so Nova and Glitch each appear once and a selected row keeps its portrait.

**Architecture:** Every decision the popover makes is extracted as a pure function over plain values — the pet→departments grouping, keyboard traversal, and each chip's visual state — because a SwiftUI row cannot be asserted on from a test but a function can. The view is then a thin renderer over those three. This is the same reasoning that made `DepartmentMenu` a type rather than view code.

**Tech Stack:** Swift 5, SwiftUI, macOS 26.2, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-29-department-picker-design.md`

## Global Constraints

- **Quit codepet.app before running any test.** A running instance (or a sibling build mid-run) holds the Firestore lock and kills the `xcodebuild test` host, with a different victim each run.
- **Run tests per-suite with `-only-testing:`.** The XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates; ~27 tests never finish out of ~970 and a whole-suite run exits 65 on a clean checkout. That is landmine 3 in `CLAUDE.md`, not a regression you introduced.
- **Count results only via `xcresulttool get test-results summary`.** The console tail lies when the host dies mid-run.
- **A `-only-testing:` branch is an untested branch.** Open a draft PR when the work is done — pushing a branch alone runs no CI.
- **Build team-signed:** `DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates`. `CODE_SIGNING_ALLOWED=NO` builds run but Firebase auth does not.
- **New `.swift` files need no project-file edit.** `PBXFileSystemSynchronizedRootGroup`: target membership follows the folder on disk.
- **Do not add `.interpolation(.none)` to the picker's sprites.** `CLAUDE.md`'s always-nearest rule is about *upscaling*. These sprites are reduced from 421pt to 20pt, where nearest samples one pixel in twenty and can drop a 4px eye outright. `CharacterImage` uses smooth scaling and that is correct here — `PetMenuIcon`'s doc comment records the measurement.
- **Do not touch `DepartmentCompanions.map`.** The cast is not part of this change.
- Branch: `feat/department-picker`, cut from `origin/main`.

---

### Task 1: The grouping — pets carrying their departments

Rows come from pets, not departments. This is the change that makes Nova appear once.

**Files:**
- Create: `codepet/Models/DepartmentPickerRows.swift`
- Test: `codepetTests/DepartmentPickerRowsTests.swift`

**Interfaces:**
- Consumes: `DepartmentMenu.rosterOrder`, `DepartmentMenu.pet(for:)`, `PetCharacter.all`
- Produces: `struct PetRow { let petId: String; let petName: String; let departments: [Department]; var id: String }` and `DepartmentPickerRows.rows: [PetRow]`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentPickerRowsTests.swift`:

```swift
import XCTest
@testable import codepet

/// The picker iterates PETS, not departments — that is the whole point of the redesign.
/// These are the rules that grouping has to hold.
final class DepartmentPickerRowsTests: XCTestCase {

    /// Totality. Every roster department lands in exactly one pet's row: none dropped,
    /// none duplicated. Add a department with no pet, or give one to a second pet, and
    /// this goes red — which is the moment a design decision is owed.
    func testGroupingCoversTheRosterExactlyOnce() {
        let flat = DepartmentPickerRows.rows.flatMap { $0.departments.map(\.key) }
        XCTAssertEqual(flat.sorted(), DepartmentMenu.rosterOrder.map(\.key).sorted(),
                       "the grouping and the roster disagree")
        XCTAssertEqual(Set(flat).count, flat.count, "a department appears in two rows")
    }

    /// The two-department pets are the reason this type exists.
    func testNovaCarriesMarketingAndSalesInOneRow() throws {
        let nova = try XCTUnwrap(DepartmentPickerRows.rows.first { $0.petId == "nova" })
        XCTAssertEqual(nova.departments.map(\.key), ["mkt", "sales"])
        XCTAssertEqual(nova.petName, "Nova")
    }

    func testGlitchCarriesOperationsAndLegalInOneRow() throws {
        let glitch = try XCTUnwrap(DepartmentPickerRows.rows.first { $0.petId == "glitch" })
        XCTAssertEqual(glitch.departments.map(\.key), ["ops", "legal"])
    }

    /// Pet order follows first appearance in the roster, so the visual order the
    /// founder already knows is preserved by the redesign rather than reshuffled.
    func testPetOrderFollowsFirstAppearanceInTheRoster() {
        XCTAssertEqual(DepartmentPickerRows.rows.map(\.petId),
                       ["byte", "luna", "nova", "sage", "crash", "glitch"])
    }

    /// Six rows for eight departments — the duplication the redesign removes.
    func testSixRowsForEightDepartments() {
        XCTAssertEqual(DepartmentPickerRows.rows.count, 6)
        XCTAssertEqual(DepartmentMenu.rosterOrder.count, 8)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentPickerRowsTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'DepartmentPickerRows' in scope`.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/DepartmentPickerRows.swift`:

```swift
// codepet/Models/DepartmentPickerRows.swift
import Foundation

/// One row of the department picker: a pet, and every department it speaks for.
///
/// Nova covers Marketing and Sales; Glitch covers Operations and Legal. The old
/// `Menu` iterated departments, so those two pets rendered twice each — same sprite,
/// same name, nothing saying they were one character with two jobs.
struct PetRow: Identifiable, Equatable {
    let petId: String
    let petName: String
    let departments: [Department]
    var id: String { petId }
}

/// The picker's rows, derived from the same two sources the menu already read.
///
/// **Why this is a type and not a `ForEach` over a dictionary.** `DepartmentCompanions.map`
/// is a `[String: String]`, and dictionary iteration order is not stable across launches —
/// grouping inline would reshuffle the roster on the founder every time they opened the
/// control. Order is taken from `rosterOrder` and pinned by a test.
enum DepartmentPickerRows {

    /// Pets in first-appearance order over `DepartmentMenu.rosterOrder`, each carrying its
    /// departments in roster order.
    ///
    /// A roster department with no pet is SKIPPED rather than given a portrait-less row.
    /// None exists today — `rosterOrder` already filters Product, the only petless
    /// department — and `DepartmentPickerRowsTests.testGroupingCoversTheRosterExactlyOnce`
    /// goes red the moment one appears, which is the right way to learn that a decision
    /// is owed rather than shipping a blank face.
    static var rows: [PetRow] {
        var order: [String] = []
        var byPet: [String: [Department]] = [:]
        for dep in DepartmentMenu.rosterOrder {
            guard let pet = DepartmentMenu.pet(for: dep) else { continue }
            if byPet[pet] == nil { order.append(pet) }
            byPet[pet, default: []].append(dep)
        }
        return order.compactMap { pet in
            guard let name = PetCharacter.all[pet]?.name else { return nil }
            return PetRow(petId: pet, petName: name, departments: byPet[pet] ?? [])
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentPickerRowsTests 2>&1 | tail -20
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/DepartmentPickerRows.swift codepetTests/DepartmentPickerRowsTests.swift
git commit -F - <<'EOF'
Group the picker's rows by pet, not by department

The Menu iterated rosterOrder, so the six pets covering eight departments
rendered Nova twice and Glitch twice -- same sprite, same name, nothing
saying they were one character with two jobs.

Order is taken from rosterOrder rather than from DepartmentCompanions.map,
whose dictionary iteration is not stable across launches; a test pins it so
the roster cannot reshuffle itself on the founder between openings.

A petless roster department is skipped rather than drawn faceless. None
exists today and the totality test goes red the moment one does.
EOF
```

---

### Task 2: Keyboard traversal as a pure function

`Menu` supplied traversal free. This is the model the view will drive, written first so it is testable at all.

**Files:**
- Create: `codepet/Models/DepartmentPickerFocus.swift`
- Test: `codepetTests/DepartmentPickerFocusTests.swift`

**Interfaces:**
- Consumes: `PetRow` (Task 1)
- Produces: `enum PickerFocus: Equatable { case anyone; case chip(pet: Int, dept: Int) }` and `DepartmentPickerFocus.down(from:rows:)`, `.up(from:rows:)`, `.left(from:rows:)`, `.right(from:rows:)`, `.department(at:rows:)` — all `static`, all returning `PickerFocus` except `department` which returns `Department?`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentPickerFocusTests.swift`:

```swift
import XCTest
@testable import codepet

/// Traversal is a pure function so it can be asserted on at all — a SwiftUI row cannot be.
final class DepartmentPickerFocusTests: XCTestCase {

    private var rows: [PetRow] { DepartmentPickerRows.rows }

    /// Down from the Anyone row enters the list at the first pet's first chip.
    func testDownFromAnyoneEntersTheFirstRow() {
        XCTAssertEqual(DepartmentPickerFocus.down(from: .anyone, rows: rows),
                       .chip(pet: 0, dept: 0))
    }

    /// Up from the first row returns to Anyone rather than dead-ending.
    func testUpFromTheFirstRowReturnsToAnyone() {
        XCTAssertEqual(DepartmentPickerFocus.up(from: .chip(pet: 0, dept: 0), rows: rows),
                       .anyone)
    }

    /// Crossing rows resets to the first chip: arriving at Nova should land on Marketing,
    /// not on whichever column the previous row happened to leave behind.
    func testMovingBetweenRowsResetsToTheFirstChip() {
        let nova = rows.firstIndex { $0.petId == "nova" }!
        XCTAssertEqual(DepartmentPickerFocus.down(from: .chip(pet: nova, dept: 1), rows: rows),
                       .chip(pet: nova + 1, dept: 0))
    }

    /// Left/right walk a two-chip row and STOP at both ends — clamped, not wrapped.
    /// Wrapping would make Sales one keypress from Marketing in both directions, which
    /// reads as the focus jumping rather than moving.
    func testRightAndLeftWalkNovasTwoChipsAndClamp() {
        let nova = rows.firstIndex { $0.petId == "nova" }!
        let first = PickerFocus.chip(pet: nova, dept: 0)
        let second = PickerFocus.chip(pet: nova, dept: 1)
        XCTAssertEqual(DepartmentPickerFocus.right(from: first, rows: rows), second)
        XCTAssertEqual(DepartmentPickerFocus.right(from: second, rows: rows), second)
        XCTAssertEqual(DepartmentPickerFocus.left(from: second, rows: rows), first)
        XCTAssertEqual(DepartmentPickerFocus.left(from: first, rows: rows), first)
    }

    /// A one-chip row has nowhere to go sideways.
    func testSidewaysOnASingleChipRowStaysPut() {
        let byte = rows.firstIndex { $0.petId == "byte" }!
        let only = PickerFocus.chip(pet: byte, dept: 0)
        XCTAssertEqual(DepartmentPickerFocus.right(from: only, rows: rows), only)
        XCTAssertEqual(DepartmentPickerFocus.left(from: only, rows: rows), only)
    }

    /// Down from the last row stays on the last row.
    func testDownFromTheLastRowClamps() {
        let last = rows.count - 1
        let end = PickerFocus.chip(pet: last, dept: 0)
        XCTAssertEqual(DepartmentPickerFocus.down(from: end, rows: rows), end)
    }

    /// Sideways from Anyone does nothing — it has no chips.
    func testSidewaysFromAnyoneDoesNothing() {
        XCTAssertEqual(DepartmentPickerFocus.right(from: .anyone, rows: rows), .anyone)
        XCTAssertEqual(DepartmentPickerFocus.left(from: .anyone, rows: rows), .anyone)
    }

    /// Return needs to know what is under the cursor.
    func testDepartmentAtResolvesTheFocusedChip() throws {
        let nova = rows.firstIndex { $0.petId == "nova" }!
        let dep = try XCTUnwrap(
            DepartmentPickerFocus.department(at: .chip(pet: nova, dept: 1), rows: rows))
        XCTAssertEqual(dep.key, "sales")
        XCTAssertNil(DepartmentPickerFocus.department(at: .anyone, rows: rows))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentPickerFocusTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'DepartmentPickerFocus' in scope`.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/DepartmentPickerFocus.swift`:

```swift
// codepet/Models/DepartmentPickerFocus.swift
import Foundation

/// Where the keyboard is in the picker.
enum PickerFocus: Equatable {
    case anyone
    case chip(pet: Int, dept: Int)
}

/// Keyboard traversal over the picker's rows.
///
/// **Pure, and deliberately so.** `Menu` gave arrow-key traversal away for free; the
/// popover writes it. Kept out of the view because a SwiftUI row cannot be asserted on
/// from a test and a function can — the same reason `DepartmentMenu` is a type.
///
/// Every move CLAMPS rather than wraps. Wrapping would put Sales one keypress from
/// Marketing in both directions, which reads as the focus teleporting rather than moving.
enum DepartmentPickerFocus {

    static func down(from focus: PickerFocus, rows: [PetRow]) -> PickerFocus {
        guard !rows.isEmpty else { return .anyone }
        switch focus {
        case .anyone:
            return .chip(pet: 0, dept: 0)
        case .chip(let pet, _):
            return .chip(pet: min(pet + 1, rows.count - 1), dept: 0)
        }
    }

    static func up(from focus: PickerFocus, rows: [PetRow]) -> PickerFocus {
        switch focus {
        case .anyone:
            return .anyone
        case .chip(let pet, _):
            return pet == 0 ? .anyone : .chip(pet: pet - 1, dept: 0)
        }
    }

    static func right(from focus: PickerFocus, rows: [PetRow]) -> PickerFocus {
        guard case .chip(let pet, let dept) = focus, pet < rows.count else { return focus }
        return .chip(pet: pet, dept: min(dept + 1, rows[pet].departments.count - 1))
    }

    static func left(from focus: PickerFocus, rows: [PetRow]) -> PickerFocus {
        guard case .chip(let pet, let dept) = focus else { return focus }
        return .chip(pet: pet, dept: max(dept - 1, 0))
    }

    /// The department under the cursor, or nil on the Anyone row.
    static func department(at focus: PickerFocus, rows: [PetRow]) -> Department? {
        guard case .chip(let pet, let dept) = focus,
              pet < rows.count, dept < rows[pet].departments.count else { return nil }
        return rows[pet].departments[dept]
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentPickerFocusTests 2>&1 | tail -20
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/DepartmentPickerFocus.swift codepetTests/DepartmentPickerFocusTests.swift
git commit -F - <<'EOF'
Keyboard traversal for the picker, as a function rather than in the view

Menu supplied arrow-key traversal free; a popover does not. Writing it inside
the view would make it the one part of the redesign no test can reach, so it
is a pure function over the grouped rows -- the same reason DepartmentMenu is
a type and not view code.

Moves clamp rather than wrap. Wrapping would put Sales one keypress from
Marketing in BOTH directions, which reads as the focus teleporting.

Crossing rows resets to the first chip so arriving at Nova lands on Marketing
rather than on whatever column the previous row left behind.
EOF
```

---

### Task 3: Chip state — the guess-versus-pick distinction

The third finding, made testable. Today `deptRow` checkmarks on `armed ?? suggestedDept`, so a department Codepet merely guessed renders as a confident pick.

**Files:**
- Create: `codepet/Models/DepartmentChipState.swift`
- Test: `codepetTests/DepartmentChipStateTests.swift`

**Interfaces:**
- Consumes: `Department`
- Produces: `enum DepartmentChipState { case idle, suggested, picked }` and `DepartmentChipState.of(_:armed:suggested:) -> DepartmentChipState`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentChipStateTests.swift`:

```swift
import XCTest
@testable import codepet

/// A guess and a pick must not render alike. The old menu checkmarked on
/// `armed ?? suggestedDept`, so Codepet's guess appeared as the founder's decision —
/// while the composer chip, reading the same state, correctly drew it dashed.
final class DepartmentChipStateTests: XCTestCase {

    private func dept(_ key: String) throws -> Department {
        try XCTUnwrap(DepartmentCatalog.find(key), "no department '\(key)' in the catalog")
    }

    /// The regression this whole type exists to prevent. Collapse the two cases and
    /// this goes red.
    func testAGuessAndAPickAreDifferentStates() throws {
        let mkt = try dept("mkt")
        let guessed = DepartmentChipState.of(mkt, armed: nil, suggested: mkt)
        let picked = DepartmentChipState.of(mkt, armed: mkt, suggested: nil)
        XCTAssertEqual(guessed, .suggested)
        XCTAssertEqual(picked, .picked)
        XCTAssertNotEqual(guessed, picked)
    }

    /// A pick outranks a suggestion on the SAME department — it is no longer a guess
    /// once the founder has chosen it.
    func testPickingTheSuggestedDepartmentMakesItPicked() throws {
        let mkt = try dept("mkt")
        XCTAssertEqual(DepartmentChipState.of(mkt, armed: mkt, suggested: mkt), .picked)
    }

    /// A suggestion is suppressed entirely once anything is armed — the rule
    /// `ChatComposer.departmentControl` already applies as
    /// `activeSuggestion = armed == nil ? suggestion : nil`. Without this, arming Sales
    /// would leave Marketing dashed beside it and two chips would claim the turn.
    func testASuggestionIsSuppressedWhileSomethingElseIsArmed() throws {
        let mkt = try dept("mkt")
        let sales = try dept("sales")
        XCTAssertEqual(DepartmentChipState.of(mkt, armed: sales, suggested: mkt), .idle)
    }

    func testEverythingElseIsIdle() throws {
        let eng = try dept("eng")
        let mkt = try dept("mkt")
        XCTAssertEqual(DepartmentChipState.of(eng, armed: nil, suggested: nil), .idle)
        XCTAssertEqual(DepartmentChipState.of(eng, armed: mkt, suggested: nil), .idle)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentChipStateTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'DepartmentChipState' in scope`.

- [ ] **Step 3: Write the implementation**

Create `codepet/Models/DepartmentChipState.swift`:

```swift
// codepet/Models/DepartmentChipState.swift
import Foundation

/// How one department chip renders: outlined, dashed, or filled.
///
/// Three states differing in SHAPE, not only in colour, so the distinction survives
/// colour-blindness without adding glyphs to a 24pt chip.
enum DepartmentChipState: Equatable {
    /// Outlined, muted. Not this turn's department.
    case idle
    /// Dashed border, tinted fill. Codepet guessed this; the founder has not confirmed it.
    case suggested
    /// Filled in the pet's colour. The founder chose this.
    case picked
}

extension DepartmentChipState {

    /// **The rule the old menu got wrong.** `ChatComposer.deptRow` checkmarked on
    /// `armed ?? suggestedDept`, which renders a guess and a pick identically — so the
    /// menu presented Codepet's guess as the founder's decision, eighteen points above a
    /// composer chip that was correctly drawing the same state dashed. One control called
    /// it a guess and the other called it settled.
    ///
    /// The suppression on the last line mirrors `departmentControl`'s
    /// `activeSuggestion = armed == nil ? suggestion : nil`: a guess is only ever shown
    /// when nothing is armed, so two chips can never both claim the turn.
    static func of(_ department: Department,
                   armed: Department?,
                   suggested: Department?) -> DepartmentChipState {
        if armed?.key == department.key { return .picked }
        if armed == nil, suggested?.key == department.key { return .suggested }
        return .idle
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentChipStateTests 2>&1 | tail -20
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/DepartmentChipState.swift codepetTests/DepartmentChipStateTests.swift
git commit -F - <<'EOF'
Make a guess and a pick different states, not one checkmark

deptRow checkmarked on `armed ?? suggestedDept`, so a department Codepet had
only GUESSED rendered as the founder's decision -- while the composer chip,
built from the same state eighteen points below, correctly drew it dashed. One
control called it a guess and the other called it settled.

Three states that differ in shape (outlined / dashed / filled), not only in
colour, so the distinction does not rest on hue in a 24pt chip.

The suppression rule mirrors departmentControl's own
`activeSuggestion = armed == nil ? suggestion : nil`: arming Sales must not
leave Marketing dashed beside it with two chips claiming one turn.
EOF
```

---

### Task 4: The picker view

The renderer over the three pure pieces. No new logic.

**Files:**
- Create: `codepet/Views/Copilot/DepartmentPicker.swift`

**Interfaces:**
- Consumes: `DepartmentPickerRows.rows`, `PickerFocus`, `DepartmentPickerFocus`, `DepartmentChipState`, `DepartmentMenu.anyoneLabel/anyoneDetail/rowTitle`, `CharacterImage`, `CodepetTheme`, `PetCharacter.all`
- Produces: `struct DepartmentPicker: View` with initializer `DepartmentPicker(armed: Department?, suggested: Department?, lang: AppLanguage, onPick: @escaping (Department) -> Void, onAnyone: @escaping () -> Void)`

- [ ] **Step 1: Write the view**

Create `codepet/Views/Copilot/DepartmentPicker.swift`:

```swift
// codepet/Views/Copilot/DepartmentPicker.swift
import SwiftUI

/// The composer's department control, as a popover.
///
/// **Why not a `Menu`.** A `Menu`'s rows flatten to `(title, image)`, so a selected row's
/// checkmark takes the image slot and the pet's sprite is dropped — on the one row whose
/// pet is about to speak, while the composer chip below still showed that face. Neither
/// that nor grouping two departments under one portrait can be expressed in a native
/// `Menu` at any price. That constraint, not taste, is why this is a popover.
///
/// Every decision here is made by a pure function elsewhere — `DepartmentPickerRows` for
/// the grouping, `DepartmentPickerFocus` for the keyboard, `DepartmentChipState` for the
/// three chip treatments. This file only draws them.
struct DepartmentPicker: View {

    let armed: Department?
    let suggested: Department?
    let lang: AppLanguage
    let onPick: (Department) -> Void
    let onAnyone: () -> Void

    @State private var focus: PickerFocus = .anyone

    private var rows: [PetRow] { DepartmentPickerRows.rows }

    /// Open with the keyboard already on whatever is current, so the first arrow press
    /// moves from the founder's actual selection rather than from the top of the list.
    private var initialFocus: PickerFocus {
        guard let dep = shown else { return .anyone }
        for (petIndex, row) in rows.enumerated() {
            if let slot = row.departments.firstIndex(where: { $0.key == dep.key }) {
                return .chip(pet: petIndex, dept: slot)
            }
        }
        return .anyone
    }

    /// A suggestion is only ever live when nothing is armed — the same rule
    /// `DepartmentChipState.of` applies, kept here so the Anyone row's checkmark agrees
    /// with the chips below it.
    private var shown: Department? { armed ?? suggested }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            anyoneRow
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 6)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                petRow(row, at: index)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 326)
        .onMoveCommand { direction in
            switch direction {
            case .up:    focus = DepartmentPickerFocus.up(from: focus, rows: rows)
            case .down:  focus = DepartmentPickerFocus.down(from: focus, rows: rows)
            case .left:  focus = DepartmentPickerFocus.left(from: focus, rows: rows)
            case .right: focus = DepartmentPickerFocus.right(from: focus, rows: rows)
            @unknown default: break
            }
        }
        // Return acts on whatever the arrows landed on. No `.onExitCommand` here on
        // purpose: `.popover` already dismisses on Esc, and overriding it would turn
        // "close without deciding" into "clear the department", which is a different act.
        .onKeyPress(.return) {
            if let dep = DepartmentPickerFocus.department(at: focus, rows: rows) {
                onPick(dep)
            } else {
                onAnyone()
            }
            return .handled
        }
        .onAppear { focus = initialFocus }
    }

    private var anyoneRow: some View {
        Button {
            onAnyone()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(DepartmentMenu.anyoneLabel(lang))
                        .font(CodepetTheme.inter(13.5, weight: .semibold))
                        .foregroundColor(CodepetTheme.bodyText)
                    Text(DepartmentMenu.anyoneDetail(lang))
                        .font(CodepetTheme.inter(11.5))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                Spacer(minLength: 0)
                if shown == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(CodepetTheme.bodyText)
                }
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(focusRing(focus == .anyone))
    }

    private func petRow(_ row: PetRow, at index: Int) -> some View {
        HStack(spacing: 10) {
            CharacterImage(row.petId, size: 20)
            Text(row.petName)
                .font(CodepetTheme.inter(13.5, weight: .medium))
                .foregroundColor(CodepetTheme.bodyText)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                ForEach(Array(row.departments.enumerated()), id: \.element.key) { slot, dep in
                    chip(dep, petId: row.petId, focused: focus == .chip(pet: index, dept: slot))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
    }

    private func chip(_ dep: Department, petId: String, focused: Bool) -> some View {
        let state = DepartmentChipState.of(dep, armed: armed, suggested: suggested)
        let petColor = PetCharacter.all[petId]?.color ?? dep.accent
        return Button {
            onPick(dep)
        } label: {
            Text(dep.name)
                .font(CodepetTheme.inter(12, weight: state == .picked ? .semibold : .regular))
                .foregroundColor(chipForeground(state, petColor: petColor))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(chipBackground(state, petColor: petColor))
                .overlay(chipBorder(state, petColor: petColor))
                .overlay(focusRing(focused, shape: RoundedRectangle(cornerRadius: 6)))
        }
        .buttonStyle(.plain)
        // The row splits the pet's name from the department visually, but a screen
        // reader must still hear the string the reply is signed with — `rowTitle` stays
        // the single source of truth for "Nova · Marketing".
        .accessibilityLabel(DepartmentMenu.rowTitle(dep))
        .accessibilityAddTraits(state == .picked ? [.isButton, .isSelected] : [.isButton])
    }

    private func chipForeground(_ state: DepartmentChipState, petColor: Color) -> Color {
        switch state {
        case .idle:      return CodepetTheme.mutedText
        case .suggested: return petColor
        case .picked:    return .white
        }
    }

    @ViewBuilder
    private func chipBackground(_ state: DepartmentChipState, petColor: Color) -> some View {
        switch state {
        case .idle:      Color.clear
        case .suggested: RoundedRectangle(cornerRadius: 6).fill(petColor.opacity(0.09))
        case .picked:    RoundedRectangle(cornerRadius: 6).fill(petColor)
        }
    }

    @ViewBuilder
    private func chipBorder(_ state: DepartmentChipState, petColor: Color) -> some View {
        switch state {
        case .idle:
            RoundedRectangle(cornerRadius: 6)
                .stroke(CodepetTheme.hairline, lineWidth: 1)
        case .suggested:
            // The same dashed language the composer chip already uses for a guess, so
            // one grammar covers both controls instead of the two contradicting.
            RoundedRectangle(cornerRadius: 6)
                .stroke(petColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .picked:
            EmptyView()
        }
    }

    private func focusRing(_ on: Bool) -> some View {
        focusRing(on, shape: RoundedRectangle(cornerRadius: 6))
    }

    private func focusRing<S: InsettableShape>(_ on: Bool, shape: S) -> some View {
        shape.stroke(on ? Color.accentColor : .clear, lineWidth: 2)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates build 2>&1 \
  | grep -E "error:|BUILD" | tail -10
```

Expected: `BUILD SUCCEEDED`, no `error:` lines. The view is not yet reachable from the app — Task 5 wires it.

- [ ] **Step 3: Commit**

```bash
git add codepet/Views/Copilot/DepartmentPicker.swift
git commit -F - <<'EOF'
The picker view: one row per pet, chips for its departments

A renderer over three pure pieces and nothing else -- the grouping, the
traversal and the chip states each already have their own tests, so this file
adds no logic that a test cannot reach.

The chip's ACCESSIBILITY label is rowTitle(dep), the whole "Nova - Marketing",
even though the row now shows the name and the department separately. The
invariant that a row and the reply it summons read alike therefore survives at
the layer where a screen-reader user actually meets it.

Not wired into the composer yet.
EOF
```

---

### Task 5: Replace the `Menu` in the composer

**Files:**
- Modify: `codepet/Views/Copilot/ChatComposer.swift:350-425` (the `Menu` inside `departmentControl`) and `:497-509` (delete `deptRow`)

**Interfaces:**
- Consumes: `DepartmentPicker` (Task 4)
- Produces: no new API. `selectedDept`, `suggestion`, `onDismissSuggestion` and the `✕` keep their current semantics.

- [ ] **Step 1: Add the popover state**

In `ChatComposer`, beside the other `@State` properties, add:

```swift
    /// Drives the department popover that replaced the `Menu`.
    @State private var pickerOpen = false
```

- [ ] **Step 2: Replace the `Menu` with a `Button` + `.popover`**

In `departmentControl`, replace the whole `Menu { … } label: { … }` expression — from `Menu {` through the closing `.fixedSize()` that ends it — with:

```swift
            Button {
                pickerOpen = true
            } label: {
                HStack(spacing: 5) {
                    if let dep = shown, let pet = DepartmentMenu.pet(for: dep) {
                        CharacterImage(pet, size: 16)
                    }
                    Text(shown.map { DepartmentMenu.armedLabel($0) }
                         ?? DepartmentMenu.restLabel(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        // Same string as a pick, dimmed. Accepting a suggestion must change
                        // nothing on screen except the chip firming up.
                        .foregroundColor(shown.map { $0.accent.opacity(armed == nil ? 0.75 : 1.0) }
                                         ?? CodepetTheme.bodyText)
                        .lineLimit(1)
                    if shown == nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, shown == nil ? 10 : 6)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .popover(isPresented: $pickerOpen, arrowEdge: .top) {
                DepartmentPicker(
                    armed: armed,
                    suggested: suggestedDept,
                    lang: lang,
                    onPick: { dep in
                        selectedDept = dep
                        pickerOpen = false
                    },
                    // Two acts, one row — with nothing armed this refuses a GUESS rather
                    // than picking "Anyone" over a pick that is not there. The `shown`
                    // guard is the other half: with nothing shown, Anyone is already the
                    // answer and clicking it is a no-op. Without it, an idle poke killed
                    // carry-over and suppressed routing for the rest of the draft.
                    onAnyone: {
                        if shown != nil {
                            if armed == nil { onDismissSuggestion() } else { selectedDept = nil }
                        }
                        pickerOpen = false
                    }
                )
            }
```

`CharacterImage` replaces `PetMenuIcon` on the label: the button is a plain `Button`, not a `Menu` label, so nothing flattens it and the `.frame` is honoured — exactly as the roster chips already work.

- [ ] **Step 3: Delete `deptRow`**

Delete the whole `deptRow(_:current:)` method at `ChatComposer.swift:497-509`, including its doc comment. It has no callers once Step 2 lands.

- [ ] **Step 4: Verify nothing still references the deleted code**

```bash
grep -n "deptRow\|PetMenuIcon" codepet/Views/Copilot/ChatComposer.swift
```

Expected: no output. If `PetMenuIcon` still appears, a call site was missed.

- [ ] **Step 5: Build and run the composer suites**

```bash
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates build 2>&1 \
  | grep -E "error:|BUILD" | tail -10
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentMenuTests \
  -only-testing:codepetTests/ComposerMetricsTests \
  -only-testing:codepetTests/ComposerEdgeRenderTests \
  -only-testing:codepetTests/DepartmentLexiconTrapTests 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`; all four suites pass. `DepartmentMenuTests` must stay green untouched — `rowTitle` and `armedLabel` are unchanged by this task.

- [ ] **Step 6: Verify it on screen**

The plan's tests cannot see a popover. Launch the app and check the four things that motivated the redesign:

```bash
open -n ~/Library/Developer/Xcode/DerivedData/CodePet-*/Build/Products/Debug/codepet.app
```

1. Nova appears **once**, with Marketing and Sales as two chips.
2. Pick Marketing — the chip fills, and **Nova's portrait is still there**.
3. Type a message that makes Codepet guess a department — the guessed chip is **dashed**, and the composer chip below is dashed too.
4. Arrow keys walk rows; ← / → walk Nova's two chips; Return picks; Esc dismisses.

A stale build is the usual reason "it looks the same" — confirm the binary's timestamp is newer than your edit before concluding anything.

- [ ] **Step 7: Commit**

```bash
git add codepet/Views/Copilot/ChatComposer.swift
git commit -F - <<'EOF'
Swap the department Menu for the popover

The Menu could not render the redesign at any price: its rows flatten to
(title, image), so a selected row's checkmark evicted the pet's sprite, and
two departments could not sit under one portrait.

The composer's own button label switches from PetMenuIcon to CharacterImage.
PetMenuIcon existed only because a Menu's LABEL flattens the same way its rows
do; a plain Button honours .frame, which is why the roster chips have always
used CharacterImage directly.

The Anyone row keeps both acts and the `shown` guard: with nothing armed it
refuses a GUESS rather than clearing a pick that is not there, and with
nothing shown it is a no-op. Dropping that guard previously killed carry-over
and suppressed routing for the rest of the draft on an idle poke.
EOF
```

---

### Task 6: Delete `PetMenuIcon` and its tests

Its only two call sites were in the control Task 5 removed.

**Files:**
- Delete: `codepet/Views/PetMenuIcon.swift`
- Delete: `codepetTests/PetMenuIconTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: nothing

- [ ] **Step 1: Confirm there are no remaining references**

```bash
grep -rn "PetMenuIcon" codepet/ codepetTests/ | grep -v "codepet/Views/PetMenuIcon.swift" | grep -v "codepetTests/PetMenuIconTests.swift"
```

Expected: **one** line only — the comment in `codepetTests/SpeechFakesTests.swift:9`, which mentions `PetMenuIcon` as historical context for a testing rule, not as a call. Any other hit means a call site survives and this task must stop.

- [ ] **Step 2: Delete both files**

```bash
git rm codepet/Views/PetMenuIcon.swift codepetTests/PetMenuIconTests.swift
```

- [ ] **Step 3: Update the stale reference in `SpeechFakesTests`**

Open `codepetTests/SpeechFakesTests.swift:9` and change the phrase `PetMenuIcon` to `a since-deleted menu-icon helper` so the comment stays true after the type is gone. The rule it illustrates — do not draw through `NSImage.lockFocus()` in a headless test host — is still live and the comment should keep making it.

- [ ] **Step 4: Build and run the suite that referenced it**

```bash
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' DEVELOPMENT_TEAM=YL72VTKBR7 \
  CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates build 2>&1 \
  | grep -E "error:|BUILD" | tail -10
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/SpeechFakesTests 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`; `SpeechFakesTests` passes.

- [ ] **Step 5: Commit**

```bash
git add -A codepet/Views codepetTests
git commit -F - <<'EOF'
Delete PetMenuIcon with the Menu it existed for

It presized an NSImage because a Menu flattens its label and rows to
(title, image) and sizes the image from NSImage.size, discarding SwiftUI
layout modifiers. Both call sites were in the control the popover replaced.

Its test suite goes with it: a suite guarding a helper that nothing calls
protects nothing, which is the repo's own standard for whether a guard is
real.

SpeechFakesTests keeps its comment -- the rule about not drawing through
NSImage.lockFocus() in a headless host is still live -- but no longer names a
type that does not exist.
EOF
```

---

### Task 7: Open the draft PR

A `-only-testing:` branch is an untested branch. Every suite above was run in isolation; nothing has run the whole thing together.

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feat/department-picker
```

- [ ] **Step 2: Open a draft PR so CI runs the full suite**

```bash
gh pr create --draft --title "Department picker: one row per pet" \
  --body "$(cat <<'EOF'
Replaces the composer's department `Menu` with a popover whose rows are pets rather than departments.

Nova covered Marketing and Sales and Glitch covered Operations and Legal, so the eight-department menu rendered each of those pets twice — same sprite, same name. A selected row also lost its portrait, because a `Menu` row flattens to `(title, image)` and the checkmark took the image slot. And `deptRow` checkmarked on `armed ?? suggestedDept`, so a department Codepet had merely guessed rendered as the founder's decision while the composer chip below drew the same state dashed.

Spec: `docs/superpowers/specs/2026-08-29-department-picker-design.md`
Plan: `docs/superpowers/plans/2026-08-30-department-picker.md`

Draft until CI has run the full suite — every suite here was run with `-only-testing:` in isolation.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Read the CI result**

```bash
gh pr checks --watch
```

Expected: green. Landmine 3's ~27 non-finishing tests are a known clean-checkout condition — compare against a run on `main` before treating any host crash as yours.

---

## Notes for the implementer

**What this plan deliberately does not do.** The picker shows who each pet is and what it covers. It does not show badges ("The Firestarter"), voice, or remit copy — a remit line doubles the popover's height to put flavour text in front of a routing decision. Two follow-on gaps are named at the end of the spec and are not in scope here: how a reply reads as coming from that specialist, and a Prototype Mode fixture demonstrating the flow.

**Product stays off the roster.** It has no pet, and `dept-product.png` is a byte-identical copy of `dept-eng.png`, so a row for it would wear Engineering's face. Surfacing Product is a known, separate, launch-blocking decision.

**If `Task 1`'s totality test goes red later,** someone has added a roster department with no pet or given one department to a second pet. That is the test doing its job: the answer is a design decision about what a petless row looks like, not a patch to the grouping.
