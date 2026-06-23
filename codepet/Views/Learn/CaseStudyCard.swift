import SwiftUI

// =============================================================================
// MARK: - CaseStudyCard
// =============================================================================

struct CaseStudyCard: View {
    let caseStudy: CaseStudy
    let progress: Double
    let completedCount: Int
    var onTap: () -> Void

    private var totalChapters: Int { caseStudy.chapters.count }
    private var isComingSoon: Bool { totalChapters == 0 }
    private var isInProgress: Bool { completedCount > 0 && completedCount < totalChapters }
    private var isComplete: Bool { totalChapters > 0 && completedCount == totalChapters }
    private var cardColor: Color { Color(hex: caseStudy.color) }
    private let dark = Color(hex: "#2D2B26")

    private var tagLine: String {
        let chapterLabel = "\(totalChapters) chapter\(totalChapters == 1 ? "" : "s")"
        let tagStr = caseStudy.tags.joined(separator: ", ")
        return "\(chapterLabel) \u{00B7} \(tagStr)"
    }

    var body: some View {
        Button(action: { if !isComingSoon { onTap() } }) {
            VStack(spacing: 0) {
                // ── Banner ──
                ZStack {
                    cardColor

                    // Decorative circles for texture
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 80, height: 80)
                        .offset(x: -50, y: -30)
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 60, height: 60)
                        .offset(x: 60, y: 20)

                    // Icon — centered, always visible
                    Image(systemName: caseStudy.icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))

                    // Status badge (top-right)
                    if isInProgress {
                        VStack {
                            HStack {
                                Spacer()
                                Text("In progress")
                                    .font(.pixelSystem(size: 9, weight: .bold))
                                    .foregroundColor(Color(hex: "#2D2B26"))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                            .fill(Color(hex: "#FCBE1D"))
                                    )
                                    .overlay(
                                        PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                            .stroke(dark, lineWidth: 2)
                                    )
                                    .padding(8)
                            }
                            Spacer()
                        }
                    } else if isComplete {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                            .fill(Color(hex: "#029902"))
                                    )
                                    .overlay(
                                        PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                            .stroke(dark, lineWidth: 2)
                                    )
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(height: 100)
                .clipped()

                // ── Body ──
                VStack(alignment: .leading, spacing: 6) {
                    Text(caseStudy.title)
                        .font(.pixelSystem(size: 14, weight: .bold))
                        .foregroundColor(dark)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if isComingSoon {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 9))
                            Text("Coming soon")
                                .font(.pixelSystem(size: 10, weight: .medium))
                        }
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.top, 2)
                    } else {
                        Text(tagLine)
                            .font(.pixelSystem(size: 10))
                            .foregroundColor(CodepetTheme.mutedText)
                            .lineLimit(1)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(dark.opacity(0.1))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isComplete ? Color(hex: "#029902") : cardColor)
                                    .frame(width: max(geo.size.width * progress, progress > 0 ? 6 : 0), height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text("\(completedCount)/\(totalChapters) chapters")
                            .font(.pixelSystem(size: 10))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#FDFCFF"))
            }
        }
        .buttonStyle(.plain)
        .opacity(isComingSoon ? 0.7 : 1)
        .background(
            PixelStaircaseRectangle(blockSize: 3, steps: 2)
                .fill(dark)
                .offset(x: 3, y: 3)
        )
        .background(
            PixelStaircaseRectangle(blockSize: 3, steps: 2)
                .fill(Color.white)
        )
        .clipShape(PixelStaircaseRectangle(blockSize: 3, steps: 2))
        .overlay(
            PixelStaircaseRectangle(blockSize: 3, steps: 2)
                .stroke(dark, lineWidth: 3)
        )
    }
}
