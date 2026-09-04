# First-Run Approval Note Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new founder's draft card says the deliverable is not saved yet, until the first time they approve anything.

**Architecture:** One persisted `Date?` on `CompanyState` mirroring `introSeenAt` field-for-field; one write inside `fileApproval`, which is the single chokepoint both approve paths already funnel through; one pure static that decides whether the note shows; one `Text` in `draftCard`. No new file except the test.

**Tech Stack:** Swift 5, SwiftUI, XCTest, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Xcode 26.2, macOS target 26.2.

**Spec:** `docs/superpowers/specs/2026-09-04-first-run-approval-note-design.md`

## Global Constraints

- **Copy is fixed by the spec.** en: `Not saved yet — approving files it in your Library.` vi: `Chưa lưu — duyệt để đưa vào Thư viện.` The dash is an em dash (`—`, U+2014), matching every other string in this file.
- **Muted, not accented.** `CodepetTheme.mutedText`, `.pixelSystem(size: 11.5)`. It is a status note; the Approve button beside it carries the emphasis. Never `accentPurple` — that is `UpstreamCredit`'s slot, and two purple lines on one card compete.
- **The retirement signal is `firstApprovalAt`, never `library.isEmpty`.** The Murror demo pre-files three artifacts (`DemoProject.filed`), so a derived signal would silence the note in prototype mode — the one surface used to demo the product. Task 4 pins this.
- **Set it in `fileApproval` only.** `approveDraft` and `approveTask` both call it (`CompanyStore.swift:2568` and `:2905`), and `ApprovalParityTests` already asserts they agree. Writing the flag in both callers instead would be two places to drift.
- **Fail-soft, matching `markIntroSeen`.** A lost write costs one extra showing of a teaching line and never a broken card. Never `try!`, never a thrown error reaching the view.
- **`CompanyState.init(from:)` is hand-written** and every key uses `decodeIfPresent` with a default. A new field MUST be added there too, or every company document written before today throws `keyNotFound` and fails to decode. This is the landmine the file's own comment warns about.
- Theme colours come from `CodepetTheme` — never a bare literal, or the card breaks in one theme.
- Commit with `git commit -F <file>`, never `-m`: bodies contain backticks and zsh would execute them.
- `xcodebuild test` exits 65 on a clean checkout — the XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates (~27 tests never finish, none actually fail). Run per-suite with `-only-testing:` and read counts from `xcresulttool get test-results summary`, **never from the exit code**. A zero count means the suite did not run — treat that as a failure, not a pass.
- Quit the running `codepet.app` before any `xcodebuild test`: a live app kills the test host. Check with `ps -eo pid,comm | awk '$2 ~ /codepet$/'` — **not** `pgrep -f`, which matches the wrapper shell's own command line and lies.
- **`osascript -e 'quit app "codepet"'` does not reliably terminate it** — measured by the Task 1 implementer on 4 Sep: the app was still present after the quit plus a sleep. Verify, and fall back to the pid:

```bash
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}')
[ -n "$PID" ] && kill "$PID" && sleep 2
ps -eo pid,comm | awk '$2 ~ /codepet$/ {print "STILL RUNNING",$1}'
```

  The last line must print nothing before you run tests. This is the founder's own app — killing it is fine here because this worktree owns the running instance, but never `pkill -f codepet`, which would also match sibling sessions' processes.

---

### Task 1: `firstApprovalAt` on the model and the wire

**Files:**
- Modify: `codepet/Models/CompanyState.swift` — the property, the memberwise init, `init(from:)`
- Modify: `codepet/Services/CompanyData.swift` — the DTO field, the hydrate mapping, the payload, the saver
- Test: `codepetTests/FirstApprovalNoteTests.swift` (create)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `CompanyState.firstApprovalAt: Date?`, `CompanyData.firstApprovalPayload(_ at: Date) -> [String: Any]`, `CompanyData.saveFirstApproval(_ companyId: String, _ at: Date) async -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/FirstApprovalNoteTests.swift`:

