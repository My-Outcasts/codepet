import { Effort } from "./anthropic";
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { DELIVERABLE_SYSTEM, DELIVERABLE_TOOL, buildRunTaskPrompt, coerceDeliverable, parseUpstream } from "./runTaskCore";

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
  // Finished work from the tasks this one dependsOn. `unknown` because it is an array off
  // the wire whose shape is not ours to trust — `parseUpstream` is what makes it a type.
  upstream?: unknown;
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
    // What the departments this task depends on already produced. Narrowed by the shared
    // `parseUpstream` rather than inline, so this handler and the ONE_SHOT_OPS entry cannot
    // read the same wire field two different ways.
    upstream: parseUpstream(body.upstream),
  });

  try {
    const response = await client().messages.create({
      model: RUN_MODEL,
      max_tokens: RUN_MAX_TOKENS,
      output_config: { effort: RUN_EFFORT },
      system: DELIVERABLE_SYSTEM,
      tools: [DELIVERABLE_TOOL as any],
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
