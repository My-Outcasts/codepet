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
