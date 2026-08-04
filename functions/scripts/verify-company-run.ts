/**
 * Staging verification for the Virtual Company backend. NOT part of the test
 * suite — it needs a real API key and makes real calls.
 *
 *   cd functions && ANTHROPIC_API_KEY=sk-... npm run verify:company
 *
 * Proves the three things unit tests with fakes cannot:
 *   1. The shared prefix is REUSABLE — two sequential calls with the same tool
 *      read the same cache entry. Measured with an explicit probe rather than
 *      asserted over the run: within a run there is no reuse to observe, because
 *      the tool definition precedes system in the cache prefix (so each phase
 *      writes its own entry) and phases 2 and 4 dispatch their agents
 *      concurrently (so no agent can read what its siblings are still writing).
 *      Asserting cache_read > 0 across the run could never pass.
 *   2. A real model reliably calls the forced tool and returns a position that
 *      parses against the schema.
 *   3. The end-to-end phase chain produces a usable brief, and prints the real
 *      per-run cost so the team has a measured number rather than an estimate.
 */
import Anthropic from "@anthropic-ai/sdk";
import { AGENT_MODEL, MODEL_PRICING, ROUTER_MODEL, SYNTHESIS_MODEL } from "../src/anthropic";
import { buildSharedPrefix, estimateTokens } from "../src/company/preamble";
import { AgentCaller, runIntake } from "../src/company/router";
import { runIndependentPass } from "../src/company/independentPass";
import { detectConflicts, needsNegotiation } from "../src/company/conflicts";
import { runNegotiation } from "../src/company/negotiation";
import { runDevilsAdvocate, shouldInvokeDevilsAdvocate } from "../src/company/devilsAdvocate";
import { runSynthesis } from "../src/company/synthesis";
import { AgentId, AgentPosition, FounderContext, TokenUsage } from "../src/company/types";

const founder: FounderContext = {
  profile:
    "Solo founder, technical, previously a backend engineer at a mid-size fintech. " +
    "Shipped one product before that reached 200 paying users then plateaued. " +
    "No design or sales background.",
  stage:
    "Pre-revenue, 4 months of runway, product in closed beta with 30 users, no " +
    "pricing page yet.",
  constraints: [
    "Cannot hire — no budget for headcount this quarter.",
    "Must ship to the App Store before the end of next month.",
    "Refuses to take outside investment at this stage."
  ],
  language: "en"
};

const rawRequest =
  "Should I build a team-collaboration feature so companies can buy seats, or " +
  "should I first put a price on the single-player product I already have?";

let totalCost = 0;
const callLog: Array<{ agent: string; model: string; usage: TokenUsage }> = [];

function fail(message: string): never {
  console.error(`\nFAIL: ${message}`);
  process.exit(1);
}

/**
 * Cache writes are billed at 1.25x the input rate, and this run writes one on
 * nearly every call, so leaving them out understated the real per-run cost.
 */
function priceOf(model: string, usage: TokenUsage, cacheWrite = 0): number {
  const p = MODEL_PRICING[model];
  if (!p) return 0;
  return (
    (usage.input * p.inputPerMTok +
      usage.output * p.outputPerMTok +
      usage.cache_read * p.inputPerMTok * 0.1 +
      cacheWrite * p.inputPerMTok * 1.25) /
    1_000_000
  );
}

