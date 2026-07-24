# Onboarding Correctness & Clean Data — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make native first-run onboarding write enriched, correct company state and stop it re-triggering for users the web treats as onboarded, and delete dead onboarding code.

**Architecture:** Three small changes in `CompanyStore` + `CompanyBrief`, plus one file deletion. Enrichment reuses the already-wired `enrichBrief` Cloud Function via a new injectable `enricher` closure on `CompanyStore` (mirrors the existing injectable-closure pattern so tests stub without network). Gating switches from the narrow `BriefContext.compose` check to a web-parity "any non-empty brief field" check.

**Tech Stack:** Swift, SwiftUI, XCTest. macOS app built with `xcodebuild` (scheme `codepet`).

## Global Constraints

- All work on branch `feat/onboarding-correctness` (already created; spec committed).
- Fail-open everywhere on the onboarding path: a failed/throwing enrich must never block or fail onboarding — fall back to the raw brief.
- Preserve existing account-switch guards: `token == hydrationToken` and `!Task.isCancelled` checks after every `await` in `scaffoldFromOnboarding`.
- Gating semantics = web parity: onboarded when `onboardedAt != nil` OR the brief has any non-empty field (strings trimmed; arrays non-empty). `stage` counts when non-nil.
- **Xcode 26.2 test caveat:** the hosted XCTest suite crashes on teardown of any `@MainActor` class (isolated-deinit toolchain bug — see `docs` / project memory). Consequence for verification: struct-only tests (Task 1, `CompanyBrief`) run normally; tests that instantiate `CompanyStore` (Tasks 2–3) compile but will crash the host on teardown under 26.2. For those, "verify" = `xcodebuild build` succeeds (compilation) + the test is authored correctly; full green run is deferred to a compatible toolchain. Do NOT treat the host crash as a code failure of these tasks.
- Build/verify command (foreground; never background xcodebuild):
  `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`

---

### Task 1: `CompanyBrief.hasAnySignal`

**Files:**
- Modify: `codepet/Models/CompanyBrief.swift`
- Test: `codepetTests/CompanyBriefTests.swift`

**Interfaces:**
- Produces: `var hasAnySignal: Bool` on `CompanyBrief` — true when any field is non-empty. Consumed by Task 2.

- [ ] **Step 1: Write the failing tests**

Add to `codepetTests/CompanyBriefTests.swift`:

```swift
func testHasAnySignal_emptyBriefIsFalse() {
    XCTAssertFalse(CompanyBrief().hasAnySignal)
}
func testHasAnySignal_blankStringsAreFalse() {
    XCTAssertFalse(CompanyBrief(founderName: "  ", projectName: "\n").hasAnySignal)
}
func testHasAnySignal_emptyCategoriesIsFalse() {
    XCTAssertFalse(CompanyBrief(categories: []).hasAnySignal)
}
func testHasAnySignal_roleOnlyIsTrue() {
    XCTAssertTrue(CompanyBrief(role: "Founder").hasAnySignal)
}
func testHasAnySignal_stageOnlyIsTrue() {
    XCTAssertTrue(CompanyBrief(stage: "Idea").hasAnySignal)
}
func testHasAnySignal_categoriesIsTrue() {
    XCTAssertTrue(CompanyBrief(categories: ["SaaS"]).hasAnySignal)
}
func testHasAnySignal_projectNameIsTrue() {
    XCTAssertTrue(CompanyBrief(projectName: "Codepet").hasAnySignal)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyBriefTests`
Expected: FAIL — `value of type 'CompanyBrief' has no member 'hasAnySignal'` (compile error).

- [ ] **Step 3: Add the helper**

In `codepet/Models/CompanyBrief.swift`, inside the `CompanyBrief` struct (after the `init`), add:

```swift
    /// True when the brief carries any founder-supplied signal. Mirrors the web
    /// gating check (`Object.keys(brief).length > 0`): any non-empty field counts.
    var hasAnySignal: Bool {
        func s(_ v: String?) -> Bool {
            guard let v else { return false }
            return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return s(founderName) || s(role) || s(tech) || s(stage)
            || s(projectName) || s(oneLiner) || s(summary) || s(notes)
            || s(link) || s(audience)
            || !(categories?.isEmpty ?? true)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyBriefTests`
