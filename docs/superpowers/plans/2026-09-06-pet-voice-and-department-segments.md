# Pet Voice and Department Segments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every departmental reply is headed by the pet that did the work; every ordinary reply carries no speaker row at all; and the day-one simulation reads as eight department chapters instead of one undifferentiated stream.

**Architecture:** One pure speaker rule (`CodepetBrand.header`) returns `String?` — nil when the product itself speaks — and the chat view renders the header row only when it is non-nil. A task's own department becomes a resolution source for a conversational turn's speaker, ahead of the existing keyword inference, because a task's department is a fact and a keyword match is an inference. Segmentation then falls out of the voice rule: a pet-authored message renders with its header, narration renders with none.

**Tech Stack:** Swift 5, SwiftUI, XCTest. macOS target 26.2. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

## Global Constraints

- **Never build a demo-only attribution path.** The demo gets pets by going through the same resolution the real chat uses. A parallel copy is how `MockChat.departmentReply` came to hardcode Codepet's board on the Murror demo.
- **Every founder-visible string is bilingual** (`AppLanguage.vi` / `.en`). An English-only credit line was a review finding on 5 Sep.
- **`MockFlowTests` (16/16) and `MockFlowScriptTests` (15/15) must stay green.** They pin the 24-beat tour, which renders through the same chat view. Red there is a real regression in the tour, not a test to adjust.
- **Build team-signed:** `DEVELOPMENT_TEAM=YL72VTKBR7`, `CODE_SIGN_IDENTITY="Apple Development"`, `-allowProvisioningUpdates`.
- **No running `codepet.app` while testing** — a live instance kills the `xcodebuild test` host. Count results only via `xcresulttool get test-results summary`.
- **Day one's measured duration must be recorded, never estimated.** Target ≤75s.

---

### Task 1: The speaker rule returns nil for the product's own voice

**Files:**
- Modify: `codepet/Models/CodepetBrand.swift`
- Test: `codepetTests/CodepetBrandTests.swift` (create if absent)

**Interfaces:**
- Produces: `CodepetBrand.header(companionId: String?, deptName: String?) -> String?` — `"Nova · Marketing"` when a pet and department are set, `"Nova"` when only a pet, `nil` when the product speaks.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CodepetBrandTests.swift
import XCTest
@testable import codepet

/// Who signs a reply. The nil case is the load-bearing one: the founder talks to the
/// product, so an ordinary turn carries no name — which is the only reason a pet's name
/// reads as different when it appears.
final class CodepetBrandTests: XCTestCase {

    func testAPetWithADepartmentSignsWithBoth() {
        XCTAssertEqual(CodepetBrand.header(companionId: "nova", deptName: "Marketing"),
                       "Nova · Marketing")
    }

    func testAPetWithNoDepartmentSignsWithItsNameAlone() {
        XCTAssertEqual(CodepetBrand.header(companionId: "nova", deptName: nil), "Nova")
        XCTAssertEqual(CodepetBrand.header(companionId: "nova", deptName: ""), "Nova")
    }

    /// NOT "Codepet". The product does not announce itself on every turn.
    func testTheProductsOwnVoiceHasNoHeader() {
        XCTAssertNil(CodepetBrand.header(companionId: nil, deptName: nil))
        XCTAssertNil(CodepetBrand.header(companionId: nil, deptName: "Marketing"))
    }

    /// An id no character claims is the product speaking, not a blank pet row.
    func testAnUnknownCompanionIdHasNoHeader() {
        XCTAssertNil(CodepetBrand.header(companionId: "nobody", deptName: "Marketing"))
    }

