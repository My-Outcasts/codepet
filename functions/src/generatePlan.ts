import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { PLAN_MODEL } from "./anthropic";
import { NarrativeSummaryInput } from "./generateGuidance";
import { resolvePlanTier, PlanTier } from "./entitlements";

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
function applyTier(plan: PlanOutput, tier: PlanTier): { plan: PlanOutput; lockedStepCount: number } {
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

const PLAN_SYSTEM_PROMPT = `You are the planning engine behind a feature called "Project Health". You produce ONE concrete, ordered action plan that helps a solo builder complete a specific health check for their project.

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

const PLAN_TOOL = {
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

const MAX_NARRATIVES = 6;

function buildPlanUserMessage(payload: PlanPayload): string {
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

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

// MARK: - Handler

export async function handleGeneratePlan(
  req: Request,
  res: Response
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  // Auth
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  // Validate
  const validationError = validatePlanPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as PlanPayload;

  // Rate limit
  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  // Build prompt
  const system = PLAN_SYSTEM_PROMPT
    .replace("<language>", payload.language === "vi" ? "Tiếng Viet" : "English");
  const user = buildPlanUserMessage(payload);

  // Call Claude (non-streaming — a plan is a few hundred tokens)
  let plan: PlanOutput;
  try {
    const response = await anthropicClient().messages.create({
      model: PLAN_MODEL,
      max_tokens: 1500,
      system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
      tools: [PLAN_TOOL as any],
      tool_choice: { type: "tool", name: "record_plan" },
      messages: [{ role: "user", content: user }]
    });

    let parsed: PlanOutput | undefined;
    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === "record_plan") {
        const input = block.input as PlanOutput;
        if (
          typeof input.summary === "string" &&
          Array.isArray(input.steps) &&
          input.steps.length > 0 &&
          typeof input.est_effort === "string"
        ) {
          parsed = {
            summary: input.summary,
            steps: input.steps,
            pitfalls: Array.isArray(input.pitfalls) ? input.pitfalls : [],
            est_effort: input.est_effort
          };
        }
      }
    }

    if (!parsed) {
      throw new Error("Anthropic response missing valid record_plan tool use");
    }
    plan = parsed;
  } catch (err) {
    logger.error("anthropic plan call failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  // Resolve entitlement and gate (server-side — locked detail never leaves here)
  const tier = await resolvePlanTier(auth.uid);
  const { plan: gatedPlan, lockedStepCount } = applyTier(plan, tier);

  // Respond
  res.status(200).json({
    plan: gatedPlan,
    tier,
    locked_step_count: lockedStepCount,
    model: PLAN_MODEL,
    generated_at: new Date().toISOString()
  });
}