Expected: PASS (all `testHasAnySignal_*`). `CompanyBriefTests` is struct-only, so it runs cleanly under Xcode 26.2.

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Models/CompanyBrief.swift codepetTests/CompanyBriefTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: add CompanyBrief.hasAnySignal (web-parity brief-signal check)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Web-parity onboarding gating predicate

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift:68-71` (`needsOnboarding`)
- Test: `codepetTests/CompanyStoreOnboardingTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief.hasAnySignal` (Task 1).
- Produces: unchanged `var needsOnboarding: Bool` / `isOnboarding` behavior, now web-aligned.

- [ ] **Step 1: Write the failing regression test**

Add to `codepetTests/CompanyStoreOnboardingTests.swift`:

```swift
/// Regression: a legacy/partial brief with only `role` (no product text) and no
/// stamp counts as onboarded on web; native must not re-onboard it.
func testNotNeededWhenBriefHasOnlyRole() async {
    let seeded = CompanyState(brief: CompanyBrief(role: "Founder"),
                              departments: [], library: [], stage: .idea,
                              companionId: "byte", onboardedAt: nil)
    let s = store(loader: { _ in seeded })
    await s.hydrate(companyId: "u")
    XCTAssertFalse(s.isOnboarding)
}
```

(If `CompanyState.stage` enum has no `.idea` case, use the same case the existing `testNotNeededWhenBriefHasSignal` test uses, e.g. `.building`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreOnboardingTests/testNotNeededWhenBriefHasOnlyRole`
Expected: FAIL — asserts `isOnboarding` is false but old predicate returns true (compose ignores `role`). (Under Xcode 26.2 the host may also crash on teardown; the assertion failure is the signal — see Global Constraints.)

- [ ] **Step 3: Update the predicate**

In `codepet/Managers/CompanyStore.swift`, replace:

```swift
    /// Mirrors the web: onboard unless a stamp exists OR the brief already has signal.
    var needsOnboarding: Bool {
        company.onboardedAt == nil && BriefContext.compose(company.brief) == nil
    }
```

with:

```swift
    /// Mirrors the web (`Boolean(onboardedAt) || Object.keys(brief).length > 0`):
    /// onboard only when there is no stamp AND the brief has no signal at all.
    var needsOnboarding: Bool {
        company.onboardedAt == nil && !company.brief.hasAnySignal
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreOnboardingTests`
Expected: the new assertion passes and existing `testNeedsOnboardingWhenNoStampAndNoBriefSignal` / `testNotNeededWhenBriefHasSignal` still pass. (Xcode 26.2: if the host crashes on teardown, confirm instead that `xcodebuild build …` succeeds and the assertions ran green before teardown.)

- [ ] **Step 5: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreOnboardingTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "fix: align onboarding gating to web (any brief field counts)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Enrich the brief before roadmap generation

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift` (add `enricher` closure to stored props + init; rewrite `scaffoldFromOnboarding`; fix stale comment on `finishOnboarding`)
- Test: `codepetTests/CompanyStoreOnboardingTests.swift`

**Interfaces:**
- Consumes: `ReflectionAPIClient().enrichBrief(_:) async throws -> CompanyBrief` (already defined, `ReflectionAPIClient.swift:608`).
- Produces: new init parameter `enricher: (CompanyBrief) async throws -> CompanyBrief` (default calls the live CF); `scaffoldFromOnboarding` now enriches → persists enriched → generates.

- [ ] **Step 1: Write the failing tests**

Add to `codepetTests/CompanyStoreOnboardingTests.swift`. Extend the local `store(...)` helper to accept an optional enricher and roadmap fetcher:

```swift
func testScaffoldPersistsEnrichedBriefBeforeRoadmap() async {
    var savedBrief: CompanyBrief?
    var roadmapSawSummary: String?
    let s = CompanyStore(
        loader: { _ in .empty },
        saver: { _, b in savedBrief = b; return true },
        roadmapFetcher: { brief, _ in roadmapSawSummary = brief.summary; return [] },
        enricher: { raw in var e = raw; e.summary = "ENRICHED"; return e }
    )
    await s.hydrate(companyId: "u")
    _ = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "Codepet"),
                                       token: s.onboardingToken)
    XCTAssertEqual(savedBrief?.summary, "ENRICHED")       // enriched brief persisted
    XCTAssertEqual(s.company.brief.summary, "ENRICHED")   // enriched brief in state
    XCTAssertEqual(roadmapSawSummary, "ENRICHED")         // roadmap generated from enriched
}