function makeCaller(client: Anthropic): AgentCaller {
  return async (args) => {
    const response = await client.messages.create({
      model: args.model,
      max_tokens: args.maxTokens ?? 2000,
      system: args.system as any,
      tools: [args.tool as any],
      tool_choice: { type: "tool", name: args.toolName },
      messages: [{ role: "user", content: args.userMessage }]
    });

    const usage: TokenUsage = {
      input: response.usage?.input_tokens ?? 0,
      output: response.usage?.output_tokens ?? 0,
      cache_read: (response.usage as any)?.cache_read_input_tokens ?? 0
    };
    const cacheWrite = (response.usage as any)?.cache_creation_input_tokens ?? 0;
    totalCost += priceOf(args.model, usage, cacheWrite);
    callLog.push({ agent: args.agent, model: args.model, usage });

    console.log(
      `  ${args.agent.padEnd(16)} ${args.model.padEnd(18)} ` +
        `in=${String(usage.input).padStart(6)} out=${String(usage.output).padStart(5)} ` +
        `cache_write=${String(cacheWrite).padStart(5)} cache_read=${String(usage.cache_read).padStart(5)}`
    );

    for (const block of response.content) {
      if (block.type === "tool_use" && block.name === args.toolName) {
        return { input: block.input, usage, stopReason: response.stop_reason };
      }
    }
    fail(`${args.agent} did not call ${args.toolName} — forced tool_choice was ignored`);
  };
}

