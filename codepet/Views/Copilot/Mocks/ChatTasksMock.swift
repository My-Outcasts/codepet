import SwiftUI

#if DEBUG
#Preview("Chat · with tasks") {
    ChatMockData.conversation([
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
    ])
}
#endif
