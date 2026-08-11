# Every reply carries its own action row

**Date:** 2026-08-11
**Status:** design approved, not yet planned
**Branch:** `feat/message-action-row` (off `main`)

## The problem

The founder's reading of the app is that Codepet's chat has none of the per-message
affordances both references put under an answer — copy, retry, feedback, a timestamp.

That reading is right about the experience and wrong about the code, and the difference
is the whole design. `messageActions` exists at `Views/Copilot/CopilotChatView.swift:639-671`
and already draws copy, retry, and a relative timestamp. Two things make it unreachable:

1. **The hover target is the invisible row itself.** `.onHover { hovering = $0 }` (`:670`)
   is attached to the same view held at `.opacity(hovering ? 1 : 0)` (`:668`). Hovering the
   message does nothing; you have to find a blank 22×20pt strip below the prose. Nothing is
   pinned, so there is no first sighting that teaches the strip exists.
2. **The row is scattered, not universal, and mostly buried mid-card.** `messageActions`
   appears exactly once, at `:1035`, inside the assistant branch of `textBubble`. Four
   card-bearing branches of `body` (`:498-548`) — a Virtual Company room, a first-run
   greeting action, a run proposal, a roadmap proposal — render `textBubble` INSIDE their
   own card, so each already gets a row wherever `text` is non-blank, which it always is at
   their construction sites. It is just nested under that card's own button rather than at
   the reply's own top level. Only three branches (verified against `git show
   9b2783d:codepet/Views/Copilot/CopilotChatView.swift`) truly render no row at all: a
   deliverable draft, the producing exec log, and an interview — plus the standalone
   nav/setup/noted chips, which render only when `text` is blank and so never reach
   `textBubble`. These are the replies most worth rating and copying either way: a row
   nested one card deep is still gated by problem 1's invisible strip, and still isn't the
   universal, pinned row the founder is asking for.

Two adjacent facts, both established by reading the current tree rather than inferred:

- **Thumbs are not blocked.** The doc comment at `:630-634` says thumbs need "a `feedback`
  collection and a Firestore rule that do not exist natively yet." Both exist.
  `Models/FeatureFeedbackManager.swift:157` already writes `db.collection("feedback")`, and
  `firestore.rules:37-43` allows `create` for any payload with `rating` an int in `1...5` and
  `feature` a string, with no field whitelist. A thumb fits that shape with no rule change
  and no deploy.
- **Retry is destructive.** `CompanyStore.retryReply` (`Managers/CompanyStore.swift:1262-1281`)
  walks back to the preceding `.me` message and calls `chatMessages.removeSubrange(askIndex...)`
  — it drops the question and every turn after it. Harmless everywhere it already rendered —
  not just on "plain-text replies," but on the four card branches above too — because the row
  was `.opacity(0)` with a blank 22×20 hover target on every one of them alike; pinning it and
  widening the hover target is what turns that latent risk live across all seven branches at
  once, not something introduced fresh by extending coverage to the three that had nothing.

## What we are building

One action row, built one way, under every assistant reply:

```
⧉ Copy   ⇪ Copy as Markdown   ↻ Try again   👍   👎        2m ago
```

Hover-reveal on the whole message, with the last reply pinned. Copy reads the payload the
reply actually rendered rather than a `text` field that is often blank on a card. Thumbs
write to the `feedback` collection that is already live. Retry is confined to the last reply
so that what it deletes is what it looks like it deletes.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Which actions | Copy, Copy as Markdown, Try again, 👍/👎, timestamp | The founder's pick. Sources was considered and dropped — no message in the model carries citations |
| Which roles | Assistant replies only | Matches both references; copy/retry/feedback are meaningless on your own words |
| Visibility | Hover-reveal, last reply pinned | Keeps the transcript quiet per the minimalist north-star, while the reply you are reading always shows its actions and teaches the affordance |
| Coverage | Every assistant branch, not just `textBubble` | The card replies are the ones worth rating; a thumbs-down you cannot give on a bad draft is the gap |
| Share | Copy as Markdown | No new OS surface, works offline, one code path, and the paste target is Notion or a PR |
| Retry scope | Last reply AND a non-blank `founderAsk` | "Newest message" is not the same claim as "answer to the founder's last ask" — roughly 15 store paths append a companion message with no ask before it. `isLast` alone makes `removeSubrange(askIndex...)` drop the wrong turn on those; gating on `founderAsk` too makes it drop exactly the last question and its answer, on every message where retry is offered. No store change, no confirm modal in a quiet row |
| Vote storage | Existing `feedback` collection | Rule already permits the shape; a new `FeedbackFeature` case keeps thumbs out of the existing `companionChat` 5-face stats |

## Architecture

### `CopilotBubble` splits into wrapper and content

The if-chain currently in `body` (`:498-548`) moves verbatim to a private `content`
property. `body` becomes the wrapper that owns the row:

```swift
var body: some View {
    if isMe || message.producing {
        content                                    // your own words; and never mid-work
    } else {
        VStack(alignment: .leading, spacing: ChatRhythm.proseToAction) {
            content
            messageActions
        }
        .onHover { hovering = $0 }                 // the whole reply, not the strip
    }
}
```

The `messageActions` call is deleted from `textBubble` (`:1035`), which is what makes the row
universal instead of per-branch. `.onHover` moves off `messageActions` (`:670`) and onto the
wrapper — the fix for problem 1.

`CopilotBubble` gains `let isLast: Bool`. The `ForEach` at `:210` is already enumerated (for
`ChatRhythm.extraGap`), so the call site at `:212` passes `index == messages.count - 1` with
no restructuring.

`messageActions` keeps `actionIcon(_:help:action:)` (`:673-684`) unchanged, so the new buttons
inherit the dock's 11pt-in-22×20 sizing, `.buttonStyle(.plain)`, and `.help(...)` tooltips.
Visibility becomes `.opacity(hovering || isLast ? 1 : 0)` — still opacity rather than a
conditional, so the row's height never changes under the cursor.

New SF Symbols: `square.and.arrow.up`, `hand.thumbsup`, `hand.thumbsdown`, alongside the
existing `doc.on.doc` and `arrow.clockwise`.

### `Models/MessageTranscript.swift` — new, pure

```swift
enum MessageTranscript {
    static func plain(_ m: CopilotMessage, lang: AppLanguage) -> String
    static func markdown(_ m: CopilotMessage, speaker: String, lang: AppLanguage) -> String
}
```

No SwiftUI, no Firebase. This is the reason coverage matters: on a draft-card reply
`message.text` is frequently blank, so today's `setString(message.text, ...)` (`:643`) would
hand the founder an empty clipboard the moment the row appears on that branch. The serializer
reads the payload the branch actually rendered, in the same precedence order as `content`:

| Payload | `plain` yields | `markdown` adds |
|---|---|---|
| `drafts` | each draft's heading, then its body | heading as `### heading` |
| `draft` | title, then body | `## title` |
| `vcRun` | the recommendation | per-seat `**dept** — position` |
| `execSteps` | the step list | steps as `- [x]` items |
| `runProposal` / `roadmapProposal` | the sentence, **only when `text` is blank** | nothing beyond the speaker line |
| `interview` | the question, **only when `text` is blank** | nothing beyond the speaker line |
| otherwise | `text` | `text` |

