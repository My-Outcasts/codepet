// codepet/Views/Library/MarkdownView.swift
import SwiftUI

/// Renders markdown (via MarkdownBlocks.parse) as CodepetTheme-styled blocks — one
/// viewer for every deliverable kind. Inline emphasis via AttributedString(markdown:).
struct MarkdownView: View {
    let markdown: String
    private var blocks: [MarkdownBlock] { MarkdownBlocks.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .font(.pixelSystem(size: level == 1 ? 16 : level == 2 ? 14 : 13, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
        case let .bullet(text):
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundColor(CodepetTheme.mutedText)
                inline(text).foregroundColor(CodepetTheme.bodyText)
            }
            .font(.pixelSystem(size: 12))
        case let .paragraph(text):
            inline(text)
                .font(.pixelSystem(size: 12))
                .foregroundColor(CodepetTheme.bodyText)
        }
    }

    /// Inline emphasis via AttributedString(markdown:), plain fallback. Block
    /// structure is already handled by MarkdownBlocks, so interpret INLINE syntax
    /// only and preserve whitespace (avoids block re-grouping within a block).
    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: text, options: options) { return Text(attr) }
        return Text(text)
    }
}
