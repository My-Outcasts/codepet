import { Effort } from "./anthropic";
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { buildRunTaskPrompt, coerceDeliverable } from "./runTaskCore";

// Sonnet 5 rather than Opus 4.8: this is schema-forced generation, the shape
// Sonnet 5 is closest to Opus on, at 40% less per token ($3/$15 vs $5/$25).
// Sonnet 5 runs adaptive thinking when `thinking` is omitted, so `effort` and a
// larger `max_tokens` below are load-bearing, not tuning — see RUN_MAX_TOKENS.
const RUN_MODEL = "claude-sonnet-5";
// `medium`, not the `high` default: the deliverable is the product, but a
// forced tool call with a fixed schema does not need the deepest reasoning
// tier. Raise this before reaching for a bigger model if quality regresses.
const RUN_EFFORT: Effort = "medium";
// `max_tokens` caps thinking AND answer together. The old 3000 was sized for a
// model that did not think by default; a deliverable that used all of it would
// now be truncated mid-JSON by the thinking that precedes it. Unused headroom
// is not billed, so this is insurance, not spend.
const RUN_MAX_TOKENS = 8000;

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

const RECORD_TOOL = {
  name: "record_deliverable",
  description: "Record the finished deliverable produced for this task.",
  input_schema: {
    type: "object",
    properties: {
      kind: { type: "string", description: "The deliverable kind that best fits what was produced." },
      title: { type: "string", description: "A short, clear title for the deliverable." },
      body: { type: "string", description: "The full deliverable content, written as markdown." },
      payload: {
        type: "object",
        additionalProperties: true,
        description: "Structured fields for the chosen kind. Fill ONLY the fields for that kind (see the per-kind guide in the prompt); omit for kinds without a structured form.",
        properties: {
          items: { type: "array", description: "checklist: 5-7 ordered steps.",
            items: { type: "object", additionalProperties: false, properties: { t: { type: "string" }, done: { type: "boolean" } }, required: ["t", "done"] } },
          call: { type: "string", description: "doc: the decision up front (1-2 sentences)." },
          sections: { type: "array", description: "doc/legal: labeled {h,p} blocks.",
            items: { type: "object", additionalProperties: false, properties: { h: { type: "string" }, p: { type: "string" } }, required: ["h", "p"] } },
          next: { type: "array", description: "doc: 1-3 next actions.", items: { type: "string" } },
          goal: { type: "string", description: "plan: one-line goal." },
          changes: { type: "array", description: "plan: areas touched.",
            items: { type: "object", additionalProperties: false, properties: { area: { type: "string" }, edit: { type: "string" } }, required: ["area", "edit"] } },
          verify: { type: "array", description: "plan: future-tense verification checks.", items: { type: "string" } },
          risks: { type: "string", description: "plan: one-line main risk." },
          messages: { type: "array", description: "dms: exactly 4 persona DMs.",
            items: { type: "object", additionalProperties: false, properties: { name: { type: "string" }, note: { type: "string" }, msg: { type: "string" } }, required: ["name", "note", "msg"] } },
          weeks: { type: "array", description: "calendar: exactly 2 weeks, each with a label and 2-3 posts.",
            items: { type: "object", additionalProperties: false, properties: {
              label: { type: "string" },
              items: { type: "array", items: { type: "object", additionalProperties: false, properties: { day: { type: "string" }, kind: { type: "string" }, body: { type: "string" } }, required: ["day", "kind", "body"] } },
            }, required: ["label", "items"] } },
          price: { type: "object", description: "sheet: monthly Pro price input {val,min,max,step}.",
            additionalProperties: false, properties: { val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" } }, required: ["val", "min", "max", "step"] },
          waitlist: { type: "object", description: "sheet: waitlist size input {val,min,max,step}.",
            additionalProperties: false, properties: { val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" } }, required: ["val", "min", "max", "step"] },
          conversion: { type: "object", description: "sheet: conversion % input {val,min,max,step}.",
            additionalProperties: false, properties: { val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" } }, required: ["val", "min", "max", "step"] },
          churn: { type: "object", description: "sheet: monthly churn % input {val,min,max,step}.",
            additionalProperties: false, properties: { val: { type: "number" }, min: { type: "number" }, max: { type: "number" }, step: { type: "number" } }, required: ["val", "min", "max", "step"] },
          summary: { type: "string", description: "sheet: one paragraph on what the model shows at the defaults." },
          title: { type: "string", description: "site: browser tab / SEO title." },
          brand: { type: "string", description: "site: company or product name." },
          kicker: { type: "string", description: "site: tiny label above the headline; empty string if none." },
          headline: { type: "string", description: "site: the hero H1." },
          headlineHi: { type: "string", description: "site: accent-colored tail of the headline; empty string if none." },
          sub: { type: "string", description: "site: one supporting sentence under the headline." },
          ctaPrimary: { type: "string", description: "site: primary button label." },
          ctaSecondary: { type: "string", description: "site: secondary button label; empty string if only one CTA." },
          howEyebrow: { type: "string", description: "site: eyebrow over the how-it-works section." },
          howTitle: { type: "string", description: "site: how-it-works section heading." },
          steps: { type: "array", description: "plan: 3-5 ordered approach steps (strings). site: exactly 3 how-it-works steps, each {h,p}.", items: {} },
          featEyebrow: { type: "string", description: "site: eyebrow over the features section." },
          featTitle: { type: "string", description: "site: features section heading." },
          features: { type: "array", description: "site: exactly 3 feature cards, each {h,p}.",
            items: { type: "object", additionalProperties: false, properties: { h: { type: "string" }, p: { type: "string" } }, required: ["h", "p"] } },
          quote: { type: "string", description: "site: one pull-quote/testimonial line; empty string if none." },
          quoteBy: { type: "string", description: "site: attribution for the quote; empty string if none." },
          finalTitle: { type: "string", description: "site: closing call-to-action heading." },
          finalSub: { type: "string", description: "site: line under the closing CTA; empty string if none." },
          finalCta: { type: "string", description: "site: closing CTA button label." },
          accent: { type: "string", description: "site: brand accent colour as a 6-digit hex." },
          footNote: { type: "string", description: "site: footer line." },
          screens: { type: "array", description: "screens: exactly 3 onboarding steps, each {name,time,kick,title,sub,art,cta,note}; art is connect/session/recap in order.",
            items: { type: "object", additionalProperties: false, properties: {
              name: { type: "string" }, time: { type: "string" }, kick: { type: "string" }, title: { type: "string" }, sub: { type: "string" },
              art: { type: "string", enum: ["connect", "session", "recap"] }, cta: { type: "string" }, note: { type: "string" },
            }, required: ["name", "time", "kick", "title", "sub", "art", "cta", "note"] } },
        },
      },
    },
    required: ["kind", "title", "body"],
  },
} as const;

interface RunTaskRequestBody {
  company_id?: string | null;
  language?: string;
  companion_id?: string;
  context?: string;
  task_id?: string;
  task_title?: string;
  task_detail?: string;
  revise_note?: string;
  current?: string;
  // Owning department of the task, so the deliverable is written with that function's
  // expertise. Backward-compatible: omitted by older clients and by legacy dept-less
  // tasks → no department block → byte-for-byte identical to before this field existed.
  dept_key?: string;
}

export async function handleRunTask(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) { res.status(401).json({ error: "invalid_token" }); return; }

  const body = (req.body ?? {}) as RunTaskRequestBody;
  const taskTitle = typeof body.task_title === "string" ? body.task_title.trim() : "";
  if (!taskTitle) { res.status(400).json({ error: "invalid_payload", detail: "task_title required" }); return; }

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({ error: "daily_limit_reached", reset_at: limit.resetAt.toISOString(), limit: limit.limit });
    return;
  }

  const prompt = buildRunTaskPrompt({
    companionId: typeof body.companion_id === "string" ? body.companion_id : "byte",
    language: body.language === "vi" ? "vi" : "en",
    context: typeof body.context === "string" ? body.context : "",
    taskTitle,
    taskDetail: typeof body.task_detail === "string" ? body.task_detail : "",
    reviseNote: typeof body.revise_note === "string" ? body.revise_note : undefined,
    current: typeof body.current === "string" ? body.current : undefined,
    // The owning department of the task, so the deliverable is written with that function's
    // expertise. Absent for a legacy dept-less task; unknown keys resolve to no brief.
    deptKey: typeof body.dept_key === "string" ? body.dept_key : undefined,
  });

  try {
    const response = await client().messages.create({
      model: RUN_MODEL,
      max_tokens: RUN_MAX_TOKENS,
      output_config: { effort: RUN_EFFORT },
      system: "You produce real, finished work product for a solo founder's company — never a plan to do the work, the work itself.",
      tools: [RECORD_TOOL as any],
      tool_choice: { type: "tool", name: "record_deliverable" },
      messages: [{ role: "user", content: prompt }],
    });
    const block = response.content.find((b) => b.type === "tool_use") as any;
    const deliverable = coerceDeliverable(block?.input, taskTitle);
    if (!deliverable) { res.status(502).json({ error: "generation_failed" }); return; }
    res.status(200).json(deliverable);
  } catch (err) {
    logger.error("runTask failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "generation_failed" });
  }
}
