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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let routing = state.routing { routingCard(routing) }
            if !state.agents.isEmpty { agentsAtWorkCard }
            ForEach(state.agents, id: \.agentId) { meta in
                if let position = state.positions[meta.agentId] {
                    positionCard(meta, position)
                }
                if let error = state.agentErrors[meta.agentId] {
                    errorRow(meta, error)
                }
            }
            if !state.conflicts.isEmpty { conflictCard }
            ForEach(state.negotiationRounds, id: \.round) { roundCard($0) }
            if let verdict = state.verdict { verdictCard(verdict) }
            if let brief = state.brief { briefCard(brief) }
            if let stopped = state.stoppedReason { stoppedRow(stopped) }
            // Contract: `error` is terminal and no `done` follows — after a failed
            // run this is the ONLY signal the founder gets that the room stopped.
            if let err = state.terminalError { terminalErrorCard(err) }
            // Spec §4.3: the founder has a right to know what the answer cost them —
            // including when the answer never arrived. Telemetry is emitted on the
            // escape hatch and on a budget stop too, so this is the one place it belongs.
            if let cost = state.telemetry?.costEstimateUsd { costRow(cost) }
        }
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
    private var agentsAtWorkCard: some View {
        HStack {
            MessageCard(hue: CodepetTheme.accentPurple) {
                VStack(alignment: .leading, spacing: 10) {
                    Text((lang == .vi ? "Đang làm việc" : "Agents at work")
                            + " · \(state.agentStatuses.count)")
                        .font(CodepetTheme.inter(10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(CodepetTheme.mutedText)
                    ForEach(Array(state.agentStatuses.enumerated()), id: \.offset) { idx, entry in
                        if idx > 0 { Divider().overlay(CodepetTheme.hairline) }
                        HStack(spacing: 8) {
                            Circle()
                                .fill(accent(entry.meta).opacity(0.16))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Text(badge(entry.meta))
                                        .font(CodepetTheme.inter(9, weight: .semibold))
                                        .foregroundColor(accent(entry.meta))
                                )
                            Text(displayName(entry.meta))
                                .font(CodepetTheme.inter(12, weight: .semibold))
                                .foregroundColor(CodepetTheme.primaryText)
                            Spacer(minLength: 6)
                            statusPill(entry.status)
                        }
                    }
                }
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        return MessageCard(hue: allAligned ? CodepetTheme.accentTeal : CodepetTheme.accentOrange) {
            VStack(alignment: .leading, spacing: 6) {
                label(allAligned ? (lang == .vi ? "HỌ ĐỒNG Ý Ở ĐÂU" : "WHERE THEY AGREE")
                                 : (lang == .vi ? "HỌ KHÔNG ĐỒNG Ý Ở ĐÂU" : "WHERE THEY DISAGREE"))
                // `id: \.offset`, not `\.reason`: the reason is free text the model
                // writes, and two identical reasons (likely in the all-ALIGNED flow)
                // silently collapsed into one row.
                ForEach(Array(state.conflicts.enumerated()), id: \.offset) { _, conflict in
                    Text("\(displayName(agentId: conflict.a)) ↔ \(displayName(agentId: conflict.b))"
                         + " · \(kindLabel(conflict.kind))")
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(conflict.reason).font(CodepetTheme.inter(14)).lineSpacing(6)
                        .foregroundColor(CodepetTheme.bodyText)
                }
            }
        }
    }

    private func roundCard(_ round: VCNegotiationRound) -> some View {
        MessageCard(hue: CodepetTheme.hairline) {
            VStack(alignment: .leading, spacing: 6) {
                label((lang == .vi ? "VÒNG " : "ROUND ") + "\(round.round)")
                // `id: \.offset`, not `\.agent`: one agent can take two turns in a
                // round, and the second one vanished.
                ForEach(Array(round.turns.enumerated()), id: \.offset) { _, turn in
                    Text("\(displayName(agentId: turn.agent)): \(turn.preciseDisagreement)")
                        .font(CodepetTheme.inter(14)).lineSpacing(6).foregroundColor(CodepetTheme.bodyText)
                    Text((lang == .vi ? "Đề xuất: " : "Proposes: ") + turn.proposal)
                        .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
                    // Contract rule 4: show each side's what_would_change_my_mind —
                    // it teaches that disagreement is settled by evidence, not authority.
                    Text((lang == .vi ? "Điều gì sẽ đổi ý họ: " : "What would change their mind: ")
                         + turn.whatWouldChangeMyMind)
                        .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
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

    private func briefCard(_ brief: VCBrief) -> some View {
        MessageCard(hue: CodepetTheme.accentPurple) {
            VStack(alignment: .leading, spacing: 8) {
                label(lang == .vi ? "KHUYẾN NGHỊ" : "RECOMMENDATION")
                Text(brief.recommendation).font(CodepetTheme.inter(14.5)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.bodyText)
                HStack(spacing: 8) {
                    // Contract rule 7: confidence as dots, not a number.
                    confidenceDots(brief.confidence)
                    Text(brief.confidenceReason).font(CodepetTheme.inter(13.5)).lineSpacing(5)
                        .foregroundColor(CodepetTheme.mutedText)
                }
                // Contract rule 3: show the_real_disagreement verbatim. No
                // paraphrasing, no softening.
                label(lang == .vi ? "BẤT ĐỒNG THẬT SỰ" : "THE REAL DISAGREEMENT")
                Text(brief.theRealDisagreement).font(CodepetTheme.inter(14)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.bodyText)
                label(lang == .vi ? "ĐÁNH ĐỔI CHỈ BẠN QUYẾT ĐƯỢC" : "THE TRADE-OFF ONLY YOU CAN MAKE")
                Text(brief.tradeoffFounderMustOwn).font(CodepetTheme.inter(14)).lineSpacing(6)
                    .foregroundColor(CodepetTheme.bodyText)
                if brief.unresolved {
                    // Contract rule 6: unresolved is a valid outcome, not an error —
                    // present it as an honest answer, the trade-off is the founder's to make.
                    Text(lang == .vi ? "Chưa ngã ngũ — đây là lựa chọn của bạn."
                                     : "Unresolved — this is your call to make.")
                        .font(CodepetTheme.inter(13, weight: .medium))
                        .foregroundColor(CodepetTheme.primaryText)
                }
                label(lang == .vi ? "DỪNG NẾU" : "STOP IF")
                ForEach(brief.killCriteria, id: \.self) { criterion in
                    Text("· " + criterion).font(CodepetTheme.inter(14)).lineSpacing(6)
                        .foregroundColor(CodepetTheme.bodyText)
                }
                Text((lang == .vi ? "Việc tiếp theo (\(brief.nextAction.owner)): "
                                  : "Next action (\(brief.nextAction.owner)): ") + brief.nextAction.action)
                    .font(CodepetTheme.inter(13, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                Text((lang == .vi ? "Vẫn chưa biết: " : "Still unknown: ") + brief.whatWeDontKnow)
                    .font(CodepetTheme.inter(13.5)).lineSpacing(5).foregroundColor(CodepetTheme.mutedText)
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

    private func badge(_ meta: VCAgentMeta) -> String {
        if let dept = DepartmentCatalog.all.first(where: { $0.key == meta.departmentKey }) {
            return dept.ab
        }
        switch meta.agentId {
        case "chief_of_staff":  return "CoS"
        case "devils_advocate": return "DA"
        default:                return String(meta.agentId.prefix(2)).uppercased()
        }
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
