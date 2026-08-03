import { ROUTER_MODEL } from "../anthropic";
import { composeAgentSystem, SystemBlock } from "./registry";
import {
  AgentId,
  FounderContext,
  isAgentId,
  RequestType,
  RoutingChoice,
  RoutingDecision,
  TokenUsage
} from "./types";

/**
 * Agents the router may convene. chief_of_staff is excluded on purpose: it is
 * the router and synthesiser, not a department that holds a position.
 */
const ROUTABLE_AGENTS: AgentId[] = ["product", "finance", "devils_advocate"];

const REQUEST_TYPES: RequestType[] = ["DECISION", "DIAGNOSIS", "PLANNING", "REVIEW"];
const DECISIONS: RoutingChoice[] = ["single_agent", "multi_agent", "needs_clarification"];

export const ROUTING_TOOL = {
  name: "record_routing",
  description:
    "Record your intake decision for this request. You must call this tool; do not answer in prose.",
  input_schema: {
    type: "object" as const,
    properties: {
      decision: {
        type: "string",
        enum: DECISIONS,
        description:
          "single_agent when one specialist suffices; multi_agent only when you can name at least two departments whose interests actually pull in different directions; needs_clarification when the missing input is material."
      },
      agents: {
        type: "array",
        items: { type: "string", enum: ROUTABLE_AGENTS },
        description:
          "Departments to convene. Exactly one for single_agent, at least two for multi_agent, empty for needs_clarification."
      },
      real_question: {
        type: "string",
        description:
          "The question actually at stake. Say so explicitly when it differs from what was asked."
      },
      request_type: { type: "string", enum: REQUEST_TYPES },
      reason_per_agent: {
        type: "object",
        additionalProperties: { type: "string" },
        description:
          "For each agent you selected, one line on why their concern is live in THIS request. If you cannot articulate why, do not include them."
      },
      excluded: {
        type: "object",
        additionalProperties: { type: "string" },
        description: "For each agent you did not select, one line on why not."
      },
      missing_info: {
        type: "array",
        items: { type: "string" },
        description:
          "Materially missing information, including any discipline this deployment does not have."
      }
    },
    required: ["decision", "agents", "real_question", "request_type"],
    additionalProperties: false
  }
};

function asStringMap(value: unknown): Record<string, string> {
  if (typeof value !== "object" || value === null) return {};
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (typeof v === "string") out[k] = v;
  }
  return out;
}

/**
 * Validates the router's tool output. Strict on purpose: a hallucinated
 * department has no role prompt in this deployment, so convening it would fail
 * later with a much less obvious error.
 */
export function parseRoutingToolInput(
  input: unknown
): RoutingDecision | { error: string } {
  if (typeof input !== "object" || input === null) {
    return { error: "routing tool input must be an object" };
  }
  const raw = input as Record<string, unknown>;

  const decision = raw.decision;
  if (typeof decision !== "string" || !(DECISIONS as string[]).includes(decision)) {
    return { error: `unknown decision: ${String(decision)}` };
  }

  if (!Array.isArray(raw.agents)) {
    return { error: "agents must be an array" };
  }
  const agents: AgentId[] = [];
  for (const candidate of raw.agents) {
    if (!isAgentId(candidate) || !ROUTABLE_AGENTS.includes(candidate)) {
      return { error: `agent not available in this deployment: ${String(candidate)}` };
    }
    if (!agents.includes(candidate)) agents.push(candidate);
  }

  if (decision === "single_agent" && agents.length !== 1) {
    return { error: `single_agent requires exactly one agent, got ${agents.length}` };
  }
  if (decision === "multi_agent" && agents.length < 2) {
    return { error: `multi_agent requires at least two agents, got ${agents.length}` };
  }

  if (typeof raw.real_question !== "string" || raw.real_question.trim().length === 0) {
    return { error: "real_question is required" };
  }
  const requestType = raw.request_type;
  if (typeof requestType !== "string" || !(REQUEST_TYPES as string[]).includes(requestType)) {
    return { error: `unknown request_type: ${String(requestType)}` };
  }

  return {
    decision: decision as RoutingChoice,
    agents,
    real_question: raw.real_question.trim(),
    request_type: requestType as RequestType,
    reason_per_agent: asStringMap(raw.reason_per_agent),
    excluded: asStringMap(raw.excluded),
    missing_info: Array.isArray(raw.missing_info)
      ? raw.missing_info.filter((m): m is string => typeof m === "string")
      : []
  };
}

/**
 * The single injection seam for every LLM phase. The real implementation lives
 * in virtualCompany.ts; tests pass fakes so no phase needs network mocking.
 */
export type AgentCaller = (args: {
  agent: AgentId;
  model: string;
  system: SystemBlock[];
  userMessage: string;
  tool: unknown;
  toolName: string;
}) => Promise<{ input: unknown; usage: TokenUsage }>;

const INTAKE_INSTRUCTION = `Perform your INTAKE duties on the founder's request below.

Judge scale honestly: does this need the company, or one person? Bias toward
single_agent. Convening the company for a small question wastes the founder's
money and trains them to ignore the output. Reserve multi_agent for decisions
that are expensive, hard to reverse, or where you can name at least two
departments whose interests actually pull in different directions.

Call record_routing.

THE REQUEST:
"""
<request>
"""`;

export async function runIntake(args: {
  founder: FounderContext;
  rawRequest: string;
  call: AgentCaller;
}): Promise<{ routing: RoutingDecision; usage: TokenUsage }> {
  const { input, usage } = await args.call({
    agent: "chief_of_staff",
    // Routing is classification and it runs on every single request, so the
    // cheapest tier is enough. Synthesis is where the top tier earns its cost.
    model: ROUTER_MODEL,
    system: composeAgentSystem({
      agent: "chief_of_staff",
      founder: args.founder,
      rawRequest: args.rawRequest
    }),
    userMessage: INTAKE_INSTRUCTION.replace("<request>", args.rawRequest.trim()),
    tool: ROUTING_TOOL,
    toolName: ROUTING_TOOL.name
  });

  const parsed = parseRoutingToolInput(input);
  if ("error" in parsed) {
    throw new Error(`unusable routing from chief_of_staff: ${parsed.error}`);
  }
  return { routing: parsed, usage };
}
