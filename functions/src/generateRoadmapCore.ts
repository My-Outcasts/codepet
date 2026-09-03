// Pure logic for the generateRoadmap CF — no firebase/express/anthropic imports, so it
// can be unit-tested (and verified) without loading the heavy Cloud-Functions module
// tree. The IO handler lives in generateRoadmap.ts and imports from here.
//
// Output shape mirrors native's flat, phase/deps `RoadmapTask`, and feeds the Overview
// board + onboarding reveal. A dept-grouped `scaffoldRoadmap` CF used to sit alongside
// this one, retained for a CompanyView that was expected to need its shape; the
// CompanyView shipped without ever calling it, so it was deleted. This is now the only
// roadmap generator.

import { departmentBlock, DEPARTMENT_NAMES } from "./departments";

export const ROADMAP_PHASES = ["find", "foundation", "build", "ship", "launch", "grow"] as const;
export type Phase = (typeof ROADMAP_PHASES)[number];

export const WHO = new Set(["does", "draft", "you"]);
export const DEPT_KEYS = new Set(["eng", "design", "mkt", "sales", "support", "fin", "ops", "legal"]);

export interface RoadmapBrief {
  projectName?: string;
  oneLiner?: string;
  summary?: string;
  audience?: string;
  stage?: string;
  categories?: string[];
}

export interface RoadmapTask {
  id: string;
  title: string;
  detail: string;
  phase: Phase;
  who: string;
  dependsOn: string[];
  done: boolean;
  drafted: boolean;
  dept: string;
}

const clip = (v: unknown, n: number) => (typeof v === "string" ? v.trim().slice(0, n) : "");

function isPhase(v: unknown): v is Phase {
  return typeof v === "string" && (ROADMAP_PHASES as readonly string[]).includes(v);
}

