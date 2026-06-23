import SwiftUI

// =============================================================================
// MARK: - MentorQACard
// =============================================================================

/// Horizontal card for a mentor Q&A entry. Colored icon square on the left,
/// question + hint in the middle, chevron on the right. Pixel-art border and
/// drop shadow using PixelStaircaseRectangle.
struct MentorQACard: View {
    let qa: MentorQA
    let isRead: Bool
    var onTap: () -> Void

    private let borderColor = Color(hex: "#2D2B26")

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // ─────────────────────────────────────────────────────────────
                // Colored icon square
                // ─────────────────────────────────────────────────────────────
                ZStack {
                    PixelStaircaseRectangle(blockSize: 2, steps: 2)
                        .fill(Color(hex: qa.iconColor))
                        .frame(width: 40, height: 40)

                    Image(systemName: qa.iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .overlay(
                    PixelStaircaseRectangle(blockSize: 2, steps: 2)
                        .stroke(borderColor, lineWidth: 2)
                )

                // ─────────────────────────────────────────────────────────────
                // Question + hint
                // ─────────────────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 3) {
                    Text(qa.question)
                        .font(CodepetTheme.body(13, weight: .semibold))
                        .foregroundColor(isRead ? CodepetTheme.mutedText : borderColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(qa.hint)
                        .font(CodepetTheme.body(11, weight: .regular))
                        .foregroundColor(CodepetTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                // ─────────────────────────────────────────────────────────────
                // Read indicator or chevron
                // ─────────────────────────────────────────────────────────────
                if isRead {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#029902").opacity(0.6))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                }
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .background(
            ZStack {
                // Shadow layer
                PixelStaircaseRectangle(blockSize: 3, steps: 2)
                    .fill(borderColor)
                    .offset(x: 3, y: 3)
                // White base
                PixelStaircaseRectangle(blockSize: 3, steps: 2)
                    .fill(Color.white)
                // Fill
                PixelStaircaseRectangle(blockSize: 3, steps: 2)
                    .fill(Color(hex: "#FDFCFF"))
            }
        )
        .overlay(
            PixelStaircaseRectangle(blockSize: 3, steps: 2)
                .stroke(borderColor, lineWidth: 3)
        )
    }
}
