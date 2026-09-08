# What each department hands the founder

**Status:** design, awaiting founder review.
**Date:** 2026-09-08
**Mockups:** https://claude.ai/code/artifact/fd886ed6-f7f5-4383-b91b-0751eeb16043
**Founder decisions (8 Sep):** departments declare primary outputs and may deviate with reason ·
shapes become real types with a compatibility read · one ask may fan out into several artifacts,
confirmed before it runs · every kind exports to a file · **Product joins the roster** · a
deliverable shows what it does not know · a failed run files nothing and bills nothing.

## The finding

Measured against the code at `4f41034`, not recalled.

Codepet has thirteen deliverable kinds, twelve real viewers (`DeliverableViewers.swift`, 1195
lines) and a Library that already groups finished work by department. The shapes are not missing.
What is missing is that **no structured kind is a shape at all — each is one company's artifact
frozen into the wire format.** The generator does not describe a checklist; it describes *this*
checklist. Verbatim from `runTaskCore.ts`:

- `sheet` — "the 4 fixed inputs `price`, `waitlist`, `conversion`, `churn` … **Never add a 5th input.**"
- `calendar` — "`weeks[]` = **exactly 2**"
- `dms` — "**exactly 4** … `name` (**persona placeholder**)"
- `screens` — `art: { enum: ["connect", "session", "recap"] }`
- `site` — "**exactly 3** `steps[]` … **exactly 3** `features[]`"
- `checklist` — "**exactly 5-7** actionable steps"

That last enum is the clearest case: one demo company's onboarding flow, fixed in the product's
schema. Every founder's Design department can produce three screens called connect, session and
recap, and nothing else.

**This is why the gaps look scattered and are not.** A business plan has no shape for the same
reason pricing cannot express usage-based billing and a communication plan cannot run six weeks:
the format encodes a worked example instead of a type. Fixing three kinds individually re-creates
the problem in the fourth.

Two further defects fall out of the same audit:

- **Nothing constrains which department produces what.** The prompt says "Pick whichever `kind`
  best fits what you produced from this exact list". A department contributes expertise
  (`DEPARTMENT_FOUNDATIONS`) and never an output shape, so Finance can hand back `screens`.
- **Nothing can leave the app.** Copy to clipboard is the only egress. `SiteViewer`'s own comment:
  "No Share affordance, no Copy link." The landing page Design renders cannot be deployed; the
  business plan Finance writes cannot be sent to an investor.

## Layer 1 — the contract

Each department declares **primary** outputs, which steer the prompt, and **allowed** outputs,
reachable when the ask calls for them. Everything else is closed. The model may deviate within
`allowed`; it can never cross into another department's world.

| Department | Pet | Primary | Allowed |
| --- | --- | --- | --- |
| Product | *see Open* | `bizplan`, `doc` | `checklist`, `sheet`, `calendar` |
| Engineering | byte | `doc`, `plan`, `checklist` | `email` |
| Design | luna | `screens`, `site`, `doc` | `post` |
| Marketing | nova | `calendar`, `post`, `doc` | `dms`, `email`, `site` |
| Sales | nova | `dms`, `email`, `doc` | `sheet`, `calendar` |
| Support | sage | `doc`, `email`, `checklist` | `legal` |
| Finance | crash | `sheet`, `doc` | `legal` |
| Operations | glitch | `checklist`, `calendar`, `doc` | `plan`, `email` |
| Legal | glitch | `legal`, `doc` | `checklist`, `email` |

**`text` and `other` appear in no row, and that is the point.** They are the untyped fallbacks;
the contract's job is to make them unreachable. `other` stays in the enum because
`DeliverableKind(raw:)` must fail open on an unknown string — it is a decode guard, not an output.

**Where the contract lives.** In `departments.ts` beside `DEPARTMENT_FOUNDATIONS`, as data, and
rendered into the prompt by the same builders. Not in Swift: the client decodes whatever `kind`
arrives (`DeliverableKind(raw:)`), so a client-side contract would be a second opinion that can
disagree with the generator. One source, server-side, mirrored in a test.

## Layer 2 — shapes become types

Every change below is additive to the payload schema. **Old artifacts keep rendering** via the
compatibility read in the next section.

