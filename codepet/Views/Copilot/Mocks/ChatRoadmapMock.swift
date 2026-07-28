import SwiftUI

#if DEBUG
#Preview("Chat · with the roadmap") {
    ChatMockData.conversation([
        CopilotMessage(role: .me, text: "What's next on the roadmap?"),
        CopilotMessage(role: .companion,
            text: "You're in Validation. The one thing between you and launch is a working sign-up that captures real interest — everything else can wait. After that: pricing, then a small paid pilot."),
        CopilotMessage(role: .companion, text: "",
            navChip: NavAction(destination: "roadmap", target: nil)),
    ])
}
#endif
