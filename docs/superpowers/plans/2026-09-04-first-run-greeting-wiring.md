# First-Run Greeting Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new founder's first screen carries the greeting that already exists and has never run.

**Architecture:** A `greetedAt: Date?` on `CompanyState` mirroring `firstApprovalAt` field-for-field; one pure gate; one call at the end of `hydrate`. `seedFirstRunGreeting` and `FirstRunGreetingBuilder` are untouched — they already work and are already tested.

**Tech Stack:** Swift 5, SwiftUI, XCTest, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Xcode 26.2.

**Spec:** `docs/superpowers/specs/2026-09-04-first-run-greeting-wiring-design.md`

## Global Constraints

- **A persisted flag, never `chatMessages.isEmpty` alone.** `newChat()` sets `chatMessages = []` (`CompanyStore.swift:1316`), so an empty-transcript condition would re-greet a founder every time they start a conversation.
- **Mirror `firstApprovalAt` exactly** — that field landed on 2026-09-04 and is the closest precedent: optional `Date` on the state, epoch millis on the wire, dedicated saver, `PrototypeMode.allowsCloudWrites` guard, fail-soft.
- **`CompanyState.init(from:)` is hand-written** and every key uses `decodeIfPresent`. A new field MUST be added there, or every company document written before today throws `keyNotFound` and fails to decode.
- **Do NOT call `startEnrichInterviewIfNeeded`.** It stays uncalled — connecting it is a separate product decision, and its comment is the record of why the greeting was dead. Leave the comment intact.
- **Do NOT edit `FirstRunGreetingBuilder` or `seedFirstRunGreeting`.** They are correct. This plan only gives them a caller.
- Commit with `git commit -F <file>`, never `-m`: bodies contain backticks and zsh would execute them.
- **Never `git stash` bare** — this worktree shares its stash stack with siblings and the stack holds another session's entry. Use a temporary WIP commit.
- `xcodebuild test` exits 65 for unrelated reasons (the XCTest host crashes on Xcode 26.2 when a `@MainActor ObservableObject` deallocates). **Never judge pass/fail from the exit code.** Read counts from `xcrun xcresulttool get test-results summary --path <bundle>`. A zero passed-count means the suite did not run — a failure, not a pass.
- **Before any `xcodebuild test`, stop the app** — a live app kills the test host, and `osascript` alone does not reliably do it:

```bash
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}')
[ -n "$PID" ] && kill "$PID" && sleep 2
ps -eo pid,comm | awk '$2 ~ /codepet$/ {print "STILL RUNNING",$1}'
```

  The last line must print nothing. Never `pkill -f codepet` — it matches sibling sessions.
- **Adding a saver to a path many suites exercise breaks every suite that does not inject it.** The real savers call `Firestore.firestore()`, which TRAPS rather than throwing under an unconfigured `FirebaseApp`, killing the host with a log reading "Restarting after unexpected exit" — which looks like an assertion failure and is not. This bit us on 2026-09-04 with `firstApprovalSaver` and cost two tasks to find. `hydrate` is exercised by MANY suites, so **Task 3 sweeps the neighbours in the same task rather than later.**

---

### Task 1: `greetedAt` on the model and the wire

**Files:**
- Modify: `codepet/Models/CompanyState.swift` — property, memberwise init, `init(from:)`
- Modify: `codepet/Services/CompanyData.swift` — DTO field, hydrate mapping, payload, saver
- Test: `codepetTests/FirstRunGreetingWiringTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `CompanyState.greetedAt: Date?`, `CompanyData.greetedPayload(_ at: Date) -> [String: Any]`, `CompanyData.saveGreeted(_ companyId: String, _ at: Date) async -> Bool`.

- [ ] **Step 1: Write the failing tests**

Create `codepetTests/FirstRunGreetingWiringTests.swift`:

```swift
// codepetTests/FirstRunGreetingWiringTests.swift
import XCTest
@testable import codepet

/// Guards on the first-run greeting actually reaching a founder.
///
/// `FirstRunGreetingBuilder` wrote the right message, carried an inline action to start the
/// first task, and was covered by two suites — and nothing called it. `seedFirstRunGreeting`
/// was reachable only from the first-run enrich interview's completion, and
/// `startEnrichInterviewIfNeeded` has no caller in the app; its own comment says so. So a new
/// founder got the hero and a task card, and the message that would have oriented them was
/// unreachable.
@MainActor
final class FirstRunGreetingWiringTests: XCTestCase {