`markdown` prefixes a `**speaker**` line using the bubble's existing `headerName` (`:486-492`),
so a specialist reply pastes as `**Glitch · Engineering**`. Where a branch carries both text and
a payload (the `vcRun` and `firstRunAction` branches render `textBubble` plus a card), both are
serialized, text first, matching what is on screen.

**The last three rows are fallbacks, not additions,** and that distinction is the difference
between a correct clipboard and a doubled one. At every site that builds those three messages
the payload's own sentence already IS `message.text` — `CompanyStore.proposeRun` (`:1940`)
constructs `text: proposal.line(language)`, `handleRoadmapProposal` (`:1550`) assigns
`chatMessages[i].text = proposal.line(language)`, and `askInterviewGap` (`:346`) constructs
`text: q.ask`. Appending the line unconditionally therefore prints it twice. Worse for
`roadmapProposal`: when the model wrote its own prose, `text` keeps that prose and the card
shows only the prose, so an unconditional append would inject a sentence that was never on
screen at all. `draft` and `vcRun` do **not** take the fallback rule — they are built with
`text: ""` or with genuinely additional prose, and their payload really is separate content.

Two rows deliberately claim less than an earlier draft of this table did. A draft body is
**not** fenced: `DeliverableKind` cannot distinguish prose from code, and guessing would
corrupt prose. A room has **no** `## title`: no title field exists on `VCBrief` or
`VirtualCompanyRunState`.

Plain `Copy` switches from raw `message.text` to `MessageTranscript.plain(message)`. The
existing 1.4s "Copied" / "Đã sao chép" acknowledgement (`:650-658`) is reused for both copy
buttons, with a distinct label for the Markdown one.

### `Models/MessageFeedbackService.swift` — new

One thumb writes one document to `feedback`:

```
feature:     "chatMessage"
rating:      5 (up) | 1 (down)
messageId:   message.id
threadId:    the active ChatThread id
companionId: message.companionId       (omitted when nil)
deptName:    message.deptName          (omitted when nil)
```

plus the identity and version fields `FeatureFeedbackManager.submit` already sends —
`userId`, `authMethod`, `displayName`, `pet`, `appVersion`, `build`, `platform: "macos"`,
`timestamp: FieldValue.serverTimestamp()` — and the same
`!AppEnvironment.isRunningTests && !ServerLoggingGate.isOptedOut` gate, so tests and
opted-out founders write nothing.

