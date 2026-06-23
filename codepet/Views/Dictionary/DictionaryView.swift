import SwiftUI

struct DictionaryView: View {

    @Environment(\.uiLanguage) private var uiLanguage
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var feedbackManager: FeatureFeedbackManager

    // Live, project-aware dictionary (terms detected in the user's real code).
    @EnvironmentObject private var dictionaryStore: ProjectDictionaryStore
    @EnvironmentObject private var dictionaryEnricher: DictionaryEnricher
    @EnvironmentObject private var eventStore: ReflectionEventStore

    /// The active surface. `nil` → resolve a default lazily (project terms if any
    /// exist, otherwise the static "Coding Basics" reference).
    @State private var surface: DictSurface?
    @State private var searchQuery: String = ""
    @State private var expandedTermIds: Set<String> = []
    @State private var showProjectPanel: Bool = true
    /// Term id to scroll to once the list rebuilds — set by a deep link from a
    /// tapped glossary term in the Reflection narrative.
    @State private var scrollTarget: String?

    /// When true the static dictionary is shown as a plain, universal reference:
    /// the project panel (Surface B) and per-card "Used in …" badges (Surface A)
    /// are hidden. Only affects the Coding Basics surface. Persisted.
    @AppStorage("cp_dictionaryDetached") private var detached: Bool = false

    /// Which dictionary surface the sidebar is pointing at.
    enum DictSurface: Hashable {
        case projectAll               // every live term
        case projectTopic(String)     // live terms in one server topic
        case basics(String)           // a static `DictionaryContent` topic id
    }

    // MARK: - Live topic metadata (server topics → sidebar styling)

    private struct LiveTopicMeta { let title: L10n; let icon: String; let accent: DiagramAccent }
    private static let liveTopicOrder = ["frameworks", "patterns", "tools", "language", "web", "concepts"]
    private static let liveTopicMeta: [String: LiveTopicMeta] = [
        "frameworks": .init(title: L10n(vi: "Framework", en: "Frameworks"), icon: "square.stack.3d.up.fill", accent: .blue),
        "patterns":   .init(title: L10n(vi: "Mẫu hình",  en: "Patterns"),   icon: "arrow.triangle.branch",   accent: .pink),
        "tools":      .init(title: L10n(vi: "Công cụ",   en: "Tools"),      icon: "wrench.and.screwdriver.fill", accent: .gold),
        "language":   .init(title: L10n(vi: "Ngôn ngữ",  en: "Language"),   icon: "curlybraces",             accent: .purple),
        "web":        .init(title: L10n(vi: "Web",       en: "Web"),        icon: "globe",                   accent: .teal),
        "concepts":   .init(title: L10n(vi: "Khái niệm", en: "Concepts"),   icon: "lightbulb.fill",          accent: .orange),
    ]

    // MARK: - Surface resolution

    private var effectiveSurface: DictSurface {
        // "From your code" (project-aware) surface removed from the app — the
        // Dictionary now shows only the static Coding Basics reference.
        if case let .basics(id)? = surface { return .basics(id) }
        return .basics(DictionaryContent.topics.first!.id)
    }

