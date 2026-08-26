import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { checkAndIncrement } from "./rateLimit";
import { MODEL, cacheableSystemBlock } from "./anthropic";
import {
  AnthropicChatMessage,
  ChatSessionPayload,
  buildChatMessages,
  buildChatSystemPrompt,
  validateChatPayload,
} from "./chatCore";

// Re-exported so `./chat` stays the name callers and tests already import.
export * from "./chatCore";

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
    system: [cacheableSystemBlock({ model: MODEL, text: args.system })],
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
