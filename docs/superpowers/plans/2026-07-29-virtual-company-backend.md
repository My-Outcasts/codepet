# Virtual Company Multi-Agent Backend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend for the Virtual Company feature — 4 LLM agents that independently analyse a founder's request, surface where they disagree, negotiate, and emit a decision brief over SSE.

**Architecture:** Orchestrator–Worker over a Firestore-persisted Blackboard, exposed as a single streaming Cloud Function (`virtualCompanyRun`). Six phases: intake/route → independent parallel pass (mutually blind) → conflict detection (pure code, no LLM) → bounded negotiation → synthesis → stream. Every LLM call goes through the existing `functions/` proxy so the Anthropic key never reaches the client.

**Tech Stack:** Firebase Functions v2 (Node 22, TypeScript strict), `@anthropic-ai/sdk`, Firestore, Jest + ts-jest.

**Source spec:** `codepet-multi-agent-prompt-en.md` (repo root). Read PART 2 (orchestration), PART 3 (agent prompts), PART 5 (technical architecture) before starting.

## Global Constraints

- **Scope is backend + logic only.** UI is owned by another engineer. Do **not** create or modify anything under `codepet/Views/`. Do **not** modify `codepet/Models/Department.swift` or `codepet/Managers/CompanyStore.swift` — surface what the client needs through the SSE contract instead. The final deliverable of this plan is a documented SSE contract, not a screen.
- **MVP roster is exactly 4 agents:** `chief_of_staff`, `devils_advocate`, `product`, `finance`. Do not add `engineering`, `design`, `gtm`, or any Tier 2 agent. Only `product` and `finance` are department agents that produce positions in Phase 2.
- **The API key never leaves the backend.** Every Anthropic call is made inside `functions/`. Declare `secrets: ["ANTHROPIC_API_KEY"]` on the function.
- **Model IDs — use these exact strings, no date suffixes:** `claude-opus-5`, `claude-sonnet-5`, `claude-haiku-4-5`.
- **Agent system prompts stay in English** regardless of founder language (spec language note). Only the founder-facing output language is controlled by `{{OUTPUT_LANGUAGE}}`.
- **Conflict detection contains zero LLM calls.** It is pure, synchronous, deterministic TypeScript (spec §2.2 Phase 3).
- **No agent may see another agent's output during Phase 2** (spec §2.2 Phase 2). This is the single most important invariant in the system.
- **`unresolved` is a valid, successful outcome.** Never manufacture consensus. Never let a budget breach silently truncate — return a partial result with a stated reason.
- **Negotiation is hard-capped at 2 rounds.** The cap is a module constant, not a request parameter.
- Follow existing `functions/src/` conventions: one `handleXxx(req, res)` per feature file wired in `index.ts`; a `validateXxxPayload(body): string | null` validator; pure exported helpers for unit testing; injectable factories (`__setXxxForTests`) instead of network mocks.
- `tsconfig.json` has `strict` and `noUnusedLocals`. Unused imports fail the build.
- Run `cd functions && npx tsc --noEmit` and `npx jest` before every commit.

---

## File Structure

All new files live under `functions/src/company/`.

| File | Responsibility |
|---|---|
| `company/types.ts` | Every shared type: `AgentId`, `Stance`, `AgentPosition`, `Conflict`, `RoutingDecision`, `NegotiationRound`, `DecisionBrief`, `Blackboard`, `TokenUsage`. No logic. |
| `company/preamble.ts` | `SHARED_PREAMBLE` (spec §3.1) + `buildSharedPrefix()` — the byte-identical cacheable prefix for every agent in a run. |
| `company/registry.ts` | `AGENT_DEFS` role prompts for the 4 agents (spec §3.2–3.8) + `composeAgentSystem()`. |
| `company/blackboard.ts` | Firestore read/write of the Blackboard. Append-only for positions and conflicts. |
| `company/router.ts` | Phase 1 intake. `ROUTING_TOOL`, `parseRoutingToolInput()`, `runIntake()`. |
| `company/independentPass.ts` | Phase 2 parallel fan-out. `POSITION_TOOL`, `parsePositionToolInput()`, `runIndependentPass()`. |
| `company/conflicts.ts` | Phase 3. `detectConflicts()` — pure, no I/O. |
| `company/negotiation.ts` | Phase 4. `NEGOTIATION_TOOL`, `runNegotiation()`, 2-round cap. |
| `company/devilsAdvocate.ts` | Phase 4b. `shouldInvokeDevilsAdvocate()` (pure) + `runDevilsAdvocate()`. |
| `company/synthesis.ts` | Phase 5. `BRIEF_TOOL`, `runSynthesis()`, 6 required components. |
| `company/budget.ts` | Token ceiling, cost estimate, kill switch. |
| `company/virtualCompany.ts` | `handleVirtualCompanyRun` — HTTP + SSE orchestrator wiring the phases together. |
| `functions/src/anthropic.ts` | **Modify:** add model-tiering constants. |
| `functions/src/index.ts` | **Modify:** export `virtualCompanyRun`. |
| `docs/superpowers/specs/virtual-company-sse-contract.md` | **Deliverable for the UI engineer.** Event names, payload schemas, ordering guarantees. |

---

## Intentional deviations from the spec

Flag these to the team; they are deliberate, not oversights.

1. **`stance` field added to the position schema.** Spec §2.2 Phase 3 requires conflict detection to be pure code, but the spec's Phase 2 schema contains only prose fields — no two prose strings can be compared deterministically. Task 3 adds a `stance` enum (`proceed` / `proceed_with_conditions` / `do_not_proceed`) to `submit_position` so Phase 3 can classify without an LLM.
2. **Positions are emitted per-agent on completion, not token-by-token.** Spec §4.2B asks for per-token parallel streaming. Positions are structured tool-use output; streaming partial JSON into typed UI fields is fragile. Phase 2 emits `agent_start` then `agent_position`. Two agents starting at once and finishing independently still produces the "room is thinking" effect. Upgradeable later via `eager_input_streaming`.
3. **Router quality is an opt-in integration eval, not a unit test.** Spec TASK 4 wants ≥80% correct routing over 20 samples — that requires real API calls. Task 5 unit-tests parsing/validation; the 20-fixture eval is a separate `npm run eval:router` gated on `RUN_LIVE_EVALS=1`.
4. **Phase 6 (founder interjection) and the telemetry dashboard are out of MVP scope.** The Blackboard is persisted so Phase 6 can be added later without a redesign.

---

## Task 1: Model tiering constants

**Files:**
- Modify: `functions/src/anthropic.ts:3-5`
- Test: `functions/src/__tests__/companyModels.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: `ROUTER_MODEL`, `AGENT_MODEL`, `SYNTHESIS_MODEL`, `MODEL_PRICING` (all from `../anthropic`).

Existing lines 3–5 pin `claude-haiku-4-5-20251001` and `claude-sonnet-4-6`. Leave `MODEL` and `PLAN_MODEL` untouched — other handlers depend on them. Add new constants alongside.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyModels.test.ts`:

```ts
import { ROUTER_MODEL, AGENT_MODEL, SYNTHESIS_MODEL, MODEL_PRICING } from "../anthropic";

describe("virtual company model tiering", () => {
  test("router uses the cheapest tier", () => {
    expect(ROUTER_MODEL).toBe("claude-haiku-4-5");
  });

  test("department agents use sonnet 5", () => {
    expect(AGENT_MODEL).toBe("claude-sonnet-5");
  });

  test("synthesis and red team use opus 5", () => {
    expect(SYNTHESIS_MODEL).toBe("claude-opus-5");
  });

  test("model ids carry no date suffix", () => {
    for (const id of [ROUTER_MODEL, AGENT_MODEL, SYNTHESIS_MODEL]) {
      expect(id).not.toMatch(/-\d{8}$/);
    }
  });

  test("pricing is defined for every tier used", () => {
    for (const id of [ROUTER_MODEL, AGENT_MODEL, SYNTHESIS_MODEL]) {
      expect(MODEL_PRICING[id]).toBeDefined();
      expect(MODEL_PRICING[id].inputPerMTok).toBeGreaterThan(0);
      expect(MODEL_PRICING[id].outputPerMTok).toBeGreaterThan(0);
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyModels -v`
Expected: FAIL — `ROUTER_MODEL` is not exported from `../anthropic`.

- [ ] **Step 3: Write minimal implementation**

Append to `functions/src/anthropic.ts` (after the existing `MODEL` / `PLAN_MODEL` / `MAX_TOKENS` block):

```ts
// ─── Virtual Company model tiering ────────────────────────────────────────────
// Cost control per spec §5.2. Cheapest tier for routing (a classification task),
// mid tier for the department agents that run in parallel, top tier for the two
// jobs where quality is the product: synthesis and the red team.
export const ROUTER_MODEL = "claude-haiku-4-5";
export const AGENT_MODEL = "claude-sonnet-5";
export const SYNTHESIS_MODEL = "claude-opus-5";

export interface ModelPrice {
  inputPerMTok: number;
  outputPerMTok: number;
  /** Minimum cacheable prefix in tokens. Below this, caching silently no-ops. */
  cacheMinTokens: number;
}

// USD per million tokens, as of 2026-07-29. Sonnet 5 is at its introductory
// rate through 2026-08-31 ($2/$10); the standard $3/$15 is used here so the
// cost estimate does not under-report after the intro period ends.
export const MODEL_PRICING: Record<string, ModelPrice> = {
  "claude-haiku-4-5": { inputPerMTok: 1, outputPerMTok: 5, cacheMinTokens: 4096 },
  "claude-sonnet-5": { inputPerMTok: 3, outputPerMTok: 15, cacheMinTokens: 1024 },
  "claude-opus-5": { inputPerMTok: 5, outputPerMTok: 25, cacheMinTokens: 512 }
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyModels -v && npx tsc --noEmit`
Expected: 5 tests PASS, no type errors.

- [ ] **Step 5: Commit**

```bash
git add functions/src/anthropic.ts functions/src/__tests__/companyModels.test.ts
git commit -m "feat(company): add model tiering constants and pricing table"
```

---

## Task 2: Core types

**Files:**
- Create: `functions/src/company/types.ts`
- Test: `functions/src/__tests__/companyTypes.test.ts`

**Interfaces:**
- Consumes: nothing.
- Produces: every type below, plus the runtime constants `ALL_AGENTS`, `DEPARTMENT_AGENTS`, `AGENT_DEPARTMENT_KEY`, and the guard `isAgentId()`.

A types file has no behaviour to test, so this task's test covers only the runtime constants and the guard — which later tasks rely on for input validation.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyTypes.test.ts`:

```ts
import {
  ALL_AGENTS,
  DEPARTMENT_AGENTS,
  AGENT_DEPARTMENT_KEY,
  isAgentId
} from "../company/types";

describe("agent roster", () => {
  test("MVP roster is exactly 4 agents", () => {
    expect(ALL_AGENTS).toEqual([
      "chief_of_staff",
      "devils_advocate",
      "product",
      "finance"
    ]);
  });

  test("only product and finance produce positions", () => {
    expect(DEPARTMENT_AGENTS).toEqual(["product", "finance"]);
  });

  test("cut agents are not in the roster", () => {
    for (const cut of ["engineering", "design", "gtm", "legal", "security"]) {
      expect(ALL_AGENTS).not.toContain(cut);
    }
  });

  test("isAgentId accepts roster members and rejects everything else", () => {
    expect(isAgentId("product")).toBe(true);
    expect(isAgentId("finance")).toBe(true);
    expect(isAgentId("gtm")).toBe(false);
    expect(isAgentId("")).toBe(false);
    expect(isAgentId("PRODUCT")).toBe(false);
  });

  test("department agents map to client-side department keys", () => {
    // finance maps onto the existing Department.all entry `fin`.
    expect(AGENT_DEPARTMENT_KEY.finance).toBe("fin");
    // product has no entry in Department.all yet — the UI engineer adds it.
    expect(AGENT_DEPARTMENT_KEY.product).toBe("product");
    // The red team is explicitly not a department (spec §3.8).
    expect(AGENT_DEPARTMENT_KEY.devils_advocate).toBeNull();
    // Chief of staff is rendered as the founder's companion pet.
    expect(AGENT_DEPARTMENT_KEY.chief_of_staff).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyTypes -v`
Expected: FAIL — cannot find module `../company/types`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/types.ts`:

```ts
// Types for the Virtual Company multi-agent system.
// Spec: codepet-multi-agent-prompt-en.md (PART 2, PART 5.3)

export type AgentId = "chief_of_staff" | "devils_advocate" | "product" | "finance";

/** Full MVP roster. Order is stable so prompt caching stays byte-identical. */
export const ALL_AGENTS: AgentId[] = [
  "chief_of_staff",
  "devils_advocate",
  "product",
  "finance"
];

/** Agents that own a departmental concern and submit a position in Phase 2. */
export const DEPARTMENT_AGENTS: AgentId[] = ["product", "finance"];

/**
 * Maps an agent to a `Department.key` on the client so the UI can reuse the
 * existing accent colour and abbreviation. `null` means "render this agent with
 * its own identity, not as a department":
 *  - chief_of_staff → the founder's companion pet
 *  - devils_advocate → spec §3.8: "You are not a department. You have no
 *    interests to protect." Giving it a department colour would misrepresent it.
 */
export const AGENT_DEPARTMENT_KEY: Record<AgentId, string | null> = {
  chief_of_staff: null,
  devils_advocate: null,
  product: "product",
  finance: "fin"
};

export function isAgentId(value: unknown): value is AgentId {
  return typeof value === "string" && (ALL_AGENTS as string[]).includes(value);
}

export type RequestType = "DECISION" | "DIAGNOSIS" | "PLANNING" | "REVIEW";

export type Confidence = 1 | 2 | 3 | 4 | 5;

/**
 * Machine-comparable summary of an agent's position. Not in the original spec
 * schema — added so Phase 3 conflict detection can be pure code with no LLM
 * call (spec §2.2 Phase 3). Two prose fields cannot be compared
 * deterministically; two enums can.
 */
export type Stance = "proceed" | "proceed_with_conditions" | "do_not_proceed";

/** Phase 2 output. Mirrors spec §2.2 plus `stance`. */
export interface AgentPosition {
  stance: Stance;
  position: string;
  reasoning: string;
  evidence_needed: string[];
  risks_i_own: string[];
  confidence: Confidence;
  cost_to_my_dept: string;
  hard_blocker: string | null;
}

export type ConflictKind = "CONFLICT" | "BLOCKER" | "TENSION" | "ALIGNED";

export interface Conflict {
  a: AgentId;
  b: AgentId;
  kind: ConflictKind;
  /** Deterministic explanation of why this pair classified as it did. */
  reason: string;
}

export type RoutingChoice = "single_agent" | "multi_agent" | "needs_clarification";

export interface RoutingDecision {
  decision: RoutingChoice;
  /** Agents to convene. Empty for needs_clarification, length 1 for single_agent. */
  agents: AgentId[];
  real_question: string;
  request_type: RequestType;
  reason_per_agent: Partial<Record<AgentId, string>>;
  excluded: Partial<Record<AgentId, string>>;
  missing_info: string[];
}

export interface NegotiationTurn {
  agent: AgentId;
  precise_disagreement: string;
  what_would_change_my_mind: string;
  proposal: string;
  /** True only when this agent believes the trade-off is now resolvable. */
  resolved: boolean;
}

export interface NegotiationRound {
  round: 1 | 2;
  turns: NegotiationTurn[];
}

export interface DevilsAdvocateVerdict {
  load_bearing_assumption: string;
  how_it_could_be_false: string;
  cheapest_test: string;
  failure_post_mortem: string;
  who_is_not_in_the_room: string;
  /** Ranked, most decision-changing first. */
  objections: string[];
  /** True when the red team finds the plan genuinely sound (spec §3.8 rules). */
  plan_is_sound: boolean;
}

export interface DecisionBrief {
  recommendation: string;
  confidence: Confidence;
  confidence_reason: string;
  the_real_disagreement: string;
  tradeoff_founder_must_own: string;
  kill_criteria: string[];
  next_action: { action: string; owner: string };
  what_we_dont_know: string;
  /** True when a conflict could not be resolved. A valid outcome, not a failure. */
  unresolved: boolean;
}

export interface FounderContext {
  profile: string;
  stage: string;
  constraints: string[];
  language: "vi" | "en";
}

export interface TokenUsage {
  input: number;
  output: number;
  cache_read: number;
}

export interface Telemetry {
  tokens_per_agent: Partial<Record<AgentId, TokenUsage>>;
  cost_estimate_usd: number;
  /** Set when the run stopped early. Null on a complete run. */
  stopped_reason: string | null;
}