    // MARK: - Task 1: the field and its wire shape

    /// Millis, not ISO — `introSeenAt` and `firstApprovalAt` beside it are numbers.
    func testGreetedPayloadIsEpochMillis() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(CompanyData.greetedPayload(at)["greetedAt"] as? Double,
                       1_700_000_000_000)
    }

    /// **The landmine.** `CompanyState.init(from:)` is hand-written because Swift's synthesised
    /// `Decodable` throws `keyNotFound` rather than falling back to a declared default. Every
    /// company document in Firestore predates this field.
    func testACompanyDocumentWithoutTheFieldStillDecodes() throws {
        let json = #"{"companionId":"byte","stage":"building"}"#
        let state = try JSONDecoder().decode(CompanyState.self, from: Data(json.utf8))
        XCTAssertNil(state.greetedAt)
        XCTAssertEqual(state.companionId, "byte")
    }

    func testItRoundTripsWhenPresent() throws {
        var state = CompanyState.empty
        state.greetedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let back = try JSONDecoder().decode(
            CompanyState.self, from: try JSONEncoder().encode(state))
        XCTAssertEqual(back.greetedAt?.timeIntervalSince1970, 1_700_000_000)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstRunGreetingWiringTests test 2>&1 | tail -12
```

Expected: FAIL — `type 'CompanyData' has no member 'greetedPayload'`.

- [ ] **Step 3: Add the property**

In `codepet/Models/CompanyState.swift`, immediately after the `var firstApprovalAt: Date?` property and its doc comment, add:

```swift
    /// When this account was greeted for the first time. Account-scoped like `introSeenAt` and
    /// `firstApprovalAt` above.
    ///
    /// **Persisted rather than derived from an empty transcript.** `newChat()` sets
    /// `chatMessages = []`, so "no messages" is true again every time the founder starts a
    /// conversation — gating on that alone would welcome someone who has used the product for
    /// a month. The transcript is session-only; this is what makes "first run" mean first run.
    var greetedAt: Date?
```

In the memberwise init, after `firstApprovalAt: Date? = nil,` add:

```swift
         greetedAt: Date? = nil,
```

and in that init's body, after `self.firstApprovalAt = firstApprovalAt`, add:

```swift
        self.greetedAt = greetedAt
```

In `init(from decoder:)`, after the `firstApprovalAt = try c.decodeIfPresent(...)` line, add:

```swift
        greetedAt = try c.decodeIfPresent(Date.self, forKey: .greetedAt)
```

`CodingKeys` is synthesised for this type — verified, the file has no hand-written enum. Do not add one.

- [ ] **Step 4: Add the DTO field, mapping, payload and saver**

In `codepet/Services/CompanyData.swift`, after the `var firstApprovalAt: Double?` line, add:

```swift
    var greetedAt: Double?        // epoch MILLIS, same shape as the two above
```

In the hydrate mapping, after the `firstApprovalAt: doc.firstApprovalAt.map { ... },` line, add:

```swift
            greetedAt: doc.greetedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
```

After `saveFirstApproval`, add:

```swift
    /// Pure Firestore payload for the greeted write — testable without Firestore.
    static func greetedPayload(_ at: Date) -> [String: Any] {
        ["greetedAt": at.timeIntervalSince1970 * 1000]
    }

    /// Write companies/{uid}.greetedAt, merge. Fail-soft: false on error — a lost write means
    /// the founder is greeted once more, never a broken screen.
    static func saveGreeted(_ companyId: String, _ at: Date) async -> Bool {
        // Prototype mode rebuilds the company from fixtures on every load, so a write here
        // would put demo data in a real founder's document. Reported as done rather than
        // failed: nothing was attempted. Same guard as `saveIntroSeen` and `saveFirstApproval`.
        //
        // This is also WHY the demo shows the greeting on every launch: the flag never
        // persists there, which is what a demo wants.
        guard PrototypeMode.allowsCloudWrites else { return true }
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(greetedPayload(at), merge: true)
            return true
        } catch {
            return false
        }
    }