```swift
// codepetTests/FirstApprovalNoteTests.swift
import XCTest
@testable import codepet

/// Guards on the draft card admitting it is not saved yet.
///
/// The rule "nothing is committed until you approve" is stated BEFORE a run (`BeaconOffer`:
/// "you approve before it is filed") and confirmed AFTER ("Added to Library"). In between, the
/// founder looks at a finished-LOOKING deliverable beside a button marked Approve, with nothing
/// saying it is unsaved. That middle moment is what this note fills.
@MainActor
final class FirstApprovalNoteTests: XCTestCase {

    // MARK: - Task 1: the field and its wire shape

    /// Millis, not ISO — `introSeenAt` next to it is a number and the web reads both.
    func testFirstApprovalPayloadIsEpochMillis() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = CompanyData.firstApprovalPayload(at)
        XCTAssertEqual(payload["firstApprovalAt"] as? Double, 1_700_000_000_000)
    }

    /// **The landmine this file's own comment warns about.** `CompanyState.init(from:)` is
    /// hand-written because Swift's synthesised `Decodable` throws `keyNotFound` rather than
    /// falling back to a declared default. Every company document in Firestore predates this
    /// field, so a required decode would fail to load EVERY existing account.
    func testACompanyDocumentWithoutTheFieldStillDecodes() throws {
        let json = #"{"companionId":"byte","stage":"building"}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertNil(state.firstApprovalAt)
        XCTAssertEqual(state.companionId, "byte")
    }

    func testItRoundTripsWhenPresent() throws {
        var state = CompanyState.empty
        state.firstApprovalAt = Date(timeIntervalSince1970: 1_700_000_000)
        let back = try JSONDecoder().decode(
            CompanyState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(back.firstApprovalAt?.timeIntervalSince1970, 1_700_000_000)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstApprovalNoteTests test 2>&1 | tail -15
```

Expected: FAIL — `type 'CompanyData' has no member 'firstApprovalPayload'` and `value of type 'CompanyState' has no member 'firstApprovalAt'`.

- [ ] **Step 3: Add the property to `CompanyState`**

In `codepet/Models/CompanyState.swift`, immediately after the `introSeenAt` property (which ends at the line `var introSeenAt: Date?`), add:

```swift
    /// When this account first approved anything. Account-scoped like `introSeenAt` above, and
    /// for the same reason: the note it retires is a one-time lesson, not a per-device one.
    ///
    /// Deliberately NOT derived from `library.isEmpty`, which looks like a free proxy since
    /// approving is the only thing that files there. The Murror demo pre-files three research
    /// artifacts (`DemoProject.filed`), so a derived signal would silence the note in prototype
    /// mode — the one surface used to demo the product, and the place the rule is most worth
    /// teaching.
    var firstApprovalAt: Date?
```

In the memberwise init, after `introSeenAt: Date? = nil,` add:

```swift
         firstApprovalAt: Date? = nil,
```

and in that init's body, after `self.introSeenAt = introSeenAt`, add:

```swift
        self.firstApprovalAt = firstApprovalAt
```

In `init(from decoder:)`, after the `introSeenAt = try c.decodeIfPresent(...)` line, add:

```swift
        firstApprovalAt = try c.decodeIfPresent(Date.self, forKey: .firstApprovalAt)
```

`CodingKeys` is synthesised for this type — verified: `CompanyState.swift` contains no hand-written enum, only `keyedBy: CodingKeys.self` at line 64 referencing the synthesised one. Adding the stored property is therefore enough, and encoding stays synthesised too. **Do not** hand-write a `CodingKeys` enum here.

- [ ] **Step 4: Add the DTO field, the mapping, the payload and the saver**

In `codepet/Services/CompanyData.swift`, after the line `var introSeenAt: Double?   // epoch MILLIS (matches the web schema's `Millis`)`, add:

```swift
    var firstApprovalAt: Double?  // epoch MILLIS, same shape as introSeenAt above
```

In the hydrate mapping, after the `introSeenAt: doc.introSeenAt.map { ... },` line, add:

```swift
            firstApprovalAt: doc.firstApprovalAt.map { Date(timeIntervalSince1970: $0 / 1000) },
```

After the existing `saveIntroSeen` function (it ends with the closing brace after `return false`), add:

```swift
    /// Pure Firestore payload for the first-approval write — testable without Firestore.
    /// Millis, not ISO, matching `introSeenPayload` above.
    static func firstApprovalPayload(_ at: Date) -> [String: Any] {
        ["firstApprovalAt": at.timeIntervalSince1970 * 1000]
    }

    /// Write companies/{uid}.firstApprovalAt, merge. Fail-soft: false on error — a lost write
    /// only means the "not saved yet" note shows once more, never a broken card.
    static func saveFirstApproval(_ companyId: String, _ at: Date) async -> Bool {
        // Prototype mode keeps the whole company in memory and rebuilds it from fixtures on
        // every load, so a write here would put demo data in a real founder's document.
        // Reported as done rather than failed: nothing was attempted, so there is no error to
        // show. Same guard as `saveIntroSeen`.
        guard PrototypeMode.allowsCloudWrites else { return true }
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(firstApprovalPayload(at), merge: true)
            return true
        } catch {
            return false
        }
    }
```