/** Source of truth for a run. Persisted so Phase 6 can resume without a restart. */
export interface Blackboard {
  run_id: string;
  uid: string;
  created_at: string;
  request: { raw: string; real_question: string; type: RequestType };
  founder: FounderContext;
  routing: RoutingDecision | null;
  positions: Partial<Record<AgentId, AgentPosition>>;
  conflicts: Conflict[];
  negotiation: NegotiationRound[];
  devils_advocate: DevilsAdvocateVerdict | null;
  synthesis: DecisionBrief | null;
  telemetry: Telemetry;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyTypes -v && npx tsc --noEmit`
Expected: 5 tests PASS, no type errors.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/types.ts functions/src/__tests__/companyTypes.test.ts
git commit -m "feat(company): core types and 4-agent MVP roster"
```

---

## Task 3: Shared preamble and cacheable prefix

**Files:**
- Create: `functions/src/company/preamble.ts`
- Test: `functions/src/__tests__/companyPreamble.test.ts`

**Interfaces:**
- Consumes: `FounderContext`, `Blackboard` from `./types`.
- Produces: `SHARED_PREAMBLE`, `POSITION_SCHEMA_DOC`, `estimateTokens(text: string): number`, `buildSharedPrefix(args: { founder: FounderContext; rawRequest: string }): string`.

This is the prompt-caching load-bearing task. The prefix must be **byte-identical for every agent in a run** — so the per-agent role prompt goes in a *second* system block, after the cache breakpoint. Getting this backwards means zero cache hits and roughly double the cost.

The prefix must also clear the target model's minimum cacheable length. `AGENT_MODEL` is `claude-sonnet-5`, whose minimum is **1024 tokens**. A prefix below that caches nothing and reports no error — it just silently costs full price. `estimateTokens` gives a cheap char-based guard; real verification is `cache_read_input_tokens > 0` in staging (Task 12).

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyPreamble.test.ts`:

```ts
import {
  SHARED_PREAMBLE,
  buildSharedPrefix,
  estimateTokens
} from "../company/preamble";
import { MODEL_PRICING, AGENT_MODEL } from "../anthropic";
import { FounderContext } from "../company/types";

const founder: FounderContext = {
  profile:
    "Solo founder, technical, previously a backend engineer at a mid-size fintech. " +
    "Has shipped one product before that reached 200 paying users then plateaued. " +
    "Comfortable with Swift and TypeScript, no design or sales background.",
  stage:
    "Pre-revenue, 4 months of runway left, product in closed beta with 30 users, " +
    "no pricing page yet.",
  constraints: [
    "Cannot hire — no budget for headcount this quarter.",
    "Must ship to the App Store before the end of next month.",
    "Refuses to take outside investment at this stage."
  ],
  language: "vi"
};

const rawRequest =
  "Should I build a team-collaboration feature so companies can buy seats, " +
  "or should I first put a price on the single-player product I already have?";

describe("estimateTokens", () => {
  test("scales with length and never returns zero for non-empty input", () => {
    expect(estimateTokens("")).toBe(0);
    expect(estimateTokens("a")).toBeGreaterThan(0);
    expect(estimateTokens("a".repeat(3500))).toBeGreaterThan(estimateTokens("a".repeat(350)));
  });

  test("approximates 3.5 chars per token", () => {
    expect(estimateTokens("a".repeat(3500))).toBe(1000);
  });
});

describe("buildSharedPrefix", () => {
  test("contains the shared preamble verbatim", () => {
    expect(buildSharedPrefix({ founder, rawRequest })).toContain(SHARED_PREAMBLE.trim());
  });

  test("embeds founder context, stage, and every constraint", () => {
    const prefix = buildSharedPrefix({ founder, rawRequest });
    expect(prefix).toContain(founder.profile);
    expect(prefix).toContain(founder.stage);
    for (const c of founder.constraints) {
      expect(prefix).toContain(c);
    }
  });

  test("resolves the output language to a human name", () => {
    expect(buildSharedPrefix({ founder, rawRequest })).toContain("Tiếng Việt");
    expect(
      buildSharedPrefix({ founder: { ...founder, language: "en" }, rawRequest })
    ).toContain("English");
  });

  test("contains no agent role text — roles live after the cache breakpoint", () => {
    const prefix = buildSharedPrefix({ founder, rawRequest });
    expect(prefix).not.toContain("Head of Product");
    expect(prefix).not.toContain("Head of Finance");
    expect(prefix).not.toContain("Devil's Advocate");
  });

  test("is deterministic — identical inputs give byte-identical output", () => {
    expect(buildSharedPrefix({ founder, rawRequest })).toBe(
      buildSharedPrefix({ founder, rawRequest })
    );
  });

  test("clears the cache minimum for the department-agent model", () => {
    // Below claude-sonnet-5's 1024-token floor, cache_control silently no-ops.
    const floor = MODEL_PRICING[AGENT_MODEL].cacheMinTokens;
    expect(estimateTokens(buildSharedPrefix({ founder, rawRequest }))).toBeGreaterThan(floor);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyPreamble -v`
Expected: FAIL — cannot find module `../company/preamble`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/preamble.ts`:

```ts
import { FounderContext } from "./types";

/**
 * Prepended to every agent (spec §3.1). Kept verbatim from the spec — this text
 * is what makes agents hold a position instead of hedging, so edits here change
 * the behaviour of the whole system.
 */
export const SHARED_PREAMBLE = `You are a department head inside a virtual technology company. A founder has
brought a real decision to the company. You are not an assistant and you are
not here to be agreeable. You are here because you own a specific concern that
nobody else in the room owns, and if you abandon it the founder loses the only
protection they have against a blind spot.

NON-NEGOTIABLE RULES:

1. Speak only from your department's lens. Do not hedge into other domains.
   If a question is outside your remit, say so in one line and stop. An
   engineer who opines on pricing is worse than useless — they crowd out the
   agent who actually owns pricing.

2. Have a position. "It depends" is not a position. If it genuinely depends,
   state what it depends on and give your position for the most likely branch.

3. Name your costs honestly. Every recommendation costs someone something.
   State what yours costs, including what it costs YOUR department. An agent
   that only lists benefits is not credible.

4. Disagree when you disagree. You will see other departments' positions in
   later rounds. Do not soften your view to match theirs. Consensus reached
   by capitulation is a failure of this system. If you change your mind, state
   the specific fact or argument that changed it.

5. Be falsifiable. State what evidence would prove you wrong. If you cannot
   name any, your confidence should be at most 2.

6. No corporate filler. No "great question", no "it's important to note", no
   restating the question. Open with your position.

7. Distinguish what you know from what you assume. Mark assumptions explicitly
   as ASSUMPTION: so the founder can challenge them.

8. Length discipline: 120–200 words for your position. You are one voice in a
   room, not the answer.`;

/**
 * Documents the position contract in the cacheable prefix. Lives here rather
 * than in each role prompt for two reasons: it is identical for every agent, and
 * putting it before the cache breakpoint grows the shared prefix past the
 * model's minimum cacheable length.
 */
export const POSITION_SCHEMA_DOC = `HOW YOU WILL BE ASKED TO ANSWER:

When asked for your position you will be given a tool called submit_position.
You must call it. Do not answer in prose. Its fields:

- stance: one of "proceed", "proceed_with_conditions", "do_not_proceed".
  This is the machine-readable summary of your view. Choose "do_not_proceed"
  only if you genuinely believe the founder should not do this — not merely
  because you have reservations. Reservations are "proceed_with_conditions".
- position: your stance in 1–2 sentences, in plain language.
- reasoning: why, seen through your department's lens only.
- evidence_needed: the specific facts that would raise your confidence.
- risks_i_own: the risks that fall inside your remit, not someone else's.
- confidence: 1 to 5. At most 2 if you cannot name falsifying evidence.
- cost_to_my_dept: what your own recommendation costs YOUR department.
- hard_blocker: your single non-negotiable, or null if you have none. Use this
  sparingly. A hard_blocker means "I cannot accept this outcome under any
  framing", not "I would prefer otherwise". Overusing it makes the founder
  stop believing any of them.

Two rules about disagreement, because they are the reason this company exists:
the founder has never had one department head push back on another, and that
tension is what they are paying for. Do not soften your position to match
someone else's. And if a trade-off genuinely cannot be resolved, saying so is
the correct answer — it tells the founder this is a choice only they can make.`;

/** Rough char→token estimate. Good enough for a cache-floor guard rail. */
export function estimateTokens(text: string): number {
  if (text.length === 0) return 0;
  return Math.max(1, Math.round(text.length / 3.5));
}

function languageName(language: FounderContext["language"]): string {
  return language === "vi" ? "Tiếng Việt" : "English";
}

/**
 * The cacheable prefix: identical bytes for every agent in a single run, so the
 * whole prefix is written to cache once and read by each subsequent agent.
 *
 * Order matters and is fixed: preamble → schema contract → founder context →
 * request. The per-agent role prompt is deliberately NOT here — it goes in a
 * second system block after the cache breakpoint (see registry.ts). Putting a
 * role prompt in this prefix would give every agent a different prefix and
 * defeat caching entirely.
 */
export function buildSharedPrefix(args: {
  founder: FounderContext;
  rawRequest: string;
}): string {
  const { founder, rawRequest } = args;
  const constraints =
    founder.constraints.length === 0
      ? "None stated."
      : founder.constraints.map((c) => `- ${c}`).join("\n");

  return [
    SHARED_PREAMBLE.trim(),
    POSITION_SCHEMA_DOC.trim(),
    `OUTPUT LANGUAGE: ${languageName(founder.language)}`,
    `FOUNDER CONTEXT:\n${founder.profile.trim()}`,
    `COMPANY STAGE:\n${founder.stage.trim()}`,
    `HARD CONSTRAINTS:\n${constraints}`,
    `THE FOUNDER'S REQUEST, VERBATIM:\n"""\n${rawRequest.trim()}\n"""`
  ].join("\n\n");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyPreamble -v && npx tsc --noEmit`
Expected: all tests PASS. If the cache-floor test fails, the prefix is short — grow `POSITION_SCHEMA_DOC`, do not lower the assertion.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/preamble.ts functions/src/__tests__/companyPreamble.test.ts
git commit -m "feat(company): shared preamble and cacheable prompt prefix"
```

---

## Task 4: Agent registry and prompt composition

**Files:**
- Create: `functions/src/company/registry.ts`
- Test: `functions/src/__tests__/companyRegistry.test.ts`

**Interfaces:**
- Consumes: `AgentId`, `ALL_AGENTS`, `FounderContext` from `./types`; `buildSharedPrefix` from `./preamble`.
- Produces:
  - `AGENT_DEFS: Record<AgentId, { role: string; model: string }>`
  - `composeAgentSystem(args: { agent: AgentId; founder: FounderContext; rawRequest: string }): SystemBlock[]`
  - `export interface SystemBlock { type: "text"; text: string; cache_control?: { type: "ephemeral" } }`

`composeAgentSystem` returns the two-block array passed straight to `client.messages.*` as `system`. Block 0 is the shared prefix carrying `cache_control`; block 1 is the role prompt.

Role prompt text comes verbatim from the spec: `chief_of_staff` §3.2, `product` §3.3, `finance` §3.7, `devils_advocate` §3.8. Copy them from `codepet-multi-agent-prompt-en.md` — do not paraphrase; the characteristic-failure and where-you-push-back sections are what keep the agents distinct.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyRegistry.test.ts`:

```ts
import { AGENT_DEFS, composeAgentSystem } from "../company/registry";
import { ALL_AGENTS, FounderContext } from "../company/types";
import { AGENT_MODEL, SYNTHESIS_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder, one prior product that plateaued at 200 users.",
  stage: "Pre-revenue, 4 months runway, 30 beta users, no pricing page.",
  constraints: ["Cannot hire this quarter.", "Must ship next month."],
  language: "en"
};
const rawRequest = "Should I add team seats or price the single-player product first?";

describe("AGENT_DEFS", () => {
  test("defines exactly the 4 MVP agents", () => {
    expect(Object.keys(AGENT_DEFS).sort()).toEqual([...ALL_AGENTS].sort());
  });

  test("every role prompt is substantial", () => {
    for (const agent of ALL_AGENTS) {
      expect(AGENT_DEFS[agent].role.length).toBeGreaterThan(400);
    }
  });

  test("department agents run on the mid tier, judgement roles on the top tier", () => {
    expect(AGENT_DEFS.product.model).toBe(AGENT_MODEL);
    expect(AGENT_DEFS.finance.model).toBe(AGENT_MODEL);
    expect(AGENT_DEFS.chief_of_staff.model).toBe(SYNTHESIS_MODEL);
    expect(AGENT_DEFS.devils_advocate.model).toBe(SYNTHESIS_MODEL);
  });

  test("each role prompt is distinct — no copy-paste between agents", () => {
    const roles = ALL_AGENTS.map((a) => AGENT_DEFS[a].role);
    expect(new Set(roles).size).toBe(roles.length);
  });

  test("role prompts state what each agent owns", () => {
    expect(AGENT_DEFS.product.role).toContain("YOU OWN");
    expect(AGENT_DEFS.finance.role).toContain("YOU OWN");
  });
});

describe("composeAgentSystem", () => {
  test("returns exactly two blocks", () => {
    const blocks = composeAgentSystem({ agent: "product", founder, rawRequest });
    expect(blocks).toHaveLength(2);
  });

  test("only the first block carries the cache breakpoint", () => {
    const blocks = composeAgentSystem({ agent: "product", founder, rawRequest });
    expect(blocks[0].cache_control).toEqual({ type: "ephemeral" });
    expect(blocks[1].cache_control).toBeUndefined();
  });

  test("the cached prefix is byte-identical across agents in the same run", () => {
    const a = composeAgentSystem({ agent: "product", founder, rawRequest });
    const b = composeAgentSystem({ agent: "finance", founder, rawRequest });
    // This is the whole point: same prefix → one cache write, N cache reads.
    expect(a[0].text).toBe(b[0].text);
  });

  test("the role block differs per agent", () => {
    const a = composeAgentSystem({ agent: "product", founder, rawRequest });
    const b = composeAgentSystem({ agent: "finance", founder, rawRequest });
    expect(a[1].text).not.toBe(b[1].text);
    expect(a[1].text).toBe(AGENT_DEFS.product.role);
  });

  test("no agent's composed prompt mentions a cut agent", () => {
    for (const agent of ALL_AGENTS) {
      const joined = composeAgentSystem({ agent, founder, rawRequest })
        .map((b) => b.text)
        .join("\n");
      expect(joined).not.toContain("Head of Engineering");
      expect(joined).not.toContain("Head of Go-to-Market");
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyRegistry -v`
Expected: FAIL — cannot find module `../company/registry`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/registry.ts`. Copy each role prompt verbatim from the spec sections named in the comments.

```ts
import { AgentId, FounderContext } from "./types";
import { buildSharedPrefix } from "./preamble";
import { AGENT_MODEL, SYNTHESIS_MODEL } from "../anthropic";

export interface SystemBlock {
  type: "text";
  text: string;
  cache_control?: { type: "ephemeral" };
}

interface AgentDef {
  /** Role prompt. Sits AFTER the cache breakpoint, so it may differ per agent. */
  role: string;
  model: string;
}

// Role prompts are copied verbatim from the spec. Do not paraphrase — the
// "characteristic failure" and "where you push back" sections are what keep the
// agents from collapsing into the same voice with different vocabulary.
const CHIEF_OF_STAFF_ROLE = `ROLE: Chief of Staff — router, decomposer, synthesizer.
[...copy spec §3.2 verbatim, from "You are the founder's translator" through the
FORBIDDEN line. Then append the MVP roster note below.]

ROSTER AVAILABLE TO YOU IN THIS DEPLOYMENT:
  product  — what is worth building, in what order
  finance  — unit economics, runway, pricing
You may also request devils_advocate as a stress test. No other departments
exist yet. If a request genuinely needs a discipline you do not have (for
example engineering cost or go-to-market), say so plainly in missing_info
rather than assigning it to product or finance.`;

const PRODUCT_ROLE = `ROLE: Head of Product.
[...copy spec §3.3 verbatim, from "YOU OWN: what gets built" through the
characteristic-failure line.]`;

const FINANCE_ROLE = `ROLE: Head of Finance.
[...copy spec §3.7 verbatim, from "YOU OWN: whether the company survives"
through "A number without its derivation is an opinion wearing a costume."]`;

const DEVILS_ADVOCATE_ROLE = `ROLE: Devil's Advocate / Red Team.
[...copy spec §3.8 verbatim, from "You are not a department" through the
RULES section.]`;

export const AGENT_DEFS: Record<AgentId, AgentDef> = {
  // Routing is a classification task, but synthesis is where the founder either
  // gets something actionable or does not — so this agent runs on the top tier.
  chief_of_staff: { role: CHIEF_OF_STAFF_ROLE, model: SYNTHESIS_MODEL },
  // The red team's whole job is finding the argument nobody else made.
  devils_advocate: { role: DEVILS_ADVOCATE_ROLE, model: SYNTHESIS_MODEL },
  product: { role: PRODUCT_ROLE, model: AGENT_MODEL },
  finance: { role: FINANCE_ROLE, model: AGENT_MODEL }
};

/**
 * Builds the `system` array for one agent.
 *
 * Block 0 — the shared prefix, byte-identical for every agent in this run,
 * carrying the cache breakpoint. Written to cache by whichever agent runs
 * first, read by all the others.
 * Block 1 — this agent's role prompt, after the breakpoint so it does not
 * fork the cache.
 */
export function composeAgentSystem(args: {
  agent: AgentId;
  founder: FounderContext;
  rawRequest: string;
}): SystemBlock[] {
  return [
    {
      type: "text",
      text: buildSharedPrefix({
        founder: args.founder,
        rawRequest: args.rawRequest
      }),
      cache_control: { type: "ephemeral" }
    },
    { type: "text", text: AGENT_DEFS[args.agent].role.trim() }
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyRegistry -v && npx tsc --noEmit`
Expected: all PASS. The `role.length > 400` assertion fails if a `[...copy spec]` placeholder was left in — that is intentional; replace every placeholder with the real spec text.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/registry.ts functions/src/__tests__/companyRegistry.test.ts
git commit -m "feat(company): agent registry with cache-safe prompt composition"
```

---

## Task 5: Conflict detection (pure code, no LLM)

**Files:**
- Create: `functions/src/company/conflicts.ts`
- Test: `functions/src/__tests__/companyConflicts.test.ts`

**Interfaces:**
- Consumes: `AgentId`, `AgentPosition`, `Conflict`, `ConflictKind`, `DEPARTMENT_AGENTS` from `./types`.
- Produces:
  - `classifyPair(a: AgentId, pa: AgentPosition, b: AgentId, pb: AgentPosition): Conflict`
  - `detectConflicts(positions: Partial<Record<AgentId, AgentPosition>>): Conflict[]`
  - `needsNegotiation(conflicts: Conflict[]): boolean`

Ordered before the LLM phases deliberately: it is pure and fully testable, and it defines the contract the position schema must satisfy. Zero I/O, zero async, zero LLM calls.

Classification rules, in priority order:

| Condition | Kind |
|---|---|
| Either side has a `hard_blocker` and the other's stance is `proceed` | `BLOCKER` |
| Stances are opposed (`do_not_proceed` vs any `proceed*`) | `CONFLICT` |
| Same direction, different intensity (`proceed` vs `proceed_with_conditions`) | `TENSION` |
| Identical stance, no blockers | `ALIGNED` |

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyConflicts.test.ts`:

```ts
import { classifyPair, detectConflicts, needsNegotiation } from "../company/conflicts";
import { AgentPosition, Stance } from "../company/types";

function pos(stance: Stance, hardBlocker: string | null = null): AgentPosition {
  return {
    stance,
    position: "p",
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 3,
    cost_to_my_dept: "c",
    hard_blocker: hardBlocker
  };
}

describe("classifyPair", () => {
  test("opposed stances are a CONFLICT", () => {
    const c = classifyPair("product", pos("proceed"), "finance", pos("do_not_proceed"));
    expect(c.kind).toBe("CONFLICT");
    expect(c.reason).toMatch(/opposed/i);
  });

  test("a hard_blocker against a proceed stance is a BLOCKER", () => {
    const c = classifyPair(
      "product",
      pos("proceed"),
      "finance",
      pos("do_not_proceed", "CAC exceeds LTV; scaling loses money faster.")
    );
    expect(c.kind).toBe("BLOCKER");
    expect(c.reason).toContain("finance");
  });

  test("BLOCKER outranks CONFLICT regardless of argument order", () => {
    const blocker = pos("do_not_proceed", "runway falls below 2 months");
    expect(classifyPair("product", pos("proceed"), "finance", blocker).kind).toBe("BLOCKER");
    expect(classifyPair("finance", blocker, "product", pos("proceed")).kind).toBe("BLOCKER");
  });

  test("same direction with different intensity is a TENSION", () => {
    const c = classifyPair("product", pos("proceed"), "finance", pos("proceed_with_conditions"));
    expect(c.kind).toBe("TENSION");
  });

  test("identical stances with no blockers are ALIGNED", () => {
    expect(classifyPair("product", pos("proceed"), "finance", pos("proceed")).kind).toBe("ALIGNED");
    expect(
      classifyPair("product", pos("do_not_proceed"), "finance", pos("do_not_proceed")).kind
    ).toBe("ALIGNED");
  });

  test("a hard_blocker on both sides of a shared stance stays ALIGNED", () => {
    // Both refuse for their own reasons — there is nothing to negotiate.
    const c = classifyPair(
      "product",
      pos("do_not_proceed", "displaces the only bet worth testing"),
      "finance",
      pos("do_not_proceed", "runway cannot absorb it")
    );
    expect(c.kind).toBe("ALIGNED");
  });
});

describe("detectConflicts", () => {
  test("returns one entry per unique department pair", () => {
    const conflicts = detectConflicts({
      product: pos("proceed"),
      finance: pos("do_not_proceed")
    });
    expect(conflicts).toHaveLength(1);
    expect(conflicts[0].a).toBe("product");
    expect(conflicts[0].b).toBe("finance");
  });

  test("returns empty when fewer than two positions exist", () => {
    expect(detectConflicts({ product: pos("proceed") })).toEqual([]);
    expect(detectConflicts({})).toEqual([]);
  });

  test("ignores non-department agents that carry no position", () => {
    const conflicts = detectConflicts({
      product: pos("proceed"),
      finance: pos("proceed")
    });
    expect(conflicts.every((c) => c.a !== "chief_of_staff" && c.b !== "chief_of_staff")).toBe(true);
  });

  test("is deterministic — pair order does not depend on key insertion order", () => {
    const a = detectConflicts({ finance: pos("proceed"), product: pos("do_not_proceed") });
    const b = detectConflicts({ product: pos("do_not_proceed"), finance: pos("proceed") });
    expect(a).toEqual(b);
  });

  test("makes no async calls — the result is available synchronously", () => {
    const result = detectConflicts({ product: pos("proceed"), finance: pos("proceed") });
    expect(Array.isArray(result)).toBe(true);
  });
});

describe("needsNegotiation", () => {
  test("true when any pair is CONFLICT or BLOCKER", () => {
    expect(needsNegotiation([{ a: "product", b: "finance", kind: "CONFLICT", reason: "" }])).toBe(true);
    expect(needsNegotiation([{ a: "product", b: "finance", kind: "BLOCKER", reason: "" }])).toBe(true);
  });

  test("false when everything is ALIGNED or merely TENSION", () => {
    // Spec §2.2 Phase 3: never debate when there is nothing to debate.
    expect(needsNegotiation([{ a: "product", b: "finance", kind: "ALIGNED", reason: "" }])).toBe(false);
    expect(needsNegotiation([{ a: "product", b: "finance", kind: "TENSION", reason: "" }])).toBe(false);
    expect(needsNegotiation([])).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyConflicts -v`
Expected: FAIL — cannot find module `../company/conflicts`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/conflicts.ts`:

```ts
import {
  AgentId,
  AgentPosition,
  Conflict,
  ConflictKind,
  DEPARTMENT_AGENTS,
  Stance
} from "./types";

/** True for any stance that means "go ahead", at any intensity. */
function isProceed(stance: Stance): boolean {
  return stance === "proceed" || stance === "proceed_with_conditions";
}

function opposed(a: Stance, b: Stance): boolean {
  return isProceed(a) !== isProceed(b);
}

/**
 * Classifies one pair of positions. Pure and deterministic — spec §2.2 Phase 3
 * requires this phase to make no LLM call, so the comparison runs on the
 * `stance` enum and `hard_blocker` presence rather than on prose.
 */
export function classifyPair(
  a: AgentId,
  pa: AgentPosition,
  b: AgentId,
  pb: AgentPosition
): Conflict {
  const mk = (kind: ConflictKind, reason: string): Conflict => ({ a, b, kind, reason });

  // A blocker only bites when the other side actually wants to proceed. Two
  // agents refusing for different reasons have nothing to negotiate.
  const aBlocks = pa.hard_blocker !== null && isProceed(pb.stance);
  const bBlocks = pb.hard_blocker !== null && isProceed(pa.stance);
  if (aBlocks || bBlocks) {
    const blocker = aBlocks ? a : b;
    const blockerText = (aBlocks ? pa.hard_blocker : pb.hard_blocker) ?? "";
    return mk("BLOCKER", `${blocker} raised a hard blocker: ${blockerText}`);
  }

  if (opposed(pa.stance, pb.stance)) {
    return mk("CONFLICT", `Directly opposed: ${a} is ${pa.stance}, ${b} is ${pb.stance}.`);
  }

  if (pa.stance !== pb.stance) {
    return mk(
      "TENSION",
      `Same direction, different priority: ${a} is ${pa.stance}, ${b} is ${pb.stance}.`
    );
  }

  return mk("ALIGNED", `Both ${a} and ${b} are ${pa.stance} with no hard blocker in play.`);
}

/**
 * Classifies every unique pair of department positions. Iterates
 * DEPARTMENT_AGENTS rather than Object.keys(positions) so the output order is
 * stable regardless of how the positions object was built.
 */
export function detectConflicts(
  positions: Partial<Record<AgentId, AgentPosition>>
): Conflict[] {
  const present = DEPARTMENT_AGENTS.filter((id) => positions[id] !== undefined);
  const out: Conflict[] = [];
  for (let i = 0; i < present.length; i++) {
    for (let j = i + 1; j < present.length; j++) {
      const a = present[i];
      const b = present[j];
      out.push(classifyPair(a, positions[a]!, b, positions[b]!));
    }
  }
  return out;
}

/** Spec §2.2: if everything is ALIGNED, skip Phase 4 entirely. */
export function needsNegotiation(conflicts: Conflict[]): boolean {
  return conflicts.some((c) => c.kind === "CONFLICT" || c.kind === "BLOCKER");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyConflicts -v && npx tsc --noEmit`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/conflicts.ts functions/src/__tests__/companyConflicts.test.ts
git commit -m "feat(company): deterministic conflict detection with no LLM call"
```

---

## Task 6: Blackboard store

**Files:**
- Create: `functions/src/company/blackboard.ts`
- Test: `functions/src/__tests__/companyBlackboard.test.ts`

**Interfaces:**
- Consumes: `Blackboard`, `AgentId`, `AgentPosition`, `Conflict`, `RoutingDecision`, `NegotiationRound`, `DevilsAdvocateVerdict`, `DecisionBrief`, `FounderContext`, `TokenUsage` from `./types`.
- Produces:
  - `newBlackboard(args: { runId: string; uid: string; rawRequest: string; founder: FounderContext; now?: Date }): Blackboard`
  - `saveBlackboard(bb: Blackboard): Promise<void>`
  - `loadBlackboard(runId: string): Promise<Blackboard | null>`
  - `recordPosition(bb: Blackboard, agent: AgentId, position: AgentPosition): Blackboard`
  - `recordUsage(bb: Blackboard, agent: AgentId, model: string, usage: TokenUsage): Blackboard`
  - `COMPANY_RUNS_COLLECTION = "company_runs"`

Mutators are pure and return a new Blackboard — that keeps them unit-testable without Firestore and makes the append-only rule (`recordPosition` never overwrites) enforceable in a plain assertion. Only `saveBlackboard` / `loadBlackboard` touch I/O.

`recordUsage` folds the cost estimate as it goes, using `MODEL_PRICING` from Task 1, so Task 11's budget guard has a running total to read.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyBlackboard.test.ts`:

```ts
import {
  newBlackboard,
  recordPosition,
  recordUsage
} from "../company/blackboard";
import { AgentPosition, FounderContext } from "../company/types";
import { AGENT_MODEL, MODEL_PRICING } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};

function pos(overrides: Partial<AgentPosition> = {}): AgentPosition {
  return {
    stance: "proceed",
    position: "p",
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 3,
    cost_to_my_dept: "c",
    hard_blocker: null,
    ...overrides
  };
}

describe("newBlackboard", () => {
  test("starts empty with the request recorded verbatim", () => {
    const bb = newBlackboard({
      runId: "r1",
      uid: "u1",
      rawRequest: "  Should I price it?  ",
      founder,
      now: new Date("2026-07-29T00:00:00Z")
    });
    expect(bb.run_id).toBe("r1");
    expect(bb.uid).toBe("u1");
    expect(bb.request.raw).toBe("Should I price it?");
    expect(bb.routing).toBeNull();
    expect(bb.positions).toEqual({});
    expect(bb.conflicts).toEqual([]);
    expect(bb.negotiation).toEqual([]);
    expect(bb.devils_advocate).toBeNull();
    expect(bb.synthesis).toBeNull();
    expect(bb.created_at).toBe("2026-07-29T00:00:00.000Z");
  });

  test("telemetry starts at zero with no stop reason", () => {
    const bb = newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder });
    expect(bb.telemetry.cost_estimate_usd).toBe(0);
    expect(bb.telemetry.tokens_per_agent).toEqual({});
    expect(bb.telemetry.stopped_reason).toBeNull();
  });
});

describe("recordPosition", () => {
  test("adds a position without mutating the input blackboard", () => {
    const bb = newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder });
    const next = recordPosition(bb, "product", pos({ position: "ship the smallest test" }));
    expect(next.positions.product?.position).toBe("ship the smallest test");
    expect(bb.positions.product).toBeUndefined();
  });

  test("is append-only — a second write for the same agent throws", () => {
    // Overwriting a position would let a later phase quietly rewrite history.
    const bb = recordPosition(
      newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder }),
      "product",
      pos()
    );
    expect(() => recordPosition(bb, "product", pos({ position: "changed" }))).toThrow(
      /already recorded/i
    );
  });
});

describe("recordUsage", () => {
  test("accumulates tokens per agent", () => {
    let bb = newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder });
    bb = recordUsage(bb, "product", AGENT_MODEL, { input: 100, output: 50, cache_read: 900 });
    bb = recordUsage(bb, "product", AGENT_MODEL, { input: 10, output: 5, cache_read: 0 });
    expect(bb.telemetry.tokens_per_agent.product).toEqual({
      input: 110,
      output: 55,
      cache_read: 900
    });
  });

  test("folds a running cost estimate using the pricing table", () => {
    const bb = recordUsage(
      newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder }),
      "product",
      AGENT_MODEL,
      { input: 1_000_000, output: 0, cache_read: 0 }
    );
    expect(bb.telemetry.cost_estimate_usd).toBeCloseTo(
      MODEL_PRICING[AGENT_MODEL].inputPerMTok,
      5
    );
  });

  test("prices cache reads at a tenth of input", () => {
    const bb = recordUsage(
      newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder }),
      "product",
      AGENT_MODEL,
      { input: 0, output: 0, cache_read: 1_000_000 }
    );
    expect(bb.telemetry.cost_estimate_usd).toBeCloseTo(
      MODEL_PRICING[AGENT_MODEL].inputPerMTok * 0.1,
      5
    );
  });

  test("an unknown model contributes no cost rather than throwing", () => {
    const bb = recordUsage(
      newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder }),
      "product",
      "some-future-model",
      { input: 1_000_000, output: 1_000_000, cache_read: 0 }
    );
    expect(bb.telemetry.cost_estimate_usd).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyBlackboard -v`
Expected: FAIL — cannot find module `../company/blackboard`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/blackboard.ts`:

```ts
import * as admin from "firebase-admin";
import { MODEL_PRICING } from "../anthropic";
import {
  AgentId,
  AgentPosition,
  Blackboard,
  FounderContext,
  TokenUsage
} from "./types";

export const COMPANY_RUNS_COLLECTION = "company_runs";

export function newBlackboard(args: {
  runId: string;
  uid: string;
  rawRequest: string;
  founder: FounderContext;
  now?: Date;
}): Blackboard {
  const raw = args.rawRequest.trim();
  return {
    run_id: args.runId,
    uid: args.uid,
    created_at: (args.now ?? new Date()).toISOString(),
    // real_question and type are filled in by the router in Phase 1. Until then
    // the raw request stands in, so a run that fails at intake still reads back.
    request: { raw, real_question: raw, type: "DECISION" },
    founder: args.founder,
    routing: null,
    positions: {},
    conflicts: [],
    negotiation: [],
    devils_advocate: null,
    synthesis: null,
    telemetry: { tokens_per_agent: {}, cost_estimate_usd: 0, stopped_reason: null }
  };
}

/**
 * Append-only. Throws rather than overwriting: a silent overwrite would let a
 * later phase rewrite what an agent actually said in Phase 2, which is exactly
 * the history the founder is being shown.
 */
export function recordPosition(
  bb: Blackboard,
  agent: AgentId,
  position: AgentPosition
): Blackboard {
  if (bb.positions[agent] !== undefined) {
    throw new Error(`position for ${agent} already recorded in run ${bb.run_id}`);
  }
  return { ...bb, positions: { ...bb.positions, [agent]: position } };
}

function costOf(model: string, usage: TokenUsage): number {
  const price = MODEL_PRICING[model];
  if (!price) return 0;
  const perToken = (perMTok: number) => perMTok / 1_000_000;
  return (
    usage.input * perToken(price.inputPerMTok) +
    usage.output * perToken(price.outputPerMTok) +
    // Cache reads bill at roughly 0.1x the input rate.
    usage.cache_read * perToken(price.inputPerMTok) * 0.1
  );
}

export function recordUsage(
  bb: Blackboard,
  agent: AgentId,
  model: string,
  usage: TokenUsage
): Blackboard {
  const prev = bb.telemetry.tokens_per_agent[agent] ?? {
    input: 0,
    output: 0,
    cache_read: 0
  };
  return {
    ...bb,
    telemetry: {
      ...bb.telemetry,
      tokens_per_agent: {
        ...bb.telemetry.tokens_per_agent,
        [agent]: {
          input: prev.input + usage.input,
          output: prev.output + usage.output,
          cache_read: prev.cache_read + usage.cache_read
        }
      },
      cost_estimate_usd: bb.telemetry.cost_estimate_usd + costOf(model, usage)
    }
  };
}

export async function saveBlackboard(bb: Blackboard): Promise<void> {
  await admin
    .firestore()
    .collection(COMPANY_RUNS_COLLECTION)
    .doc(bb.run_id)
    .set(bb, { merge: true });
}

export async function loadBlackboard(runId: string): Promise<Blackboard | null> {
  const snap = await admin
    .firestore()
    .collection(COMPANY_RUNS_COLLECTION)
    .doc(runId)
    .get();
  return snap.exists ? (snap.data() as Blackboard) : null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyBlackboard -v && npx tsc --noEmit`
Expected: all PASS. The Firestore functions are not unit-tested here — they are covered by the staging smoke test in Task 12.

- [ ] **Step 5: Add the Firestore security rule**

The client must never write a run document directly — runs are written by the function using admin credentials, and the client only reads its own. Add to `firestore.rules` inside the existing `match /databases/{database}/documents { ... }` block:

```
    // Virtual Company runs. Written only by Cloud Functions (admin SDK bypasses
    // rules); the owning founder may read their own run for replay.
    match /company_runs/{runId} {
      allow read: if request.auth != null && resource.data.uid == request.auth.uid;
      allow write: if false;
    }
```

- [ ] **Step 6: Commit**

```bash
git add functions/src/company/blackboard.ts functions/src/__tests__/companyBlackboard.test.ts firestore.rules
git commit -m "feat(company): append-only blackboard store with cost accounting"
```

---

## Task 7: Router (Phase 1 intake)

**Files:**
- Create: `functions/src/company/router.ts`
- Test: `functions/src/__tests__/companyRouter.test.ts`

**Interfaces:**
- Consumes: `composeAgentSystem` from `./registry`; `RoutingDecision`, `RoutingChoice`, `AgentId`, `isAgentId`, `DEPARTMENT_AGENTS`, `FounderContext`, `TokenUsage` from `./types`; `ROUTER_MODEL` from `../anthropic`.
- Produces:
  - `ROUTING_TOOL` (Anthropic tool definition)
  - `parseRoutingToolInput(input: unknown): RoutingDecision | { error: string }`
  - `type AgentCaller = (args: { agent: AgentId; model: string; system: SystemBlock[]; userMessage: string; tool: unknown; toolName: string }) => Promise<{ input: unknown; usage: TokenUsage }>`
  - `runIntake(args: { founder: FounderContext; rawRequest: string; call: AgentCaller }): Promise<{ routing: RoutingDecision; usage: TokenUsage }>`

`AgentCaller` is the single injection seam for every LLM phase — Tasks 8, 9, 10, 11 all take one. Real implementation lands in Task 11; tests pass fakes.

Router quality (spec's ≥80% over 20 samples) is an integration eval, not a unit test — see the deviations section. Unit tests here cover parsing and the escape hatch, which is where the real bugs live: a router that returns `gtm` (not in this deployment) must be rejected, not silently convened.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyRouter.test.ts`:

```ts
import { ROUTING_TOOL, parseRoutingToolInput, runIntake } from "../company/router";
import { FounderContext, TokenUsage } from "../company/types";
import { ROUTER_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

function validInput(overrides: Record<string, unknown> = {}) {
  return {
    decision: "multi_agent",
    agents: ["product", "finance"],
    real_question: "Is the current pricing bet wrong?",
    request_type: "DECISION",
    reason_per_agent: {
      product: "This displaces the only bet worth testing this quarter.",
      finance: "This changes the revenue structure."
    },
    excluded: {},
    missing_info: [],
    ...overrides
  };
}

describe("ROUTING_TOOL", () => {
  test("is named record_routing and requires the load-bearing fields", () => {
    expect(ROUTING_TOOL.name).toBe("record_routing");
    const required = ROUTING_TOOL.input_schema.required as string[];
    for (const field of ["decision", "agents", "real_question", "request_type"]) {
      expect(required).toContain(field);
    }
  });

  test("offers only agents that exist in this deployment", () => {
    const agentEnum = (ROUTING_TOOL.input_schema.properties as any).agents.items.enum as string[];
    expect(agentEnum.sort()).toEqual(["devils_advocate", "finance", "product"]);
    expect(agentEnum).not.toContain("gtm");
    expect(agentEnum).not.toContain("engineering");
  });
});

describe("parseRoutingToolInput", () => {
  test("accepts a well-formed routing decision", () => {
    const result = parseRoutingToolInput(validInput());
    expect("error" in result).toBe(false);
    expect((result as any).agents).toEqual(["product", "finance"]);
  });

  test("rejects an agent that does not exist in this deployment", () => {
    // A hallucinated department must not be convened — it has no role prompt.
    const result = parseRoutingToolInput(validInput({ agents: ["product", "gtm"] }));
    expect(result).toEqual({ error: expect.stringMatching(/gtm/) });
  });

  test("rejects an unknown decision value", () => {
    expect(parseRoutingToolInput(validInput({ decision: "convene_everyone" }))).toEqual({
      error: expect.stringMatching(/decision/)
    });
  });

  test("rejects single_agent that names more than one agent", () => {
    const result = parseRoutingToolInput(
      validInput({ decision: "single_agent", agents: ["product", "finance"] })
    );
    expect(result).toEqual({ error: expect.stringMatching(/single_agent/) });
  });

  test("rejects multi_agent with fewer than two agents", () => {
    // Convening "the company" with one voice defeats the point of the feature.
    const result = parseRoutingToolInput(
      validInput({ decision: "multi_agent", agents: ["product"] })
    );
    expect(result).toEqual({ error: expect.stringMatching(/multi_agent/) });
  });

  test("allows needs_clarification with no agents", () => {
    const result = parseRoutingToolInput(
      validInput({ decision: "needs_clarification", agents: [], missing_info: ["current MRR"] })
    );
    expect("error" in result).toBe(false);
    expect((result as any).missing_info).toEqual(["current MRR"]);
  });

  test("defaults optional maps and arrays instead of leaving them undefined", () => {
    const input = validInput();
    delete (input as any).reason_per_agent;
    delete (input as any).excluded;
    delete (input as any).missing_info;
    const result = parseRoutingToolInput(input) as any;
    expect(result.reason_per_agent).toEqual({});
    expect(result.excluded).toEqual({});
    expect(result.missing_info).toEqual([]);
  });

  test("rejects a non-object input", () => {
    expect(parseRoutingToolInput(null)).toEqual({ error: expect.any(String) });
    expect(parseRoutingToolInput("multi_agent")).toEqual({ error: expect.any(String) });
  });
});

describe("runIntake", () => {
  test("calls the router on the cheapest tier with the chief_of_staff prompt", async () => {
    const seen: any[] = [];
    const { routing } = await runIntake({
      founder,
      rawRequest: "Should I add team seats?",
      call: async (args) => {
        seen.push(args);
        return { input: validInput(), usage: zeroUsage };
      }
    });
    expect(seen).toHaveLength(1);
    expect(seen[0].agent).toBe("chief_of_staff");
    expect(seen[0].model).toBe(ROUTER_MODEL);
    expect(seen[0].toolName).toBe("record_routing");
    expect(routing.decision).toBe("multi_agent");
  });

  test("passes the founder's verbatim request to the router", async () => {
    let userMessage = "";
    await runIntake({
      founder,
      rawRequest: "Should I add team seats?",
      call: async (args) => {
        userMessage = args.userMessage;
        return { input: validInput(), usage: zeroUsage };
      }
    });
    expect(userMessage).toContain("Should I add team seats?");
  });

  test("throws a descriptive error when the model returns an unusable routing", async () => {
    await expect(
      runIntake({
        founder,
        rawRequest: "x",
        call: async () => ({ input: validInput({ agents: ["gtm"] }), usage: zeroUsage })
      })
    ).rejects.toThrow(/routing/i);
  });

  test("returns usage so the caller can meter the router call", async () => {
    const { usage } = await runIntake({
      founder,
      rawRequest: "x",
      call: async () => ({
        input: validInput(),
        usage: { input: 1200, output: 80, cache_read: 0 }
      })
    });
    expect(usage).toEqual({ input: 1200, output: 80, cache_read: 0 });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyRouter -v`
Expected: FAIL — cannot find module `../company/router`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/router.ts`:

```ts
import { ROUTER_MODEL } from "../anthropic";
import { composeAgentSystem, SystemBlock } from "./registry";
import {
  AgentId,
  FounderContext,
  isAgentId,
  RequestType,
  RoutingChoice,
  RoutingDecision,
  TokenUsage
} from "./types";

/** Agents the router is allowed to convene. chief_of_staff is implicit. */
const ROUTABLE_AGENTS: AgentId[] = ["product", "finance", "devils_advocate"];

const REQUEST_TYPES: RequestType[] = ["DECISION", "DIAGNOSIS", "PLANNING", "REVIEW"];
const DECISIONS: RoutingChoice[] = ["single_agent", "multi_agent", "needs_clarification"];

export const ROUTING_TOOL = {
  name: "record_routing",
  description:
    "Record your intake decision for this request. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      decision: {
        type: "string",
        enum: DECISIONS,
        description:
          "single_agent when one specialist suffices; multi_agent only when you can name at least two departments whose interests actually pull in different directions; needs_clarification when the missing input is material."
      },
      agents: {
        type: "array",
        items: { type: "string", enum: ROUTABLE_AGENTS },
        description:
          "Departments to convene. Exactly one for single_agent, at least two for multi_agent, empty for needs_clarification."
      },
      real_question: {
        type: "string",
        description:
          "The question actually at stake. Say so explicitly when it differs from what was asked."
      },
      request_type: { type: "string", enum: REQUEST_TYPES },
      reason_per_agent: {
        type: "object",
        additionalProperties: { type: "string" },
        description:
          "For each agent you selected, one line on why their concern is live in THIS request. If you cannot articulate why, do not include them."
      },
      excluded: {
        type: "object",
        additionalProperties: { type: "string" },
        description: "For each agent you did not select, one line on why not."
      },
      missing_info: {
        type: "array",
        items: { type: "string" },
        description: "Materially missing information."
      }
    },
    required: ["decision", "agents", "real_question", "request_type"],
    additionalProperties: false
  }
};

function asStringMap(value: unknown): Record<string, string> {
  if (typeof value !== "object" || value === null) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (typeof v === "string") out[k] = v;
  }
  return out;
}

/**
 * Validates the router's tool output. Strict on purpose: a hallucinated
 * department has no role prompt in this deployment, so convening it would fail
 * later with a much less obvious error.
 */
export function parseRoutingToolInput(
  input: unknown
): RoutingDecision | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "routing tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;

  const decision = raw.decision;
  if (typeof decision !== "string" || !(DECISIONS as string[]).includes(decision)) {
    return { error: `unknown decision: ${String(decision)}` };
  }

  if (!Array.isArray(raw.agents)) {
    return { error: "agents must be an array" };
  }
  const agents: AgentId[] = [];
  for (const candidate of raw.agents) {
    if (!isAgentId(candidate) || !ROUTABLE_AGENTS.includes(candidate)) {
      return { error: `agent not available in this deployment: ${String(candidate)}` };
    }
    if (!agents.includes(candidate)) agents.push(candidate);
  }

  if (decision === "single_agent" && agents.length !== 1) {
    return { error: `single_agent requires exactly one agent, got ${agents.length}` };
  }
  if (decision === "multi_agent" && agents.length < 2) {
    return { error: `multi_agent requires at least two agents, got ${agents.length}` };
  }

  if (typeof raw.real_question !== "string" || raw.real_question.trim().length === 0) {
    return { error: "real_question is required" };
  }
  const requestType = raw.request_type;
  if (typeof requestType !== "string" || !(REQUEST_TYPES as string[]).includes(requestType)) {
    return { error: `unknown request_type: ${String(requestType)}` };
  }

  return {
    decision: decision as RoutingChoice,
    agents,
    real_question: raw.real_question.trim(),
    request_type: requestType as RequestType,
    reason_per_agent: asStringMap(raw.reason_per_agent),
    excluded: asStringMap(raw.excluded),
    missing_info: Array.isArray(raw.missing_info)
      ? raw.missing_info.filter((m): m is string => typeof m === "string")
      : []
  };
}

/** Single injection seam for every LLM phase. Real impl lands in Task 11. */
export type AgentCaller = (args: {
  agent: AgentId;
  model: string;
  system: SystemBlock[];
  userMessage: string;
  tool: unknown;
  toolName: string;
}) => Promise<{ input: unknown; usage: TokenUsage }>;

const INTAKE_INSTRUCTION = `Perform your INTAKE duties on the founder's request below.

Judge scale honestly: does this need the company, or one person? Bias toward
single_agent. Convening the company for a small question wastes the founder's
money and trains them to ignore the output. Reserve multi_agent for decisions
that are expensive, hard to reverse, or where you can name at least two
departments whose interests actually pull in different directions.

Call record_routing.

THE REQUEST:
"""
<request>
"""`;

export async function runIntake(args: {
  founder: FounderContext;
  rawRequest: string;
  call: AgentCaller;
}): Promise<{ routing: RoutingDecision; usage: TokenUsage }> {
  const { input, usage } = await args.call({
    agent: "chief_of_staff",
    // Routing is classification — the cheapest tier is enough, and it runs on
    // every single request. Synthesis is where the top tier earns its cost.
    model: ROUTER_MODEL,
    system: composeAgentSystem({
      agent: "chief_of_staff",
      founder: args.founder,
      rawRequest: args.rawRequest
    }),
    userMessage: INTAKE_INSTRUCTION.replace("<request>", args.rawRequest.trim()),
    tool: ROUTING_TOOL,
    toolName: ROUTING_TOOL.name
  });

  const parsed = parseRoutingToolInput(input);
  if ("error" in parsed) {
    throw new Error(`unusable routing from chief_of_staff: ${parsed.error}`);
  }
  return { routing: parsed, usage };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyRouter -v && npx tsc --noEmit`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/router.ts functions/src/__tests__/companyRouter.test.ts
git commit -m "feat(company): phase 1 router with single_agent escape hatch"
```

---

## Task 8: Independent pass (mutually blind)

**Files:**
- Create: `functions/src/company/independentPass.ts`
- Test: `functions/src/__tests__/companyIndependentPass.test.ts`

**Interfaces:**
- Consumes: `AgentCaller` from `./router`; `composeAgentSystem` from `./registry`; `AGENT_DEFS` from `./registry`; `AgentId`, `AgentPosition`, `Stance`, `FounderContext`, `TokenUsage` from `./types`.
- Produces:
  - `POSITION_TOOL`
  - `parsePositionToolInput(input: unknown): AgentPosition | { error: string }`
  - `runIndependentPass(args: { founder: FounderContext; rawRequest: string; realQuestion: string; agents: AgentId[]; call: AgentCaller }): Promise<{ results: Array<{ agent: AgentId; position?: AgentPosition; error?: string; usage: TokenUsage; model: string }> }>`

**This task carries the most important test in the system.** Spec TASK 5: if agents can see each other in Phase 2 they anchor on whichever opinion they read first, and the entire value of multiple perspectives is gone — while every other test still passes. The mutual-blindness test must be written first and must be specific: a sentinel string in agent A's output, asserted absent from every prompt sent to agent B.

Fan-out uses `Promise.allSettled` so one agent failing degrades to an error entry for that agent only, and the run continues (spec §5.5 graceful degradation).

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyIndependentPass.test.ts`:

```ts
import {
  POSITION_TOOL,
  parsePositionToolInput,
  runIndependentPass
} from "../company/independentPass";
import { AgentId, FounderContext, TokenUsage } from "../company/types";
import { AGENT_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const rawRequest = "Should I add team seats or price the single-player product?";
const realQuestion = "Is the current pricing bet wrong?";
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

function positionInput(overrides: Record<string, unknown> = {}) {
  return {
    stance: "proceed",
    position: "Ship the smallest version that produces a real pricing signal.",
    reasoning: "Sequencing over scope.",
    evidence_needed: ["Week-4 retention on the beta cohort"],
    risks_i_own: ["Building for an imagined buyer"],
    confidence: 3,
    cost_to_my_dept: "Displaces the onboarding rework this quarter.",
    hard_blocker: null,
    ...overrides
  };
}

describe("POSITION_TOOL", () => {
  test("is named submit_position and requires every comparable field", () => {
    expect(POSITION_TOOL.name).toBe("submit_position");
    const required = POSITION_TOOL.input_schema.required as string[];
    for (const field of [
      "stance",
      "position",
      "reasoning",
      "confidence",
      "cost_to_my_dept",
      "hard_blocker"
    ]) {
      expect(required).toContain(field);
    }
  });

  test("stance is a closed enum so phase 3 can compare it without an LLM", () => {
    const stanceEnum = (POSITION_TOOL.input_schema.properties as any).stance.enum as string[];
    expect(stanceEnum.sort()).toEqual(["do_not_proceed", "proceed", "proceed_with_conditions"]);
  });
});

describe("parsePositionToolInput", () => {
  test("accepts a well-formed position", () => {
    const result = parsePositionToolInput(positionInput());
    expect("error" in result).toBe(false);
    expect((result as any).stance).toBe("proceed");
  });

  test("preserves an explicit null hard_blocker", () => {
    const result = parsePositionToolInput(positionInput({ hard_blocker: null })) as any;
    expect(result.hard_blocker).toBeNull();
  });

  test("normalises an empty-string hard_blocker to null", () => {
    // Models sometimes emit "" instead of null; "" must not read as a blocker.
    const result = parsePositionToolInput(positionInput({ hard_blocker: "  " })) as any;
    expect(result.hard_blocker).toBeNull();
  });

  test("rejects an unknown stance", () => {
    expect(parsePositionToolInput(positionInput({ stance: "maybe" }))).toEqual({
      error: expect.stringMatching(/stance/)
    });
  });

  test("clamps confidence into 1..5", () => {
    expect((parsePositionToolInput(positionInput({ confidence: 9 })) as any).confidence).toBe(5);
    expect((parsePositionToolInput(positionInput({ confidence: 0 })) as any).confidence).toBe(1);
  });

  test("rejects a missing position string", () => {
    expect(parsePositionToolInput(positionInput({ position: "" }))).toEqual({
      error: expect.stringMatching(/position/)
    });
  });

  test("defaults the list fields to empty arrays", () => {
    const input = positionInput();
    delete (input as any).evidence_needed;
    delete (input as any).risks_i_own;
    const result = parsePositionToolInput(input) as any;
    expect(result.evidence_needed).toEqual([]);
    expect(result.risks_i_own).toEqual([]);
  });
});

describe("runIndependentPass — MUTUAL BLINDNESS", () => {
  // Spec TASK 5: the most important test in the system. If it fails, the
  // feature loses its value even when everything else works.
  const SENTINEL = "SENTINEL_ALPHA_9Z_PRODUCT_ONLY";

  test("no agent's prompt contains any other agent's output", async () => {
    const promptsByAgent = new Map<AgentId, string>();

    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        promptsByAgent.set(
          args.agent,
          args.system.map((b) => b.text).join("\n") + "\n" + args.userMessage
        );
        if (args.agent === "product") {
          return {
            input: positionInput({ position: SENTINEL, reasoning: SENTINEL }),
            usage: zeroUsage
          };
        }
        return { input: positionInput(), usage: zeroUsage };
      }
    });

    const financePrompt = promptsByAgent.get("finance")!;
    expect(financePrompt).not.toContain(SENTINEL);
    // And the reverse direction, so the test does not pass by call ordering.
    expect(promptsByAgent.get("product")!).not.toContain("finance said");
  });

  test("agents are dispatched concurrently, not sequentially", async () => {
    // Sequential dispatch would let a later refactor slip a prior position into
    // a later prompt without the blindness test noticing.
    const started: AgentId[] = [];
    let releaseFirst: (() => void) | null = null;
    const firstGate = new Promise<void>((resolve) => {
      releaseFirst = resolve;
    });

    const pass = runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        started.push(args.agent);
        if (args.agent === "product") await firstGate;
        return { input: positionInput(), usage: zeroUsage };
      }
    });

    // Yield the microtask queue; both calls should already have started even
    // though the first one has not resolved.
    await Promise.resolve();
    await Promise.resolve();
    expect(started).toHaveLength(2);

    releaseFirst!();
    await pass;
  });

  test("each agent is asked the real question, not the raw request alone", async () => {
    const messages: string[] = [];
    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        messages.push(args.userMessage);
        return { input: positionInput(), usage: zeroUsage };
      }
    });
    for (const m of messages) {
      expect(m).toContain(realQuestion);
    }
  });

