// codepet/Views/Overview/RoadmapBoardView.swift
import SwiftUI

/// The Overview roadmap board — a native port of the web `RoadmapView.tsx` renderer.
/// A thin layer over `RoadmapLayoutEngine`: it takes node boxes and orthogonal edge
/// polylines and draws them. Columns are phases, rows are department lanes, edges are
/// dependencies; the edges touching the current move are lit, everything else is a faint
/// dotted dependency. The tree begins at a luminous company root node.
struct RoadmapBoardView: View {
    let tasks: [RoadmapTask]
    let companionName: String
    let founderName: String?
    let projectName: String
    let tagline: String?
    let onTaskTap: (RoadmapTask) -> Void

    @Environment(\.uiLanguage) private var lang

    /// Measured height of the scroll area, for the fit-to-height scale.
    @State private var avail: CGFloat = 0
    /// Task ids mid-pulse (a step just became current, or just unlocked).
    @State private var pulseIds: Set<String> = []
    @State private var prevStates: [String: TaskStatus] = [:]

    private var layout: RoadmapLayout { RoadmapLayoutEngine.layout(tasks) }
    private var currentId: String? { RoadmapEngine.nextStep(tasks)?.id }
    private var herePhrase: String {
        RoadmapBoardCopy.herePhrase(founderName: founderName, lang: lang)
    }

    private let headerBlock: CGFloat = 34    // phase-header row (28) + its 6pt bottom margin

    /// Scale the diagram up to fill the available height, capped at 1.0 (never upscale past
    /// natural size), and center any leftover height — so a short roadmap leaves no dead space.
    private func scale(for l: RoadmapLayout) -> CGFloat {
        let natural = l.size.height + headerBlock
        guard avail > 0, natural > 0 else { return 1 }
        return max(1, min(1.0, avail / natural))
    }

