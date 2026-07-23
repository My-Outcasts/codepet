# First-run chat greeting — design

**Date:** 2026-07-23
**Status:** approved (design)
**Scope:** native port of the web `greetFirstRun` (lib/store.tsx + lib/onboarding/firstRun.ts)

## Goal

When a founder finishes onboarding, the companion should open the conversation by
greeting them **by name**, naming the single best first move, and offering a one-tap
**"Do it with me: {task}"** action that runs the task and drops an inline draft
deliverable (Approve/Redo) into the thread. This is the onboarding→activation bridge
the web ships; native currently ends onboarding at a silent, generic empty-state.

Full parity (greeting **and** the inline action) was chosen over a text-only greeting.

## Background / current state

- **Web** (`lib/store.tsx` `greetFirstRun`, `lib/onboarding/firstRun.ts`
  `buildFirstRunGreeting`): `finishOnboarding(brief)` opens the Copilot and seeds a
  byte message. The greeting text names the best first move (from `nextStep`); the
  message carries an inline `action` (`Do it with me: {taskTitle}`) that produces the
  deliverable in-thread. A no-`nextStep` variant is a warm text-only greeting.
- **Native today**:
  - `CopilotChatView.greeting` (Views/Copilot/CopilotChatView.swift:86) is a *static
    empty-state* — a generic "Welcome, {founder}…" + quick-start chips, shown only
    while `chatMessages.isEmpty`. Not a real message; no next-step, no action.
  - `CopilotMessage` (Models/CopilotMessage.swift) is session-only, has `draft` /
    `draftApproved`, but **no action field**.
  - `RoadmapEngine.nextStep(_ tasks:) -> RoadmapTask?` (Models/RoadmapEngine.swift:27)
    is the pure beacon picker — the native equivalent of the web `nextStep`.
  - `CompanyStore` already has the run path: `runRequest(for:language:)`,
    `taskRunner`, `buildDeliverable(from:task:)`, `runningTaskIds`, and the 6C inline
    draft-card flow (`CopilotBubble.draftCard`).
  - Onboarding completes via `OnboardingView.finishWithCompanion` →
    `CompanyStore.finishOnboarding(brief:token:)`. Skip uses a separate
    `skipOnboarding()` (no brief → no greeting, matching web).
  - The Copilot panel defaults **open** (`AppShellView.copilotCollapsed = false`), so a
    seeded message is visible immediately — native needs no explicit "open chat" step.

## Design

### 1. `FirstRunGreeting` model + pure builder (new)

New file `Models/FirstRunGreeting.swift`. Verbatim-logic port of web `buildFirstRunGreeting`.

```
struct FirstRunAction: Equatable { let taskId: String; let taskTitle: String }
struct FirstRunGreeting: Equatable { let text: String; let action: FirstRunAction? }

enum FirstRunGreetingBuilder {
    static func build(brief: CompanyBrief, nextStep: RoadmapTask?, language: AppLanguage) -> FirstRunGreeting
}
```

- `who` = trimmed `brief.founderName`; `proj` = trimmed `brief.projectName` or a
  localized "your product".
