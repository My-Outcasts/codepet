import SwiftUI

#if DEBUG
/// Dev-only switch for the in-app chat-mocks gallery. Enabled by launching with
/// `-CODEPET_MOCK_GALLERY YES` (or `defaults write app.murror.codepet
/// CODEPET_MOCK_GALLERY -bool YES`). Same idiom as `MockChat`. When on, the app
/// root becomes `ChatMocksGalleryView` instead of the normal shell — a way to
/// eyeball every chat mockup in a running build, not just the Xcode canvas.
enum MockGallery {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "CODEPET_MOCK_GALLERY") }
}

/// A sidebar picker over the five chat scenario mocks, rendering the selected one
/// live in the detail pane. Every scenario is backed by the same `ChatMockData`
/// fixtures the Xcode `#Preview`s use, so this is a faithful, clickable view of
/// exactly what was designed — including the parallel agents-working component.
struct ChatMocksGalleryView: View {
    enum Scenario: String, CaseIterable, Identifiable {
        case user = "With the user"
        case roadmap = "With the roadmap"
        case tasks = "With tasks"
        case environment = "Environment setup"
        case agents = "Agents working (parallel)"
        var id: String { rawValue }
    }

    @State private var selected: Scenario? = .user

    var body: some View {
        NavigationSplitView {
            List(Scenario.allCases, selection: $selected) { scenario in
                Text(scenario.rawValue).tag(scenario)
            }
            .navigationTitle("Chat mocks")
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selected ?? .user {
        case .user:        ChatMockData.messages(ChatMockData.userScenario)
        case .roadmap:     ChatMockData.messages(ChatMockData.roadmapScenario)
        case .tasks:       ChatMockData.messages(ChatMockData.tasksScenario)
        case .environment: ChatMockData.messages(ChatMockData.envScenario)
        case .agents:      ChatMockData.agentsWorking()
        }
    }
}

#Preview("Chat mocks gallery") {
    ChatMocksGalleryView()
        .frame(width: 1100, height: 760)
}
#endif