    var body: some View {
        let l = layout
        let s = scale(for: l)
        let scaledH = (l.size.height + headerBlock) * s
        let padTop = avail > scaledH ? ((avail - scaledH) / 2).rounded() : 0

        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    phaseHeaders(l)
                    diagram(l)
                }
                .frame(width: l.size.width, alignment: .topLeading)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: l.size.width * s, height: scaledH, alignment: .topLeading)
                .padding(.top, padTop)
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { avail = g.size.height }
                    .onChange(of: g.size.height) { _, h in avail = h }
            })
            .onAppear {
                // Open framed on the current move — the founder shouldn't hunt for it.
                if let id = currentId { proxy.scrollTo(id, anchor: .center) }
                prevStates = statusMap(tasks)
            }
            .onChange(of: tasks) { _, new in detectAdvances(new) }
        }
    }

    // MARK: phase headers

    // Left-aligned to each column's card edge (web places them at `c.x`), in their own
    // 28pt row above the diagram.
    private func phaseHeaders(_ l: RoadmapLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(l.columns) { c in
                HStack(spacing: 10) {
                    Text(c.phase.label(lang).uppercased())
                        .font(CodepetTheme.inter(10.5)).tracking(1.47)     // web .14em at 10.5px
                        .foregroundColor(c.current ? CodepetTheme.accentPurple : CodepetTheme.mutedText)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(c.current ? CodepetTokens.accentTint : CodepetTokens.well))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(c.current ? CodepetTokens.accentLine : CodepetTheme.hairline,
                                    lineWidth: 1))
                    Text("\(c.done)/\(c.total)")
                        .font(CodepetTheme.inter(11)).foregroundColor(CodepetTheme.mutedText)
                }
                .fixedSize()
                .offset(x: c.x, y: 0)
            }
        }
        .frame(width: l.size.width, height: 28, alignment: .topLeading)
    }

    // MARK: diagram

    private func diagram(_ l: RoadmapLayout) -> some View {
        ZStack(alignment: .topLeading) {
            edgeCanvas(l)
            if let r = l.root { rootNode(r) }
            ForEach(l.nodes) { n in
                let status = RoadmapEngine.status(for: n.task, in: tasks)
                let isCurrent = n.task.id == currentId
                RoadmapCardView(task: n.task, status: status, isCurrent: isCurrent,
                                herePhrase: herePhrase,
                                pulsing: pulseIds.contains(n.task.id),
                                onTap: { onTaskTap(n.task) })
                    // engine coords are TOP-LEFT; SwiftUI .position is center-based
                    .position(x: n.x + RoadmapGeometry.cardW / 2,
                              y: n.y + RoadmapGeometry.cardH / 2)
                    .zIndex(isCurrent ? 1 : 0)   // keep the floating marker above neighbours
                    .id(n.task.id)
                    .help(peekText(n.task, status: status))
            }
        }
        .frame(width: l.size.width, height: l.size.height, alignment: .topLeading)
    }

    private func edgeCanvas(_ l: RoadmapLayout) -> some View {
        Canvas { ctx, _ in
            func path(_ pts: [CGPoint]) -> Path {
                var p = Path()
                guard let first = pts.first else { return p }
                p.move(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
                return p
            }
            // Root fan-out: solid, accent-tinted, its own style — never dashed, never critical.
            for e in l.rootEdges {
                ctx.stroke(path(e.points), with: .color(CodepetTheme.accentPurple.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            // Faint dotted dependencies.
            for e in l.edges where !e.critical {
                ctx.stroke(path(e.points), with: .color(CodepetTokens.faint),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
            // Critical path: a wide soft halo under a solid line.
            for e in l.edges where e.critical {
                ctx.stroke(path(e.points), with: .color(CodepetTheme.accentPurple.opacity(0.16)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
            for e in l.edges where e.critical {
                ctx.stroke(path(e.points), with: .color(CodepetTheme.accentPurple),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: l.size.width, height: l.size.height)
        .allowsHitTesting(false)
    }

    // MARK: root node

    // 172×118, accent gradient, the Codepet mark, and a blurred aura behind it so the origin
    // reads as the luminous root the whole tree grows from — not just another card.
    private func rootNode(_ r: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44)
                .fill(RadialGradient(colors: [CodepetTheme.accentPurple.opacity(0.42), .clear],
                                     center: .center, startRadius: 0, endRadius: r.width * 0.6))
                .frame(width: r.width + 52, height: r.height + 40)
                .blur(radius: 22)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 11) {
                Image("codepet-logo")
                    .resizable().interpolation(.none).scaledToFill()
                    .frame(width: 36, height: 36).clipShape(Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(projectName)
                        .font(CodepetTheme.inter(19, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText).lineLimit(1)
                    if let tagline, !tagline.isEmpty {
                        Text(tagline).font(CodepetTheme.inter(11, weight: .medium))
                            .foregroundColor(CodepetTheme.mutedText).lineLimit(1)
                    } else {
                        Text(lang == .vi ? "CÔNG TY CỦA BẠN" : "YOUR COMPANY")
                            .font(CodepetTheme.inter(9.5)).tracking(1.33)   // web .14em at 9.5px
                            .foregroundColor(CodepetTokens.accentDeep)
                    }
                }
            }
            .padding(15)
            .frame(width: r.width, height: r.height, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [CodepetTheme.accentPurple.opacity(0.16),
                                              CodepetTheme.accentPurple.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(CodepetTheme.accentPurple.opacity(0.45), lineWidth: 1))
            .shadow(color: CodepetTheme.accentPurple.opacity(0.55), radius: 22, x: 0, y: 16)
        }
        .position(x: r.midX, y: r.midY)
    }

    // NOTE: the web original fades the board's left/right scroll edges. SwiftUI's `ScrollView`
    // has no scroll-offset callback to drive that state faithfully, and a `GeometryReader`
    // sentinel hack proved fragile (fires on layout/scale changes, not just scroll, and drifts
    // under the `scaleEffect` used above). Per the brief's Step 3 fallback, the fade is omitted
    // rather than shipped broken — see the task report for detail.

    // MARK: advance pulse

    private func statusMap(_ ts: [RoadmapTask]) -> [String: TaskStatus] {
        Dictionary(uniqueKeysWithValues: ts.map { ($0.id, RoadmapEngine.status(for: $0, in: ts)) })
    }

    /// The "advance" moment (web `.rm-pulse`): a task became the current move, or a locked
    /// task unlocked because its prerequisites just completed → pulse it once, so finishing
    /// one step visibly lights up the next.
    private func detectAdvances(_ new: [RoadmapTask]) {
        let now = statusMap(new)
        guard !prevStates.isEmpty else { prevStates = now; return }
        let newCurrent = RoadmapEngine.nextStep(new)?.id
        var fresh = Set<String>()
        for (id, st) in now {
            guard let was = prevStates[id] else { continue }
            if was == .blocked && (st == .codepetCanDo || st == .needsYou) { fresh.insert(id) }
        }
        if let c = newCurrent, prevStates[c] == .blocked { fresh.insert(c) }
        prevStates = now
        guard !fresh.isEmpty else { return }
        pulseIds = fresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { pulseIds.subtract(fresh) }
    }

    /// The hover peek's plain-language line — the founder learns a card without opening chat.
    private func peekText(_ task: RoadmapTask, status: TaskStatus) -> String {
        var parts: [String] = []
        if let d = DepartmentCatalog.find(task.dept)?.name {
            parts.append("\(d) · \(task.phase.label(lang))")
        }
        if !task.detail.isEmpty { parts.append(task.detail) }
        let deps = task.dependsOn.compactMap { id in tasks.first { $0.id == id }?.title }
        if !deps.isEmpty {
            parts.append((lang == .vi ? "Mở khoá sau: " : "Unlocks after: ") + deps.joined(separator: ", "))
        }
        let unlocks = tasks.filter { $0.dependsOn.contains(task.id) }.map(\.title)
        if !unlocks.isEmpty {
            parts.append((lang == .vi ? "Dẫn tới: " : "Leads to: ")
                         + unlocks.prefix(3).joined(separator: ", "))
        }
        switch status {
        case .codepetCanDo:
            parts.append(lang == .vi ? "Nước đi tiếp theo của \(companionName). Nhấn để bắt đầu."
                                     : "\(companionName)'s next move. Click to start.")
        case .needsYou:      parts.append(lang == .vi ? "Cần bạn nhập. Nhấn để thêm." : "Your input needed. Click to add it.")
        case .needsApproval: parts.append(lang == .vi ? "Bản nháp đã sẵn sàng. Nhấn để xem lại." : "Ready for your review.")
        case .done:          parts.append(lang == .vi ? "Xong. Nhấn để mở." : "Finished — click to open the result.")
        case .blocked:       parts.append(lang == .vi ? "Cần hoàn thành các bước trước." : "Locked — finish the earlier steps first.")
        }
        return parts.joined(separator: "\n")
    }
}
