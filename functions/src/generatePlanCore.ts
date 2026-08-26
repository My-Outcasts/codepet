/**
 * Everything `generatePlan` is MADE of — the payload contract, the system prompt, the forced tool,
 * and the user message — with nothing that talks to a model.
 *
 * Split from the handler so the local path can import the builders without dragging the
 * Anthropic SDK, express and firebase-admin into an esbuild bundle that ships inside the app.
 * Same reasoning as `enrichBriefCore`, and the same anti-drift property: one prompt, two
 * transports.
 */

import { PlanTier } from "./entitlements";
import { NarrativeSummaryInput } from "./generateGuidanceCore";

// MARK: - Plan-specific types

export interface PlanProjectInput {
  name: string;
  stage: "idea" | "building" | "launch" | "growth";
  brief: string;
  tags: string[];      // ProjectTag rawValues, e.g. ["swiftUI", "firebase"]
  domains: string[];   // ProjectDomain rawValues, e.g. ["finance"]
}

export interface PlanSectionInput {
  rule_id: string;     // e.g. "biz_problem_validated"
  title: string;       // resolved, language-specific
  pillar: "engineering" | "business" | "growth";
  current_state: "missing" | "passed" | "attested";
}

export interface PlanPayload {
  language: "vi" | "en";
  project: PlanProjectInput;
  section: PlanSectionInput;
  recent_narratives?: NarrativeSummaryInput[];  // optional personalization
}

export interface PlanStep {
  title: string;
  detail: string;      // the how-to (withheld for locked steps in preview tier)
  done_when: string;
}

export interface PlanOutput {
  summary: string;
  steps: PlanStep[];
  pitfalls: string[];
  est_effort: string;
}

// MARK: - Entitlement / gating
//
// The paywall is enforced HERE, server-side: locked step `detail` is stripped
// before the response leaves the server, so a free user can never read it from
// the network. Tier resolution lives in entitlements.ts (reads the RevenueCat-
// written entitlements/{uid}); gating ships OFF until a purchase flow exists.

/** Free preview keeps summary + every step's title/done_when, but only the
 *  FIRST step's detail. Returns the (possibly redacted) plan + locked count. */
export function applyTier(plan: PlanOutput, tier: PlanTier): { plan: PlanOutput; lockedStepCount: number } {
  if (tier === "full") return { plan, lockedStepCount: 0 };
  let locked = 0;
  const steps = plan.steps.map((s, i) => {
    if (i === 0) return s;
    locked += 1;
    return { ...s, detail: "" };
  });
  return { plan: { ...plan, steps }, lockedStepCount: locked };
}

// MARK: - Validation

export function validatePlanPayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  const b = body as Partial<PlanPayload>;
  if (b.language !== "vi" && b.language !== "en") return "language must be 'vi' or 'en'";

  const p = b.project;
  if (!p || typeof p !== "object") return "project required";
  if (typeof p.name !== "string") return "project.name required";
  if (!["idea", "building", "launch", "growth"].includes(p.stage as string)) {
    return "project.stage must be idea|building|launch|growth";
  }
  if (typeof p.brief !== "string") return "project.brief required (may be empty)";
  if (!Array.isArray(p.tags)) return "project.tags must be an array";
  if (!Array.isArray(p.domains)) return "project.domains must be an array";

  const s = b.section;
  if (!s || typeof s !== "object") return "section required";
  if (typeof s.rule_id !== "string") return "section.rule_id required";
  if (typeof s.title !== "string") return "section.title required";
  if (!["engineering", "business", "growth"].includes(s.pillar as string)) {
    return "section.pillar must be engineering|business|growth";
  }
  if (!["missing", "passed", "attested"].includes(s.current_state as string)) {
    return "section.current_state must be missing|passed|attested";
  }
  if (b.recent_narratives !== undefined && !Array.isArray(b.recent_narratives)) {
    return "recent_narratives must be an array when provided";
  }
  return null;
}

// MARK: - System prompt
//
// NOTE: deliberately NO pet persona — Project Health speaks in a neutral,
// instructional voice (a separate decision from the pet-voiced daily guidance).

