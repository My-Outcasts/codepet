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
    let accent: Color
    let onTaskTap: (RoadmapTask) -> Void

    @Environment(\.uiLanguage) private var lang

    /// Task ids mid-pulse (a step just became current, or just unlocked).
    @State private var pulseIds: Set<String> = []
    @State private var prevStates: [String: TaskStatus] = [:]
    /// The previous current-move id, so a become-current transition can be detected even
    /// when the new current task was never `.blocked` (see `detectAdvances`).
    @State private var prevCurrentId: String?
    /// The task id the open-framing scroll last centered on. Web re-runs its framing effect on
    /// `[currentX, scale]`; there's no scale here — the board never rescales — so that reduces
    /// to "re-frame when the current move changes", which this id records.
    @State private var framedForId: String?
    /// Scroll-edge fade state, written only by `onScrollGeometryChange`.
    @State private var canScrollLeft = false
    @State private var canScrollRight = false

    /// Phases the founder expanded by hand from their rail. Session-only: the width rule
    /// (`RoadmapFocus`) picks the default set on every layout pass.
    @State private var userExpanded: Set<RoadmapPhase> = []

    /// Page gutters for the board. Leading is wider than the page's 24pt because the root
    /// node's aura bleeds 26pt past its own box — at 24pt the glow clips on the window edge.
    private static let insetLeading: CGFloat = 26
    private static let insetTrailing: CGFloat = 24

    private var currentId: String? { RoadmapEngine.nextStep(tasks)?.id }
    private var herePhrase: String {
        RoadmapBoardCopy.herePhrase(founderName: founderName, lang: lang)
    }

    private static let headerRow: CGFloat = 28
    private static let headerGap: CGFloat = 6
    private static let headerBlock: CGFloat = headerRow + headerGap

    var body: some View {
        // The board's own allotment, read directly instead of stored: `@State` + `onAppear`
        // measurement is what produced the old bug — a stale viewport centred the map against
        // a container ~200pt taller than the visible one, so it sat low and ran off the bottom.
        GeometryReader { g in
            let budget = max(0, g.size.width - Self.insetLeading - Self.insetTrailing)
            let expandedPhases = RoadmapFocus.expanded(tasks: tasks, availableWidth: budget,
                                                       userExpanded: userExpanded)
            let l = RoadmapLayoutEngine.layout(tasks, expanded: expandedPhases)
            let states = RoadmapGating.states(tasks)

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Self.headerGap) {
                        phaseHeaders(l, states: states)
                        diagram(l)
                    }
                    .padding(.leading, Self.insetLeading)
                    .padding(.trailing, Self.insetTrailing)
                    // Centring as LAYOUT, not arithmetic: the content grows to the viewport
                    // when it's smaller (and centres inside it) and overflows into scroll when
                    // it's bigger. Nothing to measure, nothing to go stale.
                    .frame(minWidth: g.size.width, minHeight: g.size.height, alignment: .center)
                }
                .onScrollGeometryChange(for: ScrollEdgeState.self) { geo in
                    ScrollEdgeState(
                        left: geo.contentOffset.x > 0.5,
                        right: geo.contentOffset.x < geo.contentSize.width - geo.containerSize.width - 0.5)
                } action: { _, new in
                    canScrollLeft = new.left
                    canScrollRight = new.right
                }
                .overlay(alignment: .leading) { edgeFade(leading: true, visible: canScrollLeft) }
                .overlay(alignment: .trailing) { edgeFade(leading: false, visible: canScrollRight) }
                .onAppear {
                    // Open framed on the current move — the founder shouldn't hunt for it.
                    if let id = currentId { frame(proxy, id: id) }
                    prevStates = statusMap(tasks)
                    prevCurrentId = currentId
                }
                .onChange(of: currentId) { _, new in
                    // First visit: `tasks` generates asynchronously, so `currentId` is nil at
                    // `onAppear` and the board never got framed above. Catch it the moment the
                    // current move first resolves — and again on each advance, as web does.
                    guard let id = new, framedForId != id else { return }
                    frame(proxy, id: id)
                }
                .onChange(of: tasks) { _, new in detectAdvances(new) }
            }
        }
    }

    /// Center the scroll on `id`, recording which id it framed so the `currentId` observer can
    /// tell a fresh advance from a re-render it has already handled.
    private func frame(_ proxy: ScrollViewProxy, id: String) {
        proxy.scrollTo(id, anchor: .center)
        framedForId = id
    }

    /// A non-interactive scroll-edge fade (web parity): a hint that more board scrolls off
    /// beyond the visible edge. Written entirely from `onScrollGeometryChange` above — no
    /// polling, no `GeometryReader` sentinel.
    @ViewBuilder
    private func edgeFade(leading: Bool, visible: Bool) -> some View {
        if visible {
            Group {
                if leading {
                    LinearGradient(colors: [CodepetTheme.pageBackground, .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 48)
                } else {
                    ZStack(alignment: .trailing) {
                        LinearGradient(colors: [.clear, CodepetTheme.pageBackground],
                                       startPoint: .leading, endPoint: .trailing)
                        // Web: `justify-content: flex-end; padding-right: 6` — pinned to the
                        // trailing edge of the strip, not centered within it.
                        Circle()
                            .fill(CodepetTheme.surface)
                            .overlay(Circle().stroke(CodepetTheme.hairline, lineWidth: 1))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(CodepetTheme.mutedText))
                            .padding(.trailing, 6)
                    }
                    .frame(width: 56)
                }
            }
            .frame(maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity.animation(.easeInOut(duration: 0.18)))
        }
    }

    /// Transform result for `onScrollGeometryChange` — whether more content lies past each edge.
    private struct ScrollEdgeState: Equatable {
        let left: Bool
        let right: Bool
    }

    // MARK: phase headers

    // Left-aligned to each column's card edge (web places them at `c.x`), in their own
    // 28pt row above the diagram. A locked phase wears a lock and drops the accent, so the
    // header row alone tells the founder how far the window reaches.
    private func phaseHeaders(_ l: RoadmapLayout, states: [RoadmapPhase: PhaseState]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(l.columns) { c in
                let state = states[c.phase] ?? .later
                let locked = state == .preview || state == .later
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(CodepetTheme.mutedText)
                        } else if state == .complete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(RoadmapPalette.done)
                        }
                        Text(c.phase.label(lang).uppercased())
                            .font(CodepetTheme.inter(10.5)).tracking(1.47)   // web .14em at 10.5px
                            .foregroundColor(c.current ? accent : CodepetTheme.mutedText)
                    }
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
        .frame(width: l.size.width, height: Self.headerRow, alignment: .topLeading)
    }

    // MARK: diagram

    private func diagram(_ l: RoadmapLayout) -> some View {
        ZStack(alignment: .topLeading) {
            edgeCanvas(l)
            if let r = l.root { rootNode(r) }
            ForEach(l.rails) { r in
                rail(r, height: l.size.height)
                    .position(x: r.x + RoadmapGeometry.railW / 2, y: l.size.height / 2)
            }
            ForEach(l.nodes) { n in
                let status = RoadmapEngine.status(for: n.task, in: tasks)
                let isCurrent = n.task.id == currentId
                RoadmapCardView(task: n.task, status: status, isCurrent: isCurrent,
                                herePhrase: herePhrase,
                                pulsing: pulseIds.contains(n.task.id),
                                accent: accent,
                                onTap: { onTaskTap(n.task) })
                    // `.help`/`.id` must be attached BEFORE `.position` — `.position` returns
                    // a view that consumes all offered space, so anything chained after it
                    // sees the whole diagram rect rather than the 208×64 card. Attaching
                    // these first keeps the tooltip and the ScrollViewReader anchor scoped
                    // to the card's real frame.
                    .id(n.task.id)
                    .help(peekText(n.task, status: status, isCurrent: isCurrent))
                    // engine coords are TOP-LEFT; SwiftUI .position is center-based
                    .position(x: n.x + RoadmapGeometry.cardW / 2,
                              y: n.y + RoadmapGeometry.cardH / 2)
                    .zIndex(isCurrent ? 1 : 0)   // keep the floating marker above neighbours
            }
        }
        .frame(width: l.size.width, height: l.size.height, alignment: .topLeading)
    }

    /// A collapsed phase: a slim rail carrying its name vertically plus its done/total, click
    /// to expand. An unplanned phase says so rather than showing a bare 0/0, which reads like
    /// a bug instead of an absence.
    private func rail(_ r: PhaseRail, height: CGFloat) -> some View {
        let empty = r.total == 0
        return Button { toggleExpanded(r.phase) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(CodepetTokens.well)
                RoundedRectangle(cornerRadius: 10).stroke(CodepetTheme.hairline, lineWidth: 1)
                VStack(spacing: 12) {
                    if !empty {
                        Text("\(r.done)/\(r.total)")
                            .font(CodepetTheme.inter(10)).monospacedDigit()
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    // `rotationEffect` doesn't change layout, so the label claims its
                    // horizontal size inside the 44pt frame and draws rotated — which is
                    // exactly what we want; `fixedSize` stops it wrapping first.
                    Text(r.phase.label(lang).uppercased())
                        .font(CodepetTheme.inter(10.5)).tracking(1.47)
                        .foregroundColor(CodepetTheme.mutedText.opacity(empty ? 0.6 : 1))
                        .lineLimit(1).fixedSize()
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: RoadmapGeometry.railW, height: height)
        }
        .buttonStyle(.plain)
        .help(empty ? "\(r.phase.label(lang)) · \(RoadmapBoardCopy.notPlannedYet(lang))"
                    : "\(r.phase.label(lang)) · \(r.done)/\(r.total)")
    }

    private func toggleExpanded(_ phase: RoadmapPhase) {
        if userExpanded.contains(phase) { userExpanded.remove(phase) } else { userExpanded.insert(phase) }
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
                ctx.stroke(path(e.points), with: .color(accent.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            // Faint dotted dependencies.
            for e in l.edges where !e.critical {
                ctx.stroke(path(e.points), with: .color(CodepetTokens.faint),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
            // Critical path: a wide soft halo under a solid line.
            for e in l.edges where e.critical {
                ctx.stroke(path(e.points), with: .color(accent.opacity(0.16)),
                           style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
            for e in l.edges where e.critical {
                ctx.stroke(path(e.points), with: .color(accent),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
            // A short stub into each rail, so a collapsed phase still reads as part of one
            // continuous journey rather than a detached sidebar.
            let midY = (l.size.height / 2).rounded()
            for r in l.rails {
                ctx.stroke(path([CGPoint(x: r.x - RoadmapGeometry.railGap, y: midY),
                                 CGPoint(x: r.x, y: midY)]),
                           with: .color(accent.opacity(0.25)),
                           style: StrokeStyle(lineWidth: 1.5))
            }
        }
        .frame(width: l.size.width, height: l.size.height)
        .allowsHitTesting(false)
    }

    // MARK: root node

    // 172×118, accent gradient, the Codepet mark, and a blurred aura behind it so the origin
    // reads as the luminous root the whole tree grows from — not just another card.
    //
    // Web parity: the aura bleeds a fixed 26pt/20pt on every side with no clamping — web lets
    // the scroll container clip it when the root sits against an edge, rather than shifting
    // the radial gradient's center off the card. Do not re-add a clamp here: it reads as
    // correct in isolation but throws the glow off-center relative to the card.
    private func rootNode(_ r: CGRect) -> some View {
        let auraW = r.width + 52
        let auraH = r.height + 40

        return ZStack {
            RoundedRectangle(cornerRadius: 44)
                .fill(RadialGradient(colors: [accent.opacity(0.42), .clear],
                                     center: .center, startRadius: 0, endRadius: r.width * 0.6))
                .frame(width: auraW, height: auraH)
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
                .fill(LinearGradient(colors: [accent.opacity(0.16),
                                              accent.opacity(0.06)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.45), lineWidth: 1))
            .shadow(color: accent.opacity(0.55), radius: 22, x: 0, y: 16)
        }
        .position(x: r.midX, y: r.midY)
    }

    // MARK: advance pulse

    private func statusMap(_ ts: [RoadmapTask]) -> [String: TaskStatus] {
        Dictionary(uniqueKeysWithValues: ts.map { ($0.id, RoadmapEngine.status(for: $0, in: ts)) })
    }

    /// The "advance" moment (web `.rm-pulse`): a task became the current move, or a locked
    /// task unlocked because its prerequisites just completed → pulse it once, so finishing
    /// one step visibly lights up the next. The commonest case is the former — you finish the
    /// current move and an already-unlocked sibling becomes the new beacon, without ever
    /// having been `.blocked` — so that transition is tracked via `prevCurrentId`, separately
    /// from the blocked → actionable unlock detection.
    private func detectAdvances(_ new: [RoadmapTask]) {
        let now = statusMap(new)
        let newCurrent = RoadmapEngine.nextStep(new)?.id
        guard !prevStates.isEmpty else {
            prevStates = now
            prevCurrentId = newCurrent
            return
        }
        var fresh = Set<String>()
        for (id, st) in now {
            guard let was = prevStates[id] else { continue }
            if was == .blocked && (st == .codepetCanDo || st == .needsYou) { fresh.insert(id) }
        }
        if let c = newCurrent, c != prevCurrentId { fresh.insert(c) }
        prevStates = now
        prevCurrentId = newCurrent
        guard !fresh.isEmpty else { return }
        // `.formUnion`/subtract-only-what-this-batch-added, so two advances inside the 1.5s
        // window don't truncate each other's pulse — a plain `pulseIds = fresh` replace would
        // wipe out an in-flight pulse the instant a second one starts.
        pulseIds.formUnion(fresh)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { pulseIds.subtract(fresh) }
    }

    /// The hover peek's plain-language line — the founder learns a card without opening chat.
    /// Web's `peekSentence` distinguishes the single `current` card ("…'s next move") from a
    /// merely-`available` one ("… can run this now") — both are `.codepetCanDo`, so without
    /// `isCurrent` every runnable card on the board would claim to be THE next move.
    private func peekText(_ task: RoadmapTask, status: TaskStatus, isCurrent: Bool) -> String {
        var parts: [String] = []
        // Phase is always shown — the layout engine explicitly tolerates legacy tasks with
        // `dept == nil`, and dropping the phase for them loses the peek's whole first line.
        // Prefix with the department name only when one resolves.
        if let d = DepartmentCatalog.find(task.dept)?.name {
            parts.append("\(d) · \(task.phase.label(lang))")
        } else {
            parts.append(task.phase.label(lang))
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
        if status == .blocked, let b = RoadmapGating.blocker(for: task, in: tasks) {
            parts.append(RoadmapBoardCopy.waitingOn(b.title, lang: lang))
        }
        switch status {
        case .codepetCanDo:
            if isCurrent {
                parts.append(lang == .vi ? "Nước đi tiếp theo của \(companionName). Nhấn để bắt đầu."
                                         : "\(companionName)'s next move. Click to start.")
            } else {
                parts.append(lang == .vi ? "\(companionName) có thể làm ngay bây giờ. Nhấn để bắt đầu."
                                         : "\(companionName) can run this now. Click to start.")
            }
        case .needsYou:      parts.append(lang == .vi ? "Cần bạn nhập. Nhấn để thêm." : "Your input needed. Click to add it.")
        case .needsApproval: parts.append(lang == .vi ? "Bản nháp đã sẵn sàng. Nhấn để xem lại." : "Ready for your review.")
        case .done:          parts.append(lang == .vi ? "Xong. Nhấn để mở." : "Finished — click to open the result.")
        case .blocked:       parts.append(lang == .vi ? "Cần hoàn thành các bước trước." : "Locked — finish the earlier steps first.")
        }
        return parts.joined(separator: "\n")
    }
}