  test("each agent runs on its configured model", async () => {
    const models: string[] = [];
    await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        models.push(args.model);
        return { input: positionInput(), usage: zeroUsage };
      }
    });
    expect(models).toEqual([AGENT_MODEL, AGENT_MODEL]);
  });
});

describe("runIndependentPass — graceful degradation", () => {
  test("one agent throwing does not take down the run", async () => {
    const { results } = await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async (args) => {
        if (args.agent === "finance") throw new Error("upstream 529");
        return { input: positionInput(), usage: zeroUsage };
      }
    });

    const byAgent = new Map(results.map((r) => [r.agent, r]));
    expect(byAgent.get("product")!.position).toBeDefined();
    expect(byAgent.get("finance")!.position).toBeUndefined();
    expect(byAgent.get("finance")!.error).toMatch(/529/);
  });

  test("an unparseable position becomes an error entry, not a throw", async () => {
    const { results } = await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product"],
      call: async () => ({ input: { stance: "maybe" }, usage: zeroUsage })
    });
    expect(results[0].position).toBeUndefined();
    expect(results[0].error).toMatch(/stance/);
  });

  test("returns one result per requested agent, in request order", async () => {
    const { results } = await runIndependentPass({
      founder,
      rawRequest,
      realQuestion,
      agents: ["product", "finance"],
      call: async () => ({ input: positionInput(), usage: zeroUsage })
    });
    expect(results.map((r) => r.agent)).toEqual(["product", "finance"]);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyIndependentPass -v`
Expected: FAIL — cannot find module `../company/independentPass`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/independentPass.ts`:

```ts
import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller } from "./router";
import {
  AgentId,
  AgentPosition,
  Confidence,
  FounderContext,
  Stance,
  TokenUsage
} from "./types";

const STANCES: Stance[] = ["proceed", "proceed_with_conditions", "do_not_proceed"];

export const POSITION_TOOL = {
  name: "submit_position",
  description:
    "Submit your department's independent position on this decision. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      stance: {
        type: "string",
        enum: STANCES,
        description:
          "Machine-readable summary of your view. do_not_proceed only if you genuinely believe the founder should not do this; reservations are proceed_with_conditions."
      },
      position: { type: "string", description: "Your stance in 1-2 sentences." },
      reasoning: { type: "string", description: "Why, through your department's lens only." },
      evidence_needed: {
        type: "array",
        items: { type: "string" },
        description: "What would raise your confidence."
      },
      risks_i_own: {
        type: "array",
        items: { type: "string" },
        description: "Risks inside your remit, not someone else's."
      },
      confidence: {
        type: "integer",
        minimum: 1,
        maximum: 5,
        description: "At most 2 if you cannot name falsifying evidence."
      },
      cost_to_my_dept: {
        type: "string",
        description: "What your own recommendation costs YOUR department."
      },
      hard_blocker: {
        type: ["string", "null"],
        description:
          "Your single non-negotiable, or null. Use sparingly: this means 'I cannot accept this outcome under any framing', not 'I would prefer otherwise'."
      }
    },
    required: [
      "stance",
      "position",
      "reasoning",
      "confidence",
      "cost_to_my_dept",
      "hard_blocker"
    ],
    additionalProperties: false
  }
};

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : [];
}

function clampConfidence(value: unknown): Confidence {
  const n = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 3;
  return Math.min(5, Math.max(1, n)) as Confidence;
}

export function parsePositionToolInput(input: unknown): AgentPosition | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "position tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;

  const stance = raw.stance;
  if (typeof stance !== "string" || !(STANCES as string[]).includes(stance)) {
    return { error: `unknown stance: ${String(stance)}` };
  }
  if (typeof raw.position !== "string" || raw.position.trim().length === 0) {
    return { error: "position is required" };
  }

  // Models sometimes emit "" or "  " instead of null. An empty string must not
  // read as a hard blocker — that would fabricate a BLOCKER in phase 3.
  const blockerRaw = typeof raw.hard_blocker === "string" ? raw.hard_blocker.trim() : "";
  const hardBlocker = blockerRaw.length > 0 ? blockerRaw : null;

  return {
    stance: stance as Stance,
    position: raw.position.trim(),
    reasoning: typeof raw.reasoning === "string" ? raw.reasoning.trim() : "",
    evidence_needed: stringList(raw.evidence_needed),
    risks_i_own: stringList(raw.risks_i_own),
    confidence: clampConfidence(raw.confidence),
    cost_to_my_dept:
      typeof raw.cost_to_my_dept === "string" ? raw.cost_to_my_dept.trim() : "",
    hard_blocker: hardBlocker
  };
}

/**
 * The user message for Phase 2. Contains the request and the real question and
 * NOTHING derived from another agent — that omission is the entire point of
 * this phase (spec §2.2 Phase 2).
 */
const POSITION_INSTRUCTION = `Give your independent position on this decision.

You are answering at the same moment as the other departments and you cannot
see what any of them said. Do not speculate about their views or pre-emptively
concede to them. Answer only from your own department's lens.

THE REAL QUESTION AT STAKE:
<real_question>

Call submit_position.`;

export interface PassResult {
  agent: AgentId;
  position?: AgentPosition;
  error?: string;
  usage: TokenUsage;
  model: string;
}

export async function runIndependentPass(args: {
  founder: FounderContext;
  rawRequest: string;
  realQuestion: string;
  agents: AgentId[];
  call: AgentCaller;
}): Promise<{ results: PassResult[] }> {
  const userMessage = POSITION_INSTRUCTION.replace(
    "<real_question>",
    args.realQuestion.trim()
  );

  // allSettled, not all: one department failing must not take down the room.
  const settled = await Promise.allSettled(
    args.agents.map(async (agent): Promise<PassResult> => {
      const model = AGENT_DEFS[agent].model;
      const { input, usage } = await args.call({
        agent,
        model,
        system: composeAgentSystem({
          agent,
          founder: args.founder,
          rawRequest: args.rawRequest
        }),
        userMessage,
        tool: POSITION_TOOL,
        toolName: POSITION_TOOL.name
      });

      const parsed = parsePositionToolInput(input);
      if ("error" in parsed) {
        return { agent, error: parsed.error, usage, model };
      }
      return { agent, position: parsed, usage, model };
    })
  );

  const zero: TokenUsage = { input: 0, output: 0, cache_read: 0 };
  const results: PassResult[] = settled.map((outcome, i) => {
    if (outcome.status === "fulfilled") return outcome.value;
    return {
      agent: args.agents[i],
      error: String(outcome.reason),
      usage: zero,
      model: AGENT_DEFS[args.agents[i]].model
    };
  });

  return { results };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyIndependentPass -v && npx tsc --noEmit`
Expected: all PASS, including both mutual-blindness tests.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/independentPass.ts functions/src/__tests__/companyIndependentPass.test.ts
git commit -m "feat(company): phase 2 mutually-blind parallel independent pass"
```

---

## Task 9: Negotiation loop (Phase 4)

**Files:**
- Create: `functions/src/company/negotiation.ts`
- Test: `functions/src/__tests__/companyNegotiation.test.ts`

**Interfaces:**
- Consumes: `AgentCaller` from `./router`; `composeAgentSystem`, `AGENT_DEFS` from `./registry`; `AgentId`, `AgentPosition`, `Conflict`, `NegotiationRound`, `NegotiationTurn`, `FounderContext`, `TokenUsage` from `./types`.
- Produces:
  - `MAX_NEGOTIATION_ROUNDS = 2`
  - `NEGOTIATION_TOOL`
  - `parseNegotiationToolInput(input: unknown): NegotiationTurn["proposal"] extends never ? never : Omit<NegotiationTurn, "agent"> | { error: string }`
  - `conflictingAgents(conflicts: Conflict[]): AgentId[]`
  - `isResolved(rounds: NegotiationRound[]): boolean`
  - `runNegotiation(args: { founder: FounderContext; rawRequest: string; realQuestion: string; positions: Partial<Record<AgentId, AgentPosition>>; conflicts: Conflict[]; call: AgentCaller }): Promise<{ rounds: NegotiationRound[]; unresolved: boolean; usages: Array<{ agent: AgentId; model: string; usage: TokenUsage }> }>`

Only conflicting agents participate. This is the one phase where an agent legitimately sees another agent's output — the opposing position is the input. Two hard rules from spec §2.2 Phase 4: the cap is 2 rounds and is not configurable, and `unresolved` is a valid return rather than a failure.

`isResolved` requires **every** participant in the final round to report `resolved: true`. One side conceding while the other holds is not resolution.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyNegotiation.test.ts`:

```ts
import {
  MAX_NEGOTIATION_ROUNDS,
  NEGOTIATION_TOOL,
  parseNegotiationToolInput,
  conflictingAgents,
  isResolved,
  runNegotiation
} from "../company/negotiation";
import { AgentId, AgentPosition, Conflict, FounderContext, TokenUsage } from "../company/types";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const rawRequest = "Should I scale this acquisition channel?";
const realQuestion = "Can we afford to buy information about this channel?";
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

function pos(stance: AgentPosition["stance"], hardBlocker: string | null = null): AgentPosition {
  return {
    stance,
    position: `stance is ${stance}`,
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 4,
    cost_to_my_dept: "c",
    hard_blocker: hardBlocker
  };
}

const positions: Partial<Record<AgentId, AgentPosition>> = {
  product: pos("proceed"),
  finance: pos("do_not_proceed", "CAC is $19 against an LTV of $15.")
};
const blockerConflict: Conflict[] = [
  { a: "product", b: "finance", kind: "BLOCKER", reason: "finance raised a hard blocker" }
];

function turnInput(overrides: Record<string, unknown> = {}) {
  return {
    precise_disagreement: "Whether LTV is knowable before spending.",
    what_would_change_my_mind: "Month-2 retention above 35%.",
    proposal: "Cap the test at $1.6k and stop at week 8.",
    resolved: false,
    ...overrides
  };
}

describe("cap", () => {
  test("is hard-coded at 2 rounds", () => {
    expect(MAX_NEGOTIATION_ROUNDS).toBe(2);
  });
});

describe("NEGOTIATION_TOOL", () => {
  test("requires a falsification condition, not just a rebuttal", () => {
    const required = NEGOTIATION_TOOL.input_schema.required as string[];
    expect(required).toContain("what_would_change_my_mind");
    expect(required).toContain("precise_disagreement");
    expect(required).toContain("resolved");
  });
});

describe("parseNegotiationToolInput", () => {
  test("accepts a well-formed turn", () => {
    const result = parseNegotiationToolInput(turnInput());
    expect("error" in result).toBe(false);
    expect((result as any).resolved).toBe(false);
  });

  test("rejects a turn with no falsification condition", () => {
    // Spec: a concession must carry a stated reason. No falsifier, no turn.
    expect(parseNegotiationToolInput(turnInput({ what_would_change_my_mind: "  " }))).toEqual({
      error: expect.stringMatching(/what_would_change_my_mind/)
    });
  });

  test("treats a non-boolean resolved as not resolved", () => {
    const result = parseNegotiationToolInput(turnInput({ resolved: "yes" })) as any;
    expect(result.resolved).toBe(false);
  });
});

describe("conflictingAgents", () => {
  test("returns only agents in a CONFLICT or BLOCKER pair", () => {
    expect(conflictingAgents(blockerConflict).sort()).toEqual(["finance", "product"]);
  });

  test("excludes agents whose only relationship is TENSION or ALIGNED", () => {
    expect(
      conflictingAgents([
        { a: "product", b: "finance", kind: "TENSION", reason: "" }
      ])
    ).toEqual([]);
  });

  test("de-duplicates an agent appearing in several conflicts", () => {
    const many: Conflict[] = [
      { a: "product", b: "finance", kind: "CONFLICT", reason: "" },
      { a: "product", b: "finance", kind: "BLOCKER", reason: "" }
    ];
    expect(conflictingAgents(many).sort()).toEqual(["finance", "product"]);
  });
});

describe("isResolved", () => {
  const turn = (agent: AgentId, resolved: boolean): NegotiationTurn => ({
    agent,
    precise_disagreement: "d",
    what_would_change_my_mind: "w",
    proposal: "p",
    resolved
  });

  test("true only when every participant in the last round agrees", () => {
    expect(
      isResolved([{ round: 1, turns: [turn("product", true), turn("finance", true)] }])
    ).toBe(true);
  });

  test("false when one side concedes and the other holds", () => {
    // Consensus by capitulation is a failure of this system, not a success.
    expect(
      isResolved([{ round: 1, turns: [turn("product", true), turn("finance", false)] }])
    ).toBe(false);
  });

  test("false for an empty round list", () => {
    expect(isResolved([])).toBe(false);
  });

  test("judges only the final round", () => {
    expect(
      isResolved([
        { round: 1, turns: [turn("product", false), turn("finance", false)] },
        { round: 2, turns: [turn("product", true), turn("finance", true)] }
      ])
    ).toBe(true);
  });
});

describe("runNegotiation", () => {
  test("stops after round 1 when both sides resolve", async () => {
    let calls = 0;
    const { rounds, unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async () => {
        calls++;
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    expect(rounds).toHaveLength(1);
    expect(unresolved).toBe(false);
    expect(calls).toBe(2); // one per conflicting agent, round 1 only
  });

  test("returns unresolved after exactly 2 rounds when nobody yields", async () => {
    let calls = 0;
    const { rounds, unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async () => {
        calls++;
        return { input: turnInput({ resolved: false }), usage: zeroUsage };
      }
    });
    expect(rounds).toHaveLength(MAX_NEGOTIATION_ROUNDS);
    expect(unresolved).toBe(true);
    expect(calls).toBe(4); // 2 agents x 2 rounds — never a third round
  });

  test("shows each agent the opposing position", async () => {
    const prompts = new Map<AgentId, string>();
    await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async (args) => {
        if (!prompts.has(args.agent)) prompts.set(args.agent, args.userMessage);
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    // This is the one phase where cross-visibility is correct and required.
    expect(prompts.get("product")!).toContain(positions.finance!.position);
    expect(prompts.get("finance")!).toContain(positions.product!.position);
  });

  test("surfaces the opposing hard blocker verbatim", async () => {
    let productPrompt = "";
    await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async (args) => {
        if (args.agent === "product") productPrompt = args.userMessage;
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    expect(productPrompt).toContain("CAC is $19 against an LTV of $15.");
  });

  test("returns no rounds and unresolved=false when there is nothing to debate", async () => {
    let calls = 0;
    const { rounds, unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: [{ a: "product", b: "finance", kind: "ALIGNED", reason: "" }],
      call: async () => {
        calls++;
        return { input: turnInput(), usage: zeroUsage };
      }
    });
    expect(rounds).toEqual([]);
    expect(unresolved).toBe(false);
    expect(calls).toBe(0);
  });

  test("a failing agent turn leaves the round unresolved rather than throwing", async () => {
    const { unresolved } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async (args) => {
        if (args.agent === "finance") throw new Error("upstream 529");
        return { input: turnInput({ resolved: true }), usage: zeroUsage };
      }
    });
    expect(unresolved).toBe(true);
  });

  test("reports usage per agent per round for metering", async () => {
    const { usages } = await runNegotiation({
      founder,
      rawRequest,
      realQuestion,
      positions,
      conflicts: blockerConflict,
      call: async () => ({
        input: turnInput({ resolved: true }),
        usage: { input: 500, output: 120, cache_read: 900 }
      })
    });
    expect(usages).toHaveLength(2);
    expect(usages[0].usage.output).toBe(120);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyNegotiation -v`
Expected: FAIL — cannot find module `../company/negotiation`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/negotiation.ts`:

```ts
import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller } from "./router";
import {
  AgentId,
  AgentPosition,
  Conflict,
  FounderContext,
  NegotiationRound,
  NegotiationTurn,
  TokenUsage
} from "./types";

/**
 * Hard cap, not a request parameter (spec §2.2 Phase 4). Unbounded debate is
 * where cost explodes and where agents drift toward false consensus.
 */
export const MAX_NEGOTIATION_ROUNDS = 2;

export const NEGOTIATION_TOOL = {
  name: "submit_negotiation_turn",
  description:
    "Respond to the opposing department's position. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      precise_disagreement: {
        type: "string",
        description:
          "The exact point of disagreement. Do not drift to a different objection than the one on the table."
      },
      what_would_change_my_mind: {
        type: "string",
        description:
          "A falsifiable condition. Name the observation that would move you, not a sentiment."
      },
      proposal: {
        type: "string",
        description:
          "An option that preserves both sides' hard blockers. If none exists, say plainly that this is an unresolvable trade-off the founder must choose."
      },
      resolved: {
        type: "boolean",
        description:
          "True only if you genuinely believe the trade-off is now resolvable. Conceding to keep the peace is forbidden."
      }
    },
    required: [
      "precise_disagreement",
      "what_would_change_my_mind",
      "proposal",
      "resolved"
    ],
    additionalProperties: false
  }
};