- Lead: `"{who}, your company for {proj} is ready."` / `"Your company for {proj} is ready."`
- No `nextStep`: lead + a warm "take a look around … I'll produce the work with you"
  line (department wording softened for native's phase/department model). `action = nil`.
- With `nextStep`: lead + `The best first move is "{title}". Want me to do it with you,
  right here? I'll draft it and you approve — nothing ships without your say-so.` and
  `action = FirstRunAction(taskId: task.id, taskTitle: task.title)`.
- English + Vietnamese. Pure, no I/O — unit-tested.

### 2. `CopilotMessage` — additive action field

Add to `CopilotMessage`:
```
var firstRunAction: FirstRunAction? = nil
var actionConsumed: Bool = false
```
Purely additive (defaults keep every existing construction site and Equatable intact).
Only the seeded greeting sets `firstRunAction`.

### 3. `CompanyStore.seedFirstRunGreeting()`

Appends the greeting as one companion message. Called at the **end of
`finishOnboarding`** (after `isOnboarding = false`), so it only fires on the
finish-with-brief path — skip (`skipOnboarding`) never greets, matching web.

```
private func seedFirstRunGreeting(language: AppLanguage) {
    guard companyId != nil else { return }
    let next = RoadmapEngine.nextStep(company.tasks)
    let g = FirstRunGreetingBuilder.build(brief: company.brief, nextStep: next, language: language)
    chatMessages.append(CopilotMessage(role: .companion, text: g.text, firstRunAction: g.action))
}
```

- Once-only by construction (finishOnboarding runs once at the onboarding→app edge).
- `finishOnboarding` gains a `language:` argument (default `.en`) so the greeting is
  localized; `OnboardingView.finishWithCompanion` passes the live UI language. The
  onboarding flow is English-only today, so `.en` is the effective value.

### 4. `CompanyStore.runFirstRunAction(messageId:language:)`

Runs the greeting's task and appends an inline draft — reuses the existing path, no
new run machinery.

```
func runFirstRunAction(messageId: String, language: AppLanguage) async {
    guard let i = chatMessages.firstIndex(where: { $0.id == messageId }),
          let action = chatMessages[i].firstRunAction,
          !chatMessages[i].actionConsumed,
          let task = company.tasks.first(where: { $0.id == action.taskId }),
          !runningTaskIds.contains(task.id) else { return }
    chatMessages[i].actionConsumed = true          // hide the button (optimistic, idempotent)
    runningTaskIds.insert(task.id)
    let cid = companyId
    let result = await taskRunner(runRequest(for: task, language: language))
    runningTaskIds.remove(task.id)
    guard companyId == cid else { return }          // account-switch guard
    if let draft = buildDeliverable(from: result, task: task) {
        chatMessages.append(CopilotMessage(role: .companion, text: "", draft: draft))
    } else {
        // honest fail-open, mirroring runTask's existing copy
        chatMessages.append(CopilotMessage(role: .companion,
            text: language == .vi ? "Không tạo được ngay bây giờ — thử lại nhé."
                                  : "Couldn't generate that just now — try again."))
    }
}
```

- In-flight guard via `runningTaskIds`; fail-open honest message on nil result.
- Draft appended as a **new** message (matches web "in-thread"); Approve/Redo use the
  existing `approveDraft` / `redoDraft`.

### 5. `CopilotBubble` — render the action button

When `message.firstRunAction != nil && !message.actionConsumed`, render a
"Do it with me: {taskTitle}" button below the greeting text that calls
`runFirstRunAction`. Once consumed, the button is gone (the produced draft card stands
in its place further down the thread). Existing text/draft rendering is untouched.

## Data flow

```
finishOnboarding(brief, language)           // isOnboarding = false, then:
  └─ seedFirstRunGreeting(language)          // append companion greeting (+ action)
gate → AppShellView, Copilot open           // greeting visible
user taps "Do it with me: {task}"
  └─ runFirstRunAction                        // run task, append draft card, consume action
user Approve → approveDraft → Library         // existing 6C path
```

## Edge cases

- **No open task** (`nextStep == nil`, e.g. scaffold failed / CF undeployed): text-only
  greeting, no action button. Honest, never a dead button.
- **Run fails** (nil result): honest fail-open companion message; task left as-is.
- **Account switch mid-run**: `companyId` guard drops the stale draft; hydrate/reset
  already clear `chatMessages`.
- **Double-tap**: `actionConsumed` set optimistically + `runningTaskIds` guard.
- **Returning users**: no onboarding → no greeting; the generic empty-state greeting
  still covers an empty session. Unchanged.

## Non-goals

- Persisting the greeting across sessions (native Copilot chat is session-only today).
- Replacing the generic empty-state greeting.
- The async "authored fallback → byte's own pick" upgrade the web does (native
  `nextStep` is a synchronous pure function — no upgrade step needed).

## Testing

- **Unit** (`FirstRunGreetingTests`): the pure builder across name/no-name ×
  nextStep/no-nextStep × EN/VI — asserts lead text, best-first-move sentence, and
  `action` presence/contents.
- **Build-verify**: store + `CopilotBubble` wiring compiles; manual/visual check of the
  greeting + action → draft flow (runtime needs a signed build; verified visually).

## Files touched

- `Models/FirstRunGreeting.swift` (new)
- `Models/CopilotMessage.swift` (add `firstRunAction`, `actionConsumed`)
- `Managers/CompanyStore.swift` (`seedFirstRunGreeting`, `runFirstRunAction`,
  `finishOnboarding` language arg)
- `Views/Onboarding/OnboardingView.swift` (pass language to `finishOnboarding`)
- `Views/Copilot/CopilotChatView.swift` (`CopilotBubble` action button)
- `codepetTests/FirstRunGreetingTests.swift` (new)