/** lowercase, non-alphanumeric -> "-", trim dashes. Used to build stable, readable ids. */
export function slug(s: string): string {
  return String(s ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export function buildRoadmapPrompt(args: { language: string; brief: RoadmapBrief }): string {
  const { language, brief } = args;
  const stage = clip(brief?.stage, 40);
  const lines = [
    `Product: ${clip(brief?.projectName, 120) || "(unnamed)"}${brief?.oneLiner ? " — " + clip(brief.oneLiner, 300) : ""}`,
    brief?.summary ? `Summary: ${clip(brief.summary, 400)}` : null,
    brief?.audience ? `Audience: ${clip(brief.audience, 200)}` : null,
    stage ? `Stage: ${stage}` : null,
    Array.isArray(brief?.categories) && brief.categories.length
      ? `Categories: ${brief.categories.slice(0, 10).map((c) => clip(c, 40)).join(", ")}`
      : null,
  ].filter(Boolean);

  const grounding = Array.from(DEPT_KEYS)
    .map((k) => `- ${k} (${DEPARTMENT_NAMES[k] ?? k}):\n${departmentBlock(k, stage)}`)
    .join("\n\n");

  const vi = language === "vi"
    ? "\n\nWrite every task title and detail in natural, fluent Vietnamese."
    : "";

  return (
    "You are planning a solo founder's whole company roadmap, grounded ONLY in what the founder told you below — do not invent a different product, and do not invent facts they did not give you.\n\n" +
    lines.join("\n") +
    "\n\nDepartments (grounded for the founder's current stage — use these to choose each task's owning department and to keep every task stage-appropriate):\n\n" +
    grounding +
    "\n\nGenerate 2-4 concrete tasks for EACH of the six phases — find, foundation, build, ship, launch, grow — covering the founder's whole journey from validating the idea through launch and into running & growing the company. The 'grow' phase (shown to the founder as 'Run & Grow') is post-launch: retention, referrals, growth metrics, user-retention playbooks, content/distribution channels. " +
    "For each task give: a short imperative title, a 1-2 sentence detail, a `phase` (exactly one of find, foundation, build, ship, launch, grow), a `who` of exactly 'you' (needs the founder's own judgment, identity, or decisions), 'does' (the companion can produce it autonomously), or 'draft' (the companion drafts it and the founder finalizes), a `dept` — the single owning department, chosen using the department grounding above, exactly one of eng, design, mkt, sales, support, fin, ops, legal — and `deps`: the exact TITLES of any prerequisite tasks from this same list (an empty array if it's an entry point with no prerequisite). " +
    "CHAIN THE PHASES: only 'find'-phase tasks may have empty deps (they are the entry points). EVERY task in foundation, build, ship, launch, or grow MUST list at least one prerequisite from an EARLIER phase in its deps, so the roadmap is one connected chain and nothing in a later phase is workable before its earlier phases are done." +
    vi
  );
}

interface RawTask {
  phase?: unknown;
  title?: unknown;
  detail?: unknown;
  who?: unknown;
  deps?: unknown;
  dept?: unknown;
}

interface KeptTask {
  id: string;
  title: string;
  detail: string;
  phase: Phase;
  who: string;
  deps: string[];
  dept: string;
}

/**
 * Never throws — returns {tasks: []} on junk input. Keeps only tasks with a valid
 * phase and non-empty title, caps 4/phase, assigns stable ids, then resolves each
 * task's `deps` (titles) into `dependsOn` (ids), dropping unknown/self references.
 */
export function coerceRoadmap(raw: unknown, _opts?: { language?: string }): { tasks: RoadmapTask[] } {
  const inTasks: RawTask[] = raw && Array.isArray((raw as { tasks?: unknown }).tasks)
    ? ((raw as { tasks: RawTask[] }).tasks as RawTask[])
    : [];

  const phaseCounts: Partial<Record<Phase, number>> = {};
  const kept: KeptTask[] = [];
  // Titles must be unique across the whole roadmap: deps are resolved by title, so a
  // duplicate would make title->id ambiguous (and let a same-titled task's self-reference
  // resolve to the *other* task, fabricating an edge). Drop later duplicates. Mirrors the
  // web roadmap schema's "unique title" requirement.
  const seenTitles = new Set<string>();

  for (const t of inTasks) {
    if (!t || !isPhase(t.phase)) continue;
    const title = clip(t.title, 120);
    if (!title || seenTitles.has(title)) continue;
    const count = phaseCounts[t.phase] ?? 0;
    if (count >= 4) continue;
    phaseCounts[t.phase] = count + 1;
    seenTitles.add(title);

    const who = typeof t.who === "string" && WHO.has(t.who) ? t.who : "draft";
    const detail = clip(t.detail, 400);
    const deps: string[] = Array.isArray(t.deps)
      ? (t.deps as unknown[]).filter((d): d is string => typeof d === "string")
      : [];

    const dept = typeof t.dept === "string" && DEPT_KEYS.has(t.dept) ? t.dept : "";
    kept.push({ id: `${slug(title)}-${kept.length}`, title, detail, phase: t.phase, who, deps, dept });
  }

  const idByTitle = new Map<string, string>();
  for (const k of kept) if (!idByTitle.has(k.title)) idByTitle.set(k.title, k.id);

  const tasks: RoadmapTask[] = kept.map((k) => {
    const dependsOn: string[] = [];
    for (const depTitle of k.deps) {
      const depId = idByTitle.get(clip(depTitle, 120));
      if (!depId || depId === k.id) continue; // drop unknown + self references
      if (!dependsOn.includes(depId)) dependsOn.push(depId);
    }
    return {
      id: k.id,
      title: k.title,
      detail: k.detail,
      phase: k.phase,
      who: k.who,
      dependsOn,
      done: false,
      drafted: false,
      dept: k.dept,
    };
  });

  // Backstop phase-gating: any task OUTSIDE the first phase that ended up with no
  // dependencies (the model failed to chain it) is linked to the whole preceding
  // non-empty phase, so it reads as "needs earlier steps" until that phase is done
  // — instead of fail-opening to "actionable" before its prerequisites exist.
  const idsByPhase = new Map<Phase, string[]>();
  for (const t of tasks) idsByPhase.set(t.phase, [...(idsByPhase.get(t.phase) ?? []), t.id]);
  for (const t of tasks) {
    if (t.dependsOn.length > 0) continue;
    const pi = ROADMAP_PHASES.indexOf(t.phase);
    if (pi <= 0) continue; // first-phase entry tasks are legitimately depless
    for (let j = pi - 1; j >= 0; j--) {
      const prev = idsByPhase.get(ROADMAP_PHASES[j]);
      if (prev && prev.length) { t.dependsOn = prev.filter((id) => id !== t.id); break; }
    }
  }

  return { tasks };
}

// The forced tool's schema and the system prompt, moved here from the handler when the
// local path started needing them: `local/oneShotSidecar` is esbuild-bundled into the app,
// so anything it imports from a handler drags the Anthropic SDK in with it (measured: 7.5 MB).
// Living here keeps ONE schema for both transports — the API forces this tool, and the local
// path renders this same `input_schema` into its prompt.
export const ROADMAP_TOOL = {
  name: "record_roadmap",
  description: "Record the generated phase/task/dependency roadmap.",
  input_schema: {
    type: "object",
    properties: {
      tasks: {
        type: "array",
        items: {
          type: "object",
          properties: {
            phase: { type: "string", description: "One of: find, foundation, build, ship, launch, grow." },
            title: { type: "string" },
            detail: { type: "string" },
            who: { type: "string", description: "'you' | 'does' | 'draft'" },
            dept: {
              type: "string",
              description: "The single owning department: one of eng, design, mkt, sales, support, fin, ops, legal.",
            },
            deps: {
              type: "array",
              items: { type: "string" },
              description: "Exact titles of prerequisite tasks from this same list, empty if none.",
            },
          },
          required: ["phase", "title", "who", "detail", "dept"],
        },
      },
    },
    required: ["tasks"],
  },
} as const;

export const ROADMAP_SYSTEM = "You plan a solo founder's whole-company roadmap. You never invent details the founder did not give you.";