export function parseNegotiationToolInput(
  input: unknown
): Omit<NegotiationTurn, "agent"> | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "negotiation tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;

  const disagreement =
    typeof raw.precise_disagreement === "string" ? raw.precise_disagreement.trim() : "";
  if (disagreement.length === 0) {
    return { error: "precise_disagreement is required" };
  }

  const falsifier =
    typeof raw.what_would_change_my_mind === "string"
      ? raw.what_would_change_my_mind.trim()
      : "";
  if (falsifier.length === 0) {
    // Without a falsifier there is no way for evidence to settle this, which
    // makes the turn noise rather than negotiation.
    return { error: "what_would_change_my_mind is required" };
  }

  return {
    precise_disagreement: disagreement,
    what_would_change_my_mind: falsifier,
    proposal: typeof raw.proposal === "string" ? raw.proposal.trim() : "",
    // Anything that is not literally true counts as unresolved.
    resolved: raw.resolved === true
  };
}

export function conflictingAgents(conflicts: Conflict[]): AgentId[] {
  const out: AgentId[] = [];
  for (const c of conflicts) {
    if (c.kind !== "CONFLICT" && c.kind !== "BLOCKER") continue;
    for (const agent of [c.a, c.b]) {
      if (!out.includes(agent)) out.push(agent);
    }
  }
  return out;
}

