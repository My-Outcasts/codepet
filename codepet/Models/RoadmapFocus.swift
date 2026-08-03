// codepet/Models/RoadmapFocus.swift
import CoreGraphics

/// Which phases earn a full card column, given the room available. Everything else collapses to
/// a rail (`PhaseRail`). Pure and deterministic so the board's shape is testable without a view.
///
/// The rule is progressive disclosure, not truncation: whatever collapses is still visible as a
/// labelled, counted, clickable rail, so nothing is silently hidden.
enum RoadmapFocus {
    static func expanded(tasks: [RoadmapTask], availableWidth: CGFloat,
                         userExpanded: Set<RoadmapPhase> = []) -> Set<RoadmapPhase> {
        // Only phases that actually hold tasks can be columns — an empty phase has nothing to
        // show and would spend 208pt saying so.
        let populated = RoadmapPhase.allCases.filter { p in tasks.contains { $0.phase == p } }
        guard let first = populated.first else { return [] }

        let open = RoadmapGating.openPhases(tasks)
        // The working edge: the last OPEN phase with tasks — where the beacon lives.
        let working = populated.last { open.contains($0) } ?? first
        let states = RoadmapGating.states(tasks)
        let preview = populated.first { states[$0] == .preview }

        // Never dropped: the phase the founder is working in, plus anything they opened by hand.
        var keep: Set<RoadmapPhase> = [working]
        keep.formUnion(userExpanded.filter(populated.contains))

        // Then outward from the working phase — the preview first (the one look-ahead), then
        // nearest-first, earlier phases winning ties.
        let workingIndex = populated.firstIndex(of: working) ?? 0
        var order: [RoadmapPhase] = []
        if let preview, !keep.contains(preview) { order.append(preview) }
        order += populated.enumerated()
            .filter { !keep.contains($0.element) && $0.element != preview }
            .sorted { a, b in
                let da = abs(a.offset - workingIndex), db = abs(b.offset - workingIndex)
                return da != db ? da < db : a.offset < b.offset
            }
            .map(\.element)

        for phase in order {
            var trial = keep
            trial.insert(phase)
            if RoadmapGeometry.boardWidth(expanded: trial) <= availableWidth { keep = trial }
        }
        return keep
    }
}