```

- [ ] **Step 5: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
rm -rf /tmp/g1.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstRunGreetingWiringTests \
  -resultBundlePath /tmp/g1.xcresult test > /tmp/g1.log 2>&1
grep -E '^/Users.*error:' /tmp/g1.log | head -5
xcrun xcresulttool get test-results summary --path /tmp/g1.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 3`.

- [ ] **Step 6: Commit**

```bash
cat > /tmp/c-g1.txt <<'EOF'
feat(company): remember when an account was first greeted

`greetedAt`, the third field of this exact shape after `introSeenAt` and
`firstApprovalAt`: optional Date on the state, epoch millis on the wire, merge
write, fail-soft, and silent under prototype mode.

Persisted rather than derived from an empty transcript, because `newChat()`
empties the transcript — so "no messages" is true again every time the founder
starts a conversation, and gating on that alone would welcome someone who has
used the product for a month.

Added to the hand-written `init(from:)` as well as the property: that
initializer exists because Swift's synthesised Decodable throws keyNotFound
rather than defaulting, and every company document in Firestore predates this
field. A test decodes a document without it.

3 passed / 0 failed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Models/CompanyState.swift codepet/Services/CompanyData.swift \
        codepetTests/FirstRunGreetingWiringTests.swift
git commit -F /tmp/c-g1.txt
```

---

### Task 2: The gate, as a pure static

**Files:**
- Create: `codepet/Models/FirstRunGreetingGate.swift`
- Test: `codepetTests/FirstRunGreetingWiringTests.swift` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: `FirstRunGreetingGate.shouldGreet(hasBeenGreeted: Bool, transcriptIsEmpty: Bool, hasTasks: Bool) -> Bool`.

- [ ] **Step 1: Write the failing tests**

Append inside `FirstRunGreetingWiringTests`, before its closing brace:

```swift
    // MARK: - Task 2: the gate

    /// A pure static, not a condition inside `hydrate`. Four inputs' worth of truth table is
    /// where a bug here would live, and a condition inside an async store method is only
    /// testable by driving the whole store.
    func testGreetsOnlyAFreshAccountWithWorkToName() {
        XCTAssertTrue(FirstRunGreetingGate.shouldGreet(
            hasBeenGreeted: false, transcriptIsEmpty: true, hasTasks: true))
    }

    func testDoesNotGreetTwice() {
        XCTAssertFalse(FirstRunGreetingGate.shouldGreet(
            hasBeenGreeted: true, transcriptIsEmpty: true, hasTasks: true))
    }

    /// The trap the persisted flag exists for: `newChat()` empties the transcript.
    func testDoesNotGreetIntoAConversationInProgress() {
        XCTAssertFalse(FirstRunGreetingGate.shouldGreet(
            hasBeenGreeted: false, transcriptIsEmpty: false, hasTasks: true))
    }

    /// With no roadmap there is no first move to name, and the builder falls back to "Take a
    /// look around…" — a weaker message not worth spending the one-time greeting on. Wait for
    /// the next hydrate, when the roadmap has resolved.
    func testDoesNotGreetBeforeTheRoadmapExists() {
        XCTAssertFalse(FirstRunGreetingGate.shouldGreet(
            hasBeenGreeted: false, transcriptIsEmpty: true, hasTasks: false))
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstRunGreetingWiringTests test 2>&1 | tail -10
```

Expected: FAIL — `cannot find 'FirstRunGreetingGate' in scope`.

- [ ] **Step 3: Create the gate**

Create `codepet/Models/FirstRunGreetingGate.swift`:

