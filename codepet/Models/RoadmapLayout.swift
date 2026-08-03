// codepet/Models/RoadmapLayout.swift
import CoreGraphics

/// Geometry — one source of truth for card size + spacing. Values mirror the web's
/// `lib/overview/roadmapLayout.ts` exactly; do not tune them independently.
enum RoadmapGeometry {
    static let cardW: CGFloat = 208
    static let cardH: CGFloat = 64
    static let colGap: CGFloat = 60      // horizontal gap between phase columns
    static let rowPitch: CGFloat = 96    // vertical distance between task rows
    static let top: CGFloat = 40         // room above row 0 for the "is here" marker
    static let bottomPad: CGFloat = 16
    static let rootW: CGFloat = 172
    static let rootH: CGFloat = 118
    static let rootLeft: CGFloat = 12
    static let rootGap: CGFloat = 48     // gap between the root node and column 0
    static let rootRight: CGFloat = rootLeft + rootW

    // ── Collapsed phases ─────────────────────────────────────────────────────────────
    /// A collapsed phase's slim rail: wide enough for a vertical label, narrow enough that
    /// three of them cost less than one card column.
    static let railW: CGFloat = 44
    static let railGap: CGFloat = 20

    /// Total board width for a given column mix — THE one width formula, shared by the layout
    /// engine (which must agree with what it draws) and `RoadmapFocus` (which must predict it
    /// before laying anything out). Columns accumulate their trailing gap; the last one's is
    /// replaced by `bottomPad`.
    static func boardWidth(expanded: Set<RoadmapPhase>) -> CGFloat {
        var cursor = rootRight + rootGap
        var lastGap: CGFloat = 0
        for phase in RoadmapPhase.allCases {
            let isColumn = expanded.contains(phase)
            cursor += isColumn ? (cardW + colGap) : (railW + railGap)
            lastGap = isColumn ? colGap : railGap
        }
        return cursor - lastGap + bottomPad
    }
}

/// One positioned task card. `x`/`y` are the card's TOP-LEFT (web's coordinate scheme);
/// the view converts to SwiftUI's center-based `.position`.
struct PositionedNode: Identifiable {
    let task: RoadmapTask
    let col: Int
    let row: Int
    let x: CGFloat
    let y: CGFloat
    var id: String { task.id }
}

/// A connector as a polyline: 2 points for a straight run, 4 for an orthogonal elbow.
struct EdgePath {
    let from: String
    let to: String
    let points: [CGPoint]
    let critical: Bool
}

/// A phase column's header data.
struct PhaseColumn: Identifiable {
    let phase: RoadmapPhase
    let x: CGFloat
    let done: Int
    let total: Int
    let current: Bool
    var id: String { phase.rawValue }
}

/// A collapsed phase — a slim clickable rail instead of a column of cards. `done`/`total` keep
/// the counts visible so a collapsed phase never hides progress.
struct PhaseRail: Identifiable {
    let phase: RoadmapPhase
    let x: CGFloat
    let done: Int
    let total: Int
    var id: String { phase.rawValue }
}

struct RoadmapLayout {
    let nodes: [PositionedNode]
    let edges: [EdgePath]
    let columns: [PhaseColumn]
    /// Collapsed phases, in phase order. Disjoint from `columns` — every phase is one or the other.
    let rails: [PhaseRail]
    /// The company root box, or nil when `hasRoot: false`.
    let root: CGRect?
    /// Root → entry-task connectors. Styled separately from dependency edges, never critical.
    let rootEdges: [EdgePath]
    let size: CGSize
}

/// Pure layout for the Overview roadmap board: columns = phases, rows = department lanes,
/// edges = dependencies, orthogonal connectors, critical path = the edges touching the
/// current move. Deterministic and side-effect-free so the renderer stays thin.
enum RoadmapLayoutEngine {
    static let rootId = "__root__"

    /// Canonical department lane order (top → bottom): product first, then growth-facing
    /// functions, then company-shell functions. Any dept not listed falls in after these,
    /// in first-appearance order.
    private static let deptLaneOrder = ["eng", "design", "mkt", "sales", "support", "ops", "fin", "legal"]

