import SwiftUI

#if DEBUG
#Preview("Chat · with the user") {
    ChatMockData.conversation([
        CopilotMessage(role: .me, text: "Which task should I run right now?"),
        CopilotMessage(role: .companion,
            text: "Your leverage right now is momentum, not polish. Ship the smallest thing a real user can touch this week: write your positioning in one sentence, book five short calls, and put a rough landing page in front of them. Want me to draft the positioning line?"),
        CopilotMessage(role: .me, text: "draft it"),
        CopilotMessage(role: .companion,
            text: "On it — I can start this as a task and do the work with you.",
            firstRunAction: FirstRunAction(taskId: "t1",
                                           taskTitle: "Write your positioning statement")),
    ])
}
#endif