It is a separate call rather than a reuse of `submit` for two reasons: `submit` is welded to
the once-ever toast flow and ends in `dismiss()`, and it takes `authManager`/`appState`
directly. `FeedbackFeature` gains a `chatMessage` case, which keeps per-message thumbs from
polluting the existing `companionChat` 5-face statistics. That case is never surfaced in
`FeatureFeedbackToast` — it exists for the `rawValue` and for `allCases` bookkeeping.

`rating` deliberately reuses the 1–5 int the rule already validates rather than a new boolean
field, because the rule cannot be relaxed without a deploy and a boolean would fail
`request.resource.data.rating is int`.

### Vote state

`CopilotMessage` gains `var vote: MessageVote?` (`enum MessageVote { case up, down }`), set via
a new `CompanyStore.recordVote(messageId:vote:)` that mutates the message in `chatMessages` and
fires the Firestore write. It lives on the model, not in `@State`, because SwiftUI drops view
state as rows recycle during scrolling and the founder would watch their vote disappear.

The chosen thumb renders filled (`hand.thumbsup.fill`) in `CodepetTheme.accentTeal`; the other
stays enabled so a misclick is correctable. Because `firestore.rules:42` denies `update`, a
correction writes a second document with the same `messageId` — latest `timestamp` wins on
read. This is stated here so nobody later reads duplicate `messageId`s as a bug.

`CopilotMessage` is session-only and not `Codable` (`Models/CopilotMessage.swift:8`), so the
*filled thumb* resets on relaunch. The vote itself is already durable in Firestore. Persisting
the transcript is out of scope.

### Retry

```swift
let retryEnabled = MessageActionRules.canRetry(isLast: isLast,
                                               isTyping: companyStore.isCompanionTyping,
                                               isStreaming: companyStore.isStreaming,
                                               isFanningOut: companyStore.isFanningOut,
                                               founderAsk: message.founderAsk)
...
.disabled(!retryEnabled)
```

`isLast` alone is not "answers the founder's last ask" — that assumption is false whenever a
store path appends a companion message with no ask before it (a Roadmap "Run" proposal, a
finished run's draft, a fan-out row, byte's first-run greeting, ...): roughly 15 such paths
exist, each becoming the newest message in turn. Retry offered on one of those deletes
whatever question and answer actually preceded it, several turns back, then re-asks it and
spends credits on a question nobody just asked.

`canRetry` adds a fourth gate, `founderAsk` (`CopilotMessage.founderAsk`) — non-nil only on
the reply `CompanyStore.sendChat` produced for a typed ask, stamped there and nowhere else.
With retry confined to `isLast && isFanningOut == false && a non-blank founderAsk`,
`removeSubrange(askIndex...)` removes exactly the founder's last question and its answer,
which is what a retry button under the last answer visibly promises. `CompanyStore.retryReply`
itself is otherwise unchanged; the added guard lives entirely in `canRetry` and in the
`founderAsk` stamped by `sendMessage`.

## Testing

`MessageTranscript` is pure, so it runs without the Firebase test host that flakes on
`@MainActor ObservableObject` deallocation (`CLAUDE.md` landmine 3):

- One case per payload branch of `plain` and `markdown`.
- **A draft with blank `text`** — the specific bug the serializer exists to prevent. Asserts
  the clipboard string is non-empty and contains the deliverable title.
- A `vcRun` reply asserts both the handoff line and the synthesis appear, in that order.
- `markdown` on a specialist reply asserts the `**Name · Dept**` speaker line.

Per the repo's working agreement that a guard needs a test that goes red when the guard is
deleted:

- **Retry guard:** a test asserting `retryReply` is unreachable for a non-last message —
  red if `!isLast` is dropped from `.disabled`.
- **Rule/writer drift:** a test asserting the payload `MessageFeedbackService` builds
  satisfies the rule's predicate (`rating` is an `Int` in `1...5`, `feature` a non-empty
  `String`) — red if someone switches `rating` to a `Bool` or empties `feature`, which would
  otherwise fail silently at the Firestore boundary in production.

Run per-suite with `-only-testing:` as the landmine requires. The action row's visual
behaviour is not machine-verifiable here (Screen Recording is denied on this machine), so
hover, pinning, and the filled-thumb state are a founder-verification handoff on a
team-signed build.

## Out of scope

- **Sources / grounding.** Not picked, and no field in `CopilotMessage` carries citations —
  it would need a backend contract change first.
- **Thread-level Share.** It does not exist. The chat header (`:95-126`) has exactly two
  buttons, collapse and history, and `ThreadListView`'s per-thread menu (`:418-435`) has only
  Rename and Delete. Worth building; not this.
- **Read aloud.** The second reference has it; Codepet has no speech path.
- **A markdown renderer for the transcript.** Chat text is rendered literally today
  (`AISettingsPanel.swift:6`). `MessageTranscript` writes markdown to the clipboard; it does
  not change what is drawn on screen.
- **Persisting the transcript.** Would make timestamps and thumb state survive relaunch, and
  is the natural follow-on, but it is a Firestore schema change of its own.
