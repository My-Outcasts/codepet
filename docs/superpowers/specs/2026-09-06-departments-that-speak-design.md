# Departments that speak, not just departments that are named

**Date:** 2026-09-06
**Status:** Design, awaiting founder review of the copy
**Branch:** `feat/pet-voice-and-department-segments`

## Why this exists

The founder audited the shipped work and found it incomplete. She was right, and the gap
was mine.

`MockChat` returns a department's in-character reply **only** when `req.deptKey` is set. The
day-one script never armed a department, so every conversational turn fell through to one
generic default reply — the "your leverage right now is momentum, not polish" text visible in
her first screen recording. Eight per-department replies existed and were unreachable.

`156d185` fixed the wire: a task's department now grounds the turn. But that only reaches the
**one** conversational beat day one contains. The other eight links are `.runTask` beats that
produce an artifact card and say nothing. So the departments are named, and they still do not
speak.

Worse, the existing eight replies cannot simply be reused. They are written against the
**mid-flight** board and each names one of *that* board's open tasks — Marketing offers to
build the landing page "against the brand direction Luna set". On day one none of that exists
yet. `DemoProjectParityTests` would not catch it: it checks a bolded title exists on the
project's board, and day one uses the same task array with `done` cleared, so every title
resolves while the content is temporally wrong.

## What changes

Each department gets **three** speaking beats around its work — it asks, it frames how it will
approach the work, the artifact is produced and filed, and then it reports what it found and
hands to the next department.

```
● Crash · Finance        asks     "What does that cost you a month?"
● Crash · Finance        frames   "I couldn't have answered this an hour ago…"
  □ Cost per active user           ✓ filed
● Crash · Finance        reports  "Sixty cents. Sage is next…"
```

Sixteen new beats across eight departments, on top of the eight `.petAsks` already shipped.

**Marketing holds two links** (the interviews and the landscape scan). It frames once before its
first link and reports once after its second — framing is per *department*, not per link.

### The intent

`.petAsks(deptKey:)` is replaced by `.petSays(deptKey:line:)` with

```swift
enum Line { case asks, frames, reports }
```

One intent with three lines rather than three intents: the player's handling is identical in
all three cases, and a future fourth line should not need a fourth `case` in a shared enum the
24-beat tour also compiles against.

### The table

`DayOneScript.questions` becomes `DayOneScript.script`, keyed by department, carrying all three
lines:

```swift
static let script: [String: (asks: Line, frames: String, reports: String)]
struct Line { let en: String; let vi: String }   // `asks` only
```

**Founder decision, 6 Sep: the new `frames` and `reports` lines are ENGLISH ONLY.** The eight
`asks` questions keep the bilingual `Line` they already ship with — they exist, and two of them
were corrected by review, so there is nothing to gain by removing working translated copy.

The consequence, stated plainly rather than discovered on screen: a founder running the demo in
Vietnamese will see each department's **question in Vietnamese and its framing and report in
English**. That is a mixed-language demo. It is the direct cost of not writing sixteen more
Vietnamese strings, and it is accepted. The Vietnamese drafts below are kept as reference for
whenever someone wants to finish them; they are NOT being built now.

**The two existing reply tables are NOT migrated.** `DemoProjectCodepetReplies` and
`DemoProjectMurrorReplies` stay `[String: String]` and English-only. Migrating them would mean
inventing sixteen unreviewed Vietnamese strings; two of the last three Vietnamese phrases
written for this branch were wrong (`giữ lời` reads as "keep a promise", `đừng thứ Sáu` is
ungrammatical) and were caught only by a human reading them. Recorded as a known follow-up
needing a native read, not silently absorbed.

### The budget

Day one goes from **74.6s** to roughly **115s**. The ≤75s assertion is replaced with **≤120s** —
chosen deliberately with headroom, not fitted to the result. Day one has no shared ceiling with
the 24-beat tour, so this does not touch that script's own budget.

## The copy

**English is what gets built.** The Vietnamese under each line is a DRAFT kept for reference and
is NOT being implemented — see the founder decision above. Do not transcribe it into code.

### Marketing · Nova — interviews, then the landscape scan

**frames**
> The first one is yours — twelve conversations I can't have for you. Once you've had them,
> I'll scan what's already out there and tell you where those apps stop.

> Cuộc đầu tiên là của bạn — mười hai cuộc trò chuyện tôi không thể thay bạn thực hiện. Khi bạn
> đã nói chuyện xong, tôi sẽ rà soát những gì đang có ngoài kia và chỉ ra chúng dừng lại ở đâu.

