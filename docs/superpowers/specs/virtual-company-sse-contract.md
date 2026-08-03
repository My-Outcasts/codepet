# Virtual Company — SSE Contract

Backend owner: logic/BE. UI owner: separate engineer. **This document is the boundary** — build the UI against this, not against the backend source.

**Endpoint:** `POST https://us-central1-devpet-8f4b1.cloudfunctions.net/virtualCompanyRun`
**Auth:** `Authorization: Bearer <Firebase ID token>`
**Response:** `text/event-stream`. Parse with the existing `codepet/Services/SSEParser.swift` — the frame format is identical to `chatSession`.

## Request

```json
{
  "request": "Should I add team seats or price the single-player product first?",
  "language": "vi",
  "founder": {
    "profile": "Solo technical founder, one prior product that plateaued.",
    "stage": "Pre-revenue, 4 months runway, 30 beta users.",
    "constraints": ["Cannot hire this quarter."]
  },
  "stress_test": false
}
```

| Field | Required | Notes |
|---|---|---|
| `request` | yes | Max 4000 chars, non-blank |
| `language` | yes | `"vi"` or `"en"` — controls the founder-facing output language only; agent prompts are always English |
| `founder.profile` | yes | Who the founder is. May be empty string but the key must be present |
| `founder.stage` | yes | Runway, revenue, user count |
| `founder.constraints` | yes | Array of strings; `[]` is valid |
| `stress_test` | no | `true` forces the red team to run even when the departments already disagree |

## Non-SSE error responses

These come back as plain JSON with a non-200 status — no event stream is opened.

| Status | Body | UI action |
|---|---|---|
| 400 | `{"error":"invalid_payload","detail":"..."}` | Fix the request; `detail` names the field |
| 401 | `{"error":"invalid_token"}` | Re-authenticate |
| 405 | `{"error":"method_not_allowed"}` | Must be POST |
| 429 | `{"error":"daily_limit_reached","reset_at":"...","limit":N}` | Show the reset time |
| 503 | `{"error":"feature_disabled"}` | Kill switch is on — hide the entry point entirely |

## Events, in emission order

| Event | Payload | Notes |
|---|---|---|
| `run_started` | `{run_id}` | Always first |
| `routing` | `RoutingDecision` + `agent_meta[]` | **Render immediately — do not show a spinner.** Spec §4.2A: the founder learns problem decomposition from this panel, so it is content, not a loading state |
| `agent_start` | `{agent_id, department_key}` | One per department agent, **all emitted before any position arrives**. That simultaneity is what reads as a room thinking — open every column at once |
| `agent_position` | `{agent_id, department_key, position}` | Arrives per agent as it finishes, in completion order (not request order) |
| `agent_error` | `{agent_id, department_key, error}` | Show the error in that agent's column only; the run continues |
| `conflicts` | `{conflicts: Conflict[]}` | **Highest-value view in the feature.** Do not bury it in an accordion |
| `negotiation_round` | `NegotiationRound` | Zero, one, or two events. Absent entirely when nothing conflicted |
| `devils_advocate` | `{agent_id, department_key, verdict}` | Optional; preceded by its own `agent_start` |
| `brief` | `DecisionBrief` | The final deliverable |
| `run_stopped` | `{run_id, reason}` | Budget ceiling hit mid-run. `reason` is written for the founder — **show it verbatim.** A `done` still follows |
| `telemetry` | `{tokens_per_agent, cost_estimate_usd, stopped_reason}` | Show the cost. Spec §4.3: the founder has a right to know what the answer cost them |
| `done` | `{run_id, unresolved, skipped}` | Always last on a successful stream |
| `error` | `{error, detail}` | Terminal failure. **No `done` follows** — treat as stream end |

### Two flows that skip most events

**Escape hatch.** When the router decides the request does not need the company (`routing.decision` is `"single_agent"` or `"needs_clarification"`), the stream is: `run_started` → `routing` → `telemetry` → `done` with `skipped` set to that decision. No positions, no conflicts, no brief. This is a correct and common outcome — a founder asking a one-dimensional question should not see four columns spin up. Render the routing panel and the reason, and for `needs_clarification` surface `missing_info` as the ask.

**Nothing to debate.** When both departments agree, `conflicts` arrives with all pairs `ALIGNED` and **no `negotiation_round` events follow**. The brief still arrives.

## Payload shapes

Field-for-field mirrors of `functions/src/company/types.ts`.

