# The first-run greeting has no caller

**Status:** design, awaiting founder review.
**Date:** 2026-09-04
**Founder decision:** hook it where the dock first opens on an empty transcript, so it reaches
real new users AND the demo.

## The finding

`FirstRunGreetingBuilder` produces exactly the orienting message a new founder needs:

> *"{Name}, your company for {Project} is ready. The best first move is "{task}". Want me to do
> it with you, right here? I'll draft it and you approve — nothing ships without your say-so."*

It is a verbatim-logic port of the web's `buildFirstRunGreeting`, it carries an inline
`FirstRunAction` so the founder can start that task from the message, it is covered by two test
suites (`FirstRunGreetingTests`, `CompanyStoreFirstRunGreetingTests`) — and **it never runs.**

The chain, verified:

| Step | State |
| --- | --- |
| `seedFirstRunGreeting` | called from exactly one place, `CompanyStore.swift:606` |
| that call site | the completion branch of the first-run enrich interview |
| reached only when | `interviewState.seedGreetingWhenDone == true` |
| set only by | `startEnrichInterviewIfNeeded` (`:552`) |
| callers of that | **none in `codepet/`** — one test, and nothing else |

`startEnrichInterviewIfNeeded` says so itself: *"the flow it belongs to has no live caller today
(the dock opens on the landing hero instead)"*. So the greeting is dead by inheritance — nobody
deleted it, the thing upstream of it was simply never connected.

**What a new founder gets instead:** the hero (`ChatEmptyState`) and a beacon card with **Run
it**. Reported by the founder as *"as soon as they log in, they're directed straight to a task
card — where's the initial prompt?"* They can type a free-form question (the composer reads "Ask
your company anything…") but nothing invites it.

**This also corrects the record.** The 2026-09-04 first-run-approval-note spec claims no path a
new user walks states the approval rule. That was wrong: this greeting ends with *"nothing ships
without your say-so."* The claim was made after checking the cold open and the hero, and not
this. The note that spec produced is still worth having — it lands at the moment of
consequence, where this greeting lands minutes earlier — but its framing overstated the gap.

## Design

Seed the greeting from `hydrate(companyId:)` once the company has loaded, when the transcript is
empty and this account has never been greeted.

**`greetedAt: Date?` on `CompanyState`, mirroring `introSeenAt` and `firstApprovalAt`** — same
optional-Date shape, same epoch-millis persistence under `companies/{uid}`, same dedicated saver,
same fail-soft posture. Three fields now share this shape; that is a pattern, not a coincidence,
and a fourth should follow it too.

**Why a persisted flag and not just `chatMessages.isEmpty`.** `newChat()` sets
`chatMessages = []` (`CompanyStore.swift:1316`). An empty-transcript condition alone would
re-greet the founder every time they start a new conversation — welcoming someone who has been
using the product for a month. The transcript is session-only; the flag is what makes "first
run" mean first run.

**Why prototype mode gets it for free.** `saveGreeted` will guard on
`PrototypeMode.allowsCloudWrites` like its siblings, returning `true` without writing. So in the
demo the flag lives in memory only and the greeting appears on every launch — which is what a
demo wants, and is why this hook (rather than the onboarding edge) was chosen: prototype mode
boots an already-onboarded company and never crosses that edge, which is why the founder has
never seen this message.

**The decision is a pure static**, `FirstRunGreetingGate.shouldGreet(hasBeenGreeted:transcriptIsEmpty:hasTasks:)`,
so the suite pins it without a store. `hasTasks` is included because the greeting's whole value
is naming the first move: on a company whose roadmap has not resolved yet, `nextStep` is nil and
the builder falls back to *"Take a look around…"*, which is a weaker message worth not
committing to. Better to greet on the next hydrate, with a task to name.

## Explicitly out of scope

- **The enrich interview.** It stays uncalled. It is another engineer's flow, it asks three
  brief-shaping questions, and connecting it is a separate product decision about whether a new
  founder should be interviewed before they see their company.
- **`startEnrichInterviewIfNeeded`'s visibility.** It stays `internal` with its comment intact —
  the comment is now the record of why the greeting was dead.
- **The cold open and the hero.** Unchanged.
- **Credits messaging.** Still its own conversation, still blocked on the trial amount.

## Tests

| Guard | Why |
| --- | --- |
| Greets on a fresh account with a resolved roadmap | the whole point |
| Does NOT greet when `greetedAt` is set | once per account, not per launch |
| Does NOT greet after `newChat()` empties the transcript | the trap this flag exists for |
| Does NOT greet when the roadmap is empty | no first move to name; wait for the next hydrate |
| Does NOT greet when the transcript already has messages | never interrupts a conversation |
| The greeting carries its `FirstRunAction` | the founder can start the task from the message |
| `greetedAt` survives encode/decode, and a document without it still decodes | the `keyNotFound` landmine on the hand-written `init(from:)` |
| Prototype mode greets on every launch | the reason this hook was chosen; asserted, not assumed |

## Cost

~50 lines plus tests: one field and its persistence, one saver, one pure gate, one call in
`hydrate`.
