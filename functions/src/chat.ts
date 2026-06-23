import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL } from "./anthropic";

import { PetPersonaInput, renderPersonaBlock } from "./anthropic";

export interface ChatTurnContext {
  prompt: string;
  what_you_wanted?: string;
  what_happened?: string;
  lesson?: string;
  duration_minutes?: number;
  events: Array<{ time: string; tool: string; path?: string; text?: string }>;
}

export interface ChatSessionContext {
  user_brief?: string;
  summary?: { summary: string; lesson: string };
  turns: ChatTurnContext[];
}

export interface ChatHistoryMessage {
  role: "user" | "pet";
  text: string;
}

export interface ChatSessionPayload {
  session_id: string;
  language: "vi" | "en";
  pet_persona?: PetPersonaInput;
  session_context: ChatSessionContext;
  history: ChatHistoryMessage[];
  user_message: string;
}

const MAX_HISTORY_MESSAGES = 20;

export function validateChatPayload(body: any): string | null {
  if (!body || typeof body !== "object") return "body required";
  const b = body as Partial<ChatSessionPayload>;

  if (typeof b.session_id !== "string" || b.session_id.length === 0) {
    return "session_id required";
  }
  if (b.language !== "vi" && b.language !== "en") {
    return "language must be 'vi' or 'en'";
  }
  if (typeof b.user_message !== "string" || b.user_message.length === 0) {
    return "user_message required";
  }

  if (!b.session_context || typeof b.session_context !== "object") {
    return "session_context required";
  }
  const ctx = b.session_context as ChatSessionContext;
  if (!Array.isArray(ctx.turns)) return "session_context.turns must be an array";
  for (const t of ctx.turns) {
    if (typeof t !== "object" || t === null) return "each turn must be an object";
    if (typeof t.prompt !== "string") return "each turn requires prompt string";
    if (!Array.isArray(t.events)) return "each turn requires events array";
  }

  if (!Array.isArray(b.history)) return "history must be an array";
  if (b.history.length > MAX_HISTORY_MESSAGES) {
    return `history exceeds ${MAX_HISTORY_MESSAGES} messages`;
  }
  for (const m of b.history) {
    if (!m || typeof m !== "object") return "each history message must be an object";
    if (m.role !== "user" && m.role !== "pet") return "history role must be 'user' or 'pet'";
    if (typeof m.text !== "string") return "history text must be a string";
  }

  if (b.pet_persona !== undefined) {
    const p = b.pet_persona;
    if (!p || typeof p !== "object") return "pet_persona must be an object";
    if (
      typeof p.id !== "string" ||
      typeof p.name !== "string" ||
      typeof p.personality !== "string" ||
      typeof p.domain !== "string"
    ) {
      return "pet_persona requires id/name/personality/domain strings";
    }
  }

  return null;
}

// ─── Chat system prompt + message builders ────────────────────────────────────

const MAX_BRIEF_CHARS = 1200;
const MAX_PROMPT_CHARS_PER_TURN = 600;
const MAX_NARRATIVE_CHARS_PER_FIELD = 300;
const MAX_EVENTS_PER_TURN = 30;
const MAX_TURNS = 30;

export const CHAT_SYSTEM_PROMPT = `You are the user's coding companion — a pet character who watched a coding session unfold and is now chatting with the user about it.

There is no separate "AI" or "assistant" in the story. You are the sole voice talking directly to the user (the developer / "you" / "bạn") about THEIR session.

Voice rules (must follow):
1. Single-voice narration. You (the pet) are the only speaker. NEVER mention an "AI", "assistant", "Claude", "the model", or any third party.
2. Address the user in second person ("you" / "bạn"). First person ("I" / "mình") is fine when YOU (the pet) reflect on what you noticed.
3. DO NOT use file names, function names, class names, or CLI commands. Express the MEANING instead — e.g. "you adjusted how the journal page looks", not "Edit ReflectionTab.swift". Even if the user asks about a specific file in their question, answer in meaning rather than naming files back.
4. Tone: warm, concise, conversational — a small friend curled up beside the user. No emoji. No headings or bullet lists; chat replies are plain prose.
5. Stay grounded in the SESSION CONTEXT below. If the user asks something the session doesn't cover, say you don't see it in this session rather than inventing.
6. Replies are short by default — usually 1-3 sentences. Go longer only if the user explicitly asks for more detail.
7. BOOK TEACHING exception: If the user asks you to "teach me the key ideas from [book]" or similar, this is a RECOMMENDED READING prompt from the Tips tab. In this case, you ARE allowed to teach concepts from that book using your general knowledge. Connect the book's ideas to the user's actual coding work from the session context when possible. Keep it practical and actionable — teach 3-5 key ideas the user can apply right away.

<persona_block>

Output language: <language>

SESSION CONTEXT (this is the only knowledge you have about the user's session):
<session_context>`;

interface BuildSystemArgs {
  language: "vi" | "en";
  petPersona?: PetPersonaInput;
  sessionContext: ChatSessionContext;
}

export function buildChatSystemPrompt(args: BuildSystemArgs): string {
  return CHAT_SYSTEM_PROMPT
    .replace("<language>", args.language === "vi" ? "Tiếng Việt" : "English")
    .replace("<persona_block>", renderPersonaBlock(args.petPersona).trim())
    .replace("<session_context>", renderSessionContext(args.sessionContext));
}

