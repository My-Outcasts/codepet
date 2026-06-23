import SwiftUI

/// The hero "Today's guidance" card in the Tips tab.
/// Option A design: pet speech bubble — bold colored card with pixel-art
/// style, approach pills for deep-dive, visually distinct from health checklist.
struct GuidanceCardView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tipsState: TipsState
    @EnvironmentObject var projectStore: ProjectStore
    @Environment(\.uiLanguage) private var uiLanguage

    var onRetry: (() -> Void)?

    /// Brand colors for the guidance card background, cycling per mood.
    private var cardColor: Color {
        guard let mood = tipsState.currentGuidance?.mood else {
            return Color(hex: "#9538CF")  // default purple
        }
        switch mood {
        case "excited":   return Color(hex: "#E24B4A")  // Red
        case "thinking":  return Color(hex: "#1C40CF")  // Blue
        case "proud":     return Color(hex: "#029902")  // Green
        case "concerned": return Color(hex: "#F58345")  // Orange
        case "cheering":  return Color(hex: "#FCBE1D")  // Yellow
        default:          return Color(hex: "#9538CF")  // Purple
        }
    }

    /// Whether the card color is light enough to need dark text (yellow).
    private var useDarkText: Bool {
        tipsState.currentGuidance?.mood == "cheering"
    }

    private var textPrimary: Color { useDarkText ? Color(hex: "#2D2B26") : .white }
    private var textSecondary: Color { useDarkText ? Color(hex: "#2D2B26").opacity(0.65) : Color.white.opacity(0.65) }

    private var pet: PetCharacter? {
        PetCharacter.all[appState.activeChar]
    }

    /// Bold + highlight any known project names that appear in the body text,
    /// so the user can see at a glance which project the insight is about.
    private func highlightedBody(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        // Invert against the card: white chip on colored cards, dark chip on
        // the light (cheering/yellow) card — always high contrast.
        let hlBackground: Color = useDarkText ? Color(hex: "#2D2B26") : .white
        let hlForeground: Color = useDarkText ? .white : cardColor

        // Longest names first so a project that contains another's name as a
        // substring wins the match.
        let names = projectStore.projects.values
            .map { $0.displayName }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for name in names {
            var idx = result.startIndex
            while idx < result.endIndex, let r = result[idx...].range(of: name) {
                result[r].font = .pixelSystem(size: 14, weight: .bold)
                result[r].foregroundColor = hlForeground
                result[r].backgroundColor = hlBackground
                idx = r.upperBound
            }
        }
        return result
    }

    // MARK: - Section helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.pixelSystem(size: 9, weight: .bold))
            .tracking(1.2)
            .foregroundColor(textSecondary)
    }

    /// Highlighted project chip — inverts against the card for contrast.
    private func projectChip(_ name: String) -> some View {
        Text(name)
            .font(.pixelSystem(size: 9, weight: .bold))
            .foregroundColor(useDarkText ? .white : cardColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(useDarkText ? Color(hex: "#2D2B26") : .white)
            )
    }

    private func bulletRow(glyph: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(textPrimary)
                .padding(.top, 1)
            Text(highlightedBody(text))
                .font(.pixelSystem(size: 14))
                .foregroundColor(textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Auto-refreshes on each new app build (see TipsTabView) — no
            // manual reload control.
            Eyebrow(text: uiLanguage == .vi ? "Trọng tâm hôm nay" : "Your focus today")

            if tipsState.isLoadingGuidance {
                loadingSkeleton
            } else if let error = tipsState.guidanceError {
                errorState(error)
            } else if tipsState.isGuidanceDismissed {
                dismissedState
            } else if let guidance = tipsState.currentGuidance, guidance.isFresh {
                liveCard(guidance)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Live guidance card (Option A: pet speech bubble)

    private func liveCard(_ guidance: GuidanceResult) -> some View {
        PixelCard(fill: cardColor, borderWidth: 3) {
            VStack(alignment: .leading, spacing: 0) {
                // ── Pet identity row (darker tint) ──
                HStack(spacing: 10) {
                    // Pet avatar — pixel square with solid white bg
                    ZStack {
                        PixelStaircaseRectangle(blockSize: 2, steps: 1)
                            .fill(Color.white)
                        if let pet = pet {
                            Image(pet.imageName)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .padding(3)
                        } else {
                            Image(systemName: "star.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(cardColor)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .overlay(
                        PixelStaircaseRectangle(blockSize: 2, steps: 1)
                            .stroke(Color(hex: "#2D2B26"), lineWidth: 2)
                    )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(pet?.name.capitalized ?? "Your pet")
                            .font(.pixelSystem(size: 13, weight: .bold))
                            .foregroundColor(textPrimary)
                        Text(uiLanguage == .vi ? "dựa trên các phiên gần đây" : "based on recent sessions")
                            .font(.pixelSystem(size: 10))
                            .foregroundColor(textSecondary)
                    }

                    Spacer()

                    // Dismiss X
                    Button(action: { tipsState.dismissGuidance() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(textPrimary)
                            .frame(width: 24, height: 24)
                            .background(
                                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                    .fill(Color.black.opacity(0.15))
                            )
                            .overlay(
                                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                    .stroke(textPrimary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.1))

                // ── Main message — two clear sections ──
                VStack(alignment: .leading, spacing: 14) {
                    // Completion beat — only when the previous focus was achieved
                    if guidance.status == "completed" {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(uiLanguage == .vi
                                 ? "Hoàn thành trọng tâm trước — đây là bước tiếp theo"
                                 : "Last focus complete — here's your next one")
                                .font(.pixelSystem(size: 9, weight: .bold))
                        }
                        .foregroundColor(textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                .fill(Color.white.opacity(0.22))
                        )
                    }

                    Text(guidance.headline)
                        .font(ReflectionTheme.serif(18, weight: .semibold))
                        .foregroundColor(textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    // ── Section 1: Where you're at ──
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            sectionLabel(uiLanguage == .vi ? "TÌNH HÌNH" : "WHERE YOU'RE AT")
                            if let project = guidance.project, !project.isEmpty {
                                projectChip(project)
                            }
                        }
                        bulletRow(glyph: "checkmark.circle.fill", text: guidance.strength)
                        if let gap = guidance.gap, !gap.isEmpty {
                            bulletRow(glyph: "exclamationmark.circle.fill", text: gap)
                        }
                    }

                    // ── Section 2: Your move ──
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel(uiLanguage == .vi ? "BƯỚC TIẾP THEO" : "YOUR MOVE")
                        bulletRow(glyph: "arrow.right.circle.fill", text: guidance.move)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        PixelCard(fill: Color(hex: "#9538CF"), borderWidth: 3) {
            VStack(alignment: .leading, spacing: 12) {
                // Pet row skeleton
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 80, height: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 120, height: 10)
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 2)

                // Content skeleton
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 18)
                        .frame(maxWidth: 280)
                        .skeletonPulse()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 12)
                        .skeletonPulse()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 12)
                        .frame(maxWidth: 220)
                        .skeletonPulse()
                }
            }
            .padding(16)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        PixelCard(fill: Color(hex: "#9538CF").opacity(0.15), borderWidth: 3) {
            HStack(spacing: 12) {
                ZStack {
                    PixelStaircaseRectangle(blockSize: 2, steps: 1)
                        .fill(Color(hex: "#9538CF").opacity(0.15))
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "#9538CF"))
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(uiLanguage == .vi
                         ? "Chưa đủ dữ liệu để gợi ý"
                         : "Not enough data for guidance yet")
                        .font(.pixelSystem(size: 13, weight: .bold))
                        .foregroundColor(ReflectionTheme.primaryText)
                    Text(uiLanguage == .vi
                         ? "Code thêm vài session nữa nhé!"
                         : "Code a few more sessions and I'll have suggestions!")
                        .font(.pixelSystem(size: 11))
                        .foregroundColor(ReflectionTheme.mutedText)
                }
                Spacer()
            }
            .padding(14)
        }
    }

    // MARK: - Error state

    private func errorState(_ message: String) -> some View {
        PixelCard(fill: Color(hex: "#E24B4A"), borderWidth: 3) {
            HStack(spacing: 12) {
                ZStack {
                    PixelStaircaseRectangle(blockSize: 2, steps: 1)
                        .fill(Color.white.opacity(0.15))
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 6) {
                    Text(uiLanguage == .vi ? "Không tải được gợi ý" : "Couldn't load guidance")
                        .font(.pixelSystem(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Text(message)
                        .font(.pixelSystem(size: 10))
                        .foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(2)

                    Button(action: {
                        tipsState.guidanceError = nil
                        onRetry?()
                    }) {
                        Text(uiLanguage == .vi ? "Thử lại" : "Retry")
                    }
                    .buttonStyle(PixelButtonStyle(
                        fill: .white,
                        foreground: Color(hex: "#E24B4A"),
                        paddingH: 10,
                        paddingV: 5,
                        blockSize: 2,
                        steps: 1,
                        borderWidth: 2,
                        shadowOffset: 2,
                        font: .pixelSystem(size: 10, weight: .bold)
                    ))
                }
                Spacer()
            }
            .padding(14)
        }
    }

    // MARK: - Dismissed state

    private var dismissedState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "#029902"))
            Text(uiLanguage == .vi
                 ? "Trọng tâm hôm nay đã đọc. Quay lại mai nhé!"
                 : "Today's focus read. See you tomorrow!")
                .font(.pixelSystem(size: 12))
                .foregroundColor(ReflectionTheme.mutedText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PixelStaircaseRectangle(blockSize: 3, steps: 2)
                .fill(ReflectionTheme.cardBackground)
        )
        .overlay(
            PixelStaircaseRectangle(blockSize: 3, steps: 2)
                .stroke(Color(hex: "#2D2B26").opacity(0.15), lineWidth: 2)
        )
    }
}

// MARK: - Skeleton pulse for loading state

private struct SkeletonPulseModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(0.4 + 0.3 * sin(phase))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    phase = .pi
                }
            }
    }
}

extension View {
    fileprivate func skeletonPulse() -> some View {
        modifier(SkeletonPulseModifier())
    }
}
