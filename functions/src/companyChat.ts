import { Request } from "firebase-functions/v2/https";
import { Response } from "express";
import Anthropic from "@anthropic-ai/sdk";
import * as logger from "firebase-functions/logger";
import { verifyAuth } from "./auth";
import { buildMcpConfig, loadConnectors, MCP_CLIENT_BETA, type McpConfig } from "./oauth/connectors";
import { checkAndIncrement } from "./rateLimit";
import {
  buildSystemPrompt,
  buildContextBlock,
  buildMessages,
  buildRunnableBlock,
  buildSetupBlock,
  styleBlock,
  validateRunTaskToolUse,
  validateNavigateToolUse,
  validateSetupToolUse,
  coerceRememberFacts,
  RUN_TASK_TOOL,
  NAVIGATE_TOOL,
  SETUP_TOOL,
  REMEMBER_TOOL,
  ChatTurn,
  ClaudeMessage,
  RunnableTaskRef,
  EnvSetupItem,
  SetupCategory,
  NavAction,
  SetupAction,
  RememberedFact,
} from "./companyChatCore";

const CHAT_MODEL = "claude-sonnet-5";

let _client: Anthropic | null = null;
function client(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

interface ChatRequestBody {
  language?: string;
  companion_id?: string;
  context?: string;
  history?: ChatTurn[];
  user_message?: string;
  // Roadmap tasks byte may offer to run via the run_task tool (see companyChatCore).
  // Backward-compatible: omitted entirely by older clients → treated as [] → no tool
  // offered → behavior is byte-for-byte identical to before this field existed.
  runnable?: RunnableTaskRef[];
  // Currently-OFF toolkit items (skills/connectors/agents) byte may offer to turn on
  // via the setup_capability tool (see companyChatCore). Backward-compatible: omitted
  // entirely by older clients → treated as [] → no tool offered.
  env_setup?: EnvSetupItem[];
  // The founder's tone preferences, already composed into one prompt sentence by the
  // client (`AIStyle.promptFragment()`). Backward-compatible: omitted by older clients,
  // and omitted by current ones whenever the founder hasn't changed a knob → styleBlock
  // returns "" → the system prompt is byte-for-byte what it was before this field.
  style_fragment?: string;
}

const MAX_RUNNABLE_TASKS = 60;
const MAX_ENV_SETUP_ITEMS = 40;
const SETUP_CATEGORIES: readonly SetupCategory[] = ["skills", "connectors", "agents"];

function parseRunnable(raw: unknown): RunnableTaskRef[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((r) => {
      const o = (r ?? {}) as Record<string, unknown>;
      const id = typeof o.id === "string" ? o.id.trim() : "";
      const title = typeof o.title === "string" ? o.title.trim() : "";
      return id ? { id, title } : null;
    })
    .filter((r): r is RunnableTaskRef => r !== null)
    .slice(0, MAX_RUNNABLE_TASKS);
}

function parseEnvSetup(raw: unknown): EnvSetupItem[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((r): EnvSetupItem | null => {
      const o = (r ?? {}) as Record<string, unknown>;
      const category = typeof o.category === "string" ? o.category : "";
      const name = typeof o.name === "string" ? o.name.trim() : "";
      if (!(SETUP_CATEGORIES as readonly string[]).includes(category) || !name) return null;
      const item: EnvSetupItem = { category: category as SetupCategory, name };
      if (typeof o.why === "string") item.why = o.why;
      return item;
    })
    .filter((r): r is EnvSetupItem => r !== null)
    .slice(0, MAX_ENV_SETUP_ITEMS);
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
  | { type: "done"; usage?: { cache_read_input_tokens?: number; input_tokens?: number; output_tokens?: number } };

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
    max_tokens: 1024,
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
interface ResolvedActions {
  runTaskId: string | null;
  nav: NavAction | null;
  setup: SetupAction | null;
  remember: RememberedFact[];
}

function resolveActions(
  toolUses: Array<{ name: string; input: unknown }>,
  runnable: RunnableTaskRef[],
  envSetup: EnvSetupItem[]
): ResolvedActions {
  const runTaskUse = toolUses.find((t) => t.name === "run_task");
  const navUse = toolUses.find((t) => t.name === "navigate");
  const setupUse = toolUses.find((t) => t.name === "setup_capability");
  const rememberUse = toolUses.find((t) => t.name === "remember_fact");

  let runTaskId: string | null = null;
  let nav: NavAction | null = null;
  let setup: SetupAction | null = null;

  if (runTaskUse) runTaskId = validateRunTaskToolUse(runTaskUse.input, runnable);
  if (!runTaskId && navUse) nav = validateNavigateToolUse(navUse.input);
  if (!runTaskId && !nav && setupUse) setup = validateSetupToolUse(setupUse.input, envSetup);

  const remember = rememberUse ? coerceRememberFacts(rememberUse.input) : [];

  return { runTaskId, nav, setup, remember };
}

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

  const runnable = parseRunnable(body.runnable);
  const envSetup = parseEnvSetup(body.env_setup);

  const staticSystem = buildSystemPrompt({
    companionId: typeof body.companion_id === "string" ? body.companion_id : "byte",
    language: body.language === "vi" ? "vi" : "en",
  });
  // The founder's tone preferences, runnable-task grounding and setup-toolkit
  // grounding all live in the volatile context block (not the cached static one)
  // since they're per-request, just like the context itself. The style leads: it
  // sits directly after the persona sentence it may override, and before the
  // company grounding.
  const contextBlock =
    styleBlock(typeof body.style_fragment === "string" ? body.style_fragment : "") +
    buildContextBlock(typeof body.context === "string" ? body.context : "") +
    buildRunnableBlock(runnable) +
    buildSetupBlock(envSetup);
  const messages = buildMessages(Array.isArray(body.history) ? body.history : [], userMessage);

  // Two system blocks in both paths: the static companion prompt carries the
  // cache_control breakpoint (the pricing spec's cheap-chat lever); the volatile
  // per-request company context is a SEPARATE block AFTER it, so it never enters
  // the cached prefix.
  const systemBlocks: Array<{ type: "text"; text: string; cache_control?: { type: "ephemeral" } }> = [
    { type: "text", text: staticSystem, cache_control: { type: "ephemeral" } },
    { type: "text", text: contextBlock },
  ];

  // Tool assembly: run_task and setup_capability are only offered when there's
  // something real to run/turn on (older clients that never send `runnable` /
  // `env_setup` get neither). navigate and remember_fact don't depend on any
  // per-request list, so they're always offered. NOT forced via tool_choice —
  // byte stays free to reply in plain text, or ask a clarifying question,
  // instead of calling any of them.
  // Connectors the founder has authorised (step 6 of the OAuth work). Fail-open:
  // if the read or a decrypt throws, chat proceeds with no connectors rather than
  // taking byte offline for that founder over one bad credential.
  let mcp: McpConfig = { mcpServers: [], mcpToolsets: [] };
  try {
    const encKey = process.env.CONNECTOR_ENC_KEY;
    if (encKey) mcp = buildMcpConfig(await loadConnectors(auth.uid, encKey));
  } catch (err) {
    logger.warn("connector load failed; continuing without", { uid: auth.uid, err: String(err) });
  }

  const tools: unknown[] = [
    ...(runnable.length ? [RUN_TASK_TOOL] : []),
    NAVIGATE_TOOL,
    ...(envSetup.length ? [SETUP_TOOL] : []),
    REMEMBER_TOOL,
    // Each declared server must be referenced by exactly one toolset, or the
    // request is rejected — `buildMcpConfig` keeps the two lists in step.
    ...mcp.mcpToolsets,
  ];

  const wantsStream = typeof req.headers.accept === "string" && req.headers.accept.includes("text/event-stream");

  if (!wantsStream) {
    // Existing non-streaming JSON path — response shape now additionally supports
    // a real run_task_id (was hardcoded null); already-deployed native app
    // versions that never send `runnable` still get run_task_id: null unchanged.
    try {
      const baseParams = {
        model: CHAT_MODEL,
        max_tokens: 1024,
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
      const { runTaskId, nav, setup, remember } = resolveActions(toolUses, runnable, envSetup);

      // Additive, backward-compatible response shape: run_task_id is always
      // present (existing behavior); nav/setup/remember are only included when
      // the turn actually produced one — old clients that only look for
      // {reply, run_task_id} are unaffected, and unknown fields are ignored.
      const responseBody: Record<string, unknown> = { reply, run_task_id: runTaskId };
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

  try {
    for await (const event of factory({
      client: _streamFactory ? (null as any) : client(),
      systemBlocks,
      messages,
      tools,
      mcpServers: mcp.mcpServers
    })) {
      if (event.type === "text") {
        writeFrame(res, "delta", { text: event.text });
      } else if (event.type === "tool_use_start") {
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
        const { runTaskId, nav, setup, remember } = resolveActions(completedToolUses, runnable, envSetup);
        // run_task_id/nav/setup/remember are additive on the existing done
        // frame — old clients that only look for {model, cache_hit,
        // run_task_id} are unaffected; nav/setup/remember are only included
        // when the turn actually produced one.
        const doneFrame: Record<string, unknown> = { model: CHAT_MODEL, cache_hit: cacheHit, run_task_id: runTaskId };
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
