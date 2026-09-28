// codepet/Views/Library/MarkdownView.swift
import SwiftUI

/// Renders markdown (via MarkdownBlocks.parse) as CodepetTheme-styled blocks — one
/// viewer for every deliverable kind. Inline emphasis via AttributedString(markdown:).
///
/// This is the LAST-RESORT renderer, and it was the worst-set surface in the app: 12pt, zero
/// `lineSpacing`, headings only 1–4pt larger than the body they introduced. It catches `.text`,
/// `.other`, any kind whose structured payload did not survive, AND the whole body of every
/// `.legal` and `.post` — so the deliverables with the least structure were the hardest to read,
/// which is backwards.
///
/// It now sets prose at `DeliverableStyle`'s reading size with real leading, and gives headings
/// a step big enough to see. Blanks are tinted here too: an unstructured department output is
/// exactly where a stray `[name]` is easiest to miss.
struct MarkdownView: View {
    let markdown: String
    private var blocks: [MarkdownBlock] { MarkdownBlocks.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text)
                .font(.pixelSystem(size: level == 1 ? 19 : level == 2 ? 17 : DeliverableStyle.heading,
                                   weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
                .padding(.top, 4)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 9) {
                Text("•")
                    .font(.pixelSystem(size: DeliverableStyle.body))
                    .foregroundColor(CodepetTheme.mutedText)
                inline(text)
                    .font(.pixelSystem(size: DeliverableStyle.body))
                    .lineSpacing(DeliverableStyle.leading)
                    .foregroundColor(CodepetTheme.bodyText)
            }
        case let .paragraph(text):
            inline(text)
                .font(.pixelSystem(size: DeliverableStyle.body))
                .lineSpacing(DeliverableStyle.leading)
                .foregroundColor(CodepetTheme.bodyText)
        case let .table(header, alignments, rows):
            // FIT first, scroll last. Each candidate narrows the cells a step, and the first whose
            // ideal width fits is the one drawn — so a 4-column cost table wraps its cells inside
            // a 460pt sheet instead of parking its $ columns off to the right. That is what build 4
            // shipped: always a hidden-indicator scroll at 240pt a cell, so "Rate assumed" and
            // "Per session" were reachable only by a sideways trackpad swipe nobody knew to make.
            // Below `MarkdownTableView.fitCaps.last` a cell is a word per line — the run-on
            // problem in a different shape — so past that it scrolls, and SAYS so: a visible
            // scroller and a fade at the trailing edge.
            ViewThatFits(in: .horizontal) {
                ForEach(MarkdownTableView.fitCaps, id: \.self) { cap in
                    MarkdownTableView(header: header, alignments: alignments, rows: rows,
                                      inline: inline, maxCell: cap)
                        .padding(.vertical, 2)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    MarkdownTableView(header: header, alignments: alignments, rows: rows,
                                      inline: inline, maxCell: MarkdownTableView.fitCaps.last ?? 90)
                        .padding(.vertical, 2)
                        .padding(.trailing, 28)
                        .padding(.bottom, 10)   // room for the scroller under the last row
                }
                .overlay(alignment: .trailing) {
                    LinearGradient(colors: [CodepetTheme.surface.opacity(0), CodepetTheme.surface],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Inline emphasis via AttributedString(markdown:), plain fallback, then the blanks tinted.
    /// Block structure is already handled by MarkdownBlocks, so interpret INLINE syntax
    /// only and preserve whitespace (avoids block re-grouping within a block).
    ///
    /// The tint runs on the PARSED string, never the source: parsing removes `**` and `_`
    /// markers, and every offset computed against the raw markdown would be shifted past them.
    /// `MessagePlaceholders.attributed` already does both in that order.
    private func inline(_ text: String) -> Text {
        Text(MessagePlaceholders.attributed(text,
                                            tint: DeliverableStyle.blankTint,
                                            ink: DeliverableStyle.blankInk))
    }
}

/// A pipe table as a grid: a semibold header row over a hairline, a fainter hairline between
/// rows, and each column aligned the way its separator row asked (`---:` for money columns).
/// Cells wrap past `maxCell`, so one long label cannot make the whole table a screen wide.
///
/// Its own view, not a `MarkdownView` method, so it can be rendered without the horizontal
/// `ScrollView` around it — `ImageRenderer` draws a macOS scroll view's content as blank.
struct MarkdownTableView: View {
    let header: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
    /// `MarkdownView`'s inline renderer, so cells get the same emphasis and blank tinting.
    let inline: (String) -> Text
    var maxCell: CGFloat = 240
    /// The cell caps `MarkdownView` tries in turn, widest first, before it falls back to a scroll.
    static let fitCaps: [CGFloat] = [240, 180, 140, 110, 90]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { c, text in
                    cell(text, column: c, isHeader: true)
                }
            }
            rule(CodepetTheme.hairline)
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                if r > 0 { rule(CodepetTheme.hairline.opacity(0.6)) }
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, text in
                        cell(text, column: c, isHeader: false)
                    }
                }
            }
        }
    }

    private func cell(_ text: String, column: Int, isHeader: Bool) -> some View {
        let alignment = alignments.indices.contains(column) ? alignments[column] : .leading
        return inline(text)
            .font(.pixelSystem(size: DeliverableStyle.body - 1, weight: isHeader ? .semibold : .regular))
            .lineSpacing(3)
            .foregroundColor(isHeader ? CodepetTheme.primaryText : CodepetTheme.bodyText)
            .multilineTextAlignment(alignment.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxCell, alignment: alignment.frame)
            .gridColumnAlignment(alignment.horizontal)
    }

    private func rule(_ color: Color) -> some View {
        Rectangle().fill(color).frame(height: 1).gridCellUnsizedAxes(.horizontal)
    }
}

private extension MarkdownTableAlignment {
    var horizontal: HorizontalAlignment {
        switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    var frame: Alignment {
        switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
    var text: TextAlignment {
        switch self { case .leading: .leading; case .center: .center; case .trailing: .trailing }
    }
}
