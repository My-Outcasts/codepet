// Types for the Virtual Company multi-agent system.
// Spec: codepet-multi-agent-prompt-en.md (PART 2 orchestration, PART 5.3 blackboard)

export type AgentId =
  | "chief_of_staff"
  | "devils_advocate"
  | "product"
  | "finance"
  | "engineering"
  | "design"
  | "marketing"
  | "sales"
  | "support"
  | "operations"
  | "legal";

/** Full MVP roster. Order is stable so prompt caching stays byte-identical. */
export const ALL_AGENTS: AgentId[] = [
  "chief_of_staff",
  "devils_advocate",
  "product",
  "finance",
  // Appended, never reordered: the shared prompt prefix is byte-identical per
  // run, but a reordering here would still churn every fixture that asserts the
  // roster, for no gain.
  "engineering",
  "design",
  "marketing",
  "sales",
  "support",
  "operations",
  "legal"
];

/** Agents that own a departmental concern and submit a position in Phase 2. */
export const DEPARTMENT_AGENTS: AgentId[] = [
  "product",
  "finance",
  "engineering",
  "design",
  "marketing",
  "sales",
  "support",
  "operations",
  "legal"
];

/**
 * Maps an agent to a `Department.key` on the client so the UI can reuse the
 * existing accent colour and abbreviation. `null` means "render this agent with
 * its own identity, not as a department":
 *  - chief_of_staff → the founder's companion pet
 *  - devils_advocate → spec §3.8: "You are not a department. You have no
 *    interests to protect." A department colour would misrepresent what it is.
 */
export const AGENT_DEPARTMENT_KEY: Record<AgentId, string | null> = {
  chief_of_staff: null,
  devils_advocate: null,
  product: "product",
  finance: "fin",
  // The values are `Department.key` on the client, not the agent id — the two
  // differ wherever the client abbreviated (fin, mkt, ops, eng).
  engineering: "eng",
  design: "design",
  marketing: "mkt",
  sales: "sales",
  support: "support",
  operations: "ops",
  legal: "legal"
};

export function isAgentId(value: unknown): value is AgentId {
  return typeof value === "string" && (ALL_AGENTS as string[]).includes(value);
}

export type RequestType = "DECISION" | "DIAGNOSIS" | "PLANNING" | "REVIEW";

export type Confidence = 1 | 2 | 3 | 4 | 5;

/**
 * Machine-comparable summary of an agent's position. Not in the original spec
 * schema — added so Phase 3 conflict detection can be pure code with no LLM
 * call (spec §2.2 Phase 3). Two prose fields cannot be compared
 * deterministically; two enums can.
 */
export type Stance = "proceed" | "proceed_with_conditions" | "do_not_proceed";

/** Phase 2 output. Mirrors the spec §2.2 schema plus `stance`. */
export interface AgentPosition {
  stance: Stance;
  position: string;
  reasoning: string;
  evidence_needed: string[];
  risks_i_own: string[];
  confidence: Confidence;
  cost_to_my_dept: string;
  hard_blocker: string | null;
}

export type ConflictKind = "CONFLICT" | "BLOCKER" | "TENSION" | "ALIGNED";

export interface Conflict {
  a: AgentId;
  b: AgentId;
  kind: ConflictKind;
  /** Deterministic explanation of why this pair classified as it did. */
  reason: string;
}

export type RoutingChoice = "single_agent" | "multi_agent" | "needs_clarification";

export interface RoutingDecision {
  decision: RoutingChoice;
  /** Agents to convene. Empty for needs_clarification, length 1 for single_agent. */
  agents: AgentId[];
  real_question: string;
  request_type: RequestType;
  reason_per_agent: Partial<Record<AgentId, string>>;
  excluded: Partial<Record<AgentId, string>>;
  missing_info: string[];
}

export interface NegotiationTurn {
  agent: AgentId;
  precise_disagreement: string;
  what_would_change_my_mind: string;
  proposal: string;
  /** True only when this agent believes the trade-off is now resolvable. */
  resolved: boolean;
}

export interface NegotiationRound {
  round: 1 | 2;
  turns: NegotiationTurn[];
}

export interface DevilsAdvocateVerdict {
  load_bearing_assumption: string;
  how_it_could_be_false: string;
  cheapest_test: string;
  failure_post_mortem: string;
  who_is_not_in_the_room: string;
  /** Ranked, most decision-changing first. */
  objections: string[];
  /** True when the red team finds the plan genuinely sound (spec §3.8 rules). */
  plan_is_sound: boolean;
}

export interface DecisionBrief {
  recommendation: string;
  confidence: Confidence;
  confidence_reason: string;
  the_real_disagreement: string;
  tradeoff_founder_must_own: string;
  kill_criteria: string[];
  next_action: { action: string; owner: string };
  what_we_dont_know: string;
  /** True when a conflict could not be resolved. A valid outcome, not a failure. */
  unresolved: boolean;
}

export interface FounderContext {
  profile: string;
  stage: string;
  constraints: string[];
  language: "vi" | "en";
}

export interface TokenUsage {
  input: number;
  output: number;
  cache_read: number;
}

export interface Telemetry {
  tokens_per_agent: Partial<Record<AgentId, TokenUsage>>;
  cost_estimate_usd: number;
  /** Set when the run stopped early. Null on a complete run. */
  stopped_reason: string | null;
}

/** Source of truth for a run. Persisted so Phase 6 can resume without a restart. */
export interface Blackboard {
  run_id: string;
  uid: string;
  created_at: string;
  request: { raw: string; real_question: string; type: RequestType };
  founder: FounderContext;
  routing: RoutingDecision | null;
  positions: Partial<Record<AgentId, AgentPosition>>;
  conflicts: Conflict[];
  negotiation: NegotiationRound[];
  devils_advocate: DevilsAdvocateVerdict | null;
  synthesis: DecisionBrief | null;
  telemetry: Telemetry;
}
