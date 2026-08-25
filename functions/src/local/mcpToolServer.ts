#!/usr/bin/env node
/**
 * MCP stdio server that serves Codepet's chat tools to a local `claude -p` run.
 *
 * WHY THIS EXISTS. `claude -p --json-schema` forces exactly one structured output, and
 * `companyChat` needs the opposite: eight optional tools that `companyChat.ts` records as
 * deliberately NOT forced, so byte stays free to reply in plain text or ask a clarifying
 * question. Only real tool use expresses that, and MCP is how a local `claude` is handed
 * tools it did not ship with.
 *
 * WHY HAND-ROLLED. JSON-RPC over newline-delimited stdio, answering three methods. The
 * alternative is `@modelcontextprotocol/sdk`, but this file lives under `functions/`,
 * which is the ONLY deploy source (landmine 1) — a dependency added here ships to Cloud
 * Functions to do nothing. Eighty lines beats that.
 *
 * WHAT THESE TOOLS DO: nothing. They are not actions, they are signals back to the app —
 * navigate here, remember this, run that task. The app learns what was called by reading
 * `tool_use` blocks out of the run's `stream-json`, not from this process. So a call is
 * acknowledged and dropped. The acknowledgement still matters: without a result the model
 * stalls or apologises, and that lands in the founder's transcript.
 *
 * Usage: node mcpToolServer.js <path-to-tools.json>
 * where tools.json is an array of Anthropic-shaped tool definitions
 * (`{name, description, input_schema}`) — exactly what `buildChatRequest` returns.
 */

import * as fs from "fs";

/** Anthropic names it `input_schema`; MCP names it `inputSchema`. */
interface AnthropicTool {
  name?: string;
  description?: string;
  input_schema?: unknown;
}

interface McpTool {
  name: string;
  description: string;
  inputSchema: unknown;
}

/**
 * Keep only what MCP can serve, and rename the schema field.
 *
 * Two kinds of entry are dropped, both on purpose:
 * - `web_search` is an Anthropic SERVER tool — a bare `{type, name}` with no schema,
 *   run by Anthropic rather than by anyone here. The local path reaches web search
 *   through Claude Code's own built-in instead (`--tools WebSearch`).
 * - `mcp_toolset` entries reference connector servers the HTTP path loads from Firestore.
 *   The sidecar has neither Firestore nor the founder's uid, so it never passes any.
 */
export function toMcpTools(tools: unknown[]): McpTool[] {
  const out: McpTool[] = [];
  for (const raw of tools) {
    const t = (raw ?? {}) as AnthropicTool;
    if (!t.name || !t.input_schema) continue;
    out.push({ name: t.name, description: t.description ?? "", inputSchema: t.input_schema });
  }
  return out;
}

/** The `--allowedTools` names for a tool list. Claude Code namespaces MCP tools. */
export function allowedToolNames(tools: McpTool[], serverName = "codepet"): string[] {
  return tools.map((t) => `mcp__${serverName}__${t.name}`);
}

function send(msg: unknown): void {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

export function handleRpc(req: any, tools: McpTool[]): void {
  const { id, method, params } = req ?? {};
  // A notification carries no id and must get no reply — answering one is a protocol
  // error, not a harmless extra.
  if (id === undefined || id === null) return;

  switch (method) {
    case "initialize":
      return send({
        jsonrpc: "2.0",
        id,
        result: {
          // Echo the client's version rather than pinning one we guessed at. If Claude
          // Code moves to a newer protocol, this keeps working instead of negotiating
          // down to something it no longer speaks.
          protocolVersion: params?.protocolVersion ?? "2025-06-18",
          capabilities: { tools: {} },
          serverInfo: { name: "codepet", version: "1.0.0" },
        },
      });

    case "tools/list":
      return send({ jsonrpc: "2.0", id, result: { tools } });

    case "tools/call":
      // Acknowledged, not performed. The app reads the call from stream-json; this reply
      // exists only so the model's turn can finish cleanly.
      return send({
        jsonrpc: "2.0",
        id,
        result: {
          content: [
            {
              type: "text",
              text: "Recorded. Confirm it to the founder in one short sentence.",
            },
          ],
        },
      });

    default:
      return send({
        jsonrpc: "2.0",
        id,
        error: { code: -32601, message: `unknown method: ${method}` },
      });
  }
}

/* istanbul ignore next -- process wiring, exercised by the sidecar's own run */
function main(): void {
  const toolsPath = process.argv[2];
  if (!toolsPath) {
    process.stderr.write("mcpToolServer: missing tools.json path\n");
    process.exit(2);
  }
  const tools = toMcpTools(JSON.parse(fs.readFileSync(toolsPath, "utf8")));

  let buf = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk: string) => {
    buf += chunk;
    let nl: number;
    while ((nl = buf.indexOf("\n")) !== -1) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line) continue;
      try {
        handleRpc(JSON.parse(line), tools);
      } catch (err) {
        // A malformed line must not take the server down mid-conversation: the model
        // would see the tool vanish and start apologising to the founder.
        process.stderr.write(`mcpToolServer: ${String(err)}\n`);
      }
    }
  });
}

if (require.main === module) main();
