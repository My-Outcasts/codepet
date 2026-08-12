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
/// The Review pane itself is Task 11. Until it lands this is the frame plus an
/// honest placeholder — deliberately not a spinner, which would imply something
/// is loading that is in fact not built.
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
            // Task 11 replaces this with ReviewPane. The placeholder states what
            // it is rather than pretending to load: a founder who sees a spinner
            // that never resolves learns to distrust every spinner in the app.
            VStack(alignment: .leading, spacing: 8) {
                Text(lang == .vi ? "Khung xem lại" : "Review pane")
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi
                     ? "Phần diff sẽ hiện ở đây. Chưa dựng xong."
                     : "The diff will appear here. Not built yet.")
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .padding(20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CodepetTheme.pageBackground)
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 10) {
            Text(lang == .vi ? "XEM LẠI" : "REVIEW")
                .font(CodepetTheme.inter(10, weight: .semibold)).tracking(0.5)
                .foregroundColor(hue)

            if let diff = store.diff {
                Text("+\(diff.additions) −\(diff.deletions)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(CodepetTheme.mutedText)
            }

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