func testScaffoldFailsOpenWhenEnrichThrows() async {
    struct E: Error {}
    var savedBrief: CompanyBrief?
    let s = CompanyStore(
        loader: { _ in .empty },
        saver: { _, b in savedBrief = b; return true },
        roadmapFetcher: { _, _ in [] },
        enricher: { _ in throw E() }
    )
    await s.hydrate(companyId: "u")
    _ = await s.scaffoldFromOnboarding(brief: CompanyBrief(projectName: "Raw"),
                                       token: s.onboardingToken)
    XCTAssertEqual(savedBrief?.projectName, "Raw")        // raw brief used, not blocked
    XCTAssertNil(savedBrief?.summary)                     // no enrichment applied
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreOnboardingTests/testScaffoldPersistsEnrichedBriefBeforeRoadmap`
Expected: FAIL to compile — `CompanyStore` init has no `enricher:` parameter.

- [ ] **Step 3: Add the `enricher` closure to `CompanyStore`**

In `codepet/Managers/CompanyStore.swift`, add a stored property alongside the other injectables (after `companionSaver`, ~line 32):

```swift
    private let enricher: (CompanyBrief) async throws -> CompanyBrief
```

Add the init parameter (place it after `companionSaver:` in the parameter list, before the closing `)`), with a default that calls the live CF:

```swift
         companionSaver: @escaping (String, String) async -> Bool = CompanyData.saveCompanionId,
         enricher: @escaping (CompanyBrief) async throws -> CompanyBrief = { try await ReflectionAPIClient().enrichBrief($0) }) {
```

And assign it in the init body (after `self.companionSaver = companionSaver`):

```swift
        self.enricher = enricher
```

- [ ] **Step 4: Rewrite `scaffoldFromOnboarding` to enrich first**

Replace the body of `scaffoldFromOnboarding` (`CompanyStore.swift:152-162`) with:

```swift
    func scaffoldFromOnboarding(brief: CompanyBrief, token: Int) async -> OnboardingReveal {
        guard token == hydrationToken, !Task.isCancelled, let cid = companyId else { return .empty }
        // Enrich (fail-open, mirrors web /api/scaffold): fill summary/audience/etc
        // before planning so a founder who skipped optional fields still gets a
        // full roadmap. A throw/timeout falls back to the raw brief.
        let enriched = (try? await enricher(brief)) ?? brief
        guard token == hydrationToken, !Task.isCancelled else { return .empty }
        _ = await saver(cid, enriched)
        // Cancellation guard: a Skip during the in-flight scaffold cancels this task,
        // so we bail before mutating brief/tasks (skip's empty write is the winner).
        guard token == hydrationToken, !Task.isCancelled else { return .empty }
        company.brief = enriched
        await generateRoadmap()
        guard token == hydrationToken, !Task.isCancelled else { return .empty }
        return OnboardingReveal.build(tasks: company.tasks)
    }
```

- [ ] **Step 5: Fix the stale comment on `finishOnboarding`**

In `codepet/Managers/CompanyStore.swift`, replace the doc line (`:96`):

```swift
    /// Enrich already happened in the model; here we persist + stamp + leave onboarding.
```

with:

```swift
    /// Persist + stamp + leave onboarding. (Enrichment happens earlier, in
    /// scaffoldFromOnboarding for the first-run path, or in the Settings model.)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreOnboardingTests`
Expected: new tests' assertions pass; existing onboarding tests still pass. (Xcode 26.2: on host teardown crash, verify `xcodebuild build …` succeeds and assertions ran green — see Global Constraints.)

- [ ] **Step 7: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreOnboardingTests.swift
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "feat: enrich brief before roadmap in first-run scaffold (fail-open)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Remove dead `OnboardingFlow.swift`

**Files:**
- Delete: `codepet/Views/Onboarding/OnboardingFlow.swift`

**Interfaces:** none (dead file; only self-referenced in its own `#Preview`).

- [ ] **Step 1: Re-confirm it is dead**

Run: `grep -rn "OnboardingFlow" ~/Documents/codepet-rebuild-wt/codepet ~/Documents/codepet-rebuild-wt/codepetTests`
Expected: only matches inside `OnboardingFlow.swift` itself (its declaration + `#Preview { OnboardingFlow() }`). If any OTHER file references it, STOP — it is not dead; do not delete.

- [ ] **Step 2: Delete the file**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false rm codepet/Views/Onboarding/OnboardingFlow.swift
```

- [ ] **Step 3: Verify the app still builds**

Run: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`. (If the project uses a file-list build phase that referenced the file, remove the stale reference from `codepet.xcodeproj/project.pbxproj` until the build is clean.)

- [ ] **Step 4: Commit**

```bash
GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false commit -m "chore: remove dead OnboardingFlow.swift

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Spec Change 1 (enrich before roadmap + fix comment) → Task 3. ✓
- Spec Change 2 (gating predicate → web parity via `hasAnySignal`) → Tasks 1 + 2. ✓
- Spec Change 3 (delete OnboardingFlow.swift; keep CompanyOnboardingView/Model) → Task 4 (deletes only OnboardingFlow; never touches CompanyOnboardingView/Model). ✓
- Non-goals (companion step, visual polish, functions repo) → not present in any task. ✓

**Placeholder scan:** No TBD/TODO; every code and test step shows full code. ✓

**Type consistency:** `hasAnySignal` defined in Task 1, consumed in Task 2. `enricher: (CompanyBrief) async throws -> CompanyBrief` defined and consumed consistently in Task 3. `scaffoldFromOnboarding(brief:token:) -> OnboardingReveal` signature unchanged. Test helper `store(...)` in Task 2 uses the existing helper; Task 3 tests call the full `CompanyStore(...)` init directly (with `enricher:`). ✓

**Known caveat:** Xcode 26.2 host-crash on `@MainActor` teardown affects test-RUN verification for Tasks 2–3 (documented in Global Constraints); Task 1 (struct-only) runs clean.