```swift
// codepet/Models/FirstRunGreetingGate.swift
import Foundation

/// Whether to greet the founder, as one pure decision.
///
/// **Why this type exists.** `FirstRunGreetingBuilder` and `CompanyStore.seedFirstRunGreeting`
/// were both correct and both dead: the greeting was reachable only from the first-run enrich
/// interview's completion, and nothing in the app starts that interview. A new founder got the
/// hero and a beacon card, and the message that would have oriented them never ran.
///
/// Pulled out as a static rather than written inline in `hydrate` for the same reason
/// `DraftPayloadPreview.hasStructuredPreview` is: the decision is where a bug here would live,
/// and a condition inside an async store method is only testable by driving the whole store.
enum FirstRunGreetingGate {

    /// - `hasBeenGreeted`: `company.greetedAt != nil` — account-scoped and persisted.
    /// - `transcriptIsEmpty`: never greet into a conversation already in progress.
    /// - `hasTasks`: the greeting's value is naming the first move. With no roadmap,
    ///   `RoadmapEngine.nextStep` is nil and the builder falls back to "Take a look around…",
    ///   which is not worth spending a once-per-account message on. Waiting costs nothing —
    ///   the next hydrate has a task to name.
    static func shouldGreet(hasBeenGreeted: Bool,
                            transcriptIsEmpty: Bool,
                            hasTasks: Bool) -> Bool {
        !hasBeenGreeted && transcriptIsEmpty && hasTasks
    }
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
rm -rf /tmp/g2.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstRunGreetingWiringTests \
  -resultBundlePath /tmp/g2.xcresult test > /tmp/g2.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/g2.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 7`.

- [ ] **Step 5: Commit**

```bash
cat > /tmp/c-g2.txt <<'EOF'
feat(chat): the greeting's gate, as a pure static

Three inputs, four assertions, one expression. Out of `hydrate` for the same
reason `DraftPayloadPreview.hasStructuredPreview` is out of its view body: the
decision is where the bug would live, and a condition inside an async store
method is only testable by driving the whole store.

`hasTasks` is in the gate deliberately. With no roadmap, `nextStep` is nil and
the builder falls back to "Take a look around…" — a weaker message not worth
spending a once-per-account greeting on. Waiting costs nothing; the next
hydrate has a first move to name.

7 passed / 0 failed.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Models/FirstRunGreetingGate.swift codepetTests/FirstRunGreetingWiringTests.swift
git commit -F /tmp/c-g2.txt
```

---

