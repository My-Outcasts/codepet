/**
 * Interactive feel-test for the Virtual Company. Ask it a real decision and read
 * what the room actually says. Prints every phase in full — this is the
 * exploratory counterpart to verify-company-run.ts, which is a strict pass/fail
 * check on a fixed fixture.
 *
 *   cd functions
 *   ANTHROPIC_API_KEY=sk-... npm run try:company -- "Should I raise prices or ship the team feature first?"
 *
 * Optional founder context (otherwise a generic solo-founder profile is used —
 * the output is much sharper with your real numbers in it):
 *
 *   ANTHROPIC_API_KEY=sk-... npm run try:company -- --founder ./my-founder.json "Your question"
 *
 * my-founder.json:
 *   { "profile": "...", "stage": "...", "constraints": ["...", "..."] }
 *
 * Add --stress to force the red team even when the departments already disagree.
 */
import * as fs from "fs";
import Anthropic from "@anthropic-ai/sdk";
import { MODEL_PRICING } from "../src/anthropic";
import { AgentCaller, runIntake } from "../src/company/router";
import { runIndependentPass } from "../src/company/independentPass";
import { detectConflicts, needsNegotiation } from "../src/company/conflicts";
import { runNegotiation } from "../src/company/negotiation";
import { runDevilsAdvocate, shouldInvokeDevilsAdvocate } from "../src/company/devilsAdvocate";
import { runSynthesis } from "../src/company/synthesis";
import {
  AgentId,
  AgentPosition,
  DevilsAdvocateVerdict,
  FounderContext,
  TokenUsage
} from "../src/company/types";

const DEFAULT_FOUNDER: FounderContext = {
  profile:
    "Solo founder, technical. Comfortable building the product alone; no design " +
    "or sales background. Has shipped before but never priced anything.",
  stage:
    "Pre-revenue, roughly 4 months of runway, product in closed beta with a few " +
    "dozen users, no pricing page yet.",
  constraints: [
    "Cannot hire this quarter — no headcount budget.",
    "Wants to keep shipping weekly rather than stopping to plan."
  ],
  language: "en"
};

// ── args ──────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
let founderPath: string | null = null;
let stress = false;
const words: string[] = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--founder") founderPath = argv[++i] ?? null;
  else if (argv[i] === "--stress") stress = true;
  else words.push(argv[i]);
}
const question = words.join(" ").trim();

if (!process.env.ANTHROPIC_API_KEY) {
  console.error("ANTHROPIC_API_KEY is not set.");
  process.exit(1);
}
if (!question) {
  console.error(
    'Give it a decision to chew on, e.g.\n  npm run try:company -- "Should I raise prices or ship the team feature first?"'
  );
  process.exit(1);
}

let founder = DEFAULT_FOUNDER;
if (founderPath) {
  const raw = JSON.parse(fs.readFileSync(founderPath, "utf8"));
  founder = { ...DEFAULT_FOUNDER, ...raw, language: raw.language ?? "en" };
} else {
  console.log(
    "note: using a generic founder profile. Pass --founder ./my-founder.json with your\n" +
      "      real runway, stage and constraints — the positions get much more concrete.\n"
  );
}

// ── plumbing ──────────────────────────────────────────────────────────────────
let cost = 0;
let calls = 0;
let cacheRead = 0;

// Cache writes bill at 1.25x input and happen on nearly every call, so they are
// counted here — leaving them out understated what a run actually cost.
function priceOf(model: string, u: TokenUsage, cacheWrite = 0): number {
  const p = MODEL_PRICING[model];
  if (!p) return 0;
  return (
    (u.input * p.inputPerMTok +
      u.output * p.outputPerMTok +
      u.cache_read * p.inputPerMTok * 0.1 +
      cacheWrite * p.inputPerMTok * 1.25) /
    1_000_000
  );
}

const rule = (label: string) =>
  console.log(`\n${"═".repeat(76)}\n${label}\n${"═".repeat(76)}`);

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
    calls++;
    cost += priceOf(args.model, usage, (response.usage as any)?.cache_creation_input_tokens ?? 0);
    cacheRead += usage.cache_read;
    for (const b of response.content) {
      if (b.type === "tool_use" && b.name === args.toolName) return { input: b.input, usage, stopReason: response.stop_reason };
    }
    throw new Error(`${args.agent} did not call ${args.toolName}`);
  };
}

function showPosition(agent: AgentId, p: AgentPosition): void {
  console.log(`\n── ${agent.toUpperCase()} ── stance: ${p.stance} · confidence ${p.confidence}/5`);
  console.log(`   ${p.position}`);
  console.log(`   Why: ${p.reasoning}`);
  console.log(`   Costs their own department: ${p.cost_to_my_dept}`);
  if (p.evidence_needed.length) console.log(`   Would want to know: ${p.evidence_needed.join("; ")}`);
  if (p.risks_i_own.length) console.log(`   Risks they own: ${p.risks_i_own.join("; ")}`);
  if (p.hard_blocker) console.log(`   🔒 HARD BLOCKER: ${p.hard_blocker}`);
}

