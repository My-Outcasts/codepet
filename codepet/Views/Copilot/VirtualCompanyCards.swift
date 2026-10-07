// codepet/Views/Copilot/VirtualCompanyCards.swift
import SwiftUI

/// Contract rule 7: confidence as dots, never a number — a number implies false
/// precision. File scope (not nested in `VCRunCards`) so `DepartmentRow` — its own
/// nested struct — can use it too, giving rule 7 one implementation rather than two
/// that can drift.
struct VCConfidenceDots: View {
    let value: Int

    var body: some View {
        // Clamped defensively; the wire contract guarantees 1..5.
        let n = max(0, min(5, value))
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < n ? CodepetTheme.accentPurple : CodepetTheme.hairline)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// The room, rendered inside the chat. Stacked vertically because the dock is
/// 380pt wide — positions cannot sit in columns here, so they read as a sequence.
/// The room's "still working" line: spinner, the stage, and a clock since the row appeared.
/// It never disappears between stages, so the room is never still while it is running.
struct VCProgressRow: View {
    let stage: VCProgressStage
    @Environment(\.uiLanguage) private var lang
    @State private var startedAt = Date()

    /// Since the 6 Oct design pass this draws only before the room has a question to show
    /// (routing). Once it does, the meeting card's step strip and live line carry the stage.
    var body: some View {
        HStack(spacing: 10) {
            TeamPulseDot()
            Text(stage.label(lang))
                .font(CodepetTheme.inter(13, weight: .medium))
                .foregroundColor(CodepetTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(TeamBuildCopy.clock(ctx.date.timeIntervalSince(startedAt)))
                    .font(CodepetTheme.inter(12))
                    .monospacedDigit()
                    .foregroundColor(CodepetTheme.mutedText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// The meeting's five steps in one line (`MeetingSteps`): passed steps muted, the current one
/// in ink with a pulse, later ones faint. Real stage only — nothing advances on a timer (rule 8).
struct MeetingStepStrip: View {
    let current: Int
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        let titles = MeetingSteps.titles(lang)
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, title in
                if i > 0 {
                    Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
                        .frame(minWidth: 8, maxWidth: .infinity).padding(.horizontal, 6)
                }
                HStack(spacing: 5) {
                    if i == current {
                        TeamPulseDot(size: 7)
                    } else {
                        Circle()
                            .fill(i < current ? CodepetTheme.mutedText : Color.clear)
                            .overlay(Circle().stroke(i < current ? CodepetTheme.mutedText : CodepetTheme.hairline, lineWidth: 1.5))
                            .frame(width: 7, height: 7)
                    }
                    Text(title)
                        .font(CodepetTheme.inter(11, weight: i == current ? .medium : .regular))
                        .foregroundColor(i == current ? CodepetTheme.primaryText
                                         : i < current ? CodepetTheme.mutedText : CodepetTokens.faint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titles.indices.contains(current) ? titles[current] : "")
    }
}

/// The meeting card's clock, from when the card first appeared.
private struct MeetingClock: View {
    @State private var startedAt = Date()
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(TeamBuildCopy.clock(ctx.date.timeIntervalSince(startedAt)))
                .font(CodepetTheme.inter(12))
                .monospacedDigit()
                .foregroundColor(CodepetTokens.faint)
        }
    }
}

struct VCRunCards: View {
    let state: VirtualCompanyRunState
    /// The founder has already locked this brief in — the card says so instead of
    /// offering the button a second time. Carried on the message (`actionConsumed`),
    /// not inside the run state, so a `telemetry`/`done` frame arriving after the tap
    /// cannot un-consume it.
    let lockedIn: Bool
    /// The option it was locked in with (`CopilotMessage.lockedInChoice`), named in the footer.
    var lockedInChoice: String? = nil
    let onLockIn: () -> Void
    /// Lock in the option the founder picked (CP-031). Nil falls back to `onLockIn`.
    var onLockInChoice: ((VCFounderOption) -> Void)? = nil
    /// Set by the chat (CP-032): the landed room shows department chips and one "How the team
    /// decided" link, and the four disclosures move into the side panel this opens. Nil keeps
    /// the disclosures inline — a surface with nowhere to open a panel loses nothing.
    var onOpenRecord: ((RoomRecordTab) -> Void)? = nil
    /// Set by `RoomRecordPanel`: render that tab's content instead of the chat cards.
    var recordTab: RoomRecordTab? = nil
    #if DEBUG
    /// Test seam only. `Disclosure`'s `open` is `@State`, seeded once at first render —
    /// a render test builds a fresh view hierarchy every time, so there is no other way
    /// to observe the "What each department said" disclosure's *contents* without a
    /// production change reaching in this far. Every real call site omits it and gets the
    /// normal folded-closed behaviour. DEBUG-only, not just comment-guarded: this property
    /// (and the `Disclosure.initiallyOpen` parameter it forwards to) does not exist in a
    /// release build, so no real call site can ever pass it by accident.
    var openDepartmentsForTesting: Bool = false
    #endif

    @Environment(\.uiLanguage) private var lang
    /// The call, opened in the reader every other document in the app opens into.
    @State private var readingCall: Deliverable?
    /// Which of the room's two options the founder picked on the call card (CP-031).
    @State private var pickedOption: Int?
    /// "Why them, and who sat out" on the meeting card: the routing rationale, opened in place.
    @State private var showRoomWhy = false

    /// TWO shapes, because a run in flight and a run that has landed are different reading
    /// tasks — and the contract binds them differently.
    ///
    /// WHILE RUNNING the whole process is on screen: the question decomposed, the agents, and
    /// each position appearing in the agent's own row the moment it lands. That is rule 1
    /// ("never collapse the process into a spinner plus an answer") and it is also the answer
    /// to the founder's third complaint — results used to be appended as fresh cards further
    /// down the transcript, so a finished agent's row still said "Done" while its content sat
    /// somewhere below.
    ///
    /// ONCE THE BRIEF LANDS the call leads and the process folds into disclosures. The founder
    /// was reading ~1,500 words of routing rationale and positions before reaching the one
    /// thing she could act on; the most visually dominant block was the justification for who
    /// was NOT invited. Founder call, Aug 5.
    ///
    /// Two things stay expanded against that instruction, because the contract outranks it
    /// (CLAUDE.md) and says so explicitly: the conflict card (spec §4.3, "the highest-value
    /// view in the feature", plus rule 4's `what_would_change_my_mind`) and
    /// `the_real_disagreement` (rule 3, verbatim). THE CALL also ends on
    /// `tradeoff_founder_must_own`, which is rule 5 — an answer-first order must not lose the
    /// either/or, so the either/or moves INTO the leading card rather than trailing the stack.
    /// The room's cards all end on the same vertical line.
    ///
    /// Two of the ten reserved their own 24pt trailing gutter and eight did not, so the header and
    /// the answers card were visibly narrower than the disagreement card stacked against them
    /// (founder screenshot, Aug 7: "the card size aren't uniform"). `MessageCard` fills its column
    /// and leaves the gutter to callers — which is right for a shared helper and wrong as a rule
    /// each card re-decides, because there is no way to notice two of them disagreeing except by
    /// looking. Decided once, here, for every card the room draws.
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                cards
                // Once the room has a question, its card carries the stage (strip + live line).
                if state.routing == nil, state.brief == nil, let stage = VCProgressStage.from(state) {
                    VCProgressRow(stage: stage)
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $readingCall) { DeliverableDetailView(deliverable: $0) }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let tab = recordTab {
                recordContent(tab)
            } else if let brief = state.brief, let open = onOpenRecord {
                // The record link is the call's footer now (`callFooter`); `open` is read there.
                let _ = open
                theCall(brief)
            } else if let brief = state.brief {
                // The real disagreement is inside the call since the 6 Oct pass (`realDisagreement`).
                theCall(brief)
                let departmentsSaidTitle = (lang == .vi ? "Từng phòng ban đã nói gì"
                                                         : "What each department said")
                                            + " · \(state.agents.count)"
                #if DEBUG
                Disclosure(title: departmentsSaidTitle,
                           initiallyOpen: openDepartmentsForTesting) {
                    departmentsSaid
                }
                #else
                Disclosure(title: departmentsSaidTitle) {
                    departmentsSaid
                }
                #endif
                if let routing = state.routing {
                    Disclosure(title: (lang == .vi ? "Ai ở trong phòng, và vì sao" : "Who was in the room, and why")
                                + " · \(routing.agents.count)") {
                        routingCard(routing)
                    }
                }
                if !state.negotiationRounds.isEmpty {
                    Disclosure(title: (lang == .vi ? "Họ thương lượng thế nào" : "How they negotiated")
                                + " · \(state.negotiationRounds.count)") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(state.negotiationRounds, id: \.round) { roundCard($0) }
                        }
                    }
                }
                if let verdict = state.verdict {
                    Disclosure(title: lang == .vi ? "Điều gì có thể khiến kết luận này sai"
                                                  : "What could make this wrong") {
                        verdictCard(verdict)
                    }
                }
            } else {
                // IN FLIGHT the room is ONE card: the question, how many departments have
                // answered, a segment per department, and the routing rationale behind a button.
                // It replaced two stacked cards that between them printed ~13 paragraphs and a
                // titled panel per department before a single position existed (founder, Aug 6:
                // "too cluttered — less is more"). Shape adapted from the references she sent: a
                // hero count, one segmented bar, a split footer, one outlined action.
                //
                // `liveAgents` still follows, holding ONLY the departments that have answered —
                // a landed position appears the moment it arrives (founder call, Aug 5) and is
                // never summarised (rule 2). What left is the redundant "still working" row.
                // ONE card for the whole meeting (6 Oct design pass, mock approved): the
                // question, who is in the room, the departments side by side as their answers
                // land, where they split, and the live stage. It replaced four stacked cards (the
                // room header with its counts and bars, an "Answered" card, an orange conflict
                // card, a progress row). Every word the contract asks for is still on it: each
                // position (rule 2, clamped at a sentence, never rewritten), the conflicts with
                // their reasons, each side's what_would_change_my_mind (rule 4), confidence as
                // dots (rule 7), and the process while it happens (rule 1).
                if let routing = state.routing { meetingCard(routing) }
                if let verdict = state.verdict { verdictCard(verdict) }
            }
            if let stopped = state.stoppedReason { stoppedRow(stopped) }
            // Contract: `error` is terminal and no `done` follows — after a failed
            // run this is the ONLY signal the founder gets that the room stopped.
            if let err = state.terminalError { terminalErrorCard(err) }
            // No cost line here (CP-028). A meeting runs on the founder's own Claude plan, so
            // "This run cost $0.457" was an API-price estimate printed as if it were a bill,
            // under every room. The figure is still recorded — `CompanyStore` adds it to
            // `UsageLedger` when the room ends — and Settings → Usage shows the day's total.
        }
    }