| Kind | Change | Why |
| --- | --- | --- |
| `sheet` | `inputs[{name,unit,val,min,max,step}]` + `outputs[{name,formula,value}]`; drop the fixed four and the "never a 5th" rule | Any pricing model: usage-based, seat, one-time, marketplace. The formula becomes visible, which is what makes a model auditable rather than a number |
| `calendar` | `phases[{label,from,to,items[{channel,owner,body}]}]`; weeks become one phase shape | **Absorbs `campaign`.** A two-week content calendar is a one-phase calendar; a six-week launch runway is three. No fourteenth kind |
| `checklist` | `items[{t,done,owner?,due?}]`, count unbounded | A 20-step launch runbook. Owners and dates are what make a checklist operable |
| `screens` | `art` becomes a free string; count unbounded | Removes one demo company's onboarding from the product schema |
| `site` | `sections[]` of typed blocks; `steps`/`features` become section types | Pricing tables, FAQs, any section count |
| `doc` | add `rules_out[]`, and `source` on each section | A decision that names what it forecloses is one you can revisit. `call`-first is kept — it was already right |
| `post` | add `platform`, `limit` | Renders clean today and fails on publish. The limit is checked as it renders |
| `email` | add `subject`, `to` | Subject is not a markdown heading |
| `legal` | fill `sections[{h,p}]`, numbered | **Fixes a live contradiction:** the schema documents `sections` as "doc/legal", the prompt never asks Legal to fill it, and `LegalViewer` reads only `body`. One of the three is wrong; this makes it the prompt |
| `dms` | `messages[{audience,note,msg}]` — `name` becomes `audience` | **See below** |
| `bizplan` | **new** — `slots[{key,value,source,state}]` | The one genuinely new kind |
| `plan` | unchanged | It is a code-change plan and correct as one. It is not, and never was, a business plan |
| `text`, `other` | unchanged | Fallbacks, made unreachable by Layer 1 |

### `dms` invents people, and must stop

The prompt asks for four messages whose `name` is a "persona placeholder". Sales therefore hands
the founder four messages addressed to people who do not exist, rendered identically to messages
addressed to real prospects.

This is the same objection that already deleted two things from `PostViewer`, whose comment states
the rule: engagement counts and an initials avatar were removed because "they are indistinguishable
from data, and the founder cannot tell by looking that the app is making them up." A fabricated
recipient is a stronger case than a fabricated like count, because the founder might send it.

`name` becomes `audience` — "lapsed journaler", "privacy-first buyer" — and the viewer labels the
set as templates addressed to a type. Real names enter only when the founder supplies a list.

### `bizplan`

A business plan is a set of typed claims with provenance, not an essay. Each slot carries
`key`, `value`, `source` (the deliverable id it was read from) and `state`
(`filled` · `needs_founder` · `needs_run` · `stale`).

Slots: problem · who it's for · who it's not for · offer · price · unit cost · channels ·
biggest risk · next 90 days.

The founder-visible consequence is that an empty `bizplan` is **the list of what you have not
decided** — the most useful screen a new company has. A `doc` cannot do this, because prose has no
way to be honestly incomplete.

### The compatibility read

`coercePayload` gains a legacy branch per changed kind, before the new one:

- `sheet` — a payload with `price`/`waitlist`/`conversion`/`churn` is lifted into four `inputs[]`
  entries with the units they always implied.
- `calendar` — `weeks[]` is lifted into `phases[]`, one phase per week, `channel` and `owner` empty.
- `screens`, `site`, `checklist` — already structurally compatible; only the count and enum
  constraints are relaxed.

The nine filed artifacts in `DemoProject.filed` are the test corpus: they were authored against
the old schema and must render unchanged. `DemoProjectParityTests` already fails on filler
reaching the catch-all, so it will notice a lift that produces an empty shape.

## Layer 3 — states

A shape is half a contract. Each kind renders in five conditions, none of which is defined today.

| State | Rule |
| --- | --- |
| **Empty** | Slots render **named and unfilled**, never absent. Also surfaces the five brief fields (`goal`, `traction`, `problem`, `runway`, `constraints`) that are collected by interviews and displayed nowhere — the one context a new founder supplied and cannot see |
| **Partial** | Show the fraction ("2 of 6 slots unfilled") and make each gap actionable: run the department that owns it, or answer it |
| **Failed** | Files **nothing**, bills nothing, and says what it did not do. A payload that fails `coercePayload` is a failure, **not** a document — today it silently degrades to a markdown wall and the founder was promised a model |
| **Revised** | A revision **may change kind** when the founder asks. Today the prompt forbids it ("Keep the same kind and intent"), which blocks the most natural request a founder makes. Keep a pointer to the version replaced |
| **Stale** | A cited slot records the deliverable it read. When that source is superseded, the citing artifact says "Finance's figure changed since this was written" and **never silently updates** — the founder approved the old number |

