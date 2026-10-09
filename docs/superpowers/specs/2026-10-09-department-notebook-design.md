# Department notebook — design

Status: approved in chat 2026-10-09. Step 2 of "one founder runs the whole company";
step 1 (room role prompt + department desk in Ask) is PR #247, and this builds on its desk.

## Problem

A department answers from its desk (PR #247), but it forgets what it learned. The founder
tells Finance "runway is 8 months"; `remember_fact` stores it in `company.decisions`, and the
next Finance question sees it only as one line among up to 30 company-wide facts, with
nothing saying it is Finance's. Approving a Finance deliverable extracts decisions the same
way: `rememberFromApproval` knows the deliverable's department, sends it to the prompt, and
drops it.

## Decision: tag the existing store, do not add a second one

`company.decisions` already is the notebook: three writers, a merge keyed on topic, a cap,
persistence on `companies/{uid}`, and a Memory panel to see and forget it. A per-department
store would duplicate all of that and give the founder a second place to manage. Rejected.

## Design

### Data
- `DecisionEntry.dept: String?` — a native department key (`fin`, `mkt`, …), nil for
  company-wide. Optional and omitted when nil, exactly like `scope`, so every stored
  decision decodes and re-encodes unchanged.
- **Identity stays `scope|topic`.** A topic is one truth for the company: when Sales records a
  new price, Finance's old price is replaced and the tag moves to Sales. Keying on dept would
  let two departments hold two prices.
- `MAX_DECISIONS` 30 → 60. Eight departments now share it. 60 × ~700 chars ≈ 42 KB of a
  1 MiB document.
- `normalizeDecisions` and `mergeDecisions` carry `dept` through. `mergeDecisions` gains
  `dept: String? = nil`, stamped on every extracted entry like `scope`.

### Writers
| Writer | `dept` |
|---|---|
| Chat `remember_fact` (`handleRemember`) | the turn's `deptKey` (the same one the prompt answered as), nil on an ordinary turn |
| Approval extraction (`rememberFromApproval`) | the deliverable's `deptKey(forSourceTaskId:)`, already resolved there |
| Room lock-in (`lockInVirtualCompanyDecision`) | nil: a decision several departments argued out belongs to the company |

No backend change: every stamp happens in Swift.

### Reader: the desk
`ChatContext.compose` with a `focusDepartment` and memory enabled adds
`<Dept> has noted:` to the desk: up to 8 applicable decisions with `dept == key`, newest
first. Those entries are left out of the general decisions block so none appears twice.
Memory off means neither block is composed. That is the Memory panel's promise.

### Memory panel
A row's caption gains the department name: `pricing · Finance · Codepet`. Forget and
assign are unchanged.

## Tests (each goes red if its guard is removed)
- Decisions: an entry without `dept` decodes; `dept` survives normalize and merge; the same
  topic from another department replaces and re-tags; the cap is 60.
- Store: `handleRemember` stamps the turn's dept and nil on an ordinary turn;
  `rememberFromApproval` stamps the deliverable's dept; lock-in stamps nil.
- ChatContext: the desk lists only its own department's notes, and only applicable ones;
  a noted entry is not repeated in the decisions block; no notes with memory off.
- In the app: tell Finance "our runway is 8 months", open a new chat, ask Finance about
  runway, and confirm the Memory panel row says Finance.

## Out of scope
Room routing to one department (step 3). Editing a note's department by hand. A per-department
cap.