    /// `byte` is a department character named "Byte" since 26 Aug. If a caller ever
    /// attributes a general reply to the host companion, it must NOT read "Codepet" —
    /// it reads "Byte", which is the bug this rule exists to make visible rather than hide.
    func testByteIsACharacterNotTheProduct() {
        XCTAssertEqual(CodepetBrand.header(companionId: "byte", deptName: "Engineering"),
                       "Byte · Engineering")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodepetBrandTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates
```
Expected: FAIL to compile — `type 'CodepetBrand' has no member 'header'`.

- [ ] **Step 3: Write minimal implementation**

Add to `codepet/Models/CodepetBrand.swift`, below `speakerName`:

```swift
    /// The header a message shows, or nil when the product itself is speaking.
    ///
    /// **nil rather than "Codepet".** The founder talks to the product, so it does not
    /// announce itself on every turn. A pet's name is what makes the moment it works read as
    /// different — and it only does that if the ordinary turn carries no name at all. Founder
    /// call, 6 Sep, after watching every day-one reply sign itself "Codepet".
    ///
    /// Distinct from `speakerName`, which must always yield a word: the transcript export names
    /// a speaker even for an ordinary turn. This one answers "does a row render", which is a
    /// different question and is allowed to say no.
    static func header(companionId: String?, deptName: String?) -> String? {
        guard let id = companionId, let pet = PetCharacter.all[id] else { return nil }
        guard let dept = deptName, !dept.isEmpty else { return pet.name }
        return "\(pet.name) · \(dept)"
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/CodepetBrand.swift codepetTests/CodepetBrandTests.swift
git commit -m "feat(chat): the product's own voice signs nothing"
```

---

### Task 2: The chat view renders no header row for an ordinary turn

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift:1366-1372` (`headerName`), `:1664` (transcript copy), `:2190-2201` (header row)
- Test: `codepetTests/CopilotChatHeaderTests.swift` (create)

**Interfaces:**
- Consumes: `CodepetBrand.header(companionId:deptName:) -> String?` from Task 1.
- Produces: nothing new. `headerName` becomes `String?` internally.

- [ ] **Step 1: Write the failing test**

`headerName` is `private` on a SwiftUI view and cannot be reached from a test. Assert the rule one level down — against the same function the view now calls, over the real messages the day-one script produces — so the test fails if the view is ever rewired to a different rule.

```swift
// codepetTests/CopilotChatHeaderTests.swift
import XCTest
@testable import codepet

/// The header the chat view puts above a reply, asserted through the shared rule rather
/// than through the view (`headerName` is private to a SwiftUI view and unreachable).
final class CopilotChatHeaderTests: XCTestCase {

    private func header(_ m: CopilotMessage) -> String? {
        CodepetBrand.header(companionId: m.companionId, deptName: m.deptName)
    }

    private func reply(companionId: String? = nil, deptName: String? = nil) -> CopilotMessage {
        CopilotMessage(role: .companion, text: "x",
                       companionId: companionId, deptName: deptName)
    }

    func testASpecialistReplyIsHeadedWithPetAndDepartment() {
        XCTAssertEqual(header(reply(companionId: "sage", deptName: "Support")), "Sage · Support")
    }

    func testAnOrdinaryReplyHasNoHeader() {
        XCTAssertNil(header(reply()))
    }

    /// The regression this whole change exists to prevent: no reply anywhere reads "Codepet".
    func testNoReplyIsEverHeadedCodepet() {
        let cases = [reply(), reply(companionId: "nova", deptName: "Marketing"),
                     reply(companionId: "byte", deptName: "Engineering"), reply(deptName: "Legal")]
        for m in cases {
            XCTAssertNotEqual(header(m), "Codepet", "no reply may sign itself with the product name")
        }
    }
}
```

**Founder decision, 6 Sep — this task also carries a test that can actually fail.** The four above
pass the moment Task 1 lands, and `CLAUDE.md` is explicit: *"If a test passes with and without the
code it protects, it is not protecting anything."* Add the following to the same file **after Task 4
lands** (it depends on `.petAsks`), and note it in the ledger so it is not forgotten:

```swift
    /// Goes red if a department stops attributing its message — the guard the four rule-tests
    /// above cannot provide, because they assert a pure function that is already correct.
    /// The SwiftUI row itself stays verified on screen; a unit test cannot reach it.
    func testEveryPetAskedQuestionResolvesToAPetHeader() {
        for b in DayOneScript.beats {
            guard case let .petAsks(deptKey) = b.intent else { continue }
            guard let companionId = DepartmentCompanions.companionId(for: deptKey),
                  let dept = DepartmentCatalog.find(deptKey) else {
                return XCTFail("\(deptKey) cannot be attributed at all")
            }
            let h = CodepetBrand.header(companionId: companionId, deptName: dept.name)
            XCTAssertNotNil(h, "\(deptKey)'s question would render with no header")
            XCTAssertNotEqual(h, "Codepet", "\(deptKey)'s question would be signed by the product")
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CopilotChatHeaderTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates
```
Expected: PASS if Task 1 landed. **This is expected and is not a reason to skip the task** — the test guards the rule; the view rewiring below is what makes the rule reach the screen. Verify the view change by Step 6's on-screen check, not by this test going red.

- [ ] **Step 3: Make `headerName` optional**

Replace `codepet/Views/Copilot/CopilotChatView.swift:1366-1372`:

```swift
    private var headerName: String? {
        CodepetBrand.header(companionId: message.companionId, deptName: message.deptName)
    }
```

Delete the old `guard let id = message.companionId … return pet.name` body. Keep the doc comment above it and add one line: `nil means the product is speaking and no row renders.`

- [ ] **Step 4: Fix the two call sites**

At `:1664`, the transcript export must still name a speaker:

```swift
                copy(MessageTranscript.markdown(message, speaker: headerName ?? CodepetBrand.name, lang: lang), setting: $copiedMarkdown)
```

At `:2190-2201`, render the row conditionally:

```swift
            VStack(alignment: .leading, spacing: ChatRhythm.nameToProse) {
                if let headerName {
                    HStack(spacing: 8) {
                        CompanionAvatar(companionId: message.companionId, size: 22)
                        Text(headerName)
                            .font(CodepetTheme.inter(12.5, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                    }
                }
                VStack(alignment: .leading, spacing: ChatRhythm.proseToAction) {
                    prose(message.text)
                    inlineActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
```

- [ ] **Step 5: Run the affected suites**

Run:
```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CopilotChatHeaderTests \
  -only-testing:codepetTests/CodepetBrandTests \
  -only-testing:codepetTests/MockFlowTests \
  -only-testing:codepetTests/MockFlowScriptTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates
```
Expected: PASS. `MockFlowTests` 16/16 and `MockFlowScriptTests` 15/15 — if either drops, stop: the tour regressed.

- [ ] **Step 6: Verify on screen**

```bash
open -a "$(xcodebuild -scheme codepet -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2} / FULL_PRODUCT_NAME/{n=$2} END{print d"/"n}')" \
  --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
```
Type any question with no department in it. Expected: the reply renders as plain prose with **no orb and no name above it**. Before this task it read `● Codepet`.

- [ ] **Step 7: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift codepetTests/CopilotChatHeaderTests.swift
git commit -m "feat(chat): an ordinary reply carries no speaker row"
```

---

### Task 3: A task's department resolves a conversational turn's speaker

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift:781-784` (`sendChat` signature), `:912-917` (`actingSpecialist`), `:1593` (display message)
- Modify: `codepet/Demo/MockFlowPlayer.swift:285-290` (`.walkthroughFounderTask`)
- Test: `codepetTests/ChatSpeakerResolutionTests.swift` (create)

**Interfaces:**
- Consumes: `taskSpecialist(for: RoadmapTask) -> (companionId: String, deptName: String)?` — already exists at `CompanyStore.swift:1995`, currently `private`.
- Produces: `sendChat(_:language:department:founderAsk:convenesRoom:pinned:attachments:aboutTask:)` — new trailing parameter `aboutTask: RoadmapTask? = nil`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/ChatSpeakerResolutionTests.swift
import XCTest
@testable import codepet

/// Who speaks for a turn that is ABOUT a task but names no department.
///
/// This is the gap the founder photographed: "Walk me through: Talk to 12 people about being
/// lonely" carries no department chip and no department word, so keyword inference returns
/// nil and the reply signed itself "Codepet" — on a Marketing task.
@MainActor
final class ChatSpeakerResolutionTests: XCTestCase {

    private func task(id: String, dept: String?) -> RoadmapTask {
        var t = DemoProject.murror.tasks.first { $0.id == "mur-interviews" }!
        t.dept = dept
        return t
    }

    func testATaskResolvesItsDepartmentsPet() {
        let store = CompanyStore()
        let spec = store.speakerFor(task: task(id: "mur-interviews", dept: "mkt"), text: "Walk me through: Talk to 12 people", department: nil)
        XCTAssertEqual(spec?.companionId, "nova")
        XCTAssertEqual(spec?.deptName, "Marketing")
    }

    /// Task first: its department is a fact, a keyword match is an inference.
    func testTheTaskWinsOverAKeywordInTheText() {
        let store = CompanyStore()
        let spec = store.speakerFor(task: task(id: "mur-stack", dept: "eng"), text: "ask marketing about this", department: nil)
        XCTAssertEqual(spec?.companionId, "byte", "the task's own department decides, not the word in the text")
    }

    /// A task with no department falls through to nil — the headerless state, not a "Codepet" row.
    func testATaskWithNoDepartmentYieldsNoSpeaker() {
        let store = CompanyStore()
        XCTAssertNil(store.speakerFor(task: task(id: "x", dept: nil), text: "hello", department: nil))
    }

    /// With no task, the existing keyword rule is untouched.
    func testWithNoTaskTheKeywordRuleStillApplies() {
        let store = CompanyStore()
        XCTAssertEqual(store.speakerFor(task: nil, text: "ask marketing about this", department: nil)?.companionId, "nova")
        XCTAssertNil(store.speakerFor(task: nil, text: "what should I do today?", department: nil))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ChatSpeakerResolutionTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates
```
Expected: FAIL to compile — `value of type 'CompanyStore' has no member 'speakerFor'`.

`CompanyStore()` is the bare initialiser the existing suites use in 30 places. It is sufficient here: `speakerFor` reads only the task it is passed and two static catalogs (`DepartmentCatalog`, `DepartmentCompanions`) — it touches no loaded company state.

- [ ] **Step 3: Add the resolution seam**

In `codepet/Managers/CompanyStore.swift`, immediately after `actingSpecialist` (`:917`):

```swift
    /// Who speaks for this turn: the task's own department when the turn is about a task,
    /// else the chip-or-keyword rule.
    ///
    /// **Task first, and the order is the point.** A task's `dept` is a recorded fact; a
    /// keyword match is an inference over prose. Asking "walk me through <task>" names no
    /// department, so inference returned nil and the reply signed itself with the product's
    /// name on a Marketing task — the bug the founder photographed on 6 Sep.
    ///
    /// `internal` rather than `private` so the resolution is testable without a view. The two
    /// inputs stay separate for the same reason `actingSpecialist` and `actingDeptKey` are
    /// separate: who speaks and what they know are different questions.
    func speakerFor(task: RoadmapTask?, text: String,
                    department: Department?) -> (companionId: String, deptName: String)? {
        if let task, let spec = taskSpecialist(for: task) { return spec }
        return actingSpecialist(text: text, department: department)
    }
```

Change `taskSpecialist` at `:1995` from `private func` to `func` so the seam can reach it (it is already `internal`-safe; it reads only `task` and two static catalogs).

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command.
Expected: PASS, 4 tests.

- [ ] **Step 5: Wire it into `sendChat`**

Change the signature at `:781-784`:

```swift
    func sendChat(_ raw: String, language: AppLanguage, department: Department? = nil,
                  founderAsk: String? = nil, convenesRoom: Bool = false,
                  pinned: [ContextPin] = [],
                  attachments: [ChatAttachment] = [],
                  aboutTask: RoadmapTask? = nil) async {
```

At `:1563`, replace the specialist line:

```swift
        let specialist = speakerFor(task: aboutTask, text: text, department: department)
```

Leave `let deptKey = actingDeptKey(...)` on the next line **unchanged** — the wire's `dept_key` is a separate field on purpose, and fusing them is the bug class the comment at `:920-929` records.

Leave `:1569` (`companionId: specialist?.companionId ?? company.companionId`) **unchanged** — that is the wire request telling the backend who is answering, not the displayed row.

- [ ] **Step 6: Pass the task from the walkthrough beat**

`codepet/Demo/MockFlowPlayer.swift:285-290`:

```swift
            Task {
                await store.sendChat(
                    language == .vi ? "Hướng dẫn tôi làm: \(task.title)"
                                    : "Walk me through: \(task.title)",
                    language: language,
                    aboutTask: task)
            }
```

- [ ] **Step 7: Run the affected suites**

Run:
```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/ChatSpeakerResolutionTests \
  -only-testing:codepetTests/DepartmentCompanionsTests \
  -only-testing:codepetTests/MockFlowTests \
  -only-testing:codepetTests/DayOneBridgeTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates
```
Expected: PASS across all four.

- [ ] **Step 8: Commit**

```bash
git add codepet/Managers/CompanyStore.swift codepet/Demo/MockFlowPlayer.swift codepetTests/ChatSpeakerResolutionTests.swift
git commit -m "feat(chat): a task's department decides who answers about it"
```

---

### Task 4: The pet asks its own question

**Files:**
- Modify: `codepet/Demo/MockFlowScript.swift` (add `Intent` case), `codepet/Demo/MockFlowPlayer.swift` (handle it), `codepet/Demo/DayOneScript.swift` (the table + the beats)
- Test: `codepetTests/DayOneScriptTests.swift` (extend)

**Interfaces:**
- Consumes: `CodepetBrand.header` (Task 1), `DepartmentCompanions.companionId(for:)`, `DepartmentCatalog.find(_:)`.
- Produces:
  - `MockFlowScript.Intent.petAsks(deptKey: String)` — carries the department key ONLY, no prose.
  - `DayOneScript.questions: [String: (en: String, vi: String)]` — keyed by department key.
  - `DayOneScript.question(for deptKey: String, language: AppLanguage) -> String?`

**Founder decision, 6 Sep:** the beat carries no prose and the question is resolved at play time
from one bilingual table. Neither `DayOneScript.swift` nor `MockFlowScript.swift` contains a single
`.vi` conditional — the beat tuple has no language dimension and captions are English-only by
existing design. But `.petAsks` produces a real `CopilotMessage`, and chat text IS localised
elsewhere (`.walkthroughFounderTask` picks its language at play time). Resolving from a table keeps
the script naming departments rather than prose, and puts all sixteen strings in one place.

- [ ] **Step 1: Write the failing test**

Append to `codepetTests/DayOneScriptTests.swift`:

```swift
    /// Every department opens its own segment. Eight departments, and Marketing opens once
    /// even though it holds two links.
    func testEachDepartmentIsOpenedByItsOwnPet() {
        var asked: [String] = []
        for b in beats {
            if case let .petAsks(deptKey) = b.intent {
                asked.append(deptKey)
                XCTAssertNotNil(DepartmentCompanions.companionId(for: deptKey),
                                "\(deptKey) has no pet, so nobody can ask its question")
            }
        }
        XCTAssertEqual(asked.count, 8, "no department opens twice")
        XCTAssertEqual(Set(asked), Set(["mkt", "sales", "design", "eng", "fin", "support", "legal", "ops"]))
    }

    /// A pet asks BEFORE its link runs, never after.
    func testThePetAsksBeforeTheWorkItIntroduces() {
        var seenAsk = Set<String>()
        for b in beats {
            switch b.intent {
            case let .petAsks(deptKey): seenAsk.insert(deptKey)
            case let .runTask(id):
                let dept = DemoProject.murrorDayOne.tasks.first { $0.id == id }?.dept
                XCTAssertTrue(dept.map(seenAsk.contains) ?? false,
                              "\(id) runs before its department was introduced")
            default: break
            }
        }
    }

    /// Both languages, for every department that asks. An English question inside a chat
    /// bubble in a bilingual app is the finding that was raised about the credit line on 5 Sep.
    func testEveryQuestionExistsInBothLanguages() {
        for b in beats {
            guard case let .petAsks(deptKey) = b.intent else { continue }
            for lang in [AppLanguage.en, AppLanguage.vi] {
                let q = DayOneScript.question(for: deptKey, language: lang)
                XCTAssertNotNil(q, "\(deptKey) has no question in \(lang)")
                XCTAssertFalse(q?.isEmpty ?? true, "\(deptKey)'s \(lang) question is empty")
            }
        }
    }

    /// The two languages must not be the same string — a copy-paste that leaves English
    /// in the vi slot passes a non-empty check and ships English to a Vietnamese founder.
    func testTheTwoLanguagesActuallyDiffer() {
        for (deptKey, pair) in DayOneScript.questions {
            XCTAssertNotEqual(pair.en, pair.vi, "\(deptKey) has the same text in both languages")
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DayOneScriptTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates
```
Expected: FAIL to compile — `type 'MockFlowScript.Intent' has no case 'petAsks'`.

- [ ] **Step 3: Add the intent case**

In `codepet/Demo/MockFlowScript.swift`, inside `enum Intent`, after `case say(String)`:

```swift
        /// A department's pet opens its own segment by asking the question that link answers.
        ///
        /// Carries the DEPARTMENT KEY and nothing else. Two reasons, and both were paid for.
        /// The cast is remapped from time to time (`eng` moved to byte and `fin` to crash on
        /// 26 Aug), so a script naming pets directly would keep asking in a retired pet's name.
        /// And the prose is resolved at play time because it is a CHAT MESSAGE, not a caption:
        /// captions in this file are English-only by design, but a message in the transcript
        /// has to be bilingual, and the beat tuple has no language dimension to carry it.
        case petAsks(deptKey: String)
```

- [ ] **Step 4: Handle it in the player**

In `codepet/Demo/MockFlowPlayer.swift`, alongside `case .walkthroughFounderTask:`:

```swift
        case let .petAsks(deptKey):
            store.view = .chat
            guard let companionId = DepartmentCompanions.companionId(for: deptKey),
                  let dept = DepartmentCatalog.find(deptKey),
                  let question = DayOneScript.question(for: deptKey, language: language)
            else { return }
            store.chatMessages.append(
                CopilotMessage(role: .companion, text: question,
                               companionId: companionId, deptName: dept.name))
```

An unmapped department returns without appending rather than posting an unattributed question —
the same headerless-not-"Codepet" fallthrough the spec requires.

- [ ] **Step 5: Add the bilingual question table**

In `codepet/Demo/DayOneScript.swift`, above `beats`:

```swift
    /// The question each department opens its segment with, in both languages.
    ///
    /// One table rather than sixteen literals in the beat list: the beats name departments, the
    /// copy lives here, and a translator edits one place. Keyed by department key so a cast
    /// remap cannot strand a question on a retired pet.
    static let questions: [String: (en: String, vi: String)] = [
        "mkt": (en: "Is this a real problem, or just yours? Talk to twelve people before you build anything.",
                vi: "Đây là vấn đề có thật, hay chỉ của riêng bạn? Hãy nói chuyện với mười hai người trước khi xây bất cứ thứ gì."),
        "sales": (en: "So who is this NOT for? The one person who found it insulting is worth more than the nine who liked it.",
                  vi: "Vậy sản phẩm này KHÔNG dành cho ai? Một người thấy bị xúc phạm đáng giá hơn chín người khen hay."),
        "design": (en: "Now that you know who it is for, what should it feel like?",
                   vi: "Giờ bạn đã biết nó dành cho ai — vậy nó nên mang lại cảm giác gì?"),
        "eng": (en: "What do you build it on — and does anything a person writes ever leave their device?",
                vi: "Bạn sẽ xây trên nền gì — và những gì người ta viết có bao giờ rời khỏi máy của họ không?"),
        "fin": (en: "What does that cost you a month? I cannot price anything until Byte has chosen.",
                vi: "Mỗi tháng tốn bao nhiêu? Tôi không thể tính giá cho đến khi Byte chọn xong."),
        "support": (en: "What happens when someone is genuinely struggling at 2am?",
                    vi: "Chuyện gì xảy ra khi ai đó thật sự khủng hoảng lúc 2 giờ sáng?"),
        "legal": (en: "Are you in trouble for holding their words? Say what you delete, and when.",
                  vi: "Bạn có gặp rắc rối khi giữ lời của họ không? Hãy nói rõ bạn xoá gì, và khi nào."),
        "ops": (en: "How do you ship without breaking it? Thursday, not Friday.",
                vi: "Làm sao để phát hành mà không làm hỏng? Thứ Năm, đừng thứ Sáu."),
    ]

    /// The question for a department, or nil when it has none.
    static func question(for deptKey: String, language: AppLanguage) -> String? {
        guard let pair = questions[deptKey] else { return nil }
        return language == .vi ? pair.vi : pair.en
    }
```

- [ ] **Step 6: Insert the eight beats**

Insert a `.petAsks` beat before each link's `.runTask` / `.recordFounderTask`. Chapter strings are
set in Task 5 — use the existing chapter string of the link each one introduces for now.

```swift
        ("Is this real?", 2.4, .petAsks(deptKey: "mkt"),
         "Nova opens. The first question is hers to answer, not Codepet's."),
        ("Who is it not for?", 2.2, .petAsks(deptKey: "sales"),
         "The same pet, a different department — Nova speaks for both."),
        ("What should it feel like?", 2.2, .petAsks(deptKey: "design"),
         "Luna reads the two artifacts before it."),
        ("What do I build it on?", 2.2, .petAsks(deptKey: "eng"),
         "The first question with a bill attached."),
        ("What does it cost me?", 2.2, .petAsks(deptKey: "fin"),
         "Crash says why this could not have been asked earlier."),
        ("A bad night", 2.4, .petAsks(deptKey: "support"),
         "The question a consumer app about loneliness cannot avoid."),
        ("Data deletion", 2.2, .petAsks(deptKey: "legal"),
         "Glitch reads Sage's policy before answering."),
        ("Release rhythm", 2.2, .petAsks(deptKey: "ops"),
         "The same pet again, and the last question before the day hands one back."),
```

Use the ACTUAL chapter strings already present on the two final links rather than the invented
`"Data deletion"` / `"Release rhythm"` above if they differ — read the file.

- [ ] **Step 7: Run test to verify it passes**

Run the Step 2 command.
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add codepet/Demo/MockFlowScript.swift codepet/Demo/MockFlowPlayer.swift codepet/Demo/DayOneScript.swift codepetTests/DayOneScriptTests.swift
git commit -m "feat(demo): each department is opened by its own pet, in both languages"
```

---

### Task 5: Chapters become departments, and the day is re-measured

**Files:**
- Modify: `codepet/Demo/DayOneScript.swift` (chapter strings on every existing beat)
- Test: `codepetTests/DayOneScriptTests.swift` (extend)

**Interfaces:**
- Consumes: `MockFlowScript.chapters` — already derives by deduplicating `Beat.chapter` in order. No new machinery.

- [ ] **Step 1: Write the failing test**

```swift
    /// The chapter bar reads as the opener plus eight departments, not twenty-one questions.
    func testTheChapterBarIsTheOpenerPlusEightDepartments() {
        var seen = Set<String>()
        let chapters = beats.compactMap { seen.insert($0.chapter).inserted ? $0.chapter : nil }
        XCTAssertEqual(chapters.count, 9, "one opener + eight departments")
        XCTAssertEqual(chapters.first, "Day one")
        XCTAssertEqual(Array(chapters.dropFirst()), [
            "Marketing · Nova", "Sales · Nova", "Design · Luna", "Engineering · Byte",
            "Finance · Crash", "Support · Sage", "Legal · Glitch", "Operations · Glitch",
        ])
    }

    /// The whole day still fits the budget. Recorded, not estimated.
    func testTheDayFitsItsTimeBudget() {
        let total = beats.reduce(0) { $0 + $1.seconds }
        XCTAssertLessThanOrEqual(total, 75.0, "day one runs \(total)s; budget is 75s")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DayOneScriptTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates
```
Expected: FAIL — chapter list mismatch, and likely the budget assertion too.

- [ ] **Step 3: Rename every chapter to its department**

In `codepet/Demo/DayOneScript.swift`, change the first tuple element of every beat. `"Day one"` stays on the opener. `"Is this real?"` → `"Marketing · Nova"`, `"Has someone built it?"` → `"Marketing · Nova"` (same chapter — Marketing holds two links and must not open twice), `"Who is it not for?"` → `"Sales · Nova"`, `"What should it feel like?"` → `"Design · Luna"`, `"What do I build it on?"` → `"Engineering · Byte"`, `"What does it cost me?"` → `"Finance · Crash"`, `"A bad night"` → `"Support · Sage"`, and the remaining two links to `"Legal · Glitch"` and `"Operations · Glitch"`.

- [ ] **Step 4: Trim captions to fit the budget**

Print the measured total first:

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DayOneScriptTests/testTheDayFitsItsTimeBudget \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates 2>&1 | grep "day one runs"
```

The failure message names the actual seconds. Reduce the `.runTask` beats' `seconds` and shorten their captions — the pet's question now carries what narration was explaining, so the caption beneath it is redundant by exactly that much. **Do not** shorten `.approveNewestDraft` beats: they are the moment the founder is meant to register that approval is what commits.

Re-run until the assertion passes, then record the final number in the commit message.

- [ ] **Step 5: Re-run the caption readability check**

Run:
```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/MockFlowCaptionBarLayoutTests \
  -only-testing:codepetTests/DayOneScriptTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates
```
Expected: PASS. A shortened caption still has to clear the readability floor on Slow.

- [ ] **Step 6: Commit**

```bash
git add codepet/Demo/DayOneScript.swift codepetTests/DayOneScriptTests.swift
git commit -m "feat(demo): the day reads as eight department chapters"
```

---

### Task 6: Full-suite verification and on-screen check

**Files:** none modified.

- [ ] **Step 1: Confirm no app instance is running**

```bash
pgrep -fl "codepet.app/Contents/MacOS/codepet" || echo "clear"
```
Expected: `clear`. A live instance kills the test host.

- [ ] **Step 2: Run the touched suites locally, per-suite**

**Not the whole suite locally.** `CLAUDE.md` landmine 3: the XCTest host crashes on Xcode 26.2
when a `@MainActor ObservableObject` deallocates — ~27 of ~970 tests never finish and
`xcodebuild test` exits 65 on a clean checkout, with nothing actually failing. Chasing that as a
regression is a known time sink.

```bash
xcodebuild test -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/CodepetBrandTests \
  -only-testing:codepetTests/CopilotChatHeaderTests \
  -only-testing:codepetTests/ChatSpeakerResolutionTests \
  -only-testing:codepetTests/DayOneScriptTests \
  -only-testing:codepetTests/DayOneBridgeTests \
  -only-testing:codepetTests/DayOneFixtureTests \
  -only-testing:codepetTests/DemoProjectParityTests \
  -only-testing:codepetTests/DepartmentCompanionsTests \
  -only-testing:codepetTests/MockFlowTests \
  -only-testing:codepetTests/MockFlowScriptTests \
  -only-testing:codepetTests/MockFlowCaptionBarLayoutTests \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates \
  -resultBundlePath /tmp/pet-voice.xcresult
```

- [ ] **Step 3: Count results the only way that is trustworthy**

```bash
xcrun xcresulttool get test-results summary --path /tmp/pet-voice.xcresult
```
Expected: 0 failures. Read the count from here, never from scrollback.

- [ ] **Step 3b: Get the real full-suite run from CI, not locally**

A `-only-testing:` branch is an untested branch — the first full run on this repo once found
three real regressions. The full suite is CI's job, and **pushing a branch runs nothing**: a PR
must exist, even a draft.

```bash
git push -u origin feat/pet-voice-and-department-segments
gh pr create --draft --base main \
  --title "Pets speak for their departments, and the day reads as eight chapters" \
  --body "Implements docs/superpowers/specs/2026-09-06-pet-voice-and-department-segments-design.md"
gh pr checks --watch
```
Expected: `functions` and `test` both pass. Do not report the suite green until this lands.

- [ ] **Step 4: Watch the day play**

```bash
open -a "$(xcodebuild -scheme codepet -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2} / FULL_PRODUCT_NAME/{n=$2} END{print d"/"n}')" \
  --args -CODEPET_MOCK_AUTOPLAY YES -CODEPET_DEMO_PROJECT murror-day-one
```

Check all five success criteria against the screen:
1. Every departmental reply is headed with its pet and department.
2. No reply anywhere is headed "Codepet".
3. A general reply renders as prose with no speaker row.
4. The chapter bar lists the opener plus eight departments.
5. The measured duration is recorded, not estimated.

- [ ] **Step 5: Clean up and commit the result**

```bash
rm -rf /tmp/pet-voice.xcresult
git commit --allow-empty -m "test: full suite green on the pet-voice branch — <N> tests, 0 failures, day one <T>s"
```

---

## Self-Review

**Spec coverage:** §1 optional header → Tasks 1–2. §2 task-department resolution → Task 3. §3 chapters → Task 5. §4 `.petAsks` → Task 4. Out-of-scope items (reply rewriting, per-department threads, tour script) have no tasks, correctly. Risks: shared-view regression → Task 2 Step 5 and Task 6; duration → Task 5 Step 4; bilingual → Task 4 Step 5 and Global Constraints; parity guard → unchanged and exercised by Task 6; nil department → Task 3 Step 1 test 3 and Task 4 Step 4.

**Type consistency:** `CodepetBrand.header(companionId:deptName:) -> String?` is defined in Task 1 and consumed unchanged in Tasks 2 and 4. `speakerFor(task:text:department:)` is defined in Task 3 Step 3 and used in Step 5 with the same label order. `Intent.petAsks(deptKey:question:)` is defined in Task 4 Step 3 and destructured identically in Steps 1, 4 and 5.

**Known soft spot:** Task 3's tests call `CompanyStore()`, which this plan did not verify exists. Step 2 says to grep `codepetTests/` for the factory already in use and to keep it consistent across all four tests. That is the one place an implementer must look something up rather than copy it.
