import { Effort } from "./anthropic";
import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { buildMcpConfig, loadConnectors, MCP_CLIENT_BETA, type McpConfig } from "./oauth/connectors";
import { checkAndIncrement } from "./rateLimit";
import {
  ClaudeMessage,
  buildChatRequest,
  resolveActions,
  type ChatRequestBody,
} from "./companyChatCore";

const CHAT_MODEL = "claude-sonnet-5";

// Output budget for one chat turn. Was 1024, which truncated real answers mid-word — the
// founder reported two, and the cap covers the WHOLE response, so a turn that also files a
// remember_fact spends the same budget on tool JSON. 4096 leaves room for a numbered plan plus
// a memory note. A turn that still hits it is now logged rather than silently cut (see the
// stop_reason warn below), because the failure is invisible from the transcript.
const CHAT_MAX_TOKENS = 4096;
// Sonnet 5 defaults to `high` effort. `medium` is the cost lever on the
// highest-volume model call in the product: it shortens thinking, which also
// buys back room under CHAT_MAX_TOKENS (the cap covers thinking and reply
// together, and this handler already logs when a turn hits it). This is the
// most user-visible change of the batch — raise it first if replies get
// shallower.
const CHAT_EFFORT: Effort = "medium";

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey });
  }
  return _client;
}


// ─── SSE streaming (opt-in via `Accept: text/event-stream`) ────────────────
// Mirrors chat.ts's handleChatSession stream contract exactly: same StreamEvent
// shape, same `delta`/`done`/`error` SSE frame format (event name + `data:` JSON
// shape), and the same injectable stream-factory test seam — so the native
// client's existing SSEParser (built for chatSession) can parse companyChat's
// stream unchanged. See src/chat.ts for the twin implementation.

// Beyond text/done, the stream can also surface a run_task tool_use block being
// built up incrementally (Anthropic streams a tool call's input as JSON-delta
// fragments across content_block_start → content_block_delta(input_json_delta) →
// content_block_stop). These three variants let the handler accumulate that JSON
// without the stream factory itself needing to know about run_task validation.
type StreamEvent =
  | { type: "text"; text: string }
  | { type: "tool_use_start"; index: number; name: string }
  | { type: "tool_use_delta"; index: number; partial_json: string }
  | { type: "tool_use_stop"; index: number }
  | { type: "done"; stopReason?: string | null; usage?: { cache_read_input_tokens?: number; input_tokens?: number; output_tokens?: number } };

type StreamFactory = (args: {
  client: Anthropic;
  systemBlocks: Array<{ type: "text"; text: string; cache_control?: { type: "ephemeral" } }>;
  messages: ClaudeMessage[];
  tools?: unknown[];
  /** Connector MCP servers, when the founder has authorised any. */
  mcpServers?: McpConfig["mcpServers"];
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
  systemBlocks: Array<{ type: "text"; text: string; cache_control?: { type: "ephemeral" } }>;
  messages: ClaudeMessage[];
  tools?: unknown[];
  mcpServers?: McpConfig["mcpServers"];
}): AsyncIterable<StreamEvent> {
  const params = {
    model: CHAT_MODEL,
    max_tokens: CHAT_MAX_TOKENS,
    output_config: { effort: CHAT_EFFORT },
    system: args.systemBlocks as any,
    messages: args.messages.map((m) => ({ role: m.role, content: m.content })),
    ...(args.tools && args.tools.length ? { tools: args.tools as any } : {}),
  };
  // Only take the beta path when there is actually a connector to reach. A turn
  // for a founder who has authorised nothing keeps the exact request it has
  // today, so connectors cannot regress the common case.
  const stream = args.mcpServers && args.mcpServers.length
    ? args.client.beta.messages.stream({
        ...params,
        betas: [MCP_CLIENT_BETA],
        mcp_servers: args.mcpServers,
      } as any)
    : args.client.messages.stream(params);

  for await (const event of stream) {
    if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
      yield { type: "text", text: event.delta.text };
    } else if (event.type === "content_block_delta" && event.delta.type === "input_json_delta") {
      yield { type: "tool_use_delta", index: event.index, partial_json: (event.delta as any).partial_json ?? "" };
    } else if (event.type === "content_block_start" && (event.content_block as any).type === "tool_use") {
      yield { type: "tool_use_start", index: event.index, name: (event.content_block as any).name };
    } else if (event.type === "content_block_stop") {
      yield { type: "tool_use_stop", index: event.index };
    }
  }

  const final = await stream.finalMessage();
  yield {
    type: "done",
    stopReason: final.stop_reason ?? null,
    usage: {
      cache_read_input_tokens: (final.usage as any)?.cache_read_input_tokens ?? 0,
      input_tokens: final.usage?.input_tokens ?? 0,
      output_tokens: final.usage?.output_tokens ?? 0
    }
  };
}

function writeFrame(res: Response, event: string, payload: unknown): void {
  res.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}