export const PLAN_SYSTEM_PROMPT = `You are the planning engine behind a feature called "Project Health". You produce ONE concrete, ordered action plan that helps a solo builder complete a specific health check for their project.

AUDIENCE — THIS IS CRITICAL:
Your readers are age 12 and up, many learning to build products for the first time.
- Use simple, everyday words. Write at a 6th-grade reading level.
- EVERY technical or business term MUST have a short inline explanation in parentheses. No exceptions. Example: "MRR (monthly recurring revenue — the money you make every month from subscriptions)".
- Do NOT assume the reader knows jargon like ICP, churn, funnel, CI, schema, or positioning.

YOUR JOB:
Given a project (its stage, brief, tech, and what it's about) and ONE health check that is currently missing, produce a plan to complete that check. The plan is:
- SPECIFIC to THIS project — reference its name, stage, tech, and domain. Never generic filler that could apply to any app.
- ACTIONABLE — each step is something the builder can actually do this week, not advice to "think about it".
- ORDERED — 4 to 7 steps, each building on the last.
- HONEST about effort — give a realistic total time estimate.

STAGE AWARENESS:
The project's stage (idea / building / launch / growth) tells you how much is realistic. An idea-stage project should not be told to run paid ads; a growth-stage one needs more than "talk to 5 users".

VOICE — IMPORTANT:
- Neutral, warm, and instructional. You are a guide, not a character. Do NOT speak as a pet, mascot, or named persona. Do NOT use "I".
- NEVER use asterisks (*), markdown bold (**), or italics. Output renders in a native app with no markdown.
- NEVER use the em-dash or en-dash (— or –) anywhere. They read as AI-written. Write short, plain sentences instead, or use a comma, a period, or parentheses. (Ordinary hyphens inside words like "in-person" or ranges like "2 to 3" are fine, but prefer "to" over a dash in ranges.)
- Never mention "AI", "assistant", "Claude", or any model.

OUTPUT (via the record_plan tool):
- summary: 1 to 2 plain sentences saying what this plan achieves and why it matters at this stage.
- steps: 4-7 ordered steps. Each has:
    - title: a short imperative (e.g. "Write a one-line problem statement").
    - detail: 1-3 sentences of concrete how-to, specific to this project.
    - done_when: an observable signal that the step is complete (e.g. "you have 5 quotes from real users in a doc").
- pitfalls: 0-3 short, common mistakes to avoid for this check.
- est_effort: realistic total time, plain language (e.g. "about half a day", "2-3 evenings").

CRITICAL:
- Ground everything in the ACTUAL project details provided. If the brief is empty, work from the name, tech, and domain. Do not invent features.
- Be concrete and useful, not a motivational speech.
- Remember: no em-dashes or en-dashes anywhere in your output.
Output language: <language>`;

// MARK: - Tool definition

export const PLAN_TOOL = {
  name: "record_plan",
  description: "Record ONE concrete, ordered action plan to complete a specific Project Health check, grounded in this project's real details.",
  input_schema: {
    type: "object",
    properties: {
      summary: {
        type: "string",
        description: "1-2 plain sentences: what this plan achieves and why it matters at this stage. (<=300 chars)"
      },
      steps: {
        type: "array",
        description: "4-7 ordered, actionable steps specific to this project.",
        items: {
          type: "object",
          properties: {
            title:     { type: "string", description: "Short imperative title for the step." },
            detail:    { type: "string", description: "1-3 sentences of concrete how-to, specific to this project. (<=400 chars)" },
            done_when: { type: "string", description: "Observable signal the step is complete. (<=200 chars)" }
          },
          required: ["title", "detail", "done_when"]
        }
      },
      pitfalls: {
        type: "array",
        description: "0-3 common mistakes to avoid for this check.",
        items: { type: "string" }
      },
      est_effort: {
        type: "string",
        description: "Realistic total time in plain language, e.g. 'about half a day'."
      }
    },
    required: ["summary", "steps", "est_effort"]
  }
} as const;

// MARK: - User message builder

export const MAX_NARRATIVES = 6;

export function buildPlanUserMessage(payload: PlanPayload): string {
  const p = payload.project;
  const s = payload.section;

  const tags = p.tags.length ? p.tags.join(", ") : "(none detected)";
  const domains = p.domains.length ? p.domains.join(", ") : "(none detected)";
  const brief = p.brief.trim() ? p.brief.trim().slice(0, 600) : "(no brief written yet)";

  let narrativeSection = "";
  if (payload.recent_narratives && payload.recent_narratives.length > 0) {
    const lines = payload.recent_narratives.slice(0, MAX_NARRATIVES).map((n, i) =>
      `${i + 1}. "${n.title}" — ${n.what_happened.slice(0, 200)}`
    ).join("\n");
    narrativeSection = `\n\nRecent activity on this project (for context):\n${lines}`;
  }

  return `PROJECT
- name: ${p.name}
- stage: ${p.stage}
- tech: ${tags}
- about (domain): ${domains}
- brief: ${brief}

HEALTH CHECK TO PLAN
- check: ${s.title}
- pillar: ${s.pillar}
- current state: ${s.current_state}${narrativeSection}

Now call the record_plan tool with a concrete, ordered plan to complete this check for THIS project at its current stage.`;
}

// MARK: - Anthropic client singleton

/** The system + user text for one health-check plan. */
export function planRequest(payload: PlanPayload): { system: string; user: string } {
  return {
    system: PLAN_SYSTEM_PROMPT
      .replace("<language>", payload.language === "vi" ? "Tiếng Viet" : "English"),
    user: buildPlanUserMessage(payload),
  };
}

/** A plan if it has a summary, at least one step and an effort estimate; otherwise null. */
export function coercePlan(input: unknown): PlanOutput | null {
  const p = input as PlanOutput | null;
  if (!p || typeof p !== "object") return null;
  if (typeof p.summary !== "string" || !Array.isArray(p.steps) || p.steps.length === 0) return null;
  if (typeof p.est_effort !== "string") return null;
  return {
    summary: p.summary,
    steps: p.steps,
    pitfalls: Array.isArray(p.pitfalls) ? p.pitfalls : [],
    est_effort: p.est_effort,
  };
}
