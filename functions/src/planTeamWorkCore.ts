// Pure logic for the Team Build planner — no firebase/express/anthropic imports, because the
// one-shot sidecar is esbuild-bundled and inlines this whole import graph.
import { DEPARTMENT_NAMES, DEPARTMENT_OUTPUTS, coerceKindForDepartment } from "./departments";
import { DELIVERABLE_KINDS } from "./runTaskCore";
import { DEPT_KEYS } from "./generateRoadmapCore";
import type { DecisionBrief } from "./company/types";

export const BUILD_STEP_ID = "build";
export const MAX_DEPT_STEPS = 6;
export const MAX_DEPS = 3;

export interface WorkStep { id: string; dept: string; title: string; instruction: string; kind: string; dependsOn: string[] }
export interface WorkPlan { title: string; slug: string; summary: string; projectType: string; steps: WorkStep[] }
export interface TeamPlanInput {
  language: "en" | "vi"; request: string; brief: DecisionBrief | null;
  company: Record<string, unknown>; roster: string[];
}

const str = (v: unknown, max = 600): string => (typeof v === "string" ? v.trim().slice(0, max) : "");

export function teamSlug(s: string): string {
  const ascii = s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D");
  const kebab = ascii.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  const capped = kebab.slice(0, 40).replace(/-+$/g, "");
  return capped || "project";
}

export function buildTeamPlanPrompt(input: TeamPlanInput): string {
  const roster = input.roster.filter((k) => DEPT_KEYS.has(k));
  const lines = roster.map((k) => {
    const out = DEPARTMENT_OUTPUTS[k];
    const kinds = out ? [...out.primary, ...out.allowed].join(", ") : "doc";
    return `- ${k} (${DEPARTMENT_NAMES[k] ?? k}): can produce ${kinds}`;
  });
  const b = input.brief;
  const decision = b
    ? [
        `Recommendation: ${b.recommendation}`,
        `Trade-off the founder owns: ${b.tradeoff_founder_must_own}`,
        `Kill criteria: ${b.kill_criteria.join("; ")}`,
        `What we don't know: ${b.what_we_dont_know}`,
      ].join("\n")
    : "(No room decision — plan from the request alone.)";
  return [
    `The founder asked: "${input.request}"`,
    ``,
    `What the team decided in the room:`,
    decision,
    ``,
    `Company facts (do not invent any others):`,
    JSON.stringify(input.company),
    ``,
    `Departments available on this company's roster:`,
    ...lines,
    ``,
    `Plan the work the departments must do so an engineer can then build the finished project.`,
    `Rules: at most ${MAX_DEPT_STEPS} department steps; each step depends on at most ${MAX_DEPS} earlier steps;`,
    `only use departments from the list; pick a kind that department can produce;`,
    `do NOT include the final build step — it is added for you and depends on every step.`,
    `Give the project a short title, a kebab-case slug, a one-sentence summary of what the team decided,`,
    `and a projectType naming what gets built (e.g. "Next.js landing page", "Next.js web app", "email sequence (docs)").`,
    `Anything a browser shows is built as a Next.js app — never plan plain HTML files.`,
    input.language === "vi" ? `Write every title, instruction and summary in Vietnamese.` : ``,
  ].filter((l) => l !== ``).join("\n");
}

export function coerceWorkPlan(raw: unknown, roster: string[]): WorkPlan | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const allowed = new Set(roster.filter((k) => DEPT_KEYS.has(k)));
  const rawSteps = Array.isArray(r.steps) ? r.steps : [];

  let buildInstruction = "";
  const candidates: WorkStep[] = [];
  const seen = new Set<string>();
  for (const s of rawSteps) {
    if (!s || typeof s !== "object") continue;
    const o = s as Record<string, unknown>;
    const id = str(o.id, 40);
    const dept = str(o.dept, 20);
    const kind = str(o.kind, 20);
    // A step the model marked as the build step: keep its instruction, drop the step.
    if (id === BUILD_STEP_ID || (dept === "eng" && kind === "other")) {
      buildInstruction = buildInstruction || str(o.instruction, 2000);
      continue;
    }
    if (!id || seen.has(id) || !allowed.has(dept)) continue;
    seen.add(id);
    const safeKind = DELIVERABLE_KINDS.has(kind) ? coerceKindForDepartment(dept, kind) : coerceKindForDepartment(dept, "doc");
    candidates.push({
      id, dept, kind: safeKind,
      title: str(o.title, 120) || id,
      instruction: str(o.instruction, 2000),
      dependsOn: Array.isArray(o.dependsOn) ? o.dependsOn.map((d) => str(d, 40)).filter(Boolean) : [],
    });
  }

  const kept = candidates.slice(0, MAX_DEPT_STEPS);
  const accepted = new Set<string>();
  for (const s of kept) {
    // Only edges to EARLIER accepted steps survive: removes dangling ids and every back-edge.
    s.dependsOn = [...new Set(s.dependsOn)].filter((d) => accepted.has(d)).slice(0, MAX_DEPS);
    accepted.add(s.id);
  }

  const build: WorkStep = {
    id: BUILD_STEP_ID, dept: "eng", kind: "other",
    title: "Build the project",
    instruction: buildInstruction,
    dependsOn: kept.map((s) => s.id),
  };
  const title = str(r.title, 120) || "Project";
  return {
    title,
    slug: teamSlug(str(r.slug, 120) || title),
    summary: str(r.summary, 400),
    projectType: str(r.projectType, 120) || "project",
    steps: [...kept, build],
  };
}

export const TEAM_PLAN_TOOL = {
  name: "record_team_plan",
  description: "Record the departments' work plan for a Team Build.",
  input_schema: {
    type: "object",
    properties: {
      title: { type: "string" },
      slug: { type: "string" },
      summary: { type: "string" },
      projectType: { type: "string" },
      steps: {
        type: "array",
        items: {
          type: "object",
          properties: {
            id: { type: "string" }, dept: { type: "string" }, title: { type: "string" },
            instruction: { type: "string" }, kind: { type: "string" },
            dependsOn: { type: "array", items: { type: "string" } },
          },
          required: ["id", "dept", "title", "instruction", "kind", "dependsOn"],
        },
      },
    },
    required: ["title", "slug", "summary", "projectType", "steps"],
  },
} as const;

export const TEAM_PLAN_SYSTEM =
  "You are the chief of staff of a small company's AI team. You turn a founder's request and the " +
  "team's decision into a short, concrete work plan for departments. You never invent company facts.";
