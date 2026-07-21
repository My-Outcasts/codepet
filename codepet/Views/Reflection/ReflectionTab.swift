import SwiftUI

struct ReflectionTab: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var reflectionStore: ReflectionEventStore
    @EnvironmentObject var narrativeStore: NarrativeStore
    @EnvironmentObject var summaryStore: SessionSummaryStore
    @EnvironmentObject var enricher: NarrativeEnricher
    @EnvironmentObject var endStore: SessionEndStore
    @EnvironmentObject var sessionEnricher: SessionSummaryEnricher
    @EnvironmentObject var chatStore: SessionChatStore
    @EnvironmentObject var chatController: SessionChatController
    @EnvironmentObject var demo: DemoScriptController
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var statusStore: SessionStatusStore
    @EnvironmentObject var healthNudge: HealthNudgeController
    @EnvironmentObject var feedbackManager: FeatureFeedbackManager
    @EnvironmentObject var agencyLog: AgencySignalLog
    @Environment(\.uiLanguage) private var uiLanguage

    /// When the global Skills-Advisor companion (CompanionPanelView) is open,
    /// suppress this tab's session chat so the user never sees two Nova chat
    /// boxes at once. The companion takes priority (it may be running a live
    /// exercise). Session content stays visible; only the duplicate chat hides.
    var companionOpen: Bool = false

    @State private var selectedSessionId: String? = nil
    @State private var hoveredSessionId: String? = nil
    @State private var chatExpanded = false
    @State private var sidebarCollapsed = false
    /// Tracks which project groups are collapsed in the sidebar.
    /// By default all groups are expanded (not in this set).
    @State private var collapsedProjects: Set<String> = []

    // MARK: - Cached session data (avoids recomputing on every body evaluation)

    /// Cached sessions — rebuilt only when upstream stores actually change.
    @State private var cachedSessions: [Session] = []
    /// Cached project groups — rebuilt alongside cachedSessions.
    @State private var cachedGroups: [ProjectGroup] = []
    /// Cached pinned sessions — shown in the "Pinned" section at the top.
    @State private var cachedPinnedSessions: [Session] = []
    /// Cached archived sessions — shown in the collapsible "Archived" section.
    @State private var cachedArchivedSessions: [Session] = []
    /// Whether the "Archived" section is expanded (collapsed by default).
    @State private var showArchivedExpanded = false
    /// Session awaiting delete confirmation (drives the alert).
    @State private var pendingDeleteSession: Session? = nil
    /// Session being renamed (drives the rename alert) + its editable text.
    @State private var renameSession: Session? = nil
    @State private var renameText: String = ""
    /// Input fingerprint: incremented when any upstream dependency publishes new data.
    /// onChange(of: dataVersion) triggers a single recompute of sessions + groups.
    @State private var dataVersion: Int = 0

    /// One-time, from-history brief backfill. Runs in the recompute path once
    /// sessions + summaries are loaded; idempotent and self-throttling.
    @StateObject private var briefSynthesizer = BriefSynthesizer(api: ReflectionAPIClient())

    // MARK: - Pet name

    private var petName: String {
        PetCharacter.all[appState.activeChar]?.name ?? ReflectionPet.name
    }

    // MARK: - Turn + Session assembly (cached)

    /// Recompute turns → sessions → groups. Called from onChange, NOT from the view body.
    private func recomputeSessionData() {
        let sessions: [Session]
        if appState.demoModeEnabled {
            sessions = [Session.makeWelcome()] + (demo.demoSession.map { [$0] } ?? [])
        } else {
            let inputs: [AssemblerInput] = reflectionStore.rawJSONLEvents.compactMap { entry in
                guard !entry.sessionId.isEmpty else { return nil }
                let kind: AssemblerInput.Kind
                switch entry.type {
                case "prompt":  kind = .prompt(text: entry.text)
                case "tool":    kind = .tool(text: entry.text)
                case "summary": kind = .summary(text: entry.text)
                default:        return nil
                }
                return AssemblerInput(kind: kind, isoTime: entry.isoTime, sessionId: entry.sessionId, cwd: entry.cwd, path: entry.path)
            }
            let turns = TurnAssembler.assemble(
                inputs: inputs,
                now: Date(),
                narratives: narrativeStore.narratives,
                failedTurns: enricher.failedTurns
            )
            let real = TurnAssembler.assembleSessions(
                turns: turns,
                summaries: summaryStore.summaries
            )
            sessions = [Session.makeWelcome()] + real
        }
        // Deleted sessions disappear everywhere; pinned ones rise to a "Pinned"
        // section at the top; archived ones move to the recoverable "Archived"
        // section. The remaining sessions stay in their project groups.
        let recent: (Session, Session) -> Bool = {
            ($0.turns.last?.startedAt ?? .distantPast) > ($1.turns.last?.startedAt ?? .distantPast)
        }
        // Reflection isolation: hide sessions that predate the active account's
        // first sign-in on this Mac (the ~/.codepet logs are machine-global, so
        // without this a new account would see the previous user's history).
        // Demo mode and the welcome row are always exempt.
        let watermark = appState.demoModeEnabled
            ? Date.distantPast
            : (statusStore.activeAccountStart ?? .distantPast)
        let visible = sessions.filter { session in
            if session.isWelcome { return true }
            if statusStore.isDeleted(session.id) { return false }
            let activity = session.turns.last?.startedAt ?? session.startedAt
            return activity >= watermark
        }
        cachedSessions = visible
        let active = visible.filter {
            $0.isWelcome || (!statusStore.isArchived($0.id) && !statusStore.isPinned($0.id))
        }
        cachedGroups = buildProjectGroups(from: active)
        cachedPinnedSessions = visible
            .filter { !$0.isWelcome && statusStore.isPinned($0.id) }
            .sorted(by: recent)
        cachedArchivedSessions = visible
            .filter { !$0.isWelcome && statusStore.isArchived($0.id) }
            .sorted(by: recent)
    }

    private var selectedSession: Session? {
        if appState.demoModeEnabled, let demoSess = demo.demoSession {
            return demoSess
        }
        if let id = selectedSessionId,
           let match = cachedSessions.first(where: { $0.id == id }) {
            return match
        }
        return cachedSessions.first
    }

    // MARK: - Body

    var body: some View {
        normalBody
    }

    private var normalBody: some View {
        HStack(alignment: .top, spacing: 0) {
            if sidebarCollapsed {
                // Collapsed: just a minimal toggle (Claude Code style) — no rail
                collapsedSidebarStrip
            } else {
                sessionsSidebar
                    .frame(width: 280)
            }

            Group {
                if let session = selectedSession {
                    VStack(spacing: 0) {
                        // Health nudge banner — slides in when the pet wants the user to take a break
                        if let nudge = healthNudge.activeNudge {
                            HealthNudgeBanner(nudge: nudge, onDismiss: { healthNudge.dismiss() })
                                .padding(.horizontal, 40)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 36) {
                                // The one-time milestone moment — appears at the
                                // very top when a process pattern first crosses
                                // growth → strength. Self-hides once acknowledged.
                                milestoneMoment()

                                if session.isWelcome {
                                    WelcomeSessionView()
                                } else {
                                    // Pet avatar sits above the project brief.
                                    petHeader(for: session)
                                    // Project brief card — shown when session belongs to a detected project
                                    if let resolved = projectStore.resolvedProjectPath(for: session.projectPath, sessionId: session.id),
                                       !resolved.isEmpty {
                                        ProjectBriefCard(projectPath: resolved)
                                    }
                                    sessionBody(for: session)
                                    footer
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.vertical, 32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity)

            // Right-docked chat sidebar (open state)
            if let session = selectedSession, !session.isWelcome, chatExpanded, !companionOpen {
                Divider()
                    .background(ReflectionTheme.borderLight)
                SessionChatPanel(
                    session: session,
                    onClose: {
                        if chatController.inFlightSessionId == session.id {
                            chatController.cancel()
                        }
                        chatExpanded = false
                    },
                    onSend: { text in
                        let request = makeChatRequest(for: session, userMessage: text)
                        Task {
                            await chatController.send(
                                userText: text,
                                sessionId: session.id,
                                request: request
                            )
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(ReflectionTheme.background)
        .alert(
            uiLanguage == .vi ? "Xóa phiên này?" : "Delete this session?",
            isPresented: Binding(
                get: { pendingDeleteSession != nil },
                set: { if !$0 { pendingDeleteSession = nil } }
            )
        ) {
            Button(uiLanguage == .vi ? "Hủy" : "Cancel", role: .cancel) {
                pendingDeleteSession = nil
            }
            Button(uiLanguage == .vi ? "Xóa" : "Delete", role: .destructive) {
                if let session = pendingDeleteSession {
                    if selectedSessionId == session.id { selectedSessionId = nil }
                    statusStore.delete(session.id)
                }
                pendingDeleteSession = nil
            }
        } message: {
            Text(uiLanguage == .vi
                 ? "Phiên này sẽ bị ẩn khỏi danh sách của bạn. Nếu có thể bạn vẫn cần đến nó sau này, hãy lưu trữ thay vì xóa."
                 : "This session will be hidden from your list. If you might want it later, archive it instead.")
        }
        .alert(
            uiLanguage == .vi ? "Đổi tên phiên" : "Rename session",
            isPresented: Binding(
                get: { renameSession != nil },
                set: { if !$0 { renameSession = nil } }
            )
        ) {
            TextField(uiLanguage == .vi ? "Tên phiên" : "Session name", text: $renameText)
            Button(uiLanguage == .vi ? "Hủy" : "Cancel", role: .cancel) {
                renameSession = nil
            }
            Button(uiLanguage == .vi ? "Lưu" : "Save") {
                if let session = renameSession {
                    statusStore.rename(session.id, to: renameText)
                }
                renameSession = nil
            }
        } message: {
            Text(uiLanguage == .vi
                 ? "Để trống để khôi phục tên tự động."
                 : "Leave blank to restore the auto-generated name.")
        }
        .overlay(alignment: .bottomTrailing) {
            // Floating launcher bubble — only visible when chat is collapsed.
            if let session = selectedSession, !session.isWelcome, !chatExpanded {
                SessionChatBubble(onTap: { chatExpanded = true })
                    .padding(16)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeOut(duration: 0.22), value: chatExpanded)
        .animation(.easeInOut(duration: 0.2), value: sidebarCollapsed)
        // NOTE: collapsedProjects animation is scoped to projectGroupSection
        // via .animation(.easeOut(duration: 0.12), value: isCollapsed) — do NOT
        // add a top-level .animation(value: collapsedProjects) here as it would
        // animate unrelated parts of the tree.
        .background {
            // Hidden button to capture ⌘B keyboard shortcut
            Button("") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarCollapsed.toggle()
                }
            }
            .keyboardShortcut("b", modifiers: .command)
            .hidden()
        }
        .onAppear {
            // Initial data load — runs once on first render.
            recomputeSessionData()
            registerNewProjects()
            publishActiveProject()

            // Tips tab deep-link: when arriving on Reflection with a pending
            // chat prompt, auto-select the most recent real session and open chat.
            // This must live in onAppear (not onChange) because MainTabView uses a
            // switch statement that recreates ReflectionTab on every tab change,
            // so onChange(of: selectedTab) never fires — the value is already
            // .reflection by the time the new view instance is created.
            if appState.pendingChatPrompt != nil {
                if let mostRecent = cachedSessions.first(where: { !$0.isWelcome }) {
                    selectedSessionId = mostRecent.id
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
                        withAnimation(.easeOut(duration: 0.22)) {
                            chatExpanded = true
                        }
                    }
                }
            }
        }
        // --- Data version bumpers: each upstream @Published change increments
        // the version counter. Only ONE recompute fires per runloop cycle.
        .onChange(of: reflectionStore.rawJSONLEvents.count) { _ in
            dataVersion += 1
            // New coding events arrived — mark the session as active so the
            // health nudge timer starts counting.
            healthNudge.markActive()
        }
        .onChange(of: narrativeStore.narratives.count) { _ in dataVersion += 1 }
        .onChange(of: summaryStore.summaries.count) { _ in dataVersion += 1 }
        .onChange(of: enricher.failedTurns.count) { _ in dataVersion += 1 }
        .onChange(of: appState.demoModeEnabled) { _ in dataVersion += 1 }
        .onChange(of: statusStore.activeAccountStart) { _ in dataVersion += 1 }
        .onChange(of: statusStore.pinnedSessionIds) { _ in dataVersion += 1 }
        .onChange(of: statusStore.archivedSessionIds) { _ in dataVersion += 1 }
        .onChange(of: statusStore.deletedSessionIds) { _ in dataVersion += 1 }
        // --- Single recompute when any upstream data changes
        .onChange(of: dataVersion) { _ in
            recomputeSessionData()
            registerNewProjects()

            guard !appState.demoModeEnabled else { return }
            let persona = currentPetPersona()
            for session in cachedSessions {
                for turn in session.turns where turn.state == .summarizing && turn.narrative == nil {
                    Task { await enricher.enrich(turn: turn, petPersona: persona) }
                }
            }
            autoSummarizeIfNeeded(sessions: cachedSessions, persona: persona)
            // One-time per-project: synthesize a complete brief from the
            // project's full session history (overwrites empty/auto, never a
            // user-edited description).
            briefSynthesizer.backfill(
                sessions: cachedSessions,
                projectStore: projectStore,
                language: uiLanguage == .vi ? "vi" : "en"
            )
            // The default selection (most recent session) may have changed as
            // data loaded — keep Project Health's focused project in sync.
            publishActiveProject()
        }
        .onChange(of: endStore.endedSessionIds) { _ in
            // A session just ended — recompute then check auto-summarize.
            recomputeSessionData()
            guard !appState.demoModeEnabled else { return }
            // First reflected session → ask for first-experience feedback.
            feedbackManager.requestIfFirstTime(.reflection)
            let persona = currentPetPersona()
            autoSummarizeIfNeeded(sessions: cachedSessions, persona: persona)
        }
        .onChange(of: selectedSessionId) { newId in
            // The focused session changed — sync Project Health's active project.
            publishActiveProject()
            // Auto-expand the project group that contains the selected session.
            guard let sid = newId else { return }
            for group in cachedGroups {
                if group.sessions.contains(where: { $0.id == sid }) {
                    collapsedProjects.remove(group.id)
                    break
                }
            }
        }
    }

    /// Mirror Reflection's project list into the shared ProjectStore so the Tips
    /// tab's Project Health shows the same projects, in the same order, with the
    /// same active project highlighted.
    private func publishActiveProject() {
        // Ordered project list — exactly what the sidebar groups show (most
        // recent first, sessions-only). Project Health renders its tabs from it.
        let ordered = cachedGroups.compactMap { $0.projectPath }
        projectStore.setReflectionProjectOrder(ordered)

        // The focused project — for the highlighted/active tab. Falls back to the
        // most recent real session when the welcome card is the default selection.
        let focused: Session? = (selectedSession?.isWelcome == false)
            ? selectedSession
            : cachedSessions.first(where: { !$0.isWelcome })
        guard let session = focused else {
            projectStore.setActiveProject(nil)
            return
        }
        let resolved = projectStore.resolvedProjectPath(for: session.projectPath, sessionId: session.id)
        projectStore.setActiveProject(resolved)
    }

    private func currentPetPersona() -> SummarizeTurnRequest.PetPersonaDTO? {
        guard let pet = PetCharacter.all[appState.activeChar] else { return nil }
        return SummarizeTurnRequest.PetPersonaDTO(
            id: pet.id,
            name: pet.name,
            personality: pet.personality,
            domain: pet.domain,
            voiceGuide: pet.voiceGuide,
            lensGuide: pet.lensGuide,
            emotionalTriggers: pet.emotionalTriggers,
            metaphorFamily: pet.metaphorFamily,
            signatureEmojis: pet.signatureEmojis
        )
    }

    private func makeChatRequest(for session: Session, userMessage: String) -> ChatSessionRequest {
        let history = chatStore.historySnapshot(for: session.id, lastN: 10)
            .map { ChatSessionRequest.ChatMessageDTO(role: $0.role.rawValue, text: $0.text) }
        let resolvedPath = projectStore.resolvedProjectPath(for: session.projectPath, sessionId: session.id)
        let context = ReflectionComposition.makeChatContext(
            for: session,
            userBrief: projectStore.brief(for: resolvedPath).isEmpty
                ? NarrativeEnricher.currentUserBrief(projectPath: resolvedPath)
                : projectStore.brief(for: resolvedPath)
        )
        let language = Locale.current.identifier.hasPrefix("vi") ? "vi" : "en"
        return ChatSessionRequest(
            sessionId: session.id,
            language: language,
            petPersona: currentPetPersona(),
            sessionContext: context,
            history: history,
            userMessage: userMessage
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Spacer()
            Text(uiLanguage == .vi
                 ? "Chưa có gì để nhìn lại."
                 : "Nothing to reflect on yet.")
                .font(ReflectionTheme.serif(20, weight: .medium))
                .foregroundColor(ReflectionTheme.primaryText)
                .multilineTextAlignment(.center)
            Text(uiLanguage == .vi
                 ? "Mở Claude Code và bắt đầu code — câu chuyện của bạn sẽ hiện ở đây sau mỗi phiên làm việc."
                 : "Open Claude Code and start coding — your story will appear here after each working session.")
                .font(ReflectionTheme.sans(13))
                .foregroundColor(ReflectionTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Sidebar

    private struct ProjectGroup: Identifiable {
        let projectPath: String?     // nil = ungrouped sessions
        let displayName: String
        let sessions: [Session]
        var id: String { projectPath ?? "__ungrouped__" }
    }

    /// Build project groups from a pre-computed session list. Pure function — no I/O.
    /// Called from `recomputeSessionData()`, NOT from the view body.
    private func buildProjectGroups(from sessions: [Session]) -> [ProjectGroup] {
        var byProject: [String: [Session]] = [:]  // projectPath → sessions
        var ungrouped: [Session] = []

        for session in sessions where !session.isWelcome {
            if let resolved = projectStore.resolvedProjectPath(for: session.projectPath, sessionId: session.id),
               !resolved.isEmpty {
                byProject[resolved, default: []].append(session)
            } else {
                ungrouped.append(session)
            }
        }

        var groups: [ProjectGroup] = byProject.map { path, sessions in
            let name = projectStore.project(for: path)?.displayName ?? Project.nameFromPath(path)
            return ProjectGroup(
                projectPath: path,
                displayName: name,
                sessions: sessions.sorted { ($0.turns.last?.startedAt ?? .distantPast) > ($1.turns.last?.startedAt ?? .distantPast) }
            )
        }
        // Sort project groups by most-recent session
        groups.sort { group1, group2 in
            let t1 = group1.sessions.first?.turns.last?.startedAt ?? .distantPast
            let t2 = group2.sessions.first?.turns.last?.startedAt ?? .distantPast
            return t1 > t2
        }

        // Append ungrouped sessions at the end if any
        if !ungrouped.isEmpty {
            let label = uiLanguage == .vi ? "Khác" : "Other"
            groups.append(ProjectGroup(
                projectPath: nil,
                displayName: label,
                sessions: ungrouped.sorted { ($0.turns.last?.startedAt ?? .distantPast) > ($1.turns.last?.startedAt ?? .distantPast) }
            ))
        }

        return groups
    }

    /// Register any new project paths found in sessions. Called from `.onChange`
    /// (not from the view body) so @Published mutations don't trigger
    /// "Publishing changes from within view updates" warnings.
    /// Register projects and build the cwd → root resolution cache.
    /// Called from `.onChange(of: dataVersion)` — NOT from the view body.
    private func registerNewProjects() {
        for session in cachedSessions where !session.isWelcome {
            if let path = session.projectPath, !path.isEmpty {
                // Always call detectProject so the cwd → root cache stays warm,
                // even for already-known projects. detectProject is cheap for
                // existing entries (just updates lastSeenAt).
                projectStore.detectProject(cwd: path, filePaths: session.filePaths, sessionId: session.id)
            } else if !session.filePaths.isEmpty {
                // Session has no cwd but does have file paths — try to resolve
                // project from the file paths alone.
                projectStore.detectProjectFromFilePaths(session.filePaths, sessionId: session.id)
            }
        }
    }

    /// Auto-summarize sessions that are ended or idle. Fires when:
    ///   - a SessionEnd signal arrives (user closed the Claude Code session), OR
    ///   - a session has been idle > 30 min with no summary
    private func autoSummarizeIfNeeded(
        sessions: [Session],
        persona: SummarizeTurnRequest.PetPersonaDTO?
    ) {
        let ended = endStore.endedSessionIds
        for session in sessions where !session.isWelcome {
            guard sessionEnricher.shouldAutoSummarize(session: session, endedSessionIds: ended) else { continue }
            Task { await sessionEnricher.enrich(session: session, petPersona: persona, isAutoTriggered: true) }
        }
    }

    private func sessionRowTitle(for session: Session) -> String {
        // 0. User-supplied custom name (from Rename) wins over everything.
        if let custom = statusStore.customTitle(for: session.id) { return custom }
        // 1. First sentence of summary (≤60 chars) — strip Markdown first so the
        //    truncation counts real characters, not **bold**/`code` markers.
        if let summaryText = session.summary?.summary {
            let firstSentence = summaryText.components(separatedBy: ".").first?.trimmingCharacters(in: .whitespaces) ?? summaryText
            let truncated = String(stripMarkdown(firstSentence).prefix(60))
            if !truncated.isEmpty { return truncated }
        }
        // 2. Newest turn narrative title
        let newestTurn = session.turns.last
        if let title = newestTurn?.narrative?.title { return stripMarkdown(title) }
        // 3. Fallback: "Session HH:mm"
        let prefix = uiLanguage == .vi ? "Phiên" : "Session"
        return "\(prefix) \(timeDisplay(session.startedAt))"
    }

    /// Strips inline Markdown markers (**, *, `, leading #/>) from titles so they
    /// read as plain prose in the list instead of showing raw syntax.
    private func stripMarkdown(_ s: String) -> String {
        var out = s
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
        while let first = out.first, "#>".contains(first) { out.removeFirst() }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Turns a raw folder name into a tidy label for the sidebar header:
    /// hyphens/underscores become spaces, sentence-cased (leading capital, rest
    /// lowercase) so it reads as a name without shouting.
    private func prettyProjectName(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .split(separator: " ")
            .joined(separator: " ")
        guard !cleaned.isEmpty else { return raw }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    private func sessionMetaLabel(for session: Session) -> String {
        let turnCount = session.turns.count
        let turnWord: String
        switch uiLanguage {
        case .vi: turnWord = "lượt"
        case .en: turnWord = turnCount == 1 ? "turn" : "turns"
        }
        let minWord = uiLanguage == .vi ? "phút" : "min"
        var parts = [relativeDateLabel(session.startedAt), timeDisplay(session.startedAt), "\(turnCount) \(turnWord)"]
        if let ended = session.endedAt {
            let mins = Int(ended.timeIntervalSince(session.startedAt) / 60)
            if mins > 0 { parts.append("\(mins) \(minWord)") }
        }
        return parts.joined(separator: " · ")
    }

    /// Meta as separator-free groups for the sidebar list: date+time read as one
    /// unit, then turns and duration. Rendered as a spaced HStack (no "·").
    private func sessionMetaParts(for session: Session) -> [String] {
        let turnCount = session.turns.count
        let turnWord = uiLanguage == .vi ? "lượt" : (turnCount == 1 ? "turn" : "turns")
        let minWord = uiLanguage == .vi ? "phút" : "min"
        var parts = ["\(relativeDateLabel(session.startedAt)) \(timeDisplay(session.startedAt))",
                     "\(turnCount) \(turnWord)"]
        if let ended = session.endedAt {
            let mins = Int(ended.timeIntervalSince(session.startedAt) / 60)
            if mins > 0 { parts.append("\(mins) \(minWord)") }
        }
        return parts
    }

    /// Short relative date label for session rows (since we no longer group by day).
    private func relativeDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: date)
        if day == today {
            return uiLanguage == .vi ? "Hôm nay" : "Today"
        }
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        if day == yesterday {
            return uiLanguage == .vi ? "Hôm qua" : "Yesterday"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    // MARK: - Collapsed sidebar

    /// Collapsed state mirrors Claude Code: the rail disappears entirely, leaving
    /// only a small toggle at the top-left to bring the sidebar back. No project
    /// tiles and no background strip — the content takes over the freed space.
    private var collapsedSidebarStrip: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sidebarCollapsed = false
                }
            } label: {
                Image(systemName: "line.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(ReflectionTheme.mutedText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(uiLanguage == .vi ? "Mở thanh bên (⌘B)" : "Expand sidebar (⌘B)")
            Spacer()
        }
        .padding(.top, 18)
        .padding(.leading, 14)
        .padding(.trailing, 6)
    }

    // MARK: - Full sessions sidebar

    private var sessionsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // Sidebar toggle button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ReflectionTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(ReflectionTheme.accent.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(uiLanguage == .vi ? "Ẩn thanh bên (⌘B)" : "Collapse sidebar (⌘B)")

                if !sidebarCollapsed {
                    Text(uiLanguage == .vi ? "Phiên" : "Sessions")
                        .font(ReflectionTheme.serif(16, weight: .semibold))
                        .foregroundColor(ReflectionTheme.primaryText)
                }
                Spacer()
            }
            .padding(.horizontal, sidebarCollapsed ? 8 : 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Welcome group — always pinned at top
                    VStack(alignment: .leading, spacing: 10) {
                        welcomeSidebarRow(Session.makeWelcome())
                    }

                    // Pinned sessions — surfaced at the top when non-empty
                    if !cachedPinnedSessions.isEmpty {
                        pinnedSection
                    }

                    // Project-grouped sessions (collapsible) — uses cached groups
                    ForEach(cachedGroups) { group in
                        projectGroupSection(group)
                    }

                    // Archived sessions (collapsible) — only shown when non-empty
                    if !cachedArchivedSessions.isEmpty {
                        archivedSection
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [ReflectionTheme.sidebarTop, ReflectionTheme.sidebarBottom],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ReflectionTheme.sidebarBorder)
                .frame(width: 0.5)
        }
    }

    /// A single collapsible project group. Sessions stay in the view tree
    /// (hidden via height + opacity) so SwiftUI doesn't diff-insert/remove
    /// the entire ForEach on every toggle — this is what makes it fast.
    @ViewBuilder
    private func projectGroupSection(_ group: ProjectGroup) -> some View {
        let isCollapsed = collapsedProjects.contains(group.id)
        VStack(alignment: .leading, spacing: 0) {
            // Header button
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    if isCollapsed {
                        collapsedProjects.remove(group.id)
                    } else {
                        collapsedProjects.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(ReflectionTheme.accent.opacity(0.6))
                        .frame(width: 10)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Text(prettyProjectName(group.displayName))
                        .font(ReflectionTheme.sans(14, weight: .semibold))
                        .tracking(0.2)
                        .foregroundColor(ReflectionTheme.accent)
                    Spacer()
                    Text("\(group.sessions.count)")
                        .font(ReflectionTheme.sans(9, weight: .semibold))
                        .foregroundColor(ReflectionTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(ReflectionTheme.accent.opacity(0.12))
                        )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Session rows — always in the tree, just clamped to zero height when collapsed
            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.sessions) { session in
                    sidebarSessionRow(session)
                }
            }
            .padding(.top, isCollapsed ? 0 : 10)
            .frame(maxHeight: isCollapsed ? 0 : .infinity)
            .clipped()
            .opacity(isCollapsed ? 0 : 1)
            .allowsHitTesting(!isCollapsed)
        }
        .animation(.easeOut(duration: 0.12), value: isCollapsed)
    }

    /// "Pinned" section at the top of the sidebar — accent-styled, always shown
    /// when non-empty.
    @ViewBuilder
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(ReflectionTheme.accent)
                    .rotationEffect(.degrees(45))
                Text(uiLanguage == .vi ? "ĐÃ GHIM" : "PINNED")
                    .font(CodepetTheme.pixel(12))
                    .tracking(1.2)
                    .foregroundColor(ReflectionTheme.accent)
                Spacer()
                Text("\(cachedPinnedSessions.count)")
                    .font(ReflectionTheme.sans(9, weight: .semibold))
                    .foregroundColor(ReflectionTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(ReflectionTheme.accent.opacity(0.12)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(cachedPinnedSessions) { session in
                    sidebarSessionRow(session)
                }
            }
            .padding(.top, 10)
        }
    }

    /// Collapsible "Archived" section at the bottom of the sidebar. Mirrors the
    /// project-group collapse behavior but in a muted, de-emphasized style.
    @ViewBuilder
    private var archivedSection: some View {
        let collapsed = !showArchivedExpanded
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) { showArchivedExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(ReflectionTheme.mutedText)
                        .frame(width: 10)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 9))
                        .foregroundColor(ReflectionTheme.mutedText)
                    Text(uiLanguage == .vi ? "ĐÃ LƯU TRỮ" : "ARCHIVED")
                        .font(CodepetTheme.pixel(12))
                        .tracking(1.2)
                        .foregroundColor(ReflectionTheme.mutedText)
                    Spacer()
                    Text("\(cachedArchivedSessions.count)")
                        .font(ReflectionTheme.sans(9, weight: .semibold))
                        .foregroundColor(ReflectionTheme.mutedText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ReflectionTheme.mutedText.opacity(0.12)))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(cachedArchivedSessions) { session in
                    sidebarSessionRow(session, archived: true)
                }
            }
            .padding(.top, collapsed ? 0 : 10)
            .frame(maxHeight: collapsed ? 0 : .infinity)
            .clipped()
            .opacity(collapsed ? 0 : 1)
            .allowsHitTesting(!collapsed)
        }
        .animation(.easeOut(duration: 0.12), value: showArchivedExpanded)
    }

    private func welcomeSidebarRow(_ session: Session) -> some View {
        let isSelected = session.id == selectedSessionId
        return Button {
            selectedSessionId = session.id
        } label: {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(ReflectionTheme.accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ReflectionTheme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(uiLanguage == .vi ? "Bắt đầu" : "Get started")
                        .font(ReflectionTheme.sans(12.5, weight: .semibold))
                        .foregroundColor(ReflectionTheme.accent)
                    Text(uiLanguage == .vi
                         ? "Kết nối Claude Code để bắt đầu"
                         : "Connect Claude Code to begin")
                        .font(ReflectionTheme.sans(10.5))
                        .foregroundColor(ReflectionTheme.mutedText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? LinearGradient(colors: [ReflectionTheme.accent.opacity(0.18), ReflectionTheme.accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [ReflectionTheme.accent.opacity(0.05), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private func sidebarSessionRow(_ session: Session, archived: Bool = false) -> some View {
        let isSelected = session.id == selectedSessionId
        let isHovered = session.id == hoveredSessionId
        let isLive = sessionStateColor(session) == ReflectionTheme.accent
        return Button {
            selectedSessionId = session.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(sessionStateColor(session))
                    .frame(width: isLive ? 8 : 6, height: isLive ? 8 : 6)
                    .padding(.top, isLive ? 6 : 7)
                    .shadow(color: isLive ? ReflectionTheme.accent.opacity(0.5) : .clear, radius: isLive ? 4 : 0)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        if statusStore.isPinned(session.id) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(ReflectionTheme.accent)
                                .rotationEffect(.degrees(45))
                        }
                        Text(sessionRowTitle(for: session))
                            .font(ReflectionTheme.sans(12.5, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? ReflectionTheme.primaryText : ReflectionTheme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        ForEach(Array(sessionMetaParts(for: session).enumerated()), id: \.offset) { _, part in
                            Text(part)
                                .font(ReflectionTheme.sans(10.5))
                                .foregroundColor(ReflectionTheme.mutedText)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? LinearGradient(
                              colors: [ReflectionTheme.accent.opacity(0.15), ReflectionTheme.accent.opacity(0.06)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(
                              colors: [isHovered ? Color.black.opacity(0.03) : Color.clear,
                                       isHovered ? Color.black.opacity(0.01) : Color.clear],
                              startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ReflectionTheme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // Discoverable "⋯" affordance — reveals the same menu as right-click.
            // The Menu stays in the tree always (so an open popover isn't
            // dismissed when hover flips); only its label fades in/out.
            Menu {
                sessionContextMenu(session: session)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(ReflectionTheme.secondaryText)
                    .frame(width: 24, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ReflectionTheme.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(ReflectionTheme.borderLight, lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 14)
            .padding(.top, 9)
            .opacity((session.id == hoveredSessionId || session.id == selectedSessionId) ? 1 : 0)
            .allowsHitTesting(session.id == hoveredSessionId || session.id == selectedSessionId)
        }
        .onHover { hoveredSessionId = $0 ? session.id : nil }
        .opacity(archived ? 0.7 : 1)
        .contextMenu {
            sessionContextMenu(session: session)
        }
    }

    /// Right-click actions for a session row — mirrors Claude Code's menu:
    /// Move to project · Pin · Rename · Archive · Delete.
    @ViewBuilder
    private func sessionContextMenu(session: Session) -> some View {
        let pinned = statusStore.isPinned(session.id)
        let archived = statusStore.isArchived(session.id)

        moveToProjectMenu(session: session)

        Divider()

        Button {
            statusStore.togglePin(session.id)
        } label: {
            Label(pinned ? (uiLanguage == .vi ? "Bỏ ghim" : "Unpin")
                         : (uiLanguage == .vi ? "Ghim" : "Pin"),
                  systemImage: pinned ? "pin.slash" : "pin")
        }

        Button {
            renameText = statusStore.customTitle(for: session.id) ?? sessionRowTitle(for: session)
            renameSession = session
        } label: {
            Label(uiLanguage == .vi ? "Đổi tên" : "Rename", systemImage: "pencil")
        }

        Divider()

        Button {
            if archived {
                statusStore.unarchive(session.id)
            } else {
                if selectedSessionId == session.id { selectedSessionId = nil }
                statusStore.archive(session.id)
            }
        } label: {
            Label(archived ? (uiLanguage == .vi ? "Bỏ lưu trữ" : "Unarchive")
                           : (uiLanguage == .vi ? "Lưu trữ" : "Archive"),
                  systemImage: archived ? "tray.and.arrow.up" : "archivebox")
        }

        Button(role: .destructive) {
            pendingDeleteSession = session
        } label: {
            Label(uiLanguage == .vi ? "Xóa" : "Delete", systemImage: "trash")
        }
    }

    /// Right-click "Move to…" submenu — lists all known projects.
    @ViewBuilder
    private func moveToProjectMenu(session: Session) -> some View {
        let currentResolved = projectStore.resolvedProjectPath(for: session.projectPath, sessionId: session.id)
        Menu(uiLanguage == .vi ? "Chuyển sang dự án…" : "Move to project…") {
            ForEach(projectStore.sortedProjects) { project in
                if project.id != currentResolved {
                    Button {
                        projectStore.assignSession(session.id, to: project.id)
                    } label: {
                        Label(project.displayName, systemImage: "folder")
                    }
                }
            }
        }
    }

    /// Color represents the "worst" state among the session's turns.
    private func sessionStateColor(_ session: Session) -> Color {
        let hasFailed = session.turns.contains {
            if case .failed = $0.state { return true }
            return false
        }
        if hasFailed { return ReflectionTheme.moodAlert }
        let hasSummarizing = session.turns.contains { $0.state == .summarizing || $0.state == .pending }
        if hasSummarizing { return ReflectionTheme.accent }
        return ReflectionTheme.moodCalm
    }

    // MARK: - Pet header (session level)

    @ViewBuilder
    private func petHeader(for session: Session) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                PetAvatar(mood: .calm, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(petName)
                        .font(ReflectionTheme.serif(18, weight: .medium))
                        .foregroundColor(ReflectionTheme.primaryText)
                    Text(dateDisplay(session.startedAt))
                        .font(ReflectionTheme.sans(11))
                        .foregroundColor(ReflectionTheme.mutedText)
                }
                Spacer()
            }

            // Session meta (time · turns · duration) sits right under the date.
            sessionHeaderStrip(for: session)
        }
    }

    // MARK: - Session body

    @ViewBuilder
    private func sessionBody(for session: Session) -> some View {
        // LazyVStack so long sessions only build turn views as they scroll into
        // view — a plain VStack materializes every turn (markdown parsing,
        // glossary scan, typewriter state) the instant the session is opened.
        LazyVStack(alignment: .leading, spacing: 28) {
            // Pet recap up top — high-level voice before the turn-by-turn detail.
            // In demo mode the typewriter reveal replaces the live AI call.
            SessionSummaryView(
                summary: session.summary,
                onTriggerSummary: {
                    let persona = currentPetPersona()
                    Task { await sessionEnricher.enrich(session: session, petPersona: persona, isAutoTriggered: false) }
                },
                useTypewriter: appState.demoModeEnabled,
                hasMeaningfulWork: session.hasMeaningfulWork
            )

            // The "growth edge" — one gentle, specific coaching line about HOW
            // the user worked with their AI this session (process literacy).
            // Only the most recent growth-valence signal surfaces; strengths and
            // the structured fields stay in AgencySignalLog for the Learner Model.
            growthEdgeLine(for: session)

            // Per-turn rendering (chronological, oldest first).
            // Avatar appears only on the newest turn — older turns share the
            // pet-color thread so the page doesn't feel like the avatar
            // repeats on every entry.
            ForEach(Array(session.turns.enumerated()), id: \.element.id) { index, turn in
                turnSection(for: turn, isLast: index == session.turns.count - 1)
            }
        }
    }

    /// The one-time milestone moment — the rare, elevated celebration shown the
    /// first time a process pattern crosses growth → strength. Reads the strongest
    /// not-yet-surfaced trajectory; acknowledging it marks it surfaced (so it
    /// never interrupts again) and it lives on in Profile → "How you've grown".
    @ViewBuilder
    private func milestoneMoment() -> some View {
        if let t = agencyLog.pendingMilestone() {
            let copy = MilestoneCopy.text(for: t, vietnamese: uiLanguage == .vi)
            let purple = ReflectionTheme.brandPurple
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    PetAvatar(mood: .engaged, size: 64)

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Text("◆◆◆")
                                .font(.system(size: 9))
                                .tracking(2)
                                .foregroundColor(purple)
                            Text((uiLanguage == .vi ? "\(petName) để ý thấy" : "\(petName) noticed something").uppercased())
                                .font(.pixelSystem(size: 9, weight: .semibold))
                                .tracking(0.6)
                                .foregroundColor(purple)
                        }

                        Text(copy.headline)
                            .font(ReflectionTheme.serif(18, weight: .medium))
                            .foregroundColor(ReflectionTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(copy.body)
                            .font(ReflectionTheme.sans(14))
                            .foregroundColor(ReflectionTheme.secondaryText)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            Text("\(t.signal) · growth → strength")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(purple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(purple.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(purple.opacity(0.22), lineWidth: 1))

                            HStack(spacing: 6) {
                                Text(uiLanguage == .vi ? "Đúng cảm giác chứ?" : "Felt right?")
                                    .font(ReflectionTheme.sans(12))
                                    .foregroundColor(ReflectionTheme.mutedText)
                                milestoneFeedbackButton("👍", for: t)
                                milestoneFeedbackButton("👎", for: t)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [purple.opacity(0.12), purple.opacity(0.07)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(purple.opacity(0.22), lineWidth: 1)
                )

                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(ReflectionTheme.mutedText)
                    Text(uiLanguage == .vi
                         ? "Chỉ hiện một lần, rồi chuyển vào Hồ sơ → Sự tiến bộ của bạn."
                         : "Shown once, then it moves to Profile → How you've grown.")
                        .font(ReflectionTheme.sans(12))
                        .foregroundColor(ReflectionTheme.mutedText)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func milestoneFeedbackButton(_ emoji: String, for t: Trajectory) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                agencyLog.markMilestoneSurfaced(t)
            }
        } label: {
            Text(emoji)
                .font(.system(size: 13))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(ReflectionTheme.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(ReflectionTheme.borderLight, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    /// The inline coaching line under the session recap. Renders only when the
    /// log holds a growth-valence signal for this session (so it's silent before
    /// the server contract is deployed, and on sessions with no clear process
    /// signal). Deliberately quiet — coaching, not a grade.
    @ViewBuilder
    private func growthEdgeLine(for session: Session) -> some View {
        if let edge = agencyLog.latestGrowthEdge(forSession: session.id) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ReflectionTheme.mutedText)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(ReflectionTheme.brandPurple)
                        Text(uiLanguage == .vi ? "LẦN SAU THỬ" : "NEXT REP")
                            .font(ReflectionTheme.sans(10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(ReflectionTheme.brandPurple)
                    }
                    Text(edge.observation)
                        .font(ReflectionTheme.sans(13))
                        .foregroundColor(ReflectionTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ReflectionTheme.brandPurple.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(ReflectionTheme.brandPurple.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func sessionHeaderStrip(for session: Session) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ReflectionTheme.stripText)
            Text(sessionMetaLabel(for: session))
                .font(ReflectionTheme.sans(12, weight: .medium))
                .foregroundColor(ReflectionTheme.primaryText)
            // Live badge for active (non-ended) sessions
            if session.endedAt == nil && !session.turns.isEmpty {
                Text("LIVE")
                    .font(ReflectionTheme.sans(9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(ReflectionTheme.liveBadge)
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ReflectionTheme.stripBackground)
        )
    }

    @ViewBuilder
    private func turnSection(for turn: Turn, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Turn time metadata (title now lives inside the narrative bubble)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(timeDisplay(turn.startedAt))
                        .font(ReflectionTheme.sans(12))
                        .foregroundColor(ReflectionTheme.mutedText)
                    if let ended = turn.endedAt {
                        Text("·")
                            .foregroundColor(ReflectionTheme.mutedText)
                        Text("\(Int(ended.timeIntervalSince(turn.startedAt) / 60)) \(uiLanguage == .vi ? "phút" : "min")")
                            .font(ReflectionTheme.sans(12))
                            .foregroundColor(ReflectionTheme.mutedText)
                    }
                }
            }

            // Narrative chat view or loading state
            if let narrative = turn.narrative {
                NarrativeChatTurnView(narrative: narrative, showAvatar: isLast)
            } else if turn.endedAt != nil && !turn.hasWriteEvents {
                // Completed read-only turn (status checks, git log, or text-only) — show prompt quietly.
                // Only apply after the turn has ended; pending turns should show loading state
                // so they transition naturally once tool events arrive.
                Text(turn.prompt)
                    .font(ReflectionTheme.sans(13))
                    .foregroundColor(ReflectionTheme.secondaryText)
                    .italic()
                    .lineSpacing(2)
            } else {
                TurnLoadingStates(
                    state: turn.state,
                    actionCount: turn.rawEvents.count,
                    isGenerating: enricher.enrichingTurns.contains(turn.id),
                    onRetry: {
                        let persona = currentPetPersona()
                        Task { await enricher.enrich(turn: turn, petPersona: persona) }
                    }
                )
            }

            // Collapsed technical details
            if !turn.rawEvents.isEmpty {
                TechnicalDetailsView(prompt: turn.prompt, events: turn.rawEvents)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Eyebrow(text: uiLanguage == .vi
                ? "CodePet v1.0 · reflection · ghi nhận âm thầm. chỉ hiện khi bạn yêu cầu."
                : "CodePet v1.0 · reflection · captured quietly. shown on request.")
            Spacer()
        }
        .padding(.top, 12)
    }

    // MARK: - Helpers

    private func timeDisplay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func dateDisplay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMMM d"
        return f.string(from: date)
    }

}

#Preview {
    let summaryStore = SessionSummaryStore()
    let api = ReflectionAPIClient()
    let chatStore = SessionChatStore(
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-chat.json")
    )
    let chatController = SessionChatController(api: api, store: chatStore)
    return ReflectionTab()
        .environmentObject(AppState())
        .environmentObject(ReflectionEventStore())
        .environmentObject(NarrativeStore())
        .environmentObject(summaryStore)
        .environmentObject(NarrativeEnricher(
            api: api,
            store: NarrativeStore(),
            language: "vi"
        ))
        .environmentObject(SessionEndStore())
        .environmentObject(SessionSummaryEnricher(
            api: api,
            store: summaryStore,
            language: "vi"
        ))
        .environmentObject(chatStore)
        .environmentObject(chatController)
        .environmentObject(DemoScriptController())
        .environmentObject(ProjectStore())
        .environmentObject(InterviewCoordinator())
        .frame(width: 900, height: 800)
}
