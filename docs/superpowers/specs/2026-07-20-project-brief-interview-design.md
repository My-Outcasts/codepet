# Project Brief Interview — Design Spec

**Date:** 2026-07-20
**Sub-project:** 1 of 8 in the "clone the web app → native Swift" port (build order: **brief** → companion → roadmap → chat → deliverables → toolkit → memory → billing).
**Goal:** Give the native macOS Codepet app a **founder-interview project brief** that is the source of truth, mirroring the web app's onboarding brief as closely as possible.

---

## Context: why this exists

The two Codepet products have diverged:

- **Web app** (`~/Desktop/Codepet v1.2`, Next.js on Vercel): the founder captures a project **brief** through a 6-step onboarding **interview**; byte **enriches** it; everything downstream (roadmap, chat, deliverables) reads it. One company per account.
- **Swift app** (`~/Documents/codepet`, `My-Outcasts/codepet`, macOS/SwiftUI): a menu-bar app that **watches Claude Code sessions** and *infers* a brief from session history (`BriefSynthesizer`). No interview. Multi-project (projects auto-discovered from session paths); each `Project` has a flat `brief: String`.

This sub-project ports the web app's **interview-driven brief** into the Swift app. Approved decisions from brainstorming:

1. **Generation backend:** port web AI logic to **new Firebase Cloud Functions** next to the existing ones (the Swift app already calls `devpet-8f4b1.cloudfunctions.net`).
2. **Brief model:** the **interview is the source of truth**; session-history synthesis demotes to a keep-fresh updater that never touches interview fields.
3. **Where it lands (multi-project):** **Approach A — per-project interview.** Each project *is* a "company"; the web `CompanyBrief` type ports verbatim, one per project.
4. **Fidelity mandate:** keep everything as close to the web version as possible; the per-project framing is the *only* intentional divergence.

## Scope

**In scope:**
- A structured `CompanyBrief` Swift model (verbatim port of the web type).
- A per-project 6-step interview UI (mirrors `components/Onboarding.tsx` steps).
- A `briefToContext` port (`BriefContext.swift`) composing the struct → context paragraph.
- A new `enrichBrief` Cloud Function (verbatim port of `lib/ai/enrichBrief.ts` logic) + a `ReflectionAPIClient.enrichBrief(...)` client method.
- Persistence of the structured brief (local via `ProjectStore` + cloud via `CloudSyncService`), and demoting `BriefSynthesizer` to changelog-only for interviewed projects.

**Out of scope (own later sub-projects, noted so consumers know where they land):**
- Roadmap / scaffold generation (web onboarding **step 6**). On the web, enrichment runs *inside* `/api/scaffold`; here `enrichBrief` is lifted out to run at interview submit so the brief is complete before scaffold exists. When the roadmap sub-project is built, enrichment slots back into the scaffold moment.
- Companion selection / voice / accent theming.
- Locked `decisions[]` (memory sub-project).
- Deliverables, credits/billing.

**Explicit non-goals / cleanup deferred:**
- The Swift repo's `CLAUDE.md` is **stale** (describes an old tab-based learn-to-code game that no longer exists in code). Leave it untouched this sub-project; track as separate cleanup.

## Repositories (this sub-project spans two)

| Change | Repo | Path |
|---|---|---|
| Swift model / UI / client / persistence | `My-Outcasts/codepet` | `~/Documents/codepet` |
| `enrichBrief` Cloud Function | `Murror/CodePet-Clean` (deploys to `devpet-8f4b1`) | `~/Documents/Claude/CodePet-Clean/functions` |

Branch off each repo's default (`main`) for this work.

---

## Architecture

```
[ProjectInterviewView] --answers--> [CompanyBrief (raw)]
        |                                   |
        |                         ReflectionAPIClient.enrichBrief
        |                                   v
        |                         [enrichBrief Cloud Function]  (devpet-8f4b1)
        |                                   |  {summary, audience, categories}
        |                            mergeEnrichment (fail-open)
        v                                   v
   ProjectStore.setBrief(projectPath, CompanyBrief)  --> UserDefaults + CloudSyncService (Firestore users/{uid})
        |
        v
   BriefContext.compose(brief)  -->  Project.brief : String   (unchanged consumers keep working)
        |
   BriefSynthesizer (demoted): appends changelog only; NEVER writes interview fields
```

## Components

### 1. `CompanyBrief` (Model — new)
Verbatim port of the web `CompanyBrief` (`lib/firebase/schema.ts`). `Codable`, all fields optional:

```
founderName?: String
role?: String
tech?: String
stage?: String
projectName?: String
oneLiner?: String     // highest-signal founder field
summary?: String      // byte's enriched read (from enrichBrief)
notes?: String        // free-form: pitch / README / PRD
link?: String
categories?: [String]
audience?: String
```

Founder fields (`founderName`, `role`, `tech`) live in the same brief exactly as on the web; the UI merely **prefills** them from the most recent interview as a convenience. No account-level/project-level structural split.

### 2. `BriefContext` (pure composer — new)
Verbatim logic port of `briefToContext` (`lib/ai/brief.ts`). Same slice limits and same sentence assembly:

- Limits: `projectName` 120, `oneLiner` 240, `summary` 400, `notes` 800, `categories` 6, `audience` 160, `link` 200, `role` 80, `stage` 80, `founderName` 80.
- Returns `nil` when there is no usable signal (no name / oneLiner / summary / notes) so callers fall back to a baseline.
- `summary`, when present, **replaces** oneLiner + notes (avoids repeating the product description). Categories → "It is a X / Y product." Audience → "It's for …". Founder → "The founder is a {role}, at the {stage} stage." Name → "Their name is …".

