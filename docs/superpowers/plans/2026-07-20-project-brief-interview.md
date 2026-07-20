# Project Brief Interview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the native macOS Codepet app a per-project founder-interview brief that is the source of truth, porting the web app's onboarding brief (structured `CompanyBrief`, `briefToContext` composer, `enrichBrief` enrichment) as faithfully as possible.

**Architecture:** A new Swift `CompanyBrief` model + pure `BriefContext` composer mirror the web types verbatim. A `ProjectInterviewView` (backed by a testable `ProjectInterviewModel`) collects the 6 web onboarding fields, submits them to a new `enrichBrief` Cloud Function (verbatim logic port) via a new `ReflectionAPIClient.enrichBrief` method, and persists the merged brief per-project in `ProjectStore`. The existing session-history `BriefSynthesizer` is demoted so it never overwrites an interviewed project.

**Tech Stack:** Swift/SwiftUI (macOS 13+, XcodeGen project), Firebase Auth + Firestore, Firebase Cloud Functions v2 (TypeScript, Anthropic SDK, Jest), spec source at `docs/superpowers/specs/2026-07-20-project-brief-interview-design.md`.

## Global Constraints

- **Two repos.** Swift app: work in the git worktree `~/Documents/codepet-brief-wt` (`My-Outcasts/codepet`), branch `feat/brief-interview` off `origin/main` — the COMPLETE source of truth (HEAD `a9655c7` "Promote current app as source of truth"). The local `~/Documents/codepet` checkout and `~/Downloads/codepet-main` are STALE partial exports (missing `Views/` + `CapturedEvent`) — do not use them. Functions: `~/Documents/Claude/CodePet-Clean/functions` (`Murror/CodePet-Clean`, deploys to Firebase project `devpet-8f4b1`), branch `feat/enrich-brief-fn` off `main`.
- **Functions repo is BEHIND the deployed backend.** It defines only `summarizeTurn`, `summarizeSession`, `chatSession`, but the live backend also serves `generatePlan`, `synthesizeBrief`, `generateGuidance`, `distillReference`. **NEVER run a blanket `firebase deploy`** from this checkout — it would delete the 4 undefined-here live functions. Deploy ONLY the new function: `firebase deploy --only functions:enrichBrief`. See Task 3 pre-flight.
- **Verbatim ports — preserve exact values.** Composer slice limits: `projectName` 120, `oneLiner` 240, `summary` 400, `notes` 800, `categories` 6, `audience` 160, `link` 200, `role` 80, `stage` 80, `founderName` 80. Enrichment clip limits: prompt `projectName` 120 / `oneLiner` 300 / `audience` 200 / `link` 200 / `notes` 2000; merge `summary` 400 / `audience` 200 / `categories` map-clip 40, slice 4. Founder-provided `audience`/`categories` always win over enrichment.
- **Fail-open everywhere.** Enrichment failure returns the raw brief unchanged (HTTP 200). Skipping the interview is always allowed and leaves the observed-synthesis path intact.
- **Swift conventions:** `Codable` models; UserDefaults keys prefixed `cp_`; new `ReflectionAPIClientProtocol` methods get a default-throw extension so existing mocks still compile; `Logger(subsystem: "app.murror.codepet", ...)`.
- **Out of scope / do not touch:** `decisions[]`, roadmap/scaffold generation, companion/theming, credits. Do NOT edit the stale `CLAUDE.md`.
- **Swift test command:** `cd ~/Documents/codepet-brief-wt && xcodebuild test -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/<TestClass> 2>&1 | tail -20`. Scheme is **`codepet`** (lowercase). Do NOT run `xcodegen` — the `.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup`, so new files under `codepet/` and `codepetTests/` are auto-included; adding a file needs no project regeneration.
- **Functions test command:** `cd ~/Documents/Claude/CodePet-Clean/functions && npm test -- <name>`.

---

## File Structure

**Swift app (worktree `~/Documents/codepet-brief-wt`):**
- Create `codepet/Models/CompanyBrief.swift` — structured brief (Task 1).
- Create `codepet/Models/BriefContext.swift` — pure composer (Task 2).
- Modify `codepet/Services/ReflectionAPIClient.swift` — DTOs, endpoint, method, protocol (Task 4).
- Modify `codepet/Models/Project.swift` + `codepet/Managers/ProjectStore.swift` — persist structured brief (Task 5).
- Modify `codepet/Managers/BriefSynthesizer.swift` — demotion guard (Task 6).
- Create `codepet/Views/Onboarding/ProjectInterviewModel.swift` + `ProjectInterviewView.swift` (Task 7).
- Create `codepet/Managers/InterviewCoordinator.swift`; modify `codepet/App/CodePetApp.swift` + `codepet/App/ContentView.swift` — presentation wiring (Task 8).
- Tests under `codepetTests/`.

**Functions (`~/Documents/Claude/CodePet-Clean/functions`):**
- Create `src/enrichBrief.ts` — logic + handler (Task 3).
- Modify `src/index.ts` — export the function (Task 3).
- Create `src/__tests__/enrichBrief.test.ts` (Task 3).

---

### Task 1: `CompanyBrief` model

**Files:**
- Create: `codepet/Models/CompanyBrief.swift`
- Test: `codepetTests/CompanyBriefTests.swift`

**Interfaces:**
- Produces: `struct CompanyBrief: Codable, Hashable, Equatable` with optional fields `founderName, role, tech, stage, projectName, oneLiner, summary, notes, link: String?`, `categories: [String]?`, `audience: String?`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/CompanyBriefTests.swift
import XCTest
@testable import CodePet

final class CompanyBriefTests: XCTestCase {
    func testRoundTripsThroughCodableWithOptionalFields() throws {
        let brief = CompanyBrief(
            founderName: "Mona", role: "Founder", projectName: "Codepet",
            oneLiner: "a recap tool", categories: ["macOS app"], audience: "developers"
        )
        let data = try JSONEncoder().encode(brief)
        let decoded = try JSONDecoder().decode(CompanyBrief.self, from: data)
        XCTAssertEqual(decoded, brief)
    }