    /// CONFLICT / BLOCKER / TENSION / ALIGNED are wire values, not founder-facing copy.
    private func kindLabel(_ kind: String) -> String {
        switch (kind, lang) {
        case ("ALIGNED", .vi):  return "đồng ý"
        case ("ALIGNED", _):    return "aligned"
        case ("BLOCKER", .vi):  return "chặn"
        case ("BLOCKER", _):    return "blocker"
        case ("TENSION", .vi):  return "căng"
        case ("TENSION", _):    return "tension"
        case ("CONFLICT", .vi): return "xung đột"
        case ("CONFLICT", _):   return "conflict"
        default:                return kind.lowercased()
        }
    }

    /// A department-chip summary of who is in the room right now. Deliberately
    /// NOT built on `AgentsWorkingRow`/`CompanionAvatar`/`PetCharacter`: those
    /// personify a companion pet, and department agents (and the chief of staff /
    /// devil's advocate roles) are not people (contract rule 9). A raw agent id
    /// like "product" or "devils_advocate" never matches a `PetCharacter`, so
    /// routing it through that bridge only ever produced a blank avatar image
    /// next to the generic fallback name "Codepet" — an accidental, unintended
    /// identity, not a deliberate one.
    /// The room while it works — and where each department's answer LANDS.
    ///
    /// Previously this was a status list and nothing else: it showed "Done" next to an agent
    /// whose position had been appended as a separate card further down the transcript, so the
    /// two halves of one agent's work sat in different places and the list itself carried no
    /// information once every row said Done. Now the row IS the agent: it shows a live bar
    /// while thinking, and the moment `agent_position` arrives the answer opens underneath the
    /// name it belongs to. Founder call, Aug 5 — "results should be displayed immediately upon
    /// completion, not on a new line".
    ///
    /// The bar is driven by real state (`.working` until a position or an error arrives), not a
    /// timer — rule 8 forbids artificial progress.
    /// True once this department's position has landed.
    private func answered(_ agentId: String) -> Bool { state.positions[agentId] != nil }

    /// Whether this department has anything to show yet — a position, or a failure.
    private func hasLanded(_ agentId: String) -> Bool {
        answered(agentId) || state.agentErrors[agentId] != nil
    }

    // MARK: - The meeting card (6 Oct design pass)

