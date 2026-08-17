import SwiftUI
import Combine

/// The collapsed result of an engineering run, in the chat dock.
///
/// The cloud twin of `CodeRunCardView`, and deliberately narrower: that card
/// owns a whole run's lifecycle including per-file accept, while this one is a
/// summary with a way into the Review pane. Engineering's own accent
/// (`accentBlue`, the Department catalog's colour for `key: "eng"`) so an eng
/// turn reads as distinct from the purple copilot chrome.
///
/// Four deliberate divergences from Codex, per the design's §5.2 — two of
/// which have flipped since it was written, because Codex moved:
///
/// - **Filenames are visible, not behind a tap.** Codex hid them behind an
///   aggregate and its users filed openai/codex#19891, so this card put them
///   one tap away. Their current build shows the list outright with a
///   "Show N more file" fold — the reason for the divergence went away, and on
///   14 Aug so did the tap.
/// - **The agent's prose leads, the commands follow.** `store.messages` was
///   collected from the first day and rendered nowhere, so a finished run was
///   six shell commands and no explanation of what got built.
/// - **No Undo button.** The branch IS the undo — nothing touched the founder's
///   default branch, so discarding is deleting a branch, and that belongs next
///   to the diff rather than behind a button implying local file surgery. A dead
///   Undo was already removed from this codebase once (`6982df0`).
/// - **A preview chip only for a URL that exists.** `engPreview` answers three
///   ways and the two "no"s get words instead — a chip that never resolves is
///   worse than no chip.
struct EngineeringResultBar: View {
    @ObservedObject var store: EngineeringRunStore
    @Environment(\.uiLanguage) private var lang

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
    /// Open by default. Codex hid filenames behind an aggregate, its users
    /// filed openai/codex#19891, and this card diverged deliberately to put
    /// them one tap away. Their current build shows the list outright with a
    /// "Show N more file" fold, so the tap is now the worse of the two — the
    /// reason for the divergence went away.
    @State private var filesExpanded = true
    /// Ticks once a second while the run is live, so "Worked for" climbs.
    /// Stops when the run does: `elapsedSeconds` freezes on `finishedAt`, so a
    /// finished run keeps its final number even though this keeps firing.
    @State private var now = Date()

    private var hue: Color { CodepetTheme.accentBlue }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Run metadata: how long, and on which machine. Grey and quiet,
            // above the rule, because it is not the answer.
            workedRow
            if stepsExpanded { stepList }

            // Always, not only when there is prose. It is the line between
            // the run's metadata and the run's answer, and Codex draws it
            // whether or not the answer has arrived yet — which is also when
            // the separation matters most, because otherwise the commands run
            // straight into the sentence.
            Divider().opacity(0.45)
            runLocallyRow
            summaryProse
            noteRow

            // Cards from here down, and only for things that are an artifact
            // or need an answer.
            if let diff = store.diff, !diff.files.isEmpty { changeSummary(diff) }
            approvalRows
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A 1s timer rather than TimelineView: this card sits inside the
        // transcript's ScrollView, and a TimelineView redraw there costs more
        // than a published Date on one row.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    // MARK: - the agent's own account of what it did

