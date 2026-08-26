import { Effort } from "./anthropic";
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { ROADMAP_SYSTEM, ROADMAP_TOOL, buildRoadmapPrompt, coerceRoadmap, RoadmapBrief } from "./generateRoadmapCore";

// Quality surface / credit driver — same tier as runTask (see spec).
// Sonnet 5 rather than Opus 4.8 for the same reason runTask moved: forced
// tool call against a fixed schema, 40% cheaper per token. Sonnet 5 thinks by
// default when `thinking` is omitted, so the cap below covers thinking too.
const ROADMAP_MODEL = "claude-sonnet-5";
const ROADMAP_EFFORT: Effort = "medium";
// Was 3000, sized before thinking counted against the same budget. Headroom is
// only billed if generated.
const ROADMAP_MAX_TOKENS = 8000;

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

interface GenerateRoadmapRequestBody {
  company_id?: string | null;
  language?: string;
  companion_id?: string;
  brief?: RoadmapBrief;
}

export async function handleGenerateRoadmap(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) { res.status(401).json({ error: "invalid_token" }); return; }

  const body = (req.body ?? {}) as GenerateRoadmapRequestBody;
  const brief = body.brief;
  if (!brief || typeof brief !== "object" || Array.isArray(brief)) {
    res.status(400).json({ error: "invalid_payload", detail: "brief required" });
    return;
  }

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({ error: "daily_limit_reached", reset_at: limit.resetAt.toISOString(), limit: limit.limit });
    return;
  }

  const language = body.language === "vi" ? "vi" : "en";

  try {
    const response = await client().messages.create({
      model: ROADMAP_MODEL,
      max_tokens: ROADMAP_MAX_TOKENS,
      output_config: { effort: ROADMAP_EFFORT },
      system: ROADMAP_SYSTEM,
      tools: [ROADMAP_TOOL as any],
      tool_choice: { type: "tool", name: "record_roadmap" },
      messages: [{ role: "user", content: buildRoadmapPrompt({ language, brief }) }],
    });
    const block = response.content.find((b) => b.type === "tool_use") as any;
    res.status(200).json(coerceRoadmap(block?.input, { language }));
  } catch (err) {
    logger.error("generateRoadmap failed", { uid: auth.uid, err: String(err) });
    res.status(200).json({ tasks: [] }); // fail-open — native treats [] as no-change
  }
}
