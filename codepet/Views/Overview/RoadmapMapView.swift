// codepet/Views/Overview/RoadmapMapView.swift
import SwiftUI

/// The Overview node-graph map (web RoadmapView): a scrollable canvas of dependency
/// edges under phase-positioned task cards, with a company root, status colors, a
/// beacon "{companion} is here" node, and critical-path highlighting.
struct RoadmapMapView: View {
    let tasks: [RoadmapTask]
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private let cardW: CGFloat = 205
    private let cardH: CGFloat = 84

    private var map: RoadmapMap { RoadmapMapLayout.layout(tasks, cardW: cardW, cardH: cardH) }
    private var pos: [String: CGPoint] {
        Dictionary(map.nodes.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) }, uniquingKeysWith: { a, _ in a })
    }
    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }
    private var founderName: String {
        let n = (companyStore.company.brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? companionName : n
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    edgeLayer
                    phaseHeaders
                    ForEach(map.nodes) { node in
                        nodeView(node)
                            .frame(width: cardW, height: node.task == nil ? cardH + 8 : cardH)
                            .position(x: node.x, y: node.y)
                            .id(node.id)
                    }
                }
                .frame(width: map.size.width, height: map.size.height, alignment: .topLeading)
                .padding(20)
            }
            .onAppear {
                // Only scroll for a late-phase beacon (Ship/Launch); an early beacon stays at
                // the origin so the company root + Find column are visible from the start.
                if let b = beacon, b.phase.order >= 3 {
                    proxy.scrollTo(b.id, anchor: UnitPoint(x: 0.4, y: 0.45))
                }
            }
        }
    }

    // Phase-header chips over each column (web: a bordered chip per phase, the current
    // phase a filled purple pill, the done/total count trailing outside). pad must match
    // the layout.
    private var phaseHeaders: some View {
        let col: CGFloat = 260, pad: CGFloat = 120
        let current = beacon?.phase
        return ForEach(Array(RoadmapPhase.allCases.enumerated()), id: \.offset) { pi, phase in
            let list = tasks.filter { $0.phase == phase }
            let done = list.filter { $0.done }.count
            let isCurrent = phase == current
            HStack(spacing: 6) {
                Text(phase.label(lang).uppercased()).font(CodepetTheme.inter(10, weight: .bold)).tracking(0.7)
                    .foregroundColor(isCurrent ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(isCurrent ? CodepetTheme.accentPurple.opacity(0.16) : CodepetTheme.mutedText.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .stroke(isCurrent ? CodepetTheme.accentPurple.opacity(0.55) : CodepetTheme.hairline, lineWidth: 1))
                Text("\(done)/\(list.count)").font(CodepetTheme.inter(10)).foregroundColor(CodepetTheme.mutedText)
            }
            .position(x: pad + CGFloat(pi + 1) * col, y: 4)
        }
    }

    // MARK: edges (Canvas)
    private var edgeLayer: some View {
        Canvas { ctx, _ in
            for e in map.edges {
                guard let s = pos[e.fromId], let t = pos[e.toId] else { continue }
                let start = CGPoint(x: s.x + cardW / 2, y: s.y)
                let end = CGPoint(x: t.x - cardW / 2, y: t.y)
                let midX = (start.x + end.x) / 2
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
                if e.critical {
                    ctx.stroke(path, with: .color(CodepetTheme.accentPurple.opacity(0.25)), lineWidth: 7)
                    ctx.stroke(path, with: .color(CodepetTheme.accentPurple), lineWidth: 2.5)
                } else {
                    ctx.stroke(path, with: .color(CodepetTheme.hairline),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
        }
        .frame(width: map.size.width, height: map.size.height)
    }

    // MARK: nodes
    @ViewBuilder private func nodeView(_ node: MapNode) -> some View {
        if let task = node.task {
            taskCard(task)
        } else {
            rootCard
        }
    }

    private var rootCard: some View {
        let name = (companyStore.company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let one = (companyStore.company.brief.oneLiner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 4) {
            CharacterImage(companyStore.company.companionId, size: 26)
            Text(name.isEmpty ? "Codepet" : name)
                .font(CodepetTheme.inter(14, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                .lineLimit(1)
            if !one.isEmpty {
                Text(one).font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText).lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: cardW, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(CodepetTheme.accentPurple.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CodepetTheme.accentPurple.opacity(0.35), lineWidth: 1.5))
    }

    private func taskCard(_ task: RoadmapTask) -> some View {
        let status = RoadmapEngine.status(for: task, in: tasks)
        let isBeacon = beacon?.id == task.id
        return VStack(alignment: .leading, spacing: 6) {
            if isBeacon {
                // Web shows the FOUNDER's name for a their-task beacon, the companion otherwise
                // (e.g. "MONA IS HERE" / "BYTE IS HERE").
                let who = task.who == .you ? founderName : companionName
                Text(lang == .vi ? "\(who.uppercased()) Ở ĐÂY" : "\(who.uppercased()) IS HERE")
                    .font(CodepetTheme.inter(9, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
            }
            HStack(alignment: .top, spacing: 8) {
                statusDot(status)
                Text(task.title).font(CodepetTheme.inter(12.5, weight: .semibold))
                    .foregroundColor(status == .blocked ? CodepetTheme.mutedText : CodepetTheme.primaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Web shows a small deliverable/output marker on pending (non-done, non-beacon) cards.
                if !task.done && !isBeacon {
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(CodepetTheme.mutedText.opacity(0.6), lineWidth: 1)
                        .frame(width: 11, height: 9).padding(.top, 2)
                }
            }
            statusChip(status, isBeacon: isBeacon)
        }
        .padding(10)
        .frame(width: cardW, alignment: .leading)
        .background(cardBackground(status, isBeacon: isBeacon))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            isBeacon ? CodepetTheme.accentPurple : CodepetTheme.hairline, lineWidth: isBeacon ? 1.6 : 1))
        .shadow(color: isBeacon ? CodepetTheme.accentPurple.opacity(0.3) : .clear, radius: 10)
        .opacity(status == .blocked ? 0.72 : 1)
        .onTapGesture { if status == .codepetCanDo { Task { await companyStore.runTask(task, language: lang) } } }
        .help(peekText(task, status: status))
    }

    // Web status indicator: a rounded-square container box holding a small colored square.
    private func statusDot(_ status: TaskStatus) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(CodepetTheme.mutedText.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CodepetTheme.hairline, lineWidth: 1))
                .frame(width: 28, height: 28)
            RoundedRectangle(cornerRadius: 4).fill(taskStatusTint(status)).frame(width: 13, height: 13)
        }
    }

    @ViewBuilder private func statusChip(_ status: TaskStatus, isBeacon: Bool) -> some View {
        // Only the current/beacon "Start" is a filled hero chip; every other actionable
        // card is an outline chip (avoids competing CTAs across the whole map).
        let label: String = {
            switch status {
            case .done:          return lang == .vi ? "Xong" : "Done"
            case .codepetCanDo:  return lang == .vi ? "Bắt đầu" : "Start"
            case .needsApproval: return lang == .vi ? "Duyệt" : "Review"
            case .needsYou:      return lang == .vi ? "Cần bạn" : "Add your input"
            case .blocked:       return lang == .vi ? "Cần bước trước" : "Needs earlier steps"
            }
        }()
        let filled = isBeacon && status == .codepetCanDo
        Text(label).font(CodepetTheme.inter(10, weight: .semibold))
            .foregroundColor(filled ? .white : taskStatusTint(status))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(filled ? taskStatusTint(status) : taskStatusTint(status).opacity(0.12)))
    }

    private func cardBackground(_ status: TaskStatus, isBeacon: Bool) -> some View {
        let fill: Color
        if isBeacon { fill = CodepetTheme.accentPurple.opacity(0.14) }
        else if status == .done { fill = CodepetTheme.accentTeal.opacity(0.1) }
        else { fill = CodepetTheme.surface }
        return RoundedRectangle(cornerRadius: 12).fill(fill)
    }

    private func peekText(_ task: RoadmapTask, status: TaskStatus) -> String {
        var parts: [String] = []
        if let d = DepartmentCatalog.find(task.dept)?.name { parts.append("\(d) · \(task.phase.label(lang))") }
        if !task.detail.isEmpty { parts.append(task.detail) }
        let deps = task.dependsOn.compactMap { id in tasks.first { $0.id == id }?.title }
        if !deps.isEmpty { parts.append((lang == .vi ? "Mở khoá sau: " : "Unlocks after: ") + deps.joined(separator: ", ")) }
        return parts.joined(separator: "\n")
    }
}
