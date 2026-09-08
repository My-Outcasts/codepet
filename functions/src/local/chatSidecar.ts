#!/usr/bin/env node
/**
 * Runs one companyChat turn on the founder's OWN Claude Code, and emits the same SSE
 * frames the Cloud Function does — so the app's existing `SSEParser` reads it unchanged.
 *
 * Reads the request body (the same JSON the CF takes) on stdin, writes `event: delta` /
 * `event: done` / `event: error` frames on stdout.
 *
 * WHAT IT DOES NOT DO, and why that is the point:
 *   - No auth. There is nobody to authenticate to; the founder already owns this machine.
 *   - No rate limit. The ceiling is their Claude plan, not our Firestore counter.
 *   - No Anthropic client, and no API key anywhere in the process.
 *   - No connectors. Those need Firestore and a uid, so `extraToolsets` is always empty.
 *
 * Prompts are NOT re-implemented here. `buildChatRequest` is the single builder both this
 * and the HTTP handler call, which is the whole reason it was extracted — two copies of an
 * assembly order is how prompts drift.
 */

import { spawn } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import {
  buildChatRequest,
  resolveActions,
  type ChatRequestBody,
} from "../companyChatCore";
import { flattenTranscript } from "./transcript";

// Re-exported under the name this module's tests and its own history use.
export { flattenTranscript as renderForPrompt } from "./transcript";
import { toMcpTools, allowedToolNames, serveMcp } from "./mcpToolServer";

/**
 * The flag that turns this same file into the MCP tool server.
 *
 * One file, not two, because of PACKAGING: Xcode's synchronized resource group FLATTENS
 * whatever it bundles, so a compiled sibling loses its path and `require("../…")` loses
 * its target. A single self-contained file that re-invokes itself is the only shape that
 * survives being dropped into `Contents/Resources/`.
 */
const MCP_SERVER_FLAG = "--mcp-server";

/**
 * The extension Read needs to recognise a saved attachment. Keyed by the media types
 * `mediaBlock` in `companyChatCore` is allowed to emit — anything else has no entry, so
 * `saveAttachment` declines it and the block falls back to being named. `image/jpeg` maps
 * to `.jpg` for the same reason the client maps `.jpg` to `image/jpeg`: the pair has two
 * spellings and only one of them is right.
 */
const ATTACHMENT_EXTENSIONS: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
  "application/pdf": "pdf",
};

function frame(event: string, payload: unknown): void {
  process.stdout.write(`event: ${event}\ndata: ${JSON.stringify(payload)}\n\n`);
}

/**
 * The flags one turn runs under. Every one of these was settled by measurement on
 * 2.1.241, and each is load-bearing:
 *
 * - `--mcp-config` + `--strict-mcp-config` TOGETHER. Strict alone excludes everything,
 *   this server included; it means "only what --mcp-config names".
 * - `--setting-sources ""` keeps the founder's settings out, and therefore their HOOKS.
 *   Without it their `SessionStart` hook fired and injected its own content into the turn.
 * - NOT `--safe-mode`. It would isolate more, but it disables MCP servers — measured, the
 *   init frame comes back with `mcp_servers: []` — so the run cannot reach these tools.
 * - `--tools` restricted to WebSearch (or nothing). This is a SAFETY property, not tidiness:
 *   chat has no business holding Bash, Edit or Write, and restricting it also removed the
 *   `ToolSearch` round-trip that deferred loading adds when many tools are present.
 * - `--allowedTools` last, because it is variadic. It also has to be there at all: without
 *   it the model emits the tool_use and the call is denied, so the founder gets an
 *   apology instead of an answer.
 * - **`WebSearch` goes in `--allowedTools` too, not just `--tools`.** The rule on the line
 *   above applies to it and was not applied: `--tools` makes a built-in AVAILABLE, while
 *   `--allowedTools` is what PERMITS it, so `--tools WebSearch` alongside an allow-list of
 *   only `mcp__codepet__*` names produced exactly the failure described — the model called
 *   the tool, the call was denied, and the founder got an apology. Reported 7 Sep: the
 *   toolkit toggle read "Web research — Enabled" and every search still came back
 *   "permissions not granted", because the toggle drives `enabled_skills` for the Cloud
 *   Function and never reached this list. Added HERE rather than at the call site so the
 *   two flags cannot drift apart again: enabling the tool is what permits it.
 * - **`Read` + `--restricted`, and only for a turn that carries a file.** `claude -p` cannot
 *   take an image block, so an attachment is written into the run directory and read from
 *   there. `--restricted` is what makes granting Read acceptable: it confines the file
 *   tools to the working directory, which is that same per-turn temp dir, holding nothing
 *   but `tools.json`, `mcp.json` and the files this process just wrote. Read WITHOUT it is
 *   filesystem-wide — the founder's repos, keys and Documents — which is the safety
 *   property two bullets up. Measured: `--restricted` leaves `mcp_servers: [codepet
 *   connected]` and the tool list intact, so it costs the turn nothing; and a Read one
 *   directory above cwd is refused. Both flags are off for a turn with no attachment, so
 *   ordinary flags are byte-identical to what they were.
 * - Prompt on stdin, never as an argument — the variadic flag above would swallow it.
 */
