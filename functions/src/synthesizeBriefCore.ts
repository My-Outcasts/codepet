/**
 * The payload contract, the prompt, and the schema for `synthesizeBrief` — everything that
 * decides WHAT is asked, with nothing that decides who answers.
 *
 * Split from the handler for the reason `enrichBriefCore` records: the local path is
 * esbuild-bundled into the app, so a builder that imports the Anthropic SDK ships the SDK.
 */

export interface BriefSessionInput {
  date?: string;     // e.g. "2026-06-10" — for ordering / sense of time
  summary: string;   // the session summary text
  lesson?: string;   // optional overarching lesson
}

export interface SynthesizeBriefPayload {
  language: "vi" | "en";
  project: { name: string };
  sessions: BriefSessionInput[];
  current_brief?: string;  // the user's current description, if any (for continuity)
}

export interface OverviewOutput {
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

export const SYNTH_SYSTEM_PROMPT = `You write ONE short, complete description of what a software project IS, by reading the history of work sessions on it.

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

/**
 * The system prompt with its one placeholder filled.
 *
 * A function rather than an inline `.replace` at the call site because the local
 * (`claude -p`) path needs the SAME prompt: two copies of a language substitution is how
 * a Vietnamese founder ends up with an English overview on one transport only.
 */
export function synthesizeSystemPrompt(language: "vi" | "en"): string {
  return SYNTH_SYSTEM_PROMPT.replace("<language>", language === "vi" ? "Tiếng Viet" : "English");
}

export const OVERVIEW_TOOL = {
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

export function buildSynthesizeUserMessage(payload: SynthesizeBriefPayload): string {
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