/** Resolution requires unanimity in the final round — one holdout means no. */
export function isResolved(rounds: NegotiationRound[]): boolean {
  const last = rounds[rounds.length - 1];
  if (!last || last.turns.length === 0) return false;
  return last.turns.every((t) => t.resolved);
}

function renderOpposing(
  self: AgentId,
  participants: AgentId[],
  positions: Partial<Record<AgentId, AgentPosition>>
): string {
  return participants
    .filter((a) => a !== self)
    .map((a) => {
      const p = positions[a];
      if (!p) return `${a}: (no position on record)`;
      const blocker = p.hard_blocker
        ? `\n   HARD BLOCKER: ${p.hard_blocker}`
        : "\n   No hard blocker.";
      return `${a} (stance: ${p.stance}, confidence ${p.confidence}/5):\n   ${p.position}\n   Reasoning: ${p.reasoning}${blocker}`;
    })
    .join("\n\n");
}

const NEGOTIATION_INSTRUCTION = `You are now in a bounded negotiation. Round <round> of ${MAX_NEGOTIATION_ROUNDS}.

THE REAL QUESTION AT STAKE:
<real_question>

THE OPPOSING POSITION:
<opposing>

<prior>Do all four of these:
1. State the precise point of disagreement. Do not drift to a different objection.
2. State what would change your mind, as a falsifiable condition.
3. Propose an option that preserves both hard blockers.
4. If no such option exists, say plainly that this is an unresolvable trade-off
   and the founder must choose.

Conceding to keep the peace is forbidden. If you concede, the concession must
carry a stated reason. Returning "unresolved" is a valid and useful outcome.

Call submit_negotiation_turn.`;

export async function runNegotiation(args: {
  founder: FounderContext;
  rawRequest: string;
  realQuestion: string;
  positions: Partial<Record<AgentId, AgentPosition>>;
  conflicts: Conflict[];
  call: AgentCaller;
}): Promise<{
  rounds: NegotiationRound[];
  unresolved: boolean;
  usages: Array<{ agent: AgentId; model: string; usage: TokenUsage }>;
}> {
  const participants = conflictingAgents(args.conflicts);
  // Spec §2.2 Phase 3: never debate when there is nothing to debate.
  if (participants.length < 2) {
    return { rounds: [], unresolved: false, usages: [] };
  }

  const rounds: NegotiationRound[] = [];
  const usages: Array<{ agent: AgentId; model: string; usage: TokenUsage }> = [];

  for (let round = 1; round <= MAX_NEGOTIATION_ROUNDS; round++) {
    const prior =
      rounds.length === 0
        ? ""
        : `WHAT WAS SAID IN THE PREVIOUS ROUND:\n${rounds[rounds.length - 1].turns
            .map(
              (t) =>
                `${t.agent}: ${t.precise_disagreement} — would change their mind if: ${t.what_would_change_my_mind}. Proposal: ${t.proposal}`
            )
            .join("\n")}\n\n`;

    const settled = await Promise.allSettled(
      participants.map(async (agent): Promise<NegotiationTurn> => {
        const model = AGENT_DEFS[agent].model;
        const { input, usage } = await args.call({
          agent,
          model,
          system: composeAgentSystem({
            agent,
            founder: args.founder,
            rawRequest: args.rawRequest
          }),
          userMessage: NEGOTIATION_INSTRUCTION.replace("<round>", String(round))
            .replace("<real_question>", args.realQuestion.trim())
            .replace("<opposing>", renderOpposing(agent, participants, args.positions))
            .replace("<prior>", prior),
          tool: NEGOTIATION_TOOL,
          toolName: NEGOTIATION_TOOL.name
        });
        usages.push({ agent, model, usage });

        const parsed = parseNegotiationToolInput(input);
        if ("error" in parsed) {
          // An unparseable turn cannot count as resolution.
          return {
            agent,
            precise_disagreement: `(unusable turn: ${parsed.error})`,
            what_would_change_my_mind: "",
            proposal: "",
            resolved: false
          };
        }
        return { agent, ...parsed };
      })
    );

    const turns: NegotiationTurn[] = settled.map((outcome, i) =>
      outcome.status === "fulfilled"
        ? outcome.value
        : {
            agent: participants[i],
            precise_disagreement: `(turn failed: ${String(outcome.reason)})`,
            what_would_change_my_mind: "",
            proposal: "",
            resolved: false
          }
    );

    rounds.push({ round: round as 1 | 2, turns });
    if (isResolved(rounds)) break;
  }

  return { rounds, unresolved: !isResolved(rounds), usages };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyNegotiation -v && npx tsc --noEmit`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/negotiation.ts functions/src/__tests__/companyNegotiation.test.ts
git commit -m "feat(company): phase 4 negotiation with 2-round cap and unresolved outcome"
```

---

## Task 10: Devil's advocate trigger

**Files:**
- Create: `functions/src/company/devilsAdvocate.ts`
- Test: `functions/src/__tests__/companyDevilsAdvocate.test.ts`

**Interfaces:**
- Consumes: `AgentCaller` from `./router`; `composeAgentSystem`, `AGENT_DEFS` from `./registry`; `AgentId`, `AgentPosition`, `Conflict`, `DevilsAdvocateVerdict`, `FounderContext`, `TokenUsage` from `./types`.
- Produces:
  - `DEVILS_ADVOCATE_TOOL`
  - `parseDevilsAdvocateInput(input: unknown): DevilsAdvocateVerdict | { error: string }`
  - `shouldInvokeDevilsAdvocate(args: { positions: Partial<Record<AgentId, AgentPosition>>; conflicts: Conflict[]; founderRequested?: boolean }): boolean`
  - `runDevilsAdvocate(args: { founder: FounderContext; rawRequest: string; realQuestion: string; positions: Partial<Record<AgentId, AgentPosition>>; call: AgentCaller }): Promise<{ verdict: DevilsAdvocateVerdict; model: string; usage: TokenUsage }>`

`shouldInvokeDevilsAdvocate` is pure and is the false-consensus countermeasure. Spec §3.8 triggers, adapted to a 2-department roster: with only two department agents, "three or more align" cannot happen — so the MVP trigger is **all present departments aligned** (i.e. no CONFLICT and no BLOCKER) **with high confidence and thin evidence**, or an explicit founder request.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyDevilsAdvocate.test.ts`:

```ts
import {
  DEVILS_ADVOCATE_TOOL,
  parseDevilsAdvocateInput,
  shouldInvokeDevilsAdvocate,
  runDevilsAdvocate
} from "../company/devilsAdvocate";
import { AgentId, AgentPosition, Conflict, FounderContext, TokenUsage } from "../company/types";
import { SYNTHESIS_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

function pos(overrides: Partial<AgentPosition> = {}): AgentPosition {
  return {
    stance: "proceed",
    position: "p",
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 5,
    cost_to_my_dept: "c",
    hard_blocker: null,
    ...overrides
  };
}

const aligned: Conflict[] = [{ a: "product", b: "finance", kind: "ALIGNED", reason: "" }];
const conflicted: Conflict[] = [{ a: "product", b: "finance", kind: "CONFLICT", reason: "" }];

function verdictInput(overrides: Record<string, unknown> = {}) {
  return {
    load_bearing_assumption: "That the beta cohort represents the paying market.",
    how_it_could_be_false: "The beta was recruited from the founder's own network.",
    cheapest_test: "Put the price in front of 20 strangers from a cold channel.",
    failure_post_mortem:
      "Twelve months on, seats sold to nobody outside the founder's network and the pricing page never converted a cold visitor.",
    who_is_not_in_the_room: "The user who churns silently without ever complaining.",
    objections: ["The sample is the founder's friends.", "No cold-channel evidence exists."],
    plan_is_sound: false,
    ...overrides
  };
}

describe("shouldInvokeDevilsAdvocate", () => {
  test("fires when the room agrees with high confidence and thin evidence", () => {
    // The whole point: agreement is when nobody is checking the premise.
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos({ confidence: 5 }), finance: pos({ confidence: 4 }) },
        conflicts: aligned
      })
    ).toBe(true);
  });

  test("does not fire when the departments already disagree", () => {
    // A live conflict already gives the founder the tension they need.
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos(), finance: pos({ stance: "do_not_proceed" }) },
        conflicts: conflicted
      })
    ).toBe(false);
  });

  test("does not fire when the room agrees but confidence is low", () => {
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos({ confidence: 2 }), finance: pos({ confidence: 2 }) },
        conflicts: aligned
      })
    ).toBe(false);
  });

  test("does not fire when agreement rests on named evidence", () => {
    expect(
      shouldInvokeDevilsAdvocate({
        positions: {
          product: pos({ confidence: 5, evidence_needed: ["cold-channel conversion"] }),
          finance: pos({ confidence: 5, evidence_needed: ["month-2 retention"] })
        },
        conflicts: aligned
      })
    ).toBe(false);
  });

  test("always fires when the founder explicitly asks for a stress test", () => {
    expect(
      shouldInvokeDevilsAdvocate({
        positions: { product: pos(), finance: pos({ stance: "do_not_proceed" }) },
        conflicts: conflicted,
        founderRequested: true
      })
    ).toBe(true);
  });

  test("does not fire with fewer than two positions on record", () => {
    expect(shouldInvokeDevilsAdvocate({ positions: { product: pos() }, conflicts: [] })).toBe(false);
  });
});

describe("parseDevilsAdvocateInput", () => {
  test("accepts a well-formed verdict", () => {
    const result = parseDevilsAdvocateInput(verdictInput());
    expect("error" in result).toBe(false);
    expect((result as any).objections).toHaveLength(2);
  });

  test("requires a load-bearing assumption", () => {
    expect(parseDevilsAdvocateInput(verdictInput({ load_bearing_assumption: " " }))).toEqual({
      error: expect.stringMatching(/load_bearing_assumption/)
    });
  });

  test("requires a cheapest test — every objection must be actionable", () => {
    expect(parseDevilsAdvocateInput(verdictInput({ cheapest_test: "" }))).toEqual({
      error: expect.stringMatching(/cheapest_test/)
    });
  });

  test("accepts a sound-plan verdict with no objections", () => {
    // Spec §3.8: a red team that always finds fatal flaws is noise.
    const result = parseDevilsAdvocateInput(
      verdictInput({ plan_is_sound: true, objections: [] })
    ) as any;
    expect(result.plan_is_sound).toBe(true);
    expect(result.objections).toEqual([]);
  });
});