- [ ] **Step 5: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
rm -rf /tmp/fa1.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstApprovalNoteTests \
  -resultBundlePath /tmp/fa1.xcresult test > /tmp/fa1.log 2>&1
grep -E '^/Users.*error:' /tmp/fa1.log | head -5
xcrun xcresulttool get test-results summary --path /tmp/fa1.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 3`. A zero passed count means the suite did not run — treat that as a failure.

- [ ] **Step 6: Commit**

```bash
cat > /tmp/c-fa1.txt <<'EOF'
feat(company): remember when the founder first approved anything

`firstApprovalAt`, mirroring `introSeenAt` field-for-field: optional Date on
the state, epoch millis on the wire, merge write, fail-soft.

Deliberately not derived from an empty library, which looks like a free proxy
since approving is the only thing that files there. The Murror demo pre-files
three research artifacts, so a derived signal would silence the note this
exists to gate in prototype mode — the one surface used to demo the product.

Added to the hand-written `init(from:)` as well as the property: that
initializer exists because Swift's synthesised Decodable throws keyNotFound
rather than defaulting, and every company document in Firestore predates this
field. A test decodes a document without it.

3 passed / 0 failed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Models/CompanyState.swift codepet/Services/CompanyData.swift \
        codepetTests/FirstApprovalNoteTests.swift
git commit -F /tmp/c-fa1.txt
```

---

### Task 2: The store sets it, once, at the one chokepoint

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` — the saver property (~line 211), its init parameter (~line 321), its assignment (~line 389), and `fileApproval` (~line 2576)
- Test: `codepetTests/FirstApprovalNoteTests.swift` (append)

**Interfaces:**
- Consumes: `CompanyState.firstApprovalAt`, `CompanyData.saveFirstApproval` (Task 1).
- Produces: `CompanyStore.firstApprovalSaver: (String, Date) async -> Bool` (injectable, defaulted), and the guarantee that `company.firstApprovalAt` is non-nil after any approval.

- [ ] **Step 1: Write the failing tests**

Append inside `FirstApprovalNoteTests` (before its closing brace):

```swift
    // MARK: - Task 2: the store sets it

    /// Same stubs as `CompanyStoreChatRunTests`: the live defaults reach Firestore and Firebase
    /// Auth, both of which trap under an unconfigured `FirebaseApp`.
    private func store(tasks: [RoadmapTask] = [],
                       saver: @escaping (String, Date) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in
            CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .building,
                         companionId: "byte", onboardedAt: Date(), tasks: tasks)
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in
               AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
           },
           taskRunner: { _ in nil }, librarySaver: { _, _ in true },
           decisionExtractor: { _, _ in [] },
           firstApprovalSaver: saver)
    }

    private func draft(_ taskId: String? = nil) -> Deliverable {
        // `kind` before `title` — see `Deliverable.init`.
        Deliverable(id: "d1", kind: .doc, title: "T", body: "B", sourceTaskId: taskId)
    }

    func testApprovingFromChatRecordsTheFirstApproval() async {
        let s = store()
        await s.hydrate(companyId: "u")
        XCTAssertNil(s.company.firstApprovalAt, "a fresh account has approved nothing")
        s.seedChatMessagesForTesting([
            CopilotMessage(id: "m1", role: .companion, text: "", draft: draft())
        ])
        await s.approveDraft(messageId: "m1")
        XCTAssertNotNil(s.company.firstApprovalAt)
    }

    /// The board is a real path to the same lesson. Both approve paths funnel through
    /// `fileApproval`, so this passes for free — and goes red the moment someone writes the
    /// flag in `approveDraft` instead of at the chokepoint.
    func testApprovingFromTheBoardRecordsItToo() async {
        let task = RoadmapTask(id: "t1", title: "T", detail: "", phase: .build, who: .draft,
                               drafted: true, draft: draft("t1"))
        let s = store(tasks: [task])
        await s.hydrate(companyId: "u")
        await s.approveTask(id: "t1")
        XCTAssertNotNil(s.company.firstApprovalAt)
    }

    /// Written once. A second approval must not move the timestamp — it is "when did they
    /// learn this", not "when did they last approve".
    func testTheTimestampIsNotOverwrittenByLaterApprovals() async {
        let s = store()
        await s.hydrate(companyId: "u")
        s.seedChatMessagesForTesting([
            CopilotMessage(id: "m1", role: .companion, text: "", draft: draft()),
            CopilotMessage(id: "m2", role: .companion, text: "", draft: draft())
        ])
        await s.approveDraft(messageId: "m1")
        let first = s.company.firstApprovalAt
        await s.approveDraft(messageId: "m2")
        XCTAssertEqual(s.company.firstApprovalAt, first)
    }

    /// Fail-soft, matching `markIntroSeen`: a rejected write leaves the in-memory flag set, so
    /// the founder is not re-taught inside the session they just learned it in.
    func testAFailedWriteStillRetiresTheNoteInSession() async {
        let s = store(saver: { _, _ in false })
        await s.hydrate(companyId: "u")
        s.seedChatMessagesForTesting([
            CopilotMessage(id: "m1", role: .companion, text: "", draft: draft())
        ])
        await s.approveDraft(messageId: "m1")
        XCTAssertNotNil(s.company.firstApprovalAt)
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstApprovalNoteTests test 2>&1 | tail -15
```

