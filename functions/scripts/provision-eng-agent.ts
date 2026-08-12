//
// Run ONCE per environment — by a human, with a real ANTHROPIC_API_KEY, from a
// terminal. Creates the reusable agent and container environment the
// engineering backend runs every session against, then prints the ids to put
// in the function config (see the RUNBOOK for exactly where).
//
//   cd functions
//   ANTHROPIC_API_KEY="$(grep ANTHROPIC_API_KEY local.env | cut -d= -f2-)" npm run provision:eng
//
// This is NOT called from a request path, and must never be wired into one:
// creating an agent per run would accumulate orphaned agents in the console,
// pay agent-create latency on every single run, and throw away the
// versioning that lets a session pin known-good behaviour (`engStartRun`
// pins `agentVersion` precisely so an agent edit mid-run cannot change how a
// session already in flight behaves — see `buildSessionParams` in
// `src/engineering/engStartRun.ts`). An agent and its environment are
// long-lived, hand-provisioned infrastructure, not per-request state.
//
// Re-running this script does not update the existing agent — it creates a
// SECOND agent and a second environment, each with their own id. That is
// deliberate: there is no "the" agent to update in place from here, only ever
// a new one to provision and then cut over to by hand.
import Anthropic from "@anthropic-ai/sdk";
import { ENG_MODEL } from "../src/engineering/engClient";

async function main(): Promise<void> {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error("ANTHROPIC_API_KEY is not set");
    process.exit(1);
  }

  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

  const environment = await client.beta.environments.create({
    name: "codepet-engineering",
    config: {
      type: "cloud",
      // Package managers are the whole job (installing deps, running test
      // runners); MCP is off until some feature actually needs a server.
      networking: { type: "limited", allow_package_managers: true, allow_mcp_servers: false }
    }
  });

  const agent = await client.beta.agents.create({
    name: "Codepet Engineering",
    model: ENG_MODEL,
    system: "You are a coding agent. The founder's per-company brief is supplied per session.",
    tools: [
      {
        type: "agent_toolset_20260401",
        default_config: { enabled: true, permission_policy: { type: "always_allow" } },
        // Only bash asks. Every other tool here (edit/read/write/glob/grep) is
        // reversible inside the throwaway branch each session works on — a
        // bad edit is just another edit, undone by the next one, and never
        // reaches anything outside the sandboxed checkout. Bash is the one
        // tool that can reach OUTSIDE that branch (network calls, deleting
        // files the checkout doesn't own, anything a shell can do), so it is
        // the one worth interrupting a founder for. Asking about every file
        // edit as well would just train them to click Allow without reading
        // — the approval would stop meaning anything by the time bash needed
        // it to.
        configs: [{ name: "bash", permission_policy: { type: "always_ask" } }]
      }
    ]
  });

  console.log(`ENG_ENVIRONMENT_ID=${environment.id}`);
  console.log(`ENG_AGENT_ID=${agent.id}`);
  console.log(`ENG_AGENT_VERSION=${agent.version}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
