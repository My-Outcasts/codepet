# Phase 2 — Onboarding → Per-Account Company Brief — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fresh account runs a first-run founder interview → the brief is enriched and written to `companies/{uid}` → the shell shows the company.

**Architecture:** Extend `CompanyState`/`CompanyDoc` with `onboardedAt` (ISO string) and add `CompanyData.saveBrief` (the first native `companies/{uid}` write). `CompanyStore` gains `needsOnboarding`/`isOnboarding`/`finishOnboarding`/`skipOnboarding` (injectable saver; `isOnboarding` set after `hydrate`). A `CompanyOnboardingModel`/`CompanyOnboardingView` re-base SP1's 6-step interview + `enrichBrief` per-account. `ContentView` gates: authed → `CompanyOnboardingView` when `isOnboarding`, else `AppShellView`.

**Tech Stack:** Swift/SwiftUI (macOS 13+), Firebase Firestore. Reuses `CompanyBrief`, `BriefContext.compose` (SP1), `ReflectionAPIClient.enrichBrief` (deployed), `CompanyStore`/`CompanyData`/`AppShellView` (Phase 1), `CodepetTheme`/`.pixelSystem`/`uiLanguage`. Spec: `docs/superpowers/specs/2026-07-20-phase2-onboarding-brief-design.md`.

## Global Constraints

- **Worktree/branch:** `~/Documents/codepet-rebuild-wt`, branch `feat/native-web-product`. `My-Outcasts/codepet`.
- **Toolchain:** scheme **`codepet`** (lowercase); NO `xcodegen`; test module **`@testable import codepet`**. **Run all `xcodebuild` in the FOREGROUND** (never background or pause on a build). Test: `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<Class> 2>&1 | tail -25`. Full build: `xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`. SourceKit cross-file diagnostics are FALSE POSITIVES — trust xcodebuild. `git diff`/`status` HANG on this iCloud worktree — use `ls`/`test`/`grep`, and long timeouts for git.
- **`onboardedAt` is an ISO-8601 STRING** in the doc (JSON-safe — keeps the Phase-1 `JSONSerialization` load path working; NOT a Firestore `Timestamp`).
- **Fail-open** enrich (`(try? await api.enrichBrief(raw)) ?? raw`); **fail-soft** write (`saveBrief` returns `false` on failure; `finishOnboarding` still clears `isOnboarding` + keeps the in-memory brief).
- **`needsOnboarding` mirrors the web:** `company.onboardedAt == nil && BriefContext.compose(company.brief) == nil`.
- Design in `CodepetTheme` + `.pixelSystem`, VI/EN via `@Environment(\.uiLanguage)`. Scaffold/roadmap deferred to Phase 4. Do NOT touch Giang's files or `CLAUDE.md`. Staged retirement: leave the SP1 `ProjectInterviewModel`/`ProjectStore` code in place (unreferenced).

---

## File Structure
- Modify `codepet/Models/CompanyState.swift` + `codepet/Services/CompanyData.swift` (Task 1)
- Modify `codepet/Managers/CompanyStore.swift` (Task 2)
- Create `codepet/Views/Onboarding/CompanyOnboardingModel.swift` (Task 3)
- Create `codepet/Views/Onboarding/CompanyOnboardingView.swift` + modify `codepet/App/ContentView.swift` (Task 4)
- Tests under `codepetTests/`

---

### Task 1: `onboardedAt` + `CompanyData.saveBrief`

**Files:**
- Modify: `codepet/Models/CompanyState.swift`, `codepet/Services/CompanyData.swift`
- Test: `codepetTests/CompanyDataSaveTests.swift`

**Interfaces:**
- Produces: `CompanyState.onboardedAt: Date?`; `CompanyDoc.onboardedAt: String?`; `CompanyData.briefPayload(_:onboardedAt:) -> [String: Any]` (pure); `CompanyData.saveBrief(companyId:brief:) async -> Bool`. `state(from:)` maps `onboardedAt`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyDataSaveTests.swift
import XCTest
@testable import codepet

