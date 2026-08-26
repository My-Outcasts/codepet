# Pet Topic Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Suggest the right department pet from what the founder is typing, before they name a department, as a tentative composer chip they confirm by pressing Send.

**Architecture:** Three new pure Swift types — `TextRelevance` (tokenizer, extracted from `ChatContext`), `DepartmentTopics` (per-department vocabulary), `DepartmentRouter` (a four-tier decision) — plus two `@State` properties and a weakened chip treatment in the existing composer. Tier 1 calls today's `DepartmentCompanions.mentionedDeptKey` unchanged and runs first, so existing behaviour and existing tests are untouched; everything new is a lower-confidence tier beneath it. Nothing downstream of the send changes.

**Tech Stack:** Swift 5 / SwiftUI, macOS, XCTest. No new dependencies. No `functions/` change, no wire change, no Firestore rule change.

**Spec:** `docs/superpowers/specs/2026-08-24-pet-topic-routing-design.md` — read it before Task 1. Where this plan and the spec disagree, the spec wins, except for the two deviations named in "Global Constraints" below.

## Global Constraints

- **Branch:** `feat/pet-topic-routing`, already cut from `origin/main` @ `58777fe`. Worktree `~/Developer/codepet-two-mode`. The spec is already committed there at `90ecf70`.
- **New `.swift` files need no `.xcodeproj` edit.** `PBXFileSystemSynchronizedRootGroup` — target membership follows the folder on disk (CLAUDE.md landmine 5).
- **Per-suite test command** (used in every task):
  ```bash
  xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
    -only-testing:codepetTests/<SuiteName> \
    CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
  ```
  `-derivedDataPath build/dd-ci` is **not optional**: without it the unsigned test build overwrites the signed `codepet.app` in shared DerivedData and silently breaks Firebase sign-in (CLAUDE.md).
- **Quit any running `codepet.app` before testing.** A live instance holds the Firestore lock and kills the test host, with a different victim each run.
- **A `-only-testing:` branch is an untested branch.** Task 8 runs the full suite via `./scripts/ci-test.sh` and is not optional.
- **The XCTest host crashes on Xcode 26.2** when a `@MainActor ObservableObject` deallocates — ~27 of ~970 tests never finish and `xcodebuild test` exits 65 on a clean checkout. Not a regression. `scripts/ci-test.sh` already distinguishes this from a real failure; trust its verdict, not the exit code.
- **Lexicon entries must never be department names.** Tier 1 owns those words. Enforced by a test in Task 2.
- **Lexicon single-word entries must be ≥3 characters and not stopwords**, or `TextRelevance.tokenize` drops them and the entry is dead on arrival. Enforced by a test in Task 2. This is why `ux`, `ui`, and `ci` are absent.
- **Two deliberate deviations from the spec**, both narrower than what the spec allows:
  1. Spec §3.4 says `lastActedDeptKey` is "set after a reply lands". This plan sets it **at send time**, from the department actually sent. The value is identical and it needs no completion hook. Cost: a send that fails on the network still records ownership.
  2. Spec §3.3's `Suggestion.reason` is built in the router but rendered by the view; the router returns the matched term only, and the view composes the founder-facing sentence so the string stays localizable.

---

### Task 1: Extract `TextRelevance` from `ChatContext`

A pure move. `ChatContext` must behave identically afterward — the existing `ChatContextTests` are the proof.

**Files:**
- Create: `codepet/Models/TextRelevance.swift`
- Modify: `codepet/Models/ChatContext.swift:16-45` (delete), `:69`, `:73-74` (call sites)
- Test: `codepetTests/TextRelevanceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `TextRelevance.tokenize(_ s: String) -> Set<String>`, `TextRelevance.overlap(_ a: Set<String>, _ b: Set<String>) -> Int`, `TextRelevance.stopwords: Set<String>`. Tasks 2 and 4 use all three.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/TextRelevanceTests.swift`:

```swift
import XCTest
@testable import codepet

/// The tokenizer moved out of `ChatContext` so `DepartmentRouter` could use it without a
/// second copy of the stopword list. A duplicated stopword list is a live trap: fixing one
/// copy leaves the other wrong, silently, in a grounding path.
final class TextRelevanceTests: XCTestCase {
    func testTokenizeLowercasesDedupesAndDropsShortWords() {
        let tokens = TextRelevance.tokenize("Pricing pricing PRICING at $19 ok")
        XCTAssertTrue(tokens.contains("pricing"))
        XCTAssertEqual(tokens.filter { $0 == "pricing" }.count, 1)
        // Under three characters never survives — this is why the lexicon has no "ux"/"ui".
        XCTAssertFalse(tokens.contains("at"))
        XCTAssertFalse(tokens.contains("19"))
    }

    func testTokenizeDropsStopwords() {
        let tokens = TextRelevance.tokenize("the and for our your their")
        XCTAssertTrue(tokens.isEmpty, "stopwords carry no signal; got \(tokens)")
    }

    func testTokenizeSplitsOnPunctuationSoWholeWordsOnly() {
        // "designed" must never match "design" — the Aug 7 substring defect.
        let tokens = TextRelevance.tokenize("well-designed, fast/cheap")
        XCTAssertTrue(tokens.contains("designed"))
        XCTAssertFalse(tokens.contains("design"))
        XCTAssertTrue(tokens.contains("fast"))
        XCTAssertTrue(tokens.contains("cheap"))
    }

    func testOverlapCountsSharedTokens() {
        let a = TextRelevance.tokenize("pricing runway investors")
        let b = TextRelevance.tokenize("runway investors margin")
        XCTAssertEqual(TextRelevance.overlap(a, b), 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/TextRelevanceTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: the test target fails to build — `cannot find 'TextRelevance' in scope`.

- [ ] **Step 3: Create `TextRelevance`**

Create `codepet/Models/TextRelevance.swift`:

```swift
// codepet/Models/TextRelevance.swift
import Foundation

/// Token-overlap relevance primitives, shared by chat grounding and department routing.
///
/// Extracted verbatim from `ChatContext`, which was its only user until `DepartmentRouter`
/// needed the same three things. The extraction is the point: two copies of a stopword list
/// is a trap where fixing one leaves the other wrong, silently, inside a grounding path
/// nobody looks at. `ChatContextTests` stands over this move — if the tokenizer changed
/// behaviour, prior-work selection changes with it and those tests go red.
enum TextRelevance {
    /// Words too common to carry signal for relevance matching (mirrors web STOPWORDS).
    static let stopwords: Set<String> = [
        "the", "and", "for", "our", "your", "their", "this", "that", "with", "from",
        "into", "about", "are", "was", "were", "will", "has", "have", "not", "you",
        "each", "per", "its", "via", "onto",
    ]

    /// Split text into lowercased, de-duped content tokens (≥3 chars, no stopwords).
    ///
    /// Splitting on `CharacterSet.alphanumerics.inverted` is what makes every match a WHOLE
    /// word: "designed" is the token `designed` and can never match `design`. That is the
    /// Aug 7 substring defect, closed by construction rather than by a guard.
    static func tokenize(_ s: String) -> Set<String> {
        var out: Set<String> = []
        for raw in s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) {
            if raw.count >= 3 && !stopwords.contains(raw) { out.insert(raw) }
        }
        return out
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Int {
        a.filter { b.contains($0) }.count
    }
}
```

- [ ] **Step 4: Point `ChatContext` at it**

In `codepet/Models/ChatContext.swift`, delete lines 15-21 (the `stopwords` comment and set) and lines 35-46 (the `tokenize` and `overlap` declarations). Leave every other constant — `scoreScanChars`, `titleWeight`, `bodyWeight`, `excerptCap`, `pinnedExcerptCap` — exactly where it is.

Then update the three call sites. Line 69:

```swift
        let queryTokens = TextRelevance.tokenize(q)
