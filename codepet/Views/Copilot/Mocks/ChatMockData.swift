import SwiftUI

#if DEBUG
/// Shared renderer for the chat-scenario preview mocks. Feeds fixture messages
/// through the REAL `CopilotBubble` exactly like `CopilotChatView.messageList`,
/// so the mocks match production and cannot drift. Layout constants mirror the
/// shipped spacing pass (column 760, gutter 24, top 40 / bottom 24, spacing 24).
enum ChatMockData {
    static func conversation(_ messages: [CopilotMessage]) -> some View {
        ZStack {
            ChatBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(messages) { m in
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
        .frame(width: 900, height: 720)
        .environmentObject(CompanyStore())
        .environment(\.uiLanguage, .en)
    }
}
#endif
