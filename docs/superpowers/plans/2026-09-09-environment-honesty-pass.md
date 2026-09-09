# Environment Honesty Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Environment tab incapable of claiming an unbuilt toolkit item is on.

**Architecture:** One pure predicate, `ToolItem.isBuilt(builtSkills:)`, with three honest authorities behind it — a Cloud Function manifest for skills, the `ConnectorProvider` enum for connectors, and `false` for agents until a mechanism exists. Every view and payload asks only the predicate. The load-bearing change is a guard inside `CompanyStore.toggleTool`, which makes the fake on-state unreachable from every call site rather than only from the two views that render controls.

**Tech Stack:** Swift 5 / SwiftUI (macOS 26.2, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), XCTest; Firebase Cloud Functions in TypeScript on Node 22, Jest.

Spec: `docs/superpowers/specs/2026-09-09-environment-honesty-pass-design.md`

## Global Constraints

- Worktree: `~/Developer/codepet-env-honesty`, branch `docs/environment-honesty-pass` (off `origin/main` @ `977a633`). Run every command from this directory; do **not** `cd` to `~/Developer/codepet`.
- Swift test command: `xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Suite> 2>&1 | tail -25`. Scheme is lowercase `codepet`; test module is `@testable import codepet`. Run `xcodebuild` in the FOREGROUND.
- **Quit `codepet.app` before any `xcodebuild test`.** A running app or a sibling build kills the test host, with a different victim each run.
- A whole-target `xcodebuild test` exits 65 on a clean checkout and ~27 tests never finish — this is landmine 3, not a regression. Run per-suite with `-only-testing:`.
- Never introduce a new `@MainActor ObservableObject`: the XCTest host on Xcode 26.2 crashes when one deallocates. New types here are `enum` namespaces or pure extensions. `CompanyStore` is already an `ObservableObject` and is testable **through its injected closures** — follow `codepetTests/CompanyStoreChatTests.swift`.
- Functions test command: `cd functions && npx jest src/__tests__/<file> 2>&1 | tail -25`.
- Cloud Functions region `us-central1`, project `devpet-8f4b1`. Endpoint URLs are hardcoded per client in this repo; there is no shared base-URL constant.
- SourceKit cross-file diagnostics are false positives — trust `xcodebuild`.
- Do **not** push, open a PR, or deploy at any point in this plan. Commit locally only. Pushing and deploying need the founder's explicit go-ahead.
- Never leave anything staged at the end of a task — sibling worktrees share this repo and a sibling's `git commit` has swept staged work twice.
- No change writes to a founder's stored preferences. `enabledTools` in Firestore is read-only for this entire plan.

## File Structure

**Created:**
- `codepet/Services/CapabilitiesClient.swift` — one unauthenticated GET returning the backend's skill manifest, or `nil`. Nothing else.
- `functions/src/capabilities.ts` — a pure `capabilitiesPayload()` plus a two-line `onRequest` handler shell, mirroring the repo's existing `companyChatCore` (pure) / `companyChat` (handler) split.
- `functions/src/__tests__/capabilities.test.ts`
- `codepetTests/ToolkitIsBuiltTests.swift` — the predicate's truth table.
- `codepetTests/CompanyStoreCapabilitiesTests.swift` — the manifest fetch, its fallback, the `toggleTool` guard, and the `env_setup` payload.

**Modified:**
- `codepet/Models/Toolkit.swift` — `bundledBuiltSkills`, `ToolItem.isBuilt(builtSkills:)`, `recommended(builtSkills:)`, `explorer`'s `defaultOn`.
- `codepet/Managers/CompanyStore.swift` — `builtSkills` property, `capabilitiesFetcher` seam, `refreshCapabilities()`, the `toggleTool` guard, the `env_setup` filter.
- `codepet/Models/SetupCardState.swift` — a `notBuilt` case, so a chat enable-card cannot offer what the guard would silently reject.
- `codepet/Views/Copilot/CopilotChatView.swift` — the one `SetupCardState.of` call site and its `switch`.
- `codepet/Views/Environment/EnvironmentView.swift` — `recs`, the `.task`, the browse row's control, the EN companion copy.
- `codepetTests/ToolkitTests.swift` — two assertions that change because behaviour changes.
- `codepetTests/SetupCardStateTests.swift` — three new tests, plus a required argument at 11 existing call sites.

---

### Task 1: The `isBuilt` predicate

**Files:**
- Modify: `codepet/Models/Toolkit.swift` (add to the `Toolkit` enum near `defaultEnabledIds`; add an `extension ToolItem` at end of file)
- Test: `codepetTests/ToolkitIsBuiltTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `Toolkit.bundledBuiltSkills: Set<String>` and `ToolItem.isBuilt(builtSkills: Set<String>) -> Bool`. Every later task calls exactly these two names.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/ToolkitIsBuiltTests.swift`:

```swift
// codepetTests/ToolkitIsBuiltTests.swift
import XCTest
@testable import codepet

final class ToolkitIsBuiltTests: XCTestCase {

    private func item(_ id: String) -> ToolItem {
        guard let found = Toolkit.catalog.first(where: { $0.id == id }) else {
            XCTFail("no catalog item '\(id)'")
            fatalError("no catalog item '\(id)'")
        }
        return found
    }

    func testSkillIsBuiltOnlyWhenTheManifestNamesIt() {
        XCTAssertTrue(item("web-research").isBuilt(builtSkills: ["web-research"]))
        XCTAssertFalse(item("web-research").isBuilt(builtSkills: []))
        // In the catalog, and NOT in the CF's IMPLEMENTED_SKILLS today.
        XCTAssertFalse(item("code-review").isBuilt(builtSkills: Toolkit.bundledBuiltSkills))
        XCTAssertFalse(item("changelog").isBuilt(builtSkills: Toolkit.bundledBuiltSkills))
    }

    func testAManifestArrivingLaterBuildsASkillWithNoClientChange() {
        // The property Toolkit.swift defends: shipping a skill is a backend deploy,
        // not a client release. A manifest naming 'changelog' must build it here.
        XCTAssertTrue(item("changelog").isBuilt(builtSkills: ["changelog"]))
    }

    func testConnectorIsBuiltOnlyWhenAProviderCaseExists() {
        XCTAssertTrue(item("github").isBuilt(builtSkills: []))
        // Note the manifest passed in NAMES these connectors. A skills manifest
        // must never be able to build a connector — the categories are separate
        // authorities, and this is the assertion that proves it.
        let lying: Set<String> = ["notion", "figma", "slack", "linear"]
        for id in ["notion", "figma", "slack", "linear"] {
            XCTAssertFalse(item(id).isBuilt(builtSkills: lying),
                           "\(id) has no ConnectorProvider case")
        }
    }

    func testNoAgentIsEverBuilt() {
        let everything = Set(Toolkit.catalog.map(\.id))
        for agent in Toolkit.items(in: .agents) {
            XCTAssertFalse(agent.isBuilt(builtSkills: everything),
                           "\(agent.id): no mechanism can run an agent yet")
        }
        XCTAssertEqual(Toolkit.items(in: .agents).count, 4)
    }

    func testBundledFallbackNamesTheTwoSkillsTheCFImplements() {
        XCTAssertEqual(Toolkit.bundledBuiltSkills, ["web-research", "prd-writer"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ToolkitIsBuiltTests 2>&1 | tail -25
```