    /// Left edge of every phase's slot, accumulated left to right: a full card column for an
    /// expanded phase, a slim rail for a collapsed one. Replaces the old fixed-pitch
    /// `col * (cardW + colGap)` — with rails the pitch is no longer uniform.
    private static func slotX(expanded: Set<RoadmapPhase>, hasRoot: Bool) -> [RoadmapPhase: CGFloat] {
        var cursor = hasRoot ? RoadmapGeometry.rootRight + RoadmapGeometry.rootGap
                             : RoadmapGeometry.rootLeft
        var out: [RoadmapPhase: CGFloat] = [:]
        for phase in RoadmapPhase.allCases {
            out[phase] = cursor
            cursor += expanded.contains(phase) ? (RoadmapGeometry.cardW + RoadmapGeometry.colGap)
                                               : (RoadmapGeometry.railW + RoadmapGeometry.railGap)
        }
        return out
    }

    private static func rowTop(_ row: Int) -> CGFloat {
        RoadmapGeometry.top + CGFloat(row) * RoadmapGeometry.rowPitch
    }

    /// Orthogonal connector from a right-edge point to a left-edge point. A straight
    /// segment when the rows line up, otherwise an elbow whose vertical sits in the gutter
    /// just left of the TARGET column — so it never crosses an intermediate column's cards.
    static func elbow(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        if a.y == b.y { return [a, b] }
        let mid = (b.x - RoadmapGeometry.colGap / 2).rounded()
        return [a, CGPoint(x: mid, y: a.y), CGPoint(x: mid, y: b.y), b]
    }

    /// Connector between two cards in the SAME column: a hook that drops into the column's
    /// LEFT gutter instead of doubling back through the cards. Both x's are the column's left edge.
    static func sideElbow(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let g = (a.x - RoadmapGeometry.colGap / 2).rounded()
        return [a, CGPoint(x: g, y: a.y), CGPoint(x: g, y: b.y), b]
    }

