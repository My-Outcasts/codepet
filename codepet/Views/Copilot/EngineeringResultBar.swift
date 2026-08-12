import SwiftUI

/// The collapsed result of an engineering run, in the chat dock.
///
/// The cloud twin of `CodeRunCardView`, and deliberately narrower: that card
/// owns a whole run's lifecycle including per-file accept, while this one is a
/// summary with a way into the Review pane. Engineering's own accent
/// (`accentBlue`, the Department catalog's colour for `key: "eng"`) so an eng
/// turn reads as distinct from the purple copilot chrome.
///
/// Three deliberate divergences from Codex, per the design's §5.2:
///
/// - **Filenames are ONE tap away, not two.** Codex hides edited filenames
///   behind an aggregate summary and its users filed a bug about it
///   (openai/codex#19891). "Changed 3 files" collapsed, names on first expand.
/// - **No Undo button.** The branch IS the undo — nothing touched the founder's
///   default branch, so discarding is deleting a branch, and that belongs next
///   to the diff rather than behind a button implying local file surgery. A dead
///   Undo was already removed from this codebase once (`6982df0`).
/// - **No preview chip.** Nothing serves a preview URL yet (that is Plan 2's
///   `engPreview`, wired in a later task). A chip that never resolves is worse
///   than no chip, and the design says a repo with no deploy target should
///   degrade honestly rather than show a dead affordance.
struct EngineeringResultBar: View {
    @ObservedObject var store: EngineeringRunStore
    @Environment(\.uiLanguage) private var lang

    /// The founder's ask, shown above the summary. Passed in rather than read
    /// off the store: the store holds one run's live state, while the ask
    /// belongs to the chat turn this bar is rendered inside.
    let ask: String
    /// Seconds the run has been working, or nil while that is unknown.
    var elapsed: Int?
    var onReview: () -> Void

    @State private var stepsExpanded = false
    @State private var filesExpanded = false

    private var hue: Color { CodepetTheme.accentBlue }

    var body: some View {
        HStack {
            CodepetCard {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    Text(ask)
                        .font(CodepetTheme.inter(14, weight: .medium))
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    workedRow
                    if stepsExpanded { stepList }
                    if let diff = store.diff, !diff.files.isEmpty { changeSummary(diff) }
                    if let failure = store.failure { failureRow(failure) }
                }
                .padding(14)
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - header

    @ViewBuilder private var header: some View {
        HStack(spacing: 8) {
            Text(lang == .vi ? "KỸ THUẬT" : "ENGINEERING")
                .font(CodepetTheme.inter(10, weight: .semibold)).tracking(0.5)
                .foregroundColor(hue)
            Spacer(minLength: 8)
            phaseChip
        }
    }

    @ViewBuilder private var phaseChip: some View {
        let (text, colour) = Self.phaseLabel(store.phase, lang: lang)
        Text(text)
            .font(CodepetTheme.inter(10, weight: .semibold))
            .foregroundColor(colour)
    }

    /// One label per phase, and `budgetReached` is NOT worded as a failure —
    /// the session is paused and resumable, and telling a founder their work
    /// failed when it is sitting there intact makes them start over and pay
    /// twice.
    static func phaseLabel(_ phase: EngineeringPhase, lang: AppLanguage) -> (String, Color) {
        switch phase {
        case .preparing:
            return (lang == .vi ? "Đang chuẩn bị" : "Starting", CodepetTheme.mutedText)
        case .running:
            return (lang == .vi ? "Đang làm" : "Working", CodepetTheme.accentBlue)
        case .awaitingApproval:
            return (lang == .vi ? "Cần bạn xác nhận" : "Needs you", CodepetTheme.accentGold)
        case .reviewing:
            return (lang == .vi ? "Sẵn sàng duyệt" : "Ready to review", CodepetTheme.accentGold)
        case .budgetReached:
            return (lang == .vi ? "Tạm dừng ở hạn mức" : "Paused at its limit", CodepetTheme.accentGold)
        case .failed:
            return (lang == .vi ? "Không xong" : "Didn't finish", CodepetTheme.mutedText)
        }
    }

    // MARK: - "Worked for Ns"

    @ViewBuilder private var workedRow: some View {
        Button {
            stepsExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: stepsExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                Text(workedText)
                    .font(CodepetTheme.inter(12))
            }
            .foregroundColor(CodepetTheme.mutedText)
        }
        .buttonStyle(.plain)
        // The step count is the honest fallback when no duration is known —
        // never a fabricated number. The web's version of this row invented its
        // counts (`3 + (label.length % 6)`); native shows what actually
        // happened or says nothing.
        .disabled(store.steps.isEmpty)
        .opacity(store.steps.isEmpty ? 0.5 : 1)
    }

    private var workedText: String {
        if let elapsed {
            return lang == .vi ? "Đã làm \(elapsed)s" : "Worked for \(elapsed)s"
        }
        let n = store.steps.count
        if n == 0 { return lang == .vi ? "Chưa có bước nào" : "No steps yet" }
        return lang == .vi ? "\(n) bước" : "\(n) steps"
    }

    @ViewBuilder private var stepList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.steps) { step in
                HStack(alignment: .top, spacing: 6) {
                    Text(step.done ? "✓" : "›")
                        .font(CodepetTheme.inter(11, weight: .semibold))
                        .foregroundColor(step.done ? CodepetTheme.accentTeal : CodepetTheme.mutedText)
                        .frame(width: 10, alignment: .leading)
                    Text(step.label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 2)
    }

    // MARK: - the change summary

    @ViewBuilder private func changeSummary(_ diff: EngDiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                filesExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("±")
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(hue)
                    Text(changedText(diff))
                        .font(CodepetTheme.inter(13, weight: .medium))
                        .foregroundColor(CodepetTheme.primaryText)
                    Spacer(minLength: 8)
                    Text("+\(diff.additions) −\(diff.deletions)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            .buttonStyle(.plain)

            if filesExpanded { fileList(diff) }

            // GitHub caps a compare at 300 files. Saying the list is incomplete
            // is the difference between a partial answer and a wrong one.
            if diff.truncated {
                Text(lang == .vi
                     ? "Danh sách bị cắt — còn nhiều tệp hơn thế này."
                     : "This list is cut short — there are more files than shown.")
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
            }

            Button(lang == .vi ? "Xem lại" : "Review", action: onReview)
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(hue)
                .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hue.opacity(0.06))
        )
    }

