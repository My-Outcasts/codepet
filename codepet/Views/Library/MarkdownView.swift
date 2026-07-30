// codepet/Views/Library/MarkdownView.swift
import SwiftUI

/// Renders markdown (via MarkdownBlocks.parse) as CodepetTheme-styled blocks — one
/// viewer for every deliverable kind. Inline emphasis via AttributedString(markdown:).
struct MarkdownView: View {
    let markdown: String
    private var blocks: [MarkdownBlock] { MarkdownBlocks.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accent: Color { CodepetTheme.accentPurple }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            inline(text)
                .font(CodepetTheme.inter(level == 1 ? 20 : level == 2 ? 17 : 15,
                                         weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .padding(.top, level <= 2 ? 4 : 0)
        case let .numbered(index, text):
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(CodepetTheme.inter(12, weight: .bold))
                    .foregroundColor(CodepetTheme.onAccent(accent))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(accent))
                inline(text)
                    .font(CodepetTheme.inter(15))
                    .lineSpacing(4)
                    .foregroundColor(CodepetTheme.bodyText)
                    .padding(.top, 1)
            }
        case let .bullet(text):
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(accent).frame(width: 6, height: 6).padding(.top, 8).padding(.leading, 8)
                inline(text)
                    .font(CodepetTheme.inter(15))
                    .lineSpacing(4)
                    .foregroundColor(CodepetTheme.bodyText)
            }
        case let .paragraph(text):
            inline(text)
                .font(CodepetTheme.inter(15))
                .lineSpacing(4)
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
