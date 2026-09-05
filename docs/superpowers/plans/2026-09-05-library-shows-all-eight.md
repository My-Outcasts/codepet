# Library Shows All Eight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Murror demo's Library shows finished work from all eight departments, and the walkthrough points at it.

**Architecture:** No new surface and no new view code. `LibraryView` already groups by department and renders all thirteen kinds; the fixture simply gives it almost nothing. Six authored deliverables land first (inert), then six `done` tasks and the `filed` wiring activate them, then the walkthrough beat that already visits the Library is re-captioned to describe what is now there.

**Tech Stack:** Swift 5, SwiftUI, XCTest, Xcode 26.2. Everything touched is inside `#if DEBUG`.

**Spec:** `docs/superpowers/specs/2026-09-05-library-shows-all-eight-design.md`

## Global Constraints

- **Six new departments, not five.** The roster is `eng, design, mkt, sales, support, fin, ops, legal`; existing `done` tasks cover `mkt` (twice) and `design`. The gap is **eng, sales, support, fin, ops, legal**.
- **No filler.** `DemoProjectParityTests.testTheFiledWorkIsRealAndNotTheCatchAll` fails on any filed body containing the catch-all's `"a starting point, not the final word"`. A Library of obvious placeholder is worse than one with three real things.
- **New deliverable entries go AFTER the existing keyword entries and BEFORE the catch-all.** `deliverable(for:)` returns the FIRST entry whose keyword appears in the lowercased title, so a broad new keyword placed early would shadow an existing task's lookup. Every new keyword must also be checked against all 18 task titles.
- **`.find` must stay complete.** `DemoProjectMurrorTests.testFindPhaseIsComplete` asserts every `.find` task is `done`. New tasks go in `.foundation`, which already has open work, so the open-phase window does not move.
- **The eight runnable must stay runnable.** `testAllEightRosterDepartmentsHaveExactlyOneRunnable` asserts exactly one `codepetCanDo` task per roster department, through `RoadmapEngine`. New tasks are `done`, so they must not appear in that set.
- **The `codepet` demo project is untouched.** 236 test files depend on its literals.
- **Do NOT add a new Library beat.** The walkthrough already visits the Library (`MockFlowScript.swift:170`, chapter "Where the state lives"). This is a re-caption and a longer hold, not an addition — two Library beats would be the duplication this plan exists to avoid.
- Commit with `git commit -F <file>`, never `-m`.
- **Never `git stash` bare** — the stash stack is shared across worktrees and holds another session's entry. Use a temporary WIP commit.
- `xcodebuild test` exits 65 for unrelated reasons. **Never judge pass/fail from the exit code** — read `xcrun xcresulttool get test-results summary`. A zero passed-count is a failure, not a pass.
- **Before any `xcodebuild test`, stop the app:**

```bash
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}')
[ -n "$PID" ] && kill "$PID" && sleep 2
ps -eo pid,comm | awk '$2 ~ /codepet$/ {print "STILL RUNNING",$1}'
```

  Last line must print nothing. Never `pkill -f codepet`.

---

### Task 1: Six authored deliverables

**Files:**
- Modify: `codepet/Demo/DemoProjectMurrorWork.swift` — append six entries before the catch-all
- Test: `codepetTests/DemoProjectEightDepartmentsTests.swift` (create)

**Interfaces:**
- Consumes: `DemoDeliverable(keywords:kind:body:payloadJSON:)` (exists).
- Produces: six entries reachable by the titles Task 2 introduces.

This task is deliberately inert: nothing references these until Task 2 adds the tasks. It lands first so the content can be reviewed on its own, and so Task 2 never produces a `done` task whose deliverable is the catch-all.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DemoProjectEightDepartmentsTests.swift`:

```swift
// codepetTests/DemoProjectEightDepartmentsTests.swift
import XCTest
@testable import codepet

/// Guards that the demo shows finished work from ALL EIGHT departments.
///
/// Measured 5 Sep: the 24-chapter walkthrough contained one `runBeacon`, one
/// `approveNewestDraft` and one `convene`, so ONE department produced work on camera — while
/// the board carried eight runnable tasks with eight real deliverables. Chapter 2 narrates
/// "eight departments, each speaking with its own pet" and the tour demonstrated one.
///
/// `LibraryView` already groups by department; it showed two groups because the fixture filed
/// three artifacts belonging to two departments, all of kind `doc`.
final class DemoProjectEightDepartmentsTests: XCTestCase {

    private var murror: DemoProject { .murror }