async function main(): Promise<void> {
  if (!process.env.ANTHROPIC_API_KEY) {
    fail("ANTHROPIC_API_KEY is not set");
  }

  // ── 1. Static check: does the shared prefix clear the cache floor? ──
  const prefix = buildSharedPrefix({ founder, rawRequest });
  const floor = MODEL_PRICING[AGENT_MODEL].cacheMinTokens;
  console.log(
    `shared prefix: ${prefix.length} chars, ~${estimateTokens(prefix)} est tokens ` +
      `(floor for ${AGENT_MODEL}: ${floor})`
  );
  if (estimateTokens(prefix) < floor) {
    fail("prefix is below the cache floor — caching will silently no-op");
  }

  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  const call = makeCaller(client);

  // ── 1b. Is the shared prefix actually reusable? ──
  // Two sequential calls, same tool, different agents. The second must read what
  // the first wrote; if it does not, block 0 is not byte-identical across agents
  // (usually a role prompt leaking into it) and caching would silently no-op
  // everywhere. Runs before the phase chain so a broken prefix fails cheaply.
  console.log(`\nCACHE REUSE PROBE (${AGENT_MODEL})`);
  await runIndependentPass({ founder, rawRequest, realQuestion: rawRequest, agents: ["product"], call });
  const probe = await runIndependentPass({
    founder,
    rawRequest,
    realQuestion: rawRequest,
    agents: ["finance"],
    call
  });
  const probeRead = probe.results[0]?.usage.cache_read ?? 0;
  if (probeRead === 0) {
    fail(
      "the second sequential call read nothing from cache — the shared prefix is " +
        "not byte-identical across agents, or it fell below the model's cache " +
        "minimum. Check that no role prompt leaked into block 0 of composeAgentSystem."
    );
  }
  console.log(`  reused ${probeRead} cached input tokens on the second call`);

  // ── 2. Phase 1: intake ──
  console.log(`\nPHASE 1 — intake (${ROUTER_MODEL})`);
  const intake = await runIntake({ founder, rawRequest, call });
  console.log(`  decision: ${intake.routing.decision}`);
  console.log(`  real question: ${intake.routing.real_question}`);
  console.log(`  agents: ${intake.routing.agents.join(", ") || "(none)"}`);

  if (intake.routing.decision !== "multi_agent") {
    // Not a failure — the escape hatch working is a good outcome. But this
    // script needs a multi_agent run to verify caching across agents, so say so
    // plainly rather than reporting a false PASS.
    console.log(
      `\nINCONCLUSIVE: the router chose ${intake.routing.decision} for this request, ` +
        `so phases 2-5 were skipped and cross-agent caching could not be checked. ` +
        `The escape hatch working is correct behaviour; re-run with a request that ` +
        `genuinely pits product against finance to verify caching.`
    );
    process.exit(2);
  }

  // ── 3. Phase 2: independent pass ──
  const departmentAgents = intake.routing.agents.filter((a) => a !== "devils_advocate");
  console.log(`\nPHASE 2 — independent pass (${departmentAgents.join(", ")})`);
  const pass = await runIndependentPass({
    founder,
    rawRequest,
    realQuestion: intake.routing.real_question,
    agents: departmentAgents,
    call
  });

  const positions: Partial<Record<AgentId, AgentPosition>> = {};
  for (const r of pass.results) {
    if (!r.position) fail(`${r.agent} returned no usable position: ${r.error}`);
    positions[r.agent] = r.position;
    console.log(
      `  ${r.agent}: stance=${r.position.stance} confidence=${r.position.confidence}/5 ` +
        `blocker=${r.position.hard_blocker ?? "none"}`
    );
  }

  // Phase 2 runs its agents concurrently, so the cache entry may not be readable
  // yet for the second agent — the entry only becomes readable once the first
  // response starts streaming. Later phases reuse the same prefix sequentially,
  // which is where the cache read must show up.

  // ── 4. Phase 3: conflict detection ──
  const conflicts = detectConflicts(positions);
  console.log(`\nPHASE 3 — conflict detection (pure code, no model call)`);
  for (const c of conflicts) {
    console.log(`  ${c.a} vs ${c.b}: ${c.kind} — ${c.reason}`);
  }

  // ── 5. Phase 4: negotiation ──
  let unresolved = false;
  if (needsNegotiation(conflicts)) {
    console.log(`\nPHASE 4 — negotiation`);
    const negotiation = await runNegotiation({
      founder,
      rawRequest,
      realQuestion: intake.routing.real_question,
      positions,
      conflicts,
      call
    });
    unresolved = negotiation.unresolved;
    console.log(`  rounds: ${negotiation.rounds.length}, unresolved: ${unresolved}`);
  } else {
    console.log(`\nPHASE 4 — skipped (nothing to debate)`);
  }

  // ── 6. Phase 4b: red team ──
  let redTeam = null;
  if (shouldInvokeDevilsAdvocate({ positions, conflicts })) {
    console.log(`\nPHASE 4b — red team (${SYNTHESIS_MODEL})`);
    const rt = await runDevilsAdvocate({
      founder,
      rawRequest,
      realQuestion: intake.routing.real_question,
      positions,
      call
    });
    redTeam = rt.verdict;
    console.log(`  plan judged sound: ${rt.verdict.plan_is_sound}`);
    console.log(`  load-bearing assumption: ${rt.verdict.load_bearing_assumption}`);
  } else {
    console.log(`\nPHASE 4b — red team not triggered`);
  }

  // ── 7. Phase 5: synthesis ──
  console.log(`\nPHASE 5 — synthesis (${SYNTHESIS_MODEL})`);
  const synthesis = await runSynthesis({
    founder,
    rawRequest,
    realQuestion: intake.routing.real_question,
    positions,
    conflicts,
    negotiation: [],
    devilsAdvocate: redTeam,
    unresolved,
    call
  });
  console.log(`  recommendation: ${synthesis.brief.recommendation}`);
  console.log(`  the real disagreement: ${synthesis.brief.the_real_disagreement}`);
  console.log(`  trade-off: ${synthesis.brief.tradeoff_founder_must_own}`);
  console.log(`  unresolved: ${synthesis.brief.unresolved}`);

  // ── 8. Verdict ──
  console.log(`\n─── summary ───`);
  console.log(`model calls: ${callLog.length}`);
  console.log(`measured cost: $${totalCost.toFixed(4)}`);

  // Informational, not a gate. Whatever appears here is an artefact of the probe
  // above having warmed the position-tool prefix — phase 2 then reads it. Without
  // the probe this is 0, so a low number is not a regression; the probe is the
  // health check.
  const cacheReadTotal = callLog.reduce((s, c) => s + c.usage.cache_read, 0);
  console.log(`cache-read tokens inside the phase chain: ${cacheReadTotal} (probe-warmed)`);
  console.log(`\nPASS: prefix is reusable, every agent called its tool, brief is usable.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