    private func meetingCard(_ routing: VCRouting) -> some View {
        let stage = VCProgressStage.from(state)
        let seats = MeetingSeats.departments(routing.agentMeta)
        let names = seats.map { displayName($0) }
        return HStack(spacing: 0) {
            TeamQuietSurface {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(lang == .vi ? "CUỘC HỌP" : "MEETING")
                            .font(CodepetTheme.inter(10, weight: .semibold)).tracking(1)
                            .foregroundColor(CodepetTheme.mutedText)
                        Spacer(minLength: 8)
                        if stage != nil { MeetingClock() }
                    }
                    if let stage {
                        MeetingStepStrip(current: MeetingSteps.current(stage)).padding(.top, 12)
                    }
                    Text(routing.realQuestion)
                        .font(CodepetTheme.inter(15, weight: .semibold)).lineSpacing(3)
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    HStack(spacing: 6) {
                        if !names.isEmpty {
                            Text(MeetingWords.inTheRoom(names, lang: lang) + " ·")
                                .foregroundColor(CodepetTheme.mutedText)
                        }
                        Button { withAnimation(.easeOut(duration: 0.15)) { showRoomWhy.toggle() } } label: {
                            Text(showRoomWhy ? (lang == .vi ? "ẩn lý do" : "hide why")
                                             : (lang == .vi ? "vì sao, và ai không được mời" : "why them, and who sat out"))
                                .foregroundColor(CodepetTheme.mutedText)
                                .underline(color: CodepetTheme.hairline)
                        }
                        .buttonStyle(.plain)
                        .cursorOnHover(.pointingHand)
                    }
                    .font(CodepetTheme.inter(12))
                    .padding(.top, 8)
                    if showRoomWhy { routingDetail(routing).padding(.top, 10) }
                    if !seats.isEmpty {
                        Rectangle().fill(CodepetTheme.hairline).frame(height: 1).padding(.top, 16)
                        seatGrid(seats)
                    }
                    if !state.conflicts.isEmpty { splitBand.padding(.top, 14) }
                    if let stage, MeetingSteps.current(stage) >= 2 {
                        HStack(spacing: 9) {
                            TeamPulseDot(size: 7)
                            Text(stage.label(lang))
                                .font(CodepetTheme.inter(13))
                                .foregroundColor(CodepetTheme.bodyText)
                        }
                        .padding(.top, 16)
                    }
                    if !state.negotiationRounds.isEmpty {
                        Disclosure(title: (lang == .vi ? "Họ thương lượng thế nào" : "How they negotiated")
                                    + " · \(state.negotiationRounds.count)") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(state.negotiationRounds, id: \.round) { roundCard($0) }
                            }
                        }
                        .padding(.top, 14)
                    }
                }
            }
        }
    }

    /// The departments side by side when the column allows (`MeetingSeats.columnChoices`),
    /// stacked when it does not — the dock is 380 pt wide.
    @ViewBuilder private func seatGrid(_ seats: [VCAgentMeta]) -> some View {
        let choices = MeetingSeats.columnChoices(count: seats.count)
        ViewThatFits(in: .horizontal) {
            ForEach(choices, id: \.self) { cols in seatRows(seats, cols: cols) }
        }
    }

    private func seatRows(_ seats: [VCAgentMeta], cols: Int) -> some View {
        let rows = stride(from: 0, to: seats.count, by: cols).map { Array(seats[$0..<min($0 + cols, seats.count)]) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                if r > 0 { Rectangle().fill(CodepetTheme.hairline).frame(height: 1) }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.agentId) { c, meta in
                        if c > 0 { Rectangle().fill(CodepetTheme.hairline).frame(width: 1) }
                        seat(meta)
                            .padding(.leading, c > 0 ? 16 : 0)
                            .padding(.trailing, c < row.count - 1 ? 16 : 0)
                            // idealWidth, not just minWidth: ViewThatFits measures IDEAL size, and a
                            // Text's ideal width is its whole answer on one line — without this, two
                            // columns never "fit" and the room always stacked (render, 6 Oct).
                            .frame(minWidth: cols > 1 ? 190 : 0, idealWidth: cols > 1 ? 190 : nil,
                                   maxWidth: .infinity, alignment: .topLeading)
                    }
                    // A short last row keeps its columns the width of the rows above.
                    ForEach(0..<(cols - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One department: its pet and name, its stance in words, confidence as dots (rule 7), the
    /// answer's first sentence (the rest on click — rule 2, never rewritten), and what would
    /// change its mind (rule 4) once it has said so in a negotiation turn.
    ///
    /// The pet is the department's sprite, never its name: rule 9 forbids human avatars and
    /// personal names for agents, and a pixel pet beside the word "Design" is neither. Before this
    /// the room drew no pet at all; the rest of the app already speaks for each department with
    /// its pet, so the meeting was the one place they disappeared.
    @ViewBuilder private func seat(_ meta: VCAgentMeta) -> some View {
        let position = state.positions[meta.agentId]
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                TeamPetAvatar(dept: meta.departmentKey ?? "", size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName(meta))
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    if let position {
                        Text(MeetingWords.stance(position.stance, lang: lang))
                            .font(CodepetTheme.inter(12))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                Spacer(minLength: 6)
                if let position { VCConfidenceDots(value: position.confidence).padding(.top, 5) }
            }
            if let position {
                SeatAnswer(text: position.position).padding(.top, 10)
            } else if let error = state.agentErrors[meta.agentId] {
                Text(error).font(CodepetTheme.inter(13)).foregroundColor(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            } else {
                HStack(spacing: 8) {
                    TeamPulseDot(size: 7)
                    Text(lang == .vi ? "đang nghĩ" : "thinking")
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTokens.faint)
                }
                .padding(.top, 12)
                // Where the answer will land. Static: a placeholder, not progress (rule 8).
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(CodepetTheme.hairline).frame(height: 8).frame(maxWidth: .infinity)
                    Capsule().fill(CodepetTheme.hairline).frame(height: 8).padding(.trailing, 60)
                }
                .padding(.top, 10)
            }
            if let mind = MeetingWords.changesMind(meta.agentId, rounds: state.negotiationRounds) {
                (Text(lang == .vi ? "Đổi ý nếu " : "Changes its mind if ").fontWeight(.medium)
                    .foregroundColor(CodepetTheme.bodyText)
                 + Text(mind).foregroundColor(CodepetTheme.mutedText))
                    .font(CodepetTheme.inter(12))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 16)
    }

    /// Where they split, as a soft warm band inside the meeting card — the orange-bordered card
    /// it replaces carried the same words. Pairs that share a reason are listed above one copy of
    /// it (`groupedByReason`); agreements collapse to one naming line, and an all-aligned room
    /// prints every pair under WHERE THEY AGREE (rule 2: never collapsed into one paragraph).
    private var splitBand: some View {
        let allAligned = !state.conflicts.isEmpty && state.conflicts.allSatisfy { $0.kind == "ALIGNED" }
        let disagreements = allAligned ? state.conflicts : state.conflicts.filter { $0.kind != "ALIGNED" }
        let agreed = allAligned ? [] : state.conflicts.filter { $0.kind == "ALIGNED" }
        let hue = allAligned ? CodepetTheme.accentTeal : CodepetTheme.accentOrange
        return VStack(alignment: .leading, spacing: 6) {
            if allAligned {
                Text(lang == .vi ? "Họ đồng ý ở đâu" : "Where they agree")
                    .font(CodepetTheme.inter(12, weight: .semibold)).foregroundColor(hue)
            }
            ForEach(Array(Self.groupedByReason(disagreements).enumerated()), id: \.offset) { _, group in
                ForEach(Array(group.pairs.enumerated()), id: \.offset) { _, c in
                    Text("\(displayName(agentId: c.a)) ↔ \(displayName(agentId: c.b)) · \(kindLabel(c.kind))")
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(hue)
                }
                Text(group.reason)
                    .font(CodepetTheme.inter(13)).lineSpacing(4)
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
            }
            if !agreed.isEmpty {
                Text(agreedLine(agreed))
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hue.opacity(0.07)))
        .overlay(alignment: .leading) { Rectangle().fill(hue).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// An answer's first sentence, the rest on click. The text is never altered (rule 2).
    private struct SeatAnswer: View {
        let text: String
        @Environment(\.uiLanguage) private var lang
        @State private var open = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(open ? text : MeetingWords.lead(text))
                    .font(CodepetTheme.inter(13)).lineSpacing(4)
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                if MeetingWords.hasMore(text) {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { open.toggle() } } label: {
                        Text(open ? (lang == .vi ? "Thu gọn" : "Less") : (lang == .vi ? "Đọc tiếp" : "More"))
                            .font(CodepetTheme.inter(12, weight: .medium))
                            .foregroundColor(CodepetTheme.mutedText)
                            .underline(color: CodepetTheme.hairline)
                    }
                    .buttonStyle(.plain)
                    .cursorOnHover(.pointingHand)
                }
            }
        }
    }

    /// One tab of the side panel. Every view here already existed inside the four disclosures;
    /// only where it is drawn changed.
    @ViewBuilder private func recordContent(_ tab: RoomRecordTab) -> some View {
        switch tab {
        case .stances:
            departmentsSaid
        case .disagreements:
            if let brief = state.brief { landedDisagreement(brief) }
            if !state.conflicts.isEmpty { conflictCard }
        case .record:
            if let routing = state.routing { routingCard(routing) }
            ForEach(state.negotiationRounds, id: \.round) { roundCard($0) }
            if let verdict = state.verdict { verdictCard(verdict) }
        }
    }

    private var departmentsSaid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(state.agents.enumerated()), id: \.element.agentId) { i, meta in
                if i > 0 {
                    Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
                }
                if let position = state.positions[meta.agentId] {
                    positionRow(meta, position)
                }
                if let error = state.agentErrors[meta.agentId] {
                    errorRow(meta, error)
                }
            }
        }
    }

    /// Rule 3: `the_real_disagreement` verbatim, and never behind a disclosure.
    /// ONE disagreement card, once the brief has landed.
    ///
    /// It used to be two: a `WHERE THEY DISAGREE` card whose single pair's whole body was
    /// "sales raised a hard blocker: Do not publish a public price list before…", sitting directly
    /// above a `THE REAL DISAGREEMENT` card whose narrative said the same thing again in its own
    /// words — and the recommendation above BOTH had already said it a third time. Founder, Aug 7:
    /// "why are there so many separate cards?" Because one of them had nothing of its own to say.
    ///
    /// Merged: the pairs are compact heading lines (who, and how hard), and the narrative that
    /// explains them follows verbatim — rule 3 forbids paraphrasing or softening it, and rule 4
    /// wants each side's `what_would_change_my_mind`, which the narrative carries.
    ///
    /// The pair's `reason` is dropped from THIS card only: it is the blocker text, and it is inside
    /// the narrative immediately below. While the room is still in flight there is no narrative
    /// yet, so `conflictCard` keeps printing reasons — that is the only place they are not
    /// duplicated.
    private func landedDisagreement(_ brief: VCBrief) -> some View {
        let real = brief.theRealDisagreement.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs = state.conflicts.filter { $0.kind != "ALIGNED" }
        let agreed = state.conflicts.filter { $0.kind == "ALIGNED" }
        // NOT a MessageCard any more. The founder's complaint about a landed room was
        // competing panels, and this was the second one — same border weight, same tint
        // strength, directly under the card it belongs to. It keeps every word it had:
        // the pairs, `the_real_disagreement` VERBATIM (rule 3), and the aligned line.
        //
        // Plain ink, no hue (CP-036: one tinted card per message, and here that card is THE
        // CALL above). The orange/teal flip used to say disagree vs agree; the label above
        // the line says it now. It is still its own block, not merged into THE CALL — [A1].
        return VStack(alignment: .leading, spacing: 8) {
            label(pairs.isEmpty ? (lang == .vi ? "HỌ ĐỒNG Ý" : "WHERE THEY AGREE")
                                : (lang == .vi ? "BẤT ĐỒNG THẬT SỰ" : "THE REAL DISAGREEMENT"))
            // One sentence, not one orange line per pair (CP-030): six "A ↔ B · blocker" rows
            // for what the narrative below calls two fights. The pairs stay in the full record.
            if let split = SplitSummary.line(pairs, name: { displayName(agentId: $0) }, lang: lang) {
                Text(split)
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !real.isEmpty {
                Text(real).font(CodepetTheme.inter(14)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !agreed.isEmpty {
                Text(agreedLine(agreed))
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
    }

    /// A collapsed section of the room. Closed by default: the founder opens the process she
    /// wants rather than scrolling past all of it to reach the answer.
    private struct Disclosure<Content: View>: View {
        let title: String
        @ViewBuilder var content: Content
        @State private var open: Bool

        #if DEBUG
        /// `initiallyOpen` defaults closed for every real call site. It exists so a
        /// render test can seed a disclosure open without reaching into `@State` from
        /// outside the view — see `VCRunCards.openDepartmentsForTesting`. DEBUG-only: the
        /// parameter itself does not exist in a release build, rather than trusting the
        /// default to keep every call site closed.
        init(title: String, initiallyOpen: Bool = false, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
            self._open = State(initialValue: initiallyOpen)
        }
        #else
        init(title: String, @ViewBuilder content: () -> Content) {
            self.title = title
            self.content = content()
            self._open = State(initialValue: false)
        }
        #endif

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(title).font(CodepetTheme.inter(12, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CodepetTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CodepetTheme.hairline, lineWidth: 1))
                    .hoverAffordance(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                if open { content }
            }
        }
    }

    // Spec §4.3: routing is CONTENT, not a loading state. It is the panel where
    // the founder sees their question decomposed.
    /// The routing rationale WITHOUT the question — the question is the header card's title now, so
    /// repeating it inside its own disclosure would be the clutter this replaced.
    private func routingDetail(_ routing: VCRouting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(routing.agentMeta, id: \.agentId) { meta in
                if let why = routing.reasonPerAgent[meta.agentId] {
                    Text("✓ \(displayName(meta)) — \(why)")
                        .font(CodepetTheme.inter(13)).lineSpacing(5)
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !routing.excluded.isEmpty {
                Divider().overlay(CodepetTheme.hairline)
                label(lang == .vi ? "KHÔNG MỜI, VÌ" : "NOT IN THE ROOM, BECAUSE")
                // Sorted: `excluded` is a dictionary, and unsorted iteration reshuffles the list
                // on every redraw of a live card.
                ForEach(routing.excluded.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                    Text("✗ \(roleName(entry.key)) — \(entry.value)")
                        .font(CodepetTheme.inter(13)).lineSpacing(5)
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !routing.missingInfo.isEmpty {
                Text((lang == .vi ? "Còn thiếu: " : "Missing: ")
                     + routing.missingInfo.joined(separator: "; "))
                    .font(CodepetTheme.inter(13)).lineSpacing(5)
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func routingCard(_ routing: VCRouting) -> some View {
        MessageCard(hue: CodepetTheme.accentPurple) {
            VStack(alignment: .leading, spacing: 8) {
                label(lang == .vi ? "CÂU HỎI THẬT" : "THE REAL QUESTION")
                Text(routing.realQuestion)
                    .font(CodepetTheme.inter(15, weight: .semibold)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.primaryText)
                ForEach(routing.agentMeta, id: \.agentId) { meta in
                    if let why = routing.reasonPerAgent[meta.agentId] {
                        Text("✓ \(displayName(meta)) — \(why)")
                            .font(CodepetTheme.inter(14)).lineSpacing(6)
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                // Why each department was left out. With nine to choose from the
                // router writes several of these per run, and they are the clearest
                // statement of what the question is NOT about — spec §4.2A, the
                // founder learns problem decomposition from this panel. They were
                // collected and persisted from the start and never once shown.
                //
                // Sorted, because `excluded` is a dictionary: unsorted iteration
                // reshuffles the list on every redraw of a live card.
                if !routing.excluded.isEmpty {
                    Divider().overlay(CodepetTheme.hairline)
                    label(lang == .vi ? "KHÔNG MỜI, VÌ" : "NOT IN THE ROOM, BECAUSE")
                    ForEach(routing.excluded.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                        Text("✗ \(roleName(entry.key)) — \(entry.value)")
                            .font(CodepetTheme.inter(13)).lineSpacing(5)
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                if !routing.missingInfo.isEmpty {
                    Text((lang == .vi ? "Còn thiếu: " : "Missing: ")
                         + routing.missingInfo.joined(separator: "; "))
                        .font(CodepetTheme.inter(13)).lineSpacing(5)
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }

    /// One department, one line until asked.
    ///
    /// It was a `MessageCard(hue:)` carrying five things at once: name, stance pill,
    /// confidence dots, the position, "costs their department", and sometimes a
    /// blocker. Three of those stacked read denser than the call they sat beneath.
    ///
    /// Rule 2 — never summarise the positions — is better served by this, not worse. The
    /// three stances now sit adjacent instead of separated by paragraphs, so the split is
    /// legible at a glance rather than after reading three panels. Nothing is summarised:
    /// every word is one click away, and the stance and confidence never move.
    private func positionRow(_ meta: VCAgentMeta, _ position: VCPosition) -> some View {
        DepartmentRow(
            name: displayName(meta),
            stance: stanceLabel(position.stance),
            hue: accent(meta),
            confidence: position.confidence,
            position: position.position,
            cost: (lang == .vi ? "Cái này khiến họ mất: " : "Costs their department: ")
                  + position.costToMyDept,
            blocker: position.hardBlocker)
    }

    /// Chevron, name, stance, dots — then everything else behind the row.
    ///
    /// A separate small view rather than reusing `Disclosure`: that one draws its header
    /// as a bordered `surface` pill, which would put a border back on every department
    /// and undo the point of this change.
    ///
    /// Founder ruling: department detail is now two clicks deep (open "What each
    /// department said", then open the one row you care about) where it used to be one.
    /// Asked directly whether that's acceptable, the founder confirmed: keep two clicks.
    /// Three departments read as three lines, and you open only the one you came for —
    /// the cost is that reading all three positions now takes three more clicks than
    /// before, and that is the trade for the list not being a wall.
    private struct DepartmentRow: View {
        let name: String
        let stance: String
        let hue: Color
        let confidence: Int
        let position: String
        let cost: String
        let blocker: String?
        @State private var open = false

        var body: some View {
            VStack(alignment: .leading, spacing: 7) {
                Button { withAnimation(.easeInOut(duration: 0.15)) { open.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(CodepetTheme.mutedText)
                        // NOT `sectionName()` — that is `inter(25)`, and a 25pt department
                        // name is a large part of why the current cards feel heavy. In the
                        // screenshots "Finance" renders bigger than the decision headline
                        // above it, which inverts the hierarchy. A row needs a row-sized name.
                        Text(name).font(CodepetTheme.inter(13, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Text(stance)
                            .font(CodepetTheme.inter(11, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(hue.opacity(0.12)))
                            .foregroundColor(hue)
                        Spacer(minLength: 8)
                        // Rule 7: dots, never a number.
                        VCConfidenceDots(value: confidence)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cursorOnHover(.pointingHand)
                if open {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(position).font(CodepetTheme.inter(14)).lineSpacing(6)
                            .foregroundColor(CodepetTheme.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(cost).font(CodepetTheme.inter(13)).lineSpacing(5)
                            .foregroundColor(CodepetTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let blocker {
                            Text("🔒 " + blocker)
                                .font(CodepetTheme.inter(12, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 17)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }

    // Spec §4.3: the highest-value view in the feature. Never collapsed.
    private var conflictCard: some View {
        // The contract documents an all-ALIGNED outcome as normal (the "nothing to
        // debate" flow), and "WHERE THEY DISAGREE" over a list of agreements is a lie.
        // Every row is still shown either way — contract rule 2 forbids collapsing the
        // positions into one "we agree" paragraph.
        let allAligned = !state.conflicts.isEmpty && state.conflicts.allSatisfy { $0.kind == "ALIGNED" }
        // A card headed WHERE THEY DISAGREE must not spend a paragraph on a pair that agrees.
        //
        // With three departments the classifier emits three pairs, and one of them was an ALIGNED
        // row whose whole body read "Both product and sales are do_not_proceed with no hard
        // blocker in play" — a full paragraph, under a heading claiming disagreement, saying
        // nothing the stance chips above had not already said (founder, Aug 6). Agreements now
        // collapse to a single naming line at the foot of the card. Nothing is dropped: the
        // all-ALIGNED flow still prints every row in full under WHERE THEY AGREE, which is the
        // contract's "nothing to debate" outcome and reads correctly there.
        let disagreements = allAligned ? state.conflicts : state.conflicts.filter { $0.kind != "ALIGNED" }
        let agreed = allAligned ? [] : state.conflicts.filter { $0.kind == "ALIGNED" }
        return MessageCard(hue: allAligned ? CodepetTheme.accentTeal : CodepetTheme.accentOrange) {
            VStack(alignment: .leading, spacing: 6) {
                label(allAligned ? (lang == .vi ? "HỌ ĐỒNG Ý Ở ĐÂU" : "WHERE THEY AGREE")
                                 : (lang == .vi ? "HỌ KHÔNG ĐỒNG Ý Ở ĐÂU" : "WHERE THEY DISAGREE"))
                // ONE blocker, however many pairs it bites.
                //
                // A department that raises a hard blocker conflicts with EVERY other department
                // that wants to proceed, so `classifyPair` emits the same `reason` once per pair.
                // With Sales blocking, the founder read the identical paragraph twice under
                // "Product ↔ Sales" and "Finance ↔ Sales" (screenshot, Aug 7) — the classifier is
                // right, the rendering was repeating it. Pairs that share a reason are now listed
                // together above the one copy of it.
                ForEach(Array(Self.groupedByReason(disagreements).enumerated()), id: \.offset) { _, group in
                    ForEach(Array(group.pairs.enumerated()), id: \.offset) { _, c in
                        Text("\(displayName(agentId: c.a)) ↔ \(displayName(agentId: c.b))"
                             + " · \(kindLabel(c.kind))")
                            .font(CodepetTheme.inter(13, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                    }
                    Text(group.reason).font(CodepetTheme.inter(14)).lineSpacing(6)
                        .foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                }
                if !agreed.isEmpty {
                    Text(agreedLine(agreed))
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Pairs that share a reason, grouped under it — in first-seen order, so the card's reading
    /// order still follows the classifier's stable output rather than a dictionary's.
    ///
    /// Pure and `static` so the grouping is testable without a view.
    static func groupedByReason(_ conflicts: [VCConflict]) -> [(reason: String, pairs: [VCConflict])] {
        var order: [String] = []
        var byReason: [String: [VCConflict]] = [:]
        for c in conflicts {
            if byReason[c.reason] == nil { order.append(c.reason) }
            byReason[c.reason, default: []].append(c)
        }
        return order.map { (reason: $0, pairs: byReason[$0] ?? []) }
    }

    /// "Product and Sales agree." — the pairs that had nothing to argue about, named in one line
    /// instead of a paragraph each.
    private func agreedLine(_ agreed: [VCConflict]) -> String {
        let pairs = agreed.map { "\(displayName(agentId: $0.a)) ↔ \(displayName(agentId: $0.b))" }
        let joined = pairs.joined(separator: ", ")
        return lang == .vi ? "\(joined) đồng ý." : "\(joined) agree."
    }

    /// The backend's marker for a turn it could not parse — `negotiation.ts:207` writes
    /// `(unusable turn: …)` into `precise_disagreement` and leaves the rest empty. Matched on the
    /// prefix rather than the whole string because the error text after it varies.
    ///
    /// Pure and `static` so it is testable without a view.
    static func isUnusable(_ turn: VCNegotiationTurn) -> Bool {
        turn.preciseDisagreement
            .trimmingCharacters(in: CharacterSet.whitespaces)
            .hasPrefix("(unusable turn:")
    }

    private func unusableLine(_ agentId: String) -> String {
        let who = displayName(agentId: agentId)
        return lang == .vi ? "\(who): lượt này không dùng được." : "\(who)'s turn was unusable."
    }

    private func roundCard(_ round: VCNegotiationRound) -> some View {
        MessageCard(hue: CodepetTheme.hairline) {
            VStack(alignment: .leading, spacing: 6) {
                label((lang == .vi ? "VÒNG " : "ROUND ") + "\(round.round)")
                // `id: \.offset`, not `\.agent`: one agent can take two turns in a
                // round, and the second one vanished.
                ForEach(Array(round.turns.enumerated()), id: \.offset) { _, turn in
                    // A turn the backend could not use is an ERROR, not content.
                    //
                    // `negotiation.ts:207` puts `(unusable turn: <error>)` into
                    // `preciseDisagreement` and leaves the other two fields empty, so a failed
                    // turn rendered as a body paragraph followed by the headings "Proposes:" and
                    // "What would change their mind:" with nothing after them — three lines of
                    // furniture around an absence (founder screenshot, Aug 6). One muted line now.
                    if Self.isUnusable(turn) {
                        Text(unusableLine(turn.agent))
                            .font(CodepetTheme.inter(12)).foregroundColor(CodepetTokens.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(displayName(agentId: turn.agent)): \(turn.preciseDisagreement)")
                            .font(CodepetTheme.inter(14)).lineSpacing(6).foregroundColor(CodepetTheme.bodyText)
                        // Each field only earns its heading when it has something under it.
                        if !turn.proposal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text((lang == .vi ? "Đề xuất: " : "Proposes: ") + turn.proposal)
                                .font(CodepetTheme.inter(13)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                        }
                        // Contract rule 4: show each side's what_would_change_my_mind —
                        // it teaches that disagreement is settled by evidence, not authority.
                        if !turn.whatWouldChangeMyMind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text((lang == .vi ? "Điều gì sẽ đổi ý họ: " : "What would change their mind: ")
                                 + turn.whatWouldChangeMyMind)
                                .font(CodepetTheme.inter(13)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                        }
                    }
                }
            }
        }
    }

    // No department colour: it is not a department (contract, §4.3).
    private func verdictCard(_ verdict: VCVerdict) -> some View {
        MessageCard(hue: CodepetTheme.primaryText) {
            VStack(alignment: .leading, spacing: 6) {
                // Contract: plan_is_sound true → render as endorsement, not attack.
                label(verdict.planIsSound
                      ? (lang == .vi ? "NGƯỜI PHẢN BIỆN — ĐỒNG Ý" : "THE CHALLENGER — ENDORSES")
                      : (lang == .vi ? "NGƯỜI PHẢN BIỆN" : "THE CHALLENGER"))
                Text(verdict.loadBearingAssumption).font(CodepetTheme.inter(15, weight: .medium)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.primaryText)
                if verdict.planIsSound {
                    Text(lang == .vi ? "Đã kiểm — kế hoạch vững." : "Stress-tested — the plan holds.")
                        .font(CodepetTheme.inter(14)).lineSpacing(6).foregroundColor(CodepetTheme.bodyText)
                } else {
                    Text(verdict.howItCouldBeFalse).font(CodepetTheme.inter(14)).lineSpacing(6)
                        .foregroundColor(CodepetTheme.bodyText)
                }
                Text((lang == .vi ? "Cách kiểm rẻ nhất: " : "Cheapest test: ") + verdict.cheapestTest)
                    .font(CodepetTheme.inter(13)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                if !verdict.objections.isEmpty {
                    label(lang == .vi ? "CÁC PHẢN BÁC" : "OBJECTIONS")
                    ForEach(Array(verdict.objections.enumerated()), id: \.offset) { idx, objection in
                        Text("\(idx + 1). " + objection)
                            .font(CodepetTheme.inter(14)).lineSpacing(6).foregroundColor(CodepetTheme.bodyText)
                    }
                }
                Text((lang == .vi ? "Nếu thất bại: " : "If this fails: ") + verdict.failurePostMortem)
                    .font(CodepetTheme.inter(13)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                Text((lang == .vi ? "Ai không có trong phòng: " : "Who's not in the room: ")
                     + verdict.whoIsNotInTheRoom)
                    .font(CodepetTheme.inter(13)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
            }
        }
    }

    /// THE CALL — what the room decided, what to do, and the one trade-off that is the
    /// founder's. Everything a founder acts on, in one block, at the top.
    ///
    /// It carries `tradeoff_founder_must_own` LAST of the reading content, because rule 5 says
    /// the presentation ends on the either/or. In the old chronological order that came for
    /// free (the brief was the final card); with the call leading, the either/or has to move
    /// inside it or the rule is quietly lost.
    ///
    /// `the_real_disagreement` deliberately does NOT live here — it has its own always-visible
    /// block (rule 3) so this card stays the size of a decision rather than a document.
    private func theCall(_ brief: VCBrief) -> some View {
        // ONE card since the 6 Oct design pass: the call, how sure, the real disagreement
        // VERBATIM (rule 3) under a warm rule, and the either/or LAST (rule 5). The disagreement
        // used to be its own block under the call plus a row of department chips; the names now
        // ride the confidence line and "How the team decided" is a footer link.
        let names = MeetingSeats.departments(state.routing?.agentMeta ?? state.agents).map { displayName($0) }
        let options = FounderChoice.options(brief)
        return TeamQuietSurface {
            VStack(alignment: .leading, spacing: 0) {
                Text(lang == .vi ? "QUYẾT ĐỊNH" : "THE CALL")
                    .font(CodepetTheme.inter(10, weight: .semibold)).tracking(1)
                    .foregroundColor(CodepetTheme.mutedText)
                // THE DECISION, in one line — the first sentence is the call; reasoning belongs
                // in the reader ("Read the full call").
                Text(BriefDocument.headline(brief.recommendation))
                    .font(CodepetTheme.inter(17, weight: .semibold)).lineSpacing(3)
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                // Rule 7: dots, and a word — never a number.
                HStack(spacing: 8) {
                    VCConfidenceDots(value: brief.confidence)
                    Text(MeetingWords.confidence(brief.confidence, lang: lang)
                         + (names.isEmpty ? "" : " · " + MeetingWords.list(names, lang: lang)))
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .padding(.top, 10)
                if brief.unresolved {
                    // Rule 6: unresolved is a valid outcome — the trade-off is the founder's.
                    Text(lang == .vi ? "CHƯA NGÃ NGŨ — BẠN QUYẾT" : "UNRESOLVED — YOUR CALL")
                        .font(CodepetTheme.inter(10, weight: .bold)).tracking(0.8)
                        .foregroundColor(CodepetTheme.accentGold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(CodepetTheme.accentGold.opacity(0.14)))
                        .padding(.top, 10)
                }
                realDisagreement(brief).padding(.top, 18)
                // LAST of the reading content — rule 5, and in full.
                if let options, !lockedIn {
                    Text(lang == .vi ? "Bạn quyết" : "Your call")
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .padding(.top, 20)
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                            optionTile(o, selected: pickedOption == i) { pickedOption = i }
                        }
                    }
                    .padding(.top, 10)
                } else {
                    Text(brief.tradeoffFounderMustOwn).font(CodepetTheme.inter(14)).lineSpacing(5)
                        .foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)
                }
                callFooter(brief, options: options)
            }
        }
    }

    /// Rule 3: `the_real_disagreement` verbatim, never behind a disclosure — now inside the call
    /// under a warm rule, so it reads as the thread from the meeting rather than a second panel.
    private func realDisagreement(_ brief: VCBrief) -> some View {
        let real = brief.theRealDisagreement.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs = state.conflicts.filter { $0.kind != "ALIGNED" }
        let agreed = state.conflicts.filter { $0.kind == "ALIGNED" }
        return VStack(alignment: .leading, spacing: 6) {
            Text(pairs.isEmpty ? (lang == .vi ? "HỌ ĐỒNG Ý" : "WHERE THEY AGREE")
                               : (lang == .vi ? "BẤT ĐỒNG THẬT SỰ" : "THE REAL DISAGREEMENT"))
                .font(CodepetTheme.inter(10, weight: .semibold)).tracking(1)
                .foregroundColor(pairs.isEmpty ? CodepetTheme.mutedText : CodepetTheme.accentOrange)
            if let split = SplitSummary.line(pairs, name: { displayName(agentId: $0) }, lang: lang) {
                Text(split)
                    .font(CodepetTheme.inter(13, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !real.isEmpty {
                Text(real).font(CodepetTheme.inter(13)).lineSpacing(4)
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !agreed.isEmpty {
                Text(agreedLine(agreed))
                    .font(CodepetTheme.inter(12))
                    .foregroundColor(CodepetTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle().fill(pairs.isEmpty ? CodepetTheme.hairline : CodepetTheme.accentOrange).frame(width: 2)
        }
    }

    /// Links on the left, the one action on the right. "Lock this in" appears only once an option
    /// is picked, so a stray click on the card can never decide for the founder.
    ///
    /// Once locked in, the footer leads with what was locked ("Locked in · <pick> · saved to
    /// memory") and the links move right. That line is the only receipt: the 📌 "Noted" strip
    /// that used to sit under the card said the same thing again (7 Oct design pass).
    private func callFooter(_ brief: VCBrief, options: [VCFounderOption]?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(CodepetTheme.hairline).frame(height: 1)
            if lockedIn {
                // One row when the whole receipt fits beside the links; otherwise the links drop
                // to a second row so the pick is never cut to "Low-friction i…" (seen live 7 Oct
                // on a 640pt card).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        lockedInReceipt.fixedSize()
                        Spacer(minLength: 8)
                        callLinks(brief)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        lockedInReceipt
                        HStack(spacing: 16) { callLinks(brief) }
                    }
                }
                .padding(.top, 12)
            } else {
                HStack(spacing: 16) {
                    callLinks(brief)
                    Spacer(minLength: 8)
                    if state.canLockIn, let options {
                        if let i = pickedOption, options.indices.contains(i) {
                            lockButton(FounderChoice.lockInTitle(options[i], lang: lang)) {
                                (onLockInChoice ?? { _ in onLockIn() })(options[i])
                            }
                        }
                    } else if state.canLockIn {
                        lockButton(lang == .vi ? "Chốt quyết định này" : "Lock this decision in", action: onLockIn)
                    }
                }
                .padding(.top, 12)
            }
        }
        .padding(.top, 18)
    }

    @ViewBuilder private func callLinks(_ brief: VCBrief) -> some View {
        if let open = onOpenRecord {
            footerLink(RoomRecord.linkTitle(lang)) { open(.stances) }
        }
        if BriefDocument.hasMore(brief) {
            footerLink(lang == .vi ? "Đọc toàn bộ quyết định" : "Read the full call") {
                readingCall = BriefDocument.document(brief, language: lang)
            }
        }
    }

    /// "✓ Locked in · Naive unit-number lookup · saved to memory": one line; on its own row the
    /// pick truncates only when even that row is too narrow.
    private var lockedInReceipt: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CodepetTheme.accentTeal)
            Text(LockInReceiptCopy.lockedIn(lang))
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(CodepetTheme.accentTeal)
                .fixedSize()
            if let pick = LockInReceiptCopy.pick(lockedInChoice) {
                Text("·").foregroundColor(CodepetTheme.mutedText)
                Text(pick)
                    .font(CodepetTheme.inter(12, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(-1)
            }
            Text("· " + LockInReceiptCopy.saved(lang))
                .font(CodepetTheme.inter(12))
                .foregroundColor(CodepetTheme.mutedText)
                .fixedSize()
        }
        .font(CodepetTheme.inter(12))
        .accessibilityElement(children: .combine)
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CodepetTheme.inter(12, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
                .underline(color: CodepetTheme.hairline)
        }
        .buttonStyle(.plain)
        .cursorOnHover(.pointingHand)
    }

    private func lockButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CodepetTheme.inter(12, weight: .semibold))
                .foregroundColor(CodepetTheme.onAccent(CodepetTheme.accentPurple))
                .padding(.horizontal, 14).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CodepetTheme.accentPurple))
        }
        .buttonStyle(.plain)
        .cursorOnHover(.pointingHand)
    }

    /// One of the room's two options: a radio, a label and what choosing it commits the founder to.
    private func optionTile(_ o: VCFounderOption, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .stroke(selected ? CodepetTheme.accentPurple : CodepetTheme.mutedText.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().fill(selected ? CodepetTheme.accentPurple : Color.clear).frame(width: 6, height: 6))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(o.label)
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(o.consequence)
                        .font(CodepetTheme.inter(12))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? CodepetTheme.accentPurple.opacity(0.10) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(selected ? CodepetTheme.accentPurple : CodepetTheme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cursorOnHover(.pointingHand)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // Written for the founder by the backend — shown verbatim (contract).
    private func stoppedRow(_ reason: String) -> some View {
        Text(reason).font(CodepetTheme.inter(13)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
    }

    // Contract: `error` is terminal, no `done` follows — this is the only signal
    // of a failed run, so it must be visible, not muted like `stoppedRow`.
    private func terminalErrorCard(_ code: String) -> some View {
        MessageCard(hue: Color.red) {
            VStack(alignment: .leading, spacing: 6) {
                label(lang == .vi ? "LỖI" : "ERROR")
                Text((lang == .vi ? "Phiên chạy đã dừng: " : "The run stopped: ") + code)
                    .font(CodepetTheme.inter(13, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
            }
        }
    }

    private func errorRow(_ meta: VCAgentMeta, _ error: String) -> some View {
        Text("\(displayName(meta)): \(error)")
            .font(CodepetTheme.inter(13)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(CodepetTheme.inter(10, weight: .semibold)).tracking(0.5)
            .foregroundColor(CodepetTheme.mutedText)
    }

    /// A founder-facing name for an agent we have only an id for — the `excluded`
    /// map is keyed by id and carries no `agent_meta`.
    ///
    /// Title-casing the id lands on exactly the client's own department names for
    /// all nine (engineering → Engineering, operations → Operations), so this stays
    /// consistent with the invited rows above WITHOUT duplicating the backend's
    /// id→`Department.key` mapping here, where it would silently drift.
    private func roleName(_ agentId: String) -> String {
        switch agentId {
        case "chief_of_staff":  return lang == .vi ? "Ban điều hành" : "Chief of staff"
        case "devils_advocate": return lang == .vi ? "Người phản biện" : "The Challenger"
        default:
            return agentId.split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    private func displayName(_ meta: VCAgentMeta) -> String {
        if let dept = DepartmentCatalog.all.first(where: { $0.key == meta.departmentKey }) {
            return dept.name
        }
        // The two department_key == null roles (contract's mapping table) are not
        // departments and have no catalog entry; name them by role, not a raw id.
        switch meta.agentId {
        case "chief_of_staff":  return lang == .vi ? "Ban điều hành" : "Chief of staff"
        case "devils_advocate": return lang == .vi ? "Người phản biện" : "The Challenger"
        default:                return meta.agentId
        }
    }

    /// Same names, resolved from a bare `agent_id` — conflicts and negotiation turns
    /// carry only the id, and `devils_advocate` / `chief_of_staff` / `finance` are wire
    /// values, never something to print at a founder. The department key comes from the
    /// agent's own `agent_start`/`agent_meta` entry when there is one.
    private func displayName(agentId: String) -> String {
        let meta = state.agents.first { $0.agentId == agentId }
            ?? state.routing?.agentMeta.first { $0.agentId == agentId }
        return displayName(meta ?? VCAgentMeta(agentId: agentId, departmentKey: nil))
    }

    private func accent(_ meta: VCAgentMeta) -> Color {
        if let dept = DepartmentCatalog.all.first(where: { $0.key == meta.departmentKey }) {
            return dept.accent
        }
        // Contract rule 9 / the mapping table: the challenger must NOT wear a department
        // colour. The old fallback handed it `accentPurple` — Design's, Sales' and
        // Legal's — which is exactly the misrepresentation the rule forbids. It gets the
        // same ink as its own verdict card instead.
        // The chief of staff falls through to neutral ink for the same reason: every
        // accent in the theme is already some department's.
        return meta.agentId == "devils_advocate" ? CodepetTheme.primaryText : CodepetTheme.mutedText
    }

    private func stanceLabel(_ stance: String) -> String {
        switch (stance, lang) {
        case ("proceed", .vi):                 return "nên làm"
        case ("proceed", _):                   return "proceed"
        case ("proceed_with_conditions", .vi): return "làm, có điều kiện"
        case ("proceed_with_conditions", _):   return "with conditions"
        case ("do_not_proceed", .vi):          return "không nên"
        default:                               return "do not proceed"
        }
    }
}

/// "How the team decided" (CP-032): the landed room's record, in the side column the pane
/// already uses for a Team Build step, or a sheet in the dock.
struct RoomRecordPanel: View {
    let state: VirtualCompanyRunState
    @Binding var tab: RoomRecordTab
    let onClose: () -> Void

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang == .vi ? "Cả đội đã quyết định thế nào" : "How the team decided")
                    .font(CodepetTheme.inter(CodepetType.title3, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .buttonStyle(.plain)
                .help(lang == .vi ? "Đóng" : "Close")
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            HStack(spacing: 2) {
                ForEach(RoomRecordTab.allCases) { t in
                    Button { tab = t } label: {
                        Text(t.title(state, lang: lang))
                            .font(CodepetTheme.inter(12, weight: tab == t ? .semibold : .regular))
                            .foregroundColor(tab == t ? CodepetTheme.primaryText : CodepetTheme.mutedText)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .overlay(alignment: .bottom) {
                                if tab == t { Rectangle().fill(CodepetTheme.accentPurple).frame(height: 2) }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            Divider().overlay(CodepetTheme.hairline)
            ScrollView {
                VCRunCards(state: state, lockedIn: false, onLockIn: {}, recordTab: tab)
                    .padding(.horizontal, 6).padding(.vertical, 12)
            }
        }
        .background(CodepetTheme.pageBackground)
    }
}

/// The call card's locked-in receipt (7 Oct design pass, CP-075). Pure, so the copy is
/// testable without a view.
enum LockInReceiptCopy {
    static func lockedIn(_ lang: AppLanguage) -> String { lang == .vi ? "Đã chốt" : "Locked in" }
    static func saved(_ lang: AppLanguage) -> String { lang == .vi ? "đã lưu vào bộ nhớ" : "saved to memory" }
    /// The pick to name, or nil when there is none worth naming (a lock-in of the room's own
    /// recommendation, which is already the card's headline).
    static func pick(_ label: String?) -> String? {
        guard let t = label?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
