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

    // ── Edge routing ─────────────────────────────────────────────────────────────────
    /// How far a staggered vertical run keeps off BOTH walls of its gutter, so the spread can
    /// never touch a card's edge or be drawn on top of a preceding rail.
    static let trunkInset: CGFloat = 14
    /// A same-column hook hugs its column's left edge, INSIDE every inbound trunk's spread —
    /// so an in-phase dependency can't be drawn on top of a cross-phase one.
    static let sideHookInset: CGFloat = 8
    /// Clearance kept below the deepest routing corridor, so a corridor along the board's
    /// bottom row isn't stroked exactly on the canvas edge (where it renders half-clipped).
    static let corridorPad: CGFloat = 12

    /// The card-free horizontal corridor just below `row` — where a skip-level edge travels.
    ///
    /// Cards are `cardH` (64) tall on a `rowPitch` (96) pitch, so exactly `rowPitch - cardH`
    /// (32) is always free between one row's bottom and the next row's top; the corridor runs
    /// down its middle. Taking the corridor below `max(sourceRow, targetRow)` therefore clears
    /// every card on the board: it is below both endpoints' rows and above row `max + 1`.
    static func corridorY(below row: Int) -> CGFloat {
        top + CGFloat(row) * rowPitch + cardH + (rowPitch - cardH) / 2
    }

    /// Total board width for a given column mix — THE one width formula, shared by the layout
    /// engine (which must agree with what it draws) and `RoadmapFocus` (which must predict it
    /// before laying anything out). Columns accumulate their trailing gap; the last one's is
    /// replaced by `bottomPad`.
    static func boardWidth(expanded: Set<RoadmapPhase>, hasRoot: Bool = true) -> CGFloat {
        var cursor = hasRoot ? rootRight + rootGap : rootLeft
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

    /// The usable gap immediately LEFT of each phase's slot — the band an inbound edge's
    /// vertical run lives in. Deliberately derived, not assumed: `colGap` after a column,
    /// `railGap` after a rail, `rootGap` in front of the first phase (0 when there is no root,
    /// where column 0 starts flush at `rootLeft` and can only ever be entered by a
    /// same-column edge).
    private static func leadingGaps(expanded: Set<RoadmapPhase>, hasRoot: Bool) -> [RoadmapPhase: CGFloat] {
        var out: [RoadmapPhase: CGFloat] = [:]
        for (i, phase) in RoadmapPhase.allCases.enumerated() {
            if i == 0 {
                out[phase] = hasRoot ? RoadmapGeometry.rootGap : 0
            } else {
                out[phase] = expanded.contains(RoadmapPhase.allCases[i - 1])
                    ? RoadmapGeometry.colGap : RoadmapGeometry.railGap
            }
        }
        return out
    }

    private static func rowTop(_ row: Int) -> CGFloat {
        RoadmapGeometry.top + CGFloat(row) * RoadmapGeometry.rowPitch
    }

    /// The x of an edge's vertical run, inside the gutter whose RIGHT wall is `rightWall`.
    ///
    /// Staggered by `lane` (the SOURCE's row) rather than fixed at the gutter's middle. The
    /// old `b.x - colGap / 2` depended only on the TARGET's column, so every inbound edge of a
    /// column stacked its vertical onto the same 1.5pt line: one dependency and nine were
    /// indistinguishable, and the apparent weight of that shared trunk came from alpha
    /// stacking rather than from meaning. Keying on the source's lane separates edges that
    /// come from different places while still merging edges that leave the SAME place — which
    /// is honest, because that really is one fan-out.
    ///
    /// `gutter` is passed in, never assumed: it is `colGap` between two columns but only
    /// `railGap` when the preceding phase collapsed to a rail, and `rootGap` in front of the
    /// first phase. Hard-coding `colGap / 2` put the vertical 10pt INSIDE a preceding rail.
    /// `trunkInset` bounds the spread so it stays clear of both walls at any gutter width;
    /// a gutter too narrow to stagger degrades to a single centred trunk rather than
    /// overflowing onto a card or a rail.
    static func trunkX(rightWall: CGFloat, gutter: CGFloat, lane: Int) -> CGFloat {
        let half = max(0, gutter / 2 - RoadmapGeometry.trunkInset)
        let step = half / 2
        let offset = CGFloat(min(max(lane, 0), 4) - 2) * step
        return (rightWall - gutter / 2 + offset).rounded()
    }

    /// Orthogonal connector from a right-edge point to a left-edge point: a straight run when
    /// the rows line up, otherwise a 4-point elbow turning on `trunk`. Correct only when no
    /// card sits between the two columns on the source's row — otherwise use `detour`.
    static func route(from a: CGPoint, to b: CGPoint, trunk: CGFloat) -> [CGPoint] {
        if a.y == b.y { return [a, b] }
        return [a, CGPoint(x: trunk, y: a.y), CGPoint(x: trunk, y: b.y), b]
    }

    /// A skip-level connector: out of the source into its OWN trailing gutter, down (or up) to
    /// a card-free `corridor`, across every intervening column there, then into the target's
    /// gutter and in. Six points.
    ///
    /// This is the fix for the flaw that made the board unreadable. `route`'s horizontal leg
    /// runs at the SOURCE's y all the way to the target's gutter, so an edge that skips a
    /// column passes straight through the intervening column at that y. Cards are deliberately
    /// opaque (see `RoadmapCardView.cardFill` — a transparent card would let connectors bleed
    /// through it), so the line vanished behind the intervening card and re-emerged on its far
    /// side: A → C rendered as the chain A → B → C, inventing a dependency that was not in the
    /// data. Travelling in the corridor between two rows means the run can never pass behind
    /// a card at all.
    static func detour(from a: CGPoint, to b: CGPoint,
                       exit: CGFloat, corridor: CGFloat, trunk: CGFloat) -> [CGPoint] {
        [a,
         CGPoint(x: exit, y: a.y), CGPoint(x: exit, y: corridor),
         CGPoint(x: trunk, y: corridor),
         CGPoint(x: trunk, y: b.y), b]
    }

    /// Connector between two cards in the SAME column: a hook down the column's own left
    /// margin instead of doubling back through the cards. Both x's are the column's left edge.
    ///
    /// The hook hugs the card edge (`sideHookInset`) rather than sitting at the gutter's
    /// middle, where it used to be drawn on top of the inbound cross-phase trunks in the very
    /// same gutter — two structurally different relationships, identical and superimposed.
    static func sideHook(from a: CGPoint, to b: CGPoint, hook: CGFloat) -> [CGPoint] {
        [a, CGPoint(x: hook, y: a.y), CGPoint(x: hook, y: b.y), b]
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

        let gapOf = leadingGaps(expanded: expandedSet, hasRoot: hasRoot)
        func gutter(_ phase: RoadmapPhase) -> CGFloat { gapOf[phase] ?? RoadmapGeometry.colGap }

        // Would a horizontal run at `row` from column `cA` to column `cB` pass BEHIND a card?
        // Only cards can be dodged: a rail spans the board's full height, so no corridor can
        // route around one, and a rail holds no cards anyway.
        func obstructed(from cA: Int, to cB: Int, row: Int) -> Bool {
            guard cB - cA > 1 else { return false }
            return ((cA + 1)..<cB).contains { occ[$0]?.contains(row) == true }
        }

        /// The deepest corridor any routed edge uses, so the canvas can grow to contain it.
        var deepestCorridor: CGFloat = 0

        var edges: [EdgePath] = []
        for t in shown {
            for dep in t.dependsOn {
                guard ids.contains(dep), let a = nodeById[dep], let b = nodeById[t.id] else { continue }
                let points: [CGPoint]
                if a.col == b.col {
                    points = sideHook(from: CGPoint(x: a.x, y: centerY(a)),
                                      to: CGPoint(x: b.x, y: centerY(b)),
                                      hook: (b.x - RoadmapGeometry.sideHookInset).rounded())
                } else {
                    let aPt = CGPoint(x: rightX(a), y: centerY(a))
                    let bPt = CGPoint(x: b.x, y: centerY(b))
                    let trunk = trunkX(rightWall: b.x, gutter: gutter(b.task.phase), lane: a.row)
                    // A skip-level edge detours through a card-free corridor. `a.col + 1` is
                    // guaranteed in range: `obstructed` only returns true when b.col > a.col + 1.
                    if obstructed(from: a.col, to: b.col, row: a.row) {
                        let next = phases[a.col + 1]
                        let corridor = RoadmapGeometry.corridorY(below: max(a.row, b.row))
                        deepestCorridor = max(deepestCorridor, corridor)
                        points = detour(from: aPt, to: bPt,
                                        exit: trunkX(rightWall: xOf[next] ?? aPt.x,
                                                     gutter: gutter(next), lane: a.row),
                                        corridor: corridor, trunk: trunk)
                    } else {
                        points = route(from: aPt, to: bPt, trunk: trunk)
                    }
                }
                edges.append(EdgePath(from: dep, to: t.id, points: points,
                                      critical: t.id == currentId || dep == currentId))
            }
        }

        // Entry tasks — nothing inside the roadmap gates them, so the root is what feeds them.
        let entries = nodes.filter { n in n.task.dependsOn.allSatisfy { !ids.contains($0) } }

        // A root edge reaching past column 0 crosses whole columns, so it needs the same
        // corridor treatment. Decided STRUCTURALLY (does any earlier column hold a card?)
        // rather than from the root's own y, because that y depends on the height this very
        // loop is about to determine. Over-detouring is safe: a corridor is always card-free.
        var rootCorridor: [String: CGFloat] = [:]
        if hasRoot {
            for n in entries where n.col > 0 {
                guard (0..<n.col).contains(where: { occ[$0]?.isEmpty == false }) else { continue }
                let corridor = RoadmapGeometry.corridorY(below: n.row)
                rootCorridor[n.task.id] = corridor
                deepestCorridor = max(deepestCorridor, corridor)
            }
        }

        let maxRows = max(1, nodes.map { $0.row + 1 }.max() ?? 1)
        let rowsHeight = RoadmapGeometry.top + CGFloat(maxRows - 1) * RoadmapGeometry.rowPitch
            + RoadmapGeometry.cardH + RoadmapGeometry.bottomPad
        // `corridorY(below: maxRows - 1)` lands exactly ON `rowsHeight`, so a corridor along the
        // bottom row would be stroked half-outside the canvas. Grow to keep it inside.
        let height = deepestCorridor > 0
            ? max(rowsHeight, deepestCorridor + RoadmapGeometry.corridorPad)
            : rowsHeight
        let width = RoadmapGeometry.boardWidth(expanded: expandedSet, hasRoot: hasRoot)

        // The current phase is read from the WHOLE task set, not just the shown ones: the
        // beacon's phase may be collapsed into a rail, so `shown`/`expandedSet` can't be used here.
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
            // Seated on the rows it actually connects to, NOT on the canvas centre. Centring on
            // the canvas put the root's edge y a few points off every lane it fed (12pt, with
            // `top: 40` and one row) — so each root edge picked up a pointless little jog and
            // then ran parallel to, and a hair above, the real edges on that lane. With a single
            // entry task the first leg is now dead straight.
            let anchorY = entries.isEmpty
                ? height / 2
                : entries.map { centerY($0) }.reduce(0, +) / CGFloat(entries.count)
            let ry = min(max(0, (anchorY - RoadmapGeometry.rootH / 2).rounded()),
                         max(0, height - RoadmapGeometry.rootH))
            root = CGRect(x: RoadmapGeometry.rootLeft, y: ry,
                          width: RoadmapGeometry.rootW, height: RoadmapGeometry.rootH)
            let start = CGPoint(x: RoadmapGeometry.rootRight, y: ry + RoadmapGeometry.rootH / 2)
            for n in entries {
                let bPt = CGPoint(x: n.x, y: centerY(n))
                // Each root edge gets its own trunk (keyed on the TARGET's row): unlike a
                // dependency fan-out, these want to be countable, not bundled.
                let trunk = trunkX(rightWall: n.x, gutter: gutter(n.task.phase), lane: n.row)
                let points: [CGPoint]
                if let corridor = rootCorridor[n.task.id] {
                    let first = phases[0]
                    points = detour(from: start, to: bPt,
                                    exit: trunkX(rightWall: xOf[first] ?? start.x,
                                                 gutter: gutter(first), lane: n.row),
                                    corridor: corridor, trunk: trunk)
                } else {
                    points = route(from: start, to: bPt, trunk: trunk)
                }
                rootEdges.append(EdgePath(from: rootId, to: n.task.id, points: points,
                                          critical: false))
            }
        }

        return RoadmapLayout(nodes: nodes, edges: edges, columns: columns, rails: rails,
                             root: root, rootEdges: rootEdges,
                             size: CGSize(width: width, height: height))
    }
}