```

Lines 73-74:

```swift
            let titleScore = titleWeight * TextRelevance.overlap(queryTokens, TextRelevance.tokenize(item.title))
            let bodyScore = bodyWeight * TextRelevance.overlap(queryTokens, TextRelevance.tokenize(String(item.body.prefix(scoreScanChars))))
```

- [ ] **Step 5: Run both suites to verify they pass**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/TextRelevanceTests \
  -only-testing:codepetTests/ChatContextTests \
  -only-testing:codepetTests/ChatContextFocusTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: PASS, all three suites. `ChatContextTests` going red here means the move was not behaviour-preserving — fix the extraction, do not edit the test.

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/TextRelevance.swift codepet/Models/ChatContext.swift codepetTests/TextRelevanceTests.swift
git commit -F - <<'EOF'
refactor(chat): lift the tokenizer out of ChatContext

DepartmentRouter needs the same tokenize/overlap/stopwords that prior-work
selection uses. Two copies of a stopword list is a trap — fix one, the other
stays wrong, silently, in a grounding path. Pure move; ChatContextTests is the
proof it was clean.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 2: The `DepartmentTopics` vocabulary

Data plus three guard tests. No routing logic here.

**Files:**
- Create: `codepet/Models/DepartmentTopics.swift`
- Test: `codepetTests/DepartmentTopicsTests.swift`

**Interfaces:**
- Consumes: `TextRelevance.tokenize`, `TextRelevance.stopwords` (Task 1).
- Produces: `DepartmentTopics.Vocabulary` (a struct with `en: [String]` and `vi: [String]`), `DepartmentTopics.map: [String: Vocabulary]`, and `DepartmentTopics.terms(for deptKey: String, language: AppLanguage) -> [String]`. Task 4 calls `terms(for:language:)`.

An entry containing a space is a **phrase**, matched against raw text in Task 4. An entry without a space is a **token**, matched against `tokenize` output.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentTopicsTests.swift`:

```swift
import XCTest
@testable import codepet

/// The vocabulary is data, and these three tests are what stop it rotting into a source of
/// silent no-ops and stolen turns.
final class DepartmentTopicsTests: XCTestCase {

    /// A single-word entry shorter than 3 characters, or one that is a stopword, is DEAD:
    /// `TextRelevance.tokenize` drops it, so it can never match and nothing says so. This is
    /// why the lexicon has no "ux", "ui" or "ci".
    func testEverySingleWordEntrySurvivesTheTokenizer() {
        for (key, vocab) in DepartmentTopics.map {
            for term in vocab.en where !term.contains(" ") {
                XCTAssertGreaterThanOrEqual(term.count, 3,
                    "\(key): \"\(term)\" is under 3 chars — tokenize() drops it, so it can never match")
                XCTAssertFalse(TextRelevance.stopwords.contains(term),
                    "\(key): \"\(term)\" is a stopword — tokenize() drops it")
                XCTAssertEqual(term, term.lowercased(),
                    "\(key): \"\(term)\" must be lowercase — tokenize() lowercases before comparing")
            }
        }
    }

    /// Department NAMES belong to tier 1, which requires them to be ADDRESSED. Putting a name
    /// in a lexicon lets tier 2 fire on a bare mention and re-opens the Aug 10 regression from
    /// underneath — "we have support from two angel investors" summoning Sage · Support.
    func testNoEntryIsADepartmentName() {
        let names = Set(DepartmentCatalog.all.map { $0.name.lowercased() })
        for (key, vocab) in DepartmentTopics.map {
            for term in vocab.en {
                XCTAssertFalse(names.contains(term),
                    "\(key): \"\(term)\" is a department name — tier 1 owns that word")
            }
        }
    }

    /// Every key must resolve to a real department that HAS a pet. `product` is in the catalog
    /// to resolve a Virtual Company wire key and has no companion, so a lexicon for it would
    /// score a department that can never be suggested.
    func testEveryKeyIsAMappedDepartment() {
        for key in DepartmentTopics.map.keys {
            XCTAssertNotNil(DepartmentCatalog.find(key), "\(key) is not in the catalog")
            XCTAssertNotNil(DepartmentCompanions.companionId(for: key),
                            "\(key) has no companion — it can never be suggested")
        }
        XCTAssertNil(DepartmentTopics.map["product"], "product has no pet; see spec §2.5")
    }

    func testTermsForLanguageReturnsEnglishAndAnEmptyVietnamese() {
        XCTAssertFalse(DepartmentTopics.terms(for: "fin", language: .en).isEmpty)
        XCTAssertTrue(DepartmentTopics.terms(for: "fin", language: .vi).isEmpty,
                      "the vi table ships present and empty — spec §2.6")
        XCTAssertTrue(DepartmentTopics.terms(for: "product", language: .en).isEmpty)
    }

    /// The worked example in spec §4.4 depends on this exact word.
    func testFinanceKnowsInvestors() {
        XCTAssertTrue(DepartmentTopics.terms(for: "fin", language: .en).contains("investors"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentTopicsTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: build failure — `cannot find 'DepartmentTopics' in scope`.

- [ ] **Step 3: Write the vocabulary**

Create `codepet/Models/DepartmentTopics.swift`:

```swift
// codepet/Models/DepartmentTopics.swift
import Foundation

/// What each department's work SOUNDS like, so a pet can arrive before the founder names it.
///
/// Deliberately separate from `DepartmentCompanions`, which owns the department NAMES and
/// requires them to be addressed. That distinction is the whole safety model: tier 1 fires on
/// "ask finance", tier 2 fires on "runway", and neither can fire on the other's evidence.
///
/// **Nothing here may be a department name.** A name in a lexicon lets tier 2 fire on a bare
/// mention, which is the Aug 10 regression re-entering through the back door.
/// `DepartmentTopicsTests` enforces it.
///
/// **Single-word entries must be ≥3 characters, lowercase, and not stopwords**, because
/// `TextRelevance.tokenize` drops everything else — a shorter entry is dead on arrival and
/// nothing announces it. That is why "ux", "ui" and "ci" are absent despite being obvious
/// vocabulary. Multi-word entries are matched as phrases against the raw text instead and are
/// not subject to that floor.
///
/// `product` has no entry: it has no companion (`DepartmentCatalog.roster` filters it, and its
/// cover art is a byte-identical copy of Engineering's), so scoring it would rank a department
/// that can never be suggested.
enum DepartmentTopics {
    struct Vocabulary {
        let en: [String]
        /// Ships present and empty. Adding Vietnamese is then a data fill, not a refactor —
        /// spec §2.6. A Vietnamese founder sees today's behaviour, which is a no-op rather
        /// than a regression.
        let vi: [String]
    }

