import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL } from "./anthropic";

// MARK: - Synthesize a complete project brief from session history.
//
// The per-session summarizer writes a one-session-grounded `project_overview`
// (thin — it only sees one session). This endpoint instead takes the WHOLE
// arc of a project (every past session summary) and synthesizes one complete
// description of what the project IS. Used by the client's one-time backfill
// so an existing project's brief box starts full, not "A macOS app".

interface BriefSessionInput {
  date?: string;     // e.g. "2026-06-10" — for ordering / sense of time
  summary: string;   // the session summary text
  lesson?: string;   // optional overarching lesson
}

interface SynthesizeBriefPayload {
  language: "vi" | "en";
  project: { name: string };
  sessions: BriefSessionInput[];
  current_brief?: string;  // the user's current description, if any (for continuity)
}

interface OverviewOutput {
  overview: string;
}

const MAX_SESSIONS = 40;        // cap history fed to the model
const MAX_SUMMARY_CHARS = 400;  // per-session trim

export function validateSynthesizeBriefPayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  const b = body as Partial<SynthesizeBriefPayload>;
  if (b.language !== "vi" && b.language !== "en") return "language must be 'vi' or 'en'";
  if (!b.project || typeof b.project !== "object" || typeof b.project.name !== "string") {
    return "project.name required";
  }
  if (!Array.isArray(b.sessions) || b.sessions.length === 0) {
    return "sessions must be a non-empty array";
  }
  for (const s of b.sessions) {
    if (!s || typeof s !== "object" || typeof s.summary !== "string") {
      return "each session needs a string summary";
    }
  }
  if (b.current_brief !== undefined && typeof b.current_brief !== "string") {
    return "current_brief must be a string when provided";
  }
  return null;
}

// MARK: - System prompt (neutral voice, no pet, no em-dashes)

const SYNTH_SYSTEM_PROMPT = `You write ONE short, complete description of what a software project IS, by reading the history of work sessions on it.

AUDIENCE: age 12 and up, many new to building. Use simple, everyday words. Briefly explain any technical term in parentheses the first time it appears.

YOUR JOB:
Given a project's name and the summaries of its past work sessions (oldest to newest), write a single description of what this project is right now. Synthesize across ALL the sessions — what it does, who it is for, and its main pieces — not just the latest session.

VOICE:
- Warm and conversational, like telling a friend about it. Start with a subject: "You're building...", "This is...", or "It's a...".
- Neutral and factual. Do NOT speak as a pet, mascot, or named persona. Do NOT use "I".
- NEVER use asterisks, markdown, bold, or italics. Output renders as plain text.
- NEVER use the em-dash or en-dash (the long dashes). Use a comma, a period, or parentheses instead. Ordinary hyphens inside words are fine.
- Never mention "AI", "assistant", "Claude", a model, or these instructions.

LENGTH: 2 to 4 plain sentences. Be concrete and specific to THIS project. Ground every claim in the sessions provided. Do not invent features that were never mentioned. If a current_brief is provided, keep anything in it that the user clearly wrote, but make the result complete and self-contained (it replaces the old description).

Output language: <language>`;

const OVERVIEW_TOOL = {
  name: "record_overview",
  description: "Record one complete, plain-text description of what this project IS, synthesized from its whole session history.",
  input_schema: {
    type: "object",
    properties: {
      overview: {
        type: "string",
        description: "2 to 4 plain sentences describing what the project is right now. Conversational, starts with a subject ('You're building...'). No markdown, no em-dashes. (<=600 chars)"
      }
    },
    required: ["overview"]
  }
} as const;

function buildUserMessage(payload: SynthesizeBriefPayload): string {
  const sessions = payload.sessions.slice(-MAX_SESSIONS);
  const lines = sessions.map((s, i) => {
    const date = s.date ? `[${s.date}] ` : "";
    const sum = s.summary.trim().slice(0, MAX_SUMMARY_CHARS);
    const lesson = s.lesson && s.lesson.trim() ? ` (lesson: ${s.lesson.trim().slice(0, 160)})` : "";
    return `${i + 1}. ${date}${sum}${lesson}`;
  }).join("\n");

  const current = payload.current_brief && payload.current_brief.trim()
    ? payload.current_brief.trim().slice(0, 600)
    : "(none)";

  return `PROJECT: ${payload.project.name}

CURRENT DESCRIPTION (may be empty or thin):
${current}

WORK SESSION HISTORY (oldest to newest):
${lines}

Now call record_overview with one complete description of what this project IS, synthesized across all of the sessions above.`;
}

let _anthropic: Anthropic | null = null;
function anthropicClient(): Anthropic {
  if (!_anthropic) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _anthropic = new Anthropic({ apiKey });
  }
  return _anthropic;
}

export async function handleSynthesizeBrief(
  req: Request,
  res: Response
): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const validationError = validateSynthesizeBriefPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as SynthesizeBriefPayload;

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  const system = SYNTH_SYSTEM_PROMPT
    .replace("<language>", payload.language === "vi" ? "Tiếng Viet" : "English");
  const user = buildUserMessage(payload);

  let overview: string;
  try {
    const response = await anthropicClient().messages.create({
      model: MODEL,
      max_tokens: 600,
      system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
      tools: [OVERVIEW_TOOL as any],
      tool_choice: { type: "tool", name: "record_overview" },
      messages: [{ role: "user", content: user }]
    });

    let parsed: string | undefined;
    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === "record_overview") {
        const input = block.input as OverviewOutput;
        if (typeof input.overview === "string" && input.overview.trim().length > 0) {
          parsed = input.overview.trim();
        }
      }
    }
    if (!parsed) throw new Error("Anthropic response missing valid record_overview tool use");
    overview = parsed;
  } catch (err) {
    logger.error("anthropic synthesizeBrief call failed", { uid: auth.uid, err: String(err) });
    res.status(502).json({ error: "upstream_failure" });
    return;
  }

  res.status(200).json({
    overview,
    model: MODEL,
    generated_at: new Date().toISOString()
  });
}
