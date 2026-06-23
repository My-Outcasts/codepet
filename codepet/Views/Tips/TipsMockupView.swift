import SwiftUI

// MOCKUP — no function, all data hardcoded.
// Reuses ReflectionTheme tokens (accent, fonts, PetAvatar, Eyebrow) for visual consistency.

struct TipsMockupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.uiLanguage) private var uiLanguage

    private var petName: String {
        PetCharacter.all[appState.activeChar]?.name ?? ReflectionPet.name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                heroInsight
                setupSection
                skillsSection
                readingSection
                petNote
                footer
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ReflectionTheme.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            PetAvatar(mood: .calm, size: 96)

            VStack(alignment: .leading, spacing: 6) {
                Text(petName)
                    .font(ReflectionTheme.serif(28, weight: .medium))
                    .foregroundColor(ReflectionTheme.primaryText)

                Text(uiLanguage == .vi ? "Mẹo agentic coding của bạn" : "Your agentic coding tips")
                    .font(ReflectionTheme.sans(13))
                    .foregroundColor(ReflectionTheme.mutedText)
            }

            Spacer()

            progressRing
        }
    }

    private var progressRing: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(ReflectionTheme.borderLight, lineWidth: 4)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: 7.0 / 15.0)
                    .stroke(ReflectionTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                Text("7")
                    .font(ReflectionTheme.serif(16, weight: .medium))
                    .foregroundColor(ReflectionTheme.primaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(uiLanguage == .vi ? "trên 15" : "of 15")
                    .font(ReflectionTheme.sans(11))
                    .foregroundColor(ReflectionTheme.mutedText)
                Text(uiLanguage == .vi ? "kỹ năng đã thành thạo" : "skills mastered")
                    .font(ReflectionTheme.sans(11, weight: .semibold))
                    .foregroundColor(ReflectionTheme.primaryText)
            }
        }
    }

    // MARK: - Hero insight card

    private var heroInsight: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: uiLanguage == .vi ? "Gợi ý hôm nay" : "Today's guidance")

            HStack(alignment: .top, spacing: 14) {
                Rectangle()
                    .fill(ReflectionTheme.accent)
                    .frame(width: 3)
                    .cornerRadius(1.5)

                VStack(alignment: .leading, spacing: 12) {
                    Text(PersonaContent.resolvePerPetL10n(
                            PersonaContent.tipGuidanceHeadlineByPet,
                            petId: appState.activeChar,
                            personaFallback: PersonaContent.tipGuidanceHeadline,
                            persona: appState.languagePersona,
                            language: uiLanguage,
                            fallback: uiLanguage == .vi ? "Chế độ Plan đã sẵn sàng khi bạn cần." : "Plan mode is ready when you are."
                        ))
                        .font(ReflectionTheme.serif(22, weight: .medium))
                        .foregroundColor(ReflectionTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(PersonaContent.tipGuidanceBody?.value(for: appState.languagePersona, language: uiLanguage)
                         ?? (uiLanguage == .vi
                             ? "Tuần này bạn ghi nhận 3 lần thêm scope. Plan mode làm scope hiện rõ trước khi bạn bắt đầu — để bạn cắt thật lòng, trước khi code được viết."
                             : "You've captured 3 scope additions this week. Plan mode makes the scope visible before you start — so you can cut things honestly, before code is written."))
                        .font(ReflectionTheme.serif(15))
                        .foregroundColor(ReflectionTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        pillButton(label: uiLanguage == .vi ? "Dạy tôi →" : "Teach me →", primary: true)
                        pillButton(label: uiLanguage == .vi ? "Để sau" : "Not now", primary: false)
                    }
                }
            }
            .padding(22)
            .pixelBox(fill: ReflectionTheme.cardBackground)
        }
    }

    // MARK: - Setup section

    private let defaultSetupItems: [TipSetupItem] = [
        TipSetupItem(
            title: L10n(vi: "Claude Code", en: "Claude Code"),
            status: L10n(vi: "Đã cài · v2.1.4", en: "Installed · v2.1.4"),
            state: .done, actionLabel: nil
        ),
        TipSetupItem(
            title: L10n(vi: "Server MCP CodePet", en: "CodePet MCP server"),
            status: L10n(vi: "Đã kết nối · 2h trước", en: "Connected · 2h ago"),
            state: .done, actionLabel: nil
        ),
        TipSetupItem(
            title: L10n(vi: "Plugin Superpowers", en: "Superpowers plugin"),
            status: L10n(vi: "Chưa cài — thêm hệ thống skill cho Claude", en: "Not installed — adds skill system for Claude"),
            state: .warning, actionLabel: L10n(vi: "Cài đặt", en: "Install")
        ),
        TipSetupItem(
            title: L10n(vi: "CLAUDE.md của dự án", en: "Project CLAUDE.md"),
            status: L10n(vi: "Trống — chưa có hướng dẫn dự án", en: "Empty — no project instructions yet"),
            state: .missing, actionLabel: L10n(vi: "Viết template", en: "Write template")
        )
    ]

    /// Pet-specialized setup section. Falls back to default items if the
    /// active pet has no entry.
    private var setupItems: [TipSetupItem] {
        TipsContent.tipSetupByPet[appState.activeChar] ?? defaultSetupItems
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: uiLanguage == .vi ? "Cài đặt của bạn" : "Your setup")

            VStack(spacing: 0) {
                ForEach(Array(setupItems.enumerated()), id: \.offset) { index, item in
                    setupRow(item)
                    if index < setupItems.count - 1 {
                        Rectangle()
                            .fill(ReflectionTheme.borderLight)
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                    }
                }
            }
            .pixelBox(fill: ReflectionTheme.cardBackground)
        }
    }

    private func setupRow(_ item: TipSetupItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: item.state.icon)
                .font(.pixelSystem(size: 16, weight: .medium))
                .foregroundColor(item.state.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title(uiLanguage))
                    .font(ReflectionTheme.sans(13, weight: .semibold))
                    .foregroundColor(ReflectionTheme.primaryText)
                Text(item.status(uiLanguage))
                    .font(ReflectionTheme.sans(11))
                    .foregroundColor(ReflectionTheme.mutedText)
            }

            Spacer()

            if let action = item.actionLabel {
                HStack(spacing: 4) {
                    Text(action(uiLanguage))
                        .font(ReflectionTheme.sans(11, weight: .semibold))
                        .foregroundColor(ReflectionTheme.accent)
                    Image(systemName: "arrow.right")
                        .font(.pixelSystem(size: 9, weight: .semibold))
                        .foregroundColor(ReflectionTheme.accent)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    // MARK: - Skills grid

    private struct SkillTile {
        let icon: String
        let title: String
        let hint: String
        let practiced: Int   // 0-5 filled dots
        let total: Int
    }

    private func defaultSkills(_ lang: AppLanguage) -> [SkillTile] {
        [
            SkillTile(
                icon: "list.bullet.rectangle",
                title: lang == .vi ? "Lập kế hoạch trước khi prompt" : "Plan before prompting",
                hint: lang == .vi ? "Phác thảo ý định trước khi nhờ AI viết code." : "Outline intent before asking AI to code.",
                practiced: 3, total: 5
            ),
            SkillTile(
                icon: "doc.text",
                title: lang == .vi ? "Viết CLAUDE.md" : "Write CLAUDE.md",
                hint: lang == .vi ? "Bối cảnh dự án bền vững cho mỗi session." : "Persistent project context for every session.",
                practiced: 1, total: 5
            ),
            SkillTile(
                icon: "xmark.circle",
                title: lang == .vi ? "Từ chối gợi ý" : "Reject the suggestion",
                hint: lang == .vi ? "Nói không khi câu trả lời của AI không khớp ý định." : "Say no when AI's answer doesn't fit intent.",
                practiced: 4, total: 5
            ),
            SkillTile(
                icon: "checkmark.shield",
                title: lang == .vi ? "Kiểm tra trước khi ship" : "Test before shipping",
                hint: lang == .vi ? "Xác minh đầu ra của AI — đừng tin, hãy kiểm tra." : "Verify AI output — don't trust, verify.",
                practiced: 2, total: 5
            )
        ]
    }

    /// Resolve the 4 skill tiles for the active pet's domain. Falls back to
    /// the default set if the pet has no entry in `TipsContent.tipSkillsByPet`.
    private var skills: [SkillTile] {
        guard let petTiles = TipsContent.tipSkillsByPet[appState.activeChar] else {
            return defaultSkills(uiLanguage)
        }
        return petTiles.enumerated().map { index, tile in
            SkillTile(
                icon: tile.icon,
                title: tile.title(uiLanguage),
                hint: tile.hint(uiLanguage),
                practiced: [3, 1, 4, 2][index % 4],   // mock progress, varied
                total: 5
            )
        }
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: uiLanguage == .vi ? "Kỹ năng agentic coding" : "Agentic coding skills")
                Spacer()
                Text(uiLanguage == .vi ? "Hiển thị 4 / 15" : "4 of 15 shown")
                    .font(ReflectionTheme.sans(10))
                    .foregroundColor(ReflectionTheme.mutedText)
                Text("·")
                    .foregroundColor(ReflectionTheme.mutedText)
                Text(uiLanguage == .vi ? "Xem tất cả" : "See all")
                    .font(ReflectionTheme.sans(10, weight: .semibold))
                    .foregroundColor(ReflectionTheme.accent)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in
                    skillTile(skill)
                }
            }
        }
    }

    private func skillTile(_ skill: SkillTile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: skill.icon)
                    .font(.pixelSystem(size: 16, weight: .medium))
                    .foregroundColor(ReflectionTheme.accent)
                Spacer()
                Text("\(skill.practiced)/\(skill.total)")
                    .font(ReflectionTheme.mono(10))
                    .foregroundColor(ReflectionTheme.mutedText)
            }

            Text(skill.title)
                .font(ReflectionTheme.serif(15, weight: .medium))
                .foregroundColor(ReflectionTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(skill.hint)
                .font(ReflectionTheme.sans(11))
                .foregroundColor(ReflectionTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 3) {
                ForEach(0..<skill.total, id: \.self) { index in
                    Circle()
                        .fill(index < skill.practiced ? ReflectionTheme.accent : ReflectionTheme.borderLight)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .pixelBox(fill: ReflectionTheme.cardBackground)
    }

    // MARK: - Reading section

    private let defaultReadings: [TipReadingItem] = [
        TipReadingItem(
            title: L10n(vi: "The Pragmatic Programmer", en: "The Pragmatic Programmer"),
            author: "Hunt & Thomas",
            kind: L10n(vi: "Sách · 384 trang", en: "Book · 384 pages"),
            why: L10n(
                vi: "Chương 8 về sự đa nghi thực dụng giúp bạn từ chối những câu trả lời quá tự tin của AI. Tư duy nền tảng của agentic coding.",
                en: "Ch. 8 on pragmatic paranoia helps you reject AI's over-confident answers. Foundational agentic-coding mindset."
            )
        ),
        TipReadingItem(
            title: L10n(vi: "Spec-first programming", en: "Spec-first programming"),
            author: "Thoughtbot",
            kind: L10n(vi: "Bài luận · 12 phút", en: "Essay · 12 min"),
            why: L10n(
                vi: "Khớp với cách CodePet theo dõi ý định trước khi ra kết quả. Ngắn, áp dụng được ngay, hữu ích tức thì.",
                en: "Matches how CodePet tracks intent before output. Short, actionable, immediately useful."
            )
        )
    ]

    /// Pet-specialized reading list. Falls back to default if pet has no entry.
    private var readings: [TipReadingItem] {
        TipsContent.tipReadingPool[appState.activeChar] ?? defaultReadings
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: uiLanguage == .vi ? "Sách nên đọc" : "Recommended reading")

            VStack(spacing: 12) {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, item in
                    readingCard(item)
                }
            }
        }
    }

    private func readingCard(_ item: TipReadingItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.pixelSystem(size: 22))
                .foregroundColor(ReflectionTheme.accent)
                .frame(width: 40, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(ReflectionTheme.accent.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title(uiLanguage))
                    .font(ReflectionTheme.serif(16, weight: .medium))
                    .foregroundColor(ReflectionTheme.primaryText)

                Text("\(item.author) · \(item.kind(uiLanguage))")
                    .font(ReflectionTheme.sans(11))
                    .foregroundColor(ReflectionTheme.mutedText)

                Text(item.why(uiLanguage))
                    .font(ReflectionTheme.serif(13))
                    .foregroundColor(ReflectionTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                pillButton(label: uiLanguage == .vi ? "Đưa cho Claude" : "Feed to Claude", primary: true)
                pillButton(label: uiLanguage == .vi ? "Mở" : "Open", primary: false)
            }
            .fixedSize()
        }
        .padding(18)
        .pixelBox(fill: ReflectionTheme.cardBackground)
    }

    // MARK: - Pet's note

    private var petNoteText: String {
        if let note = TipsContent.tipPetNoteByPet[appState.activeChar] {
            return note(uiLanguage)
        }
        return uiLanguage == .vi
            ? "Tôi để ý tuần này bạn bỏ qua bước kiểm tra hai lần. Tôi không phán xét — chỉ giữ một tấm gương. Ngủ ngon. Mai mình quay lại."
            : "I noticed you skipped validation twice this week. I'm not judging — just holding a mirror. Sleep well. We'll pick it up tomorrow."
    }

    private var petNote: some View {
        HStack(alignment: .top, spacing: 14) {
            PetAvatar(mood: .calm, size: 64)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: uiLanguage == .vi ? "Lời nhắn từ \(petName)" : "A note from \(petName)")
                Text("“\(petNoteText)”")
                    .font(ReflectionTheme.serif(15))
                    .italic()
                    .foregroundColor(ReflectionTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .pixelBox(fill: ReflectionTheme.cardBackground)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Eyebrow(text: uiLanguage == .vi
                    ? "Mẹo CodePet · v1.0 · đồng hành cùng bạn, không áp đặt bạn."
                    : "CodePet tips · v1.0 · held for you, not over you.")
            Spacer()
        }
        .padding(.top, 12)
    }

    // MARK: - Helpers

    private func pillButton(label: String, primary: Bool) -> some View {
        Button(action: {}) {
            Text(label)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(PixelButtonStyle(
            fill: primary ? ReflectionTheme.accent : ReflectionTheme.borderLight.opacity(0.5),
            foreground: primary ? .white : ReflectionTheme.secondaryText,
            paddingH: 12,
            paddingV: 6,
            blockSize: 2,
            steps: 2,
            borderWidth: 2,
            shadowOffset: 2,
            font: .pixelSystem(size: 11, weight: primary ? .semibold : .medium)
        ))
    }
}

// View-layer mapping of TipSetupState → color (depends on ReflectionTheme).
extension TipSetupState {
    var color: Color {
        switch self {
        case .done:    return ReflectionTheme.moodCalm
        case .warning: return ReflectionTheme.moodAlert
        case .missing: return ReflectionTheme.mutedText
        }
    }
}

#Preview {
    TipsMockupView()
        .frame(width: 900, height: 900)
}
