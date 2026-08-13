import SwiftUI

/// The content-area half of the engineering workspace.
///
/// The dock keeps the transcript, the exec log, the approval cards and the
/// composer — untouched, still on the right, still the same thread. This view
/// takes the content area beside it, which is what the design's §5.3 means by
/// "same thread, more room". It is not a sheet and not a nav destination:
/// `ShellLayout.contentSurface` routes to it without changing
/// `companyStore.view`, so leaving review restores the founder's page because
/// nothing ever navigated away from it.
///
/// The frame; `ReviewPane` is the content. Kept separate so the shell owns the
/// header and the close affordance while the pane owns the diff and its own
/// scrolling — a long diff scrolls inside the pane, and the way out of review
/// never scrolls away with it.
struct EngineeringWorkspaceView: View {
    let runId: String
    @ObservedObject var store: EngineeringRunStore
    var onClose: () -> Void

    @Environment(\.uiLanguage) private var lang

    private var hue: Color { CodepetTheme.accentBlue }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ReviewPane(store: store, onScope: { await store.loadDiff(scope: $0) })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CodepetTheme.pageBackground)
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 10) {
            Text(lang == .vi ? "XEM LẠI" : "REVIEW")
                .font(CodepetTheme.inter(10, weight: .semibold)).tracking(0.5)
                .foregroundColor(hue)

            Spacer(minLength: 8)

            // "Close" rather than "Back": there is nowhere to go back TO — the
            // founder's page was never left. Closing puts the content area back
            // the way it was.
            Button(lang == .vi ? "Đóng" : "Close", action: onClose)
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(hue)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

#if DEBUG
#Preview("Engineering workspace") {
    let store = EngineeringRunStore(runner: MockEngineeringRunner())
    return EngineeringWorkspaceView(runId: "run_mock_1", store: store, onClose: {})
        .environment(\.uiLanguage, .en)
        .frame(width: 640, height: 420)
}
#endif