**reports**
> Twelve conversations and a scan, and they agree: every app in this category ends with someone
> understanding themselves alone. That's the gap. Now the harder question — and it's still me asking it.

> Mười hai cuộc trò chuyện và một lượt rà soát, và chúng đồng ý với nhau: mọi ứng dụng trong
> nhóm này đều kết thúc ở chỗ người dùng hiểu chính mình một mình. Đó chính là khoảng trống.
> Giờ đến câu hỏi khó hơn — và vẫn là tôi hỏi.

### Sales · Nova — who it is not for

**frames**
> Same voice, different job. Marketing found who this is for; Sales has to find who it isn't,
> and be specific enough that it stings.

> Vẫn là tôi, nhưng công việc khác. Marketing tìm ra sản phẩm dành cho ai; Sales phải tìm ra nó
> KHÔNG dành cho ai, và cụ thể đến mức hơi nhói.

**reports**
> One of your twelve found it insulting. That's the most useful sentence in the file — it's what
> stops outreach spending its best hours in the wrong places. Luna's turn: now we know who, she
> can decide how it feels.

> Một trong mười hai người thấy bị xúc phạm. Đó là câu hữu ích nhất trong hồ sơ này — nó giữ cho
> việc tiếp cận không tiêu những giờ tốt nhất vào sai chỗ. Đến lượt Luna: đã biết dành cho ai,
> giờ mới quyết được cảm giác của nó.

### Design · Luna — what it should feel like

**frames**
> I've read the interviews and the disqualifier list. Feeling comes last, not first — I can only
> shape it once I know who it's for and who it isn't.

> Tôi đã đọc các cuộc phỏng vấn và danh sách những người không phù hợp. Cảm giác đến sau cùng,
> không phải đầu tiên — tôi chỉ định hình được khi đã biết nó dành cho ai và không dành cho ai.

**reports**
> Soft, quiet, unhurried — and never graded. Naming a feeling must not feel like being marked.
> Byte next: someone has to decide what this actually runs on.

> Nhẹ, tĩnh, không vội — và không bao giờ bị chấm điểm. Gọi tên một cảm xúc không được giống như
> bị đánh giá. Tiếp theo là Byte: phải có người quyết định thứ này chạy trên nền tảng gì.

### Engineering · Byte — what to build it on

**frames**
> Direction's set, so I can pick a stack. The question that matters isn't the framework — it's
> whether anything a person writes ever leaves their device.

> Đã có định hướng nên tôi chọn được nền tảng. Câu hỏi quan trọng không phải là framework nào —
> mà là những gì người ta viết có bao giờ rời khỏi máy của họ không.

**reports**
> On-device where it can be, and nothing leaves with a name attached. That decision sets your
> running cost, which is why Crash goes next and not first.

> Xử lý ngay trên máy khi có thể, và không gì rời đi kèm theo tên. Quyết định đó định ra chi phí
> vận hành, và đó là lý do Crash đi sau chứ không đi đầu.

### Finance · Crash — what it costs

**frames**
> I couldn't have answered this an hour ago. Pricing needs a stack — now Byte's chosen, I can put
> a number on it.

> Một giờ trước tôi chưa trả lời được câu này. Muốn tính giá thì phải có nền tảng — giờ Byte đã
> chọn xong, tôi đặt được con số.

**reports**
> Sixty cents a month per active user, at your numbers, on Byte's stack. Charge four dollars and
> you can breathe. Sage is next, and hers is the question a product about loneliness cannot dodge.

> Sáu mươi xu mỗi tháng cho mỗi người dùng hoạt động, theo số liệu của bạn, trên nền tảng Byte
> chọn. Thu bốn đô la là bạn thở được. Tiếp theo là Sage, và câu của cô ấy là câu mà một sản phẩm
> về sự cô đơn không thể né.

### Support · Sage — a bad night

**frames**
> I want to be careful here. Someone struggling at 2am doesn't need a chatbot being clever, and
> what the app says then has to be written down, not improvised.

> Chỗ này tôi muốn cẩn thận. Người đang khủng hoảng lúc 2 giờ sáng không cần một con bot tỏ ra
> thông minh, và những gì ứng dụng nói lúc đó phải được viết sẵn, không phải ứng biến.

**reports**
> What it says, when it says it, and what it refuses to handle — written as policy rather than
> left to a prompt. Glitch reads this next: holding those words is a legal question too.

> Nói gì, nói khi nào, và từ chối xử lý những gì — viết thành chính sách chứ không phó mặc cho
> một câu lệnh. Glitch sẽ đọc phần này: lưu giữ những lời đó cũng là một vấn đề pháp lý.

### Legal · Glitch — the deletion promise

