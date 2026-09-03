import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import {
  buildExtractPrompt,
  ExtractRequestBody,
  parseDeliverable,
  parseExisting,
  coerceDecisions,
  DECISIONS_EXTRACT_SCHEMA,
  EXTRACT_SYSTEM,
} from "./extractDecisionsCore";

// Light model — extraction is simple; matches companyChat's tier.
const DECISIONS_MODEL = "claude-sonnet-5";

const RECORD_TOOL = {
  name: "record_decisions",
  description: "Record the durable decisions this approved deliverable locks in.",
  input_schema: DECISIONS_EXTRACT_SCHEMA,
} as const;

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

export async function handleExtractDecisions(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) { res.status(401).json({ error: "invalid_token" }); return; }

  const body = (req.body ?? {}) as ExtractRequestBody;
  const deliverable = parseDeliverable(body);
  // Fire-and-forget call: invalid input is harmless — nothing to extract.
  if (!deliverable) { res.status(200).json({ decisions: [] }); return; }

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({ error: "daily_limit_reached", reset_at: limit.resetAt.toISOString(), limit: limit.limit });
    return;
  }

  try {
    const response = await client().messages.create({
      model: DECISIONS_MODEL,
      // 1024 was set when this cap covered the answer alone. Sonnet 5 thinks by
      // default, and thinking is charged against the same budget, so a decision
      // list that fit before could return truncated tool JSON — which this
      // handler cannot distinguish from a model that ignored the schema,
      // because it fails open to an empty list.
      max_tokens: 3000,
      // Extraction from text already in the prompt. Nothing here needs the
      // `high` default; `low` is the whole point of running it on a mid tier.
      output_config: { effort: "low" },
      system: EXTRACT_SYSTEM,
      tools: [RECORD_TOOL as any],
      tool_choice: { type: "tool", name: "record_decisions" },
      messages: [{ role: "user", content: buildExtractPrompt(deliverable, parseExisting(body)) }],
    });
    const block = response.content.find((b) => b.type === "tool_use") as any;
    res.status(200).json(coerceDecisions(block?.input));
  } catch (err) {
    logger.error("extractDecisions failed", { uid: auth.uid, err: String(err) });
    res.status(200).json({ decisions: [] }); // fail-open — approval already happened client-side
  }
}
