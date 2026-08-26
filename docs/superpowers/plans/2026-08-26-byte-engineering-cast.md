# Byte Takes Engineering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Byte the Engineering department's pet and Crash the Finance pet, with Codepet as the host of general conversation — so the roster on the empty hero shows Byte, and the product's own voice and a department's voice stop sharing a name.

**Architecture:** Three commits, ordered so no intermediate state is visibly broken. First delete the host-shadow rule from `DepartmentCompanions` (a pure signature change; the cast is untouched). Then change two entries in the cast map, which is only safe *after* the rule is gone. Then rename the character and fix every surface that was rendering "Codepet" by accident of that name. The pet↔department map lives only in the Swift client — `functions/` is not touched.

**Tech Stack:** Swift 5 / SwiftUI, macOS deployment target 26.2, XCTest, `xcodebuild` (scheme `codepet`, no xcodegen).

**Spec:** `docs/superpowers/specs/2026-08-26-byte-engineering-department-design.md` (read it before Task 1; it carries the reasoning this plan only executes).

## Global Constraints

- **Branch:** work on `feat/byte-engineering-cast`. Do NOT commit to `main` (project rule: branch, PR, say what you verified). The spec's two commits are already on this branch.
- **The character id `"byte"` must not change.** Only the display `name` changes. `actor:'byte'`, `company.companionId`, `PetCharacter.starters`, and `imageName` → `char-byte` are all keyed on the id, and changing it is a Firestore migration.
- **Test module:** `@testable import codepet`. Scheme is lowercase `codepet`. There is no xcodegen step.
- **New `.swift` files need no project-file edit** — target membership follows the folder on disk (`PBXFileSystemSynchronizedRootGroup`). This plan adds one new test file.
- **Run every `xcodebuild` in the FOREGROUND.** Never background it.
- **SourceKit cross-file diagnostics ("Cannot find type X", "No such module") are FALSE POSITIVES.** Trust `xcodebuild`, not the editor.
- **Quit codepet.app before running tests.** A running instance (or a sibling session's build mid-run) takes the Firestore lock and kills the `xcodebuild test` host, with a different victim each run.
- **Per-suite test command** (used in every task):
  ```bash
  cd ~/Developer/codepet && xcodebuild test -scheme codepet -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Suite> 2>&1 | tail -25
  ```
- **A `-only-testing:` run is not a verified branch.** Task 4 runs the whole target and counts with `xcresulttool`, because a whole-target `xcodebuild test` exits 65 on a clean checkout for reasons unrelated to this work (the XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates; ~27 of ~970 tests never finish). Judge the full run by the `xcresulttool` counts, never by the exit code.
- **No `functions/` changes.** `functions/src/departments.ts` expertise is keyed by department and is pet-agnostic; `companyChatCore` already takes `companion_id` and `dept_key` as independent fields.

---

### Task 1: Delete the host-shadow rule

`specialistId(for:host:)` returns nil whenever a department's pet IS the founder's own companion. Every founder's companion is `byte` (the onboarding picker was removed 14 Aug), so once Task 2 maps `byte` to `eng`, Engineering becomes the one department that shows an orb and never signs a reply. The rule goes first so Task 2 lands safely.

Its premise never held: `CopilotChatView.headerName` returns `CodepetBrand.name` whenever `message.companionId` is nil, which is every general turn — so the host never signs with a pet's name and there is no self-handoff to suppress. Suppression only ever hid attribution, never expertise: `CompanyStore.actingDeptKey` is already separate from `actingSpecialist`.

**Files:**
- Modify: `codepet/Models/DepartmentCompanions.swift:22-37` (delete `specialistId`, rewrite the doc comment above it)
- Modify: `codepet/Models/DepartmentMenu.swift:19-38` (`pet`, `rowTitle`, `armedLabel` lose `host:`)
- Modify: `codepet/Managers/CompanyStore.swift:852-863` (`actingSpecialist`)
- Modify: `codepet/Views/Copilot/DepartmentRoster.swift:67-69` (`chip`)
- Modify: `codepet/Views/Copilot/ChatComposer.swift:333,346,358,362,415-421`
- Create: `codepetTests/DepartmentMenuTests.swift`
- Test: `codepetTests/DepartmentCompanionsTests.swift:7-15`, `codepetTests/TwoModeHeroTests.swift:429-448`

**Interfaces:**
- Produces: `DepartmentCompanions.companionId(for deptKey: String) -> String?` (already exists, unchanged — it becomes the only resolver). `DepartmentMenu.pet(for department: Department) -> String?`, `DepartmentMenu.rowTitle(_ department: Department) -> String`, `DepartmentMenu.armedLabel(_ department: Department) -> String` — all three lose their `host: String` parameter.
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write the failing tests**

Replace `testSpecialistIdDeclinesTheHostAndTheUnmapped` in `codepetTests/DepartmentCompanionsTests.swift` (lines 5-15, the doc comment and the whole function) with:

```swift
    /// The composer's chip and the send that follows it read the same rule, so what the chip
    /// shows and what signs the reply cannot disagree. One unconditional resolver is what
    /// guarantees it: with no `host` parameter there is no input on which they could differ.
    ///
    /// The deleted `specialistId(for:host:)` returned nil here whenever `host == "nova"`, so the
    /// founder whose own companion was Nova got no attribution on Marketing. That is the
    /// behaviour change, and it gets no assertion of its own because it can no longer be
    /// expressed: there is no second input to vary. Nothing in Swift can assert that a deleted
    /// symbol stays deleted, so the guard against the rule returning is the doc comment on
    /// `DepartmentCompanions` and this test's name, not an assertion.
    func testCompanionIdIsUnconditional() {
        XCTAssertEqual(DepartmentCompanions.companionId(for: "mkt"), "nova")
        // Product is in the catalog to resolve a Virtual Company wire key; it has no pet.
        XCTAssertNil(DepartmentCompanions.companionId(for: "product"))
    }
```

Create `codepetTests/DepartmentMenuTests.swift`. `DepartmentMenu` has had no test coverage at all, despite its own doc comment claiming its one rule is testable — this closes that:

```swift
import XCTest
@testable import codepet

/// `DepartmentMenu`'s doc comment says a SwiftUI `Menu`'s rows cannot be asserted on, which
/// is why the type exists at all — and then nothing asserted on the type either. These are
/// the rules it claims to hold.
final class DepartmentMenuTests: XCTestCase {

    private func dept(_ key: String) throws -> Department {
        try XCTUnwrap(DepartmentCatalog.find(key), "no department '\(key)' in the catalog")
    }

    /// The row shows the pet that signs the reply. Both sides now read the same
    /// unconditional resolver, so this cannot drift.
    func testRowTitleNamesThePetThatSignsTheReply() throws {
        let mkt = try dept("mkt")
        let pet = try XCTUnwrap(DepartmentMenu.pet(for: mkt))
        XCTAssertEqual(pet, DepartmentCompanions.companionId(for: "mkt"))
        let name = try XCTUnwrap(PetCharacter.all[pet]?.name)
        XCTAssertEqual(DepartmentMenu.rowTitle(mkt), "\(name) · Marketing")
    }

    /// Picking a row and reading the button back must not look like two choices.
    func testArmedLabelMatchesTheRow() throws {
        for dep in DepartmentMenu.rosterOrder {
            XCTAssertEqual(DepartmentMenu.armedLabel(dep), DepartmentMenu.rowTitle(dep),
                           "\(dep.name)'s button and row disagree")
        }
    }

    /// A department with no pet shows the department alone — the row never promises a pet
    /// that will not appear. Product is that department today.
    func testUnmappedDepartmentShowsItsNameAlone() throws {
        let product = try dept("product")
        XCTAssertNil(DepartmentMenu.pet(for: product))
        XCTAssertEqual(DepartmentMenu.rowTitle(product), "Product")
    }

    /// Product is filtered out of the menu: `dept-product.png` is a byte-identical copy of
    /// `dept-eng.png`, so a row for it would wear Engineering's identity.
    func testRosterOrderExcludesProduct() {
        XCTAssertFalse(DepartmentMenu.rosterOrder.contains { $0.key == "product" })
    }
}
```

In `codepetTests/TwoModeHeroTests.swift`, replace lines 429-437 (`testEveryRosterDepartmentHasAPetToSpeakForIt`, its doc comment included) with:

```swift
    /// Eight departments, every one with a voice. Product is deliberately absent —
    /// it has placeholder art and no pet, which is the launch-blocking gap.
    func testEveryRosterDepartmentHasAPetToSpeakForIt() {
        for dep in DepartmentCatalog.roster {
            let pet = DepartmentCompanions.companionId(for: dep.key)
            XCTAssertNotNil(pet, "\(dep.name) would show the host orb and no name")
            XCTAssertNotNil(PetCharacter.all[pet ?? ""],
                            "\(dep.name) maps to '\(pet ?? "")', which is not a character")
        }
        XCTAssertFalse(DepartmentCatalog.roster.contains { $0.key == "product" })
    }
```

and replace lines 439-448 (`testTheCastIsSmallerThanTheRoster`, its doc comment included) with:

```swift
    /// Five pets cover eight departments. That is the design (nova takes Marketing
    /// and Sales, sage Finance and Support, glitch Operations and Legal) — if this
    /// ever became 1:1 the roster would be claiming eight characters we do not have.
    func testTheCastIsSmallerThanTheRoster() {
        let pets = Set(DepartmentCatalog.roster.compactMap {
            DepartmentCompanions.companionId(for: $0.key)
        })
        XCTAssertLessThan(pets.count, DepartmentCatalog.roster.count)
        XCTAssertEqual(pets, ["crash", "luna", "nova", "sage", "glitch"],
                       "five voices across eight departments")
    }
```

Note the expected set is still the CURRENT cast — Task 1 changes no mapping. Task 2 changes both this set and the comment above it.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Developer/codepet && xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DepartmentCompanionsTests \
  -only-testing:codepetTests/DepartmentMenuTests 2>&1 | tail -25
```

Expected: FAIL at compile — `error: incorrect argument label in call` / `extra argument 'host' in call` from `DepartmentMenuTests` calling `pet(for:)` and `rowTitle(_:)` without `host:`.

- [ ] **Step 3: Delete `specialistId` and rewrite the doc comment it leaves behind**

In `codepet/Models/DepartmentCompanions.swift`, delete lines 22-37 — the whole `/// The pet that visibly takes over…` doc comment through the closing brace of `specialistId` — and replace with nothing. Then replace the type's own header comment (lines 3-7, `/// Maps each business department…` through `enum DepartmentCompanions {`) with:

```swift
/// Maps each business department to the pet that speaks for it. Casting is by domain fit
/// (see PetCharacter.domain) and is freely editable — nothing depends on the exact cast.
///
/// **There is no host entry, and no host rule.** Codepet is the host: a general turn carries
/// no `companionId` and `CopilotChatView.headerName` signs it `CodepetBrand.name`. The pets are
/// department characters and nothing else.
///
/// This map used to be read through `specialistId(for:host:)`, which returned nil whenever a
/// department's pet WAS the founder's own companion — "announcing a handoff to yourself says
/// nothing". That premise assumed the host signs replies with a pet's name. It does not, and
/// never did. What the rule actually did was hide attribution from exactly one founder per
/// department, and once `byte` took Engineering — with every founder's companion defaulting to
/// `byte` since the onboarding picker was removed on 14 Aug — it would have hidden Engineering's
/// pet from everybody.
///
/// The invariant it was written to protect survives without it, more strongly: a chip promising
/// a pet that the send then declines to hand off to is a lie the founder can see in one tap, and
/// with one unconditional resolver the chip and the send have no input on which they can differ.
enum DepartmentCompanions {
```

- [ ] **Step 4: Drop `host` from `DepartmentMenu`**

In `codepet/Models/DepartmentMenu.swift`, replace lines 4-11 (the type doc comment) and lines 19-38 (`pet`, `rowTitle`, `armedLabel` and their comments) so the file reads:

```swift
/// The contents of the composer's departments menu — spec §4.
///
/// **Why this is a type and not just view code.** A SwiftUI `Menu`'s rows cannot be
/// asserted on from a test, and the one rule this control must never break is
/// testable: the pet a row shows has to be the pet that signs the reply. That rule
/// has exactly one home, `DepartmentCompanions.companionId`, which is also what
/// `CompanyStore.actingSpecialist` calls on send. This type reads it and nothing
/// else, so the menu and the answer cannot disagree. `DepartmentMenuTests` holds it.
```

```swift
    /// The pet this row summons, or nil for a department with no pet.
    /// Delegates — see the type comment for why it must.
    static func pet(for department: Department) -> String? {
        DepartmentCompanions.companionId(for: department.key)
    }

    /// `Byte · Engineering`. The pet's name leads because that is the order the
    /// reply is signed in (`CopilotChatView.headerName` renders `Nova · Marketing`),
    /// so the row and the answer read alike. No mapped pet means the department
    /// alone — the row never promises a pet that will not appear.
    static func rowTitle(_ department: Department) -> String {
        guard let id = pet(for: department),
              let name = PetCharacter.all[id]?.name else { return department.name }
        return "\(name) · \(department.name)"
    }

    /// The armed button's own label. Same string as the row, so picking a row and
    /// reading the button back cannot look like two different choices.
    static func armedLabel(_ department: Department) -> String {
        rowTitle(department)
    }
```

- [ ] **Step 5: Update the three call sites**

In `codepet/Managers/CompanyStore.swift`, replace lines 852-863 (the `actingSpecialist` doc comment and body):

```swift
    /// The pet to bring in for this turn, if a department is in focus — from the explicit
    /// chip, else a department named in the text. Returns nil when no department applies or
    /// it has no mapped pet.
    private func actingSpecialist(text: String, department: Department?) -> (companionId: String, deptName: String)? {
        guard let deptKey = actingDeptKey(text: text, department: department),
              let dept = DepartmentCatalog.find(deptKey),
              let companionId = DepartmentCompanions.companionId(for: deptKey)
        else { return nil }
        return (companionId, dept.name)
    }
```

Then in the doc comment for `actingDeptKey` immediately below it, replace the paragraph beginning `/// `actingSpecialist` returns nil in two very different situations:` through `/// answer got no expertise. Who speaks and what they know are now resolved separately.` with:

```swift
    /// `actingSpecialist` and this used to be one function, and the fusion cost the answer: a
    /// founder whose companion was Nova asked Marketing a question and the model was told
    /// nothing about marketing, because the department was read off a nil that meant "no
    /// handoff to announce" rather than "no department". The host rule that produced that nil
    /// is gone as of 26 Aug, but who speaks and what they know stay separately resolved — the
    /// wire fields are separate too (`companion_id` vs `dept_key`), and re-fusing them would
    /// reintroduce the same class of bug the next time a department has no pet. Product is one.
```

In `codepet/Views/Copilot/DepartmentRoster.swift`, replace lines 67-69:

```swift
    private func chip(_ dep: Department) -> some View {
        let on = selected?.key == dep.key
        let pet = DepartmentCompanions.companionId(for: dep.key)
```

The `CompanionOrb` fallback below it stays exactly as it is — every roster department maps to a pet, so the branch is unreachable from the roster today, but it is the correct rendering for a department with no pet and Product is exactly that the moment it is unfiltered. Update only its comment, from `// No mapped companion — the host answers. Show the orb rather` to:

```swift
                    // No mapped pet — Codepet answers. Show the orb rather
```

In `codepet/Views/Copilot/ChatComposer.swift`, make four edits:

Delete line 333 entirely (`let host = companyStore.company.companionId`) — it has no other readers.

Line 346: `Button { selectedDept = dep } label: { deptRow(dep, host: host) }` → `Button { selectedDept = dep } label: { deptRow(dep) }`

Line 358: `let pet = DepartmentMenu.pet(for: dep, host: host),` → `let pet = DepartmentMenu.pet(for: dep),`

Line 362: `Text(armed.map { DepartmentMenu.armedLabel($0, host: host) }` → `Text(armed.map { DepartmentMenu.armedLabel($0) }`

Lines 415-421, the `deptRow` signature and its two calls:

```swift
    @ViewBuilder private func deptRow(_ dep: Department) -> some View {
        let on = selectedDept?.key == dep.key
        let title = DepartmentMenu.rowTitle(dep)
        if on {
            Label(title, systemImage: "checkmark")
        } else if let pet = DepartmentMenu.pet(for: dep),
                  let sprite = PetMenuIcon.image(pet) {
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd ~/Developer/codepet && xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DepartmentCompanionsTests \
  -only-testing:codepetTests/DepartmentMenuTests \
  -only-testing:codepetTests/TwoModeHeroTests \
  -only-testing:codepetTests/CompanyStoreChatTests 2>&1 | tail -25
```

Expected: `** TEST SUCCEEDED **`.

If `CompanyStoreChatTests` fails, read the failure before changing anything: it exercises `actingSpecialist`, and a founder-companion-specific assertion there is the deleted rule showing up in a second place. Update it the same way — assert the pet IS returned rather than that it is suppressed.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet
git add codepet/Models/DepartmentCompanions.swift codepet/Models/DepartmentMenu.swift \
  codepet/Managers/CompanyStore.swift codepet/Views/Copilot/DepartmentRoster.swift \
  codepet/Views/Copilot/ChatComposer.swift codepetTests/DepartmentCompanionsTests.swift \
  codepetTests/DepartmentMenuTests.swift codepetTests/TwoModeHeroTests.swift
git commit -F - <<'MSG'
Delete the host-shadow rule: one unconditional resolver for who speaks

specialistId(for:host:) returned nil whenever a department's pet WAS the
founder's own companion, on the reasoning that announcing a handoff to
yourself says nothing. That assumed the host signs replies with a pet's
name. It does not: headerName returns CodepetBrand.name whenever
message.companionId is nil, which is every general turn.

What the rule actually did was hide attribution from one founder per
department -- and it was about to hide Engineering's pet from everybody,
since byte takes Engineering next and every founder's companion has
defaulted to byte since the onboarding picker was removed on 14 Aug.

Nothing downstream depended on it. companyChatCore already splits
companion_id from dept_key, and actingDeptKey is already separate from
actingSpecialist, so suppression only ever hid attribution, never
expertise.

The invariant survives more strongly: with one unconditional resolver the
chip and the send have no input on which they can differ. DepartmentMenu
gets its first tests -- its doc comment has claimed since it was written
that this rule is testable, and nothing was testing it.

Consequence, deliberate: a founder who picks Nova in Settings now sees
"Nova - Marketing" sign a Marketing reply, where the turn used to stay
with the host. The department is the new information in that header.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 2: Recast Engineering and Finance

Two entries in the map. Safe only because Task 1 removed the rule that would have blanked Engineering.

**Files:**
- Modify: `codepet/Models/DepartmentCompanions.swift` (the `map` literal — `eng` and `fin` lines)
- Test: `codepetTests/DepartmentCompanionsTests.swift:17-19`, `codepetTests/TwoModeHeroTests.swift` (the `testTheCastIsSmallerThanTheRoster` set), `codepetTests/PetMenuIconTests.swift:27`

**Interfaces:**
- Consumes: `DepartmentCompanions.companionId(for:)` from Task 1 (unconditional, no `host:`).
- Produces: `companionId(for: "eng") == "byte"`, `companionId(for: "fin") == "crash"`. Task 3 relies on `"byte"` being a roster pet when it renames the character.

- [ ] **Step 1: Write the failing tests**

In `codepetTests/DepartmentCompanionsTests.swift`, replace `testCompanionIdForEng` (lines 17-19) with:

```swift
    /// Byte takes Engineering — the department whose subject is the product being built,
    /// and the one whose founder-facing traffic is heaviest. This is the assertion that
    /// fails if a host rule is ever reintroduced: byte is also every founder's default
    /// companion, so a host rule would resolve this to nil for essentially everybody.
    func testCompanionIdForEng() {
        XCTAssertEqual(DepartmentCompanions.companionId(for: "eng"), "byte")
    }

    /// Crash takes Finance, which frees Sage to speak for Support alone.
    func testCompanionIdForFin() {
        XCTAssertEqual(DepartmentCompanions.companionId(for: "fin"), "crash")
    }

    /// Sage no longer doubles up. Nova (Marketing + Sales) and Glitch (Operations + Legal)
    /// still do, and that is the design.
    func testSageSpeaksForSupportAlone() {
        let sages = DepartmentCatalog.roster
            .filter { DepartmentCompanions.companionId(for: $0.key) == "sage" }
            .map(\.key)
        XCTAssertEqual(sages, ["support"])
    }
```

In `codepetTests/TwoModeHeroTests.swift`, update `testTheCastIsSmallerThanTheRoster` — the doc comment's count and the expected set:

```swift
    /// Six pets cover eight departments. That is the design (nova takes Marketing
    /// and Sales, glitch Operations and Legal) — if this ever became 1:1 the roster
    /// would be claiming eight characters we do not have.
    func testTheCastIsSmallerThanTheRoster() {
        let pets = Set(DepartmentCatalog.roster.compactMap {
            DepartmentCompanions.companionId(for: $0.key)
        })
        XCTAssertLessThan(pets.count, DepartmentCatalog.roster.count)
        XCTAssertEqual(pets, ["byte", "crash", "luna", "nova", "sage", "glitch"],
                       "six voices across eight departments")
    }
```

In `codepetTests/PetMenuIconTests.swift`, replace line 26-27 — the comment and the hardcoded list. It claims to be "every pet the roster can summon, per `DepartmentCompanions`" and is a copy that was already free to drift; derive it so the comment becomes true:

```swift
    /// Every pet the roster can summon, per `DepartmentCompanions`. DERIVED, not copied:
    /// this was a hardcoded list making the same claim, which recasting Engineering and
    /// Finance would have left wrong by one with nothing to catch it.
    private var pets: [String] {
        Set(DepartmentCatalog.roster.compactMap {
            DepartmentCompanions.companionId(for: $0.key)
        }).sorted()
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Developer/codepet && xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DepartmentCompanionsTests 2>&1 | tail -25
```

Expected: FAIL — `testCompanionIdForEng` reports `XCTAssertEqual failed: ("crash") is not equal to ("byte")`, and `testCompanionIdForFin` reports `("sage") is not equal to ("crash")`.

- [ ] **Step 3: Recast the two entries**

In `codepet/Models/DepartmentCompanions.swift`, replace the `eng` and `fin` lines of the `map` literal. The trailing comments are the map's record of WHY the cast is what it is, so they are rewritten, not carried over — leaving Sage's "real data, not vibes" on Crash's entry would make the file lie:

```swift
        "eng": "byte",       // data flow, state, algorithms — and the product IS software
        "design": "luna",    // Designer (UX/UI)
        "mkt": "nova",       // Firestarter — launches, energy
        "sales": "nova",     // growth energy (shares the marketing persona)
        "support": "sage",   // calm, patient, methodical
        "fin": "crash",      // runway is a shipping constraint, not an essay
        "ops": "glitch",     // DevOps — automation
        "legal": "glitch",   // rules & edges
```

Note on the `fin` line: Crash is "The Brawler Bug" and Finance previously belonged to Sage the analyst, so this is a weak persona fit on its face. It was raised and decided (see the spec, §1). The comment says what Crash brings rather than repeating Sage's reasoning.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd ~/Developer/codepet && xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/DepartmentCompanionsTests \
  -only-testing:codepetTests/DepartmentMenuTests \
  -only-testing:codepetTests/TwoModeHeroTests \
  -only-testing:codepetTests/PetMenuIconTests 2>&1 | tail -25
```

Expected: `** TEST SUCCEEDED **`. `PetMenuIconTests` passing confirms `char-byte.imageset` renders at menu-icon size — Byte's sprite already exists, so no asset work is needed.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add codepet/Models/DepartmentCompanions.swift codepetTests/DepartmentCompanionsTests.swift \
  codepetTests/TwoModeHeroTests.swift codepetTests/PetMenuIconTests.swift
git commit -F - <<'MSG'
Byte takes Engineering, Crash takes Finance

The roster showed eight departments and no Byte, because byte was held back
as the host/generalist so it had somebody to hand off TO. That was coherent
while the founder picked a companion at onboarding; the picker was removed
14 Aug, so every founder hosts byte and the slot cost a character for
nothing -- while Engineering, the department whose subject is the product
being built, was voiced by Crash and Byte spoke for nothing.

Six voices across eight departments now. Sage drops to Support alone; Nova
and Glitch still double up, which is the design.

The map's trailing comments are its record of why the cast is what it is, so
the two that moved are rewritten rather than carried over. Finance's old
line quoted Sage's own persona copy ("real data, not vibes") and would have
been a lie attached to Crash.

PetMenuIconTests held a hardcoded pet list whose comment claimed it was
"every pet the roster can summon, per DepartmentCompanions". It was not, and
this change would have left it wrong by one with nothing to catch it. Now
derived.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 3: Rename the character to "Byte", and fix every surface that said "Codepet" by accident

`PetCharacter.all["byte"].name` is `"Codepet"` — the same string as `CodepetBrand.name`. Now that Byte speaks for Engineering, a handed-off reply would render `"Codepet · Engineering"` beside a general reply's `"Codepet"`, making the product's voice and one department indistinguishable.

Four surfaces render the host's name by reading `company.companionId` and only say "Codepet" because byte happens to be named that. **They must change in this same commit** — the rename alone turns the empty-state greeting into "Byte".

**Files:**
- Modify: `codepet/Models/Character.swift:36`
- Modify: `codepet/Views/Copilot/ChatEmptyState.swift:150-152`
- Modify: `codepet/Views/Copilot/CopilotChatView.swift:2029` and delete `1203-1205`
- Modify: `codepet/Models/DepartmentMenu.swift` (`anyoneLabel`)
- Modify: `codepetTests/SecondBrainDataTests.swift:49-50` (a stale comment only — see Step 6)
- Modify: `codepet/Models/PetVoice.swift:55` (comment only)
- Create: `codepetTests/HostIdentityTests.swift`

**Interfaces:**
- Consumes: `DepartmentCompanions.companionId(for: "eng") == "byte"` from Task 2.
- Produces: `PetCharacter.all["byte"]!.name == "Byte"`, `PetCharacter.all["byte"]!.id == "byte"`. `ChatEmptyState.hostName` ceases to exist.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/HostIdentityTests.swift`:

```swift
import XCTest
@testable import codepet

/// Codepet is the host; the pets are department characters. Two names that must not merge.
///
/// These exist because renaming the `byte` character is the kind of change that half-lands:
/// three surfaces resolved the host's name through `company.companionId` and rendered
/// "Codepet" only because byte happened to be called that. Renaming byte without touching
/// them turns the empty-state greeting into "Byte", and nothing else would have complained.
@MainActor
final class HostIdentityTests: XCTestCase {

    /// The character got its own name back so "Codepet · Engineering" cannot appear.
    func testByteIsNamedByte() throws {
        let byte = try XCTUnwrap(PetCharacter.all["byte"])
        XCTAssertEqual(byte.name, "Byte")
        XCTAssertNotEqual(byte.name, CodepetBrand.name,
                          "the product's voice and a department's voice would share a name")
    }

    /// The id is a Firestore key — `actor:'byte'`, `companionId`, and `char-byte` all read it.
    /// Only the display name moved.
    func testByteKeepsItsId() throws {
        let byte = try XCTUnwrap(PetCharacter.all["byte"])
        XCTAssertEqual(byte.id, "byte")
        XCTAssertEqual(byte.imageName, "char-byte")
        XCTAssertTrue(PetCharacter.starters.contains("byte"))
    }

    /// Byte now speaks for Engineering, so the header reads "Byte · Engineering".
    func testEngineeringSignsAsByte() throws {
        let pet = try XCTUnwrap(DepartmentCompanions.companionId(for: "eng"))
        let eng = try XCTUnwrap(DepartmentCatalog.find("eng"))
        XCTAssertEqual(DepartmentMenu.rowTitle(eng), "Byte · Engineering")
        XCTAssertEqual(PetCharacter.all[pet]?.name, "Byte")
    }

    /// The composer menu's "no department" row names the host. It used to say
    /// "Anyone — byte routes it", which after the recast would tell the founder that
    /// Engineering's pet routes everything.
    func testTheAnyoneRowNamesCodepetNotAPet() {
        for lang in [AppLanguage.en, AppLanguage.vi] {
            let label = DepartmentMenu.anyoneLabel(lang)
            XCTAssertTrue(label.contains(CodepetBrand.name),
                          "\(lang) label '\(label)' does not name the host")
            XCTAssertFalse(label.lowercased().contains("byte"),
                           "\(lang) label '\(label)' names a department pet as the router")
        }
    }
}
```

**On testing the host surfaces — read this before writing the test.** The obvious test here is a trap. Asserting `PetCharacter.all["byte"]?.name == "Byte"` alongside `CodepetBrand.name == "Codepet"` passes whether or not `ChatEmptyState` is fixed, and the project's working agreement is explicit: *a test that passes with and without the code it protects is not protecting anything.*

`ChatEmptyState.hostName` is `private` inside a generic `View` with an `@EnvironmentObject`, so it cannot be read from a test without restructuring the view. The fix is to remove the thing that could be reverted rather than to test around it: `hostName` becomes a one-line constant with a single caller, so Step 4 **deletes it** and passes `CodepetBrand.name` at the call site. There is then no site to revert.

What IS testable is the function that value flows into. `BeaconOffer.offer` interpolates the host into founder-facing copy, and it is a pure static. Add to `codepetTests/HostIdentityTests.swift`:

```swift
extension HostIdentityTests {
    /// The hero's beacon card says who can and cannot do a task, and it names the host in
    /// prose: "This one needs you — Codepet can only prepare it…". The product is what
    /// speaks there, so the name must be the brand, never a pet.
    ///
    /// This is the reachable half of the guard. Its other half is structural: `ChatEmptyState`
    /// no longer HAS a `hostName` — it passes `CodepetBrand.name` at the call site — so there
    /// is no resolved-from-companion value left to revert.
    func testTheBeaconNamesTheProductNotAPet() throws {
        // `who: .you` selects the one branch whose copy interpolates the host.
        let task = RoadmapTask(id: "t1", title: "Talk to five users",
                               detail: "", phase: .find, who: .you, dept: "eng")
        let offer = try XCTUnwrap(BeaconOffer.offer(for: task, in: [task],
                                                    host: CodepetBrand.name, language: .en))
        XCTAssertTrue(offer.detail.contains("Codepet"),
                      "the beacon detail '\(offer.detail)' does not name the host")
        XCTAssertFalse(offer.detail.contains("Byte"),
                       "a pet is claiming the product's line")
    }
}
```

`RoadmapTask.init` is `(id:title:detail:phase:who:dependsOn:done:drafted:dept:draft:)` with defaults from `dependsOn` onward, so the five leading arguments above are all that is required.

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd ~/Developer/codepet && xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/HostIdentityTests 2>&1 | tail -25
```

Expected: FAIL — `testByteIsNamedByte` reports `("Codepet") is not equal to ("Byte")`, and `testTheAnyoneRowNamesCodepetNotAPet` reports the en label names a department pet as the router.

- [ ] **Step 3: Rename the character**

In `codepet/Models/Character.swift`, line 36:

```swift
            id: "byte", name: "Byte", badge: "The Chaotic Core",
```

- [ ] **Step 4: Point the four host surfaces at `CodepetBrand`**

`codepet/Views/Copilot/ChatEmptyState.swift` — **delete** `hostName` (lines 150-152) entirely:

```swift
    private var hostName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
```

and pass the brand at its one call site, line 79, inside `heroBody`:

```swift
            if let offer = BeaconOffer.offer(for: beaconTask, in: beaconTasks,
                                             host: CodepetBrand.name, language: lang) {
```

Deleting rather than rewriting is deliberate. As a one-line constant `hostName` would be a
computed property that reads nothing, whose only purpose is to be a place someone can later
re-introduce a companion lookup — and it cannot be covered by a test, being `private` on a
generic `View`. Removing it removes the reversion target.

`codepet/Views/Copilot/CopilotChatView.swift`, line 2029 — inside `whatItDid`. A run with no specialist is the product's own work:

```swift
        let who = PetCharacter.all[message.companionId ?? ""]?.name ?? CodepetBrand.name
```

`codepet/Views/Copilot/CopilotChatView.swift`, lines 1203-1205 — delete `companionName` entirely. Nothing reads it; only the adjacent `companionAccent` is used. It is one of the sites that would have flipped to "Byte", and deleting something with no readers is cheaper than fixing it:

```swift
    private var companionName: String {
        PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet"
    }
```

- [ ] **Step 5: Fix the user-facing copy that names the host "byte"**

`codepet/Models/DepartmentMenu.swift` — replace `anyoneLabel` and its doc comment:

```swift
    /// The off state, made nameable. Deselecting used to be reachable only by
    /// clicking an armed chip a second time; letting Codepet route it is a real choice
    /// and it should be a row you can pick, with a checkmark saying it is what you
    /// have.
    ///
    /// Says "Codepet", not a pet's name: routing is the host's job. This read
    /// "byte routes it" until 26 Aug, which after byte took Engineering would have told
    /// the founder that Engineering's character routes everything. `anyoneDetail` below
    /// has said "Let Codepet pick who answers" the whole time — the two lines about one
    /// control disagreed, and the recast is what made it visible.
    static func anyoneLabel(_ lang: AppLanguage) -> String {
        lang == .vi ? "Ai cũng được — Codepet tự chọn" : "Anyone — Codepet routes it"
    }
```

`codepet/Models/PetVoice.swift`, line 55 — comment only, no behavior change. Byte stays on the `default` branch, which is also the unknown-pet fallback, so its speaking voice is unchanged:

```swift
        default:
            // Byte, and the fallback for an unknown pet: the overlay must never be
            // voiceless. Byte speaks for Engineering, the most-heard department, so the
            // most listenable voice belongs here either way.
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
cd ~/Developer/codepet && xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/HostIdentityTests \
  -only-testing:codepetTests/DepartmentMenuTests \
  -only-testing:codepetTests/MessageTranscriptTests \
  -only-testing:codepetTests/SecondBrainDataTests \
  -only-testing:codepetTests/VoiceComposerTests 2>&1 | tail -25
```

Expected: `** TEST SUCCEEDED **`.

`SecondBrainDataTests` is in this list to prove a **non**-change. `SecondBrainData.companionName`
was in the spec's blast-radius list and was withdrawn (§5 [A2]): `SecondBrainPanel.swift:45`
renders it under the label **"Companion"**, which is `company.companionId` doing its own job, not
the host. Leave the code alone. Both assertions in `testCompanionNameResolves` still pass — only
its comment (lines 49-50) goes stale, because it excludes byte as a test case on the grounds that
byte's name "literally IS 'Codepet'". Update it:

```swift
    func testCompanionNameResolves() {
        // Both are real hits distinguishable from the `?? "Codepet"` fallback — byte included,
        // since it was renamed to "Byte" on 26 Aug. This catches a broken lookup.
        XCTAssertEqual(SecondBrainData(company: company(companionId: "byte")).companionName, "Byte")
        XCTAssertEqual(SecondBrainData(company: company(companionId: "nova")).companionName, "Nova")
        XCTAssertEqual(SecondBrainData(company: company(companionId: "nope")).companionName,
                       "Codepet")
    }
```

`MessageTranscriptTests` is in this list because `MessageTranscript.markdown(_:speaker:lang:)` is handed `headerName` — if any transcript fixture asserts the literal `"Codepet"` for a message that carries `companionId: "byte"`, it now expects `"Byte"` and must be updated to match. That is a correct change, not a regression: the transcript names who spoke.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet
git add codepet/Models/Character.swift codepet/Views/Copilot/ChatEmptyState.swift \
  codepet/Views/Copilot/CopilotChatView.swift codepet/Models/DepartmentMenu.swift \
  codepet/Models/PetVoice.swift codepetTests/HostIdentityTests.swift \
  codepetTests/SecondBrainDataTests.swift
git commit -F - <<'MSG'
Byte gets its name back; the host says Codepet on purpose

PetCharacter.all["byte"].name was "Codepet", the same string as
CodepetBrand.name. With Byte now speaking for Engineering, a handed-off
reply would have rendered "Codepet - Engineering" beside a general reply's
"Codepet", making the product's own voice and one department
indistinguishable -- precisely the failure headerName's comment describes
and reverses.

The id stays "byte", so nothing in Firestore moves.

The rename could not land alone. Surfaces that resolved the host's name
through company.companionId rendered "Codepet" only because byte happened
to be called that; renaming byte turns the empty-state greeting into "Byte"
and nothing else would have complained.

ChatEmptyState.hostName is deleted, not rewritten -- as a constant it would
be a property reading nothing whose only purpose is to be somewhere a
companion lookup can creep back in, and being private on a generic View it
cannot be covered by a test. Its one caller passes CodepetBrand.name.
CopilotChatView.companionName had no readers at all and is deleted too.

SecondBrainData.companionName was in the spec's list and is NOT changed:
SecondBrainPanel renders it under the label "Companion", which is
company.companionId doing its own job. The rule the mistake taught, since
this call shape appears at five sites: reading the companion is correct
wherever the surface means "the founder's companion" and wrong wherever it
means "who is speaking right now". Read the label before deciding.

DepartmentMenu.anyoneLabel is the only user-facing string in the set: it
said "Anyone -- byte routes it", which after the recast would tell the
founder that Engineering's pet routes everything. Its own neighbour
anyoneDetail has said "Let Codepet pick who answers" the whole time.

PetVoice keeps byte on the default branch -- same voice, corrected comment.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 4: Verify the whole target, then open the PR

Tasks 1-3 each ran four or five suites. That is not a verified branch — a `-only-testing:` run only proves what you pointed it at, and this change touches the chat header, the empty state, the composer, the roster, the run receipt and the transcript. The first full run after a stretch of targeted ones is where regressions surface.

**Files:** none modified unless the run finds something.

**Interfaces:**
- Consumes: all three commits from Tasks 1-3.

- [ ] **Step 1: Quit the app and confirm nothing holds the Firestore lock**

```bash
pgrep -fl codepet | grep -v pgrep
```

Expected: no output. If `codepet.app` is running it will kill the test host mid-run with a different victim each time, which reads exactly like a flaky regression. Quit it from the Dock — do NOT `pkill` without asking, a sibling session may be mid-build.

- [ ] **Step 2: Run the whole target into a result bundle**

```bash
cd ~/Developer/codepet && rm -rf /tmp/byte-eng.xcresult && \
xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath /tmp/byte-eng.xcresult 2>&1 | tail -5
```

Expected: exit 65 and `** TEST FAILED **`. **This is not a result.** A whole-target run exits 65 on a clean checkout — the XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates, and ~27 of ~970 tests never finish. Ignore the exit code entirely and go to Step 3.

- [ ] **Step 3: Count with `xcresulttool`, which is the only trustworthy reading**

```bash
xcrun xcresulttool get test-results summary --path /tmp/byte-eng.xcresult
```

Expected: a `failedTests` count of 0, with `passedTests` in the ~940+ range. Any non-zero `failedTests` is a real regression from this branch — read the failing test names in the same output and fix before proceeding.

For a named failure, re-run just that suite to iterate:

```bash
cd ~/Developer/codepet && xcodebuild test -scheme codepet -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<FailingSuite> 2>&1 | tail -30
```

- [ ] **Step 4: Build the app target signed, so the branch is known to ship**

Tests compile the model layer; they do not prove the app target links. Sign it with the team — an adhoc build breaks the keychain:

```bash
cd ~/Developer/codepet && xcodebuild build -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Push and open a draft PR**

Pushing a branch runs NOTHING in CI — the workflow triggers on pull requests, so a pushed branch with no PR looks green while having run zero tests. Open the PR, even as a draft.

```bash
cd ~/Developer/codepet && git push -u origin feat/byte-engineering-cast
gh pr create --draft --title "Byte takes Engineering; Codepet is the host" --body "$(cat <<'BODY'
Byte is on the roster for the first time. It speaks for Engineering, Crash moves to Finance, and Codepet is the host of general conversation.

Spec: `docs/superpowers/specs/2026-08-26-byte-engineering-department-design.md`
Plan: `docs/superpowers/plans/2026-08-26-byte-engineering-cast.md`

### Three commits

1. **Delete the host-shadow rule.** `specialistId(for:host:)` suppressed a pet whenever it was the founder's own companion. Its premise never held — `headerName` signs a general reply `CodepetBrand.name`, never a pet name — and since every founder's companion defaults to `byte`, it was about to hide Engineering's pet from everybody. `DepartmentMenu` gets its first tests.
2. **Recast.** `eng` → `byte`, `fin` → `crash`. Six voices across eight departments.
3. **Rename `byte` to "Byte"** and fix the four surfaces that rendered "Codepet" only because byte was named that — including `anyoneLabel`, which told the founder "byte routes it".

### Deliberate behavior change

A founder who picks Nova in Settings now sees **"Nova · Marketing"** sign a Marketing reply, where that turn used to stay with the host. The department is the new information in that header; the suppressed version threw it away.

### Verification

- Whole target via `xcresulttool get test-results summary` — not the exit code, which is 65 on a clean checkout for unrelated toolchain reasons.
- Signed app-target build succeeds.
- **Not verified on screen.** Screen Recording is denied here, so the roster showing Byte · Engineering and the composer's "Anyone — Codepet routes it" row need a human look.

### Out of scope

Product still has no pet and `dept-product.png` is still md5-identical to `dept-eng.png`, which is why the roster shows eight of nine departments. Still launch-blocking, untouched here.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

- [ ] **Step 6: Hand off the visual check**

Screen Recording is denied in this environment, so native UI cannot be screenshotted — green tests are not a visual verification and must not be reported as one. Ask Mona one specific question:

> On the empty chat screen, does the roster now show **Byte · Engineering** as the first chip, and does the composer's departments menu say **"Anyone — Codepet routes it"**?

---

## Notes for the implementer

**Read the spec before Task 1.** This plan executes it; the spec carries why each piece is shaped the way it is, and two of the decisions (Crash on Finance, and the Nova-in-Settings behavior change) were raised as objections and deliberately overruled. Re-litigating them mid-implementation wastes the decision.

**Do not "fix" the `CompanionOrb` fallback in `DepartmentRoster`.** After Task 2 every roster department maps to a pet, so the branch is unreachable and will look like dead code. It is the correct rendering for a department with no pet, and Product becomes exactly that the moment it is unfiltered.

**Do not touch `anyoneDetail`.** It has no callers, which is tempting, but removing it is unrelated to this work.

**If a test outside the listed suites fails,** read it before editing it. Assertions that encode the old cast (`"crash"` for Engineering) or the old host rule (a nil where a pet is now returned) should move. An assertion about something else has found a real regression.