    /// `expanded` = the phases rendering as full card columns; every other phase collapses to a
    /// rail and its tasks are left out of `nodes` entirely (no cards, no lanes, no height).
    /// `nil` means every phase is a column — the pre-rails behaviour, which the existing
    /// geometry tests pin.
    static func layout(_ tasks: [RoadmapTask], hasRoot: Bool = true,
                       expanded: Set<RoadmapPhase>? = nil) -> RoadmapLayout {
        let expandedSet = expanded ?? Set(RoadmapPhase.allCases)
        let phases = RoadmapPhase.allCases
        let xOf = slotX(expanded: expandedSet, hasRoot: hasRoot)
        // Only tasks in an expanded phase get cards; the rest are represented by their rail.
        let shown = tasks.filter { expandedSet.contains($0.phase) }
        var colOf: [RoadmapPhase: Int] = [:]
        for (i, p) in phases.enumerated() { colOf[p] = i }

        // ── Department lanes ──────────────────────────────────────────────────────────
        // Each department keeps a single horizontal row across the columns it appears in,
        // so a function reads as a track left-to-right. Depts that never share a column
        // pack onto the same lane; a 2nd task in one (phase, dept) cell spills to the
        // nearest free row in that column only.
        var deptCols: [String: Set<Int>] = [:]
        var deptSeen: [String] = []
        for t in shown {
            guard let c = colOf[t.phase] else { continue }
            let d = t.dept ?? ""            // legacy tasks predate `dept`
            if deptCols[d] == nil { deptCols[d] = []; deptSeen.append(d) }
            deptCols[d]?.insert(c)
        }
        let orderedDepts = deptLaneOrder.filter { deptCols[$0] != nil }
            + deptSeen.filter { !deptLaneOrder.contains($0) }

        // Greedy interval-graph coloring: give each dept the lowest lane whose
        // already-claimed columns don't clash with the dept's columns.
        var laneOf: [String: Int] = [:]
        var laneCols: [Set<Int>] = []
        for d in orderedDepts {
            guard let cols = deptCols[d] else { continue }
            var lane = 0
            while lane < laneCols.count && !laneCols[lane].isDisjoint(with: cols) { lane += 1 }
            laneOf[d] = lane
            if lane == laneCols.count { laneCols.append([]) }
            laneCols[lane].formUnion(cols)
        }
        let laneCount = max(1, laneCols.count)

        // Place a task at its dept lane, or the nearest free row in that column if the
        // lane is taken there (search down, then up, then extend below all lanes).
        var occ: [Int: Set<Int>] = [:]
        func takeRow(_ col: Int, _ lane: Int) -> Int {
            var used = occ[col] ?? []
            var row = lane
            if used.contains(row) {
                row = -1
                var r = lane + 1
                while r < laneCount && row < 0 { if !used.contains(r) { row = r }; r += 1 }
                r = lane - 1
                while r >= 0 && row < 0 { if !used.contains(r) { row = r }; r -= 1 }
                if row < 0 { row = laneCount; while used.contains(row) { row += 1 } }
            }
            used.insert(row)
            occ[col] = used
            return row
        }

        var nodes: [PositionedNode] = []
        var nodeById: [String: PositionedNode] = [:]
        for task in shown {
            guard let col = colOf[task.phase] else { continue }   // unknown phase → skip, don't crash
            let row = takeRow(col, laneOf[task.dept ?? ""] ?? 0)
            let n = PositionedNode(task: task, col: col, row: row,
                                   x: xOf[task.phase] ?? 0, y: rowTop(row))
            nodes.append(n)
            nodeById[task.id] = n
        }

        func centerY(_ n: PositionedNode) -> CGFloat { n.y + RoadmapGeometry.cardH / 2 }
        func rightX(_ n: PositionedNode) -> CGFloat { n.x + RoadmapGeometry.cardW }

        // An edge is CRITICAL when it TOUCHES the current task — the incoming edge that led
        // here and the outgoing edges to what this move unblocks. Nothing else.
        let currentId = RoadmapEngine.nextStep(tasks)?.id
        let ids = Set(tasks.map { $0.id })

        var edges: [EdgePath] = []
        for t in shown {
            for dep in t.dependsOn {
                guard ids.contains(dep), let a = nodeById[dep], let b = nodeById[t.id] else { continue }
                let points = a.col == b.col
                    ? sideElbow(from: CGPoint(x: a.x, y: centerY(a)),
                                to: CGPoint(x: b.x, y: centerY(b)))
                    : elbow(from: CGPoint(x: rightX(a), y: centerY(a)),
                            to: CGPoint(x: b.x, y: centerY(b)))
                edges.append(EdgePath(from: dep, to: t.id, points: points,
                                      critical: t.id == currentId || dep == currentId))
            }
        }

        let maxRows = max(1, nodes.map { $0.row + 1 }.max() ?? 1)
        let height = RoadmapGeometry.top + CGFloat(maxRows - 1) * RoadmapGeometry.rowPitch
            + RoadmapGeometry.cardH + RoadmapGeometry.bottomPad
        let width = RoadmapGeometry.boardWidth(expanded: expandedSet)

        // The current phase is read from the WHOLE task set, not just the shown ones: the
        // beacon's phase may be collapsed, and its rail should still flag as current.
        let currentPhase = currentId.flatMap { id in tasks.first { $0.id == id }?.phase }
        var columns: [PhaseColumn] = []
        var rails: [PhaseRail] = []
        for p in phases {
            let list = tasks.filter { $0.phase == p }
            let done = list.filter { $0.done }.count
            if expandedSet.contains(p) {
                columns.append(PhaseColumn(phase: p, x: xOf[p] ?? 0, done: done,
                                           total: list.count, current: p == currentPhase))
            } else {
                rails.append(PhaseRail(phase: p, x: xOf[p] ?? 0, done: done, total: list.count))
            }
        }

        var root: CGRect?
        var rootEdges: [EdgePath] = []
        if hasRoot {
            let ry = ((height - RoadmapGeometry.rootH) / 2).rounded()
            root = CGRect(x: RoadmapGeometry.rootLeft, y: ry,
                          width: RoadmapGeometry.rootW, height: RoadmapGeometry.rootH)
            let start = CGPoint(x: RoadmapGeometry.rootRight, y: ry + RoadmapGeometry.rootH / 2)
            for n in nodes where n.task.dependsOn.allSatisfy({ !ids.contains($0) }) {
                rootEdges.append(EdgePath(from: rootId, to: n.task.id,
                                          points: elbow(from: start,
                                                        to: CGPoint(x: n.x, y: centerY(n))),
                                          critical: false))
            }
        }

        return RoadmapLayout(nodes: nodes, edges: edges, columns: columns, rails: rails,
                             root: root, rootEdges: rootEdges,
                             size: CGSize(width: width, height: height))
    }
}
