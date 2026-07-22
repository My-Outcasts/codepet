// codepet/Models/RoadmapMapLayout.swift
import CoreGraphics

/// One node in the roadmap map. The company root has `task == nil`.
struct MapNode: Identifiable { let id: String; let task: RoadmapTask?; let x: CGFloat; let y: CGFloat }
/// A dependency edge (from → to). `critical` marks the beacon's dependency chain.
struct MapEdge { let fromId: String; let toId: String; let critical: Bool }
struct RoadmapMap { let nodes: [MapNode]; let edges: [MapEdge]; let size: CGSize }

/// Pure geometry for the Overview node-graph map (web RoadmapView): columns = phases,
/// rows = task order, a company root node at the left, dependency edges, critical path.
enum RoadmapMapLayout {
    static let rootId = "__root__"

    static func layout(_ tasks: [RoadmapTask], col: CGFloat = 260, row: CGFloat = 108,
                       cardW: CGFloat = 200, cardH: CGFloat = 76, pad: CGFloat = 40) -> RoadmapMap {
        let phases = RoadmapPhase.allCases
        var byPhase: [RoadmapPhase: [RoadmapTask]] = [:]
        for t in tasks { byPhase[t.phase, default: []].append(t) }
        let maxRows = max(1, phases.map { byPhase[$0]?.count ?? 0 }.max() ?? 0)

        var nodes: [MapNode] = []
        var pos: [String: CGPoint] = [:]

        // root: column 0, vertically centered against the tallest column
        let rootX = pad
        let rootY = pad + CGFloat(maxRows - 1) * row / 2
        nodes.append(MapNode(id: rootId, task: nil, x: rootX, y: rootY))
        pos[rootId] = CGPoint(x: rootX, y: rootY)

        for (pi, phase) in phases.enumerated() {
            let list = byPhase[phase] ?? []
            let x = pad + CGFloat(pi + 1) * col
            let yOffset = CGFloat(maxRows - list.count) * row / 2   // center the column
            for (ri, task) in list.enumerated() {
                let y = pad + yOffset + CGFloat(ri) * row
                nodes.append(MapNode(id: task.id, task: task, x: x, y: y))
                pos[task.id] = CGPoint(x: x, y: y)
            }
        }

        // beacon + its transitive dependency ids → critical path
        let beacon = RoadmapEngine.nextStep(tasks)
        var criticalIds = Set<String>()
        if let b = beacon {
            criticalIds.insert(b.id)
            let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var stack = b.dependsOn
            while let id = stack.popLast() {
                if criticalIds.insert(id).inserted, let dep = byId[id] { stack.append(contentsOf: dep.dependsOn) }
            }
        }

        var edges: [MapEdge] = []
        let firstPhase = phases.first
        for t in tasks {
            if t.dependsOn.isEmpty && t.phase == firstPhase {
                edges.append(MapEdge(fromId: rootId, toId: t.id, critical: criticalIds.contains(t.id)))
            }
            for dep in t.dependsOn where pos[dep] != nil {
                // Critical if the edge TOUCHES the beacon or its dependency chain
                // (web highlights edges touching the current move), i.e. either endpoint.
                edges.append(MapEdge(fromId: dep, toId: t.id,
                                     critical: criticalIds.contains(t.id) || criticalIds.contains(dep)))
            }
        }

        let width = pad * 2 + CGFloat(phases.count + 1) * col
        let height = pad * 2 + CGFloat(maxRows) * row
        return RoadmapMap(nodes: nodes, edges: edges, size: CGSize(width: width, height: height))
    }
}