    func testDecodesEmptyObjectToAllNils() throws {
        let decoded = try JSONDecoder().decode(CompanyBrief.self, from: Data("{}".utf8))
        XCTAssertNil(decoded.projectName)
        XCTAssertNil(decoded.categories)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/CompanyBriefTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'CompanyBrief' in scope`.

- [ ] **Step 3: Write the model**

```swift
// codepet/Models/CompanyBrief.swift
import Foundation

/// The founder's structured, self-described brief for a single project.
/// Verbatim port of the web app's `CompanyBrief` (lib/firebase/schema.ts). All
/// fields optional; a memberwise init lets call sites build partial briefs.
struct CompanyBrief: Codable, Hashable, Equatable {
    var founderName: String?
    var role: String?
    var tech: String?
    /// Free-text lifecycle stage from the onboarding slider (e.g. "Idea",
    /// "Building"). Distinct from `Project.stage` (the health-engine enum).
    var stage: String?
    var projectName: String?
    /// One-sentence description of the product (highest-signal field).
    var oneLiner: String?
    /// byte's enriched read of the product, when inputs were rich enough.
    var summary: String?
    /// Free-form details: pitch, README, PRD notes, anything pasted.
    var notes: String?
    /// Website / repo / Figma link.
    var link: String?
    /// Product categories (e.g. "Web app", "SaaS", "Dev tool").
    var categories: [String]?
    /// Who the product is for (target user / customer).
    var audience: String?

    init(founderName: String? = nil, role: String? = nil, tech: String? = nil,
         stage: String? = nil, projectName: String? = nil, oneLiner: String? = nil,
         summary: String? = nil, notes: String? = nil, link: String? = nil,
         categories: [String]? = nil, audience: String? = nil) {
        self.founderName = founderName; self.role = role; self.tech = tech
        self.stage = stage; self.projectName = projectName; self.oneLiner = oneLiner
        self.summary = summary; self.notes = notes; self.link = link
        self.categories = categories; self.audience = audience
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet
git add codepet/Models/CompanyBrief.swift codepetTests/CompanyBriefTests.swift
git commit -m "feat(brief): CompanyBrief model (verbatim port of web schema)"
```

---

### Task 2: `BriefContext` composer

**Files:**
- Create: `codepet/Models/BriefContext.swift`
- Test: `codepetTests/BriefContextTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief` (Task 1).
- Produces: `enum BriefContext { static func compose(_ brief: CompanyBrief?) -> String? }` — returns `nil` when there is no product signal.

- [ ] **Step 1: Write the failing test** (ports `lib/ai/brief.test.ts`)

```swift
// codepetTests/BriefContextTests.swift
import XCTest
@testable import CodePet

final class BriefContextTests: XCTestCase {
    func testReturnsNilWithoutProductSignal() {
        XCTAssertNil(BriefContext.compose(nil))
        XCTAssertNil(BriefContext.compose(CompanyBrief(role: "founder")))
    }

    func testUsesOneLinerAndNotesWhenNotEnriched() {
        let ctx = BriefContext.compose(CompanyBrief(
            projectName: "Codepet", oneLiner: "a recap tool", notes: "reads sessions")) ?? ""
        XCTAssertTrue(ctx.contains("a recap tool."))
        XCTAssertTrue(ctx.contains("reads sessions."))
    }

    func testSummaryReplacesOneLinerAndNotes() {
        let ctx = BriefContext.compose(CompanyBrief(
            projectName: "Codepet", oneLiner: "a recap tool",
            summary: "A local-first macOS companion that recaps coding sessions.",
            notes: "reads sessions and builds a dictionary")) ?? ""
        XCTAssertTrue(ctx.contains("A local-first macOS companion that recaps coding sessions."))
        XCTAssertFalse(ctx.contains("a recap tool."))
        XCTAssertFalse(ctx.contains("reads sessions and builds a dictionary"))
    }

    func testIncludesCategoriesAndAudienceAlongsideSummary() {
        let ctx = BriefContext.compose(CompanyBrief(
            projectName: "Codepet", summary: "A recap companion.",
            categories: ["macOS app", "dev tool"], audience: "AI-first developers")) ?? ""
        XCTAssertTrue(ctx.contains("macos app / dev tool"))
        XCTAssertTrue(ctx.contains("It's for AI-first developers."))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/BriefContextTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'BriefContext' in scope`.

- [ ] **Step 3: Write the composer** (verbatim logic port of `briefToContext`)

```swift
// codepet/Models/BriefContext.swift
import Foundation

/// Composes a `CompanyBrief` into a single plain-language paragraph the
/// companion writes from. Verbatim logic port of the web `briefToContext`
/// (lib/ai/brief.ts): same slice limits, same sentence assembly, and the same
/// contract of returning nil when there is no usable product signal.
enum BriefContext {
    static func compose(_ brief: CompanyBrief?) -> String? {
        guard let b = brief else { return nil }
        func str(_ v: String?, _ n: Int) -> String {
            guard let v = v else { return "" }
            return String(v.trimmingCharacters(in: .whitespacesAndNewlines).prefix(n))
        }
        let name = str(b.projectName, 120)
        let oneLiner = str(b.oneLiner, 240)
        let summary = str(b.summary, 400)
        let notes = str(b.notes, 800)
        let categories = Array((b.categories ?? []).prefix(6))
        let audience = str(b.audience, 160)
        let link = str(b.link, 200)
        if name.isEmpty && oneLiner.isEmpty && summary.isEmpty && notes.isEmpty { return nil }

        func dot(_ s: String) -> String { s.hasSuffix(".") ? s : s + "." }
        var parts: [String] = ["The company is \(name.isEmpty ? "the founder's product" : name)."]
        // byte's enriched summary is a distillation of the one-liner + notes, so
        // when it exists it REPLACES both (avoid repeating the description ~3x).
        if !summary.isEmpty {
            parts.append(dot(summary))
        } else if !oneLiner.isEmpty {
            parts.append(dot(oneLiner))
        }
        if !categories.isEmpty {
            parts.append("It is a \(categories.joined(separator: " / ").lowercased()) product.")
        }
        if !audience.isEmpty { parts.append("It's for \(audience).") }
        if !notes.isEmpty && summary.isEmpty { parts.append(dot(notes)) }
        if !link.isEmpty { parts.append("Reference: \(link).") }
        var who: [String] = []
        let role = str(b.role, 80)
        let stage = str(b.stage, 80)
        if !role.isEmpty { who.append("a \(role.lowercased())") }
        if !stage.isEmpty { who.append("at the \(stage.lowercased()) stage") }
        if !who.isEmpty { parts.append("The founder is \(who.joined(separator: ", ")).") }
        let founderName = str(b.founderName, 80)
        if !founderName.isEmpty { parts.append("Their name is \(founderName).") }
        return parts.joined(separator: " ")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet
git add codepet/Models/BriefContext.swift codepetTests/BriefContextTests.swift
git commit -m "feat(brief): BriefContext composer (verbatim port of briefToContext)"
```

---

### Task 3: `enrichBrief` Cloud Function

**Files (functions repo `~/Documents/Claude/CodePet-Clean`):**
- Create: `functions/src/enrichBrief.ts`
- Modify: `functions/src/index.ts` (add export)
- Test: `functions/src/__tests__/enrichBrief.test.ts`

**Interfaces:**
- Produces (HTTP): `POST /enrichBrief`, Bearer-auth, body `{ brief: CompanyBrief }` → `200 { brief: CompanyBrief }` (merged, or unchanged on no-signal / failure).
- Produces (pure, exported for tests): `hasEnrichableSignal(brief)`, `buildEnrichPrompt(brief)`, `mergeEnrichment(brief, e)`.

- [ ] **Step 1: Pre-flight — protect the deployed backend**

Create the branch and confirm this checkout is safe to deploy from **selectively only**:

```bash
cd ~/Documents/Claude/CodePet-Clean
git checkout -b feat/enrich-brief-fn
git fetch origin && git log --oneline -1 origin/main
grep -c "onRequest" functions/src/index.ts   # expect 3 before this task
```

If the printed commit is behind what you expect, or another source of truth for `generatePlan`/`synthesizeBrief` is found, STOP and confirm with the human which functions source is authoritative before deploying. Regardless: **only ever** `firebase deploy --only functions:enrichBrief` from here (Step 8).

- [ ] **Step 2: Write the failing test** (ports `lib/ai/enrichBrief.test.ts`)

```ts
// functions/src/__tests__/enrichBrief.test.ts
import { hasEnrichableSignal, buildEnrichPrompt, mergeEnrichment, BriefEnrichment } from "../enrichBrief";

describe("hasEnrichableSignal", () => {
  it("is true with a one-liner or notes, false without", () => {
    expect(hasEnrichableSignal({ oneLiner: "a companion" })).toBe(true);
    expect(hasEnrichableSignal({ notes: "pasted readme" })).toBe(true);
    expect(hasEnrichableSignal({ projectName: "Codepet", stage: "Private beta" })).toBe(false);
    expect(hasEnrichableSignal({ oneLiner: "   " })).toBe(false);
  });
});

describe("buildEnrichPrompt", () => {
  it("includes the founder inputs and forbids invention", () => {
    const p = buildEnrichPrompt({ projectName: "Codepet", oneLiner: "a macOS companion for founders", notes: "post-session recap" });
    expect(p).toContain("Codepet");
    expect(p).toContain("a macOS companion for founders");
    expect(p).toContain("post-session recap");
    expect(p).toContain("do not invent");
  });
  it("caps very long notes", () => {
    const p = buildEnrichPrompt({ projectName: "X", notes: "z".repeat(5000) });
    expect(p.length).toBeLessThan(3000);
  });
});

describe("mergeEnrichment", () => {
  const e: BriefEnrichment = { summary: "A macOS companion that recaps your coding sessions.", audience: "solo founders shipping with AI", categories: ["macOS app", "dev tool"] };
  it("fills gaps but never overrides the founder's own audience/categories", () => {
    const out = mergeEnrichment({ projectName: "Codepet", audience: "roommates", categories: ["SaaS"] }, e);
    expect(out.audience).toBe("roommates");
    expect(out.categories).toEqual(["SaaS"]);
    expect(out.summary).toBe("A macOS companion that recaps your coding sessions.");
  });
  it("fills audience + categories when the founder left them blank", () => {
    const out = mergeEnrichment({ projectName: "Codepet", oneLiner: "x" }, e);
    expect(out.audience).toBe("solo founders shipping with AI");
    expect(out.categories).toEqual(["macOS app", "dev tool"]);
  });
  it("caps categories at 4 and drops empties", () => {
    const out = mergeEnrichment({ projectName: "X" }, { summary: "s", audience: "", categories: ["a", "", "b", "c", "d", "e"] });
    expect(out.categories).toEqual(["a", "b", "c", "d"]);
  });
  it("keeps a prior summary when enrichment returns none", () => {
    const out = mergeEnrichment({ projectName: "X", summary: "existing" }, { summary: "", audience: "", categories: [] });
    expect(out.summary).toBe("existing");
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/Documents/Claude/CodePet-Clean/functions && npm test -- enrichBrief 2>&1 | tail -20`
Expected: FAIL — cannot find module `../enrichBrief`.

- [ ] **Step 4: Write the function** (verbatim logic port + tool-based structured call, matching the repo's Anthropic pattern in `summarizeTurn.ts`/`anthropic.ts`)

```ts
// functions/src/enrichBrief.ts
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL } from "./anthropic";

export interface CompanyBrief {
  founderName?: string; role?: string; tech?: string; stage?: string;
  projectName?: string; oneLiner?: string; summary?: string; notes?: string;
  link?: string; categories?: string[]; audience?: string;
}
export interface BriefEnrichment { summary: string; audience: string; categories: string[]; }

const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");

/** Only worth a model call when the founder gave something to read. */
export function hasEnrichableSignal(brief: CompanyBrief): boolean {
  return !!(brief.oneLiner?.trim() || brief.notes?.trim());
}

/** Ask the model to read the founder's inputs into a structured brief. */
export function buildEnrichPrompt(brief: CompanyBrief): string {
  const lines = [
    `Product name: ${clip(brief.projectName, 120) || "(unnamed)"}`,
    brief.oneLiner ? `Founder's one-liner: ${clip(brief.oneLiner, 300)}` : null,
    brief.categories?.length ? `Founder-picked categories: ${brief.categories.join(", ")}` : null,
    brief.audience ? `Founder-stated audience: ${clip(brief.audience, 200)}` : null,
    brief.link ? `Link: ${clip(brief.link, 200)}` : null,
    brief.notes ? `Founder's notes / pitch:\n${clip(brief.notes, 2000)}` : null,
  ].filter(Boolean);
  return (
    "Read what the founder told you about their product and produce a crisp structured read of it.\n\n" +
    lines.join("\n") +
    "\n\nProduce: a sharp 1-2 sentence summary of what it is and does; who it's for (audience); and 2-4 product categories. Ground EVERYTHING only in what the founder said — do not invent features, an audience, or a different product. If you genuinely can't infer a field, use an empty string / empty array rather than guessing."
  );
}

/** Fill gaps without overriding what the founder explicitly typed. */
export function mergeEnrichment(brief: CompanyBrief, e: BriefEnrichment): CompanyBrief {
  const summary = clip(e.summary, 400);
  const audience = clip(e.audience, 200);
  const cats = Array.isArray(e.categories)
    ? e.categories.map((c) => clip(c, 40)).filter(Boolean).slice(0, 4) : [];
  return {
    ...brief,
    summary: summary || brief.summary,
    audience: brief.audience?.trim() ? brief.audience : audience || brief.audience,
    categories: brief.categories?.length ? brief.categories : cats.length ? cats : brief.categories,
  };
}

const ENRICH_TOOL = {
  name: "record_brief",
  description: "Record the structured read of the founder's product.",
  input_schema: {
    type: "object",
    properties: {
      summary: { type: "string", description: "A sharp 1-2 sentence description of what the product is and does, in plain language — grounded ONLY in what the founder said." },
      audience: { type: "string", description: "Who the product is for, inferred from the founder's input. Empty string if you genuinely cannot tell." },
      categories: { type: "array", items: { type: "string" }, description: "2-4 short product categories. Empty array if unclear." },
    },
    required: ["summary", "audience", "categories"],
  },
} as const;

const ENRICH_SYSTEM =
  "You read a founder's raw notes about their product and distill them into a crisp, faithful structured summary. You never invent details the founder did not give you.";

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

/** Enrich a brief in place. Returns unchanged when already summarized or no signal. */
export async function enrich(brief: CompanyBrief): Promise<CompanyBrief> {
  if (brief.summary?.trim() || !hasEnrichableSignal(brief)) return brief;
  const response = await client().messages.create({
    model: MODEL,
    max_tokens: 1024,
    system: ENRICH_SYSTEM,
    tools: [ENRICH_TOOL as any],
    tool_choice: { type: "tool", name: "record_brief" },
    messages: [{ role: "user", content: buildEnrichPrompt(brief) }],
  });
  const block = response.content.find((b) => b.type === "tool_use") as any;
  if (!block) return brief;
  return mergeEnrichment(brief, block.input as BriefEnrichment);
}

export async function handleEnrichBrief(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) { res.status(401).json({ error: "invalid_token" }); return; }
  const brief = (req.body?.brief ?? null) as CompanyBrief | null;
  if (!brief || typeof brief !== "object") { res.status(400).json({ error: "invalid_payload", detail: "brief required" }); return; }
  // No signal (or already summarized) → return as-is without spending a call or the rate limit.
  if (brief.summary?.trim() || !hasEnrichableSignal(brief)) { res.status(200).json({ brief }); return; }
  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) { res.status(429).json({ error: "daily_limit_reached", reset_at: limit.resetAt.toISOString(), limit: limit.limit }); return; }
  try {
    res.status(200).json({ brief: await enrich(brief) });
  } catch (err) {
    logger.error("enrichBrief failed", { uid: auth.uid, err: String(err) });
    res.status(200).json({ brief }); // fail-open — client keeps the raw answers
  }
}
```

- [ ] **Step 5: Export the function**

Modify `functions/src/index.ts` — add the import next to the others and the export after `chatSession`:

```ts
import { handleEnrichBrief } from "./enrichBrief";
// ...
export const enrichBrief = onRequest(
  { cors: false, secrets: ["ANTHROPIC_API_KEY"] },
  handleEnrichBrief
);
```

- [ ] **Step 6: Run tests + typecheck**

Run: `cd ~/Documents/Claude/CodePet-Clean/functions && npm test -- enrichBrief 2>&1 | tail -20 && npx tsc --noEmit 2>&1 | tail -20`
Expected: Jest PASS (all describe blocks), `tsc` clean.

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/Claude/CodePet-Clean
git add functions/src/enrichBrief.ts functions/src/index.ts functions/src/__tests__/enrichBrief.test.ts
git commit -m "feat(functions): enrichBrief — verbatim logic port of web enrichBrief route"
```

- [ ] **Step 8: Deploy ONLY the new function** (never blanket-deploy — see Global Constraints)

Run: `cd ~/Documents/Claude/CodePet-Clean && firebase deploy --only functions:enrichBrief`
Expected: `enrichBrief` created at `https://us-central1-devpet-8f4b1.cloudfunctions.net/enrichBrief`; the 4 pre-existing live functions untouched. Verify with `firebase functions:list | grep -E "enrichBrief|generatePlan|synthesizeBrief"` (all still present).

---

### Task 4: `ReflectionAPIClient.enrichBrief` client method

**Files:**
- Modify: `codepet/Services/ReflectionAPIClient.swift`
- Test: `codepetTests/ReflectionAPIClientEnrichTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief` (Task 1); the deployed `enrichBrief` endpoint (Task 3).
- Produces: `func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief` on `ReflectionAPIClientProtocol` (default-throw extension) and on the concrete client; DTOs `EnrichBriefRequest`/`EnrichBriefResponse`.

- [ ] **Step 1: Write the failing test** (mocked `URLProtocol`, following the existing `ReflectionAPIClientTests` pattern)

```swift
// codepetTests/ReflectionAPIClientEnrichTests.swift
import XCTest
@testable import CodePet

final class ReflectionAPIClientEnrichTests: XCTestCase {
    func testEnrichBriefReturnsMergedBriefFromServer() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in
            let body = #"{"brief":{"projectName":"Codepet","summary":"A recap companion.","audience":"devs","categories":["macOS app"]}}"#
            return (200, Data(body.utf8))
        }
        let client = ReflectionAPIClient(session: URLSession(configuration: config)) { "test-token" }
        let out = try await client.enrichBrief(CompanyBrief(projectName: "Codepet", oneLiner: "a recap tool"))
        XCTAssertEqual(out.summary, "A recap companion.")
        XCTAssertEqual(out.categories, ["macOS app"])
    }

    func testEnrichBriefThrowsOnHTTPError() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in (429, Data(#"{"error":"daily_limit_reached"}"#.utf8)) }
        let client = ReflectionAPIClient(session: URLSession(configuration: config)) { "t" }
        do { _ = try await client.enrichBrief(CompanyBrief(oneLiner: "x")); XCTFail("expected throw") }
        catch { /* expected */ }
    }
}

/// Minimal URLProtocol stub (add once; skip if the test target already has one).
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

> If `codepetTests` already declares a `StubURLProtocol` (check `ReflectionAPIClientTests.swift`), reuse it and delete the duplicate class here.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ReflectionAPIClientEnrichTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'ReflectionAPIClient' has no member 'enrichBrief'`.

- [ ] **Step 3: Add DTOs, endpoint, protocol requirement, and method**

In `ReflectionAPIClient.swift`, add DTOs near the other request/response structs:

```swift
struct EnrichBriefRequest: Codable { let brief: CompanyBrief }
struct EnrichBriefResponse: Codable { let brief: CompanyBrief }
```

Add the endpoint constant alongside the existing `static let ...Endpoint` block:

```swift
private static let enrichBriefEndpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/enrichBrief")!
```

Add to the `ReflectionAPIClientProtocol` declaration and a default-throw extension (so existing mocks keep compiling — mirrors `fetchPlan`):

```swift
// in protocol ReflectionAPIClientProtocol { ... }
func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief

// in extension ReflectionAPIClientProtocol { ... }
func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief {
    throw ReflectionAPIError.malformedResponse
}
```

Add the concrete implementation next to `summarizeTurn` (same POST + Bearer shape):

```swift
func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief {
    let token = try await authTokenProvider()
    var urlRequest = URLRequest(url: Self.enrichBriefEndpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    urlRequest.httpBody = try JSONEncoder().encode(EnrichBriefRequest(brief: brief))

    let (data, response) = try await session.data(for: urlRequest)
    guard let http = response as? HTTPURLResponse else { throw ReflectionAPIError.malformedResponse }
    if http.statusCode == 200 {
        do { return try JSONDecoder().decode(EnrichBriefResponse.self, from: data).brief }
        catch { throw ReflectionAPIError.malformedResponse }
    }
    throw ReflectionAPIError.http(status: http.statusCode, body: nil)
}
```

> `ReflectionAPIError.http(status:body:)` takes a typed `SummarizeTurnError?` body; pass `nil` here (the enrich endpoint's error bodies aren't needed by callers).

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet
git add codepet/Services/ReflectionAPIClient.swift codepetTests/ReflectionAPIClientEnrichTests.swift
git commit -m "feat(brief): ReflectionAPIClient.enrichBrief client method"
```

---

### Task 5: Persist the structured brief in `ProjectStore`

**Files:**
- Modify: `codepet/Models/Project.swift` (add field)
- Modify: `codepet/Managers/ProjectStore.swift` (setter/getter)
- Test: `codepetTests/ProjectStoreBriefTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief` (Task 1), `BriefContext` (Task 2).
- Produces: `Project.companyBrief: CompanyBrief?`; `ProjectStore.setCompanyBrief(projectId:brief:)`; `ProjectStore.companyBrief(for:) -> CompanyBrief?`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/ProjectStoreBriefTests.swift
import XCTest
@testable import CodePet

@MainActor
final class ProjectStoreBriefTests: XCTestCase {
    private func storeWithProject(_ id: String) -> ProjectStore {
        let store = ProjectStore()
        store.upsertProject(path: id, firstSeen: Date())   // existing discovery entry point
        return store
    }

    func testSetCompanyBriefPersistsAndComposesStringAndMarksUserOwned() {
        let id = "/tmp/p1"
        let store = storeWithProject(id)
        store.setCompanyBrief(projectId: id, brief: CompanyBrief(projectName: "Codepet", oneLiner: "a recap tool"))
        XCTAssertEqual(store.companyBrief(for: id)?.projectName, "Codepet")
        XCTAssertTrue(store.brief(for: id).contains("a recap tool."))
        XCTAssertFalse(store.briefDescriptionIsSynthesisWritable(projectPath: id))
    }
}
```

> Use the real discovery entry point the store already exposes to insert a project. Confirm its name (e.g. `upsertProject`/`recordProject`/`observe`) by reading `ProjectStore.swift` and adjust the helper. If none is public, insert via the existing `updateBrief(projectId:brief:)` after discovery, or expose a test seam.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ProjectStoreBriefTests 2>&1 | tail -20`
Expected: FAIL — no member `setCompanyBrief` / `companyBrief`.

- [ ] **Step 3: Add the field + store methods**

In `codepet/Models/Project.swift`, add after `var brief: String`:

```swift
    /// Structured founder-interview brief (source of truth). When present, the
    /// flat `brief` string above is its composed render (see BriefContext).
    /// Optional + defaulted so projects persisted before this field decode cleanly.
    var companyBrief: CompanyBrief? = nil
```

In `codepet/Managers/ProjectStore.swift`, add near `updateBrief`/`brief(for:)`:

```swift
    /// Read the structured founder brief for a project path, if any.
    func companyBrief(for projectPath: String?) -> CompanyBrief? {
        guard let path = projectPath else { return nil }
        return projects[path]?.companyBrief
    }

    /// Set the structured founder brief. Recomposes the flat `brief` string and
    /// marks the project user-owned so from-history synthesis never overwrites it.
    func setCompanyBrief(projectId: String, brief: CompanyBrief) {
        guard var project = projects[projectId] else { return }
        project.companyBrief = brief
        if let composed = BriefContext.compose(brief) { project.brief = composed }
        projects[projectId] = project
        markBriefUserOwned(projectPath: projectId)   // persists markers
        persist()                                    // persists projects dict
        logger.info("Set founder brief for \(project.displayName)")
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet
git add codepet/Models/Project.swift codepet/Managers/ProjectStore.swift codepetTests/ProjectStoreBriefTests.swift
git commit -m "feat(brief): persist structured CompanyBrief per project"
```

---

### Task 6: Demote `BriefSynthesizer` for interviewed projects

**Files:**
- Modify: `codepet/Managers/BriefSynthesizer.swift`
- Test: `codepetTests/BriefSynthesizerDemotionTests.swift`

**Interfaces:**
- Consumes: `ProjectStore.companyBrief(for:)` (Task 5).
- Produces: no new API — an explicit guard so `backfill(...)` skips any project that has a `companyBrief`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/BriefSynthesizerDemotionTests.swift
import XCTest
@testable import CodePet

@MainActor
final class BriefSynthesizerDemotionTests: XCTestCase {
    func testBackfillSkipsProjectsWithAFounderBrief() {
        let api = NoCallAPIStub()   // fails the test if any endpoint is hit
        let synth = BriefSynthesizer(api: api, minSessions: 1)
        let store = ProjectStore()
        let id = "/tmp/interviewed"
        store.upsertProject(path: id, firstSeen: Date())
        store.setCompanyBrief(projectId: id, brief: CompanyBrief(projectName: "P", oneLiner: "x"))

        synth.backfill(sessions: [makeSummarizedSession(path: id)], projectStore: store, language: "en")
        XCTAssertFalse(api.wasCalled, "synthesizer must not run for an interviewed project")
    }
}
```

> `NoCallAPIStub` conforms to `ReflectionAPIClientProtocol` (all methods `XCTFail` + throw); `makeSummarizedSession` builds a `Session` with a non-nil `summary` at `path`. Model these on the existing `NarrativeStoreTests`/`BriefSynthesizer` test fixtures.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/BriefSynthesizerDemotionTests 2>&1 | tail -20`
Expected: FAIL — the synthesizer fires (`wasCalled == true`) because a summarized session with ≥minSessions triggers it.

- [ ] **Step 3: Add the guard**

In `BriefSynthesizer.backfill(...)`, inside the `for (path, entries)` loop, add this as the FIRST guard (before the existing `briefBackfillDone` check):

```swift
            // Interview brief is the source of truth — never synthesize over it.
            if projectStore.companyBrief(projectPath: path) != nil {
                projectStore.markBriefBackfilled(projectPath: path)
                continue
            }
```

> Use the getter name from Task 5 (`companyBrief(for:)`); the parameter label above assumes `companyBrief(for path:)` — match the actual signature.

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/codepet
git add codepet/Managers/BriefSynthesizer.swift codepetTests/BriefSynthesizerDemotionTests.swift
git commit -m "feat(brief): demote BriefSynthesizer over interviewed projects"
```

---

### Task 7: `ProjectInterviewModel` + `ProjectInterviewView`

**Files:**
- Create: `codepet/Views/Onboarding/ProjectInterviewModel.swift`
- Create: `codepet/Views/Onboarding/ProjectInterviewView.swift`
- Test: `codepetTests/ProjectInterviewModelTests.swift`

**Interfaces:**
- Consumes: `CompanyBrief` (1), `ReflectionAPIClientProtocol.enrichBrief` (4), `ProjectStore.setCompanyBrief` (5).
- Produces: `@MainActor final class ProjectInterviewModel: ObservableObject` with published fields `founderName, role, projectName, oneLiner, audience: String`, `stageIndex: Int`; `static let stages: [String]`; `static func shouldPrompt(for: Project) -> Bool`; `func buildBrief() -> CompanyBrief`; `func submit(projectId:store:api:) async -> Bool`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/ProjectInterviewModelTests.swift
import XCTest
@testable import CodePet

@MainActor
final class ProjectInterviewModelTests: XCTestCase {
    func testShouldPromptOnlyWhenNoFounderBrief() {
        var p = Project(id: "/tmp/x", displayName: "x", brief: "", firstSeenAt: Date(), lastSeenAt: Date())
        XCTAssertTrue(ProjectInterviewModel.shouldPrompt(for: p))
        p.companyBrief = CompanyBrief(projectName: "x")
        XCTAssertFalse(ProjectInterviewModel.shouldPrompt(for: p))
    }

    func testBuildBriefMapsFieldsIncludingStageLabel() {
        let m = ProjectInterviewModel()
        m.founderName = "Mona"; m.role = "Founder"; m.projectName = "Codepet"
        m.oneLiner = "a recap tool"; m.audience = "devs"; m.stageIndex = 1
        let b = m.buildBrief()
        XCTAssertEqual(b.founderName, "Mona")
        XCTAssertEqual(b.projectName, "Codepet")
        XCTAssertEqual(b.stage, ProjectInterviewModel.stages[1])
        XCTAssertEqual(b.oneLiner, "a recap tool")
    }

    func testSubmitEnrichesAndPersists() async {
        let m = ProjectInterviewModel()
        m.projectName = "Codepet"; m.oneLiner = "a recap tool"
        let store = ProjectStore(); store.upsertProject(path: "/tmp/x", firstSeen: Date())
        let api = EnrichStub(returning: CompanyBrief(projectName: "Codepet", summary: "Enriched.", oneLiner: "a recap tool"))
        let ok = await m.submit(projectId: "/tmp/x", store: store, api: api)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.companyBrief(for: "/tmp/x")?.summary, "Enriched.")
    }
}

/// Stub returning a fixed enriched brief. Conform to ReflectionAPIClientProtocol;
/// only enrichBrief is implemented (the rest use the protocol's default throw).
final class EnrichStub: ReflectionAPIClientProtocol {
    let out: CompanyBrief
    init(returning: CompanyBrief) { self.out = returning }
    func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief { out }
    func summarizeTurn(_ r: SummarizeTurnRequest) async throws -> SummarizeTurnResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeTurnStream(_ r: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> { .init { $0.finish() } }
    func summarizeSession(_ r: SummarizeSessionRequest) async throws -> SummarizeSessionResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeSessionStream(_ r: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> { .init { $0.finish() } }
    func chatSessionStream(_ r: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> { .init { $0.finish() } }
    func fetchGuidance(_ r: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse { throw ReflectionAPIError.malformedResponse }
    func synthesizeBrief(_ r: SynthesizeBriefRequest) async throws -> SynthesizeBriefResponse { throw ReflectionAPIError.malformedResponse }
}
```

> Match `EnrichStub`'s explicit methods to the exact non-defaulted requirements in `ReflectionAPIClientProtocol` (methods that already have default-throw extensions — `fetchPlan`, `fetchReferenceDistillation`, and now `enrichBrief` — need not be repeated). Trim to whatever the compiler actually requires.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/ProjectInterviewModelTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'ProjectInterviewModel' in scope`.

- [ ] **Step 3: Write the model**

```swift
// codepet/Views/Onboarding/ProjectInterviewModel.swift
import Foundation
import Combine

/// Drives the per-project founder interview. The 6 fields mirror the web
/// onboarding (components/Onboarding.tsx): name, role, product name, one-liner,
/// audience, stage. On submit it enriches via the server and persists the brief.
@MainActor
final class ProjectInterviewModel: ObservableObject {
    @Published var founderName = ""
    @Published var role = ""
    @Published var projectName = ""
    @Published var oneLiner = ""
    @Published var audience = ""
    @Published var stageIndex = 2
    @Published var isSubmitting = false

    /// Onboarding stage labels (mirror the web OB_STAGES ordering).
    static let stages = ["Idea", "Prototype", "Building", "Private beta", "Launched"]

    /// Prompt the interview only when the project has no founder brief yet.
    static func shouldPrompt(for project: Project) -> Bool { project.companyBrief == nil }

    /// Map the collected fields into a CompanyBrief (empty fields → nil).
    func buildBrief() -> CompanyBrief {
        func nz(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return CompanyBrief(
            founderName: nz(founderName), role: nz(role),
            stage: Self.stages[min(max(stageIndex, 0), Self.stages.count - 1)],
            projectName: nz(projectName), oneLiner: nz(oneLiner), audience: nz(audience)
        )
    }

    /// Enrich (fail-open) and persist. Returns true when a brief was stored.
    func submit(projectId: String, store: ProjectStore, api: ReflectionAPIClientProtocol) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        let raw = buildBrief()
        let enriched = (try? await api.enrichBrief(raw)) ?? raw   // fail-open
        store.setCompanyBrief(projectId: projectId, brief: enriched)
        return true
    }
}
```

- [ ] **Step 4: Write the view** (thin; drives the model)

```swift
// codepet/Views/Onboarding/ProjectInterviewView.swift
import SwiftUI

/// Per-project founder interview. Skippable and non-blocking; on finish it
/// enriches + persists via the model. Presented as a sheet (see Task 8).
struct ProjectInterviewView: View {
    let projectId: String
    let onDone: () -> Void
    @EnvironmentObject var projectStore: ProjectStore
    @StateObject private var model = ProjectInterviewModel()
    @State private var step = 0
    private let api: ReflectionAPIClientProtocol = ReflectionAPIClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case 0: field("First — what should I call you?", text: $model.founderName, placeholder: "e.g. Mona")
            case 1: field("Which best describes you?", text: $model.role, placeholder: "e.g. Founder")
            case 2: field("What's this project called?", text: $model.projectName, placeholder: "e.g. Codepet")
            case 3: field("In one line, what is it?", text: $model.oneLiner, placeholder: "e.g. a recap tool for founders")
            case 4: field("Who is it for?", text: $model.audience, placeholder: "e.g. solo founders shipping with AI")
            default:
                Text("What stage is it at?").font(.headline)
                Picker("Stage", selection: $model.stageIndex) {
                    ForEach(Array(ProjectInterviewModel.stages.enumerated()), id: \.offset) { i, s in Text(s).tag(i) }
                }.pickerStyle(.segmented)
            }
            HStack {
                Button("Skip") { onDone() }
                Spacer()
                if step < 5 {
                    Button("Next") { step += 1 }.disabled(false)
                } else {
                    Button(model.isSubmitting ? "Saving…" : "Finish") {
                        Task { _ = await model.submit(projectId: projectId, store: projectStore, api: api); onDone() }
                    }.disabled(model.isSubmitting)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: same as Step 2. Expected: PASS (3 model tests). The view compiles as part of the target build.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet
git add codepet/Views/Onboarding/ProjectInterviewModel.swift codepet/Views/Onboarding/ProjectInterviewView.swift codepetTests/ProjectInterviewModelTests.swift
git commit -m "feat(brief): project interview model + view (6-step founder interview)"
```

---

### Task 8: Presentation wiring (coordinator + sheet)

**Files:**
- Create: `codepet/Managers/InterviewCoordinator.swift`
- Modify: `codepet/App/CodePetApp.swift` (register coordinator env object)
- Modify: `codepet/App/ContentView.swift` (present sheet)
- Test: `codepetTests/InterviewCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ProjectInterviewModel.shouldPrompt(for:)` (7), `Project` (5).
- Produces: `@MainActor final class InterviewCoordinator: ObservableObject { @Published var active: Project?; func request(_ project: Project) }`.

- [ ] **Step 1: Write the failing test**

```swift
// codepetTests/InterviewCoordinatorTests.swift
import XCTest
@testable import CodePet

@MainActor
final class InterviewCoordinatorTests: XCTestCase {
    func testRequestActivatesOnlyWhenNoBrief() {
        let c = InterviewCoordinator()
        var p = Project(id: "/tmp/x", displayName: "x", brief: "", firstSeenAt: Date(), lastSeenAt: Date())
        c.request(p)
        XCTAssertEqual(c.active?.id, "/tmp/x")
        c.active = nil
        p.companyBrief = CompanyBrief(projectName: "x")
        c.request(p)
        XCTAssertNil(c.active, "should not prompt when a founder brief already exists")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/InterviewCoordinatorTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'InterviewCoordinator' in scope`.

- [ ] **Step 3: Write the coordinator**

```swift
// codepet/Managers/InterviewCoordinator.swift
import Foundation
import Combine

/// Owns which project (if any) is currently showing the founder interview.
/// A single, minimal presentation seam: call `request(_:)` from any surface
/// that wants to prompt an interview; ContentView presents the sheet.
@MainActor
final class InterviewCoordinator: ObservableObject {
    @Published var active: Project?

    /// Prompt the interview for a project, but only when it has no founder brief.
    func request(_ project: Project) {
        guard ProjectInterviewModel.shouldPrompt(for: project) else { return }
        active = project
    }
}
```

- [ ] **Step 4: Register + present**

In `codepet/App/CodePetApp.swift`, create the coordinator alongside the other `@StateObject`s and inject it into the root view's environment (mirror how `ProjectStore` is provided):

```swift
    @StateObject private var interviewCoordinator = InterviewCoordinator()
    // ... in the WindowGroup content:
    // .environmentObject(interviewCoordinator)
```

In `codepet/App/ContentView.swift`, add the env object and a sheet on the root `Group`:

```swift
    @EnvironmentObject var interviewCoordinator: InterviewCoordinator
    // ... attach to the outer Group (next to the existing .overlay/.animation modifiers):
    .sheet(item: $interviewCoordinator.active) { project in
        ProjectInterviewView(projectId: project.id) { interviewCoordinator.active = nil }
            .environmentObject(projectStore)
    }
```

> `Project` is already `Identifiable` (its `id` is the path), so `.sheet(item:)` works directly. Also add `.environmentObject(InterviewCoordinator())` to the `ContentView` `#Preview` so the preview compiles.

- [ ] **Step 5: Run test + full build to verify**

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:codepetTests/InterviewCoordinatorTests 2>&1 | tail -20`
Expected: PASS, and the app target builds (sheet wired).

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/codepet
git add codepet/Managers/InterviewCoordinator.swift codepet/App/CodePetApp.swift codepet/App/ContentView.swift codepetTests/InterviewCoordinatorTests.swift
git commit -m "feat(brief): present founder interview via InterviewCoordinator sheet"
```

> **Trigger policy (deliberately minimal, per YAGNI):** this task wires the *presentation* seam and one caller-agnostic entry (`InterviewCoordinator.request`). Which surfaces call `request(_:)` (e.g. auto-prompt on a project's first explicit focus, or a manual "Set up this project" affordance) is decided when the projects UI is mapped — likely alongside the roadmap sub-project. Do NOT auto-fire on background discovery (every `cd` into a repo would prompt).

---

## Final verification

After Task 8, run the full suite once:

Run: `cd ~/Documents/codepet && xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30`
Expected: all `codepetTests` pass, app builds clean.

Run: `cd ~/Documents/Claude/CodePet-Clean/functions && npm test 2>&1 | tail -20 && npx tsc --noEmit`
Expected: all Jest suites pass, `tsc` clean.

---

## Self-Review

**Spec coverage:** CompanyBrief model (Task 1 ✓), BriefContext composer (Task 2 ✓), enrichBrief function + verbatim schema/prompt/merge/gate (Task 3 ✓), client method (Task 4 ✓), ProjectStore persistence + composed-string + user-owned (Task 5 ✓), demoted synthesizer (Task 6 ✓), 6-step interview UI (Task 7 ✓), fail-open (Tasks 3/7 ✓), presentation trigger (Task 8 ✓). Out-of-scope (decisions[], scaffold, CLAUDE.md) untouched ✓.

**Type consistency:** `CompanyBrief` fields identical across model, DTO, function interface, and composer. `setCompanyBrief(projectId:brief:)` / `companyBrief(for:)` used consistently in Tasks 5–8. `shouldPrompt(for:)` defined in Task 7, used in Task 8. `ReflectionAPIClientProtocol.enrichBrief` added with default-throw in Task 4, relied on by Tasks 7–8 stubs.

**Known verification gaps for the implementer (resolve while implementing, not blockers):** (a) confirm `ProjectStore`'s real project-insertion API name for test setup (Task 5 note); (b) confirm/reuse an existing `StubURLProtocol` in `codepetTests` (Task 4 note); (c) trim protocol-stub methods to the compiler's actual non-defaulted set (Task 7 note); (d) new files under `codepet/`/`codepetTests/` are auto-included by the project's `PBXFileSystemSynchronizedRootGroup` — no `xcodegen`/project edit needed; there is already an `OnboardingFlow.swift` in `codepet/Views/Onboarding/`, so keep the new `ProjectInterviewView`/`ProjectInterviewModel` names distinct.