describe("runDevilsAdvocate", () => {
  test("runs on the top tier with the red-team role prompt", async () => {
    const seen: any[] = [];
    await runDevilsAdvocate({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: { product: pos(), finance: pos() },
      call: async (args) => {
        seen.push(args);
        return { input: verdictInput(), usage: zeroUsage };
      }
    });
    expect(seen[0].agent).toBe("devils_advocate");
    expect(seen[0].model).toBe(SYNTHESIS_MODEL);
  });

  test("is shown every position so it can steel-man before attacking", async () => {
    let prompt = "";
    await runDevilsAdvocate({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: {
        product: pos({ position: "PRODUCT_SAYS_THIS" }),
        finance: pos({ position: "FINANCE_SAYS_THIS" })
      },
      call: async (args) => {
        prompt = args.userMessage;
        return { input: verdictInput(), usage: zeroUsage };
      }
    });
    expect(prompt).toContain("PRODUCT_SAYS_THIS");
    expect(prompt).toContain("FINANCE_SAYS_THIS");
  });

  test("throws with a descriptive message on an unusable verdict", async () => {
    await expect(
      runDevilsAdvocate({
        founder,
        rawRequest: "x",
        realQuestion: "q",
        positions: { product: pos() },
        call: async () => ({ input: { objections: [] }, usage: zeroUsage })
      })
    ).rejects.toThrow(/devils_advocate/i);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyDevilsAdvocate -v`
Expected: FAIL — cannot find module `../company/devilsAdvocate`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/devilsAdvocate.ts`:

```ts
import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller } from "./router";
import {
  AgentId,
  AgentPosition,
  Conflict,
  DevilsAdvocateVerdict,
  FounderContext,
  TokenUsage
} from "./types";

const HIGH_CONFIDENCE = 4;

export const DEVILS_ADVOCATE_TOOL = {
  name: "submit_red_team",
  description:
    "Submit your red-team analysis. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      load_bearing_assumption: {
        type: "string",
        description: "The one belief that, if false, collapses everything."
      },
      how_it_could_be_false: { type: "string" },
      cheapest_test: {
        type: "string",
        description: "The cheapest way to find out quickly. Every objection must be actionable."
      },
      failure_post_mortem: {
        type: "string",
        description:
          "It is twelve months from now and this was a clear mistake. Two sentences on why — the actual mechanism, not 'the market changed'."
      },
      who_is_not_in_the_room: {
        type: "string",
        description: "Whose interest has no representative here."
      },
      objections: {
        type: "array",
        items: { type: "string" },
        description: "Ranked. Lead with the one that would change the decision."
      },
      plan_is_sound: {
        type: "boolean",
        description:
          "True if the plan is genuinely sound. A red team that always finds fatal flaws is noise."
      }
    },
    required: [
      "load_bearing_assumption",
      "how_it_could_be_false",
      "cheapest_test",
      "failure_post_mortem",
      "who_is_not_in_the_room",
      "plan_is_sound"
    ],
    additionalProperties: false
  }
};

export function parseDevilsAdvocateInput(
  input: unknown
): DevilsAdvocateVerdict | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "red team tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;
  const str = (key: string): string =>
    typeof raw[key] === "string" ? (raw[key] as string).trim() : "";

  for (const required of ["load_bearing_assumption", "cheapest_test", "failure_post_mortem"]) {
    if (str(required).length === 0) {
      return { error: `${required} is required` };
    }
  }

  return {
    load_bearing_assumption: str("load_bearing_assumption"),
    how_it_could_be_false: str("how_it_could_be_false"),
    cheapest_test: str("cheapest_test"),
    failure_post_mortem: str("failure_post_mortem"),
    who_is_not_in_the_room: str("who_is_not_in_the_room"),
    objections: Array.isArray(raw.objections)
      ? raw.objections.filter((o): o is string => typeof o === "string")
      : [],
    plan_is_sound: raw.plan_is_sound === true
  };
}

/**
 * The false-consensus countermeasure (spec §3.8). Pure so it can be reasoned
 * about and tested without a model call.
 *
 * The spec's primary trigger is "three or more departments align quickly", which
 * cannot occur with a 2-department MVP roster. The equivalent signal here is:
 * the whole room agrees, confidence is high, and nobody named the evidence their
 * confidence rests on. That combination is exactly when nobody is checking the
 * premise — which is what the red team exists for.
 */
export function shouldInvokeDevilsAdvocate(args: {
  positions: Partial<Record<AgentId, AgentPosition>>;
  conflicts: Conflict[];
  founderRequested?: boolean;
}): boolean {
  if (args.founderRequested === true) return true;

  const present = Object.values(args.positions).filter(
    (p): p is AgentPosition => p !== undefined
  );
  if (present.length < 2) return false;

  const hasLiveDisagreement = args.conflicts.some(
    (c) => c.kind === "CONFLICT" || c.kind === "BLOCKER"
  );
  if (hasLiveDisagreement) return false;

  const allConfident = present.every((p) => p.confidence >= HIGH_CONFIDENCE);
  const evidenceIsThin = present.every((p) => p.evidence_needed.length === 0);
  return allConfident && evidenceIsThin;
}

const RED_TEAM_INSTRUCTION = `The room has reached a view. Stress-test it.

THE REAL QUESTION AT STAKE:
<real_question>

WHAT EACH DEPARTMENT SAID:
<positions>

Work through all four parts of your method: find the load-bearing assumption,
write the failure post-mortem, attack the strongest version of the
recommendation rather than the weakest, and name who is not in the room.

If the plan is genuinely sound, say so plainly and name the one thing you would
still monitor. Do not be contrarian for its own sake.

Call submit_red_team.`;

function renderPositions(positions: Partial<Record<AgentId, AgentPosition>>): string {
  return Object.entries(positions)
    .filter(([, p]) => p !== undefined)
    .map(([agent, p]) => {
      const position = p as AgentPosition;
      const blocker = position.hard_blocker
        ? `\n   HARD BLOCKER: ${position.hard_blocker}`
        : "";
      return `${agent} (stance: ${position.stance}, confidence ${position.confidence}/5):\n   ${position.position}\n   Reasoning: ${position.reasoning}\n   Cost to their own department: ${position.cost_to_my_dept}${blocker}`;
    })
    .join("\n\n");
}

export async function runDevilsAdvocate(args: {
  founder: FounderContext;
  rawRequest: string;
  realQuestion: string;
  positions: Partial<Record<AgentId, AgentPosition>>;
  call: AgentCaller;
}): Promise<{ verdict: DevilsAdvocateVerdict; model: string; usage: TokenUsage }> {
  const model = AGENT_DEFS.devils_advocate.model;
  const { input, usage } = await args.call({
    agent: "devils_advocate",
    model,
    system: composeAgentSystem({
      agent: "devils_advocate",
      founder: args.founder,
      rawRequest: args.rawRequest
    }),
    userMessage: RED_TEAM_INSTRUCTION.replace(
      "<real_question>",
      args.realQuestion.trim()
    ).replace("<positions>", renderPositions(args.positions)),
    tool: DEVILS_ADVOCATE_TOOL,
    toolName: DEVILS_ADVOCATE_TOOL.name
  });

  const parsed = parseDevilsAdvocateInput(input);
  if ("error" in parsed) {
    throw new Error(`unusable verdict from devils_advocate: ${parsed.error}`);
  }
  return { verdict: parsed, model, usage };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyDevilsAdvocate -v && npx tsc --noEmit`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/devilsAdvocate.ts functions/src/__tests__/companyDevilsAdvocate.test.ts
git commit -m "feat(company): devil's advocate trigger as false-consensus countermeasure"
```

---

## Task 11: Synthesis (Phase 5)

**Files:**
- Create: `functions/src/company/synthesis.ts`
- Test: `functions/src/__tests__/companySynthesis.test.ts`

**Interfaces:**
- Consumes: `AgentCaller` from `./router`; `composeAgentSystem`, `AGENT_DEFS` from `./registry`; `AgentId`, `AgentPosition`, `Conflict`, `NegotiationRound`, `DevilsAdvocateVerdict`, `DecisionBrief`, `FounderContext`, `TokenUsage` from `./types`.
- Produces:
  - `BRIEF_TOOL`
  - `parseBriefToolInput(input: unknown): DecisionBrief | { error: string }`
  - `briefOmitsDissent(brief: DecisionBrief, conflicts: Conflict[]): boolean`
  - `runSynthesis(args: { founder: FounderContext; rawRequest: string; realQuestion: string; positions: Partial<Record<AgentId, AgentPosition>>; conflicts: Conflict[]; negotiation: NegotiationRound[]; devilsAdvocate: DevilsAdvocateVerdict | null; unresolved: boolean; call: AgentCaller }): Promise<{ brief: DecisionBrief; model: string; usage: TokenUsage }>`

`briefOmitsDissent` is the guard that makes spec's TASK 9 assertion mechanical: when a conflict existed, the brief must not come back with an empty `the_real_disagreement`. Burying dissent is the failure mode the whole feature exists to prevent, so it is checked in code rather than trusted to the prompt.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companySynthesis.test.ts`:

```ts
import {
  BRIEF_TOOL,
  parseBriefToolInput,
  briefOmitsDissent,
  runSynthesis
} from "../company/synthesis";
import { AgentPosition, Conflict, DecisionBrief, FounderContext, TokenUsage } from "../company/types";
import { SYNTHESIS_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue, 4 months runway.",
  constraints: ["Cannot hire."],
  language: "en"
};
const zeroUsage: TokenUsage = { input: 0, output: 0, cache_read: 0 };

function pos(overrides: Partial<AgentPosition> = {}): AgentPosition {
  return {
    stance: "proceed",
    position: "p",
    reasoning: "r",
    evidence_needed: [],
    risks_i_own: [],
    confidence: 4,
    cost_to_my_dept: "c",
    hard_blocker: null,
    ...overrides
  };
}

const conflicted: Conflict[] = [
  { a: "product", b: "finance", kind: "BLOCKER", reason: "finance raised a hard blocker" }
];

function briefInput(overrides: Record<string, unknown> = {}) {
  return {
    recommendation: "Run a capped 8-week test at $1.6k before committing further.",
    confidence: 3,
    confidence_reason: "The channel has never run a full cycle, so LTV is a guess.",
    the_real_disagreement:
      "Finance: CAC is $19 against a $15 LTV, so scaling loses money faster. Product: we have not run a full cycle, so blocking now means never learning which channels work.",
    tradeoff_founder_must_own:
      "Spend $1.6k to buy information, or preserve three months of runway and accept not knowing.",
    kill_criteria: ["Month-2 retention below 35%", "CAC still above $19 at week 8"],
    next_action: { action: "Cap the channel test at $1.6k and instrument week-8 LTV", owner: "founder" },
    what_we_dont_know: "Real LTV for this channel — no cohort has completed a full cycle.",
    unresolved: true,
    ...overrides
  };
}

describe("BRIEF_TOOL", () => {
  test("requires all six components from spec §2.2 Phase 5", () => {
    const required = BRIEF_TOOL.input_schema.required as string[];
    for (const field of [
      "recommendation",
      "the_real_disagreement",
      "tradeoff_founder_must_own",
      "kill_criteria",
      "next_action",
      "what_we_dont_know"
    ]) {
      expect(required).toContain(field);
    }
  });
});

describe("parseBriefToolInput", () => {
  test("accepts a well-formed brief", () => {
    const result = parseBriefToolInput(briefInput());
    expect("error" in result).toBe(false);
    expect((result as any).unresolved).toBe(true);
  });

  test("rejects a brief missing the trade-off the founder must own", () => {
    // Spec forbids ending on "it depends on your priorities".
    expect(parseBriefToolInput(briefInput({ tradeoff_founder_must_own: "  " }))).toEqual({
      error: expect.stringMatching(/tradeoff_founder_must_own/)
    });
  });

  test("rejects a brief with no kill criteria", () => {
    expect(parseBriefToolInput(briefInput({ kill_criteria: [] }))).toEqual({
      error: expect.stringMatching(/kill_criteria/)
    });
  });

  test("rejects a next_action with no owner", () => {
    expect(
      parseBriefToolInput(briefInput({ next_action: { action: "do it", owner: "" } }))
    ).toEqual({ error: expect.stringMatching(/owner/) });
  });

  test("clamps confidence into 1..5", () => {
    expect((parseBriefToolInput(briefInput({ confidence: 99 })) as any).confidence).toBe(5);
  });
});

describe("briefOmitsDissent", () => {
  const brief = (overrides: Partial<DecisionBrief> = {}): DecisionBrief =>
    ({ ...(parseBriefToolInput(briefInput()) as DecisionBrief), ...overrides });

  test("true when a conflict existed but the brief records no disagreement", () => {
    // The exact failure the feature exists to prevent.
    expect(briefOmitsDissent(brief({ the_real_disagreement: "" }), conflicted)).toBe(true);
  });

  test("true when the brief hand-waves the disagreement away", () => {
    expect(
      briefOmitsDissent(brief({ the_real_disagreement: "Everyone agreed." }), conflicted)
    ).toBe(true);
  });

  test("false when the brief names both sides", () => {
    expect(briefOmitsDissent(brief(), conflicted)).toBe(false);
  });

  test("false when there was no conflict to report", () => {
    expect(
      briefOmitsDissent(brief({ the_real_disagreement: "" }), [
        { a: "product", b: "finance", kind: "ALIGNED", reason: "" }
      ])
    ).toBe(false);
  });
});

describe("runSynthesis", () => {
  test("runs chief_of_staff on the top tier", async () => {
    const seen: any[] = [];
    await runSynthesis({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: { product: pos(), finance: pos() },
      conflicts: conflicted,
      negotiation: [],
      devilsAdvocate: null,
      unresolved: true,
      call: async (args) => {
        seen.push(args);
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(seen[0].agent).toBe("chief_of_staff");
    expect(seen[0].model).toBe(SYNTHESIS_MODEL);
  });

  test("passes both positions verbatim so dissent can be quoted", async () => {
    let prompt = "";
    await runSynthesis({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: {
        product: pos({ position: "PRODUCT_VERBATIM" }),
        finance: pos({ position: "FINANCE_VERBATIM", hard_blocker: "BLOCKER_VERBATIM" })
      },
      conflicts: conflicted,
      negotiation: [],
      devilsAdvocate: null,
      unresolved: true,
      call: async (args) => {
        prompt = args.userMessage;
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(prompt).toContain("PRODUCT_VERBATIM");
    expect(prompt).toContain("FINANCE_VERBATIM");
    expect(prompt).toContain("BLOCKER_VERBATIM");
  });

  test("tells the synthesiser when the negotiation did not resolve", async () => {
    let prompt = "";
    await runSynthesis({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: { product: pos(), finance: pos() },
      conflicts: conflicted,
      negotiation: [],
      devilsAdvocate: null,
      unresolved: true,
      call: async (args) => {
        prompt = args.userMessage;
        return { input: briefInput(), usage: zeroUsage };
      }
    });
    expect(prompt).toMatch(/unresolved/i);
  });

  test("forces unresolved=true on the brief when negotiation did not resolve", async () => {
    // The model must not be able to paper over an unresolved trade-off.
    const { brief } = await runSynthesis({
      founder,
      rawRequest: "x",
      realQuestion: "q",
      positions: { product: pos(), finance: pos() },
      conflicts: conflicted,
      negotiation: [],
      devilsAdvocate: null,
      unresolved: true,
      call: async () => ({ input: briefInput({ unresolved: false }), usage: zeroUsage })
    });
    expect(brief.unresolved).toBe(true);
  });

  test("throws when the brief buries dissent that actually existed", async () => {
    await expect(
      runSynthesis({
        founder,
        rawRequest: "x",
        realQuestion: "q",
        positions: { product: pos(), finance: pos() },
        conflicts: conflicted,
        negotiation: [],
        devilsAdvocate: null,
        unresolved: true,
        call: async () => ({
          input: briefInput({ the_real_disagreement: "Everyone agreed." }),
          usage: zeroUsage
        })
      })
    ).rejects.toThrow(/dissent/i);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companySynthesis -v`
Expected: FAIL — cannot find module `../company/synthesis`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/synthesis.ts`:

```ts
import { AGENT_DEFS, composeAgentSystem } from "./registry";
import { AgentCaller } from "./router";
import {
  AgentId,
  AgentPosition,
  Confidence,
  Conflict,
  DecisionBrief,
  DevilsAdvocateVerdict,
  FounderContext,
  NegotiationRound,
  TokenUsage
} from "./types";

export const BRIEF_TOOL = {
  name: "record_decision_brief",
  description:
    "Record the decision brief. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      recommendation: {
        type: "string",
        description: "One paragraph. Judged on one criterion: could the founder act tomorrow morning?"
      },
      confidence: { type: "integer", minimum: 1, maximum: 5 },
      confidence_reason: { type: "string", description: "Why that confidence and not higher." },
      the_real_disagreement: {
        type: "string",
        description:
          "Who opposed, on what grounds, quoted closely enough that the founder can judge for themselves. Never average opposing views into a middle position nobody argued for. If nobody disagreed, say so explicitly."
      },
      tradeoff_founder_must_own: {
        type: "string",
        description:
          "The choice no department can make for them, stated as a clean either/or. Never end on 'it depends on your priorities' without saying what those priorities trade against."
      },
      kill_criteria: {
        type: "array",
        items: { type: "string" },
        description: "Observable events that mean 'we were wrong, stop'. At least one."
      },
      next_action: {
        type: "object",
        properties: {
          action: { type: "string", description: "Small enough to start today." },
          owner: { type: "string" }
        },
        required: ["action", "owner"],
        additionalProperties: false
      },
      what_we_dont_know: {
        type: "string",
        description: "The gap that most threatens this recommendation."
      },
      unresolved: {
        type: "boolean",
        description: "True if a trade-off could not be resolved. A valid, honest outcome."
      }
    },
    required: [
      "recommendation",
      "confidence",
      "the_real_disagreement",
      "tradeoff_founder_must_own",
      "kill_criteria",
      "next_action",
      "what_we_dont_know"
    ],
    additionalProperties: false
  }
};

function clampConfidence(value: unknown): Confidence {
  const n = typeof value === "number" && Number.isFinite(value) ? Math.round(value) : 3;
  return Math.min(5, Math.max(1, n)) as Confidence;
}

export function parseBriefToolInput(input: unknown): DecisionBrief | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "brief tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;
  const str = (key: string): string =>
    typeof raw[key] === "string" ? (raw[key] as string).trim() : "";

  for (const required of [
    "recommendation",
    "tradeoff_founder_must_own",
    "what_we_dont_know"
  ]) {
    if (str(required).length === 0) return { error: `${required} is required` };
  }

  const killCriteria = Array.isArray(raw.kill_criteria)
    ? raw.kill_criteria.filter((k): k is string => typeof k === "string" && k.trim().length > 0)
    : [];
  if (killCriteria.length === 0) {
    return { error: "kill_criteria requires at least one observable event" };
  }

  const action = raw.next_action;
  if (typeof action !== "object" || action === null) {
    return { error: "next_action is required" };
  }
  const actionText = (action as Record<string, unknown>).action;
  const owner = (action as Record<string, unknown>).owner;
  if (typeof actionText !== "string" || actionText.trim().length === 0) {
    return { error: "next_action.action is required" };
  }
  if (typeof owner !== "string" || owner.trim().length === 0) {
    return { error: "next_action.owner is required" };
  }

  return {
    recommendation: str("recommendation"),
    confidence: clampConfidence(raw.confidence),
    confidence_reason: str("confidence_reason"),
    the_real_disagreement: str("the_real_disagreement"),
    tradeoff_founder_must_own: str("tradeoff_founder_must_own"),
    kill_criteria: killCriteria.map((k) => k.trim()),
    next_action: { action: actionText.trim(), owner: owner.trim() },
    what_we_dont_know: str("what_we_dont_know"),
    unresolved: raw.unresolved === true
  };
}

/** Phrases that mean the brief smoothed the conflict away instead of showing it. */
const CONSENSUS_TELLS = [
  "everyone agreed",
  "all agreed",
  "no disagreement",
  "there was no disagreement",
  "the room agreed",
  "unanimous"
];

/**
 * Mechanical check for the failure mode the feature exists to prevent: a real
 * conflict existed and the brief did not report it. Spec §2.2 Phase 5 forbids
 * blurring the conflict, and spec TASK 9 requires asserting dissent survives.
 */
export function briefOmitsDissent(brief: DecisionBrief, conflicts: Conflict[]): boolean {
  const hadConflict = conflicts.some((c) => c.kind === "CONFLICT" || c.kind === "BLOCKER");
  if (!hadConflict) return false;

  const text = brief.the_real_disagreement.trim().toLowerCase();
  if (text.length === 0) return true;
  return CONSENSUS_TELLS.some((tell) => text.includes(tell));
}

const SYNTHESIS_INSTRUCTION = `Perform your SYNTHESIS duties.

THE REAL QUESTION AT STAKE:
<real_question>

WHAT EACH DEPARTMENT SAID, VERBATIM:
<positions>

CONFLICT DETECTION FOUND:
<conflicts>

<negotiation><red_team>Your synthesis is judged on one criterion: could the founder act tomorrow
morning? Produce all six components.

Never average opposing views into a middle position that nobody argued for.
Quote the disagreement closely enough that the founder can judge it themselves.
Do not bury dissent in a footnote.

Call record_decision_brief.`;