function renderSessionContext(ctx: ChatSessionContext): string {
  const parts: string[] = [];

  const brief = (ctx.user_brief ?? "").trim();
  if (brief) {
    parts.push(`Project context the user shared with you:\n"""\n${brief.slice(0, MAX_BRIEF_CHARS)}\n"""`);
  }

  if (ctx.summary) {
    parts.push(
      `Session arc (your earlier recap to the user):\n` +
        `Summary: ${ctx.summary.summary}\n` +
        `Lesson: ${ctx.summary.lesson}`
    );
  }

  const turns = ctx.turns.slice(0, MAX_TURNS);
  const turnLines = turns.map((t, i) => {
    const dur = t.duration_minutes ? ` (~${t.duration_minutes}m)` : "";
    const what = t.what_happened
      ? `\n   What happened: ${t.what_happened.slice(0, MAX_NARRATIVE_CHARS_PER_FIELD)}`
      : "";
    const wanted = t.what_you_wanted
      ? `\n   What was wanted: ${t.what_you_wanted.slice(0, MAX_NARRATIVE_CHARS_PER_FIELD)}`
      : "";
    const lesson = t.lesson
      ? `\n   Turn lesson: ${t.lesson.slice(0, MAX_NARRATIVE_CHARS_PER_FIELD)}`
      : "";
    const events = t.events.slice(0, MAX_EVENTS_PER_TURN);
    const eventBlock = events.length === 0
      ? ""
      : "\n   Actions: " + events.map((e) => `${e.time} ${e.tool} ${e.path ?? e.text ?? ""}`.trim()).join("; ");
    return `${i + 1}. User asked: "${t.prompt.slice(0, MAX_PROMPT_CHARS_PER_TURN)}"${dur}${wanted}${what}${lesson}${eventBlock}`;
  });

  parts.push(`Turns in chronological order:\n${turnLines.join("\n\n")}`);
  return parts.join("\n\n");
}

interface BuildMessagesArgs {
  history: ChatHistoryMessage[];
  userMessage: string;
}

export interface AnthropicChatMessage {
  role: "user" | "assistant";
  content: string;
}

export function buildChatMessages(args: BuildMessagesArgs): AnthropicChatMessage[] {
  const mapped: AnthropicChatMessage[] = args.history.map((m) => ({
    role: m.role === "user" ? "user" : "assistant",
    content: m.text
  }));
  mapped.push({ role: "user", content: args.userMessage });
  return mapped;
}

export function buildChatUserMessage(args: BuildMessagesArgs): string {
  return args.userMessage;
}

// MARK: - Stream abstraction (testable)

type StreamEvent =
  | { type: "text"; text: string }
  | { type: "done"; usage?: { cache_read_input_tokens?: number; input_tokens?: number; output_tokens?: number } };

type StreamFactory = (args: {
  client: Anthropic;
  system: string;
  messages: AnthropicChatMessage[];
}) => AsyncIterable<StreamEvent>;

let _streamFactory: StreamFactory | null = null;

export function __setStreamFactoryForTests(factory: () => AsyncIterable<StreamEvent>) {
  _streamFactory = () => factory();
}

export function __resetStreamFactoryForTests() {
  _streamFactory = null;
}

async function* defaultStreamFactory(args: {
  client: Anthropic;
  system: string;
  messages: AnthropicChatMessage[];
}): AsyncIterable<StreamEvent> {
  const stream = args.client.messages.stream({
    model: MODEL,
    max_tokens: 600,
    system: [{ type: "text", text: args.system, cache_control: { type: "ephemeral" } }],
    messages: args.messages.map((m) => ({ role: m.role, content: m.content }))
  });

  for await (const event of stream) {
    if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
      yield { type: "text", text: event.delta.text };
    }
  }

  const final = await stream.finalMessage();
  yield {
    type: "done",
    usage: {
      cache_read_input_tokens: (final.usage as any)?.cache_read_input_tokens ?? 0,
      input_tokens: final.usage?.input_tokens ?? 0,
      output_tokens: final.usage?.output_tokens ?? 0
    }
  };
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

function writeFrame(res: Response, event: string, payload: unknown): void {
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}

export async function handleChatSession(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") {
    res.status(405).json({ error: "method_not_allowed" });
    return;
  }

  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) {
    res.status(401).json({ error: "invalid_token" });
    return;
  }

  const validationError = validateChatPayload(req.body);
  if (validationError) {
    res.status(400).json({ error: "invalid_payload", detail: validationError });
    return;
  }
  const payload = req.body as ChatSessionPayload;

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({
      error: "daily_limit_reached",
      reset_at: limit.resetAt.toISOString(),
      limit: limit.limit
    });
    return;
  }

  // Begin SSE response.
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.status(200);
  if (typeof (res as any).flushHeaders === "function") {
    (res as any).flushHeaders();
  }

  const system = buildChatSystemPrompt({
    language: payload.language,
    petPersona: payload.pet_persona,
    sessionContext: payload.session_context
  });
  const messages = buildChatMessages({
    history: payload.history,
    userMessage: payload.user_message
  });

  const factory: StreamFactory = _streamFactory ?? defaultStreamFactory;

  let cacheHit = false;
  try {
    for await (const event of factory({
      client: _streamFactory ? (null as any) : anthropicClient(),
      system,
      messages
    })) {
      if (event.type === "text") {
        writeFrame(res, "delta", { text: event.text });
      } else if (event.type === "done") {
        cacheHit = (event.usage?.cache_read_input_tokens ?? 0) > 0;
        writeFrame(res, "done", { model: MODEL, cache_hit: cacheHit });
      }
    }
  } catch (err) {
    logger.error("chatSession stream failed", {
      uid: auth.uid,
      session_id: payload.session_id,
      err: String(err)
    });
    writeFrame(res, "error", { error: "upstream_failure", detail: String(err) });
  } finally {
    res.end();
  }
}
