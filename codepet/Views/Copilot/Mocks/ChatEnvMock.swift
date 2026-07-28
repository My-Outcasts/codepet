import SwiftUI

#if DEBUG
#Preview("Chat · setting up the environment") {
    ChatMockData.conversation([
        CopilotMessage(role: .me, text: "Help me set up my tools."),
        CopilotMessage(role: .companion,
            text: "You'll want your code and your notes connected so I can act on them. Start with GitHub — it lets me open PRs and read your repo."),
        CopilotMessage(role: .companion, text: "",
            setupSuggestion: SetupAction(category: "connectors", name: "GitHub")),
        CopilotMessage(role: .companion, text: "",
            noted: [RememberedFact(topic: "Stack",
                                   statement: "Ships a native macOS app in Swift")]),
    ])
}
#endif
