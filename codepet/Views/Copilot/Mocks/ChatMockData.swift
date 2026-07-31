import SwiftUI

#if DEBUG
/// Shared fixtures + renderer for the chat-scenario mocks. Feeds fixture messages
/// through the REAL `CopilotBubble` exactly like `CopilotChatView.messageList`, so
/// the mocks match production and cannot drift. The same fixtures back both the
/// Xcode `#Preview`s and the in-app dev gallery (`ChatMocksGalleryView`), so what
/// you click in the running app is byte-for-byte what the previews show. Layout
/// constants mirror the shipped spacing pass (column 760, gutter 24, top 40 /
/// bottom 24, spacing 24).
enum ChatMockData {
    /// Core renderer — fills the space it's given (used by the resizable gallery).
    static func messages(_ msgs: [CopilotMessage]) -> some View {
        ZStack {
            ChatBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(msgs) { m in
                        CopilotBubble(message: m).id(m.id)
                    }
                }
                .padding(.top, 40)
                .padding(.bottom, 24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
            }
        }
        .environmentObject(CompanyStore())
        .environment(\.uiLanguage, .en)
    }

    /// Preview convenience — the core renderer at a fixed canvas size.
    static func conversation(_ msgs: [CopilotMessage]) -> some View {
        messages(msgs).frame(width: 900, height: 720)
    }

    /// The parallel agents-working block, rendered in the chat column like a
    /// companion message (top 40 / bottom 24 / centered — matches `messages`).
    static func agentsWorking() -> some View {
        ZStack {
            ChatBackdrop()
            ScrollView {
                AgentsWorkingRow(runs: agentRuns, now: agentsNow)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 24)
            }
        }
        .environmentObject(CompanyStore())
        .environment(\.uiLanguage, .en)
    }

    // MARK: - Fixtures (shared by the previews and the in-app gallery)

    /// Chat working with the user: Q&A + a "Do it with me" first-run action.
    static var userScenario: [CopilotMessage] {
        [
            CopilotMessage(role: .me, text: "Which task should I run right now?"),
            CopilotMessage(role: .companion,
                text: "Your leverage right now is momentum, not polish. Ship the smallest thing a real user can touch this week: write your positioning in one sentence, book five short calls, and put a rough landing page in front of them. Want me to draft the positioning line?"),
            CopilotMessage(role: .me, text: "draft it"),
            CopilotMessage(role: .companion,
                text: "On it — I can start this as a task and do the work with you.",
                firstRunAction: FirstRunAction(taskId: "t1",
                                               taskTitle: "Write your positioning statement")),
        ]
    }

    /// Chat working with the roadmap: a summary + a "Go to Roadmap" nav chip.
    static var roadmapScenario: [CopilotMessage] {
        [
            CopilotMessage(role: .me, text: "What's next on the roadmap?"),
            CopilotMessage(role: .companion,
                text: "You're in Validation. The one thing between you and launch is a working sign-up that captures real interest — everything else can wait. After that: pricing, then a small paid pilot."),
            CopilotMessage(role: .companion, text: "",
                navChip: NavAction(destination: "roadmap", target: nil)),
        ]
    }

    /// Chat working with tasks: a live exec-log then two draft cards (one approved).
    static var tasksScenario: [CopilotMessage] {
        [
            CopilotMessage(role: .me, text: "Run the landing page copy task."),
            CopilotMessage(role: .companion, text: "Write your landing page copy",
                producing: true, companionId: "nova", deptName: "Marketing",
                execSteps: [
                    ExecStep(label: "Reading your brief — mission, audience, voice", done: true),
                    ExecStep(label: "Pulling in the Marketing playbook", done: true),
                    ExecStep(label: "Drafting the headline and subhead", done: false),
                    ExecStep(label: "Matching your tone and past decisions", done: false),
                ]),
            CopilotMessage(role: .companion, text: "",
                draft: Deliverable(kind: .post, title: "Landing page copy",
                    body: "Headline — Your AI cofounder, not another chatbot.\n\nSubhead — Codepet plans your next move, does the work with you, and remembers every decision — grounded in your actual company.")),
            CopilotMessage(role: .companion, text: "",
                draft: Deliverable(kind: .post, title: "Positioning statement",
                    body: "For solo founders who can code but stall on everything else, Codepet is the AI cofounder that runs the whole company with you."),
                draftApproved: true),
        ]
    }

    /// Chat setting up the environment: a setup card + a "Noted" chip.
    static var envScenario: [CopilotMessage] {
        [
            CopilotMessage(role: .me, text: "Help me set up my tools."),
            CopilotMessage(role: .companion,
                text: "You'll want your code and your notes connected so I can act on them. Start with GitHub — it lets me open PRs and read your repo."),
            CopilotMessage(role: .companion, text: "",
                setupSuggestion: SetupAction(category: "connectors", name: "GitHub")),
            CopilotMessage(role: .companion, text: "",
                noted: [RememberedFact(topic: "Stack",
                                       statement: "Ships a native macOS app in Swift")]),
        ]
    }

    /// A fixed clock so elapsed times are stable across preview reloads / launches.
    static let agentsNow = Date(timeIntervalSince1970: 134)

    /// Three concurrent department agents — two working, one done.
    static var agentRuns: [AgentRun] {
        let base = Date(timeIntervalSince1970: 0)
        return [
            AgentRun(companionId: "byte", deptName: "Engineering",
                     taskTitle: "Building the waitlist API",
                     steps: [
                        ExecStep(label: "Scaffold the route", done: true),
                        ExecStep(label: "Define the schema", done: true),
                        ExecStep(label: "Write the handler", done: false),
                        ExecStep(label: "Add tests", done: false),
                     ],
                     status: .working, startedAt: base),
            AgentRun(companionId: "luna", deptName: "Design",
                     taskTitle: "Landing hero visual pass",
                     steps: [
                        ExecStep(label: "Moodboard", done: true),
                        ExecStep(label: "Layout", done: false),
                        ExecStep(label: "Typography", done: false),
                     ],
                     status: .working, startedAt: base),
            AgentRun(companionId: "sage", deptName: "Legal",
                     taskTitle: "Privacy policy draft",
                     steps: [ExecStep(label: "Draft clauses", done: true)],
                     status: .done, startedAt: base),
        ]
    }
}
#endif
