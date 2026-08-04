// codepet/Views/Copilot/VirtualCompanyCards.swift
import SwiftUI

/// The room, rendered inside the chat. Stacked vertically because the dock is
/// 380pt wide — positions cannot sit in columns here, so they read as a sequence.
struct VCRunCards: View {
    let state: VirtualCompanyRunState
    let onLockIn: () -> Void

    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let routing = state.routing { routingCard(routing) }
            if !state.agents.isEmpty { AgentsWorkingRow(runs: agentRuns) }
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
        }
    }

    /// Bridges into the existing multi-agent row, which already knows how to show
    /// N concurrent agents with avatar, dept, status pill and elapsed time.
    private var agentRuns: [AgentRun] {
        state.agentStatuses.map { entry in
            let dept = DepartmentCatalog.all.first { $0.key == entry.meta.departmentKey }
            return AgentRun(id: entry.meta.agentId,
                            companionId: entry.meta.agentId,
                            deptName: dept?.name ?? (lang == .vi ? "Ban điều hành" : "Chief of staff"),
                            taskTitle: state.routing?.realQuestion ?? "",
                            steps: [],
                            status: entry.status,
                            startedAt: Date())
        }
    }

    // Spec §4.3: routing is CONTENT, not a loading state. It is the panel where
    // the founder sees their question decomposed.
    private func routingCard(_ routing: VCRouting) -> some View {
        MessageCard(hue: CodepetTheme.accentPurple) {
            VStack(alignment: .leading, spacing: 8) {
                label(lang == .vi ? "CÂU HỎI THẬT" : "THE REAL QUESTION")
                Text(routing.realQuestion)
                    .font(CodepetTheme.inter(15, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                ForEach(routing.agentMeta, id: \.agentId) { meta in
                    if let why = routing.reasonPerAgent[meta.agentId] {
                        Text("✓ \(displayName(meta)) — \(why)")
                            .font(CodepetTheme.inter(13))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                if !routing.missingInfo.isEmpty {
                    Text((lang == .vi ? "Còn thiếu: " : "Missing: ")
                         + routing.missingInfo.joined(separator: "; "))
                        .font(CodepetTheme.inter(12))
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
                    Text("\(position.confidence)/5")
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                }
                Text(position.position).font(CodepetTheme.inter(14))
                    .foregroundColor(CodepetTheme.bodyText)
                Text((lang == .vi ? "Cái này khiến họ mất: " : "Costs their department: ")
                     + position.costToMyDept)
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
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
        MessageCard(hue: CodepetTheme.accentOrange) {
            VStack(alignment: .leading, spacing: 6) {
                label(lang == .vi ? "HỌ KHÔNG ĐỒNG Ý Ở ĐÂU" : "WHERE THEY DISAGREE")
                ForEach(state.conflicts, id: \.reason) { conflict in
                    Text("\(conflict.a) ↔ \(conflict.b) · \(conflict.kind)")
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                    Text(conflict.reason).font(CodepetTheme.inter(13))
                        .foregroundColor(CodepetTheme.bodyText)
                }
            }
        }
    }

    private func roundCard(_ round: VCNegotiationRound) -> some View {
        MessageCard(hue: CodepetTheme.hairline) {
            VStack(alignment: .leading, spacing: 6) {
                label((lang == .vi ? "VÒNG " : "ROUND ") + "\(round.round)")
                ForEach(round.turns, id: \.agent) { turn in
                    Text("\(turn.agent): \(turn.preciseDisagreement)")
                        .font(CodepetTheme.inter(13)).foregroundColor(CodepetTheme.bodyText)
                    Text((lang == .vi ? "Đề xuất: " : "Proposes: ") + turn.proposal)
                        .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                }
            }
        }
    }

    // No department colour: it is not a department (contract, §4.3).
    private func verdictCard(_ verdict: VCVerdict) -> some View {
        MessageCard(hue: CodepetTheme.primaryText) {
            VStack(alignment: .leading, spacing: 6) {
                label(lang == .vi ? "NGƯỜI PHẢN BIỆN" : "THE CHALLENGER")
                Text(verdict.loadBearingAssumption).font(CodepetTheme.inter(14, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(verdict.howItCouldBeFalse).font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                Text((lang == .vi ? "Cách kiểm rẻ nhất: " : "Cheapest test: ") + verdict.cheapestTest)
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
            }
        }
    }

    private func briefCard(_ brief: VCBrief) -> some View {
        MessageCard(hue: CodepetTheme.accentPurple) {
            VStack(alignment: .leading, spacing: 8) {
                label(lang == .vi ? "KHUYẾN NGHỊ" : "RECOMMENDATION")
                Text(brief.recommendation).font(CodepetTheme.inter(14))
                    .foregroundColor(CodepetTheme.bodyText)
                label(lang == .vi ? "ĐÁNH ĐỔI CHỈ BẠN QUYẾT ĐƯỢC" : "THE TRADE-OFF ONLY YOU CAN MAKE")
                Text(brief.tradeoffFounderMustOwn).font(CodepetTheme.inter(13))
                    .foregroundColor(CodepetTheme.bodyText)
                label(lang == .vi ? "DỪNG NẾU" : "STOP IF")
                ForEach(brief.killCriteria, id: \.self) { criterion in
                    Text("· " + criterion).font(CodepetTheme.inter(13))
                        .foregroundColor(CodepetTheme.bodyText)
                }
                Text((lang == .vi ? "Việc tiếp theo (\(brief.nextAction.owner)): "
                                  : "Next action (\(brief.nextAction.owner)): ") + brief.nextAction.action)
                    .font(CodepetTheme.inter(13, weight: .medium))
                    .foregroundColor(CodepetTheme.primaryText)
                Text((lang == .vi ? "Vẫn chưa biết: " : "Still unknown: ") + brief.whatWeDontKnow)
                    .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
                if let cost = state.telemetry?.costEstimateUsd {
                    // Spec §4.3: the founder has a right to know what the answer cost.
                    Text(String(format: "$%.3f", cost))
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                Button(action: onLockIn) {
                    Text(lang == .vi ? "Chốt quyết định này" : "Lock this decision in")
                        .font(CodepetTheme.inter(13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CodepetTheme.accentPurple))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Written for the founder by the backend — shown verbatim (contract).
    private func stoppedRow(_ reason: String) -> some View {
        Text(reason).font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
    }

    private func errorRow(_ meta: VCAgentMeta, _ error: String) -> some View {
        Text("\(displayName(meta)): \(error)")
            .font(CodepetTheme.inter(12)).foregroundColor(CodepetTheme.mutedText)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(CodepetTheme.inter(10, weight: .semibold)).tracking(0.5)
            .foregroundColor(CodepetTheme.mutedText)
    }

    private func displayName(_ meta: VCAgentMeta) -> String {
        DepartmentCatalog.all.first { $0.key == meta.departmentKey }?.name ?? meta.agentId
    }

    private func accent(_ meta: VCAgentMeta) -> Color {
        DepartmentCatalog.all.first { $0.key == meta.departmentKey }?.accent
            ?? CodepetTheme.accentPurple
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