**frames**
> I've read Sage's policy. People are typing the most private thing they have into this, so the
> deletion promise has to be plain language first and paperwork second.

> Tôi đã đọc chính sách của Sage. Người ta gõ vào đây điều riêng tư nhất họ có, nên lời hứa về
> việc xoá dữ liệu phải là ngôn ngữ dễ hiểu trước, giấy tờ sau.

**reports**
> One tap and it's gone. No confirmation email, no support ticket, no "are you sure" chain
> designed to make you give up. Same voice for the last one: shipping this without breaking it.

> Một chạm là mất hẳn. Không email xác nhận, không phiếu hỗ trợ, không chuỗi "bạn có chắc không"
> dựng ra để bạn bỏ cuộc. Vẫn giọng này cho câu cuối: phát hành mà không làm hỏng.

### Operations · Glitch — the release rhythm

**frames**
> Still me. Legal was about what you owe them; Operations is about not breaking it while you keep
> your word.

> Vẫn là tôi. Pháp lý nói về điều bạn nợ họ; Vận hành nói về việc không làm hỏng trong lúc bạn
> giữ lời hứa đó.

**reports**
> Thursday, not Friday — a Friday release means a weekend of nobody watching. That's nine
> questions answered, and the tenth is yours: who do you tell first?

> Thứ Năm, không phải thứ Sáu — phát hành thứ Sáu nghĩa là cả cuối tuần không ai trông. Vậy là
> chín câu hỏi đã có lời đáp, và câu thứ mười là của bạn: bạn sẽ nói với ai đầu tiên?

## Tests

- Every department has all three lines, non-empty. The eight `asks` keep their bilingual guard
  (`en != vi`); `frames` and `reports` are English-only and must NOT gain an empty `vi` slot.
- Ordering per department: `asks` → `frames` → its link(s) → `reports`. A report before its
  work is backwards and must fail.
- Exactly 8 departments speak, each exactly three times.
- Every bolded title in any line exists on the day-one board (extends the existing parity guard
  to the new copy).
- The day's total is ≤120s, and the failure message names the actual number.
- Caption readability still clears at the Slow pace.

## Risks

- **The demo becomes mixed-language in Vietnamese.** Question in Vietnamese, framing and report
  in English. Accepted deliberately; the alternative was sixteen unreviewed Vietnamese strings,
  and two of the last three written for this branch were wrong. Recorded as a follow-up needing
  a native read, not as an oversight.
- Replacing `.petAsks` with `.petSays` churns Task 4's tests. They are ours to update, but a
  count assertion that silently keeps passing on the new case would hide a regression.
- ~115s is a long demo. If it drags on screen, the lever is cutting `frames` — the reports carry
  the chain, the frames carry the reasoning.

---

# Amendment, 6 Sep — the founder asks, the department answers

The founder watched the built version and caught two things. Both are mine.

## 1. The pet was asking the founder's own question

The brief was *"imagine what questions **they** would have when starting a project"* — the
questions belong to the founder. They shipped as pet-authored messages, so Nova asks a question
and then answers it herself. The whole chapter contains exactly one founder message, and it is
the auto-generated `"Walk me through:"` line. That is not a conversation.

**Fix:** the `asks` line posts as the FOUNDER — `role: .me`, no `companionId`, no speaker row,
right-aligned like any other thing the founder types. The pet's `frames` line becomes its
answer. Each segment then reads:

```
                     Is this a real problem, or just mine?   ← founder
● Nova · Marketing   The first one is yours — twelve
                     conversations I can't have for you…     ← Nova answers
  □ artifact                                        ✓ filed
● Nova · Marketing   Twelve conversations and a scan…        ← Nova reports
```

## 2. Day one was serving mid-flight copy

Grounding `dept_key` in the task (`156d185`) made `MockChat`'s department replies reachable —
and `murrorDayOne` borrows `murrorDepartmentReplies`, which is written against the **mid-flight**
board. So the demo showed Marketing saying *"…I will write it against the brand direction Luna
set"* on day one, four segments before Luna speaks. This spec predicted that failure and then
caused it.

**Fix, two parts:**
- `.walkthroughFounderTask` is removed from the day-one script. It was the only beat triggering
  a `MockChat` conversational turn, and it is now redundant: the founder's question and the
  department's answer are both scripted beats. `.recordFounderTask` still files the artifact.
- `murrorDayOne` gets `departmentReplies: [:]`. Belt and braces — if any future beat does trigger
  a chat turn, it must not be able to serve another board's copy.
- A test asserts the day-one script contains **no** beat that triggers a `MockChat` reply, so
  this cannot silently return.