// Resolves the completed tool_use blocks from a turn (regardless of whether
// they came from the non-streaming response.content array, or were
// accumulated from stream events) into the turn's action fields. run_task,
// navigate, and setup_capability are mutually exclusive — the first of that
// trio that produced a VALID action wins (same priority order as the web app's
// route.ts: run_task, then navigate, then setup_capability); a tool that fired
// but didn't validate (hallucinated task, unknown destination, unmatched
// toolkit item) falls through to the next candidate rather than winning by
// default. remember_fact is orthogonal — it's resolved independently and can
// co-occur with any of the other three in the same turn.
export async function handleCompanyChat(req: Request, res: Response): Promise<void> {
  if (req.method !== "POST") { res.status(405).json({ error: "method_not_allowed" }); return; }
  const auth = await verifyAuth(req.headers.authorization);
  if (!auth) { res.status(401).json({ error: "invalid_token" }); return; }

  const body = (req.body ?? {}) as ChatRequestBody;
  const userMessage = typeof body.user_message === "string" ? body.user_message.trim() : "";
  if (!userMessage) { res.status(400).json({ error: "invalid_payload", detail: "user_message required" }); return; }

  const limit = await checkAndIncrement(auth.uid);
  if (!limit.allowed) {
    res.status(429).json({ error: "daily_limit_reached", reset_at: limit.resetAt.toISOString(), limit: limit.limit });
    return;
  }

  // Connectors the founder has authorised. Fail-open: if the read or a decrypt throws,
  // chat proceeds with no connectors rather than taking byte offline for that founder
  // over one bad credential. This is the one part of assembly the sidecar cannot share —
  // it needs Firestore and the founder's uid.
  let mcp: McpConfig = { mcpServers: [], mcpToolsets: [] };
  try {
    const encKey = process.env.CONNECTOR_ENC_KEY;
    if (encKey) mcp = buildMcpConfig(await loadConnectors(auth.uid, encKey));
  } catch (err) {
    logger.warn("connector load failed; continuing without", { uid: auth.uid, err: String(err) });
  }

  // One builder for both paths — see buildChatRequest in companyChatCore. Each declared
  // MCP server must be referenced by exactly one toolset or the request is rejected;
  // buildMcpConfig keeps the two lists in step.
  const { systemBlocks, messages, tools, runnable, openTasks, envSetup } =
    buildChatRequest(body, mcp.mcpToolsets);

  const wantsStream = typeof req.headers.accept === "string" && req.headers.accept.includes("text/event-stream");

  if (!wantsStream) {
    // Existing non-streaming JSON path — response shape now additionally supports
    // a real run_task_id (was hardcoded null); already-deployed native app
    // versions that never send `runnable` still get run_task_id: null unchanged.
    try {
      const baseParams = {
        model: CHAT_MODEL,
        max_tokens: CHAT_MAX_TOKENS,
        output_config: { effort: CHAT_EFFORT },
        system: systemBlocks as any,
        messages: messages as any,
        ...(tools ? { tools: tools as any } : {}),
      };
      const response = mcp.mcpServers.length
        ? await client().beta.messages.create({
            ...baseParams,
            betas: [MCP_CLIENT_BETA],
            mcp_servers: mcp.mcpServers,
          } as any)
        : await client().messages.create(baseParams);
      const reply = response.content
        .filter((b) => b.type === "text")
        .map((b) => (b as { text: string }).text)
        .join("")
        .trim();
      const toolUses = response.content
        .filter((b) => b.type === "tool_use")
        .map((b) => ({ name: (b as any).name as string, input: (b as any).input }));
      const { runTaskId, nav, setup, remember, completeTaskId, addTask, drafts } =
        resolveActions(toolUses, runnable, envSetup, openTasks);

      // Additive, backward-compatible response shape: run_task_id is always
      // present (existing behavior); nav/setup/remember are only included when
      // the turn actually produced one — old clients that only look for
      // {reply, run_task_id} are unaffected, and unknown fields are ignored.
      const responseBody: Record<string, unknown> = { reply, run_task_id: runTaskId };
      if (completeTaskId) responseBody.complete_task_id = completeTaskId;
      if (addTask) responseBody.add_task = addTask;
      if (drafts) responseBody.drafts = drafts;
      if (nav) responseBody.nav = nav;
      if (setup) responseBody.setup = setup;
      if (remember.length) responseBody.remember = remember;
      res.status(200).json(responseBody);
    } catch (err) {
      logger.error("companyChat failed", { uid: auth.uid, err: String(err) });
      res.status(502).json({ error: "generation_failed" });
    }
    return;
  }

  // Streaming path — SSE, opted into via `Accept: text/event-stream`. Frame
  // format matches chat.ts's handleChatSession exactly (delta/done/error).
  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");
  res.status(200);
  if (typeof (res as any).flushHeaders === "function") {
    (res as any).flushHeaders();
  }

  const factory: StreamFactory = _streamFactory ?? defaultStreamFactory;

  // Generalized N-tool accumulator: any tool_use block (run_task, navigate,
  // setup_capability, remember_fact, or an unrecognized future tool) is
  // tracked by its content-block index while its JSON input streams in
  // (content_block_start → input_json_delta* → content_block_stop), then moved
  // into `completedToolUses` once its block closes. This replaces the old
  // single-purpose run_task-only accumulator — the same shape now serves every
  // tool this turn might call, including several in the same response.
  const openToolUses = new Map<number, { name: string; json: string }>();
  const completedToolUses: Array<{ name: string; input: unknown }> = [];
  // Enough to attribute an empty turn without guessing: how much text ever streamed, and which
  // tools the model reached for. A turn with zero of both is the shape the founder saw as "I
  // didn't have an answer for that" — measured client-side as one `done` frame, no deltas.
  let textChars = 0;
  const toolsCalled: string[] = [];

  try {
    for await (const event of factory({
      client: _streamFactory ? (null as any) : client(),
      systemBlocks,
      messages,
      tools,
      mcpServers: mcp.mcpServers
    })) {
      if (event.type === "text") {
        textChars += event.text.length;
        writeFrame(res, "delta", { text: event.text });
      } else if (event.type === "tool_use_start") {
        toolsCalled.push(event.name);
        openToolUses.set(event.index, { name: event.name, json: "" });
      } else if (event.type === "tool_use_delta") {
        const acc = openToolUses.get(event.index);
        if (acc) acc.json += event.partial_json;
      } else if (event.type === "tool_use_stop") {
        const acc = openToolUses.get(event.index);
        if (acc) {
          let input: unknown = {};
          try {
            input = acc.json ? JSON.parse(acc.json) : {};
          } catch (parseErr) {
            logger.error("companyChat tool_use JSON parse failed", {
              uid: auth.uid,
              name: acc.name,
              err: String(parseErr)
            });
            input = {};
          }
          completedToolUses.push({ name: acc.name, input });
          openToolUses.delete(event.index);
        }
      } else if (event.type === "done") {
        const cacheHit = (event.usage?.cache_read_input_tokens ?? 0) > 0;
        const { runTaskId, nav, setup, remember, completeTaskId, addTask, drafts } =
          resolveActions(completedToolUses, runnable, envSetup, openTasks);
        // Truncation was silent by construction: the API reports it, this function ignored it,
        // and the client rendered half a sentence as a finished answer.
        if (event.stopReason === "max_tokens") {
          logger.warn("companyChat hit the output cap", {
            uid: auth.uid, textChars, toolsCalled, max_tokens: CHAT_MAX_TOKENS
          });
        }
        // A tool that fired and did not validate is dropped on purpose (a hallucinated task id
        // must not run something), but dropping it QUIETLY made "can we do the task in here"
        // answerable with nothing at all.
        const droppedTools = completedToolUses
          .filter((t) => (t.name === "run_task" && !runTaskId)
                      || (t.name === "navigate" && !nav)
                      || (t.name === "setup_capability" && !setup)
                      || (t.name === "complete_task" && !completeTaskId)
                      || (t.name === "add_task" && !addTask)
                      || (t.name === "draft_message" && !drafts))
          .map((t) => ({ name: t.name, input: t.input }));
        if (droppedTools.length) {
          logger.warn("companyChat dropped a tool call that failed validation", {
            uid: auth.uid, droppedTools, runnableIds: runnable.map((r) => r.id)
          });
        }
        // The whole point of this pass: an empty turn is now attributable rather than a mystery.
        if (textChars === 0 && !runTaskId && !nav && !setup && !remember.length
            && !completeTaskId && !addTask && !drafts) {
          logger.warn("companyChat produced an EMPTY turn", {
            uid: auth.uid,
            stopReason: event.stopReason ?? null,
            toolsCalled,
            completedToolUses: completedToolUses.map((t) => t.name),
            mcpServers: mcp.mcpServers.length,
            toolsOffered: (tools as Array<{ name?: string }>).map((t) => t?.name ?? "?"),
            messageCount: messages.length
          });
        }
        // run_task_id/nav/setup/remember are additive on the existing done
        // frame — old clients that only look for {model, cache_hit,
        // run_task_id} are unaffected; nav/setup/remember are only included
        // when the turn actually produced one.
        const doneFrame: Record<string, unknown> = { model: CHAT_MODEL, cache_hit: cacheHit, run_task_id: runTaskId };
        if (completeTaskId) doneFrame.complete_task_id = completeTaskId;
        if (addTask) doneFrame.add_task = addTask;
        if (drafts) doneFrame.drafts = drafts;
        if (nav) doneFrame.nav = nav;
        if (setup) doneFrame.setup = setup;
        if (remember.length) doneFrame.remember = remember;
        writeFrame(res, "done", doneFrame);
      }
    }
  } catch (err) {
    logger.error("companyChat stream failed", { uid: auth.uid, err: String(err) });
    writeFrame(res, "error", { error: "upstream_failure", detail: String(err) });
  } finally {
    res.end();
  }
}