    static let map: [String: Vocabulary] = [
        "eng": Vocabulary(en: [
            "api", "backend", "frontend", "database", "schema", "endpoint", "refactor",
            "bug", "crash", "stacktrace", "deploy", "server", "repo", "codebase",
            "migration", "latency", "caching", "authentication", "test suite", "pull request",
        ], vi: []),
        "design": Vocabulary(en: [
            "layout", "typography", "font", "colour", "color", "palette", "spacing",
            "wireframe", "mockup", "icon", "logo", "branding", "visual", "screen",
            "contrast", "accessibility", "empty state", "first run", "onboarding flow",
        ], vi: []),
        "mkt": Vocabulary(en: [
            "launch", "campaign", "seo", "blog", "social", "newsletter", "audience",
            "positioning", "messaging", "brand", "press", "announcement", "growth",
            "landing page", "waitlist", "content calendar", "product hunt",
        ], vi: []),
        "sales": Vocabulary(en: [
            "lead", "leads", "prospect", "outreach", "demo", "deal", "quota", "discount",
            "conversion", "upsell", "cold email", "sales call", "free trial",
        ], vi: []),
        "support": Vocabulary(en: [
            "ticket", "complaint", "refund", "faq", "escalation", "churn",
            "bug report", "help doc", "response time", "user question",
        ], vi: []),
        "fin": Vocabulary(en: [
            "pricing", "price", "runway", "burn", "revenue", "mrr", "arr", "margin",
            "invoice", "invoicing", "budget", "forecast", "investor", "investors",
            "funding", "valuation", "subscription", "billing", "stripe",
            "cash flow", "burn rate", "unit economics",
        ], vi: []),
        "ops": Vocabulary(en: [
            "automation", "workflow", "process", "vendor", "hiring", "integration",
            "infrastructure", "monitoring", "backup", "uptime", "incident",
            "standard operating procedure",
        ], vi: []),
        "legal": Vocabulary(en: [
            "terms", "privacy", "gdpr", "compliance", "contract", "licence", "license",
            "licensing", "trademark", "copyright", "liability", "incorporation", "nda",
            "terms of service", "privacy policy", "data protection",
        ], vi: []),
    ]