Stale is a new obligation created by provenance. It is worth it: the alternative is a business plan
that cites a price Finance has since changed, and looks correct.

## Layer 4 — lifecycle

### One ask, several artifacts

`record_deliverable` becomes `record_deliverables` — an ordered set. The founder sees the split
**before it runs**, with per-artifact credit cost, and can drop any part.

```
"a marketing and communication plan, and the social posts for it"

  → calendar   nova · Marketing    ~4 credits
  → post ×6    nova · Marketing    ~2 credits
  → screens    luna · Design       ~6 credits   [offered]

  [Run all]  [Just the plan]  [Pick…]
```

- **Ordered by dependency.** The posts belong to the plan's phases, so the plan is produced first
  and fed forward as upstream work.
- **Crossing departments is offered, never assumed.** The `screens` row costs credits in another
  department; it is presented the way `ChainOffer` already presents `[Run both]` / `[Just mine]`.
- **Approval stays per-artifact, through one path.** Every approval routes through
  `CompanyStore.fileApproval` — the single site both `approveDraft` and `approveTask` call.
  `ApprovalParityTests` exists because those two drifted once; N approvals per ask must not become
  a second code path. Write approval logic there, not in the callers.
- **Members succeed or fail independently.** If the `calendar` lands and `post` fails, the calendar
  is still offered for approval and the posts file nothing and bill nothing. A set is not a
  transaction — one member's failure must not discard work the founder can already use. The
  founder is told which member failed and what it did not do, by name.

### Assembly

`UpstreamWork` caps upstream context at 3 items × 1500 characters, enforced in `parseUpstream`
rather than trusted from the client. A `bizplan` citing Finance, Sales, Engineering and Support is
already at four sources, and 1500 characters is a fragment of a real document.

**Cite slots, not documents.** Pull the one figure or sentence a slot needs. This is cheaper than
raising the cap, and it is the same mechanism that makes provenance and staleness work — so the
cap stays where it is.

### Editing

**A filed artifact is immutable.** Moving a `sheet` slider is an exploration, and the viewer offers
"save as a new version". Approval is the founder's signature and must not change under them.

**Export takes what is on screen** (founder decision, 8 Sep). Exporting is not editing, so this does
not weaken the rule above: the filed artifact is untouched, and the file the founder receives shows
the sliders they moved and the boxes they ticked. The alternative — exporting the as-drafted payload
— was rejected because the founder moves the sliders *in order to* get numbers out, and the button
beside Copy would have handed back the original ones. Copy already reads live state; the two buttons
must not disagree about what the document is.

### Export

Every kind exports to a file. Nothing leaves without the founder choosing it.

| Kind | Export |
| --- | --- |
| `doc`, `bizplan`, `legal`, `plan` | `.md` + `.pdf` |
| `sheet` | `.csv` — inputs, outputs, and the formula |
| `calendar` | `.csv` + `.ics` |
| `site` | `.html` folder, ready to host |
| `post`, `dms`, `email` | `.txt` per item |
| `screens` | `.png` per screen |
| `checklist` | `.md` |

**Where it goes.** `DeliverableFrame`'s `action:` slot, whose comment warns that "that frame is
shared by 9 viewers and 13 deliverable kinds, and widening a shared API to serve one kind is the
wrong trade." Export is the case that inverts the objection: it serves **every** kind, so widening
the shared frame is correct here for exactly the reason it was wrong before. `action:` gains an
export case alongside `.copy`.

**Overwriting is the panel's job for a single file** (founder decision, 8 Sep). `NSSavePanel`
already asks Replace/Cancel, which is founder confirmation at the point of naming and clearer than
silently writing a differently-named file. A **set** (`dms`, `calendar`) is picked as a directory
with no per-file prompt, so there the rule is never-overwrite: a repeat becomes `plan-2.md`. The
rule is narrow because the guarantee is only needed where the panel cannot give it.

**The mechanism.** The founder picks a destination through `NSSavePanel`; the app writes and never
uploads. Rendering is per-kind and pure where it can be — a function from payload to file bytes,
testable without a view — which is the same split that made `DepartmentPickerRows` assertable.
`.pdf` is the one exception: it renders through the existing viewer via `ImageRenderer`, so the
exported page looks like the artifact the founder approved rather than a second layout that can
drift from it.

Deployment of `site` to a live URL is **out of scope** — see below.

## Product joins the roster

`bizplan` belongs to Product, as in any real company. Product already exists in
`DepartmentCatalog.all` and already convenes in the Virtual Company room; it is excluded from
`.roster` by one filter because `dept-product.png` is a byte-identical copy of `dept-eng.png` and
a roster row would wear Engineering's identity.