### Task 3: Wire it into `hydrate`, and sweep the neighbours

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` — the saver property (~line 212), its init parameter (~line 323), its assignment (~line 386), and the tail of `hydrate` (~line 502)
- Test: `codepetTests/FirstRunGreetingWiringTests.swift` (append)
- Possibly modify: other suites in `codepetTests/` — see Step 5

**Interfaces:**
- Consumes: `CompanyState.greetedAt`, `CompanyData.saveGreeted` (Task 1); `FirstRunGreetingGate.shouldGreet` (Task 2); `seedFirstRunGreeting` (exists, unchanged).
- Produces: `CompanyStore.greetedSaver: (String, Date) async -> Bool` (injectable, defaulted).

- [ ] **Step 1: Write the failing tests**

Append inside `FirstRunGreetingWiringTests`:

```swift
    // MARK: - Task 3: through the store

    /// Same stubs as `CompanyStoreChatRunTests`: the live defaults reach Firestore and Firebase
    /// Auth, both of which trap under an unconfigured `FirebaseApp`.
    private func store(tasks: [RoadmapTask],
                       greetedAt: Date? = nil,
                       saver: @escaping (String, Date) async -> Bool = { _, _ in true })
        -> CompanyStore {
        CompanyStore(loader: { _ in
            var s = CompanyState(brief: {
                var b = CompanyBrief(); b.founderName = "Mona"; b.projectName = "Murror"; return b
            }(), departments: [], library: [], stage: .building,
               companionId: "byte", onboardedAt: Date(), tasks: tasks)
            s.greetedAt = greetedAt
            return s
        }, saver: { _, _ in true }, tasksSaver: { _, _ in true },
           chatSender: { _ in nil },
           chatStreamer: { _ in
               AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
           },
           taskRunner: { _ in nil }, librarySaver: { _, _ in true },
           firstApprovalSaver: { _, _ in true },
           greetedSaver: saver,
           decisionExtractor: { _, _ in [] })
    }

    private var runnable: [RoadmapTask] {
        [RoadmapTask(id: "t1", title: "Write your landing page copy", detail: "",
                     phase: .find, who: .does, dept: "mkt")]
    }

    /// The whole point: a new founder's first screen carries the greeting.
    func testAFreshAccountIsGreetedOnHydrate() async {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        XCTAssertEqual(s.chatMessages.count, 1)
        let g = s.chatMessages[0]
        XCTAssertEqual(g.role, .companion)
        XCTAssertTrue(g.text.contains("Mona"), g.text)
        XCTAssertTrue(g.text.contains("Murror"), g.text)
        XCTAssertTrue(g.text.contains("Write your landing page copy"), g.text)
        XCTAssertNotNil(g.firstRunAction, "the founder must be able to start it from here")
        XCTAssertNotNil(s.company.greetedAt, "and the account is marked as greeted")
    }

    /// The rule the greeting itself states. Asserted because it is the reason this message is
    /// worth reaching a founder at all, and a copy edit that dropped it should go red.
    func testTheGreetingStatesThatNothingShipsWithoutApproval() async {
        let s = store(tasks: runnable)
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.chatMessages[0].text.contains("nothing ships without your say-so"),
                      s.chatMessages[0].text)
    }

    func testAnAlreadyGreetedAccountIsNotGreetedAgain() async {
        let s = store(tasks: runnable, greetedAt: Date(timeIntervalSince1970: 1))
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.chatMessages.isEmpty)
    }

    func testAnEmptyRoadmapIsNotGreeted() async {
        let s = store(tasks: [])
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.chatMessages.isEmpty)
        XCTAssertNil(s.company.greetedAt, "and it is NOT marked greeted — try again next time")
    }

    /// Fail-soft: a rejected write still marks the account greeted in memory, so a founder is
    /// not welcomed twice inside one session.
    func testAFailedWriteStillMarksTheSessionGreeted() async {
        let s = store(tasks: runnable, saver: { _, _ in false })
        await s.hydrate(companyId: "u")
        XCTAssertEqual(s.chatMessages.count, 1)
        XCTAssertNotNil(s.company.greetedAt)
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/FirstRunGreetingWiringTests test 2>&1 | tail -12
```

Expected: FAIL — `extra argument 'greetedSaver' in call`.

- [ ] **Step 3: Add the injectable saver**

In `codepet/Managers/CompanyStore.swift`, immediately after `private let firstApprovalSaver: (String, Date) async -> Bool`, add:

```swift
    private let greetedSaver: (String, Date) async -> Bool
```

In the initializer's parameter list, immediately after the `firstApprovalSaver:` parameter, add:

```swift
         greetedSaver: @escaping (String, Date) async -> Bool = CompanyData.saveGreeted,
```

In the initializer's body, immediately after `self.firstApprovalSaver = firstApprovalSaver`, add:

```swift
        self.greetedSaver = greetedSaver
```

**Note the ordering.** `greetedSaver` must sit next to `firstApprovalSaver` in the declaration, which is well ABOVE `decisionExtractor`. Swift requires labelled arguments at a call site to appear in declaration order, so every test that passes both must put `greetedSaver` before `decisionExtractor`. Task 3 Step 1's helper already does.

- [ ] **Step 4: Seed at the end of `hydrate`**

In `hydrate(companyId:)`, at the very end of the method — immediately after the `codingMemoryGate(loaded.founderPrefs.memoryEnabled)` line and before the closing brace — add:

```swift
        // The first-run greeting, which until now had no caller at all: it was reachable only
        // from the first-run enrich interview's completion, and nothing in the app starts that
        // interview (see `startEnrichInterviewIfNeeded`'s own comment). So a new founder got the
        // hero and a beacon card, and the message that names their first move never ran.
        //
        // HERE rather than at the onboarding→app edge, deliberately: prototype mode boots an
        // already-onboarded company and never crosses that edge, which is why this greeting has
        // never been seen in the demo. `saveGreeted` is silent under prototype mode, so the
        // demo re-greets on every launch — which is what a demo wants.
        if FirstRunGreetingGate.shouldGreet(hasBeenGreeted: company.greetedAt != nil,
                                            transcriptIsEmpty: chatMessages.isEmpty,
                                            hasTasks: !company.tasks.isEmpty) {
            seedFirstRunGreeting(language: language)
            let now = Date()
            company.greetedAt = now
            // Fire-and-forget and fail-soft, matching `markIntroSeen`: a lost write costs one
            // extra greeting, never a broken screen.
            if let cid = companyId { _ = await greetedSaver(cid, now) }
        }
```

**`hydrate` has no `language` parameter.** Check its signature first. If it does not take one, add `language: AppLanguage` as a parameter with a default of `.en` and pass it through from the call sites — OR, if a language is already reachable on the store, use that. Resolve this before writing the code and record which you chose in your report; do not guess silently.

- [ ] **Step 5: Sweep the neighbours — IN THIS TASK**

`hydrate` is exercised by many suites, and this task adds a saver call to it. On 2026-09-04 the identical change to `fileApproval` broke five suites and took two tasks to find, because the suite proving the new code works is the one that stubs the thing that breaks.

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
grep -ln "hydrate(companyId" codepetTests/*.swift
```

Every suite that appears there is a candidate. Run all of them, plus the approval and demo suites:

```bash
for s in $(grep -ln "hydrate(companyId" codepetTests/*.swift | xargs -n1 basename | sed 's/\.swift//') \
         FirstRunGreetingTests CompanyStoreFirstRunGreetingTests ApprovalParityTests \
         DemoProjectFiledTests PrototypeParityTests; do
  rm -rf /tmp/n-$s.xcresult
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/n-$s.xcresult test > /tmp/n-$s.log 2>&1
  p=$(xcrun xcresulttool get test-results summary --path /tmp/n-$s.xcresult 2>/dev/null | grep '"passedTests"' | head -1 | tr -dc 0-9)
  f=$(xcrun xcresulttool get test-results summary --path /tmp/n-$s.xcresult 2>/dev/null | grep '"failedTests"' | head -1 | tr -dc 0-9)
  printf "%-34s pass=%-4s fail=%s\n" "$s" "${p:-0}" "${f:-0}"
done
```

**Two failure shapes to expect, and they are different:**

1. **A host crash** — the log says "Restarting after unexpected exit, crash, or test timeout" and counts are carried over from previous launches. That means a suite reached the real `CompanyData.saveGreeted`. Fix by adding `greetedSaver: { _, _ in true },` to that suite's `CompanyStore(...)` construction, before `decisionExtractor:`.
2. **A real assertion failure** — a suite that asserts on `chatMessages` now finds a greeting it did not expect. That is this change altering behaviour those tests describe, and it needs judgment, not a stub: the greeting may be correct there, in which case update the expectation and say so in your report; or the gate may be wrong, in which case STOP and report rather than editing assertions to match.

Do not proceed until every row reads `fail=0` with `pass>0`.

- [ ] **Step 6: Commit**

Commit the wiring and any neighbour fixes as TWO commits: the wiring first, then the sweep fallout with its own message naming which suites and why.

```bash
cat > /tmp/c-g3.txt <<'EOF'
feat(chat): a new founder is finally greeted

The greeting has existed and worked since the native port and has never once
run. It was reachable only from the first-run enrich interview's completion,
and nothing in the app starts that interview — its own comment says so. So a
new founder got the hero and a beacon card, and the message naming their first
move was unreachable. Reported by the founder as "as soon as they log in
they're directed straight to a task card — where's the initial prompt?".

Seeded at the end of `hydrate` rather than at the onboarding→app edge, and
that choice is load-bearing: prototype mode boots an already-onboarded company
and never crosses that edge, which is exactly why this message has never been
seen in the demo. `saveGreeted` is silent under prototype mode, so the demo
greets on every launch.

Gated on a persisted `greetedAt`, not on an empty transcript: `newChat()`
empties the transcript, so that condition is true again every time the founder
starts a conversation.

It also happens to state the approval rule — "nothing ships without your
say-so" — which the 2026-09-04 approval-note spec claimed no path a new user
walks says. That claim was made after checking the cold open and the hero, and
not this. A test now pins the phrase.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Managers/CompanyStore.swift codepetTests/FirstRunGreetingWiringTests.swift
git commit -F /tmp/c-g3.txt
```

---

### Task 4: See it, then document it

- [ ] **Step 1: Build signed and launch into the demo**

```bash
cd ~/Developer/codepet-two-mode
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates build 2>&1 | grep -oE "BUILD (SUCCEEDED|FAILED)"
APP=~/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app
ls -l "$APP/Contents/MacOS/codepet" | awk '{print "binary:",$6,$7,$8}'
git log -1 --format="commit: %ad" --date=format:'%b %d %H:%M'
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 3
open "$APP" --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror
sleep 14
ps -eo pid,comm | awk '$2 ~ /codepet$/ {print "running pid",$1}'
```

Binary and commit timestamps must match to the minute, or the build is stale.

- [ ] **Step 2: Confirm on screen**

The demo is the reason this hook was chosen, so it is checkable here rather than only by a founder:

1. Launch → the chat opens with **a greeting message**, not a bare hero. It names Mona, names Murror, names the first task, and ends "nothing ships without your say-so."
2. The greeting carries an inline action to start that task.
3. Start a **new chat** → **no second greeting**. This is the `newChat()` trap; if a greeting appears here, the flag is not doing its job.
4. Quit and relaunch → the greeting is back (prototype mode does not persist the flag — expected and correct).

Screen Recording is granted on this machine (corrected 4 Sep), so `screencapture -x` works; delete captures after reading them, and bring the app frontmost with `tell application "System Events" to set frontmost of process "codepet" to true` rather than `tell application "codepet" to activate`, which fails with -10673.

- [ ] **Step 3: Document it, and commit**

Add to `CLAUDE.md`, under the prototype-mode section:

```markdown
- **A new account is greeted on hydrate**, once, gated on `CompanyState.greetedAt` — the third
  field of that shape after `introSeenAt` and `firstApprovalAt`. Seeded in `hydrate`, NOT at the
  onboarding edge: prototype mode never crosses that edge, which is why the greeting went
  unseen for months. `saveGreeted` is silent under prototype mode, so the demo greets every
  launch. **Never gate this on an empty transcript** — `newChat()` empties it.
- `startEnrichInterviewIfNeeded` is still uncalled. That is deliberate and separate; its comment
  is the record of why the greeting was dead.
```

```bash
cat > /tmp/c-g4.txt <<'EOF'
docs: the greeting's hook point, and why it is not the onboarding edge

Prototype mode boots an already-onboarded company, so anything seeded at the
onboarding→app edge is invisible in the demo — which is how a working,
tested greeting went unseen long enough to be assumed absent.

Also records the `newChat()` trap: the transcript is session-only and gets
emptied, so it can never be the gate for a once-per-account message.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add CLAUDE.md
git commit -F /tmp/c-g4.txt
```

---

## Self-Review

**Spec coverage.** `greetedAt` mirroring `firstApprovalAt` → Task 1. The pure gate with all three inputs → Task 2. The `hydrate` hook and the prototype-mode reasoning → Task 3. Every spec test row maps: fresh account greeted (Task 3), not twice (Tasks 2 + 3), not after `newChat` (Task 2's `transcriptIsEmpty` case), not on an empty roadmap (Tasks 2 + 3), carries its `FirstRunAction` (Task 3), encode/decode and the `keyNotFound` landmine (Task 1), prototype greets every launch (Task 4 Step 2, on screen — it cannot be unit-tested without a real Firestore).

**One spec row moved to on-screen verification.** "Prototype mode greets on every launch" depends on `PrototypeMode.allowsCloudWrites` short-circuiting a real Firestore write, which a unit test cannot observe. Task 4 Step 2 check 4 covers it instead. Recorded rather than dropped.

**Placeholder scan.** One deliberate unknown, flagged rather than guessed: Task 3 Step 4 does not know whether `hydrate` takes a `language` parameter, tells the implementer to check, gives both resolutions, and requires the choice to be reported. Everything else carries complete code.

**Type consistency.** `greetedAt` is `Date?` in Task 1 and read as `!= nil` in Task 3. `greetedSaver` has the same `(String, Date) async -> Bool` at its declaration, default, and test injection. `shouldGreet(hasBeenGreeted:transcriptIsEmpty:hasTasks:)` is used with identical labels in Tasks 2 and 3. `CompanyData.saveGreeted` matches the saver's type.

**The lesson from the last plan is applied.** Task 3 sweeps the neighbours in the same task that adds the saver, and distinguishes the two failure shapes — a host crash needing a stub, versus a real assertion failure needing judgment — because conflating them is how a test gets edited to match a bug.
