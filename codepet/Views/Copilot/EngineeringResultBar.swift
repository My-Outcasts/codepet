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
    /// Reopens the connect-or-create sheet. Optional because the gallery and
    /// the previews have no sheet to open — but wherever a founder can see
    /// `.noRepoLinked`, this must be wired, or the message is an instruction
    /// with no control ("never a dead-end", spec §7).
    var onConnectRepo: (() -> Void)?
    /// Offered only when a project folder is linked. Nil hides the control —
    /// an offer to run somewhere the founder has not set up is not an offer.
    var onRunLocally: (() -> Void)?

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
                    destinationRow
                    workedRow
                    if stepsExpanded { stepList }
                    if let diff = store.diff, !diff.files.isEmpty { changeSummary(diff) }
                    noteRow
                    approvalRows
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

    // MARK: - where this is running

    /// Says where the work is happening, and offers the other machine.
    ///
    /// Build stopped being a choice between two modes on 14 Aug and became one
    /// mode with a destination. The destination still has to be VISIBLE: local
    /// edits files on the founder's disk for the price of an ordinary turn,
    /// cloud opens a branch and can spend 40 credits. A founder who cannot tell
    /// which is happening cannot tell what a run cost them or where to look for
    /// the result.
    @ViewBuilder private var destinationRow: some View {
        HStack(spacing: 8) {
            Text(lang == .vi
                 ? "Đang làm trên một nhánh trong repo của bạn."
                 : "Working on a branch in your repo.")
                .font(CodepetTheme.inter(11))
                .foregroundColor(CodepetTheme.mutedText)
            Spacer(minLength: 8)
            if let onRunLocally, Self.canSwitchToLocal(store.phase) {
                Button(lang == .vi ? "Chạy trên máy mình" : "Run on my machine", action: onRunLocally)
                    .font(CodepetTheme.inter(11, weight: .semibold))
                    .foregroundColor(hue)
                    .buttonStyle(.plain)
            }
        }
    }

    /// Only before there is anything to lose.
    ///
    /// Once a run is reviewing or paused at its cap it has produced a branch,
    /// and offering to start over somewhere else invites throwing that away by
    /// accident — the founder reads it as "also run locally", not "abandon
    /// this". Early on there is nothing to abandon.
    static func canSwitchToLocal(_ phase: EngineeringPhase) -> Bool {
        switch phase {
        case .preparing, .running, .awaitingApproval: return true
        case .reviewing, .budgetReached, .failed: return false
        }
    }

    // MARK: - the agent's outstanding questions

    /// Inside this card, not stacked beneath it.
    ///
    /// They were separate siblings in the transcript until Aug 13, which put
    /// two different container idioms on top of each other: this card carries
    /// `CodepetCard`'s opaque surface, shadow and `cardRadius` behind a 24pt
    /// right gutter, while the ask drew its own tinted rect at radius 10 across
    /// the FULL width. Visibly misaligned, and in a column this narrow the
    /// second set of chrome costs roughly 40pt of vertical furniture to say
    /// nothing — the run and its question are one event, not two.
    ///
    /// Salience is why they were separated, and that concern was right: an ask
    /// the founder must ACT on cannot read as part of a summary they have
    /// already skimmed. It is answered here by the tint and stroke against this
    /// card's surface — the same device `changeSummary` uses — rather than by a
    /// second border. Answering collapses the section and the card simply gets
    /// shorter, where before a whole sibling card vanished from under the
    /// cursor.
    @ViewBuilder private var approvalRows: some View {
        ForEach(store.approvals) { approval in
            EngineeringApprovalCard(approval: approval) { allow, reason in
                await store.answer(toolUseId: approval.id, allow: allow, reason: reason)
            }
        }
    }

    // MARK: - the one explanatory line

    @ViewBuilder private var noteRow: some View {
        if let text = Self.note(phase: store.phase, failure: store.failure, lang: lang) {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)

                // Drawn only when repeating the operation could actually answer
                // differently AND the store still knows what to repeat. Everything
                // else gets the message alone — see `EngineeringError.isRetryable`.
                if store.canRetry {
                    Button(lang == .vi ? "Thử lại" : "Try again") {
                        Task { await store.retry() }
                    }
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(hue)
                    .buttonStyle(.plain)
                }

                // "Connect one first" is an instruction. Without a control it
                // is an instruction the founder cannot follow from where they
                // are standing — which is the definition of the dead end §7
                // forbids for exactly this state.
                if store.failure == .noRepoLinked, let onConnectRepo {
                    Button(lang == .vi ? "Kết nối repo" : "Connect a repo", action: onConnectRepo)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(hue)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// The single line of explanation under the summary, and the one place that
    /// decides which line it is.
    ///
    /// Two paths reach a budget pause and they leave DIFFERENT state behind.
    /// The stream ending with `budget_reached` sets only `phase`; answering a
    /// card on an already-paused run comes back 409 and sets `failure` too. So
    /// rendering off `failure` alone — which this bar did until now — meant the
    /// commonest path, a run that simply exhausts its budget while the founder
    /// watches, drew the "Paused at its limit" chip and NOTHING that said the
    /// work was safe on the branch. Rendering off both would print the same
    /// sentence twice on the other path. The phase decides first; the failure
    /// fills in every case the phase has no opinion about.
    ///
    /// The phase also WINS over a failure, so a diff fetch that happened to
    /// fail cannot displace the one sentence telling the founder their work
    /// survived — the sentence that stops them re-running and paying twice.
    static func note(phase: EngineeringPhase,
                     failure: EngineeringError?,
                     lang: AppLanguage) -> String? {
        if case .budgetReached = phase { return message(for: .budgetReached, lang: lang) }
        guard let failure else { return nil }
        return message(for: failure, lang: lang)
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
            // The balance is definitionally 0 here — `engStartRun` refuses on
            // `credits <= 0` — so printing it would say "you have 0", which
            // the founder already knows. The number worth showing is what a
            // run needs, because that is the one they can act on.
            return lang == .vi
                ? "Hết credit rồi. Một lần chạy cần tối đa \(EngineeringRun.creditsPerRun) credit."
                : "You're out of credits. A run needs up to \(EngineeringRun.creditsPerRun)."
        case .budgetReached:
            // Paused, not failed, and the work is intact — saying otherwise
            // makes a founder start over and pay twice. No "Resume" control:
            // raising a session's budget resumes it on Anthropic's side, but
            // Codepet ships no endpoint that does it, and a dead button was
            // already removed from this codebase once (`6982df0`).
            return lang == .vi
                ? "Lần chạy này đã dừng ở hạn mức. Phần đã làm vẫn còn nguyên trên nhánh — mở phần xem lại để xem."
                : "This run stopped at its spend limit. The work so far is intact on the branch — open Review to see it."
        case .repoUnusable:
            // Names the cause AND both ways out, because "try again" on the
            // same empty repo produces the same 422.
            return lang == .vi
                ? "Repo đó chưa có commit nào nên chưa có nhánh để làm việc. Chọn repo khác, hoặc để Codepet tạo một cái mới."
                : "That repo has no commits yet, so there's no branch to build on. Pick another, or let Codepet make you one."
        case .nothingToShip:
            // The run recorded no repo or no branch, so there is nothing to
            // open a PR from. Ours to explain, not theirs to fix — and never
            // worded as "your repo is broken", which is what sharing a 422
            // with `repoUnusable` used to make it say.
            return lang == .vi
                ? "Lần chạy này chưa có nhánh nào để mở PR."
                : "This run has no branch to open a pull request from."
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