Joining the roster needs:

1. **A sprite** for `dept-product.png`.
2. **A pet.** Nothing else blocks it.
3. **The `chief_of_staff` role prompt updated.** The convene roster lives in prose there, and the
   router acts on that prose rather than the enum — two tests in `companyRegistry.test.ts` enforce
   this. Product is already listed for convening; the roster change must not desync them.
4. `LibraryView` and the eight-department fixture assertions become nine.
   `DemoProjectEightDepartmentsTests` is named for the count it pins.

## Open — Product's voice

Seven pet characters exist; six are cast. The only uncast pet is **`null`, "The Chaos Gremlin"**,
personality "chaotic, silly, unpredictable".

That is the wrong voice for the department that owns the business plan and the roadmap — Product is
the soberest seat in the company. Two ways out, and this is a founder call:

- **Recast `null`.** `DepartmentCompanions`' own comment says casting is by editorial fit, that
  `PetCharacter.domain` does not predict it, and that the map "is freely editable, since nothing
  depends on the exact cast." Null's personality string is game-layer content; rewriting it costs
  nothing structural.
- **Add a seventh voice** for Product and leave Null as the chaos gremlin it is.

This is the launch-blocking item already on record. It is now the only thing between Product and
the roster.

## Build order

This spec is too large for one implementation plan. Six phases, each its own plan, each shippable
on its own. The order is by dependency first and by founder-visible value second.

| # | Phase | Depends on | Why here |
| --- | --- | --- | --- |
| 1 | **Export** (Layer 4) | nothing | No wire change, no schema risk, and it is the only phase that makes existing artifacts more useful the day it lands. Per-kind, so it can ship one renderer at a time |
| 2 | **The contract** (Layer 1) | nothing | Data in `departments.ts` plus prompt rendering plus tests. No wire change. Makes `text`/`other` unreachable, which is a quality floor everything else stands on |
| 3 | **Shapes become types** (Layer 2) + the **Failed** rule | 2 | The wire change, and the riskiest phase. The Failed rule rides here because it is the same function: `coercePayload` returning `null` must stop meaning "file it as markdown". That is a correctness bug, not a feature |
| 4 | **`bizplan` + Product on the roster** | 3, and the pet decision | Needs the slot machinery from phase 3. Blocked on Open below — do not start it before the voice is settled |
| 5 | **Fan-out** (Layer 4) | 3 | `record_deliverables`, per-artifact approval through `fileApproval`, the confirmation step. Independent of 4 |
| 6 | **Remaining states** (Layer 3) | 4 | Empty and Partial are cheap once slots exist. **Stale** needs provenance, which arrives with `bizplan`. Revised is a prompt change and can be pulled earlier if wanted |

Phases 1 and 2 are independent of everything and of each other. If only one thing gets built,
build phase 1.

## What this breaks

- **The wire format changes for five kinds.** Mitigated by the compatibility read; the nine
  `DemoProject.filed` artifacts are the corpus that proves it.
- **`record_deliverables` changes the run contract** for both transports. The local sidecar imports
  the same builders (`ONE_SHOT_OPS`), so the change lands once — but `scripts/build-sidecar.sh`
  must run, or the routers report `localUnavailable`.
- **The eight-department count becomes nine** in fixtures and assertions.
- **Fan-out multiplies credit spend per ask.** The confirmation step is what keeps that honest.

## Testing

- A test per department asserting its primary and allowed sets, and that `text`/`other` are
  unreachable from any department.
- A legacy-payload test per changed kind: the old shape lifts to the new one with no field lost.
- A failure test: a payload that fails coercion files nothing and bills nothing. Break the guard
  and watch it go red — five tests in a recent plan could not fail, and this is the class of guard
  that invites it.
- A fan-out test asserting every artifact in a set routes through `fileApproval`.
- An export test per kind: the file is produced and non-empty.

## Out of scope

- **Deploying `site` to a live URL.** Real hosting, domains and a per-company cost. Export of an
  `.html` folder is the deliberate stopping point.
- **Rewriting the eight department replies in each pet's voice.** Structural change only, as in the
  6 Sep spec — content work with its own bilingual cost.
- **Vietnamese payload content.** `body` and `title` are already handled
  (`language === "vi"`); payload field content is not specified, and is a separate decision.
- **A visual editor for any kind.** Filed artifacts are immutable; editing is out.
- **Raising `UpstreamWork`'s caps.** Slot-level citation replaces the need.
