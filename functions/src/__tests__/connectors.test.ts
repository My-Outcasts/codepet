import { buildMcpConfig, MCP_CLIENT_BETA } from "../oauth/connectors";

const github = { name: "github", url: "https://api.githubcopilot.com/mcp/", token: "gho_1" };

describe("buildMcpConfig", () => {
  it("returns both halves for one connector", () => {
    const { mcpServers, mcpToolsets } = buildMcpConfig([github]);
    expect(mcpServers).toEqual([
      { type: "url", url: github.url, name: "github", authorization_token: "gho_1" }
    ]);
    expect(mcpToolsets).toEqual([{ type: "mcp_toolset", mcp_server_name: "github" }]);
  });

  // `mcp_servers` without a matching toolset is rejected by the API, so every
  // declared server must be referenced exactly once. This is the invariant the
  // whole module exists to hold — drift here is a 400 on every chat turn.
  it("emits exactly one toolset per declared server, by name", () => {
    const linear = { name: "linear", url: "https://mcp.linear.app/mcp", token: "lin_1" };
    const { mcpServers, mcpToolsets } = buildMcpConfig([github, linear]);
    expect(mcpToolsets).toHaveLength(mcpServers.length);
    expect(mcpToolsets.map((t) => t.mcp_server_name).sort()).toEqual(
      mcpServers.map((s) => s.name).sort()
    );
  });

  it("is empty for a founder with no connectors — the common case stays untouched", () => {
    expect(buildMcpConfig([])).toEqual({ mcpServers: [], mcpToolsets: [] });
  });

  // A half-written record must not produce a server with an empty token: the API
  // would accept it and every call through that server would fail unauthorised.
  it.each([
    [{ name: "", url: github.url, token: "t" }, "no name"],
    [{ name: "github", url: "", token: "t" }, "no url"],
    [{ name: "github", url: github.url, token: "" }, "no token"]
  ])("drops an incomplete record (%s)", (record) => {
    expect(buildMcpConfig([record]).mcpServers).toHaveLength(0);
    expect(buildMcpConfig([record]).mcpToolsets).toHaveLength(0);
  });

  it("keeps the good connector when a sibling is incomplete", () => {
    const { mcpServers } = buildMcpConfig([github, { name: "linear", url: "", token: "x" }]);
    expect(mcpServers.map((s) => s.name)).toEqual(["github"]);
  });

  it("pins the beta that gates mcp_servers", () => {
    expect(MCP_CLIENT_BETA).toBe("mcp-client-2025-11-20");
  });
});