export function claudeArgs(opts: {
  mcpConfigPath: string;
  allowed: string[];
  model?: string;
  effort?: string;
  webSearch: boolean;
  systemPrompt: string;
  /** True only for a turn that actually wrote a file into the run dir — see `--restricted`. */
  readAttachments?: boolean;
}): string[] {
  // See the `WebSearch` note above: available and permitted are two different flags, and
  // the tool is useless with only the first. Read is subject to exactly the same rule.
  const allowedWithBuiltins = [
    ...opts.allowed,
    ...(opts.webSearch ? ["WebSearch"] : []),
    ...(opts.readAttachments ? ["Read"] : []),
  ];
  // "" when neither is on, which the CLI accepts as "no built-ins".
  const tools = [opts.webSearch ? "WebSearch" : null, opts.readAttachments ? "Read" : null]
    .filter(Boolean)
    .join(",");
  return [
    "-p",
    // REPLACE, not append. Claude Code's own system prompt is a coding assistant's; byte's
    // is complete on its own and the two fight each other for persona and format. This is
    // where both of buildChatRequest's system blocks land, in their built order.
    "--system-prompt", opts.systemPrompt,
    "--mcp-config", opts.mcpConfigPath,
    "--strict-mcp-config",
    "--setting-sources", "",
    "--output-format", "stream-json",
    "--verbose",
    "--include-partial-messages",
    // Empty string when off, which the CLI accepts as "no built-ins" — the restriction is
    // the safety property described above.
    "--tools", tools,
    // Never granted without this: see the `Read` note above.
    ...(opts.readAttachments ? ["--restricted"] : []),
    ...(opts.model ? ["--model", opts.model] : []),
    // Verified on 2.1.241 that --effort is accepted alongside every model Codepet offers,
    // Haiku 4.5 included: the API rejects `effort` on some models but the CLI absorbs that
    // rather than passing the error through.
    ...(opts.effort ? ["--effort", opts.effort] : []),
    ...(allowedWithBuiltins.length ? ["--allowedTools", ...allowedWithBuiltins] : []),
  ];
}

/** The user-facing text of a turn, and every tool it called, read out of stream-json. */
export interface TurnResult {
  text: string;
  toolUses: Array<{ name: string; input: unknown }>;
  model: string | null;
  /**
   * Which stream block the last text came from. Bookkeeping for the paragraph break in
   * `ingestLine`, not part of the answer — optional so every existing constructor and test
   * fixture stays valid.
   */
  lastTextBlock?: number;
}

/**
 * Translate one line of `claude -p --output-format stream-json` into what a caller needs.
 *
 * `onDelta` fires for streamed text so the founder sees it arrive. Tool calls are
 * collected rather than streamed: `resolveActions` validates them against the runnable /
 * open-task / setup lists as a SET at the end of the turn, and a half-built call cannot be
 * validated against anything.
 *
 * MCP tool names arrive namespaced (`mcp__codepet__navigate`); the validators expect the
 * bare name, so the prefix is stripped here — the one place it can be, since everything
 * downstream is shared with the HTTP path.
 */
