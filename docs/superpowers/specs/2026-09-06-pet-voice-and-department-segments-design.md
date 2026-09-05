# Pets speak for their departments, and the day reads as eight chapters

**Date:** 2026-09-06
**Status:** Design, approved
**Branch:** `feat/pet-voice-and-department-segments`

## The complaint

Watching the day-one simulation play, the founder asked two things:

1. *"Why isn't there a separate script for each department, but instead everything is presented all at once like this?"*
2. *"Why, when agents in each department respond, do they use 'Codepet' instead of calling out the specific pets?"*

Both are accurate descriptions of what ships today. Neither is a rendering bug.

## What is actually wrong

### The voice is unwired, not undesigned

`CopilotChatView.headerName` already encodes the correct rule, and its own comment states it:

> Who is speaking. "Codepet" for the product's own voice; a pet's name ONLY when that pet
> is the one doing the work — a department specialist, carried on `companionId`.

`CopilotMessage` carries `companionId` and `deptName` for exactly this. The run **card** sets
them — which is why the screen says *What Nova did · 6 steps* and *Built on Sage's "Decide what
happens on a bad night"*. The **prose beside the card does not**.

The cause is a single missing input. `CompanyStore.actingSpecialist(text:department:)` resolves a
pet from two sources only:

```swift
department?.key ?? DepartmentCompanions.mentionedDeptKey(in: text)
```

— the confirmed department chip, or the founder *naming* a department in their message. **A task's
own department is never consulted for the reply**, even though `taskSpecialist(for:)` resolves
precisely that and is already used for the run card:

```swift
guard let deptKey = task.dept, let dept = DepartmentCatalog.find(deptKey),
      let companionId = DepartmentCompanions.companionId(for: deptKey) else { return nil }
```

So every day-one reply takes the `else` branch and signs itself with `company.companionId`, which
is `"byte"`, which renders as **"Codepet"** after the display rename.

Confirming the gap is structural rather than incidental: `codepet/Demo/*.swift` sets
`companionId` **zero times**.

### The day is one undifferentiated stream

`DayOneScript` is 21 beats playing into one thread. The chain it demonstrates is real and worth
keeping — *"Crash cannot price anything without knowing what it runs on, so this question could
not have been asked earlier"* — but the founder sees nine near-identical cards in one scroll. The
earlier fix moved this from *one department working while narration claims eight* to *eight
departments in one stream*. It never reached *each department has a workflow you can watch*.

## The rule

Two states, not three.

| When | Header |
|---|---|
| A pet is doing departmental work | `● Nova · Marketing` — pet avatar, pet accent |
| Everything else | **no header row at all** — plain prose |

The founder chats with Codepet; the pets are department characters, not the assistant. So the
product does not announce itself on every turn, and the pets stand out by *contrast* rather than by
decoration. This is the existing documented rule with its `else` branch corrected: today that branch
returns `CodepetBrand.name` and still draws a row.

## Design

### 1. The header row becomes optional

`headerName` returns an optional. When no pet is attached, the header row is not rendered at all —
no orb, no name. When a pet is attached it renders unchanged.

The real chat and the demo render through the same view, so this lands in both at once. That is
intentional: it is the property that keeps them from drifting.

### 2. A task's department resolves the reply's voice

Resolve the specialist through the existing `taskSpecialist(for:)` and carry the result on
`companionId` / `deptName` for every message that names a task: the `producing` placeholder, the
exec-log row, and the finished draft reply. These are the three that already resolve a task and
today attribute only the card, not the message.

A reply that names no task is unaffected and stays headerless — which is the general-conversation
case, reached by the same branch rather than by a second rule.

**Explicitly not a demo-only attribution path.** The demo gets pets because it goes through the same
resolution the real chat does. A parallel copy is exactly how `MockChat.departmentReply` came to
hardcode Codepet's board on the Murror demo, and rebuilding one here would reproduce that failure on
the surface this change exists to fix.

### 3. Chapters become departments

`MockFlowScript.chapters` already derives from `beats` by deduplicating the `chapter` string in
order, and `firstBeat(of:)` finds each chapter's entry point. No new machinery is needed — the
chapter strings in `DayOneScript` change from questions (*"Is this real?"*, *"Has someone built
it?"*) to departments (*"Marketing · Nova"*, *"Finance · Crash"*).

Marketing holds two links — the interviews and the landscape scan — which is why nine questions
cover eight departments. The chapter bar therefore shows the opener plus eight departments rather
than the current twenty-one-beat sequence.

### 4. The pet asks its own question

A new intent, `.petAsks(deptKey: String, question: String)`, appends a message authored by that
department's pet — `companionId` and `deptName` set through the same resolution as (2).

This is what visibly breaks the thread into segments: a pet-authored message renders with its
`Nova · Marketing` header, and general narration around it renders with none. Segmentation falls
out of the voice rule rather than needing separate treatment.

## Out of scope

- **Rewriting the eight replies in each pet's voice.** The body of each department reply stays
  exactly as written. This change is structural; making Crash sound blunt about money and Sage
  careful about a person in crisis is content work with its own bilingual cost, and it is
  deliberately deferred. (The eight *questions* added by `.petAsks` are new strings — that is the
  one place new founder-visible prose enters, and it is bounded to one line per department.)
- **Per-department threads.** The sidebar keeps one conversation. Considered and not chosen.
- **The 24-beat tour's own script.** It inherits the header change and nothing else.

## Risks and guards

- **The header change is shared with the tour.** `MockFlowTests` (16/16) and `MockFlowScriptTests`
  (15/15) must stay green; they pin the 24-beat sequence.
- **Duration.** Day one currently runs ~66s. Eight `.petAsks` beats added naively would push it near
  90s. The lever is trimming the existing `.runTask` captions, since the pet's question now carries
  what narration was explaining. Net duration must be **measured, not assumed**, with a target of
  ≤75s — and the readability assertion re-run, since a shortened caption still has to clear it on
  Slow.
- **Bilingual.** The eight questions are new founder-visible strings and need Vietnamese. Every
  string added this week is bilingual; an English-only credit line was a finding on 5 Sep.
- **`DemoProjectParityTests` stays load-bearing.** Any task title a reply bolds must exist on that
  project's own board. A pet asking about a task on the wrong board is exactly what it catches.
- **A pet with no department, and a department with no pet.** `taskSpecialist` returns nil when
  `task.dept` is nil or unmapped. That nil must fall through to the no-header state rather than to
  a "Codepet" row — the same branch, reached honestly.

## Success criteria

1. Playing day one, every departmental reply is headed with its pet and department.
2. No reply anywhere is headed "Codepet".
3. A general reply renders as prose with no speaker row.
4. The chapter bar lists the opener plus eight departments.
5. The full suite stays green, and day one's measured duration is recorded rather than estimated.