final class CompanyDataSaveTests: XCTestCase {
    func testStateMapsOnboardedAtISOString() {
        let iso = "2026-07-20T10:00:00Z"
        let s = CompanyData.state(from: CompanyDoc(brief: CompanyBrief(projectName: "Codepet"),
                                                   stage: "building", companionId: "nova", onboardedAt: iso))
        XCTAssertNotNil(s.onboardedAt)
        XCTAssertNil(CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil, onboardedAt: nil)).onboardedAt)
    }
    func testBriefPayloadHasBriefDictAndOnboardedAt() {
        let payload = CompanyData.briefPayload(CompanyBrief(projectName: "Codepet", oneLiner: "a recap tool"),
                                               onboardedAt: "2026-07-20T10:00:00Z")
        XCTAssertEqual(payload["onboardedAt"] as? String, "2026-07-20T10:00:00Z")
        let brief = payload["brief"] as? [String: Any]
        XCTAssertEqual(brief?["projectName"] as? String, "Codepet")
        XCTAssertEqual(brief?["oneLiner"] as? String, "a recap tool")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (FOREGROUND): `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataSaveTests 2>&1 | tail -25`
Expected: FAIL — extra `onboardedAt:` arg to `CompanyDoc`, no `briefPayload`/`onboardedAt` member.

- [ ] **Step 3: Add `onboardedAt` to the models**

In `codepet/Models/CompanyState.swift`, add to `CompanyState` (after `var companionId: String`):

```swift
    var onboardedAt: Date?
```

And update `.empty` to include it:

```swift
    static let empty = CompanyState(
        brief: CompanyBrief(), departments: [], library: [], stage: .idea, companionId: "byte", onboardedAt: nil)
```

- [ ] **Step 4: Add `onboardedAt` + `saveBrief` to `CompanyData`**

In `codepet/Services/CompanyData.swift`:

1. Add to `CompanyDoc`:

```swift
    var onboardedAt: String?   // ISO-8601 string (JSON-safe; not a Firestore Timestamp)
```

2. In `state(from:)`, add the `onboardedAt` mapping to the returned `CompanyState`:

```swift
            companionId: doc.companionId ?? "byte",
            onboardedAt: doc.onboardedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
```

3. Add the pure payload builder + the write (inside `enum CompanyData`):

```swift
    /// Pure Firestore payload for a brief write — testable without Firestore.
    static func briefPayload(_ brief: CompanyBrief, onboardedAt: String) -> [String: Any] {
        var payload: [String: Any] = ["onboardedAt": onboardedAt]
        if let data = try? JSONEncoder().encode(brief),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            payload["brief"] = dict
        }
        return payload
    }

    /// Write companies/{uid} (brief + onboardedAt), merge. Fail-soft: false on error.
    /// First native write to companies/{uid}.
    static func saveBrief(companyId: String, brief: CompanyBrief) async -> Bool {
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            try await Firestore.firestore().collection("companies").document(companyId)
                .setData(briefPayload(brief, onboardedAt: iso), merge: true)
            return true
        } catch {
            return false
        }
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/Models/CompanyState.swift codepet/Services/CompanyData.swift codepetTests/CompanyDataSaveTests.swift
git commit -m "feat(onboarding): onboardedAt + CompanyData.saveBrief (companies/{uid} write)"
```

---

### Task 2: `CompanyStore` onboarding (needsOnboarding / finishOnboarding / skip)

**Files:**
- Modify: `codepet/Managers/CompanyStore.swift`
- Test: `codepetTests/CompanyStoreOnboardingTests.swift`

**Interfaces:**
- Consumes: `CompanyState.onboardedAt`, `CompanyData.saveBrief` (Task 1); `BriefContext.compose` (SP1).
- Produces: `CompanyStore` gains `@Published private(set) var isOnboarding`, `private(set) var companyId: String?`, `var needsOnboarding: Bool`, `func finishOnboarding(brief:) async`, `func skipOnboarding() async`, an injectable `saver`; `hydrate` sets `isOnboarding`; `reset` clears it.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyStoreOnboardingTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreOnboardingTests: XCTestCase {
    private func store(loader: @escaping (String) async -> CompanyState,
                       saver: @escaping (String, CompanyBrief) async -> Bool = { _, _ in true }) -> CompanyStore {
        CompanyStore(loader: loader, saver: saver)
    }

    func testNeedsOnboardingWhenNoStampAndNoBriefSignal() async {
        let s = store(loader: { _ in .empty })
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.needsOnboarding)
        XCTAssertTrue(s.isOnboarding)
    }
    func testNotNeededWhenBriefHasSignal() async {
        let seeded = CompanyState(brief: CompanyBrief(projectName: "Codepet", oneLiner: "x"),
                                  departments: [], library: [], stage: .building, companionId: "byte", onboardedAt: nil)
        let s = store(loader: { _ in seeded })
        await s.hydrate(companyId: "u")
        XCTAssertFalse(s.isOnboarding)
    }
    func testFinishOnboardingSavesStampsAndClears() async {
        var savedBrief: CompanyBrief?
        let s = store(loader: { _ in .empty }, saver: { _, b in savedBrief = b; return true })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: CompanyBrief(projectName: "Codepet"))
        XCTAssertEqual(savedBrief?.projectName, "Codepet")
        XCTAssertEqual(s.company.brief.projectName, "Codepet")
        XCTAssertNotNil(s.company.onboardedAt)
        XCTAssertFalse(s.isOnboarding)
    }
    func testFinishClearsEvenWhenSaveFails() async {
        let s = store(loader: { _ in .empty }, saver: { _, _ in false })
        await s.hydrate(companyId: "u")
        await s.finishOnboarding(brief: CompanyBrief(projectName: "Codepet"))
        XCTAssertFalse(s.isOnboarding)                       // not trapped by a failed write
        XCTAssertEqual(s.company.brief.projectName, "Codepet") // in-memory brief kept
    }
    func testSkipStampsAndClears() async {
        let s = store(loader: { _ in .empty })
        await s.hydrate(companyId: "u")
        await s.skipOnboarding()
        XCTAssertFalse(s.isOnboarding)
        XCTAssertNotNil(s.company.onboardedAt)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (FOREGROUND): `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyStoreOnboardingTests 2>&1 | tail -25`
Expected: FAIL — no `saver`/`isOnboarding`/`needsOnboarding`/`finishOnboarding`/`skipOnboarding`.

- [ ] **Step 3: Extend `CompanyStore`**

Add the new stored/published properties (near the existing ones):

```swift
    @Published private(set) var isOnboarding: Bool = false
    /// The hydrated company's id, needed for writes. Set by `hydrate`, cleared by `reset`.
    private(set) var companyId: String?
    private let saver: (String, CompanyBrief) async -> Bool
```

Update `init` to inject the saver:

```swift
    init(loader: @escaping (String) async -> CompanyState = CompanyData.load,
         saver: @escaping (String, CompanyBrief) async -> Bool = CompanyData.saveBrief) {
        self.loader = loader
        self.saver = saver
    }
```

Add the computed gate:

```swift
    /// Mirrors the web: onboard unless a stamp exists OR the brief already has signal.
    var needsOnboarding: Bool {
        company.onboardedAt == nil && BriefContext.compose(company.brief) == nil
    }
```

In `hydrate`, set `companyId` before the await and `isOnboarding` after the guard-passed assignment:

```swift
    func hydrate(companyId: String) async {
        hydrationToken &+= 1
        let token = hydrationToken
        self.companyId = companyId
        isHydrating = true
        let loaded = await loader(companyId)
        guard token == hydrationToken else { return }
        company = loaded
        isHydrating = false
        isOnboarding = needsOnboarding
    }
```

Add finish/skip (inside the class):

```swift
    /// Enrich already happened in the model; here we persist + stamp + leave onboarding.
    /// Fail-soft: a failed cloud write still lets the founder into the app.
    func finishOnboarding(brief: CompanyBrief) async {
        if let cid = companyId { _ = await saver(cid, brief) }
        company.brief = brief
        company.onboardedAt = Date()
        isOnboarding = false
    }

    /// Skip: stamp with the current (empty) brief so they aren't re-blocked.
    func skipOnboarding() async {
        if let cid = companyId { _ = await saver(cid, company.brief) }
        company.onboardedAt = Date()
        isOnboarding = false
    }
```

In `reset()`, add `companyId = nil` and `isOnboarding = false`:

```swift
    func reset() {
        hydrationToken &+= 1
        companyId = nil
        company = .empty
        view = .overview
        isHydrating = false
        isOnboarding = false
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/Managers/CompanyStore.swift codepetTests/CompanyStoreOnboardingTests.swift
git commit -m "feat(onboarding): CompanyStore needsOnboarding + finish/skip onboarding"
```

---

### Task 3: `CompanyOnboardingModel`

**Files:**
- Create: `codepet/Views/Onboarding/CompanyOnboardingModel.swift`
- Test: `codepetTests/CompanyOnboardingModelTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief`, `CompanyStore.finishOnboarding` (Task 2), `ReflectionAPIClientProtocol.enrichBrief` (SP1).
- Produces: `@MainActor final class CompanyOnboardingModel: ObservableObject` — 6 fields, `static let stages`, `buildBrief()`, `submit(store:api:) async`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyOnboardingModelTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyOnboardingModelTests: XCTestCase {
    func testBuildBriefMapsFieldsAndStage() {
        let m = CompanyOnboardingModel()
        m.founderName = "Mona"; m.role = "Founder"; m.projectName = "Codepet"
        m.oneLiner = "a recap tool"; m.audience = "devs"; m.stageIndex = 1
        let b = m.buildBrief()
        XCTAssertEqual(b.founderName, "Mona")
        XCTAssertEqual(b.projectName, "Codepet")
        XCTAssertEqual(b.oneLiner, "a recap tool")
        XCTAssertEqual(b.stage, CompanyOnboardingModel.stages[1])
    }
    func testSubmitEnrichesAndFinishes() async {
        let m = CompanyOnboardingModel()
        m.projectName = "Codepet"; m.oneLiner = "a recap tool"
        let store = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true })
        await store.hydrate(companyId: "u")
        let api = OnboardEnrichStub(returning: CompanyBrief(projectName: "Codepet", summary: "Enriched."))
        await m.submit(store: store, api: api)
        XCTAssertEqual(store.company.brief.summary, "Enriched.")
        XCTAssertFalse(store.isOnboarding)
    }
    func testSubmitFailOpenStillFinishes() async {
        let m = CompanyOnboardingModel(); m.projectName = "Codepet"
        let store = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true })
        await store.hydrate(companyId: "u")
        await m.submit(store: store, api: ThrowingEnrichStub())
        XCTAssertEqual(store.company.brief.projectName, "Codepet") // raw brief kept
        XCTAssertFalse(store.isOnboarding)
    }
}