`deptKeyFor` remains correct and valuable — it is what the LIVE hero-card walkthrough button
needs. Day one simply no longer exercises it.

## The eight questions, in the founder's voice

First person, and stripped of the coaching instruction — that content already lives in each
department's `frames` and `reports` lines, so nothing is lost.

⚠ **The Vietnamese below is a rewrite and needs a native read.** These are short first-person
questions rather than the idiom-heavy paragraphs that went wrong before, but two of three
Vietnamese phrases written for this branch were still wrong.

| dept | en | vi |
|---|---|---|
| `mkt` | Is this a real problem, or just mine? | Đây có phải vấn đề thật không, hay chỉ mình tôi thấy vậy? |
| `sales` | So who is this not for? | Vậy sản phẩm này không dành cho ai? |
| `design` | What should it feel like? | Nó nên mang lại cảm giác gì? |
| `eng` | What do I build it on? And does anything people write leave their device? | Tôi nên xây trên nền tảng gì? Và những gì người ta viết có rời khỏi máy của họ không? |
| `fin` | What is this going to cost me a month? | Mỗi tháng cái này sẽ tốn của tôi bao nhiêu? |
| `support` | What happens if someone's really struggling at 2am? | Chuyện gì xảy ra nếu ai đó thật sự khủng hoảng lúc 2 giờ sáng? |
| `legal` | Am I in trouble for holding what people write? | Tôi có gặp rắc rối khi lưu giữ những gì người ta viết không? |
| `ops` | How do I ship this without breaking it? | Làm sao để phát hành mà không làm hỏng nó? |

The `frames` and `reports` copy is UNCHANGED — it already reads as an answer.

## Tests

- The `asks` beat posts with `role: .me` and **no** `companionId`; `frames` and `reports` post as
  the pet. A test that would go red if `asks` regressed to a pet message.
- Day one contains no beat that triggers a `MockChat` conversational reply.
- `murrorDayOne.departmentReplies` is empty, so mid-flight copy cannot reach it.
- Runtime is re-measured, not estimated. Removing `.walkthroughFounderTask` shortens the day.

---

# Amendment 2, 6 Sep — the day needs an opening

The founder watched the built version and objected to the cold start: after onboarding, the
transcript's first line is *"Is this a real problem, or just mine?"* with no context at all.

She also asked whether the flow of the remaining features had been cut back. **A section-by-section
audit says no for departments and yes for surfaces:**

| section | time | beats |
|---|---|---|
| Day one | 3.2s | 1 |
| Marketing · Nova | 15.6s | 6 |
| Sales · Nova | 13.0s | 5 |
| Design · Luna | 12.2s | 5 |
| Engineering · Byte | 12.4s | 5 |
| Finance · Crash | 12.8s | 5 |
| Support · Sage | 13.0s | 5 |
| Legal · Glitch | 13.0s | 5 |
| Operations · Glitch | 17.6s | 7 |

Every department gets the same five beats; Marketing has six because it holds two links and
Operations seven because it carries the ending. No department was trimmed.

**But roughly 104s of 112.8s is chat.** There are two `.go` beats in the whole run, both bolted
onto Operations' chapter at the end: the Library gets ONE beat, then the Roadmap. Tasks, Company
and Environment are never visited. Nine artifacts are produced and the place they live is a
single passing beat inside another department's section.

**Founder decision: the Library moment is NOT being added now.** Recorded as a known gap, not an
oversight.

## The opening

Four new beats in the `Day one` chapter, after the existing `.hold`. English only, consistent
with `frames`/`reports`.

The three Codepet lines are the PRODUCT speaking, so they render as bare prose with **no speaker
row** — that is the rule already shipped, not an exception. Only the founder's reply is
right-aligned.

**summary** (host)
> Here's what I have so far: Murror — an app for people who feel lonely and don't know how to
> reach each other. That came from onboarding, and it's all I know. No plan, no brand, no users.

**prompt** (host)
> Before I bring in the departments — tell me anything else that matters. Who is it for, what
> have you tried, what worries you?

**founderReply** (founder, `role: .me`)
> It started because I couldn't tell anyone I was lonely without it sounding like a crisis. I
> want something that helps people say the small version out loud.

**setup** (host)
> That's the thing to protect. Eight departments, nine questions — I'll bring each one in as it
> becomes answerable, and you approve everything before it's filed.

## The intent

`.opening(OpeningLine)` where `enum OpeningLine { case summary, prompt, founderReply, setup }`.
The player posts `summary`, `prompt` and `setup` with no `companionId` (product voice, no row)
and `founderReply` with `role: .me`.

Kept separate from `.petSays` because these lines belong to no department, and giving them a
`deptKey` would be a lie the header rule would then have to special-case.

