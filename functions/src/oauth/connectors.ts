// Turning stored connector credentials into the two parameters the Messages API
// needs to let Claude call a provider's hosted MCP server.
//
// The split here is deliberate: `buildMcpConfig` is pure and unit-tested, while
// `loadConnectors` does the Firestore read and the decryption. The pure half is
// where the easy mistake lives — see the note on toolsets below.
import * as admin from "firebase-admin";
import { openToken, type SealedToken } from "./githubOAuthCore";

/** The beta that gates `mcp_servers` on the Messages API. */
export const MCP_CLIENT_BETA = "mcp-client-2025-11-20";

export interface ConnectorRecord {
  /** MCP server name — also the key a toolset references. */
  name: string;
  url: string;
  token: string;
}

export interface McpConfig {
  mcpServers: Array<{ type: "url"; url: string; name: string; authorization_token: string }>;
  /** Appended to the request's existing `tools`, not passed separately. */
  mcpToolsets: Array<{ type: "mcp_toolset"; mcp_server_name: string }>;
}

/**
 * Both halves or neither.
 *
 * `mcp_servers` on its own is a validation error: every declared server must be
 * referenced by exactly one `mcp_toolset` entry in `tools`. Building them in one
 * place is what stops the two lists drifting apart — the failure mode otherwise
 * is a 400 on every chat turn the moment a founder connects something.
 */
export function buildMcpConfig(connectors: ConnectorRecord[]): McpConfig {
  const usable = connectors.filter((c) => c.name && c.url && c.token);
  return {
    mcpServers: usable.map((c) => ({
      type: "url" as const,
      url: c.url,
      name: c.name,
      authorization_token: c.token
    })),
    mcpToolsets: usable.map((c) => ({ type: "mcp_toolset" as const, mcp_server_name: c.name }))
  };
}

interface ConnectorDoc {
  provider?: string;
  mcpUrl?: string;
  sealed?: SealedToken;
}

/**
 * Every connector this founder has authorised, decrypted and ready to send.
 *
 * Fail-open by design: a connector that cannot be read or opened is dropped, and
 * chat continues without it. The alternative — failing the turn — would mean one
 * corrupted credential silently takes byte offline for that founder, which is a
 * far worse outcome than a reply that just doesn't reach GitHub.
 */
export async function loadConnectors(uid: string, encKey: string): Promise<ConnectorRecord[]> {
  const snap = await admin.firestore().collection(`companies/${uid}/connectors`).get();
  const out: ConnectorRecord[] = [];
  for (const doc of snap.docs) {
    const data = doc.data() as ConnectorDoc;
    if (!data.mcpUrl || !data.sealed) continue;
    try {
      out.push({
        name: data.provider ?? doc.id,
        url: data.mcpUrl,
        token: openToken(data.sealed, encKey)
      });
    } catch {
      // A tampered or unreadable blob. Never log the error — it can echo
      // ciphertext — and never fail the turn over it.
      continue;
    }
  }
  return out;
}