    /// What the agent SAYS it did, above what it ran.
    ///
    /// Collected since the store was written and rendered nowhere until 14 Aug.
    /// A finished run showed six shell commands and no explanation — the
    /// opposite of Codex, which leads with "Created a complete, responsive
    /// landing-page source package" and folds the commands away. The commands
    /// are evidence; this is the answer.
    ///
    /// Every message, not just the last: the agent narrates as it goes, and
    /// keeping only the final line would drop the reasoning that explains a
    /// permission ask three rows above.
    @ViewBuilder private var summaryProse: some View {
        if !store.messages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(store.messages.enumerated()), id: \.offset) { _, line in
                    // 14pt and leaded, against 13 flat before. This is the
                    // ANSWER, and it was set smaller than the founder's own
                    // question while four lines of monospaced shell sat above
                    // it — which is why the surface still read as a log after
                    // the card came off. Codex's answer is its largest text.
                    Text(line)
                        .font(CodepetTheme.inter(14))
                        .lineSpacing(3)
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// "2m 4s", or "41s" under a minute — Codex's shape, and it reads better
    /// than 124 seconds at the length these runs actually take.
    static func duration(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(seconds % 60)s"
    }

    // MARK: - "Worked for Ns"

    @ViewBuilder private var workedRow: some View {
        Button {
            stepsExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: stepsExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                // One line of metadata, not two. The destination used to have
                // its own row under this one, which put two grey lines above
                // the answer — Codex has none there at all, and the closest
                // honest thing is to say both in one breath.
                Text(workedText + " · " + Self.destinationText(lang: lang))
                    .font(CodepetTheme.inter(12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(CodepetTheme.mutedText)
        }
        .buttonStyle(.plain)
        // The step count is the honest fallback when no duration is known —
        // never a fabricated number. The web's version of this row invented its
        // counts (`3 + (label.length % 6)`); native shows what actually
        // happened or says nothing.
        .disabled(store.visibleSteps.isEmpty)
        .opacity(store.visibleSteps.isEmpty ? 0.5 : 1)
    }

    /// "Working… 41s" while it runs, "Worked for 1m 44s" once it has stopped.
    ///
    /// The tense IS the status. There was a phase chip in an eyebrow until 14
    /// Aug — "Working", "Needs you", "Ready to review" — and it went with the
    /// card: Codex carries the same information in this one line plus the
    /// presence of an ask, and a founder reading "Working… 41s" does not also
    /// need a badge saying Working.
    ///
    /// "Needs you" is not lost either: the permission card is on screen,
    /// unanswered, which is a louder signal than a word in a corner.
    static func workedPrefix(running: Bool, lang: AppLanguage) -> String {
        if running { return lang == .vi ? "Đang làm… " : "Working… " }
        return lang == .vi ? "Đã làm " : "Worked for "
    }

    /// Whether the clock is still moving — the run has not reached a terminal
    /// state. `awaitingApproval` counts as running: the session is alive and
    /// billing, it is just blocked on a human.
    static func isRunning(_ phase: EngineeringPhase) -> Bool {
        switch phase {
        case .preparing, .running, .awaitingApproval: return true
        case .reviewing, .budgetReached, .failed: return false
        }
    }

    private var workedText: String {
        // The store's clock first, the caller's override second. `elapsed` was
        // the only source until 14 Aug and the dock never passed one, so in the
        // running app this row could never say a duration — only a preview and
        // the gallery ever supplied a number.
        if let secs = elapsed ?? store.elapsedSeconds(now: now) {
            return Self.workedPrefix(running: Self.isRunning(store.phase), lang: lang)
                + Self.duration(secs)
        }
        // The VISIBLE count, or the row would promise steps the list does not
        // show — "6 steps" above four rows is its own small lie.
        let n = store.visibleSteps.count
        if n == 0 { return lang == .vi ? "Chưa có bước nào" : "No steps yet" }
        return lang == .vi ? "\(n) bước" : "\(n) steps"
    }

    @ViewBuilder private var stepList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.visibleSteps) { step in
                HStack(alignment: .top, spacing: 6) {
                    Text(step.done ? "✓" : "›")
                        .font(CodepetTheme.inter(11, weight: .semibold))
                        .foregroundColor(step.done ? CodepetTheme.accentTeal : CodepetTheme.mutedText)
                        .frame(width: 10, alignment: .leading)
                    Text(step.label)
                        .font(.system(size: 10.5, design: .monospaced))
                        // Dimmer than the prose on purpose. Expanded, this is
                        // evidence you went looking for, not the reply.
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 2)
    }

    // MARK: - the change summary

    /// The diff, shaped like Codex's: a title with its counts beneath, the
    /// action at the top right, then the files as rows with the basename
    /// carrying the weight, then a fold.
    ///
    /// Restyled 14 Aug from a tinted block with the counts on the same line
    /// and "Review" as a text link underneath. The information was all there;
    /// it read as a sub-section of a log rather than as an artifact you can
    /// act on, which is the whole difference Mona was pointing at.
    ///
    /// No Undo, unlike theirs — Codex edits local files, ours works on a
    /// branch, and the branch IS the undo.
    @ViewBuilder private func changeSummary(_ diff: EngDiffSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(changedText(diff))
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text("+\(diff.additions) −\(diff.deletions)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                Spacer(minLength: 8)
                Button(lang == .vi ? "Xem lại" : "Review", action: onReview)
                    .font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(hue)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().opacity(0.35)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.shownFiles(diff, expanded: filesExpanded)) { file in
                    fileRow(file)
                }
                if let more = Self.hiddenCount(diff, expanded: filesExpanded) {
                    Button {
                        filesExpanded.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(Self.foldLabel(more: more, lang: lang))
                                .font(CodepetTheme.inter(12))
                            Image(systemName: filesExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // GitHub caps a compare at 300 files. Saying the list is incomplete
            // is the difference between a partial answer and a wrong one.
            if diff.truncated {
                Text(lang == .vi
                     ? "Danh sách bị cắt — còn nhiều tệp hơn thế này."
                     : "This list is cut short — there are more files than shown.")
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CodepetTheme.mutedText.opacity(0.07))
        )
    }

    /// Three files, then a fold — Codex's threshold, and it fits the dock.
    static let visibleFileLimit = 3

    static func shownFiles(_ diff: EngDiffSummary, expanded: Bool) -> [EngFileDiff] {
        expanded ? diff.files : Array(diff.files.prefix(visibleFileLimit))
    }

    /// How many rows the fold is hiding, or nil when there is nothing to fold.
    static func hiddenCount(_ diff: EngDiffSummary, expanded: Bool) -> Int? {
        let hidden = diff.files.count - visibleFileLimit
        guard hidden > 0 else { return nil }
        return expanded ? 0 : hidden
    }

    /// "Show 1 more file" / "Show 4 more files" / "Collapse files" — Codex's
    /// wording, including the singular, because "Show 1 more files" is the
    /// kind of thing that makes a product feel unfinished.
    static func foldLabel(more: Int, lang: AppLanguage) -> String {
        if more == 0 { return lang == .vi ? "Thu gọn" : "Collapse files" }
        if lang == .vi { return "Xem thêm \(more) tệp" }
        return more == 1 ? "Show 1 more file" : "Show \(more) more files"
    }

    @ViewBuilder private func fileRow(_ file: EngFileDiff) -> some View {
        HStack(spacing: 8) {
            // The directory recedes and the filename carries the weight —
            // scanning a diff means reading basenames.
            Text(Self.directory(file.path))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(CodepetTheme.mutedText)
            + Text(Self.basename(file.path))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(CodepetTheme.primaryText)

            Spacer(minLength: 8)
            if file.isBinary {
                Text(lang == .vi ? "nhị phân" : "binary")
                    .font(CodepetTheme.inter(10))
                    .foregroundColor(CodepetTheme.mutedText)
            } else {
                Text("+\(file.additions)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(CodepetTheme.accentGreen)
                Text("−\(file.deletions)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(CodepetTheme.accentPink)
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Everything up to and including the last slash, or empty. Split rather
    /// than styled whole so a rename ("old → new") keeps reading correctly:
    /// the basename of the DISPLAY path is what changed.
    static func directory(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }

    static func basename(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
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
    /// Shortened to fit beside the duration: "Worked for 41s · on a branch in
    /// your repo". The long form was a sentence on its own row.
    static func destinationText(lang: AppLanguage) -> String {
        lang == .vi ? "trên một nhánh trong repo của bạn" : "on a branch in your repo"
    }

    /// The switch to the other machine, on its own quiet row and only while
    /// there is nothing to lose. It cannot join the metadata line — that line
    /// is text, and this needs a hit target.
    @ViewBuilder private var runLocallyRow: some View {
        if let onRunLocally, Self.canSwitchToLocal(store.phase) {
            Button(lang == .vi ? "Chạy trên máy mình" : "Run on my machine", action: onRunLocally)
                .font(CodepetTheme.inter(11, weight: .semibold))
                .foregroundColor(hue)
                .buttonStyle(.plain)
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
        if let failure { return message(for: failure, lang: lang) }
        // A run can reach `.failed` with NO refusal attached — an unrecognised
        // stop reason maps there and sets nothing (`EngineeringRun.phase`'s
        // default). The phase chip was the only thing marking it, and the chip
        // is gone, so this state would otherwise be silent: a run that simply
        // stops with no explanation anywhere.
        if case .failed = phase {
            return lang == .vi
                ? "Lần chạy này dừng lại mà không nói rõ lý do. Phần đã làm vẫn ở trên nhánh."
                : "This run stopped without saying why. Whatever it finished is still on the branch."
        }
        return nil
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
    return EngineeringResultBar(store: store, elapsed: 41, onReview: {})
        .padding()
        .frame(width: 360)
}
#endif