## The budget

Roughly +14s, taking the day to about **127s**. The ceiling moves from 120s to **140s** —
deliberate headroom, not fitted to the result.

This is the third raise: 75 → 120 → 140, against a ceiling a previous author set at 90s with the
note *"a Ns simulation is one nobody watches twice."* The founder has been told twice and has not
asked for it shorter. Recorded so the next person sees the trend rather than just the number.

## Tests

- The three host lines post with NO `companionId` and NO `deptName`; `founderReply` posts with
  `role: .me`. Must go red if any of them regresses to a pet message.
- The opening plays before any department speaks.
- Runtime re-measured, read out of a failing assertion, not estimated.

---

# Amendment 3, 6 Sep — the environment, the code, and a slimmer bar

## Audit answer

Confirmed: the day-one flow ends at the roadmap reveal. 48 beats — chat for nine segments, one
Library beat, then Roadmap. **`AppView.environment` and the Developer (CODE) mode are never
visited.**

## Why these two belong together

`Views/Environment/` holds `ProjectLinker.swift`. **Linking a project folder is the real
prerequisite for a code run** — without one, `startBuild` lands in `.noProject` and refuses.
So Environment is not a decorative extra stop before Code; it is the thing that makes Code
possible.

That satisfies the founder's constraint that *whatever runs in the prototype should also work in
actual use*: the demo shows the real precondition rather than a build that works by magic and
then fails for a real founder who never linked anything.

Both sections use existing, real mechanisms — nothing mimed:
- `.go(.environment)` — a real destination
- `.mode(.developer)` — already used by the 24-beat tour ("Your company touches your code")
- `MockEngineeringRunner` — drives the same `EngineeringRunStore` the live runner does, with no
  credits and no network. Endings: `finishes`, `pausesAgain`, `failsAtBudget`.

## Placement

The existing roadmap beat already hands off into this: *"the beacon has moved to her tenth
question — how people hear about it. Codepet points at the landing page and waits."*

```
Operations reports → Library (nine artifacts) → Roadmap (beacon → landing page)
                                                        ↓
                     Environment · Byte    link the folder, choose the tools
                                                        ↓
                     Code · Byte           the landing page actually gets built
                                                        ↓
                     Roadmap               ten questions in, the board has moved
```

**Byte carries both.** It chose the stack four questions earlier, so it is the voice that knows
what the environment needs and what the first code should be. Continuity, not a new cast member.

## The copy — English only, per the founder's standing decision

### Environment · Byte

**asks** (founder)
> What do I need set up before any of this can run?

**frames** (Byte)
> I picked the stack four questions ago. Before I can touch code, this company needs a folder to
> work in — and you decide which tools it is allowed to use.

**reports** (Byte)
> Linked. Three tools on, the rest off until they earn it. Nothing here needs a card yet.

### Code · Byte

**asks** (founder)
> Can you build the landing page?

**frames** (Byte)
> That is the beacon's tenth question — how people hear about it. I work on your machine, I show
> you every change, and nothing is saved until you say so.

**reports** (Byte)
> One page, Luna's direction, Nova's positioning line. A draft until you approve it — same as
> everything else today.

### Closing beat

> Ten questions in, and the board has moved.

## Runtime

Roughly +30s, taking the day to about **157s**. The ceiling would move 140 → 170.

**This is the fourth raise (75 → 120 → 140 → 170) against a prior author's 90s ceiling whose note
read "a Ns simulation is one nobody watches twice."** The lever that has been offered three times
and not taken: cutting the eight department `frames` lines returns ~25s and lands at ~132s. The
founder keeps the questions, the artifacts, the reports and the handoffs; she loses each
department's reasoning about why it goes when it does. **Not doing this unless she says so** —
it is her copy.

## The bottom bar

`codepet/Demo/MockFlowCaptionBar.swift` — three stacked rows (caption, nine chapter chips,
controls), ~145px, and the chip row wraps.

**Founder decision: fold the chapters into the controls.** The chips row is deleted. The current
chapter and position become one compact label inside the control bar, and clicking it opens a
menu to jump to any chapter. Saves a row, keeps every capability, and stops the row wrapping as
sections are added — which matters immediately, since this amendment adds two.

## Tests

- The environment beat navigates to `AppView.environment`; the code beat enters `.developer`
  mode. Both must go red if the destination changes.
- The code run uses `MockEngineeringRunner` — no network, no credits.
- Chapter jumping still works with the chips row gone: `firstBeat(of:)` still resolves every
  chapter, and a test pins the chapter list.
- Runtime re-measured, read out of a failing assertion.