    /// The vocabulary for one department in the active language. Empty for an unknown key,
    /// for `product`, and for every key in `.vi` until that table is filled.
    static func terms(for deptKey: String, language: AppLanguage) -> [String] {
        guard let vocab = map[deptKey] else { return [] }
        return language == .vi ? vocab.vi : vocab.en
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentTopicsTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/DepartmentTopics.swift codepetTests/DepartmentTopicsTests.swift
git commit -F - <<'EOF'
feat(routing): what each department's work sounds like

The vocabulary only. Three guard tests hold the rules that make it safe: no
entry may be a department name (tier 1 owns those, and a name here re-opens the
Aug 10 regression from underneath), every single-word entry must survive
tokenize() or it is dead on arrival, and every key must have a pet.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 3: `DepartmentRouter` — tier 1 and tier 4 only

Build the shell with the two tiers that need no scoring, so tier order is proven before scoring exists.

**Files:**
- Create: `codepet/Models/DepartmentRouter.swift`
- Test: `codepetTests/DepartmentRouterTests.swift`

**Interfaces:**
- Consumes: `DepartmentCompanions.mentionedDeptKey(in:)` (existing).
- Produces: `DepartmentRouter.Tier` (`.addressed`, `.topical`, `.carryOver`), `DepartmentRouter.Suggestion` (`deptKey: String`, `tier: Tier`, `matched: String?`), and
  `DepartmentRouter.suggest(text:tasks:lastActed:language:) -> Suggestion?`. Tasks 4, 5 and 7 all use this signature; it does not change again.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentRouterTests.swift`:

```swift
import XCTest
@testable import codepet

/// Tier order is the safety model. Tier 1 is today's behaviour, called unchanged and placed
/// above everything new — so every message that routes today routes the same way, and the new
/// tiers can only add answers where there were none.
final class DepartmentRouterTests: XCTestCase {

    func testAddressedWins() {
        let s = DepartmentRouter.suggest(text: "ask marketing about the launch",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "mkt")
        XCTAssertEqual(s?.tier, .addressed)
    }

    func testNothingToGoOnYieldsNoSuggestion() {
        XCTAssertNil(DepartmentRouter.suggest(text: "hello",
                                              tasks: [], lastActed: nil, language: .en))
    }

    func testEmptyDraftIsNeverPreArmed() {
        XCTAssertNil(DepartmentRouter.suggest(text: "",
                                              tasks: [], lastActed: nil, language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "   \n  ",
                                              tasks: [], lastActed: nil, language: .en))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentRouterTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: build failure — `cannot find 'DepartmentRouter' in scope`.

- [ ] **Step 3: Write the shell**

Create `codepet/Models/DepartmentRouter.swift`:

```swift
// codepet/Models/DepartmentRouter.swift
import Foundation

/// Which department a chat turn belongs to, and how sure we are.
///
/// **Why this is its own type.** Both recorded routing regressions came from one function
/// answering two questions at once, and `DepartmentCompanions` has already been split once for
/// exactly that reason — `actingSpecialist` → `actingDeptKey`, whose comment says the fusion
/// "cost the answer". *Who speaks*, *what they know*, and *how sure we are* are three
/// questions. This file owns the third and only the third: it returns a department key and
/// never resolves a pet. `DepartmentCompanions.specialistId(for:host:)` still decides whether
/// there is a handoff to show, which is why `host` is not a parameter here.
///
/// **Tier order is the safety model.** Tier 1 is `mentionedDeptKey`, unchanged and first, so
/// every message that routes today routes identically. The new tiers can only produce an
/// answer where there was none — never a different one.
enum DepartmentRouter {
    enum Tier: Equatable {
        /// The founder addressed a department by name — "ask finance". Today's behaviour.
        case addressed
        /// The founder's words match a department's vocabulary. New, and guarded (§4.3).
        case topical
        /// Nothing in this draft, but a department owns the conversation. New.
        case carryOver
    }

    struct Suggestion: Equatable {
        let deptKey: String
        let tier: Tier
        /// The term that fired, for the founder-facing "you mentioned …" hover. nil at tiers
        /// that matched on something other than a word. The view composes the sentence, so
        /// this stays a bare term and stays localizable.
        let matched: String?
    }

    /// The department to suggest, or nil to leave the turn with the host.
    ///
    /// Pure and deterministic: same inputs, same answer, no clock, no network, no state. That
    /// is what lets the two August regressions be held down by tests rather than by hope.
    static func suggest(text: String,
                        tasks: [RoadmapTask],
                        lastActed: String?,
                        language: AppLanguage) -> Suggestion? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Tier 1 — addressed by name. Today's rule, first, unchanged.
        if let key = DepartmentCompanions.mentionedDeptKey(in: trimmed) {
            return Suggestion(deptKey: key, tier: .addressed, matched: nil)
        }

        // Tier 4 — nothing to go on. Tiers 2 and 3 land between these in Tasks 4 and 5.
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentRouterTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/DepartmentRouter.swift codepetTests/DepartmentRouterTests.swift
git commit -F - <<'EOF'
feat(routing): the router shell, tier 1 first and unchanged

Tier order is the safety model, so it gets proven before any scoring exists.
mentionedDeptKey runs first and untouched; everything new lands beneath it and
can only add an answer where there was none.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Tier 2 — topical scoring, thresholds, and the three guards

The substance of the feature.

**Files:**
- Modify: `codepet/Models/DepartmentRouter.swift`
- Test: `codepetTests/DepartmentRouterTests.swift`

**Interfaces:**
- Consumes: `TextRelevance.tokenize`/`overlap` (Task 1), `DepartmentTopics.terms(for:language:)` (Task 2), `RoadmapTask.dept`/`.title` (existing, `dept` is `String?`).
- Produces: no signature change. `suggest` now returns `.topical` suggestions.

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/DepartmentRouterTests.swift`, inside the class:

```swift
    // MARK: - Tier 2: topical

    private func task(_ title: String, dept: String) -> RoadmapTask {
        // `TaskWho` is `does | draft | you` — there is no `.founder`.
        RoadmapTask(id: UUID().uuidString, title: title, detail: "",
                    phase: .build, who: .you, dept: dept)
    }

    func testTopicalRoutesWithoutNamingTheDepartment() {
        let s = DepartmentRouter.suggest(text: "how should I price the pro tier?",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertEqual(s?.tier, .topical)
        XCTAssertEqual(s?.matched, "price")
    }

    /// The floor. One weak token must not route a turn.
    func testASingleNonLexiconTokenYieldsNothing() {
        XCTAssertNil(DepartmentRouter.suggest(text: "can you look at this thing tomorrow",
                                              tasks: [], lastActed: nil, language: .en))
    }

    /// The margin, and the "near-ties stay with byte" decision. This sentence is genuinely
    /// two departments and byte is the honest answer.
    func testTwoDepartmentsWithinTheMarginYieldNothing() {
        let s = DepartmentRouter.suggest(
            text: "the landing page copy feels off and I'm not sure the price is right",
            tasks: [], lastActed: nil, language: .en)
        XCTAssertNil(s, "mkt and fin are within the margin; got \(String(describing: s))")
    }

    /// Guard 1 — the Aug 7 shape. A founder pasting a customer's words must not change who
    /// answers. DIRECT REGRESSION TEST.
    func testQuotedSpansDoNotVote() {
        let s = DepartmentRouter.suggest(
            text: "She said \"it emails me when something's off instead of a refund ticket\"",
            tasks: [], lastActed: nil, language: .en)
        XCTAssertNil(s, "words inside a quote are someone else's; got \(String(describing: s))")
    }

    func testBlockquotedLinesDoNotVote() {
        let s = DepartmentRouter.suggest(text: "what do you make of this\n> refund ticket faq",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertNil(s)
    }

    /// Guard 2 — whole words only, inherited from the tokenizer.
    func testSubstringsDoNotFire() {
        XCTAssertNil(DepartmentRouter.suggest(text: "the app is well designed",
                                              tasks: [], lastActed: nil, language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "our operational costs are high",
                                              tasks: [], lastActed: nil, language: .en))
    }

    /// Multi-word entries match against raw text, since tokenize() cannot see a phrase.
    func testPhrasesMatch() {
        let s = DepartmentRouter.suggest(text: "the landing page needs work",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "mkt")
        XCTAssertEqual(s?.matched, "landing page")
    }

    /// The founder's own roadmap is signal. Same sentence, different company, different answer.
    func testTasksBoostTheirDepartment() {
        let text = "can we make the checkout smoother"
        XCTAssertNil(DepartmentRouter.suggest(text: text, tasks: [],
                                              lastActed: nil, language: .en))
        let withWork = DepartmentRouter.suggest(
            text: text,
            tasks: [task("Redesign the checkout screen", dept: "design"),
                    task("Checkout empty state", dept: "design")],
            lastActed: nil, language: .en)
        XCTAssertEqual(withWork?.deptKey, "design")
        XCTAssertEqual(withWork?.tier, .topical)
    }

    /// Spec §4.4's third example — an approved behaviour CHANGE. Tier 1 still refuses to hand
    /// this to Support off the bare word "support"; tier 2 gives it to Finance, which is who
    /// should hold a sentence about investors.
    func testInvestorsSentenceGoesToFinanceNotSupport() {
        let s = DepartmentRouter.suggest(text: "we have support from two angel investors",
                                         tasks: [], lastActed: nil, language: .en)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertNil(DepartmentCompanions.mentionedDeptKey(in: "we have support from two angel investors"),
                     "tier 1 must still refuse this — the Aug 10 regression")
    }

    /// Vietnamese has no vocabulary yet, so tier 2 is silent rather than wrong.
    func testVietnameseYieldsNoTopicalSuggestion() {
        XCTAssertNil(DepartmentRouter.suggest(text: "định giá cho pro tier thế nào?",
                                              tasks: [], lastActed: nil, language: .vi))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentRouterTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -30
```

Expected: FAIL. The topical tests return nil because tier 2 does not exist yet.

- [ ] **Step 3: Implement tier 2**

In `codepet/Models/DepartmentRouter.swift`, add these members inside the enum, above `suggest`:

```swift
    // A lexicon hit is hand-curated, dense signal; a task-title hit is the founder's own
    // vocabulary and worth less on its own.
    private static let lexiconWeight = 3
    private static let taskWeight = 1
    // A department with many tasks must not win on volume alone.
    private static let taskScoreCap = 3
    /// One solid lexicon hit, minimum. A stray token cannot route a turn.
    private static let floor = 3
    /// The winner must beat the runner-up by this much. This is where "strongest wins,
    /// near-ties go to byte" lives: a genuinely two-department sentence fails here, and byte
    /// hosting an ambiguous question is the correct answer rather than a fallback.
    private static let margin = 2

    /// Remove text the founder did not write in their own voice.
    ///
    /// The Aug 7 regression was a pasted customer quote — *"emails me when something's off
    /// instead of using support"* — where one incidental word inside someone else's sentence
    /// changed who answered. Quoted spans and blockquoted lines do not vote.
    ///
    /// This catches the QUOTED shape only. An unquoted paste is defended by the floor and the
    /// margin and by nothing else; that is accepted because tier 2's failure mode is now a
    /// tentative chip the founder can see and dismiss before sending, not an answer already
    /// written in the wrong pet's name.
    static func stripQuoted(_ text: String) -> String {
        let unquoted = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
            .joined(separator: "\n")

        var out = ""
        var inQuote = false
        for ch in unquoted {
            if ch == "\"" || ch == "\u{201C}" || ch == "\u{201D}" {
                inQuote.toggle()
                continue
            }
            if !inQuote { out.append(ch) }
        }
        return out
    }

    /// Whole-phrase containment, the same discipline `DepartmentCompanions.isAddressed` uses:
    /// a phrase must not match inside a longer word.
    private static func contains(phrase: String, in text: String) -> Bool {
        var search = text.startIndex
        while let r = text.range(of: phrase, range: search..<text.endIndex) {
            defer { search = r.upperBound }
            let beforeOK = r.lowerBound == text.startIndex
                || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if beforeOK && afterOK { return true }
        }
        return false
    }

    /// Score one department, returning the total and the first term that fired.
    private static func score(deptKey: String,
                              tokens: Set<String>,
                              raw: String,
                              tasks: [RoadmapTask],
                              language: AppLanguage) -> (total: Int, matched: String?) {
        var hits = 0
        var matched: String?
        for term in DepartmentTopics.terms(for: deptKey, language: language) {
            let hit = term.contains(" ")
                ? contains(phrase: term, in: raw)
                : tokens.contains(term)
            if hit {
                hits += 1
                if matched == nil { matched = term }
            }
        }

        let titles = tasks.filter { $0.dept == deptKey }.map { $0.title }.joined(separator: " ")
        let taskScore = min(TextRelevance.overlap(tokens, TextRelevance.tokenize(titles)), taskScoreCap)

        return (lexiconWeight * hits + taskWeight * taskScore, matched)
    }
```

Then replace the tier 4 comment and `return nil` at the end of `suggest` with:

```swift
        // Tier 2 — topical. Scored on the founder's own words, with quoted text removed.
        let raw = stripQuoted(trimmed).lowercased()
        let tokens = TextRelevance.tokenize(raw)
        let ranked = DepartmentTopics.map.keys
            .map { (key: $0, result: score(deptKey: $0, tokens: tokens, raw: raw,
                                           tasks: tasks, language: language)) }
            // Sorted by score, then by key, so a tie is broken the same way every run —
            // a non-deterministic winner would make the margin check untestable.
            .sorted { $0.result.total != $1.result.total
                        ? $0.result.total > $1.result.total
                        : $0.key < $1.key }

        if let best = ranked.first, best.result.total >= floor {
            let runnerUp = ranked.dropFirst().first?.result.total ?? 0
            if best.result.total - runnerUp >= margin {
                return Suggestion(deptKey: best.key, tier: .topical, matched: best.result.matched)
            }
        }

        // Tier 4 — nothing to go on. Tier 3 lands above this in Task 5.
        return nil
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentRouterTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -30
```

Expected: PASS.

If `testTwoDepartmentsWithinTheMarginYieldNothing` fails, the two departments are further apart than the fixture assumed — adjust the **lexicon** so the sentence is a genuine tie, not the margin constant. The margin is the product decision; the vocabulary is the tunable.

- [ ] **Step 5: Verify tier 1's own suites are still green**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentCompanionsTests \
  -only-testing:codepetTests/DepartmentAddressingTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: PASS, unmodified. These are the canary for the whole spec — they exercise `mentionedDeptKey` directly, and tier 1 is unchanged. If either goes red, the tier order is wrong.

- [ ] **Step 6: Commit**

```bash
git add codepet/Models/DepartmentRouter.swift codepetTests/DepartmentRouterTests.swift
git commit -F - <<'EOF'
feat(routing): topical tier, with the guards the August burns paid for

Scores the founder's words against the department vocabulary and their own
dept-tagged tasks. A floor stops a stray token routing a turn; a margin sends
genuinely two-department sentences to byte. Quoted spans and blockquoted lines
do not vote — the Aug 7 paste is now a direct regression test.

Whole-word matching is inherited from the tokenizer rather than guarded, so the
Aug 7 substring defect cannot recur through this path at all.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Tier 3 — carry-over

**Files:**
- Modify: `codepet/Models/DepartmentRouter.swift`
- Test: `codepetTests/DepartmentRouterTests.swift`

**Interfaces:**
- Consumes: the `lastActed: String?` parameter already on `suggest` (Task 3).
- Produces: no signature change. `suggest` now returns `.carryOver` suggestions.

- [ ] **Step 1: Write the failing tests**

Append to `codepetTests/DepartmentRouterTests.swift`, inside the class:

```swift
    // MARK: - Tier 3: carry-over

    func testKeywordFreeFollowUpStaysWithTheLastDepartment() {
        let s = DepartmentRouter.suggest(text: "make it shorter",
                                         tasks: [], lastActed: "fin", language: .en)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertEqual(s?.tier, .carryOver)
        XCTAssertNil(s?.matched, "carry-over matched no word — the view says 'continuing with'")
    }

    func testAClearWinnerDisplacesCarryOver() {
        let s = DepartmentRouter.suggest(text: "the landing page needs work",
                                         tasks: [], lastActed: "fin", language: .en)
        XCTAssertEqual(s?.deptKey, "mkt")
        XCTAssertEqual(s?.tier, .topical)
    }

    func testAddressingDisplacesCarryOver() {
        let s = DepartmentRouter.suggest(text: "ask design about this",
                                         tasks: [], lastActed: "fin", language: .en)
        XCTAssertEqual(s?.deptKey, "design")
        XCTAssertEqual(s?.tier, .addressed)
    }

    func testNoLastActedMeansNoCarryOver() {
        XCTAssertNil(DepartmentRouter.suggest(text: "make it shorter",
                                              tasks: [], lastActed: nil, language: .en))
    }

    /// A department that lost its pet — or a stale key — must not be carried forward.
    func testCarryOverIgnoresAnUnroutableKey() {
        XCTAssertNil(DepartmentRouter.suggest(text: "make it shorter",
                                              tasks: [], lastActed: "product", language: .en))
        XCTAssertNil(DepartmentRouter.suggest(text: "make it shorter",
                                              tasks: [], lastActed: "nonsense", language: .en))
    }

    /// Carry-over is language-agnostic: it is memory, not vocabulary.
    func testCarryOverWorksInVietnamese() {
        let s = DepartmentRouter.suggest(text: "ngắn hơn được không",
                                         tasks: [], lastActed: "fin", language: .vi)
        XCTAssertEqual(s?.deptKey, "fin")
        XCTAssertEqual(s?.tier, .carryOver)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentRouterTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -30
```

Expected: FAIL on the carry-over tests — `suggest` returns nil where `.carryOver` is expected.

- [ ] **Step 3: Implement tier 3**

In `codepet/Models/DepartmentRouter.swift`, replace the final tier 4 block with:

```swift
        // Tier 3 — carry-over. Nothing in this draft, but a department owns the conversation.
        //
        // This is the narrow half of a rule that was deliberately removed once. The chip is
        // cleared on every send under "One message, one handoff" (CopilotChatView) because a
        // durable, silent selection had Nova answering pricing questions with nothing on
        // screen saying why. That bug had two halves — the pick was never re-derived, and
        // nothing displaced it. A suggestion is re-derived from the current draft every turn
        // and is displaced by any winner above, so only the useful half survives here. The
        // caller keeps explicit picks one-message-one-handoff.
        //
        // A key with no pet is not carried forward: it could never be suggested anyway, and
        // carrying it would keep a dead department "in charge" invisibly.
        if let lastActed, DepartmentCompanions.companionId(for: lastActed) != nil {
            return Suggestion(deptKey: lastActed, tier: .carryOver, matched: nil)
        }

        // Tier 4 — nothing to go on.
        return nil
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentRouterTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -30
```

Expected: PASS, all four tiers.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/DepartmentRouter.swift codepetTests/DepartmentRouterTests.swift
git commit -F - <<'EOF'
feat(routing): carry-over, the narrow half of a rule we removed once

A keyword-free follow-up stays with the department that answered last, so a pet
reads as a colleague rather than a per-message lottery. Only the useful half of
the old sticky chip survives: a suggestion is re-derived every turn and
displaced by any winner above it, which is the property the original lacked.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 6: The suggested chip in `ChatComposer`

**Files:**
- Create: `codepet/Models/DepartmentSuggestionLabel.swift`
- Modify: `codepet/Views/Copilot/ChatComposer.swift:59` (new properties), `:319-386` (`departmentControl`), `:402-413` (`deptRow`), and `ChatComposerPreviewHost` near `:795`
- Test: `codepetTests/DepartmentSuggestionLabelTests.swift`

**Interfaces:**
- Consumes: `DepartmentRouter.Tier` (Task 3), `DepartmentMenu.armedLabel/pet/rowTitle` (existing).
- Produces: on `ChatComposer` — `let suggestedDept: Department?`, `let suggestionTier: DepartmentRouter.Tier?`, `let suggestionMatched: String?`, `let onDismissSuggestion: () -> Void`. Task 7 supplies all four. Also `DepartmentSuggestionLabel.help(tier:matched:pet:department:lang:) -> String`.

The founder-facing sentence lives in its own pure type so it is assertable — a SwiftUI `.help()` string cannot be read from a test, the same reason `DepartmentMenu` exists.

- [ ] **Step 1: Write the failing test**

Create `codepetTests/DepartmentSuggestionLabelTests.swift`:

```swift
import XCTest
@testable import codepet

/// The hover sentence is what makes a wrong guess legible instead of spooky — the founder can
/// see it matched "support" in a sentence about investors and dismiss it knowing why. It lives
/// in a pure type because a SwiftUI `.help()` string cannot be asserted on, which is the same
/// reason `DepartmentMenu` exists.
final class DepartmentSuggestionLabelTests: XCTestCase {
    private let design = DepartmentCatalog.find("design")!

    func testTopicalNamesTheWordThatFired() {
        let s = DepartmentSuggestionLabel.help(tier: .topical, matched: "landing page",
                                               pet: "luna", department: design, lang: .en)
        XCTAssertTrue(s.contains("landing page"), s)
        XCTAssertTrue(s.lowercased().contains("mentioned"), s)
    }

    func testCarryOverSaysItIsContinuing() {
        let s = DepartmentSuggestionLabel.help(tier: .carryOver, matched: nil,
                                               pet: "luna", department: design, lang: .en)
        XCTAssertTrue(s.lowercased().contains("continuing"), s)
        XCTAssertTrue(s.contains("Design"), s)
    }

    /// A topical hit with no recorded term must not render "you mentioned ".
    func testTopicalWithoutATermFallsBackToTheDepartment() {
        let s = DepartmentSuggestionLabel.help(tier: .topical, matched: nil,
                                               pet: "luna", department: design, lang: .en)
        XCTAssertFalse(s.contains("mentioned \"\""), s)
        XCTAssertTrue(s.contains("Design"), s)
    }

    func testVietnameseIsTranslated() {
        let s = DepartmentSuggestionLabel.help(tier: .carryOver, matched: nil,
                                               pet: "luna", department: design, lang: .vi)
        XCTAssertFalse(s.lowercased().contains("continuing"), s)
        XCTAssertFalse(s.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentSuggestionLabelTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: build failure — `cannot find 'DepartmentSuggestionLabel' in scope`.

- [ ] **Step 3: Write the label type**

Create `codepet/Models/DepartmentSuggestionLabel.swift`:

```swift
// codepet/Models/DepartmentSuggestionLabel.swift
import Foundation

/// The hover sentence on a suggested department chip.
///
/// A guess the founder cannot interrogate is a guess they have to trust or fight. Naming the
/// word that fired turns a wrong suggestion into something obviously wrong-for-a-reason —
/// "you mentioned \"support\"" on a sentence about investors explains itself and gets
/// dismissed without alarm.
///
/// Its own type because a SwiftUI `.help()` string is unreachable from a test, exactly as
/// `DepartmentMenu` is its own type for the menu rows.
enum DepartmentSuggestionLabel {
    static func help(tier: DepartmentRouter.Tier,
                     matched: String?,
                     pet: String?,
                     department: Department,
                     lang: AppLanguage) -> String {
        let who = pet.flatMap { PetCharacter.all[$0]?.name }
            .map { "\($0) · \(department.name)" } ?? department.name

        switch tier {
        case .carryOver:
            return lang == .vi ? "Tiếp tục với \(who)" : "Continuing with \(who)"
        case .topical, .addressed:
            guard let matched, !matched.isEmpty else {
                return lang == .vi ? "Gợi ý — \(who)" : "Suggested — \(who)"
            }
            return lang == .vi
                ? "Gợi ý — bạn có nhắc “\(matched)”"
                : "Suggested — you mentioned “\(matched)”"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentSuggestionLabelTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: PASS.

- [ ] **Step 5: Add the four properties to `ChatComposer`**

In `codepet/Views/Copilot/ChatComposer.swift`, immediately after `@Binding var selectedDept: Department?` (line 59), add:

```swift
    /// The department the router guessed from the draft, rendered tentatively. Distinct from
    /// `selectedDept` on purpose: an explicit pick must never be silently overwritten, and a
    /// guess must never look like a choice. Shown only when `selectedDept == nil`.
    var suggestedDept: Department?
    var suggestionTier: DepartmentRouter.Tier?
    var suggestionMatched: String?
    /// The founder refusing the guess. Clears it for the current draft; the owner decides how
    /// long the refusal holds.
    var onDismissSuggestion: () -> Void = {}
```

Defaults on all four so no other call site of `ChatComposer` has to change.

- [ ] **Step 6: Render the suggested state**

In `departmentControl` (starting line 319), replace the first two lines of the function body:

```swift
        let host = companyStore.company.companionId
        let armed = selectedDept
```

with:

```swift
        let host = companyStore.company.companionId
        let armed = selectedDept
        // A guess only renders when the founder has not chosen. `shown` drives the label, the
        // sprite and the ✕; `armed` alone drives the SOLID treatment, so a suggestion and a
        // pick can never look alike.
        let suggested = armed == nil ? suggestedDept : nil
        let shown = armed ?? suggested
```

Then, within the same function, make these five substitutions:

1. The sprite condition — replace `if let dep = armed,` with `if let dep = shown,`
2. The label — replace
   ```swift
                    Text(armed.map { DepartmentMenu.armedLabel($0, host: host) }
                         ?? DepartmentMenu.restLabel(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(armed?.accent ?? CodepetTheme.bodyText)
   ```
   with
   ```swift
                    Text(shown.map { DepartmentMenu.armedLabel($0, host: host) }
                         ?? DepartmentMenu.restLabel(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        // Same string as a pick, dimmed. Accepting a suggestion must change
                        // nothing on screen except the chip firming up — a suggestion that
                        // read differently would look like a second feature.
                        .foregroundColor(shown == nil ? CodepetTheme.bodyText
                                         : (shown!.accent.opacity(armed == nil ? 0.75 : 1.0)))
   ```
3. The chevron and padding — replace `if armed == nil {` (the chevron) with `if shown == nil {`, and `.padding(.trailing, armed == nil ? 10 : 6)` with `.padding(.trailing, shown == nil ? 10 : 6)`

3b. **The menu rows must show the suggestion as checked**, or opening the menu over a suggested chip says "Anyone — byte routes it" while the chip names a pet. Replace the `Anyone` row's condition `if armed == nil {` with `if shown == nil {`, and the row call `Button { selectedDept = dep } label: { deptRow(dep, host: host) }` with:

   ```swift
                    Button { selectedDept = dep } label: { deptRow(dep, host: host, current: shown) }
   ```

   Then widen `deptRow` (line ~402) to take the effective department rather than reading the selection itself:

   ```swift
    @ViewBuilder private func deptRow(_ dep: Department, host: String,
                                      current: Department?) -> some View {
        let on = current?.key == dep.key
   ```

   Leave the rest of `deptRow` unchanged. Picking the already-checked suggested row is a normal pick: it writes `selectedDept`, which promotes the guess to a choice.
4. The `✕` button — replace
   ```swift
            if let dep = armed {
                Button { selectedDept = nil } label: {
   ```
   with
   ```swift
            if let dep = shown {
                Button {
                    if armed == nil { onDismissSuggestion() } else { selectedDept = nil }
                } label: {
   ```
5. The background, stroke and hover — replace the three trailing modifiers with:

```swift
        // The armed treatment is the retired chip's treatment, unchanged. The suggested
        // treatment is the same two values weakened, and a DASHED stroke — the one visual
        // difference, carrying the whole "not yet real" meaning.
        .background(Capsule().fill(shown.map { $0.accent.opacity(armed == nil ? 0.07 : 0.15) }
                                   ?? CodepetTheme.surface))
        .overlay(
            Capsule().strokeBorder(
                shown?.accent ?? CodepetTheme.hairline,
                style: armed == nil && suggested != nil
                    ? StrokeStyle(lineWidth: 1, dash: [3, 2])
                    : StrokeStyle(lineWidth: 1)
            )
        )
        .hoverAffordance(Capsule(), accent: shown?.accent ?? CodepetTheme.accentPurple)
        .help(suggested.map {
            DepartmentSuggestionLabel.help(tier: suggestionTier ?? .topical,
                                           matched: suggestionMatched,
                                           pet: DepartmentMenu.pet(for: $0, host: host),
                                           department: $0, lang: lang)
        } ?? "")
```

- [ ] **Step 7: Add a preview for the suggested state**

In `ChatComposerPreviewHost` (line ~795), add one property beside the existing `selected`:

```swift
    /// Supply a suggestion to see the DASHED chip — the state the founder sees before they
    /// have chosen anything.
    var suggested: Department? = nil
```

and pass three of the four new properties into its `ChatComposer(...)` call, immediately after `selectedDept: $dept,`:

```swift
            suggestedDept: suggested,
            suggestionTier: .topical,
            suggestionMatched: "layout",
```

`onDismissSuggestion` is left at its default — a preview has nothing to dismiss into.

Then add the preview at the end of the file, after `#Preview("ChatComposer (Marketing armed)")` and inside the `#if DEBUG` block:

```swift
/// Design SUGGESTED, not picked: dashed stroke, fill at 0.07, label at 0.75. Compare against
/// the armed preview above — same chip, same string, same sprite. That comparison is the whole
/// visual design, and it is the one thing green tests cannot check.
#Preview("ChatComposer (Design suggested)") {
    ChatComposerPreviewHost(suggested: DepartmentCatalog.find("design"))
}
```

- [ ] **Step 8: Build and run the composer-adjacent suites**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentSuggestionLabelTests \
  -only-testing:codepetTests/ComposerEdgeRenderTests \
  -only-testing:codepetTests/DepartmentHeaderLayoutTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: PASS. A compile error here is the likely failure, not an assertion.

- [ ] **Step 9: Commit**

```bash
git add codepet/Models/DepartmentSuggestionLabel.swift codepet/Views/Copilot/ChatComposer.swift codepetTests/DepartmentSuggestionLabelTests.swift
git commit -F - <<'EOF'
feat(composer): the suggested chip — same chip, weakened, dashed

The armed treatment unchanged at 0.15 + solid; the suggested treatment is the
same two values at 0.07 with a dashed stroke and a dimmed label. Same string
either way, so accepting a suggestion changes nothing on screen except the chip
firming up.

Hover names the word that fired. A guess the founder cannot interrogate is one
they have to trust or fight; "you mentioned 'support'" on a sentence about
investors explains itself and gets dismissed without alarm.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 7: Wire it into `CopilotChatView`

**Files:**
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` — `:46` (new `@State`), `:435-460` (composer call site), `:975-990` (send), plus three `.onChange` modifiers
- Test: none. See below.

**Interfaces:**
- Consumes: `DepartmentRouter.suggest(text:tasks:lastActed:language:)` (Tasks 3-5), the four new `ChatComposer` properties (Task 6).
- Produces: nothing further.

**This task has no unit test, and that is stated rather than papered over.**

Everything it adds is SwiftUI view state — `@State`, `.onChange`, and an edit inside `send()` — which XCTest cannot reach here. An earlier draft of this plan carried a test that asserted `(picked ?? suggested)?.key`; that tests Swift's `??` operator and would pass with the entire feature deleted, so it was removed. A green test that cannot fail makes the suite less trustworthy, and this repo has been burned before by checks that passed while verifying nothing.

Task 7's verification is therefore: **it compiles**, the **full suite stays green** (Task 8), and **Mona confirms the behaviour on screen** (Task 8 Step 5). Do not invent a test to close this gap — say it is uncovered.

- [ ] **Step 1: Add the view state**

In `codepet/Views/Copilot/CopilotChatView.swift`, immediately after `@State private var selectedDept: Department?` (line 46), add:

```swift
    /// The router's guess for the current draft, and the evidence behind it. Separate from
    /// `selectedDept` so an explicit pick is never silently overwritten (spec §3.4).
    @State private var suggestedDept: Department?
    @State private var suggestionTier: DepartmentRouter.Tier?
    @State private var suggestionMatched: String?
    /// The founder pressed ✕. Holds for the current draft only — refusing once must not mean
    /// re-refusing after every keystroke.
    @State private var suggestionDismissed = false
    /// Which department actually took the last turn, so a keyword-free follow-up can stay with
    /// it. Reset on thread switch; this is the ONLY sticky state, and `selectedDept` still
    /// clears on every send exactly as it does today.
    @State private var lastActedDeptKey: String?
```

- [ ] **Step 2: Recompute on every draft change**

Add a private method next to `armDepartment` (line 771):

```swift
    /// Re-derive the guess from the current draft. Cheap, pure, and called on every keystroke
    /// pause — there is no network and no persistence behind it.
    ///
    /// Suppressed in `.build`: that send does not read the department at all, so arming a chip
    /// there would promise a handoff that cannot happen.
    private func refreshSuggestion() {
        guard mode != .build, !suggestionDismissed else {
            suggestedDept = nil
            suggestionTier = nil
            suggestionMatched = nil
            return
        }
        let s = DepartmentRouter.suggest(text: companyStore.chatDraft,
                                         tasks: companyStore.company.tasks,
                                         lastActed: lastActedDeptKey,
                                         language: lang)
        suggestedDept = DepartmentCatalog.find(s?.deptKey)
        suggestionTier = s?.tier
        suggestionMatched = s?.matched
    }
```

Attach it to the same view the composer is rendered from — put these three modifiers next to the existing `.onChange` modifiers on the chat body:

```swift
        .onChange(of: companyStore.chatDraft) { _, _ in refreshSuggestion() }
        .onChange(of: mode) { _, _ in refreshSuggestion() }
        .onChange(of: companyStore.activeThreadId) { _, _ in
            // A new conversation owns nobody. Carry-over resets with the thread.
            lastActedDeptKey = nil
            suggestionDismissed = false
            refreshSuggestion()
        }
```

If the file's other `.onChange` uses the single-parameter form, match whichever form the surrounding code already uses rather than mixing the two.

- [ ] **Step 3: Pass the four properties to the composer**

At the `ChatComposer(...)` call site (line ~451), immediately after `selectedDept: $selectedDept,` add:

```swift
            suggestedDept: suggestedDept,
            suggestionTier: suggestionTier,
            suggestionMatched: suggestionMatched,
            onDismissSuggestion: {
                // An explicit refusal ends the conversation's ownership too — otherwise the
                // dismissed department returns as carry-over on the very next keystroke.
                suggestionDismissed = true
                lastActedDeptKey = nil
                suggestedDept = nil
                suggestionTier = nil
                suggestionMatched = nil
            },
```

- [ ] **Step 4: Resolve the department on send**

In `send()`, replace lines 986-987:

```swift
        let dept = selectedDept
        selectedDept = nil
```

with:

```swift
        // An explicit pick outranks a guess, always. `selectedDept` still clears on every
        // send — "one message, one handoff" is unchanged for a pick. Only the SUGGESTION
        // carries over, and only via `lastActedDeptKey`, which the router re-derives against
        // the next draft and any winner displaces (spec §5).
        let dept = selectedDept ?? suggestedDept
        selectedDept = nil
        suggestedDept = nil
        suggestionTier = nil
        suggestionMatched = nil
        suggestionDismissed = false
        if let dept { lastActedDeptKey = dept.key }
```

Leave the comment block above those lines in place — it explains why the pick is consumed and is still accurate.

- [ ] **Step 5: Build and run the chat suites**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/DepartmentRouterTests \
  -only-testing:codepetTests/ChatModeEngineeringTests \
  -only-testing:codepetTests/MessageTranscriptTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci 2>&1 | tail -20
```

Expected: PASS. A compile error at the composer call site is the likely failure.

- [ ] **Step 6: Commit**

```bash
git add codepet/Views/Copilot/CopilotChatView.swift
git commit -F - <<'EOF'
feat(chat): the guess reaches the composer, and the send honours it

Recomputed on every draft change, on mode change, and reset on thread switch.
Send resolves selectedDept ?? suggestedDept, so an explicit pick always wins and
is never silently overwritten.

selectedDept still clears on every send — "one message, one handoff" is
unchanged for a pick. Only the suggestion carries over, through
lastActedDeptKey, which is re-derived against the next draft and displaced by
any winner. A ✕ clears the carry-over too, or the dismissed department returns
on the next keystroke.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
```

---

### Task 8: Full suite, then a draft PR

`-only-testing:` runs have covered five suites out of roughly forty. A `-only-testing:` branch is an untested branch.

**Files:** none — verification only.

- [ ] **Step 1: Check for a running app — do NOT kill it**

```bash
ps -Ao pid,args | grep "[c]odepet.app" || echo "none running"
```

A live instance holds the Firestore lock and can kill the test host mid-run, with a different victim each time. But **never `pkill`**: on this machine the running instance is frequently a *concurrent session's* app from another worktree, and killing it knocks over someone else's work.

If an instance is running, read the path in its argv. If it is from **another worktree**, leave it alone and run the suite anyway — note in the report that a sibling instance was live, so a mid-run host death has a known cause. If it is from **this** worktree, ask Mona to quit it and wait; do not kill it yourself.

- [ ] **Step 2: Run the whole suite**

```bash
./scripts/ci-test.sh 2>&1 | tail -30
```

Expected: `All N test(s) passed.` — N around 1080. Read the script's own verdict, not the exit code: it distinguishes a real failure from the known `@MainActor` dealloc host crash, from a target that did not build, and from nothing having run.

If it reports `TARGET DID NOT BUILD`, that is a regression in the code. If it warns that the host died part way, whatever runs after the crash point was **not covered** — say so rather than reporting green.

- [ ] **Step 3: Confirm the canary suites specifically**

```bash
xcrun xcresulttool get test-results summary --path build/ci.xcresult \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['totalTestCount'], 'total /', d['failedTests'], 'failed')"
```

Expected: `0 failed`. `DepartmentCompanionsTests` and `DepartmentAddressingTests` must be green **and unmodified** — `git diff origin/main --stat -- codepetTests/DepartmentCompanionsTests.swift codepetTests/DepartmentAddressingTests.swift` must print nothing. They are the canary for the whole spec.

- [ ] **Step 4: Push and open a draft PR**

Pushing a branch runs **nothing** — CI triggers on pull requests only. A draft PR is what gets the suite executed.

```bash
git push -u origin feat/pet-topic-routing
gh pr create --draft --title "The right pet arrives before you name it" --body "$(cat <<'EOF'
Topical department routing. Today a pet only appears when the founder names its
department; `how do I price my product?` gets no specialist, and there is a
passing test asserting exactly that.

Adds a lower-confidence tier BENEATH `mentionedDeptKey` rather than loosening
it. Tier 1 runs first and unchanged, so every message that routes today routes
identically — `DepartmentCompanionsTests` and `DepartmentAddressingTests` are
green and unmodified, and they are the canary for this whole change.

The guess arms the composer chip tentatively (dashed, weakened); the founder
confirms by pressing Send. Nothing downstream of the send changes.

Spec: `docs/superpowers/specs/2026-08-24-pet-topic-routing-design.md`
Plan: `docs/superpowers/plans/2026-08-24-pet-topic-routing.md`

Two things reviewers should look at hardest:
- §5 — stickiness partially re-opens a door closed on purpose. Narrowed to the
  suggestion layer; explicit picks still clear on every send.
- §4.4 — "we have support from two angel investors" now routes to Finance. That
  is a deliberate, approved behaviour change on a sentence with history.

What is NOT covered, stated plainly:
- The view wiring (Task 7) has no unit test — it is `@State`, `.onChange` and a
  send-path edit, which XCTest cannot reach here. It compiles and the suite is
  green; that is not the same as verified.
- How the dashed chip actually looks on screen. Green tests are not a claim
  about that.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Hand the visual check to Mona**

Build and run signed, then ask **one** specific question. The visual treatment cannot be verified from here — green tests say the logic is right, not that the chip reads as tentative rather than broken.

```bash
xcodebuild -project CodePet.xcodeproj -scheme codepet -configuration Debug \
  -destination 'platform=macOS' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=YL72VTKBR7 CODE_SIGN_IDENTITY="Apple Development" build 2>&1 | tail -5
```

Then ask her to type `how should I price the pro tier?` without sending, and answer: **does the dashed chip read as a suggestion you could accept, or as a broken chip?**

---

## Verification checklist

- [ ] `./scripts/ci-test.sh` reports all tests passed
- [ ] `DepartmentCompanionsTests` and `DepartmentAddressingTests` green **and unmodified**
- [ ] `ChatContextTests` green and unmodified — proof the Task 1 extraction was behaviour-preserving
- [ ] Draft PR open, CI green on it
- [ ] Mona has seen the dashed chip and confirmed it reads as tentative