Expected: FAIL — `extra argument 'firstApprovalSaver' in call`.

- [ ] **Step 3: Add the injectable saver**

In `codepet/Managers/CompanyStore.swift`, immediately after the line `private let introSeenSaver: (String, Date) async -> Bool` (~line 211), add:

```swift
    private let firstApprovalSaver: (String, Date) async -> Bool
```

In the initializer's parameter list, immediately after `introSeenSaver: @escaping (String, Date) async -> Bool = CompanyData.saveIntroSeen,` (~line 321), add:

```swift
         firstApprovalSaver: @escaping (String, Date) async -> Bool = CompanyData.saveFirstApproval,
```

In the initializer's body, immediately after `self.introSeenSaver = introSeenSaver` (~line 389), add:

```swift
        self.firstApprovalSaver = firstApprovalSaver
```

- [ ] **Step 4: Record it in `fileApproval`**

In `fileApproval` (~line 2576), immediately after the line `company.library.append(draft)`, add:

```swift
        // The founder has now approved something, so the "not saved yet" note on the draft card
        // has done its job and retires (see `DraftCardCopy.shouldShowNotFiledNote`).
        //
        // HERE and not in `approveDraft`/`approveTask`: this is the one path both of them call,
        // which is why `ApprovalParityTests` exists. Writing it in the two callers instead would
        // be two places to drift, and the board is as real a way to learn the rule as the chat.
        //
        // Set once. This records WHEN THEY LEARNED IT, not when they last approved.
        if company.firstApprovalAt == nil {
            let now = Date()
            company.firstApprovalAt = now
            // Fire-and-forget and fail-soft, matching `markIntroSeen`: a lost write costs one
            // extra showing of a teaching line, never a broken card or a blocked approval.
            if let cid = companyId { _ = await firstApprovalSaver(cid, now) }
        }
```

- [ ] **Step 5: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
rm -rf /tmp/fa2.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstApprovalNoteTests \
  -resultBundlePath /tmp/fa2.xcresult test > /tmp/fa2.log 2>&1
grep -E '^/Users.*error:' /tmp/fa2.log | head -5
xcrun xcresulttool get test-results summary --path /tmp/fa2.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 7`.

- [ ] **Step 6: Commit**

```bash
cat > /tmp/c-fa2.txt <<'EOF'
feat(company): record the first approval at the one path both approvals share

Written in `fileApproval`, not in `approveDraft` and `approveTask`. Those two
already funnel through it — `ApprovalParityTests` exists because they once
drifted — so the chokepoint is one place instead of two, and approving from
the board teaches the same lesson as approving from chat.

Set once: this records when the founder LEARNED the rule, not when they last
approved, so a second approval must not move it. A test pins that.

Fail-soft like `markIntroSeen`: a rejected write leaves the in-memory flag
set, so a founder is not re-taught inside the session they just learned in.

