// codepet/Services/MockChat.swift
#if DEBUG
import Foundation

/// Dev-only chat stub. When the `CODEPET_MOCK_CHAT` flag is set (launch arg
/// `-CODEPET_MOCK_CHAT YES` or the UserDefaults key), `CompanyChatClient` and
/// `RunTaskClient` short-circuit to canned local responses — so the whole
/// redesigned chat experience (streaming orb, un-bubbled messages, thumbs,
/// run→produce→approve cards, nav/setup/remember chips) can be exercised with
/// ZERO Anthropic spend.
///
/// Compiled ONLY under `#if DEBUG`; the flag defaults off, so a normal build
/// still hits the real Cloud Functions. It is a KEYWORD ROUTER — the word you
/// type decides which affordance fires (see `route`), giving a deterministic
/// full-coverage test conversation:
///   "run …"       → run a real open task → inline draft card (Approve/Open/Redo)
///   "remember …"  → auto-merge a decision → "Noted" chip
///   "connect …"   → suggest enabling an off toolkit item → enable card
///   "roadmap …"   → a tappable "go to Roadmap" nav chip
///   "long …"      → a long multi-paragraph reply (rendering / scroll)
///   anything else → a normal streamed reply
///
/// Toggle from the CLI (or just relaunch with the launch arg):
///   defaults write app.murror.codepet CODEPET_MOCK_CHAT -bool YES   # on
///   defaults write app.murror.codepet CODEPET_MOCK_CHAT -bool NO    # off
enum MockChat {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "CODEPET_MOCK_CHAT") }

    /// Decide the reply text + which `.done` action fires, from the message text
    /// and the request's own `runnable`/`envSetup` lists (so echoed ids are valid).
    private static func route(_ req: CompanyChatRequest) -> (text: String, action: ChatDoneAction) {
        let msg = req.userMessage.lowercased()

        // run → produce → approve (the core loop). Needs a runnable task.
        if msg.contains("run") || msg.contains("draft") || msg.contains("produce") {
            if let task = req.runnable.first {
                return ("On it — drafting \u{201C}\(task.title)\u{201D} for you now\u{2026}",
                        ChatDoneAction(runTaskId: task.id))
            }
            return ("You don\u{2019}t have a task I can run right now — everything\u{2019}s either done or waiting on you.",
                    ChatDoneAction())
        }

        // remember → auto-merged decision + "Noted" chip.
        if msg.contains("remember") || msg.contains("note that") {
            let fact = RememberedFact(topic: "Founder note",
                                      statement: req.userMessage.trimmingCharacters(in: .whitespacesAndNewlines))
            return ("Got it — I\u{2019}ll remember that.", ChatDoneAction(remember: [fact]))
        }

        // setup → suggest enabling an off toolkit item.
        if msg.contains("connect") || msg.contains("enable") || msg.contains("setup") || msg.contains("turn on") {
            if let tool = req.envSetup.first {
                return ("Want me to turn on \(tool.name)? Tap to enable it.",
                        ChatDoneAction(setup: SetupAction(category: tool.category, name: tool.name)))
            }
            return ("Everything in your toolkit is already on — nothing to connect.", ChatDoneAction())
        }

        // nav → a tappable "go here" chip.
        if msg.contains("roadmap") || msg.contains("go to") || msg.contains("open ") {
            return ("Here\u{2019}s your roadmap — tap to jump over.",
                    ChatDoneAction(nav: NavAction(destination: "roadmap", target: nil)))
        }

        // long → multi-paragraph rendering / scroll.
        if msg.contains("long") {
            return ("""
            Here\u{2019}s a fuller take. First, the fastest way to learn is to put something \
            small in front of real people this week — even a rough version teaches you more \
            than another week of planning.

            Second, keep your scope brutally narrow: one problem, one type of user, one clear \
            outcome. Everything else is a distraction until that core loop works.

            Third, write down what you expect to happen before you ship, then compare. That \
            gap between expectation and reality is where the real product insight lives.

            Want me to turn any of this into a concrete plan you can act on?
            """, ChatDoneAction())
        }

        // default reply.
        return ("""
        Good question — let\u{2019}s break it down. For the next few weeks I\u{2019}d focus on three \
        moves: first, lock your core value proposition into a single clear sentence; second, get \
        five real user conversations booked this week; and third, ship the smallest thing they \
        can actually try. Want me to draft a plan for any of these?
        """, ChatDoneAction())
    }

    /// Non-streaming counterpart of `stream`.
    static func reply(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        try? await Task.sleep(nanoseconds: 300_000_000)
        let (text, action) = route(req)
        return CompanyChatReply(text: text, runTaskId: action.runTaskId, nav: action.nav,
                                setup: action.setup, remember: action.remember)
    }

    /// Streams the routed reply word-by-word (with small delays) then a `.done`
    /// frame carrying the routed action — mirroring the real CF's SSE shape so
    /// the store's streaming path is exercised end-to-end.
    static func stream(_ req: CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        let (full, action) = route(req)
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                try? await Task.sleep(nanoseconds: 500_000_000)  // "Working on it…" beat
                var chunk = ""
                for ch in full {
                    chunk.append(ch)
                    if ch == " " {
                        continuation.yield(.delta(chunk))
                        chunk = ""
                        try? await Task.sleep(nanoseconds: 45_000_000)
                    }
                }
                if !chunk.isEmpty { continuation.yield(.delta(chunk)) }
                continuation.yield(.done(model: "mock", cacheHit: false, action: action))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Canned deliverable for `RunTaskClient.run` — so a `run_task_id` produces a
    /// real inline draft card (Approve / Open / Redo) offline.
    static func runResult(_ req: RunTaskRequest) async -> RunTaskResponse? {
        try? await Task.sleep(nanoseconds: 700_000_000)  // "producing…" beat
        let note = req.reviseNote.map { "\n\n_Revised per: \($0)_" } ?? ""
        let body = """
        ## \(req.taskTitle)

        A first draft to get you moving. Treat this as a starting point, not the final word.

        **Objective** — \(req.taskDetail.isEmpty ? "Move this task forward with a concrete first step." : req.taskDetail)

        **Suggested steps**
        1. Define what "done" looks like in one sentence.
        2. Do the smallest version of it today.
        3. Get one piece of real feedback before polishing.

        **Watch out for** — scope creep and polishing before validating.\(note)
        """
        return RunTaskResponse(kind: "plan", title: req.taskTitle, body: body, payload: nil)
    }
}
#endif