export function ingestLine(
  line: string,
  acc: TurnResult,
  onDelta: (text: string) => void,
  serverName = "codepet"
): void {
  let o: any;
  try {
    o = JSON.parse(line);
  } catch {
    return; // Not every line is JSON; a non-JSON line is not an error worth surfacing.
  }

  if (o.type === "system" && o.subtype === "init" && typeof o.model === "string") {
    acc.model = o.model;
    return;
  }

  // Partial text, enabled by --include-partial-messages. This is what makes the reply
  // stream instead of landing in one block after a long silence.
  if (o.type === "stream_event") {
    const ev = o.event;
    if (ev?.type === "content_block_delta" && ev.delta?.type === "text_delta") {
      const t = ev.delta.text ?? "";
      if (t) {
        // **A NEW text block is a new paragraph, not a continuation.** Text arrives as
        // deltas that were simply concatenated, so when a turn emits text, then a tool
        // call, then more text, the two blocks ran together with no separator at all:
        // "…rather than recite from memory.Web research is queued to switch on" and
        // "…going to pull real pages.Still blocked on my end" (founder screenshots,
        // 7 Sep). Every such sentence pair is one denied tool call away from happening,
        // so it shows up exactly when something has gone wrong — the worst time to look
        // broken.
        //
        // Keyed on the block INDEX the delta carries, not on `content_block_start`:
        // deltas always carry `index`, and relying on a second event type would make
        // this depend on the CLI continuing to emit it. An index we cannot read falls
        // through to the old behaviour rather than guessing.
        const idx = typeof ev.index === "number" ? ev.index : undefined;
        if (
          idx !== undefined &&
          acc.lastTextBlock !== undefined &&
          idx !== acc.lastTextBlock &&
          acc.text &&
          !/\s$/.test(acc.text)
        ) {
          acc.text += "\n\n";
          onDelta("\n\n");
        }
        if (idx !== undefined) acc.lastTextBlock = idx;
        acc.text += t;
        onDelta(t);
      }
    }
    return;
  }

  if (o.type === "assistant") {
    for (const c of o.message?.content ?? []) {
      if (c.type === "tool_use" && typeof c.name === "string") {
        const prefix = `mcp__${serverName}__`;
        acc.toolUses.push({
          name: c.name.startsWith(prefix) ? c.name.slice(prefix.length) : c.name,
          input: c.input,
        });
      }
    }
    return;
  }

  // `result` repeats the final text. Only trusted when partial streaming gave us nothing,
  // so a run without deltas still produces a reply rather than an empty turn.
  if (o.type === "result" && !acc.text && typeof o.result === "string") {
    acc.text = o.result;
    onDelta(o.result);
  }
}