Expected: FAILS TO COMPILE — `value of type 'ToolItem' has no member 'isBuilt'` and `type 'Toolkit' has no member 'bundledBuiltSkills'`. A compile failure is the correct red here.

- [ ] **Step 3: Write minimal implementation**

In `codepet/Models/Toolkit.swift`, inside `enum Toolkit`, directly above `static var defaultEnabledIds`:

```swift
    /// The skills this binary is compiled knowing about, used ONLY until the live
    /// manifest arrives: first paint, offline, or a failed fetch.
    ///
    /// A floor, not a copy to keep in sync. `IMPLEMENTED_SKILLS` in the CF stays the
    /// authority, so a skill shipped backend-only becomes built via the manifest
    /// without this list changing.
    static let bundledBuiltSkills: Set<String> = ["web-research", "prd-writer"]
```

At the end of `codepet/Models/Toolkit.swift`, append:

```swift
extension ToolItem {

    /// Whether this item does anything at all today.
    ///
    /// Three categories, three honest authorities, one accessor — so no view and no
    /// payload has to know where the truth came from:
    ///
    ///  - **skills**: the CF owns it (`IMPLEMENTED_SKILLS`), delivered as `builtSkills`.
    ///    `parseEnabledSkills` drops any id it has not implemented, so a skill absent
    ///    from the manifest genuinely cannot affect a turn.
    ///  - **connectors**: `ConnectorProvider` IS the OAuth implementation, so the enum
    ///    having a case is the same fact as the consent flow existing. Adding
    ///    `case notion` builds that row and nothing else needs to change.
    ///  - **agents**: nothing can run one. This is the single line that changes when
    ///    subagents land — see the local Claude Code execution design.
    ///
    /// Takes the skill set rather than reading a singleton: hidden global state makes
    /// every gate untestable, and a new observable service type would trip landmine 3.
    func isBuilt(builtSkills: Set<String>) -> Bool {
        switch category {
        case .skills:     return builtSkills.contains(id)
        case .connectors: return ConnectorProvider(rawValue: id) != nil
        case .agents:     return false
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ToolkitIsBuiltTests 2>&1 | tail -25
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Prove the tests can fail**

Temporarily change the `.agents` line to `return builtSkills.contains(id)`, re-run the command from Step 4, and confirm `testNoAgentIsEverBuilt` goes RED. Then restore `return false` and re-run to green.

This step is not optional. Five tests in an earlier plan could not fail; breaking the guard and watching it go red is the only thing that proves a test is load-bearing.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-env-honesty
git add codepet/Models/Toolkit.swift codepetTests/ToolkitIsBuiltTests.swift
git commit -m "Add ToolItem.isBuilt, one predicate over three honest authorities"
git status --short   # must be empty
```

---

### Task 2: Stop recommending and defaulting things that do not exist

**Files:**
- Modify: `codepet/Models/Toolkit.swift` (the `explorer` catalog entry; `recommended`)
- Modify: `codepetTests/ToolkitTests.swift:11` and `:39-40`
- Test: `codepetTests/ToolkitIsBuiltTests.swift` (append two tests)

**Interfaces:**
- Consumes: `ToolItem.isBuilt(builtSkills:)`, `Toolkit.bundledBuiltSkills` (Task 1).
- Produces: `Toolkit.recommended(builtSkills: Set<String>) -> [ToolItem]`. This **replaces** the `static var recommended` property — Task 6's view code calls the function form.

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/ToolkitIsBuiltTests.swift`, inside the class:

```swift
    func testNothingUnbuiltShipsDefaultOn() {
        // The drift guard. It asserts on the RAW `defaultOn` data rather than on
        // `defaultEnabledIds`, and that distinction is the whole point: if
        // `defaultEnabledIds` filtered by isBuilt, this test would pass forever
        // even after somebody re-added a default-on item that does nothing.
        let defaults = Toolkit.catalog.filter(\.defaultOn)
        for item in defaults {
            XCTAssertTrue(item.isBuilt(builtSkills: Toolkit.bundledBuiltSkills),
                          "'\(item.id)' ships defaultOn but does nothing")
        }
        XCTAssertFalse(defaults.isEmpty, "a catalog with no defaults would pass vacuously")
    }

    func testRecommendationsOnlyOfferWhatCanBeActedOn() {
        let recs = Toolkit.recommended(builtSkills: Toolkit.bundledBuiltSkills)
        XCTAssertEqual(recs.map(\.id).sorted(), ["github", "prd-writer"])
        // Browse all still carries them; only the pitch drops them.
        for id in ["code-review", "notion", "test-writer"] {
            XCTAssertTrue(Toolkit.catalog.contains { $0.id == id },
                          "\(id) must remain in the catalog")
        }
    }

    func testALaterManifestWidensRecommendationsWithNoClientChange() {
        let recs = Toolkit.recommended(builtSkills: ["prd-writer", "code-review"])
        XCTAssertTrue(recs.map(\.id).contains("code-review"))
    }
```

Change `codepetTests/ToolkitTests.swift:11` from:

```swift
        XCTAssertEqual(Toolkit.defaultEnabledIds, ["prd-writer", "github", "explorer"])
```

to:

```swift
        // `explorer` was here and was removed: it is an agent, nothing can run one,
        // and shipping it defaultOn gave every company a fake enabled agent.
        XCTAssertEqual(Toolkit.defaultEnabledIds, ["prd-writer", "github"])
```

Change `codepetTests/ToolkitTests.swift:39-40` from:

```swift
        XCTAssertFalse(Toolkit.recommended.isEmpty)
        XCTAssertTrue(Toolkit.recommended.allSatisfy { $0.why != nil })