Output feeds `Project.brief: String` so all existing consumers are unchanged.

### 3. `ProjectInterviewView` (SwiftUI — new)
Mirrors `components/Onboarding.tsx` steps, per project, in order:
1. `founderName` — "First — what should I call you?" (prefilled if known)
2. `role` — "Which best describes you?"
3. `projectName`
4. `oneLiner`
5. `audience`
6. `stage` — slider over the web `OB_STAGES` set

Behavior mirrors web: **skippable / deferrable** and non-blocking. Skipping falls back to today's observed synthesis. On submit → call `enrichBrief` → merge → persist.

### 4. `enrichBrief` Cloud Function (new — `Murror/CodePet-Clean/functions`)
Verbatim logic port of `lib/ai/enrichBrief.ts`, added to `functions/src` and exported from `index.ts` via `onRequest(...)`, following the existing function pattern (Bearer-token auth via `auth.ts`, Anthropic via `anthropic.ts`, `cache.ts`, `rateLimit.ts`).

Ported pieces (values preserved exactly):
- **`ENRICH_SCHEMA`** — object requiring `summary` (string), `audience` (string), `categories` (array of string), `additionalProperties:false`, with the same field descriptions.
- **`hasEnrichableSignal(brief)`** — only worth a model call when `oneLiner || notes` is non-empty.
- **`buildEnrichPrompt(brief)`** — same prompt text: lists product name / one-liner / categories / audience / link / notes (with the same clip limits: projectName 120, oneLiner 300, audience 200, link 200, notes 2000), and the same "Ground EVERYTHING only in what the founder said … use empty string / empty array rather than guessing" instruction.
- **`mergeEnrichment(brief, e)`** — clips (summary 400, audience 200, categories: map clip 40 / filter / slice 4); **founder-provided `audience`/`categories` win**, byte only fills gaps and always adds `summary`.

Request: `{ brief: CompanyBrief }` (Bearer ID token). Response: enriched `CompanyBrief` (or the raw brief on model failure — fail-open).

### 5. `ReflectionAPIClient.enrichBrief(...)` (client — new)
New endpoint constant `…/enrichBrief` and a method mirroring existing ones (POST, `Authorization: Bearer <token>`, `application/json`, `CompanyBrief` in/out). Same error enum shape as existing endpoints.

### 6. `ProjectStore` (extended) + persistence
- Store/read the structured `CompanyBrief` per `projectPath` (new keyed store, mirroring the existing brief-string keying), persisted to UserDefaults and synced via `CloudSyncService` (Firestore `users/{uid}`), matching current patterns.
- Reuse/extend the existing ownership markers (`markBriefUserOwned`, `briefDescriptionIsSynthesisWritable`, `markBriefBackfilled`) so an interviewed project's brief is treated as user-owned.

### 7. `BriefSynthesizer` (demoted)
For projects that have an interview brief: the synthesizer may **append to the changelog only** and must **never overwrite interview fields**. The existing `briefDescriptionIsSynthesisWritable` gate already protects user-owned briefs; extend it to treat any interview-sourced `CompanyBrief` as user-owned. No elaborate merge — this keeps us close to the web app, which has no synthesizer at all.

## Data flow

1. Project first opened with no `CompanyBrief` → `ProjectInterviewView` presented (non-blocking).
2. User answers (or skips → fall back to observed synthesis, done).
3. On submit, if `hasEnrichableSignal` → `ReflectionAPIClient.enrichBrief` → `enrichBrief` function → `mergeEnrichment`.
4. Resulting `CompanyBrief` persisted (UserDefaults + Firestore), marked user-owned.
5. `BriefContext.compose` renders `Project.brief: String`; downstream sub-projects read either the struct or the composed string.
6. Later sessions: `BriefSynthesizer` appends changelog only.

## Error handling

- `enrichBrief` failure is **fail-open** (matches the web app): keep the raw interview answers, skip enrichment, no blocking error — the brief is still usable.
- Persistence failure keeps the in-memory brief and retries quietly (mirror existing `ProjectStore`/`CloudSyncService` behavior); never a dead end.
- Skipping the interview is always allowed and leaves the observed-synthesis path intact.

## Testing

Swift unit tests (mirroring the web tests, matching the repo's existing test culture):
- `BriefContextTests` — port of `lib/ai/brief.test.ts` cases (nil on no-signal; summary replaces oneLiner+notes; categories/audience/founder/link composition; slice limits).
- `EnrichmentMergeTests` — port of `lib/ai/enrichBrief.test.ts` (founder audience/categories win; summary always applied; clip/slice limits; `hasEnrichableSignal` gate).
- `BriefOwnershipTests` — interview brief is user-owned; `BriefSynthesizer` cannot overwrite interview fields.

Cloud Function tests (mirroring `functions/src/__tests__`):
- `enrichBrief` — schema-valid output, prompt grounding, fail-open on model error, auth required.

## Verbatim-port references (source → target)

| Web source | Swift/Function target |
|---|---|
| `lib/firebase/schema.ts` `CompanyBrief` | `CompanyBrief` model |
| `lib/ai/brief.ts` `briefToContext` | `BriefContext.compose` |
| `lib/ai/enrichBrief.ts` (`ENRICH_SCHEMA`, `hasEnrichableSignal`, `buildEnrichPrompt`, `mergeEnrichment`) | `enrichBrief` Cloud Function |
| `lib/firebase/serverBrief.ts` (PATCH `updateMask=brief`, fail-open) | `ProjectStore` persistence pattern |
| `components/Onboarding.tsx` (6 steps) | `ProjectInterviewView` |

## Open decisions

None — all resolved in brainstorming. Ready for implementation planning.
