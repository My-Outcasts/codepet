// codepet/Views/Copilot/VirtualCompanyCards.swift
import SwiftUI

/// The room, rendered inside the chat. Stacked vertically because the dock is
/// 380pt wide — positions cannot sit in columns here, so they read as a sequence.
struct VCRunCards: View {
    let state: VirtualCompanyRunState
    /// The founder has already locked this brief in — the card says so instead of
    /// offering the button a second time. Carried on the message (`actionConsumed`),
    /// not inside the run state, so a `telemetry`/`done` frame arriving after the tap
    /// cannot un-consume it.
    let lockedIn: Bool
    let onLockIn: () -> Void

    @Environment(\.uiLanguage) private var lang
    /// The call, opened in the reader every other document in the app opens into.
    @State private var readingCall: Deliverable?

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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let brief = state.brief {
                theCall(brief)
                // ONE card, not two — see `landedDisagreement`. `conflictCard` is now the
                // in-flight rendering only, where there is no narrative to duplicate.
                landedDisagreement(brief)
                Disclosure(title: (lang == .vi ? "Từng phòng ban đã nói gì" : "What each department said")
                            + " · \(state.agents.count)") {
                    departmentsSaid
                }
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
                if let routing = state.routing { roomHeaderCard(routing) }
                if state.agents.contains(where: { answered($0.agentId) }) { liveAgents }
                if !state.conflicts.isEmpty { conflictCard }
                // Behind a disclosure while the room is still running, matching what already
                // happens once the brief lands. In flight these dumped inline, and a round is the
                // longest thing the room produces — several screens of two departments arguing,
                // above the answer the founder is waiting for (founder, Aug 6).
                if !state.negotiationRounds.isEmpty {
                    Disclosure(title: (lang == .vi ? "Họ thương lượng thế nào" : "How they negotiated")
                                + " · \(state.negotiationRounds.count)") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(state.negotiationRounds, id: \.round) { roundCard($0) }
                        }
                    }
                }
                if let verdict = state.verdict { verdictCard(verdict) }
            }
            if let stopped = state.stoppedReason { stoppedRow(stopped) }
            // Contract: `error` is terminal and no `done` follows — after a failed
            // run this is the ONLY signal the founder gets that the room stopped.
            if let err = state.terminalError { terminalErrorCard(err) }
            // Spec §4.3: the founder has a right to know what the answer cost them —
            // including when the answer never arrived. Telemetry is emitted on the
            // escape hatch and on a budget stop too, so this is the one place it belongs.
            if let cost = state.telemetry?.costEstimateUsd { costRow(cost) }
        }
        .sheet(item: $readingCall) { DeliverableDetailView(deliverable: $0) }
    }

    private func costRow(_ cost: Double) -> some View {
        Text(String(format: (lang == .vi ? "Phiên này tốn $%.3f" : "This run cost $%.3f"), cost))
            .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
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

    /// THE ROOM, in flight: one card, five elements.
    ///
    /// Built with its own chrome rather than `MessageCard`, which applies one uniform inset — this
    /// card has bands (a recessed footer that reaches the card's edges), so it owns its padding.
    /// The visual language is MessageCard's exactly: surface, hue at 12%, a same-hue 1pt border,
    /// radius 12.
    private func roomHeaderCard(_ routing: VCRouting) -> some View {
        let hue = CodepetTheme.accentPurple
        let roster = routing.agentMeta
        let done = roster.filter { answered($0.agentId) }.count
        return HStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        label(lang == .vi ? "PHÒNG HỌP" : "THE ROOM")
                        Spacer(minLength: 6)
                        // Counted, never estimated — and a count rather than a percentage,
                        // because a percentage of three departments implies precision that is
                        // not there. Real state only (rule 8).
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(done)")
                                .font(CodepetTheme.inter(24, weight: .semibold))
                                .tracking(-0.6)
                                .monospacedDigit()
                                .foregroundColor(CodepetTheme.primaryText)
                            Text(lang == .vi ? "/ \(roster.count) đã trả lời"
                                             : "of \(roster.count) answered")
                                .font(CodepetTheme.inter(11))
                                .foregroundColor(CodepetTheme.mutedText)
                        }
                        .fixedSize()
                    }
                    Text(routing.realQuestion)
                        .font(CodepetTheme.inter(15, weight: .semibold))
                        .lineSpacing(3)
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 9)
                    rosterBar(roster)
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 13)

                // The recessed footer, split in two — reaches the card's edges, so it needs the
                // card to own its padding (see the note above).
                HStack(spacing: 0) {
                    footCell(key: lang == .vi ? "TRONG PHÒNG" : "IN THE ROOM",
                             value: "\(roster.count)",
                             unit: lang == .vi ? "phòng ban" : roster.count == 1 ? "department" : "departments")
                    Rectangle().fill(CodepetTheme.hairline).frame(width: 1)
                    footCell(key: lang == .vi ? "KHÔNG MỜI" : "SAT OUT",
                             value: "\(routing.excluded.count)",
                             unit: lang == .vi ? "đều có lý do" : "with reasons")
                }
                .background(Color.black.opacity(0.16))
                .overlay(alignment: .top) { Rectangle().fill(CodepetTheme.hairline).frame(height: 1) }

                // The thirteen paragraphs, behind one full-width control.
                Disclosure(title: lang == .vi ? "Vì sao chọn những phòng ban này?"
                                              : "Why these departments?") {
                    routingDetail(routing)
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CodepetTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hue.opacity(0.12)))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hue.opacity(0.9), lineWidth: 1))
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One segment per department, filled in that department's colour when its position lands.
    ///
    /// The segment is the roster AND the progress — your first reference's segmented bar, except
    /// each segment means something. Nothing animates toward completion: a segment is empty or
    /// full, because a partial fill would be the artificial progress rule 8 forbids. Departments
    /// still thinking pulse their empty track, which is liveness, not progress.
    private func rosterBar(_ roster: [VCAgentMeta]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(roster, id: \.agentId) { meta in
                    RosterSegment(color: accent(meta), filled: answered(meta.agentId))
                }
            }
            HStack(spacing: 5) {
                ForEach(roster, id: \.agentId) { meta in
                    Text(displayName(meta).uppercased())
                        .font(CodepetTheme.inter(8.5, weight: .semibold))
                        .tracking(0.7)
                        .foregroundColor(answered(meta.agentId) ? accent(meta) : CodepetTokens.faint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 13)
    }

    private func footCell(key: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(CodepetTheme.inter(9, weight: .semibold)).tracking(1)
                .foregroundColor(CodepetTokens.faint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(CodepetTheme.inter(14, weight: .semibold)).monospacedDigit()
                    .foregroundColor(CodepetTheme.primaryText)
                Text(unit)
                    .font(CodepetTheme.inter(11))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    /// The departments that have ANSWERED (or failed). The working ones are the header's segments
    /// now, so this card no longer repeats them as titled rows.
    private var liveAgents: some View {
        let landed = state.agentStatuses.filter { hasLanded($0.meta.agentId) }
        return HStack {
            MessageCard(hue: CodepetTheme.accentPurple) {
                VStack(alignment: .leading, spacing: 12) {
                    Text((lang == .vi ? "Đã trả lời" : "Answered") + " · \(landed.count)")
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(CodepetTheme.mutedText)
                    ForEach(Array(landed.enumerated()), id: \.offset) { idx, entry in
                        if idx > 0 { Divider().overlay(CodepetTheme.hairline) }
                        agentRow(entry)
                    }
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func agentRow(_ entry: (meta: VCAgentMeta, status: AgentRunStatus)) -> some View {
        let position = state.positions[entry.meta.agentId]
        VStack(alignment: .leading, spacing: 8) {
            // The DEPARTMENT leads, in its own colour and at the run-theater's title size.
            //
            // It used to lead with a 20pt circle holding a two-letter badge ("Fi", "Pr", "Mk"),
            // which read as an initials avatar for a person who does not exist and left the
            // department itself as smaller, quieter text beside it (founder, Aug 6: "that's the
            // old version"). The department IS the identity here, so it gets the ink. The badge
            // is gone rather than restyled — an abbreviation earns its place only when there is
            // no room for the word, and there is.
            //
            // Still no pet sprite and no personal name: contract rule 9. A department NAME is not
            // a personal name, so setting it in full weight stays inside the rule.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayName(entry.meta).uppercased())
                    .font(CodepetTheme.inter(11.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(accent(entry.meta))
                    .lineLimit(1)
                if let position {
                    Text(stanceLabel(position.stance))
                        .font(CodepetTheme.inter(11, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent(entry.meta).opacity(0.12)))
                        .foregroundColor(accent(entry.meta))
                }
                Spacer(minLength: 6)
                // Contract rule 7: dots, never a number.
                if let position { confidenceDots(position.confidence) } else { statusPill(entry.status) }
            }
            if let position {
                // One line at rest, the whole thing on tap.
                //
                // Three departments each printed a full paragraph plus, for two of them, a bold
                // 🔒 blocker paragraph — five paragraphs before the founder reached the conflict
                // card, which then printed those same two blockers again VERBATIM (Aug 6:
                // "displays too much information all at once"). Rule 2 forbids SUMMARISING the
                // positions into one paragraph; it does not require every one of them open at
                // once, and the text here is never rewritten — it is the same string, clamped
                // until asked for. Post-brief `departmentsSaid` has always worked this way.
                //
                // The 🔒 line is gone from this row entirely: rule 4 pins the blocker to the
                // CONFLICT card, which is where the founder can act on it, and printing it in
                // both places is what made this card feel like a wall.
                ExpandingPosition(text: position.position)
            } else if let error = state.agentErrors[entry.meta.agentId] {
                Text(error).font(CodepetTheme.inter(13)).foregroundColor(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // No "still working" branch: `liveAgents` is filtered to departments that have landed,
            // and the header card's segments are where waiting is shown now. The panel that used to
            // sit here — spinner, a sentence, and a bar, per department — was mine from Aug 6 and
            // was most of what made the room feel cluttered.
        }
    }

    /// Every department's full position, verbatim and individually — contract rule 2 forbids
    /// summarising them into one paragraph, and a disclosure is a place to put them, not a
    /// licence to condense them.
    private var departmentsSaid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(state.agents, id: \.agentId) { meta in
                if let position = state.positions[meta.agentId] {
                    positionCard(meta, position)
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
        return MessageCard(hue: pairs.isEmpty ? CodepetTheme.accentTeal : CodepetTheme.accentOrange) {
            VStack(alignment: .leading, spacing: 8) {
                label(pairs.isEmpty ? (lang == .vi ? "HỌ ĐỒNG Ý" : "WHERE THEY AGREE")
                                    : (lang == .vi ? "BẤT ĐỒNG THẬT SỰ" : "THE REAL DISAGREEMENT"))
                if !pairs.isEmpty {
                    // One line per pair: who, and how hard. `id: \.offset` because `reason` is
                    // free text and two identical reasons silently collapsed into one row.
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(pairs.enumerated()), id: \.offset) { _, c in
                            Text("\(displayName(agentId: c.a)) ↔ \(displayName(agentId: c.b))"
                                 + " · \(kindLabel(c.kind))")
                                .font(CodepetTheme.inter(12.5, weight: .semibold))
                                .foregroundColor(CodepetTheme.mutedText)
                        }
                    }
                }
                if !real.isEmpty {
                    Text(real).font(CodepetTheme.inter(14)).lineSpacing(6)
                        .foregroundColor(CodepetTheme.bodyText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !agreed.isEmpty {
                    Text(agreedLine(agreed))
                        .font(CodepetTheme.inter(12.5))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A department's position: one line at rest, the full text on tap.
    ///
    /// The text is never altered — clamping is not summarising (rule 2). Expanding is the founder
    /// asking for it, which is the same bargain `departmentsSaid` has always offered after the
    /// brief lands; this brings the in-flight card in line with it.
    private struct ExpandingPosition: View {
        let text: String
        @State private var open = false

        var body: some View {
            Button { withAnimation(.easeInOut(duration: 0.16)) { open.toggle() } } label: {
                Text(text)
                    .font(CodepetTheme.inter(14)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(open ? nil : 1)
                    .fixedSize(horizontal: false, vertical: open)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursorOnHover(.pointingHand)
        }
    }

    /// One department's segment in the roster bar.
    ///
    /// Two states only — empty or full. There is no in-between, because a segment creeping toward
    /// full would be inventing progress the backend never reported (rule 8): a room agent thinks,
    /// and then a position lands. While it is still thinking the empty track breathes, which says
    /// "alive" without claiming how far along it is.
    private struct RosterSegment: View {
        let color: Color
        let filled: Bool
        @State private var breathing = false

        var body: some View {
            Capsule()
                .fill(filled ? AnyShapeStyle(LinearGradient(
                        colors: [color.opacity(0.65), color],
                        startPoint: .leading, endPoint: .trailing))
                             : AnyShapeStyle(CodepetTokens.well))
                .frame(height: 5)
                .frame(maxWidth: .infinity)
                .opacity(filled ? 1 : (breathing ? 0.95 : 0.5))
                .animation(.easeInOut(duration: 0.35), value: filled)
                .onAppear {
                    guard !filled else { return }
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        breathing = true
                    }
                }
        }
    }

    /// A collapsed section of the room. Closed by default: the founder opens the process she
    /// wants rather than scrolling past all of it to reach the answer.
    private struct Disclosure<Content: View>: View {
        let title: String
        @ViewBuilder var content: Content
        @State private var open = false

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

    private func statusPill(_ status: AgentRunStatus) -> some View {
        let fg: Color
        let bg: Color
        switch status {
        case .working:   fg = CodepetTheme.accentPurple; bg = CodepetTheme.accentPurple.opacity(0.14)
        case .reviewing: fg = CodepetTheme.accentGold;   bg = CodepetTheme.accentGold.opacity(0.16)
        case .done:      fg = CodepetTheme.accentTeal;   bg = CodepetTheme.accentTeal.opacity(0.16)
        case .failed:    fg = Color.red;                 bg = Color.red.opacity(0.14)
        }
        return Text(status.label(lang))
            .font(CodepetTheme.inter(9, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
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
                        .font(CodepetTheme.inter(13.5)).lineSpacing(5)
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
                        .font(CodepetTheme.inter(13.5)).lineSpacing(5)
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !routing.missingInfo.isEmpty {
                Text((lang == .vi ? "Còn thiếu: " : "Missing: ")
                     + routing.missingInfo.joined(separator: "; "))
                    .font(CodepetTheme.inter(13.5)).lineSpacing(5)
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
                    .font(CodepetTheme.inter(16.5, weight: .semibold)).lineSpacing(6)
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
                            .font(CodepetTheme.inter(13.5)).lineSpacing(5)
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                if !routing.missingInfo.isEmpty {
                    Text((lang == .vi ? "Còn thiếu: " : "Missing: ")
                         + routing.missingInfo.joined(separator: "; "))
                        .font(CodepetTheme.inter(13.5)).lineSpacing(5)
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }

    private func positionCard(_ meta: VCAgentMeta, _ position: VCPosition) -> some View {
        MessageCard(hue: accent(meta)) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(displayName(meta)).font(CodepetTheme.sectionName())
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(stanceLabel(position.stance))
                        .font(CodepetTheme.inter(11, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(accent(meta).opacity(0.12)))
                        .foregroundColor(accent(meta))
                    Spacer()
                    // Contract rule 7: confidence as dots, not a number — a number
                    // implies false precision.
                    confidenceDots(position.confidence)
                }
                Text(position.position).font(CodepetTheme.inter(14.5)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.bodyText)
                Text((lang == .vi ? "Cái này khiến họ mất: " : "Costs their department: ")
                     + position.costToMyDept)
                    .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                if let blocker = position.hardBlocker {
                    Text("🔒 " + blocker)
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                }
            }
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
                // `id: \.offset`, not `\.reason`: the reason is free text the model
                // writes, and two identical reasons (likely in the all-ALIGNED flow)
                // silently collapsed into one row.
                ForEach(Array(disagreements.enumerated()), id: \.offset) { _, conflict in
                    Text("\(displayName(agentId: conflict.a)) ↔ \(displayName(agentId: conflict.b))"
                         + " · \(kindLabel(conflict.kind))")
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(conflict.reason).font(CodepetTheme.inter(14)).lineSpacing(6)
                        .foregroundColor(CodepetTheme.bodyText)
                }
                if !agreed.isEmpty {
                    Text(agreedLine(agreed))
                        .font(CodepetTheme.inter(12.5))
                        .foregroundColor(CodepetTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
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
                            .font(CodepetTheme.inter(12.5)).foregroundColor(CodepetTokens.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(displayName(agentId: turn.agent)): \(turn.preciseDisagreement)")
                            .font(CodepetTheme.inter(14)).lineSpacing(6).foregroundColor(CodepetTheme.bodyText)
                        // Each field only earns its heading when it has something under it.
                        if !turn.proposal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text((lang == .vi ? "Đề xuất: " : "Proposes: ") + turn.proposal)
                                .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                        }
                        // Contract rule 4: show each side's what_would_change_my_mind —
                        // it teaches that disagreement is settled by evidence, not authority.
                        if !turn.whatWouldChangeMyMind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text((lang == .vi ? "Điều gì sẽ đổi ý họ: " : "What would change their mind: ")
                                 + turn.whatWouldChangeMyMind)
                                .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
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
                Text(verdict.loadBearingAssumption).font(CodepetTheme.inter(14.5, weight: .medium)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.primaryText)
                if verdict.planIsSound {
                    Text(lang == .vi ? "Đã kiểm — kế hoạch vững." : "Stress-tested — the plan holds.")
                        .font(CodepetTheme.inter(14)).lineSpacing(6).foregroundColor(CodepetTheme.bodyText)
                } else {
                    Text(verdict.howItCouldBeFalse).font(CodepetTheme.inter(14)).lineSpacing(6)
                        .foregroundColor(CodepetTheme.bodyText)
                }
                Text((lang == .vi ? "Cách kiểm rẻ nhất: " : "Cheapest test: ") + verdict.cheapestTest)
                    .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                if !verdict.objections.isEmpty {
                    label(lang == .vi ? "CÁC PHẢN BÁC" : "OBJECTIONS")
                    ForEach(Array(verdict.objections.enumerated()), id: \.offset) { idx, objection in
                        Text("\(idx + 1). " + objection)
                            .font(CodepetTheme.inter(14)).lineSpacing(6).foregroundColor(CodepetTheme.bodyText)
                    }
                }
                Text((lang == .vi ? "Nếu thất bại: " : "If this fails: ") + verdict.failurePostMortem)
                    .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                Text((lang == .vi ? "Ai không có trong phòng: " : "Who's not in the room: ")
                     + verdict.whoIsNotInTheRoom)
                    .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
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
        MessageCard(hue: CodepetTheme.accentPurple) {
            VStack(alignment: .leading, spacing: 8) {
                label(lang == .vi ? "QUYẾT ĐỊNH" : "THE CALL")
                // THE DECISION, in one line. `recommendation` runs ~200 words and the rest of the
                // card added ~350 more, all unclamped in a 380pt column (founder, Aug 7). The
                // first sentence IS the call; everything after it is reasoning, and reasoning
                // belongs in the reader.
                Text(BriefDocument.headline(brief.recommendation))
                    .font(CodepetTheme.inter(16, weight: .semibold)).lineSpacing(4)
                    .foregroundColor(CodepetTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // Contract rule 7: confidence as dots, not a number. The REASON moves to the
                // reader — it was 55 words of grey text indented under the dots.
                confidenceDots(brief.confidence)
                if brief.unresolved {
                    // Contract rule 6: unresolved is a valid outcome, not an error —
                    // present it as an honest answer, the trade-off is the founder's to make.
                    Text(lang == .vi ? "CHƯA NGÃ NGŨ — BẠN QUYẾT" : "UNRESOLVED — YOUR CALL")
                        .font(CodepetTheme.inter(10, weight: .bold)).tracking(0.8)
                        .foregroundColor(CodepetTheme.accentGold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(CodepetTheme.accentGold.opacity(0.14)))
                }
                // LAST of the reading content — rule 5, and IN FULL.
                //
                // Founder's call, Aug 7, when asked whether to clamp it: "Rule 5 says end on the
                // either/or." A two-line clamp on a ~100-word trade-off cuts before the "or", and
                // half a trade-off is not ending on the either/or — it is ending on one option,
                // which is the "it's up to you" the rule exists to forbid. So the either/or is the
                // one long thing that stays on the card.
                label(lang == .vi ? "ĐÁNH ĐỔI CHỈ BẠN QUYẾT ĐƯỢC" : "THE TRADE-OFF ONLY YOU CAN MAKE")
                Text(brief.tradeoffFounderMustOwn).font(CodepetTheme.inter(14)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                // The recommendation in full, the next action, the kill criteria and what nobody
                // knew — in the reader every other document in the app opens into (founder's
                // call: "the call should read like every other document").
                if BriefDocument.hasMore(brief) {
                    Button { readingCall = BriefDocument.document(brief, language: lang) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text").font(.system(size: 11, weight: .semibold))
                            Text(lang == .vi ? "Đọc toàn bộ quyết định" : "Read the full call")
                        }
                        .font(CodepetTheme.inter(12.5, weight: .semibold))
                        .foregroundColor(CodepetTheme.bodyText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CodepetTheme.hairline, lineWidth: 1))
                        .hoverAffordance(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .cursorOnHover(.pointingHand)
                    .padding(.top, 2)
                }
                // The cost line is NOT here: a run that failed or was budget-stopped
                // still cost the founder money and never reaches this card. It renders
                // once, for every outcome, at the bottom of the stack (`costRow`).
                if lockedIn {
                    Text("📌 " + (lang == .vi ? "Đã chốt — quyết định này giờ dẫn đường cho cả app."
                                              : "Locked in — this decision now grounds the rest of the app."))
                        .font(CodepetTheme.inter(12, weight: .medium))
                        .foregroundColor(CodepetTheme.accentTeal)
                } else if state.canLockIn {
                    // Only offered when there is something to record — see `canLockIn`.
                    Button(action: onLockIn) {
                        Text(lang == .vi ? "Chốt quyết định này" : "Lock this decision in")
                            .font(CodepetTheme.inter(13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(CodepetTheme.accentPurple))
                            .hoverAffordance(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Written for the founder by the backend — shown verbatim (contract).
    private func stoppedRow(_ reason: String) -> some View {
        Text(reason).font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
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
            .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(CodepetTheme.inter(10, weight: .semibold)).tracking(0.5)
            .foregroundColor(CodepetTheme.mutedText)
    }

    // Contract rule 7: dots, not a number — a number implies false precision.
    // Clamped defensively; the wire contract guarantees 1..5.
    private func confidenceDots(_ confidence: Int) -> some View {
        let n = max(0, min(5, confidence))
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i < n ? CodepetTheme.accentPurple : CodepetTheme.hairline)
                    .frame(width: 6, height: 6)
            }
        }
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
