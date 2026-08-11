# Engineering Mode — Plan 1: Backend session lifecycle

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Cloud Functions that create, drive, stream and durably record an Anthropic Managed Agents coding session against a founder's GitHub repo — drivable end-to-end from a terminal, before any Swift exists.

**Architecture:** Three `onRequest` handlers following the existing `companyChat` shape (`verifyAuth` → validate → work → SSE or JSON) plus one unauthenticated webhook. Every unit of real logic lands in a pure, jest-testable module (`engBudget`, `engEvents`, `engDiff`, `engWebhookCore`); the handlers are thin glue that does Firestore and network. This mirrors the `companyChat.ts` / `companyChatCore.ts` split already in the repo.

**Tech Stack:** TypeScript, Node 22, firebase-functions v2, firebase-admin, `@anthropic-ai/sdk` (Managed Agents beta), jest + ts-jest.

**Spec:** `docs/superpowers/specs/2026-08-11-engineering-mode-design.md`

## Global Constraints

- Region `us-central1`; Firebase project `devpet-8f4b1`. Set globally in `src/index.ts` — do not set per-function.
- **Never create a file named `.env` inside `functions/`.** `firebase deploy` loads every `.env*` as ordinary env vars, collides with `secrets:`, and fails with a 400. Local secrets go in `functions/local.env` (gitignored).
- **Deploy scoped only:** `firebase deploy --only functions:<name>`. A blanket deploy from a branch behind `main` deletes `main`'s functions from prod.
- Beta header for Managed Agents is `managed-agents-2026-04-01`. The SDK sets it automatically on `client.beta.{agents,environments,sessions}.*` — do not pass it by hand.
- Model for engineering runs: `claude-opus-5`. (Open decision in the spec §11 is Opus 5 vs. Sonnet 5 — this plan hardcodes one constant, `ENG_MODEL`, so the switch is one line.)
- Session budget currency is `USD` only; `amount` is an **integer string in cents** with no leading zeros (`"2500"` = $25.00). Decimal forms like `"25.00"` are rejected.
- Agents are created **once at deploy**, never in a request path.
- Every new pure module gets a `__tests__/*.test.ts` sibling. `npm test` must pass before any commit.

---

### Task 1: Prove Managed Agents access (spike — do this before anything else)

This task exists to answer the spec's blocking open question: does our Anthropic account have Managed Agents beta access at all? **If this task fails, stop and escalate — Plans 1–4 are all void and the fallback is the already-merged local runner.**

This is a throwaway spike, not shipped code. It is the one task in this plan without a test-first cycle.

**Files:**
- Create: `functions/scripts/spike-cma-access.ts` (throwaway — deleted in Step 6)

**Interfaces:**
- Consumes: nothing
- Produces: a yes/no answer, and the confirmed SDK version that exposes `client.beta.agents`

- [ ] **Step 1: Check whether the pinned SDK exposes the Managed Agents surface**

```bash
cd ~/Developer/codepet/functions
node -e "const A=require('@anthropic-ai/sdk');const c=new A({apiKey:'x'});console.log('agents:',!!c.beta?.agents,'sessions:',!!c.beta?.sessions,'environments:',!!c.beta?.environments)"
```

Expected: `agents: true sessions: true environments: true`.

If any is `false`, upgrade and re-run:

```bash
npm install @anthropic-ai/sdk@latest
node -e "const A=require('@anthropic-ai/sdk');const c=new A({apiKey:'x'});console.log('agents:',!!c.beta?.agents)"
```

- [ ] **Step 2: Write the spike script**

```typescript
// functions/scripts/spike-cma-access.ts
// THROWAWAY. Proves the account can create a Managed Agents session with a
// GitHub repo mounted, and that events stream back. Delete after answering.
import Anthropic from "@anthropic-ai/sdk";

async function main(): Promise<void> {
  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

  const environment = await client.beta.environments.create({
    name: `spike-${process.pid}`,
    config: { type: "cloud", networking: { type: "unrestricted" } }
  });
  console.log("environment:", environment.id);

  const agent = await client.beta.agents.create({
    name: "Spike Engineer",
    model: "claude-opus-5",
    system: "You are a coding agent. Be brief.",
    tools: [{ type: "agent_toolset_20260401" }]
  });
  console.log("agent:", agent.id, "v", agent.version);

  const session = await client.beta.sessions.create({
    agent: { type: "agent", id: agent.id, version: agent.version },
    environment_id: environment.id,
    title: "spike",
    resources: [
      {
        type: "github_repository",
        url: process.env.SPIKE_REPO_URL!,
        authorization_token: process.env.SPIKE_GITHUB_TOKEN!,
        mount_path: "/workspace/repo"
      }
    ],
    budget: { type: "limit", max_list_cost: { amount: "100", currency: "USD" } }
  });
  console.log("session:", session.id, session.status);
  console.log(`trace: https://platform.claude.com/workspaces/default/sessions/${session.id}`);

  // Stream FIRST, then send — the stream only delivers events emitted after it opens.
  const stream = await client.beta.sessions.events.stream(session.id);
  await client.beta.sessions.events.send(session.id, {
    events: [
      {
        type: "user.message",
        content: [{ type: "text", text: "List the files at the repo root, then stop." }]
      }
    ]
  });

  for await (const event of stream) {
    console.log("<-", event.type);
    if (event.type === "agent.message") {
      for (const block of event.content) {
        if (block.type === "text") process.stdout.write(block.text);
      }
    }
    if (event.type === "session.status_terminated") break;
    if (event.type === "session.status_idle" && event.stop_reason?.type !== "requires_action") break;
  }

  await client.beta.sessions.archive(session.id);
  console.log("\nOK — Managed Agents is reachable and the repo mounted.");
}

main().catch((err) => {
  console.error("SPIKE FAILED:", err);
  process.exit(1);
});
```

- [ ] **Step 3: Create a scratch repo and a fine-grained token**

On GitHub, create a private repo `codepet-cma-spike` with a README. Mint a fine-grained PAT scoped to **that repo only**, `Contents: Read and write`.

- [ ] **Step 4: Run the spike**

```bash
cd ~/Developer/codepet/functions
ANTHROPIC_API_KEY="$(grep ANTHROPIC_API_KEY local.env | cut -d= -f2-)" \
SPIKE_REPO_URL="https://github.com/<owner>/codepet-cma-spike" \
SPIKE_GITHUB_TOKEN="github_pat_..." \
npx ts-node --compilerOptions '{"module":"commonjs"}' scripts/spike-cma-access.ts
```

Expected: environment id, agent id, session id, a stream of `session.status_running` / `agent.tool_use` / `agent.message` events, the repo's root files listed, and `OK — Managed Agents is reachable`.

**Failure triage — the answer to the blocker is in the error:**

| Error | Means |
|---|---|
| `404` on `/v1/environments` or "unknown beta" | **No Managed Agents access.** STOP. Escalate to Giang; the plan is void. |
| `403` / `permission_error` | Access exists but the key's workspace lacks it. Check which workspace the key belongs to. |
| `400` naming `max_list_cost` | Budget shape drifted from this plan. Re-read the current field spec and fix Task 2 to match before continuing. |
| Auth failure cloning the repo | Token scope, not CMA. Re-mint with `Contents: Read and write`. |

- [ ] **Step 5: Record the answer**

Write the outcome into the spec's open-questions section — the concrete SDK version, the environment/agent ids created, and whether it worked. A later reader must not have to re-run this.

- [ ] **Step 6: Delete the spike and commit the SDK bump only**

```bash
cd ~/Developer/codepet
rm functions/scripts/spike-cma-access.ts
git add functions/package.json functions/package-lock.json docs/superpowers/specs/2026-08-11-engineering-mode-design.md
git commit -F- <<'EOF'
chore(functions): confirm Managed Agents access, pin the SDK that exposes it

The spec's blocking open question was whether our account can create
Managed Agents sessions at all. It can: a session with a GitHub repo
mounted streamed tool events back and archived cleanly.

Records the answer in the spec so nobody re-runs the spike, and pins the
SDK version whose `client.beta.agents` surface we verified by hand. The
spike script itself is deleted — it proved a fact, it isn't a fixture.
EOF
```

---

### Task 2: Credits → session budget (pure)

**Files:**
- Create: `functions/src/engineering/engBudget.ts`
- Test: `functions/src/engineering/__tests__/engBudget.test.ts`

**Interfaces:**
- Consumes: nothing
- Produces: `creditsToBudget(credits: number): SessionBudget`, `listCostToCredits(cents: number): number`, `CREDIT_CENTS`, `DEFAULT_RUN_CREDITS`, and `type SessionBudget = { type: "limit"; max_list_cost: { amount: string; currency: "USD" } }`

- [ ] **Step 1: Write the failing test**

```typescript
// functions/src/engineering/__tests__/engBudget.test.ts
import {
  creditsToBudget,
  listCostToCredits,
  CREDIT_CENTS,
  DEFAULT_RUN_CREDITS
} from "../engBudget";

