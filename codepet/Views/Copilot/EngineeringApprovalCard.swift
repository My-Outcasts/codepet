import SwiftUI

/// The agent asking permission, inline in the transcript.
///
/// NOT a sheet, NOT an alert, NOT a `confirmationDialog`. Three reasons, in
/// order of how much they cost:
///
/// 1. Modal dialogs are a known hazard in this codebase — a JavaScript-style
///    modal blocks everything behind it, and an approval can arrive while the
///    founder is reading the diff that prompted it.
/// 2. An `npm install` does not warrant seizing the whole app.
/// 3. The transcript IS the record. An ask that appeared and vanished in a
///    modal leaves no trace of what was approved; one in the transcript stays
///    scrollable next to the step it authorised.
///
/// The copy is pure static functions of (state, language) for the same reason
/// as `EngineeringResultBar`: copy that reads `@Environment` can only be
/// exercised by rendering, and rendering cannot assert on words.
struct EngineeringApprovalCard: View {
    let approval: EngApproval
    /// Called with `allow`, and a reason when denying. Async because the store's
    /// `answer` is — this card does not await it for any state of its own.
    let onAnswer: (Bool, String?) async -> Void

    @Environment(\.uiLanguage) private var lang

    private var hue: Color { CodepetTheme.accentGold }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.prompt(lang: lang))
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(CodepetTheme.bodyText)

            // The command a founder is being asked about, verbatim and
            // monospaced. `EngineeringFrame.renderInput` already lifted it out
            // of the tool's JSON — nobody should read `{"command": …}` to
            // answer a yes/no.
            Text(approval.input)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(CodepetTheme.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CodepetTheme.mutedText.opacity(0.08))
                )

            HStack(spacing: 10) {
                Button(Self.allowLabel(lang: lang)) { answer(true) }
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(hue)
                    .buttonStyle(.plain)

                Button(Self.denyLabel(lang: lang)) { answer(false) }
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hue.opacity(0.35), lineWidth: 1)
        )
    }

    /// NO in-flight state, deliberately.
    ///
    /// The obvious design is a `@State private var sending` that disables both
    /// buttons for the round trip. It would guard a window that does not exist:
    /// `EngineeringRunStore.answer` removes this ask from `approvals`
    /// synchronously on the main actor BEFORE its `await`, so the card leaves
    /// the view tree before the send begins and cannot be tapped again.
    ///
    /// It would also be untestable — SwiftUI `@State` is not reachable from
    /// XCTest — so it would have been a guard with no proof, protecting nothing.
    /// The real guard is the store's synchronous removal, plus its `answered`
    /// set for a replayed ask; both are tested in EngineeringRunStoreTests.
    private func answer(_ allow: Bool) {
        Task { await onAnswer(allow, nil) }
    }

    // MARK: - copy

    static func prompt(lang: AppLanguage) -> String {
        lang == .vi ? "Muốn chạy:" : "Wants to run:"
    }

    /// "Allow", not "Yes" or "OK": the founder is granting a specific
    /// permission, and the word should say so.
    static func allowLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Cho phép" : "Allow"
    }

    /// "Not this", not "Deny" or "Cancel". Denying one command is not stopping
    /// the run — the agent can try another way — and "Cancel" reads as
    /// abandoning the whole thing.
    static func denyLabel(lang: AppLanguage) -> String {
        lang == .vi ? "Cách khác đi" : "Not this"
    }
}

#if DEBUG
#Preview("Approval — bash") {
    EngineeringApprovalCard(
        approval: EngApproval(id: "tu_1", name: "bash", input: "npm install stripe"),
        onAnswer: { _, _ in }
    )
    .environment(\.uiLanguage, .en)
    .padding()
    .frame(width: 320)
}
#endif