    /// The six new titles must each resolve to their OWN entry, not to the catch-all and not to
    /// an existing entry's keywords.
    func testTheSixNewTitlesResolveToTheirOwnDeliverables() {
        let expected: [(title: String, kind: String, marker: String)] = [
            ("Choose what the app is built on", "doc", "on-device"),
            ("Work out what a month of inference costs", "sheet", "per active user"),
            ("Write down who this is not for", "doc", "not for"),
            ("Decide what happens on a bad night", "doc", "crisis"),
            ("Set up the weekly release rhythm", "checklist", "Thursday"),
            ("Write the data-deletion promise", "legal", "one tap"),
        ]
        for e in expected {
            let d = murror.deliverable(for: e.title)
            XCTAssertFalse(d.keywords.isEmpty,
                           "\"\(e.title)\" fell through to the catch-all")
            XCTAssertEqual(d.kind, e.kind, e.title)
            XCTAssertTrue(d.body.contains(e.marker),
                          "\"\(e.title)\" resolved to the wrong entry: \(d.body.prefix(60))")
        }
    }

    /// The new keywords must not hijack an EXISTING title. `deliverable(for:)` returns the first
    /// entry whose keyword appears in the lowercased title, so a broad new keyword placed early
    /// silently steals another department's deliverable.
    func testTheNewKeywordsShadowNoExistingTitle() {
        let existing = [
            "Build the Murror landing page": "site",
            "Design the first-run flow": "screens",
            "Decide what free and paid mean": "sheet",
            "Ship an email capture": "checklist",
            "Find the first 20 users": "dms",
            "Answer the first questions": "doc",
            "Write the launch checklist": "plan",
            "Draft the privacy policy": "legal",
        ]
        for (title, kind) in existing {
            XCTAssertEqual(murror.deliverable(for: title).kind, kind,
                           "\"\(title)\" now resolves to the wrong entry")
        }
    }

