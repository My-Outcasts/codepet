import SwiftUI

/// Detail sheet for a skill challenge — shows full description,
/// acceptance criteria, difficulty, and a button to start coding.
struct ChallengeDetailView: View {
    let challenge: SkillChallenge
    let skillColor: Color
    let isCompleted: Bool
    var onStartCoding: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiLanguage) private var uiLanguage

    private let dark = Color(hex: "#2D2B26")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ──
            ZStack {
                skillColor

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 80, height: 80)
                    .offset(x: -60, y: -20)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        difficultyBadge

                        Text(challenge.title)
                            .font(CodepetTheme.body(20, weight: .bold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .frame(height: 100)

            // ── Body ──
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // What to do
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel(uiLanguage == .vi ? "BÀI TẬP" : "THE EXERCISE")

                        Text(challenge.description)
                            .font(.pixelSystem(size: 14))
                            .foregroundColor(dark)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // How the AI verifies
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel(uiLanguage == .vi ? "HOÀN THÀNH KHI" : "DONE WHEN")

                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(skillColor)
                                .padding(.top, 2)

                            Text(challenge.acceptanceCriteria)
                                .font(.pixelSystem(size: 13))
                                .foregroundColor(dark.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(skillColor.opacity(0.08))
                        )
                    }

                    // How it works
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel(uiLanguage == .vi ? "CÁCH HOẠT ĐỘNG" : "HOW IT WORKS")

                        VStack(alignment: .leading, spacing: 10) {
                            stepRow(number: "1", text: uiLanguage == .vi
                                   ? "Nhấn nút bên dưới để mở Claude Code với prompt sẵn"
                                   : "Tap the button below to open Claude Code with a ready prompt")
                            stepRow(number: "2", text: uiLanguage == .vi
                                   ? "Claude Code sẽ thực hiện thay đổi cho dự án của bạn"
                                   : "Claude Code will make the changes to your project")
                            stepRow(number: "3", text: uiLanguage == .vi
                                   ? "Codepet tự động phát hiện và đánh dấu bài tập hoàn thành"
                                   : "Codepet auto-detects the work and marks the exercise complete")
                        }
                    }

                    // Status
                    if isCompleted {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "#029902"))
                            Text(uiLanguage == .vi ? "Bài tập đã hoàn thành!" : "Exercise completed!")
                                .font(.pixelSystem(size: 14, weight: .bold))
                                .foregroundColor(Color(hex: "#029902"))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "#029902").opacity(0.08))
                        )
                    }

                    Spacer(minLength: 20)

                    // Start coding button
                    if !isCompleted {
                        Button(action: {
                            onStartCoding()
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text(uiLanguage == .vi ? "Bắt đầu với Claude Code" : "Start in Claude Code")
                                    .font(.pixelSystem(size: 14, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            // Match the app's canonical pixel button (blockSize 2,
                            // steps 1, 2px border + 2px shadow) instead of the
                            // heavier 3px chrome.
                            .background(
                                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                    .fill(skillColor)
                            )
                            .overlay(
                                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                    .stroke(dark, lineWidth: 2)
                            )
                            .background(
                                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                                    .fill(dark)
                                    .offset(x: 2, y: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 450, minHeight: 500)
        .background(Color(hex: "#FDFCFF"))
    }

    // MARK: - Components

    private var difficultyBadge: some View {
        let (label, color): (String, Color) = {
            switch challenge.difficulty {
            case .starter:  return (uiLanguage == .vi ? "Khởi đầu" : "Starter", Color(hex: "#029902"))
            case .practice: return (uiLanguage == .vi ? "Luyện tập" : "Practice", Color(hex: "#D49700"))
            case .stretch:  return (uiLanguage == .vi ? "Thử thách" : "Stretch", Color(hex: "#E24B4A"))
            case .expert:   return (uiLanguage == .vi ? "Chuyên gia" : "Expert", Color(hex: "#7B3FE4"))
            }
        }()

        return Text(label)
            .font(.pixelSystem(size: 10, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                    .fill(Color.white)
            )
            .overlay(
                PixelStaircaseRectangle(blockSize: 2, steps: 1)
                    .stroke(dark, lineWidth: 1.5)
            )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.pixelSystem(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundColor(dark.opacity(0.4))
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.pixelSystem(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(skillColor)
                )

            Text(text)
                .font(.pixelSystem(size: 12))
                .foregroundColor(dark.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