// ── run ───────────────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  const call = makeCaller(client);

  console.log(`YOUR QUESTION:\n  "${question}"`);

  rule("PHASE 1 — intake: what is actually being asked, and who should weigh in");
  const intake = await runIntake({ founder, rawRequest: question, call });
  const r = intake.routing;
  console.log(`Real question: ${r.real_question}`);
  console.log(`Classified as: ${r.request_type}`);
  console.log(`Decision: ${r.decision}`);
  for (const [a, why] of Object.entries(r.reason_per_agent)) console.log(`  ✓ ${a} — ${why}`);
  for (const [a, why] of Object.entries(r.excluded)) console.log(`  ✗ ${a} — ${why}`);
  if (r.missing_info.length) console.log(`Missing info: ${r.missing_info.join("; ")}`);

  if (r.decision !== "multi_agent") {
    console.log(
      `\nThe coordinator judged this doesn't need the whole company — it chose ` +
        `${r.decision}. That is the escape hatch working as designed, not a failure. ` +
        `Ask something with a real trade-off in it (money against speed, scope against ` +
        `runway) to see the room argue.`
    );
    console.log(`\n${calls} model calls · $${cost.toFixed(4)}`);
    return;
  }

  rule("PHASE 2 — each department answers alone, unable to see the others");
  const agents = r.agents.filter((a) => a !== "devils_advocate");
  const pass = await runIndependentPass({
    founder,
    rawRequest: question,
    realQuestion: r.real_question,
    agents,
    call
  });
  const positions: Partial<Record<AgentId, AgentPosition>> = {};
  for (const res of pass.results) {
    if (res.position) {
      positions[res.agent] = res.position;
      showPosition(res.agent, res.position);
    } else {
      console.log(`\n── ${res.agent.toUpperCase()} ── failed: ${res.error}`);
    }
  }

  rule("PHASE 3 — where they actually disagree (computed, not asked)");
  const conflicts = detectConflicts(positions);
  if (!conflicts.length) console.log("Only one department answered — nothing to compare.");
  for (const c of conflicts) console.log(`${c.a} vs ${c.b}: ${c.kind}\n   ${c.reason}`);

  let unresolved = false;
  if (needsNegotiation(conflicts)) {
    rule("PHASE 4 — they argue it out (2 rounds maximum)");
    const neg = await runNegotiation({
      founder,
      rawRequest: question,
      realQuestion: r.real_question,
      positions,
      conflicts,
      call
    });
    unresolved = neg.unresolved;
    for (const round of neg.rounds) {
      console.log(`\n─ Round ${round.round} ─`);
      for (const t of round.turns) {
        console.log(`\n  ${t.agent}: ${t.precise_disagreement}`);
        console.log(`     Would change their mind if: ${t.what_would_change_my_mind}`);
        console.log(`     Proposes: ${t.proposal}`);
        console.log(`     Considers it settled: ${t.resolved}`);
      }
    }
    console.log(`\nOutcome: ${unresolved ? "UNRESOLVED — your call" : "they converged"}`);
  } else {
    rule("PHASE 4 — skipped: nothing worth debating");
  }

  let redTeam: DevilsAdvocateVerdict | null = null;
  if (shouldInvokeDevilsAdvocate({ positions, conflicts, founderRequested: stress })) {
    rule("PHASE 4b — the challenger tries to break the plan");
    const rt = await runDevilsAdvocate({
      founder,
      rawRequest: question,
      realQuestion: r.real_question,
      positions,
      call
    });
    redTeam = rt.verdict;
    console.log(`Plan judged sound: ${redTeam.plan_is_sound}`);
    console.log(`Load-bearing assumption: ${redTeam.load_bearing_assumption}`);
    console.log(`How it could be false: ${redTeam.how_it_could_be_false}`);
    console.log(`Cheapest way to find out: ${redTeam.cheapest_test}`);
    console.log(`If this fails in 12 months: ${redTeam.failure_post_mortem}`);
    console.log(`Nobody here represents: ${redTeam.who_is_not_in_the_room}`);
    redTeam.objections.forEach((o, i) => console.log(`  ${i + 1}. ${o}`));
  } else {
    rule("PHASE 4b — challenger not triggered (they already disagree, or --stress not set)");
  }

  rule("PHASE 5 — the brief");
  const syn = await runSynthesis({
    founder,
    rawRequest: question,
    realQuestion: r.real_question,
    positions,
    conflicts,
    negotiation: [],
    devilsAdvocate: redTeam,
    unresolved,
    call
  });
  const b = syn.brief;
  console.log(`RECOMMENDATION (confidence ${b.confidence}/5)\n  ${b.recommendation}`);
  console.log(`  Why that confidence: ${b.confidence_reason}`);
  console.log(`\nTHE REAL DISAGREEMENT\n  ${b.the_real_disagreement}`);
  console.log(`\nTHE TRADE-OFF ONLY YOU CAN MAKE\n  ${b.tradeoff_founder_must_own}`);
  console.log(`\nSTOP IF\n${b.kill_criteria.map((k) => `  · ${k}`).join("\n")}`);
  console.log(`\nNEXT ACTION (${b.next_action.owner})\n  ${b.next_action.action}`);
  console.log(`\nSTILL UNKNOWN\n  ${b.what_we_dont_know}`);
  if (b.unresolved) console.log(`\n⚠ Left UNRESOLVED — the room could not settle it for you.`);

  console.log(
    `\n${"─".repeat(76)}\n${calls} model calls · $${cost.toFixed(4)} · ` +
      `${cacheRead.toLocaleString()} cached input tokens reused`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
