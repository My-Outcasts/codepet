import SwiftUI

// =============================================================================
// MARK: - ChapterReaderView
// =============================================================================

/// Full-screen reader for an individual chapter. Shows the narrative text in
/// serif font, a highlighted "Key Lesson" callout, optional challenge and code
/// snippet sections, and a "Mark as complete" button at the bottom.
struct ChapterReaderView: View {
    @EnvironmentObject var learnProgress: LearnProgress
    @Environment(\.dismiss) private var dismiss

    let chapter: Chapter
    let caseStudyTitle: String
    let chapterNumber: Int

    private var isCompleted: Bool {
        learnProgress.completedChapterIds.contains(chapter.id)
    }

    private let borderColor = Color(hex: "#2D2B26")

    var body: some View {
        ZStack {
            Color(hex: "#F7F5FC")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ─────────────────────────────────────────────────────────────
                // Top bar
                // ─────────────────────────────────────────────────────────────
                topBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {

                        // ─────────────────────────────────────────────────────
                        // Chapter header
                        // ─────────────────────────────────────────────────────
                        chapterHeader

                        // ─────────────────────────────────────────────────────
                        // Narrative text
                        // ─────────────────────────────────────────────────────
                        narrativeSection

                        // ─────────────────────────────────────────────────────
                        // Key Lesson callout
                        // ─────────────────────────────────────────────────────
                        keyLessonCallout

                        // ─────────────────────────────────────────────────────
                        // Challenge (optional)
                        // ─────────────────────────────────────────────────────
                        if let challenge = chapter.challenge {
                            challengeSection(challenge)
                        }

                        // ─────────────────────────────────────────────────────
                        // Code Snippet (optional)
                        // ─────────────────────────────────────────────────────
                        if let code = chapter.codeSnippet {
                            codeSnippetSection(code)
                        }

                        // ─────────────────────────────────────────────────────
                        // Mark as complete button
                        // ─────────────────────────────────────────────────────
                        completeButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(CodepetTheme.body(14, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#7C3AED"))
            }
            .buttonStyle(.plain)

            Spacer()

            if isCompleted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                    Text("Completed")
                        .font(CodepetTheme.body(12, weight: .semibold))
                }
                .foregroundColor(Color(hex: "#029902"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(hex: "#F7F5FC"))
    }

    // MARK: - Chapter Header

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CHAPTER \(chapterNumber)")
                .font(CodepetTheme.body(10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(Color(hex: "#7C3AED"))

            Text(chapter.title)
                .font(CodepetTheme.display(24))
                .foregroundColor(borderColor)

            Text(caseStudyTitle)
                .font(CodepetTheme.body(12, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
        }
    }

    // MARK: - Narrative

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            let paragraphs = chapter.narrative
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(ReflectionTheme.serif(14))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Key Lesson Callout

    private var keyLessonCallout: some View {
        HStack(alignment: .top, spacing: 12) {
            // Accent bar
            PixelStaircaseRectangle(blockSize: 2, steps: 1)
                .fill(Color(hex: "#7C3AED"))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "#7C3AED"))
                    Text("KEY LESSON")
                        .font(CodepetTheme.body(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(Color(hex: "#7C3AED"))
                }

                Text(chapter.keyLesson)
                    .font(CodepetTheme.body(14, weight: .semibold))
                    .foregroundColor(borderColor)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .pixelBox(
            fill: Color(hex: "#7C3AED").opacity(0.06),
            borderColor: Color(hex: "#7C3AED").opacity(0.3),
            shadowOffset: 0,
            blockSize: 3,
            steps: 2,
            borderWidth: 2
        )
    }

    // MARK: - Challenge Section

    private func challengeSection(_ challenge: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#E07650"))
                Text("CHALLENGE")
                    .font(CodepetTheme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "#E07650"))
            }

            Text(challenge)
                .font(ReflectionTheme.serif(13))
                .foregroundColor(CodepetTheme.bodyText)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .pixelBox(
            fill: Color(hex: "#E07650").opacity(0.06),
            borderColor: Color(hex: "#E07650").opacity(0.3),
            shadowOffset: 0,
            blockSize: 3,
            steps: 2,
            borderWidth: 2
        )
    }

    // MARK: - Code Snippet Section

    private func codeSnippetSection(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "#1C40CF"))
                Text("CODE")
                    .font(CodepetTheme.body(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(Color(hex: "#1C40CF"))
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(Color(hex: "#E8E3D8"))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                PixelStaircaseRectangle(blockSize: 3, steps: 2)
                    .fill(Color(hex: "#1E1B2E"))
            )
            .overlay(
                PixelStaircaseRectangle(blockSize: 3, steps: 2)
                    .stroke(Color(hex: "#2D2B26"), lineWidth: 2)
            )
        }
    }

    // MARK: - Complete Button

    private var completeButton: some View {
        HStack {
            Spacer()

            if isCompleted {
                Button(action: {}) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Completed")
                            .font(CodepetTheme.body(14, weight: .bold))
                    }
                }
                .buttonStyle(PixelButtonStyle(
                    fill: Color(hex: "#029902"),
                    foreground: .white,
                    borderColor: Color(hex: "#2D2B26"),
                    paddingH: 20,
                    paddingV: 10,
                    blockSize: 3,
                    steps: 2,
                    borderWidth: 3,
                    shadowOffset: 3
                ))
                .disabled(true)
            } else {
                Button(action: {
                    learnProgress.markChapterCompleted(chapter.id)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text("Mark as complete")
                            .font(CodepetTheme.body(14, weight: .bold))
                    }
                }
                .buttonStyle(PixelButtonStyle(
                    fill: Color(hex: "#7C3AED"),
                    foreground: .white,
                    borderColor: Color(hex: "#2D2B26"),
                    paddingH: 20,
                    paddingV: 10,
                    blockSize: 3,
                    steps: 2,
                    borderWidth: 3,
                    shadowOffset: 3
                ))
            }

            Spacer()
        }
        .padding(.top, 8)
    }
}