    private var isLive: Bool {
        switch effectiveSurface {
        case .projectAll, .projectTopic: return true
        case .basics: return false
        }
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Live data

    /// Server topics that actually have at least one detected term, in canonical
    /// order — the dynamic "From your code" groups.
    private var liveTopicsPresent: [String] {
        let present = Set(dictionaryStore.sortedEntries.map { $0.topic.lowercased() })
        return Self.liveTopicOrder.filter { present.contains($0) }
    }

    private func liveEntries(forTopic key: String) -> [DictionaryEntry] {
        dictionaryStore.sortedEntries.filter { $0.topic.lowercased() == key }
    }

    /// The live entries currently visible: scoped to the selected topic (or all)
    /// and filtered by the search query.
    private var liveVisibleEntries: [DictionaryEntry] {
        let base: [DictionaryEntry]
        switch effectiveSurface {
        case .projectTopic(let key): base = liveEntries(forTopic: key)
        default:                     base = dictionaryStore.sortedEntries
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.term.lowercased().contains(q)
                || $0.title.lowercased().contains(q)
                || $0.cardDefinition.lowercased().contains(q)
        }
    }

    private func liveAccent(_ key: String) -> Color {
        (Self.liveTopicMeta[key.lowercased()]?.accent ?? .purple).color
    }

    // MARK: - Static data (Coding Basics surface)

    private var selectedTopicId: String {
        if case .basics(let id) = effectiveSurface { return id }
        return DictionaryContent.topics.first!.id
    }

    private var visibleTerms: [DictionaryTerm] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return DictionaryContent.terms(in: selectedTopicId)
        }
        return DictionaryContent.search(trimmed)
    }

    /// The most-recent project's matched terms + inferred stack (static surface).
    private var projectGroup: DictionaryMatcher.ProjectTermGroup? {
        DictionaryMatcher.match(projects: projectStore.projects)
    }

    private var effectiveGroup: DictionaryMatcher.ProjectTermGroup? {
        detached ? nil : projectGroup
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
                .frame(width: 220)

            Rectangle()
                .fill(CodepetTheme.hairline)
                .frame(width: 1)

            contentPane
                .frame(maxWidth: .infinity)
        }
        .background(CodepetTheme.pageBackground)
        .onAppear { consumePendingTerm() }
        .onChange(of: appState.pendingDictionaryTerm) { _, _ in consumePendingTerm() }
    }

    private func refreshLive() async {
        await dictionaryEnricher.refresh(
            store: dictionaryStore,
            eventStore: eventStore,
            projectStore: projectStore,
            appState: appState
        )
    }

    /// Consume a deep link set by tapping a glossary term in a narrative. These
    /// always point at static reference terms, so they switch to Coding Basics.
    private func consumePendingTerm() {
        guard let id = appState.pendingDictionaryTerm else { return }
        openTerm(id)
        appState.pendingDictionaryTerm = nil
    }

    private func openTerm(_ id: String) {
        guard let term = DictionaryContent.terms.first(where: { $0.id == id }) else { return }
        searchQuery = ""
        surface = .basics(term.topicId)
        expandedTermIds.insert(id)
        scrollTarget = id
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(uiLanguage == .vi ? "TỪ ĐIỂN" : "DICTIONARY")
                .font(CodepetTheme.body(11, weight: .bold))
                .tracking(1.2)
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    basicsSection
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: Sidebar — "From your code" (live)

    @ViewBuilder
    private var liveSection: some View {
        sectionHeader(uiLanguage == .vi ? "TỪ CODE CỦA BẠN" : "FROM YOUR CODE")

        liveAllRow

        ForEach(liveTopicsPresent, id: \.self) { key in
            liveTopicRow(key)
        }
    }

    private var liveAllRow: some View {
        let count = dictionaryStore.entries.count
        let selected: Bool = { if case .projectAll = effectiveSurface { return !isSearching }; return false }()
        let accent = CodepetTheme.accentPurple
        return Button {
            surface = .projectAll
            searchQuery = ""
            feedbackManager.requestIfFirstTime(.dictionary)
        } label: {
            sidebarRowLabel(icon: "sparkles",
                            title: uiLanguage == .vi ? "Tất cả" : "All",
                            count: count, accent: accent, selected: selected)
        }
        .buttonStyle(.plain)
    }

    private func liveTopicRow(_ key: String) -> some View {
        let meta = Self.liveTopicMeta[key]
        let accent = (meta?.accent ?? .purple).color
        let count = liveEntries(forTopic: key).count
        let selected: Bool = { if case .projectTopic(let k) = effectiveSurface { return k == key && !isSearching }; return false }()
        return Button {
            surface = .projectTopic(key)
            searchQuery = ""
            feedbackManager.requestIfFirstTime(.dictionary)
        } label: {
            sidebarRowLabel(icon: meta?.icon ?? "circle.fill",
                            title: meta?.title(uiLanguage) ?? key.capitalized,
                            count: count, accent: accent, selected: selected)
        }
        .buttonStyle(.plain)
    }

    // MARK: Sidebar — "Coding Basics" (static)

    @ViewBuilder
    private var basicsSection: some View {
        sectionHeader(uiLanguage == .vi ? "KIẾN THỨC NỀN" : "CODING BASICS")
            .padding(.top, 8)

        ForEach(DictionaryContent.topics) { topic in
            basicsTopicRow(topic)
        }
    }

    private func basicsTopicRow(_ topic: DictionaryTopic) -> some View {
        let accent = topic.accent.color
        let count = DictionaryContent.terms(in: topic.id).count
        let selected: Bool = { if case .basics(let id) = effectiveSurface { return id == topic.id && !isSearching }; return false }()
        return Button {
            surface = .basics(topic.id)
            searchQuery = ""
            feedbackManager.requestIfFirstTime(.dictionary)
        } label: {
            sidebarRowLabel(icon: topic.icon, title: topic.title(uiLanguage),
                            count: count, accent: accent, selected: selected)
        }
        .buttonStyle(.plain)
    }

    // MARK: Sidebar — shared row chrome

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.pixelSystem(size: 9, weight: .semibold))
            .tracking(1.0)
            .foregroundColor(CodepetTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarRowLabel(icon: String, title: String, count: Int, accent: Color, selected: Bool) -> some View {
        HStack(spacing: 10) {
            sidebarIcon(icon, accent: accent, selected: selected)
            Text(title)
                .font(CodepetTheme.body(13, weight: .semibold))
                .foregroundColor(selected ? .white : CodepetTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            countBadge(count, accent: accent, selected: selected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? accent : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func sidebarIcon(_ name: String, accent: Color, selected: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(selected ? .white : accent)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.22) : accent.opacity(0.16))
            )
    }

    private func countBadge(_ count: Int, accent: Color, selected: Bool) -> some View {
        Text("\(count)")
            .font(.pixelSystem(size: 10, weight: .semibold))
            .foregroundColor(selected ? .white : accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(selected ? Color.white.opacity(0.22) : accent.opacity(0.12))
            )
    }

    // MARK: - Content pane

    @ViewBuilder
    private var contentPane: some View {
        if isLive {
            liveContentPane
        } else {
            staticContentPane
        }
    }

    // MARK: Content — live surface

    private var liveContentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            liveHeader
            Divider().background(CodepetTheme.hairline)
            liveCardList
        }
    }

    private var liveAccentForHeader: Color {
        if case .projectTopic(let key) = effectiveSurface { return liveAccent(key) }
        return CodepetTheme.accentPurple
    }

    private var liveHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            liveHeroBanner
            searchField
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var liveHeroBanner: some View {
        let accent = liveAccentForHeader
        let isTopic: String? = { if case .projectTopic(let k) = effectiveSurface { return k }; return nil }()
        let icon = isTopic.flatMap { Self.liveTopicMeta[$0]?.icon } ?? "sparkles"
        let title: String = {
            if let k = isTopic { return Self.liveTopicMeta[k]?.title(uiLanguage) ?? k.capitalized }
            return uiLanguage == .vi ? "Từ code của bạn" : "From your code"
        }()
        let entries = liveVisibleEntries
        let mastered = entries.filter { $0.evolution == "mastered" }.count
        let projectName = primaryProjectName
        let subtitle: String = {
            if isSearching {
                let n = entries.count
                return uiLanguage == .vi ? "\(n) kết quả" : "\(n) result\(n == 1 ? "" : "s")"
            }
            var parts: [String] = []
            if let projectName, isTopic == nil { parts.append(projectName) }
            parts.append(uiLanguage == .vi ? "\(entries.count) từ" : "\(entries.count) term\(entries.count == 1 ? "" : "s")")
            if mastered > 0 { parts.append(uiLanguage == .vi ? "\(mastered) thành thạo" : "\(mastered) mastered") }
            return parts.joined(separator: " · ")
        }()
        return PixelCard(fill: accent.opacity(0.16), borderColor: accent,
                         shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .pixelBox(fill: accent, shadowOffset: 2, blockSize: 2, steps: 1, borderWidth: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(CodepetTheme.body(22, weight: .bold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(CodepetTheme.body(12))
                            .foregroundColor(CodepetTheme.bodyText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)

                liveRefreshButton
#if DEBUG
                debugSeedButton
#endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    /// The "✓ seen again in X.swift — counts as a rep" banner: a term that
    /// leveled up passively, by recurring in real code instead of via a quiz.
    private func passiveRepToast(_ rep: ProjectDictionaryStore.PassiveRep) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(CodepetTheme.accentTeal)
            (Text(rep.term).font(CodepetTheme.body(13, weight: .bold))
                + Text(uiLanguage == .vi ? " xuất hiện lại" : " showed up again").font(CodepetTheme.body(13)))
                .foregroundColor(CodepetTheme.primaryText)
            if !rep.file.isEmpty {
                Text(rep.file)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(CodepetTheme.accentTeal)
            }
            Text(uiLanguage == .vi ? "— tính là một lần ôn." : "— counts as a rep.")
                .font(CodepetTheme.body(13))
                .foregroundColor(CodepetTheme.bodyText)
            Spacer(minLength: 0)
            Button { dictionaryStore.lastPassiveRep = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CodepetTheme.accentTeal.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(CodepetTheme.accentTeal.opacity(0.4), lineWidth: 1))
        )
    }

#if DEBUG
    private var debugSeedButton: some View {
        Button { dictionaryStore.debugSeedDueReviews() } label: {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .padding(7)
                .background(Circle().fill(Color.orange))
        }
        .buttonStyle(.plain)
        .help("DEBUG: make terms due now to exercise the review flow")
    }
#endif

    private var liveRefreshButton: some View {
        Button {
            Task { await dictionaryEnricher.refresh(
                store: dictionaryStore, eventStore: eventStore,
                projectStore: projectStore, appState: appState, force: true) }
        } label: {
            HStack(spacing: 5) {
                if dictionaryEnricher.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(uiLanguage == .vi ? "Quét lại" : "Rescan")
                    .font(.pixelSystem(size: 10, weight: .semibold))
            }
            .foregroundColor(CodepetTheme.accentPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(CodepetTheme.accentPurple.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(dictionaryEnricher.isLoading)
        .help(uiLanguage == .vi ? "Quét code gần đây tìm từ mới" : "Scan recent code for new terms")
    }

    @ViewBuilder
    private var liveCardList: some View {
        let entries = liveVisibleEntries
        if entries.isEmpty {
            liveEmptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if !isSearching {
                            if let rep = dictionaryStore.lastPassiveRep {
                                passiveRepToast(rep)
                            }
                            DictionaryReviewSection()
                        }
                        ForEach(entries) { entry in
                            ProjectDictionaryCard(
                                entry: entry,
                                accent: liveAccent(entry.topic),
                                isExpanded: expandedTermIds.contains(entry.id),
                                onToggleExpand: { toggleExpand(entry.id) }
                            )
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
                }
            }
        }
    }

    private var liveEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: isSearching ? "magnifyingglass" : "sparkles")
                .font(.system(size: 30))
                .foregroundColor(CodepetTheme.mutedText)
            if isSearching {
                Text(uiLanguage == .vi
                     ? "Không có kết quả cho \u{201C}\(searchQuery)\u{201D}."
                     : "No matches for \u{201C}\(searchQuery)\u{201D}.")
                    .font(CodepetTheme.body(13))
                    .foregroundColor(CodepetTheme.mutedText)
            } else {
                Text(uiLanguage == .vi ? "Chưa có từ nào từ code của bạn" : "No terms from your code yet")
                    .font(CodepetTheme.body(15, weight: .bold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(uiLanguage == .vi
                     ? "Cứ tiếp tục code — những thuật ngữ bạn dùng sẽ xuất hiện ở đây, kèm nơi chúng được nhìn thấy."
                     : "Keep coding — terms you use will show up here, with where they were seen.")
                    .font(CodepetTheme.body(13))
                    .foregroundColor(CodepetTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Button {
                    surface = .basics(DictionaryContent.topics.first!.id)
                } label: {
                    Text(uiLanguage == .vi ? "Xem kiến thức nền →" : "Browse Coding Basics →")
                        .font(.pixelSystem(size: 12, weight: .semibold))
                        .foregroundColor(CodepetTheme.accentPurple)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var primaryProjectName: String? {
        projectStore.projects.values
            .sorted { $0.lastSeenAt > $1.lastSeenAt }
            .first?.displayName
    }

    // MARK: Content — static surface (Coding Basics)

    private var staticContentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(CodepetTheme.hairline)
            cardList
        }
    }

    private var currentTopic: DictionaryTopic? {
        isSearching ? nil : DictionaryContent.topic(forId: selectedTopicId)
    }

    private var headerAccent: Color {
        currentTopic?.accent.color ?? CodepetTheme.accentPurple
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            heroBanner
            searchField
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var tailorToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { detached.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: detached ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(detached
                     ? (uiLanguage == .vi ? "Đã tách" : "Detached")
                     : (uiLanguage == .vi ? "Theo dự án" : "Tailored"))
                    .font(.pixelSystem(size: 10, weight: .semibold))
            }
            .foregroundColor(detached ? CodepetTheme.mutedText : CodepetTheme.accentPurple)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(detached
                               ? Color.white.opacity(0.7)
                               : CodepetTheme.accentPurple.opacity(0.16))
            )
        }
        .buttonStyle(.plain)
        .help(detached
              ? (uiLanguage == .vi ? "Bật lại gợi ý theo dự án của bạn" : "Tailor the dictionary to your project")
              : (uiLanguage == .vi ? "Xem từ điển không gắn với dự án" : "Show the dictionary without your project"))
    }

    private var heroBanner: some View {
        let accent = headerAccent
        let icon = currentTopic?.icon ?? "magnifyingglass"
        let title = isSearching
            ? (uiLanguage == .vi ? "Kết quả tìm kiếm" : "Search results")
            : currentTopicTitle
        let subtitle: String = {
            if isSearching {
                let n = visibleTerms.count
                return uiLanguage == .vi ? "\(n) kết quả" : "\(n) result\(n == 1 ? "" : "s")"
            }
            return currentTopic?.blurb(uiLanguage) ?? ""
        }()
        return PixelCard(fill: accent.opacity(0.16), borderColor: accent,
                         shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .pixelBox(fill: accent, shadowOffset: 2, blockSize: 2, steps: 1, borderWidth: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(CodepetTheme.body(22, weight: .bold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(CodepetTheme.body(12))
                            .foregroundColor(CodepetTheme.bodyText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)

                tailorToggle

                if !isSearching {
                    let count = DictionaryContent.terms(in: selectedTopicId).count
                    VStack(spacing: 1) {
                        Text("\(count)")
                            .font(CodepetTheme.display(20, weight: .bold))
                            .foregroundColor(accent)
                        Text(uiLanguage == .vi ? "từ" : "terms")
                            .font(.pixelSystem(size: 9, weight: .semibold))
                            .tracking(1.0)
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.7))
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isSearching ? (isLive ? liveAccentForHeader : headerAccent) : CodepetTheme.mutedText)
            TextField(uiLanguage == .vi ? "Tìm kiếm…" : "Search…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(CodepetTheme.body(13))
                .foregroundColor(CodepetTheme.primaryText)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(CodepetTheme.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
        .codepetInput()
    }

    private var currentTopicTitle: String {
        DictionaryContent.topics.first { $0.id == selectedTopicId }?.title(uiLanguage)
            ?? (uiLanguage == .vi ? "Từ điển" : "Dictionary")
    }

    private func cardView(_ term: DictionaryTerm) -> some View {
        DictionaryCard(
            term: term,
            isExpanded: expandedTermIds.contains(term.id),
            onToggleExpand: { toggleExpand(term.id) },
            projectTags: effectiveGroup?.tags ?? [],
            projectName: effectiveGroup?.projectName
        )
        .id(term.id)
    }

    @ViewBuilder
    private var cardList: some View {
        if visibleTerms.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if !isSearching, let group = effectiveGroup {
                            projectPanel(group, proxy: proxy)
                        }
                        ForEach(visibleTerms) { term in
                            cardView(term)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                        scrollTarget = nil
                    }
                }
            }
        }
    }

    // MARK: - Static project panel (Surface B)

    private func projectPanel(_ group: DictionaryMatcher.ProjectTermGroup, proxy: ScrollViewProxy) -> some View {
        PixelCard(fill: Color(hex: "#EEEDFE"), shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showProjectPanel.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundColor(CodepetTheme.accentPurple)
                        Text(uiLanguage == .vi
                             ? "Trong \(group.projectName), bạn đang dùng:"
                             : "In \(group.projectName), you're using:")
                            .font(CodepetTheme.body(14, weight: .bold))
                            .foregroundColor(CodepetTheme.primaryText)
                        Spacer()
                        Image(systemName: showProjectPanel ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showProjectPanel {
                    stackPills(group.tags)
                    termGrid(group, proxy: proxy)
                }
            }
            .padding(16)
        }
        .padding(.bottom, 4)
    }

    private func stackPills(_ tags: Set<ProjectTag>) -> some View {
        let labels = projectTagLabels(tags)
        return HStack(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.pixelSystem(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(techTagColor(label)))
            }
            Spacer(minLength: 0)
        }
    }

    private func termGrid(_ group: DictionaryMatcher.ProjectTermGroup, proxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(group.terms) { matched in
                Button {
                    jumpTo(matched.term, proxy: proxy)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(CodepetTheme.accentPurple)
                        Text(matched.term.title(uiLanguage))
                            .font(CodepetTheme.body(12, weight: .semibold))
                            .foregroundColor(CodepetTheme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.7))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func jumpTo(_ term: DictionaryTerm, proxy: ScrollViewProxy) {
        searchQuery = ""
        surface = .basics(term.topicId)
        expandedTermIds.insert(term.id)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(term.id, anchor: .top) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(CodepetTheme.mutedText)
            Text(uiLanguage == .vi
                 ? "Không có kết quả cho \u{201C}\(searchQuery)\u{201D}."
                 : "No matches for \u{201C}\(searchQuery)\u{201D}.")
                .font(CodepetTheme.body(13))
                .foregroundColor(CodepetTheme.mutedText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleExpand(_ id: String) {
        if expandedTermIds.contains(id) {
            expandedTermIds.remove(id)
        } else {
            expandedTermIds.insert(id)
            feedbackManager.requestIfFirstTime(.dictionary)
        }
    }
}