    private func changedText(_ diff: EngDiffSummary) -> String {
        let n = diff.files.count
        if lang == .vi { return "Đã sửa \(n) tệp" }
        return n == 1 ? "Changed 1 file" : "Changed \(n) files"
    }

    @ViewBuilder private func fileList(_ diff: EngDiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(diff.files) { file in
                HStack(spacing: 8) {
                    // `path`, not `file`: for a rename this reads "old → new",
                    // which is the point — otherwise a renamed file looks like
                    // one that appeared from nowhere.
                    Text(file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CodepetTheme.bodyText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    if file.isBinary {
                        // A binary file has no patch to show. Naming it is
                        // still information; an empty body would read as a bug.
                        Text(lang == .vi ? "nhị phân" : "binary")
                            .font(CodepetTheme.inter(10))
                            .foregroundColor(CodepetTheme.mutedText)
                    } else {
                        Text("+\(file.additions) −\(file.deletions)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
            }
        }
    }

    // MARK: - failure

    @ViewBuilder private func failureRow(_ failure: EngineeringError) -> some View {
        Text(Self.message(for: failure, lang: lang))
            .font(CodepetTheme.inter(12))
            .foregroundColor(CodepetTheme.bodyText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Every refusal in the founder's words, and never blaming them for ours.
    ///
    /// STATIC and language-explicit, not an instance method reading
    /// `@Environment`. Copy that depends on the environment can only be
    /// exercised by rendering, and rendering cannot assert on words — so the
    /// first version of this was untestable, and the tests that tried to call
    /// it did not compile. A pure function of (failure, language) is testable
    /// in both languages, which is the only way to catch a missing Vietnamese
    /// string before a founder sees an English one.
    static func message(for failure: EngineeringError, lang: AppLanguage) -> String {
        switch failure {
        case .noRepoLinked:
            return lang == .vi
                ? "Chưa có repo nào để làm việc — kết nối một repo trước nhé."
                : "There's no repo to build in yet — connect one first."
        case .gitHubNotConnected:
            return lang == .vi
                ? "Cần kết nối GitHub trước khi chạy."
                : "Connect GitHub before running this."
        case .noCredits:
            return lang == .vi
                ? "Hết credit cho lần chạy này."
                : "You're out of credits for a run."
        case .misconfigured:
            // Ours. Never worded as something the founder did or can fix.
            return lang == .vi
                ? "Có gì đó bên phía chúng tôi bị lỗi. Chúng tôi đang xem."
                : "Something's broken on our side. We're looking at it."
        case .unavailable:
            return lang == .vi
                ? "Không kết nối được lúc này — thử lại nhé."
                : "Couldn't reach the run just now — try again."
        case .unknown:
            return lang == .vi
                ? "Có gì đó không ổn. Thử lại nhé."
                : "Something went wrong. Try again."
        }
    }
}

#if DEBUG
/// Driven by `MockEngineeringRunner`, so the gallery works with no credits, no
/// repo and no network — which is currently the only way to see this at all.
#Preview("Engineering — needs you") {
    let store = EngineeringRunStore(runner: MockEngineeringRunner())
    store.handle(.step(ExecStep(id: "s1", label: "read the repository", done: true, kind: .mono)))
    store.handle(.step(ExecStep(id: "s2", label: "npm install stripe", done: false, kind: .mono)))
    store.handle(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm install stripe")))
    return EngineeringResultBar(store: store, ask: "add stripe checkout", elapsed: 41, onReview: {})
        .padding()
        .frame(width: 360)
}
#endif