```

to:

```swift
        let recs = Toolkit.recommended(builtSkills: Toolkit.bundledBuiltSkills)
        XCTAssertFalse(recs.isEmpty)
        XCTAssertTrue(recs.allSatisfy { $0.why != nil })
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ToolkitIsBuiltTests -only-testing:codepetTests/ToolkitTests 2>&1 | tail -30
```

Expected: FAILS TO COMPILE — `Toolkit.recommended(builtSkills:)` does not exist yet. After Step 3's first edit it will compile and then `testNothingUnbuiltShipsDefaultOn` and `ToolkitTests.testDefaultsAndPartition` fail on `explorer`.

- [ ] **Step 3: Write minimal implementation**

In `codepet/Models/Toolkit.swift`, change the `explorer` catalog entry from:

```swift
        ToolItem(id: "explorer", name: "Explorer", badge: "Ex",
                 detail: "Searches the codebase to answer questions fast.",
                 category: .agents, recommended: false, why: nil, defaultOn: true),
```

to:

```swift
        // defaultOn was true and is now false: nothing can run an agent, so every
        // company was seeded with one that does nothing. The stored id is left alone
        // in existing companies (see the spec) — this only stops NEW ones.
        ToolItem(id: "explorer", name: "Explorer", badge: "Ex",
                 detail: "Searches the codebase to answer questions fast.",
                 category: .agents, recommended: false, why: nil, defaultOn: false),
```

Replace:

```swift
    static var recommended: [ToolItem] { catalog.filter(\.recommended) }
```

with:

```swift
    /// The items worth pitching — recommended AND actually built.
    ///
    /// The line is drawn at intent: Browse all is a catalog and may honestly show
    /// the future, but a card headed "Recommended for your project" whose `why`
    /// promises a benefit is a pitch, and a pitch may only offer what exists.
    ///
    /// Takes the live manifest rather than the bundled floor, so a skill shipped
    /// backend-only becomes recommendable on deploy with no client release.
    static func recommended(builtSkills: Set<String>) -> [ToolItem] {
        catalog.filter { $0.recommended && $0.isBuilt(builtSkills: builtSkills) }
    }
```

Leave `defaultEnabledIds` exactly as it is — unfiltered. Step 1's test explains why: filtering it would make the drift guard vacuous.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ToolkitIsBuiltTests -only-testing:codepetTests/ToolkitTests 2>&1 | tail -30
```

Expected: PASS, 8 tests in `ToolkitIsBuiltTests` and 8 in `ToolkitTests`.

- [ ] **Step 5: Prove the drift guard can fail**

Temporarily set `code-review`'s `defaultOn` to `true`, re-run Step 4, and confirm `testNothingUnbuiltShipsDefaultOn` goes RED naming `code-review`. Restore `false` and re-run to green.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-env-honesty
git add codepet/Models/Toolkit.swift codepetTests/ToolkitIsBuiltTests.swift codepetTests/ToolkitTests.swift
git commit -m "Stop defaulting and recommending items that do nothing"
git status --short   # must be empty
```

---

### Task 3: The `capabilities` endpoint

**Files:**
- Create: `functions/src/capabilities.ts`
- Create: `functions/src/__tests__/capabilities.test.ts`
- Modify: `functions/src/index.ts` (an import near the other handler imports; an export near `companyChat`)

**Interfaces:**
- Consumes: `IMPLEMENTED_SKILLS` from `functions/src/companyChatCore.ts` (already exported at line 379).
- Produces: `GET https://us-central1-devpet-8f4b1.cloudfunctions.net/capabilities` → `{"skills":["web-research","prd-writer"]}`. Task 4's Swift client decodes exactly this shape.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/capabilities.test.ts`:

```ts
import { capabilitiesPayload } from "../capabilities";
import { IMPLEMENTED_SKILLS } from "../companyChatCore";

describe("capabilitiesPayload", () => {
  it("returns exactly the skills this backend implements", () => {
    expect(capabilitiesPayload()).toEqual({ skills: [...IMPLEMENTED_SKILLS] });
  });

  it("names the two skills implemented today", () => {
    expect(capabilitiesPayload().skills).toEqual(["web-research", "prd-writer"]);
  });

  it("cannot drift from the array that gates behaviour", () => {
    // The reason this is an endpoint over IMPLEMENTED_SKILLS rather than a
    // hand-maintained manifest doc: a second list can disagree with the one
    // parseEnabledSkills actually enforces, which is the bug class this whole
    // pass exists to remove.
    expect(capabilitiesPayload().skills).toHaveLength(IMPLEMENTED_SKILLS.length);
  });

  it("returns a fresh array so a caller cannot mutate the constant", () => {
    const first = capabilitiesPayload().skills;
    first.push("not-a-skill");
    expect(capabilitiesPayload().skills).toEqual([...IMPLEMENTED_SKILLS]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/Developer/codepet-env-honesty/functions && npx jest src/__tests__/capabilities.test.ts 2>&1 | tail -25
```

Expected: FAIL — `Cannot find module '../capabilities'`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/capabilities.ts`:

```ts
// Which skills this backend actually implements, so the app can tell a built
// toolkit item from an unbuilt one.
//
// It exists to keep a property the client would otherwise have to give up:
// `IMPLEMENTED_SKILLS` is the authority on what a turn can do, so shipping a
// skill must stay a backend deploy rather than a client release. Exporting that
// same array — rather than maintaining a second manifest that can disagree with
// it — is the whole design.
//
// Deliberately UNAUTHENTICATED: the response is a static constant naming which
// features exist, with no founder data in it. That is what lets the Environment
// tab resolve its state on first paint without a token round-trip.
import type { Request } from "firebase-functions/v2/https";
import type { Response } from "express";
import { IMPLEMENTED_SKILLS } from "./companyChatCore";

/**
 * The response body. Pure and separately tested, mirroring the
 * companyChatCore / companyChat split — the handler below stays a shell so
 * there is nothing in it worth faking an express `Response` to reach.
 *
 * Spreads into a new array so a caller cannot mutate the module constant.
 */
export function capabilitiesPayload(): { skills: string[] } {
  return { skills: [...IMPLEMENTED_SKILLS] };
}

export function handleCapabilities(_req: Request, res: Response): void {
  // Five minutes: long enough that opening the tab repeatedly costs nothing,
  // short enough that a founder sees a newly deployed skill the same session.
  res.set("Cache-Control", "public, max-age=300");
  res.json(capabilitiesPayload());
}
```

In `functions/src/index.ts`, add to the handler imports (after the `handleCompanyChat` import on line 20):

```ts
import { handleCapabilities } from "./capabilities";
```

And add the export after the `companyChat` export block (which ends on line 86):

```ts
// Which skills the backend implements, so the Environment tab can tell a built
// item from an unbuilt one. Unauthenticated by design — a static constant with
// no founder data, read on first paint before a token necessarily exists.
export const capabilities = onRequest({ cors: false }, handleCapabilities);
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd ~/Developer/codepet-env-honesty/functions && npx jest src/__tests__/capabilities.test.ts 2>&1 | tail -25
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Verify the whole functions build still compiles**

