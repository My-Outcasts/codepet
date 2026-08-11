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
