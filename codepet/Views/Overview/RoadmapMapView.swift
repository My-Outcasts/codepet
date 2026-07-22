// codepet/Views/Overview/RoadmapMapView.swift
import SwiftUI

/// The Overview node-graph map (web RoadmapView): a scrollable canvas of dependency
/// edges under phase-positioned task cards, with a company root, status colors, a
/// beacon "{companion} is here" node, and critical-path highlighting.
struct RoadmapMapView: View {
    let tasks: [RoadmapTask]
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    private let cardW: CGFloat = 200
    private let cardH: CGFloat = 76

    private var map: RoadmapMap { RoadmapMapLayout.layout(tasks, cardW: cardW, cardH: cardH) }
    private var pos: [String: CGPoint] {
        Dictionary(map.nodes.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) }, uniquingKeysWith: { a, _ in a })
    }
    private var beacon: RoadmapTask? { RoadmapEngine.nextStep(tasks) }
    private var companionName: String { PetCharacter.all[companyStore.company.companionId]?.name ?? "Codepet" }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                edgeLayer
                ForEach(map.nodes) { node in
                    nodeView(node)
                        .frame(width: cardW, height: node.task == nil ? cardH + 8 : cardH)
                        .position(x: node.x, y: node.y)
                }
            }
            .frame(width: map.size.width, height: map.size.height, alignment: .topLeading)
            .padding(20)
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
                Text("\(companionName) " + (lang == .vi ? "đang ở đây" : "is here"))
                    .font(CodepetTheme.inter(9, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
            }
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(taskStatusTint(status)).frame(width: 7, height: 7).padding(.top, 3)
                Text(task.title).font(CodepetTheme.inter(12.5, weight: .semibold))
                    .foregroundColor(status == .blocked ? CodepetTheme.mutedText : CodepetTheme.primaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if status == .blocked {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundColor(CodepetTheme.mutedText)
                }
            }
            statusChip(status)
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

    @ViewBuilder private func statusChip(_ status: TaskStatus) -> some View {
        let (label, filled): (String, Bool) = {
            switch status {
            case .done:          return (lang == .vi ? "Xong" : "Done", false)
            case .codepetCanDo:  return (lang == .vi ? "Bắt đầu" : "Start", true)
            case .needsApproval: return (lang == .vi ? "Duyệt" : "Review", true)
            case .needsYou:      return (lang == .vi ? "Cần bạn" : "Add your input", true)
            case .blocked:       return (lang == .vi ? "Cần bước trước" : "Needs earlier steps", false)
            }
        }()
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