/* istanbul ignore next -- process wiring; the pure parts above carry the tests */
async function main(): Promise<void> {
  const raw = await new Promise<string>((resolve) => {
    let s = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c: string) => (s += c));
    process.stdin.on("end", () => resolve(s));
  });

  let body: ChatRequestBody;
  try {
    body = JSON.parse(raw) as ChatRequestBody;
  } catch (err) {
    frame("error", { error: "invalid_payload", detail: String(err) });
    return;
  }

  // The one builder, shared with the HTTP handler. No connector toolsets: this process
  // has no Firestore and no uid to load them for.
  const built = buildChatRequest(body);
  const mcpTools = toMcpTools(built.tools);
  const allowed = allowedToolNames(mcpTools);
  // web_search never reaches MCP (it has no schema, so `toMcpTools` drops it). Its
  // presence in the built list is how we know the founder turned the skill on.
  const webSearch = built.tools.some(
    (t) => typeof (t as any)?.type === "string" && (t as any).type.startsWith("web_search")
  );

  // A run directory the founder's CLAUDE.md cannot be discovered from: discovery walks UP
  // from cwd, so a temp dir keeps their repo instructions out of Codepet's turn.
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "codepet-chat-"));
  const toolsPath = path.join(dir, "tools.json");
  const mcpConfigPath = path.join(dir, "mcp.json");
  fs.writeFileSync(toolsPath, JSON.stringify(built.tools));
  fs.writeFileSync(
    mcpConfigPath,
    JSON.stringify({
      // `__filename` — this very file, re-invoked in server mode.
      mcpServers: {
        codepet: { command: process.execPath, args: [__filename, MCP_SERVER_FLAG, toolsPath] },
      },
    })
  );

  const acc: TurnResult = { text: "", toolUses: [], model: null };

  // Every media block this turn carries, written into the run dir so Claude Code can open
  // it. Named by position rather than by the founder's filename: `buildMessages` keeps only
  // what the API needs on a content block, so the filename is not here to use — and a
  // counter that never rewinds keeps the five screenshots of one turn apart.
  let saved = 0;
  const saveAttachment = (block: unknown): string | null => {
    const b = block as { source?: { data?: unknown; media_type?: unknown } };
    const data = b?.source?.data;
    const mediaType = typeof b?.source?.media_type === "string" ? b.source.media_type : "";
    const ext = ATTACHMENT_EXTENSIONS[mediaType];
    if (typeof data !== "string" || !data || !ext) return null;
    const name = `attachment-${++saved}.${ext}`;
    try {
      fs.writeFileSync(path.join(dir, name), Buffer.from(data, "base64"));
    } catch {
      return null; // the number stays spent, so the next name is still unique
    }
    return name;
  };

  // Rendered BEFORE the flags, because whether anything was written is what decides
  // `readAttachments` — and therefore whether this turn is granted Read at all.
  const prompt = flattenTranscript(built.messages, saveAttachment);

  const args = claudeArgs({
    mcpConfigPath,
    allowed,
    model: process.env.CODEPET_CHAT_MODEL,
    effort: process.env.CODEPET_CHAT_EFFORT,
    webSearch,
    systemPrompt: built.systemBlocks.map((b) => b.text).join("\n\n"),
    readAttachments: saved > 0,
  });

  // A login shell so the founder's PATH resolves, and the two credential variables
  // stripped: precedence puts them ABOVE the subscription, and under -p a present key is
  // always used — so an exported key would bill their API account for work this whole
  // design exists to put on the plan they already pay for.
  const env = { ...process.env };
  delete env.ANTHROPIC_API_KEY;
  delete env.ANTHROPIC_AUTH_TOKEN;

  const quoted = args.map((a) => `'${a.replace(/'/g, "'\\''")}'`).join(" ");
  const child = spawn("/bin/zsh", ["-lc", `claude ${quoted}`], { cwd: dir, env });

  // The turn's prompt goes on stdin, never as an argument: `--allowedTools` above is
  // variadic and would swallow it. `renderForPrompt` is what carries the history, since
  // `claude -p` takes one prompt rather than a messages array.
  child.stdin.write(prompt);
  child.stdin.end();

  let buf = "";
  child.stdout.setEncoding("utf8");
  child.stdout.on("data", (chunk: string) => {
    buf += chunk;
    let nl: number;
    while ((nl = buf.indexOf("\n")) !== -1) {
      const line = buf.slice(0, nl);
      buf = buf.slice(nl + 1);
      ingestLine(line, acc, (t) => frame("delta", { text: t }));
    }
  });

  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (c: string) => (stderr += c));

  child.on("close", (code) => {
    if (buf.trim()) ingestLine(buf, acc, (t) => frame("delta", { text: t }));

    if (code !== 0 && !acc.text && !acc.toolUses.length) {
      frame("error", { error: "upstream_failure", detail: stderr.trim() || `claude exited ${code}` });
      cleanup();
      return;
    }

    // Same resolver the HTTP path uses, against the same lists the prompt was built from.
    const { runTaskId, nav, setup, remember, completeTaskId, addTask, drafts } =
      resolveActions(acc.toolUses, built.runnable, built.envSetup, built.openTasks);

    // Same additive frame shape as the CF. `cache_hit` is reported false rather than
    // omitted or guessed: prompt caching is not reachable through the CLI, so claiming a
    // hit would be an invention and omitting the field would break older readers.
    const done: Record<string, unknown> = {
      model: acc.model ?? "claude-code-local",
      cache_hit: false,
      run_task_id: runTaskId,
    };
    if (completeTaskId) done.complete_task_id = completeTaskId;
    if (addTask) done.add_task = addTask;
    if (drafts) done.drafts = drafts;
    if (nav) done.nav = nav;
    if (setup) done.setup = setup;
    if (remember.length) done.remember = remember;
    frame("done", done);
    cleanup();
  });

  function cleanup(): void {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch { /* best effort */ }
  }
}

if (require.main === module) {
  const flagAt = process.argv.indexOf(MCP_SERVER_FLAG);
  if (flagAt !== -1) {
    // Server mode: `claude` spawned us to serve tools, not to run a turn.
    serveMcp(process.argv[flagAt + 1]);
  } else {
    main().catch((err) => frame("error", { error: "sidecar_failure", detail: String(err) }));
  }
}