describe("creditsToBudget", () => {
  it("converts credits to an integer-cents string", () => {
    expect(creditsToBudget(40)).toEqual({
      type: "limit",
      max_list_cost: { amount: "200", currency: "USD" }
    });
  });

  it("never emits a decimal amount — the API rejects '25.00'", () => {
    const { amount } = creditsToBudget(7).max_list_cost;
    expect(amount).toMatch(/^[1-9][0-9]*$/);
  });

  it("rounds a fractional credit balance down, so we never over-grant", () => {
    // 7.9 credits * 5c = 39.5c → 39, not 40
    expect(creditsToBudget(7.9).max_list_cost.amount).toBe("39");
  });

  it("floors at one cent — a zero amount is rejected by the API", () => {
    expect(creditsToBudget(0).max_list_cost.amount).toBe("1");
    expect(creditsToBudget(-5).max_list_cost.amount).toBe("1");
  });

  it("caps a large balance at the per-run ceiling", () => {
    // A founder with 800 credits still gets a 40-credit run, not an 800-credit one.
    expect(creditsToBudget(800)).toEqual(creditsToBudget(DEFAULT_RUN_CREDITS));
  });
});

describe("listCostToCredits", () => {
  it("rounds spend up, so a partial credit is charged", () => {
    expect(listCostToCredits(1)).toBe(1);
    expect(listCostToCredits(5)).toBe(1);
    expect(listCostToCredits(6)).toBe(2);
  });

  it("charges nothing for a session that never ran", () => {
    expect(listCostToCredits(0)).toBe(0);
  });

  it("round-trips against CREDIT_CENTS", () => {
    expect(listCostToCredits(CREDIT_CENTS * 12)).toBe(12);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engBudget.test.ts`
Expected: FAIL — `Cannot find module '../engBudget'`

- [ ] **Step 3: Write the implementation**

```typescript
// functions/src/engineering/engBudget.ts
//
// Credits ↔ the session budget Managed Agents enforces.
//
// This is the whole of our spend enforcement for engineering runs. The
// platform refuses to start a model request once a session's list cost
// reaches the cap, so a bug here is not "we mis-report usage" — it is
// "a founder's run can outspend their balance". Hence: round the grant
// DOWN and the charge UP, and cap every run regardless of balance.

/** One credit, in cents. Matches the $0.05/credit overage rate. */
export const CREDIT_CENTS = 5;

/**
 * Per-run ceiling, in credits. A run that needs more than this is a run
 * that has gone wrong; the session pauses at `budget_reached` and the
 * founder decides whether to raise it. Proposed in spec §6, pending
 * closed-beta calibration.
 */
export const DEFAULT_RUN_CREDITS = 40;

export interface SessionBudget {
  type: "limit";
  max_list_cost: { amount: string; currency: "USD" };
}

/**
 * The budget to attach to a session, given the founder's remaining credits.
 *
 * Two deliberate asymmetries: the balance is floored (never grant a fraction
 * of a credit the founder doesn't have) and the result is capped at
 * DEFAULT_RUN_CREDITS (a rich balance is not permission for one runaway run).
 * The one-cent floor exists because the API rejects a zero or negative amount
 * outright — a founder at zero credits should be stopped by our own balance
 * check with a clear message, not by a 400 from Anthropic.
 */
export function creditsToBudget(credits: number): SessionBudget {
  const grantable = Math.min(Math.floor(credits * CREDIT_CENTS), DEFAULT_RUN_CREDITS * CREDIT_CENTS);
  const amount = Math.max(1, grantable);
  return { type: "limit", max_list_cost: { amount: String(amount), currency: "USD" } };
}

/** What to debit once a session reports its final list cost, in cents. */
export function listCostToCredits(cents: number): number {
  if (cents <= 0) return 0;
  return Math.ceil(cents / CREDIT_CENTS);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engBudget.test.ts`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add functions/src/engineering/engBudget.ts functions/src/engineering/__tests__/engBudget.test.ts
git commit -F- <<'EOF'
feat(eng): credits ↔ Managed Agents session budget

The session budget is our entire spend enforcement for engineering runs —
the platform stops issuing model requests once a session's list cost hits
the cap — so this module is deliberately paranoid in one direction: the
grant rounds down, the charge rounds up, and every run is capped at
DEFAULT_RUN_CREDITS no matter how large the balance.

The one-cent floor is not a rounding nicety. A zero or negative amount is
a 400 from the API, and a founder out of credits deserves our own message
rather than an upstream error, so the floor keeps the failure ours.
EOF
```

---

### Task 3: CMA event → exec step (pure)

The native client renders `ExecStep` rows. This maps the CMA event stream onto that shape server-side, so both the live SSE relay and the webhook backfill produce identical rows.

**Files:**
- Create: `functions/src/engineering/engEvents.ts`
- Test: `functions/src/engineering/__tests__/engEvents.test.ts`

**Interfaces:**
- Consumes: nothing
- Produces: `toExecStep(event: unknown): ExecStep | null`, `type ExecStep = { id: string; label: string; done: boolean }`

- [ ] **Step 1: Write the failing test**

```typescript
// functions/src/engineering/__tests__/engEvents.test.ts
import { toExecStep } from "../engEvents";

describe("toExecStep", () => {
  it("labels a bash tool use with the command", () => {
    expect(
      toExecStep({
        type: "agent.tool_use",
        id: "sevt_1",
        name: "bash",
        input: { command: "npm test" }
      })
    ).toEqual({ id: "sevt_1", label: "ran npm test", done: false });
  });

  it("labels a file edit with the path, not the whole payload", () => {
    expect(
      toExecStep({
        type: "agent.tool_use",
        id: "sevt_2",
        name: "edit",
        input: { path: "/workspace/repo/api/billing.ts", old_str: "a", new_str: "b" }
      })
    ).toEqual({ id: "sevt_2", label: "edited api/billing.ts", done: false });
  });

  it("strips the mount prefix so the founder sees a repo-relative path", () => {
    const step = toExecStep({
      type: "agent.tool_use",
      id: "sevt_3",
      name: "read",
      input: { path: "/workspace/repo/src/deep/file.ts" }
    });
    expect(step?.label).toBe("read src/deep/file.ts");
  });

  it("marks the matching tool_result as done", () => {
    expect(
      toExecStep({ type: "agent.tool_result", id: "sevt_9", tool_use_id: "sevt_1" })
    ).toEqual({ id: "sevt_1", label: "", done: true });
  });

  it("returns null for events that are not steps", () => {
    expect(toExecStep({ type: "agent.message", id: "sevt_4", content: [] })).toBeNull();
    expect(toExecStep({ type: "session.status_running", id: "sevt_5" })).toBeNull();
  });

  it("survives a tool_use with no recognised input rather than crashing the stream", () => {
    const step = toExecStep({ type: "agent.tool_use", id: "sevt_6", name: "mystery", input: {} });
    expect(step).toEqual({ id: "sevt_6", label: "mystery", done: false });
  });

  it("truncates a long command so one step can't blow out the card", () => {
    const step = toExecStep({
      type: "agent.tool_use",
      id: "sevt_7",
      name: "bash",
      input: { command: "x".repeat(300) }
    });
    expect(step!.label.length).toBeLessThanOrEqual(88);
    expect(step!.label.endsWith("…")).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engEvents.test.ts`
Expected: FAIL — `Cannot find module '../engEvents'`

- [ ] **Step 3: Write the implementation**

```typescript
// functions/src/engineering/engEvents.ts
//
// CMA session events → the ExecStep rows the run card renders.
//
// Pure on purpose: the live SSE relay and the webhook backfill both call
// this, and a founder who watched a run must see the same rows as one who
// closed the app and came back. Two code paths producing two different
// transcripts of the same run is the bug this shape prevents.

/** The mount path every session uses; see engRepo.MOUNT_PATH. */
const MOUNT_PREFIX = "/workspace/repo/";

/** Longest label a step row can carry before the card starts wrapping badly. */
const MAX_LABEL = 88;

export interface ExecStep {
  id: string;
  label: string;
  /** A `done: true` step with an empty label is a completion marker for `id`. */
  done: boolean;
}

function relPath(p: unknown): string | null {
  if (typeof p !== "string" || p.length === 0) return null;
  return p.startsWith(MOUNT_PREFIX) ? p.slice(MOUNT_PREFIX.length) : p;
}

function truncate(s: string): string {
  return s.length <= MAX_LABEL ? s : s.slice(0, MAX_LABEL - 1) + "…";
}

function label(name: string, input: Record<string, unknown>): string {
  const path = relPath(input.path);
  switch (name) {
    case "bash":
      return typeof input.command === "string" ? `ran ${input.command}` : "ran a command";
    case "read":
      return path ? `read ${path}` : "read a file";
    case "write":
      return path ? `created ${path}` : "created a file";
    case "edit":
      return path ? `edited ${path}` : "edited a file";
    case "glob":
    case "grep":
      return typeof input.pattern === "string" ? `searched ${input.pattern}` : "searched";
    case "web_search":
      return typeof input.query === "string" ? `searched the web: ${input.query}` : "searched the web";
    default:
      // An unrecognised tool is still worth showing — the founder should see
      // that *something* happened, and a new built-in tool must not blank the
      // transcript or throw mid-stream.
      return name;
  }
}

/**
 * One event → one step row, or null when the event isn't step-shaped.
 *
 * Never throws. A malformed event drops out of the transcript; it does not
 * take the stream down with it.
 */
export function toExecStep(event: unknown): ExecStep | null {
  if (typeof event !== "object" || event === null) return null;
  const e = event as Record<string, unknown>;

  if (e.type === "agent.tool_use" || e.type === "agent.mcp_tool_use") {
    const id = typeof e.id === "string" ? e.id : null;
    const name = typeof e.name === "string" ? e.name : "tool";
    if (!id) return null;
    const input = (typeof e.input === "object" && e.input !== null ? e.input : {}) as Record<string, unknown>;
    return { id, label: truncate(label(name, input)), done: false };
  }

  if (e.type === "agent.tool_result" || e.type === "agent.mcp_tool_result") {
    const target = typeof e.tool_use_id === "string" ? e.tool_use_id : null;
    if (!target) return null;
    return { id: target, label: "", done: true };
  }

  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engEvents.test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add functions/src/engineering/engEvents.ts functions/src/engineering/__tests__/engEvents.test.ts
git commit -F- <<'EOF'
feat(eng): map CMA session events to ExecStep rows

Kept pure and shared because two paths produce this transcript — the live
SSE relay and the webhook that backfills a run the founder closed the app
on. If those two disagreed, the same run would read differently depending
on whether anyone was watching it, which is exactly the kind of quiet
inconsistency a founder learns not to trust.

An unrecognised tool degrades to its own name rather than returning null:
a new built-in tool should leave a visible gap in the story, not an
invisible one. Nothing here throws — a malformed event drops a row, it
does not kill the stream.
EOF
```

---

### Task 4: GitHub compare → file diffs (pure)

**Files:**
- Create: `functions/src/engineering/engDiff.ts`
- Test: `functions/src/engineering/__tests__/engDiff.test.ts`

**Interfaces:**
- Consumes: nothing
- Produces: `parseCompare(payload: unknown): DiffSummary`, `type FileDiff = { file: string; path: string; additions: number; deletions: number; status: string; patch: string | null }`, `type DiffSummary = { files: FileDiff[]; additions: number; deletions: number; truncated: boolean }`

- [ ] **Step 1: Write the failing test**

```typescript
// functions/src/engineering/__tests__/engDiff.test.ts
import { parseCompare } from "../engDiff";

const compare = {
  files: [
    { filename: "api/billing.ts", additions: 62, deletions: 0, status: "added", patch: "@@ -0,0 +1,62 @@\n+import Stripe" },
    { filename: "web/Checkout.tsx", additions: 21, deletions: 14, status: "modified", patch: "@@ -1,4 +1,5 @@\n-old\n+new" },
    { filename: "assets/logo.png", additions: 0, deletions: 0, status: "added" }
  ]
};

describe("parseCompare", () => {
  it("extracts one entry per changed file", () => {
    expect(parseCompare(compare).files).toHaveLength(3);
  });

  it("totals additions and deletions across files", () => {
    const summary = parseCompare(compare);
    expect(summary.additions).toBe(83);
    expect(summary.deletions).toBe(14);
  });

  it("keeps a binary file with a null patch rather than dropping it", () => {
    const binary = parseCompare(compare).files.find((f) => f.path === "assets/logo.png");
    expect(binary).toEqual({ path: "assets/logo.png", additions: 0, deletions: 0, status: "added", patch: null });
  });

  it("flags a truncated compare so the UI can say so", () => {
    // GitHub caps the compare response at 300 files.
    const many = { files: Array.from({ length: 300 }, (_, i) => ({ filename: `f${i}.ts`, additions: 1, deletions: 0, status: "added", patch: "@@" })) };
    expect(parseCompare(many).truncated).toBe(true);
    expect(parseCompare(compare).truncated).toBe(false);
  });

  it("reads the new name for a rename, and keeps the old one visible", () => {
    const renamed = { files: [{ filename: "b.ts", previous_filename: "a.ts", additions: 0, deletions: 0, status: "renamed" }] };
    expect(parseCompare(renamed).files[0].path).toBe("a.ts → b.ts");
  });

  it("returns an empty summary for a compare with no changes", () => {
    expect(parseCompare({ files: [] })).toEqual({ files: [], additions: 0, deletions: 0, truncated: false });
  });

  it("returns an empty summary rather than throwing on a malformed payload", () => {
    expect(parseCompare(null)).toEqual({ files: [], additions: 0, deletions: 0, truncated: false });
    expect(parseCompare({ files: "nope" })).toEqual({ files: [], additions: 0, deletions: 0, truncated: false });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engDiff.test.ts`
Expected: FAIL — `Cannot find module '../engDiff'`

- [ ] **Step 3: Write the implementation**

```typescript
// functions/src/engineering/engDiff.ts
//
// GitHub's compare payload → the diff the Review pane renders.
//
// The diff deliberately comes from GitHub rather than from parsing what the
// agent said it did. The agent's narration is a claim; `base...head` is the
// fact. It also gives all three review scopes (branch, last turn, a single
// commit) from the same call, because each is just a different base.

/** GitHub caps a compare response at 300 files. */
const COMPARE_FILE_CAP = 300;

export interface FileDiff {
  /** The file's current name — what consumers key off when fetching contents.
   * For a rename, `file` is the new name; `path` is the display label. */
  file: string;
  /** Display label. For a rename, shows "old → new"; otherwise equals `file`. */
  path: string;
  additions: number;
  deletions: number;
  status: string;
  /** null for binary files — GitHub omits the patch. */
  patch: string | null;
}

export interface DiffSummary {
  files: FileDiff[];
  additions: number;
  deletions: number;
  /** True when GitHub hit its file cap and the list is incomplete. */
  truncated: boolean;
}

// A function, not a shared `const EMPTY` returned via `{ ...EMPTY }`. A spread is
// a SHALLOW copy, so every empty result would hand out the same `files` array
// instance — one caller doing `result.files.push(...)` would corrupt the constant
// for the life of the warm process, including later calls with good payloads.
function emptyDiffSummary(): DiffSummary {
  return { files: [], additions: 0, deletions: 0, truncated: false };
}

function num(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

export function parseCompare(payload: unknown): DiffSummary {
  if (typeof payload !== "object" || payload === null) return emptyDiffSummary();
  const raw = (payload as Record<string, unknown>).files;
  if (!Array.isArray(raw)) return emptyDiffSummary();

  const files: FileDiff[] = [];
  let additions = 0;
  let deletions = 0;

  // Derived from the RAW length, before filtering. Deriving it from the output
  // array instead means a genuinely capped 300-file response containing one
  // malformed entry reports `truncated: false` — the UI then tells the founder
  // it is showing the whole change while hiding part of it.
  const truncated = raw.length >= COMPARE_FILE_CAP;

  for (const entry of raw) {
    if (typeof entry !== "object" || entry === null) continue;
    const f = entry as Record<string, unknown>;
    if (typeof f.filename !== "string") continue;

    // A rename with no content change would otherwise show as a file that
    // appeared from nowhere. Showing both names costs one arrow and saves
    // the founder wondering where the old file went.
    const path =
      typeof f.previous_filename === "string" ? `${f.previous_filename} → ${f.filename}` : f.filename;

    const add = num(f.additions);
    const del = num(f.deletions);
    additions += add;
    deletions += del;

    files.push({
      // The identity, separate from the label above. A consumer fetching the
      // file or anchoring a review comment to file:line needs a real path;
      // for a rename, `path` names no file that exists.
      file: typeof f.filename === "string" ? f.filename : "",
      path,
      additions: add,
      deletions: del,
      status: typeof f.status === "string" ? f.status : "modified",
      // Binary files carry no patch. Keep the row — "we changed your logo"
      // is information even when we cannot show the bytes.
      patch: typeof f.patch === "string" ? f.patch : null
    });
  }

  return { files, additions, deletions, truncated };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engDiff.test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add functions/src/engineering/engDiff.ts functions/src/engineering/__tests__/engDiff.test.ts
git commit -F- <<'EOF'
feat(eng): parse a GitHub compare into the review pane's diff

The diff comes from `base...head` rather than from parsing the agent's own
account of what it changed. The narration is a claim; the compare is the
fact, and a founder approving a change deserves the second one. It also
means all three review scopes fall out of one call — branch, last turn and
a single commit differ only in the base.

Binary files keep a row with a null patch instead of being filtered out:
"your logo changed" is worth knowing even when the bytes aren't renderable.
Renames show both names, so a file never appears to arrive from nowhere.
EOF
```

---

### Task 5: Resolve the founder's repo and token

**Files:**
- Create: `functions/src/engineering/engRepo.ts`
- Test: `functions/src/engineering/__tests__/engRepo.test.ts`

**Interfaces:**
- Consumes: `openToken` and `SealedToken` from `../oauth/githubOAuthCore`
- Produces: `MOUNT_PATH`, `parseRepoUrl(url: string): { owner: string; repo: string } | null`, `branchName(runId: string): string`, `loadRepo(uid: string, encKey: string): Promise<RepoLink | null>`, `type RepoLink = { url: string; owner: string; repo: string; defaultBranch: string; token: string }`

- [ ] **Step 1: Write the failing test**

```typescript
// functions/src/engineering/__tests__/engRepo.test.ts
import { parseRepoUrl, branchName, MOUNT_PATH } from "../engRepo";

describe("parseRepoUrl", () => {
  it("reads owner and repo from an https URL", () => {
    expect(parseRepoUrl("https://github.com/My-Outcasts/codepet")).toEqual({
      owner: "My-Outcasts",
      repo: "codepet"
    });
  });

  it("tolerates a trailing .git and a trailing slash", () => {
    expect(parseRepoUrl("https://github.com/a/b.git")).toEqual({ owner: "a", repo: "b" });
    expect(parseRepoUrl("https://github.com/a/b/")).toEqual({ owner: "a", repo: "b" });
  });

  it("rejects anything that is not a GitHub repo URL", () => {
    expect(parseRepoUrl("https://gitlab.com/a/b")).toBeNull();
    expect(parseRepoUrl("https://github.com/a")).toBeNull();
    expect(parseRepoUrl("not a url")).toBeNull();
    expect(parseRepoUrl("")).toBeNull();
  });
});

describe("branchName", () => {
  it("namespaces every branch under codepet/", () => {
    expect(branchName("abc123")).toBe("codepet/run-abc123");
  });

  it("is stable for a run id, so a retry reuses the branch", () => {
    expect(branchName("abc123")).toBe(branchName("abc123"));
  });
});

describe("MOUNT_PATH", () => {
  it("matches the prefix engEvents strips from tool paths", () => {
    // engEvents.MOUNT_PREFIX is MOUNT_PATH + "/". If these drift, every step
    // row shows an absolute container path instead of a repo-relative one.
    expect(MOUNT_PATH).toBe("/workspace/repo");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engRepo.test.ts`
Expected: FAIL — `Cannot find module '../engRepo'`

- [ ] **Step 3: Write the implementation**

```typescript
// functions/src/engineering/engRepo.ts
//
// Which repo an engineering run works on, and the token that reaches it.
//
// The token is read here and handed to the session's `github_repository`
// resource — it is never written into a prompt, a system message, or an
// event. Managed Agents injects it into git traffic *after* the request
// leaves the sandbox, so nothing running in the container can read it.
import * as admin from "firebase-admin";
import { openToken, type SealedToken } from "../oauth/githubOAuthCore";

/** Where the repo is mounted in every session container. */
export const MOUNT_PATH = "/workspace/repo";

export interface RepoLink {
  url: string;
  owner: string;
  repo: string;
  defaultBranch: string;
  token: string;
}

interface RepoDoc {
  url?: string;
  defaultBranch?: string;
  sealed?: SealedToken;
}

const GITHUB_URL = /^https:\/\/github\.com\/([^/\s]+)\/([^/\s]+?)(?:\.git)?\/?$/;

export function parseRepoUrl(url: string): { owner: string; repo: string } | null {
  const m = GITHUB_URL.exec(url.trim());
  if (!m) return null;
  return { owner: m[1], repo: m[2] };
}

/**
 * One branch per run, namespaced so a founder can tell at a glance which
 * branches on their repo are ours. Derived from the run id rather than the
 * ask, so a retry lands on the same branch instead of forking a new one.
 */
export function branchName(runId: string): string {
  return `codepet/run-${runId}`;
}

/**
 * The founder's linked repo, or null when they have not connected one.
 *
 * Unlike `loadConnectors`, this does NOT fail open. A chat turn without a
 * connector is a slightly worse answer; an engineering run without a repo
 * has nothing to work on, and starting one anyway would burn credits to
 * produce nothing. The caller turns null into the connect-or-create prompt.
 */
export async function loadRepo(uid: string, encKey: string): Promise<RepoLink | null> {
  const snap = await admin.firestore().doc(`companies/${uid}/engineering/repo`).get();
  if (!snap.exists) return null;

  const data = snap.data() as RepoDoc;
  if (!data.url || !data.sealed) return null;

  const parsed = parseRepoUrl(data.url);
  if (!parsed) return null;

  let token: string;
  try {
    token = openToken(data.sealed, encKey);
  } catch {
    // A tampered or unreadable blob. Never log the error — it can echo
    // ciphertext. Treat it as "no repo linked" so the founder is asked to
    // reconnect rather than shown a decryption failure.
    return null;
  }

  return {
    url: data.url,
    owner: parsed.owner,
    repo: parsed.repo,
    defaultBranch: data.defaultBranch ?? "main",
    token
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engRepo.test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/codepet
git add functions/src/engineering/engRepo.ts functions/src/engineering/__tests__/engRepo.test.ts
git commit -F- <<'EOF'
feat(eng): resolve the founder's linked repo and its token

Deliberately does NOT fail open, unlike loadConnectors. A chat turn missing
a connector still produces a useful answer; an engineering run missing a
repo has nothing to work on, so starting one anyway would spend a founder's
credits to accomplish nothing. Returning null lets the caller show the
connect-or-create prompt instead.

An unreadable sealed blob is treated as "no repo linked" rather than as an
error, for the same reason and one more: the decryption failure could echo
ciphertext into a log.

MOUNT_PATH is asserted in the test against the prefix engEvents strips. If
the two drift, every step row silently shows an absolute container path.
EOF
```

---

### Task 6: `engStartRun` — create the session

**Files:**
- Create: `functions/src/engineering/engStartRun.ts`
- Create: `functions/src/engineering/engClient.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/engineering/__tests__/engStartRun.test.ts`

**Interfaces:**
- Consumes: `creditsToBudget` (Task 2), `loadRepo` / `MOUNT_PATH` / `branchName` (Task 5)
- Produces: `handleEngStartRun(req, res)`, `buildSessionParams(...)` (pure, tested), `getEngClient()`, `ENG_MODEL`, `ENG_AGENT_ID_ENV`

- [ ] **Step 1: Write the failing test for the pure half**

```typescript
// functions/src/engineering/__tests__/engStartRun.test.ts
import { buildSessionParams } from "../engStartRun";

const repo = {
  url: "https://github.com/acme/widget",
  owner: "acme",
  repo: "widget",
  defaultBranch: "main",
  token: "github_pat_secret"
};

describe("buildSessionParams", () => {
  it("mounts the repo at the shared mount path", () => {
    const p = buildSessionParams({ agentId: "agent_1", agentVersion: 3, environmentId: "env_1", repo, credits: 40, ask: "add checkout", brief: "" });
    expect(p.resources).toEqual([
      {
        type: "github_repository",
        url: "https://github.com/acme/widget",
        authorization_token: "github_pat_secret",
        mount_path: "/workspace/repo",
        checkout: { type: "branch", name: "main" }
      }
    ]);
  });

  it("pins the agent version, so a mid-run agent update cannot change behaviour", () => {
    const p = buildSessionParams({ agentId: "agent_1", agentVersion: 3, environmentId: "env_1", repo, credits: 40, ask: "x", brief: "" });
    expect(p.agent).toMatchObject({ type: "agent_with_overrides", id: "agent_1", version: 3 });
  });

  it("attaches a budget derived from the founder's credits", () => {
    const p = buildSessionParams({ agentId: "a", agentVersion: 1, environmentId: "e", repo, credits: 10, ask: "x", brief: "" });
    expect(p.budget).toEqual({ type: "limit", max_list_cost: { amount: "50", currency: "USD" } });
  });

  it("puts the company brief in the system override, never in the user message", () => {
    const p = buildSessionParams({ agentId: "a", agentVersion: 1, environmentId: "e", repo, credits: 5, ask: "add checkout", brief: "Acme sells widgets." });
    expect(p.agent.system).toContain("Acme sells widgets.");
    const firstEvent = p.initial_events[0] as { content: Array<{ text: string }> };
    expect(firstEvent.content[0].text).toBe("add checkout");
    expect(firstEvent.content[0].text).not.toContain("Acme sells widgets.");
  });

  it("never puts the token anywhere but the repo resource", () => {
    const p = buildSessionParams({ agentId: "a", agentVersion: 1, environmentId: "e", repo, credits: 5, ask: "x", brief: "y" });
    const withoutResources = JSON.stringify({ ...p, resources: [] });
    expect(withoutResources).not.toContain("github_pat_secret");
  });

  it("starts the run in the same call, so the session never sits idle", () => {
    const p = buildSessionParams({ agentId: "a", agentVersion: 1, environmentId: "e", repo, credits: 5, ask: "add checkout", brief: "" });
    expect(p.initial_events).toHaveLength(1);
    expect(p.initial_events[0].type).toBe("user.message");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engStartRun.test.ts`
Expected: FAIL — `Cannot find module '../engStartRun'`

- [ ] **Step 3: Write the shared client**

```typescript
// functions/src/engineering/engClient.ts
//
// One Anthropic client for every engineering handler, built lazily so the
// module can be imported by tests that never touch the network.
import Anthropic from "@anthropic-ai/sdk";

/**
 * The model engineering runs use. Spec §11 leaves Opus 5 vs. Sonnet 5 open
 * as a margin decision — this constant is the single place that changes.
 */
export const ENG_MODEL = "claude-opus-5";

/** Set at deploy from the agent created by `scripts/provision-eng-agent.ts`. */
export const ENG_AGENT_ID_ENV = "ENG_AGENT_ID";
export const ENG_AGENT_VERSION_ENV = "ENG_AGENT_VERSION";
export const ENG_ENVIRONMENT_ID_ENV = "ENG_ENVIRONMENT_ID";

let client: Anthropic | null = null;

export function getEngClient(): Anthropic {
  if (!client) client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  return client;
}
```

- [ ] **Step 4: Write the handler**

```typescript
// functions/src/engineering/engStartRun.ts
//
// Start an engineering run: resolve the repo, size the budget from the
// founder's credits, create a Managed Agents session with the repo mounted,
// and record it. Returns as soon as the session exists — the transcript
// arrives over engStream, and the outcome is durable via engWebhook even if
// nobody connects.
// `firebase-functions/v2/https` exports Request but NOT Response — importing both
// from it is a TS2305. Every existing handler in this repo (runTask.ts and ~10
// others) takes Response from express; match that.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { verifyAuth } from "../auth";
import { creditsToBudget, type SessionBudget } from "./engBudget";
import { loadRepo, branchName, MOUNT_PATH, type RepoLink } from "./engRepo";
import {
  getEngClient,
  ENG_AGENT_ID_ENV,
  ENG_AGENT_VERSION_ENV,
  ENG_ENVIRONMENT_ID_ENV,
  ENG_MODEL
} from "./engClient";

export interface SessionParams {
  agent: {
    type: "agent_with_overrides";
    id: string;
    version: number;
    system: string;
    model: string;
  };
  environment_id: string;
  title: string;
  resources: Array<Record<string, unknown>>;
  budget: SessionBudget;
  initial_events: Array<{ type: string; content: Array<{ type: "text"; text: string }> }>;
}

function systemFor(repo: RepoLink, brief: string): string {
  return [
    "You are the engineering department of a founder's company.",
    `Their repository is mounted at ${MOUNT_PATH}; its default branch is ${repo.defaultBranch}.`,
    "",
    "Work on a branch, never on the default branch. Run the project's own tests",
    "before you report success, and say plainly when something fails rather than",
    "describing an intention as a result.",
    "",
    "The person reading your messages is a founder, not necessarily an engineer.",
    "Lead with what changed and what it means for their product; keep the",
    "implementation detail after that, for whoever wants it.",
    brief ? `\nAbout the company:\n${brief}` : ""
  ].join("\n");
}

/**
 * Pure: everything the session-create call needs.
 *
 * Split out from the handler because the security-relevant invariant lives
 * here — the GitHub token appears in the repo resource and nowhere else. A
 * test asserts that by serialising the params with resources removed.
 */
export function buildSessionParams(args: {
  agentId: string;
  agentVersion: number;
  environmentId: string;
  repo: RepoLink;
  credits: number;
  ask: string;
  brief: string;
}): SessionParams {
  return {
    // Overrides, not a bare id: the brief is per-founder, and versioning an
    // agent per user would be a new immutable object on every brief edit.
    // The version is pinned so an agent update mid-run cannot change how a
    // session already in flight behaves.
    agent: {
      type: "agent_with_overrides",
      id: args.agentId,
      version: args.agentVersion,
      system: systemFor(args.repo, args.brief),
      model: ENG_MODEL
    },
    environment_id: args.environmentId,
    title: args.ask.slice(0, 80),
    resources: [
      {
        type: "github_repository",
        url: args.repo.url,
        authorization_token: args.repo.token,
        mount_path: MOUNT_PATH,
        checkout: { type: "branch", name: args.repo.defaultBranch }
      }
    ],
    budget: creditsToBudget(args.credits),
    // Seeding the kickoff here means the session is created already running.
    // Creating it idle and then sending would be two round trips and a window
    // where a founder sees a run that exists but is doing nothing.
    initial_events: [{ type: "user.message", content: [{ type: "text", text: args.ask }] }]
  };
}

export async function handleEngStartRun(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const ask = typeof req.body?.ask === "string" ? req.body.ask.trim() : "";
  if (!ask) {
    res.status(400).json({ error: "invalid_payload", detail: "ask required" });
    return;
  }

  const encKey = process.env.CONNECTOR_ENC_KEY;
  if (!encKey) {
    res.status(500).json({ error: "misconfigured", detail: "CONNECTOR_ENC_KEY absent" });
    return;
  }

  const repo = await loadRepo(auth.uid, encKey);
  if (!repo) {
    // Not an error — the client renders connect-or-create from this.
    res.status(409).json({ error: "no_repo_linked" });
    return;
  }

  const db = admin.firestore();
  const companySnap = await db.doc(`companies/${auth.uid}`).get();
  const company = companySnap.data() ?? {};
  // `Number.isFinite`, not `typeof === "number"`: `typeof NaN === "number"` is
  // true, and `NaN <= 0` is false, so a corrupted balance field would sail past
  // a naive check and start a run. engBudget guards this too — the belt here is
  // so a founder with a broken balance gets an honest 402 rather than a one-cent
  // run that dies at its budget a second later.
  const credits = Number.isFinite(company.credits) ? (company.credits as number) : 0;
  if (credits <= 0) {
    res.status(402).json({ error: "no_credits" });
    return;
  }

  const agentId = process.env[ENG_AGENT_ID_ENV];
  const agentVersion = Number(process.env[ENG_AGENT_VERSION_ENV]);
  const environmentId = process.env[ENG_ENVIRONMENT_ID_ENV];
  if (!agentId || !environmentId || !Number.isFinite(agentVersion)) {
    res.status(500).json({ error: "misconfigured", detail: "engineering agent not provisioned" });
    return;
  }

  const runRef = db.collection(`companies/${auth.uid}/engRuns`).doc();
  const params = buildSessionParams({
    agentId,
    agentVersion,
    environmentId,
    repo,
    credits,
    ask,
    brief: typeof company.brief === "string" ? company.brief : ""
  });

  let sessionId: string;
  try {
    const session = await getEngClient().beta.sessions.create(params as never);
    sessionId = session.id;
  } catch (err) {
    res.status(502).json({ error: "session_create_failed", detail: String(err) });
    return;
  }

  await runRef.set({
    sessionId,
    ask,
    repo: repo.url,
    branch: branchName(runRef.id),
    baseBranch: repo.defaultBranch,
    status: "running",
    creditsSpent: 0,
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });

  res.status(200).json({ runId: runRef.id, sessionId });
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engStartRun.test.ts`
Expected: PASS, 6 tests.

- [ ] **Step 6: Register the function**

In `functions/src/index.ts`, add the import beside the others:

```typescript
import { handleEngStartRun } from "./engineering/engStartRun";
```

and the export after `runTask`:

```typescript
// The engineering coding agent. CONNECTOR_ENC_KEY opens the founder's stored
// GitHub token so the session can mount their repo; the token is handed to the
// session resource and never enters the container.
export const engStartRun = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY", "CONNECTOR_ENC_KEY"]
  },
  handleEngStartRun
);
```

- [ ] **Step 7: Typecheck and run the whole suite**

```bash
cd ~/Developer/codepet/functions && npm run build && npm test
```

Expected: `tsc` clean; every suite passes.

- [ ] **Step 8: Commit**

```bash
cd ~/Developer/codepet
git add functions/src/engineering/engClient.ts functions/src/engineering/engStartRun.ts functions/src/engineering/__tests__/engStartRun.test.ts functions/src/index.ts
git commit -F- <<'EOF'
feat(eng): engStartRun — create a Managed Agents session on the founder's repo

Uses agent_with_overrides rather than a bare agent id so the company brief
can ride in as the system prompt without minting a new immutable agent
version every time a founder edits their brief. The version is pinned, so
updating the agent cannot change how a session already in flight behaves.

initial_events seeds the kickoff in the create call: the session comes up
already running, instead of existing-but-idle for a round trip while a
founder watches nothing happen.

The security-relevant invariant — the GitHub token appears in the repo
resource and nowhere else — is asserted by serialising the params with
resources stripped and checking the secret is absent. Delete the resource
block and that test goes red.

No repo returns 409 and no credits returns 402 rather than a generic error:
both are states the client renders as an offer, not a failure.
EOF
```

---

### Task 7: `engStream` — SSE relay with reconnect dedupe

**Files:**
- Create: `functions/src/engineering/engStream.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/engineering/__tests__/engStream.test.ts`

**Interfaces:**
- Consumes: `toExecStep` (Task 3), `getEngClient` (Task 6)
- Produces: `handleEngStream(req, res)`, `dedupe(seen: Set<string>, event: {id?: unknown}): boolean`, `isTerminal(event: unknown): boolean`

- [ ] **Step 1: Write the failing test**

```typescript
// functions/src/engineering/__tests__/engStream.test.ts
import { dedupe, isTerminal } from "../engStream";

describe("dedupe", () => {
  it("passes an event the first time and blocks it after", () => {
    const seen = new Set<string>();
    const e = { id: "sevt_1" };
    expect(dedupe(seen, e)).toBe(true);
    expect(dedupe(seen, e)).toBe(false);
  });

  it("passes an event with no id — an interrupt echo can arrive id-less", () => {
    expect(dedupe(new Set(), {})).toBe(true);
  });
});

describe("isTerminal", () => {
  it("ends on termination", () => {
    expect(isTerminal({ type: "session.status_terminated" })).toBe(true);
  });

  it("ends on a completed turn", () => {
    expect(isTerminal({ type: "session.status_idle", stop_reason: { type: "end_turn" } })).toBe(true);
  });

  it("ends when the budget is reached — only a budget change resumes it", () => {
    expect(isTerminal({ type: "session.status_idle", stop_reason: { type: "budget_reached" } })).toBe(true);
  });

  it("does NOT end while the agent is waiting on the founder", () => {
    // A tool approval sits here. Breaking would strand the run.
    expect(isTerminal({ type: "session.status_idle", stop_reason: { type: "requires_action" } })).toBe(false);
  });

  it("does not end on ordinary activity", () => {
    expect(isTerminal({ type: "agent.message" })).toBe(false);
    expect(isTerminal({ type: "session.status_running" })).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engStream.test.ts`
Expected: FAIL — `Cannot find module '../engStream'`

- [ ] **Step 3: Write the implementation**

```typescript
// functions/src/engineering/engStream.ts
//
// Relay a session's events to the app as SSE.
//
// The reconnect contract is the point of this file. SSE has no replay, so a
// client that drops and reconnects would otherwise miss everything emitted
// in the gap. On every connect we open the live stream FIRST (it buffers
// from that moment), then read the full history, then tail — deduping by
// event id where the two overlap.
// `firebase-functions/v2/https` exports Request but NOT Response — importing both
// from it is a TS2305. Every existing handler in this repo (runTask.ts and ~10
// others) takes Response from express; match that.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { verifyAuth } from "../auth";
import { toExecStep } from "./engEvents";
import { getEngClient } from "./engClient";

function writeFrame(res: Response, event: string, payload: unknown): void {
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}

/** True the first time an id is seen. Id-less events always pass. */
export function dedupe(seen: Set<string>, event: { id?: unknown }): boolean {
  const id = typeof event.id === "string" ? event.id : null;
  if (!id) return true;
  if (seen.has(id)) return false;
  seen.add(id);
  return true;
}

/**
 * Whether to stop reading.
 *
 * `requires_action` is idle but NOT terminal — the agent is blocked on a tool
 * approval and will continue the moment one arrives. Breaking there is the
 * classic bug: the run looks finished and is actually waiting on a founder
 * who is no longer being shown anything to approve.
 */
export function isTerminal(event: unknown): boolean {
  if (typeof event !== "object" || event === null) return false;
  const e = event as Record<string, unknown>;
  if (e.type === "session.status_terminated") return true;
  if (e.type !== "session.status_idle") return false;
  const reason = (e.stop_reason as Record<string, unknown> | undefined)?.type;
  return reason !== "requires_action";
}

export async function handleEngStream(req: Request, res: Response): Promise<void> {
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const runId = typeof req.query.runId === "string" ? req.query.runId : "";
  if (!runId) {
    res.status(400).json({ error: "invalid_payload", detail: "runId required" });
    return;
  }

  const runRef = admin.firestore().doc(`companies/${auth.uid}/engRuns/${runId}`);
  const runSnap = await runRef.get();
  if (!runSnap.exists) {
    res.status(404).json({ error: "run_not_found" });
    return;
  }
  const sessionId = runSnap.data()?.sessionId as string | undefined;
  if (!sessionId) {
    res.status(409).json({ error: "run_has_no_session" });
    return;
  }

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.status(200);
  if (typeof (res as unknown as { flushHeaders?: () => void }).flushHeaders === "function") {
    (res as unknown as { flushHeaders: () => void }).flushHeaders();
  }

  const client = getEngClient();
  const seen = new Set<string>();

  const relay = (event: Record<string, unknown>): void => {
    const step = toExecStep(event);
    if (step) writeFrame(res, "step", step);
    if (event.type === "agent.message") {
      const blocks = Array.isArray(event.content) ? event.content : [];
      const text = blocks
        .filter((b): b is { type: string; text: string } =>
          typeof b === "object" && b !== null && (b as { type?: string }).type === "text")
        .map((b) => b.text)
        .join("");
      if (text) writeFrame(res, "message", { text });
    }
    if (event.type === "agent.tool_use" && (event as { evaluated_permission?: string }).evaluated_permission === "ask") {
      writeFrame(res, "approval", { toolUseId: event.id, name: event.name, input: event.input });
    }
  };

  try {
    // Order matters. Open the stream before listing history: the stream only
    // carries events emitted after it opens, so listing first leaves a gap
    // between the last history page and the first live event.
    const stream = await client.beta.sessions.events.stream(sessionId);

    for await (const past of client.beta.sessions.events.list(sessionId)) {
      const e = past as unknown as Record<string, unknown>;
      if (dedupe(seen, e)) relay(e);
    }

    for await (const live of stream) {
      const e = live as unknown as Record<string, unknown>;
      // Dedupe gates the relay only. The terminal check must run even for an
      // event we already saw in history, or a run that finished before the
      // client connected never closes the stream.
      if (dedupe(seen, e)) relay(e);
      if (isTerminal(e)) {
        writeFrame(res, "done", { runId, stopReason: (e.stop_reason as { type?: string })?.type ?? "end_turn" });
        break;
      }
    }
  } catch (err) {
    writeFrame(res, "error", { error: "stream_failed", detail: String(err) });
  } finally {
    res.end();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engStream.test.ts`
Expected: PASS, 7 tests.

- [ ] **Step 5: Register the function**

In `functions/src/index.ts`:

```typescript
import { handleEngStream } from "./engineering/engStream";
```

```typescript
// Long-lived SSE. timeoutSeconds is the v2 maximum (60 min); a run longer
// than that survives because engWebhook records the outcome independently.
export const engStream = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"],
    timeoutSeconds: 3600
  },
  handleEngStream
);
```

- [ ] **Step 6: Typecheck and run the whole suite**

```bash
cd ~/Developer/codepet/functions && npm run build && npm test
```

Expected: `tsc` clean; every suite passes.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet
git add functions/src/engineering/engStream.ts functions/src/engineering/__tests__/engStream.test.ts functions/src/index.ts
git commit -F- <<'EOF'
feat(eng): engStream — SSE relay with a lossless reconnect

SSE has no replay, so a dropped connection would otherwise lose every event
emitted in the gap. The fix is ordering: open the live stream first (it
buffers from that moment), then read history, then tail — deduping by event
id across the overlap.

Two guards with tests that go red if they're deleted. `requires_action` is
idle but not terminal: break there and a run blocked on a tool approval
looks finished while it waits on a founder who is no longer being shown
anything to approve. And dedupe gates the relay only, never the terminal
check — otherwise a run that finished before the client connected replays
its history and then hangs forever.
EOF
```

---

### Task 8: `engWebhook` — durable outcome

**Files:**
- Create: `functions/src/engineering/engWebhook.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/engineering/__tests__/engWebhook.test.ts`

**Interfaces:**
- Consumes: `listCostToCredits` (Task 2), `getEngClient` (Task 6)
- Produces: `handleEngWebhook(req, res)`, `statusFor(stopReason: string | undefined): RunStatus`, `type RunStatus = "running" | "reviewing" | "budgetReached" | "failed"`

- [ ] **Step 1: Write the failing test**

```typescript
// functions/src/engineering/__tests__/engWebhook.test.ts
import { statusFor } from "../engWebhook";

describe("statusFor", () => {
  it("maps a completed turn to reviewing — the diff is what comes next", () => {
    expect(statusFor("end_turn")).toBe("reviewing");
  });

  it("maps a budget pause to its own status, not to failed", () => {
    // The session is paused and resumable. Calling it failed would tell the
    // founder their work is gone when it is sitting there waiting.
    expect(statusFor("budget_reached")).toBe("budgetReached");
  });

  it("maps exhausted retries to failed", () => {
    expect(statusFor("retries_exhausted")).toBe("failed");
  });

  it("keeps a run that is waiting on the founder as running", () => {
    expect(statusFor("requires_action")).toBe("running");
  });

  it("treats an unknown stop reason as failed rather than silently reviewing", () => {
    expect(statusFor("something_new")).toBe("failed");
    expect(statusFor(undefined)).toBe("failed");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engWebhook.test.ts`
Expected: FAIL — `Cannot find module '../engWebhook'`

- [ ] **Step 3: Write the implementation**

```typescript
// functions/src/engineering/engWebhook.ts
//
// The durable half of a run.
//
// engStream only exists while the app holds a connection. This endpoint is
// what makes a run survive the founder quitting Codepet: Anthropic posts the
// session's terminal transition here, we fetch the finished session, debit
// the credits it actually spent, and write the outcome. Unauthenticated by
// necessity — Anthropic is the caller — so the HMAC signature is the only
// thing standing between this and a forged run record.
// `firebase-functions/v2/https` exports Request but NOT Response — importing both
// from it is a TS2305. Every existing handler in this repo (runTask.ts and ~10
// others) takes Response from express; match that.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { listCostToCredits } from "./engBudget";
import { getEngClient } from "./engClient";

export type RunStatus = "running" | "reviewing" | "budgetReached" | "failed";

/**
 * A session's stop reason → the run status the card renders.
 *
 * `budget_reached` gets its own status rather than folding into `failed`.
 * The session is paused, not dead: raising the budget resumes the work in
 * place. Telling a founder their run failed when it is sitting there intact
 * would make them start over and pay twice.
 *
 * Unknown reasons map to `failed`, not `reviewing`. If Anthropic adds a stop
 * reason we have not handled, the honest read is "we do not know that this
 * finished", not a card inviting a founder to ship an unverified diff.
 */
export function statusFor(stopReason: string | undefined): RunStatus {
  switch (stopReason) {
    case "end_turn":
      return "reviewing";
    case "budget_reached":
      return "budgetReached";
    case "requires_action":
      return "running";
    default:
      return "failed";
  }
}

export async function handleEngWebhook(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const client = getEngClient();
  let event: { id: string; data: { type: string; id: string } };
  try {
    // Verifies the HMAC and rejects a stale timestamp. `req.rawBody` — not
    // req.body — because re-serialising the JSON changes the bytes the MAC
    // was computed over.
    const raw = (req as unknown as { rawBody?: Buffer }).rawBody?.toString("utf8") ?? "";
    event = (await client.beta.webhooks.unwrap(raw, {
      headers: req.headers as Record<string, string>
    })) as typeof event;
  } catch {
    res.status(400).send("invalid signature");
    return;
  }

  const db = admin.firestore();

  // Deliveries retry, and the same event id arrives more than once. A
  // create-if-absent write is the dedupe: the second delivery loses the race
  // and returns early rather than debiting the founder twice.
  const seenRef = db.doc(`webhookEvents/${event.id}`);
  try {
    await seenRef.create({ at: admin.firestore.FieldValue.serverTimestamp() });
  } catch {
    res.status(204).send("");
    return;
  }

  if (event.data.type !== "session.status_idled" && event.data.type !== "session.status_terminated") {
    res.status(204).send("");
    return;
  }

  const sessionId = event.data.id;
  const matches = await db.collectionGroup("engRuns").where("sessionId", "==", sessionId).limit(1).get();
  if (matches.empty) {
    // Not ours, or the run record was deleted. Acknowledge — retrying will
    // not make it exist.
    res.status(204).send("");
    return;
  }
  const runRef = matches.docs[0].ref;

  const session = (await client.beta.sessions.retrieve(sessionId)) as unknown as {
    usage?: { list_cost?: { amount?: string } };
  };
  const events = await client.beta.sessions.events.list(sessionId);
  const lastIdle = [...events.data]
    .reverse()
    .find((e) => (e as unknown as { type?: string }).type === "session.status_idle") as
    | { stop_reason?: { type?: string } }
    | undefined;

  const cents = Number(session.usage?.list_cost?.amount ?? "0");
  const creditsSpent = listCostToCredits(Number.isFinite(cents) ? cents : 0);

  await runRef.set(
    {
      status: statusFor(lastIdle?.stop_reason?.type),
      creditsSpent,
      endedAt: admin.firestore.FieldValue.serverTimestamp()
    },
    { merge: true }
  );

  await runRef.parent.parent!.set(
    { credits: admin.firestore.FieldValue.increment(-creditsSpent) },
    { merge: true }
  );

  res.status(204).send("");
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engWebhook.test.ts`
Expected: PASS, 5 tests.

- [ ] **Step 5: Note the known test gap, then register the function**

The spec's test plan (§8) asks for a replayed-delivery test on the dedupe. It is **not** in Step 1, and the reason is worth stating rather than hiding: the dedupe *is* the Firestore `create` throwing on an existing doc, so there is no pure function to test. It needs the emulator.

Add this to `functions/src/engineering/__tests__/engWebhook.test.ts` as a skipped test with the reason attached, so the gap is visible in the suite rather than only in this document:

```typescript
// The dedupe guard — a create-if-absent write on the event id — is what
// stops a retried delivery debiting a founder twice. It cannot be tested
// without the Firestore emulator, because the guard IS the write failing.
// Unskip once the emulator is wired into CI; do not delete this instead.
it.skip("ignores a replayed delivery rather than double-debiting", () => {});
```

Then in `functions/src/index.ts`:

```typescript
import { handleEngWebhook } from "./engineering/engWebhook";
```

```typescript
// Reached by Anthropic, not by the app, so it is deliberately NOT
// authenticated — the HMAC signature verified inside the handler is what
// proves the caller. Mirrors githubOAuthCallback and revenueCatWebhook.
export const engWebhook = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY", "ANTHROPIC_WEBHOOK_SIGNING_KEY"]
  },
  handleEngWebhook
);
```

- [ ] **Step 6: Typecheck and run the whole suite**

```bash
cd ~/Developer/codepet/functions && npm run build && npm test
```

Expected: `tsc` clean; every suite passes.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet
git add functions/src/engineering/engWebhook.ts functions/src/engineering/__tests__/engWebhook.test.ts functions/src/index.ts
git commit -F- <<'EOF'
feat(eng): engWebhook — make a run outlive the app

engStream only exists while the app holds a connection, which would make
"start something big and close your laptop" a way to lose the result. This
records the outcome independently, so a run finishes whether or not anyone
is watching.

Unauthenticated by necessity — Anthropic is the caller — so the HMAC is the
only thing between this and a forged run record. It verifies against
req.rawBody rather than req.body, because re-serialising the JSON changes
the bytes the MAC covers.

Deliveries retry, so a create-if-absent write on the event id is the
dedupe; without it the second delivery debits the founder's credits twice.
budget_reached maps to its own status rather than to failed: the session is
paused and resumable, and telling a founder it failed would make them start
over and pay for the same work again.
EOF
```

---

### Task 9: `engSendTurn` — follow-ups

**Files:**
- Create: `functions/src/engineering/engSendTurn.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/src/engineering/__tests__/engSendTurn.test.ts`

**Interfaces:**
- Consumes: `getEngClient` (Task 6)
- Produces: `handleEngSendTurn(req, res)`, `buildTurnEvents(body: unknown): TurnEvent[] | null`

- [ ] **Step 1: Write the failing test**

```typescript
// functions/src/engineering/__tests__/engSendTurn.test.ts
import { buildTurnEvents } from "../engSendTurn";

describe("buildTurnEvents", () => {
  it("builds a plain follow-up message", () => {
    expect(buildTurnEvents({ text: "use a webhook instead" })).toEqual([
      { type: "user.message", content: [{ type: "text", text: "use a webhook instead" }] }
    ]);
  });

  it("builds a tool approval", () => {
    expect(buildTurnEvents({ approve: { toolUseId: "sevt_1", allow: true } })).toEqual([
      { type: "user.tool_confirmation", tool_use_id: "sevt_1", result: "allow" }
    ]);
  });

  it("carries a reason on a denial, so the agent can adjust", () => {
    expect(buildTurnEvents({ approve: { toolUseId: "sevt_1", allow: false, reason: "use pnpm" } })).toEqual([
      { type: "user.tool_confirmation", tool_use_id: "sevt_1", result: "deny", deny_message: "use pnpm" }
    ]);
  });

  it("builds an interrupt", () => {
    expect(buildTurnEvents({ interrupt: true })).toEqual([{ type: "user.interrupt" }]);
  });

  it("rejects an empty or unrecognised body", () => {
    expect(buildTurnEvents({})).toBeNull();
    expect(buildTurnEvents({ text: "   " })).toBeNull();
    expect(buildTurnEvents(null)).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engSendTurn.test.ts`
Expected: FAIL — `Cannot find module '../engSendTurn'`

- [ ] **Step 3: Write the implementation**

```typescript
// functions/src/engineering/engSendTurn.ts
//
// Everything the founder sends into a live session: a follow-up, a tool
// approval, or a stop. One endpoint rather than three, because they are the
// same call with a different event body and the client's state machine is
// simpler for it.
// `firebase-functions/v2/https` exports Request but NOT Response — importing both
// from it is a TS2305. Every existing handler in this repo (runTask.ts and ~10
// others) takes Response from express; match that.
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import * as admin from "firebase-admin";
import { verifyAuth } from "../auth";
import { getEngClient } from "./engClient";

export type TurnEvent =
  | { type: "user.message"; content: Array<{ type: "text"; text: string }> }
  | { type: "user.tool_confirmation"; tool_use_id: string; result: "allow" | "deny"; deny_message?: string }
  | { type: "user.interrupt" };

export function buildTurnEvents(body: unknown): TurnEvent[] | null {
  if (typeof body !== "object" || body === null) return null;
  const b = body as Record<string, unknown>;

  if (b.interrupt === true) return [{ type: "user.interrupt" }];

  const approve = b.approve as Record<string, unknown> | undefined;
  if (approve && typeof approve.toolUseId === "string") {
    if (approve.allow === true) {
      return [{ type: "user.tool_confirmation", tool_use_id: approve.toolUseId, result: "allow" }];
    }
    const event: TurnEvent = {
      type: "user.tool_confirmation",
      tool_use_id: approve.toolUseId,
      result: "deny"
    };
    // A denial with a reason lets the agent try another way instead of
    // stalling on a wall it cannot see the shape of.
    if (typeof approve.reason === "string" && approve.reason.trim()) {
      event.deny_message = approve.reason.trim();
    }
    return [event];
  }

  const text = typeof b.text === "string" ? b.text.trim() : "";
  if (text) return [{ type: "user.message", content: [{ type: "text", text }] }];

  return null;
}

export async function handleEngSendTurn(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const runId = typeof req.body?.runId === "string" ? req.body.runId : "";
  const events = buildTurnEvents(req.body);
  if (!runId || !events) {
    res.status(400).json({ error: "invalid_payload", detail: "runId and one of text/approve/interrupt required" });
    return;
  }

  const runSnap = await admin.firestore().doc(`companies/${auth.uid}/engRuns/${runId}`).get();
  const sessionId = runSnap.data()?.sessionId as string | undefined;
  if (!runSnap.exists || !sessionId) {
    res.status(404).json({ error: "run_not_found" });
    return;
  }

  try {
    await getEngClient().beta.sessions.events.send(sessionId, { events: events as never });
  } catch (err) {
    // A session paused at its budget rejects anything that starts new work.
    // Surface that as its own state rather than a generic upstream failure —
    // the client turns it into "raise the cap", not "something broke".
    const detail = String(err);
    if (detail.includes("budget")) {
      res.status(409).json({ error: "budget_reached" });
      return;
    }
    res.status(502).json({ error: "send_failed", detail });
    return;
  }

  res.status(200).json({ ok: true });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd ~/Developer/codepet/functions && npx jest src/engineering/__tests__/engSendTurn.test.ts`
Expected: PASS, 5 tests.

- [ ] **Step 5: Register the function**

In `functions/src/index.ts`:

```typescript
import { handleEngSendTurn } from "./engineering/engSendTurn";
```

```typescript
export const engSendTurn = onRequest(
  {
    cors: false,
    secrets: ["ANTHROPIC_API_KEY"]
  },
  handleEngSendTurn
);
```

- [ ] **Step 6: Typecheck and run the whole suite**

```bash
cd ~/Developer/codepet/functions && npm run build && npm test
```

Expected: `tsc` clean; every suite passes.

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/codepet
git add functions/src/engineering/engSendTurn.ts functions/src/engineering/__tests__/engSendTurn.test.ts functions/src/index.ts
git commit -F- <<'EOF'
feat(eng): engSendTurn — follow-ups, approvals and interrupts

One endpoint for all three because they are the same call with a different
event body, and the client's state machine is simpler when "talk to the
running session" is one thing rather than three.

A denial carries its reason through to the agent so it can try another way,
instead of stalling against a wall whose shape it cannot see.

A session paused at its budget rejects anything that starts new work; that
maps to its own 409 rather than a generic upstream failure, so the client
can offer "raise the cap" instead of reporting that something broke.
EOF
```

---

### Task 10: Provision the agent and environment, then verify end-to-end

**Files:**
- Create: `functions/scripts/provision-eng-agent.ts`
- Create: `functions/scripts/verify-eng-run.ts`
- Modify: `functions/package.json` (two scripts)

**Interfaces:**
- Consumes: `ENG_MODEL` (Task 6)
- Produces: the `ENG_AGENT_ID` / `ENG_AGENT_VERSION` / `ENG_ENVIRONMENT_ID` values the handlers read

- [ ] **Step 1: Write the provisioning script**

```typescript
// functions/scripts/provision-eng-agent.ts
//
// Run ONCE per environment. Creates the reusable agent and container
// environment, then prints the ids to put in the function config.
//
// This is not called from a request path on purpose: creating an agent per
// run accumulates orphaned agents, pays create latency every time, and
// throws away the versioning that lets a session pin known-good behaviour.
import Anthropic from "@anthropic-ai/sdk";
import { ENG_MODEL } from "../src/engineering/engClient";

async function main(): Promise<void> {
  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

  const environment = await client.beta.environments.create({
    name: "codepet-engineering",
    config: {
      type: "cloud",
      // Package managers are the whole job; MCP is off until something needs it.
      networking: { type: "limited", allow_package_managers: true, allow_mcp_servers: false }
    }
  });

  const agent = await client.beta.agents.create({
    name: "Codepet Engineering",
    model: ENG_MODEL,
    system: "You are a coding agent. The founder's per-company brief is supplied per session.",
    tools: [
      {
        type: "agent_toolset_20260401",
        default_config: { enabled: true, permission_policy: { type: "always_allow" } },
        // Everything else is reversible inside a throwaway branch. Bash is the
        // one tool that can reach outside it, so it is the one that asks.
        configs: [{ name: "bash", permission_policy: { type: "always_ask" } }]
      }
    ]
  });

  console.log(`ENG_ENVIRONMENT_ID=${environment.id}`);
  console.log(`ENG_AGENT_ID=${agent.id}`);
  console.log(`ENG_AGENT_VERSION=${agent.version}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Add the npm scripts**

In `functions/package.json`, inside `"scripts"`:

```json
"provision:eng": "ts-node --compilerOptions '{\"module\":\"commonjs\"}' scripts/provision-eng-agent.ts",
"verify:eng": "ts-node --compilerOptions '{\"module\":\"commonjs\"}' scripts/verify-eng-run.ts"
```

- [ ] **Step 3: Run provisioning and record the ids**

```bash
cd ~/Developer/codepet/functions
ANTHROPIC_API_KEY="$(grep ANTHROPIC_API_KEY local.env | cut -d= -f2-)" npm run provision:eng
```

Expected: three `KEY=value` lines. Append them to `functions/local.env`, and set them for deployed functions:

```bash
printf 'ENG_ENVIRONMENT_ID=env_...\nENG_AGENT_ID=agent_...\nENG_AGENT_VERSION=1\n' >> functions/.env.devpet-8f4b1
```

**Note:** `.env.devpet-8f4b1` is the project-suffixed env file firebase-functions v2 reads at deploy. It must **not** be named plain `.env` — see Global Constraints.

- [ ] **Step 4: Write the end-to-end verification script**

```typescript
// functions/scripts/verify-eng-run.ts
//
// Drives the deployed functions the way the app will: start a run, tail the
// SSE relay, print what comes back. Keeps a human in the loop for the one
// thing unit tests cannot cover — whether the agent actually does the job.
const BASE = process.env.ENG_BASE ?? "https://us-central1-devpet-8f4b1.cloudfunctions.net";

async function main(): Promise<void> {
  const idToken = process.env.ID_TOKEN;
  if (!idToken) throw new Error("ID_TOKEN required — get one with `npm run token`");

  const started = await fetch(`${BASE}/engStartRun`, {
    method: "POST",
    headers: { Authorization: `Bearer ${idToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({ ask: process.env.ASK ?? "Add a CONTRIBUTING.md explaining how to run the tests." })
  });
  if (!started.ok) throw new Error(`engStartRun ${started.status}: ${await started.text()}`);
  const { runId } = (await started.json()) as { runId: string };
  console.log("runId:", runId);

  const stream = await fetch(`${BASE}/engStream?runId=${runId}`, {
    headers: { Authorization: `Bearer ${idToken}`, Accept: "text/event-stream" }
  });
  const reader = stream.body!.getReader();
  const decoder = new TextDecoder();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    process.stdout.write(decoder.decode(value));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 5: Deploy the four functions — scoped**

```bash
cd ~/Developer/codepet
firebase deploy --only functions:engStartRun,functions:engStream,functions:engSendTurn,functions:engWebhook
```

Before running this, confirm the export set is a superset of what is live:

```bash
firebase functions:list
```

- [ ] **Step 6: Register the webhook endpoint**

In the Anthropic Console → Manage → Webhooks, add `https://us-central1-devpet-8f4b1.cloudfunctions.net/engWebhook`, subscribed to `session.status_idled` and `session.status_terminated`. Copy the `whsec_` secret once — it is shown only at creation — and set it:

```bash
printf 'ANTHROPIC_WEBHOOK_SIGNING_KEY=whsec_...\n' >> functions/.env.devpet-8f4b1
firebase deploy --only functions:engWebhook
```

- [ ] **Step 7: Seed a repo link and run the verification**

In Firestore, create `companies/<your-uid>/engineering/repo` with `url` (the scratch repo from Task 1) and a `sealed` blob produced by the existing GitHub OAuth flow. Then:

```bash
cd ~/Developer/codepet/functions
npm run token                      # prints an ID_TOKEN
ID_TOKEN=<paste> npm run verify:eng
```

Expected: a `runId`, then a stream of `event: step` frames naming real files, `event: approval` when the agent wants bash, and `event: done`. Confirm in Firestore that the run doc moved to `status: "reviewing"` with a non-zero `creditsSpent` — that proves the webhook fired.

- [ ] **Step 8: Commit**

```bash
cd ~/Developer/codepet
git add functions/scripts/provision-eng-agent.ts functions/scripts/verify-eng-run.ts functions/package.json
git commit -F- <<'EOF'
chore(eng): provision the engineering agent + end-to-end verification

Provisioning is a one-time script rather than a request-path call. Creating
an agent per run would accumulate orphaned agents, pay create latency every
time, and throw away the versioning that lets a session pin known-good
behaviour.

Only bash asks for permission. Everything else the agent does is reversible
inside a throwaway branch; bash is the one tool that can reach outside it,
so it is the one worth interrupting a founder for. Asking about every file
edit would train them to click Allow without reading.

verify-eng-run drives the deployed functions the way the app will, because
the one thing the jest suite cannot answer is whether the agent actually
does the job.
EOF
```

---

## What this plan does NOT cover

Three further plans follow, each producing working software on its own:

- **Plan 2 — Repo onboarding.** Connect-or-create, repo scaffolding from the brief, the Vercel GitHub app install, and writing `companies/{uid}/engineering/repo`. Task 10 Step 7 seeds that document by hand precisely because this plan does not build it.

  **Hard contract inherited from Plan 1, Task 5 — do not lose this.** The repo
  document MUST carry `defaultBranch`, read from the GitHub API at link time
  (`GET /repos/{owner}/{repo}` → `default_branch`). `loadRepo` fails closed when the
  field is absent: it returns `null` and the founder is asked to connect a repo.
  It does **not** guess `"main"`.

  Why the guess was removed: a repo whose real default is `master` would mount
  `checkout: { branch: "main" }`, a branch that does not exist, and the founder
  would meet an obscure git error *inside a paid run* rather than a clean prompt
  before one started. Reading the field once at link time costs a single API call;
  guessing costs a wasted run and a support conversation.

  Consequence to handle in Plan 2: any repo document written before this field
  existed resolves to `null`, so the founder is prompted to re-link. That is the
  intended behaviour, not a regression — but the copy should say "reconnect your
  repo", not "no repo linked", when a document exists and only the field is missing.
- **Plan 3 — Native Engineering mode.** `ChatMode.engineering`, `EngineeringClient`, `EngineeringRunStore`, the collapsed result bar, live streaming into the dock.
- **Plan 4 — Review pane and ship.** The expanded workspace, scope tabs, diff rendering, the PR and preview actions.