function renderPositions(positions: Partial<Record<AgentId, AgentPosition>>): string {
  return Object.entries(positions)
    .filter(([, p]) => p !== undefined)
    .map(([agent, p]) => {
      const position = p as AgentPosition;
      const blocker = position.hard_blocker
        ? `\n   HARD BLOCKER: ${position.hard_blocker}`
        : "";
      return `${agent} (stance: ${position.stance}, confidence ${position.confidence}/5):\n   Position: ${position.position}\n   Reasoning: ${position.reasoning}\n   Cost to their own department: ${position.cost_to_my_dept}\n   Evidence they want: ${position.evidence_needed.join("; ") || "none named"}${blocker}`;
    })
    .join("\n\n");
}

export async function runSynthesis(args: {
  founder: FounderContext;
  rawRequest: string;
  realQuestion: string;
  positions: Partial<Record<AgentId, AgentPosition>>;
  conflicts: Conflict[];
  negotiation: NegotiationRound[];
  devilsAdvocate: DevilsAdvocateVerdict | null;
  unresolved: boolean;
  call: AgentCaller;
}): Promise<{ brief: DecisionBrief; model: string; usage: TokenUsage }> {
  const negotiationBlock =
    args.negotiation.length === 0
      ? ""
      : `THE NEGOTIATION (${args.unresolved ? "ended UNRESOLVED" : "reached resolution"}):\n` +
        args.negotiation
          .map(
            (r) =>
              `Round ${r.round}:\n` +
              r.turns
                .map(
                  (t) =>
                    `  ${t.agent}: ${t.precise_disagreement}\n    Would change their mind if: ${t.what_would_change_my_mind}\n    Proposal: ${t.proposal}\n    Considers it resolved: ${t.resolved}`
                )
                .join("\n")
          )
          .join("\n\n") +
        "\n\n";

  const redTeamBlock =
    args.devilsAdvocate === null
      ? ""
      : `THE RED TEAM SAID:\n  Load-bearing assumption: ${args.devilsAdvocate.load_bearing_assumption}\n  How it could be false: ${args.devilsAdvocate.how_it_could_be_false}\n  Cheapest test: ${args.devilsAdvocate.cheapest_test}\n  Failure post-mortem: ${args.devilsAdvocate.failure_post_mortem}\n  Not in the room: ${args.devilsAdvocate.who_is_not_in_the_room}\n  Plan judged sound: ${args.devilsAdvocate.plan_is_sound}\n\n`;

  const conflictBlock =
    args.conflicts.length === 0
      ? "No pairs to compare."
      : args.conflicts.map((c) => `${c.a} vs ${c.b}: ${c.kind} — ${c.reason}`).join("\n");

  const model = AGENT_DEFS.chief_of_staff.model;
  const { input, usage } = await args.call({
    agent: "chief_of_staff",
    model,
    system: composeAgentSystem({
      agent: "chief_of_staff",
      founder: args.founder,
      rawRequest: args.rawRequest
    }),
    userMessage: SYNTHESIS_INSTRUCTION.replace("<real_question>", args.realQuestion.trim())
      .replace("<positions>", renderPositions(args.positions))
      .replace("<conflicts>", conflictBlock)
      .replace("<negotiation>", negotiationBlock)
      .replace("<red_team>", redTeamBlock),
    tool: BRIEF_TOOL,
    toolName: BRIEF_TOOL.name
  });

  const parsed = parseBriefToolInput(input);
  if ("error" in parsed) {
    throw new Error(`unusable decision brief from chief_of_staff: ${parsed.error}`);
  }
  if (briefOmitsDissent(parsed, args.conflicts)) {
    throw new Error(
      "decision brief buried dissent: a CONFLICT or BLOCKER existed but the_real_disagreement does not report it"
    );
  }

  // The negotiation outcome is authoritative — the synthesiser cannot downgrade
  // an unresolved trade-off into a resolved one.
  return { brief: { ...parsed, unresolved: parsed.unresolved || args.unresolved }, model, usage };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companySynthesis -v && npx tsc --noEmit`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/synthesis.ts functions/src/__tests__/companySynthesis.test.ts
git commit -m "feat(company): phase 5 synthesis with mechanical dissent guard"
```

---

## Task 12: Budget guardrails and kill switch

**Files:**
- Create: `functions/src/company/budget.ts`
- Test: `functions/src/__tests__/companyBudget.test.ts`

**Interfaces:**
- Consumes: `Blackboard`, `TokenUsage` from `./types`.
- Produces:
  - `MAX_RUN_TOKENS = 200_000`
  - `MAX_RUN_COST_USD = 1.5`
  - `totalTokens(bb: Blackboard): number`
  - `budgetState(bb: Blackboard): { withinBudget: boolean; reason: string | null }`
  - `isFeatureEnabled(): Promise<boolean>`
  - `KILL_SWITCH_DOC = "config/virtual_company"`

Spec §5.2: on breach, stop and return a partial result with an explanation — never truncate silently. The kill switch must disable the feature without a deploy, so it reads a Firestore config doc, defaulting to **enabled** if the doc is absent (a missing config must not take the feature down).

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyBudget.test.ts`:

```ts
import {
  MAX_RUN_TOKENS,
  MAX_RUN_COST_USD,
  totalTokens,
  budgetState
} from "../company/budget";
import { newBlackboard, recordUsage } from "../company/blackboard";
import { FounderContext } from "../company/types";
import { AGENT_MODEL } from "../anthropic";

const founder: FounderContext = {
  profile: "Solo technical founder.",
  stage: "Pre-revenue.",
  constraints: [],
  language: "en"
};
const fresh = () => newBlackboard({ runId: "r1", uid: "u1", rawRequest: "x", founder });

describe("totalTokens", () => {
  test("is zero for a fresh run", () => {
    expect(totalTokens(fresh())).toBe(0);
  });

  test("sums input and output across agents but excludes cache reads", () => {
    // Cache reads are billed at a tenth and are the behaviour we want to
    // encourage — counting them against the ceiling would penalise caching.
    let bb = fresh();
    bb = recordUsage(bb, "product", AGENT_MODEL, { input: 100, output: 50, cache_read: 5000 });
    bb = recordUsage(bb, "finance", AGENT_MODEL, { input: 200, output: 25, cache_read: 5000 });
    expect(totalTokens(bb)).toBe(375);
  });
});

describe("budgetState", () => {
  test("a fresh run is within budget", () => {
    expect(budgetState(fresh())).toEqual({ withinBudget: true, reason: null });
  });

  test("breaches on the token ceiling with a stated reason", () => {
    const bb = recordUsage(fresh(), "product", AGENT_MODEL, {
      input: MAX_RUN_TOKENS,
      output: 1,
      cache_read: 0
    });
    const state = budgetState(bb);
    expect(state.withinBudget).toBe(false);
    expect(state.reason).toMatch(/token/i);
  });

  test("breaches on the cost ceiling with a stated reason", () => {
    // 1M output tokens on the mid tier is $15, well past the per-run ceiling.
    const bb = recordUsage(fresh(), "product", AGENT_MODEL, {
      input: 0,
      output: 1_000_000,
      cache_read: 0
    });
    const state = budgetState(bb);
    expect(state.withinBudget).toBe(false);
    expect(state.reason).toMatch(/cost/i);
  });

  test("the reason is always human-readable, never empty on a breach", () => {
    const bb = recordUsage(fresh(), "product", AGENT_MODEL, {
      input: MAX_RUN_TOKENS + 1,
      output: 0,
      cache_read: 0
    });
    expect(budgetState(bb).reason!.length).toBeGreaterThan(10);
  });

  test("ceilings are set to plausible per-run values", () => {
    expect(MAX_RUN_TOKENS).toBeGreaterThan(50_000);
    expect(MAX_RUN_COST_USD).toBeGreaterThan(0);
    expect(MAX_RUN_COST_USD).toBeLessThan(10);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyBudget -v`
Expected: FAIL — cannot find module `../company/budget`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/budget.ts`:

```ts
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { Blackboard } from "./types";

/**
 * Per-run ceilings. A 4-agent run with a cached prefix should land far below
 * these; they exist to stop a runaway loop, not to shape normal runs.
 */
export const MAX_RUN_TOKENS = 200_000;
export const MAX_RUN_COST_USD = 1.5;

/** Config doc read at request time so the feature can be disabled without a deploy. */
export const KILL_SWITCH_DOC = "config/virtual_company";

/**
 * Billable generation and fresh input. Cache reads are excluded deliberately —
 * they cost a tenth of input and are the behaviour we want, so charging them
 * against the ceiling would punish a well-cached run.
 */
export function totalTokens(bb: Blackboard): number {
  return Object.values(bb.telemetry.tokens_per_agent).reduce(
    (sum, usage) => sum + (usage?.input ?? 0) + (usage?.output ?? 0),
    0
  );
}

export function budgetState(bb: Blackboard): { withinBudget: boolean; reason: string | null } {
  const tokens = totalTokens(bb);
  if (tokens >= MAX_RUN_TOKENS) {
    return {
      withinBudget: false,
      reason: `Run stopped: token ceiling reached (${tokens} of ${MAX_RUN_TOKENS} allowed for one run).`
    };
  }
  const cost = bb.telemetry.cost_estimate_usd;
  if (cost >= MAX_RUN_COST_USD) {
    return {
      withinBudget: false,
      reason: `Run stopped: cost ceiling reached (estimated $${cost.toFixed(2)} of $${MAX_RUN_COST_USD.toFixed(2)} allowed for one run).`
    };
  }
  return { withinBudget: true, reason: null };
}

/**
 * Reads the kill switch. Defaults to enabled when the doc or field is missing —
 * a config document that was never created must not take the feature down. Any
 * read error also defaults to enabled and is logged, so a Firestore blip does
 * not look like an intentional shutdown.
 */
export async function isFeatureEnabled(): Promise<boolean> {
  try {
    const [collection, doc] = KILL_SWITCH_DOC.split("/");
    const snap = await admin.firestore().collection(collection).doc(doc).get();
    if (!snap.exists) return true;
    const enabled = (snap.data() as Record<string, unknown>).enabled;
    return enabled !== false;
  } catch (err) {
    logger.warn("virtual company kill switch unreadable; defaulting to enabled", {
      err: String(err)
    });
    return true;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyBudget -v && npx tsc --noEmit`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/company/budget.ts functions/src/__tests__/companyBudget.test.ts
git commit -m "feat(company): per-run budget ceilings and no-deploy kill switch"
```

---

## Task 13: SSE endpoint, orchestrator, and the UI contract

**Files:**
- Create: `functions/src/company/virtualCompany.ts`
- Modify: `functions/src/index.ts` (add the `virtualCompanyRun` export after `generateDictionary`)
- Create: `docs/superpowers/specs/virtual-company-sse-contract.md`
- Test: `functions/src/__tests__/companyVirtualCompany.test.ts`

**Interfaces:**
- Consumes: everything from Tasks 6–12; `verifyAuth` from `../auth`; `checkAndIncrement` from `../rateLimit`.
- Produces:
  - `validateRunPayload(body: unknown): string | null`
  - `handleVirtualCompanyRun(req: Request, res: Response): Promise<void>`
  - `__setAgentCallerForTests(caller: AgentCaller)` / `__resetAgentCallerForTests()`
  - `RunPayload` interface

This is the last backend task. It follows the existing `handleChatSession` shape exactly: method check → auth → payload validation → rate limit → SSE headers → stream. The real `AgentCaller` lives here and is the only place that touches the Anthropic SDK; it is swapped out in tests via the `__set...ForTests` seam already used by `chat.ts`.

The orchestrator order is fixed: intake → (escape hatch) → independent pass → conflict detection → negotiation → devil's advocate → synthesis. A budget check runs between phases, and a breach emits `run_stopped` with the reason and then `done` — never a silent truncation.

- [ ] **Step 1: Write the failing test**

Create `functions/src/__tests__/companyVirtualCompany.test.ts`:

```ts
import { validateRunPayload } from "../company/virtualCompany";

describe("validateRunPayload", () => {
  const valid = {
    request: "Should I add team seats or price the single-player product first?",
    language: "en",
    founder: {
      profile: "Solo technical founder, one prior product that plateaued.",
      stage: "Pre-revenue, 4 months runway, 30 beta users.",
      constraints: ["Cannot hire this quarter."]
    }
  };

  test("returns null for a valid payload", () => {
    expect(validateRunPayload(valid)).toBeNull();
  });

  test("rejects a missing request", () => {
    expect(validateRunPayload({ ...valid, request: "   " })).toMatch(/request/);
  });

  test("rejects a request longer than the cap", () => {
    expect(validateRunPayload({ ...valid, request: "x".repeat(4001) })).toMatch(/request/);
  });

  test("rejects an unsupported language", () => {
    expect(validateRunPayload({ ...valid, language: "fr" })).toMatch(/language/);
  });

  test("rejects a missing founder block", () => {
    expect(validateRunPayload({ ...valid, founder: undefined })).toMatch(/founder/);
  });

  test("rejects non-string constraints", () => {
    const bad = { ...valid, founder: { ...valid.founder, constraints: [1, 2] } };
    expect(validateRunPayload(bad)).toMatch(/constraints/);
  });

  test("accepts an empty constraints array", () => {
    const ok = { ...valid, founder: { ...valid.founder, constraints: [] } };
    expect(validateRunPayload(ok)).toBeNull();
  });

  test("accepts the optional stress_test flag", () => {
    expect(validateRunPayload({ ...valid, stress_test: true })).toBeNull();
    expect(validateRunPayload({ ...valid, stress_test: "yes" })).toMatch(/stress_test/);
  });

  test("rejects a non-object body", () => {
    expect(validateRunPayload(null)).toMatch(/body/);
    expect(validateRunPayload("go")).toMatch(/body/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd functions && npx jest companyVirtualCompany -v`
Expected: FAIL — cannot find module `../company/virtualCompany`.

- [ ] **Step 3: Write minimal implementation**

Create `functions/src/company/virtualCompany.ts`:

```ts
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "../auth";
import { checkAndIncrement } from "../rateLimit";
import { AgentCaller, runIntake } from "./router";
import { runIndependentPass } from "./independentPass";
import { detectConflicts, needsNegotiation } from "./conflicts";
import { runNegotiation } from "./negotiation";
import { runDevilsAdvocate, shouldInvokeDevilsAdvocate } from "./devilsAdvocate";
import { runSynthesis } from "./synthesis";
import { budgetState, isFeatureEnabled } from "./budget";
import {
  newBlackboard,
  recordPosition,
  recordUsage,
  saveBlackboard
} from "./blackboard";
import { AGENT_DEPARTMENT_KEY, AgentId, Blackboard, FounderContext } from "./types";

const MAX_REQUEST_CHARS = 4000;

export interface RunPayload {
  request: string;
  language: "vi" | "en";
  founder: { profile: string; stage: string; constraints: string[] };
  stress_test?: boolean;
}

export function validateRunPayload(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return "body required";
  const b = body as Record<string, unknown>;

  if (typeof b.request !== "string" || b.request.trim().length === 0) {
    return "request required";
  }
  if (b.request.length > MAX_REQUEST_CHARS) {
    return `request exceeds ${MAX_REQUEST_CHARS} characters`;
  }
  if (b.language !== "vi" && b.language !== "en") {
    return "language must be 'vi' or 'en'";
  }

  const founder = b.founder;
  if (typeof founder !== "object" || founder === null) return "founder required";
  const f = founder as Record<string, unknown>;
  if (typeof f.profile !== "string") return "founder.profile must be a string";
  if (typeof f.stage !== "string") return "founder.stage must be a string";
  if (!Array.isArray(f.constraints)) return "founder.constraints must be an array";
  if (!f.constraints.every((c) => typeof c === "string")) {
    return "founder.constraints must contain only strings";
  }

  if (b.stress_test !== undefined && typeof b.stress_test !== "boolean") {
    return "stress_test must be a boolean";
  }
  return null;
}

// ─── Anthropic call seam ──────────────────────────────────────────────────────

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

/**
 * The only place in the feature that talks to the Anthropic SDK. Every agent
 * call is forced through a tool so the output is schema-validated rather than
 * parsed out of free text (spec §5.4 — text parsing breaks in production).
 */
const defaultAgentCaller: AgentCaller = async (args) => {
  const response = await anthropicClient().messages.create({
    model: args.model,
    max_tokens: 2000,
    system: args.system as any,
    tools: [args.tool as any],
    tool_choice: { type: "tool", name: args.toolName },
    messages: [{ role: "user", content: args.userMessage }]
  });

  const usage = {
    input: response.usage?.input_tokens ?? 0,
    output: response.usage?.output_tokens ?? 0,
    cache_read: (response.usage as any)?.cache_read_input_tokens ?? 0
  };

  for (const block of response.content) {
    if (block.type === "tool_use" && block.name === args.toolName) {
      return { input: block.input, usage };
    }
  }
  throw new Error(`${args.agent} did not call ${args.toolName}`);
};

let _agentCaller: AgentCaller | null = null;
export function __setAgentCallerForTests(caller: AgentCaller): void {
  _agentCaller = caller;
}
export function __resetAgentCallerForTests(): void {
  _agentCaller = null;
}

// ─── SSE plumbing ─────────────────────────────────────────────────────────────

function writeFrame(res: Response, event: string, payload: unknown): void {
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}

function agentMeta(agent: AgentId) {
  return { agent_id: agent, department_key: AGENT_DEPARTMENT_KEY[agent] };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

export async function handleVirtualCompanyRun(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const validationError = validateRunPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as RunPayload;

  if (!(await isFeatureEnabled())) {
    res.status(503).json({ error: "feature_disabled" });
    return;
  }

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.status(200);
  if (typeof (res as any).flushHeaders === "function") {
    (res as any).flushHeaders();
  }

  const founder: FounderContext = {
    profile: payload.founder.profile,
    stage: payload.founder.stage,
    constraints: payload.founder.constraints,
    language: payload.language
  };
  const runId = `run_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  let bb: Blackboard = newBlackboard({
    runId,
    uid: auth.uid,
    rawRequest: payload.request,
    founder
  });
  const call: AgentCaller = _agentCaller ?? defaultAgentCaller;

  /** Emits run_stopped + done and returns true when the budget is spent. */
  const stopIfOverBudget = (): boolean => {
    const state = budgetState(bb);
    if (state.withinBudget) return false;
    bb = { ...bb, telemetry: { ...bb.telemetry, stopped_reason: state.reason } };
    // Partial result with a stated reason — never a silent truncation.
    writeFrame(res, "run_stopped", { run_id: runId, reason: state.reason });
    return true;
  };

  try {
    writeFrame(res, "run_started", { run_id: runId });

    // ── Phase 1: intake ──
    const intake = await runIntake({ founder, rawRequest: payload.request, call });
    bb = recordUsage(bb, "chief_of_staff", intake.usage ? "" : "", intake.usage);
    bb = {
      ...bb,
      routing: intake.routing,
      request: {
        raw: bb.request.raw,
        real_question: intake.routing.real_question,
        type: intake.routing.request_type
      }
    };
    writeFrame(res, "routing", {
      ...intake.routing,
      agent_meta: intake.routing.agents.map(agentMeta)
    });

    // ── Escape hatch: skip phases 2-5 entirely (spec §2.2 Phase 1) ──
    if (intake.routing.decision !== "multi_agent") {
      writeFrame(res, "telemetry", bb.telemetry);
      writeFrame(res, "done", {
        run_id: runId,
        unresolved: false,
        skipped: intake.routing.decision
      });
      await saveBlackboard(bb);
      return;
    }

    if (stopIfOverBudget()) {
      writeFrame(res, "done", { run_id: runId, unresolved: false, skipped: null });
      await saveBlackboard(bb);
      return;
    }

    // ── Phase 2: independent pass, mutually blind ──
    const departmentAgents = intake.routing.agents.filter((a) => a !== "devils_advocate");
    for (const agent of departmentAgents) {
      writeFrame(res, "agent_start", agentMeta(agent));
    }

    const pass = await runIndependentPass({
      founder,
      rawRequest: payload.request,
      realQuestion: intake.routing.real_question,
      agents: departmentAgents,
      call
    });

    for (const result of pass.results) {
      bb = recordUsage(bb, result.agent, result.model, result.usage);
      if (result.position) {
        bb = recordPosition(bb, result.agent, result.position);
        writeFrame(res, "agent_position", {
          ...agentMeta(result.agent),
          position: result.position
        });
      } else {
        // Graceful degradation: this column errors, the run continues.
        writeFrame(res, "agent_error", {
          ...agentMeta(result.agent),
          error: result.error ?? "unknown"
        });
      }
    }

    // ── Phase 3: conflict detection — pure code, no LLM ──
    const conflicts = detectConflicts(bb.positions);
    bb = { ...bb, conflicts };
    writeFrame(res, "conflicts", { conflicts });

    // ── Phase 4: negotiation, only when there is something to debate ──
    let unresolved = false;
    if (needsNegotiation(conflicts) && !stopIfOverBudget()) {
      const negotiation = await runNegotiation({
        founder,
        rawRequest: payload.request,
        realQuestion: intake.routing.real_question,
        positions: bb.positions,
        conflicts,
        call
      });
      for (const u of negotiation.usages) {
        bb = recordUsage(bb, u.agent, u.model, u.usage);
      }
      bb = { ...bb, negotiation: negotiation.rounds };
      unresolved = negotiation.unresolved;
      for (const round of negotiation.rounds) {
        writeFrame(res, "negotiation_round", round);
      }
    }

    // ── Phase 4b: red team ──
    const wantsRedTeam = shouldInvokeDevilsAdvocate({
      positions: bb.positions,
      conflicts,
      founderRequested: payload.stress_test === true
    });
    if (wantsRedTeam && !stopIfOverBudget()) {
      writeFrame(res, "agent_start", agentMeta("devils_advocate"));
      try {
        const redTeam = await runDevilsAdvocate({
          founder,
          rawRequest: payload.request,
          realQuestion: intake.routing.real_question,
          positions: bb.positions,
          call
        });
        bb = recordUsage(bb, "devils_advocate", redTeam.model, redTeam.usage);
        bb = { ...bb, devils_advocate: redTeam.verdict };
        writeFrame(res, "devils_advocate", {
          ...agentMeta("devils_advocate"),
          verdict: redTeam.verdict
        });
      } catch (err) {
        writeFrame(res, "agent_error", {
          ...agentMeta("devils_advocate"),
          error: String(err)
        });
      }
    }

    // ── Phase 5: synthesis ──
    if (stopIfOverBudget()) {
      writeFrame(res, "done", { run_id: runId, unresolved, skipped: null });
      await saveBlackboard(bb);
      return;
    }

    const synthesis = await runSynthesis({
      founder,
      rawRequest: payload.request,
      realQuestion: intake.routing.real_question,
      positions: bb.positions,
      conflicts,
      negotiation: bb.negotiation,
      devilsAdvocate: bb.devils_advocate,
      unresolved,
      call
    });
    bb = recordUsage(bb, "chief_of_staff", synthesis.model, synthesis.usage);
    bb = { ...bb, synthesis: synthesis.brief };
    writeFrame(res, "brief", synthesis.brief);

    writeFrame(res, "telemetry", bb.telemetry);
    writeFrame(res, "done", {
      run_id: runId,
      unresolved: synthesis.brief.unresolved,
      skipped: null
    });
    await saveBlackboard(bb);
  } catch (err) {
    logger.error("virtualCompanyRun failed", {
      uid: auth.uid,
      run_id: runId,
      err: String(err)
    });
    writeFrame(res, "error", { error: "upstream_failure", detail: String(err) });
    try {
      await saveBlackboard(bb);
    } catch {
      // Persisting a failed run is best-effort; the client already has the error.
    }
  } finally {
    res.end();
  }
}
```

Note on the `recordUsage` call after intake: replace the placeholder `intake.usage ? "" : ""` with `ROUTER_MODEL` imported from `../anthropic`, so the router's spend is priced at the tier it actually ran on.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd functions && npx jest companyVirtualCompany -v && npx tsc --noEmit`
Expected: all PASS, no type errors. Fix the `recordUsage` placeholder before this step or `tsc` will flag the empty-string model.

- [ ] **Step 5: Wire the endpoint into `index.ts`**

Add the import beside the others at the top of `functions/src/index.ts`:

```ts
import { handleVirtualCompanyRun } from "./company/virtualCompany";
```

Then append the export at the end of the file:

```ts
// Virtual Company: 4 agents analyse a founder's decision independently, surface
// where they disagree, negotiate under a 2-round cap, then synthesise a brief.
// Streams SSE — see docs/superpowers/specs/virtual-company-sse-contract.md for
// the event contract the client consumes.
export const virtualCompanyRun = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"],
    // A full run makes up to 8 sequential/parallel model calls across 5 phases.
    timeoutSeconds: 540
  },
  handleVirtualCompanyRun
);
```

- [ ] **Step 6: Verify the build and the whole suite**

Run: `cd functions && npm run build && npx jest`
Expected: build succeeds, every test passes.

- [ ] **Step 7: Write the SSE contract for the UI engineer**

Create `docs/superpowers/specs/virtual-company-sse-contract.md`. This is the handoff artifact — the UI engineer builds against this document, not against the backend source.

````markdown
# Virtual Company — SSE Contract

Backend owner: logic/BE. UI owner: separate. This document is the boundary.

**Endpoint:** `POST https://us-central1-devpet-8f4b1.cloudfunctions.net/virtualCompanyRun`
**Auth:** `Authorization: Bearer <Firebase ID token>`
**Response:** `text/event-stream`. Parse with the existing `codepet/Services/SSEParser.swift`.

## Request

```json
{
  "request": "Should I add team seats or price the single-player product first?",
  "language": "vi",
  "founder": {
    "profile": "Solo technical founder, one prior product that plateaued.",
    "stage": "Pre-revenue, 4 months runway, 30 beta users.",
    "constraints": ["Cannot hire this quarter."]
  },
  "stress_test": false
}
```

`request` max 4000 chars. `language` is `vi` or `en`. `stress_test: true` forces the
red team to run even when the departments disagree.

## Non-SSE error responses

| Status | Body | Meaning |
|---|---|---|
| 400 | `{"error":"invalid_payload","detail":"..."}` | Fix the request |
| 401 | `{"error":"invalid_token"}` | Re-authenticate |
| 429 | `{"error":"daily_limit_reached","reset_at":"...","limit":N}` | Show reset time |
| 503 | `{"error":"feature_disabled"}` | Kill switch is on — hide the entry point |

## Events, in emission order

| Event | Payload | Notes |
|---|---|---|
| `run_started` | `{run_id}` | Always first |
| `routing` | `RoutingDecision` + `agent_meta[]` | **Render immediately** — do not show a spinner. Spec §4.2A: the founder learns problem decomposition from this panel. |
| `agent_start` | `{agent_id, department_key}` | One per department agent, all emitted before any position arrives — this is what produces the "whole room is thinking" effect |
| `agent_position` | `{agent_id, department_key, position}` | Arrives per agent as it finishes, in completion order |
| `agent_error` | `{agent_id, department_key, error}` | Show the error in that agent's column only; the run continues |
| `conflicts` | `{conflicts: Conflict[]}` | **Highest-value view.** Do not bury in an accordion |
| `negotiation_round` | `NegotiationRound` | Zero, one, or two events. Absent entirely when nothing conflicted |
| `devils_advocate` | `{agent_id, department_key, verdict}` | Optional. Preceded by its own `agent_start` |
| `brief` | `DecisionBrief` | The final deliverable |
| `telemetry` | `{tokens_per_agent, cost_estimate_usd, stopped_reason}` | Show the cost — the founder has a right to know what the answer cost them (spec §4.3) |
| `run_stopped` | `{run_id, reason}` | Budget ceiling hit. `reason` is human-readable — show it verbatim |
| `done` | `{run_id, unresolved, skipped}` | Always last on a successful stream |
| `error` | `{error, detail}` | Terminal failure; no `done` follows |

## Payload shapes

Field-for-field mirrors of `functions/src/company/types.ts`.

```ts
RoutingDecision = {
  decision: "single_agent" | "multi_agent" | "needs_clarification"
  agents: AgentId[]
  real_question: string
  request_type: "DECISION" | "DIAGNOSIS" | "PLANNING" | "REVIEW"
  reason_per_agent: { [agentId]: string }
  excluded: { [agentId]: string }
  missing_info: string[]
}

AgentPosition = {
  stance: "proceed" | "proceed_with_conditions" | "do_not_proceed"
  position: string
  reasoning: string
  evidence_needed: string[]
  risks_i_own: string[]
  confidence: 1..5
  cost_to_my_dept: string
  hard_blocker: string | null   // non-null → show the 🔒 badge
}

Conflict = {
  a: AgentId, b: AgentId
  kind: "CONFLICT" | "BLOCKER" | "TENSION" | "ALIGNED"
  reason: string
}

NegotiationRound = { round: 1 | 2, turns: NegotiationTurn[] }
NegotiationTurn = {
  agent: AgentId
  precise_disagreement: string
  what_would_change_my_mind: string   // the falsification condition — show it
  proposal: string
  resolved: boolean
}

DecisionBrief = {
  recommendation: string
  confidence: 1..5
  confidence_reason: string
  the_real_disagreement: string          // never paraphrase this in the UI
  tradeoff_founder_must_own: string
  kill_criteria: string[]
  next_action: { action: string, owner: string }
  what_we_dont_know: string
  unresolved: boolean
}
```

## Rendering rules the backend depends on

These are not style preferences — they are why the feature exists (spec §4.3).

1. **Never collapse the process into a spinner + answer.** That deletes the differentiator.
2. **Never summarise the positions into one "we agree" paragraph.** The backend already refuses to emit a brief that buries dissent; do not re-introduce it in the UI.
3. **Show `the_real_disagreement` verbatim.** No paraphrasing, no softening.
4. **Show each side's `what_would_change_my_mind`** on the conflict card. It teaches that disagreement is settled by evidence, not authority.
5. **End on the either/or**, not on "it's up to you" — use `tradeoff_founder_must_own`.
6. **`unresolved: true` is a valid outcome, not an error.** Present it as an honest answer.
7. **Render `confidence` as dots, not a number.** A number implies false precision.
8. **No artificial delay or fake typing.** Users detect it and lose trust.
9. **No human avatars or personal names for agents.** These are departments, not simulated people.

## `department_key` mapping

Every `agent_*` event carries `department_key` so the client can reuse existing styling.

| `agent_id` | `department_key` | Client-side action |
|---|---|---|
| `product` | `"product"` | **No entry in `Department.all` yet — please add one** (`Department.swift:47`) |
| `finance` | `"fin"` | Already exists; reuse it |
| `chief_of_staff` | `null` | Render as the founder's companion pet (`companyStore.company.companionId`) |
| `devils_advocate` | `null` | Needs its own visual identity — **do not give it a department colour.** Spec §3.8: "You are not a department. You have no interests to protect." A department colour would misrepresent what it is. |

## Known deviation from the spec

Spec §4.2B asks for per-token parallel streaming inside the meeting room. Positions
are structured tool-use output, so streaming partial JSON into typed fields is
fragile. The backend emits `agent_start` then `agent_position` per agent instead.
Two agents starting together and finishing independently still gives the parallel
effect. If per-token streaming turns out to matter, it is a backend change
(`eager_input_streaming`) — raise it and it can be added without touching the
event names above.
````

- [ ] **Step 8: Commit**

```bash
git add functions/src/company/virtualCompany.ts \
        functions/src/__tests__/companyVirtualCompany.test.ts \
        functions/src/index.ts \
        docs/superpowers/specs/virtual-company-sse-contract.md
git commit -m "feat(company): SSE orchestrator endpoint and UI event contract"
```

---

## Task 14: Staging verification

**Files:**
- Create: `functions/scripts/verify-company-run.ts`
- Modify: `functions/package.json` (add the `verify:company` script)

No unit test — this task's deliverable is evidence from a real run. Everything before this point is tested against fakes; this is where the two things fakes cannot prove get checked: that prompt caching actually engages, and that a real model reliably calls the tools.

- [ ] **Step 1: Write the verification script**

Create `functions/scripts/verify-company-run.ts`:

```ts
/**
 * Staging verification. Not part of the test suite — needs a real API key and
 * makes real calls. Run: ANTHROPIC_API_KEY=sk-... npm run verify:company
 *
 * Proves the two things unit tests with fakes cannot:
 *   1. The shared prefix is actually being cached (cache_read_input_tokens > 0
 *      on the second and later agent calls in the same run).
 *   2. A real model reliably calls the forced tool and returns a parseable
 *      position.
 */
import Anthropic from "@anthropic-ai/sdk";
import { AGENT_MODEL, MODEL_PRICING } from "../src/anthropic";
import { composeAgentSystem } from "../src/company/registry";
import { buildSharedPrefix, estimateTokens } from "../src/company/preamble";
import { POSITION_TOOL, parsePositionToolInput } from "../src/company/independentPass";
import { detectConflicts } from "../src/company/conflicts";
import { AgentId, AgentPosition, FounderContext } from "../src/company/types";

const founder: FounderContext = {
  profile:
    "Solo founder, technical, previously a backend engineer. Shipped one product " +
    "that reached 200 paying users then plateaued. No design or sales background.",
  stage:
    "Pre-revenue, 4 months of runway, product in closed beta with 30 users, no " +
    "pricing page yet.",
  constraints: [
    "Cannot hire — no budget for headcount this quarter.",
    "Must ship to the App Store before the end of next month.",
    "Refuses to take outside investment at this stage."
  ],
  language: "en"
};

const rawRequest =
  "Should I build a team-collaboration feature so companies can buy seats, or " +
  "should I first put a price on the single-player product I already have?";

const realQuestion = "Is the current pricing bet wrong?";

async function main(): Promise<void> {
  const prefix = buildSharedPrefix({ founder, rawRequest });
  const floor = MODEL_PRICING[AGENT_MODEL].cacheMinTokens;
  console.log(`shared prefix: ${prefix.length} chars, ~${estimateTokens(prefix)} tokens`);
  console.log(`cache floor for ${AGENT_MODEL}: ${floor} tokens`);
  if (estimateTokens(prefix) < floor) {
    console.error("FAIL: prefix is below the cache floor — caching will silently no-op");
    process.exit(1);
  }

  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  const positions: Partial<Record<AgentId, AgentPosition>> = {};
  let sawCacheRead = false;

  // Sequential on purpose: the first call writes the cache, later calls should
  // read it. Parallel calls would all miss (the entry is not readable until the
  // first response starts streaming).
  for (const agent of ["product", "finance"] as AgentId[]) {
    const response = await client.messages.create({
      model: AGENT_MODEL,
      max_tokens: 2000,
      system: composeAgentSystem({ agent, founder, rawRequest }) as any,
      tools: [POSITION_TOOL as any],
      tool_choice: { type: "tool", name: POSITION_TOOL.name },
      messages: [
        {
          role: "user",
          content: `Give your independent position. THE REAL QUESTION: ${realQuestion}\n\nCall submit_position.`
        }
      ]
    });

    const usage = response.usage as any;
    const cacheRead = usage?.cache_read_input_tokens ?? 0;
    const cacheWrite = usage?.cache_creation_input_tokens ?? 0;
    console.log(
      `${agent}: input=${usage?.input_tokens} output=${usage?.output_tokens} ` +
        `cache_write=${cacheWrite} cache_read=${cacheRead}`
    );
    if (cacheRead > 0) sawCacheRead = true;

    const block = response.content.find(
      (b) => b.type === "tool_use" && b.name === POSITION_TOOL.name
    );
    if (!block) {
      console.error(`FAIL: ${agent} did not call submit_position`);
      process.exit(1);
    }
    const parsed = parsePositionToolInput((block as any).input);
    if ("error" in parsed) {
      console.error(`FAIL: ${agent} returned an unparseable position: ${parsed.error}`);
      process.exit(1);
    }
    positions[agent] = parsed;
    console.log(`  stance=${parsed.stance} confidence=${parsed.confidence} blocker=${parsed.hard_blocker ?? "none"}`);
  }

  if (!sawCacheRead) {
    console.error(
      "FAIL: no cache read on the second call — the shared prefix is not byte-identical " +
        "across agents, or it is below the model's cache minimum"
    );
    process.exit(1);
  }

  console.log("\nconflicts:", JSON.stringify(detectConflicts(positions), null, 2));
  console.log("\nPASS: caching engaged and both agents returned parseable positions.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Add the npm script**

In `functions/package.json`, add to `"scripts"`:

```json
    "verify:company": "ts-node scripts/verify-company-run.ts"
```

If `ts-node` is not already a dev dependency, install it: `cd functions && npm i -D ts-node`.

- [ ] **Step 3: Run the verification**

Run: `cd functions && ANTHROPIC_API_KEY=<key> npm run verify:company`

Expected output shape:
```
shared prefix: ~4200 chars, ~1200 tokens
cache floor for claude-sonnet-5: 1024 tokens
product: input=... cache_write=1200 cache_read=0
finance: input=... cache_write=0 cache_read=1200
PASS: caching engaged and both agents returned parseable positions.
```

The load-bearing line is `cache_read=1200` on the **second** agent. If it reads 0, the prefix differs between agents — check that no role prompt leaked into block 0 of `composeAgentSystem`.

- [ ] **Step 4: Record the result and commit**

Note the observed per-run cost from the script output in the commit message so the team has a real number rather than an estimate.

```bash
git add functions/scripts/verify-company-run.ts functions/package.json
git commit -m "chore(company): staging verification for prompt caching and tool adherence"
```

---

## Self-Review

**Spec coverage.** Every spec requirement in scope maps to a task:

| Spec | Task |
|---|---|
| §1.3 roster (Tier 0 + reduced Tier 1) | 2 |
| §2.1 orchestrator + blackboard pattern | 6, 13 |
| §2.2 Phase 1 intake + escape hatch | 7, 13 |
| §2.2 Phase 2 mutually blind parallel pass | 8 |
| §2.2 Phase 3 conflict detection, pure code | 5 |
| §2.2 Phase 4 negotiation, 2-round cap, unresolved valid | 9 |
| §2.2 Phase 4 devil's advocate trigger | 10 |
| §2.2 Phase 5 synthesis, 6 components | 11 |
| §2.2 Phase 6 founder interjection | **Out of MVP scope** — blackboard persisted so it can be added later |
| §3.1 shared preamble | 3 |
| §3.2–3.8 role prompts | 4 |
| §5.1 key never in client | 13 (Global Constraints) |
| §5.2 caching, tiering, escape hatch, round cap, budget | 1, 3, 7, 9, 12 |
| §5.3 blackboard schema, persisted | 2, 6 |
| §5.4 structured output via tool-use | 7, 8, 9, 10, 11 |
| §5.5 SSE with agentId, graceful degradation, rate limit, kill switch | 8, 12, 13 |
| §4.1–4.3 UI requirements | **Owned by the UI engineer** — delivered as the Task 13 contract |
| §6 TASK 17 telemetry dashboard | **Out of MVP scope** — `telemetry` event ships the data |
| §7 acceptance criteria | Task 14 covers the mechanical ones; the behavioural ones ("conflict detected in ≥8 of 20 requests", "≥2 runs end unresolved") need a live eval once the endpoint is deployed |

**Gap identified and accepted:** spec §7's behavioural acceptance criteria cannot be checked before deployment. After Task 14, run 20 real founder requests through the endpoint and count how many produce a `CONFLICT`/`BLOCKER` and how many end `unresolved: true`. If every run ends aligned, the feature has failed on its own terms and the position prompts need re-tuning — that is a follow-up, not a task in this plan.

**Type consistency:** `AgentCaller` is defined once in `router.ts` and imported by Tasks 8–11. `SystemBlock` is defined once in `registry.ts`. `AgentPosition.stance` is used consistently by `conflicts.ts`, `negotiation.ts`, `devilsAdvocate.ts`, and `synthesis.ts`. `recordUsage(bb, agent, model, usage)` keeps the same 4-arg signature at every call site in Task 13.

**Known placeholder to fix during execution:** Task 4's role prompts contain `[...copy spec §3.x verbatim]` markers. These are deliberate — the text is long and lives in the spec file rather than being duplicated here. Task 4's `role.length > 400` assertion fails until they are replaced, so they cannot ship by accident.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-29-virtual-company-backend.md`.

14 tasks, all backend. Task 13 produces the SSE contract document the UI engineer works from; Task 14 is the only task needing a real API key.