```ts
AgentId = "chief_of_staff" | "devils_advocate" | "product" | "finance"

RoutingDecision = {
  decision: "single_agent" | "multi_agent" | "needs_clarification"
  agents: AgentId[]
  real_question: string          // often differs from what was asked — show both
  request_type: "DECISION" | "DIAGNOSIS" | "PLANNING" | "REVIEW"
  reason_per_agent: { [agentId]: string }   // why this department was convened
  excluded: { [agentId]: string }           // why others were not
  missing_info: string[]
}

AgentPosition = {
  stance: "proceed" | "proceed_with_conditions" | "do_not_proceed"
  position: string
  reasoning: string
  evidence_needed: string[]
  risks_i_own: string[]
  confidence: 1..5
  cost_to_my_dept: string
  hard_blocker: string | null    // non-null → show the 🔒 badge
}

Conflict = {
  a: AgentId, b: AgentId
  kind: "CONFLICT" | "BLOCKER" | "TENSION" | "ALIGNED"
  reason: string
}

NegotiationRound = { round: 1 | 2, turns: NegotiationTurn[] }
NegotiationTurn = {
  agent: AgentId
  precise_disagreement: string
  what_would_change_my_mind: string   // the falsification condition — show it
  proposal: string
  resolved: boolean
}

DevilsAdvocateVerdict = {
  load_bearing_assumption: string
  how_it_could_be_false: string
  cheapest_test: string
  failure_post_mortem: string
  who_is_not_in_the_room: string
  objections: string[]           // ranked, most decision-changing first
  plan_is_sound: boolean         // true → render as endorsement, not attack
}

DecisionBrief = {
  recommendation: string
  confidence: 1..5
  confidence_reason: string
  the_real_disagreement: string          // never paraphrase this in the UI
  tradeoff_founder_must_own: string
  kill_criteria: string[]
  next_action: { action: string, owner: string }
  what_we_dont_know: string
  unresolved: boolean
}

Telemetry = {
  tokens_per_agent: { [agentId]: { input, output, cache_read } }
  cost_estimate_usd: number
  stopped_reason: string | null
}
```

## Rendering rules the backend depends on

These are not style preferences. They are the reasons the feature exists (spec §4.3), and several are already enforced server-side — re-introducing them in the UI would undo that work.

1. **Never collapse the process into a spinner plus an answer.** That deletes the only differentiator.
2. **Never summarise the positions into one "we agree" paragraph.** The backend already refuses to emit a brief that buries dissent — `runSynthesis` throws on it. Do not re-introduce it in the presentation layer.
3. **Show `the_real_disagreement` verbatim.** No paraphrasing, no softening.
4. **Show each side's `what_would_change_my_mind`** on the conflict card. It teaches that disagreement is settled by evidence, not authority.
5. **End on the either/or** — use `tradeoff_founder_must_own`, never "it's up to you".
6. **`unresolved: true` is a valid outcome, not an error.** Present it as an honest answer: the trade-off is the founder's to make.
7. **Render `confidence` as dots, not a number.** A number implies false precision.
8. **No artificial delay or fake typing.** Users detect it and lose trust.
9. **No human avatars or personal names for agents.** These are departments, not simulated people.

## `department_key` mapping

Every `agent_*` event carries `department_key` so the client can reuse existing styling.

| `agent_id` | `department_key` | Client-side action |
|---|---|---|
| `product` | `"product"` | **No entry in `Department.all` yet — please add one** (`codepet/Models/Department.swift:47`) |
| `finance` | `"fin"` | Already exists; reuse it |
| `chief_of_staff` | `null` | Render as the founder's companion pet (`companyStore.company.companionId`) |
| `devils_advocate` | `null` | Needs its own visual identity — **do not give it a department colour.** Spec §3.8: "You are not a department. You have no interests to protect." A department colour would misrepresent what it is |

## Known deviation from the spec

Spec §4.2B asks for per-token parallel streaming inside the meeting room. Positions are structured tool-use output, so streaming partial JSON into typed fields is fragile. The backend emits `agent_start` then `agent_position` per agent instead. Two agents starting together and finishing independently still gives the parallel effect.

If per-token streaming turns out to matter for the UX, it is a backend change (`eager_input_streaming` on the tool) — raise it and it can be added **without changing any event name above**.

## Things the backend guarantees, so the UI need not defend against them

- A brief that buries dissent when a conflict existed. `runSynthesis` throws instead.
- More than two negotiation rounds. Hard-capped in code, not configurable.
- A silent truncation on budget exhaustion. You always get `run_stopped` with a reason, then `done`.
- An agent in `routing.agents` that has no role prompt. The router's output is validated against this deployment's roster.
- A `hard_blocker` that is an empty string. Normalised to `null` before it reaches you, so `hard_blocker !== null` is a safe test for the 🔒 badge.