```bash
cd ~/Developer/codepet-env-honesty/functions && npx tsc --noEmit 2>&1 | tail -20
```

Expected: no output. `index.ts` importing a new module is where a typo surfaces, and Jest alone would not catch it.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-env-honesty
git add functions/src/capabilities.ts functions/src/__tests__/capabilities.test.ts functions/src/index.ts
git commit -m "Serve IMPLEMENTED_SKILLS so the client need not hard-code what is built"
git status --short   # must be empty
```

**Do not deploy.** `firebase deploy` uploads the working tree, and deploying `functions/` from a branch behind main deletes main's functions from production. This endpoint reaches prod only when the founder says so, from main.

---

### Task 4: The client reads the manifest, and falls back safely

**Files:**
- Create: `codepet/Services/CapabilitiesClient.swift`
- Modify: `codepet/Managers/CompanyStore.swift` (a `@Published` near `connectedProviders:3450`; an init parameter near `toolsSaver:350`; the stored property near `:238`; the assignment near `:423`; a new method near `refreshConnectorStatus:3452`)
- Test: `codepetTests/CompanyStoreCapabilitiesTests.swift` (create)

**Interfaces:**
- Consumes: `Toolkit.bundledBuiltSkills` (Task 1); the endpoint shape from Task 3.
- Produces: `CompanyStore.builtSkills: Set<String>`, `CompanyStore.refreshCapabilities() async`, and the init parameter `capabilitiesFetcher: @escaping () async -> Set<String>?`. Tasks 5 and 6 read `builtSkills`.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/CompanyStoreCapabilitiesTests.swift`:

```swift
// codepetTests/CompanyStoreCapabilitiesTests.swift
import XCTest
@testable import codepet

/// `CompanyStore` is exercised through its injected closures — see
/// CompanyStoreChatTests for the same pattern. Never construct the real client.
@MainActor
final class CompanyStoreCapabilitiesTests: XCTestCase {

    private func store(
        capabilities: @escaping () async -> Set<String>? = { nil }
    ) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     capabilitiesFetcher: capabilities)
    }

    func testStartsAtTheBundledFloorBeforeAnyFetch() {
        // First paint must never render a built skill as unbuilt, so the floor is
        // the starting value rather than an empty set.
        XCTAssertEqual(store().builtSkills, Toolkit.bundledBuiltSkills)
    }

    func testAdoptsTheManifestWhenTheFetchSucceeds() async {
        let s = store(capabilities: { ["web-research", "prd-writer", "changelog"] })
        await s.refreshCapabilities()
        XCTAssertEqual(s.builtSkills, ["web-research", "prd-writer", "changelog"])
    }

    func testFallsBackToTheFloorRatherThanEmptyWhenTheFetchFails() async {
        let s = store(capabilities: { nil })
        await s.refreshCapabilities()
        // An empty set would render EVERY skill as unbuilt — a worse lie than the
        // one this pass fixes. nil and "no skills" must stay different things.
        XCTAssertEqual(s.builtSkills, Toolkit.bundledBuiltSkills)
        XCTAssertFalse(s.builtSkills.isEmpty)
    }

    func testAnEmptyManifestIsHonouredAndIsNotTreatedAsAFailure() async {
        // A backend that genuinely implements nothing is a real answer, distinct
        // from an unreachable one.
        let s = store(capabilities: { [] })
        await s.refreshCapabilities()
        XCTAssertTrue(s.builtSkills.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreCapabilitiesTests 2>&1 | tail -25
```

Expected: FAILS TO COMPILE — no `capabilitiesFetcher:` parameter, no `builtSkills`, no `refreshCapabilities()`.

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Services/CapabilitiesClient.swift`:

```swift
// Which skills the backend implements. One unauthenticated GET — see the note on
// the `capabilities` function: the payload is a static constant with no founder
// data, which is what lets the Environment tab resolve its state on first paint.
import Foundation

enum CapabilitiesClient {

