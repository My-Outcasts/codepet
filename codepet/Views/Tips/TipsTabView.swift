import SwiftUI
import AppKit

/// The live Tips tab — replaces TipsMockupView.
/// Reads real skill progress from TipsState, fetches daily AI guidance
/// via GuidanceEnricher, and renders per-pet content from TipsContent.
struct TipsTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var tipsState: TipsState
    @EnvironmentObject var narrativeStore: NarrativeStore
    @EnvironmentObject var projectStore: ProjectStore
    @Environment(\.uiLanguage) private var uiLanguage

    /// Owned by this view — created once with a fresh API client.
    @StateObject private var guidanceEnricher = GuidanceEnricher(api: ReflectionAPIClient())

    /// Scans project files for business/growth signals (payment SDKs, analytics,
    /// SEO files). Cached per path; feeds auto-detection in `healthReports`.
    @StateObject private var projectScanner = ProjectScanner()

    /// Generates per-section action plans for Project Health checks.
    @StateObject private var planEnricher = PlanEnricher(api: ReflectionAPIClient())

    // Learn section navigation

    private var petName: String {
        PetCharacter.all[appState.activeChar]?.name ?? ReflectionPet.name
    }

    /// The active pet's accent color, used to theme the note box.
    private var petColor: Color {
        PetCharacter.all[appState.activeChar]?.color ?? ReflectionTheme.accent
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                // HIDDEN (2026-06-15): daily AI "Your focus today" guidance card.
                // Hidden until it proves user value. Restore by un-commenting this
                // block AND the `.task` fetch below.
                // GuidanceCardView(onRetry: {
                //     Task {
                //         let memory = PetMemoryStore.shared.allMemoryPrompt()
                //         await guidanceEnricher.fetchIfNeeded(
                //             tipsState: tipsState,
                //             narrativeStore: narrativeStore,
                //             appState: appState,
                //             petMemory: memory,
                //             projectStore: projectStore
                //         )
                //     }
                // })
                projectFoldersSection
                skillsSection
                    .id(Self.skillsAnchor)
                petNote
                footer
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ReflectionTheme.background)
        .onAppear {
            projectScanner.refresh(projects: Array(projectStore.projects.values))
            consumePendingScroll(proxy)
        }
        .onChange(of: projectStore.projects.count) { _ in
            projectScanner.refresh(projects: Array(projectStore.projects.values))
        }
        .onChange(of: appState.pendingScrollToSkills) { _ in
            consumePendingScroll(proxy)
        }
        }
        // HIDDEN (2026-06-15): daily AI guidance fetch. Disabled while the
        // GuidanceCardView above is hidden, so we don't spend a daily AI request
        // generating guidance nobody sees. Restore alongside the card.
        // .task {
        //     // Pass aggregated pet memory for richer AI guidance context.
        //     // A new app build forces a fresh fetch (replaces the manual reload),
        //     // otherwise the normal once-per-day cache applies.
        //     let memory = PetMemoryStore.shared.allMemoryPrompt()
        //     let isNewBuild = currentBuildSignature != lastBuildSignature
        //     await guidanceEnricher.fetchIfNeeded(
        //         tipsState: tipsState,
        //         narrativeStore: narrativeStore,
        //         appState: appState,
        //         petMemory: memory,
        //         projectStore: projectStore,
        //         force: isNewBuild
        //     )
        //     // Only mark this build as seen once we actually have fresh guidance,
        //     // so a failed/empty fetch retries on the next visit.
        //     if isNewBuild, tipsState.currentGuidance?.isFresh == true {
        //         lastBuildSignature = currentBuildSignature
        //     }
        // }
    }

    // MARK: - Build-change detection

    /// Persisted signature of the build that last refreshed guidance.
    @AppStorage("cp_tips_lastBuildSig") private var lastBuildSignature: String = ""

    /// A signature that changes on every new build. The app executable's
    /// modification date is rewritten on each compile/link, so it's a reliable
    /// "new build" marker without manually bumping the version number.
    private var currentBuildSignature: String {
        if let url = Bundle.main.executableURL,
           let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            return String(Int(date.timeIntervalSince1970))
        }
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
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
        let mastered = tipsState.masteredCount(for: appState.activeChar)
        let total = tipsState.totalSkillsPerPet
        let fraction = total > 0 ? CGFloat(mastered) / CGFloat(total) : 0

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(ReflectionTheme.borderLight, lineWidth: 4)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(ReflectionTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
                Text("\(mastered)")
                    .font(ReflectionTheme.serif(16, weight: .medium))
                    .foregroundColor(ReflectionTheme.primaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(uiLanguage == .vi ? "trên \(total)" : "of \(total)")
                    .font(ReflectionTheme.sans(11))
                    .foregroundColor(ReflectionTheme.mutedText)
                Text(uiLanguage == .vi ? "kỹ năng đã thành thạo" : "skills mastered")
                    .font(ReflectionTheme.sans(11, weight: .semibold))
                    .foregroundColor(ReflectionTheme.primaryText)
            }
        }
    }

    // ── Project folders (unified health + reading per project) ────────

    private var healthReports: [ProjectHealthReport] {
        projectStore.projects.values
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
            .map { ProjectHealthEngine.evaluate(project: $0, scan: projectScanner.results[$0.id]) }
    }

    private var projectFoldersSection: some View {
        ProjectFoldersView(
            projects: projectStore.projects,
            readingGroups: readingGroups,
            healthReports: healthReports,
            uiLanguage: uiLanguage,
            orderedProjectPaths: projectStore.reflectionProjectOrder,
            syncedProjectPath: projectStore.activeProjectPath,
            onFeedToClaude: { item, projectName in
                let title = item.title(uiLanguage)
                let prompt: String
                if let proj = projectName {
                    prompt = uiLanguage == .vi
                        ? "Dựa trên \"\(title)\" của \(item.author), đưa cho mình 3 thay đổi cụ thể nên áp dụng cho dự án \(proj). Thực tế, áp dụng được ngay — đừng tóm tắt sách."
                        : "Based on \"\(title)\" by \(item.author), give me 3 specific changes to make to my \(proj) project. Concrete and actionable — not a book summary."
                } else {
                    prompt = uiLanguage == .vi
                        ? "Đưa cho mình 3 ý chính áp dụng được ngay từ \"\(title)\" của \(item.author)."
                        : "Give me 3 specific, actionable takeaways I can apply right now from \"\(title)\" by \(item.author)."
                }
                appState.pendingChatPrompt = prompt
                appState.selectedTab = .reflection
            },
            onOpenURL: { NSWorkspace.shared.open($0) },
            onSetStage: { projectId, stage in
                projectStore.setStage(projectId: projectId, stage: stage)
            },
            onToggleAttestation: { projectId, ruleId in
                projectStore.toggleAttestation(projectId: projectId, ruleId: ruleId)
            },
            planEnricher: planEnricher
        )
    }

    // MARK: - Skills grid

    /// Scroll anchor id for the "Agentic coding skills" section, so the Profile
    /// exercises card can deep-link straight to it.
    static let skillsAnchor = "agenticSkills"

    /// Consume a deep link from the Profile exercises card: scroll to the skills
    /// section, then reset the flag. A short delay lets the project-folders
    /// section above settle so the target lands at the top accurately.
    private func consumePendingScroll(_ proxy: ScrollViewProxy) {
        guard appState.pendingScrollToSkills else { return }
        appState.pendingScrollToSkills = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(Self.skillsAnchor, anchor: .top)
            }
        }
    }

    private var petSkillTiles: [TipSkillTile]? {
        TipsContent.tipSkillsByPet[appState.activeChar]
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: uiLanguage == .vi ? "Kỹ năng agentic coding" : "Agentic coding skills")
                Spacer()
                let mastered = tipsState.masteredCount(for: appState.activeChar)
                Text(uiLanguage == .vi
                     ? "\(mastered) / \(tipsState.totalSkillsPerPet) đã thành thạo"
                     : "\(mastered) of \(tipsState.totalSkillsPerPet) mastered")
                    .font(ReflectionTheme.sans(10))
                    .foregroundColor(ReflectionTheme.mutedText)
            }

            if let tiles = petSkillTiles {
                LazyVGrid(
                    columns: [GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        SkillTileView(
                            petId: appState.activeChar,
                            index: index,
                            tile: tile,
                            onStartChallenge: { challenge in
                                // Open the large practice-workspace modal (MainTabView)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appState.activeExercise = challenge
                                }
                            }
                        )
                    }
                }
            } else {
                // Fallback: pet has no skill tiles defined
                Text(uiLanguage == .vi
                     ? "Kỹ năng cho pet này sẽ sớm được thêm."
                     : "Skills for this pet coming soon.")
                    .font(ReflectionTheme.sans(13))
                    .foregroundColor(ReflectionTheme.mutedText)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pixelBox(fill: ReflectionTheme.cardBackground)
            }
        }
    }

    // MARK: - Reading groups (used by ProjectFoldersView)

    private var readingGroups: [ReadingMatcher.ProjectReadingGroup] {
        ReadingMatcher.match(
            petId: appState.activeChar,
            projects: projectStore.projects
        )
    }

    // MARK: - Pet's note

    private var petNoteText: String {
        if let note = TipsContent.tipPetNoteByPet[appState.activeChar] {
            return note(uiLanguage)
        }
        return uiLanguage == .vi
            ? "Tôi để ý tuần này bạn bỏ qua bước kiểm tra hai lần. Tôi không phán xét — chỉ giữ một tấm gương."
            : "I noticed you skipped validation twice this week. I'm not judging — just holding a mirror."
    }

    private var petNote: some View {
        HStack(alignment: .top, spacing: 14) {
            PetAvatar(mood: .calm, size: 64)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: uiLanguage == .vi ? "Lời nhắn từ \(petName)" : "A note from \(petName)")
                Text("\u{201C}\(petNoteText.emDashesAsCommas)\u{201D}")
                    .font(ReflectionTheme.serif(15))
                    .italic()
                    .foregroundColor(ReflectionTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        // Themed to the active pet: a light tint of its color behind a border in
        // the same hue (the canonical info-box look).
        .pixelBox(fill: petColor.opacity(0.12), borderColor: petColor,
                  shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
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

}
