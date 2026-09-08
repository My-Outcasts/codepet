// codepet/Views/Copilot/WrapLayout.swift
import SwiftUI

/// Lays children left to right, wrapping to a new row when the next one will not fit.
///
/// Exists because the composer must show EVERY attached file: ten tiles do not fit one 380pt
/// dock row, and an overflow counter would put state the founder cannot see into the control
/// she is about to send from.
///
/// The row-breaking is `rows(widths:available:spacing:)` — a static function over plain
/// numbers, so it is checkable without a view hierarchy. `sizeThatFits` and `placeSubviews`
/// are thin wrappers over it.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    /// Index groups, one per row. Pure arithmetic — see the type's comment.
    ///
    /// An item wider than `available` takes a row of its own rather than being skipped: a
    /// dropped child is an invisible failure, and this file exists because of one of those.
    static func rows(widths: [CGFloat], available: CGFloat, spacing: CGFloat) -> [[Int]] {
        var out: [[Int]] = []
        var row: [Int] = []
        var used: CGFloat = 0
        for (i, w) in widths.enumerated() {
            let gap = row.isEmpty ? 0 : spacing
            if !row.isEmpty && used + gap + w > available {
                out.append(row)
                row = [i]
                used = w
            } else {
                row.append(i)
                used += gap + w
            }
        }
        if !row.isEmpty { out.append(row) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(widths: sizes.map(\.width), available: available, spacing: spacing)

        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for row in rows {
            var rowHeight: CGFloat = 0
            var rowWidth: CGFloat = 0
            for (position, index) in row.enumerated() {
                rowHeight = max(rowHeight, sizes[index].height)
                rowWidth += sizes[index].width
                if position > 0 { rowWidth += spacing }
            }
            totalHeight += rowHeight
            maxRowWidth = max(maxRowWidth, rowWidth)
        }
        if rows.count > 1 { totalHeight += rowSpacing * CGFloat(rows.count - 1) }
        return CGSize(width: min(maxRowWidth, available), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = Self.rows(widths: sizes.map(\.width), available: bounds.width, spacing: spacing)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            var rowHeight: CGFloat = 0
            for i in row { rowHeight = max(rowHeight, sizes[i].height) }
            for i in row {
                subviews[i].place(at: CGPoint(x: x, y: y + (rowHeight - sizes[i].height) / 2),
                                  proposal: ProposedViewSize(sizes[i]))
                x += sizes[i].width + spacing
            }
            y += rowHeight + rowSpacing
        }
    }
}
