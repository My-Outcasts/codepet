import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL } from "./anthropic";
import {
  CompanyBrief,
  BriefEnrichment,
  ENRICH_SYSTEM,
  ENRICH_TOOL,
  buildEnrichPrompt,
  hasEnrichableSignal,
  mergeEnrichment,
} from "./enrichBriefCore";

// Re-exported so `./enrichBrief` stays the name callers already import, whichever half of
// it they wanted.
export * from "./enrichBriefCore";

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