7 passed / 0 failed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Managers/CompanyStore.swift codepetTests/FirstApprovalNoteTests.swift
git commit -F /tmp/c-fa2.txt
```

---

### Task 3: The decision, as a pure static

**Files:**
- Create: `codepet/Views/Copilot/DraftCardCopy.swift`
- Test: `codepetTests/FirstApprovalNoteTests.swift` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: `DraftCardCopy.shouldShowNotFiledNote(hasApproved: Bool, draftApproved: Bool) -> Bool`, `DraftCardCopy.notFiledNote(_ lang: AppLanguage) -> String`.

- [ ] **Step 1: Write the failing tests**

Append inside `FirstApprovalNoteTests`:

```swift
    // MARK: - Task 3: the decision

    /// A pure static, not a condition inside `draftCard`'s body. Same reasoning as
    /// `DraftPayloadPreview.hasStructuredPreview`: the bug worth guarding lives in the
    /// decision, and a decision inside a `View` body is only testable by rendering it.
    func testTheNoteShowsOnlyBeforeTheFirstApproval() {
        XCTAssertTrue(DraftCardCopy.shouldShowNotFiledNote(hasApproved: false,
                                                           draftApproved: false))
        XCTAssertFalse(DraftCardCopy.shouldShowNotFiledNote(hasApproved: true,
                                                            draftApproved: false),
                       "retired once the founder has approved anything")
    }

    /// An approved card already says "Added to Library". Two answers to one question on one
    /// card is worse than none.
    func testTheNoteNeverShowsOnAnApprovedCard() {
        XCTAssertFalse(DraftCardCopy.shouldShowNotFiledNote(hasApproved: false,
                                                            draftApproved: true))
        XCTAssertFalse(DraftCardCopy.shouldShowNotFiledNote(hasApproved: true,
                                                            draftApproved: true))
    }

    func testTheCopyIsExactlyWhatTheSpecSays() {
        XCTAssertEqual(DraftCardCopy.notFiledNote(.en),
                       "Not saved yet — approving files it in your Library.")
        XCTAssertEqual(DraftCardCopy.notFiledNote(.vi),
                       "Chưa lưu — duyệt để đưa vào Thư viện.")
    }

    /// An em dash, not a hyphen — every other string on this card uses one, and a lone hyphen
    /// reads as a typo beside them.
    func testTheCopyUsesAnEmDash() {
        XCTAssertTrue(DraftCardCopy.notFiledNote(.en).contains("\u{2014}"))
        XCTAssertTrue(DraftCardCopy.notFiledNote(.vi).contains("\u{2014}"))
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstApprovalNoteTests test 2>&1 | tail -12
```

Expected: FAIL — `cannot find 'DraftCardCopy' in scope`.

- [ ] **Step 3: Create the file**

Create `codepet/Views/Copilot/DraftCardCopy.swift`:

```swift
// codepet/Views/Copilot/DraftCardCopy.swift
import Foundation

/// Copy and one decision for the draft card, kept out of the view so the suite can pin them.
///
/// **Why the note exists.** "Nothing is committed until you approve it" is the product's
/// governing promise, and the app stated it BEFORE a run (`BeaconOffer`: "you approve before it
/// is filed") and confirmed it AFTER ("Added to Library") — with nothing in between. So at the
/// one moment it becomes concrete, the founder was looking at a finished-LOOKING deliverable
/// beside a button marked Approve, with no indication it was unsaved.
enum DraftCardCopy {

    /// Whether to tell the founder this draft is not filed yet.
    ///
    /// **A pure static, not a condition in `draftCard`'s body.** Same reasoning as
    /// `DraftPayloadPreview.hasStructuredPreview`: the decision is where a bug here would live,
    /// and a decision inside a `View` body is only testable by rendering it.
    ///
    /// `hasApproved` is `company.firstApprovalAt != nil` — it retires because the rule was
    /// LEARNED, not because a counter ran out. `draftApproved` suppresses it on a card that
    /// already says "Added to Library": two answers to one question is worse than none.
    static func shouldShowNotFiledNote(hasApproved: Bool, draftApproved: Bool) -> Bool {
        !hasApproved && !draftApproved
    }

    /// The note itself. Wording fixed by
    /// `docs/superpowers/specs/2026-09-04-first-run-approval-note-design.md`.
    ///
    /// "Not saved yet" rather than "Not approved yet": the founder can see it is unapproved —
    /// the Approve button is right there. What they cannot see is that unapproved means unsaved.
    static func notFiledNote(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Chưa lưu — duyệt để đưa vào Thư viện."
            : "Not saved yet — approving files it in your Library."
    }
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
rm -rf /tmp/fa3.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstApprovalNoteTests \
  -resultBundlePath /tmp/fa3.xcresult test > /tmp/fa3.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/fa3.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 11`.

- [ ] **Step 5: Commit**

```bash
cat > /tmp/c-fa3.txt <<'EOF'
feat(chat): the draft card's "not saved yet" decision, as a pure static

`DraftCardCopy.shouldShowNotFiledNote` and the copy beside it, out of the view
for the same reason `DraftPayloadPreview.hasStructuredPreview` is: the bug
worth guarding lives in the decision, and a decision inside a View body is
only testable by rendering it.

"Not saved yet" rather than "Not approved yet" — the founder can SEE it is
unapproved, the button is right there. What they cannot see is that
unapproved means unsaved.

11 passed / 0 failed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Views/Copilot/DraftCardCopy.swift codepetTests/FirstApprovalNoteTests.swift
git commit -F /tmp/c-fa3.txt
```

---

### Task 4: Mount it, and pin the demo

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` — inside `draftCard`, at the `if message.draftApproved {` branch (~line 2354)
- Test: `codepetTests/FirstApprovalNoteTests.swift` (append)

**Interfaces:**
- Consumes: `DraftCardCopy.shouldShowNotFiledNote`, `DraftCardCopy.notFiledNote` (Task 3), `CompanyState.firstApprovalAt` (Task 1).
- Produces: nothing later tasks rely on.

- [ ] **Step 1: Write the failing test**

Append inside `FirstApprovalNoteTests`:

```swift
    // MARK: - Task 4: the demo, and the trap

    /// **The derived-from-Library trap, pinned.** `library.isEmpty` looks like a free proxy for
    /// "has never approved", since approving is the only thing that files there. The Murror demo
    /// pre-files three research artifacts (`DemoProject.filed`) so departments can build on each
    /// other — so a derived signal would silence this note in prototype mode, which is the one
    /// surface used to demo the product and the place the rule is most worth teaching.
    ///
    /// This test fails if anyone "simplifies" the flag away.
    func testTheMurrorDemoShowsTheNoteDespiteAPrefilledLibrary() {
        let library = DemoProject.murror.library()
        XCTAssertFalse(library.isEmpty, "fixture changed — the trap this pins is gone")

        let state = CompanyState(brief: CompanyBrief(), departments: [], library: library,
                                 stage: .building, companionId: "byte", onboardedAt: Date(),
                                 tasks: DemoProject.murror.tasks)
        XCTAssertNil(state.firstApprovalAt, "a pre-filled library is not an approval")
        XCTAssertTrue(
            DraftCardCopy.shouldShowNotFiledNote(hasApproved: state.firstApprovalAt != nil,
                                                 draftApproved: false),
            "the demo must still teach the rule")
    }
```

- [ ] **Step 2: Run to verify it fails**

It will fail to compile only if Task 1 or 3 was skipped. If Tasks 1–3 are done this test PASSES immediately — that is expected and correct: it is a regression guard on a property the earlier tasks already establish, not a driver for new code. Run it and confirm it passes:

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
rm -rf /tmp/fa4.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstApprovalNoteTests \
  -resultBundlePath /tmp/fa4.xcresult test > /tmp/fa4.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/fa4.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 12`.

To prove it guards something, temporarily change `shouldShowNotFiledNote`'s body to `!hasApproved && !draftApproved && false`, re-run, confirm this test goes red, then revert.

- [ ] **Step 3: Mount the note**

In `codepet/Views/Copilot/CopilotChatView.swift`, find this block inside `draftCard` (~line 2354):

```swift
                    if message.draftApproved {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                            Text(lang == .vi ? "Đã thêm vào Thư viện" : "Added to Library")
                        }
```

Immediately BEFORE that `if message.draftApproved {` line, insert:

```swift
                    // The one moment the approval promise is silent. `BeaconOffer` says "you
                    // approve before it is filed" before the run, and the branch below confirms
                    // "Added to Library" after — but here the founder is looking at a
                    // finished-LOOKING deliverable beside a button marked Approve, with nothing
                    // saying it is unsaved.
                    //
                    // Retires on the founder's FIRST approval, account-wide: it is a one-time
                    // lesson, and a founder who learned it on the board does not need it here.
                    if DraftCardCopy.shouldShowNotFiledNote(
                        hasApproved: companyStore.company.firstApprovalAt != nil,
                        draftApproved: message.draftApproved) {
                        Text(DraftCardCopy.notFiledNote(lang))
                            .font(.pixelSystem(size: 11.5))
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

```

Read `companyStore.company.firstApprovalAt` live rather than capturing it into a `let` above: approving updates the published `company`, and the note must disappear from every other card on screen in the same frame.

- [ ] **Step 4: Build and confirm it compiles**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
rm -rf /tmp/fa5.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstApprovalNoteTests \
  -resultBundlePath /tmp/fa5.xcresult test > /tmp/fa5.log 2>&1
grep -E '^/Users.*error:' /tmp/fa5.log | head -5
xcrun xcresulttool get test-results summary --path /tmp/fa5.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: no errors, `"failedTests" : 0`, `"passedTests" : 12`.

- [ ] **Step 5: Run the suites this could disturb**

`draftCard` and the approval path are shared, so re-run every suite that touches them:

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
for s in FirstApprovalNoteTests ApprovalParityTests ApprovalTierTests \
         CompanyStoreChatRunTests CompanyStoreRunTaskTests CopilotMessageDraftTests \
         DraftPayloadPreviewTests UpstreamCreditTests DemoProjectFiledTests \
         PrototypeParityTests; do
  rm -rf /tmp/r-$s.xcresult
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/r-$s.xcresult test \
    > /tmp/log-$s.txt 2>&1
  p=$(xcrun xcresulttool get test-results summary --path /tmp/r-$s.xcresult 2>/dev/null \
      | grep '"passedTests"' | head -1 | tr -dc 0-9)
  f=$(xcrun xcresulttool get test-results summary --path /tmp/r-$s.xcresult 2>/dev/null \
      | grep '"failedTests"' | head -1 | tr -dc 0-9)
  printf "%-28s pass=%-4s fail=%s\n" "$s" "${p:-0}" "${f:-0}"
done
```

Expected: every row `fail=0` and `pass` greater than 0. A `pass=0` row means that suite did not run — investigate rather than continuing.

- [ ] **Step 6: Commit**

```bash
cat > /tmp/c-fa4.txt <<'EOF'
feat(chat): a first draft says it is not saved yet

The founder's own question — "what is the first thing new users need to know
when they first open the app?" — answered with the approval model, at the one
moment it was silent.

`BeaconOffer` already says "you approve before it is filed" before a run, and
the card says "Added to Library" after. In between, the founder looks at a
finished-LOOKING deliverable — a rendered landing page, a working four-input
pricing model — beside a button marked Approve, with nothing saying it is
unsaved. That is where the promise either becomes concrete or is forgotten.

Retires on the first approval, account-wide, because the rule was learned and
not because a counter ran out. Muted rather than accented: it is a status
note, and the Approve button beside it already carries the emphasis.

Reads `firstApprovalAt` live rather than through a captured value, so
approving clears the note from every other card on screen in the same frame.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Views/Copilot/CopilotChatView.swift codepetTests/FirstApprovalNoteTests.swift
git commit -F /tmp/c-fa4.txt
```

---

### Task 5: See it, then document it

- [ ] **Step 1: Render the card and read it**

Rendering caught two bugs in this feature's predecessor that no test could have — a possessive applied to a sentence-shaped title, and a preview with no tap target. `CopilotChatView`'s `draftCard` takes an `@EnvironmentObject`, so render the pieces instead.

Create `codepetTests/ZZTempNoteRenderTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import codepet

final class ZZTempNoteRenderTests: XCTestCase {
    func testDumpNote() throws {
        let view = VStack(alignment: .leading, spacing: 9) {
            Text("Decide what free and paid mean")
                .font(.pixelSystem(size: 14.5, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(DraftCardCopy.notFiledNote(.en))
                .font(.pixelSystem(size: 11.5))
                .foregroundColor(CodepetTheme.mutedText)
            Text(DraftCardCopy.notFiledNote(.vi))
                .font(.pixelSystem(size: 11.5))
                .foregroundColor(CodepetTheme.mutedText)
        }
        .frame(width: 320, alignment: .leading)
        .padding(12)
        .background(Color(hex: "#F7F5FC"))

        let r = ImageRenderer(content: view)
        r.scale = 2
        let img = try XCTUnwrap(r.nsImage)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(img.tiffRepresentation)))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let path = "\(NSHomeDirectory())/Desktop/preview-not-filed.png"
        try png.write(to: URL(fileURLWithPath: path))
        print("[render] \(rep.pixelsWide)x\(rep.pixelsHigh) -> \(path)")
    }
}
```

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/ZZTempNoteRenderTests test 2>&1 | grep -oE "\[render\].*"
```

Open the PNG and read both lines. Check: the em dash renders as a dash and not a box; the Vietnamese diacritics are intact; the muted grey is legible against the card, not so faint it reads as disabled. Then delete the temp file:

```bash
rm codepetTests/ZZTempNoteRenderTests.swift
```

- [ ] **Step 2: Build signed and launch into the demo**

```bash
cd ~/Developer/codepet-two-mode
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build 2>&1 | grep -oE "BUILD (SUCCEEDED|FAILED)"
APP=~/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app
ls -l "$APP/Contents/MacOS/codepet" | awk '{print "binary:",$6,$7,$8}'
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 3
open "$APP" --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
sleep 14
ps -eo pid,comm | awk '$2 ~ /codepet$/ {print "running pid",$1}'
```

Compare the binary timestamp against `git log -1 --format=%ad --date=format:'%b %d %H:%M'`. Matching to the minute means the build is not stale.

- [ ] **Step 2b: Confirm on screen — the founder's step**

Screen Recording is denied on this machine, so these are checks only the founder can make:

1. Run any task → the card reads **"Not saved yet — approving files it in your Library."** above Approve/Redo
2. Press **Approve** → the note is replaced by "Added to Library" on that card
3. Run a second task → **no note** on the new card, because the rule is now learned
4. Relaunch → still no note (it is persisted, not per-session)

- [ ] **Step 3: Document it, and commit**

Add to `CLAUDE.md` under the prototype-mode section:

```markdown
- **A first draft says it is not saved yet**, until the founder's first approval. Gated on
  `CompanyState.firstApprovalAt`, set in `CompanyStore.fileApproval` — the one path both
  `approveDraft` and `approveTask` call. **Never derive this from an empty library:** the demo
  pre-files three artifacts (`DemoProject.filed`), so a derived signal goes quiet in prototype
  mode, and `FirstApprovalNoteTests` pins that.
```

```bash
cat > /tmp/c-fa5.txt <<'EOF'
docs: the first-draft note, and why it is not derived from the library

The trap is worth the four lines: an empty library reads as a perfect proxy
for "has never approved", and it is wrong exactly where the rule matters most
— prototype mode, whose fixture pre-files three artifacts so departments can
build on each other.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add CLAUDE.md
git commit -F /tmp/c-fa5.txt
```

---

## Self-Review

**Spec coverage.** Copy → Task 3 (`notFiledNote`) and Task 5 Step 1 (read on screen). Placement above Approve/Redo → Task 4 Step 3. Muted styling → Global Constraints + Task 4 Step 3. `firstApprovalAt` mirroring `introSeenAt` → Task 1. Rejected library-derivation → Global Constraints, Task 1 Step 3 doc comment, and Task 4 Step 1's pinning test. Both approve paths → Task 2, satisfied at the `fileApproval` chokepoint. Pure decision function → Task 3. Every spec test row maps: fresh account (Task 3), retired once set (Task 3), absent on approved card (Task 3), live rather than snapshot (Task 4 Step 3's note about reading `companyStore.company` directly), `approveTask` sets it (Task 2), nil `companyId` no crash (Task 2's `if let cid`), demo shows the note (Task 4).

**One spec deviation, deliberate.** The spec says "set by both approve paths". The code has a single chokepoint — `fileApproval`, which both call, with `ApprovalParityTests` already guarding that they agree — so Task 2 writes it once there. This satisfies the spec's intent (the board teaches the same lesson) with one site instead of two, and Task 2's `testApprovingFromTheBoardRecordsItToo` goes red if someone later moves the write into `approveDraft`.

**Placeholder scan.** No TBDs. Every code step carries complete code. Task 4 Step 2 explains why its test passes immediately rather than pretending it drives new code, and gives a break-the-guard procedure instead.

**Type consistency.** `firstApprovalAt` is `Date?` in Task 1 and read as `!= nil` in Tasks 2 and 4. `firstApprovalSaver` has the same `(String, Date) async -> Bool` signature at its declaration, its default, and its test injection. `shouldShowNotFiledNote(hasApproved:draftApproved:)` and `notFiledNote(_:)` are used with identical labels in Tasks 3 and 4. `CompanyData.saveFirstApproval` matches the saver's type.

**Known gap, out of scope by the spec.** The note does not appear in the Tasks draft-preview sheet, and the once-per-account roadmap briefing still only fires on the Roadmap surface.