final class OnboardEnrichStub: ReflectionAPIClientProtocol {
    let out: CompanyBrief
    init(returning: CompanyBrief) { self.out = returning }
    func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief { out }
}
final class ThrowingEnrichStub: ReflectionAPIClientProtocol {
    func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief { throw ReflectionAPIError.malformedResponse }
}
```

> `ReflectionAPIClientProtocol` has default-throw extensions for most methods (from SP1), so these stubs only need `enrichBrief`. If the compiler demands more non-defaulted methods, add them as `throw ReflectionAPIError.malformedResponse` / empty streams — trim to what it requires.

- [ ] **Step 2: Run test to verify it fails**

Run (FOREGROUND): `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyOnboardingModelTests 2>&1 | tail -25`
Expected: FAIL — `cannot find 'CompanyOnboardingModel' in scope`.

- [ ] **Step 3: Write the model**

```swift
// codepet/Views/Onboarding/CompanyOnboardingModel.swift
import Foundation
import Combine

/// Drives the first-run founder interview (per-account). Re-bases SP1's field
/// mapping onto CompanyStore: collect 6 fields → enrich (fail-open) → the store
/// persists to companies/{uid} and stamps onboardedAt.
@MainActor
final class CompanyOnboardingModel: ObservableObject {
    @Published var founderName = ""
    @Published var role = ""
    @Published var projectName = ""
    @Published var oneLiner = ""
    @Published var audience = ""
    @Published var stageIndex = 2
    @Published var isSubmitting = false