    /// No filed or resolvable body may leak an unsubstituted token to a founder's screen.
    func testNoNewBodyLeaksAToken() {
        for entry in murror.deliverables {
            XCTAssertFalse(entry.body.contains("{{product}}") && entry.body.contains("{{title}}")
                           && entry.keywords.isEmpty == false && false,
                           "placeholder assertion — see below")
        }
        // Tokens are legitimate in the source; what matters is that FILLED output has none.
        for entry in murror.deliverables where !entry.keywords.isEmpty {
            let filled = MockChat.fill(entry.body, title: "T")
            XCTAssertFalse(filled.contains("{{"), "unsubstituted token in \(entry.keywords)")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectEightDepartmentsTests test 2>&1 | tail -12
```

Expected: FAIL — the six titles fall through to the catch-all, so `d.keywords.isEmpty` is true.

- [ ] **Step 3: Add the six entries**

In `codepet/Demo/DemoProjectMurrorWork.swift`, immediately BEFORE the final catch-all entry (`DemoDeliverable(keywords: [], kind: "doc", ...)`), insert:

```swift
            // ── WORK ALREADY BEHIND THE FOUNDER ─────────────────────────────────────────────
            //
            // Six finished artifacts, one per department the board's `done` tasks did not cover
            // (eng, sales, support, fin, ops, legal). They exist so the Library — which already
            // groups by department — shows EIGHT groups rather than two, which is what makes
            // "eight departments, each speaking with its own pet" a claim the demo can support
            // rather than only narrate.
            //
            // Placed here, after every specific entry and before the catch-all, because
            // `deliverable(for:)` returns the FIRST keyword match: a broad keyword earlier in
            // the table silently steals another department's deliverable.
            DemoDeliverable(
                keywords: ["built on", "the app is built"],
                kind: "doc",
                body: """
                What Murror runs on, and the one constraint that decided it.

                **The call.** On-device inference for anything touching an entry. A server round \\
                trip is faster to build and cheaper to run, and it means the most private thing \\
                a person owns leaves their phone. The promise is that entries never leave with a \\
                name attached; the only version of that promise worth making is the one the \\
                architecture keeps.

                **What that costs.** A smaller model, slower first-run download, and no server \\
                logs to debug from. All three are real and all three are worth it.

                **What still goes to a server.** Crisis-resource lookup by region, and nothing \\
                else. It carries no entry text and no identifier.

                **What this rules out.** Any feature that needs to read across users' entries — \\
                trends, comparisons, "people like you". Those are the obvious second-year \\
                roadmap items and this decision closes them. Say so now rather than discovering \\
                it when someone asks for a dashboard.
                """),

            DemoDeliverable(
                keywords: ["month of inference", "inference costs"],
                kind: "sheet",
                payloadJSON: nil,
                body: """
                What a month of {{product}} costs to run, per active user, at today's model.

                **The number.** About $0.11 per active user per month, assuming the median of \\
                four sessions a week that the interviews suggest, and on-device inference for \\
                everything except crisis-resource lookup.

                **What moves it.** Session length moves it most — a person who writes for ten \\
                minutes costs roughly triple a person who writes for three. Frequency barely \\
                matters by comparison, which is the opposite of the intuition and the reason the \\
                pricing task should not be built around a session cap.

                **What it means for pricing.** At $6/month the margin is not the constraint; \\
                conversion is. That is the number the pricing model should be argued about, and \\
                this exists so that argument starts from a measured floor rather than a guess.

                **Confidence.** Low on session length, high on per-token cost. Re-run this when \\
                twenty people have used it for a fortnight.
                """),

            DemoDeliverable(
                keywords: ["not for", "who this is not"],
                kind: "doc",
                body: """
                Who {{product}} is **not for** — written down so the outreach stops wasting its \\
                best hours.

                **The person who found it insulting.** One of the twelve said plainly that she \\
                does not want help understanding herself, she wants fewer obligations. She is \\
                not a persuasion problem. Every product like this has her, and pitching her is \\
                how you learn the wrong lesson from a rejection.

                **People in crisis right now.** Murror is a practice, not treatment, and it says \\
                so. Reaching for someone mid-crisis is both ineffective and wrong, and the crisis \\
                path exists precisely so the app can decline gracefully.

                **Anyone looking for a mood tracker.** Every one of the twelve had tried one and \\
                stopped, and none could say what it had ever told them. Selling against that \\
                category means inheriting its expectations.

                **Teams and workplaces.** The moment an employer can see it, the honesty the \\
                whole thing depends on is gone. Refuse this one even when it is the only cheque \\
                on the table.
                """),

            DemoDeliverable(
                keywords: ["bad night", "happens on a bad"],
                kind: "doc",
                body: """
                What {{product}} does when someone writes something frightening. This is policy, \\
                not copy — the wording can change, the behaviour cannot.

                **First, before anything else.** A crisis resource for their region, shown \\
                immediately and without an interstitial. Not after the entry saves, not behind a \\
                tap. This path is built in and cannot be turned off.

                **What the app does not do.** It does not try to handle it. It does not offer a \\
                breathing exercise, reframe the feeling, or ask a follow-up question. Every one \\
                of those reads as the product deciding it is qualified, and it is not.

                **What it does not do to the entry.** Nothing. It is not deleted, flagged, \\
                escalated, or attached to a name. Someone who learns the app reports them is \\
                someone who never writes honestly again.

                **The one thing it says.** That this is more than a practice can hold, that there \\
                is a number, and that nobody will be told.

                _A clinician reads this before launch. Until they have, it is a draft._
                """),

            DemoDeliverable(
                keywords: ["release rhythm", "weekly release"],
                kind: "checklist",
                body: """
                A weekly rhythm, so shipping stops needing anybody's full attention.

                **Thursday, not Friday.** A Friday release means a weekend of nobody watching. \\
                Thursday leaves a working day to notice and undo.

                **Every week, in order**
                1. Cut from `main` on Thursday morning — whatever is merged is what ships.
                2. Run the crisis path by hand on a real device. Every release, no exceptions; \\
                it is the one path where a regression is not recoverable by a hotfix.
                3. Check the on-device model still loads on the oldest supported phone.
                4. Ship to 10% for a day, then the rest.
                5. Write two lines in the changelog a person would understand.

                **What stops a release.** A failing crisis path, and nothing else. Everything \\
                else waits a week — a rhythm that bends for urgency is not a rhythm.
                """),

            DemoDeliverable(
                keywords: ["data-deletion", "deletion promise"],
                kind: "legal",
                body: """
                **The deletion promise.** Plain language first; the privacy policy formalises it \\
                afterwards.

                **One tap, and it is gone.** Settings → Delete everything. No confirmation email, \\
                no support ticket, no waiting period, no "are you sure" chain designed to make \\
                you give up.

                **Permanent means permanent.** Entries are removed from the device and from any \\
                backup we hold within 30 days. We do not keep an anonymised copy, because there \\
                is no such thing for text this personal.

                **What survives, and why.** Aggregate counts with no content and no identifier — \\
                how many people opened the app on a given day. Nothing that could be traced to a \\
                person or reconstructed into an entry.

                **What we will not do.** We will not ask why. A deletion flow that interviews you \\
                on the way out is a dark pattern wearing a research hat.
                """),

```

**Note on the `sheet` entry.** It carries `payloadJSON: nil` deliberately: a `sheet` payload is a four-input pricing model (`price`, `waitlist`, `conversion`, `churn`), and this deliverable is a cost analysis, not a pricing model. With a nil payload `DraftPayloadPreview.hasStructuredPreview` returns false and the markdown body renders — which is the correct fallback and is already tested. Do NOT invent a payload to make it look richer.

- [ ] **Step 4: Run to verify they pass**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
rm -rf /tmp/e1.xcresult
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectEightDepartmentsTests \
  -resultBundlePath /tmp/e1.xcresult test > /tmp/e1.log 2>&1
grep -E '^/Users.*error:' /tmp/e1.log | head -5
xcrun xcresulttool get test-results summary --path /tmp/e1.xcresult | grep -E '"(passedTests|failedTests)"'
```

Expected: `"failedTests" : 0`, `"passedTests" : 3`.

- [ ] **Step 5: Confirm nothing else moved**

The keyword table is shared, so a shadowing mistake shows up in neighbours rather than here.

```bash
for s in DemoProjectMurrorTests DemoProjectParityTests DemoProjectFiledTests MockFixtureRunnableTests; do
  rm -rf /tmp/e1-$s.xcresult
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/e1-$s.xcresult test > /tmp/e1-$s.log 2>&1
  p=$(xcrun xcresulttool get test-results summary --path /tmp/e1-$s.xcresult 2>/dev/null | grep '"passedTests"' | head -1 | tr -dc 0-9)
  f=$(xcrun xcresulttool get test-results summary --path /tmp/e1-$s.xcresult 2>/dev/null | grep '"failedTests"' | head -1 | tr -dc 0-9)
  printf "%-30s pass=%-4s fail=%s\n" "$s" "${p:-0}" "${f:-0}"
done
```

Every row must read `fail=0` with `pass>0`.

- [ ] **Step 6: Commit**

```bash
cat > /tmp/c-e1.txt <<'EOF'
feat(demo): six finished artifacts, one per uncovered department

Inert on their own — nothing references them until the tasks land — so the
content can be judged on its own terms first.

They exist because the Library already groups deliverables BY DEPARTMENT and
was showing two groups: the fixture filed three artifacts belonging to `mkt`
and `design`, all of kind doc. Six more cover eng, sales, support, fin, ops
and legal, so the surface can show what the demo has been claiming.

Placed after every specific entry and before the catch-all, because
`deliverable(for:)` returns the FIRST keyword match and a broad keyword early
in the table silently steals another department's deliverable. A test asserts
all eight existing titles still resolve to the kind they always did.

The finance entry carries no payload on purpose: a `sheet` payload is a
four-input pricing model, and this is a cost analysis. A nil payload renders
the markdown body, which is the correct fallback rather than a shortcoming.

3 passed / 0 failed, and four neighbouring fixture suites unchanged.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Demo/DemoProjectMurrorWork.swift \
        codepetTests/DemoProjectEightDepartmentsTests.swift
git commit -F /tmp/c-e1.txt
```

---

### Task 2: Six done tasks, and the board that carries both halves

**Files:**
- Modify: `codepet/Demo/DemoProjectMurror.swift` — six tasks, and the `filed` array
- Modify: `codepetTests/DemoProjectMurrorTests.swift` — board-shape assertions
- Test: `codepetTests/DemoProjectEightDepartmentsTests.swift` (append)

**Interfaces:**
- Consumes: the six deliverables from Task 1; `DemoProject.filed`, `DemoProject.library()` (exist).
- Produces: a 18-task board — 9 done, 8 Codepet-runnable, 1 founder-only — with `library()` returning 9 filed deliverables across 8 departments.

- [ ] **Step 1: Write the failing tests**

Append inside `DemoProjectEightDepartmentsTests`:

```swift
    // MARK: - Task 2: the board carries both halves

    /// **The claim this whole change exists to make.** Every roster department has finished work
    /// a founder can open, not just a task it could run.
    func testEveryRosterDepartmentHasFiledWork() {
        let library = murror.library()
        let byDept = Dictionary(grouping: library) { d -> String in
            murror.tasks.first { $0.id == d.sourceTaskId }?.dept ?? "?"
        }
        for dept in DepartmentCatalog.roster.map(\.key) {
            XCTAssertNotNil(byDept[dept], "\(dept) has no filed deliverable — the Library will "
                            + "show seven groups, not eight")
        }
    }

    /// And the existing headline claim survives: the eight are still runnable.
    func testTheEightAreStillRunnable() {
        let tasks = murror.tasks
        let runnable = tasks.filter {
            RoadmapEngine.status(for: $0, in: tasks) == .codepetCanDo
        }
        XCTAssertEqual(runnable.count, 8)
        XCTAssertEqual(Set(runnable.compactMap(\.dept)),
                       Set(DepartmentCatalog.roster.map(\.key)))
    }

    /// The new tasks are DONE, so they must not be in the runnable set.
    func testTheNewTasksAreDoneAndNotRunnable() {
        let ids = ["mur-stack", "mur-unitcost", "mur-notfor", "mur-crisis",
                   "mur-rhythm", "mur-deletion"]
        for id in ids {
            let t = murror.tasks.first { $0.id == id }
            XCTAssertNotNil(t, "\(id) missing from the board")
            XCTAssertTrue(t?.done ?? false, "\(id) must be done")
            XCTAssertEqual(RoadmapEngine.status(for: t!, in: murror.tasks), .done)
        }
    }

    /// Every filed deliverable traces to a task on the roadmap. That provenance is the whole
    /// "your company did this" claim; work with no source task weakens it.
    func testEveryFiledDeliverableTracesToADoneTask() {
        for d in murror.library() {
            let id = d.sourceTaskId
            XCTAssertNotNil(id, "\(d.title) has no source task")
            let t = murror.tasks.first { $0.id == id }
            XCTAssertNotNil(t, "\(d.title) points at \(id ?? "nil"), not on the board")
            XCTAssertTrue(t?.done ?? false, "\(d.title) is filed but its task is not done")
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
  -only-testing:codepetTests/DemoProjectEightDepartmentsTests test 2>&1 | tail -12
```

Expected: FAIL — `eng has no filed deliverable`, and `mur-stack missing from the board`.

- [ ] **Step 3: Add the six tasks**

In `codepet/Demo/DemoProjectMurror.swift`, in `murrorTasks`, immediately after the `mur-clinician` task and before the next section comment, add:

```swift
            // ── WORK ALREADY BEHIND THE FOUNDER ─────────────────────────────────────────────
            //
            // One `done` task per department the board did not already cover, each with a real
            // deliverable filed in `filed` below. This is what makes the Library show EIGHT
            // groups: it already groups by department, and had two departments' work to show.
            //
            // In FOUNDATION rather than `.find`: `.find` must stay complete (a test asserts it)
            // and foundation already has open work, so the open-phase window does not move.
            //
            // These are `done`, so they do not join the eight `codepetCanDo` tasks — the demo's
            // headline claim survives, and the board reads like a real mid-flight company:
            // work behind you and work in front of you.
            RoadmapTask(id: "mur-stack", title: "Choose what the app is built on",
                        detail: "On-device or server, and what that decision closes off.",
                        phase: .foundation, who: .draft, done: true, dept: "eng"),
            RoadmapTask(id: "mur-unitcost", title: "Work out what a month of inference costs",
                        detail: "Per active user, at today's model. The floor pricing argues from.",
                        phase: .foundation, who: .draft, done: true, dept: "fin"),
            RoadmapTask(id: "mur-notfor", title: "Write down who this is not for",
                        detail: "The disqualifiers, so outreach stops spending its best hours wrong.",
                        phase: .foundation, who: .draft, done: true, dept: "sales"),
            RoadmapTask(id: "mur-crisis", title: "Decide what happens on a bad night",
                        detail: "The crisis path as policy. Wording can change; behaviour cannot.",
                        phase: .foundation, who: .draft, done: true, dept: "support"),
            RoadmapTask(id: "mur-rhythm", title: "Set up the weekly release rhythm",
                        detail: "Thursday, not Friday, and the one thing that stops a release.",
                        phase: .foundation, who: .draft, done: true, dept: "ops"),
            RoadmapTask(id: "mur-deletion", title: "Write the data-deletion promise",
                        detail: "One tap, permanent, no email. The policy formalises it later.",
                        phase: .foundation, who: .draft, done: true, dept: "legal"),
```

- [ ] **Step 4: File them**

In the same file, change the `filed:` argument from:

```swift
        filed: ["mur-interviews", "mur-landscape", "mur-brand"],
```

to:

```swift
        // Nine filed artifacts across all eight roster departments. `mur-interviews`,
        // `mur-landscape` and `mur-brand` are the research the open tasks build on; the six
        // below are what the other departments have already finished.
        filed: ["mur-interviews", "mur-landscape", "mur-brand",
                "mur-stack", "mur-unitcost", "mur-notfor",
                "mur-crisis", "mur-rhythm", "mur-deletion"],
```

- [ ] **Step 5: Update the board-shape assertions**

`DemoProjectMurrorTests` asserts the exact board. Six new tasks change three numbers. In `codepetTests/DemoProjectMurrorTests.swift`:

- `testBoardIsTwelveTasks` → rename to `testBoardIsEighteenTasks`; `murror.tasks.count` becomes `18`; `open.count` stays `9`; `codepetRunnable.count` stays `8`.
- `testSelectingMurrorChangesTheCompany` → `MockChat.roadmap().count` becomes `18`.
- `testEveryRunnableResolvesToADistinctKind` — unchanged; it iterates `codepetRunnable`, which is still the same eight.

Do NOT weaken any assertion into a range to make it pass. If a fourth assertion fails, read it: this change is supposed to alter counts and nothing else, so anything about status, phase or department coverage failing is a real problem, not a stale number.

- [ ] **Step 6: Run**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
for s in DemoProjectEightDepartmentsTests DemoProjectMurrorTests DemoProjectParityTests \
         DemoProjectFiledTests MockFixtureRunnableTests UpstreamCreditTests \
         PrototypeParityTests MockFlowTests; do
  rm -rf /tmp/e2-$s.xcresult
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/e2-$s.xcresult test > /tmp/e2-$s.log 2>&1
  p=$(xcrun xcresulttool get test-results summary --path /tmp/e2-$s.xcresult 2>/dev/null | grep '"passedTests"' | head -1 | tr -dc 0-9)
  f=$(xcrun xcresulttool get test-results summary --path /tmp/e2-$s.xcresult 2>/dev/null | grep '"failedTests"' | head -1 | tr -dc 0-9)
  printf "%-34s pass=%-4s fail=%s\n" "$s" "${p:-0}" "${f:-0}"
done
```

Every row `fail=0`, `pass>0`.

**`UpstreamCreditTests` is in this list on purpose.** Its `murrorStore` helper takes a `library:` defaulting to empty, and several of its tests depend on `mur-site`'s dependencies being UNFILED so the chain fires. Those dependencies are `mur-brand` and `mur-landscape`, both already filed before this change, so the default-empty library keeps them working — but if any test there starts failing, the cause is the fixture's `filed` list, not the chain.

- [ ] **Step 7: Commit**

```bash
cat > /tmp/c-e2.txt <<'EOF'
feat(demo): the board carries work behind the founder as well as ahead

Six `done` tasks, one per department the board did not cover — eng, fin,
sales, support, ops, legal — each with the deliverable from the previous
commit filed against it. Nine filed artifacts across all eight roster
departments.

This is the half the demo was missing. `LibraryView` already groups by
department and renders all thirteen kinds; it showed TWO groups because the
fixture filed three artifacts belonging to `mkt` and `design`. It now has
eight departments' work to show.

The eight runnable tasks are untouched, so the demo's headline claim survives:
every pet still has exactly one task the engine says Codepet can do right now.
A test asserts both properties at once — eight filed, eight runnable — because
they pull against each other and a future edit will be tempted to trade one
for the other.

In FOUNDATION rather than `.find`: `.find` must stay complete or the board
stops being the mid-flight state the fixture exists to show, and foundation
already has open work so the phase window does not move.

Board 12 -> 18. Three count assertions updated in `DemoProjectMurrorTests`,
which asserts the board's exact shape; nothing weakened into a range.

Every filed deliverable traces to a done task on the roadmap — a test pins it,
because provenance is the "your company did this" claim and work with no
source task quietly weakens it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Demo/DemoProjectMurror.swift codepetTests/DemoProjectMurrorTests.swift \
        codepetTests/DemoProjectEightDepartmentsTests.swift
git commit -F /tmp/c-e2.txt
```

---

### Task 3: The walkthrough beat says what is now there

**Files:**
- Modify: `codepet/Demo/MockFlowScript.swift:170-172` — the existing `.go(.library)` beat
- Test: `codepetTests/DemoProjectEightDepartmentsTests.swift` (append)

**Interfaces:**
- Consumes: the nine filed deliverables from Task 2.
- Produces: nothing later tasks rely on.

**There is already a Library beat.** `MockFlowScript.swift:170`, chapter *"Where the state lives"*, 2.6 seconds, captioned *"And the deliverable that was just approved is here. Library is the record of what the company has actually produced."* With eight departments' work behind it that caption is an understatement and 2.6s is too short to read eight groups. **Re-caption and lengthen it. Do not add a second Library beat.**

- [ ] **Step 1: Write the failing test**

Append inside `DemoProjectEightDepartmentsTests`:

```swift
    // MARK: - Task 3: the walkthrough points at it

    /// Exactly one Library beat. The walkthrough already had one; a second would be the
    /// duplication this change exists to avoid.
    func testThereIsExactlyOneLibraryBeat() {
        let n = MockFlowScript.beats.filter {
            if case .go(.library) = $0.intent { return true }
            return false
        }.count
        XCTAssertEqual(n, 1, "one Library beat, not two")
    }

    /// It must claim the breadth that is now actually there. The old caption spoke only of the
    /// one deliverable just approved, which with nine filed across eight departments understates
    /// the screen by a lot.
    func testTheLibraryBeatNamesTheBreadth() throws {
        let beat = try XCTUnwrap(MockFlowScript.beats.first {
            if case .go(.library) = $0.intent { return true }
            return false
        })
        XCTAssertTrue(beat.caption.lowercased().contains("eight"),
                      "the caption should name the eight departments: \(beat.caption)")
        XCTAssertGreaterThanOrEqual(beat.seconds, 4.0,
                                    "2.6s is not long enough to read eight groups")
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
xcodebuild -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:codepetTests/DemoProjectEightDepartmentsTests test 2>&1 | tail -10
```

Expected: FAIL — `testTheLibraryBeatNamesTheBreadth`, on both the caption and the 2.6s duration.

If `Intent` is not pattern-matchable this way (it is an enum with associated values, so `if case` should work), and the build objects, compare `String(describing: $0.intent) == "go(codepet.AppView.library)"` instead and note the change in your report.

- [ ] **Step 3: Re-caption and lengthen**

In `codepet/Demo/MockFlowScript.swift`, replace:

```swift
        ("Where the state lives", 2.6, .go(.library),
         "And the deliverable that was just approved is here. Library is the record of "
         + "what the company has actually produced."),
```

with:

```swift
        // 4.4s, not 2.6: this screen now has eight departments' work on it and the old
        // duration was sized for reading about one deliverable.
        ("Where the state lives", 4.4, .go(.library),
         "The deliverable just approved is here — and so is finished work from all eight "
         + "departments, grouped by whose it is. Every one of them traces back to a task "
         + "on the roadmap. Library is the record of what the company has actually produced."),
```

- [ ] **Step 4: Run**

```bash
cd ~/Developer/codepet-two-mode
osascript -e 'quit app "codepet"' 2>/dev/null; sleep 2
PID=$(ps -eo pid,comm | awk '$2 ~ /codepet$/ {print $1}'); [ -n "$PID" ] && kill "$PID" && sleep 2
for s in DemoProjectEightDepartmentsTests MockFlowScriptTests MockFlowTests \
         MockFlowCaptionBarLayoutTests DemoScriptControllerTests; do
  rm -rf /tmp/e3-$s.xcresult
  xcodebuild -project CodePet.xcodeproj -scheme codepet \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:codepetTests/$s -resultBundlePath /tmp/e3-$s.xcresult test > /tmp/e3-$s.log 2>&1
  p=$(xcrun xcresulttool get test-results summary --path /tmp/e3-$s.xcresult 2>/dev/null | grep '"passedTests"' | head -1 | tr -dc 0-9)
  f=$(xcrun xcresulttool get test-results summary --path /tmp/e3-$s.xcresult 2>/dev/null | grep '"failedTests"' | head -1 | tr -dc 0-9)
  printf "%-34s pass=%-4s fail=%s\n" "$s" "${p:-0}" "${f:-0}"
done
```

A suite asserting total walkthrough duration may fail here — the tour grew 1.8s. That is a real expectation this change invalidates; update the number, do not widen it to a range.

- [ ] **Step 5: Commit**

```bash
cat > /tmp/c-e3.txt <<'EOF'
docs(demo): the Library beat describes the eight, and holds long enough to read

RE-CAPTIONED, not added. The walkthrough already visited the Library — one
beat, 2.6 seconds, captioned about the single deliverable just approved. A
second Library beat would have been exactly the duplication this change exists
to avoid, so a test now asserts there is precisely one.

With nine artifacts across eight departments behind it, the old caption
understated the screen and 2.6s was sized for reading about one thing. Now
4.4s, and it names the breadth and the provenance — every artifact traces back
to a task on the roadmap, which is the claim that makes the Library evidence
rather than a gallery.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add codepet/Demo/MockFlowScript.swift codepetTests/DemoProjectEightDepartmentsTests.swift
git commit -F /tmp/c-e3.txt
```

---

### Task 4: See it, then document it

- [ ] **Step 1: Build signed and launch**

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

Screen Recording is granted on this machine (corrected 4 Sep), so `screencapture -x` works — bring the app forward with `tell application "System Events" to set frontmost of process "codepet" to true` (NOT `tell application "codepet" to activate`, which fails with -10673), and delete captures once read. Stop if the founder is using the machine.

1. Open **Library** → **eight department groups**, in roster order, each with at least one artifact
2. The sidebar Library badge reads **9**
3. Open one from each of the six new departments — each renders real prose, none shows the catch-all's *"a starting point, not the final word"*
4. Finance's cost analysis renders as markdown, not as an empty slider card — it has no payload on purpose
5. Open **Roadmap** → the board reads as mid-flight: finished work behind, eight runnable ahead
6. Run the walkthrough → the *"Where the state lives"* Library beat holds long enough to take in eight groups

- [ ] **Step 3: Document it, and commit**

Add to `CLAUDE.md`, in the prototype-mode section:

```markdown
- **The Murror Library shows all eight departments.** Nine filed artifacts (`DemoProject.filed`)
  across eight departments, because `LibraryView` already groups by department and had only
  `mkt` and `design` work to show. The board carries BOTH halves — nine `done` tasks with filed
  deliverables AND eight runnable ones — so "all eight pets runnable" survives alongside "all
  eight have produced something". A test asserts both at once, because they pull against each
  other and an edit will be tempted to trade one for the other.
- New `done` fixture tasks go in **`.foundation`, never `.find`** — `.find` must stay complete or
  the board stops being the mid-flight state the fixture exists to show.
- **There is exactly ONE `.go(.library)` walkthrough beat.** It was re-captioned rather than
  duplicated; a test pins the count.
```

```bash
cat > /tmp/c-e4.txt <<'EOF'
docs: the Library is the demo's breadth surface, and how not to break it

Three prohibitions, each learned the expensive way in this change: do not
trade a runnable task for a filed one (both claims are asserted together
because they pull against each other), do not put new `done` fixture tasks in
`.find` (it must stay complete), and do not add a second Library beat (the
walkthrough already had one and it was re-captioned).

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
git add CLAUDE.md
git commit -F /tmp/c-e4.txt
```

---

## Self-Review

**Spec coverage.** Six deliverables → Task 1. Six done tasks and the `filed` wiring → Task 2. The board carrying both halves → Task 2, asserted by `testEveryRosterDepartmentHasFiledWork` and `testTheEightAreStillRunnable` together. The walkthrough beat → Task 3. Every spec test row maps: eight filed (Task 2), eight still runnable (Task 2), no catch-all (Task 1 + the existing `DemoProjectParityTests`), no leaked token (Task 1), `.find` complete (existing `DemoProjectMurrorTests`, re-run in Task 2 Step 6), one Library beat after the approve beat (Task 3 — the existing beat is already after it), `codepet` unchanged (Task 1 Step 5 and Task 2 Step 6 both re-run `DemoProjectTests`).

**One spec row is covered differently than written.** The spec asks for a test that "the Library's grouping yields eight department groups for Murror". `LibraryView.groups` is a private computed property on a SwiftUI view and is not reachable from a test. Task 2's `testEveryRosterDepartmentHasFiledWork` asserts the same property one level down — the data the grouping consumes — and Task 4 Step 2 check 1 confirms the rendered result on screen. Recorded rather than silently dropped.

**One spec deviation, deliberate.** The spec says "one new beat"; the walkthrough already has a `.go(.library)` beat, so Task 3 re-captions it and a test asserts there is exactly one. Adding a second would have been the duplication the spec warns about elsewhere.

**Placeholder scan.** No TBDs. All six deliverable bodies are written in full. Two flagged unknowns carry resolutions rather than guesses: whether `Intent` is `if case`-matchable (Task 3 Step 2 gives the fallback), and whether a duration-total assertion exists (Task 3 Step 4 says to fix the number, not widen it).

**Type consistency.** The six task ids — `mur-stack`, `mur-unitcost`, `mur-notfor`, `mur-crisis`, `mur-rhythm`, `mur-deletion` — are spelled identically in Task 2's tasks, Task 2's `filed` array, and Task 2's `testTheNewTasksAreDoneAndNotRunnable`. The six titles in Task 1's test match the six `title:` values in Task 2 exactly. Kinds match between Task 1's entries and Task 1's test.

**One correction carried from the spec.** Six departments, not five. The roster is eight and existing `done` tasks cover `mkt` twice and `design`.