    static let endpoint = URL(
        string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/capabilities")!

    private struct Payload: Decodable { let skills: [String] }

    /// The implemented skill ids, or `nil` when the manifest could not be read.
    ///
    /// `nil` and an empty set are deliberately different returns. Empty means the
    /// backend implements nothing; `nil` means we do not know, and the caller must
    /// substitute `Toolkit.bundledBuiltSkills` rather than render every skill as
    /// unbuilt on a dropped connection.
    static func fetch() async -> Set<String>? {
        guard let (data, response) = try? await URLSession.shared.data(from: endpoint),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return Set(payload.skills)
    }
}
```

In `codepet/Managers/CompanyStore.swift`, add the stored property beside `toolsSaver` (line 238):

```swift
    private let capabilitiesFetcher: () async -> Set<String>?
```

Add the init parameter immediately after `toolsSaver` (line 350):

```swift
         capabilitiesFetcher: @escaping () async -> Set<String>? = CapabilitiesClient.fetch,
```

Add the assignment beside `self.toolsSaver = toolsSaver` (line 423):

```swift
        self.capabilitiesFetcher = capabilitiesFetcher
```

Add the published property beside `connectedProviders` (line 3450):

```swift
    /// The skills the backend implements, as last read.
    ///
    /// Seeded from the bundled floor rather than empty so first paint is never wrong
    /// in the unsafe direction, then widened by the manifest. Read by every
    /// `isBuilt(builtSkills:)` call in the app.
    @Published private(set) var builtSkills: Set<String> = Toolkit.bundledBuiltSkills
```

Add the method immediately after `refreshConnectorStatus()` (line 3455):

```swift
    /// Re-read the backend's skill manifest.
    ///
    /// Falls back to the bundled floor, never to empty: an empty set would render
    /// every skill as unbuilt, which is a worse lie than the one this pass fixes.
    func refreshCapabilities() async {
        builtSkills = await capabilitiesFetcher() ?? Toolkit.bundledBuiltSkills
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreCapabilitiesTests 2>&1 | tail -25
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Prove the fallback test can fail**

Temporarily change `refreshCapabilities()` to `builtSkills = await capabilitiesFetcher() ?? []`, re-run Step 4, and confirm `testFallsBackToTheFloorRatherThanEmptyWhenTheFetchFails` goes RED. Restore and re-run to green.

- [ ] **Step 6: Commit**

```bash
cd ~/Developer/codepet-env-honesty
git add codepet/Services/CapabilitiesClient.swift codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreCapabilitiesTests.swift
git commit -m "Read the skill manifest, falling back to the bundled floor not empty"
git status --short   # must be empty
```

---

### Task 5: The invariant — an unbuilt item cannot be turned on, and is never offered

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift:3475` (`toggleTool`) and `:1672` (the `env_setup` filter)
- Test: `codepetTests/CompanyStoreCapabilitiesTests.swift` (append)

**Interfaces:**
- Consumes: `CompanyStore.builtSkills` (Task 4), `ToolItem.isBuilt(builtSkills:)` (Task 1).
- Produces: no new API. `toggleTool(id:)` keeps its signature and becomes a no-op for unbuilt ids.

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/CompanyStoreCapabilitiesTests.swift`, inside the class:

```swift
    /// Records every `toolsSaver` call so a test can prove no WRITE happened,
    /// not merely that no visible change happened.
    private final class SaveSpy {
        var calls: [[String]] = []
    }

    private func storeWithSpy(
        enabled: Set<String>,
        capabilities: @escaping () async -> Set<String>? = { Toolkit.bundledBuiltSkills }
    ) -> (CompanyStore, SaveSpy) {
        let spy = SaveSpy()
        var state = CompanyState.empty
        state.enabledTools = enabled
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                             toolsSaver: { _, ids in spy.calls.append(ids); return true },
                             capabilitiesFetcher: capabilities)
        return (s, spy)
    }

    func testTogglingAnUnbuiltItemNeitherChangesStateNorWrites() async {
        let (s, spy) = storeWithSpy(enabled: [])
        await s.refreshCapabilities()
        await s.toggleTool(id: "code-reviewer")     // an agent: nothing can run one
        XCTAssertFalse(s.company.enabledTools.contains("code-reviewer"))
        XCTAssertTrue(spy.calls.isEmpty, "an unbuilt id must not reach the saver")
    }

    func testTogglingAnUnbuiltConnectorDoesNotWrite() async {
        let (s, spy) = storeWithSpy(enabled: [])
        await s.refreshCapabilities()
        await s.toggleTool(id: "notion")            // recommended, but no OAuth exists
        XCTAssertFalse(s.company.enabledTools.contains("notion"))
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testTogglingABuiltItemStillWorks() async {
        let (s, spy) = storeWithSpy(enabled: [])
        await s.refreshCapabilities()
        await s.toggleTool(id: "web-research")
        XCTAssertTrue(s.company.enabledTools.contains("web-research"))
        XCTAssertEqual(spy.calls.count, 1, "the guard must not break the real path")
    }

    func testAnIdOutsideTheCatalogIsRejected() async {
        let (s, spy) = storeWithSpy(enabled: [])
        await s.refreshCapabilities()
        await s.toggleTool(id: "not-a-real-tool")
        XCTAssertFalse(s.company.enabledTools.contains("not-a-real-tool"))
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testAStoredUnbuiltIdSurvivesUntouched() async {
        // The migration decision: leave the data, fix the read. The founder's
        // original intent is preserved, so a later-shipped item arrives already on.
        let (s, spy) = storeWithSpy(enabled: ["prd-writer", "github", "explorer"])
        await s.refreshCapabilities()
        await s.toggleTool(id: "explorer")
        XCTAssertTrue(s.company.enabledTools.contains("explorer"),
                      "nothing in this pass may write to founder prefs")
        XCTAssertTrue(spy.calls.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreCapabilitiesTests 2>&1 | tail -30
```

Expected: `testTogglingAnUnbuiltItemNeitherChangesStateNorWrites`, `testTogglingAnUnbuiltConnectorDoesNotWrite` and `testAnIdOutsideTheCatalogIsRejected` FAIL — today `toggleTool` inserts any id and calls the saver.

If `CompanyState.enabledTools` is not settable from the test, load the state through the injected `loader` exactly as written above; do not add a setter to the model.

- [ ] **Step 3: Write minimal implementation**

In `codepet/Managers/CompanyStore.swift`, change `toggleTool` (line 3475) from:

```swift
    func toggleTool(id: String) async {
        if company.enabledTools.contains(id) {
```

to:

```swift
    func toggleTool(id: String) async {
        // THE invariant, and the reason it lives here rather than only in the views:
        // an unbuilt item must be unreachable from EVERY call site — the two
        // Environment controls, `applySetup` acting on the companion's
        // `setup_capability`, and any site added later. A row that renders no control
        // is the UX; this is what makes the fake on-state impossible.
        //
        // It blocks turning an unbuilt item OFF as well, which is intended: the
        // stored id is preserved deliberately so a later-shipped item arrives on.
        // An id outside the catalog cannot be built by definition, so it is rejected.
        guard let item = Toolkit.catalog.first(where: { $0.id == id }),
              item.isBuilt(builtSkills: builtSkills) else { return }
        if company.enabledTools.contains(id) {
```

Change the `envSetup` construction (line 1672) from:

```swift
        let envSetup = Toolkit.catalog
            .filter { !company.enabledTools.contains($0.id) }
```

to:

```swift
        // `isBuilt` is what stops `setup_capability` pitching something that does
        // nothing. The CF offers only what this list carries, so filtering here
        // needs no backend change.
        let envSetup = Toolkit.catalog
            .filter { !company.enabledTools.contains($0.id) && $0.isBuilt(builtSkills: builtSkills) }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreCapabilitiesTests 2>&1 | tail -30
```

Expected: PASS, 9 tests.

- [ ] **Step 5: Run every suite that touches chat payloads or the store**

The `env_setup` change alters a request payload, so suites asserting on requests must be checked:

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreChatTests -only-testing:codepetTests/ToolkitTests -only-testing:codepetTests/ToolkitIsBuiltTests 2>&1 | tail -30
```

Expected: PASS. If a `CompanyStoreChatTests` case asserts an `env_setup` count that included unbuilt items, update the expected value and add a one-line comment saying unbuilt items are no longer offered — do not weaken the assertion to `>= 0`.

- [ ] **Step 6: Prove the guard is load-bearing**

Temporarily delete the `guard` line pair from `toggleTool`, re-run Step 4, and confirm three tests go RED. Restore and re-run to green.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet-env-honesty
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreCapabilitiesTests.swift
git commit -m "Guard toggleTool and env_setup so an unbuilt item can never turn on"
git status --short   # must be empty
```

---

### Task 6: The chat's enable-card cannot offer what cannot be enabled

Task 5's guard creates a new instance of a bug this codebase has already paid for. `SetupCardState.of` returns `.offer(item)` for any resolvable, currently-off item — including an unbuilt one reached from **stale chat history**, whose card survives in the transcript after the `env_setup` filter stops the CF offering new ones. The founder presses Enable, `activateSetup` calls `toggleTool`, the guard silently returns, and a working-looking button does nothing.

That is exactly the 7 Sep incident recorded in `SetupCardState.swift`'s own doc comment: *"An action with no acknowledgement is indistinguishable from a dead control."* The file's stated rule — *"a card that cannot act must not show a pill that pretends it can"* — is what this task applies.

**Files:**
- Modify: `codepet/Models/SetupCardState.swift` (a new case; `of` gains a parameter)
- Modify: `codepet/Views/Copilot/CopilotChatView.swift:2047` (the one call site) and its `switch` at `:2059-2079`
- Test: `codepetTests/SetupCardStateTests.swift` (append two tests; update 11 existing call sites)

**Interfaces:**
- Consumes: `ToolItem.isBuilt(builtSkills:)` (Task 1), `CompanyStore.builtSkills` (Task 4).
- Produces: `SetupCardState.notBuilt(ToolItem)` and the signature `SetupCardState.of(_ setup: SetupAction, enabledTools: Set<String>, builtSkills: Set<String>) -> SetupCardState`.

**The new parameter is deliberately NOT defaulted.** This repo's `ClaudeCodeStatus.authorised` records why: a defaulted gate is how `sendChat`'s `convenesRoom:` left eight tests red for a day. Requiring it costs 11 mechanical edits and makes every test state which manifest it assumes.

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/SetupCardStateTests.swift`, inside the class:

```swift
    /// A card offering something that does not exist must draw no pill. Reachable
    /// from stale transcript history after the `env_setup` filter stops the CF
    /// offering new ones — and without this, the press would hit `toggleTool`'s
    /// guard and return silently, which is the 7 Sep bug all over again.
    func testAnUnbuiltItemDrawsNoControlEvenThoughItIsOff() {
        let codeReview = SetupAction(category: "skills", name: "Code review")
        let state = SetupCardState.of(codeReview,
                                      enabledTools: [],
                                      builtSkills: Toolkit.bundledBuiltSkills)
        XCTAssertEqual(state, .notBuilt(Toolkit.find(category: "skills", name: "Code review")!))
        // The name is still carried, so the transcript keeps the record of the offer.
        XCTAssertEqual(state.item?.id, "code-review")
    }

    func testAnAgentOfferIsNeverAnOffer() {
        let testWriter = SetupAction(category: "agents", name: "Test Writer")
        XCTAssertEqual(SetupCardState.of(testWriter,
                                         enabledTools: [],
                                         builtSkills: Set(Toolkit.catalog.map(\.id))),
                       .notBuilt(Toolkit.find(category: "agents", name: "Test Writer")!))
    }

    func testAManifestThatBuildsASkillRestoresItsOffer() {
        let codeReview = SetupAction(category: "skills", name: "Code review")
        XCTAssertEqual(SetupCardState.of(codeReview,
                                         enabledTools: [],
                                         builtSkills: ["code-review"]),
                       .offer(Toolkit.find(category: "skills", name: "Code review")!))
    }
```

Then add `builtSkills: Toolkit.bundledBuiltSkills` to all 11 existing `SetupCardState.of(...)` call sites in that file (lines 13, 21, 22, 33, 44, 45, 50, 61, 68, 69, 77). Every existing test's subject is `web-research` or `github`, both built, so all 8 keep passing unchanged.

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/SetupCardStateTests 2>&1 | tail -25
```

Expected: FAILS TO COMPILE — no `builtSkills:` parameter and no `.notBuilt` case.

- [ ] **Step 3: Write minimal implementation**

In `codepet/Models/SetupCardState.swift`, add the case after `unresolved`:

```swift
    /// Resolvable, off, and does nothing yet: title it, and draw NO button.
    ///
    /// Distinct from `unresolved` on purpose — the item is real and nameable, it
    /// simply has no implementation — and distinct from `offer` because the rule
    /// this whole type exists to enforce is that a card which cannot act must not
    /// show a pill that pretends it can. Without this case, `toggleTool`'s guard
    /// would turn the press into a silent no-op: the 7 Sep bug exactly.
    case notBuilt(ToolItem)
```

Change `of` from:

```swift
    static func of(_ setup: SetupAction, enabledTools: Set<String>) -> SetupCardState {
        guard let item = Toolkit.find(category: setup.category, name: setup.name) else {
            return .unresolved
        }
        return enabledTools.contains(item.id) ? .enabled(item) : .offer(item)
    }
```

to:

```swift
    /// `builtSkills` is required rather than defaulted: a defaulted gate is how
    /// `sendChat`'s `convenesRoom:` left eight tests red for a day, and this one
    /// decides whether a control appears at all.
    static func of(_ setup: SetupAction,
                   enabledTools: Set<String>,
                   builtSkills: Set<String>) -> SetupCardState {
        guard let item = Toolkit.find(category: setup.category, name: setup.name) else {
            return .unresolved
        }
        // Already-on is checked FIRST, so a stored id for something since un-built
        // still acknowledges rather than reading as unavailable.
        if enabledTools.contains(item.id) { return .enabled(item) }
        return item.isBuilt(builtSkills: builtSkills) ? .offer(item) : .notBuilt(item)
    }
```

Extend `item` to carry the new case:

```swift
    var item: ToolItem? {
        switch self {
        case .offer(let i), .enabled(let i), .notBuilt(let i): return i
        case .unresolved: return nil
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/SetupCardStateTests 2>&1 | tail -25
```

Expected: FAILS TO COMPILE in the app target — `CopilotChatView.swift:2047` still calls the two-parameter `of`, and its `switch` is no longer exhaustive. That is the next step, not a surprise.

- [ ] **Step 5: Update the one view call site**

In `codepet/Views/Copilot/CopilotChatView.swift`, change line 2047 from:

```swift
        let state = SetupCardState.of(setup, enabledTools: companyStore.company.enabledTools)
```

to:

```swift
        let state = SetupCardState.of(setup,
                                      enabledTools: companyStore.company.enabledTools,
                                      builtSkills: companyStore.builtSkills)
```

And add the case to the `switch`, immediately before `case .unresolved:`:

```swift
            case .notBuilt:
                // Named above, with no pill. `toggleTool` would reject the press
                // anyway, and a button whose press does nothing reads as broken.
                Text(lang == .vi ? "Chưa xây dựng" : "Not built yet")
                    .font(.pixelSystem(size: 10, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
```

- [ ] **Step 6: Run the tests again**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/SetupCardStateTests -only-testing:codepetTests/CompanyStoreChatTests 2>&1 | tail -30
```

Expected: PASS, 11 tests in `SetupCardStateTests`. `CompanyStoreChatTests` includes `testDoneWithSetupAppendsSuggestionAndActivateSetupIsGuarded`, which pins `activateSetup`'s existing guard — it must stay green.

- [ ] **Step 7: Prove the new case is load-bearing**

Temporarily change the last line of `of` to `return .offer(item)`, re-run Step 6, and confirm `testAnUnbuiltItemDrawsNoControlEvenThoughItIsOff` and `testAnAgentOfferIsNeverAnOffer` go RED. Restore and re-run to green.

- [ ] **Step 8: Commit**

```bash
cd ~/Developer/codepet-env-honesty
git add codepet/Models/SetupCardState.swift codepet/Views/Copilot/CopilotChatView.swift codepetTests/SetupCardStateTests.swift
git commit -m "Draw no pill on an enable-card for something that is not built"
git status --short   # must be empty
```

---

### Task 7: The tab says what is true

**Files:**
- Modify: `codepet/Views/Environment/EnvironmentView.swift` — `recs:17`, `needsYouCount:21`, `companionText:178-179`, the `.task:48`, `ToolRowView`'s `provider` doc comment `:338-341`, and the row's control `:368-410`
- Test: manual on-screen verification (a SwiftUI body is not unit-testable here; the predicate behind it is already covered by Tasks 1 and 5)

**Interfaces:**
- Consumes: `CompanyStore.builtSkills`, `CompanyStore.refreshCapabilities()` (Task 4), `Toolkit.recommended(builtSkills:)` (Task 2), `ToolItem.isBuilt(builtSkills:)` (Task 1).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Point the recommendation grid at the live manifest**

In `codepet/Views/Environment/EnvironmentView.swift`, change line 17 from:

```swift
    private var recs: [ToolItem] { Toolkit.recommended }
```

to:

```swift
    /// web `recs` = every recommended item that is actually built. An unbuilt item
    /// stays visible in Browse all, labelled — a catalog may show the future, but a
    /// card promising a benefit may only offer what exists.
    private var recs: [ToolItem] { Toolkit.recommended(builtSkills: companyStore.builtSkills) }
```

`needsYouCount` (line 21) now reads an already-filtered list and needs no edit of its own. Delete the stale half of its comment if it claims otherwise.

- [ ] **Step 2: Fetch the manifest when the tab appears**

Change the `.task` at line 48 from:

```swift
        .task { await companyStore.refreshConnectorStatus() }
```

to:

```swift
        // The server owns connector state, so re-read it whenever this surface
        // appears — a consent completed in another window must not leave a stale
        // "Connect" button here. The skill manifest rides along for the same
        // reason: a skill deployed since launch must not read as unbuilt.
        .task {
            await companyStore.refreshConnectorStatus()
            await companyStore.refreshCapabilities()
        }
```

- [ ] **Step 3: Stop the companion claiming it turned on agents**

Change `companionText`'s EN return (lines 178-179) from:

```swift
        return Text("Based on your ") + boldStage
             + Text(", here's the toolkit I'd set up. I've turned on the skills and agents I can\(tail)")
```

to:

```swift
        // "I've turned on the skills and agents I can" was here and is gone: no
        // agent can be on, so the companion was claiming something it had not done.
        // This now matches the VI string, which never made the agents claim.
        return Text("Based on your ") + boldStage
             + Text(", here's the toolkit I'd set up\(tail)")
```

- [ ] **Step 4: Render "Not built yet" instead of a control**

In `ToolRowView`, replace the now-stale doc comment on `provider` (lines 336-341) — it currently says unbuilt connectors "keep the toggle they have today rather than being quietly disabled; see the note in the PR", which this task reverses:

```swift
    /// The connector behind this row, when a real consent flow exists for it.
    ///
    /// `nil` for skills and agents, which are genuine local flips. Also `nil` for a
    /// connector whose OAuth is not built — but such a row now renders no control at
    /// all (see `isBuilt`), so it can no longer fall through to a local toggle.
    private var provider: ConnectorProvider? {
        item.category == .connectors ? ConnectorProvider(rawValue: item.id) : nil
    }

    /// Whether this row's item does anything today. An unbuilt item renders no
    /// control: there must be nothing to press and no on-state to fake.
    private var isBuilt: Bool { item.isBuilt(builtSkills: companyStore.builtSkills) }
```

Then in `body`, wrap the existing `Button` (line 368, `Button {`, through line 412, `.disabled(connecting)`) in an `isBuilt` branch. The result:

```swift
            Spacer(minLength: 8)
            if !isBuilt {
                // Replaces the control entirely rather than disabling it. A dimmed
                // toggle still reads as something to press; a plain label does not.
                Text(lang == .vi ? "Chưa xây dựng" : "Not built yet")
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 15).padding(.vertical, 6)
                    .fixedSize()
            } else {
                Button {
                    if let provider {
                        // A real connector: consent, then reconcile from the server.
                        // Never flips a local flag on its own — the token has to exist.
                        connecting = true
                        Task {
                            await companyStore.connectProvider(provider)
                            connecting = false
                        }
                    } else {
                        Task { await companyStore.toggleTool(id: item.id) }
                    }
                } label: {
                    if connecting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 15).padding(.vertical, 4)
                    } else if on {
                        // web `.eb.on` — borderless, quiet: a filled tick + muted label
                        HStack(spacing: 6) {
                            Text("✓")
                                .font(CodepetTheme.inter(10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(CodepetTheme.accentPurple))
                            Text(item.category.onLabel(lang))
                                .font(CodepetTheme.inter(12))
                                .foregroundColor(CodepetTheme.mutedText)
                        }
                        .padding(6)
                    } else {
                        Text(item.category.enableVerb(lang))
                            .font(CodepetTheme.inter(12, weight: .semibold))
                            .foregroundColor(CodepetTheme.accentPurple)
                            .padding(.horizontal, 15).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(CodepetTheme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(CodepetTokens.accentLine, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(connecting)
            }
```

- [ ] **Step 5: Build the app, signed**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild -scheme codepet -destination 'platform=macOS' -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. Build team-signed, not adhoc — adhoc breaks the keychain and Firebase auth will not work at runtime.

- [ ] **Step 6: Verify on screen, not by reading the diff**

Quit any running `codepet.app` first, then launch the build from Step 5 and open the Environment tab.

```bash
screencapture -x /tmp/env-tab.png && open /tmp/env-tab.png
```

Confirm all four, by looking:

1. Under **Browse all → Agents**, all four rows read "Not built yet" with **no** button.
2. Under **Connectors**, `github` still shows a real Connect/Connected control; `notion`, `figma`, `slack`, `linear` read "Not built yet".
3. **Recommended for your project** shows exactly two cards: PRD writer and GitHub.
4. The companion paragraph no longer says "I've turned on the skills and agents I can".

"Still looks the same" means a stale build, not a failed change — rebuild before concluding anything. Do not mark this step done from the diff alone; the whole point of the pass is what the founder sees.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet-env-honesty
git add codepet/Views/Environment/EnvironmentView.swift
git commit -m "Render the real state of an unbuilt toolkit item"
git status --short   # must be empty
```

---

### Task 8: Whole-suite verification and handoff

**Files:** none modified.

- [ ] **Step 1: Run every suite this plan touched**

```bash
cd ~/Developer/codepet-env-honesty && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:codepetTests/ToolkitTests \
  -only-testing:codepetTests/ToolkitIsBuiltTests \
  -only-testing:codepetTests/CompanyStoreCapabilitiesTests \
  -only-testing:codepetTests/SetupCardStateTests \
  -only-testing:codepetTests/CompanyStoreChatTests 2>&1 | tail -30
```

Expected: PASS, no failures.

- [ ] **Step 2: Count results from the result bundle, not the log tail**

```bash
cd ~/Developer/codepet-env-honesty && xcrun xcresulttool get test-results summary --path "$(ls -td ~/Library/Developer/Xcode/DerivedData/codepet-*/Logs/Test/*.xcresult | head -1)" 2>&1 | head -30
```

A grep of the log tail has reported false greens before; the result bundle is the only trustworthy count.

- [ ] **Step 3: Run the functions suite**

```bash
cd ~/Developer/codepet-env-honesty/functions && npx jest 2>&1 | tail -25
```

Expected: PASS. `companyChat.test.ts` asserts on `parseEnabledSkills` and must be unaffected — this plan changed no CF behaviour, only added an endpoint.

- [ ] **Step 4: Confirm no founder-pref write was introduced**

```bash
cd ~/Developer/codepet-env-honesty && git diff origin/main --unified=0 | grep -nE '^\+.*(toolsSaver|saveEnabledTools|enabledTools\s*=|enabledTools\.(insert|remove))' || echo "clean: no new write to enabledTools"
```

Expected: `clean: no new write to enabledTools`. The one `enabledTools.insert`/`.remove` pair inside `toggleTool` is pre-existing and unchanged; anything else added is a spec violation (decision 6).

- [ ] **Step 5: Review the commit series**

```bash
cd ~/Developer/codepet-env-honesty && git log --oneline origin/main..HEAD && git status --short
```

Expected: nine commits (the spec, this plan, and seven task commits) and an empty status.

- [ ] **Step 6: Stop and hand back**

Do **not** push, open a PR, or deploy. Report to the founder: the commit list, the test counts from Step 2 and Step 3, and the four on-screen confirmations from Task 6 Step 6.

Note for the founder in that report: **CI runs nothing on a pushed branch** — a PR is required, even a draft, and the `capabilities` endpoint does not exist in production until `functions/` is deployed from main. Until that deploy, `CapabilitiesClient.fetch` returns `nil` and the app runs on `Toolkit.bundledBuiltSkills`, which is correct and is exactly what the Task 4 fallback test covers.

## Self-Review

**Spec coverage.** Every decision maps to a task: decision 2 (the predicate) → Task 1; decision 5 (recommendations) and 7 (defaults) → Task 2; decision 3 (the manifest endpoint) → Task 3; the client half of decision 3 → Task 4; the `toggleTool` guard, the `env_setup` filter and decision 6 (leave the data) → Task 5; decision 4 (row presentation) → Task 7. The spec's "Call sites" table rows 1-8 are all covered.

**Two additions the spec's table did not list**, both found while writing this plan and both the same lie in a different surface:

- Task 7 Step 3 — the EN companion string claimed "I've turned on the skills and agents I can". No agent can be on, so the companion was reporting an action it had not taken. The VI string never made the claim, so this also brings the two into parity.
- Task 6 in full — `SetupCardState.of` would return `.offer` for an unbuilt item reached from stale chat history, and Task 5's guard would then make the press a silent no-op. That is precisely the 7 Sep incident that `SetupCardState` was created to prevent, so the pass would have reintroduced the bug it exists to fix. Add both to the spec's call-site table when it is next edited.

**One spec correction, made deliberately.** The spec's decision 7 says a test asserts no `defaultOn` item is unbuilt. It did not say what that test asserts *on*. Task 2 asserts on the raw `catalog.filter(\.defaultOn)` data and leaves `defaultEnabledIds` unfiltered, because filtering the accessor would make the guard pass vacuously forever — a later default-on fake would be masked rather than caught. Update the spec's decision 7 to say so if it is edited again.

**Placeholder scan.** No TBD/TODO. Every code step carries the actual code; every command carries its expected output. Task 7 is the only task with no unit test, because a SwiftUI `body` is not unit-testable in this target — the predicate behind it is covered by Tasks 1 and 5, and its Step 6 substitutes a real on-screen check rather than asserting on a property. Every other task ends with a step that deletes its own guard and confirms the test goes red, which is the repo's stated rule: a test that passes with and without the code it protects is not protecting anything.

**Type consistency.** `isBuilt(builtSkills:)` takes `Set<String>` at every call site (Tasks 1, 2, 5, 6, 7). `Toolkit.recommended(builtSkills:)` is a function everywhere after Task 2, including both updated `ToolkitTests` assertions. `SetupCardState.of` takes `(_ setup:, enabledTools:, builtSkills:)` in Task 6's implementation, its three new tests, the 11 updated existing call sites, and `CopilotChatView:2047` — the parameter is required, never defaulted. `capabilitiesFetcher` is `() async -> Set<String>?` in the stored property, the init parameter, and every test. `builtSkills` is the property name on `CompanyStore` and the argument label everywhere. `capabilitiesPayload()` returns `{ skills: string[] }`, the exact shape `CapabilitiesClient.Payload` decodes.

**One ordering dependency worth naming.** Task 6 must come after Task 5, not before: its whole justification is the silent no-op that Task 5's guard introduces. Running them in the other order leaves a window where the guard exists and the card still offers.