    /// Onboarding stage labels (mirror the web OB_STAGES ordering).
    static let stages = ["Idea", "Prototype", "Building", "Private beta", "Launched"]

    func buildBrief() -> CompanyBrief {
        func nz(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return CompanyBrief(
            founderName: nz(founderName), role: nz(role),
            stage: Self.stages[min(max(stageIndex, 0), Self.stages.count - 1)],
            projectName: nz(projectName), oneLiner: nz(oneLiner), audience: nz(audience))
    }

    /// Enrich (fail-open) then hand to the store to persist + finish onboarding.
    func submit(store: CompanyStore, api: ReflectionAPIClientProtocol) async {
        isSubmitting = true
        defer { isSubmitting = false }
        let raw = buildBrief()
        let enriched = (try? await api.enrichBrief(raw)) ?? raw
        await store.finishOnboarding(brief: enriched)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/Views/Onboarding/CompanyOnboardingModel.swift codepetTests/CompanyOnboardingModelTests.swift
git commit -m "feat(onboarding): CompanyOnboardingModel (6-field interview, fail-open enrich)"
```

---

### Task 4: `CompanyOnboardingView` + `ContentView` gate

**Files:**
- Create: `codepet/Views/Onboarding/CompanyOnboardingView.swift`
- Modify: `codepet/App/ContentView.swift`

**Interfaces:**
- Consumes: `CompanyOnboardingModel` (Task 3), `CompanyStore` (Task 2, `@EnvironmentObject`), `AppShellView` (Phase 1), `CodepetTheme`, `.pixelSystem`.
- Produces: `struct CompanyOnboardingView: View`; the authed gate in `ContentView`.

- [ ] **Step 1: Write the view**

```swift
// codepet/Views/Onboarding/CompanyOnboardingView.swift
import SwiftUI

/// First-run founder interview, shown before the shell for a fresh account.
/// 6 steps → enrich → persist to companies/{uid}. Styled in CodepetTheme, VI/EN.
struct CompanyOnboardingView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var uiLanguage
    @StateObject private var model = CompanyOnboardingModel()
    @State private var step = 0
    private let api: ReflectionAPIClientProtocol = ReflectionAPIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(uiLanguage == .vi ? "Chào mừng đến Codepet" : "Welcome to Codepet")
                .font(.pixelSystem(size: 20, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(uiLanguage == .vi ? "Kể cho tôi về công ty của bạn." : "Tell me about your company.")
                .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)

            switch step {
            case 0: field(uiLanguage == .vi ? "Tôi nên gọi bạn là gì?" : "What should I call you?", $model.founderName, "e.g. Mona")
            case 1: field(uiLanguage == .vi ? "Vai trò của bạn?" : "Which best describes you?", $model.role, "e.g. Founder")
            case 2: field(uiLanguage == .vi ? "Dự án tên gì?" : "What's it called?", $model.projectName, "e.g. Codepet")
            case 3: field(uiLanguage == .vi ? "Một câu mô tả?" : "In one line, what is it?", $model.oneLiner, "e.g. a recap tool for founders")
            case 4: field(uiLanguage == .vi ? "Dành cho ai?" : "Who is it for?", $model.audience, "e.g. solo founders")
            default:
                Text(uiLanguage == .vi ? "Giai đoạn?" : "What stage is it at?")
                    .font(.pixelSystem(size: 13, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                Picker("", selection: $model.stageIndex) {
                    ForEach(Array(CompanyOnboardingModel.stages.enumerated()), id: \.offset) { i, s in Text(s).tag(i) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            HStack {
                Button(uiLanguage == .vi ? "Bỏ qua" : "Skip") { Task { await companyStore.skipOnboarding() } }
                    .buttonStyle(.plain).foregroundColor(CodepetTheme.mutedText)
                Spacer()
                if step < 5 {
                    Button(uiLanguage == .vi ? "Tiếp" : "Next") { step += 1 }
                        .buttonStyle(.plain).foregroundColor(CodepetTheme.accentPurple)
                } else {
                    Button(model.isSubmitting ? (uiLanguage == .vi ? "Đang lưu…" : "Saving…")
                                              : (uiLanguage == .vi ? "Hoàn tất" : "Finish")) {
                        Task { await model.submit(store: companyStore, api: api) }
                    }
                    .buttonStyle(.plain).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
                    .disabled(model.isSubmitting)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CodepetTheme.pageBackground)
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.pixelSystem(size: 14, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
```

- [ ] **Step 2: Add the gate in `ContentView`**

In `codepet/App/ContentView.swift`, the authed branch currently reads:

```swift
            } else {
                // Authenticated (or guest) — the company shell (web product).
                AppShellView()
            }
```

Replace it with the onboarding gate:

```swift
            } else if companyStore.isOnboarding {
                // Fresh account — first-run founder interview before the shell.
                CompanyOnboardingView()
            } else {
                // Authenticated (or guest) — the company shell (web product).
                AppShellView()
            }
```

- [ ] **Step 3: Full build to verify**

Run (FOREGROUND): `cd ~/Documents/codepet-rebuild-wt && xcodebuild build -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -15`
Expected: `** BUILD SUCCEEDED **`. A fresh account now sees `CompanyOnboardingView`; finishing (or skipping) flips `isOnboarding` false and routes to `AppShellView`.

- [ ] **Step 4: Commit**

```bash
cd ~/Documents/codepet-rebuild-wt
git add codepet/Views/Onboarding/CompanyOnboardingView.swift codepet/App/ContentView.swift
git commit -m "feat(onboarding): CompanyOnboardingView + ContentView first-run gate"
```

---

## Final verification

Run the Phase-2 suite + build (FOREGROUND): `cd ~/Documents/codepet-rebuild-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyDataSaveTests -only-testing:codepetTests/CompanyStoreOnboardingTests -only-testing:codepetTests/CompanyOnboardingModelTests 2>&1 | tail -20` — all pass; `xcodebuild build ...` → `** BUILD SUCCEEDED **`.

---

## Self-Review

**Spec coverage:** onboardedAt + saveBrief write (Task 1 ✓), needsOnboarding/isOnboarding/finish/skip (Task 2 ✓), CompanyOnboardingModel re-basing buildBrief + fail-open enrich (Task 3 ✓), CompanyOnboardingView + gate (Task 4 ✓). ISO-string onboardedAt ✓; fail-open enrich + fail-soft write ✓; scaffold deferred ✓; CodepetTheme/VI-EN ✓; staged retirement (SP1 model left) ✓; Giang/CLAUDE.md untouched ✓.

**Type consistency:** `CompanyState.onboardedAt: Date?` / `CompanyDoc.onboardedAt: String?` defined Task 1, used Task 2. `saver: (String, CompanyBrief) async -> Bool` = `CompanyData.saveBrief` signature (Task 1) matches `CompanyStore.init` (Task 2). `finishOnboarding(brief:)`/`skipOnboarding()`/`isOnboarding` defined Task 2, consumed Tasks 3/4. `CompanyOnboardingModel.submit(store:api:)`/`stages`/`buildBrief` defined Task 3, consumed Task 4. `needsOnboarding` uses `BriefContext.compose` (SP1) consistently.

**Known verification gaps for the implementer (resolve inline):** (a) trim the enrich stubs in Task 3 to the protocol's actual non-defaulted set (compiler-driven); (b) confirm `ReflectionAPIError.malformedResponse` is the right error case name for the throwing stub (it's what SP1 used); (c) the `ContentView` authed-branch text may differ slightly from Phase 1's exact comment — match the real `else { AppShellView() }` block when inserting the gate.
